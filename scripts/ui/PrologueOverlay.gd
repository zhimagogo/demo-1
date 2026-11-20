class_name PrologueOverlay
extends CanvasLayer
## 序章轻量界面。公开节点保留为直接子节点，兼容关卡回归与旧探针。
signal map_requested
signal retry_requested

const STAR_TOTAL := 3
var result_open := false
var _theme: Theme
var _objective_panel: Panel
var _objective_list: VBoxContainer
var _timer_label: Label
var _result_layer: Control
var _result_frame: Panel
var _result_title: Label
var _result_stars: Label
var _result_stats: Label
var _result_hint: Label
var _map_button: Button
var _retry_button: Button
var _rows: Array[Dictionary] = []
var _health_panel: Panel
var _health_bar: ProgressBar
var _health_text: Label
var _skills_text: Label
var _controls: Label
var _capture_bar: ProgressBar
var _capture_label: Label
var _hero: Hero
var _intro: Label
var _result_extras: Array[Control] = []
var _hud_accum := 0.0

func _ready() -> void:
	layer = 20
	add_to_group(&"prologue_overlay")
	_theme = CampaignStyle.theme()
	_build_objective_card()
	_build_player_status()
	_build_result_layer()
	_set_result_visible(false)
	_capture_label.hide()
	_intro = _label("OpeningTitle", "十年流亡，今日归乡。", 28, CampaignStyle.CREAM)
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(_intro, Vector4(-330, -42, 330, 8), Vector2(0.5, 0.44))
	_intro.add_theme_color_override("font_shadow_color", CampaignStyle.INK)
	_intro.add_theme_constant_override("shadow_offset_y", 2)
	var fade := create_tween()
	fade.tween_interval(2.2)
	fade.tween_property(_intro, "modulate:a", 0.0, 1.2)
	fade.tween_callback(_intro.hide)

func _build_objective_card() -> void:
	_objective_panel = Panel.new()
	_objective_panel.name = "ObjectivePanel"
	_objective_panel.add_theme_stylebox_override("panel", CampaignStyle.box(Color(CampaignStyle.INK, 0.92), Color(CampaignStyle.MUTED, 0.2)))
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective_panel)
	_rect(_objective_panel, Vector4(28, 28, 354, 208))
	var chapter := _label("ChapterLabel", "序 章　/　故土残火", 12, CampaignStyle.GOLD)
	_rect(chapter, Vector4(48, 42, 330, 62))
	var title := _label("MissionLabel", "让王旗，再次升起", 23, CampaignStyle.CREAM)
	title.add_theme_font_override("font", CampaignStyle.font(true))
	_rect(title, Vector4(48, 66, 334, 100))
	_objective_list = VBoxContainer.new()
	_objective_list.name = "ObjectiveList"
	_objective_list.theme = _theme
	_objective_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_list.add_theme_constant_override("separation", 12)
	add_child(_objective_list)
	_rect(_objective_list, Vector4(48, 115, 334, 190))
	_timer_label = _label("TimerLabel", "用时 0.0 秒", 13, CampaignStyle.CREAM)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rect(_timer_label, Vector4(-278, 30, -28, 56), Vector2(1, 0))
	_capture_label = _label("CaptureLabel", "", 15, CampaignStyle.GOLD)
	_capture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(_capture_label, Vector4(-210, 30, 210, 66), Vector2(0.5, 0))
	_capture_label.add_theme_stylebox_override("normal", CampaignStyle.box(Color(CampaignStyle.INK, 0.92), Color(CampaignStyle.GOLD, 0.25)))
	_capture_bar = _bar("CaptureProgress", CampaignStyle.GOLD)
	_rect(_capture_bar, Vector4(-135, 70, 135, 74), Vector2(0.5, 0))
	_capture_bar.hide()

func _build_player_status() -> void:
	_health_panel = Panel.new()
	_health_panel.name = "HeroStatus"
	_health_panel.add_theme_stylebox_override("panel", CampaignStyle.box(Color(CampaignStyle.INK, 0.92), Color(CampaignStyle.MUTED, 0.2)))
	_health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_panel)
	_rect(_health_panel, Vector4(28, -126, 300, -28), Vector2(0, 1))
	_health_text = _label("HeroHealthLabel", "归乡者", 14, CampaignStyle.CREAM)
	_rect(_health_text, Vector4(44, -116, 284, -90), Vector2(0, 1))
	_health_bar = _bar("HeroHealth", CampaignStyle.GREEN)
	_rect(_health_bar, Vector4(44, -83, 284, -77), Vector2(0, 1))
	_skills_text = _label("SkillStatus", "", 12, CampaignStyle.GOLD)
	_rect(_skills_text, Vector4(44, -68, 284, -42), Vector2(0, 1))
	_controls = _label("ControlHint", "", 12, CampaignStyle.CREAM)
	_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for item in [_controls, _timer_label]:
		item.add_theme_color_override("font_shadow_color", Color(CampaignStyle.INK, 0.95))
		item.add_theme_constant_override("shadow_offset_x", 1)
		item.add_theme_constant_override("shadow_offset_y", 1)
	_rect(_controls, Vector4(-690, -77, -28, -28), Vector2(1, 1))

func _build_result_layer() -> void:
	_result_layer = Control.new()
	_result_layer.name = "ResultLayer"
	_result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_result_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.045, 0.095, 0.12, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(dim)
	_result_frame = Panel.new()
	_result_frame.name = "ResultFrame"
	_result_frame.add_theme_stylebox_override("panel", CampaignStyle.box(CampaignStyle.PANEL, Color(CampaignStyle.GOLD, 0.4), 6))
	_result_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_layer.add_child(_result_frame)
	_rect(_result_frame, Vector4(-296, -235, 296, 235), Vector2(0.5, 0.5))
	var eyebrow := _center_label("ResultChapter", "序 章　/　故土残火", 12, CampaignStyle.GOLD, Vector4(-250, -207, 250, -181))
	_result_extras.append(eyebrow)
	_result_title = _center_label("ResultTitle", "序 章 完 成", 34, CampaignStyle.CREAM, Vector4(-260, -165, 260, -113))
	var story := _center_label("ResultStory", "一座旧城，一面王旗。王国由此重生。", 14, CampaignStyle.MUTED, Vector4(-260, -105, 260, -73))
	_result_extras.append(story)
	_result_stars = _center_label("ResultStars", "☆ ☆ ☆", 56, CampaignStyle.GOLD, Vector4(-250, -64, 250, 16))
	_result_stats = _center_label("ResultStats", "", 15, CampaignStyle.CREAM, Vector4(-260, 29, 260, 61))
	_result_hint = _center_label("ResultHint", "", 13, CampaignStyle.MUTED, Vector4(-260, 68, 260, 122))
	_map_button = _result_button("MapButton", "返回远征地图　→", Vector4(-252, 148, 30, 196))
	CampaignStyle.primary(_map_button)
	_map_button.pressed.connect(_on_map_pressed)
	_retry_button = _result_button("RetryButton", "再战一次", Vector4(42, 148, 252, 196))
	_retry_button.pressed.connect(_on_retry_pressed)

func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.name = node_name
	item.theme = _theme
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(item)
	return item

func _center_label(node_name: String, text: String, font_size: int, color: Color, rect: Vector4) -> Label:
	var item := _label(node_name, text, font_size, color)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rect(item, rect, Vector2(0.5, 0.5))
	return item

func _bar(node_name: String, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.max_value = 1.0
	bar.show_percentage = false
	var background := CampaignStyle.box(CampaignStyle.INK.lightened(0.12), Color.TRANSPARENT, 2)
	var fill := CampaignStyle.box(color, Color.TRANSPARENT, 2)
	for style in [background, fill]:
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar

func _result_button(node_name: String, text: String, rect: Vector4) -> Button:
	var button := Button.new()
	button.name = node_name
	button.theme = _theme
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	add_child(button)
	_rect(button, rect, Vector2(0.5, 0.5))
	return button

func _rect(control: Control, rect: Vector4, anchor: Vector2 = Vector2.ZERO) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = rect.x
	control.offset_top = rect.y
	control.offset_right = rect.z
	control.offset_bottom = rect.w

func _set_result_visible(shown: bool) -> void:
	for control in [_result_layer, _result_title, _result_stars, _result_stats, _result_hint, _map_button, _retry_button]:
		control.visible = shown
	for control in _result_extras:
		control.visible = shown
	for control in [_objective_panel, _objective_list, _timer_label, _health_panel, _health_bar, _health_text, _skills_text, _controls, _capture_label]:
		control.visible = not shown
	# 标题也是直接子节点，结算时一起收起。
	get_node("ChapterLabel").visible = not shown
	get_node("MissionLabel").visible = not shown
	if shown:
		_capture_bar.hide()
		if _intro != null:
			_intro.hide()

func set_objectives(list: Array) -> void:
	_rebuild_rows(list)
	refresh_objectives(list)

func refresh_objectives(list: Array) -> void:
	if _rows.size() != list.size():
		_rebuild_rows(list)
	for i in mini(list.size(), _rows.size()):
		var item: Dictionary = list[i]
		var row: Dictionary = _rows[i]
		var done := bool(item.get("done", false))
		(row["mark"] as Label).text = "✓" if done else "%02d" % (i + 1)
		(row["mark"] as Label).add_theme_color_override("font_color", CampaignStyle.GREEN if done else CampaignStyle.GOLD)
		(row["text"] as Label).text = String(item.get("text", ""))
		(row["text"] as Label).modulate.a = 0.55 if done else 1.0
		(row["progress"] as Label).text = String(item.get("progress_text", ""))

func set_capture(progress: float, active: bool, ready: bool) -> void:
	_capture_bar.visible = active and not result_open
	_capture_bar.value = progress
	_capture_label.visible = (active or ready) and not result_open
	_capture_label.text = "正在重立王旗…" if active else "匪徒已清剿 · 沿金色路标返回城堡" if ready else ""

func set_timer(seconds: float) -> void:
	_timer_label.text = "用时 %.1f 秒　 /　三星目标 90 秒" % seconds
	_timer_label.add_theme_color_override("font_color", CampaignStyle.MUTED if seconds > 90 else CampaignStyle.CREAM)

func show_result(stars: int, seconds: float, deaths: int) -> void:
	result_open = true
	var cells := PackedStringArray()
	for i in STAR_TOTAL:
		cells.append("★" if i < clampi(stars, 0, STAR_TOTAL) else "☆")
	_result_stars.text = " ".join(cells)
	_result_stats.text = "远征用时 %.1f 秒　 ·　 阵亡 %d 次" % [seconds, deaths]
	_result_hint.text = "✓ 收复故土　　%s 全程未阵亡　　%s 90 秒内完成" % ["✓" if deaths == 0 else "○", "✓" if seconds <= 90 else "○"]
	_set_result_visible(true)
	_map_button.grab_focus()
	# 结算已冻结游戏，动画使用真实时间继续播放。
	_result_stars.modulate.a = 0.0
	var reveal := create_tween().set_ignore_time_scale(true)
	reveal.tween_property(_result_stars, "modulate:a", 1.0, 0.55)

func _rebuild_rows(list: Array) -> void:
	for child in _objective_list.get_children():
		_objective_list.remove_child(child)
		child.queue_free()
	_rows.clear()
	for i in list.size():
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 27
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_objective_list.add_child(row)
		var mark := Label.new()
		mark.custom_minimum_size.x = 22
		mark.add_theme_font_size_override("font_size", 12)
		row.add_child(mark)
		var body := Label.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_font_size_override("font_size", 14)
		row.add_child(body)
		var progress := Label.new()
		progress.add_theme_font_size_override("font_size", 12)
		progress.add_theme_color_override("font_color", CampaignStyle.MUTED)
		row.add_child(progress)
		_rows.append({"row": row, "mark": mark, "text": body, "progress": progress})

func _process(delta: float) -> void:
	if result_open:
		return
	_hud_accum += delta
	if _hud_accum < 0.1:
		return
	_hud_accum = 0.0
	if not is_instance_valid(_hero):
		for unit in get_tree().get_nodes_in_group("player_unit"):
			if is_instance_valid(unit) and unit is Hero:
				_hero = unit as Hero
				break
	if not is_instance_valid(_hero) or _hero.health == null:
		return
	_health_bar.value = _hero.health.current_hp / maxf(1, _hero.health.max_hp)
	_health_text.text = "归乡者　　%d / %d" % [ceili(_hero.health.current_hp), ceili(_hero.health.max_hp)]
	var skills := PackedStringArray()
	for i in mini(2, _hero.hero_def.skills.size()):
		var ratio := _hero.skill_cd_ratio(i)
		var status := "就绪" if ratio >= 1 else "%.0f秒" % ((1.0 - ratio) * _hero.hero_def.skills[i].cooldown)
		skills.append("%s %s %s" % ["Q" if i == 0 else "C", _hero.hero_def.skills[i].display_name, status])
	_skills_text.text = "　".join(skills)
	_controls.text = "WASD 移动　 鼠标指向瞄准　 左键挥剑\nShift 冲刺　 Q/C 技能　 Esc 暂停"
	if SelectionManager.view_mode == SelectionManager.ViewMode.TACTICAL:
		_controls.text = "战术视角 · 右键下令　\nEsc 暂停"
	if _hero.is_dead_flag:
		_health_text.text = "倒下了… 正在返回故土"

func _unhandled_input(event: InputEvent) -> void:
	if result_open and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		map_requested.emit()

func _on_map_pressed() -> void:
	map_requested.emit()

func _on_retry_pressed() -> void:
	retry_requested.emit()
