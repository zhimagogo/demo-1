extends Node
## v28 交付留档工具：战斗打击感样张（定向火星喷溅 / 命中白闪 / 重击落地震波 /
## 交叉双匕弧 / 斧光白热刃口同框）。
##
## 运行：
##   godot --path . tools/v28_combat_shot.tscn   # → artifacts/v28-combat-feel.png
##
## 构图要点（v27 教训）：先冻结摆位再触发；粒子不做寿命覆盖（one_shot 的 lifetime
## 同时是发射时长）；网格类特效用长寿命副本 + debug_anim_progress 定格。

const ROW_Z: float = -34.0

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	var spawner := world.get_node("PawnSpawner")
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day

	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	hero.global_position = Vector3(0.0, 0.0, -38.5)
	hero.velocity = Vector3.ZERO
	hero.release_squad()
	hero.set_party([])
	controller.enter_hero_mode()
	var hero_placeholder := hero.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if hero_placeholder != null:
		hero_placeholder.visible = false
	if hero.model_rig != null:
		hero.model_rig.visible = false
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.yaw = PI
	tp.pitch = -0.3
	tp.target_distance = 3.6

	# 三组打击位：战士重劈（定向喷溅向右）/ 刺客背刺（交叉双匕弧 + 定向喷溅）
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-4.6, 0.0, ROW_Z))
	var dummy_w: Pawn = _spawn_dummy(spawner, Vector3(-2.4, 0.0, ROW_Z + 0.4))
	var assassin: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(), Vector3(3.6, 0.0, ROW_Z))
	var dummy_a: Pawn = _spawn_dummy(spawner, Vector3(5.2, 0.0, ROW_Z - 0.2))
	for _i in 6:
		await get_tree().physics_frame
	for p: Pawn in [warrior, assassin, dummy_w, dummy_a]:
		_freeze(p)

	# ① 战士强制暴击重劈：斧光（白热刃口）+ 定向火星锥（向目标方向喷）+ 白闪 + 暴击星芒
	_face(warrior, dummy_w)
	warrior.crit_stat = 1.0
	warrior.attacker._cooldown_left = 0.0
	warrior.attacker.try_attack(dummy_w)
	warrior.play_anim(&"fight")
	# ② 刺客背刺式交叉双匕弧 + 定向喷溅（手动摆位：真背刺会瞬移，构图不可控）
	_face(assassin, dummy_a)
	VFXManager.spawn_effect(&"dagger_arc", dummy_a.global_position + Vector3(0.0, 1.0, 0.4),
		assassin.rotation.y, {"spin_scale": -1.0, "lifetime": 3.0})
	VFXManager.spawn_effect(&"dagger_arc", dummy_a.global_position + Vector3(0.0, 1.0, 0.4),
		assassin.rotation.y + 0.35, {"spin_scale": 1.0, "lifetime": 3.0})
	var stab_yaw: float = atan2(-(dummy_a.global_position.x - assassin.global_position.x),
		-(dummy_a.global_position.z - assassin.global_position.z))
	VFXManager.spawn_hit_impact(dummy_a.global_position + Vector3(0.0, 1.05, 0.0),
		Color(0.72, 1.0, 0.9), &"hit_spark", "v28_assassin", stab_yaw)

	# 网格类长寿命副本定格（暴击星芒 / 命中白闪 / 重击震波 / 命中环）
	VFXManager.spawn_effect(&"crit_burst", dummy_w.global_position + Vector3(0.0, 1.4, 0.0), 0.0,
		{"lifetime": 3.0})
	VFXManager.spawn_effect(&"impact_flash", dummy_w.global_position + Vector3(0.0, 1.0, 0.0), 0.0,
		{"lifetime": 3.0})
	VFXManager.spawn_effect(&"heavy_shock", hero.global_position + Vector3(0.0, 0.25, 0.0), 0.0,
		{"lifetime": 3.0})

	# 定格（0.17s：火星锥正好喷到一半）
	for _i in 10:
		await get_tree().physics_frame
	VFXManager.debug_anim_progress = 0.42
	for p: Pawn in [warrior, assassin]:
		if p.model_rig != null and p.model_rig.anim_player != null:
			p.model_rig.anim_player.speed_scale = 0.0
	print("crit=", int(VFXManager.stat_spawned_by_id.get(&"crit_burst", 0)) >= 1,
		" cone=", int(VFXManager.stat_spawned_by_id.get(&"hit_spark_cone", 0)) >= 1,
		" flash=", int(VFXManager.stat_spawned_by_id.get(&"impact_flash", 0)) >= 1)

	# 定格取景
	TimeManager.set_speed(0.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		var pause_overlay := hud.get("pause_overlay") as CanvasItem
		if pause_overlay != null:
			pause_overlay.visible = false
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/v28-combat-feel.png")
	print("saved artifacts/v28-combat-feel.png")
	get_tree().quit()


func _face(p: Node3D, target: Node3D) -> void:
	var dir: Vector3 = target.global_position - p.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		p.look_at_target(dir.normalized())


func _spawn_dummy(spawner: Node, at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 600.0
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	return spawner.call("spawn_raider", at, d)


## 冻结单位：本体与状态机都停（与 CombatVfxTest 同款）。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)
