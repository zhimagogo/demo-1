class_name DragonMenu
extends Control
## ============================================================================
## 驯龙界面（v26）：对龙园按 E 弹出（EventBus.dragon_menu_requested）。
## - 每条龙一张卡：字徽 / 名称 / 描述 / 属性与技能说明 + 操作按钮——
##   未解锁 →「解锁 · N 金币」（金币不足置灰）；已解锁 →「出战 / 召回」；
##   出战中阵亡等待复苏 → 显示复苏倒计时；
## - 打开 = 真暂停 + ui_modal_count（第三人称自动释放鼠标）；Esc / 「离开」关闭；
## - 数据全部来自 GameDefs.dragon_defs()（新龙加表即自动出现在这里）。
## ============================================================================

var is_open: bool = false

var _dim: ColorRect
var _cards_box: VBoxContainer
var _previous_speed: float = 1.0
var _card_states: Array = []     # [{def, btn, status}]（刷新按钮可用态 / 状态文字用）


func _ready() -> void:
	name = "DragonMenu"
	add_to_group("dragon_menu")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build_ui()
	EventBus.dragon_menu_requested.connect(_on_menu_requested)
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.dragon_deploy_changed.connect(_on_deploy_changed)


func _on_menu_requested(_garden: Node) -> void:
	open()


func _on_resource_changed(_id: StringName, _amt: int, _d: int) -> void:
	if is_open:
		_refresh_states()


func _on_deploy_changed(_id: StringName, _pet: Node) -> void:
	if is_open:
		_refresh_states()


# ============================================================================
# 开 / 关（真暂停 + UI 模态，同 CitizenMenu 范式）
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
	_rebuild_cards()
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
	if event.is_action_pressed("cancel"):
		close()
		get_viewport().set_input_as_handled()


# ============================================================================
# UI 构建
# ============================================================================

func _dragon_system() -> DragonSystem:
	return get_tree().get_first_node_in_group("dragon_system") as DragonSystem


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.0, 0.0, 0.66)
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
	panel.custom_minimum_size = Vector2(620.0, 420.0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(UIStyle.section_title("龙 园 · 驯 龙", &"skill_flame", 18))

	var subtitle := Label.new()
	subtitle.text = "花金币驯服巨龙。驯服后的巨龙是编外战斗伙伴：不占 4 人编队位，始终跟随主角，\n并攻击主角攻击的目标（集火令 T 优先）。同一时刻只能带一条龙出战。"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(subtitle)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	box.add_child(_cards_box)

	var close_btn := Button.new()
	close_btn.text = "离 开（Esc）"
	close_btn.custom_minimum_size = Vector2(180.0, 34.0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


func _rebuild_cards() -> void:
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.free()
	_card_states.clear()
	for d in GameDefs.dragon_defs():
		var card := _make_card(d)
		_cards_box.add_child(card)
	_refresh_states()


## 单条龙的驯龙卡：左字徽 + 中间信息（名 / 描述 / 技能）+ 右侧操作按钮。
func _make_card(d: DragonDef) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIStyle.panel_style(&"light"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)

	var badge := IconBadge.new(&"skill_flame", 40, d.class_color, "龙")
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)
	var name_l := Label.new()
	name_l.text = d.display_name
	name_l.add_theme_font_size_override("font_size", 16)
	name_l.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	name_row.add_child(name_l)
	var hp_l := Label.new()
	hp_l.text = "生命 %.0f · 攻击 %.0f · 防御 %.0f" % [d.max_hp, d.fireball_damage, d.defense]
	hp_l.add_theme_font_size_override("font_size", 12)
	hp_l.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	hp_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(hp_l)

	var desc_l := Label.new()
	desc_l.text = d.description
	desc_l.add_theme_font_size_override("font_size", 12)
	desc_l.add_theme_color_override("font_color", Color(UIStyle.TEXT_DIM, 0.9))
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_l)

	var skill_l := Label.new()
	skill_l.text = "【%s】%s" % [d.breath_name, d.skill_desc]
	skill_l.add_theme_font_size_override("font_size", 12)
	skill_l.add_theme_color_override("font_color", Color(1.0, 0.62, 0.35))
	skill_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_l.custom_minimum_size = Vector2(0.0, 30.0)
	vbox.add_child(skill_l)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120.0, 34.0)
	# 按下时按「当前状态」分发（未驯服 → 解锁；待命 → 出战；出战中 → 召回），
	# 连接只建立一次，_refresh_states 只改文字与可用态。
	btn.pressed.connect(_on_card_pressed.bind(d.id))
	side.add_child(btn)
	var status := Label.new()
	status.text = ""
	status.add_theme_font_size_override("font_size", 11)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	side.add_child(status)

	_card_states.append({"def": d, "btn": btn, "status": status})
	return card


## 刷新每张卡的操作按钮（解锁价 / 可负担性 / 出战态）与状态文字（含复苏倒计时）。
func _refresh_states() -> void:
	var ds := _dragon_system()
	if ds == null:
		return
	for entry in _card_states:
		var d: DragonDef = entry["def"]
		var btn: Button = entry["btn"]
		var status: Label = entry["status"]
		if not ds.is_unlocked(d.id):
			btn.text = "解锁 · %d 金币" % d.unlock_cost
			btn.disabled = not ResourceManager.has(GameDefs.GOLD, d.unlock_cost)
			status.text = "未驯服"
			status.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		elif ds.deployed_id == d.id:
			btn.text = "召回"
			btn.disabled = false
			if ds.current_pet() != null:
				status.text = "出战中 · 跟随主角"
				status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
			else:
				status.text = "倒下了 · %.0f 秒后复苏" % ceilf(maxf(ds.respawn_left, 0.0))
				status.add_theme_color_override("font_color", UIStyle.DANGER)
		else:
			btn.text = "出战"
			btn.disabled = false
			status.text = "已驯服 · 待命"
			status.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)


## 卡片按钮分发：未驯服 → 解锁；待命 → 出战；出战中 → 召回。
func _on_card_pressed(dragon_id: StringName) -> void:
	var ds := _dragon_system()
	if ds == null:
		return
	if not ds.is_unlocked(dragon_id):
		if not ds.try_unlock(dragon_id):
			AudioManager.play_sfx(&"build_error")
	elif ds.deployed_id == dragon_id:
		ds.undeploy()
	else:
		ds.deploy(dragon_id)
	_refresh_states()


func _process(_delta: float) -> void:
	# 复苏倒计时文字需要走表（暂停中 TimeManager 停走，但 respawn_left 由 DragonSystem
	# 的 _process 推进——它同样被 time_scale 暂停，这里只在开表时刷新读数即可）
	if is_open:
		var ds := _dragon_system()
		if ds != null and ds.respawn_left > 0.0:
			_refresh_states()
