extends Node
## 同机位草坪对照：-- --label=before/after --view=city/meadow/close/shore/night/build/reference/gameplay
var label := "after"
var view := "meadow"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--view="): view = arg.trim_prefix("--view=")
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")

func _run() -> void:
	get_window().size = Vector2i(1440, 900)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var world := main.get_node("WorldRoot")
	for sys_name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem", "HeroController"]:
		world.get_node(sys_name).set_process(false)
		world.get_node(sys_name).set_physics_process(false)
	main.get_node("HUD").hide()
	TimeManager.begin(21.0 if view == "night" else 12.0)
	TimeManager.clock_frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.far = 350.0
	add_child(camera)
	var focus := Vector3(-12, 0, 13)
	var offset := Vector3(0, 28, 24)
	match view:
		"meadow": focus = Vector3(21, 0, 42); offset = Vector3(0, 24, 20)
		"close": focus = Vector3(20, 0, 40); offset = Vector3(0, 5.2, 6.2)
		"shore": focus = Vector3(33, 0, -34); offset = Vector3(0, 26, 23)
		"night": focus = Vector3(-12, 0, 13)
		"reference": focus = Vector3(12, 0, 38); offset = Vector3(8, 15, 12)
	camera.position = focus + offset
	camera.look_at(focus)
	camera.make_current()
	if view == "reference" or view == "gameplay":
		var hero := main.get("hero") as Hero
		if hero != null:
			hero.global_position = focus
			hero.velocity = Vector3.ZERO
			hero.set_physics_process(false)
			hero.state_machine.set_physics_process(false)
	if view == "gameplay":
		var hero := main.get("hero") as Hero
		var iso := world.get_node("IsometricCamera") as IsometricCamera
		hero.global_position = Vector3(12, 0, 38)
		iso.edge_pan = false
		iso._focus = hero.global_position
		iso.follow_target = hero
		iso.snap_distance()
		iso.make_current()
	if view == "build":
		focus = Vector3(-7, 0, 10)
		camera.position = focus + Vector3(0, 13, 11)
		camera.look_at(focus)
		ResourceManager.add(GameDefs.GOLD, 1000)
		SelectionManager.ui_modal_count = 0
		var build := world.get_node("BuildSystem") as BuildSystem
		for def: BuildingDef in GameDefs.building_defs():
			if def.id == &"house":
				build.enter_build_mode(def)
				build.try_place_at(Vector3(-11, 0, 11))
		for def: BuildingDef in GameDefs.building_defs():
			if def.is_road:
				build.enter_build_mode(def)
				for i in 6: build.try_place_at(Vector3(-5, 0, 5 + i * 2))
		build.exit_build_mode()
		camera.make_current()
	for i in 90: await get_tree().process_frame
	var samples: Array[float] = []
	for i in 120:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("GRASS PERF view=%s median_ms=%.2f p95_ms=%.2f draw_calls=%d primitives=%d" % [view, samples[60], samples[114], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var folder := "res://artifacts/grass-v46/" + label
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var file := folder + "/" + view + ".png"
		get_viewport().get_texture().get_image().save_png(file)
		print("GRASS SHOT ", file)
	get_tree().quit()
