class_name TutorialOverlay
extends Control
## ============================================================================
## 新手引导浮层（v6 图标化）：聚光灯遮罩 + 步骤引导卡。
## · 遮罩用 draw_rect 画四块暗色矩形「挖洞」，mouse_filter=IGNORE，
##   完全不拦截游戏操作（玩家照常点选 / 下令 / 建造）；
## · 步骤卡停在屏幕右中：tutorial 图标徽章 + 标题 + n/9 步骤徽章 + 步骤进度条 +
##   信息步的「下一步 / 开始经营」按钮（play 图标）与「跳过引导」（快进图标）；
## · 焦点高亮三类目标：建造菜单卡片（UI 矩形）、世界单位（主角 / 最近资源点，
##   相机投影到屏幕，带脉冲金圈）、无焦点（全屏压暗）。
## 注意：遮罩 IGNORE、卡片 PASS（按钮自身 STOP）是与玩法交互的契约，不要改。
## ============================================================================

const DIM := Color(0.0, 0.0, 0.0, 0.45)     # 有焦点时的遮罩暗度（洞外区域）
const DIM_SOFT := Color(0.0, 0.0, 0.0, 0.28) # 无焦点（信息步）用轻压暗——别把要讲解的小镇整个压黑
const HOLE_PAD := 10.0                       # 焦点矩形外扩边距
const CARD_W := 360.0

var system: TutorialSystem = null

var _card: PanelContainer
var _title: Label
var _step_count: Label
var _dots: HBoxContainer
var _dot_styles: Array = []
var _desc: Label
var _hint: Label
var _hint_icon: IconRect
var _next_btn: Button
var _skip_btn: Button
var _pulse: float = 0.0
var _focus_rect := Rect2()                   # 屏幕空间焦点矩形（无面积=全屏压暗）
var _focus_world := false                    # 世界投影目标（额外画脉冲圈）
var _focus_center := Vector2.ZERO


func _ready() -> void:
	# 注意：必须用 set_anchors_and_offsets_preset —— set_anchors_preset 只动锚点、
	# 会按「保持当前矩形」反推 offsets，此时控件尚未布局（size=0）→ 永远是 0 尺寸。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_card()
	EventBus.tutorial_step_changed.connect(_on_step_changed)
	EventBus.tutorial_finished.connect(_on_finished)
	EventBus.tutorial_skipped.connect(_on_finished)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = -CARD_W - 24.0
	_card.offset_right = -24.0
	_card.offset_top = -138.0
	_card.offset_bottom = 138.0
	# PASS：卡片背景不吞点击——聚光目标（主角/资源点）漂到卡片后面时，
	# 玩家仍能透过卡片空白处点到世界；按钮自身是 STOP 不受影响。
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	# 卡片样式：暗金描边 + 略深的底，与「临时浮层」的身份匹配
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.11, 0.09, 0.07, 0.96)
	csb.border_color = UIStyle.BORDER_GOLD
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(8)
	csb.set_content_margin_all(12)
	_card.add_theme_stylebox_override("panel", csb)
	add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_card.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var icon := IconBadge.new(&"tutorial", 26, UIStyle.GOLD, "导")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", UIStyle.BORDER_GOLD_BRIGHT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_title)
	_step_count = Label.new()
	_step_count.add_theme_font_size_override("font_size", 13)
	_step_count.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_step_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_step_count)
	box.add_child(head)

	# 步骤进度条：每步一段，走过的段变金——扫一眼就知道还剩几步
	_dots = HBoxContainer.new()
	_dots.add_theme_constant_override("separation", 3)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_dots)

	box.add_child(HSeparator.new())

	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(CARD_W - 48.0, 0)
	box.add_child(_desc)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	_skip_btn = Button.new()
	_skip_btn.text = "跳过引导 (Esc)"
	_skip_btn.tooltip_text = "跳过剩余步骤（顶栏「？」可随时重播）"
	_skip_btn.custom_minimum_size = Vector2(104, 32)
	_apply_button_icon(_skip_btn, &"fast_forward")
	_skip_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		_skip_btn.release_focus()
		if system != null:
			system.skip())
	foot.add_child(_skip_btn)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)

	_next_btn = Button.new()
	_next_btn.custom_minimum_size = Vector2(124, 34)
	_apply_button_icon(_next_btn, &"play")
	_next_btn.pressed.connect(func() -> void:
		AudioManager.play_sfx(&"ui_click")
		_next_btn.release_focus()
		if system != null:
			system.advance())
	foot.add_child(_next_btn)

	# 「等你操作…」提示：准星图标 + 文字（比裸符号更明确）
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 4)
	hint_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_icon = IconRect.new(&"target", 15, UIStyle.GOLD, "等")
	_hint_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_row.add_child(_hint_icon)
	_hint = Label.new()
	_hint.text = "等你操作…"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", UIStyle.GOLD)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_row.add_child(_hint)
	foot.add_child(hint_row)
	box.add_child(foot)


## 按钮图标：素材缺失时保持 null（按钮自动退化为纯文字，不留空洞）。
func _apply_button_icon(btn: Button, id: StringName) -> void:
	var tex := IconDB.get_texture(id)
	if tex != null:
		btn.icon = tex
		btn.add_theme_constant_override("icon_max_width", 16)


# ---- 事件 ----

func _on_step_changed(index: int, total: int) -> void:
	if system == null:
		system = _find_system()
	if system == null or index < 0 or index >= system.steps.size():
		return
	var s = system.steps[index]
	_title.text = s.title
	_step_count.text = "%d/%d" % [index + 1, total]
	_desc.text = s.desc
	var info: bool = not s.wait_input
	_next_btn.visible = info
	_hint.visible = not info
	_hint_icon.visible = not info
	_next_btn.text = s.button if s.button != "" else "下一步"
	_paint_dots(index, total)
	visible = true
	# 步骤切换时卡片金色闪一下，提示视线转移
	var tw := create_tween()
	tw.tween_property(_card, "modulate", Color(1.35, 1.2, 0.85), 0.1)
	tw.tween_property(_card, "modulate", Color(1, 1, 1), 0.3)


func _on_finished() -> void:
	visible = false


## 按当前步重建 / 着色步骤进度条。
func _paint_dots(index: int, total: int) -> void:
	if total != _dot_styles.size():
		for c in _dots.get_children():
			_dots.remove_child(c)
			c.queue_free()
		_dot_styles.clear()
		for i in total:
			var seg := Panel.new()
			seg.custom_minimum_size = Vector2(0, 4)
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(2)
			seg.add_theme_stylebox_override("panel", sb)
			_dots.add_child(seg)
			_dot_styles.append(sb)
	for i in _dot_styles.size():
		var sb: StyleBoxFlat = _dot_styles[i]
		if i < index:
			sb.bg_color = Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.55)   # 已走过
		elif i == index:
			sb.bg_color = UIStyle.BORDER_GOLD_BRIGHT                                      # 当前步
		else:
			sb.bg_color = Color(0.30, 0.26, 0.19, 0.85)                                   # 未到


# ---- 每帧解析焦点 + 重绘 ----

func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * 2.4, TAU)
	_resolve_focus()
	queue_redraw()


func _resolve_focus() -> void:
	_focus_world = false
	_focus_rect = Rect2()
	if system == null or system.state != TutorialSystem.State.RUNNING:
		return
	var s = system.current()
	var kind: String = s.focus.get("kind", "none")
	match kind:
		"ui_build_card":
			var btn := _find_build_card(String(s.focus.get("arg", "house")))
			if btn != null and btn.is_visible_in_tree():
				_focus_rect = btn.get_global_rect().grow(HOLE_PAD)
		"world":
			var pos := _world_focus_screen_pos(String(s.focus.get("arg", "hero")))
			if pos != Vector2.INF:
				_focus_world = true
				_focus_center = pos
				_focus_rect = Rect2(pos - Vector2(72.0, 72.0), Vector2(144.0, 144.0))
	# 半出屏的焦点矩形裁剪回屏内；完全出屏则退化为全屏压暗
	if _focus_rect.has_area():
		_focus_rect = _focus_rect.intersection(Rect2(Vector2.ZERO, size))
		if not _focus_rect.has_area():
			_focus_rect = Rect2()
			_focus_world = false


func _find_system() -> TutorialSystem:
	if not is_inside_tree():
		return null   # 场景重载拆卸期：EventBus 信号仍可能到达
	return get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem


func _find_build_card(building_id: String) -> Button:
	# 沿祖先找到持有 build_menu 的 HUD 根（HUD 无 class_name，按属性识别）
	var n: Node = self
	while n != null:
		var menu = n.get("build_menu")
		if menu != null and menu.has_method("get_card_button"):
			return menu.call("get_card_button", StringName(building_id))
		n = n.get_parent()
	return null


func _world_focus_screen_pos(selector: String) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.INF
	var target: Node3D = null
	var lift := 1.5
	if selector == "hero":
		for n in get_tree().get_nodes_in_group("player_unit"):
			if n is Hero and is_instance_valid(n):
				target = n as Node3D
				break
	elif selector == "resource":
		# 高亮距主角最近的资源点（玩家视线最顺的位置）。
		# 抬升量按资源实际高度自适应：必须落在拾取盒内（盒顶 = mesh 高 +0.6），
		# 固定 +2.5 对矮石头会悬在盒外——聚光点就成了点不中的「假目标」。
		var hero: Node3D = null
		for n in get_tree().get_nodes_in_group("player_unit"):
			if n is Hero:
				hero = n as Node3D
				break
		var origin: Vector3 = hero.global_position if hero != null else Vector3.ZERO
		var best: float = INF
		for n in get_tree().get_nodes_in_group("resource_node"):
			if n is Node3D and is_instance_valid(n):
				var node3d := n as Node3D
				var d: float = node3d.global_position.distance_to(origin)
				if d < best:
					best = d
					target = node3d
		if target != null and "mesh_size" in target:
			var mh: float = (target.get("mesh_size") as Vector3).y
			lift = clampf(mh + 0.3, 1.2, 2.5)
		else:
			lift = 1.5
	# v21：兵营聚光选择器已随兵营移除（原 recruit 步改为定居信息步，不再需要世界聚光）
	if target == null:
		return Vector2.INF
	var wp: Vector3 = target.global_position + Vector3(0, lift, 0)
	if cam.is_position_behind(wp):
		return Vector2.INF
	return cam.unproject_position(wp)


# ---- 绘制 ----

func _draw() -> void:
	var vr := Rect2(Vector2.ZERO, size)
	if not _focus_rect.has_area():
		draw_rect(vr, DIM_SOFT)
		return
	var r := _focus_rect
	# 四块暗矩形围出「聚光灯洞」
	draw_rect(Rect2(vr.position, Vector2(r.position.x - vr.position.x, vr.size.y)), DIM)
	draw_rect(Rect2(Vector2(r.end.x, vr.position.y), Vector2(vr.end.x - r.end.x, vr.size.y)), DIM)
	draw_rect(Rect2(Vector2(r.position.x, vr.position.y), Vector2(r.size.x, r.position.y - vr.position.y)), DIM)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y), Vector2(r.size.x, vr.end.y - r.end.y)), DIM)
	# 洞口柔化：紧贴焦点的两层极淡描边，让硬切边过渡得更自然（仍不遮挡内容）
	var a := 0.55 + 0.45 * sin(_pulse)
	draw_rect(r.grow(2.0), Color(UIStyle.GOLD, 0.10), false, 3.0)
	draw_rect(r.grow(5.0), Color(UIStyle.GOLD, 0.05), false, 3.0)
	# 脉冲金环（两层）标记焦点
	draw_rect(r, Color(UIStyle.BORDER_GOLD_BRIGHT, a), false, 2.5)
	draw_rect(r.grow(4.0 + 3.0 * sin(_pulse * 0.7 + 1.0)), Color(UIStyle.GOLD, a * 0.45), false, 1.5)
	# 世界目标额外画收缩圈，模拟「点这里」
	if _focus_world:
		draw_arc(_focus_center, 26.0 + 6.0 * sin(_pulse + 1.2), 0.0, TAU, 40,
			Color(UIStyle.BORDER_GOLD_BRIGHT, 0.5 + 0.5 * sin(_pulse)), 2.5, true)
