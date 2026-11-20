class_name ComboHitDef
extends Resource
## 单段普攻定义。3 段连招由 HeroDef.combo_hits 给出（如 轻-轻-重）。
## anim_id / vfx_id / sfx_id 为「动作 / 特效 / 音效」接口钩子，缺省走占位 id。

@export var step: int = 1                # 段序（1/2/3）
@export var damage: float = 12.0
@export var windup: float = 0.08         # 蓄力（原地，不上步）
@export var active: float = 0.12         # 命中判定窗口
@export var recovery: float = 0.2        # 收招
@export var range: float = 2.6           # 命中距离
@export var half_arc: float = 0.9        # 前方扇形半角（弧度，PI=全圆）
@export var lunge: float = 0.6           # （已停用）蓄力期向前突进距离——普攻不再上步，字段保留兼容旧数据
@export var hit_stop: float = 0.05       # 命中顿帧（秒）
@export var anim_id: StringName = &""    # 动画 id（接 HeroAnimator）
@export var vfx_id: StringName = &""     # 特效 id（接 VFXManager）
@export var sfx_id: StringName = &""     # 音效 id（接 AudioManager）
