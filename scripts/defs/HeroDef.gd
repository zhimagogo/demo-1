class_name HeroDef
extends PawnDef
## 主角定义：在 PawnDef 基础上扩展职业 / 连招 / 技能 / 复活 / 动画骨骼。
## 后续扩展职业（弓箭手 / 骑士 / 法师）只需新增 GameDefs.hero_<class>_def() 返回不同 HeroDef，
## 配合不同 SkillDef 列表即可，无需改 Hero 运行时。

@export var class_id: StringName = &"warrior"        # 职业标识（warrior / archer / knight / mage）
@export var combo_hits: Array[ComboHitDef] = []      # 普攻连招段（通常 3 段）
@export var skills: Array[SkillDef] = []             # 可用技能（技能槽取前 N 个）
@export var combo_window: float = 0.8                # 连招递进允许间隔（超时回到第 1 段）

@export var respawn_at_base: bool = true             # 死亡后在基地复活（否则触发失败）
@export var respawn_delay: float = 5.0               # 复活延迟（秒）

@export var anim_rig: PackedScene = null             # 将来挂骨骼模型 + AnimationPlayer；为 null 时走 tween 占位
