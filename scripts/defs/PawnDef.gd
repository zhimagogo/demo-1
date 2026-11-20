class_name PawnDef
extends Resource
## Pawn（小人 / 敌人）属性定义。

@export var id: StringName
@export var display_name: String = ""
@export var max_hp: float = 100.0
@export var move_speed: float = 4.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var mesh_color: Color = Color.LIGHT_BLUE
@export var team: int = 0                         # 0=Player 1=Enemy 2=Neutral
@export var is_auto_fighter: bool = true          # 是否自动索敌迎击
@export var regen_per_sec: float = 0.0            # 城内每秒回血量（士兵「城内生活」回血；0=不回血）

# ---- 经济 / 成长 / 逃跑（v3 新增）----
@export var carry_capacity: int = 0               # 村民搬运容量（0=不需要搬运，如主角直接入库）
@export var xp_value: int = 0                     # 被击杀时授予击杀者的经验（0=无经验）
@export var loot_gold: int = 0                    # 狩猎掉落金币（CombatSystem 读取；0=用默认 5）
@export var flee_hp_ratio: float = 0.0            # 血量低于此比例触发逃跑（0=死战不退；野怪用）
@export var flee_chance: float = 1.0              # v35：低血时真正逃跑的概率（1=旧行为必跑；<1=小概率怂怪，多数死战——近战小兵友好）
@export var is_boss: bool = false                 # 头目（HUD 血条横幅、不掉队、不逃跑）
@export var model_tint: Color = Color(1, 1, 1, 1) # 模型整体染色（精英怪 / 头目区分；白色=不染）

# 攻击类型（决定 AttackerComponent 走即时伤害还是生成飞行投射物，
# 以及远程兵是否进入风筝战斗状态）
enum AttackKind { MELEE, RANGED }
@export var attack_kind: int = AttackKind.MELEE
# 远程专用（attack_kind == RANGED 时生效）
@export var projectile_speed: float = 16.0        # 箭矢飞行速度（m/s）
@export var kite_safe_range: float = 0.0          # 敌人比这近就后撤（风筝）；0 = 不风筝（近战）

# 骨骼模型（占位美术通道）。model_path 为空 → 用胶囊占位；指向 .glb 则运行时挂载。
# 占位资源统一放 res://assets/_PLACEHOLDER/，便于一眼识别与后续替换（见该目录 README）。
@export var model_path: String = ""
@export var model_scale: float = 1.0
@export var model_face_offset_deg: float = 0.0   # 模型默认朝向与项目 -Z 前向的偏差（度）；背对则设 180
# 「半径盒」体型倍率（v32）：碰撞胶囊 / 拾取柱 / 导航半径 / 选中·瞄准环统一 × 此值。
# 默认 1.0 = 人形口径（胶囊 r0.4 h1.6、拾取柱 r0.6 h2.0）。模型放大时**必须同步放大**，
# 否则外观与物理盒脱节：巨龙翻倍后旧盒只到脚踝——穿建筑、拾取只命中脚下一点、
# 小队分离力也压不住它。
@export var body_scale: float = 1.0
# 头顶血条 / 气泡高度覆盖（0 = 自动按 model_scale 估算 / 量模型包围盒）。
# 供「静态 AABB 与实渲身高严重不符」的模型使用（如 bocdagla 龙：AABB 高 10.45、
# 实渲仅 ~5.68 单位，自动量测会把血条顶到半空——驯龙系统按实渲口径配置）。
@export var hud_head_height: float = 0.0
# 脚下队伍绿圈的外半径（v29）：默认 0.42 是按人形脚掌定的；大体型单位（巨龙）不放大
# 就会被身体整个盖住——等于没有队伍标。≤0 = 用 Pawn 的默认值。
@export var squad_ring_radius: float = 0.0
# 模型候选池：非空时，每个实例 _apply_def 从中随机抽一个（殖民者多外观多样化）；
# 为空则用上面的单一 model_path。占位资源统一放 res://assets/_PLACEHOLDER/。
@export var model_path_pool: Array[String] = []
# 武器挂点：占位 KayKit 角色把「该手可用的所有武器变体」都挂在同一个手部挂点下
# （主角手部挂点里躺着 1H/2H 剑 + 4 面盾），且默认全部可见 → 剑和盾同时出现在同一只手上。
# 这里指定每只手保留的模型节点名（如 "1H_Sword" / "Rectangle_Shield"）；
# 空 = 保留该挂点第一个子节点（KayKit 排序里第一个即该模型的主武器）；
# 名字在该模型里不存在 = 该手空手。详见 PawnModelRig.apply_weapon_loadout()。
@export var model_weapon_main: StringName = &""      # 主手（右手）
@export var model_weapon_offhand: StringName = &""   # 副手（左手）
# 动画名覆盖（可选）：键 = 项目 key（idle/move/run/harvest/fight/follow/dead/shoot/cast/stab/hit/combo_*/skill_*），
# 值 = 该模型的真实动画名（String/StringName）或其候选数组（按序取第一个存在的）。
# 不填则走 PawnModelRig.ANIM_CANDIDATES 的全局候选回退——KayKit 人形与 Quaternius 怪物
# 两套命名（Idle/Walking_A/… 与 Idle/Walk/Run/Punch/Death）**都已覆盖，通常无需填本字段**。
# 用途：① 换用第三套命名完全不同的美术资源时，只覆盖该单位、不污染全局表；
# ② 按武器 / 攻击方式挑选更贴合的动作（如双手斧走 2H_Slice、长杖施法走 Spellcast）。
@export var anim_map: Dictionary = {}
# 攻击类动画（fight/shoot/stab）的播放速度倍率：动画时长超过攻击间隔的兵种
# （如刺客 Dualwield_Slice 1.17s / 攻击间隔 0.55s）按倍速播，让动作节奏跟上出招节奏。
@export var attack_anim_speed: float = 1.0
# 飞行单位（v21 猛兽）：模型只有 Flying_Idle / Fast_Flying 这类空中动画、没有地面待机/行走。
# 置 true 后 PawnModelRig 走 FALLBACK_FLYER 回退（idle→Flying_Idle、run→Fast_Flying）。
# 注意：这**只影响动画选择**，不改变移动逻辑（空中单位的寻路/攻击判定仍与地面单位一致）。
@export var is_flying_unit: bool = false
# 个体显示名（流民定居后的随机姓名等；空 = 用 display_name）
@export var unit_name: String = ""
# 职业字徽与配色（HUD 小队列表 / 编队界面用；空 = 无字徽）
@export var class_icon: String = ""
@export var class_color: Color = Color.WHITE
# 职业主动技能（v19 四职业定居小兵；null = 无技能——村民 / 流民 / 兵营兵 / 野怪均不配）
@export var skill: PawnSkillDef
# v33 进阶职业技能：转职后的进阶职业在这里追加**新**主动技能（基础四职业为空）。
# 施放优先级 = extra_skills 先于 skill（进阶技能更有牌面：跳劈先手、隐身保命），见 PawnSkillComponent。
@export var extra_skills: Array[PawnSkillDef] = []


## 全部主动技能（主技能在前 + 进阶技能；过滤 null）。UI / 测试按此枚举。
func all_skills() -> Array[PawnSkillDef]:
	var out: Array[PawnSkillDef] = []
	if skill != null:
		out.append(skill)
	for s in extra_skills:
		if s != null:
			out.append(s)
	return out


## 是否持有某 id 的技能（解锁状态另由技能树判定）。
func has_skill_id(skill_id: StringName) -> bool:
	for s in all_skills():
		if s.id == skill_id:
			return true
	return false

# ---- v20 小兵属性系统（六维 + 等级成长）----
# 血量(max_hp) / 攻击(attack_damage) / 移速(move_speed) 复用上方既有字段，
# 这里补齐后三维：防御 / 暴击率 / 暴击倍率。基础值按兵种风格分配（见 GameDefs）。
@export var defense: float = 0.0             # 防御力（减伤：受伤 × K/(K+defense)，K=Pawn.DEFENSE_K）
@export var crit_rate: float = 0.0           # 暴击率（0~1；0 = 不暴击。成长封顶 Pawn.CRIT_CAP）
@export var crit_multiplier: float = 2.0     # 暴击伤害倍率（暴击时攻击 × 此值）
# 是否参与「击杀得经验 → 升级 → 六维成长」线：小兵（兵营兵 + 定居四职业）为 true；
# 主角有自己的成长线（Hero.xp_to_next / damage_mult），村民 / 流民 / 野怪不升级。
@export var can_level: bool = false

# ---- v25 技能树 / 转职 ----
# 技能树：非空 = 该单位拥有技能树（每次升级 +1 技能点，可在技能树界面加点；
# 树布局按 id 从 GameDefs.skill_tree_def 取）。主角与定居四职业（含进阶）配置。
@export var skill_tree_id: StringName = &""
# 转职：Lv.5 起可转职的进阶职业 id 列表（GameDefs.settler_advanced_def 按 id 取 def）。
# 空 = 不可转职（进阶职业自身不可再转，村民 / 流民 / 野怪不配）。
@export var promotes_to: Array[StringName] = []
