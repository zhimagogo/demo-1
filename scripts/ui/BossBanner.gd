class_name BossBanner
extends PanelContainer
## 头目横幅（v6 图标化重制）：Boss 存活期间顶部中央显示 warning + boss 真图标、
## 名号与血条；红金配色 + 收敛的脉动（仅图标透明度与描边呼吸，不闪、不遮任务卡）。
## 监听 boss_spawned / boss_died，血量直连 Boss 的 HealthComponent。

const BANNER_BORDER := Color(1.0, 0.72, 0.35, 0.95)   # 红金配色里的「金」

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_fill: StyleBoxFlat
var _boss: Node = null
var _warn_icon: IconBadge
var _boss_icon: IconBadge
var _panel_style: StyleBoxFlat
var _pulse_tween: Tween = null


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.0
	offset_left = -210
	offset_top = 56
	offset_right = 210
	offset_bottom = 124
	visible = false

	# 红金面板：深血红底 + 金描边
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.17, 0.055, 0.05, 0.94)
	_panel_style.border_color = BANNER_BORDER
	_panel_style.set_border_width_all(2)
	_panel_style.set_corner_radius_all(6)
	_panel_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _panel_style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	# 名号行：警告图标（左）+ 头目名（中，红色）+ 头骨图标（右）
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_warn_icon = IconBadge.new(&"warning", 24, Color(1.0, 0.55, 0.35), "袭")
	_warn_icon.tooltip_text = "夜袭头目来袭"
	head.add_child(_warn_icon)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.5))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_name_label.add_theme_constant_override("outline_size", 3)
	head.add_child(_name_label)
	_boss_icon = IconBadge.new(&"boss", 26, UIStyle.GOLD, "首")
	_boss_icon.tooltip_text = "头目：死战不退"
	head.add_child(_boss_icon)
	root.add_child(head)

	# 血条行：hp 图标 + 红条（金描边）
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 5)
	var hp_icon := IconRect.new(&"hp", 14, Color(1.0, 0.45, 0.4), "血")
	hp_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(hp_icon)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.85, 0.2, 0.2)
	_hp_fill.border_color = Color(UIStyle.BORDER_GOLD.r, UIStyle.BORDER_GOLD.g, UIStyle.BORDER_GOLD.b, 0.5)
	_hp_fill.set_border_width_all(1)
	_hp_fill.set_corner_radius_all(3)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0, 13)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	hp_row.add_child(_hp_bar)
	root.add_child(hp_row)

	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_died.connect(_on_boss_died)


func _on_boss_spawned(boss: Node) -> void:
	_boss = boss
	if boss == null or not is_instance_valid(boss):
		return
	var def = boss.get("def")
	var boss_name: String = "夜袭头目"
	if def != null and def.unit_name != "":
		boss_name = def.unit_name
	_name_label.text = "%s 来袭" % boss_name
	var health = boss.get_node_or_null("HealthComponent")
	if health != null:
		_hp_bar.max_value = health.max_hp
		_hp_bar.value = health.current_hp
		if not health.health_changed.is_connected(_on_hp_changed):
			health.health_changed.connect(_on_hp_changed)
	visible = true
	modulate = Color(1, 1, 1, 1)
	_start_pulse()


func _on_hp_changed(current: float, max_hp: float) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current


func _on_boss_died(_boss: Node) -> void:
	if _boss != null and is_instance_valid(_boss):
		var health = _boss.get_node_or_null("HealthComponent")
		if health != null and health.health_changed.is_connected(_on_hp_changed):
			health.health_changed.disconnect(_on_hp_changed)
	_boss = null
	_stop_pulse()
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0.0), 0.6)
	tw.tween_callback(func(): visible = false)


## 收敛的脉动：只让整条横幅透明度在 0.90~1.00 之间、两侧图标在 0.70~1.00 之间呼吸
## （±10% / ±15%），既不闪烁也不放大，避免与任务卡 / 引导卡抢注意力。
func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1, 0.90), 0.9)
	_pulse_tween.parallel().tween_property(_warn_icon, "modulate", Color(1, 1, 1, 0.70), 0.9)
	_pulse_tween.parallel().tween_property(_boss_icon, "modulate", Color(1, 1, 1, 0.70), 0.9)
	_pulse_tween.tween_property(self, "modulate", Color(1, 1, 1, 1.0), 0.9)
	_pulse_tween.parallel().tween_property(_warn_icon, "modulate", Color(1, 1, 1, 1.0), 0.9)
	_pulse_tween.parallel().tween_property(_boss_icon, "modulate", Color(1, 1, 1, 1.0), 0.9)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	if _warn_icon != null:
		_warn_icon.modulate = Color(1, 1, 1, 1)
	if _boss_icon != null:
		_boss_icon.modulate = Color(1, 1, 1, 1)
