class_name BuildMenu
extends PanelContainer
## ============================================================================
## 底部建造菜单（v6 图标化）：卡片 = 真实建筑图标（building_*）+ 中文名 + 热键角标 +
## 造价芯片（res_* 小图标 + 数字）。
##
## 状态：资源不足 → 卡片置灰、缺哪种资源的数字变暗红；进入建造模式 → 当前目标卡片
## 金边高亮、标题栏提示「建造模式中」与操作（左键放置 / R 旋转 / Esc 取消）。
##
## 行为：数字键 1..6 直接建造（BuildSystem 全局处理）、pressed → enter_build_mode()、
## get_card_button() 接口与 tutorial 的聚光高亮（读 get_global_rect）全部保持原样。
## 横向预算：卡片 6×104 + 5×8 = 664 ≤ 面板内容宽 668（逻辑像素，宁紧勿溢）。
## ============================================================================

const SAFE_X := 12                 # 左右安全边距（与 TopBar 统一）
const SAFE_BOTTOM := 12            # 底部安全边距
const PANEL_W := 700               # 面板右边界（左对齐 12）
const PANEL_H := 110
const CARD_SIZE := Vector2(104, 64)
const CARD_SEP := 8
const CARD_ICON_PX := 24
const COST_ICON_PX := 12
const CAPTION_IDLE := "建造 · B 开关 · 数字键选建筑（当前造价统一金币）"
const CAPTION_ACTIVE := "建造模式中：%s · 准星对地左键放置 / R 旋转 / B·Esc 取消"

var _cards: Array = []      # [{ btn, def, cost_labels: Dictionary }]
var _build_system: Node = null
var _caption: Label = null
var _row: HBoxContainer = null


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = SAFE_X
	offset_top = -PANEL_H - SAFE_BOTTOM
	offset_right = PANEL_W
	offset_bottom = -SAFE_BOTTOM

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	_caption = Label.new()
	_caption.text = CAPTION_IDLE
	_caption.add_theme_font_size_override("font_size", 13)
	_caption.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_caption)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", CARD_SEP)
	col.add_child(_row)
	_build_system = _find_build_system()

	var defs := GameDefs.building_defs()
	for i in defs.size():
		var def: BuildingDef = defs[i]
		_row.add_child(_make_card(def, i + 1))

	EventBus.resource_changed.connect(func(_id, _amt, _d): _refresh_affordability())
	# v37：建筑落地 / 被拆会改变「已达上限」状态 → 卡片置灰实时跟随（不依赖资源变化，
	# 因为满资源时建造本身不会再触发 resource_changed）。
	EventBus.building_placed.connect(func(_b, _c): _refresh_affordability.call_deferred())
	EventBus.building_removed.connect(func(_b, _c): _refresh_affordability.call_deferred())
	EventBus.build_mode_entered.connect(func(_def): _refresh_selection())
	EventBus.build_mode_exited.connect(func(): _refresh_selection())
	_refresh_affordability()
	_refresh_selection()


func _make_card(def: BuildingDef, slot: int) -> Control:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE      # 只走鼠标/热键，避免点完留下焦点环
	card.tooltip_text = _tooltip_for(def)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 6
	vb.offset_top = 4
	vb.offset_right = -6
	vb.offset_bottom = -4
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 3)

	# ---- 第一行：建筑图标 + 中文名 + 热键角标 ----
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 5)
	top.add_theme_constant_override("alignment", BoxContainer.ALIGNMENT_BEGIN)
	var icon := IconBadge.new(IconDB.building_icon(def.id), CARD_ICON_PX,
		UIStyle.building_accent(def.id), String(def.display_name.substr(0, 1)))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(icon)
	var name_l := Label.new()
	name_l.text = def.display_name
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	top.add_child(_make_keycap(slot, def.hotkey_hint))
	vb.add_child(top)

	# ---- 第二行：造价（小图标 + 数字；HFlow 保证极端情况自动换行不溢出）----
	var cost_row := HFlowContainer.new()
	cost_row.add_theme_constant_override("h_separation", 7)
	cost_row.add_theme_constant_override("v_separation", 1)
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_labels: Dictionary = {}
	for rid in def.cost:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ri := IconRect.new(IconDB.resource_icon(rid), COST_ICON_PX,
			_resource_color(rid), _resource_char(rid))
		ri.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_child(ri)
		var cl := Label.new()
		cl.text = "%d" % def.cost[rid]
		cl.add_theme_font_size_override("font_size", 12)
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(cl)
		cost_labels[rid] = cl
		cost_row.add_child(chip)
	vb.add_child(cost_row)

	card.add_child(vb)
	card.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		if _build_system != null:
			_build_system.enter_build_mode(def))
	card.mouse_entered.connect(func() -> void: AudioManager.play_sfx(&"ui_hover"))
	_cards.append({ "btn": card, "def": def, "cost_labels": cost_labels })
	return card


## 热键角标：小圆角键帽（数字），tooltip 给全完整快捷键（"数字 1 直接建造"）。
func _make_keycap(slot: int, hint: String) -> Control:
	var key := Label.new()
	key.text = "%d" % slot
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", UIStyle.GOLD)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.custom_minimum_size = Vector2(16, 15)
	key.tooltip_text = hint
	key.mouse_filter = Control.MOUSE_FILTER_PASS   # PASS：键帽自己弹提示，点击仍属于卡片
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	var bc := UIStyle.BORDER_GOLD
	sb.border_color = Color(bc.r, bc.g, bc.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	key.add_theme_stylebox_override("normal", sb)
	return key


## 造价小图标配色：统一取 UIStyle 的 v6 亮色表（图标是白前景，颜色全靠 accent 上色；
## GameDefs 的 SADDLE_BROWN / DIM_GRAY 在深木底上对比度不足）。
func _resource_color(rid: StringName) -> Color:
	return UIStyle.resource_color(rid)


## 造价图标缺图时的字徽回退字（木/石/食/金）。
func _resource_char(rid: StringName) -> String:
	match rid:
		&"wood": return "木"
		&"stone": return "石"
		&"food": return "食"
		&"gold": return "金"
	return "?"


## 可负担性 + 数量上限（v37）：卡片整体置灰 + **缺哪种资源的数字变暗红**（比只灰整卡更好定位缺口）；
## 已达 max_count 上限的建筑（酒馆 / 龙园全场唯一）同样置灰，造价芯片改显「满」——
## 已建的那座被拆掉后，building_removed 会重新放开卡片。
func _refresh_affordability() -> void:
	for entry in _cards:
		var def: BuildingDef = entry["def"]
		var at_limit := _at_limit(def)
		(entry["btn"] as Button).disabled = at_limit or not ResourceManager.can_afford(def.cost)
		(entry["btn"] as Button).tooltip_text = _tooltip_for(def)
		var labels: Dictionary = entry["cost_labels"]
		for rid in labels:
			var cl := labels[rid] as Label
			var short: bool = ResourceManager.get_amount(rid) < int(def.cost[rid])
			if at_limit:
				cl.text = "满"
				cl.add_theme_color_override("font_color", UIStyle.DANGER)
			else:
				cl.text = "%d" % int(def.cost[rid])
				cl.add_theme_color_override("font_color",
					UIStyle.DANGER.darkened(0.35) if short else UIStyle.TEXT_MAIN)


## 该建筑是否已达上限（v37）。无 BuildSystem（纯 UI 测试场景 / 已释放实例）时回落静态判定。
func _at_limit(def: BuildingDef) -> bool:
	if def == null or def.max_count <= 0:
		return false
	if is_instance_valid(_build_system):
		return _build_system.build_limit_reached(def)
	return GameDefs.building_at_limit(get_tree(), def)


## 卡片 tooltip：名称 / 说明 / 快捷键；已达上限时追加一行醒目提示。
func _tooltip_for(def: BuildingDef) -> String:
	var text: String = "%s\n%s\n%s" % [def.display_name, def.description, def.hotkey_hint]
	if _at_limit(def):
		text += "\n【已达上限】全场只能建造 %d 座——拆掉后即可重建" % def.max_count
	return text


## 建造模式高亮：当前目标卡片金边 + 金字，标题栏改「建造模式中」提示。
func _refresh_selection() -> void:
	var active := _current_build_def()
	for entry in _cards:
		var btn: Button = entry["btn"]
		var def: BuildingDef = entry["def"]
		if active != null and active.id == def.id:
			btn.add_theme_stylebox_override("normal", _active_style())
			btn.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
		else:
			btn.remove_theme_stylebox_override("normal")
			btn.remove_theme_color_override("font_color")
		btn.modulate = Color(1.0, 0.95, 0.6) if active != null else Color(1, 1, 1)
	if active != null and _caption != null:
		_caption.text = "铺设土路 · 长按左键拖动连续铺设 · 自动连接 · B·Esc 取消" if active.is_road else CAPTION_ACTIVE % active.display_name
		_caption.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	elif _caption != null:
		_caption.text = CAPTION_IDLE
		_caption.add_theme_color_override("font_color", UIStyle.TEXT_DIM)


## 当前建造目标（走 BuildSystem.current_def；无建造模式时为 null）。
func _current_build_def() -> BuildingDef:
	if not SelectionManager.build_mode_active or not is_instance_valid(_build_system):
		return null
	return _build_system.get("current_def") as BuildingDef


## 高亮卡片的 normal 样式：亮金描边 + 稍亮底（内边距与主题 Button 对齐，避免尺寸跳动）。
func _active_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIStyle.BG_PANEL_LIGHT
	sb.border_color = UIStyle.BORDER_GOLD_BRIGHT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(6)
	return sb


## 按建筑 id 取卡片按钮（新手引导高亮「房屋」卡用）。
func get_card_button(building_id: StringName) -> Button:
	for entry in _cards:
		if (entry["def"] as BuildingDef).id == building_id:
			return entry["btn"]
	return null


func _find_build_system() -> Node:
	var arr := get_tree().get_nodes_in_group("build_system")
	return arr[0] if arr.size() > 0 else null
