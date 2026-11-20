extends Node
## ============================================================================
## v40.2 分时段氛围 QA 截图工具（窗口模式；无头模式只做结构自检后退出）
## ============================================================================
## 运行：
##   bash tools/godot_locked.sh --path . tools/ambience_shot.tscn
##   可选：-- --hours=12,18.5,21     指定时间段（默认 12:00 / 18:30 / 21:00）
##         -- --out-root=res://artifacts/world40c
##
## 输出（每个时段一个子目录，共 8 张 × N 时段）：
##   01-frostfall.png … 06-salthollow.png   六区域 30m 等距主图
##   07-lakeside-dock.png                   湖上码头 / 小船（找不到码头时退回湖西岸）
##   08-windmill.png                        风车近景（白天场，附 08b-windmill-later 相隔 ~2.5s，
##                                          用于证明扇叶在转）；黄昏 / 夜晚场改为 08-city.png 城市夜景
##
## 昼 / 昏 / 夜检查要点：白天粒子不过曝、码头小船清楚；黄昏暖色与粒子可见性；
## 夜间萤火 / 余烬 / 雾气 / 区域灯与湖岸灯 —— 重点看「光点悬空在建筑里」「粒子过密过亮」。
##
## 抓帧：每张前 ≥4 process 帧 + `await RenderingServer.frame_post_draw`；
## 换时段后等 ≥30 帧让 DayNightCycle / 区域粒子门控收敛。支持 --hour 式时段参数。
## 任何路径 quit：看门狗按帧数兜底。
## ============================================================================

const SHOT_SIZE := Vector2i(1600, 1000)
const DEFAULT_OUT_ROOT := "res://artifacts/world40c"
const DEFAULT_HOURS := [12.0, 18.5, 21.0]
const REGION_DISTANCE := 30.0
const DOCK_DISTANCE := 15.0
const WINDMILL_DISTANCE := 16.0
const CITY_DISTANCE := 55.0
const MAX_FRAMES := 24000           # 看门狗：约 400s @60fps

var _out_root: String = DEFAULT_OUT_ROOT
var _hours: Array = DEFAULT_HOURS.duplicate()
var _main: Node = null
var _hud: Node = null
var _iso: IsometricCamera = null
var _qa_cam: Camera3D = null
var _themed: Node3D = null
var _dock: Node3D = null
var _windmill: Node3D = null
var _failures: int = 0
var _saved: Array[String] = []
var _frames: int = 0


func _ready() -> void:
	_parse_args()
	call_deferred("_run")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("[amb] 截图工具超时（%d 帧）强制退出" % MAX_FRAMES)
		get_tree().quit(2)


## 可选参数：--hours=12,18.5,21 / --out-root=res://artifacts/world40c
func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hours="):
			var hours: Array = []
			for item in arg.trim_prefix("--hours=").split(",", false):
				hours.append(clampf(float(item), 0.0, 24.0))
			if not hours.is_empty():
				_hours = hours
		elif arg.begins_with("--out-root="):
			_out_root = arg.trim_prefix("--out-root=").trim_suffix("/")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	get_window().size = SHOT_SIZE
	var headless := DisplayServer.get_name() == "headless"
	print("[amb] 窗口 %dx%d，无头=%s，时段=%s，输出=%s"
		% [SHOT_SIZE.x, SHOT_SIZE.y, str(headless), str(_hours), _out_root])

	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	if packed == null:
		_check(false, "Main.tscn 可加载")
		get_tree().quit(1)
		return
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _i in 30:
		await get_tree().process_frame

	var world := _main.get_node_or_null("WorldRoot") as Node3D
	if world == null:
		_check(false, "WorldRoot 存在")
		get_tree().quit(1)
		return
	# 停刷怪 + 清场：分时段截图不展示战斗
	TimeManager.set_speed(1.0)
	var spawner := world.get_node_or_null("WildlifeSpawner")
	if spawner != null:
		(spawner as Node).set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	_hud = _main.get_node_or_null("HUD")
	if _hud != null:
		_hud.hide()

	var controller := world.get_node_or_null("HeroController") as HeroController
	if controller != null:
		controller.exit_hero_mode()
	_iso = world.get_node_or_null("IsometricCamera") as IsometricCamera
	if _iso == null:
		_check(false, "IsometricCamera 存在")
		get_tree().quit(1)
		return
	_iso.edge_pan = false
	_iso._yaw_step = 0
	_iso.follow_target = null
	_iso.make_current()
	# 自由机位相机（备用；本工具主要用等距相机）
	_qa_cam = Camera3D.new()
	_qa_cam.name = "AmbienceQaCamera"
	_qa_cam.fov = 60.0
	_qa_cam.far = 600.0
	add_child(_qa_cam)
	await get_tree().physics_frame
	await get_tree().process_frame

	_find_targets(world)
	_check_structure(world)
	if headless:
		print("[amb] 无头模式：跳过截图（自检失败 %d 项）" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return

	for hour in _hours:
		await _shoot_hour(float(hour))
	print("[amb] 截图完成，共 %d 张，自检失败 %d 项" % [_saved.size(), _failures])
	for path in _saved:
		print("  · %s" % path)
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================================
# 目标发现：码头 / 小船 / 风车（ThemedRegions 运行时生成，名字按关键词找）
# ============================================================================

func _find_targets(world: Node3D) -> void:
	var scenery := world.get_node_or_null("WorldScenery")
	if scenery == null:
		return
	_themed = scenery.get_node_or_null("ThemedRegions") as Node3D
	if _themed == null:
		return
	_dock = _find_child_with_keywords(_themed, ["Dock", "Pier", "港口"])
	if _dock == null:
		# 没有码头时用「非沼泽」的小船作为湖上景点
		_dock = _find_child_with_keywords(_themed, ["Boat"], ["Swamp"])
	_windmill = _find_child_with_keywords(_themed, ["Windmill"])


func _find_child_with_keywords(parent: Node3D, keywords: Array, excludes: Array = []) -> Node3D:
	for child in parent.get_children():
		if not (child is Node3D):
			continue
		var child_name := String(child.name)
		var matched := false
		for keyword in keywords:
			if child_name.contains(String(keyword)):
				matched = true
				break
		if not matched:
			continue
		for exclude in excludes:
			if child_name.contains(String(exclude)):
				matched = false
				break
		if matched:
			return child as Node3D
	return null


# ============================================================================
# 结构自检（无头模式也跑）
# ============================================================================

func _check_structure(world: Node3D) -> void:
	var grid := world.get_node_or_null("GridSystem") as GridSystem
	_check(grid != null and grid.grid_size == Vector2i(128, 128), "世界网格 128×128 格")
	_check(WorldRegions.count() == 6, "六个主题区域数据（当前 %d）" % WorldRegions.count())
	_check(_themed != null, "WorldScenery/ThemedRegions 已挂载")
	print("INFO: 码头/小船节点=%s；风车节点=%s"
		% [String(_dock.name) if _dock != null else "未找到",
			String(_windmill.name) if _windmill != null else "未找到"])

	# 区域环境粒子（RegionAmbience 由 Lead 新增；未落地时只记录，不判 FAIL）
	var scenery := world.get_node_or_null("WorldScenery")
	var ambience: Node = null
	if scenery != null:
		ambience = scenery.get_node_or_null("RegionAmbience")
	var emitter_count := 0
	var particle_budget := 0
	if ambience != null:
		var stack: Array[Node] = [ambience]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is GPUParticles3D:
				emitter_count += 1
				particle_budget += (node as GPUParticles3D).amount
			for child in node.get_children():
				stack.append(child)
		print("INFO: RegionAmbience 发射器=%d，总粒子预算=%d（目标 ≤8 / ≤1200）"
			% [emitter_count, particle_budget])
	else:
		print("INFO: RegionAmbience 尚未挂载（脚本未落地时正常，正式验收会再查）")


# ============================================================================
# 分时段拍摄
# ============================================================================

func _shoot_hour(hour: float) -> void:
	# 直接写 game_seconds 校准游戏内时刻（TimeManager.begin 只收整数小时）
	TimeManager.game_seconds = hour / 24.0 * TimeManager.seconds_per_day
	await get_tree().process_frame
	for _i in 30:
		await get_tree().process_frame
	var hour_dir := "%s/%s" % [_out_root, _hour_label(hour)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(hour_dir))
	print("[amb] ===== 时段 %.1f:00 → %s =====" % [hour, hour_dir])

	# 01~06：六区域主图（30m 等距）
	var regions := WorldRegions.all()
	for index in regions.size():
		var region := regions[index]
		var landmark: Vector2 = region["landmark"]
		_iso.make_current()
		_iso.target_distance = REGION_DISTANCE
		_iso.focus_on(Vector3(landmark.x, 0.0, landmark.y))
		await _capture(hour_dir, "%02d-%s" % [index + 1, String(region["id"])])

	# 07：湖上码头 / 小船（找不到时退回湖西岸）
	_iso.make_current()
	if _dock != null:
		var dock_pos := _dock.global_position
		_iso.target_distance = DOCK_DISTANCE
		_iso.focus_on(Vector3(dock_pos.x, 0.0, dock_pos.z))
	else:
		_iso.target_distance = 18.0
		_iso.focus_on(Vector3(21.0, 0.0, -28.0))
	await _capture(hour_dir, "07-lakeside-dock")

	# 白天场：风车近景 + 2.5s 后第二张（证明扇叶在转）；黄昏 / 夜场：城市夜景
	if hour < 17.5 and _windmill != null:
		var windmill_pos := _windmill.global_position
		_iso.make_current()
		_iso.target_distance = WINDMILL_DISTANCE
		_iso.focus_on(Vector3(windmill_pos.x, 0.0, windmill_pos.z))
		await _capture(hour_dir, "08-windmill")
		# 等 ~2.5 秒再拍第二张：扇叶角度不同即证明在转
		await _wait_seconds(2.5)
		await _capture(hour_dir, "08b-windmill-later")
	else:
		_iso.make_current()
		_iso.target_distance = CITY_DISTANCE
		_iso.focus_on(Vector3(0.0, 0.0, -6.0))
		await _capture(hour_dir, "08-city")

	# 窗口模式顺便记录实测帧率（vsync 开启时约 60）
	if DisplayServer.get_name() != "headless":
		var fps := await _measure_fps()
		print("[amb] 时段 %.1f:00 实测 FPS ≈ %.1f" % [hour, fps])


func _hour_label(hour: float) -> String:
	var whole := floori(hour)
	var minutes := roundi((hour - float(whole)) * 60.0)
	return "%02d%02d" % [whole, minutes]


func _wait_seconds(seconds: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(seconds * 1000.0):
		await get_tree().process_frame


## 实测帧率：统计约 0.7 秒内的 process 帧数。
func _measure_fps() -> float:
	var start := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - start < 700:
		await get_tree().process_frame
		frames += 1
	var elapsed := float(maxi(Time.get_ticks_msec() - start, 1)) / 1000.0
	return float(frames) / elapsed


# ============================================================================
# 抓帧
# ============================================================================

func _settle(frames: int) -> void:
	for _i in maxi(frames, 3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _grab_frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _capture(dir: String, name: String) -> void:
	# v42：推拉改阻尼平滑后，取景前把视距对齐目标值，样张不会停在过渡途中
	_iso.snap_distance()
	await _settle(4)
	var image := await _grab_frame()
	var path := "%s/%s.png" % [dir, name]
	var err := image.save_png(path)
	if err == OK:
		_saved.append(path)
		print("[amb] 截图 %s（%dx%d）" % [path, image.get_width(), image.get_height()])
	else:
		_check(false, "保存截图 %s（err=%d）" % [path, err])
