class_name FloatingLabels
extends Control
## 漂浮文字层（v3 新增）：
## - 伤害数字：damage_dealt 信号 → 白/金（我方输出）红（敌方对我）橙（建筑受损）
## - 事件文字：floating_text 信号 → 资源入库「+10 木材」/ 升级 / 头目讨伐
## 实现：Label 池（无 3D 依赖），世界坐标一次性投影到屏幕后向上漂移淡出。
## 3D 目标移动不追踪（伤害数字寿命 0.7s，追踪反而抖）。

const POOL_SIZE: int = 44
const LIFE: float = 0.75
const RISE: float = 46.0          # 像素上浮距离
const HEAVY_THRESHOLD: float = 26.0   # 大伤害（重击/技能）字号更大

var _pool: Array = []             # [{ label, life, base_pos, vy }]
var _cam: Camera3D = null
var _display_font: Font = null    # 重击数字用的粗体（懒加载，避免每次 spawn 都建）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL_SIZE:
		var l := Label.new()
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# v6 描边 + 投影：正文字体换成楷体后字重更细，压在草地/雪地/水面上也要读得出来
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.03, 0.94))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_color_override("shadow_color", Color(0.0, 0.0, 0.0, 0.45))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(l)
		_pool.append({ "label": l, "life": 0.0, "pos": Vector2.ZERO, "vy": 0.0 })
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.floating_text.connect(_on_floating_text)


func _process(delta: float) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
	for entry in _pool:
		if entry["life"] <= 0.0:
			continue
		entry["life"] = maxf(0.0, entry["life"] - delta)
		var l: Label = entry["label"]
		if entry["life"] == 0.0:
			l.visible = false
			continue
		entry["pos"].y -= entry["vy"] * delta
		l.position = entry["pos"]
		# 前 70% 不透明，后 30% 淡出
		var a: float = clampf(entry["life"] / (LIFE * 0.3), 0.0, 1.0)
		l.modulate = Color(1, 1, 1, a)


## 取一个池位（轮转复用最旧的）
func _acquire() -> Dictionary:
	var best: Dictionary = _pool[0]
	for entry in _pool:
		if entry["life"] <= 0.0:
			return entry
		if entry["life"] < best["life"]:
			best = entry
	return best


func _spawn(world_pos: Vector3, text: String, color: Color, size: int) -> void:
	if _cam == null:
		_cam = get_viewport().get_camera_3d()
		if _cam == null:
			return
	if _cam.is_position_behind(world_pos):
		return
	var screen := _cam.unproject_position(world_pos)
	var entry := _acquire()
	var l: Label = entry["label"]
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# 重击 / 大数字用粗体标题字，普通伤害沿用正文楷体（都带描边，见 _ready）
	if size >= 22:
		if _display_font == null:
			_display_font = UIStyle.make_display_font()
		l.add_theme_font_override("font", _display_font)
	else:
		l.remove_theme_font_override("font")
	entry["pos"] = screen + Vector2(randf_range(-8.0, 8.0), randf_range(-4.0, 4.0))
	entry["vy"] = RISE / LIFE
	entry["life"] = LIFE
	l.visible = true
	l.modulate = Color(1, 1, 1, 1)
	l.position = entry["pos"]


func _on_damage_dealt(target: Node, amount: float, source: Node) -> void:
	if not (target is Node3D) or not is_instance_valid(target):
		return
	var pos: Vector3 = (target as Node3D).global_position + Vector3(0, 1.7, 0)
	# 颜色规则：我方输出=暖白（重击=金），敌方打我=红，建筑受损=橙
	var is_player_source := false
	if source is Pawn:
		is_player_source = (source as Pawn).team_comp != null and (source as Pawn).team_comp.team == TeamComponent.Team.PLAYER
	elif source is Building:
		is_player_source = true
	var text := "%d" % int(round(amount))
	if is_player_source:
		if amount >= HEAVY_THRESHOLD:
			_spawn(pos, text, Color(1.0, 0.82, 0.3), 22)
		else:
			_spawn(pos, text, Color(1.0, 0.97, 0.9), 16)
	elif target is Building:
		_spawn(pos, text, Color(1.0, 0.62, 0.3), 16)
	else:
		_spawn(pos, text, Color(1.0, 0.42, 0.38), 16)


func _on_floating_text(text: String, color: Color, world_pos: Vector3) -> void:
	_spawn(world_pos, text, color, 19)
