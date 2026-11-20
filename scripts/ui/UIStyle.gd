class_name UIStyle
extends RefCounted
## ============================================================================
## UI 风格中心（v6）：「Kenney CC0 九宫格 + 开源中文字体 + 语义图标」的暗金主题。
##
## 三层结构：
##   一、调色板常量 —— v5 全部常量原样保留（面板直接引用，不得改名）。
##   二、主题装配 build_theme() —— 面板/按钮/进度条/输入框/滚动条/弹出菜单全部覆盖；
##       九宫格贴图来自 res://assets/ui/kenney（asset-scout 产出，CC0 1.0），
##       字体来自 res://assets/ui/fonts（OFL 中文字体）。
##   三、事实工厂 —— 面板一行拿到：图标徽章、胶囊底、标题条、装饰分隔、资源配色。
##
## ★ 缺资源不报错原则（v6 硬约束）★
## 本文件任何地方都**不允许**因为资源缺失而报错、中断或画出空白：
##   · 切片表 slices.json 不存在 / 无法解析 / 缺条目 → 回退 v5 的 StyleBoxFlat；
##   · 单个 PNG 不存在或未导入（ResourceLoader.exists 为假）→ 同样回退 StyleBoxFlat；
##   · 字体 ttf/otf 缺失 → 回退系统字体链（PingFang SC / 雅黑 / Noto）。
## 判定集中在 _slice_info / _slice_texture 两个函数里，其余代码只关心「拿到没有」。
## ============================================================================

# ============================================================================
# 一、调色板
# ============================================================================

# —— v5 保留常量（面板依赖，签名/名字冻结）——
const BG_PANEL := Color(0.13, 0.105, 0.085, 0.94)        # 深胡桃木面板
const BG_PANEL_LIGHT := Color(0.19, 0.155, 0.115, 0.95)  # 卡片 / hover
const BORDER_GOLD := Color(0.62, 0.50, 0.28, 0.9)        # 暗金描边
const BORDER_GOLD_BRIGHT := Color(0.93, 0.78, 0.38, 1.0) # 高亮金
const TEXT_MAIN := Color(0.94, 0.90, 0.82)               # 暖白
const TEXT_DIM := Color(0.72, 0.66, 0.55)                # 暖灰
const GOLD := Color(0.95, 0.80, 0.38)                    # 金
const HP_GREEN := Color(0.36, 0.80, 0.36)
const HP_RED := Color(0.86, 0.28, 0.24)
const XP_BLUE := Color(0.35, 0.62, 0.95)
const DANGER := Color(1.0, 0.42, 0.36)

# —— v6 新增配色（供面板引用）——
const BG_SLOT := Color(0.075, 0.062, 0.05, 0.92)         # 内凹槽：进度条底 / 列表底 / 输入框
const BORDER_GOLD_DIM := Color(0.40, 0.33, 0.20, 0.85)   # 弱化描边（胶囊 / 分隔）
const TEXT_ON_GOLD := Color(0.12, 0.09, 0.06)            # 金色底上的深字
const SCROLL_BG := Color(0.09, 0.075, 0.062, 0.85)
const SCROLL_GRAB := Color(0.40, 0.33, 0.21, 0.95)
const SCROLL_GRAB_HI := Color(0.62, 0.50, 0.28, 1.0)

## 资源配色（顶栏观感：木棕 / 石灰 / 食绿 / 金）。
## 注意：图标 PNG 是**纯白前景**，最终颜色 = 这里的值（靠 modulate 上色），
## 所以取值全部保留了 0.5 以上的亮度，保证在深胡桃木底上可读；
## 比 GameDefs 的 Color.SADDLE_BROWN / Color.DIM_GRAY 更亮一档，是刻意的。
## 同时给 res_ 前缀别名，避免调用方写错键名。
const RES_COLORS := {
	&"wood": Color(0.76, 0.53, 0.30),
	&"stone": Color(0.72, 0.75, 0.80),
	&"food": Color(0.58, 0.82, 0.40),
	&"gold": Color(0.98, 0.82, 0.38),
	&"res_wood": Color(0.76, 0.53, 0.30),
	&"res_stone": Color(0.72, 0.75, 0.80),
	&"res_food": Color(0.58, 0.82, 0.40),
	&"res_gold": Color(0.98, 0.82, 0.38),
}

## 单位配色：村民 / 士兵 / 主角 / 野怪 / 头目。
## 键名别名（villager/enemy/elite… 以及顶栏 stat_* 图标 id）一并登记，
## 面板无论用哪种写法都能取到颜色，不会因为键名拼法不同而崩。
const UNIT_COLORS := {
	&"colonist": Color(0.58, 0.80, 0.94),   # 村民（蓝灰）
	&"villager": Color(0.58, 0.80, 0.94),
	&"peasant": Color(0.58, 0.80, 0.94),
	&"stat_pop": Color(0.58, 0.80, 0.94),
	&"soldier": Color(0.88, 0.63, 0.42),    # 士兵（陶土橙）
	&"melee": Color(0.88, 0.63, 0.42),
	&"ranged": Color(0.80, 0.72, 0.45),
	&"stat_soldier": Color(0.88, 0.63, 0.42),
	&"hero": Color(1.0, 0.84, 0.36),        # 主角（金）
	&"stat_hero": Color(1.0, 0.84, 0.36),
	&"raider": Color(0.90, 0.44, 0.38),     # 野怪（血红）
	&"enemy": Color(0.90, 0.44, 0.38),
	&"stat_enemy": Color(0.90, 0.44, 0.38),
	&"elite": Color(0.95, 0.55, 0.32),
	&"boss": Color(0.98, 0.38, 0.62),       # 头目（紫红）
}

# ============================================================================
# 二、资源目录与九宫格表
# ============================================================================

const SLICE_DIR := "res://assets/ui/kenney/"
const SLICE_JSON := SLICE_DIR + "slices.json"
const FONT_DIR := "res://assets/ui/fonts/"
const FONT_BODY_FILES: Array[String] = ["ui_cjk.ttf", "ui_cjk.otf"]
const FONT_DISPLAY_FILES: Array[String] = ["ui_cjk_bold.ttf", "ui_cjk_bold.otf"]

## bar_track 之类「凹槽底」贴图的最低平均不透明度。
## Kenney 的 barBack 系列原图只有 10% 黑（alpha≈26/255），是刻意的浅槽，
## 直接当进度条槽底会「悬空」——低于此阈值就改用 panel_inset 当槽底。
const SLICE_OPAQUE_MIN := 0.25

## 按钮最小高度提示（asset-scout 实测：hover 切片 margin 12px，需要 ≥25px 才不变形）。
const BUTTON_MIN_HEIGHT := 30

# —— 九宫格调制色（源图是纯白遮罩或中性灰，颜色一律运行时给）——
# 按钮源图实体像素 ≈ (0.86,0.86,0.91)，故 modulate 后实际色 ≈ tint × 0.86。
const TINT_BTN_NORMAL := Color(0.27, 0.22, 0.16)
const TINT_BTN_HOVER := Color(0.50, 0.40, 0.22)
const TINT_BTN_PRESSED := Color(0.20, 0.165, 0.125)
const TINT_BTN_DISABLED := Color(0.30, 0.29, 0.28)
const TINT_CHIP := Color(0.22, 0.18, 0.14)
const TINT_PANEL_ORNATE := Color(0.235, 0.19, 0.13, 0.97)
const TINT_FRAME_GOLD := Color(0.78, 0.62, 0.30, 1.0)
const TINT_DIVIDER := Color(0.72, 0.58, 0.30, 1.0)

# —— 静态缓存（贴图 / 字体只加载一次）——
static var _slices: Dictionary = {}
static var _slices_loaded: bool = false
static var _tex_cache: Dictionary = {}
static var _tex_missing: Dictionary = {}
static var _opacity_cache: Dictionary = {}
static var _font_body: Font = null
static var _font_display: Font = null
static var _font_source: String = ""
static var _display_font_source: String = ""
static var _font_fallback: Font = null
static var _font_fallback_checked: bool = false
static var _res_names: Dictionary = {}


# ============================================================================
# 三、主题装配
# ============================================================================

## 构建整套 HUD Theme（HUD 根部挂一次，向下传播）。
## 贴图缺失时每个槽位都自动落回 v5 的 StyleBoxFlat 外观，UI 不会变空/报错。
static func build_theme() -> Theme:
	var theme := Theme.new()
	var body_font := make_font()
	theme.default_font = body_font
	theme.default_font_size = 15
	_apply_type_fonts(theme, body_font)

	# ---- 面板：深胡桃木九宫格（缺图 → v5 圆角 StyleBoxFlat）----
	theme.set_stylebox("panel", "PanelContainer", panel_style(&"dark"))
	theme.set_stylebox("panel", "Panel", panel_style(&"dark"))
	theme.set_stylebox("panel", "PopupPanel", panel_style(&"dark"))
	theme.set_stylebox("panel", "TooltipPanel", panel_style(&"tooltip"))
	theme.set_color("font_color", "TooltipLabel", TEXT_MAIN)

	# ---- Button：四态 + 聚焦环 ----
	theme.set_stylebox("normal", "Button", button_style(&"normal"))
	theme.set_stylebox("hover", "Button", button_style(&"hover"))
	theme.set_stylebox("pressed", "Button", button_style(&"pressed"))
	theme.set_stylebox("disabled", "Button", button_style(&"disabled"))
	theme.set_stylebox("focus", "Button", _focus_style())
	theme.set_color("font_color", "Button", TEXT_MAIN)
	theme.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.42))
	theme.set_color("font_hover_color", "Button", BORDER_GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_focus_color", "Button", TEXT_MAIN)
	theme.set_constant("h_separation", "Button", 4)

	# ---- Label ----
	theme.set_color("font_color", "Label", TEXT_MAIN)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("font_color", "RichTextLabel", TEXT_MAIN)
	theme.set_color("default_color", "RichTextLabel", TEXT_MAIN)

	# ---- ProgressBar：内凹槽 + 贴图填充 ----
	theme.set_stylebox("background", "ProgressBar", bar_background_style())
	theme.set_stylebox("fill", "ProgressBar", bar_style(&"gold"))
	theme.set_color("font_color", "ProgressBar", TEXT_MAIN)

	# ---- HSeparator / VSeparator ----
	theme.set_stylebox("separator", "HSeparator", separator_style())
	theme.set_stylebox("separator", "VSeparator", separator_style())

	# ---- LineEdit（将来改名 / 存档备注等输入）----
	var le_normal := panel_style(&"inset")
	le_normal.content_margin_left = 8.0
	le_normal.content_margin_right = 8.0
	le_normal.content_margin_top = 5.0
	le_normal.content_margin_bottom = 5.0
	theme.set_stylebox("normal", "LineEdit", le_normal)
	var le_focus := panel_style(&"inset")
	le_focus.content_margin_left = 8.0
	le_focus.content_margin_right = 8.0
	le_focus.content_margin_top = 5.0
	le_focus.content_margin_bottom = 5.0
	if le_focus is StyleBoxFlat:
		(le_focus as StyleBoxFlat).border_color = BORDER_GOLD_BRIGHT
		(le_focus as StyleBoxFlat).set_border_width_all(2)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	var le_readonly := panel_style(&"inset")
	theme.set_stylebox("read_only", "LineEdit", le_readonly)
	theme.set_color("font_color", "LineEdit", TEXT_MAIN)
	theme.set_color("font_placeholder_color", "LineEdit", Color(TEXT_DIM, 0.6))
	theme.set_color("font_selected_color", "LineEdit", TEXT_ON_GOLD)
	theme.set_color("selection_color", "LineEdit", Color(BORDER_GOLD, 0.55))
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	theme.set_color("clear_button_color_pressed", "LineEdit", GOLD)

	# ---- CheckBox / CheckButton：沿用 Button 底盘，只补字色 ----
	theme.set_color("font_color", "CheckBox", TEXT_MAIN)
	theme.set_color("font_hover_color", "CheckBox", BORDER_GOLD_BRIGHT)
	theme.set_color("font_pressed_color", "CheckBox", GOLD)
	theme.set_color("font_disabled_color", "CheckBox", Color(0.55, 0.5, 0.42))
	theme.set_stylebox("normal", "CheckButton", button_style(&"normal"))
	theme.set_stylebox("hover", "CheckButton", button_style(&"hover"))
	theme.set_stylebox("pressed", "CheckButton", button_style(&"pressed"))
	theme.set_stylebox("disabled", "CheckButton", button_style(&"disabled"))
	theme.set_color("font_color", "CheckButton", TEXT_MAIN)

	# ---- 滚动条：细条纯色（细条上贴九宫格会失真，故走 StyleBoxFlat）----
	_apply_scrollbars(theme)

	# ---- PopupMenu：面板 + hover 胶囊 + 分隔线 ----
	theme.set_stylebox("panel", "PopupMenu", panel_style(&"dark"))
	theme.set_stylebox("hover", "PopupMenu", hover_style())
	theme.set_stylebox("separator", "PopupMenu", separator_style())
	theme.set_color("font_color", "PopupMenu", TEXT_MAIN)
	theme.set_color("font_hover_color", "PopupMenu", BORDER_GOLD_BRIGHT)
	theme.set_color("font_disabled_color", "PopupMenu", Color(0.55, 0.5, 0.42))
	theme.set_color("font_separator_color", "PopupMenu", TEXT_DIM)
	theme.set_color("font_accelerator_color", "PopupMenu", TEXT_DIM)
	theme.set_constant("v_separation", "PopupMenu", 4)
	theme.set_constant("item_start_padding", "PopupMenu", 6)
	theme.set_constant("item_end_padding", "PopupMenu", 6)

	# ---- ItemList ----
	theme.set_stylebox("panel", "ItemList", panel_style(&"inset"))
	theme.set_stylebox("focus", "ItemList", _focus_flat())
	theme.set_stylebox("selected", "ItemList", hover_style())
	theme.set_stylebox("selected_focus", "ItemList", hover_style())
	theme.set_stylebox("cursor", "ItemList", _cursor_style(true))
	theme.set_stylebox("cursor_unselected", "ItemList", _cursor_style(false))
	theme.set_color("font_color", "ItemList", TEXT_MAIN)
	theme.set_color("font_selected_color", "ItemList", BORDER_GOLD_BRIGHT)
	theme.set_color("guide_color", "ItemList", Color(BORDER_GOLD_DIM, 0.4))
	theme.set_constant("v_separation", "ItemList", 2)
	theme.set_constant("h_separation", "ItemList", 4)

	# ---- Tree（将来的科技树 / 建筑管理）----
	theme.set_stylebox("panel", "Tree", panel_style(&"inset"))
	theme.set_stylebox("focus", "Tree", _focus_flat())
	theme.set_stylebox("selected", "Tree", hover_style())
	theme.set_stylebox("selected_focus", "Tree", hover_style())
	theme.set_stylebox("cursor", "Tree", _cursor_style(true))
	theme.set_stylebox("cursor_unselected", "Tree", _cursor_style(false))
	theme.set_stylebox("custom_button", "Tree", button_style(&"normal"))
	theme.set_stylebox("custom_button_pressed", "Tree", button_style(&"pressed"))
	theme.set_stylebox("custom_button_hover", "Tree", button_style(&"hover"))
	theme.set_stylebox("title_button_normal", "Tree", panel_style(&"dark"))
	theme.set_stylebox("title_button_hover", "Tree", hover_style())
	theme.set_stylebox("title_button_pressed", "Tree", panel_style(&"inset"))
	theme.set_color("font_color", "Tree", TEXT_MAIN)
	theme.set_color("font_selected_color", "Tree", BORDER_GOLD_BRIGHT)
	theme.set_color("guide_color", "Tree", Color(BORDER_GOLD_DIM, 0.3))
	theme.set_color("relationship_line_color", "Tree", Color(BORDER_GOLD_DIM, 0.5))
	theme.set_color("parent_hl_line_color", "Tree", BORDER_GOLD)
	theme.set_color("children_hl_line_color", "Tree", BORDER_GOLD_DIM)
	theme.set_color("title_button_color", "Tree", TEXT_MAIN)
	theme.set_constant("draw_relationship_lines", "Tree", 1)
	theme.set_constant("v_separation", "Tree", 4)
	theme.set_constant("item_margin", "Tree", 10)

	return theme


## 给常见控件显式挂上主题字体（不依赖 default_font 的隐式传播，
## 保证 FontFile 中文字体真的落到每个控件上）。
static func _apply_type_fonts(theme: Theme, font: Font) -> void:
	# 全部用正文字体：标题字体（更粗）只由 section_title / 面板显式取用，
	# 不让它顺着 theme 传播，避免正文/提示文案被无意加粗。
	for type_name in ["Label", "Button", "CheckBox", "CheckButton", "LineEdit", "ProgressBar",
			"PopupMenu", "ItemList", "Tree", "TooltipLabel", "RichTextLabel", "OptionButton"]:
		theme.set_font("font", type_name, font)


static func _apply_scrollbars(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = SCROLL_BG
	track.set_corner_radius_all(4)
	track.content_margin_left = 0.0
	track.content_margin_right = 0.0
	var grab := StyleBoxFlat.new()
	grab.bg_color = SCROLL_GRAB
	grab.set_corner_radius_all(4)
	grab.set_border_width_all(1)
	grab.border_color = BORDER_GOLD_DIM
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = SCROLL_GRAB_HI
	grab_hi.border_color = BORDER_GOLD_BRIGHT
	var grab_pr := grab.duplicate() as StyleBoxFlat
	grab_pr.bg_color = GOLD
	grab_pr.border_color = BORDER_GOLD_BRIGHT
	var track_focus := track.duplicate() as StyleBoxFlat
	track_focus.border_color = BORDER_GOLD
	track_focus.set_border_width_all(1)
	for type_name in ["ScrollBar", "VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, track)
		theme.set_stylebox("scroll_focus", type_name, track_focus)
		theme.set_stylebox("grabber", type_name, grab)
		theme.set_stylebox("grabber_highlight", type_name, grab_hi)
		theme.set_stylebox("grabber_pressed", type_name, grab_pr)


# ============================================================================
# 四、字体链
# ============================================================================

## 正文/默认字体：优先项目自带的 OFL 中文字体（FontFile），缺失回退引擎内置字体。
## 返回 Font（SystemFont 与 FontFile 的共同基类）——面板请用 `Font` 声明接收变量。
##
## v47 性能修复：旧实现把 SystemFont 链挂成 fallback。部分 macOS / 无桌面环境里
## SystemFont 解析失败（ascent=0），此后每次文本度量都会调用 FreeType 加载空字体，
## 逐帧刷屏并白白吃掉 CPU（实测主线程 process_time 近 30ms）。现在优先使用引擎
## 内嵌 fallback；只有它也不可用时才退回 SystemFont。
static func make_font() -> Font:
	if _font_body != null:
		return _font_body
	for file_name in FONT_BODY_FILES:
		var ff := _load_font_file(FONT_DIR + file_name)
		if ff != null:
			ff.fallbacks = _fallback_list()
			_font_body = ff
			_font_source = FONT_DIR + file_name
			return _font_body
	_font_body = _fallback_font()
	if _font_body == null:
		_font_body = _system_chain()
	_font_source = "引擎内置字体" if _font_body == _font_fallback else "系统字体链"
	return _font_body


## 标题字体：优先同族粗体文件；缺失时用「正文 + 加粗」或加粗系统字体。
## 用途：面板标题、模态卡头、结算横幅。
static func make_display_font() -> Font:
	if _font_display != null:
		return _font_display
	for file_name in FONT_DISPLAY_FILES:
		var ff := _load_font_file(FONT_DIR + file_name)
		if ff != null:
			ff.fallbacks = _fallback_list()
			_font_display = ff
			_display_font_source = FONT_DIR + file_name
			return _font_display
	var body := make_font()
	if body is FontFile:
		# 只有常规字重时，用 FontVariation 让笔画变粗一点，避免标题发虚
		var fv := FontVariation.new()
		fv.base_font = body
		fv.variation_embolden = 0.35
		_font_display = fv
		_display_font_source = "正文 + embolden"
		return _font_display
	_font_display = _fallback_font()
	if _font_display == null:
		_font_display = _system_chain(true)
	_display_font_source = "引擎内置字体"
	return _font_display


## 显式请求系统字体链（macOS 苹方 / Windows 雅黑 / Linux Noto）。
## v47：优先返回引擎内置字体——它在所有运行环境都可用；SystemFont 仅作最后兜底。
static func make_system_font(heavy: bool = false) -> Font:
	var fallback := _fallback_font()
	if fallback != null:
		return fallback
	return _system_chain(heavy)


## 引擎内置默认字体（与系统字体无关，一定有有效度量）。
static func _fallback_font() -> Font:
	if not _font_fallback_checked:
		_font_fallback_checked = true
		var fallback := ThemeDB.fallback_font
		if fallback != null and fallback.get_ascent(16) > 0.0:
			_font_fallback = fallback
	return _font_fallback


## fallback 数组；没有可用 fallback 时返回空数组（不挂坏掉的 SystemFont）。
static func _fallback_list() -> Array[Font]:
	var fallback := _fallback_font()
	if fallback == null:
		return []
	return [fallback]


static func _system_chain(heavy: bool = false) -> SystemFont:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	if heavy:
		sf.font_weight = 700
	return sf


## 加载字体文件；不存在 / 未导入 / 类型不对都返回 null（不报错）。
static func _load_font_file(path: String) -> FontFile:
	if not ResourceLoader.exists(path, "Font"):
		return null
	var res: Resource = ResourceLoader.load(path, "Font", ResourceLoader.CACHE_MODE_REUSE)
	if res is FontFile:
		return res
	return null


## 当前字体来源（诊断用）。
static func font_source() -> String:
	if _font_source == "":
		make_font()
	return _font_source


# ============================================================================
# 五、样式工厂（面板可直接调用）
# ============================================================================

## 面板底：dark（主面板）/ light（悬浮卡）/ inset（凹槽）/ tooltip / ornate（雕花卡）/ frame（中空金框）。
## 未接到的贴图会自动落回等价 StyleBoxFlat。
static func panel_style(kind: StringName = &"dark") -> StyleBox:
	match kind:
		&"light":
			var sb_light := _slice_box(&"panel_dark", BG_PANEL_LIGHT, Vector4(10, 8, 10, 8))
			return sb_light if sb_light != null else _flat(BG_PANEL_LIGHT, BORDER_GOLD, 1, 6, 10, 8)
		&"inset":
			var sb_inset := _slice_box(&"panel_inset", BG_SLOT, Vector4(8, 6, 8, 6))
			return sb_inset if sb_inset != null else _flat(BG_SLOT, BORDER_GOLD_DIM, 1, 4, 8, 6)
		&"tooltip":
			var sb_tip := _slice_box(&"panel_inset", Color(0.08, 0.07, 0.055, 0.97), Vector4(9, 7, 9, 7))
			return sb_tip if sb_tip != null else _flat(Color(0.08, 0.07, 0.055, 0.97), BORDER_GOLD, 1, 4, 9, 7)
		&"ornate":
			var sb_orn := _slice_box(&"frame_ornate", TINT_PANEL_ORNATE, Vector4(16, 14, 16, 14))
			return sb_orn if sb_orn != null else _flat(Color(0.155, 0.125, 0.095, 0.97), BORDER_GOLD_BRIGHT, 2, 8, 16, 14)
		&"frame":
			# 中空金框：叠在内容之上做「模态描边」，中心不绘制
			var sb_frame := _slice_box(&"frame_ornate_hollow", TINT_FRAME_GOLD, Vector4(16, 14, 16, 14), false)
			if sb_frame != null:
				return sb_frame
			var flat_frame := StyleBoxFlat.new()
			flat_frame.bg_color = Color(0, 0, 0, 0)
			flat_frame.draw_center = false
			flat_frame.border_color = BORDER_GOLD_BRIGHT
			flat_frame.set_border_width_all(2)
			flat_frame.set_corner_radius_all(8)
			flat_frame.set_content_margin_all(14)
			return flat_frame
		_:
			var sb_dark := _slice_box(&"panel_dark", BG_PANEL, Vector4(11, 9, 11, 9))
			return sb_dark if sb_dark != null else _flat(BG_PANEL, BORDER_GOLD, 1, 6, 11, 9)


## 按钮四态（normal / hover / pressed / disabled）。
static func button_style(state: StringName = &"normal") -> StyleBox:
	var slice := &"button_normal"
	var tint := TINT_BTN_NORMAL
	match state:
		&"hover":
			slice = &"button_hover"
			tint = TINT_BTN_HOVER
		&"pressed":
			slice = &"button_pressed"
			tint = TINT_BTN_PRESSED
		&"disabled":
			slice = &"button_disabled"
			tint = TINT_BTN_DISABLED
	# 四态共用同一套内容边距（12/7），否则 hover 时文字会位移 3px
	var content := Vector4(12, 7, 12, 7)
	var sb := _slice_box(slice, tint, content)
	if sb != null:
		return sb
	match state:
		&"hover":
			return _flat(Color(0.28, 0.225, 0.15, 0.98), BORDER_GOLD_BRIGHT, 1, 5, 12, 7)
		&"pressed":
			return _flat(Color(0.15, 0.12, 0.09, 0.98), GOLD, 1, 5, 12, 7)
		&"disabled":
			return _flat(Color(0.16, 0.15, 0.13, 0.7), Color(0.3, 0.28, 0.24, 0.5), 1, 5, 12, 7)
	return _flat(Color(0.20, 0.165, 0.12, 0.95), Color(0.45, 0.37, 0.22, 0.9), 1, 5, 12, 7)


## 顶栏资源胶囊 / 快捷键标签底。
static func chip_style() -> StyleBox:
	var sb := _slice_box(&"chip_bg", TINT_CHIP, Vector4(10, 4, 10, 4))
	return sb if sb != null else _flat(BG_PANEL_LIGHT, BORDER_GOLD_DIM, 1, 12, 10, 4)


## 列表 / 菜单 hover 行底（比 chip 更亮一点）。
static func hover_style() -> StyleBox:
	var sb := _slice_box(&"chip_bg", Color(0.42, 0.34, 0.20), Vector4(8, 3, 8, 3))
	return sb if sb != null else _flat(Color(0.28, 0.225, 0.15, 0.9), BORDER_GOLD, 1, 4, 8, 3)


## 进度条填充：gold（金币/通用）、hp、hp_low、xp；track = 底槽（与主题同一条决策链）。
static func bar_style(kind: StringName = &"gold") -> StyleBox:
	var slice := &"bar_fill"
	var tint := Color(1, 1, 1)          # 源图本身就是 Kenney 的暖金
	match kind:
		&"track":
			return bar_background_style()
		&"hp":
			slice = &"bar_fill_cool"
			tint = Color(0.35, 1.0, 0.45)   # 冷色源 → 青绿
		&"hp_low":
			slice = &"bar_fill"
			tint = Color(1.0, 0.32, 0.26)   # 暖金源 → 橙红
		&"xp":
			slice = &"bar_fill_cool"
			tint = Color(0.55, 0.82, 1.0)   # 蓝
	var sb := _slice_box(slice, tint, Vector4(1, 0, 1, 0))
	if sb != null:
		return sb
	match kind:
		&"hp":
			return _flat(HP_GREEN, HP_GREEN, 0, 3, 1, 0)
		&"hp_low":
			return _flat(HP_RED, HP_RED, 0, 3, 1, 0)
		&"xp":
			return _flat(XP_BLUE, XP_BLUE, 0, 3, 1, 0)
	var flat_gold := _flat(GOLD, GOLD, 0, 3, 1, 0)
	return flat_gold


## 进度条底槽。
## 决策链（实测驱动，v6 定稿）：
##   1) Kenney `bar_track` 只有 alpha≈0.102 的「浅凹槽」——低于 SLICE_OPAQUE_MIN(0.25)，
##      当槽底会像悬空，故只在足够不透明时才采用（自检，不写死）。
##   2) 回退**不用 panel_inset**：它 48×48 的 8px 纹理 margin 会让 StyleBox 最小高度变成 16px，
##      而 HUD 现有进度条是 9~14px（英雄 XP 9 / 任务 10 / 头目 13 / 顶栏 14），
##      强行拉高会顶动各面板既有的固定布局。因此回退到**几何与 v5 完全一致的纯色凹槽**
##      （无最小高度、1px 暗金边、内边距 2），保证主题换肤不改变 HUD 尺寸。
## 需要「大进度条上叠一层浅凹槽」的场合，用 bar_style(&"track")。
static func bar_background_style() -> StyleBox:
	if _slice_opacity(&"bar_track") >= SLICE_OPAQUE_MIN:
		var sb := _slice_box(&"bar_track", Color(0.5, 0.45, 0.38, 1.0), Vector4(2, 0, 2, 0))
		if sb != null:
			return sb
	return _flat(Color(0.09, 0.08, 0.06, 0.9), Color(0.35, 0.30, 0.18, 0.8), 1, 4, 2, 2)


## 分隔线（分隔条 / 中缝）：可被 HSeparator / VSeparator 直接用。
static func separator_style() -> StyleBox:
	var line := StyleBoxLine.new()
	line.color = Color(0.5, 0.42, 0.25, 0.55)
	line.grow_begin = -2
	line.grow_end = -2
	return line


static func _focus_style() -> StyleBox:
	# 聚焦环刻意用纯色描边而不是九宫格：按钮高度只有 30~36px，
	# frame_ornate_hollow 的 16px 角饰在这个尺寸下会互相重叠变形。
	# 需要「雕花金框」的大卡片请用 panel_style(&"frame")。
	# 内容边距必须与 button_style 四态一致（12/7），否则按下 Tab 聚焦时文字会跳。
	return _focus_flat(12.0, 7.0, 5)


static func _focus_flat(pad_h: float = 0.0, pad_v: float = 0.0, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	sb.border_color = BORDER_GOLD_BRIGHT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


static func _cursor_style(filled: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(BORDER_GOLD, 0.28 if filled else 0.12)
	sb.set_corner_radius_all(3)
	return sb


# ============================================================================
# 六、事实工厂（给面板一行调用）
# ============================================================================

## 圆形图标徽章（深色圆底 + accent 描边 + 真实图标）；缺图自动回退字徽。
static func icon_badge(id: StringName, px: int, tint: Color, fallback_char: String = "") -> Control:
	return IconBadge.new(id, px, tint, fallback_char)


## 纯图标（无圆底），用于顶栏 / 列表行内嵌图标。
static func icon(id: StringName, px: int, tint: Color, fallback_char: String = "") -> Control:
	return IconRect.new(id, px, tint, fallback_char)


## 带图标位 + 装饰分隔的标题条（面板复用）。
## icon_id 传空则不出图标；返回的容器 mouse_filter=IGNORE，不会挡面板操作。
static func section_title(text: String, icon_id: StringName = &"", icon_px: int = 16) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_id != &"":
		var badge := icon_badge(icon_id, icon_px, BORDER_GOLD_BRIGHT, "")
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	var title := Label.new()
	title.text = text
	title.add_theme_font_override("font", make_display_font())
	title.add_theme_color_override("font_color", BORDER_GOLD_BRIGHT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	var tail := HSeparator.new()
	tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tail)
	box.add_child(row)
	box.add_child(ornament_divider())
	return box


## 横向装饰分隔（Kenney 双线花饰；缺图回退程序化细线 + 中心菱形）。
static func ornament_divider() -> Control:
	var info := _slice_info(&"divider_h")
	var tex := _slice_texture(&"divider_h", info)
	if tex != null:
		var np := NinePatchRect.new()
		np.texture = tex
		np.patch_margin_left = int(_margin(info, "l"))
		np.patch_margin_right = int(_margin(info, "r"))
		np.patch_margin_top = int(_margin(info, "t"))
		np.patch_margin_bottom = int(_margin(info, "b"))
		np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		np.modulate = TINT_DIVIDER
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		np.custom_minimum_size = Vector2(0.0, float(maxi(8, tex.get_height())))
		np.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return np
	var fallback := OrnamentLine.new()
	fallback.custom_minimum_size = Vector2(0.0, 8.0)
	fallback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return fallback


## 资源配色：wood / stone / food / gold（接受 String 或 StringName，也接受 res_ 前缀）。
static func resource_color(res_id) -> Color:
	var key := StringName(res_id)
	if RES_COLORS.has(key):
		return RES_COLORS[key]
	var stripped := StringName(String(key).trim_prefix("res_"))
	if RES_COLORS.has(stripped):
		return RES_COLORS[stripped]
	return GOLD


## 资源显示名：转发 GameDefs.resource_defs()，不重复实现（面板已有逻辑时只做转发）。
static func resource_name(res_id) -> String:
	if _res_names.is_empty():
		for rd in GameDefs.resource_defs():
			_res_names[rd.id] = String(rd.display_name)
	var key := StringName(res_id)
	if _res_names.has(key):
		return _res_names[key]
	var stripped := StringName(String(key).trim_prefix("res_"))
	if _res_names.has(stripped):
		return _res_names[stripped]
	return String(key)


## 单位配色：colonist / soldier / hero / raider / boss（含 villager / enemy / elite / stat_* 别名）。
static func unit_color(unit_id) -> Color:
	var key := StringName(unit_id)
	if UNIT_COLORS.has(key):
		return UNIT_COLORS[key]
	return TEXT_MAIN


# ============================================================================
# 七、v5 保留方法（签名冻结）
# ============================================================================

## 血条填充色：>50% 绿 → >25% 黄 → 红。
static func hp_fill_color(ratio: float) -> Color:
	if ratio > 0.5:
		return HP_GREEN
	if ratio > 0.25:
		return Color(0.95, 0.75, 0.25)
	return HP_RED


## 建筑图标徽字色：按建筑类型给一个固定的主题色。
static func building_accent(id: StringName) -> Color:
	match id:
		&"wall": return Color(0.62, 0.55, 0.45)
		&"house": return Color(0.85, 0.55, 0.45)
		&"dirt_road": return Color(0.78, 0.64, 0.40)
		&"tavern": return Color(0.9, 0.62, 0.3)
		&"dragon_garden": return Color(0.82, 0.45, 0.95)   # 龙园：暗紫（龙焰魔法感）
	return GOLD


# ============================================================================
# 八、九宫格底层：切片表读取 / 贴图加载 / 缓存（全部「缺即 null，不报错」）
# ============================================================================

## 读 slices.json（只读一次）。容错三种顶层形态：
##   {id: {...}} / {"slices": {...}} / [{file: "...", ...}, ...]
## 下划线开头的键（_meta / _omitted）一律跳过（asset-scout 约定的元数据）。
static func _load_slices() -> void:
	if _slices_loaded:
		return
	_slices_loaded = true
	if not FileAccess.file_exists(SLICE_JSON):
		return
	var file := FileAccess.open(SLICE_JSON, FileAccess.READ)
	if file == null:
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null:
		return
	var table: Dictionary = {}
	if parsed is Array:
		for entry in (parsed as Array):
			if entry is Dictionary:
				var d := entry as Dictionary
				var id := StringName(d.get("id", _id_from_file(String(d.get("file", "")))))
				if id != &"":
					table[id] = d
	elif parsed is Dictionary:
		var root := parsed as Dictionary
		var source: Dictionary = root
		if root.has("slices") and root["slices"] is Dictionary:
			source = root["slices"] as Dictionary
		for raw_key in source.keys():
			var key := String(raw_key)
			if key.begins_with("_"):
				continue
			var value: Variant = source[raw_key]
			if value is Dictionary:
				table[StringName(key)] = value
	_slices = table


## 取切片元数据；不存在返回空字典。
static func _slice_info(id: StringName) -> Dictionary:
	_load_slices()
	if _slices.has(id):
		var info: Variant = _slices[id]
		if info is Dictionary:
			return info as Dictionary
	return {}


## 取切片贴图；文件缺失 / 未导入 / 类型不对都返回 null（带负缓存，不重复 IO、不报错）。
static func _slice_texture(id: StringName, info: Dictionary = {}) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	if _tex_missing.has(id):
		return null
	var resolved := info
	if resolved.is_empty():
		resolved = _slice_info(id)
	var file_name := String(resolved.get("file", String(id) + ".png"))
	if file_name == "":
		_tex_missing[id] = true
		return null
	var path := file_name if file_name.begins_with("res://") else SLICE_DIR + file_name
	if not ResourceLoader.exists(path, "Texture2D"):
		_tex_missing[id] = true
		return null
	var res: Resource = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		_tex_cache[id] = res
		return res
	_tex_missing[id] = true
	return null


## 切片贴图的平均不透明度（用于「源图是不是只是浅槽」这类自检）。
## 贴图不可读（VRAM 压缩等）时返回 1.0，即不做额外限制。
static func _slice_opacity(id: StringName) -> float:
	if _opacity_cache.has(id):
		return _opacity_cache[id]
	var tex := _slice_texture(id)
	if tex == null:
		return 1.0
	var img := tex.get_image()
	if img == null:
		_opacity_cache[id] = 1.0
		return 1.0
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		_opacity_cache[id] = 1.0
		return 1.0
	var total := 0.0
	var samples := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			total += img.get_pixel(x, y).a
			samples += 1
	var value := 1.0 if samples == 0 else total / float(samples)
	_opacity_cache[id] = value
	return value


## 组装九宫格 StyleBoxTexture；任一步缺失返回 null（调用方回退 StyleBoxFlat）。
## content 为 Vector4(左, 上, 右, 下)，任一分量 < 0 表示「沿用贴图 margin」。
static func _slice_box(id: StringName, tint: Color, content: Vector4 = Vector4(-1, -1, -1, -1),
		draw_center: bool = true) -> StyleBoxTexture:
	var info := _slice_info(id)
	var tex := _slice_texture(id, info)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	var axis := String(info.get("axis", "9slice"))
	var ml := _margin(info, "l")
	var mt := _margin(info, "t")
	var mr := _margin(info, "r")
	var mb := _margin(info, "b")
	# 3slice_h / 3slice_v：纵向（横向）不切，margin 必须为 0，否则中间渐变被拉断
	if axis == "3slice_h":
		mt = 0.0
		mb = 0.0
	elif axis == "3slice_v":
		ml = 0.0
		mr = 0.0
	sb.texture_margin_left = ml
	sb.texture_margin_top = mt
	sb.texture_margin_right = mr
	sb.texture_margin_bottom = mb
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.draw_center = draw_center
	sb.modulate_color = tint
	if content.x >= 0.0:
		sb.content_margin_left = content.x
	if content.y >= 0.0:
		sb.content_margin_top = content.y
	if content.z >= 0.0:
		sb.content_margin_right = content.z
	if content.w >= 0.0:
		sb.content_margin_bottom = content.w
	return sb


## 某切片是否真的接到了贴图（诊断 / 回归断言用）。
static func slice_available(id: StringName) -> bool:
	return _slice_texture(id) != null


## 交付诊断报告：哪些切片接到了、哪些回退了、字体来源。
## 供回归脚本 / 交付记录打印，不含任何副作用。
static func theme_asset_report() -> Dictionary:
	var textured: Array[String] = []
	var fallback: Array[String] = []
	for raw_id in ["panel_dark", "panel_inset", "frame_ornate", "frame_ornate_hollow",
			"button_normal", "button_hover", "button_pressed", "button_disabled",
			"chip_bg", "bar_track", "bar_fill", "bar_fill_cool", "divider_h"]:
		var id := StringName(raw_id)
		if _slice_texture(id) != null:
			textured.append(raw_id)
		else:
			fallback.append(raw_id)
	var body := make_font()
	var display := make_display_font()
	return {
		"slice_json_exists": FileAccess.file_exists(SLICE_JSON),
		"slice_count": _slices.size() if _slices_loaded else 0,
		"textured": textured,
		"fallback_flat": fallback,
		"bar_track_opacity": _slice_opacity(&"bar_track"),
		"bar_track_used": _slice_texture(&"bar_track") != null
				and _slice_opacity(&"bar_track") >= SLICE_OPAQUE_MIN,
		"font_source": font_source(),
		"font_class": body.get_class() if body != null else "无",
		"display_font_source": _display_font_source,
		"display_font_class": display.get_class() if display != null else "无",
	}


static func _margin(info: Dictionary, side: String) -> float:
	return float(info.get("margin_" + side, 0))


static func _id_from_file(file_name: String) -> String:
	return file_name.get_file().get_basename()


## 纯色 StyleBoxFlat 回退构造（v5 外观，参数顺序：底 / 边 / 边宽 / 圆角 / 内边距）。
static func _flat(bg: Color, border: Color, border_w: int, radius: int,
		pad_h: float = 10.0, pad_v: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


## 缺图时的程序化分隔装饰：一条暗金细线 + 中心菱形。
class OrnamentLine extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 4.0 or h <= 2.0:
			return
		var mid := h * 0.5
		var half := w * 0.5
		draw_line(Vector2(0.0, mid), Vector2(half - 7.0, mid), UIStyle.BORDER_GOLD_DIM, 1.0, true)
		draw_line(Vector2(half + 7.0, mid), Vector2(w, mid), UIStyle.BORDER_GOLD_DIM, 1.0, true)
		var d := Vector2(half, mid)
		var r := maxf(2.5, minf(4.0, h * 0.45))
		draw_colored_polygon(PackedVector2Array([
			d + Vector2(0.0, -r), d + Vector2(r, 0.0), d + Vector2(0.0, r), d + Vector2(-r, 0.0)]),
			UIStyle.BORDER_GOLD)
		draw_polyline(PackedVector2Array([
			d + Vector2(0.0, -r), d + Vector2(r, 0.0), d + Vector2(0.0, r), d + Vector2(-r, 0.0),
			d + Vector2(0.0, -r)]), UIStyle.BORDER_GOLD_BRIGHT, 1.0, true)
