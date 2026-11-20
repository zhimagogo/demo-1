extends Node
## ============================================================================
## v38 交付留档：3D 关卡选择地图样张 + 结构 / 逻辑自检（不参与游戏运行）。
##
## 运行（带窗口，真渲染出图）：
##   bash tools/godot_locked.sh --path . tools/level_select3d_shot.tscn
##   → artifacts/v38-level-map.png          选中序章、角色站在序章岛上
##   → artifacts/v38-level-map-locked.png   选中 ch2（暂未开放）后的置灰面板与 Toast
##
## 无头（--headless）运行时自动跳过截图，只跑结构自检与逻辑烟测。
##
## ★ 任何路径都必须 quit：脚本里另有一个挂在 tree.root 下的看门狗节点（Guard），
##   它在本工具被意外切场景 / 流程挂住时强制退出，保证跑批不被拖死。
##
## 自检项：
##   ① 回归要求的 16 个节点名齐全；
##   ② 5 座岛 + 5 面旗子生成完毕；
##   ③ flag_world_position() 对每关都落在自己那座岛的顶面内、且是可走点；
##   ④ 脚本化驱动一次移动后 player_position 确实变化；
##   ⑤ 暂未开放关（ch2/ch3）拒绝进入且不发生场景切换；
##   ⑥ 序章可选中、可进入（is_playable + 主按钮可点）；
##   ⑦ teleport_player(flag_world_position(prologue)) → 面板切到序章 + HintLabel 含「E」。
## ============================================================================

const SHOT_SCENE := "res://tools/level_select3d_shot.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/main/LevelSelect3D.tscn"
const SHOT_SIZE := Vector2i(1600, 1000)
const REQUIRED_NODES: PackedStringArray = [
	"TopBar", "TitleLabel", "TotalStarsLabel",
	"InfoPanel", "InfoChapterLabel", "InfoTitleLabel", "InfoSubtitleLabel", "InfoDescLabel",
	"ObjectivesBox", "StarHintsBox", "StarRow", "StartButton", "BackButton", "ToastLabel",
	"HintLabel",
]

var _screen: Node3D = null
var _size := SHOT_SIZE
var _headless := false
var _failures := 0
var _frames := 0


func _ready() -> void:
	_parse_args()
	_headless = DisplayServer.get_name() == "headless"
	get_window().size = _size

	var guard := Guard.new()
	guard.shot_name = SHOT_SCENE
	get_tree().root.add_child.call_deferred(guard)

	print("[shot] 窗口尺寸 %dx%d，无头模式=%s，视口=%s"
		% [_size.x, _size.y, str(_headless), str(get_viewport().get_visible_rect().size)])

	_screen = load(LEVEL_SELECT_SCENE).instantiate() as Node3D
	add_child(_screen)
	await _wait(10)

	_check_structure()
	await _check_and_shot_prologue()
	await _check_and_shot_locked()

	print("[shot] 自检失败项 = %d" % _failures)
	if _failures > 0:
		push_error("[shot] 3D 关卡地图自检失败 %d 项" % _failures)
	# 等一帧让 toast / tween 收尾，再退出
	await _wait(3)
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================================
# 工具
# ============================================================================

func _wait(frames: int) -> void:
	for _i in maxi(frames, 1):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _find(node_name: String) -> Node:
	if _screen == null:
		return null
	var direct := _screen.get_node_or_null(node_name)
	if direct != null:
		return direct
	return _screen.find_child(node_name, true, false)


func _parse_args() -> void:
	for raw in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var arg := String(raw)
		if arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				_size = Vector2i(int(parts[0]), int(parts[1]))


func _snap(shot_name: String) -> void:
	if _headless:
		print("[shot] 无头模式跳过截图：", shot_name)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("[shot] 取不到渲染结果，跳过截图：", shot_name)
		return
	var path := "res://artifacts/%s.png" % shot_name
	img.save_png(path)
	print("[shot] 已保存 ", path)


## 合成一次鼠标左键点击（画布像素 → 窗口像素：stretch=canvas_items 下事件管线按窗口坐标收件）。
func _inject_click(canvas_px: Vector2) -> void:
	var win := Vector2(get_window().size)
	var canvas := get_viewport().get_visible_rect().size
	var k := Vector2(1.0, 1.0)
	if canvas.x > 1.0 and canvas.y > 1.0:
		k = Vector2(win.x / canvas.x, win.y / canvas.y)
	var at := canvas_px * k
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	Input.parse_input_event(release)


## 合成一次 E（interact）按键：走真实事件管线（InputMap → _unhandled_input）。
func _inject_interact() -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_E
	release.keycode = KEY_E
	release.pressed = false
	Input.parse_input_event(release)


# ============================================================================
# 自检
# ============================================================================

func _check_structure() -> void:
	print("[shot] ---- 结构自检 ----")
	for node_name in REQUIRED_NODES:
		_check(_find(node_name) != null, "关卡地图构建 %s" % node_name)
	_check(_screen is Node3D, "关卡地图是 3D 场景（Node3D 根）")
	_check(not _screen.find_children("*", "Camera3D", true, false).is_empty(), "3D 地图有相机")
	_check(not _screen.find_children("*", "CanvasLayer", true, false).is_empty(),
		"3D 地图有覆盖 UI 层（CanvasLayer）")
	var light := _screen.find_children("*", "DirectionalLight3D", true, false)
	_check(not light.is_empty(), "3D 地图有方向光")
	_check(_screen.get_node_or_null("WorldEnvironment") != null, "3D 地图有 WorldEnvironment")

	var report: Dictionary = _screen.call("map_report")
	print("[shot] 地图规模：", report)
	_check(int(report.get("islands", 0)) == 5, "生成 5 座漂浮岛（实际 %d）" % int(report.get("islands", 0)))
	_check(int(report.get("flags", 0)) == 5, "生成 5 面旗子（实际 %d）" % int(report.get("flags", 0)))
	_check(int(report.get("decor", 0)) > 40 and int(report.get("decor", 0)) < 400,
		"装饰数量在对的区间（实际 %d）" % int(report.get("decor", 0)))
	_check(int(report.get("walkable_cells", 0)) > 200,
		"可行走网格非空（实际 %d 格）" % int(report.get("walkable_cells", 0)))

	# 五座岛必须被道路连成一片（站在序章岛上能走到其它任何一座岛）
	var total_cells := int(report.get("walkable_cells", 0))
	var reach := int(_screen.call("reachable_cells",
		_screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID)))
	_check(reach >= int(float(total_cells) * 0.9),
		"序章岛经道路与其它岛屿连通（可达 %d / %d 格）" % [reach, total_cells])

	# 每关的旗子落点必须在自己那座岛的顶面内，且站得住
	for level in LevelCatalog.all():
		var at: Vector3 = _screen.call("flag_world_position", level.id)
		var on_island: bool = _screen.call("island_contains", level.region, at)
		var walkable: bool = _screen.call("is_walkable_point", at)
		_check(on_island, "关卡 %s 的旗子落在 %s 岛内 %s" % [level.id, level.region, str(at)])
		_check(walkable, "关卡 %s 的旗子落点可站立" % level.id)
	_check(_screen.get_node_or_null("Player") != null, "地图上有可操控的小人（Player 节点）")


func _check_and_shot_prologue() -> void:
	print("[shot] ---- 序章：选中 + 角色站上序章岛 ----")
	var start_button := _find("StartButton") as Button
	var hint := _find("HintLabel") as Label
	var panel_title := _find("InfoTitleLabel") as Label

	_screen.call("select_level", LevelCatalog.PROLOGUE_ID)
	await _wait(2)
	var prologue := LevelCatalog.prologue()
	_check(prologue != null and prologue.is_playable(), "序章可进入（is_playable）")
	_check(start_button != null and not start_button.disabled, "选中序章 → 主按钮可点")
	_check(LevelRuntime.selected_id == LevelCatalog.PROLOGUE_ID, "选中序章写入 LevelRuntime 会话")

	# 角色瞬移到序章旗旁：面板应自动切到序章、提示条给出「按 E」
	_screen.call("teleport_player", _screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID))
	await _wait(20)
	_check(_screen.selected_id == LevelCatalog.PROLOGUE_ID, "角色走到序章旗旁 → 自动选中序章")
	_check(hint != null and hint.text.contains("E"), "旗旁提示条含「E」（实际：%s）"
		% (hint.text if hint != null else "<无>"))
	_check(panel_title != null and panel_title.text == "故土残火",
		"信息面板切到序章（实际：%s）" % (panel_title.text if panel_title != null else "<无>"))

	await _wait(30)
	await _snap("v38-level-map")

	# 脚本化驱动一次移动：player_position 必须真的变化（WASD 通路）
	var before: Vector3 = _screen.get("player_position")
	Input.action_press("move_right")
	await _wait(12)
	Input.action_release("move_right")
	await _wait(4)
	var after: Vector3 = _screen.get("player_position")
	var moved := before.distance_to(after) > 0.05
	_check(moved, "脚本化移动后 player_position 变化（%.2f → %.2f，位移 %.2f m）"
		% [before.x, after.x, before.distance_to(after)])

	# 点击走位通路：walk_to → 角色走过去（轮询到抵达为止，最多 150 帧）
	var target: Vector3 = _screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID) \
		+ Vector3(-2.0, 0.0, -1.0)
	_screen.call("walk_to", target)
	var arrived := false
	for _i in 200:
		await get_tree().process_frame
		var now: Vector3 = _screen.get("player_position")
		if now.distance_to(target) < 0.4:
			arrived = true
			break
	var reached: Vector3 = _screen.get("player_position")
	_check(arrived and reached.distance_to(target) < 0.6,
		"walk_to 走位抵达目标附近（距目标 %.2f m）" % reached.distance_to(target))

	# 真实鼠标点击通路：合成左键事件（世界点 → 画布像素 → 窗口像素 → 事件管线）
	var cam := get_viewport().get_camera_3d()
	var click_world: Vector3 = _screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID) \
		+ Vector3(2.4, 0.0, 1.2)
	var click_px := cam.unproject_position(click_world)
	_inject_click(click_px)
	var clicked_arrived := false
	for _i in 200:
		await get_tree().process_frame
		var now: Vector3 = _screen.get("player_position")
		if now.distance_to(click_world) < 0.5:
			clicked_arrived = true
			break
	var after_click: Vector3 = _screen.get("player_position")
	_check(clicked_arrived and after_click.distance_to(click_world) < 0.8,
		"鼠标左键点地面 → 角色走到落点（距落点 %.2f m）" % after_click.distance_to(click_world))
	_check(bool(_screen.call("is_walkable_point", after_click)), "走位后角色仍在可走点（未掉进虚空）")
	# 回到序章旗旁（略微错开一点站位，样张里旗子与角色互不遮挡），样张固定展示「角色站在序章岛上」
	_screen.call("teleport_player",
		_screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID) + Vector3(1.0, 0.0, 2.2))
	await _wait(10)


func _check_and_shot_locked() -> void:
	print("[shot] ---- 暂未开放：ch2 / ch3 拒绝进入 ----")
	var start_button := _find("StartButton") as Button
	var panel_title := _find("InfoTitleLabel") as Label
	var hint := _find("HintLabel") as Label
	var scene_before := get_tree().current_scene

	for id in [&"ch2", &"ch3"]:
		_screen.call("select_level", id)
		await _wait(2)
		_check(start_button != null and start_button.disabled, "选中 %s → 主按钮置灰" % id)
		var entered: bool = _screen.call("try_enter_selected")
		_check(entered == false, "%s 拒绝进入（try_enter_selected=false）" % id)
		_check(LevelRuntime.enter_level(id) == false, "LevelRuntime.enter_level(%s) 拒绝" % id)
	_check(get_tree().current_scene == scene_before, "拒绝进入后没有发生场景切换")
	_check(LevelRuntime.selected_id != &"ch2" and LevelRuntime.selected_id != &"ch3",
		"被拒绝的关卡没有写进会话选择")

	# 样张：角色站到 ch2 旗旁 + 面板置灰 + Toast 拒绝提示
	_screen.call("teleport_player", _screen.call("flag_world_position", &"ch2"))
	await _wait(20)
	_check(_screen.selected_id == &"ch2", "角色走到 ch2 旗旁 → 自动选中 ch2")
	_check(hint != null and hint.text.contains("暂未开放"), "ch2 提示条为「暂未开放 · 敬请期待」（实际：%s）"
		% (hint.text if hint != null else "<无>"))
	_check(panel_title != null and panel_title.text == "盐碱商道",
		"信息面板切到 ch2（实际：%s）" % (panel_title.text if panel_title != null else "<无>"))
	_screen.call("try_enter_selected")     # 弹 Toast
	await _wait(6)
	var toast := _find("ToastLabel") as Label
	_check(toast != null and toast.visible and toast.text.contains("暂未开放"),
		"暂未开放关弹 Toast（实际：%s）" % (toast.text if toast != null else "<无>"))
	await _snap("v38-level-map-locked")

	# 真实 E 键通路：暂未开放关只弹 Toast，绝不切场景
	if toast != null:
		toast.visible = false
	_inject_interact()
	await _wait(6)
	_check(toast != null and toast.visible and toast.text.contains("暂未开放"),
		"按 E 命中暂未开放关 → 只弹 Toast（实际：%s）" % (toast.text if toast != null else "<无>"))
	_check(get_tree().current_scene == scene_before, "按 E 之后仍然没有发生场景切换")


# ============================================================================
# 看门狗：任何路径都要退出（脚本报错 / 意外切场景都不能挂住跑批）
# ============================================================================

class Guard extends Node:
	const SHOT_SCENE_PATH := "res://tools/level_select3d_shot.tscn"
	var shot_name: String = ""
	var frames := 0

	func _process(_delta: float) -> void:
		frames += 1
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path != "" and scene.scene_file_path != SHOT_SCENE_PATH:
			push_error("[shot] 场景被意外切换到 %s，强制退出" % scene.scene_file_path)
			get_tree().quit(1)
			return
		if frames > 4000:
			push_error("[shot] 超时未完成，强制退出（可能有脚本错误中断了流程）")
			get_tree().quit(1)
