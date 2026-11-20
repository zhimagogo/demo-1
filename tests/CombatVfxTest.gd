extends Node
## 攻击特效链回归（v12）：godot --headless --path . tests/CombatVfxTest.tscn
## 覆盖：主角三段连招刀光（含第 3 段重击）/ 命中点火星与冲击环（位置在目标体表而非主角脚下）/
##       四职业小兵专属特效（斧光·双匕弧·枪口闪光·施法微光）/ 投射物拖尾 /
##       预算上限与同帧节流 / 生命周期自动释放。

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var spawner := world.get_node("PawnSpawner")
	var hero := controller.hero as Hero
	_check(hero != null, "hero spawns for vfx test")
	if hero == null:
		_finish()
		return
	_check(VFXManager.MAX_ACTIVE_EFFECTS > 0, "vfx manager exposes the active budget")

	# 相机 / 主角朝向收敛到 -Z（yaw 写入后要跨帧才生效），再按 facing_dir 摆靶子，
	# 否则挥砍扇形会朝旧方向挥空（见 AGENTS.md 的第三人称时序坑）。
	tp.yaw = 0.0
	for _i in 4:
		await get_tree().physics_frame
	hero.global_position = Vector3(10.0, 0.0, -30.0)
	hero.aim_dir = Vector3(0.0, 0.0, -1.0)
	for _i in 3:
		await get_tree().physics_frame
	var fwd := hero.facing_dir()
	var victim: Raider = spawner.call("spawn_raider", hero.global_position + fwd * 1.7, GameDefs.raider_def())
	_freeze(victim)
	victim.global_position = hero.global_position + fwd * 1.7
	await get_tree().physics_frame

	# ---- 1) 主角普攻：月牙刀光出现在身前 ----
	VFXManager.reset_stats()
	hero.request_basic_attack()
	var arc := await _wait_group(&"vfx_slash", 90)
	_check(arc != null, "hero swing spawns a slash arc (group vfx_slash)")
	if arc != null:
		var flat := Vector2(arc.global_position.x - hero.global_position.x,
			arc.global_position.z - hero.global_position.z)
		var dist := flat.length()
		_check(dist > 0.5 and dist < 3.0, "slash arc sits 0.5-3m in front of hero (%.2fm)" % dist)
		var facing := Vector2(fwd.x, fwd.z).normalized()
		_check(flat.normalized().dot(facing) > 0.5, "slash arc is on the facing side of hero")
		_check(arc.name.begins_with("SlashArc"), "arc node is named SlashArc* (%s)" % arc.name)
		_check(int(VFXManager.stat_spawned_by_id.get(&"slash_arc", 0)) >= 1,
			"light slash effect id counted in stats")
	var heavy_early := get_tree().get_first_node_in_group(&"vfx_slash_heavy")
	_check(heavy_early == null, "combo step 1 is a light arc, not the heavy one")

	# ---- 2) 命中反馈：火星 + 冲击环落在命中点 ----
	var ring := await _wait_group(&"vfx_ring", 60)
	_check(ring != null, "hitting an enemy spawns an impact ring")
	if ring != null:
		var hit_point := victim.global_position + Vector3(0.0, 1.05, 0.0) \
			- fwd * 0.45
		var d_hit := ring.global_position.distance_to(hit_point)
		_check(d_hit < 1.5, "impact ring lands near the hit point (%.2fm error)" % d_hit)
		var d_hero := ring.global_position.distance_to(hero.global_position)
		_check(d_hero > 1.0, "impact ring is not at the hero's feet (%.2fm away)" % d_hero)
	_check(int(VFXManager.stat_spawned_by_id.get(&"hit_spark", 0)) >= 1, "sparks spawned on hit")

	# ---- 3) 第 3 段重击：更粗更亮的暖色刀光 ----
	await _wait_hero_state(hero, "hero_idle", 180)
	hero._start_combo(3)
	var heavy := await _wait_group(&"vfx_slash_heavy", 90)
	_check(heavy != null, "third combo step spawns a heavy slash arc")
	if heavy != null:
		_check(heavy.name.begins_with("SlashArcHeavy"), "heavy arc named SlashArcHeavy* (%s)" % heavy.name)

	# ---- 4) 四职业小兵专属特效 ----
	VFXManager.reset_stats()
	var cases := [
		[GameDefs.settler_warrior_def(), &"axe_arc"],
		[GameDefs.settler_assassin_def(), &"dagger_arc"],
		[GameDefs.settler_archer_def(), &"muzzle_flash"],
		[GameDefs.settler_mage_def(), &"cast_glow"],
	]
	var hits := 0
	var bolt_trail := false
	var bolt_seen := false
	for i in cases.size():
		var pd: PawnDef = cases[i][0]
		var expect: StringName = cases[i][1]
		var at: Vector3 = hero.global_position + Vector3(-7.0 + float(i) * 2.6, 0.0, 7.0)
		var soldier: Pawn = spawner.call("spawn_soldier", pd, at)
		_freeze(soldier)
		soldier.global_position = at
		soldier.look_at_target(Vector3(0.0, 0.0, -1.0))
		var reach: float = 1.2 if pd.attack_kind == PawnDef.AttackKind.MELEE else 3.0
		var target: Raider = spawner.call("spawn_raider", at + Vector3(0.0, 0.0, -reach), GameDefs.raider_def())
		_freeze(target)
		target.global_position = at + Vector3(0.0, 0.0, -reach)
		await get_tree().physics_frame
		soldier.attacker.try_attack(target)
		await get_tree().physics_frame
		if pd.id == &"settler_archer":
			# "projectiles" 分组里挂的是 Main.tscn 的容器节点，弹体是它的子节点
			var container := get_tree().get_first_node_in_group("projectiles")
			if container != null:
				for p in container.get_children():
					if p is Projectile and is_instance_valid(p):
						bolt_seen = true
						bolt_trail = (p as Node).get_node_or_null("ArrowTrail") != null
						print("INFO: projectile children = ", _child_names(p), " trail=", (p as Node).get("trail_effect"))
						break
		var got: bool = int(VFXManager.stat_spawned_by_id.get(expect, 0)) > 0
		_check(got, "%s attack spawns its own effect (%s)" % [pd.display_name, expect])
		if got:
			hits += 1
	_check(hits >= 3, "at least 3 of 4 classes have dedicated attack vfx (%d/4)" % hits)
	_freeze_all_raiders()
	_check(int(VFXManager.stat_spawned_by_id.get(&"hit_spark", 0)) >= 1, "melee classes spawn hit sparks")
	_check(int(VFXManager.stat_spawned_by_id.get(&"hit_ring", 0)) >= 1, "every hit spawns an impact ring")
	_check(bolt_seen, "archer shot creates a projectile")
	_check(bolt_trail, "projectile flies with a trail node attached")

	# ---- 5) 节流：同一单位 0.1s 内不重复生成同种命中特效 ----
	VFXManager.reset_stats()
	var probe: Vector3 = hero.global_position + Vector3(0.0, 1.0, 0.0)
	for _i in 5:
		VFXManager.spawn_effect(&"hit_spark", probe, 0.0,
			{"throttle_key": "throttle_probe", "throttle_time": 0.5})
	_check(int(VFXManager.stat_spawned_by_id.get(&"hit_spark", 0)) == 1,
		"throttle blocks repeated spawns inside the window")

	# ---- 6) 预算：同帧 40 次生成不报错、活动数不超上限、节点数有界（v27 预算扩到 30，加量保证溢出）----
	await _wait_vfx_drained(240)
	VFXManager.reset_stats()
	for _i in 40:
		VFXManager.spawn_effect(&"hit_burst", probe, 0.0)
	var active := VFXManager.active_effect_count()
	_check(active <= VFXManager.MAX_ACTIVE_EFFECTS,
		"active effects stay within the budget (%d/%d)" % [active, VFXManager.MAX_ACTIVE_EFFECTS])
	_check(VFXManager.get_child_count() < 44,
		"vfx node count stays bounded (%d)" % VFXManager.get_child_count())
	_check(VFXManager.stat_dropped_by_budget > 0, "overflow spawns are dropped instead of queued")

	# ---- 6b) 优先级：名额满时保「出招表现」（刀光 / 枪口闪光），丢「命中反馈」（火星 / 冲击环）----
	await _wait_vfx_drained(240)
	VFXManager.reset_stats()
	var anchor: Node = VFXManager.spawn_effect(&"slash_arc", probe, 0.0)   # priority 1
	for _i in 40:
		VFXManager.spawn_effect(&"hit_burst", probe, 0.0)                  # priority 0
	_check(VFXManager.active_effect_count() == VFXManager.MAX_ACTIVE_EFFECTS,
		"priority probe fills the budget (%d/%d)" % [VFXManager.active_effect_count(), VFXManager.MAX_ACTIVE_EFFECTS])
	var dropped_before: int = VFXManager.stat_dropped_by_budget
	_check(VFXManager.spawn_effect(&"hit_spark", probe, 0.0) == null,
		"hit-class vfx (priority 0) is dropped when the budget is full")
	_check(VFXManager.stat_dropped_by_budget > dropped_before, "dropped hit-class spawn is counted")
	var recycled: Node = VFXManager.spawn_effect(&"slash_arc_heavy", probe, 0.0)
	_check(recycled != null, "slash arc (priority 1) still spawns at the cap by recycling a hit vfx")
	_check(is_instance_valid(anchor) and anchor.is_inside_tree(),
		"an equal-priority attack vfx is never recycled for a peer")
	_check(VFXManager.active_effect_count() <= VFXManager.MAX_ACTIVE_EFFECTS,
		"recycling keeps the active count at the cap (%d)" % VFXManager.active_effect_count())

	# ---- 7) 生命周期：到期自动释放 ----
	await _wait_frames(90)
	_check(VFXManager.active_effect_count() == 0,
		"effects auto-free after their lifetime (%d left)" % VFXManager.active_effect_count())
	_check(VFXManager.get_child_count() == 0,
		"vfx node tree drains after lifetime (%d left)" % VFXManager.get_child_count())

	# ---- 8) 既有语义不变：未注册 / 空 id 仍返回 null ----
	_check(VFXManager.spawn_effect(&"no_such_effect", probe, 0.0) == null, "unknown id still returns null")
	_check(VFXManager.spawn_effect(&"", probe, 0.0) == null, "empty id still returns null")

	# ---- 贴图管线信息（Lead 的 assets/vfx/textures 落地后自动生效）----
	if DirAccess.dir_exists_absolute(VFXManager.VFX_TEX_DIR):
		print("INFO: vfx texture dir present, file textures = ", VFXManager.file_texture_count())
		for role in VFXManager.texture_sources():
			print("INFO: texture role ", role, " -> ", VFXManager.texture_sources()[role])
	else:
		print("INFO: assets/vfx/textures/ absent, procedural fallback active")

	# ---- 一次普攻生成的特效节点数（交付回报用）----
	await _wait_vfx_drained(120)
	VFXManager.reset_stats()
	hero.aim_dir = Vector3(0.0, 0.0, -1.0)
	var r2: Raider = spawner.call("spawn_raider", hero.global_position + hero.facing_dir() * 1.6, GameDefs.raider_def())
	_freeze(r2)
	r2.global_position = hero.global_position + hero.facing_dir() * 1.6
	await get_tree().physics_frame
	if hero.state_machine.current_state != null and hero.state_machine.current_state.name == "hero_idle":
		hero.request_basic_attack()
		await _wait_frames(20)
		print("INFO: one basic attack spawned ", VFXManager.stat_spawned_by_id)

	_finish()


func _finish() -> void:
	print("COMBAT VFX TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 工具 ----

## 冻结单位：Pawn 自身与状态机节点都要停（状态机是独立 Node，自己跑 _physics_process）。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)


func _freeze_all_raiders() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		_freeze(e)


func _child_names(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append((c as Node).name)
	return out


func _wait_group(group: StringName, max_frames: int) -> Node3D:
	for _i in max_frames:
		var n := get_tree().get_first_node_in_group(group)
		if n != null and is_instance_valid(n):
			return n as Node3D
		await get_tree().physics_frame
	return null


func _wait_hero_state(hero: Hero, state_name: String, max_frames: int) -> bool:
	for _i in max_frames:
		if hero.state_machine != null and hero.state_machine.current_state != null \
				and hero.state_machine.current_state.name == state_name:
			return true
		await get_tree().physics_frame
	return false


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _wait_vfx_drained(max_frames: int) -> void:
	for _i in max_frames:
		if VFXManager.get_child_count() == 0 and VFXManager.active_effect_count() == 0:
			return
		await get_tree().physics_frame
