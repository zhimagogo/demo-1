class_name PauseMenu
extends Control
## ============================================================================
## PauseMenu —— 游戏内按 Esc 弹出的暂停菜单（HUD 顶层的模态浮层）。
## 打开 = 记住当前倍速并把 time_scale 归零（真暂停）+ 占用 ui_modal_count
## （HeroController._sync_mouse_mode 据此自动释放鼠标指针）；关闭 = 原倍速恢复。
##
## Esc 的全局优先级链（关键契约，勿破坏）：
##   1. 游戏结束（GAME_OVER）→ 不响应（结算浮层自理）；
##   2. 建造模式激活 → 放行（Esc 归 BuildSystem 退出建造）；
##   3. 新手引导进行中 → 放行（Esc 归 TutorialSystem 快捷跳过）；
##   4. 本菜单的「设置」子页开着 → 只收起子页；
##   5. 菜单已开 → 关闭并恢复；否则 → 打开并暂停。
##   注意：HUD 晚于 WorldRoot 挂树，本节点先于 BuildSystem / TutorialSystem
##   收到 _unhandled_input，因此 2/3 的「放行」必须在这里自查，不能依赖对端。
## ============================================================================

const MENU_SCENE := "res://scenes/main/MainMenu.tscn"

var is_open: bool = false

var _dim: ColorRect
var _info_label: Label
var _buttons_box: VBoxContainer
var _settings_box: VBoxContainer
var _resume_button: Button
var _settings_button: Button
var _level_map_button: Button
var _main_menu_button: Button
var _quit_button: Button
var _settings_panel: SettingsPanel
var _previous_speed: float = 1.0


func _ready() -> void:
	# HUD 在 _build_ui 里挂主题；这里只做节点登记与浮层装配
	name = "PauseMenu"
	add_to_group("pause_menu")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 关闭时不挡任何点击
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.62)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 打开时挡住对世界的误点
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(&"ornate"))
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	center.add_child(panel)

	# —— 按钮主页 ——
	_buttons_box = VBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 10)
	panel.add_child(_buttons_box)

	var title := UIStyle.section_title("暂  停", &"pause", 18)
	_buttons_box.add_child(title)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_buttons_box.add_child(_info_label)

	_resume_button = _menu_button("继 续 游 戏", &"play")
	_resume_button.pressed.connect(close)
	_buttons_box.add_child(_resume_button)

	_settings_button = _menu_button("设        置", &"help")
	_settings_button.pressed.connect(_open_settings_view)
	_buttons_box.add_child(_settings_button)

	# v38：关卡系统 —— 从对局里退回关卡选择地图（与「返回主菜单」同一套状态清理）
	_level_map_button = _menu_button("返 回 关 卡 地 图", &"map")
	# Demo 期间屏蔽选关入口，保留地图资源供后续恢复。
	_level_map_button.visible = false
	_level_map_button.pressed.connect(_return_to_level_select)
	_buttons_box.add_child(_level_map_button)

	_main_menu_button = _menu_button("返 回 主 菜 单", &"home")
	_main_menu_button.pressed.connect(_return_to_main_menu)
	_buttons_box.add_child(_main_menu_button)
	_quit_button = _menu_button("退 出 游 戏", &"close")
	_quit_button.pressed.connect(_on_quit_pressed)
	_buttons_box.add_child(_quit_button)

	var esc_hint := Label.new()
	esc_hint.text = "Esc 继续"
	esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_hint.add_theme_font_size_override("font_size", 12)
	esc_hint.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.7))
	_buttons_box.add_child(esc_hint)

	# —— 设置子页（与按钮主页同卡片内切换，菜单保持暂停态）——
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 8)
	_settings_box.visible = false
	panel.add_child(_settings_box)

	_settings_panel = SettingsPanel.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.closed.connect(_close_settings_view)
	_settings_box.add_child(_settings_panel)


func _menu_button(text: String, _icon_id: StringName) -> Button:
	# icon_id 预留给正式美术的按钮内嵌图标；当前用纯文字保持主题一致
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230.0, 38.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_entered.connect(func() -> void: AudioManager.play_sfx(&"ui_hover"))
	return button


# ============================================================================
# 开 / 关
# ============================================================================

func open() -> void:
	if is_open or GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	is_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_previous_speed = TimeManager.time_scale
	_refresh_info()
	_show_button_view()
	# 真暂停 + UI 模态计数（>0 时 HeroController 自动释放鼠标指针）
	TimeManager.set_speed(0.0)
	SelectionManager.ui_modal_count += 1
	AudioManager.play_sfx(&"ui_click")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)
	if GameManager.phase != GameManager.Phase.GAME_OVER:
		# 恢复打开前的倍速（打开时若是 P 暂停态则恢复为暂停态，行为一致）
		TimeManager.set_speed(_previous_speed if _previous_speed > 0.0 else 0.0)
	AudioManager.play_sfx(&"ui_click")


# ============================================================================
# 输入：Esc 全局优先级链（见文件头注释）
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	# 2) 建造模式：Esc 归 BuildSystem（退出建造）
	if SelectionManager.build_mode_active:
		return
	# 3) 新手引导进行中：Esc 归 TutorialSystem（快捷跳过）
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null and tutorial.state == TutorialSystem.State.RUNNING:
		return
	# 3.5) 编队界面开着：Esc 归 PartyPanel（v10；它挂在菜单之后、先收到输入，这里防御性放行）
	var party_panel := get_tree().get_first_node_in_group("party_panel")
	if party_panel != null and party_panel.has_method("is_open") and party_panel.get("is_open"):
		return
	# 3.6) v25 技能树面板 / 入住职业选择弹窗开着：同上防御性放行（它们先收到输入并自行消费）
	var tree_panel := get_tree().get_first_node_in_group("skill_tree_panel")
	if tree_panel != null and tree_panel.get("is_open"):
		return
	var settle_picker := get_tree().get_first_node_in_group("settle_class_picker")
	if settle_picker != null and settle_picker.get("is_open"):
		return
	# 3.7) v26 驯龙界面开着：同上防御性放行（它先收到输入并自行消费）
	var dragon_menu := get_tree().get_first_node_in_group("dragon_menu")
	if dragon_menu != null and dragon_menu.get("is_open"):
		return
	# 4) 设置子页开着：只收起子页
	if _settings_box.visible:
		_close_settings_view()
		get_viewport().set_input_as_handled()
		return
	# 5/6) 开关菜单
	if is_open:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


# ============================================================================
# 动作
# ============================================================================

func _open_settings_view() -> void:
	AudioManager.play_sfx(&"ui_click")
	_settings_panel.sync_from_settings()
	_show_settings_view()


func _close_settings_view() -> void:
	_show_button_view()


func _show_button_view() -> void:
	_buttons_box.visible = true
	_settings_box.visible = false


func _show_settings_view() -> void:
	_buttons_box.visible = false
	_settings_box.visible = true


func _refresh_info() -> void:
	_info_label.text = "第 %d 天 · %02d:00" % [TimeManager.day, TimeManager.hour]


func _return_to_main_menu() -> void:
	AudioManager.play_sfx(&"ui_click")
	_teardown_session()
	get_tree().change_scene_to_file(MENU_SCENE)


## v38：回到关卡选择地图（关卡地图是「一局的入口」，与返回主菜单并列的出口）。
func _return_to_level_select() -> void:
	AudioManager.play_sfx(&"ui_click")
	_teardown_session()
	get_tree().change_scene_to_file(LevelCatalog.LEVEL_SELECT_SCENE)


## 场景拆除前的全局状态清理（Autoload 不随场景重载，残留会污染下一局）。
## 返回主菜单 / 返回关卡地图 / 以后的任何退出出口都必须走这里。
func _teardown_session() -> void:
	var build := get_tree().get_first_node_in_group("build_system") as BuildSystem
	if build != null and build.is_building:
		build.exit_build_mode()
	SelectionManager.build_mode_active = false   # 防御性复位（场景拆除不留下任何残留标志）
	var hero_controller := get_tree().get_first_node_in_group("hero_controller") as HeroController
	if hero_controller != null and SelectionManager.hero_mode_active:
		hero_controller.exit_hero_mode()
	SelectionManager.clear()
	# 收起本菜单（恢复计数与倍速），再对模态计数硬归零：
	# 入驻提示等模态随场景销毁不会自行减计数
	close()
	SelectionManager.ui_modal_count = 0
	TimeManager.set_speed(1.0)   # 菜单场景的进场动画与循环按真实时间走


func _on_quit_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	get_tree().quit()
