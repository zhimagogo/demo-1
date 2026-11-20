class_name PawnSkillDef
extends Resource
## ============================================================================
## 小兵职业技能定义（v19）：四职业定居小兵（法师 / 战士 / 游侠 / 刺客）各配一个
## 主动技能，全部带 CD、全部带特效或显示。执行分支由 kind 派发到
## PawnSkillComponent（数据驱动，与主角 SkillDef 同范式但字段按小兵 AI 施法裁剪）。
##
## v33 进阶职业技能：转职后的四个进阶职业各追加一个主动技能（狂战士跳劈 /
## 元素法师陨石术 / 狙击手贯穿射击 / 暗杀者隐身），经 PawnDef.extra_skills 挂载、
## 由进阶技能树节点（SkillNodeDef.unlocks_skill_id）解锁。
## ============================================================================

enum Kind { BLIZZARD, BLOOD_RAGE, RAPID_SHOT, BACKSTAB, LEAP_SLAM, METEOR, PIERCING_SHOT, STEALTH }

@export var id: StringName
@export var display_name: String = ""
@export var kind: int = Kind.BLIZZARD
@export var cooldown: float = 10.0        # 冷却秒数（所有技能必须 > 0）
# 释放距离上限（中心距）：超出则不施法，继续按普攻逻辑走位；0 = 无距离要求（自身增益）
@export var cast_range: float = 0.0
@export var damage: float = 0.0           # 每段伤害（背刺 = 单次高额；快速射击 = 每箭）

# ---- 暴风雪（法师）：目标地点持续 AoE，逐跳伤害 + 减速 ----
@export var radius: float = 4.5           # AoE 半径（比普攻判定明显大一圈）
@export var duration: float = 3.0         # 场持续秒数
@export var tick_interval: float = 0.5    # 伤害跳间隔
@export var slow_factor: float = 0.55     # 移速乘到 55%（越小越慢）
@export var slow_duration: float = 1.2    # 每跳减速持续（逐跳刷新）

# ---- 血怒（战士）：自身增益，伤害提升 + 普攻吸血 ----
@export var buff_duration: float = 6.0    # 增益持续秒数
@export var damage_mult: float = 1.5      # 伤害倍率（AttackerComponent.damage 临时放大）
@export var lifesteal_ratio: float = 0.6  # 造成伤害的吸血比例

# ---- 快速射击（游侠）：短促三连射 + 给目标挂易伤 ----
@export var shot_count: int = 3           # 连射箭数
@export var shot_interval: float = 0.14   # 每箭间隔
@export var vuln_mult: float = 1.3        # 易伤：受到伤害 ×1.3
@export var vuln_duration: float = 3.0    # 易伤持续秒数

# ---- 背刺（刺客）：闪现目标身后 + 重伤（CD 就绪时优先先手）----
# 仅 damage / cast_range 参与判定（瞬移落点固定「目标身后 1.1m」）。

# ============================================================================
# v33 进阶职业技能字段
# ============================================================================

# ---- 前摇 / 收招（跳劈、陨石）：> 0 时施法进入 SkillCastState，不再瞬发 ----
@export var windup: float = 0.0            # 前摇（吟唱）秒数；0 = 瞬发
@export var recover: float = 0.25          # 收招硬直秒数

# ---- 跳劈（狂战士）：跃向锁定落点 → 落地圆形 AOE + 击飞控制 ----
# 复用既有 radius 作为落地 AOE 半径；leap_speed 决定滞空时长（距离/速度，钳到 0.25~0.9s）
@export var leap_speed: float = 16.0       # 滞空水平速度（m/s）
@export var leap_height: float = 3.0       # 抛物线顶点高度（米）
@export var knockback_distance: float = 3.2  # 击飞水平位移（米）
@export var knockback_height: float = 2.6    # 击飞高度（米）
@export var airborne_time: float = 0.55      # 击飞滞空秒数
@export var stun_duration: float = 1.1       # 落地后眩晕（控制）秒数

# ---- 陨石术（元素法师）：原地吟唱 → 落点预警 → 落地高额伤害（可躲避）----
@export var telegraph: float = 1.1         # 预警圈出现到落地的秒数（离开圈即无伤）

# ---- 贯穿射击（狙击手）：大号弹体直线贯穿一串目标 ----
@export var pierce_length: float = 26.0    # 贯穿距离（米）
@export var pierce_radius: float = 1.0     # 贯穿判定半径（米）
@export var pierce_speed: float = 26.0     # 弹体飞行速度（m/s）

# ---- 隐身（暗杀者）：模型 shader 进入隐身态，敌人一段时间内索敌不到 ----
@export var stealth_duration: float = 5.0  # 隐身持续秒数
@export var escape_hp_ratio: float = 0.35  # 逃生触发血线（血量比例低于此值即释放）
@export var approach_range: float = 7.0    # 接近目标触发距离（米）
