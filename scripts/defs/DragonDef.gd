class_name DragonDef
extends PawnDef
## ============================================================================
## 巨龙定义（驯龙系统）：在 PawnDef 之上叠加「龙园解锁 + 火球普攻 + 火息技能」参数。
## 数据驱动：新龙只需在 GameDefs.dragon_defs() 追加一个 def，龙园菜单 / 市民出战区 /
## DragonPet 行为全部自动接入（模型 / 数值 / 描述 / 解锁价都来自本 def）。
## ============================================================================

@export var unlock_cost: int = 100            # 龙园解锁价（金币）

# ---- 普攻：朝目标吐火球，命中爆炸造成小片溅射 ----
@export var fireball_damage: float = 22.0     # 直击伤害
@export var fireball_cooldown: float = 1.6    # 两发火球间隔（秒）
@export var fireball_range: float = 10.0      # 吐球射程（中心距）
@export var fireball_speed: float = 13.0      # 火球飞行速度（m/s）
@export var splash_radius: float = 2.2        # 爆炸溅射半径（米）
@export var splash_damage: float = 12.0       # 溅射伤害（直击目标只吃直击伤）

# ---- 技能：原地向目标方向吐火，持续 2 秒的长距锥形（默认 40° 全角）伤害 ----
@export var breath_name: String = "烈焰吐息"
@export var breath_range: float = 14.0        # 锥形长度（米）
@export var breath_half_arc_deg: float = 20.0 # 锥形半角（度；40° 全角扇形）
@export var breath_duration: float = 2.0      # 吐息持续（秒）
@export var breath_tick_interval: float = 0.4 # 每 0.4s 一跳伤害
@export var breath_damage: float = 9.0        # 每跳伤害
@export var breath_cooldown: float = 12.0     # 技能 CD（秒）

# ---- 自主攻击（v32）：主角没有指定/攻击目标时，龙自己守住主角身边这一圈 ----
# 半径**以主角为圆心**量（不是以龙为圆心）：玩家会被怪打到的那一圈 = 龙该清的那一圈，
# 怪飘出这个圈（×AUTO_LEASH_MULT 滞回）龙就脱战回跟随，不会被引着满地图跑。
@export var auto_attack_range: float = 11.0   # 自主索敌半径（米，圆心 = 主角）

# ---- UI 展示 ----
@export var description: String = ""          # 龙园卡片说明（空 = 用默认模板）
@export var skill_desc: String = ""           # 技能说明行
