class_name TopBar
extends PanelContainer
## ============================================================================
## 顶栏（v6 图标化）：资源胶囊（木/石/食/金）· 人口（村民/士兵）· 昼夜时刻 ·
## 天气 · 野怪 · 主城 HP · 倍速 / 暂停 / 引导重播。
##
## 视觉：胶囊底 + IconBadge 语义图标（IconDB 的 res_* / stat_* / time_* / weather_* /
## hp / pause / play / fast_forward / help），缺图时 IconBadge 内部自动回退字徽；
## 配色一律取 UIStyle 常量。布局用 HBoxContainer.separation + StyleBoxFlat 内边距控制，
## 不靠空格凑宽度；数值标签右对齐并锁定最小宽度，数字增长时整条顶栏不抖动。
##
## 行为未变：所有数字仍由 EventBus 信号增量刷新，信号名 / 公开方法签名保持原样。
## 横向预算（逻辑像素）：HUD 基准分辨率 1152×648，顶栏内容宽度约 1100——
## 新增字段前先算宽度，宁紧勿溢（旧版 4 个倍速按钮 + ？按钮就曾溢出屏幕外）。
## ============================================================================

# —— 布局常量（逻辑像素）——
const SAFE_X := 12             # 左右安全边距（与 BuildMenu 统一）
const ICON_PX := 17            # 胶囊内图标直径
const VALUE_FONT := 14         # 数值字号
const TAG_FONT := 13           # 时刻 / 天气字号
const CHIP_SEP := 8            # 胶囊间距
const ITEM_SEP := 5            # 图标与数字间距
const PILL_PAD := Vector2(7, 2)  # 胶囊内边距（纵向压缩：顶栏一行只有 24px 可用）
const PILL_BG := Color(0.0, 0.0, 0.0, 0.22)   # 胶囊底：比面板更深一档

# —— 图标配色 ——
# 资源 / 人口 / 兵种一律取 UIStyle 的 v6 亮色表（RES_COLORS / UNIT_COLORS）：
# 图标 PNG 是纯白前景、颜色全靠 accent 上色，而 GameDefs 的 SADDLE_BROWN / DIM_GRAY
# 在深胡桃木胶囊上对比度不足（真机实拍最亮 luma≈76），故不直接拿它上色。
# 时刻 / 天气的颜色不在那两张表里，保留本文件的专用色（白昼暖 / 夜晚冷 / 天气分档）。
const COLOR_ENEMY := Color(1.0, 0.55, 0.45)
const COLOR_DAY := Color(1.0, 0.85, 0.4)
const COLOR_NIGHT := Color(0.55, 0.6, 0.95)
const COLOR_CLEAR := Color(0.9, 0.8, 0.45)
const COLOR_CLOUD := Color(0.6, 0.62, 0.68)
const COLOR_RAIN := Color(0.45, 0.6, 0.9)
const COLOR_STORM := Color(0.72, 0.7, 0.95)

var _res_labels: Dictionary = {}   # StringName -> Label
var _villager_label: Label
var _soldier_label: Label
var _day_label: Label
var _phase_icon: IconBadge
var _weather_icon: IconBadge
var _weather_label: Label
var _base_hp_bar: ProgressBar
var _base_hp_label: Label
var _base_hp_icon: IconBadge
var _hp_fill: StyleBoxFlat
var _speed_buttons: Array = []
var _monster_label: Label

var _row: HBoxContainer


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = SAFE_X
	offset_top = 10
	offset_right = -SAFE_X
	offset_bottom = 54
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶栏专用面板样式：沿用主题色，但压缩纵向内边距，让 24px 高的一行控件不溢出边框。
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = UIStyle.BG_PANEL
	panel_sb.border_color = UIStyle.BORDER_GOLD
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(6)
	panel_sb.content_margin_left = 10
	panel_sb.content_margin_right = 10
	panel_sb.content_margin_top = 5
	panel_sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", panel_sb)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", CHIP_SEP)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_build_resource_pill()
	_build_population_pill()
	_build_clock_pill()
	_build_weather_pill()
	_build_enemy_pill()

	# ---- 右侧弹性区：把 HP / 倍速推到最右 ----
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)

	_build_base_hp_pill()
	_build_speed_buttons()

	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.time_tick.connect(_on_time_tick)
	EventBus.time_scale_changed.connect(_on_time_scale_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.night_changed.connect(_on_night_changed)
	EventBus.pawn_spawned.connect(_on_pawn_spawned)
	EventBus.pawn_died.connect(_on_pawn_died)
	EventBus.hero_died.connect(func(_h): _refresh_population())
	_refresh_population()
	_refresh_clock()
	_update_base_hp()
	_refresh_enemy_count()


## ============================ 构建：胶囊与控件 ============================

## 造一个「胶囊」：暗底 + 微金边的水平容器，返回其内部 HBoxContainer 供塞内容。
## PASS 鼠标过滤：胶囊可弹 tooltip，又把点击让给下层（与旧版 IGNORE 行为一致）。
func _add_pill(sep: int, tip: String = "") -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.tooltip_text = tip
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = PILL_BG
	var bc := UIStyle.BORDER_GOLD
	sb.border_color = Color(bc.r, bc.g, bc.b, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = PILL_PAD.x
	sb.content_margin_right = PILL_PAD.x
	sb.content_margin_top = PILL_PAD.y
	sb.content_margin_bottom = PILL_PAD.y
	panel.add_theme_stylebox_override("panel", sb)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	_row.add_child(panel)
	return box


## 数值标签：右对齐 + 锁定最小宽度（数字位数变化时顶栏不抖动）+ 可弹 tooltip。
func _add_value(parent: Node, min_w: int, color: Color = UIStyle.TEXT_MAIN,
		font: int = VALUE_FONT, tip: String = "") -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(min_w, 0)
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_PASS   # Label 默认 IGNORE，PASS 才弹得出 tooltip
	if tip != "":
		l.tooltip_text = tip
	parent.add_child(l)
	return l


## 图标 + 数值 的最小单元（左图标右数字，间距走 separation）。
func _add_icon_value(parent: Node, icon_id: StringName, tint: Color, fb: String,
		min_w: int, color: Color, font: int, tip: String) -> Label:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", ITEM_SEP)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(item)
	var icon := IconBadge.new(icon_id, ICON_PX, tint, fb)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(icon)
	return _add_value(item, min_w, color, font, tip)


## 资源胶囊：木 / 石 / 食 / 金（图标走 IconDB.resource_icon()，颜色走 UIStyle.resource_color()）。
func _build_resource_pill() -> void:
	var box := _add_pill(8, "资源储量：木材 / 石头 / 食物 / 金币")
	for rd in GameDefs.resource_defs():
		var label := _add_icon_value(box, IconDB.resource_icon(rd.id), UIStyle.resource_color(rd.id),
			String(rd.display_name.substr(0, 1)), 30, UIStyle.TEXT_MAIN, VALUE_FONT,
			rd.display_name)
		label.text = "%d" % ResourceManager.get_amount(rd.id)
		_res_labels[rd.id] = label


## 人口胶囊：定居居民（流民入住觉醒的小兵，占房屋床位）。
func _build_population_pill() -> void:
	var box := _add_pill(10, "人口：定居居民（房屋床位上限，流民入住觉醒为小兵）")
	_villager_label = _add_icon_value(box, &"stat_pop", UIStyle.unit_color(&"stat_pop"), "民", 22,
		UIStyle.TEXT_MAIN, VALUE_FONT, "定居居民数（流民入住房屋后觉醒为小兵）")
	_soldier_label = _add_icon_value(box, &"stat_soldier", UIStyle.unit_color(&"stat_soldier"), "兵", 22,
		UIStyle.TEXT_MAIN, VALUE_FONT, "未定居武装小兵数（v21 起小兵均由定居觉醒）")


## 时刻胶囊：昼夜图标（time_day / time_night）随时间切换 + 「第 N 天 HH:00」。
func _build_clock_pill() -> void:
	var box := _add_pill(6, "游戏时间：昼夜推进，夜晚野怪会集结攻城")
	_phase_icon = IconBadge.new(&"time_day", ICON_PX, COLOR_DAY, "昼")
	_phase_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_phase_icon)
	_day_label = _add_value(box, 86, UIStyle.TEXT_MAIN, TAG_FONT)


## 天气胶囊：晴 / 云 / 雨 / 暴雨 四档图标 + 文字档位（沿用 weather_changed 的分档逻辑）。
func _build_weather_pill() -> void:
	var box := _add_pill(6, "天气：雨天压暗天光、浇湿地表；暴雨伴随雷电")
	_weather_icon = IconBadge.new(&"weather_clear", ICON_PX, COLOR_CLEAR, "晴")
	_weather_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_weather_icon)
	_weather_label = _add_value(box, 28, UIStyle.TEXT_MAIN, TAG_FONT)
	_weather_label.text = "晴朗"


## 野怪胶囊：城外威胁计数（stat_enemy）。
func _build_enemy_pill() -> void:
	var box := _add_pill(6, "城外野怪数（夜晚会更多）")
	_monster_label = _add_icon_value(box, &"stat_enemy", COLOR_ENEMY, "怪", 20,
		COLOR_ENEMY, VALUE_FONT, "城外野怪数（夜晚会更多）")
	_monster_label.text = "0"


## 主城 HP 胶囊：hp 图标 + 主城名 + 血条 + 当前/上限数值。
func _build_base_hp_pill() -> void:
	var box := _add_pill(6, "主城耐久：归零即陷落")
	_base_hp_icon = IconBadge.new(&"hp", ICON_PX, UIStyle.HP_GREEN, "血")
	_base_hp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_base_hp_icon)
	var name_l := Label.new()
	name_l.text = "主城"
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_l)
	_base_hp_bar = ProgressBar.new()
	_base_hp_bar.custom_minimum_size = Vector2(86, 14)
	_base_hp_bar.min_value = 0.0
	_base_hp_bar.max_value = float(GameManager.player_base_max_health)
	_base_hp_bar.value = float(GameManager.player_base_health)
	_base_hp_bar.show_percentage = false
	_base_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 填充色按血量比例动态变（>50% 绿 → >25% 黄 → 红），比固定金条更能一眼看出危险。
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = UIStyle.HP_GREEN
	_hp_fill.set_corner_radius_all(3)
	_base_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	box.add_child(_base_hp_bar)
	_base_hp_label = _add_value(box, 62, UIStyle.TEXT_DIM, 12)


## 倍速 / 暂停 / 引导重播按钮：图标走 pause / play / fast_forward / help。
func _build_speed_buttons() -> void:
	var tiers := [
		{ "mult": 0.0, "icon": &"pause", "text": "", "fb": "停", "tip": "暂停 / 继续（P）", "w": 28 },
		{ "mult": 1.0, "icon": &"play", "text": "1×", "fb": "▶", "tip": "正常速度", "w": 40 },
		{ "mult": 2.0, "icon": &"fast_forward", "text": "2×", "fb": "2×", "tip": "2 倍速", "w": 40 },
		{ "mult": 3.0, "icon": &"fast_forward", "text": "3×", "fb": "3×", "tip": "3 倍速", "w": 40 },
	]
	for t in tiers:
		var b := Button.new()
		_apply_button_icon(b, t["icon"], String(t["text"]), String(t["fb"]))
		_style_compact_button(b, 4, 2)
		b.add_theme_font_size_override("font_size", 11)
		b.custom_minimum_size = Vector2(int(t["w"]), 24)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = String(t["tip"])
		b.focus_mode = Control.FOCUS_NONE   # 顶栏不吃 Tab：Tab 是主角模式热键
		var m: float = t["mult"]
		b.pressed.connect(func() -> void:
			if m == 0.0:
				var is_paused: bool = TimeManager.time_scale <= 0.0
				GameManager.set_paused(not is_paused)
			else:
				TimeManager.set_speed(m)
			AudioManager.play_sfx(&"ui_click"))
		_row.add_child(b)
		_speed_buttons.append({ "btn": b, "mult": m })

	# ---- 新手引导重播（v4）----
	var help := Button.new()
	_apply_button_icon(help, &"help", "", "？")
	_style_compact_button(help, 4, 2)
	help.add_theme_font_size_override("font_size", 11)
	help.custom_minimum_size = Vector2(28, 24)
	help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	help.tooltip_text = "重播新手引导"
	help.focus_mode = Control.FOCUS_NONE
	help.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		help.release_focus()
		var t := get_tree().get_first_node_in_group("tutorial_system")
		if t != null and t.has_method("restart"):
			t.restart())
	_row.add_child(help)


## 给按钮挂语义图标：有贴图就用 Button.icon（限宽 13px），缺图时退回文字字形，避免空按钮。
func _apply_button_icon(b: Button, icon_id: StringName, text: String, fallback: String) -> void:
	if IconDB.has_icon(icon_id):
		b.icon = IconDB.get_texture(icon_id)
		b.add_theme_constant_override("icon_max_width", 13)
		b.text = text
	else:
		b.text = text if text != "" else fallback


## 紧凑按钮样式：沿用主题配色，但把内边距压到 (4,2)，让 24px 高的按钮放得下图标 + 数字。
func _style_compact_button(b: Button, h_pad: int, v_pad: int) -> void:
	var states := {
		"normal": [Color(0.20, 0.165, 0.12, 0.95), Color(0.45, 0.37, 0.22, 0.9)],
		"hover": [Color(0.28, 0.225, 0.15, 0.98), UIStyle.BORDER_GOLD_BRIGHT],
		"pressed": [Color(0.15, 0.12, 0.09, 0.98), UIStyle.GOLD],
		"disabled": [Color(0.16, 0.15, 0.13, 0.7), Color(0.3, 0.28, 0.24, 0.5)],
	}
	for state in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state][0]
		sb.border_color = states[state][1]
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = h_pad
		sb.content_margin_right = h_pad
		sb.content_margin_top = v_pad
		sb.content_margin_bottom = v_pad
		b.add_theme_stylebox_override(state, sb)


## ============================ 刷新 ============================

func _on_resource_changed(id: StringName, amount: int, _delta: int) -> void:
	if _res_labels.has(id):
		(_res_labels[id] as Label).text = "%d" % amount


func _on_time_tick(_s: float, day: int, hour: int) -> void:
	# 场景重载（游戏结束→重新开始）期间本节点已脱离场景树，但 TimeManager 仍会
	# 广播 time_tick —— get_tree() 此时为 null，不守卫会崩。
	if not is_inside_tree():
		return
	_set_clock_text(day, hour)
	_refresh_clock_icon(hour)
	_update_base_hp()
	_refresh_enemy_count()


func _on_time_scale_changed(scale: float) -> void:
	for entry in _speed_buttons:
		var btn: Button = entry["btn"]
		var mult: float = entry["mult"]
		var active: bool = is_equal_approx(mult, scale)
		btn.modulate = Color(1.0, 0.92, 0.6) if active else Color(1, 1, 1)


func _on_weather_changed(weather_id: StringName, intensity: float) -> void:
	match weather_id:
		&"rain":
			if intensity >= 0.9:
				_weather_icon.set_badge(&"weather_storm", -1, COLOR_STORM, "暴")
				_weather_label.text = "暴雨"
			else:
				_weather_icon.set_badge(&"weather_rain", -1, COLOR_RAIN, "雨")
				if intensity < 0.35:
					_weather_label.text = "小雨"
				elif intensity < 0.65:
					_weather_label.text = "中雨"
				else:
					_weather_label.text = "大雨"
		&"cloudy":
			_weather_icon.set_badge(&"weather_cloud", -1, COLOR_CLOUD, "云")
			_weather_label.text = "多云"
		_:
			_weather_icon.set_badge(&"weather_clear", -1, COLOR_CLEAR, "晴")
			_weather_label.text = "晴朗"


func _on_night_changed(is_night: bool) -> void:
	_set_phase(is_night)


func _on_pawn_spawned(pawn: Node) -> void:
	if pawn is Colonist or pawn is Soldier:
		_refresh_population()


func _on_pawn_died(pawn: Node) -> void:
	if pawn is Colonist or pawn is Soldier:
		_refresh_population.call_deferred()


func _refresh_population() -> void:
	if not is_inside_tree():
		return   # 场景重载拆卸期：pawn 信号仍可能到达
	var residents: int = 0
	var soldiers: int = 0
	for n in get_tree().get_nodes_in_group("player_unit"):
		if not is_instance_valid(n) or not (n is Pawn):
			continue
		if n.is_dead_flag:
			continue
		if n is Colonist:
			residents += 1   # 兼容旧存档/测试直接生成的村民
		elif n is Soldier:
			# 定居小兵（挂了家 = 占床位）算「民」；未挂家的（测试/临时生成）算「兵」
			if (n as Soldier).home != null and is_instance_valid((n as Soldier).home):
				residents += 1
			else:
				soldiers += 1
	_villager_label.text = "%d" % residents
	_soldier_label.text = "%d" % soldiers


## 时刻文字 + 昼夜图标（初始与 time_tick 用；night_changed 只翻图标）。
func _refresh_clock() -> void:
	_set_clock_text(TimeManager.day, TimeManager.hour)
	_refresh_clock_icon(TimeManager.hour)


func _set_clock_text(day: int, hour: int) -> void:
	_day_label.text = "第%d天 %02d:00" % [day, hour]


func _refresh_clock_icon(hour: int) -> void:
	_set_phase(hour >= 20 or hour < 6)


## 昼夜图标 + 时刻文字配色：白天暖、夜晚冷（同一处设置，避免两条路径不一致）。
func _set_phase(is_night: bool) -> void:
	_phase_icon.set_badge(&"time_night" if is_night else &"time_day", -1,
		COLOR_NIGHT if is_night else COLOR_DAY, "夜" if is_night else "昼")
	_day_label.add_theme_color_override("font_color",
		Color(0.82, 0.86, 1.0) if is_night else UIStyle.TEXT_MAIN)


## 主城血量：条 + 数值 + 图标配色（绿→黄→红）。
func _update_base_hp() -> void:
	var hp: int = GameManager.player_base_health
	var mx: int = maxi(1, GameManager.player_base_max_health)
	_base_hp_bar.value = float(hp)
	_base_hp_label.text = "%d/%d" % [hp, mx]
	var c := UIStyle.hp_fill_color(float(hp) / float(mx))
	_hp_fill.bg_color = c
	_base_hp_icon.set_accent(c)


func _refresh_enemy_count() -> void:
	if not is_inside_tree():
		return
	var cs := get_tree().get_first_node_in_group("combat_system") as CombatSystem
	_monster_label.text = "%d" % (cs.enemies_alive if cs != null else 0)
