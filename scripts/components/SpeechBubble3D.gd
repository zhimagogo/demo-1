class_name SpeechBubble3D
extends Node3D
## ============================================================================
## 小兵人设气泡（v14）：挂在 Pawn 头顶（命名 "SpeechBubble3D"），随机低频地
## 冒出一句符合自己人设的台词（台词池在 GameDefs.BUBBLE_LINES，按 def.id + 心情取用）。
##
## 实现走 HealthBar3D 同款「Sprite3D 公告牌 + 程序化贴图」管线（项目约定：头顶
## 指示类元素一律抄血条方案），文字用 Label3D 叠在气泡底之上：
##   - billboard + no_depth_test：穿过人群可见，与血条 / 集火箭头同一约定
##   - top_level：不随 Pawn 转身，每帧钉在头顶（血条上方、集火箭头下方）
##   - 文字宽度自适应：按字体量测结果横向拉伸底图（圆角轻微变形，占位可接受）
##
## 「不要太频繁」的硬约束（三层）：
##   1) 单位间隔：同一小兵两泡之间至少 INTERVAL_MIN(45s)，上限 INTERVAL_MAX(95s)；
##   2) 全场并发：同时最多 MAX_CONCURRENT(3) 个气泡，满了就短延时重试；
##   3) 出生延迟：首泡不早于 FIRST_DELAY_MIN(14s)，避免刷兵瞬间满屏气泡。
##
## 台词池为空的单位（主角 / 野怪）永不冒泡；死亡期间自动抑制。
## 计时走 _process 的 delta（受 Engine.time_scale 缩放，暂停时气泡也随之冻结）。
## ============================================================================

# ---- 视觉常量 ----
const PIXEL_SIZE := 0.0055          # 贴图像素 → 世界米
const TEX_W := 192                  # 气泡底图宽（px）
const TEX_H := 64                   # 气泡底图高（px，含尾巴）
const TAIL_H := 12                  # 底部尾巴高（px，指向头顶）
const CORNER := 13                  # 圆角半径（px）
const TAIL_W := 16                  # 尾巴根部宽（px）
const PAD_X := 26.0                 # 文字左右留白（px）
const FONT_SIZE := 24
const RISE_BASE := 2.1              # 与 HealthBar3D.RISE 对齐的血条高度
const RISE_MARGIN := 0.46           # 气泡中心再抬高（避开血条，低于集火箭头）
const BOB_AMP := 0.03              # 轻微浮动幅度（米）
const BOB_SPEED := 2.2

const COLOR_FILL := Color(1.0, 0.985, 0.93, 0.96)    # 暖纸白底
const COLOR_EDGE := Color(0.55, 0.44, 0.26, 0.95)    # 暗金描边（配 UIStyle）
const COLOR_TEXT := Color(0.26, 0.19, 0.10, 1.0)     # 深褐文字

# ---- v16 俯视角可读性（恒定屏幕像素）----
# 气泡是世界尺寸（宽 ~1.06m）：第三人称 5~6m 观距下观感正常，但等距俯瞰相机悬在
# ~44m 高空，同一气泡在屏幕上只剩十来个像素——用户反馈「俯视角下太小看不见」。
# 抄 HealthBar3D 的方案：按当前相机在气泡深度处的竖直视野跨度等比放大根节点，
# 使屏幕像素尺寸与近景一致。REF_SPAN 取第三人称 6m 观距的竖直视野（2*6*tan(39°)），
# ≤ 参考跨度时保持 1×（不动 v14 调好的近景观感），更远按跨度等比放大并封顶。
const REF_SPAN: float = 9.73
const VIEW_SCALE_MAX: float = 9.0
var _view_scale: float = 1.0

# ---- 动画 ----
const FADE_IN := 0.16               # 淡入时长
const FADE_OUT := 0.30              # 淡出时长
const POP_TIME := 0.20              # 弹出过冲时长

# ---- 频率约束（「不要太频繁」）----
const FIRST_DELAY_MIN := 14.0       # 出生后首泡不早于此
const FIRST_DELAY_MAX := 40.0
const INTERVAL_MIN := 45.0          # 同一小兵两泡间隔下限
const INTERVAL_MAX := 95.0
const CROWDED_RETRY := 6.0          # 全场气泡满员时的重试间隔基准
const DISPLAY_SEC := 4.0            # 气泡停留时长
const MAX_CONCURRENT := 3           # 全场同时可见的气泡上限

# 状态名 → 心情（决定取哪一池台词；缺省按 idle 日常池处理）
const STATE_MOOD := {
	"fight": &"combat",
	"villager_flee": &"combat",
	"harvest": &"work",
	"villager_work": &"work",
	"villager_deliver": &"work",
	"patrol": &"work",
	"move": &"work",
}

# 全场并发计数（静态共享）与共享贴图 / 字体
static var _active: int = 0
static var _tex: Texture2D
static var _font: Font

var _bg: Sprite3D
var _label: Label3D
var _timer: float = 0.0             # 距下一次自动冒泡（仅未显示时倒计时）
var _showing: bool = false
var _t: float = 0.0                 # 本次显示已经过的时间
var _duration: float = DISPLAY_SEC
var _text: String = ""


func _ready() -> void:
	visible = false
	# top_level：脱离父节点(Pawn)的旋转/缩放，避免单位转身带动气泡歪斜（同 HealthBar3D）
	top_level = true
	add_to_group("speech_bubbles")
	_ensure_tex()
	_bg = Sprite3D.new()
	_bg.name = "BubbleBg"
	_bg.texture = _tex
	_bg.pixel_size = PIXEL_SIZE
	_bg.modulate = COLOR_FILL
	_bg.no_depth_test = true          # 穿过人群可见（与血条 / 集火箭头同款约定）
	_bg.shaded = false                # 不受光照，颜色恒定
	_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bg.render_priority = 20
	add_child(_bg)
	_label = Label3D.new()
	_label.name = "BubbleText"
	_label.font = _ensure_font()      # HUD 同款中文字体（缺文件自动回退系统链）
	_label.font_size = FONT_SIZE
	_label.outline_size = 0           # 浅底深字，不需要描边
	_label.pixel_size = PIXEL_SIZE
	_label.modulate = COLOR_TEXT
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.render_priority = 21
	# 贴图含底部尾巴：把文字上移半个尾巴高，对齐圆角主体中心
	_label.position.y = TAIL_H * 0.5 * PIXEL_SIZE
	add_child(_label)
	# 出生延迟随机化：错开刷兵瞬间的冒泡节奏
	_timer = randf_range(FIRST_DELAY_MIN, FIRST_DELAY_MAX)


func _exit_tree() -> void:
	# 显示中被释放（单位死亡 queue_free 等）：归还并发名额，防止满员卡死
	if _showing:
		_showing = false
		_active -= 1


func _process(delta: float) -> void:
	if not _showing:
		_timer -= delta
		if _timer <= 0.0:
			_try_show()
		return
	# 显示中：主人死了立刻收起，否则正常动画 + 跟随
	var pawn := _parent_pawn()
	if pawn == null or pawn.is_dead_flag:
		_end()
		return
	_t += delta
	_follow()
	_animate()
	if _t >= _duration:
		_end()


# ---- 对外接口 ----

## 直接展示一条气泡（脚本化演出 / 测试用；不走并发上限与台词池）。
## duration 为停留时长，实际最短被淡入淡出总和撑住。
func show_bubble(text: String, duration: float = DISPLAY_SEC) -> void:
	_text = text
	_duration = maxf(duration, FADE_IN + FADE_OUT + 0.1)
	_t = 0.0
	_fit_text(text)
	if not _showing:
		_showing = true
		_active += 1
	visible = true
	_set_alpha(0.0)
	_follow()


## 立即收起气泡（并发名额一并归还）。
func hide_now() -> void:
	if _showing:
		_end()


func is_showing() -> bool:
	return _showing


func current_text() -> String:
	return _text


## 全场当前可见的气泡数。
static func active_count() -> int:
	return _active


## 下一次自动冒泡的随机间隔（秒）。
static func next_interval() -> float:
	return randf_range(INTERVAL_MIN, INTERVAL_MAX)


## 状态名 → 心情（idle / work / combat）。
static func mood_for_state(state_name: String) -> StringName:
	return STATE_MOOD.get(state_name, &"idle")


## 测试 / 调试用：直接设定自动冒泡倒计时。
func debug_set_timer(sec: float) -> void:
	_timer = sec


# ---- 内部 ----

## 自动冒泡入口：检查主人 / 并发 / 台词池，条件不满足就短延时重试。
func _try_show() -> void:
	if _parent_state_name() == "chat":
		_timer = CROWDED_RETRY
		return   # 聊天状态负责一问一答，自动人设气泡不能覆盖对白
	var pawn := _parent_pawn()
	if pawn == null or pawn.is_dead_flag:
		_timer = CROWDED_RETRY
		return
	if _active >= MAX_CONCURRENT:
		_timer = randf_range(CROWDED_RETRY * 0.6, CROWDED_RETRY * 1.4)
		return
	var line := pick_line()
	if line == "":
		# 该单位没有台词池（主角 / 野怪）：间隔再拉长，等于基本不冒泡
		_timer = INTERVAL_MIN
		return
	show_bubble(line, DISPLAY_SEC + randf_range(-0.4, 0.8))
	_timer = next_interval()


## 按「主人 def + 当前心情」挑一句人设台词；无台词返回空串。
func pick_line() -> String:
	var pawn := _parent_pawn()
	if pawn == null or pawn.def == null:
		return ""
	var mood := mood_for_state(_parent_state_name())
	var lines: Array = GameDefs.bubble_lines_for(pawn.def.id, mood)
	if lines.is_empty():
		return ""
	return lines.pick_random()


func _parent_pawn() -> Pawn:
	var p := get_parent()
	if is_instance_valid(p) and p is Pawn:
		return p as Pawn
	return null


func _parent_state_name() -> String:
	var pawn := _parent_pawn()
	if pawn != null and pawn.state_machine != null and pawn.state_machine.current_state != null:
		return pawn.state_machine.current_state.name
	return "idle"


## 按文字宽度横向拉伸底图（高度不变；圆角被轻微拉伸，占位效果可接受）。
func _fit_text(text: String) -> void:
	_label.text = text
	var f := _ensure_font()
	var measured: Vector2 = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var need_w: float = maxf(measured.x, float(FONT_SIZE)) + PAD_X * 2.0
	_bg.scale = Vector3(need_w / float(TEX_W), 1.0, 1.0)


func _animate() -> void:
	# 透明度：淡入 → 停留 → 淡出
	var a: float = minf(_t / FADE_IN, 1.0)
	a = minf(a, (_duration - _t) / FADE_OUT)
	_set_alpha(clampf(a, 0.0, 1.0))
	# 弹出过冲：0.85 → 1.10 → 1.00（同帧叠加一个半程鼓包）
	var k: float = clampf(_t / POP_TIME, 0.0, 1.0)
	var pop: float = lerpf(0.85, 1.0, k) + 0.10 * sin(k * PI)
	scale = Vector3.ONE * pop * _view_scale


func _end() -> void:
	_showing = false
	visible = false
	scale = Vector3.ONE
	_set_alpha(0.0)
	_active -= 1
	if _timer <= 0.0:
		_timer = next_interval()


func _set_alpha(a: float) -> void:
	_bg.modulate = Color(COLOR_FILL.r, COLOR_FILL.g, COLOR_FILL.b, COLOR_FILL.a * a)
	_label.modulate = Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, a)


## 每帧钉在主人头顶（血条之上），带极轻微的呼吸浮动。
func _follow() -> void:
	var p := get_parent()
	if not (is_instance_valid(p) and p is Node3D):
		return
	_update_view_scale()
	var rise: float = RISE_BASE + RISE_MARGIN
	var pawn := p as Pawn
	if pawn.def != null:
		rise = RISE_BASE * maxf(pawn.def.model_scale, 0.85) + RISE_MARGIN
	if pawn.health_bar != null:
		rise = pawn.health_bar.head_height() + RISE_MARGIN
	# 放大后气泡自身更高：锚点随之上抬，让尾巴尖仍保持在头顶之上（不吞掉角色）
	rise += (_view_scale - 1.0) * (TEX_H * 0.5 * PIXEL_SIZE)
	global_position = (p as Node3D).global_position \
		+ Vector3(0.0, rise + sin(_t * BOB_SPEED) * BOB_AMP, 0.0)


## v16 恒定屏幕尺寸：按当前相机在气泡深度处的竖直视野跨度换算根节点缩放。
## 与 HealthBar3D._follow 同一套数学（透视用 2·depth·tan(fov/2)，正交用 cam.size，
## KEEP_WIDTH 换算回竖直跨度），保证气泡在等距俯瞰 44m 观距下与第三人称近景
## 屏幕像素一致——否则俯视角下只有十来个像素，看不见。
func _update_view_scale() -> void:
	if not is_inside_tree():
		_view_scale = 1.0
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_view_scale = 1.0
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var viewport_height := maxf(viewport_size.y, 1.0)
	var depth := maxf(0.1, -(cam.global_transform.affine_inverse() * global_position).z)
	var view_span: float = cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL \
			else 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5)
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		view_span *= viewport_height / maxf(viewport_size.x, 1.0)
	_view_scale = clampf(view_span / REF_SPAN, 1.0, VIEW_SCALE_MAX)


static func _ensure_font() -> Font:
	if _font == null:
		# 与 HUD 共用同一份中文字体（UIStyle 静态缓存，只加载一次）
		_font = UIStyle.make_font()
	return _font


## 程序化气泡底图：圆角矩形 + 暗金描边 + 底部指向头顶的小尾巴（纯代码，零外部资源）。
static func _ensure_tex() -> void:
	if _tex != null:
		return
	var body_h := TEX_H - TAIL_H
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in TEX_H:
		for x in TEX_W:
			if y < body_h:
				# 圆角矩形带符号距离：内负外正，|d|<=2px 视作描边
				var d := _rounded_dist(float(x), float(y), float(body_h))
				if d <= 0.0:
					img.set_pixel(x, y, COLOR_FILL)
				elif d <= 2.0:
					img.set_pixel(x, y, COLOR_EDGE)
			else:
				# 尾巴：上宽下尖的小三角，根部与主体底边相连
				var ty: float = float(y - body_h) / float(TAIL_H)
				var half_w: float = TAIL_W * 0.5 * (1.0 - ty * 0.85)
				if absf(float(x) - float(TEX_W) * 0.5) <= half_w:
					img.set_pixel(x, y, COLOR_EDGE if absf(absf(float(x) - float(TEX_W) * 0.5) - half_w) < 1.2 else COLOR_FILL)
	_tex = ImageTexture.create_from_image(img)


## 到圆角矩形边缘的像素距离（内负外正）。矩形占贴图上部 body_h 高、全宽。
static func _rounded_dist(x: float, y: float, body_h: float) -> float:
	var rx := float(CORNER)
	var cx: float = clampf(x, rx, float(TEX_W - 1) - rx)
	var cy: float = clampf(y, float(CORNER), body_h - 1.0 - float(CORNER))
	var dx: float = x - cx
	var dy: float = y - cy
	return Vector2(dx, dy).length() - float(CORNER)
