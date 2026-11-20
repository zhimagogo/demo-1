extends Node3D
## ============================================================================
## v32 巨龙「体型翻倍 + 懒跟随 + 自主攻击」实机样张与客观量测：
##   godot --path . tools/v32_dragon_ai_shot.tscn
## 产出 artifacts/：
##   ① v32-dragon-scale.png   翻倍巨龙在主角身边（第三人称，看是否挡视线）
##   ② v32-dragon-buffer.png  缓冲半径：主角在圈内走动，龙原地不动
##   ③ v32-dragon-chase.png   出圈后追到「跟随半径」（侧翼槽位）再停
##   ④ v32-dragon-guard.png   自主守备：主角没下令，龙自己打主角身边的怪
## 控制台量测：屏幕偏心距（准星 = 屏幕中心，越大越不挡视线）、侧向/后方偏移、
## 缓冲圈内位移、出圈追赶到位距离、自主索敌半径内的接战与圈外忽略。
## ============================================================================

var _main: Node
var _world: Node3D
var _pet: DragonPet
var _hero: Hero
var _cam: ThirdPersonCamera
var _spawner: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	_world = _main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem"]:
		var node := _world.get_node_or_null(n)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	await _frames(2)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	_hero = _find_hero()
	_cam = _world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	_spawner = get_tree().get_first_node_in_group("pawn_spawner")

	# ---- 驯龙（真实链路：建龙园 → 解锁 → 自动出战）----
	ResourceManager.add(GameDefs.GOLD, 2000)
	var build := _world.get_node("BuildSystem") as BuildSystem
	var garden_def: BuildingDef
	for d in GameDefs.building_defs():
		if d.id == &"dragon_garden":
			garden_def = d
	build.enter_build_mode(garden_def)
	for cand in [Vector3(12.0, 0.0, -12.0), Vector3(14.0, 0.0, -14.0), Vector3(-12.0, 0.0, -12.0),
			Vector3(12.0, 0.0, 12.0), Vector3(-12.0, 0.0, 12.0), Vector3(0.0, 0.0, -16.0)]:
		build.try_place_at(cand)
		if not get_tree().get_nodes_in_group("dragon_garden").is_empty():
			break
	build.exit_build_mode()
	await _frames(3)
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	ds.try_unlock(&"dragon_obsidian")
	await _frames(4)
	_pet = ds.current_pet()
	if _pet == null:
		print("V32 SHOT: 布景失败（龙未出战），中止")
		get_tree().quit(1)
		return
	_pet.follow_leader = _hero
	_hero.global_position = Vector3(20.0, 0.0, -2.0)
	await _frames(6)
	_pet.global_position = _hero.global_position + Vector3(5.0, 0.0, 0.0)
	await _frames(30)
	print("SCALE: model_scale=%.2f body_scale=%.1f 胶囊r=%.2f 拾取r=%.2f 嘴高=%.2f 血条高=%.2f 脚圈=%.2f" % [
		_pet.dragon_def.model_scale, _pet.body_scale(),
		(_pet.get_node("CollisionShape3D").shape as CapsuleShape3D).radius,
		(_pet.get_node("SelectableComponent").get_child(0).shape as CylinderShape3D).radius,
		_pet.mouth_height(), _pet.dragon_def.hud_head_height, _pet.dragon_def.squad_ring_radius])

	# ---- ① 翻倍体型 + 站位（第三人称实机，看是否挡镜头）----
	await _frames(60)
	_report("① 翻倍体型站定")
	await _shot("v32-dragon-scale.png")

	# ---- ② 缓冲半径：主角在圈内挪 8m，龙必须不动 ----
	var p0 := _pet.global_position
	_hero.global_position = _hero.global_position + Vector3(0.0, 0.0, -8.0)
	await _frames(90)
	print("BUFFER: 圈内挪 8m → 龙位移 %.2f m（要求 ≈0）" % p0.distance_to(_pet.global_position))
	_report("② 缓冲圈内")
	await _shot("v32-dragon-buffer.png")

	# ---- ③ 出圈追赶：拉到 26m 外 → 追到跟随半径 ----
	var chase_from := _pet.global_position.distance_to(_hero.global_position)
	_hero.global_position = _pet.global_position + Vector3(26.0, 0.0, 0.0)
	await get_tree().physics_frame
	var arrived_at := -1.0
	for i in 600:
		await get_tree().physics_frame
		if _pet.global_position.distance_to(_hero.global_position) < 6.5 \
				and Vector2(_pet.velocity.x, _pet.velocity.z).length() < 0.25:
			arrived_at = _pet.global_position.distance_to(_hero.global_position)
			break
	print("CHASE: 出圈距离 %.1fm → 追到 %.2fm 处停住" % [chase_from, arrived_at])
	_report("③ 追到跟随半径")
	await _shot("v32-dragon-chase.png")

	# ---- ④ 自主守备：主角不下令，龙自己打圈内的怪 ----
	var mob: Pawn = _spawner.call("spawn_raider", _hero.global_position + Vector3(0.0, 0.0, -9.0),
		GameDefs.raider_def())
	mob.global_position = _hero.global_position + Vector3(0.0, 0.0, -9.0)
	_hero.note_attack_target(null)
	_hero._attack_target_left = 0.0
	var engaged := false
	for i in 180:
		await get_tree().physics_frame
		if _pet.pick_target() == mob:
			engaged = true
			break
	print("GUARD: 主角未下令 → 龙自主接战=%s state=%s" % [engaged, _pet.state_machine.current_state.name])
	await _frames(20)
	_report("④ 自主守备")
	await _shot("v32-dragon-guard.png")

	# 圈外对照：20m 外的怪不主动打
	var far_mob: Pawn = _spawner.call("spawn_raider", _hero.global_position + Vector3(20.0, 0.0, 0.0),
		GameDefs.raider_def())
	far_mob.global_position = _hero.global_position + Vector3(20.0, 0.0, 0.0)
	if is_instance_valid(mob):
		mob.health.apply_damage(99999.0)
	await _frames(90)
	print("GUARD: 圈外 20m 的怪 → pick_target=%s（要求 <null>，即不主动去打圈外的怪）" % str(_pet.pick_target()))
	print("V32 DRAGON SHOT: done")
	get_tree().quit()


func _report(tag: String) -> void:
	var off: Vector3 = _pet.global_position - _hero.global_position
	off.y = 0.0
	var f := _hero.facing_dir()
	var right := Vector3(-f.z, 0.0, f.x)
	var cam := get_viewport().get_camera_3d()
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var sp := cam.unproject_position(_pet.global_position + Vector3(0.0, _pet.mouth_height(), 0.0))
	print("[%s] 距离=%.2fm 侧向=%+.2fm 后方=%+.2fm | 龙屏幕偏心=%.0fpx（准星=屏幕中心）" % [
		tag, off.length(), off.dot(right), -off.dot(f), (sp - center).length()])


func _find_hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _shot(fname: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s" % fname)
	print("saved ", fname)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
