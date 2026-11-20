class_name FocusMarker
extends Node3D
## ============================================================================
## 集火箭头（v11）：小队集火期间悬浮在目标头顶的红色下指箭头。
## 实现走 HealthBar3D 同款「Sprite3D 公告牌 + 程序化贴图」管线——项目里所有
## 头顶血条都靠它渲染，稳过 MeshInstance3D 方案（后者在围攻人堆里偶发不可见）。
## - 上下浮动 + 轻微脉动，一眼认出「全队正在围攻谁」
## - 自跟踪 target（每帧跟随移动中的目标，按模型缩放自动抬到头顶上方）
## - no_depth_test：穿过围攻的小队成员依然可见（指标绝不能被挡）
## - 目标死亡 / 失效自动隐藏；由 HeroController 在集火令变化时指派 target
## ============================================================================

const BOB_AMP: float = 0.10        # 浮动幅度（米）
const BOB_SPEED: float = 3.2       # 浮动角速度
const PULSE_AMP: float = 0.12      # 大小脉动幅度（比例）
const BASE_HEIGHT: float = 2.1     # 基准头顶高度（按目标 model_scale 放大）
const MARGIN: float = 0.95         # 头顶以上的留白（避开血条）

var target: Node3D = null          # 当前集火目标（null = 隐藏待命）

var _arrow: Sprite3D = null
var _t: float = 0.0

# 共享箭头贴图（下指三角 + 底缘高光，纯程序生成，零外部资源）
static var _tex: Texture2D


func _ready() -> void:
	visible = false
	if _tex == null:
		var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		# 下指箭头：宽头窄尾的竖三角（底边在 y=8 顶点在 y=56）
		for y in 64:
			for x in 48:
				var dy := float(y - 8) / 48.0            # 0..1 三角高度进度
				var half_w := 22.0 * (1.0 - dy)          # 上宽下尖
				if dy >= 0.0 and dy <= 1.0 and absf(float(x) - 23.5) <= half_w:
					var edge := absf(float(x) - 23.5) / maxf(half_w, 0.001)
					var c := Color(1.0, 0.98 - 0.10 * edge, 0.95 - 0.25 * edge)
					img.set_pixel(x, y, c)
		_tex = ImageTexture.create_from_image(img)
	_arrow = Sprite3D.new()
	_arrow.name = "Arrow"
	_arrow.texture = _tex
	_arrow.pixel_size = 0.012                 # 48×64 → 0.58×0.77m
	_arrow.modulate = Color(1.0, 0.16, 0.10, 0.96)
	_arrow.no_depth_test = true               # 穿过围攻人群可见（与血条同款约定）
	_arrow.shaded = false                     # 不受光照，颜色恒定
	_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_arrow.render_priority = 30
	add_child(_arrow)


func _process(delta: float) -> void:
	var alive: bool = target != null and is_instance_valid(target) \
		and target is Pawn and not (target as Pawn).is_dead_flag
	if not alive:
		visible = false
		target = null
		return
	visible = true
	_t += delta
	# 头顶高度按模型缩放（头目 1.75× → 箭头抬得更高），叠加上下浮动
	var model_scale: float = 1.0
	if (target as Pawn).def != null:
		model_scale = maxf((target as Pawn).def.model_scale, 0.8)
	var height := BASE_HEIGHT * model_scale
	if (target as Pawn).health_bar != null:
		height = (target as Pawn).health_bar.head_height()
	global_position = target.global_position \
		+ Vector3.UP * (height + MARGIN + sin(_t * BOB_SPEED) * BOB_AMP)
	# 轻微脉动：像「锁定中」的心跳
	var pulse := 1.0 + PULSE_AMP * sin(_t * BOB_SPEED * 2.0)
	_arrow.scale = Vector3(pulse, pulse, 1.0)
