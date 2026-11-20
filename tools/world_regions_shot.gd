extends Node
## ============================================================================
## v40 世界扩张验收截图工具（窗口模式；无头模式只做结构自检）
## ============================================================================
## 运行：
##   bash tools/godot_locked.sh --path . tools/world_regions_shot.tscn
##   → artifacts/world40/01-frostfall.png ... 06-salthollow.png（等距相机聚焦六区域地标）
##   → artifacts/world40/07-overview.png（高空全景，等距相机拉高到 320m）
##   → artifacts/world40/08-minimap.png（小地图特写）+ 08-minimap-context.png（全屏上下文）
##
## 无头（--headless）运行时自动跳过截图，只做结构自检并 quit（可用于跑批冒烟）。
##
## 抓帧约定（高频坑合集）：同进程连续两帧可能拿到逐字节相同的旧纹理——
## 每张前先等 ≥3 个 process 帧让相机 transform / 世界渲染收敛，再
## `await RenderingServer.frame_post_draw` 后读 `get_viewport().get_texture()`。
##
## 任何路径都会 quit：另挂一个看门狗节点兜底（脚本中途报错 / 卡流程时强制退出）。
## ============================================================================

const SHOT_DIR := "res://artifacts/world40"
const SHOT_SIZE := Vector2i(1600, 1000)
const LANDMARK_DISTANCE := 30.0    # 地标特写：等距相机距离（俯角 -50°，主地标占画面约 1/5 宽）
const OVERVIEW_DISTANCE := 320.0   # 高空全景：拉高到可俯瞰整张 256m 地图
const MINIMAP_DISTANCE := 76.0     # 小地图截图机位（主城周边）
const DEFAULT_HOUR := 12.0         # 默认截图时刻（正午顶光：地标细节清楚、瀑布区不落阴影）
const MAX_FRAMES := 15000          # 看门狗：约 250s @60fps，超时强制退出
const SHOT_SCENE := "res://tools/world_regions_shot.tscn"

var _main: Node = null
var _hud: Node = null
var _iso: IsometricCamera = null
var _failures: int = 0
var _saved: Array[String] = []
var _frames: int = 0
var _hour: float = DEFAULT_HOUR


func _ready() -> void:
	_parse_args()
	call_deferred("_run")


## 可选：`godot --path . tools/world_regions_shot.tscn -- --hour=12` 指定截图时刻。
func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			_hour = clampf(float(arg.trim_prefix("--hour=")), 7.0, 17.0)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("[world40] 截图工具超时（%d 帧）强制退出" % MAX_FRAMES)
		get_tree().quit(2)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	get_window().size = SHOT_SIZE
	var headless := DisplayServer.get_name() == "headless"
	print("[world40] 窗口 %dx%d，无头模式=%s" % [SHOT_SIZE.x, SHOT_SIZE.y, str(headless)])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# ---- 实例化主场景并等世界程序化内容（散布 / 水系 / 主题地标）落定 ----
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
	# 稳定白昼 + 停刷怪：截图不展示战斗，画面干净、光照确定
	TimeManager.begin(_hour)
	TimeManager.set_speed(1.0)
	print("[world40] 截图时刻 %.1f:00（--hour= 可覆盖）" % _hour)
	var spawner := world.get_node_or_null("WildlifeSpawner")
	if spawner != null:
		(spawner as Node).set_process(false)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	_hud = _main.get_node_or_null("HUD")

	# 切到等距相机（战术俯瞰）并固定 0° 朝向；关掉边缘平移防止鼠标位置拖走焦点
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
	await get_tree().physics_frame
	await get_tree().process_frame

	_check_structure(world)

	if headless:
		print("[world40] 无头模式：跳过截图（%d 项自检，%d 失败）" % [4 + WorldRegions.count(), _failures])
		get_tree().quit(0 if _failures == 0 else 1)
		return

	# ---- 1~6：六个主题区域地标特写（HUD 隐藏，只留世界画面）----
	if _hud != null:
		_hud.hide()
	var regions := WorldRegions.all()
	for index in regions.size():
		var region := regions[index]
		var landmark: Vector2 = region["landmark"]
		var region_id := String(region["id"])
		_iso.target_distance = LANDMARK_DISTANCE
		_iso.focus_on(Vector3(landmark.x, 0.0, landmark.y))
		await _capture("%02d-%s" % [index + 1, region_id])

	# ---- 7：高空全景（隐藏 HUD，拉高俯瞰整张地图）----
	_iso.target_distance = OVERVIEW_DISTANCE
	_iso.focus_on(Vector3.ZERO)
	await _capture("07-overview")

	# ---- 8：小地图（恢复 HUD，近景主城，裁出面板区域）----
	_iso.target_distance = MINIMAP_DISTANCE
	_iso.focus_on(Vector3.ZERO)
	if _hud != null and is_instance_valid(_hud):
		_hud.show()
	await _settle(10)
	await _capture_minimap()

	print("[world40] 截图完成，共 %d 张，自检失败 %d 项" % [_saved.size(), _failures])
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
	var regions := WorldRegions.all()
	_check(WorldRegions.count() == 6, "六个主题区域数据（当前 %d）" % WorldRegions.count())
	_check(_hud != null and _hud.get("minimap") != null, "HUD 装配小地图")
	var all_in_map := true
	for region in regions:
		var landmark: Vector2 = region["landmark"]
		if absf(landmark.x) > WorldLayout.MAP_HALF or absf(landmark.y) > WorldLayout.MAP_HALF:
			all_in_map = false
	_check(all_in_map, "六区域地标全部在 256m 图内")
	# 主题区域挂载情况只做记录（脚本并行开发中，缺失不阻塞截图）
	var scenery := world.get_node_or_null("WorldScenery")
	if scenery != null:
		for node_name in ["ThemedRegions", "RegionTracker"]:
			var node := scenery.get_node_or_null(node_name)
			print("INFO: WorldScenery/%s %s" % [node_name, "已挂载" if node != null else "尚未落地"])


# ============================================================================
# 抓帧与保存
# ============================================================================

## 等渲染稳定：≥3 个 process 帧 + 一帧后绘制完成。
func _settle(frames: int) -> void:
	for _i in maxi(frames, 3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 抓取当前窗口帧（调用前应已 _settle）。
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
		print("[world40] 截图 %s（%dx%d）" % [path, image.get_width(), image.get_height()])
	else:
		_check(false, "保存截图 %s（err=%d）" % [path, err])


## 小地图特写：整帧 → 按小地图控件矩形裁剪；同时留一张全屏上下文。
func _capture_minimap() -> void:
	_iso.snap_distance()
	var full := await _grab_frame()
	var context_path := "%s/08-minimap-context.png" % SHOT_DIR
	if full.save_png(context_path) == OK:
		print("[world40] 截图 %s（%dx%d）" % [context_path, full.get_width(), full.get_height()])
	var minimap = _hud.get("minimap") if _hud != null else null
	if minimap == null:
		_check(false, "小地图节点可用（裁剪小地图特写）")
		return
	# canvas_items 拉伸：控件矩形是逻辑画布坐标，PNG 是窗口像素，需按比例换算（坑合集）
	var canvas_size := get_viewport().get_visible_rect().size
	var image_size := Vector2(full.get_width(), full.get_height())
	if canvas_size.x <= 1.0 or canvas_size.y <= 1.0:
		_check(false, "视口逻辑尺寸有效（%.0fx%.0f）" % [canvas_size.x, canvas_size.y])
		return
	var scale := image_size / canvas_size
	var rect: Rect2 = minimap.get_global_rect()
	var image_rect := Rect2i(
		Vector2i(roundi(rect.position.x * scale.x), roundi(rect.position.y * scale.y)),
		Vector2i(roundi(rect.size.x * scale.x), roundi(rect.size.y * scale.y)))
	image_rect = image_rect.grow(4).intersection(Rect2i(Vector2i.ZERO, Vector2i(full.get_width(), full.get_height())))
	if image_rect.size.x < 16 or image_rect.size.y < 16:
		_check(false, "小地图裁剪区域有效（当前 %s）" % str(image_rect))
		return
	var crop := full.get_region(image_rect)
	var path := "%s/08-minimap.png" % SHOT_DIR
	if crop.save_png(path) == OK:
		_saved.append(path)
		print("[world40] 截图 %s（%dx%d，逻辑矩形 %s）"
			% [path, crop.get_width(), crop.get_height(), str(rect)])
	else:
		_check(false, "保存小地图特写 %s" % path)
