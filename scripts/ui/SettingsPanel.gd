class_name SettingsPanel
extends PanelContainer
## ============================================================================
## SettingsPanel —— 通用设置面板（主菜单与游戏内 ESC 菜单共用一份实现）。
## 覆盖三组设置：显示（窗口模式 / 垂直同步）、音频（主音量）、操控（鼠标灵敏度）。
## 所有改动即时应用并写入 user://settings.cfg（GameSettings 负责），无「保存」按钮；
## 「恢复默认」一键回缺省并刷新控件。
##
## 用法：作为子节点加入任意 CenterContainer；面板通过 closed 信号告知宿主「返回」。
## ============================================================================

signal closed

var _syncing: bool = false   # 程序化回填控件时挂起信号，避免回填触发写入循环

var quality_option: OptionButton
var window_mode_option: OptionButton
var vsync_check: CheckButton
var volume_slider: HSlider
var volume_label: Label
var sensitivity_slider: HSlider
var sensitivity_label: Label
var reset_button: Button
var back_button: Button


func _ready() -> void:
	custom_minimum_size = Vector2(430.0, 0.0)
	add_theme_stylebox_override("panel", UIStyle.panel_style(&"ornate"))
	_build_ui()
	sync_from_settings()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	box.add_child(UIStyle.section_title("设  置", &"help", 18))

	# ---- 画面（v47 渲染分级）----
	box.add_child(_group_label("画面"))
	quality_option = OptionButton.new()
	quality_option.name = "QualityOption"
	quality_option.focus_mode = Control.FOCUS_NONE
	for quality_name in GameSettings.QUALITY_NAMES:
		quality_option.add_item(quality_name)
	quality_option.item_selected.connect(func(index: int) -> void:
		if _syncing:
			return
		var rq := get_node_or_null("/root/RenderQuality")
		if rq != null:
			rq.call("set_preset", index, true)
		else:
			GameSettings.set_quality(index))
	box.add_child(_row("画质档位", quality_option))
	var quality_hint := Label.new()
	quality_hint.text = "低：省 SSAO / 后处理 / 视距；中：SSAO + 软阴影；高：加 SSIL、夜间体积雾；极致：MSAA 2× + 4 段阴影。切换即时生效。"
	quality_hint.add_theme_font_size_override("font_size", 12)
	quality_hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(quality_hint)

	# ---- 显示 ----
	box.add_child(_group_label("显示"))
	window_mode_option = OptionButton.new()
	window_mode_option.name = "WindowModeOption"
	window_mode_option.focus_mode = Control.FOCUS_NONE   # 方向键留给改选项本身
	for mode_name in GameSettings.WINDOW_MODE_NAMES:
		window_mode_option.add_item(mode_name)
	window_mode_option.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			GameSettings.set_window_mode(index))
	box.add_child(_row("窗口模式", window_mode_option))

	vsync_check = CheckButton.new()
	vsync_check.name = "VSyncCheck"
	vsync_check.focus_mode = Control.FOCUS_NONE
	vsync_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			GameSettings.set_vsync(on))
	box.add_child(_row("垂直同步", vsync_check))

	# ---- 音频 ----
	box.add_child(_group_label("音频"))
	volume_slider = HSlider.new()
	volume_slider.name = "VolumeSlider"
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.custom_minimum_size = Vector2(0.0, 24.0)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_label = Label.new()
	volume_label.name = "VolumeLabel"
	volume_label.custom_minimum_size = Vector2(48.0, 0.0)
	volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	volume_slider.value_changed.connect(func(value: float) -> void:
		if not _syncing:
			GameSettings.set_master_volume(value / 100.0)
			volume_label.text = "%d%%" % int(value))
	box.add_child(_row2("主音量", volume_slider, volume_label))

	# ---- 操控 ----
	box.add_child(_group_label("操控"))
	sensitivity_slider = HSlider.new()
	sensitivity_slider.name = "SensitivitySlider"
	sensitivity_slider.min_value = 20.0
	sensitivity_slider.max_value = 200.0
	sensitivity_slider.step = 5.0
	sensitivity_slider.custom_minimum_size = Vector2(0.0, 24.0)
	sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_slider.focus_mode = Control.FOCUS_NONE
	sensitivity_label = Label.new()
	sensitivity_label.name = "SensitivityLabel"
	sensitivity_label.custom_minimum_size = Vector2(48.0, 0.0)
	sensitivity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	sensitivity_slider.value_changed.connect(func(value: float) -> void:
		if not _syncing:
			GameSettings.set_look_sensitivity(value / 100.0)
			sensitivity_label.text = "%d%%" % int(value))
	box.add_child(_row2("鼠标灵敏度", sensitivity_slider, sensitivity_label))
	var hint := Label.new()
	hint.text = "灵敏度影响第三人称镜头转动速度（20% ~ 200%；当前版本玩家为俯视角主控，此项暂不生效）"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	# ---- 按钮 ----
	box.add_child(UIStyle.ornament_divider())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	reset_button = Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "恢复默认"
	reset_button.custom_minimum_size = Vector2(120.0, 34.0)
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(_on_reset)
	buttons.add_child(reset_button)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "返  回"
	back_button.custom_minimum_size = Vector2(120.0, 34.0)
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		closed.emit())
	buttons.add_child(back_button)
	box.add_child(buttons)


## 把 GameSettings 当前值回填到控件（打开面板 / 恢复默认后调用）。
func sync_from_settings() -> void:
	_syncing = true
	quality_option.selected = GameSettings.quality()
	window_mode_option.selected = GameSettings.window_mode()
	vsync_check.button_pressed = GameSettings.vsync_enabled()
	volume_slider.value = GameSettings.master_volume() * 100.0
	volume_label.text = "%d%%" % int(GameSettings.master_volume() * 100.0)
	sensitivity_slider.value = GameSettings.look_sensitivity() * 100.0
	sensitivity_label.text = "%d%%" % int(GameSettings.look_sensitivity() * 100.0)
	_syncing = false


func _on_reset() -> void:
	AudioManager.play_sfx(&"ui_click")
	GameSettings.reset_defaults()
	var rq := get_node_or_null("/root/RenderQuality")
	if rq != null:
		rq.call("set_preset", GameSettings.quality(), false)
	sync_from_settings()


# ---- 布局小工厂 ----

func _group_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UIStyle.make_display_font())
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	return label


func _row(text: String, control: Control) -> HBoxContainer:
	return _row2(text, control, null)


func _row2(text: String, control: Control, tail: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(92.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	if tail != null:
		tail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tail)
	return row
