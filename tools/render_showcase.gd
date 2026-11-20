extends Node
## ============================================================================
## 渲染样张 + 帧时（v47）：固定机位 / 固定时刻的多视角对照工具。
##
##   bash tools/godot_locked.sh --path . tools/render_showcase.tscn -- --label=before
##   bash tools/godot_locked.sh --path . tools/render_showcase.tscn -- --label=after --view=city_night
##   bash tools/godot_locked.sh --path . tools/render_showcase.tscn -- --label=probe --quality=low --shots=0
##
## 产物：artifacts/render-v47/<label>/<view>.png（1600×900）
## 每次都会打印 VIEW 指标，便于前后对比帧时 / draw calls / primitives。
## 注意：必须以窗口模式运行（headless 的 Dummy 渲染器没有 GPU 数据）。
## ============================================================================

const VIEWS := [
	{"name": "city_day", "hour": 10.0, "focus": Vector3(0, 0, 6), "offset": Vector3(0, 36, 32)},
	{"name": "street_day", "hour": 12.0, "focus": Vector3(-12, 0, 12), "offset": Vector3(0, 13, 11)},
	{"name": "hero_close", "hour": 12.0, "focus": Vector3(0, 0, 8), "offset": Vector3(0, 4.6, 4.2)},
	{"name": "hero_foot", "hour": 12.0, "focus": Vector3(10, 0, 30), "offset": Vector3(0, 1.8, 2.1)},
	{"name": "gameplay_day", "hour": 12.0, "focus": Vector3(12, 0, 38), "offset": Vector3(0, 24, 20)},
	{"name": "forest_day", "hour": 12.0, "focus": Vector3(-42, 0, 32), "offset": Vector3(0, 16, 17)},
	{"name": "lake_day", "hour": 12.0, "focus": Vector3(44, 0, -36), "offset": Vector3(0, 22, 24)},
	{"name": "waterfall_day", "hour": 12.0, "focus": Vector3(54, 0, -62), "offset": Vector3(0, 14, 18)},
	{"name": "city_dusk", "hour": 18.3, "focus": Vector3(0, 0, 6), "offset": Vector3(0, 34, 30)},
	{"name": "city_night", "hour": 21.0, "focus": Vector3(0, 0, 6), "offset": Vector3(0, 30, 26)},
	{"name": "gameplay_night", "hour": 22.0, "focus": Vector3(12, 0, 38), "offset": Vector3(0, 20, 18)},
]

var label := "after"
var only_view := ""
var quality := ""
var shots := true
var samples := 60

var _main: Node
var _world: Node3D
var _camera: Camera3D
var _env: Environment


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
		if arg.begins_with("--view="):
			only_view = arg.trim_prefix("--view=")
		if arg.begins_with("--quality="):
			quality = arg.trim_prefix("--quality=")
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=") != "0"
		if arg.begins_with("--samples="):
			samples = int(arg.trim_prefix("--samples="))
	if DisplayServer.get_name() == "headless":
		print("SHOWCASE SKIP：headless 无法出图，请用窗口模式运行")
		get_tree().quit()
		return
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1600, 900)
	# 样张也用无 vsync 的真实帧时，方便与探针数据对照。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED, DisplayServer.MAIN_WINDOW_ID)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_world = _main.get_node("WorldRoot") as Node3D
	for sys_name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem", "HeroController", "WeatherSystem"]:
		var sys := _world.get_node_or_null(sys_name)
		if sys != null:
			sys.set_process(false)
			sys.set_physics_process(false)
	var hud := _main.get_node_or_null("HUD")
	if hud != null:
		hud.process_mode = Node.PROCESS_MODE_DISABLED
		hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TimeManager.clock_frozen = true
	TimeManager.set_process(false)
	_env = (_world.get_node("WorldEnvironment") as WorldEnvironment).environment
	_apply_quality()
	_stage_city()
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 350.0
	add_child(_camera)
	_camera.make_current()

	var hero := _main.get("hero") as Hero
	if hero != null:
		hero.global_position = Vector3(0, 0, 8)
		hero.velocity = Vector3.ZERO
		hero.set_physics_process(false)
		hero.state_machine.set_physics_process(false)

	for view: Dictionary in VIEWS:
		if only_view != "" and String(view["name"]) != only_view:
			continue
		await _shoot(view)
	get_tree().quit()


## 应用画质档位（v47 起存在 RenderQuality autoload；旧版本没有时忽略）。
func _apply_quality() -> void:
	var rq := get_node_or_null("/root/RenderQuality")
	if rq == null:
		return
	var idx := 2
	match quality:
		"low": idx = 0
		"medium": idx = 1
		"high": idx = 2
		"ultra": idx = 3
		"": return
	rq.call("set_preset", idx, false)


## 固定一座有生活感的城：少量房屋 / 酒馆 / 龙园 / 土路 + 四职业小兵。
## 全部走正式 BuildSystem / PawnSpawner，保证材质、光照、碰撞与游戏内一致。
func _stage_city() -> void:
	ResourceManager.add(GameDefs.GOLD, 1000)
	SelectionManager.ui_modal_count = 0
	var build := _world.get_node("BuildSystem") as BuildSystem
	var hero := _main.get("hero") as Hero
	var houses := [Vector3(-14, 0, 16), Vector3(-8, 0, 20), Vector3(10, 0, 18), Vector3(16, 0, 12)]
	for spot: Vector3 in houses:
		if hero != null:
			hero.global_position = spot + Vector3(0, 0, -2)
		for def: BuildingDef in GameDefs.building_defs():
			if def.id == &"house":
				build.enter_build_mode(def)
				build.try_place_at(spot)
	build.exit_build_mode()
	for spot: Vector3 in [Vector3(14, 0, 2), Vector3(-16, 0, 4)]:
		if hero != null:
			hero.global_position = spot + Vector3(0, 0, -2)
		for def: BuildingDef in GameDefs.building_defs():
			if def.id == &"tavern" or def.id == &"dragon_garden":
				build.enter_build_mode(def)
				build.try_place_at(spot)
	build.exit_build_mode()
	# 城内土路：从城堡向南铺一条，连接房屋。
	for def: BuildingDef in GameDefs.building_defs():
		if def.is_road:
			build.enter_build_mode(def)
			for i in 9:
				build.try_place_at(Vector3(0, 0, 8 + i * 2))
			for i in 4:
				build.try_place_at(Vector3(-2 - i * 2, 0, 16))
	build.exit_build_mode()
	if hero != null:
		hero.global_position = Vector3(0, 0, 10)
	var spawner := _world.get_node("PawnSpawner")
	var spots := [Vector3(-4, 0, 12), Vector3(4, 0, 12), Vector3(-2, 0, 20), Vector3(6, 0, 18)]
	var ids := [&"settler_warrior", &"settler_mage", &"settler_archer", &"settler_assassin"]
	for i in ids.size():
		spawner.spawn_soldier(GameDefs.settler_def(ids[i]), spots[i])


func _shoot(view: Dictionary) -> void:
	TimeManager.begin(float(view["hour"]))
	var focus: Vector3 = view["focus"]
	_camera.position = focus + (view["offset"] as Vector3)
	_camera.look_at(focus)
	_camera.make_current()
	var hero := _main.get("hero") as Hero
	if hero != null and String(view["name"]).begins_with("hero_"):
		hero.global_position = focus
	# 等 DayNightCycle（0.1s 节拍）把天色 / 火光 / 雾全部收敛。
	for i in 24:
		await get_tree().process_frame
	var times: Array[float] = []
	for i in samples:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	print("VIEW name=%s hour=%.1f median=%.2f p95=%.2f draws=%d prims=%d" % [
		String(view["name"]), float(view["hour"]), times[times.size() / 2],
		times[mini(times.size() - 1, int(times.size() * 0.95))],
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])
	if not shots:
		return
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/render-v47/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := folder + "/" + String(view["name"]) + ".png"
	get_viewport().get_texture().get_image().save_png(file)
	print("SHOWCASE shot=", file)
