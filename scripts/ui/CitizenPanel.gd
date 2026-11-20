class_name CitizenPanel
extends Control
## ============================================================================
## 市民管理界面（v25，按 V 或右上「市民管理」按钮打开；由原编队界面升级而来）：
##   · 出征编队：上排 4 个出战槽位（点击移出）——编队功能保留不变；
##   · 主角行：等级 / 血量 / 技能点 +「技能树」入口；
##   · 城镇市民列表：全部市民（含已在编队内的，标「在队」），每行展示
##     等级 / 职业 / 血量 / 攻防 / 技能点，并提供「技能树」与「转职」操作；
##   · 转职：基础职业 Lv.5 起二选一进阶（战士→狂战士/骑士 …），点击即转。
## 打开 = 记住当前倍速并真暂停 + 占用 ui_modal_count（HeroController 据此释放鼠标）；
## 关闭 = V / Esc / 「完成」按钮，恢复原倍速。
## Esc 优先级链：技能树面板 > 本界面 > PauseMenu（各自 _unhandled_input 消费，
## PauseMenu 另有防御性放行）。
## ============================================================================

var is_open: bool = false

var _dim: ColorRect
var _slots_box: HBoxContainer
var _roster_box: VBoxContainer
var _dragon_box: VBoxContainer
var _count_label: Label
var _flash_label: Label
var _hero_row_box: VBoxContainer
var _previous_speed: float = 1.0
var _flash_timer: float = 0.0
# v33.1：市民行就地刷新器（instance_id -> Callable）——技能树加点后不必整表重建
var _row_refreshers: Dictionary = {}


func _ready() -> void:
	name = "PartyPanel"   # 节点名沿用旧编队界面（测试 / 工具按名与分组取用）
	add_to_group("party_panel")
	add_to_group("citizen_panel")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 关闭时不挡任何点击
	# 全矩形铺满父级 + 显式清零 offsets（父级已布局时 set_anchors_preset 会按当前
	# 0×0 rect 回推 offsets → 面板永远 0×0 不可见，准星同款坑）
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_ui()
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.soldier_promoted.connect(_on_soldier_promoted)
	EventBus.skill_tree_changed.connect(_on_skill_tree_changed)
	# v26 驯龙：解锁 / 出战状态变化时刷新巨龙区
	EventBus.dragon_unlocked.connect(_on_dragon_changed)
	EventBus.dragon_deploy_changed.connect(_on_dragon_changed)


func _on_dragon_changed(_id: StringName, _pet: Node = null) -> void:
	if is_open:
		_refresh()


func _on_party_changed(_hero_node: Node, _members: Array) -> void:
	if is_open:
		_refresh()


func _on_soldier_promoted(_pawn: Node, _new_def: Resource) -> void:
	if is_open:
		_refresh()   # 转职后职业名 / 字徽 / 数值全变，整表重建


func _on_skill_tree_changed(p: Pawn) -> void:
	if not is_open:
		return
	# v33.1：加点会改技能点 / 攻击 / 生命上限——主角行照旧重建，市民行走就地刷新器
	# （找不到对应行时兜底整表重建，避免出现「界面数字不动」）。
	if p is Hero:
		_refresh_hero_row()
		return
	if p != null and is_instance_valid(p) and _row_refreshers.has(p.get_instance_id()):
		(_row_refreshers[p.get_instance_id()] as Callable).call()
		return
	_refresh()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.66)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.offset_left = 0.0   # 显式清零：set_anchors_preset 在父级已布局时会按当前 0×0 rect 回推 offsets
	_dim.offset_top = 0.0
	_dim.offset_right = 0.0
	_dim.offset_bottom = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 打开时挡住对世界的误点
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
	panel.custom_minimum_size = Vector2(820.0, 560.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(UIStyle.section_title("市 民 管 理", &"home", 18))

	var subtitle := Label.new()
	subtitle.text = "城镇全部市民一览（含已编队的）。点击成员行加入 / 移出出征编队；Lv.%d 可转职进阶；点「技能树」消耗技能点强化角色（每次升级 +1 点）。" % GameDefs.PROMOTE_LEVEL
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)

	_count_label = Label.new()
	_count_label.text = "出战 0/4"
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	box.add_child(_count_label)

	# ---- 上排：4 个出战槽位（点击移出）----
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 10)
	_slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_slots_box)

	# ---- v26 出战巨龙区（编外第 5 位：不占上方 4 槽，龙园驯服后在此出战 / 召回）----
	_dragon_box = VBoxContainer.new()
	_dragon_box.add_theme_constant_override("separation", 4)
	box.add_child(_dragon_box)

	# ---- 主角行：等级 / 血量 / 技能点 + 技能树入口 ----
	_hero_row_box = VBoxContainer.new()
	_hero_row_box.add_theme_constant_override("separation", 4)
	box.add_child(_hero_row_box)

	# ---- 下区：城镇市民列表（滚动） ----
	var roster_title := Label.new()
	roster_title.text = "—— 城镇市民 ——"
	roster_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roster_title.add_theme_font_size_override("font_size", 13)
	roster_title.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	roster_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(roster_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 230.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 5)
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_box)

	_flash_label = Label.new()
	_flash_label.text = ""
	_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash_label.add_theme_font_size_override("font_size", 13)
	_flash_label.add_theme_color_override("font_color", UIStyle.DANGER)
	box.add_child(_flash_label)

	var close_btn := Button.new()
	close_btn.text = "完 成（V / Esc）"
	close_btn.custom_minimum_size = Vector2(200.0, 36.0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


# ============================================================================
# 开 / 关（真暂停 + UI 模态）
# ============================================================================

func open() -> void:
	if is_open or GameManager.phase == GameManager.Phase.GAME_OVER:
		return
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
	if GameManager.phase != GameManager.Phase.GAME_OVER:
		TimeManager.set_speed(_previous_speed if _previous_speed > 0.0 else 0.0)
	AudioManager.play_sfx(&"ui_click")


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	# 技能树面板开着时输入归它（它挂在更上层、先收到；这里防御性放行）
	var tree_panel := get_tree().get_first_node_in_group("skill_tree_panel")
	if tree_panel != null and tree_panel.get("is_open"):
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("party_menu"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_label.text = ""


# ============================================================================
# 数据装配
# ============================================================================

func _hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero and is_instance_valid(n):
			return n
	return null


## 技能树面板（挂在 HUD 顶层；按分组取回）。
func _skill_tree_panel() -> SkillTreePanel:
	return get_tree().get_first_node_in_group("skill_tree_panel") as SkillTreePanel


func _refresh() -> void:
	var hero := _hero()
	if hero == null:
		return
	var members: Array = hero.alive_party()
	_count_label.text = "出战 %d/%d" % [members.size(), Hero.SQUAD_MAX]
	_build_slots(hero, members)
	_build_dragon_section()
	_refresh_hero_row()
	_build_roster(hero, members)


## 上排出战槽位：有成员显示卡片（点击移出），空位显示占位卡。
func _build_slots(hero: Hero, members: Array) -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	for i in Hero.SQUAD_MAX:
		if i < members.size():
			_slots_box.add_child(_slot_card(hero, members[i]))
		else:
			_slots_box.add_child(_empty_slot_card())


## 出战槽位大卡：字徽 + 姓名 + 职业 + 血条；点击移出编队。
func _slot_card(hero: Hero, pawn: Pawn) -> Control:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(158.0, 66.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style: StyleBox = UIStyle.panel_style(&"light")
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10.0
	row.offset_right = -10.0
	row.offset_top = 0.0
	row.offset_bottom = 0.0
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon_color: Color = pawn.def.class_color if pawn.def != null and pawn.def.class_color != Color.WHITE else UIStyle.GOLD
	var icon_text: String = pawn.def.class_icon if pawn.def != null and pawn.def.class_icon != "" else "兵"
	var badge := IconBadge.new(&"", 34, icon_color, icon_text)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vbox)

	var name_label := Label.new()
	name_label.text = "%s·Lv.%d" % [pawn.get_display_name(), pawn.level]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	vbox.add_child(name_label)
	var class_label := Label.new()
	class_label.text = pawn.def.display_name if pawn.def != null else "小兵"
	class_label.add_theme_font_size_override("font_size", 11)
	class_label.add_theme_color_override("font_color", icon_color)
	vbox.add_child(class_label)

	var hp_bg := ColorRect.new()
	hp_bg.color = UIStyle.BG_SLOT
	hp_bg.custom_minimum_size = Vector2(120.0, 6.0)
	hp_bg.clip_contents = true
	vbox.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	var ratio: float = clampf(pawn.health.ratio(), 0.0, 1.0) if pawn.health != null else 1.0
	hp_fill.color = UIStyle.HP_GREEN if ratio > 0.35 else UIStyle.HP_RED
	hp_fill.size = Vector2(120.0 * ratio, 6.0)
	hp_bg.add_child(hp_fill)

	var hint := Label.new()
	hint.text = "移出"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)

	btn.pressed.connect(func() -> void:
		hero.remove_party_member(pawn)
		_flash("已移出：%s" % pawn.get_display_name())
		_refresh()
	)
	return btn


## 空槽位占位卡。
func _empty_slot_card() -> Control:
	var ph := PanelContainer.new()
	ph.custom_minimum_size = Vector2(158.0, 66.0)
	ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ph.add_theme_stylebox_override("panel", UIStyle.panel_style(&"inset"))
	var label := Label.new()
	label.text = "空 位"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.7))
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ph.add_child(label)
	return ph


# ============================================================================
# v26 出战巨龙区：编外第 5 位（龙园驯服，不占上方 4 槽）
# ============================================================================

func _dragon_system() -> DragonSystem:
	return get_tree().get_first_node_in_group("dragon_system") as DragonSystem


## 巨龙出战区：标题 + 每条龙一行（字徽 + 名 + 状态 + 出战/召回按钮）。
## 未建龙园 → 引导文案；已建但未驯服 → 提示去龙园按 E 解锁。
func _build_dragon_section() -> void:
	for c in _dragon_box.get_children():
		_dragon_box.remove_child(c)
		c.free()
	var title := Label.new()
	title.text = "—— 出战巨龙（编外 · 龙园驯服） ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_dragon_box.add_child(title)

	var ds := _dragon_system()
	var defs := GameDefs.dragon_defs()
	if ds == null or defs.is_empty():
		var hint := Label.new()
		hint.text = "（未接入驯龙系统）"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.7))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_dragon_box.add_child(hint)
		return
	if not ds.has_garden() and ds.unlocked.is_empty():
		var hint := Label.new()
		hint.text = "建造「龙园」后可驯龙：走近龙园按 [E] 花金币解锁，巨龙将额外随队出战"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.85))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_dragon_box.add_child(hint)
		return
	for d in defs:
		_dragon_box.add_child(_dragon_row(ds, d))


## 单条龙行：字徽 + 名称 + 状态（未驯服 / 待命 / 出战中 / 复苏中）+ 出战/召回按钮。
func _dragon_row(ds: DragonSystem, d: DragonDef) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel_style(&"light"))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var badge := IconBadge.new(&"skill_flame", 26, d.class_color, "龙")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var name_l := Label.new()
	name_l.text = d.display_name
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var status_l := Label.new()
	status_l.add_theme_font_size_override("font_size", 11)
	status_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status_l)

	if not ds.is_unlocked(d.id):
		status_l.text = "未驯服 · 走近龙园按 [E] 解锁（%d 金币）" % d.unlock_cost
		status_l.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.85))
		return card

	var dragon_id := d.id
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72.0, 28.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ds.deployed_id == dragon_id:
		status_l.text = "出战中 · 跟随主角" if ds.current_pet() != null \
			else "倒下了 · %.0f 秒后复苏" % ceilf(maxf(ds.respawn_left, 0.0))
		status_l.add_theme_color_override("font_color",
			Color(0.55, 1.0, 0.6) if ds.current_pet() != null else UIStyle.DANGER)
		btn.text = "召回"
		btn.pressed.connect(func() -> void:
			ds.undeploy()
			_refresh())
	else:
		status_l.text = "已驯服 · 待命"
		status_l.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
		btn.text = "出战"
		btn.pressed.connect(func() -> void:
			if ds.deploy(dragon_id):
				_flash("「%s」出战：跟随主角，攻击你攻击的目标" % d.display_name)
			_refresh())
	row.add_child(btn)
	return card


## 主角行：主角也是「人物」之一，同样有技能树入口。
func _refresh_hero_row() -> void:
	for c in _hero_row_box.get_children():
		_hero_row_box.remove_child(c)
		c.free()
	var hero := _hero()
	if hero == null:
		return
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel_style(&"light"))
	_hero_row_box.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var badge := IconBadge.new(&"stat_hero", 34, UIStyle.GOLD, "侠")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var name_l := Label.new()
	name_l.text = "主角 · Lv.%d %s" % [hero.level, hero.hero_title()]
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var hp_l := Label.new()
	var hp_text := "生命 —" 
	if hero.health != null:
		hp_text = "生命 %d/%d" % [ceili(hero.health.current_hp), ceili(hero.health.max_hp)]
	hp_l.text = hp_text
	hp_l.add_theme_font_size_override("font_size", 12)
	hp_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hp_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hp_l)

	var pts_l := Label.new()
	pts_l.text = "技能点 %d" % hero.skill_points
	pts_l.add_theme_font_size_override("font_size", 12)
	pts_l.add_theme_color_override("font_color", UIStyle.XP_BLUE if hero.skill_points > 0 else UIStyle.TEXT_DIM)
	pts_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pts_l)

	row.add_child(_skill_tree_button(hero))


## 城镇全部市民（含已编队的，标「在队」）。
func _build_roster(hero: Hero, members: Array) -> void:
	_row_refreshers.clear()   # 行被重建：旧刷新器随节点一起作废（v33.1）
	for c in _roster_box.get_children():
		c.queue_free()
	var soldiers: Array = []
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Soldier and is_instance_valid(n) and not (n as Pawn).is_dead_flag:
			soldiers.append(n)
	if soldiers.is_empty():
		var empty := Label.new()
		empty.text = "城镇还没有市民——建造房屋吸引流民入住，觉醒为职业小兵"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_roster_box.add_child(empty)
		return
	soldiers.sort_custom(func(a, b): return (a as Pawn).get_display_name() < (b as Pawn).get_display_name())
	for s in soldiers:
		_roster_box.add_child(_citizen_row(hero, s, members.has(s)))


## 市民行：字徽 + 姓名行（名·Lv / 职业 / 在队标）+ 信息行（血条 / 攻防 / 技能点）
## + 操作区（技能树 / 转职 / 编队）。整行是浅色卡（Panel，非 Button，避免嵌套按钮误触）。
func _citizen_row(hero: Hero, pawn: Pawn, in_party: bool) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel_style(&"light"))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var icon_color: Color = pawn.def.class_color if pawn.def != null and pawn.def.class_color != Color.WHITE else UIStyle.GOLD
	var icon_text: String = pawn.def.class_icon if pawn.def != null and pawn.def.class_icon != "" else "兵"
	var badge := IconBadge.new(&"", 30, icon_color, icon_text)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vbox.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "%s·Lv.%d" % [pawn.get_display_name(), pawn.level]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var class_label := Label.new()
	class_label.text = pawn.def.display_name if pawn.def != null else "小兵"
	class_label.add_theme_font_size_override("font_size", 11)
	class_label.add_theme_color_override("font_color", icon_color)
	name_row.add_child(class_label)
	if in_party:
		var tag := Label.new()
		tag.text = "［在队］"
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
		name_row.add_child(tag)

	# 信息行：迷你血条 + 数值 + 攻防 + 技能点（v33.1：加点后由 _row_refreshers 就地刷新）
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 8)
	vbox.add_child(info_row)
	var hp_bg := ColorRect.new()
	hp_bg.color = UIStyle.BG_SLOT
	hp_bg.custom_minimum_size = Vector2(90.0, 6.0)
	hp_bg.clip_contents = true
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_row.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	var ratio: float = clampf(pawn.health.ratio(), 0.0, 1.0) if pawn.health != null else 1.0
	hp_fill.color = UIStyle.HP_GREEN if ratio > 0.35 else UIStyle.HP_RED
	hp_fill.size = Vector2(90.0 * ratio, 6.0)
	hp_bg.add_child(hp_fill)
	var hp_text := Label.new()
	var hp_str := ""
	if pawn.health != null:
		hp_str = "%d/%d" % [ceili(pawn.health.current_hp), ceili(pawn.health.max_hp)]
	hp_text.text = hp_str
	hp_text.add_theme_font_size_override("font_size", 11)
	hp_text.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	info_row.add_child(hp_text)
	var stat_text := Label.new()
	stat_text.text = "攻 %.0f · 防 %.0f" % [pawn.attacker.damage if pawn.attacker != null else 0.0, pawn.defense_stat]
	stat_text.add_theme_font_size_override("font_size", 11)
	stat_text.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	info_row.add_child(stat_text)
	var pts: Label = null
	if pawn.has_skill_tree():
		pts = Label.new()
		pts.text = "技能点 %d" % pawn.skill_points
		pts.add_theme_font_size_override("font_size", 11)
		pts.add_theme_color_override("font_color", UIStyle.XP_BLUE if pawn.skill_points > 0 else UIStyle.TEXT_DIM)
		info_row.add_child(pts)

	# ---- 操作区：技能树 / 转职 / 编队 ----
	var skill_btn: Button = null
	if pawn.has_skill_tree():
		skill_btn = _skill_tree_button(pawn)
		row.add_child(skill_btn)
	var soldier := pawn as Soldier
	if soldier != null:
		row.add_child(_promote_area(soldier))

	var party_btn := Button.new()
	party_btn.focus_mode = Control.FOCUS_NONE
	party_btn.text = "移出编队" if in_party else "加入编队"
	party_btn.custom_minimum_size = Vector2(84.0, 30.0)
	party_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	party_btn.pressed.connect(func() -> void:
		if in_party:
			hero.remove_party_member(pawn)
			_flash("已移出：%s" % pawn.get_display_name())
		elif not hero.add_party_member(pawn):
			_flash("队伍已满（4/4）——先点击上方成员移出")
		_refresh()
	)
	row.add_child(party_btn)

	# v33.1 实时刷新：在技能树面板里加点后，本行的「技能点 / 攻防 / 生命 / tooltip」就地更新
	# （旧版只刷新主角行，市民行要关掉面板重开才变——真机反馈的「点技能点不实时刷新」）。
	_row_refreshers[pawn.get_instance_id()] = func() -> void:
		if not is_instance_valid(pawn):
			return
		if pts != null and is_instance_valid(pts):
			pts.text = "技能点 %d" % pawn.skill_points
			pts.add_theme_color_override("font_color",
				UIStyle.XP_BLUE if pawn.skill_points > 0 else UIStyle.TEXT_DIM)
		stat_text.text = "攻 %.0f · 防 %.0f" % [
			pawn.attacker.damage if pawn.attacker != null else 0.0, pawn.defense_stat]
		if pawn.health != null:
			hp_text.text = "%d/%d" % [ceili(pawn.health.current_hp), ceili(pawn.health.max_hp)]
			var r := clampf(pawn.health.ratio(), 0.0, 1.0)
			hp_fill.size = Vector2(90.0 * r, 6.0)
			hp_fill.color = UIStyle.HP_GREEN if r > 0.35 else UIStyle.HP_RED
		if skill_btn != null and is_instance_valid(skill_btn):
			skill_btn.tooltip_text = "可用技能点 %d" % pawn.skill_points
	return card


## 「技能树」小按钮：打开技能树面板（挂在 HUD 顶层，按分组取回）。
func _skill_tree_button(pawn: Pawn) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "技能树"
	btn.custom_minimum_size = Vector2(74.0, 30.0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pts_hint := "可用技能点 %d" % pawn.skill_points if pawn.has_skill_tree() else ""
	if pts_hint != "":
		btn.tooltip_text = pts_hint
	btn.pressed.connect(func() -> void:
		var panel := _skill_tree_panel()
		if panel != null:
			panel.open_for(pawn)
	)
	return btn


## 转职操作区：Lv.5 起出现两个进阶按钮（点击即转）；基础职业未达标给提示；
## 进阶职业显示「已进阶」。
func _promote_area(pawn: Soldier) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if pawn.def == null:
		return box

	if pawn.def.promotes_to.is_empty():
		var done := Label.new()
		done.text = "已进阶"
		done.add_theme_font_size_override("font_size", 11)
		done.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		done.custom_minimum_size = Vector2(64.0, 0.0)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(done)
		return box

	if not pawn.can_promote():
		var lock := Label.new()
		lock.text = "Lv.%d 转职" % GameDefs.PROMOTE_LEVEL
		lock.add_theme_font_size_override("font_size", 11)
		lock.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.8))
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock.custom_minimum_size = Vector2(64.0, 0.0)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.tooltip_text = "等级到达 Lv.%d 后可转职进阶" % GameDefs.PROMOTE_LEVEL
		box.add_child(lock)
		return box

	for adv_id in pawn.def.promotes_to:
		var adv_def: PawnDef = GameDefs.settler_advanced_def(adv_id)
		if adv_def == null:
			continue
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "转职·%s" % adv_def.display_name
		btn.custom_minimum_size = Vector2(96.0, 30.0)
		btn.tooltip_text = "攻 %.0f · 防 %.0f · 血 %.0f（保留等级 / 经验；技能点清空并全额返还，可在新技能树重新分配）" % [
			adv_def.attack_damage, adv_def.defense, adv_def.max_hp]
		var target_id: StringName = adv_id
		btn.pressed.connect(func() -> void:
			if pawn.promote_to(target_id):
				_flash("%s 已转职为「%s」· 技能点已返还" % [pawn.get_display_name(), pawn.def.display_name])
			_refresh()
		)
		box.add_child(btn)
	return box


func _flash(text: String) -> void:
	_flash_label.text = text
	_flash_timer = 2.0
	AudioManager.play_sfx(&"ui_click")
