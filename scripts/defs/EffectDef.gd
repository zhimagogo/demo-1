class_name EffectDef
extends Resource
## 程序化特效定义：驱动 VFXManager 代码生成特效节点。
## 两套管线并存，用 kind 区分：
## - Kind.PARTICLES：GPUParticles3D（shape 决定发射形状：爆开 / 扇形 / 球 / 尾迹）
## - Kind.SLASH：自绘月牙弧面网格 + vfx_arc.gdshader（刀光）
## - Kind.RING / FLASH / GLOW：1×1 公告牌网格 + vfx_billboard.gdshader
##   （冲击环 / 枪口十字星 / 蓄力微光，尺寸由节点 scale 控制）
## - Kind.TRAIL：挂在投射物上的持续发射尾迹（不可单独 spawn）
## 将来可用 res://assets/vfx/<id>.tscn 覆盖替换（spawn_effect 内优先尝试场景），调用方不变。

enum Shape { BURST, ARC, RING, AURA, TRAIL }
enum Kind { PARTICLES, SLASH, RING, FLASH, GLOW, TRAIL }

@export var kind: int = Kind.PARTICLES
@export var shape: int = Shape.BURST
@export var node_name: String = "Vfx"          # 场景树里的节点名（测试/调试按名断言）
@export var color: Color = Color.WHITE
@export var amount: int = 16
@export var lifetime: float = 0.4
@export var scale_min: float = 0.2
@export var scale_max: float = 0.6
@export var speed_min: float = 1.0
@export var speed_max: float = 4.0
@export var radius: float = 1.0                # ARC / RING / AURA 的粒子发射球半径
@export var gravity: Vector3 = Vector3.ZERO    # 火星受重力下坠
@export var damping: float = 0.0               # 速度阻尼（拖尾感）
@export var size: float = 0.22                 # 粒子面片边长（米）
@export var spread: float = 180.0              # 粒子发射锥角（度）
@export var texture_role: StringName = &""     # 贴图角色：spark/star/ring/smoke/flame/glow
## 粒子坐标空间：false = 世界坐标（粒子留在原地，拖尾用）；
## true = 跟随发射器（一次性爆点可旋转节点来定向喷射——定向命中喷溅用）。
@export var local_coords: bool = false
## 粒子贴图随机旋转抖动（度；cartoon 火舌 / 烟团翻滚的关键——每颗粒子一个随机朝向）。
## 需要 _particle_mesh 走 BILLBOARD_PARTICLES（v30 起为默认）。
@export var angle_jitter: float = 10.0
## 粒子混合方式：false = 加法混合（发光体：火星 / 微光 / 余烬）；
## true = alpha 混合（不透明色块体：卡通火舌 / 烟团——加法在明亮草地上会被「加白」）。
@export var alpha_blend: bool = false

# ---- 网格 / 公告牌类（Kind != PARTICLES）----
@export var arc_deg: float = 140.0             # 弧的圆心角（度）
@export var arc_width: float = 1.3             # 弧外半径（米）
@export var arc_inner_ratio: float = 0.48      # 内半径 / 外半径
@export var scale_from: float = 0.62           # 生命周期起始缩放
@export var scale_to: float = 1.12             # 生命周期结束缩放
@export var spin_deg: float = 70.0             # 生命周期内绕 Y 旋转角度（刀光扫动感）
@export var rise: float = 0.0                  # 生命周期内沿世界 Y 漂移（米）
@export var fade_in_end: float = 0.16          # 进度到此值前完全淡入
@export var fade_out_start: float = 0.46       # 进度在此值后淡出
@export var heavy: bool = false                # 重击刀光（更粗更亮；测试按分组断言）
@export var ring_amount: float = 0.0           # 公告牌：0 = 光斑，1 = 空心环
@export var softness: float = 0.55             # 公告牌：边缘柔化
@export var thickness: float = 0.30            # 公告牌：环带宽度
@export var strength: float = 1.0              # 公告牌：亮度/不透明度增益
@export var no_depth_test: bool = false        # 穿过人群可见（冲击环用）
## 预算优先级：MAX_ACTIVE_EFFECTS 满员时的取舍依据。
## 0 = 命中反馈（火星 / 冲击环 / 魔法爆散）——名额不够时优先丢；
## 1 = 出招表现（刀光弧 / 枪口闪光 / 施法微光 / 技能特效）——回收最旧的低优先级节点后照常生成，
##     否则大规模夜战里玩家会以为「技能没打出去」。
@export var priority: int = 0
