class_name SkillTreePanel
extends Control
## ============================================================================
## 技能树界面（v25.2 全面美化，树状布局）：每个人物（主角 + 市民）可点击进入
## （市民管理 / 主角行的「技能树」按钮）。每次升级 +1 技能点，从根节点逐级点亮：
##
##     ╭────────╮        ╭────────╮        ╭────────╮
##     │ ◉ 职业技 │───◆───│ ◈ 伤害 │───◆───│ ◈ 生命 │      节点卡四态：
##     │ 主动技名 │  金线  │ ●●○○○  │  流光  │ ●○○○○  │      · 已满级（金框+星标）
##     │ [点 亮] │        │ [加点] │        │ [加点] │      · 可加点（彩框+呼吸辉光）
##     ╰────────╯        ╰────────╯        ╰────────╯      · 已投入（常态彩框）
##                                                          · 未解锁（暗化+锁印）
## · 根节点「职业技」= 该职业现在的主动技能（血怒 / 暴风雪 / 快速射击 / 背刺），
##   点亮后才能在战斗中施放（Pawn.try_cast_combat_skill 门禁）；进阶职业的改名
##   （如雷电法师的「雷暴」）自动跟随 def.skill 显示。
## · 主角树根节点预点亮（Q/C 技能不参与门禁，节点只作树根）。
## · 布局按节点深度分列、父子之间由 TreeConnectors 画贝塞尔连线（发光 + 流光粒子 +
##   箭头），树区背景 TreeBackdrop 画同心圆纹章；连线/辉光每帧重绘，布局变化自动跟随
##   （v25.1 曾只在刷新时画一次，容器排版未定稿 → 连线悬空错位，真机样张实锤）。
## · 节点卡状态全数据驱动（SkillNodeDef + PawnSkillTree），后续加分支无需改本界面。
## 打开 = 真暂停 + 占用 ui_modal_count；通常叠在市民管理之上（市民管理保持打开，
## 关闭本面板即回到市民管理）。Esc / V 关闭。
##
## **刷新必须 call_deferred**：「加点」按钮的 pressed 回调里加点 → skill_tree_changed
## → 重建树；若同步 remove+free 正在发信号的按钮节点，Godot 会报「freed while a
## signal is being emitted」并可能直接崩（v25.1 真机实锤）。
## ============================================================================

var is_open: bool = false
var pawn: Pawn = null

var _dim: ColorRect
var _portrait: IconBadge
var _title_label: Label
var _subtitle_label: Label
var _points_chip: PanelContainer
var _points_label: Label
var _bonus_label: RichTextLabel
var _tree_area: Control
var _backdrop: TreeBackdrop
var _lines: TreeConnectors
var _columns_box: HBoxContainer
var _note_label: Label
var _previous_speed: float = 1.0
var _cards: Dictionary = {}    # StringName(节点 id) -> PanelContainer(节点卡)

# ---- v33.1 悬停浮动弹窗（卡片只留缩略图 + 简介，详细信息移到浮窗）----
var _tip: PanelContainer
var _tip_badge: IconBadge
var _tip_title: Label
var _tip_head: Label
var _tip_desc: Label
var _tip_fx: Label
var _tip_req: Label
var _tip_state: Label
var _tip_node_id: StringName = &""   # 当前浮窗对应的节点（空 = 未显示）


## 连线层：按「父卡右缘中点 → 子卡左缘中点」画三次贝塞尔连线。
## 双层描（宽辉光 + 亮芯）+ 子端箭头；前置满足时叠两颗沿曲线流动的光点。
## draw 时实时取卡片位置、面板 _process 每帧 queue_redraw——布局变化 / 开场
## 排版未定稿时连线都不会悬空（v25.2 修）。
class TreeConnectors:
	extends Control
	var pairs: Array = []   # [{ from: Control, to: Control, lit: bool, color: Color }]
	const COLOR_DIM := Color(0.42, 0.37, 0.30, 0.85)

	func _draw() -> void:
		for p in pairs:
			var from_c: Control = p["from"]
			var to_c: Control = p["to"]
			if from_c == null or to_c == null or not is_instance_valid(from_c) \
					or not is_instance_valid(to_c):
				continue
			var a: Vector2 = from_c.get_global_rect().position \
					+ Vector2(from_c.get_global_rect().size.x, from_c.get_global_rect().size.y * 0.5) - global_position
			var b: Vector2 = to_c.get_global_rect().position \
					+ Vector2(0.0, to_c.get_global_rect().size.y * 0.5) - global_position
			var col: Color = p["color"] if p["lit"] else COLOR_DIM
			# 水平出入的三次贝塞尔（控制点在两点水平中线上），弧度自然朝向下一列
			var dx: float = maxf(26.0, (b.x - a.x) * 0.55)
			var c1 := a + Vector2(dx, 0.0)
			var c2 := b - Vector2(dx, 0.0)
			var pts := PackedVector2Array()
			var steps := 28
			for i in steps + 1:
				pts.append(_bezier(a, c1, c2, b, float(i) / float(steps)))
			# 辉光层（宽、低透明）→ 亮芯层
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.16 if p["lit"] else 0.10), 9.0, true)
			draw_polyline(pts, Color(col.r, col.g, col.b, 0.92 if p["lit"] else 0.55), 2.5, true)
			# 子端箭头（沿末端切线的小三角）
			var dir := (pts[steps] - pts[steps - 1]).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var perp := Vector2(-dir.y, dir.x) * 5.5
			var tip := b + dir * 2.0
			draw_colored_polygon(PackedVector2Array(
				[tip, tip - dir * 11.0 + perp, tip - dir * 11.0 - perp]),
				Color(col.r, col.g, col.b, 0.95))
			# 已点亮：两颗沿曲线流动的光点（真实时间驱动，暂停中界面依然有生命感）
			if p["lit"]:
				var now := Time.get_ticks_msec() / 1000.0
				for k in 2:
					var t := fmod(now * 0.4 + float(k) * 0.5, 1.0)
					var pt := _bezier(a, c1, c2, b, t)
					draw_circle(pt, 6.0, Color(col.r, col.g, col.b, 0.16))
					draw_circle(pt, 2.8, Color(col.r, col.g, col.b, 0.75))

	func _bezier(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return a * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + b * (t * t * t)


## 树区背景：中心柔光 + 两圈同心圆环 + 环上暗金菱形星点（低透明度，衬托而非抢戏）。
class TreeBackdrop:
	extends Control
	const GOLD := Color(0.95, 0.80, 0.38)

	func _draw() -> void:
		if size.x < 40.0 or size.y < 40.0:
			return
		var c := size * 0.5
		# 中心柔光：三层递减圆叠加出径向渐变感
		for ring in [{ "r": 250.0, "a": 0.020 }, { "r": 180.0, "a": 0.028 }, { "r": 115.0, "a": 0.038 }]:
			draw_circle(c, ring["r"], Color(GOLD.r, GOLD.g, GOLD.b, ring["a"]))
		# 同心圆环
		draw_arc(c, 152.0, 0.0, TAU, 72, Color(GOLD.r, GOLD.g, GOLD.b, 0.055), 1.0, true)
		draw_arc(c, 214.0, 0.0, TAU, 72, Color(GOLD.r, GOLD.g, GOLD.b, 0.038), 1.0, true)
		# 外环 8 颗菱形星点（45° 均布）
		for i in 8:
			var ang := TAU * float(i) / 8.0 + 0.26
			var d := c + Vector2(cos(ang), sin(ang)) * 214.0
			var r := 3.0
			draw_colored_polygon(PackedVector2Array([
				d + Vector2(0, -r), d + Vector2(r, 0), d + Vector2(0, r), d + Vector2(-r, 0)]),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.10))


## 圆形纹章徽座：IconBadge 外面套发光环——已点亮 / 可加点时呼吸辉光，
## 未解锁时暗化 + 右下角小锁印（纯 draw，无图片依赖）。
class Medallion:
	extends Control
	var accent: Color = UIStyle.GOLD
	var glow := 0.0            # 常驻辉光强度 0~1（已点亮节点）
	var breathes := false      # 可加点时呼吸闪烁
	var locked := false
	var _badge: IconBadge
	var _side_px: int = 58

	func _init(color: Color, px: int = 58) -> void:
		accent = color
		_side_px = px
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge = IconBadge.new(&"", px - 12, color, "")
		add_child(_badge)

	func _ready() -> void:
		if not resized.is_connected(_layout_badge):
			resized.connect(_layout_badge)
		_layout_badge()
		if breathes:
			set_process(true)   # 呼吸辉光需要每帧重绘；仅在需要的节点上启用

	## IconBadge 子件始终钉在徽座正中（否则停在 (0,0)，圆盘与外环错位成月牙）
	func _layout_badge() -> void:
		if _badge == null:
			return
		_badge.position = (size - _badge.custom_minimum_size) * 0.5

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var breathe: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 480.0)
		var g := glow if not breathes else glow * (0.62 + 0.38 * breathe)
		if g > 0.0:
			draw_circle(c, r, Color(accent.r, accent.g, accent.b, 0.20 * g))
			draw_circle(c, r * 0.82, Color(accent.r, accent.g, accent.b, 0.10 * g))
		# 外环：已点亮整圈亮环，未点亮虚淡环
		draw_arc(c, r - 1.5, 0.0, TAU, 48,
			Color(accent.r, accent.g, accent.b, 0.85 if glow > 0.4 else 0.35), 2.0, true)
		if locked:
			_draw_lock(c + Vector2(r * 0.34, r * 0.34), 11.0)

	func _draw_lock(origin: Vector2, s: float) -> void:
		# 小锁印：锁环（半圆弧）+ 锁体（圆角矩形），暗金
		var col := Color(0.85, 0.72, 0.45, 0.92)
		var back := Color(0.06, 0.05, 0.04, 0.85)
		draw_circle(origin + Vector2(s * 0.5, s * 0.5), s * 0.72, back)
		draw_arc(origin + Vector2(s * 0.5, s * 0.42), s * 0.30, PI, TAU, 16, col, 2.0, true)
		var body := Rect2(origin + Vector2(s * 0.12, s * 0.42), Vector2(s * 0.76, s * 0.58))
		var sb := StyleBoxFlat.new()
		sb.bg_color = back
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(3)
		draw_style_box(sb, body)
		draw_circle(origin + Vector2(s * 0.5, s * 0.66), 1.8, col)
		draw_line(origin + Vector2(s * 0.5, s * 0.66), origin + Vector2(s * 0.5, s * 0.80), col, 2.0)


func _ready() -> void:
	name = "SkillTreePanel"
	add_to_group("skill_tree_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 全矩形铺满父级 + 显式清零 offsets（父级已布局时 set_anchors_preset 会按当前
	# 0×0 rect 回推 offsets → 面板永远 0×0 不可见，准星同款坑）
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_ui()
	EventBus.skill_tree_changed.connect(_on_skill_tree_changed)
	EventBus.pawn_leveled.connect(_on_pawn_leveled)
	EventBus.hero_leveled.connect(_on_hero_leveled)


func _process(_delta: float) -> void:
	# 连线每帧重绘：容器排版晚于首帧、窗口缩放、刷新重建都会挪动卡片，
	# 逐帧取样位置保证连线永远钉在卡片边缘（每帧仅 2~3 条折线，开销可忽略）。
	if is_open and visible:
		_lines.queue_redraw()
		_update_hover_tip()


func _on_skill_tree_changed(_p: Node) -> void:
	call_deferred("_refresh")   # 延迟刷新：避免 free 掉正在发 pressed 信号的加点按钮


func _on_pawn_leveled(_p: Node, _lv: int) -> void:
	call_deferred("_refresh")


func _on_hero_leveled(_p: Node, _lv: int) -> void:
	call_deferred("_refresh")


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.0, 0.0, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.offset_left = 0.0
	_dim.offset_top = 0.0
	_dim.offset_right = 0.0
	_dim.offset_bottom = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIStyle.panel_style(&"ornate"))
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	box.add_child(UIStyle.section_title("技 能 树", &"xp", 18))

	# ---- 人物信息条：职业纹章 + 姓名/职业/等级 + 技能点胶囊 ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var unit_color := UIStyle.GOLD
	var unit_char := "英"
	if pawn != null and pawn.def != null and String(pawn.def.class_icon) != "":
		unit_color = pawn.def.class_color
		unit_char = pawn.def.class_icon
	_portrait = IconBadge.new(&"", 44, unit_color, unit_char)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_portrait)

	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 1)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_box)
	_title_label = Label.new()
	_title_label.text = "—"
	_title_label.add_theme_font_override("font", UIStyle.make_display_font())
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_box.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.text = ""
	_subtitle_label.add_theme_font_size_override("font_size", 12)
	_subtitle_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	name_box.add_child(_subtitle_label)

	_points_chip = PanelContainer.new()
	_points_chip.add_theme_stylebox_override("panel", UIStyle.chip_style())
	_points_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_points_chip)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 6)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points_chip.add_child(chip_row)
	chip_row.add_child(UIStyle.icon(&"xp", 16, UIStyle.XP_BLUE))
	_points_label = Label.new()
	_points_label.text = "可用技能点 0"
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", UIStyle.XP_BLUE)
	chip_row.add_child(_points_label)

	# 已生效加成（RichTextLabel 走 bbcode 上色两段收益值）
	_bonus_label = RichTextLabel.new()
	_bonus_label.bbcode_enabled = true
	_bonus_label.fit_content = true
	_bonus_label.scroll_active = false
	_bonus_label.custom_minimum_size = Vector2(0.0, 20.0)
	_bonus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus_label.add_theme_color_override("default_color", UIStyle.TEXT_DIM)
	_bonus_label.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_bonus_label)

	# ---- 树区：背景纹章层 → 连线层（垫底）→ 按深度分列的节点卡 ----
	# v33.1：卡片改「缩略图 + 简介」紧凑版（详细说明走悬停浮窗），树区高度随之收窄
	_tree_area = Control.new()
	_tree_area.custom_minimum_size = Vector2(0.0, 236.0)
	_tree_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_tree_area)

	_backdrop = TreeBackdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = 0.0
	_backdrop.offset_top = 0.0
	_backdrop.offset_right = 0.0
	_backdrop.offset_bottom = 0.0
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_area.add_child(_backdrop)

	_lines = TreeConnectors.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.offset_left = 0.0
	_lines.offset_top = 0.0
	_lines.offset_right = 0.0
	_lines.offset_bottom = 0.0
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_area.add_child(_lines)

	_columns_box = HBoxContainer.new()
	_columns_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_columns_box.offset_left = 0.0
	_columns_box.offset_top = 0.0
	_columns_box.offset_right = 0.0
	_columns_box.offset_bottom = 0.0
	_columns_box.add_theme_constant_override("separation", 58)   # 列间留白给贝塞尔连线
	_columns_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_area.add_child(_columns_box)

	_note_label = Label.new()
	_note_label.text = ""
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_label.add_theme_font_size_override("font_size", 12)
	_note_label.add_theme_color_override("font_color", UIStyle.DANGER)
	_note_label.custom_minimum_size = Vector2(0.0, 18.0)   # 占位防整版跳动
	box.add_child(_note_label)

	# ---- 底栏：操作提示 + 关闭按钮 ----
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var hint := Label.new()
	hint.text = "每次升级 +1 技能点 · 悬停卡片看详情 · 转职会清空并全额返还技能点"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(hint)
	var close_btn := Button.new()
	close_btn.text = "关 闭（Esc）"
	close_btn.custom_minimum_size = Vector2(150.0, 32.0)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	foot.add_child(close_btn)

	_build_tip()


# ============================================================================
# 悬停浮窗（v33.1）：卡片只放缩略图 + 简介，完整说明 / 收益 / 前置 / 状态在这里
# ============================================================================

## 浮窗骨架（一次性构建；内容在悬停切换节点时重填）。挂在本面板根节点上、
## 排在 center 之后 → 永远画在卡片之上；mouse_filter=IGNORE 不抢鼠标。
func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.name = "NodeTip"
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(272.0, 0.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.072, 0.058, 0.98)
	sb.border_color = Color(UIStyle.BORDER_GOLD_BRIGHT, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 12
	_tip.add_theme_stylebox_override("panel", sb)
	add_child(_tip)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	_tip_badge = IconBadge.new(&"", 30, UIStyle.GOLD, "技")
	_tip_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_tip_badge)
	var head_box := VBoxContainer.new()
	head_box.add_theme_constant_override("separation", 1)
	head_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_box)
	_tip_title = Label.new()
	_tip_title.add_theme_font_size_override("font_size", 14)
	_tip_title.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	_tip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_box.add_child(_tip_title)
	_tip_head = Label.new()
	_tip_head.add_theme_font_size_override("font_size", 11)
	_tip_head.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_tip_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_box.add_child(_tip_head)

	_tip_desc = _tip_line(12, UIStyle.TEXT_MAIN, box)
	_tip_fx = _tip_line(11, UIStyle.BORDER_GOLD_BRIGHT, box)
	_tip_req = _tip_line(11, UIStyle.DANGER, box)
	_tip_state = _tip_line(11, UIStyle.XP_BLUE, box)


func _tip_line(font_size: int, color: Color, parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(248.0, 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## 每帧悬停检测（比 mouse_entered/exited 稳：卡片内的按钮、pip 等子控件都算命中）。
func _update_hover_tip() -> void:
	if pawn == null or not is_instance_valid(pawn) or pawn.skill_tree == null:
		_tip.visible = false
		_tip_node_id = &""
		return
	var mpos := get_global_mouse_position()
	var hovered: Control = null
	var hovered_id: StringName = &""
	for id in _cards.keys():
		var c: Control = _cards[id]
		if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		if c.get_global_rect().has_point(mpos):
			hovered = c
			hovered_id = id
			break
	if hovered == null:
		_tip.visible = false
		_tip_node_id = &""
		return
	if hovered_id != _tip_node_id:
		_tip_node_id = hovered_id
		_fill_tip(pawn.skill_tree.node(hovered_id))
	_tip.visible = true
	_position_tip(hovered)


## 填充浮窗内容（完整说明 / 每级与当前收益 / 前置 / 当前状态）。
func _fill_tip(n: SkillNodeDef) -> void:
	if n == null:
		_tip.visible = false
		return
	var tree := pawn.skill_tree
	var cur_rank := tree.rank(n.id)
	var maxed := cur_rank >= n.max_rank
	var locked := n.requires_node != &"" and tree.rank(n.requires_node) < n.requires_rank

	_tip_badge.set_badge(&"", 30, n.color, n.icon)
	_tip_title.text = _node_title(n)
	_tip_title.add_theme_color_override("font_color",
		UIStyle.BORDER_GOLD_BRIGHT if maxed else (UIStyle.TEXT_DIM if locked else UIStyle.TEXT_MAIN))
	var kind_text := "强化节点"
	if n.unlocks_skill:
		kind_text = "职业主动技" if _is_primary_skill_node(n) else "进阶专属技"
	_tip_head.text = "%s · 等级 %d/%d" % [kind_text, cur_rank, n.max_rank]

	_tip_desc.text = n.desc

	var fx: Array[String] = []
	if n.damage_per_rank > 0.0:
		fx.append("每级 攻击伤害 +%.0f%%（满级 +%.0f%%）"
			% [roundf(n.damage_per_rank * 100.0), roundf(n.damage_per_rank * float(n.max_rank) * 100.0)])
	if n.hp_per_rank > 0.0:
		fx.append("每级 生命上限 +%.0f%%（满级 +%.0f%%）"
			% [roundf(n.hp_per_rank * 100.0), roundf(n.hp_per_rank * float(n.max_rank) * 100.0)])
	if n.unlocks_skill:
		fx.append("战斗中自动施放（受冷却与施法条件约束）")
	if not fx.is_empty():
		if n.damage_per_rank > 0.0 or n.hp_per_rank > 0.0:
			fx.append("当前已生效：攻击 +%.0f%% / 生命 +%.0f%%"
				% [roundf(n.damage_bonus_at(cur_rank) * 100.0), roundf(n.hp_bonus_at(cur_rank) * 100.0)])
	_tip_fx.text = "\n".join(fx)
	_tip_fx.visible = not fx.is_empty()

	var req_text := pawn.skill_tree.tree_def.requirement_text(n)
	_tip_req.text = ("⚠ " + req_text) if (req_text != "" and locked) else ""
	_tip_req.visible = _tip_req.text != ""

	_tip_state.text = _tip_state_text(n, cur_rank, maxed, locked)


## 状态行：可加点（金）/ 已满级 / 未解锁 / 技能点不足。
func _tip_state_text(n: SkillNodeDef, cur_rank: int, maxed: bool, locked: bool) -> String:
	if n.pre_unlocked and not maxed:
		return "✦ 已随职业解锁（无需加点）"
	if maxed:
		return "★ 已满级"
	if locked:
		return "🔒 尚未解锁"
	if pawn.skill_points <= 0:
		return "技能点不足（升级获得）"
	return "可加点：点击卡片下方「%s」" % ("点亮" if n.unlocks_skill else "加点")


## 浮窗跟随卡片：默认贴在卡片右侧，超出视口则翻到左侧 / 内收（永不越界）。
func _position_tip(card: Control) -> void:
	_tip.reset_size()
	var r := card.get_global_rect()
	var tip_size := _tip.size
	var vp := get_viewport_rect().size
	var pos := Vector2(r.position.x + r.size.x + 10.0, r.position.y)
	if pos.x + tip_size.x > vp.x - 12.0:
		pos.x = r.position.x - tip_size.x - 10.0
	pos.x = clampf(pos.x, 12.0, maxf(12.0, vp.x - tip_size.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vp.y - tip_size.y - 12.0))
	_tip.global_position = pos


# ============================================================================
# 开 / 关（真暂停 + UI 模态）
# ============================================================================

func open_for(target: Pawn) -> void:
	if is_open or target == null or not is_instance_valid(target) or not target.has_skill_tree():
		return
	if GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	pawn = target
	is_open = true
	visible = true
	_dim.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_previous_speed = TimeManager.time_scale
	TimeManager.set_speed(0.0)
	SelectionManager.ui_modal_count += 1
	_refresh()
	AudioManager.play_sfx(&"ui_click")


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_dim.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)
	# 市民管理通常还开着（它有自己的倍速管理）；只有独立打开时才在这里恢复
	var citizen := get_tree().get_first_node_in_group("citizen_panel")
	if citizen == null or not citizen.get("is_open"):
		if GameManager.phase != GameManager.Phase.GAME_OVER:
			TimeManager.set_speed(_previous_speed if _previous_speed > 0.0 else 0.0)
	AudioManager.play_sfx(&"ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("party_menu"):
		close()
		get_viewport().set_input_as_handled()


# ============================================================================
# 渲染：按深度分列 + 发光连线
# ============================================================================

## 该人物职业技的实际显示名（进阶职业改名自动跟随；主角取 Q 技能名）。
func _class_skill_name() -> String:
	if pawn is Hero and (pawn as Hero).hero_def != null \
			and not (pawn as Hero).hero_def.skills.is_empty():
		return (pawn as Hero).hero_def.skills[0].display_name
	if pawn.def != null and pawn.def.skill != null:
		return pawn.def.skill.display_name
	return "—"


## v33：该节点是否解锁「主技能」（旧树无 unlocks_skill_id = 视为根节点语义）。
## 进阶技能节点（跳劈 / 陨石术 / 贯穿射击 / 隐身）返回 false，保留自己的显示名。
func _is_primary_skill_node(n: SkillNodeDef) -> bool:
	if n.unlocks_skill_id == &"":
		return true
	return pawn != null and pawn.def != null and pawn.def.skill != null \
		and n.unlocks_skill_id == pawn.def.skill.id


## 卡片宽度（v33.1 紧凑卡）：三列（基础职业 / 主角）154；进阶树四列 126——
## 4×154 + 3×44 已经比旧的 4×198 + 3×58 收窄一半，四列树不再顶破 1152 逻辑宽。
func _card_width() -> float:
	if pawn == null or pawn.skill_tree == null or pawn.skill_tree.tree_def == null:
		return 154.0
	var cols: int = pawn.skill_tree.tree_def.max_depth() + 1
	return 154.0 if cols <= 3 else 126.0


## 列间距（v33.1）：三列留 44（连线弧度好看），四列收 28 把总宽压下来。
func _column_separation() -> int:
	if pawn == null or pawn.skill_tree == null or pawn.skill_tree.tree_def == null:
		return 44
	return 44 if pawn.skill_tree.tree_def.max_depth() + 1 <= 3 else 28


func _refresh() -> void:
	if not is_open or pawn == null or not is_instance_valid(pawn) or pawn.skill_tree == null:
		return
	var tree := pawn.skill_tree.tree_def
	var class_txt: String = pawn.def.display_name if pawn.def != null else ""
	var unit_color := UIStyle.GOLD
	var unit_char := "英"
	if pawn.def != null and String(pawn.def.class_icon) != "":
		unit_color = pawn.def.class_color
		unit_char = pawn.def.class_icon
	if pawn is Hero:
		class_txt = "主角 · %s" % (pawn as Hero).hero_title()
	_portrait.set_badge(&"", 44, unit_color, unit_char)
	_title_label.text = pawn.get_display_name()
	_subtitle_label.text = "%s · Lv.%d" % [class_txt, pawn.level]
	_points_label.text = "可用技能点 %d" % pawn.skill_points
	_points_label.add_theme_color_override("font_color",
		UIStyle.XP_BLUE if pawn.skill_points > 0 else UIStyle.TEXT_DIM)
	# 已生效加成汇总（实时读运行时树，加点后立即刷新）
	var parts: Array[String] = []
	var dmg := pawn.skill_tree.damage_bonus()
	var hp := pawn.skill_tree.hp_bonus()
	if dmg > 0.0:
		parts.append("攻击伤害 [color=#f2a45c]+%.0f%%[/color]" % roundf(dmg * 100.0))
	if hp > 0.0:
		parts.append("生命上限 [color=#8fe08a]+%.0f%%[/color]" % roundf(hp * 100.0))
	_bonus_label.text = ("已生效加成　" + " · ".join(parts)) if not parts.is_empty() \
		else "尚未加点 —— 沿树点亮节点获得强化"
	_note_label.text = ""

	# 重建列：列号 = 节点深度（根 0 → 职业技，1 → 进阶技能 / 伤害强化，…）
	# v33.1：列间距按列数动态收窄（三列 44 / 四列 28），先把浮窗收起避免指到旧卡片
	_columns_box.add_theme_constant_override("separation", _column_separation())
	_tip.visible = false
	_tip_node_id = &""
	for c in _columns_box.get_children():
		_columns_box.remove_child(c)
		c.free()
	_cards.clear()
	var depth_columns: Array = []
	for _i in tree.max_depth() + 1:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 14)
		col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_columns_box.add_child(col)
		depth_columns.append(col)
	for n in tree.nodes:
		if n == null:
			continue
		var card := _node_card(n)
		(depth_columns[tree.node_depth(n)] as VBoxContainer).add_child(card)
		_cards[n.id] = card

	# v33.1 树区高度自适应：同一深度的多个节点叠在同一列（进阶树「跳劈 + 伤害强化」
	# 都在深度 1 → 列高 282 > 旧的固定 236，卡片会压到底部提示行上——真机实锤的「超框」）。
	# 取最高列的实际内容高作为树区最小高度，列少时仍保留 236 的观感下限。
	var tallest := 0.0
	for col in depth_columns:
		var col_h := 0.0
		var kids := (col as VBoxContainer).get_children()
		for ch in kids:
			col_h += (ch as Control).get_combined_minimum_size().y
		col_h += 14.0 * maxf(0.0, float(kids.size() - 1))
		tallest = maxf(tallest, col_h)
	_tree_area.custom_minimum_size = Vector2(0.0, maxf(236.0, tallest + 10.0))

	# 连线：子节点 → 其前置节点（颜色取子节点主题色，随前置是否满足点亮）
	_lines.pairs.clear()
	for n in tree.nodes:
		if n == null or n.requires_node == &"":
			continue
		var parent_card: Control = _cards.get(n.requires_node)
		var my_card: Control = _cards.get(n.id)
		if parent_card != null and my_card != null:
			_lines.pairs.append({
				"from": parent_card, "to": my_card,
				"lit": pawn.skill_tree.rank(n.requires_node) >= n.requires_rank,
				"color": n.color,
			})
	_lines.queue_redraw()
	_backdrop.queue_redraw()


## 单个技能节点卡（v33.1 紧凑版）：名称/级数 + 纹章缩略图 + 一行简介 +「加点 / 点亮」按钮。
## 完整说明 / 每级收益 / 前置要求 / 当前状态全部移到悬停浮窗（_build_tip / _fill_tip）——
## v33 的进阶树是 4 列，旧竖版卡会把面板顶出画面（真机实锤）。
## 四态视觉：已满级（金框）· 可加点（彩框 + 呼吸辉光）· 已投入（常态彩框）· 未解锁（暗化 + 锁印）。
func _node_card(n: SkillNodeDef) -> Control:
	var tree := pawn.skill_tree
	var cur_rank := tree.rank(n.id)
	var maxed := cur_rank >= n.max_rank
	var locked := n.requires_node != &"" and tree.rank(n.requires_node) < n.requires_rank
	var can_invest := not maxed and not locked and pawn.skill_points > 0

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_card_width(), 0.0)
	card.add_theme_stylebox_override("panel", _card_style(n, maxed, locked, can_invest))
	card.mouse_filter = Control.MOUSE_FILTER_PASS   # 悬停检测由 _process 统一做（含卡内按钮）

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# ---- 名称行：节点名 + 级数（窄卡放不下就省略号截断，不撑宽卡片）----
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 4)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_row)
	var name_l := Label.new()
	name_l.text = _node_title(n)
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.add_theme_color_override("font_color",
		UIStyle.BORDER_GOLD_BRIGHT if maxed else n.color if not locked else UIStyle.TEXT_DIM)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.clip_text = true
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_l)
	var rank_l := Label.new()
	rank_l.text = "%d/%d" % [cur_rank, n.max_rank]
	rank_l.add_theme_font_size_override("font_size", 10)
	rank_l.add_theme_color_override("font_color",
		UIStyle.BORDER_GOLD_BRIGHT if cur_rank > 0 else UIStyle.TEXT_DIM)
	rank_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(rank_l)

	# ---- 纹章缩略图：发光环 + 字徽（未解锁暗化 + 锁印）----
	var medal_slot := CenterContainer.new()
	medal_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(medal_slot)
	var medal := Medallion.new(n.color if not locked else Color(0.5, 0.46, 0.4), 46)
	medal.glow = 1.0 if maxed else (0.55 if cur_rank > 0 else 0.0)
	medal.breathes = can_invest
	medal.locked = locked
	if locked:
		medal._badge.glyph_tint = Color(0.75, 0.72, 0.66, 1)   # 未解锁字徽灰化（须先于 set_badge，glyph 色在重建时读取）
	medal._badge.set_badge(&"", 38, n.color if not locked else Color(0.5, 0.46, 0.4), n.icon)
	medal_slot.add_child(medal)

	# ---- 一行简介：只给「这节点是干什么的」；详细数值 / 前置 / 状态见悬停浮窗 ----
	var desc_l := Label.new()
	desc_l.text = _short_desc(n)
	desc_l.add_theme_font_size_override("font_size", 10)
	desc_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	desc_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc_l.clip_text = true
	desc_l.custom_minimum_size = Vector2(0.0, 16.0)
	desc_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_l)

	# ---- 底部动作槽：加点 / 点亮按钮（满级或预点亮显示状态徽标）----
	var action_slot := CenterContainer.new()
	action_slot.custom_minimum_size = Vector2(0.0, 26.0)
	action_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(action_slot)
	if maxed or n.pre_unlocked:
		var done_l := Label.new()
		if n.pre_unlocked and not maxed:
			done_l.text = "已随职业解锁"
		elif n.unlocks_skill:
			done_l.text = "✦ 已点亮"
		else:
			done_l.text = "★ 已满级"
		done_l.add_theme_font_override("font", UIStyle.make_display_font())
		done_l.add_theme_font_size_override("font_size", 12)
		done_l.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
		done_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		action_slot.add_child(done_l)
	else:
		var invest_btn := Button.new()
		invest_btn.focus_mode = Control.FOCUS_NONE
		invest_btn.text = "点亮" if n.unlocks_skill else "加点"
		invest_btn.add_theme_font_size_override("font_size", 11)
		invest_btn.custom_minimum_size = Vector2(78.0, 24.0)
		var reason := pawn.skill_tree.invest_block_reason(n.id, pawn.skill_points)
		invest_btn.disabled = reason != ""
		if locked:
			invest_btn.tooltip_text = pawn.skill_tree.tree_def.requirement_text(n)
		elif reason != "":
			invest_btn.tooltip_text = reason
		var node_id: StringName = n.id
		invest_btn.pressed.connect(func() -> void:
			if not pawn.try_invest_skill_point(node_id):
				_note_label.text = pawn.skill_tree.invest_block_reason(node_id, pawn.skill_points)
		)
		action_slot.add_child(invest_btn)
	return card


## 卡片 / 浮窗标题：「职业技」根节点显示该职业现在的主动技能名（血怒 / 暴风雪 /
## 快速射击 / 背刺…；进阶职业改名自动跟随），其余节点用节点名。
func _node_title(n: SkillNodeDef) -> String:
	if n.unlocks_skill and _is_primary_skill_node(n):
		return "职业技 · %s" % _class_skill_name()
	return n.display_name


## 卡片上的一行简介（详细说明与数值走悬停浮窗，窄卡只保留「这节点干什么」）。
func _short_desc(n: SkillNodeDef) -> String:
	if n.unlocks_skill:
		return "点亮解锁「%s」" % _skill_name_for_node(n)
	if n.damage_per_rank > 0.0:
		return "每级 攻击 +%.0f%%" % roundf(n.damage_per_rank * 100.0)
	if n.hp_per_rank > 0.0:
		return "每级 生命 +%.0f%%" % roundf(n.hp_per_rank * 100.0)
	return n.desc


## 节点解锁的技能显示名（主技能走 _class_skill_name；进阶技能在 def.extra_skills 里查）。
func _skill_name_for_node(n: SkillNodeDef) -> String:
	if _is_primary_skill_node(n):
		return _class_skill_name()
	if pawn != null and pawn.def != null:
		for s in pawn.def.all_skills():
			if s != null and s.id == n.unlocks_skill_id:
				return s.display_name
	return n.display_name

## 节点卡四态外观：金框满级 / 彩框+辉光可加点 / 常态 / 暗化未解锁。
func _card_style(n: SkillNodeDef, maxed: bool, locked: bool, can_invest: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	if maxed:
		sb.bg_color = Color(0.21, 0.17, 0.10, 0.97)
		sb.border_color = UIStyle.BORDER_GOLD_BRIGHT
		sb.set_border_width_all(2)
		sb.shadow_color = Color(UIStyle.BORDER_GOLD_BRIGHT, 0.30)
		sb.shadow_size = 10
	elif locked:
		sb.bg_color = Color(0.105, 0.09, 0.075, 0.95)
		sb.border_color = Color(0.32, 0.28, 0.22, 0.8)
		sb.set_border_width_all(1)
	elif can_invest:
		sb.bg_color = Color(0.20, 0.165, 0.12, 0.97)
		sb.border_color = Color(n.color, 0.9)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(n.color, 0.22)
		sb.shadow_size = 8
	else:
		sb.bg_color = UIStyle.BG_PANEL_LIGHT
		sb.border_color = Color(n.color.darkened(0.35), 0.75)
		sb.set_border_width_all(1)
	return sb
