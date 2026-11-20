extends Node
## ============================================================================
## v40.1 视觉 QA 截图工具（窗口模式；无头模式只做结构自检后退出）
## ============================================================================
## 运行：
##   bash tools/godot_locked.sh --path . tools/visual_qa_shot.tscn
##   可选：-- --hour=12（默认 12:00 顶光）
##
## 输出 artifacts/world40b/：
##   01-frostfall-a/b/c.png … 06-salthollow-a/b/c.png  六区域 × 三机位
##     a = 30m 等距（与旧验收图同机位，便于纵向对比）
##     b = 16m 近景（垂直于来路的侧向机位，看清道具细节；正 NE 在霜区会被瀑布崖体挡住）
##     c = 相机 y≈4m / 俯角 -12° 的低角度，站在「来路方向」20m 处正面看地标
##         （第三人称视高，最容易暴露埋地 / 悬空 / 树穿建筑 / 小径压道具）
##   07-city-signposts.png      北门路标（等距近景）
##   08-lakeside.png            湖西岸 / 码头方向低角度
##   09-waterfall-cliff.png     霜语瀑布崖体低角度
##   10-map-edge.png            地图北边缘低角度（(0,-118) 朝北看远山 / 雾毯，查裸露地面边缘）
##   11-overview-200m.png       高空全景 200m（主交付图，雾影响小、地图占满画面）
##   12-overview-320m.png       高空全景 320m（世界边界 / 远山 / 雾毯尺度示意）
##
## 抓帧约定：每张前 ≥4 个 process 帧 + `await RenderingServer.frame_post_draw`；
## 机位切换后先让相机 transform / 阴影稳定再抓帧（同进程连抓会拿到旧纹理）。
## 任何路径都会 quit：另一条看门狗按帧数强制退出。
## ============================================================================

const SHOT_DIR := "res://artifacts/world40b"
const SHOT_SIZE := Vector2i(1600, 1000)
const ISO_DISTANCE := 30.0          # a 机位：30m 等距
const NEAR_DISTANCE := 16.0         # b 机位：16m 近景
const NEAR_PITCH_DEG := 50.0        # b 机位俯角（与等距相机同俯角）
const LOW_DISTANCE := 20.0          # c 机位：沿「来路方向」离地标 20m（18~22m 区间）
const LOW_HEIGHT := 4.4             # c 机位：相机高度 y≈4m（第三人称视高）
const LOW_TARGET_HEIGHT := 0.2      # c 机位注视高度（地标地面基座）→ 俯角约 -12°
const LOW_PITCH_DEG := 12.0         # c 机位目标俯角（y≈4.4m / 20m 时约 -11.9°）
const OVERVIEW_LOW := 200.0         # 全景 200m
const OVERVIEW_HIGH := 320.0        # 全景 320m（世界边界 / 远山 / 雾毯）
const DEFAULT_HOUR := 12.0
const MAX_FRAMES := 20000           # 看门狗：约 330s @60fps

var _main: Node = null
var _hud: Node = null
var _iso: IsometricCamera = null
var _qa_cam: Camera3D = null
var _failures: int = 0
var _saved: Array[String] = []
var _frames: int = 0
var _hour: float = DEFAULT_HOUR


func _ready() -> void:
	_parse_args()
	call_deferred("_run")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("[qa] 截图工具超时（%d 帧）强制退出" % MAX_FRAMES)
		get_tree().quit(2)


## 可选：`godot --path . tools/visual_qa_shot.tscn -- --hour=12` 指定截图时刻。
func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			_hour = clampf(float(arg.trim_prefix("--hour=")), 7.0, 17.0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	get_window().size = SHOT_SIZE
	var headless := DisplayServer.get_name() == "headless"
	print("[qa] 窗口 %dx%d，无头模式=%s，截图时刻 %.1f:00"
		% [SHOT_SIZE.x, SHOT_SIZE.y, str(headless), _hour])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# ---- 实例化主场景并等程序化内容（地标 / 植被 / 水系）落定 ----
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
	# 固定光照 + 停刷怪 + 清场：截图不展示战斗，画面稳定可对比
	TimeManager.begin(_hour)
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

	# 等距相机：固定 0° 朝向、关边缘平移（防止鼠标位置把焦点拖走）
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
	# 自由机位相机（b / c / 崖体 / 湖边）：手动摆位 + look_at
	_qa_cam = Camera3D.new()
	_qa_cam.name = "QaCamera"
	_qa_cam.fov = 60.0
	_qa_cam.far = 600.0
	add_child(_qa_cam)
	await get_tree().physics_frame
	await get_tree().process_frame

	_check_structure(world)
	if headless:
		print("[qa] 无头模式：跳过截图（自检失败 %d 项）" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return

	# ---- 01~06：六区域 × 三机位 ----
	var near_horizontal := NEAR_DISTANCE * cos(deg_to_rad(NEAR_PITCH_DEG))
	var near_height := NEAR_DISTANCE * sin(deg_to_rad(NEAR_PITCH_DEG))
	var segments := WorldLayout.TRAIL_SEGMENTS
	var first_trail := maxi(0, segments.size() - WorldRegions.count())
	var regions := WorldRegions.all()
	for index in regions.size():
		var region := regions[index]
		var region_id := String(region["id"])
		var landmark: Vector2 = region["landmark"]
		var target := Vector3(landmark.x, 0.0, landmark.y)
		var prefix := "%02d-%s" % [index + 1, region_id]
		# a：30m 等距
		_iso.target_distance = ISO_DISTANCE
		_iso.focus_on(target)
		_iso.make_current()
		await _capture(prefix + "-a")
		# 来路方向（与该区域小径终点方向、ThemedRegions 石碑朝向同源；数据缺失退化 SW）
		var approach := Vector2(-1.0, 1.0).normalized()
		var trail_index := first_trail + index
		if trail_index >= 0 and trail_index < segments.size():
			var segment: Array = segments[trail_index]
			var trail_start: Vector2 = segment[0]
			var trail_end: Vector2 = segment[1]
			if trail_start.distance_squared_to(trail_end) > 0.0001:
				approach = (trail_start - trail_end).normalized()
		# b：16m 近景，取「来路左侧」——固定的正 NE 在霜区会被瀑布崖体整个挡住
		var side := Vector2(-approach.y, approach.x)
		_aim_camera(
			Vector3(landmark.x + side.x * near_horizontal, near_height,
				landmark.y + side.y * near_horizontal),
			target + Vector3(0.0, 1.0, 0.0))
		await _capture(prefix + "-b")
		# c：y≈4m / 俯角 -12° 低角度，从「来路方向」18~22m 处正面看地标
		_aim_camera(
			Vector3(landmark.x + approach.x * LOW_DISTANCE, LOW_HEIGHT,
				landmark.y + approach.y * LOW_DISTANCE),
			Vector3(landmark.x, LOW_TARGET_HEIGHT, landmark.y))
		await _capture(prefix + "-c")

	# ---- 07：北门路标（等距近景）----
	_iso.target_distance = 16.0
	_iso.focus_on(Vector3(2.414, 0.0, -21.5))
	_iso.make_current()
	await _capture("07-city-signposts")

	# ---- 08：湖西岸 / 码头方向（低角度）----
	_aim_camera(Vector3(12.0, 3.2, -20.0), Vector3(24.0, 1.0, -28.0))
	await _capture("08-lakeside")

	# ---- 09：霜语瀑布崖体（低角度，看崖体与地面衔接）----
	_aim_camera(Vector3(34.0, 4.0, -36.0), Vector3(44.5, 2.6, -50.0))
	await _capture("09-waterfall-cliff")

	# ---- 10：地图北边缘（站在 (0,-118) 附近朝北看远山 / 雾毯，检查地面边缘与虚空）----
	_aim_camera(Vector3(0.0, 5.0, -110.0), Vector3(0.0, 0.5, -145.0))
	await _capture("10-map-edge")

	# ---- 11~12：高空全景（200m = 主交付图 / 320m = 世界边界与远山）----
	for distance in [OVERVIEW_LOW, OVERVIEW_HIGH]:
		_iso.make_current()
		_iso.target_distance = distance
		_iso.focus_on(Vector3(0.0, 0.0, -6.0))
		await _capture("%02d-overview-%dm" % [11 + int((distance - OVERVIEW_LOW) / 120.0), int(distance)])

	print("[qa] 截图完成，共 %d 张，自检失败 %d 项" % [_saved.size(), _failures])
	for path in _saved:
		print("  · %s" % path)
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================================
# 结构自检（无头模式也会跑）
# ============================================================================

func _check_structure(world: Node3D) -> void:
	var grid := world.get_node_or_null("GridSystem") as GridSystem
	_check(grid != null and grid.grid_size == Vector2i(128, 128)
			and is_equal_approx(grid.half_x(), WorldLayout.MAP_HALF),
		"世界网格 128×128 格 @2m（half=%.0fm）" % (grid.half_x() if grid != null else -1.0))
	_check(WorldRegions.count() == 6, "六个主题区域数据（当前 %d）" % WorldRegions.count())
	_check(_hud != null and _hud.get("minimap") != null, "HUD 装配小地图")
	var scenery := world.get_node_or_null("WorldScenery")
	var themed: Node3D = null
	if scenery != null:
		themed = scenery.get_node_or_null("ThemedRegions") as Node3D
	_check(themed != null, "WorldScenery/ThemedRegions 已挂载")
	if themed != null:
		print("INFO: ThemedRegions 直接子节点 %d 个" % themed.get_child_count())
	for region in WorldRegions.all():
		var landmark: Vector2 = region["landmark"]
		_check(absf(landmark.x) <= WorldLayout.MAP_HALF and absf(landmark.y) <= WorldLayout.MAP_HALF,
			"%s 地标在图内（%.0f, %.0f）" % [String(region["id"]), landmark.x, landmark.y])


# ============================================================================
# 相机与抓帧
# ============================================================================

## 自由机位：摆到 eye 并看向 target（下一帧渲染生效）。
func _aim_camera(eye: Vector3, target: Vector3) -> void:
	_qa_cam.global_position = eye
	_qa_cam.look_at(target, Vector3.UP)
	_qa_cam.make_current()


func _settle(frames: int) -> void:
	for _i in maxi(frames, 3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _grab_frame() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _capture(name: String) -> void:
	# v42：推拉改阻尼平滑后，取景前把视距对齐目标值
	_iso.snap_distance()
	await _settle(4)
	var image := await _grab_frame()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	var err := image.save_png(path)
	if err == OK:
		_saved.append(path)
		print("[qa] 截图 %s（%dx%d）" % [path, image.get_width(), image.get_height()])
	else:
		_check(false, "保存截图 %s（err=%d）" % [path, err])
