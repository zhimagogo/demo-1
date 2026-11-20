extends Control
## ============================================================================
## MainMenu —— 开始界面（游戏入口场景，project.godot 的 main_scene）。
## 暗金主题标题页：开始游戏（→ Demo 沙盒直入）/ 测试关卡（→ 沙盒直入）/ 设置 / 退出。
## 全部 UI 在代码里构建（与 HUD 同一范式，统一走 UIStyle 主题）。
##
## 对外契约：
##   · 信号 start_requested：点击「开始游戏」时发出（供回归测试挂钩）；
##   · 常量 GAME_SCENE：沙盒对局场景路径（「测试关卡」直入用）；
##   · 常量 LEVEL_SELECT_SCENE：关卡选择地图（暂时屏蔽入口，保留资源）；
##   · 命名子节点 StartButton / TestLevelButton / SettingsButton / QuitButton / SettingsLayer。
## ============================================================================

signal start_requested

const GAME_SCENE := "res://scenes/main/Main.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/main/LevelSelect3D.tscn"
const GAME_TITLE := "王国亲征"
const GAME_SUBTITLE := "俯视角亲征 · 模拟经营 · 战斗沙盒"
const VERSION_TEXT := "v42 · Godot 4.7"

var start_button: Button
var test_level_button: Button
var settings_button: Button
var quit_button: Button
var settings_layer: Control
var settings_panel: SettingsPanel

var _dim: ColorRect


func _ready() -> void:
	# 主菜单永远是根场景：显示/音频/灵敏度设置在此全量应用一次
	GameSettings.apply_all()
	_build_ui()
	_fade_in()


func _build_ui() -> void:
	# ---- 背景：垂直暗金渐层 + 上下加深（中景透亮、四角收暗的舞台感）----
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.055, 0.042, 0.030),
		Color(0.115, 0.088, 0.060),
		Color(0.028, 0.020, 0.014)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	bg.texture = tex
	add_child(bg)

	var vignette := TextureRect.new()
	vignette.name = "Vignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	var vg := Gradient.new()
	# 径向暗角：中心透明、四角收暗（offset 0 在 fill_from=中心）
	vg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	vg.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55)])
	var vtex := GradientTexture2D.new()
	vtex.gradient = vg
	vtex.fill = GradientTexture2D.FILL_RADIAL
	vtex.fill_from = Vector2(0.5, 0.45)
	vtex.fill_to = Vector2(0.5, 0.0)
	vignette.texture = vtex
	add_child(vignette)

	# ---- 主体：单一流式布局（上弹性 spacer → 标题组 → 固定间距 → 按钮组 → 下弹性 spacer）----
	# 不用「标题固定 offset + 按钮 50% 居中」的双锚点方案：两套独立锚点在不同字体行高 /
	# 窗口纵横比下余量会被吃掉导致重叠；单一流式布局在任意画布尺寸下都不可能重合。
	var flow := VBoxContainer.new()
	flow.name = "MenuFlow"
	flow.set_anchors_preset(Control.PRESET_FULL_RECT)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_theme_constant_override("separation", 0)
	add_child(flow)

	var top_spacer := Control.new()
	top_spacer.name = "TopSpacer"
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_spacer.size_flags_stretch_ratio = 2.0   # 上下 2:3 → 内容簇整体略偏下，标题不过分贴顶
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(top_spacer)

	# ---- 标题组 ----
	var title_box := VBoxContainer.new()
	title_box.name = "TitleBox"
	title_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 10)
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(title_box)

	var title := Label.new()
	title.name = "GameTitle"
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIStyle.make_display_font())
	title.add_theme_font_size_override("font_size", 74)
	title.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = GAME_SUBTITLE
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	subtitle.add_theme_constant_override("letter_spacing", 4)
	title_box.add_child(subtitle)

	var divider_box := HBoxContainer.new()
	divider_box.alignment = BoxContainer.ALIGNMENT_CENTER
	divider_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var divider := UIStyle.ornament_divider()
	divider.custom_minimum_size = Vector2(360.0, 0.0)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	divider_box.add_child(divider)
	title_box.add_child(divider_box)

	# ---- 标题组与按钮组之间的固定间距（流式布局的重叠保险）----
	var gap := Control.new()
	gap.name = "TitleGap"
	gap.custom_minimum_size = Vector2(0.0, 36.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(gap)

	# ---- 按钮列（中央）----
	var center := VBoxContainer.new()
	center.name = "ButtonBox"
	center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 14)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(center)

	start_button = _menu_button("开 始 游 戏", Vector2(240.0, 46.0), 20)
	start_button.name = "StartButton"
	start_button.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)   # 主操作金色字
	start_button.pressed.connect(_on_start_pressed)
	center.add_child(start_button)

	# v38「测试关卡」：旧沙盒世界的直达入口（关卡选择地图里同样有它的节点，
	# 这里是给开发者/回归测试留的一键直达）。
	test_level_button = _menu_button("测 试 关 卡", Vector2(240.0, 40.0), 17)
	test_level_button.name = "TestLevelButton"
	test_level_button.pressed.connect(_on_test_level_pressed)
	center.add_child(test_level_button)

	settings_button = _menu_button("设        置", Vector2(240.0, 40.0), 17)
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_open_settings)
	center.add_child(settings_button)

	quit_button = _menu_button("退 出 游 戏", Vector2(240.0, 40.0), 17)
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(_on_quit_pressed)
	center.add_child(quit_button)

	var bottom_spacer := Control.new()
	bottom_spacer.name = "BottomSpacer"
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_spacer.size_flags_stretch_ratio = 3.0
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(bottom_spacer)

	# ---- 页脚：操作预告 + 版本 ----
	var footer := Label.new()
	footer.name = "FooterHints"
	footer.text = "白天经营城邦 · 夜晚野怪攻城 —— WASD 移动 / 鼠标瞄准 / 左键挥砍 / 1~6 直接建造"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -46.0
	footer.offset_bottom = -22.0
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	add_child(footer)

	var version := Label.new()
	version.name = "VersionLabel"
	version.text = VERSION_TEXT
	version.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	version.offset_left = -140.0
	version.offset_top = 12.0
	version.offset_right = -16.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.7))
	add_child(version)

	# ---- 设置浮层（默认隐藏）----
	settings_layer = Control.new()
	settings_layer.name = "SettingsLayer"
	settings_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.visible = false
	add_child(settings_layer)

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(_dim)

	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_layer.add_child(center_wrap)

	settings_panel = SettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.closed.connect(_close_settings)
	center_wrap.add_child(settings_panel)


func _menu_button(text: String, min_size: Vector2, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_entered.connect(func() -> void: AudioManager.play_sfx(&"ui_hover"))
	return button


func _fade_in() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_ignore_time_scale(true)   # 主菜单进场动画不受 time_scale 影响
	tween.tween_property(self, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ---- 动作 ----

func _on_start_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	start_requested.emit()
	print("[MainMenu] 开始游戏 → Demo 沙盒")
	_goto_game()


## v38：测试关卡入口 —— 直入沙盒（等价于在地图上点「测试关卡 · 沙盒战场」）。
func _on_test_level_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	print("[MainMenu] 测试关卡 → 沙盒对局")
	_goto_game()



func _goto_game() -> void:
	# 从暂停菜单「返回主菜单」再进来时，time_scale 可能残留 0 —— 进对局前统一恢复
	TimeManager.set_speed(1.0)
	# 本入口固定进沙盒关（关卡地图上的「测试关卡」同款）：显式选择，避免上一局的
	# 剧情关选择残留导致又进一次序章。
	LevelRuntime.select(LevelCatalog.SANDBOX_ID)
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	print("[MainMenu] 退出游戏")
	get_tree().quit()


func _open_settings() -> void:
	AudioManager.play_sfx(&"ui_click")
	settings_panel.sync_from_settings()
	settings_layer.visible = true


func _close_settings() -> void:
	settings_layer.visible = false


# ---- Esc：设置浮层开着 → 关闭浮层；否则无操作（开始界面没有可「取消」的东西）----
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and settings_layer.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
