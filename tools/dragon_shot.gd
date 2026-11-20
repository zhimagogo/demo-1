extends Node3D
## ============================================================================
## v26 驯龙系统实机样张工具：
##   godot --path . tools/dragon_shot.tscn
## 产出三张样张（artifacts/）：
##   ① v26-dragon-follow.png   黑曜龙随队出征（跟随主角 + 绿色队伍标）
##   ② v26-dragon-garden.png   龙园建筑 + 准星 [E] 驯龙提示 + 龙园驯龙界面
##   ③ v26-dragon-breath.png   烈焰吐息锥形火舌 + 火球爆炸溅射
## ============================================================================

var _main: Node
var _shots: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	settlement.set_process(false)
	settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	ResourceManager.add(GameDefs.GOLD, 2000)

	# ---- 布置：空地建龙园、主角带龙出征 ----
	var build := world.get_node("BuildSystem") as BuildSystem
	var garden_def: BuildingDef
	for d in GameDefs.building_defs():
		if d.id == &"dragon_garden":
			garden_def = d
	build.enter_build_mode(garden_def)
	build.try_place_at(Vector3(12.0, 0.0, -12.0))
	build.exit_build_mode()
	await get_tree().physics_frame
	ds.try_unlock(&"dragon_obsidian")
	await get_tree().physics_frame
	var pet := ds.current_pet()
	hero.global_position = Vector3(16.0, 0.0, -4.0)
	await get_tree().physics_frame

	# ---- ① 随队出征：主角 + 龙（等龙跟上就位）----
	var cam := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	cam._distance = 6.4   # 拉远一点，把龙的体型拍全（无公开 setter，工具直写）
	await _wait_frames(210)
	await _save("v26-dragon-follow.png")

	# ---- ② 龙园 + 驯龙界面（对龙园按 E 的那张卡）----
	var hud := _main.get_node_or_null("HUD")
	hero.global_position = Vector3(12.0, 0.0, -6.4)
	await _wait_frames(50)
	var garden: Building = get_tree().get_nodes_in_group("dragon_garden")[0]
	EventBus.dragon_menu_requested.emit(garden)
	await _wait_frames(6)
	await _save("v26-dragon-garden.png")
	hud.get("dragon_menu").call("close")

	# ---- ③ 战斗：吐息锥形火舌 + 火球（朝一群野怪）----
	var d1: Pawn = spawner.call("spawn_raider", Vector3(16.0, 0.0, -14.0), GameDefs.raider_def())
	var d2: Pawn = spawner.call("spawn_raider", Vector3(18.0, 0.0, -14.0), GameDefs.raider_def())
	await get_tree().physics_frame
	hero.note_attack_target(d1)
	pet._breath_cd_left = 0.0
	await _wait_frames(40)     # 吐息中段（火舌最盛）
	print("STATE=", pet.state_machine.current_state.name,
		" cd=", pet._breath_cd_left,
		" flame_child=", pet.get_node_or_null("BreathFlame"),
		" d1_hp=", d1.health.current_hp, "/", d1.health.max_hp,
		" d2_hp=", d2.health.current_hp, "/", d2.health.max_hp,
		" pet_pos=", pet.global_position, " pet_fwd=", pet.facing_dir())
	await _save("v26-dragon-breath.png")
	# 火舌可见性差分：同帧隐藏火舌再抓一张，diff 面积即火舌的屏幕足迹
	var flame := pet.get_node_or_null("BreathFlame") as GPUParticles3D
	if flame != null:
		flame.visible = false
		await _wait_frames(2)
		await _save("v26-dragon-breath-noflame.png")

	print("DRAGON SHOT: done")
	get_tree().quit()


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _save(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s" % fname)
	print("saved ", fname)
