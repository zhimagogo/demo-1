extends Node
## ============================================================================
## 渲染性能消融探针（v47）：同一机位 / 同一时刻下逐项关闭或替换渲染特性，
## 量化每个特性花的毫秒数。每测完一项立即回测一次基线，用相邻基线插值抵消
## 机器随时间的轻微漂移（M4 集显在连续跑批时会有 1~2ms 的温热波动）。
##
##   bash tools/godot_locked.sh --path . tools/render_probe.tscn -- --view=gameplay
##   bash tools/godot_locked.sh --path . tools/render_probe.tscn -- --view=city --samples=90
##
## 输出：
##   PROBE config=ssil_off base=11.80 median=10.42 delta=-1.38 draws=1621 prims=3029092
## 注意：必须以窗口模式运行（headless 的 Dummy 渲染器没有 GPU 数据）。
## ============================================================================

const VIEWS := {
	"gameplay": {"focus": Vector3(12, 0, 38), "offset": Vector3(0, 24, 20)},
	"city": {"focus": Vector3(-12, 0, 13), "offset": Vector3(0, 28, 24)},
	"meadow": {"focus": Vector3(21, 0, 42), "offset": Vector3(0, 24, 20)},
	"shore": {"focus": Vector3(33, 0, -34), "offset": Vector3(0, 26, 23)},
}

var view := "gameplay"
var samples := 60
var _main: Node
var _world: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D
var _grass_nodes: Array[Node] = []
var _decor_node: Node
var _postfx: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.trim_prefix("--view=")
		if arg.begins_with("--samples="):
			samples = int(arg.trim_prefix("--samples="))
	if DisplayServer.get_name() == "headless":
		print("PROBE SKIP：headless 渲染器没有 GPU 数据，请用窗口模式运行")
		get_tree().quit()
		return
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1440, 900)
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
	TimeManager.begin(12.0)
	TimeManager.clock_frozen = true
	TimeManager.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_env = (_world.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sun = _world.get_node("Sun") as DirectionalLight3D
	_decor_node = _world.get_node("Decorations/DecorationScatter") as Node
	for child in _decor_node.get_children():
		if String(child.name).begins_with("MM_grass_"):
			_grass_nodes.append(child)
	_postfx = _main.get_node_or_null("PostFx")

	var spec: Dictionary = VIEWS.get(view, VIEWS["gameplay"])
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 350.0
	add_child(_camera)
	_camera.position = (spec["focus"] as Vector3) + (spec["offset"] as Vector3)
	_camera.look_at(spec["focus"] as Vector3)
	_camera.make_current()

	var hero := _main.get("hero") as Hero
	if hero != null:
		hero.global_position = spec["focus"] as Vector3
		hero.velocity = Vector3.ZERO
		hero.set_physics_process(false)
		hero.state_machine.set_physics_process(false)

	for i in 40:
		await get_tree().process_frame
	print("PROBE stage=warm")

	var configs := _build_configs()
	var base_before := await _measure()
	var rows: Array[Dictionary] = []
	for config: Dictionary in configs:
		_apply(config)
		var m := await _measure()
		_apply({})
		var b := await _measure()
		var base: float = (float(base_before["median"]) + float(b["median"])) * 0.5
		m["base"] = base
		m["delta"] = float(m["median"]) - base
		m["name"] = config["name"]
		rows.append(m)
		print("PROBE config=%s base=%.2f median=%.2f delta=%+.2f p95=%.2f draws=%d prims=%d" % [
			config["name"], base, float(m["median"]), float(m["delta"]), float(m["p95"]), int(m["draws"]), int(m["prims"]),
		])
		base_before = b
	_apply({})
	get_tree().quit()


func _build_configs() -> Array[Dictionary]:
	return [
		{"name": "ssao_off", "ssao": false},
		{"name": "ssil_off", "ssil": false},
		{"name": "volumetric_off", "volumetric": false},
		{"name": "postfx_off", "postfx": false},
		{"name": "hard_shadow", "shadow_soft": 0, "shadow_angular": 0.0},
		{"name": "soft_low_shadow", "shadow_soft": 2, "shadow_angular": 0.55},
		{"name": "shadow_2split_96", "shadow_mode": 1, "shadow_distance": 96.0, "shadow_soft": 2, "shadow_angular": 0.55},
		{"name": "shadow_2split_72", "shadow_mode": 1, "shadow_distance": 72.0, "shadow_soft": 1, "shadow_angular": 0.45},
		{"name": "shadow_off", "shadow": false},
		{"name": "no_heightfog", "height_fog": false},
		{"name": "no_fog", "fog": false},
		{"name": "grass_off", "grass": false},
		{"name": "decor_off", "decor": false},
		{"name": "smoothed_scale_087", "scale": 0.87, "scale_mode": 1},
		{"name": "msaa_2x", "msaa": 1},
	]


func _measure() -> Dictionary:
	for i in 12:
		await get_tree().process_frame
	var times: Array[float] = []
	for i in samples:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
	times.sort()
	return {
		"median": times[times.size() / 2],
		"p95": times[mini(times.size() - 1, int(times.size() * 0.95))],
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


func _apply(config: Dictionary) -> void:
	# 回到高档基线（与 RenderQuality.PRESETS[2] 对齐），再应用单项覆盖。
	_env.ssao_enabled = true
	_env.ssil_enabled = true
	_env.glow_enabled = true
	_env.fog_enabled = true
	_env.volumetric_fog_enabled = true
	_env.fog_height_density = 0.012
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 120.0
	_sun.light_angular_distance = 0.75
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	for node in _grass_nodes:
		(node as Node3D).visible = true
	_decor_node.visible = true
	if _postfx != null:
		_postfx.visible = true
	var win := get_window()
	win.msaa_3d = Viewport.MSAA_DISABLED
	win.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	win.scaling_3d_scale = 1.0

	_env.ssao_enabled = config.get("ssao", true)
	_env.ssil_enabled = config.get("ssil", true)
	_env.glow_enabled = config.get("glow", true)
	_env.fog_enabled = config.get("fog", true)
	_env.volumetric_fog_enabled = config.get("volumetric", true)
	if not config.get("height_fog", true):
		_env.fog_height_density = 0.0
	_sun.shadow_enabled = config.get("shadow", true)
	_sun.directional_shadow_mode = config.get("shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	_sun.directional_shadow_max_distance = config.get("shadow_distance", 120.0)
	_sun.light_angular_distance = config.get("shadow_angular", 0.75)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		config.get("shadow_soft", RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM))
	if not config.get("grass", true):
		for node in _grass_nodes:
			(node as Node3D).visible = false
	if not config.get("decor", true):
		_decor_node.visible = false
	if not config.get("postfx", true) and _postfx != null:
		_postfx.visible = false
	win.msaa_3d = config.get("msaa", Viewport.MSAA_DISABLED)
	win.scaling_3d_mode = config.get("scale_mode", Viewport.SCALING_3D_MODE_BILINEAR)
	win.scaling_3d_scale = config.get("scale", 1.0)
