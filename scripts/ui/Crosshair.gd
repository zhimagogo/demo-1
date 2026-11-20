class_name Crosshair
extends Control
## ============================================================================
## 第三人称准星：中心点 + 可交互时扩散的四角标线 + 下方交互提示。
## - 监听 EventBus.crosshair_target_changed（HeroController 节流刷新）
## - 操控模式（hero_mode_active）显示；战术俯瞰隐藏
## - 建造模式下变绿色细十字（与 3D 预览绿/红格呼应）
## - 纯 _draw 自绘 + 插值动画，mouse_filter=IGNORE 不挡任何操作
## ============================================================================

const DOT_R: float = 2.6            # 中心点半径
const GAP_MIN: float = 7.0          # 角标离中心最小间距（收缩态）
const GAP_MAX: float = 15.0         # 角标离中心最大间距（可交互扩张态）
const TICK_LEN: float = 7.0         # 角标线长度
const LERP_SPEED: float = 12.0      # 扩张/收缩插值速度

var _gap: float = GAP_MIN           # 当前角标间距（插值）
var _interactive: bool = false      # 是否指向可交互目标（金色扩张）
var _building_mode: bool = false    # 建造模式（绿色）
var _enemy_mode: bool = false       # 瞄准怪物（红色 + 血量条，v10）
var _enemy: Pawn = null             # 当前瞄准的怪物（血量条读取）
var _prompt_label: Label
var _hp_bg: ColorRect               # 怪物血量条（背景 / 填充）
var _hp_fill: ColorRect


func _ready() -> void:
	# 注意：只调 set_anchors_preset 会按「当前 rect」推回 offsets——若挂树时父级已完成布局
	# （工具 / 测试实例化 HUD 的时序），会把 0×0 的当前尺寸锁死成 (0,0,-w,-h) → 准星整体
	# 塌缩到左上角画不出来。这里显式清零四个 offset，保证任何时序下都是全屏铺满。
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.offset_top = 30.0   # 准星下方
	_prompt_label.offset_bottom = 58.0
	_prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", UIStyle.GOLD)
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.text = ""
	add_child(_prompt_label)
	# 怪物血量条：准星上方细条（瞄准怪物时显示，v10）
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bg.set_anchors_preset(Control.PRESET_CENTER)
	_hp_bg.offset_left = -34.0
	_hp_bg.offset_right = 34.0
	_hp_bg.offset_top = -30.0
	_hp_bg.offset_bottom = -24.0
	_hp_bg.visible = false
	add_child(_hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.92, 0.25, 0.2)
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.set_anchors_preset(Control.PRESET_CENTER)
	_hp_fill.offset_left = -32.0
	_hp_fill.offset_top = -28.0
	_hp_fill.offset_bottom = -26.0
	_hp_fill.visible = false
	add_child(_hp_fill)
	visible = false

	EventBus.crosshair_target_changed.connect(_on_target_changed)
	EventBus.hero_mode_changed.connect(_on_mode_changed)
	EventBus.build_mode_entered.connect(func(_def): _building_mode = true)
	EventBus.build_mode_exited.connect(func(): _building_mode = false)


func _on_mode_changed(_active: bool) -> void:
	# 显隐由 _process 统一管理（hero_mode_active && 无 UI 模态）；模式切换时只清提示
	_prompt_label.text = ""


func _on_target_changed(_target: Node, prompt: String, kind: StringName) -> void:
	_interactive = prompt != "" and prompt.begins_with("[E]")
	_enemy_mode = kind == &"enemy"
	_enemy = _target as Pawn if _enemy_mode else null
	_prompt_label.text = prompt


func _process(delta: float) -> void:
	# UI 模态（入驻提示 / 引导信息卡）期间鼠标已释放，准星无意义 → 隐藏；
	# 俯视角主控用鼠标落点瞄准（无屏幕中心准星），也隐藏
	visible = SelectionManager.view_mode == SelectionManager.ViewMode.HERO \
			and SelectionManager.ui_modal_count <= 0
	if not visible:
		return
	# 怪物血量条：目标活着就实时刷新宽度
	var hp_ok: bool = _enemy != null and is_instance_valid(_enemy) and _enemy.health != null
	_hp_bg.visible = hp_ok
	_hp_fill.visible = hp_ok
	if hp_ok:
		var ratio: float = clampf(_enemy.health.ratio(), 0.0, 1.0)
		_hp_fill.offset_right = -32.0 + 64.0 * ratio
	var target_gap: float = GAP_MAX if (_interactive or _enemy_mode) else GAP_MIN
	_gap = lerpf(_gap, target_gap, 1.0 - exp(-delta * LERP_SPEED))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(1.0, 1.0, 1.0, 0.92)
	if _building_mode:
		col = Color(0.55, 1.0, 0.65, 0.95)
	elif _enemy_mode:
		col = Color(1.0, 0.3, 0.25, 0.95)   # 瞄准怪物：红色准星（v10）
	elif _interactive:
		col = UIStyle.GOLD
	draw_circle(c, DOT_R, Color(0, 0, 0, 0.55))
	draw_circle(c, DOT_R - 0.8, col)
	# 四角标线（上下左右）：扩张 = 命中可交互目标
	var half := TICK_LEN * 0.5
	draw_line(c + Vector2(0, -_gap - TICK_LEN), c + Vector2(0, -_gap), col, 1.6)
	draw_line(c + Vector2(0, _gap), c + Vector2(0, _gap + TICK_LEN), col, 1.6)
	draw_line(c + Vector2(-_gap - TICK_LEN, 0), c + Vector2(-_gap, 0), col, 1.6)
	draw_line(c + Vector2(_gap, 0), c + Vector2(_gap + TICK_LEN, 0), col, 1.6)
	# 建造模式附加小方框角（提示网格吸附）
	if _building_mode:
		var r := _gap + TICK_LEN + 3.0
		var tl := c + Vector2(-r, -r)
		var br := c + Vector2(r, r)
		draw_line(tl, tl + Vector2(half * 2.0, 0), col, 1.2)
		draw_line(tl, tl + Vector2(0, half * 2.0), col, 1.2)
		draw_line(br, br - Vector2(half * 2.0, 0), col, 1.2)
		draw_line(br, br - Vector2(0, half * 2.0), col, 1.2)
