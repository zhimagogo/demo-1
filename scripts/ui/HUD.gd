extends CanvasLayer
## HUD 根（v3 重制）：统一主题 + 全部面板装配。
## 顶栏 / 任务卡 / 头目横幅 / 选中信息 / 小地图 / 建造菜单 / 主角面板 /
## 消息日志 / 漂浮伤害数字 / 暂停与结算遮罩 / 入驻提示 / 调试覆盖层。
## v21：招募菜单（RecruitMenu）随兵营一并移除——小兵统一由流民定居觉醒。
## v25：市民管理（CitizenPanel，按 V 或右上按钮打开，含编队 / 转职 / 技能树入口）、
## 流民入住职业选择弹窗（SettleClassPicker）、技能树面板（SkillTreePanel）。

var top_bar: TopBar
var hero_panel: HeroPanel
var build_menu: BuildMenu
var event_log: EventLog
var selection_panel: SelectionInfoPanel
var quest_panel: QuestPanel
var boss_banner: BossBanner
var minimap: Minimap
var floating_labels: FloatingLabels
var crosshair: Crosshair
var party_panel: CitizenPanel          # 市民管理（节点名 / 分组沿用 party_panel，兼容取用）
var settle_picker: SettleClassPicker   # 流民入住职业选择弹窗
var skill_tree_panel: SkillTreePanel   # 技能树面板（叠在市民管理之上）
var dragon_menu: DragonMenu            # v26 驯龙界面（对龙园按 E 打开：解锁巨龙 / 出战召回）
var citizen_button: Button             # 右上「市民管理」独立入口按钮
var pause_overlay: ColorRect
var pause_label: Label
var gameover_overlay: ColorRect
var gameover_label: Label
var settlement_notice: ColorRect
var settlement_notice_label: Label
var _notice_previous_speed: float = 1.0
var tutorial_overlay: TutorialOverlay
var pause_menu: PauseMenu
var _debug_label: Label
var _debug_visible: bool = false
var _gameover_icon: IconBadge
var _gameover_sub: Label
var _gameover_btn: Button
var defense_button: Button            # v31 夜间守城准备：恢复时间、迎战夜潮
var defense_hint: Label               # 准备期状态行（残敌数 / 城防就绪）
var _night_prep_active: bool = false

# ---- v40 区域发现横幅（顶部居中、头目横幅下方；事件来自 RegionTracker，不轮询位置）----
const REGION_BANNER_TOP := 132.0       # 顶栏 10~54、头目横幅 56~124，横幅从 132 开始
const REGION_BANNER_HALF_W := 240.0    # 居中 480 宽：左缘 336 > 任务卡右缘 320，不压任务卡
const REGION_BANNER_H := 96.0
const REGION_FADE_IN := 0.25           # 淡入
const REGION_HOLD := 4.5               # 停留
const REGION_FADE_OUT := 0.6           # 淡出
const REGION_EXIT_FADE := 0.25         # 离开区域：立即开始淡出（比自然淡出更快）

var region_banner: PanelContainer      # 区域横幅根（测试可 get_node("RegionBanner") 取）
var _region_kicker: Label              # 「✦ 新区域」小字（仅首次发现显示）
var _region_name: Label                # 区域名（大字，用区域 accent 着色）
var _region_subtitle: Label            # 一句话副标题
var _region_accent_bar: ColorRect      # 左侧竖线（区域 accent）
var _region_panel_style: StyleBoxFlat # 面板底（描边随区域 accent 变）
var _region_tween: Tween
var _region_shown_id: StringName = &"" # 当前横幅显示的区域 id（重复进入只刷新倒计时）


func _ready() -> void:
	layer = 10
	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.build_theme()
	add_child(root)

	# 全屏：漂浮文字层（最底，不挡操作）
	floating_labels = FloatingLabels.new()
	root.add_child(floating_labels)

	# 第三人称准星（操控模式显示；交互提示 / 建造模式变色）
	crosshair = Crosshair.new()
	root.add_child(crosshair)

	top_bar = TopBar.new()
	root.add_child(top_bar)

	quest_panel = QuestPanel.new()
	root.add_child(quest_panel)

	boss_banner = BossBanner.new()
	root.add_child(boss_banner)

	# v40 区域发现横幅：顶部居中、头目横幅下方（与任务卡 / 选中信息 / 小地图都不重叠）。
	_build_region_banner(root)

	selection_panel = SelectionInfoPanel.new()
	root.add_child(selection_panel)

	minimap = Minimap.new()
	root.add_child(minimap)

	build_menu = BuildMenu.new()
	root.add_child(build_menu)

	hero_panel = HeroPanel.new()
	root.add_child(hero_panel)
	# v17 去冗余：原 SquadPanel 独立卡已并入 HeroPanel（小队计数 / 成员 / 集火 / 操作提示
	# 只此一处；顺带消灭「小队面板压任务卡」「主角面板压建造菜单」两处重叠）。

	event_log = EventLog.new()
	root.add_child(event_log)

	# 暂停遮罩：居中 [pause 图标 + 提示文字]（图标走 IconDB，缺图自动回退字徽）
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.42)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.visible = false
	var pause_center := CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(pause_center)
	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 10)
	pause_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_center.add_child(pause_box)
	var pause_icon := IconBadge.new(&"pause", 44, UIStyle.GOLD, "停")
	pause_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pause_box.add_child(pause_icon)
	pause_label = Label.new()
	pause_label.text = "已暂停 —— 按 P 继续 · Esc 打开菜单"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 30)
	pause_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	pause_box.add_child(pause_label)
	root.add_child(pause_overlay)

	# 新手引导浮层（v4 新增）：聚光灯遮罩 + 步骤卡。压暗只作用于世界画面与 HUD 面板、
	# 位于模态（游戏结束 / 入驻提示）之下——结算与暂停确认必须盖过引导。
	# 只负责渲染，状态与推进在 WorldRoot/TutorialSystem；遮罩不拦截任何操作。
	tutorial_overlay = TutorialOverlay.new()
	tutorial_overlay.system = get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	root.add_child(tutorial_overlay)

	# 游戏结束遮罩：居中 [结算大图标 + 标题 + 战绩 + 重新开始]
	# 图标：胜利 crown（金）/ 失败 boss（危险红，夜袭头目）；文案与按钮行为与旧版一致。
	gameover_overlay = ColorRect.new()
	gameover_overlay.color = Color(0.02, 0.0, 0.0, 0.72)
	gameover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_overlay.visible = false
	var go_center := CenterContainer.new()
	go_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_overlay.add_child(go_center)
	var go_box := VBoxContainer.new()
	go_box.alignment = BoxContainer.ALIGNMENT_CENTER
	go_box.add_theme_constant_override("separation", 12)
	go_center.add_child(go_box)
	_gameover_icon = IconBadge.new(&"crown", 64, UIStyle.GOLD, "胜")
	_gameover_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go_box.add_child(_gameover_icon)
	gameover_label = Label.new()
	gameover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gameover_label.add_theme_font_size_override("font_size", 44)
	go_box.add_child(gameover_label)
	_gameover_sub = Label.new()
	_gameover_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gameover_sub.add_theme_font_size_override("font_size", 17)
	_gameover_sub.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	go_box.add_child(_gameover_sub)
	_gameover_btn = Button.new()
	_gameover_btn.text = "重新开始"
	_gameover_btn.custom_minimum_size = Vector2(140, 40)
	_gameover_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_gameover_btn.focus_mode = Control.FOCUS_NONE
	_gameover_btn.pressed.connect(func():
		# 游戏结束会把 time_scale 归零；场景重载不会恢复它——不重置会「重开后仍暂停」
		TimeManager.set_speed(1.0)
		get_tree().reload_current_scene())
	go_box.add_child(_gameover_btn)
	root.add_child(gameover_overlay)

	# 入驻提示：定居的暂停确认卡（避免重要人口变化在日志中一闪而过）
	settlement_notice = ColorRect.new()
	settlement_notice.color = Color(0.0, 0.0, 0.0, 0.55)
	settlement_notice.set_anchors_preset(Control.PRESET_FULL_RECT)
	settlement_notice.visible = false
	settlement_notice.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -230.0
	panel.offset_top = -110.0
	panel.offset_right = 230.0
	panel.offset_bottom = 110.0
	settlement_notice.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var notice_icon := IconBadge.new(&"home", 42, Color(0.85, 0.6, 0.45), "家")
	notice_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(notice_icon)
	settlement_notice_label = Label.new()
	settlement_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settlement_notice_label.add_theme_font_size_override("font_size", 24)
	box.add_child(settlement_notice_label)
	var hint := Label.new()
	# v25 收敛：白天讨伐 / 夜晚驻防由引导与夜晚播报讲；这里只留本卡上下文需要的键位
	hint.text = "按 V 市民管理 · G 集结 / 解散 · 准星对怪按 T 集火"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(hint)
	var confirm := Button.new()
	confirm.text = "继续"
	confirm.custom_minimum_size = Vector2(130.0, 36.0)
	confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(_dismiss_settlement_notice)
	box.add_child(confirm)
	root.add_child(settlement_notice)

	# 调试覆盖层（F1 切换）：FPS / 节点数 / 敌人 / 单位数，用于排查卡顿与泄漏
	_debug_label = Label.new()
	_debug_label.text = ""
	_debug_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_label.offset_left = -260.0
	_debug_label.offset_top = 56
	_debug_label.offset_right = -12.0
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.visible = false
	root.add_child(_debug_label)

	# Esc 暂停菜单：继续 / 设置 / 返回主菜单 / 退出。
	# 打开时自身占用 ui_modal_count 并把 time_scale 归零（HeroController 据此释放鼠标）。
	pause_menu = PauseMenu.new()
	root.add_child(pause_menu)

	# v25 流民入住职业选择弹窗：挂在 PauseMenu 之后（Esc 由 PauseMenu 防御性放行；
	# 弹窗必须点选职业，无取消语义）。
	settle_picker = SettleClassPicker.new()
	root.add_child(settle_picker)

	# v26 驯龙界面：对龙园按 E 打开（EventBus.dragon_menu_requested），
	# 真暂停模态；Esc 由本界面自收，PauseMenu 防御性放行。
	dragon_menu = DragonMenu.new()
	root.add_child(dragon_menu)

	# 市民管理界面（v25 由编队界面升级；仍挂 PauseMenu 之后 = 暂停菜单之上）：
	# 按 V 或右上「市民管理」按钮打开，真暂停 + 模态。Esc / V 由本界面自己收。
	party_panel = CitizenPanel.new()
	root.add_child(party_panel)

	# 技能树面板（v25，最后挂 = 最顶层）：从市民管理行内「技能树」按钮进入，
	# 关闭后回到仍开着的市民管理。
	skill_tree_panel = SkillTreePanel.new()
	root.add_child(skill_tree_panel)

	# v25 市民管理独立入口按钮：右侧竖向空档（选中信息面板 y≤344 与小地图 y≥440 之间），
	# 不与任何既有面板重叠；点击等同按 V（建造模式让位）。
	citizen_button = Button.new()
	citizen_button.text = "市民管理 (V)"
	citizen_button.tooltip_text = "查看全部市民 / 编队 / 转职 / 技能树（快捷键 V）"
	citizen_button.focus_mode = Control.FOCUS_NONE
	citizen_button.anchor_left = 1.0
	citizen_button.anchor_top = 0.0
	citizen_button.anchor_right = 1.0
	citizen_button.anchor_bottom = 0.0
	citizen_button.offset_left = -116.0
	citizen_button.offset_top = 352.0
	citizen_button.offset_right = -12.0
	citizen_button.offset_bottom = 390.0
	citizen_button.pressed.connect(_on_citizen_button_pressed)
	root.add_child(citizen_button)

	# v31 夜间守城准备按钮：入夜时间静止，清完残敌、配置好小队后点它恢复时间并
	# 迎战夜潮。底部居中（建造菜单在左下、准星在屏幕中心，互不遮挡）；
	# 不占模态——准备期玩家仍可自由战斗 / 建造 / 打开市民管理。
	# 第三人称鼠标被捕获点不到按钮时，「回车」是同义入口（见 _unhandled_input）。
	defense_hint = Label.new()
	defense_hint.text = ""
	defense_hint.anchor_left = 0.5
	defense_hint.anchor_right = 0.5
	defense_hint.anchor_top = 1.0
	defense_hint.anchor_bottom = 1.0
	defense_hint.offset_left = -280.0
	defense_hint.offset_right = 280.0
	defense_hint.offset_top = -168.0
	defense_hint.offset_bottom = -138.0
	defense_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defense_hint.add_theme_font_size_override("font_size", 14)
	defense_hint.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	defense_hint.visible = false
	root.add_child(defense_hint)

	defense_button = Button.new()
	defense_button.text = "准备守城"
	defense_button.tooltip_text = "时间恢复流动，夜潮攻城开始（回车亦可）"
	defense_button.focus_mode = Control.FOCUS_NONE
	defense_button.anchor_left = 0.5
	defense_button.anchor_right = 0.5
	defense_button.anchor_top = 1.0
	defense_button.anchor_bottom = 1.0
	defense_button.offset_left = -150.0
	defense_button.offset_right = 150.0
	defense_button.offset_top = -128.0
	defense_button.offset_bottom = -80.0
	defense_button.add_theme_font_size_override("font_size", 20)
	defense_button.visible = false
	defense_button.pressed.connect(_on_defense_button_pressed)
	root.add_child(defense_button)


## v40 区域发现横幅：顶部居中、头目横幅下方（y 132）。
## 只做表现层——进出判定与叙事文本全部来自 RegionTracker 广播的 EventBus 信号；
## 横幅自身不轮询主角位置，也不改任何既有面板的布局与信号连接。
func _build_region_banner(root: Control) -> void:
	region_banner = PanelContainer.new()
	region_banner.name = "RegionBanner"
	region_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	region_banner.anchor_left = 0.5
	region_banner.anchor_right = 0.5
	region_banner.anchor_top = 0.0
	region_banner.anchor_bottom = 0.0
	region_banner.offset_left = -REGION_BANNER_HALF_W
	region_banner.offset_right = REGION_BANNER_HALF_W
	region_banner.offset_top = REGION_BANNER_TOP
	region_banner.offset_bottom = REGION_BANNER_TOP + REGION_BANNER_H
	region_banner.visible = false
	# 暗金面板底：描边与左侧竖线在显示时按区域 accent 重新着色（缺 accent 回落亮金）。
	_region_panel_style = StyleBoxFlat.new()
	_region_panel_style.bg_color = Color(0.10, 0.085, 0.07, 0.93)
	_region_panel_style.border_color = Color(UIStyle.BORDER_GOLD, 0.85)
	_region_panel_style.set_border_width_all(1)
	_region_panel_style.set_corner_radius_all(6)
	_region_panel_style.content_margin_left = 14.0
	_region_panel_style.content_margin_right = 14.0
	_region_panel_style.content_margin_top = 8.0
	_region_panel_style.content_margin_bottom = 8.0
	region_banner.add_theme_stylebox_override("panel", _region_panel_style)
	root.add_child(region_banner)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	region_banner.add_child(row)

	# 左侧 accent 竖线（区域强调色）
	_region_accent_bar = ColorRect.new()
	_region_accent_bar.name = "RegionAccent"
	_region_accent_bar.color = UIStyle.GOLD
	_region_accent_bar.custom_minimum_size = Vector2(4.0, 0.0)
	_region_accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_region_accent_bar)

	var text_box := VBoxContainer.new()
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)

	# 「✦ 新区域」：仅会话内首次发现显示
	_region_kicker = Label.new()
	_region_kicker.name = "RegionKicker"
	_region_kicker.text = ""
	_region_kicker.visible = false
	_region_kicker.add_theme_font_size_override("font_size", 12)
	_region_kicker.add_theme_color_override("font_color", UIStyle.GOLD)
	_region_kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_region_kicker)

	# 区域名（大字，accent 着色 + 黑描边保证任何地表上都可读）
	_region_name = Label.new()
	_region_name.name = "RegionName"
	_region_name.add_theme_font_override("font", UIStyle.make_display_font())
	_region_name.add_theme_font_size_override("font_size", 26)
	_region_name.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	_region_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_region_name.add_theme_constant_override("outline_size", 3)
	_region_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_region_name)

	# 一句话副标题（小字，暖灰）
	_region_subtitle = Label.new()
	_region_subtitle.name = "RegionSubtitle"
	_region_subtitle.add_theme_font_size_override("font_size", 13)
	_region_subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_region_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_region_subtitle)


## 市民管理按钮：与 V 键同语义（建造模式让位；已在开时静默）。
func _on_citizen_button_pressed() -> void:
	if party_panel == null or party_panel.is_open:
		return
	if SelectionManager.build_mode_active:
		return
	party_panel.open()


func _connect_signals() -> void:
	EventBus.time_scale_changed.connect(_on_time_scale_changed)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.game_over.connect(_on_game_over)
	EventBus.resident_settled.connect(_on_resident_settled)
	EventBus.night_prep_started.connect(_on_night_prep_started)
	EventBus.night_defense_started.connect(_on_night_defense_started)
	# v40 区域发现：追踪器广播，HUD 只负责横幅表现（故事文本 / 音效由 RegionTracker 发）
	EventBus.region_discovered.connect(_on_region_discovered)
	EventBus.region_entered.connect(_on_region_entered)
	EventBus.region_exited.connect(_on_region_exited)


# ---- v31 夜间守城准备 ----

func _on_defense_button_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	GameManager.request_night_defense()


func _on_night_prep_started() -> void:
	_night_prep_active = true
	defense_button.visible = true
	defense_hint.visible = true


func _on_night_defense_started() -> void:
	_night_prep_active = false
	defense_button.visible = false
	defense_hint.visible = false


## 准备期状态行：残敌数 → 城防就绪（每帧刷，成本 = 一次分组查询，与调试层同量级）。
func _refresh_defense_hint() -> void:
	if defense_hint == null:
		return
	var remaining: int = get_tree().get_nodes_in_group("enemy").size()
	if remaining > 0:
		defense_hint.text = "时间静止 · 残敌 %d 只——清剿残敌、配置小队后开战" % remaining
	else:
		defense_hint.text = "城防就绪 · 配置小队（V 市民管理 / G 集结 / T 集火）后迎战夜潮"


func _on_time_scale_changed(scale: float) -> void:
	# P 键裸暂停遮罩：Esc 菜单开着时不重复显示（菜单自带更深的遮罩与操作）
	pause_overlay.visible = scale <= 0.0 \
			and GameManager.phase != GameManager.Phase.GAME_OVER \
			and not pause_menu.is_open


func _on_phase_changed(_old: int, new_phase: int) -> void:
	pause_overlay.visible = new_phase == GameManager.Phase.PAUSED and not pause_menu.is_open


func _on_game_over(victory: bool) -> void:
	gameover_overlay.visible = true
	_night_prep_active = false
	defense_button.visible = false
	defense_hint.visible = false
	gameover_label.text = "胜  利！" if victory else "基地陷落…"
	# 结算大图标：胜利戴冠（金）/ 失败是夜袭头目（危险红）
	_gameover_icon.set_badge(&"crown" if victory else &"boss", -1,
		UIStyle.BORDER_GOLD_BRIGHT if victory else UIStyle.DANGER, "胜" if victory else "败")
	AudioManager.play_sfx(&"victory" if victory else &"game_over")
	var hero := _find_hero()
	var stats := ""
	if hero != null:
		stats = "主角 Lv.%d「%s」 · 击杀 %d · 第 %d 天" % [hero.level, hero.hero_title(), hero.kill_count, TimeManager.day]
	_gameover_sub.text = stats


func _find_hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _on_resident_settled(resident_name: String, _house: Node) -> void:
	_notice_previous_speed = TimeManager.time_scale
	TimeManager.set_speed(0.0)
	settlement_notice_label.text = "%s 入驻了城镇" % resident_name
	settlement_notice.visible = true
	# UI 模态：占住鼠标（第三人称操控下临时释放指针，方便点击「继续」）
	SelectionManager.ui_modal_count += 1
	AudioManager.play_sfx(&"settle")


func _dismiss_settlement_notice() -> void:
	if not settlement_notice.visible:
		return   # 幂等：未打开时不重复减模态计数、不动倍速（测试/重复调用安全）
	settlement_notice.visible = false
	SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)
	AudioManager.play_sfx(&"ui_click")
	if GameManager.phase != GameManager.Phase.GAME_OVER:
		TimeManager.set_speed(_notice_previous_speed)


# ---- v40 区域发现横幅 ----

## 会话内首次发现某区域：横幅带「✦ 新区域」小字（故事文本与音效由 RegionTracker 负责）。
func _on_region_discovered(region_id: StringName, region_name: String, subtitle: String,
		_lore: String) -> void:
	_show_region_banner(region_id, region_name, subtitle, true)


## 每次进入区域（含首次）：只弹名字 + 副标题；首次的额外叙事已在 region_discovered 处理。
func _on_region_entered(region_id: StringName, region_name: String, subtitle: String,
		_lore: String, first_time: bool) -> void:
	_show_region_banner(region_id, region_name, subtitle, first_time)


## 离开区域：立即开始淡出（不等停留计时走完）。
func _on_region_exited(_region_id: StringName) -> void:
	if region_banner == null or not region_banner.visible:
		return
	if not is_inside_tree():
		return
	_kill_region_tween()
	_region_shown_id = &""
	_region_tween = create_tween()
	_region_tween.set_ignore_time_scale(true)
	_region_tween.tween_property(region_banner, "modulate", Color(1, 1, 1, 0), REGION_EXIT_FADE)
	_region_tween.tween_callback(_hide_region_banner)


## 弹横幅：淡入 0.25s → 停留 4.5s → 淡出 0.6s。
## 同一区域重复进入只刷新倒计时（不重新淡入、不闪一下）。
func _show_region_banner(region_id: StringName, region_name: String, subtitle: String,
		first_time: bool) -> void:
	if region_banner == null or not is_inside_tree():
		return
	var accent := _region_accent_color(region_id)
	_region_name.text = region_name
	_region_subtitle.text = subtitle
	_region_kicker.text = "✦ 新区域" if first_time else ""
	_region_kicker.visible = first_time
	_region_name.add_theme_color_override("font_color", accent)
	_region_accent_bar.color = accent
	_region_panel_style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	region_banner.visible = true

	var refresh_only := _region_shown_id == region_id and region_banner.modulate.a > 0.01
	_region_shown_id = region_id
	_kill_region_tween()
	# set_ignore_time_scale(true)：3× 调速或暂停时横幅节奏仍按真实时间走，
	# 不会因为 Engine.time_scale 变化而快进 / 冻结。
	_region_tween = create_tween()
	_region_tween.set_ignore_time_scale(true)
	if refresh_only:
		region_banner.modulate = Color(1, 1, 1, 1)
	else:
		region_banner.modulate = Color(1, 1, 1, 0)
		_region_tween.tween_property(region_banner, "modulate", Color(1, 1, 1, 1), REGION_FADE_IN)
	_region_tween.tween_interval(REGION_HOLD)
	_region_tween.tween_property(region_banner, "modulate", Color(1, 1, 1, 0), REGION_FADE_OUT)
	_region_tween.tween_callback(_hide_region_banner)


func _hide_region_banner() -> void:
	_region_shown_id = &""
	if region_banner != null:
		region_banner.visible = false


func _kill_region_tween() -> void:
	if _region_tween != null and _region_tween.is_valid():
		_region_tween.kill()
	_region_tween = null


## 区域强调色：取 WorldRegions 的 accent；找不到区域（异常/已删数据）回落亮金。
func _region_accent_color(region_id: StringName) -> Color:
	var region := WorldRegions.find(region_id)
	if region.is_empty():
		return UIStyle.BORDER_GOLD_BRIGHT
	var accent: Variant = region.get("accent")
	if accent is Color:
		return accent as Color
	return UIStyle.BORDER_GOLD_BRIGHT


## 横幅是否正在显示（回归断言用，只读）。
func is_region_banner_showing() -> bool:
	return region_banner != null and region_banner.visible and region_banner.modulate.a > 0.01


## 横幅当前显示的区域名（无横幅时为空串，回归断言用，只读）。
func region_banner_region_name() -> String:
	return "" if _region_name == null else _region_name.text


func _process(_delta: float) -> void:
	if _debug_label != null and _debug_label.visible:
		_debug_label.text = "FPS:%d  节点:%d  敌人:%d  单位:%d" % [
			Engine.get_frames_per_second(),
			get_tree().get_node_count(),
			get_tree().get_nodes_in_group("enemy").size(),
			get_tree().get_nodes_in_group("player_unit").size()]
	if _night_prep_active:
		_refresh_defense_hint()


func _unhandled_input(event: InputEvent) -> void:
	# F1 切换调试覆盖层（FPS / 节点 / 实体数）—— 卡顿时看节点数是否持续上涨（泄漏）或
	# FPS 掉而节点稳（渲染/GPU）。F1 是物理键，不与任何游戏操作冲突。
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F1:
		_debug_visible = not _debug_visible
		if _debug_label != null:
			_debug_label.visible = _debug_visible
		get_viewport().set_input_as_handled()
	# v31 守城准备期：回车 = 点「准备守城」（第三人称鼠标被捕获点不到按钮时的同义
	# 入口）。有模态界面（市民管理 / 入住选职业 / 暂停菜单…）打开时不抢键。
	if _night_prep_active and event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		if SelectionManager.ui_modal_count <= 0 and GameManager.phase != GameManager.Phase.GAME_OVER:
			GameManager.request_night_defense()
			get_viewport().set_input_as_handled()
