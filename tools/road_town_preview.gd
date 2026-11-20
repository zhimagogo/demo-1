extends Node
## 真实主场景的道路与城内生活预览；模拟按键和鼠标拖动，并保存可复查画面。

var main: Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(20261017)
	for id in [&"build_place", &"build_error"]:
		AudioManager._streams[id] = null
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null:
		tutorial.skip()
	for name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem"]:
		world.get_node(name).set_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	TimeManager.begin(11)
	TimeManager.clock_frozen = true
	TimeManager.set_speed(1)
	ResourceManager.add(GameDefs.GOLD, 1000)
	var controller := world.get_node("HeroController") as HeroController
	var build := world.get_node("BuildSystem") as BuildSystem
	var grid := world.get_node("GridSystem") as GridSystem
	var camera := world.get_node("IsometricCamera") as IsometricCamera
	main.get_node("HUD").visible = false
	controller.hero.state_machine.set_physics_process(false)
	controller.hero.global_position = Vector3.ZERO
	var defs := GameDefs.building_defs()
	for entry in [[1, Vector3(-16, 0, -12)], [1, Vector3(10, 0, -12)], [2, Vector3(-14, 0, 12)]]:
		build.enter_build_mode(defs[entry[0]])
		build.try_place_at(entry[1])
	build.enter_build_mode(defs[4])
	controller.set_view_mode(SelectionManager.ViewMode.TOPDOWN)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.hero.release_squad()
	controller.hero.global_position = Vector3(-11, 0, 7)
	controller.hero.state_machine.set_physics_process(false)
	camera.set_process(false)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 46
	camera.global_position = Vector3(20, 36, 33)
	camera.look_at(Vector3(0, 0, 2))
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var road_key := InputEventKey.new()
	road_key.physical_keycode = KEY_5
	road_key.keycode = KEY_5
	road_key.pressed = true
	get_viewport().push_input(road_key, true)
	if build.current_def == null or build.current_def.id != &"dirt_road":
		push_error("FAIL: 数字 5 未选择土路")
	# 用真实鼠标事件验证长按 + 快速拖动，六格应连续铺出且释放后停止。
	var from := Vector3(-17, 0, 9)
	var to := Vector3(-7, 0, 9)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(from)
	get_viewport().warp_mouse(motion.position)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = motion.position
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	motion = InputEventMouseMotion.new()
	motion.position = camera.unproject_position(to)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().warp_mouse(motion.position)
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	release.pressed = false
	get_viewport().push_input(release, true)
	print("ROAD INPUT: tiles=", grid.road_cells.size(), ", released=", not build._road_painting)
	if grid.road_cells.size() < 6 or build._road_painting:
		push_error("FAIL: 真实长按铺路事件未生成连续道路")
	controller.hero.global_position = Vector3.ZERO
	# 展示十字、丁字、拐角、独立段和住宅支路。
	build.begin_road_stroke(Vector3(-7, 0, 9))
	build.paint_road_to(Vector3(17, 0, 9))
	build.end_road_stroke()
	build.begin_road_stroke(Vector3(9, 0, -17))
	build.paint_road_to(Vector3(9, 0, 17))
	build.end_road_stroke()
	build.begin_road_stroke(Vector3(-11, 0, 9))
	build.paint_road_to(Vector3(-11, 0, -5))
	build.paint_road_to(Vector3(-7, 0, -5))
	build.end_road_stroke()
	build.try_place_at(Vector3(-17, 0, 3))
	build.exit_build_mode()
	controller.hero.global_position = Vector3(0, 0, -8)
	var spawner := world.get_node("PawnSpawner")
	var a: Soldier = spawner.spawn_soldier(GameDefs.settler_warrior_def(), Vector3(-5, 0, 9))
	var b: Soldier = spawner.spawn_soldier(GameDefs.settler_mage_def(), Vector3(-3, 0, 9))
	for s in [a, b]:
		s.chat_cooldown = 999
		s.speech_bubble.debug_set_timer(999)
		s.state_machine.transition_to("wander")
		s.state_machine.set_physics_process(false)
		s.set_process(false)
	a.chat_cooldown = 0
	b.chat_cooldown = 0
	a.try_chat_with(b)
	for i in 120:
		await get_tree().physics_frame
		a.state_machine.current_state.physics_update(1.0 / 60.0)
		b.state_machine.current_state.physics_update(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/roads-town")
	get_viewport().get_texture().get_image().save_png("res://artifacts/roads-town/overview.png")
	# 第二张近景观察路面拼接与交谈；两个画面用途不同，不作像素差异比较。
	camera.size = 22
	camera.global_position = Vector3(9, 18, 25)
	camera.look_at(Vector3(0, 0, 8))
	for i in 60:
		await get_tree().physics_frame
		a.state_machine.current_state.physics_update(1.0 / 60.0)
		b.state_machine.current_state.physics_update(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/roads-town/detail.png")
	# 带完整 HUD 验证第 5 张建造卡与道路操作提示。
	main.get_node("HUD").visible = true
	camera.size = 40
	camera.global_position = Vector3(20, 36, 33)
	camera.look_at(Vector3(0, 0, 2))
	controller.hero.global_position = Vector3(0, 0, 8)
	build.enter_build_mode(defs[4])
	get_viewport().warp_mouse(camera.unproject_position(Vector3(3, 0, 15)))
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/roads-town/build-menu.png")
	get_tree().quit()
