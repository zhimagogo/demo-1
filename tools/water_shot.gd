extends Node
## 水系交付留档工具（v43 首版 / v45 二轮迭代）：湖泊 + 多股瀑布 + 湖心岛 + 码头的新视觉样张。
##
## 运行（窗口模式，非 headless）：
##   bash tools/godot_locked.sh --path . tools/water_shot.tscn -- --label=v45
## 输出（artifacts/）：
##   <label>-water-fall-front.png      正面：多股落水 + 分层崖壁 + 落水白沫
##   <label>-water-fall-side.png       侧面：崖壁层次 + 水雾飞溅
##   <label>-water-lake-overview.png   全景：湖泊（含小岛 / 码头 / 岸线）
##   <label>-water-lake-shallow.png    v45 近景：湖岸湿沙 / 水线 / 浅滩（新增）
##   <label>-water-plunge.png          v45 近景：落水点翻涌 / 白沫丘 / 潭面（新增）
##   <label>-water-island.png          近景：湖心小岛（岩石 / 芦苇 / 小树）
##   <label>-water-pier.png            近景：湖东岸码头 / 小船 / 湖灯
##   <label>-water-night.png           夜景：湖面 + 瀑布（不发灰）
##   <label>-water-rain.png            雨天：湖面涟漪 + 瀑布亮度
##
## 取景约定（AGENTS.md）：
##   · HUD 隐藏、HeroController 退出主控、IsometricCamera 停 _process，全部用固定机位 Camera3D；
##   · 每张图前等 ≥3 process 帧 + 两次 frame_post_draw（同进程连续抓帧可能拿到旧纹理）；
##   · 昼夜用 TimeManager.begin(hour) + DayNightCycle._process() 立即应用，再冻结 time_scale；
##   · 雨天强度直接推 WeatherSystem 的内部强度（不依赖 time_scale），并等粒子铺开。

var _main: Node
var _world: Node3D
var _cam: Camera3D
var _label := "v45"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	get_window().size = Vector2i(1600, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_world = _main.get_node("WorldRoot") as Node3D
	(_world.get_node("WildlifeSpawner") as Node).set_process(false)
	(_world.get_node("ResourceGrowthSystem") as Node).set_process(false)
	for raider in get_tree().get_nodes_in_group("enemy"):
		raider.queue_free()
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	(_world.get_node("HeroController") as HeroController).exit_hero_mode()
	var iso := _world.get_node("IsometricCamera") as IsometricCamera
	iso.set_process(false)
	iso.edge_pan = false
	var feature := _world.get_node_or_null("WorldScenery/WaterFeature") as WaterFeature
	if feature != null:
		print("water feature: blocked_cells=%d cleared_scatter=%d readback=%s"
			% [feature.blocked_cells, feature.cleared_scatter, str(feature.scatter_readback)])
	_cam = Camera3D.new()
	_cam.name = "WaterShotCamera"
	_cam.far = 400.0
	_world.add_child(_cam)
	_cam.current = true
	# WeatherSystem 会在第一次 _process 时缓存当时 current 的相机（等距相机）；换机位后要重指，
	# 否则雨丝 / 溅射会跟着旧的等距相机飞，截图里看不到雨。
	var weather := _world.get_node_or_null("WeatherSystem")
	if weather != null:
		weather.set("_camera", _cam)
	_set_time(11)
	# ---- 白天样张 ----
	await _shot(Vector3(52.5, 11.0, -48.0), Vector3(57.2, 4.2, -65.0), 58.0, "fall-front")
	await _shot(Vector3(73.0, 12.5, -50.0), Vector3(57.0, 4.0, -64.0), 54.0, "fall-side")
	await _shot(Vector3(24.0, 34.0, -20.0), Vector3(57.0, 0.0, -47.0), 62.0, "lake-overview")
	# v45 近景：湖岸湿沙 / 水线 / 浅滩过渡（水线是这轮改动最大的地方之一）
	await _shot(Vector3(29.0, 3.6, -30.6), Vector3(37.6, 0.35, -36.2), 50.0, "lake-shallow")
	await _shot(Vector3(43.0, 5.6, -26.5), Vector3(48.5, 0.8, -36.0), 55.0, "island")
	# v45 近景：落水点翻涌（白沫丘 / 水帘入水 / 潭面涟漪）
	await _shot(Vector3(58.5, 6.4, -53.6), Vector3(56.0, 1.2, -63.6), 55.0, "plunge")
	await _shot(Vector3(77.0, 5.0, -33.0), Vector3(68.0, 1.0, -41.5), 56.0, "pier")
	# ---- 夜景：同一机位看湖 + 瀑布，验证夜里水面不发灰 ----
	_set_time(22)
	await _shot(Vector3(33.0, 20.0, -22.0), Vector3(55.0, 1.0, -47.0), 60.0, "night")
	# ---- 雨天：白天强雨，验证湖面涟漪与瀑布亮度 ----
	_set_time(14)
	await _drive_rain()
	await _shot(Vector3(38.0, 12.0, -28.0), Vector3(56.0, 1.0, -47.0), 60.0, "rain")
	print("water_shot: done (label=%s)" % _label)
	get_tree().quit()


## 冻结昼夜到指定小时（TimeManager.begin 同时校准 hour 与 game_seconds，
## 只写 game_seconds 会让 DayNightCycle 按旧 hour 画天色——AGENTS.md 高频坑）。
func _set_time(hour: int) -> void:
	TimeManager.begin(hour)
	var dnc := _world.get_node_or_null("DayNightCycle")
	if dnc != null and dnc.has_method("_process"):
		dnc.call("_process", 0.2)
	TimeManager.set_speed(0.0)


## 把 WeatherSystem 推到满强度降雨（不依赖 time_scale：直接推进内部强度）。
func _drive_rain() -> void:
	var weather := _world.get_node_or_null("WeatherSystem") as WeatherSystem
	if weather == null:
		return
	weather.call("_apply_state", WeatherSystem.State.RAIN)
	weather.set("_strength_target", 1.0)
	weather.set("_strength_walk_timer", 99.0)
	weather.set("_thunder_timer", 99.0)
	for i in 14:
		weather.call("_update_strength", 0.2)
		weather.call("_tick_apply")
	# GPUParticles 的推进同样吃 Engine.time_scale：定格（speed=0）时雨丝会冻在 18~29m 高的
	# 发射盒里、根本不在画面内。因此雨天这张先恢复 1× 跑 1.5s 让雨落下，再抓帧。
	TimeManager.set_speed(1.0)
	for i in 90:
		await get_tree().process_frame
	print("rain strength: %.2f" % float(weather.call("rain_strength")))


func _shot(eye: Vector3, target: Vector3, fov: float, label: String) -> void:
	_cam.fov = fov
	_cam.global_position = eye
	_cam.look_at(target)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://artifacts/%s-water-%s.png" % [_label, label]
	img.save_png(path)
	print("saved %s" % path)
