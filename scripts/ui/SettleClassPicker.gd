class_name SettleClassPicker
extends Control
## ============================================================================
## 流民入住职业选择弹窗（v25）：流民抵达房屋后（settle_class_choice_required），
## 暂停世界弹出四职业卡片，玩家点选一个 → settle_class_chosen → SettlementSystem
## 完成转化（resident_settled）。多名流民同时抵达时按队列逐个处理。
## 打开 = 记住当前倍速并真暂停 + 占用 ui_modal_count（HeroController 据此释放鼠标）；
## 队列清空才恢复倍速。必须点选（无取消语义：流民已抵达，定居不可逆）。
## ============================================================================

var is_open: bool = false

var _queue: Array = []                    # [{ refugee: Node, house: Node }]
var _dim: ColorRect
var _refugee_label: Label
var _cards_box: HBoxContainer
var _previous_speed: float = 1.0


func _ready() -> void:
	name = "SettleClassPicker"
	add_to_group("settle_class_picker")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 关闭时不挡任何点击
	_fill_parent_rect()
	_build_ui()
	EventBus.settle_class_choice_required.connect(_on_choice_required)


## 全矩形铺满父级（含显式清零 offsets：父级已布局时 set_anchors_preset 会按当前
## 0×0 rect 回推 offsets，得到 -width 的 offset_right → 面板永远 0×0 不可见，准星同款坑）。
func _fill_parent_rect() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.66)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.offset_left = 0.0
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
	panel.custom_minimum_size = Vector2(760.0, 360.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(UIStyle.section_title("选 择 觉 醒 职 业", &"home", 18))

	_refugee_label = Label.new()
	_refugee_label.text = "一位流民即将入住，为他选择觉醒职业"
	_refugee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refugee_label.add_theme_font_size_override("font_size", 15)
	_refugee_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	box.add_child(_refugee_label)

	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_cards_box)

	var hint := Label.new()
	hint.text = "选择后流民立即觉醒为该职业小兵；等级到 5 后可在「市民管理」（V）中转职进阶"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(hint)

	_build_class_cards()


## 四职业卡片：字徽 + 职业名 + 三维概览 + 主动技能名；点击即选定。
func _build_class_cards() -> void:
	for class_id in GameDefs.settler_def_ids():
		var d: PawnDef = GameDefs.settler_def(class_id)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(158.0, 176.0)
		var style: StyleBox = UIStyle.panel_style(&"light")
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", UIStyle.panel_style(&"light"))
		btn.add_theme_stylebox_override("pressed", UIStyle.panel_style(&"light"))

		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 8.0
		vb.offset_right = -8.0
		vb.offset_top = 0.0
		vb.offset_bottom = 0.0
		vb.add_theme_constant_override("separation", 4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(vb)

		var badge := IconBadge.new(&"", 42, d.class_color, d.class_icon)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(badge)

		var name_l := Label.new()
		name_l.text = d.display_name
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 18)
		name_l.add_theme_color_override("font_color", d.class_color)
		vb.add_child(name_l)

		var stats := Label.new()
		stats.text = "生命 %d · 攻击 %d\n防御 %d · 移速 %.1f" % [
			int(d.max_hp), int(d.attack_damage), int(d.defense), d.move_speed]
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats.add_theme_font_size_override("font_size", 12)
		stats.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
		vb.add_child(stats)

		var skill_l := Label.new()
		skill_l.text = "技能：%s" % (d.skill.display_name if d.skill != null else "无")
		skill_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_l.add_theme_font_size_override("font_size", 12)
		skill_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		vb.add_child(skill_l)

		var cid: StringName = class_id
		btn.pressed.connect(func() -> void: _choose(cid))
		_cards_box.add_child(btn)


# ============================================================================
# 队列与开 / 关（真暂停 + UI 模态）
# ============================================================================

func _on_choice_required(refugee: Node, house: Node) -> void:
	_queue.append({ "refugee": refugee, "house": house })
	if not is_open:
		_show_next()


## 显示队列中的下一位；队列空 → 收起并恢复倍速。
func _show_next() -> void:
	while not _queue.is_empty():
		var head: Dictionary = _queue[0]
		var refugee: Node = head["refugee"]
		if refugee == null or not is_instance_valid(refugee):
			_queue.pop_front()   # 等待期间已失效（房屋被拆等）：跳过
			continue
		if not is_open:
			_open_modal()
		_refugee_label.text = "流民%s即将入住，为他选择觉醒职业" % _refugee_suffix(refugee)
		return
	if is_open:
		_close_modal()


func _open_modal() -> void:
	is_open = true
	visible = true
	_dim.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_previous_speed = TimeManager.time_scale
	TimeManager.set_speed(0.0)
	SelectionManager.ui_modal_count += 1


func _close_modal() -> void:
	is_open = false
	visible = false
	_dim.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)
	if GameManager.phase != GameManager.Phase.GAME_OVER:
		TimeManager.set_speed(_previous_speed if _previous_speed > 0.0 else 0.0)


## 玩家点选职业：先收起（恢复倍速 / 弹下一位），再广播选择——
## 这样紧随其后的 resident_settled 入驻提示记录到的是正常倍速而非弹窗期的 0。
func _choose(class_id: StringName) -> void:
	if not is_open or _queue.is_empty():
		return
	var head: Dictionary = _queue.pop_front()
	_show_next()   # 队列空 → 收起恢复倍速；还有下一位 → 换人继续（保持暂停）
	AudioManager.play_sfx(&"ui_click")
	EventBus.settle_class_chosen.emit(head["refugee"], head["house"], class_id)


## 流民显示名后缀（无名的流民显示「一位」）。
func _refugee_suffix(refugee: Node) -> String:
	var n: String = refugee.get_display_name() if refugee.has_method("get_display_name") else ""
	return "「%s」" % n if n != "" and n != "流民" else ""
