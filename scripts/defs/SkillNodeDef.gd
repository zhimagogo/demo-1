class_name SkillNodeDef
extends Resource
## ============================================================================
## 技能树节点定义（v25）：树上的一个可加点「口」。
## 当前通用树两分支——伤害强化（每级 +5% 攻击伤害）/ 生命强化（每级 +6% 生命上限），
## 后续按职业细分树、更多分支（主动技能解锁等）时只需新增节点定义，无需改运行时。
## ============================================================================

@export var id: StringName                    # 节点 id（树内唯一；如 &"damage"）
@export var display_name: String = ""         # 显示名（如「伤害强化」）
@export var desc: String = ""                 # 效果说明（UI 卡片正文）
@export var branch: int = 1                   # 分支编号（UI 按分支分列展示）
@export var max_rank: int = 5                 # 可投入的级数（「5 个升级口」）
# 每级收益（加算乘区，0.05 = 每级 +5%）；两类都配则同时生效
@export var damage_per_rank: float = 0.0      # 每级攻击伤害加成
@export var hp_per_rank: float = 0.0          # 每级生命上限加成
# 前置：需要另一节点至少投入 requires_rank 级才可加点（空 = 无前置）
@export var requires_node: StringName = &""
@export var requires_rank: int = 0
# ---- v25.1 职业技根节点 ----
# unlocks_skill = 职业技节点：点亮（rank≥1）后该单位的职业主动技能才可施放
# （树的起点，通常 max_rank=1、无属性收益）；技能名/参数取 pawn.def.skill（进阶
# 职业改名如「雷暴」自动跟随），树定义里不重复配置。
@export var unlocks_skill: bool = false
# v33 多技能门禁：rank ≥ 1 时解锁**该 id 的技能**（进阶职业树用——「职业技」节点解锁
# 主技能、「跳劈/陨石术/贯穿射击/隐身」节点解锁新技能）。
# 树里只要有一个节点声明了本字段，PawnSkillTree 就按**精确 id**判定（不再看 gate_node_id）；
# 全树都没声明 = 回落旧语义（gate_node_id 根节点解锁 def.skill）。
@export var unlocks_skill_id: StringName = &""
# pre_unlocked = 初始即视为已点亮（不耗点）——主角用：Q/C 技能不锁，节点只作树根
@export var pre_unlocked: bool = false
# 视觉：字徽与配色（IconBadge 缺真图时自动回退字徽）
@export var icon: String = ""
@export var color: Color = Color.WHITE


## 当前投入 rank 级时的累计攻击伤害加成（如 0.05×3 = +15%）。
func damage_bonus_at(rank: int) -> float:
	return damage_per_rank * float(clampi(rank, 0, max_rank))


## 当前投入 rank 级时的累计生命上限加成。
func hp_bonus_at(rank: int) -> float:
	return hp_per_rank * float(clampi(rank, 0, max_rank))
