class_name SkillDef
extends Resource
## 技能定义。target_kind 决定执行分支（数据驱动派发）：
## 新增职业 / 技能只需加 TargetKind 分支（如弓箭手 PROJECTILE、法师 SELF_AOE 大范围）。

enum TargetKind { SELF_AOE, DIRECTIONAL_DASH, PROJECTILE, BUFF }

@export var id: StringName
@export var display_name: String = ""
@export var cooldown: float = 6.0
@export var damage: float = 30.0
@export var windup: float = 0.2          # 蓄力时长
@export var duration: float = 0.4        # 生效持续（AoE 多 tick / 冲锋位移用时）
@export var recovery: float = 0.3        # 收招时长
@export var target_kind: int = TargetKind.SELF_AOE
@export var radius: float = 4.0          # SELF_AOE 半径
@export var half_arc: float = PI         # 扇形半角（PI=全圆，用于 AoE / 冲锋判定）
@export var tick_interval: float = 0.15  # 多段造伤间隔
@export var dash_distance: float = 7.0   # DIRECTIONAL_DASH 位移距离
@export var vfx_id: StringName = &""     # 特效 id（接 VFXManager）
@export var sfx_id: StringName = &""     # 音效 id（接 AudioManager）
@export var anim_id: StringName = &""    # 动画 id（接 HeroAnimator）
@export var icon_color: Color = Color.WHITE
