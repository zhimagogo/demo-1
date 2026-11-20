class_name HeroPanel
extends PanelContainer
## ============================================================================
## 主角面板（v17 去冗余合并版）：主角信息 + 小队成员合并为**一张卡**。
## 上半（原 HeroPanel）：头像框 / 称号 / HP 条 / 经验条 / 连招段位 / 技能卡。
## 下半（原 SquadPanel 独立卡已并入，计数与成员从此只有一处）：
##   「小队 n/4 · G 集结 · T 集火 · V 编队」标题行 + 成员紧凑单行
##   （职业徽 + 姓名 + 迷你血条 + 数值 + 跟随/自主）+ 集火目标行 + 空态一行。
## 全部连 EventBus 主角/编队信号；数据每 0.25s 节流刷新（血量/跟随/集火）。
## 图标一律走 IconBadge / IconRect（IconDB 真美术资源，缺失时自动回退字徽）。
##
## 布局契约（v17）：底边锚死在建造菜单上方 8px（offset_bottom=-130），顶边随内容
## 收放且**不得越过左上任务卡下缘**（画布 y ≥ 190）——旧版 SquadPanel 压任务卡、
## HeroPanel 压建造菜单的两处重叠就此消灭。
## ============================================================================

# 技能 1/2 的语义图标与配色（绑定 GameDefs.hero_warrior_def().skills 顺序：旋风斩 / 冲锋斩）
const SKILL_ICONS: Array = [&"skill_slash", &"skill_flame"]
const SKILL_ACCENTS: Array = [Color(0.55, 0.8, 1.0), Color(1.0, 0.62, 0.3)]
const SKILL_FALLBACKS: Array = ["旋", "冲"]
const COMBO_MAX := 3                       # 连招段位数（与 Hero 连招段数一致）

# —— 小队区紧凑布局常量 ——
const ROW_HP_W := 44.0                     # 成员行迷你血条宽
const ROW_HP_H := 5.0
const FOCUS_BAR_W := 90.0                  # 集火行血条宽
const BOTTOM_GAP := 130.0                  # 底边距屏幕底（= 建造菜单高 122 + 8px 间隙）
const TOP_LIMIT := -458.0                  # 顶边最远端（画布 y=190，任务卡下缘 182 + 8px）

var _hp_bar: ProgressBar
var _hp_fill: StyleBoxFlat
var _hp_label: Label
var _hp_icon: IconRect
var _xp_bar: ProgressBar
var _xp_label: Label
var _xp_icon: IconRect
var _title_label: Label
var _combo_pips: Array = []         # Array[Dictionary]{ panel, style }（连招段位指示块）
var _combo_label: Label             # 「2/3」段位读数，比单纯亮点更清楚
var _skill_cards: Array = []        # Array[Dictionary]{ panel, label, key, icon, mask }
# —— 小队区（v17 自 SquadPanel 并入；_rows 字段名与旧 SquadPanel 一致，SceneValidation 契约）——
var _squad_title: Label
var _squad_rows_box: VBoxContainer
var _focus_row: HBoxContainer
var _focus_label: Label
var _focus_fill: ColorRect
var _empty_label: Label
var _rows: Dictionary = {}          # member instance_id → { pawn, name, fill, text, status }
var _update_timer: float = 0.0
var _avatar_frame: Control            # 头像金框（主角模式时加亮）
var _avatar_style: StyleBoxFlat     # 头像金框样式（主角模式时加亮）
var _hero: Hero = null


func _ready() -> void:
	# 左下角定位：底边锚死建造菜单上方，顶边由内容决定（_fit_height 动态收放）
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 12
	offset_right = 348
	offset_bottom = -BOTTOM_GAP
	offset_top = TOP_LIMIT                # 初值取最大高度；首个 deferred fit 收紧
	modulate = Color(0.85, 0.85, 0.85)
	visible = false
	_build()
	EventBus.hero_spawned.connect(_on_hero_spawned)
	EventBus.hero_mode_changed.connect(_on_mode_changed)
	EventBus.hero_hp_changed.connect(_on_hp_changed)
	EventBus.hero_leveled.connect(_on_leveled)
	EventBus.combo_step_changed.connect(_on_combo_changed)
	EventBus.skill_cooldown_changed.connect(_on_skill_cd)
	EventBus.squad_changed.connect(_on_squad_changed)
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.squad_focus_changed.connect(_on_focus_changed)
	EventBus.dragon_deploy_changed.connect(_on_dragon_deploy_changed)
	# 自查既有主角：Main._ready() 的顺序是 _spawn_hero() → _setup_hud()，主角在 HUD 建好之前
	# 就已经 emit hero_spawned（Hero._ready()），信号早于本面板存在 → 不补这一枪面板会永远停在
	# visible=false（真机表现为按 Tab 进主角模式也看不到面板）。
	var existing := _find_hero()
	if existing != null:
		_on_hero_spawned(existing)
	# 首帧主题/字体度量收敛后再按内容收紧一次高度
	_fit_height.call_deferred()


## 场景里的主角（与 HUD.gd 同一套查找方式）。复活不会重发 hero_spawned，但主角节点始终存在
## （Hero._on_died() 只隐藏不 queue_free），故绑定一次即长期有效；本函数也作为兜底重绑定用。
func _find_hero() -> Hero:
	if _hero != null and is_instance_valid(_hero):
		return _hero
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero and is_instance_valid(n):
			_hero = n
			return _hero
	return null


func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# ---- 头像行：金框头像（stat_hero）+ 职业/称号（连招段位挪到行尾，省一行）----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_make_avatar_frame())
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_theme_constant_override("separation", 0)
	var title_r := Label.new()
	title_r.text = "主角 · 战士"
	title_r.add_theme_font_size_override("font_size", 15)
	name_box.add_child(title_r)
	_title_label = Label.new()
	_title_label.text = "Lv.1 新兵"
	_title_label.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	_title_label.add_theme_font_size_override("font_size", 12)
	name_box.add_child(_title_label)
	head.add_child(name_box)
	# 连招段位：说明 + 3 个亮暗指示块 + 段位读数（不再单独占一行）
	var combo_caption := Label.new()
	combo_caption.text = "连招"
	combo_caption.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	combo_caption.add_theme_font_size_override("font_size", 12)
	combo_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(combo_caption)
	for i in COMBO_MAX:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(14, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var psb := StyleBoxFlat.new()
		psb.bg_color = _combo_dim_color()
		psb.border_color = Color(UIStyle.BORDER_GOLD.r, UIStyle.BORDER_GOLD.g, UIStyle.BORDER_GOLD.b, 0.55)
		psb.set_border_width_all(1)
		psb.set_corner_radius_all(3)
		pip.add_theme_stylebox_override("panel", psb)
		head.add_child(pip)
		_combo_pips.append({ "panel": pip, "style": psb })
	_combo_label = Label.new()
	_combo_label.text = "—"
	_combo_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_combo_label.add_theme_font_size_override("font_size", 12)
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_combo_label)
	root.add_child(head)

	# ---- 生命行：hp 图标 + 条 + 数值 ----
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 5)
	_hp_icon = IconRect.new(&"hp", 16, UIStyle.HP_GREEN, "血")
	_hp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_icon)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = UIStyle.HP_GREEN
	_hp_fill.set_corner_radius_all(3)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 15)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_row.add_child(_hp_label)
	root.add_child(hp_row)

	# ---- 经验行：xp 图标 + 条 + 数值 ----
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 5)
	_xp_icon = IconRect.new(&"xp", 14, UIStyle.XP_BLUE, "验")
	_xp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(_xp_icon)
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = UIStyle.XP_BLUE
	xp_fill.set_corner_radius_all(3)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 8)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("fill", xp_fill)
	_xp_bar.tooltip_text = "击杀野怪获得经验；升级 +30 生命上限并提升伤害"
	xp_row.add_child(_xp_bar)
	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 12)
	_xp_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	xp_row.add_child(_xp_label)
	root.add_child(xp_row)

	# ---- 技能卡：真图标 + 冷却遮罩（自上而下退去）+ 灰化 + 键位 ----
	var skill_row := HBoxContainer.new()
	skill_row.add_theme_constant_override("separation", 8)
	for i in 2:
		skill_row.add_child(_make_skill_card(i))
	root.add_child(skill_row)

	# ---- 小队区（v17 并入）：标题行自带操作提示，不再另起一行 ----
	var squad_head := HBoxContainer.new()
	squad_head.add_theme_constant_override("separation", 8)
	_squad_title = Label.new()
	_squad_title.text = "小队 0/4"
	_squad_title.add_theme_font_override("font", UIStyle.make_display_font())
	_squad_title.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	_squad_title.add_theme_font_size_override("font_size", 13)
	squad_head.add_child(_squad_title)
	var squad_spacer := Control.new()
	squad_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_head.add_child(squad_spacer)
	var squad_hint := Label.new()
	squad_hint.text = "G 集结 · T 集火 · V 市民管理"
	squad_hint.add_theme_font_size_override("font_size", 11)
	squad_hint.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.85))
	squad_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_head.add_child(squad_hint)
	root.add_child(squad_head)

	# 集火目标行（无集火令时隐藏；整行显隐会改面板高度 → 同步 _fit_height）
	_focus_row = HBoxContainer.new()
	_focus_row.add_theme_constant_override("separation", 6)
	_focus_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_row.visible = false
	root.add_child(_focus_row)
	var focus_badge := IconBadge.new(&"boss", 18, UIStyle.DANGER, "火")
	focus_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_focus_row.add_child(focus_badge)
	_focus_label = Label.new()
	_focus_label.add_theme_font_size_override("font_size", 11)
	_focus_label.add_theme_color_override("font_color", UIStyle.DANGER)
	_focus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_focus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focus_row.add_child(_focus_label)
	var fbg := ColorRect.new()
	fbg.color = UIStyle.BG_SLOT
	fbg.custom_minimum_size = Vector2(FOCUS_BAR_W, 4.0)
	fbg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fbg.clip_contents = true
	_focus_row.add_child(fbg)
	_focus_fill = ColorRect.new()
	_focus_fill.color = UIStyle.HP_RED
	_focus_fill.custom_minimum_size = Vector2(FOCUS_BAR_W, 4.0)
	_focus_fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fbg.add_child(_focus_fill)

	_squad_rows_box = VBoxContainer.new()
	_squad_rows_box.add_theme_constant_override("separation", 3)
	root.add_child(_squad_rows_box)

	_empty_label = Label.new()
	_empty_label.text = "暂无小兵 · 建造房屋吸引流民入住觉醒"
	_empty_label.add_theme_font_size_override("font_size", 11)
	_empty_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_empty_label)


## 头像金框（PanelContainer 只作画框用，内部是圆形图标徽章）。
func _make_avatar_frame() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.tooltip_text = "主角：WASD 移动 · 鼠标瞄准 · 左键挥砍"
	_avatar_frame = frame
	_avatar_style = StyleBoxFlat.new()
	_avatar_style.bg_color = Color(0.10, 0.085, 0.065, 0.96)
	_avatar_style.border_color = UIStyle.BORDER_GOLD_BRIGHT
	_avatar_style.set_border_width_all(2)
	_avatar_style.set_corner_radius_all(8)
	_avatar_style.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", _avatar_style)
	var avatar := IconBadge.new(&"stat_hero", 36, UIStyle.GOLD, "侠")
	frame.add_child(avatar)
	return frame


## 单张技能卡：图标（含冷却遮罩）+ 名称/冷却文本 + 键位角标。
func _make_skill_card(index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(148, 58)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var csb := StyleBoxFlat.new()
	csb.bg_color = UIStyle.BG_PANEL_LIGHT
	csb.border_color = Color(UIStyle.BORDER_GOLD.r, UIStyle.BORDER_GOLD.g, UIStyle.BORDER_GOLD.b, 0.75)
	csb.set_border_width_all(1)
	csb.set_corner_radius_all(5)
	csb.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", csb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	# 图标 + 冷却遮罩：wrap 钳住遮罩范围，遮罩高度用锚点比例表示「剩余冷却」
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(36, 36)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.clip_contents = true
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sicon := IconBadge.new(SKILL_ICONS[index], 36, SKILL_ACCENTS[index], SKILL_FALLBACKS[index])
	# 手工铺满 wrap（wrap 不是容器，不参与布局，故显式给锚点+零偏移）
	sicon.anchor_left = 0.0
	sicon.anchor_top = 0.0
	sicon.anchor_right = 1.0
	sicon.anchor_bottom = 1.0
	sicon.offset_left = 0.0
	sicon.offset_top = 0.0
	sicon.offset_right = 0.0
	sicon.offset_bottom = 0.0
	wrap.add_child(sicon)
	var mask := ColorRect.new()
	mask.color = Color(0.02, 0.02, 0.03, 0.62)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.anchor_left = 0.0
	mask.anchor_right = 1.0
	mask.anchor_top = 0.0
	mask.anchor_bottom = 1.0
	mask.offset_left = 0.0
	mask.offset_right = 0.0
	mask.offset_top = 0.0
	mask.offset_bottom = 0.0
	mask.visible = false
	wrap.add_child(mask)
	hb.add_child(wrap)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vb.add_theme_constant_override("separation", 0)
	var lbl := Label.new()
	lbl.text = "技能%d\n(就绪)" % (index + 1)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)
	var key_l := Label.new()
	key_l.text = "按 Q" if index == 0 else "按 C"
	key_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	key_l.add_theme_font_size_override("font_size", 11)
	vb.add_child(key_l)
	hb.add_child(vb)
	card.add_child(hb)

	_skill_cards.append({ "panel": card, "label": lbl, "key": key_l, "icon": sicon, "mask": mask })
	return card


## 未点亮段位块的底色（比正文更暗，亮起来时一眼可辨）。
func _combo_dim_color() -> Color:
	return Color(0.24, 0.20, 0.15, 0.9)


## 面板高度随内容收放：底边固定，顶边 = 底边 − 内容高，最远不越过任务卡下缘。
## 行的增删（编队变化 / 集火行显隐）都走这里，避免固定大黑框压任务卡。
func _fit_height() -> void:
	if not is_inside_tree():
		return
	var min_h := get_combined_minimum_size().y
	offset_top = clampf(offset_bottom - min_h, TOP_LIMIT, offset_bottom)


# ---- 事件 ----

func _on_hero_spawned(hero) -> void:
	_hero = hero as Hero
	visible = true
	if _hero != null and _hero.hero_def != null:
		for i in mini(_skill_cards.size(), _hero.hero_def.skills.size()):
			var entry: Dictionary = _skill_cards[i]
			(entry["label"] as Label).text = "%s\n就绪" % _hero.hero_def.skills[i].display_name
	_refresh_level()
	if _hero != null and _hero.health != null:
		_on_hp_changed(_hero, _hero.health.current_hp, _hero.health.max_hp)
	_on_combo_changed(_hero, 0)
	_rebuild_squad()


func _on_mode_changed(active: bool) -> void:
	modulate = Color(1.0, 0.95, 0.7) if active else Color(0.85, 0.85, 0.85)
	# 主角模式下头像金框加亮，作为「正在直接操控」的状态提示
	if _avatar_style != null:
		_avatar_style.border_color = UIStyle.GOLD if active else UIStyle.BORDER_GOLD_BRIGHT
		_avatar_style.set_border_width_all(3 if active else 2)
		if _avatar_frame != null:
			_avatar_frame.queue_redraw()      # 改的是覆盖样式盒，显式重绘


func _on_hp_changed(_h, current: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	var ratio: float = current / max_hp if max_hp > 0.0 else 0.0
	var fill := UIStyle.hp_fill_color(ratio)
	_hp_fill.bg_color = fill
	if _hp_icon != null:
		_hp_icon.set_tint(fill)          # 图标与血条同色，低血时整行一起变红
	_hp_label.text = "生命 %d / %d" % [int(current), int(max_hp)]


func _on_leveled(_hero, _level: int) -> void:
	_refresh_level()


func _refresh_level() -> void:
	if _hero == null:
		return
	_title_label.text = "Lv.%d %s · 击杀 %d" % [_hero.level, _hero.hero_title(), _hero.kill_count]
	_title_label.tooltip_text = "伤害 %.0f · 移速 %.1f" % [
		_hero.def.attack_damage * _hero.damage_mult(), _hero.move_speed]
	_refresh_xp()


func _refresh_xp() -> void:
	if _hero == null:
		return
	_xp_bar.max_value = _hero.xp_to_next()
	_xp_bar.value = _hero.xp
	_xp_label.text = "经验 %d / %d" % [_hero.xp, _hero.xp_to_next()]


func _process(_delta: float) -> void:
	# 兜底重绑定：主角若晚于本面板出现、或节点被替换（例如将来调整 Main 的创建顺序），
	# 下一帧就补上绑定并显示；已绑定后这里只剩一次空判 + is_instance_valid，开销可忽略。
	if _hero == null or not is_instance_valid(_hero):
		var found := _find_hero()
		if found != null:
			_on_hero_spawned(found)
	if _hero != null and visible:
		_xp_bar.value = _hero.xp
		_xp_label.text = "经验 %d / %d" % [_hero.xp, _hero.xp_to_next()]
	# 小队区节流刷新：血量 / 跟随态 / 集火目标（信号管结构变化，这里只刷动态值）
	_update_timer -= _delta
	if _update_timer <= 0.0:
		_update_timer = 0.25
		if _hero != null and visible:
			if not _rows.is_empty():
				_refresh_status()
			_refresh_focus()


func _on_combo_changed(_hero, step: int) -> void:
	var lit: int = clampi(step, 0, COMBO_MAX)
	for i in _combo_pips.size():
		var entry: Dictionary = _combo_pips[i]
		var style: StyleBoxFlat = entry["style"]
		style.bg_color = UIStyle.GOLD if i < lit else _combo_dim_color()
		style.border_color = UIStyle.BORDER_GOLD_BRIGHT if i < lit else \
			Color(UIStyle.BORDER_GOLD.r, UIStyle.BORDER_GOLD.g, UIStyle.BORDER_GOLD.b, 0.55)
		# 显式重绘：改的是覆盖样式盒的颜色，不能指望容器顺带重画
		(entry["panel"] as Panel).queue_redraw()
	if _combo_label != null:
		_combo_label.text = "%d/%d" % [lit, COMBO_MAX] if lit > 0 else "—"
		_combo_label.add_theme_color_override("font_color",
			UIStyle.BORDER_GOLD_BRIGHT if lit > 0 else UIStyle.TEXT_DIM)


func _on_skill_cd(_h, index: int, ratio: float) -> void:
	if index < 0 or index >= _skill_cards.size():
		return
	var entry: Dictionary = _skill_cards[index]
	var card: PanelContainer = entry["panel"]
	var ready: bool = ratio >= 1.0
	card.modulate = Color(1, 1, 1) if ready else Color(0.58, 0.58, 0.58)
	# 冷却遮罩：高度 = 剩余冷却比例，随冷却推进自上而下退去
	var mask: ColorRect = entry["mask"]
	mask.visible = not ready
	mask.anchor_bottom = clampf(1.0 - ratio, 0.0, 1.0)
	var icon: IconBadge = entry["icon"]
	icon.set_accent(SKILL_ACCENTS[index] if ready else SKILL_ACCENTS[index].darkened(0.45))
	var name: String = "技能%d" % (index + 1)
	if _hero != null and _hero.hero_def != null and index < _hero.hero_def.skills.size():
		name = _hero.hero_def.skills[index].display_name
	(entry["label"] as Label).text = "%s\n就绪" % name if ready else "%s\n%.0f%%" % [name, ratio * 100.0]


# ============================================================================
# 小队区（v17 自 SquadPanel 并入）
# ============================================================================

func _on_party_changed(_hero_node: Node, _members: Array) -> void:
	_rebuild_squad()


func _on_squad_changed(_hero_node: Node, _members: Array) -> void:
	_refresh_status()          # 集结/解散只改跟随态，不重建行


func _on_focus_changed(_hero_node: Node, _target: Node) -> void:
	_refresh_focus()


## v26 出战巨龙变化：小队区末尾的龙行随之增删。
func _on_dragon_deploy_changed(_id: StringName, _pet: Node) -> void:
	_rebuild_squad()


## 重建成员行（编队变化 / 主角出生）。remove_child + free 立即摘除，
## 保证 _fit_height 量到的是新内容（queue_free 的垂死节点会虚增最小高度）。
func _rebuild_squad() -> void:
	var hero := _find_hero()
	if hero == null or not is_inside_tree():
		return
	for child in _squad_rows_box.get_children():
		_squad_rows_box.remove_child(child)
		child.free()
	_rows.clear()
	var members: Array = hero.alive_party()
	_squad_title.text = "小队 %d/%d" % [members.size(), Hero.SQUAD_MAX]
	_empty_label.visible = members.is_empty()
	for m in members:
		_add_squad_row(m)
	# v26 编外巨龙行：出战中的龙追加在小队末尾（不占 4 槽计数，复活等待期不显示行）
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	if ds != null and ds.current_pet() != null:
		_add_squad_row(ds.current_pet())
		if members.is_empty():
			_empty_label.visible = false   # 有龙无兵也不显示空态行
	_refresh_status()
	_refresh_focus()
	_fit_height()


## 成员紧凑单行：职业字徽 + 姓名（tooltip 职业名）+ 迷你血条 + 数值 + 跟随/自主。
func _add_squad_row(m: Node) -> void:
	var pawn := m as Pawn
	if pawn == null or pawn.def == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_squad_rows_box.add_child(row)

	var icon_color: Color = pawn.def.class_color if pawn.def.class_color != Color.WHITE else UIStyle.GOLD
	var icon_text: String = pawn.def.class_icon if pawn.def.class_icon != "" else "兵"
	var badge := IconBadge.new(&"", 20, icon_color, icon_text)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var name_label := Label.new()
	name_label.text = pawn.get_display_name()
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS 才弹 tooltip（职业名）
	name_label.tooltip_text = pawn.def.display_name
	row.add_child(name_label)

	var hp_bg := ColorRect.new()
	hp_bg.color = UIStyle.BG_SLOT
	hp_bg.custom_minimum_size = Vector2(ROW_HP_W, ROW_HP_H)
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bg.clip_contents = true
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = UIStyle.HP_GREEN
	hp_fill.custom_minimum_size = Vector2(ROW_HP_W, ROW_HP_H)
	hp_fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bg.add_child(hp_fill)

	var hp_text := Label.new()
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hp_text)

	var status := Label.new()
	status.text = "自主"
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.custom_minimum_size = Vector2(30.0, 0.0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)

	_rows[pawn.get_instance_id()] = {
		"pawn": pawn, "name": name_label, "fill": hp_fill, "text": hp_text, "status": status,
	}


## 刷新血量 / 状态文字（0.25s 节流调用；行结构在 party_changed 时重建）。
func _refresh_status() -> void:
	var hero := _find_hero()
	if hero == null:
		return
	var valid_ids: Array = []
	for id in _rows.keys():
		var info: Dictionary = _rows[id]
		# 先无类型接引用再校验：已释放实例只有 is_instance_valid 不抛错
		# （直接赋给 Pawn 类型变量或对它做 is/is_dead 都会先抛 freed instance 错）
		var raw: Variant = info["pawn"]
		if not is_instance_valid(raw):
			continue
		var p := raw as Pawn
		if p == null or p.is_dead_flag:
			continue
		valid_ids.append(id)
		var ratio: float = 1.0
		if p.health != null:
			ratio = clampf(p.health.ratio(), 0.0, 1.0)
		var fill: ColorRect = info["fill"]
		fill.size = Vector2(ROW_HP_W * ratio, ROW_HP_H)
		fill.color = UIStyle.HP_GREEN if ratio > 0.35 else UIStyle.HP_RED
		# v20 属性系统：成员名旁带等级（升级后 0.25s 节流内跟随刷新）
		var name_lbl: Label = info["name"]
		name_lbl.text = "%s·Lv.%d" % [p.get_display_name(), p.level]
		var text: Label = info["text"]
		if p.health != null:
			text.text = "%d/%d" % [ceili(p.health.current_hp), ceili(p.health.max_hp)]
		var status: Label = info["status"]
		var dp := p as DragonPet
		if dp != null:
			status.text = "出战"
			status.add_theme_color_override("font_color", Color(0.8, 0.55, 1.0))
		elif hero.squad.has(p):
			status.text = "跟随"
			status.add_theme_color_override("font_color", UIStyle.GOLD)
		else:
			status.text = "自主"
			status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	# 成员死亡后由 party_changed 重建；这里只防御失效引用
	if valid_ids.size() != _rows.size():
		for id in _rows.keys():
			if not valid_ids.has(id):
				_rows.erase(id)


## 集火目标行：活着才显示（显隐变化会改面板高度 → 同步 _fit_height）。
func _refresh_focus() -> void:
	var hero := _find_hero()
	var show := hero != null and hero.is_focus_alive() \
			and hero.focus_target != null and is_instance_valid(hero.focus_target)
	if not show:
		if _focus_row.visible:
			_focus_row.visible = false
			_fit_height()
		return
	var t: Pawn = hero.focus_target as Pawn
	if t == null:
		if _focus_row.visible:
			_focus_row.visible = false
			_fit_height()
		return
	_focus_row.visible = true
	_focus_label.text = "集火 %s" % t.get_display_name()
	var ratio: float = clampf(t.health.ratio(), 0.0, 1.0) if t.health != null else 1.0
	_focus_fill.size = Vector2(FOCUS_BAR_W * ratio, 4.0)
	_fit_height()
