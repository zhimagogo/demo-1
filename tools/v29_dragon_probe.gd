extends Node3D
## ============================================================================
## v29 龙系统诊断探针（只读测量 + 固定机位样张，不改任何游戏逻辑）：
##   godot --path . tools/v29_dragon_probe.tscn
## 产出（artifacts/）：
##   v29-dragon-side.png / -front.png / -top.png   固定机位全身（朝向 / 体型 / 绿标）
##   v29-dragon-markoff.png                        同机位关掉队伍绿标（对照）
##   v29-dragon-walk.png                           移动中（朝向 vs 速度方向）
##   v29-dragon-fireball.png / -breath.png         火球 / 吐息实拍
## 控制台打印客观量测：骨骼头/尾世界坐标 vs facing_dir 点积、可见 AABB、队伍环、动画解析。
## ============================================================================

var _main: Node
var _world: Node3D
var _pet: DragonPet
var _hero: Hero
var _cam: Camera3D
var _dummy: Node3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	_world = _main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem"]:
		var node := _world.get_node_or_null(n)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	await _frames(2)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	var hud := _main.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	_hero = _find_hero()
	# 主角挪远并冻结：本探针只测龙，不测主角
	_hero.set_physics_process(false)
	_hero.global_position = Vector3(70.0, 0.0, 70.0)

	# 相机：独立固定机位（不跟随主角）
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.current = true

	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	_pet = spawner.call("spawn_dragon", GameDefs.dragon_obsidian_def(), Vector3(18.0, 0.0, -12.0))
	await _frames(4)
	_pet.follow_leader = null          # 无 leader → 跟随态原地站定，方便固定机位
	await _frames(10)
	_report("静态站定")

	# ---- ① 四机位全身 ----
	await _shot_from(Vector3(10.0, 3.2, 0.0), "v29-dragon-side.png")
	await _shot_from(Vector3(0.0, 3.2, -10.0), "v29-dragon-front.png")
	await _shot_from(Vector3(0.01, 15.0, 0.01), "v29-dragon-top.png")
	_pet.set_squad_mark(false)
	await _frames(3)
	await _shot_from(Vector3(10.0, 3.2, 0.0), "v29-dragon-markoff.png", false)
	_pet.set_squad_mark(true)
	await _frames(3)

	# ---- ② 移动朝向：给一个 12m 外的假 leader，龙走过去 ----
	_dummy = Node3D.new()
	add_child(_dummy)
	_dummy.global_position = _pet.global_position + Vector3(12.0, 0.0, 0.0)
	_hero.global_position = _dummy.global_position
	_pet.follow_leader = _hero
	var samples: Array = []
	for i in 90:
		await get_tree().physics_frame
		if i % 10 == 0:
			var v := Vector2(_pet.velocity.x, _pet.velocity.z)
			var f := Vector2(_pet.facing_dir().x, _pet.facing_dir().z)
			var dot := f.normalized().dot(v.normalized()) if v.length() > 0.3 else 0.0
			samples.append("t=%d v=%.2f facing·vel=%.3f pos=%s" % [i, v.length(), dot, str(_pet.global_position.round())])
		if i == 20:
			await _shot_from(Vector3(10.0, 3.2, 0.0), "v29-dragon-walk.png", false)
	for s in samples:
		print("WALK ", s)
	# 站定 2s 漂移量（贴身跟随是否「搓地」）
	await _frames(60)
	var p0 := _pet.global_position
	await _frames(120)
	print("SETTLE drift_2s=%.3f  pos=%s" % [p0.distance_to(_pet.global_position), str(_pet.global_position.round())])
	_pet.follow_leader = null
	await _frames(5)

	# ---- ③ 战斗：火球 / 吐息 ----
	var spawner2 := get_tree().get_first_node_in_group("pawn_spawner")
	var raider: Pawn = spawner2.call("spawn_raider", _pet.global_position + Vector3(0.0, 0.0, -8.0), GameDefs.raider_def())
	await _frames(2)
	_hero.global_position = _pet.global_position + Vector3(0.0, 0.0, 6.0)
	_pet.follow_leader = _hero
	_hero.note_attack_target(raider)
	# 等火球出膛（打印过程，抓飞行中段）
	var shot_done := false
	for i in 200:
		await get_tree().physics_frame
		var projs := get_tree().get_nodes_in_group("projectiles")
		if i % 6 == 0:
			print("FIGHT t=%d state=%s vel=%.2f facing=%s proj=%d pet=%s tgt=%s" % [
				i, _pet.state_machine.current_state.name, _pet.velocity.length(),
				str(_pet.facing_dir().round()), projs.size(),
				str(_pet.global_position.round()), str(raider.global_position.round())])
		if not shot_done and projs.size() > 0:
			shot_done = true
			await _shot_from(Vector3(9.0, 2.2, 1.0), "v29-dragon-fireball.png", true, Vector3(0.0, 1.2, -3.0))
		if i > 60 and _pet.state_machine.current_state.name == "dragon_breath":
			break
	# 强制吐息再来一次，抓喷火中段
	_pet._breath_cd_left = 0.0
	await _frames(6)
	print("BREATH state=", _pet.state_machine.current_state.name)
	await _frames(30)
	for c in _pet.get_children():
		if c is GPUParticles3D:
			print("  LAYER ", c.name, " emitting=", (c as GPUParticles3D).emitting,
				" amount=", (c as GPUParticles3D).amount,
				" global_pos=", str((c as GPUParticles3D).global_position.round()))
	await _shot_from(Vector3(9.0, 2.2, 1.0), "v29-dragon-breath.png", true, Vector3(0.0, 1.2, -3.0))
	var flame := _pet.get_node_or_null("BreathFlame") as GPUParticles3D
	if flame != null:
		flame.visible = false
		await _frames(2)
		await _shot_from(Vector3(9.0, 2.2, 1.0), "v29-dragon-breath-noflame.png", true, Vector3(0.0, 1.2, -3.0))

	print("V29 DRAGON PROBE: done")
	get_tree().quit()


# ---- 诊断打印 ----

func _report(tag: String) -> void:
	print("==== %s ====" % tag)
	print("pet_pos=%s rot_y=%.1f° facing=%s" % [
		str(_pet.global_position.round()), rad_to_deg(_pet.rotation.y), str(_pet.facing_dir().round())])
	var rig := _pet.get_node_or_null("ModelRig") as Node3D
	if rig == null:
		print("!! ModelRig 缺失")
		return
	print("rig scale=%s rot_y=%.1f° children=%d" % [str(rig.scale), rad_to_deg(rig.rotation.y), rig.get_child_count()])
	# 可见 AABB（世界坐标）
	var aabb := _world_aabb(rig)
	print("visual AABB pos=%s size=%s  (顶端 y=%.2f)" % [
		str(aabb.position.round()), str(aabb.size.round()), aabb.position.y + aabb.size.y])
	# 骨骼：头/尾相对位置 vs facing_dir（朝向的客观判据）
	var skel := _find_skeleton(rig)
	if skel != null:
		var bone_names: Array = []
		for i in skel.get_bone_count():
			bone_names.append(String(skel.get_bone_name(i)))
		print("bones(%d)=%s" % [skel.get_bone_count(), str(bone_names)])
		var fwd := _pet.facing_dir()
		for want in ["Head", "Head_Tip", "Head.Tip", "Neck", "Tail", "Tail_Tip", "Tail.Tip"]:
			var idx := skel.find_bone(want)
			if idx < 0:
				continue
			var wp: Vector3 = skel.global_transform * skel.get_bone_global_pose(idx).origin
			var rel := wp - _pet.global_position
			var flat := Vector2(rel.x, rel.z)
			var dot := flat.normalized().dot(Vector2(fwd.x, fwd.z)) if flat.length() > 0.05 else 0.0
			print("  bone %-9s world=(%.2f, %.2f, %.2f)  flat_len=%.2f  dot(facing)=%+.3f" % [
				want, wp.x, wp.y, wp.z, flat.length(), dot])
	# 动画
	print("anim resolved: idle=%s move=%s run=%s fight=%s" % [
		rig.resolved_anim(&"idle"), rig.resolved_anim(&"move"),
		rig.resolved_anim(&"run"), rig.resolved_anim(&"fight")])
	# 队伍标
	print("squad_ring=%s outline_meshes=%d" % [
		str(_pet.get_node_or_null("SquadRing") != null),
		(rig.get("_outline_meshes") as Array).size() if rig.get("_outline_meshes") != null else -1])


func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).visible and not String(n.name).begins_with("Outline"):
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var a: AABB = mi.global_transform * mi.get_aabb()
				if first:
					out = a
					first = false
				else:
					out = out.merge(a)
		if n is Sprite3D or n is Label3D or n is GPUParticles3D:
			continue
		for c in n.get_children():
			stack.append(c)
	return out


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


# ---- 工具 ----

func _find_hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _shot_from(offset: Vector3, fname: String, refocus: bool = true,
		look_offset: Vector3 = Vector3(0.0, 1.5, 0.0)) -> void:
	if refocus:
		_cam.global_position = _pet.global_position + offset
		_cam.look_at(_pet.global_position + look_offset, Vector3.UP)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s" % fname)
	print("saved ", fname)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
