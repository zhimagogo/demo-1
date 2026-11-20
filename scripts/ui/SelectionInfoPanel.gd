class_name SelectionInfoPanel
extends PanelContainer
## 右侧选中信息面板（v6 图标化重制）：
## 单选：真图标头像徽章（按选中对象动态取 res_* / building_* / stat_* / boss / shield）+
##       姓名/称号 + 语义标签芯片 + 血条 + 关键属性 +（士兵）三姿态切换（防御/进攻/驻守）
## 多选：图标化类型计数 + 批量姿态按钮。
## 每 0.25s 轮询刷新血量 / 背包（信号太碎，轮询更稳）。

const STANCE_ICONS: Array = [&"shield", &"attack", &"home"]      # 防御 / 进攻 / 驻守
const STANCE_FALLBACKS: Array = ["守", "攻", "驻"]

var _title: Label
var _subtitle: Label
var _icon: IconBadge
var _tags: HBoxContainer            # 语义标签芯片行（图标 + 短文本）
var _hp_bar: ProgressBar
var _hp_label: Label
var _detail: Label
var _stance_row: HBoxContainer
var _stance_buttons: Array = []
var _selected: Array = []
var _accum: float = 0.0
var _hp_fill: StyleBoxFlat   # 本面板专属血条填充色（不污染全局主题）


func _ready() -> void:
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -248
	offset_top = 64
	offset_right = -12
	offset_bottom = 344
	visible = false

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# 头像行
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_icon = IconBadge.new(&"target", 44, UIStyle.GOLD, "?")
	head.add_child(_icon)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_box.add_child(_subtitle)
	head.add_child(name_box)
	root.add_child(head)

	# 语义标签芯片行（图标 + 短文本，按选中对象重建）
	_tags = HBoxContainer.new()
	_tags.add_theme_constant_override("separation", 10)
	root.add_child(_tags)

	# 血条（专属 fill 样式：可随血量变色而不动全局主题）
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = UIStyle.HP_GREEN
	_hp_fill.set_corner_radius_all(3)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 16)
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	root.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 12)
	_hp_label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	root.add_child(_hp_label)

	root.add_child(HSeparator.new())

	# 属性明细
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail)

	# 姿态按钮行（士兵才有）
	_stance_row = HBoxContainer.new()
	_stance_row.add_theme_constant_override("separation", 6)
	root.add_child(_stance_row)
	var stance_names := ["防御", "进攻", "驻守"]
	var stance_tips := [
		"守城墙：视野 16m，不追 34m 外的敌人",
		"主动出击：视野 30m，追到天涯海角",
		"站桩守位：只打 9m 内的敌人，不离锚点 9m",
	]
	for i in 3:
		var b := Button.new()
		b.text = stance_names[i]
		b.tooltip_text = stance_tips[i]
		b.custom_minimum_size = Vector2(66, 30)
		b.toggle_mode = true
		# 真图标挂在按钮上；素材缺失时 icon 为 null，按钮自动退化为纯文字
		var stance_tex := IconDB.get_texture(STANCE_ICONS[i])
		if stance_tex != null:
			b.icon = stance_tex
			b.add_theme_constant_override("icon_max_width", 16)
		var idx := i
		b.pressed.connect(func() -> void: _set_stance(idx))
		_stance_row.add_child(b)
		_stance_buttons.append(b)

	EventBus.selection_changed.connect(_on_selection_changed)


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		_refresh_dynamic()


func _on_selection_changed(selected: Array) -> void:
	_selected = selected.filter(func(p): return p != null and is_instance_valid(p))
	if _selected.is_empty():
		visible = false
		return
	# v17 去冗余：主角信息卡的唯一来源是常驻的 HeroPanel（头像/称号/生命/经验/连招/技能）。
	# 单选主角时本面板不再弹第二张重复卡（否则生命/经验/等级/击杀会同屏印两遍）。
	# 多选（含主角的编队框选）仍走下方聚合视图，展示的是计数而非重复属性。
	if _selected.size() == 1 and _selected[0] is Hero:
		visible = false
		return
	visible = true
	if _selected.size() == 1:
		_refresh_single(_selected[0])
	else:
		_refresh_multi()


func _refresh_single(p) -> void:
	# get_display_name 是 Pawn 的方法（内部读 def.unit_name）；直接在 def 资源上调用会报错
	var display: String = p.get_display_name() if p.has_method("get_display_name") else "单位"
	var sub := ""
	# 按选中对象取真图标：单位 → stat_*，建筑 → building_*，资源点 → res_*，主城 → shield/crown
	var icon_id: StringName = &"target"
	var icon_fb := "选"
	var accent: Color = UIStyle.GOLD
	var tags: Array = []

	if p is Hero:
		var hero: Hero = p
		icon_id = &"stat_hero"
		icon_fb = "侠"
		accent = Color(1.0, 0.82, 0.35)
		display = "%s · Lv.%d" % [display, hero.level]
		sub = "「%s」 · 击杀 %d" % [hero.hero_title(), hero.kill_count]
		tags = [
			_tag(&"stat_hero", "主角", accent, "侠"),
			_tag(&"attack", "近战", accent, "攻"),
			_tag(&"xp", "Lv.%d" % hero.level, UIStyle.XP_BLUE, "验"),
		]
	elif p is Soldier:
		var soldier: Soldier = p
		var ranged: bool = soldier.def != null and soldier.def.attack_kind == PawnDef.AttackKind.RANGED
		icon_id = &"stat_soldier"
		icon_fb = "兵"
		accent = Color(0.5, 0.62, 0.92)
		sub = "姿态可在下方切换"
		tags = [
			_tag(&"unit_ranged" if ranged else &"unit_melee", "远程" if ranged else "近战",
				accent, "远" if ranged else "近"),
			_tag(&"stat_soldier", "士兵", accent, "兵"),
			_tag(&"xp", "Lv.%d" % soldier.level, UIStyle.XP_BLUE, "级"),
			_tag(STANCE_ICONS[int(soldier.stance)], Pawn.STANCE_NAMES[int(soldier.stance)],
				UIStyle.GOLD, STANCE_FALLBACKS[int(soldier.stance)]),
		]
	elif p is Colonist:
		icon_id = &"stat_pop"
		icon_fb = "民"
		accent = Color(0.6, 0.82, 0.9)
		sub = "搬运背包 %d / %d" % [p.carried_amount, p.def.carry_capacity]
		tags = [
			_tag(&"stat_pop", "村民", accent, "民"),
			_tag(&"carry", "背包 %d/%d" % [p.carried_amount, p.def.carry_capacity], accent, "包"),
		]
	elif p is Refugee:
		icon_id = &"stat_pop"
		icon_fb = "流"
		accent = Color(0.75, 0.9, 1.0)
		sub = "正在前往空房定居"
		tags = [_tag(&"stat_pop", "流民", accent, "流"), _tag(&"home", "寻找空房", accent, "家")]
	elif p is Raider:
		var is_boss: bool = p.def != null and p.def.is_boss
		icon_id = &"boss" if is_boss else &"stat_enemy"
		icon_fb = "首" if is_boss else "敌"
		accent = UIStyle.DANGER if is_boss else Color(0.9, 0.35, 0.3)
		sub = "夜袭头目" if is_boss else "城外野怪"
		if p.def != null and p.def.unit_name != "":
			display = p.def.unit_name
		tags = [_tag(icon_id, "头目" if is_boss else "野怪", accent, icon_fb)]
		if is_boss:
			tags.append(_tag(&"warning", "死战不退", accent, "警"))
	elif p is Building:
		var bdef: BuildingDef = p.def
		icon_id = IconDB.building_icon(bdef.id) if bdef != null else &"tool_hammer"
		icon_fb = "建"
		accent = UIStyle.building_accent(bdef.id) if bdef != null else UIStyle.GOLD
		display = bdef.display_name if bdef != null and bdef.display_name != "" else "建筑"
		sub = "城内建筑"
		tags = [_tag(icon_id, display, accent, "建")]
		# v22：酒馆展示疗伤光环参数（箭塔「自动索敌」标签已随箭塔移除）
		if bdef != null and bdef.is_tavern:
			tags.append(_tag(&"hp", "小兵疗伤 +%d/s" % int(bdef.heal_per_sec), accent, "愈"))
	elif p is ResourceNode:
		var res_id: StringName = p.yield_resource
		icon_id = IconDB.resource_icon(res_id)
		icon_fb = "木" if res_id == &"wood" else "石"
		accent = Color(0.45, 0.78, 0.42) if res_id == &"wood" else Color(0.62, 0.62, 0.66)
		display = "木材资源点" if res_id == &"wood" else "石矿资源点"
		sub = "右键下令采集（战术俯瞰）"
		tags = [
			_tag(icon_id, "木材" if res_id == &"wood" else "石料", accent, icon_fb),
			_tag(&"carry", "单次 %d" % p.yield_amount, accent, "采"),
		]
	elif p.is_in_group("base_core"):
		icon_id = &"shield"
		icon_fb = "城"
		accent = UIStyle.GOLD
		display = "主城"
		sub = "城镇核心 · 失守即游戏结束"
		tags = [_tag(&"shield", "主城", accent, "城"), _tag(&"crown", "核心", accent, "冠")]

	_icon.set_badge(icon_id, 44, accent, icon_fb)
	_title.text = display
	_subtitle.text = sub
	_set_tags(tags)
	_refresh_dynamic()


func _refresh_multi() -> void:
	var counts := {}
	var order: Array = []
	for p in _selected:
		var key: String = "单位"
		if p is Hero:
			key = "主角"
		elif p is Soldier:
			key = "士兵"
		elif p is Colonist:
			key = "村民"
		elif p is Raider:
			key = "野怪"
		if not counts.has(key):
			counts[key] = 0
			order.append(key)
		counts[key] += 1
	var parts: Array = []
	var tags: Array = []
	for key in order:
		parts.append("%s×%d" % [key, counts[key]])
		tags.append(_tag(_icon_for_unit_key(key), "%s×%d" % [key, counts[key]],
			_color_for_unit_key(key), String(key).substr(0, 1)))
	_title.text = "选中 %d 个单位" % _selected.size()
	_subtitle.text = " · ".join(parts)
	_icon.set_badge(&"stat_pop", 44, Color(0.6, 0.65, 0.7), "队")
	_set_tags(tags)
	_hp_bar.visible = false
	_hp_label.visible = false
	_detail.text = "右键下达命令（战术俯瞰）\n士兵可用下方按钮批量切换姿态"
	_refresh_dynamic()


func _refresh_dynamic() -> void:
	if _selected.size() == 1:
		var p = _selected[0]
		var h = p.get("health")
		if h != null and p.get("def") != null:
			_hp_bar.visible = true
			_hp_label.visible = true
			_hp_bar.max_value = h.max_hp
			_hp_bar.value = h.current_hp
			var ratio: float = h.ratio()
			_hp_fill.bg_color = UIStyle.hp_fill_color(ratio)
			_hp_label.text = "生命 %d / %d" % [int(h.current_hp), int(h.max_hp)]
		elif p is ResourceNode:
			# 资源点没有 HealthComponent：血条位显示剩余储量，读起来更直观
			var left_ratio: float = p.remaining_ratio()
			_hp_bar.visible = true
			_hp_label.visible = true
			_hp_bar.max_value = 1.0
			_hp_bar.value = left_ratio
			_hp_fill.bg_color = UIStyle.hp_fill_color(left_ratio)
			_hp_label.text = "剩余储量 %.0f%%" % (left_ratio * 100.0)
			_detail.text = "采集一次获得 %d，储量耗尽后消失" % p.yield_amount
			_stance_row.visible = false
			return
		# 属性明细
		var lines: Array = []
		var dmg = p.get("def").attack_damage if p.get("def") != null else null
		if p is Hero:
			var hero: Hero = p
			lines.append("伤害 %.0f（等级 ×%.2f）" % [hero.def.attack_damage * hero.damage_mult(), hero.damage_mult()])
			lines.append("经验 %d / %d" % [hero.xp, hero.xp_to_next()])
		elif p is Soldier:
			# v20 属性系统：小兵六维面板（等级/经验 + 攻/防/移/暴实时值，含升级成长）
			var xp_txt := "经验 %d / %d" % [p.xp, p.xp_to_next()]
			if p.level >= Pawn.MAX_LEVEL:
				xp_txt = "经验 MAX"
			lines.append("等级 Lv.%d · %s" % [p.level, xp_txt])
			lines.append("攻击 %.0f · 防御 %.0f · 移速 %.1f"
				% [p.attacker.damage, p.defense_stat, p.move_speed])
			lines.append("暴击 %.0f%%（暴伤 ×%.1f）" % [p.crit_chance() * 100.0, p.crit_multiplier()])
		elif p is Raider:
			# v20.3：怪物也有六维——野怪面板与小兵同构（无经验行，怪物不升级）
			lines.append("攻击 %.0f · 防御 %.0f · 移速 %.1f"
				% [p.attacker.damage, p.defense_stat, p.move_speed])
			lines.append("暴击 %.0f%%（暴伤 ×%.1f）" % [p.crit_chance() * 100.0, p.crit_multiplier()])
			if p.def != null and p.def.is_boss:
				lines.append("死战不退 · 全队集火（酒馆疗伤备战）")
		elif dmg != null:
			lines.append("攻击 %.0f · 射程 %.1f" % [float(dmg), float(p.get("def").attack_range)])
		var sp = p.get("move_speed")
		if sp != null and not (p is Soldier) and not (p is Raider):
			lines.append("移速 %.1f" % float(sp))
		# v19 职业技能行：技能名 + 冷却状态（就绪 / 剩余 CD 实时刷新）
		# v25.1：技能树未点亮「职业技」根节点时显示未解锁（战斗中不会施放）
		var pd = p.get("def")
		if pd != null and pd.get("skill") != null:
			var sk: PawnSkillDef = pd.skill
			var unlocked: bool = true
			if p.has_method("combat_skill_unlocked"):
				unlocked = p.call("combat_skill_unlocked")
			if not unlocked:
				lines.append("技能 %s · 未解锁（技能树点亮）" % sk.display_name)
			else:
				var comp = p.get("skill_comp")
				var state_txt := "未装备"
				if comp != null:
					var left: float = float(comp.call("cooldown_left"))
					state_txt = "就绪" if left <= 0.0 else "冷却 %.0fs" % left
				lines.append("技能 %s · CD %.0fs（%s）" % [sk.display_name, sk.cooldown, state_txt])
		if p is Colonist and p.def.carry_capacity > 0:
			lines.append("背包 %d / %d" % [p.carried_amount, p.def.carry_capacity])
		_detail.text = "\n".join(lines)
		_stance_row.visible = p is Soldier
		if p is Soldier:
			_sync_stance_buttons(int(p.stance))
	else:
		var has_soldier: bool = false
		var stance: int = -1
		for p in _selected:
			if p is Soldier:
				has_soldier = true
				stance = p.stance if stance == -1 else stance
		_stance_row.visible = has_soldier
		if has_soldier:
			_sync_stance_buttons(stance)


## 标签芯片数据：图标 id + 文本 + 配色 + 缺图回退字。
func _tag(id: StringName, text: String, color: Color, fb: String) -> Dictionary:
	return { "id": id, "text": text, "color": color, "fb": fb }


## 重建标签芯片行（仅在选中变化时调用，不参与 0.25s 轮询）。
func _set_tags(tags: Array) -> void:
	for c in _tags.get_children():
		_tags.remove_child(c)
		c.queue_free()
	for t in tags:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		var icon := IconRect.new(t["id"], 14, t["color"], t["fb"])
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(icon)
		var lbl := Label.new()
		lbl.text = String(t["text"])
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", t["color"])
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(lbl)
		_tags.add_child(chip)


func _icon_for_unit_key(key: String) -> StringName:
	match key:
		"主角": return &"stat_hero"
		"士兵": return &"stat_soldier"
		"村民": return &"stat_pop"
		"野怪": return &"stat_enemy"
	return &"target"


func _color_for_unit_key(key: String) -> Color:
	match key:
		"主角": return Color(1.0, 0.82, 0.35)
		"士兵": return Color(0.5, 0.62, 0.92)
		"村民": return Color(0.6, 0.82, 0.9)
		"野怪": return UIStyle.DANGER
	return UIStyle.TEXT_MAIN


func _sync_stance_buttons(active: int) -> void:
	for i in _stance_buttons.size():
		(_stance_buttons[i] as Button).button_pressed = i == active


func _set_stance(idx: int) -> void:
	var applied: bool = false
	for p in _selected:
		if p is Soldier and is_instance_valid(p):
			(p as Soldier).stance = idx
			if idx == Pawn.Stance.HOLD:
				(p as Soldier).hold_anchor = (p as Node3D).global_position
			applied = true
	if applied:
		AudioManager.play_sfx(&"ui_click")
		_sync_stance_buttons(idx)
		if _selected.size() == 1 and _selected[0] is Soldier:
			_refresh_single(_selected[0])   # 姿态芯片实时跟着按钮走
		EventBus.game_message.emit("士兵姿态：%s" % Pawn.STANCE_NAMES[idx], Color(0.75, 0.85, 1.0))
