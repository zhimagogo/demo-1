extends Node
## v30 交付留档工具：巨龙卡通火焰样张（卡通火球飞行+爆炸 / 多层卡通火舌吐息）。
##
## 运行：
##   godot --path . tools/v30_dragon_fire_shot.tscn
## 产物：artifacts/v30-dragon-fireball.png（火球飞行+爆炸） / v30-dragon-breath.png（吐息）

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var spawner := world.get_node("PawnSpawner")
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day

	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	hero.global_position = Vector3(0.0, 0.0, -40.0)
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
	tp.pitch = -0.26
	tp.target_distance = 4.6

	# 巨龙 + 两只木桩（正前方一只吃火球 / 右侧一只吃吐息）
	var dragon: DragonPet = spawner.call("spawn_dragon", GameDefs.dragon_obsidian_def(),
		Vector3(0.0, 0.0, -40.0))
	var dummy_a: Pawn = _spawn_dummy(spawner, Vector3(-4.2, 0.0, -44.0))
	var dummy_b: Pawn = _spawn_dummy(spawner, Vector3(6.0, 0.0, -47.0))
	for _i in 8:
		await get_tree().physics_frame

	# ---- 第 1 张：火球飞行 + 命中爆炸 ----
	var dir_a: Vector3 = (dummy_a.global_position - dragon.global_position).normalized()
	dragon.rotation.y = atan2(-dir_a.x, -dir_a.z)
	dragon.spawn_fireball(dummy_a, dir_a)
	for _i in 7:
		await get_tree().physics_frame      # ~0.12s：火球飞出 1.5m，在镜头前方清晰可读
	await _shot("artifacts/v30-dragon-fireball.png")
	# 等命中爆炸（speed 13 → 剩余 ~4m ≈ 0.3s）
	for _i in 26:
		await get_tree().physics_frame
	await _shot("artifacts/v30-dragon-explosion.png")

	# ---- 第 2 张：吐息（卡通火舌锥 + 嘴部灯光）----
	var dir_b: Vector3 = (dummy_b.global_position - dragon.global_position).normalized()
	dragon.state_machine.transition_to("dragon_breath", {"target": dummy_b})
	# 等起手转身结束 + 火舌铺开（windup 0.28 + 0.6）
	await get_tree().create_timer(0.95).timeout
	await _shot("artifacts/v30-dragon-breath.png")
	print("breath firing=", world.get_node("Pawns").get_child_count() > 0)
	get_tree().quit()


func _shot(path: String) -> void:
	TimeManager.set_speed(0.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		var pause_overlay := hud.get("pause_overlay") as CanvasItem
		if pause_overlay != null:
			pause_overlay.visible = false
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://" + path)
	print("saved ", path)
	TimeManager.set_speed(1.0)


func _spawn_dummy(spawner: Node, at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 6000.0
	d.attack_damage = 0.0
	d.flee_hp_ratio = 0.0
	return spawner.call("spawn_raider", at, d)
