class_name GameDefs
extends RefCounted
## ============================================================================
## 数据注册中心：集中创建默认 Def 实例。
## 框架阶段用代码内置；后续可改为扫描 res://resources/defs/*.tres 加载，
## 接口保持不变。
## ============================================================================

# 资源 id 常量，全局引用
const WOOD: StringName = &"wood"
const STONE: StringName = &"stone"
const FOOD: StringName = &"food"
const GOLD: StringName = &"gold"

# 村民随机姓名池（流民定居时取名，营造「活人城镇」氛围）
const VILLAGER_SURNAMES := ["林", "苏", "陈", "赵", "洛", "顾", "沈", "叶", "秦", "宋", "唐", "白"]
const VILLAGER_GIVEN_NAMES := ["小满", "阿禾", "铁柱", "春妮", "石娃", "念安", "大山", "青儿", "木头", "阿蛮", "知秋", "稻花", "阿岩", "小穗", "长庚", "阿萤"]
# 夜袭头目随机名号
const BOSS_TITLES := ["碎颅者", "黑棘", "断牙", "血鬃", "灰爪", "夜嚎", "铁蹄", "蚀骨"]
const BOSS_NAMES := ["格罗什", "卡尔加", "莫尔戈", "乌鲁克", "德拉戈", "巴尔萨", "克鲁姆", "加尔鲁"]


static func random_villager_name() -> String:
	return VILLAGER_SURNAMES.pick_random() + VILLAGER_GIVEN_NAMES.pick_random()


static func random_boss_name() -> String:
	return "%s·%s" % [BOSS_TITLES.pick_random(), BOSS_NAMES.pick_random()]


static func starting_resources() -> Dictionary:
	# v22：采集（木材/石料）暂时屏蔽、建筑造价统一改金币 → 开局资源只发金币，
	# 金币收入 = 击杀野怪掉落（走近自动拾取）+ 任务奖励。
	return { GOLD: 150 }


# v22 采集开关：经济线重新设计前，砍树/采石不再产出资源（资源点保留为场景障碍/景观）。
# 关闭时 ResourceNode.harvest_by / harvest_carry 直接返回 0——不入账、不消耗储量、不发采集信号。
const HARVEST_INCOME_ENABLED := false

# 城镇道路与小兵生活节奏（游戏秒，随调速 / 暂停统一变化）。
const ROAD_SPEED_MULTIPLIER: float = 1.2
const SOLDIER_PATROL_SECONDS := Vector2(18.0, 30.0)
const SOLDIER_TOWN_SECONDS := Vector2(30.0, 55.0)
const SOLDIER_CHAT_RADIUS: float = 2.8
const SOLDIER_CHAT_SECONDS: float = 6.0
const SOLDIER_CHAT_COOLDOWN := Vector2(25.0, 45.0)
const SOLDIER_CHAT_LINES := [
	["今天村里真热闹。", "是啊，又来了新邻居。"],
	["巡逻回来，歇一会儿？", "好，等会儿去酒馆坐坐。"],
	["这条新路走着真省劲。", "下次出门就走这边。"],
	["最近练得怎么样？", "感觉下次能帮上更多忙。"],
]

# v43 夜间待命：夜里未编队 / 非驻守的小兵回城站在待命点，2~3 人可围站闲聊。
# 白天双人聊天契约（SOLDIER_CHAT_* / SoldierChatState）保持不动；夜间走这里的独立参数。
const SOLDIER_NIGHT_CHAT_RADIUS: float = 5.0             # 招募一起闲聊的相邻待命小兵半径（米）
const SOLDIER_NIGHT_CHAT_SECONDS := Vector2(10.5, 13.5)  # 一次夜间群聊时长
const SOLDIER_NIGHT_CHAT_COOLDOWN := Vector2(25.0, 45.0) # 群聊结束后各自回待命点的冷却
const SOLDIER_NIGHT_CHAT_LINE_INTERVAL: float = 3.0      # 轮流冒泡间隔（SpeechBubble3D 上限 3，留节流余量）
const SOLDIER_NIGHT_CHAT_LINES := [
	"今天清了两窝野怪，箭都射钝了。",
	"酒馆那桶麦酒还剩半桶，换班去喝一口？",
	"守夜别打瞌睡，东边林子刚才有动静。",
	"明早我想去矿坑那边转转，看看有没有漏网的。",
	"风大了，把火把挑旺些，别让城墙黑灯瞎火。",
	"听说北边又来了新的流民，城里越来越热闹了。",
	"今晚谁守南门？我跟他换一班。",
	"打完这仗，我就想踏踏实实睡一觉。",
]


## 夜间群聊台词（3 句随机风味 + 1 句用 TimeManager.day 生成的「第 N 夜」）。
## 返回 Array[String]；由 Soldier.try_night_chat_with 传入 TimeManager.day。
static func soldier_night_chat_lines(day: int) -> Array:
	var pool: Array = []
	for line in SOLDIER_NIGHT_CHAT_LINES:
		pool.append(String(line))
	pool.shuffle()
	var lines: Array = []
	var count: int = mini(3, pool.size())
	for i in count:
		lines.append(pool[i])
	lines.append("已经守到第 %d 夜了，大家都精神点。" % maxi(1, day))
	return lines

# v34 小队经验共享：小队里任何人击杀（主角 / 队友 / 编外巨龙），击杀者拿全额经验，
# 其余在队成员按本比例分账（「先按击杀者的 50% 算」，后续可在此调参）。
const SQUAD_XP_SHARE_RATIO: float = 0.5


## 小队非击杀者成员分到的经验（击杀者全额 base_xp，其余按 SQUAD_XP_SHARE_RATIO 折算；
## 向下取整、保底 1 点——小额击杀也不让队友白跑）。
static func squad_share_xp(base_xp: int) -> int:
	return maxi(1, int(float(base_xp) * SQUAD_XP_SHARE_RATIO))


static func resource_defs() -> Array:
	var arr: Array = []
	var wood := ResourceDef.new()
	wood.id = WOOD; wood.display_name = "木材"; wood.color = Color.SADDLE_BROWN
	arr.append(wood)
	var stone := ResourceDef.new()
	stone.id = STONE; stone.display_name = "石头"; stone.color = Color.DIM_GRAY
	arr.append(stone)
	var food := ResourceDef.new()
	food.id = FOOD; food.display_name = "食物"; food.color = Color.LIME_GREEN
	arr.append(food)
	var gold := ResourceDef.new()
	gold.id = GOLD; gold.display_name = "金币"; gold.color = Color.GOLD; gold.is_currency = true
	arr.append(gold)
	return arr


static func building_defs() -> Array:
	# v22 建筑表（3 种，造价统一金币）：删农田/市集/箭塔，新增酒馆（小兵回血）。
	# 采集经济暂时屏蔽（HARVEST_INCOME_ENABLED=false），金币靠击杀野怪掉落。
	var arr: Array = []

	var wall := BuildingDef.new()
	wall.id = &"wall"; wall.display_name = "木墙"
	wall.cost = { GOLD: 10 }
	wall.max_hp = 400.0
	wall.mesh_size = Vector3(2.0, 2.8, 0.45)
	wall.mesh_color = Color.SADDLE_BROWN
	wall.description = "围墙工事。夜袭时野怪会优先啃咬挡路的家伙。"
	wall.hotkey_hint = "数字 1 直接建造（B 菜单）"
	# Medieval-Hexagon 石墙（neutral 中性色，所有玩家通用）。真实尺寸 2.0×1.1×0.8，scale=1.15
	# → 宽 2.3 / 高 1.27m：仍占 1×1 格（v43 只做视觉放大，占地与碰撞逻辑不变）。
	wall.model_path = "res://assets/_PLACEHOLDER/medieval_hexagon_buildings/wall_straight.gltf"
	wall.model_scale = 1.15
	arr.append(wall)

	var house := BuildingDef.new()
	house.id = &"house"; house.display_name = "房屋"
	house.cost = { GOLD: 30 }
	house.max_hp = 200.0
	house.footprint = Vector2i(3, 3)               # 占 9 格（3×3 = 6×6m 场地）
	house.mesh_size = Vector3(5.2, 4.2, 5.2)        # 小于占地(6×6m)留缝，碰撞盒据此
	house.mesh_color = Color.CORAL
	house.producer_resource = FOOD
	house.producer_amount = 5
	house.producer_interval = 8.0
	house.description = "一张床位 + 后院菜园（+5 食物/8s）。空房会吸引流民入住并觉醒为随机职业小兵。"
	house.hotkey_hint = "数字 2 直接建造（B 菜单）"
	# Medieval-Hexagon 小屋（home_A）。真实 0.79×0.93×0.85，scale=6.2 → 宽 ~4.9、高 ~5.77m，
	# v43 房屋放大：3×3 格占地（6×6m）内填满主体、远高于人物 1.8m（视觉/碰撞/占格同步放大）。
	house.model_path = "res://assets/_PLACEHOLDER/medieval_hexagon_buildings/building_home_A_blue.gltf"
	house.model_scale = 6.2
	arr.append(house)

	var tavern := BuildingDef.new()
	tavern.id = &"tavern"; tavern.display_name = "酒馆"
	tavern.cost = { GOLD: 50 }
	tavern.max_hp = 220.0
	tavern.footprint = Vector2i(3, 3)               # v43：与房屋同档 3×3（6×6m）
	tavern.mesh_size = Vector3(5.2, 4.4, 5.2)
	tavern.mesh_color = Color(0.85, 0.62, 0.32)     # 麦酒琥珀色
	tavern.is_tavern = true
	tavern.heal_radius = 8.0                        # 回血光环半径（小兵入圈即回血；v43 随建筑放大 6→8m）
	tavern.heal_per_sec = 20.0                      # 光环每秒回血（约为小兵自带城内回血的 3~4 倍）
	tavern.description = "小兵的疗伤据点：馆旁 %dm 内的小兵每秒回 %.0f 血。\n小兵在城外血量低于 20%% 时会自动放下战斗、回馆疗伤。"
	tavern.description = tavern.description % [int(tavern.heal_radius), tavern.heal_per_sec]
	tavern.max_count = 1                            # v37：全场唯一——疗伤据点一座足矣，防止叠馆刷回血
	tavern.hotkey_hint = "数字 3 直接建造（B 菜单）· 全场限建 1 座"
	# Medieval-Hexagon 酒馆（building_tavern_blue）。真实 1.17×1.40×1.33，scale=4.4
	# → 宽 ~5.15、高 ~6.16m，与放大后的房屋（5.77m）同量级、填满 3×3 格。
	tavern.model_path = "res://assets/_PLACEHOLDER/medieval_hexagon_buildings/building_tavern_blue.gltf"
	tavern.model_scale = 4.4
	arr.append(tavern)

	# v26 驯龙系统：龙园——v43 起占地 4×4（8×8m，全场最大，比房屋/酒馆的 3×3 再大一圈），
	# 走近按 E 弹出驯龙界面花金币解锁巨龙（见 DragonSystem / DragonMenu / DragonMenuUI）。
	var garden := BuildingDef.new()
	garden.id = &"dragon_garden"; garden.display_name = "龙园"
	garden.cost = { GOLD: 120 }
	garden.max_hp = 400.0
	garden.footprint = Vector2i(4, 4)               # 8×8 米，全场最大占地
	garden.mesh_size = Vector3(7.2, 4.2, 7.2)       # 碰撞盒 / 预览依据（略小于占地留缝）
	garden.mesh_color = Color(0.45, 0.40, 0.55)
	garden.is_dragon_garden = true
	garden.description = "驯龙据点：走近按 [E] 打开驯龙界面，花金币解锁巨龙；\n解锁后的巨龙可随小队出战（编外第 5 位，跟随你并攻击你攻击的目标）。"
	garden.max_count = 1                            # v37：全场唯一——驯龙据点一座足矣（4×4 占地本就稀缺）
	garden.hotkey_hint = "数字 4 直接建造（B 菜单）· 全场限建 1 座"
	# 复用已导入的 Medieval-Hexagon 大厅（原兵营模型，v21 起闲置）：真实 1.44×1.64×1.57，
	# scale 4.2 → 宽 ~6.05 / 高 ~6.89m，填满 4×4 格但留出「龙院」活动余地。
	garden.model_path = "res://assets/_PLACEHOLDER/medieval_hexagon_buildings/building_barracks_blue.gltf"
	garden.model_scale = 4.2
	arr.append(garden)

	var road := BuildingDef.new()
	road.id = &"dirt_road"; road.display_name = "土路"
	road.is_road = true
	road.bakes_into_navmesh = false
	road.cost = { GOLD: 1 }
	road.mesh_size = Vector3(2.0, 0.04, 2.0)
	road.mesh_color = Color(0.62, 0.46, 0.28)
	road.description = "长按左键拖动连续铺路，路口自动连接。流民和友方小兵优先沿路行走，路上移速 +20%。"
	road.hotkey_hint = "数字 5 铺土路 · 长按左键拖动 · 自动连接"
	arr.append(road)

	return arr


# ---- v37 建筑数量上限：全场唯一建筑（酒馆 / 龙园）的数据侧判定 ----

## 场上存活的某类建筑数量（按建筑 def.id 匹配 "building" 分组；无建筑系统时返回 0）。
static func count_placed_buildings(tree: SceneTree, building_id: StringName) -> int:
	if tree == null or String(building_id) == "":
		return 0
	var n := 0
	for node in tree.get_nodes_in_group("building"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var b := node as Building
		if b != null and b.def != null and b.def.id == building_id:
			n += 1
	return n


## 该建筑是否已达 max_count 上限（max_count ≤ 0 = 无限量，恒为 false）。
static func building_at_limit(tree: SceneTree, def: BuildingDef) -> bool:
	if def == null or def.max_count <= 0:
		return false
	if String(def.id) == "":
		# 受限建筑漏填 id → 计数永远为 0、上限静默失效；宁可吵一点也不要静默（v37）
		push_warning("BuildingDef.max_count=%d 但 id 为空，数量上限无法生效（%s）" % [def.max_count, def.display_name])
		return false
	return count_placed_buildings(tree, def.id) >= def.max_count


static func colonist_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"colonist"; d.display_name = "村民"
	d.max_hp = 90.0
	d.move_speed = 4.3
	d.attack_damage = 6.0
	d.attack_range = 2.0
	d.attack_cooldown = 1.2
	d.mesh_color = Color(0.72, 0.82, 0.86)
	d.team = 0
	d.is_auto_fighter = false          # 村民不参战：遇敌逃跑（VillagerFleeState）
	d.carry_capacity = 10              # 一次背 10 份资源回城入库
	d.regen_per_sec = 2.0              # 城内缓慢回血
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"
	# KayKit 占位 GLB 以 +Z 为正面；项目逻辑统一以 Godot 的 -Z 为前方。
	d.model_face_offset_deg = 180.0
	# 村民外观多样化：每个实例从候选池随机抽一个模型（KayKit 同骨架，动画映射通用、朝向偏移一致）
	d.model_path_pool = [
		"res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb",               # Rogue
		"res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb",     # Barbarian
		"res://assets/_PLACEHOLDER/characters/placeholder_colonist_mage.glb",          # Mage
		"res://assets/_PLACEHOLDER/characters/placeholder_colonist_rogue_hooded.glb",  # Rogue 兜帽版
	]
	return d


## 流民：统一兜帽游侠模型、空手（不显示任何武器）——「还在路上的陌生人」。
## 定居后由 SettlementSystem 转成随机职业的小兵（见 settler_*_def）。
static func refugee_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"refugee"; d.display_name = "流民"
	d.max_hp = 80.0
	d.move_speed = 4.0
	d.attack_damage = 0.0
	d.attack_range = 2.0
	d.attack_cooldown = 1.2
	d.mesh_color = Color(0.72, 0.82, 0.86)
	d.team = 0
	d.is_auto_fighter = false
	d.carry_capacity = 0
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist_rogue_hooded.glb"
	d.model_face_offset_deg = 180.0
	# 该模型手上挂着匕首/弩全部变体；指定不存在的名字 = 双手空空（流民不带武器）
	d.model_weapon_main = &"none"
	d.model_weapon_offhand = &"none"
	return d


static func raider_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"raider"; d.display_name = "掠夺者"
	d.max_hp = 70.0
	d.move_speed = 3.5
	d.attack_damage = 9.0
	d.attack_range = 1.8
	d.attack_cooldown = 1.2
	d.mesh_color = Color.TOMATO
	d.team = 1
	d.xp_value = 10
	d.loot_gold = 10                 # v22 赏金提升（原 5）：金币是唯一建造货币，击杀是主要收入
	d.flee_hp_ratio = 0.25            # 血线：低于它才考虑逃跑（夜袭攻城时不逃）
	d.flee_chance = 0.2               # v35 小概率怂怪：低血时约 1/5 才跑，其余死战——
	                                  # 近战小兵追不上 1.5× 速的逃跑怪，多数怪站桩让近战能正常输出
	# v20.3 怪物属性（对应小兵六维复审）：HP 60→80 / 攻 8→9 / 防 2 / XP 8→10——
	# 杂兵按「量取胜」风格：单只能扛小兵 3~5 拍（原 2~4 拍即死），夜潮存在感拉满；
	# 轻防御几乎无感（−2.4%），仅接入六维框架。防 3.5 移速追不上任何职业，靠围城施压。
	d.defense = 2.0
	# v21 怪物皮：原「KayKit 野蛮人染暗红」换成 Quaternius Ultimate Monsters（CC0）怪物。
	# 普通野怪从池里随机抽一个 → 夜潮里一群怪不再全是同一张脸（与殖民者 model_path_pool 同范式）。
	# 池内为 Big/Blob 组地面怪，动画名统一为 Idle/Walk/Run/Punch(或 Bite_Front)/Death，
	# 已被 PawnModelRig.ANIM_CANDIDATES 的候选回退覆盖，无需 per-def anim_map。
	d.model_path = "res://assets/_PLACEHOLDER/monsters/Orc.gltf"
	d.model_path_pool = [
		"res://assets/_PLACEHOLDER/monsters/Orc.gltf",
		"res://assets/_PLACEHOLDER/monsters/Ninja.gltf",
		"res://assets/_PLACEHOLDER/monsters/Cactoro.gltf",
		"res://assets/_PLACEHOLDER/monsters/Yeti.gltf",
		"res://assets/_PLACEHOLDER/monsters/GreenBlob.gltf",
	]
	d.model_face_offset_deg = 180.0
	# 缩放按**真机渲染高度**定（tools/monster_skin_shot.tscn 实测；人类小兵标尺 2.80m）。
	# 静态 AABB 双向失准（T-pose 张臂/绑定姿态），不能用来反推——本项目龙的实例是 AABB 10.45 vs 实渲 5.68。
	# 目标：杂兵约 1.6~1.8m（≈0.62× 人类，高矮不齐 = 野怪自然体型差异）。
	d.model_scale = 0.55              # 实渲约 1.23(Yeti)~2.11(Cactoro)m
	d.model_tint = Color(1.0, 0.62, 0.52)   # 保留原「暗红野怪」的阵营暗示
	return d


## 序章驻守匪徒：明确的人形敌人，沿用普通野怪的经验与掉落口径。
static func prologue_raider_def() -> PawnDef:
	var d := raider_def()
	d.id = &"prologue_guard"
	d.display_name = "匪徒"
	d.max_hp = 45.0
	d.attack_damage = 7.0
	d.move_speed = 3.0
	d.flee_chance = 0.0
	d.model_path_pool.clear()
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb"
	d.model_scale = 1.02
	d.model_tint = Color(0.95, 0.64, 0.53)
	d.model_weapon_main = &"2H_Axe"
	d.model_weapon_offhand = &"none"
	d.anim_map = {&"fight": ["2H_Melee_Attack_Slice", "2H_Melee_Attack_Chop"]}
	return d


static func raider_elite_def() -> PawnDef:
	var d := raider_def()
	d.id = &"raider_elite"; d.display_name = "精英掠夺者"
	d.max_hp = 190.0
	d.move_speed = 3.7
	d.attack_damage = 14.0
	d.attack_range = 2.0
	d.attack_cooldown = 1.1
	d.mesh_color = Color.ORANGE_RED
	d.xp_value = 25
	d.loot_gold = 45                  # v22 赏金提升（原 25）
	d.flee_hp_ratio = 0.2
	d.flee_chance = 0.15              # v35 精英更悍：低血仅 15% 概率逃跑
	# v20.3 精英六维（中坚风格）：HP 170→200 / 防 10（−11%）/ 暴击 10%——
	# 需要小兵 2~3 人围殴（单人 14+ 拍），暴击 ×2 偶发重击制造治疗压力（酒馆存在感）。
	d.defense = 10.0
	d.crit_rate = 0.10
	# 精英换「蘑菇王」：体型更高、戴冠，一眼认出精英。
	d.model_path = "res://assets/_PLACEHOLDER/monsters/MushroomKing.gltf"
	d.model_path_pool = []            # 精英固定造型（不参与普通怪的随机池）
	d.model_scale = 0.66              # 实渲约 2.31m（≈0.82× 人类，精英应明显高于杂兵）
	d.model_tint = Color(1.0, 0.45, 0.36)
	return d


static func raider_boss_def() -> PawnDef:
	var d := raider_def()
	d.id = &"raider_boss"; d.display_name = "夜袭头目"
	d.max_hp = 750.0
	d.move_speed = 3.9
	d.attack_damage = 26.0
	d.attack_range = 2.6
	d.attack_cooldown = 1.4
	d.mesh_color = Color.CRIMSON
	d.xp_value = 90
	d.loot_gold = 200                 # v22 赏金提升（原 120）
	d.flee_hp_ratio = 0.0             # 头目死战不退
	d.is_boss = true
	# v20.3 头目六维（攻城兵器风格）：HP 650→800 / 攻 24→26 / 防 20（−20%）/ 暴击 15%——
	# 战士单挑 ~8 击必倒（需轮换或酒馆），全队集火 ~13s；主角重击 ×0.8 仍是最优解。
	# 夜潮节奏核算：普通 70 HP ≈ 全队 6~8s 清一波 < 9s 波间隔——防线可守但有漏刀，
	# 漏怪由 1000 HP 主城与城墙吸收（浸泡实测 80 HP 会滚雪球攻破主城，70 是平衡点）。
	d.defense = 20.0
	d.crit_rate = 0.15
	# 头目换「幽灵」：飞行怪 + 紫染，与地面杂兵区分最明显（夜袭头目从夜潮里飘来）。
	# is_flying_unit 让动画走飞行回退（idle→Flying_Idle、run→Fast_Flying）。
	d.model_path = "res://assets/_PLACEHOLDER/monsters/Ghost.gltf"
	d.model_path_pool = []
	d.is_flying_unit = true
	d.model_scale = 1.06              # 实渲约 3.29m ≈ 1.18× 人类身高（比精英 2.31m 再高一档，压得住场）
	d.model_tint = Color(0.85, 0.42, 1.0)
	return d


# ---- 小兵 = 流民定居四职业（v21 起唯一小兵来源）----
# v21 前这里还有「兵营近战兵 / 远程兵」两种小兵与配套训练条目——兵营删除后全部移除，
# 所有小兵都由房屋吸引流民、入住觉醒为下列四职业之一（见 SettlementSystem）。
# 战士：野蛮人体格 + 双手斧，贴身重击（近战 2.2m）＋ 血怒（吸血增伤）
# 法师：法师体格 + 长杖（左手），远程弹幕（10m 最远）＋ 暴风雪（范围减速）
# 刺客：游侠体格 + 双匕首，快速贴身连刺（近战 1.7m、攻速最快）＋ 背刺（闪现重伤）
# 游侠：游侠体格 + 手弩，中远程风筝（9.5m）＋ 快速射击（三连射挂易伤）
# 普攻距离由 attack_range 决定：法师 > 游侠 > 战士 > 刺客。
# v19：四职业各配一个主动技能（见 skill_*_def，全部带 CD 与特效/显示），
# 游侠另有基础被动——移速比其他小怪快 25%（全职业最快脚程）。
# v20 属性系统：四职业各按风格配防御 / 暴击率基础值并开启等级成长（can_level）
# ——战士防最高、法师攻最高、刺客暴击最高、游侠腿最快（v21 起为仅有的四种小兵）。
# v24 属性复审（适配 v21+ 新形态）：修正「肉盾比远程carry输出还高」的倒挂——
# Lv.1 期望 DPS 刺客 20.9 > 法师 16.8(+暴风雪 AoE) > 游侠 13.1 > 战士 13.7(血怒期 20.5)；
# 防御拉开到 6/10/12/28 四档（每档差 ≥2 个百分点减伤）；坦克靠 EHP（165×1.35）站桩。

static func settler_def_ids() -> Array:
	return [&"settler_warrior", &"settler_mage", &"settler_assassin", &"settler_archer"]


## 随机返回一个定居职业 def（流民入驻时调用）。
static func random_settler_def() -> PawnDef:
	match settler_def_ids().pick_random():
		&"settler_warrior": return settler_warrior_def()
		&"settler_mage": return settler_mage_def()
		&"settler_assassin": return settler_assassin_def()
		_: return settler_archer_def()


## 按职业 id 取定居职业 def（基础四职业 + 八个进阶职业均可取；查无回落游侠）。
## 流民入住的职业选择（v25）与转职共用本入口。
static func settler_def(class_id: StringName) -> PawnDef:
	match class_id:
		&"settler_warrior": return settler_warrior_def()
		&"settler_mage": return settler_mage_def()
		&"settler_assassin": return settler_assassin_def()
		&"settler_archer": return settler_archer_def()
		_: return settler_advanced_def(class_id)


static func settler_warrior_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"settler_warrior"; d.display_name = "战士"
	d.max_hp = 165.0
	d.move_speed = 4.0
	d.attack_damage = 14.0
	d.attack_range = 2.2            # 双手斧近战
	d.attack_cooldown = 1.1
	d.mesh_color = Color(0.85, 0.55, 0.4)
	d.team = 0
	d.is_auto_fighter = true
	d.attack_kind = PawnDef.AttackKind.MELEE
	d.regen_per_sec = 6.0
	d.xp_value = 0
	d.loot_gold = 0
	# v24 属性复审（重装风格）：血最厚 + 防最高（−26% 受伤），贴身对拼靠血怒续；
	# 持续输出全职业垫底——坦克不该同时是最高输出
	d.defense = 28.0
	d.crit_rate = 0.08
	d.can_level = true
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb"
	d.model_face_offset_deg = 180.0
	d.model_scale = 1.12
	# 双手斧在右手挂点；左手留空（2H 武器不配盾）
	d.model_weapon_main = &"2H_Axe"
	d.model_weapon_offhand = &"none"
	# 动作匹配：双手斧走 2H 横斩（旧版播 1H 单手剑动作，与武器不符）；
	# 血怒起手把 cast 覆盖成举臂吼叫（Cheer），贴合「仰天暴怒」的表现
	d.anim_map = {
		&"fight": ["2H_Melee_Attack_Slice", "2H_Melee_Attack_Chop"],
		&"cast": ["Cheer", "Spellcast_Raise"],
	}
	d.class_icon = "战"; d.class_color = Color(0.92, 0.5, 0.34)
	# v19 主动技能：血怒（6s 内伤害 ×1.5、造成伤害 60% 吸血，CD 15s）
	d.skill = skill_blood_rage_def()
	# v25：拥有技能树（升级得技能点）；Lv.5 可转职 狂战士 / 骑士
	d.skill_tree_id = &"generic"
	d.promotes_to = [&"settler_berserker", &"settler_knight"]
	return d


static func settler_mage_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"settler_mage"; d.display_name = "法师"
	d.max_hp = 80.0
	d.move_speed = 3.7
	d.attack_damage = 24.0
	d.attack_range = 10.0           # 全职业最远普攻距离
	d.attack_cooldown = 1.6
	d.mesh_color = Color(0.5, 0.7, 1.0)
	d.team = 0
	d.is_auto_fighter = true
	d.attack_kind = PawnDef.AttackKind.RANGED
	d.projectile_speed = 14.0
	d.kite_safe_range = 6.0         # 被近身就后撤拉开距离
	d.regen_per_sec = 5.0
	d.xp_value = 0
	d.loot_gold = 0
	# v24 属性复审（玻璃大炮风格）：全职业最高单发攻击 + 远程持续输出第二，
	# 血最薄防最低——输出身份终于配得上玻璃体质
	d.defense = 6.0
	d.crit_rate = 0.14
	d.can_level = true
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist_mage.glb"
	d.model_face_offset_deg = 180.0
	d.model_scale = 1.0
	# 长杖在该模型的右手挂点（左手是咒语书）；主手持杖、副手空
	d.model_weapon_main = &"2H_Staff"
	d.model_weapon_offhand = &"none"
	# 动作匹配：远程法弹走施法投掷（Spellcast_Shoot 举杖甩出，旧版播 1H 近战挥砍），
	# 暴风雪用举杖引导（Spellcast_Raise）
	d.anim_map = {
		&"shoot": ["Spellcast_Shoot", "Spellcasting"],
		&"cast": ["Spellcast_Raise", "Spellcasting"],
	}
	d.class_icon = "法"; d.class_color = Color(0.5, 0.72, 1.0)
	# v19 主动技能：暴风雪（目标地点 AoE，逐跳伤害 + 减速，CD 9s）
	d.skill = skill_blizzard_def()
	# v25：技能树 + Lv.5 转职 元素法师 / 雷电法师
	d.skill_tree_id = &"generic"
	d.promotes_to = [&"settler_elementalist", &"settler_storm_mage"]
	return d


static func settler_assassin_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"settler_assassin"; d.display_name = "刺客"
	d.max_hp = 90.0
	d.move_speed = 5.0               # 全职业最快脚程（次于游侠被动）
	d.attack_damage = 9.0
	d.attack_range = 1.7             # 匕首贴身（全职业最近）
	d.attack_cooldown = 0.55         # 攻速最快
	d.mesh_color = Color(0.55, 0.9, 0.65)
	d.team = 0
	d.is_auto_fighter = true
	d.attack_kind = PawnDef.AttackKind.MELEE
	d.regen_per_sec = 5.0
	d.xp_value = 0
	d.loot_gold = 0
	# v24 属性复审（暴击流风格）：全职业最高暴击率 + 攻速最快——期望单挑输出第一
	# （背刺先手再加爆发），但血薄防中——打得快也死得快
	d.defense = 12.0
	d.crit_rate = 0.28
	d.can_level = true
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"
	d.model_face_offset_deg = 180.0
	d.model_scale = 1.02
	# 双匕首：主手 Knife + 副手 Knife_Offhand
	d.model_weapon_main = &"Knife"
	d.model_weapon_offhand = &"Knife_Offhand"
	# 动作匹配：双持走 Dualwield 挥砍（旧版播单手 1H 动作，副手匕首不参与）
	d.anim_map = {
		&"fight": ["Dualwield_Melee_Attack_Slice", "1H_Melee_Attack_Slice_Horizontal"],
	}
	# 攻速匹配：Dualwield_Slice 1.17s ÷ 攻击间隔 0.55s ≈ ×1.9——连刺节奏与动作同步
	d.attack_anim_speed = 1.9
	d.class_icon = "刺"; d.class_color = Color(0.55, 0.9, 0.62)
	# v19 主动技能：背刺（7m 内闪现目标身后重击，CD 就绪优先先手，CD 10s）
	d.skill = skill_backstab_def()
	# v25：技能树 + Lv.5 转职 暗杀者 / 忍者
	d.skill_tree_id = &"generic"
	d.promotes_to = [&"settler_slayer", &"settler_ninja"]
	return d


static func settler_archer_def() -> PawnDef:
	var d := PawnDef.new()
	d.id = &"settler_archer"; d.display_name = "游侠"
	d.max_hp = 85.0
	# v19 基础被动：移速比其他小怪快 25%（原 4.2 × 1.25 = 5.25，全职业最快，
	# 超过刺客 5.0）——「游侠腿快」的职业身份一眼可辨
	d.move_speed = 5.25
	d.attack_damage = 14.0
	d.attack_range = 9.5            # 中远程
	d.attack_cooldown = 1.3
	d.mesh_color = Color(0.95, 0.85, 0.42)
	d.team = 0
	d.is_auto_fighter = true
	d.attack_kind = PawnDef.AttackKind.RANGED
	d.projectile_speed = 18.0
	d.kite_safe_range = 5.0
	d.regen_per_sec = 5.0
	d.xp_value = 0
	d.loot_gold = 0
	# v24 属性复审（灵巧射手风格）：全职业最快脚程 + 次高暴击——放风筝的同时赌要害；
	# 血防偏低，被追上就难受
	d.defense = 10.0
	d.crit_rate = 0.22
	d.can_level = true
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"
	d.model_face_offset_deg = 180.0
	d.model_scale = 1.02
	# 手弩（单手弩）在主手；副手空
	d.model_weapon_main = &"1H_Crossbow"
	d.model_weapon_offhand = &"none"
	# 动作匹配：手弩射击走 1H_Ranged_Shoot（举弩击发，旧版播 1H 近战挥砍）
	d.anim_map = {
		&"shoot": ["1H_Ranged_Shoot", "Throw"],
	}
	d.class_icon = "游"; d.class_color = Color(0.95, 0.85, 0.42)
	# v19 主动技能：快速射击（三连射 + 给目标挂 3s 易伤，CD 8s）
	d.skill = skill_rapid_shot_def()
	# v25：技能树 + Lv.5 转职 狙击手 / 漫游射手
	d.skill_tree_id = &"generic"
	d.promotes_to = [&"settler_sniper", &"settler_wanderer"]
	return d


# ---- v25 转职（进阶职业）：Lv.5 起二选一，四职业 × 2 = 8 个进阶 def ----
# 战士 → 狂战士（输出）/ 骑士（重甲）；法师 → 元素法师（更爆）/ 雷电法师（更快）；
# 游侠 → 狙击手（更远更痛）/ 漫游射手（更快更活）；刺客 → 暗杀者（暴击）/ 忍者（极速）。
# 数值为基础职业的风格化微调（框架先行，后续平衡再调）；模型/武器沿用基础职业，
# 以字徽 / 配色 / 染色区分。进阶 def 自身 promotes_to 为空（不可再转）。

## 转职等级门槛（Soldier.can_promote / 市民管理界面按钮据此显示）。
const PROMOTE_LEVEL: int = 5

## 基础职业 → 可选进阶职业 id。
static func settler_advanced_ids(base_id: StringName) -> Array[StringName]:
	match base_id:
		&"settler_warrior": return [&"settler_berserker", &"settler_knight"]
		&"settler_mage": return [&"settler_elementalist", &"settler_storm_mage"]
		&"settler_archer": return [&"settler_sniper", &"settler_wanderer"]
		&"settler_assassin": return [&"settler_slayer", &"settler_ninja"]
	return []


## 进阶职业 id → def（查无返回 null）。
static func settler_advanced_def(adv_id: StringName) -> PawnDef:
	match adv_id:
		&"settler_berserker":
			var d := settler_warrior_def()
			d.id = adv_id; d.display_name = "狂战士"
			d.class_icon = "狂"; d.class_color = Color(1.0, 0.42, 0.3)
			d.model_tint = Color(1.0, 0.62, 0.55)
			# 输出形态：更痛更暴，血防略降——越战越勇
			d.max_hp = 150.0; d.attack_damage = 17.0; d.defense = 22.0; d.crit_rate = 0.14
			d.regen_per_sec = 7.0
			d.skill.damage_mult = 1.7      # 血怒增伤更凶
			# v33 进阶职业技能：跳劈（前摇 → 跃击落点 → 圆形 AOE + 击飞控制）
			# 专属技能树让玩家在转职后重新分配点数点亮「跳劈」节点
			d.extra_skills = [skill_leap_slam_def()]
			d.skill_tree_id = &"settler_berserker_tree"
			d.promotes_to = []
			return d
		&"settler_knight":
			var k := settler_warrior_def()
			k.id = adv_id; k.display_name = "骑士"
			k.class_icon = "骑"; k.class_color = Color(0.75, 0.82, 0.95)
			k.model_tint = Color(0.8, 0.85, 1.0)
			# 重甲形态：血更厚防更高，输出略降——站得住的前排
			k.max_hp = 200.0; k.attack_damage = 13.0; k.defense = 34.0; k.crit_rate = 0.05
			k.regen_per_sec = 8.0
			k.skill.lifesteal_ratio = 0.75  # 血怒吸血更足
			k.promotes_to = []
			return k
		&"settler_elementalist":
			var e := settler_mage_def()
			e.id = adv_id; e.display_name = "元素法师"
			e.class_icon = "元"; e.class_color = Color(0.45, 0.9, 0.85)
			e.model_tint = Color(0.6, 0.95, 0.9)
			# 元素形态：单发与暴风雪都更痛
			e.attack_damage = 27.0
			e.skill.damage = 10.0; e.skill.radius = 5.0
			# v33 进阶职业技能：陨石术（长吟唱 → 落点预警 → 高额 AoE，可被躲避）
			e.extra_skills = [skill_meteor_def()]
			e.skill_tree_id = &"settler_elementalist_tree"
			e.promotes_to = []
			return e
		&"settler_storm_mage":
			var s := settler_mage_def()
			s.id = adv_id; s.display_name = "雷电法师"
			s.class_icon = "雷"; s.class_color = Color(0.78, 0.62, 1.0)
			s.model_tint = Color(0.82, 0.7, 1.0)
			# 雷暴形态：出手更快、范围更小更频繁（Placeholder 复用暴风雪表现，后续换专属特效）
			s.attack_damage = 22.0; s.crit_rate = 0.22
			s.skill.display_name = "雷暴"
			s.skill.cooldown = 6.5; s.skill.radius = 3.6; s.skill.duration = 2.0
			s.promotes_to = []
			return s
		&"settler_sniper":
			var n := settler_archer_def()
			n.id = adv_id; n.display_name = "狙击手"
			n.class_icon = "狙"; n.class_color = Color(1.0, 0.72, 0.38)
			n.model_tint = Color(1.0, 0.8, 0.55)
			# 狙击形态：更远更痛更致命，出手更慢
			n.attack_damage = 18.0; n.attack_range = 12.0; n.attack_cooldown = 1.8
			n.crit_rate = 0.28
			n.skill.cast_range = 12.0; n.skill.damage = 16.0
			# v33 进阶职业技能：贯穿射击（大号弹体直线贯穿一串目标，射程很远）
			n.extra_skills = [skill_piercing_shot_def()]
			n.skill_tree_id = &"settler_sniper_tree"
			n.promotes_to = []
			return n
		&"settler_wanderer":
			var w := settler_archer_def()
			w.id = adv_id; w.display_name = "漫游射手"
			w.class_icon = "漫"; w.class_color = Color(0.65, 1.0, 0.55)
			w.model_tint = Color(0.72, 1.0, 0.65)
			# 漫游形态：腿更快、射更快，伤害略降——放风筝大师
			w.max_hp = 90.0; w.attack_damage = 13.0; w.attack_cooldown = 0.95
			w.move_speed = 5.8
			w.promotes_to = []
			return w
		&"settler_slayer":
			var y := settler_assassin_def()
			y.id = adv_id; y.display_name = "暗杀者"
			y.class_icon = "暗"; y.class_color = Color(0.95, 0.35, 0.4)
			y.model_tint = Color(1.0, 0.5, 0.55)
			# 暴击形态：要害一击
			y.attack_damage = 10.0; y.crit_rate = 0.40; y.crit_multiplier = 2.4
			y.skill.damage = 40.0
			# v33 进阶职业技能：隐身（模型 shader 隐身态，敌人一段时间内索敌不到）
			y.extra_skills = [skill_stealth_def()]
			y.skill_tree_id = &"settler_slayer_tree"
			y.promotes_to = []
			return y
		&"settler_ninja":
			var j := settler_assassin_def()
			j.id = adv_id; j.display_name = "忍者"
			j.class_icon = "忍"; j.class_color = Color(0.62, 0.78, 1.0)
			j.model_tint = Color(0.65, 0.75, 0.95)
			# 极速形态：手最快、腿也快
			j.max_hp = 85.0; j.defense = 10.0; j.attack_cooldown = 0.45
			j.move_speed = 5.6; j.crit_rate = 0.30
			j.skill.cooldown = 8.0
			j.promotes_to = []
			return j
	return null


# ---- v25 技能树 ----
## 按树 id 取技能树布局。市民通用树（职业技根节点需点亮）+ 主角树（根节点
## 随职业预点亮，主角 Q/C 技能不参与门禁）+ v33 四棵进阶职业树（多一个「新技能」节点）。
## 运行时（PawnSkillTree）与 UI 均数据驱动、无需改动。
static func skill_tree_def(tree_id: StringName) -> SkillTreeDef:
	match tree_id:
		&"hero":
			return _generic_tree_def(true)
		# ---- v33 进阶职业树：转职后换树（转职时点数全额返还，玩家重新分配）----
		&"settler_berserker_tree":
			return _advanced_tree_def(tree_id, "狂战士", &"blood_rage", "血怒", &"leap_slam", "跳劈", "跳")
		&"settler_elementalist_tree":
			return _advanced_tree_def(tree_id, "元素法师", &"blizzard", "暴风雪", &"meteor", "陨石术", "陨")
		&"settler_sniper_tree":
			return _advanced_tree_def(tree_id, "狙击手", &"rapid_shot", "快速射击", &"piercing_shot", "贯穿射击", "贯")
		&"settler_slayer_tree":
			return _advanced_tree_def(tree_id, "暗杀者", &"backstab", "背刺", &"stealth", "隐身", "隐")
		_:
			return _generic_tree_def(false)


## 通用技能树（v25.1 树状布局）：
##   根「职业技」（点亮后解锁该职业主动技能，1 级）
##     └→ 分支一「伤害强化」5 级（每级 +5% 攻击伤害）
##           └→ 分支二「生命强化」5 级（每级 +6% 生命上限）
## pre_unlock_root = 根节点初始已点亮（主角树用——技能不锁，节点只作树根 lineage）。
static func _generic_tree_def(pre_unlock_root: bool) -> SkillTreeDef:
	var t := SkillTreeDef.new()
	t.id = &"hero" if pre_unlock_root else &"generic"
	t.display_name = "技能树"

	var root := SkillNodeDef.new()
	root.id = &"class_skill"; root.branch = 0
	root.display_name = "职业技"
	root.desc = "点亮后解锁该职业的主动技能"
	root.max_rank = 1
	root.unlocks_skill = true
	root.pre_unlocked = pre_unlock_root
	root.icon = "技"; root.color = Color(1.0, 0.85, 0.35)

	var dmg := SkillNodeDef.new()
	dmg.id = &"damage"; dmg.branch = 1
	dmg.display_name = "伤害强化"
	dmg.desc = "每级攻击伤害 +5%（满级 +25%）"
	dmg.max_rank = 5
	dmg.damage_per_rank = 0.05
	dmg.requires_node = &"class_skill"; dmg.requires_rank = 1
	dmg.icon = "伤"; dmg.color = Color(1.0, 0.62, 0.3)

	var hp := SkillNodeDef.new()
	hp.id = &"vitality"; hp.branch = 2
	hp.display_name = "生命强化"
	hp.desc = "每级生命上限 +6%（满级 +30%）"
	hp.max_rank = 5
	hp.hp_per_rank = 0.06
	hp.requires_node = &"damage"; hp.requires_rank = 1
	hp.icon = "生"; hp.color = Color(0.45, 0.95, 0.55)

	t.nodes = [root, dmg, hp]
	t.gate_node_id = &"class_skill"
	return t


## v33 进阶职业树：在通用树结构上加一个「新技能」节点（转职专属主动技能）。
## 布局（UI 按 branch 分列、按 requires_node 连线）：
##   branch 0 「职业技」根 —— 解锁主技能（血怒 / 暴风雪 / 快速射击 / 背刺）
##   branch 1 「新技能」 —— 需点亮职业技，解锁跳劈 / 陨石术 / 贯穿射击 / 隐身
##   branch 2 「伤害强化」5 级（需职业技）→ branch 3 「生命强化」5 级（需伤害强化 1 级）
static func _advanced_tree_def(tree_id: StringName, class_name_cn: String,
		primary_id: StringName, primary_name: String, new_id: StringName,
		new_name: String, new_icon: String) -> SkillTreeDef:
	var t := SkillTreeDef.new()
	t.id = tree_id
	t.display_name = "%s · 技能树" % class_name_cn

	var root := SkillNodeDef.new()
	root.id = &"class_skill"; root.branch = 0
	root.display_name = "职业技"
	root.desc = "点亮后解锁「%s」" % primary_name
	root.max_rank = 1
	root.unlocks_skill = true
	root.unlocks_skill_id = primary_id
	root.icon = "技"; root.color = Color(1.0, 0.85, 0.35)

	# 转职专属技能节点：转职后点数已全额返还，玩家在此把它点亮
	var adv := SkillNodeDef.new()
	adv.id = &"advanced_skill"; adv.branch = 1
	adv.display_name = new_name
	adv.desc = "转职专属：点亮后解锁「%s」" % new_name
	adv.max_rank = 1
	adv.unlocks_skill = true
	adv.unlocks_skill_id = new_id
	adv.requires_node = &"class_skill"; adv.requires_rank = 1
	adv.icon = new_icon; adv.color = Color(1.0, 0.62, 0.3)

	var dmg := SkillNodeDef.new()
	dmg.id = &"damage"; dmg.branch = 2
	dmg.display_name = "伤害强化"
	dmg.desc = "每级攻击伤害 +5%（满级 +25%）"
	dmg.max_rank = 5
	dmg.damage_per_rank = 0.05
	dmg.requires_node = &"class_skill"; dmg.requires_rank = 1
	dmg.icon = "伤"; dmg.color = Color(1.0, 0.62, 0.3)

	var hp := SkillNodeDef.new()
	hp.id = &"vitality"; hp.branch = 3
	hp.display_name = "生命强化"
	hp.desc = "每级生命上限 +6%（满级 +30%）"
	hp.max_rank = 5
	hp.hp_per_rank = 0.06
	hp.requires_node = &"damage"; hp.requires_rank = 1
	hp.icon = "生"; hp.color = Color(0.45, 0.95, 0.55)

	t.nodes = [root, adv, dmg, hp]
	t.gate_node_id = &"class_skill"
	return t


# ---- 四职业技能定义（v19：每个技能都有 CD > 0、都有特效或显示）----

## 法师 · 暴风雪：在目标地点落下暴风雪区域（半径 4.5m，比普攻判定大一圈），
## 持续 3s 每 0.5s 一跳伤害并减速 45%（逐跳刷新）。
static func skill_blizzard_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"blizzard"; s.display_name = "暴风雪"
	s.kind = PawnSkillDef.Kind.BLIZZARD
	s.cooldown = 9.0
	s.cast_range = 10.0             # 与普攻射程一致（进射程即可施放）
	s.damage = 8.0                  # 每跳伤害（3s 共 6 跳）
	s.radius = 4.5
	s.duration = 3.0
	s.tick_interval = 0.5
	s.slow_factor = 0.55            # 移速减到 55%
	s.slow_duration = 1.2
	return s


## 战士 · 血怒：6s 内伤害 ×1.5、造成伤害的 60% 转化为自身回血。
static func skill_blood_rage_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"blood_rage"; s.display_name = "血怒"
	s.kind = PawnSkillDef.Kind.BLOOD_RAGE
	s.cooldown = 15.0
	s.cast_range = 0.0              # 自身增益：无距离要求，接战即怒
	s.damage = 0.0
	s.buff_duration = 6.0
	s.damage_mult = 1.5
	s.lifesteal_ratio = 0.6
	return s


## 游侠 · 快速射击：0.14s 间隔连射 3 箭（每箭等同普攻伤害），
## 并给目标挂 3s 易伤（受到伤害 +30%）。
static func skill_rapid_shot_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"rapid_shot"; s.display_name = "快速射击"
	s.kind = PawnSkillDef.Kind.RAPID_SHOT
	s.cooldown = 8.0
	s.cast_range = 9.5              # 与普攻射程一致
	s.damage = 12.0                 # 每箭伤害
	s.shot_count = 3
	s.shot_interval = 0.14
	s.vuln_mult = 1.3               # 易伤：受伤 +30%
	s.vuln_duration = 3.0
	return s


## 刺客 · 背刺：闪现到目标身后 1.1m 造成大量伤害（约 3.5 倍普攻）；
## 施法距离 7m 远大于普攻 1.7m——CD 就绪时由战斗状态优先先手释放。
static func skill_backstab_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"backstab"; s.display_name = "背刺"
	s.kind = PawnSkillDef.Kind.BACKSTAB
	s.cooldown = 10.0
	s.cast_range = 7.0              # 突进距离（远超普攻 1.7m）
	s.damage = 32.0                 # 单次重伤
	return s


# ---- v33 进阶职业技能定义（狂战士 / 元素法师 / 狙击手 / 暗杀者各一个）----
# 定位：转职才拿得到的「招牌技」，全部带前摇或条件，靠技能树节点（unlocks_skill_id）解锁。
# 数值口径：比基础四技能更强，但都有可被对手利用的破绽（前摇 / 预警 / 冷却更长）。

## 狂战士 · 跳劈：较长前摇（0.55s 原地蓄力）后跃向锁定落点砸地，
## 落点半径 3.4m 内单次圆形 AoE 伤害，并把怪物**击飞**（滞空 0.55s）**并控制**（落地眩晕 1.1s）。
static func skill_leap_slam_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"leap_slam"; s.display_name = "跳劈"
	s.kind = PawnSkillDef.Kind.LEAP_SLAM
	s.cooldown = 14.0
	s.cast_range = 8.0             # 跃击距离上限（再远就够不着，回落血怒/普攻）
	s.damage = 34.0                # 落地单次伤害（圈内全体）
	s.windup = 0.55                # 前摇：举斧蓄力，期间不动不出手
	s.recover = 0.30
	s.radius = 3.4                 # 落地圆形 AoE 半径
	s.leap_speed = 16.0            # 滞空水平速度（时长 = 距离/速度，钳 0.25~0.9s）
	s.leap_height = 3.0            # 抛物线顶点高度
	s.knockback_distance = 3.2     # 击飞水平位移
	s.knockback_height = 2.6       # 击飞高度
	s.airborne_time = 0.55         # 击飞滞空时长
	s.stun_duration = 1.1          # 落地眩晕（控制）时长
	return s


## 元素法师 · 陨石术：**长前摇**（1.0s 原地吟唱）后在「吟唱瞬间锁定的目标位置」落下陨石，
## 预警圈 1.1s 后落地，半径 4.2m 内造成 55 高额伤害——**离开圈的敌人不受伤**（可被躲避）。
static func skill_meteor_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"meteor"; s.display_name = "陨石术"
	s.kind = PawnSkillDef.Kind.METEOR
	s.cooldown = 16.0
	s.cast_range = 11.0
	s.damage = 55.0                # 高额（对比暴风雪每跳 8）：命中即重创，代价是慢 + 可躲
	s.windup = 1.0                 # 原地吟唱时长
	s.recover = 0.35
	s.telegraph = 1.1              # 预警圈出现到落地的窗口
	s.radius = 4.2
	return s


## 狙击手 · 贯穿射击：向前射出一枚更大的子弹，沿直线贯穿一串目标（每个只吃一次 26 伤害），
## 射程 26m 远超普攻 12m——站桩输出位的一发「排队枪毙」。
static func skill_piercing_shot_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"piercing_shot"; s.display_name = "贯穿射击"
	s.kind = PawnSkillDef.Kind.PIERCING_SHOT
	s.cooldown = 12.0
	s.cast_range = 18.0            # 出手距离（弹体本身飞 26m）
	s.damage = 26.0                # 每个被贯穿目标各吃一次
	s.pierce_length = 26.0
	s.pierce_radius = 1.0          # 贯穿判定半宽（比普通弹体 0.75 更粗）
	s.pierce_speed = 26.0
	return s


## 暗杀者 · 隐身：模型 shader 进入隐身态，5s 内敌人索敌不到（造成伤害立即破隐）。
## 释放条件：血量低于 35%（逃生）或接近目标（2.5~7m）时先手潜行。
static func skill_stealth_def() -> PawnSkillDef:
	var s := PawnSkillDef.new()
	s.id = &"stealth"; s.display_name = "隐身"
	s.kind = PawnSkillDef.Kind.STEALTH
	s.cooldown = 18.0
	s.cast_range = 0.0             # 自身增益：无距离要求
	s.damage = 0.0
	s.stealth_duration = 5.0
	s.escape_hp_ratio = 0.35       # 逃生血线
	s.approach_range = 7.0         # 接近目标触发距离
	return s


# ---- v26 驯龙系统：巨龙表（龙园花金币解锁，编队第 5 位出战）----
# 龙是「小队宠物」定位：不占 4 人编队槽、不自动索敌——它只跟着主角，并攻击
# 「主角正在打的目标」（集火令 T 优先，其次主角最近攻击目标，见 Hero.live_pet_target()）。
# 数据驱动：新龙只需在 dragon_defs() 追加一个 DragonDef（模型 / 数值 / 描述 / 解锁价），
# 龙园菜单、市民出战区、DragonPet 行为与测试全部自动接入。

## 全部可驯巨龙（龙园菜单 / 市民出战区按本表渲染）。
static func dragon_defs() -> Array[DragonDef]:
	return [dragon_obsidian_def()]


## 按龙 id 取 def（查无返回 null）。
static func dragon_def(dragon_id: StringName) -> DragonDef:
	for d in dragon_defs():
		if d.id == dragon_id:
			return d
	return null


## 首龙「黑曜龙」：bocdagla 四足带翼龙占位皮（授权见 assets/_PLACEHOLDER/dragons/CREDITS.md）。
## 体型按实渲口径 0.55（≈3.1m 高，1.4× 人类）——该资产静态 AABB 比 Real 渲染大 1.84×，
## 缩放与血条高度不得按 AABB 反推（dragon-assets/poc/REPORT.md §3 实测）。
static func dragon_obsidian_def() -> DragonDef:
	var d := DragonDef.new()
	d.id = &"dragon_obsidian"; d.display_name = "黑曜龙"
	d.max_hp = 360.0
	d.move_speed = 5.4               # 略慢于主角 6.0；远距跟随态自带追赶加成补齐
	d.attack_damage = 22.0           # 火球直击（面板展示用；实际走 DragonDef.fireball_*）
	d.attack_range = 10.0            # 吐球射程
	d.attack_cooldown = 1.6
	d.mesh_color = Color(0.35, 0.32, 0.42)
	d.team = 0
	d.is_auto_fighter = true         # v32：主角没指定目标时自主守住主角身边 11m 圈
	d.auto_attack_range = 11.0       # 自主索敌半径（圆心 = 主角，见 DragonDef 注释）
	d.defense = 12.0
	d.crit_rate = 0.0
	d.can_level = false
	d.xp_value = 0
	d.loot_gold = 0
	# v34 回城疗伤：白天回城镇范围每秒回 4 血（360 血约 90s 回满；晚上守城期间不回）。
	d.regen_per_sec = 4.0
	d.unit_name = "黑曜龙"
	d.class_icon = "龙"; d.class_color = Color(0.85, 0.45, 1.0)
	# ---- 火球普攻：直击 + 小片爆炸溅射 ----
	d.unlock_cost = 150
	d.fireball_damage = 22.0
	d.fireball_cooldown = 1.6
	d.fireball_range = 10.0
	d.fireball_speed = 13.0
	d.splash_radius = 2.2
	d.splash_damage = 12.0
	# ---- 烈焰吐息：原地朝目标方向喷火 2s，40° 锥形长距持续伤害 ----
	d.breath_name = "烈焰吐息"
	d.breath_range = 14.0
	d.breath_half_arc_deg = 20.0     # 半角 20° = 全角 40° 扇形
	d.breath_duration = 2.0
	d.breath_tick_interval = 0.4
	d.breath_damage = 9.0
	d.breath_cooldown = 12.0
	# ---- 模型与动画（bocdagla 命名与 KayKit/Quaternius 都不同 → per-def anim_map 覆盖）----
	# v32 体型翻倍：实渲 ≈6.2m（原 3.1m）。**连带必须同步改的四项**——
	# ① body_scale=2.0（碰撞胶囊 / 拾取柱 / 导航半径 / 选中·瞄准环）；② hud_head_height ×2；
	# ③ squad_ring_radius ×2；④ DragonPet 的嘴部出口按 model_scale 比例自动算（不再写死米数）。
	d.model_path = "res://assets/_PLACEHOLDER/dragons/Dragon2.glb"
	d.model_scale = 1.10             # 实渲 ≈6.2m；AABB 高 10.45 不可信（按实渲口径标定）
	d.body_scale = 2.0               # 半径盒同步翻倍（人形口径 r0.4/h1.6 → r0.8/h3.2）
	d.model_face_offset_deg = 180.0  # 模型头朝 +Z，项目前方 -Z
	d.hud_head_height = 6.8          # 血条抬到龙头上方（自动量测会被膨胀 AABB 顶到半空）
	d.squad_ring_radius = 2.5        # 脚下队伍绿圈按体型放大（人形 0.42 会被龙身整个盖住）
	# 注意：Godot 的 glTF 导入器会把 `_loop` 后缀剥掉（实测：GLB 原始名 Idle_loop /
	# Walk_menacing_loop → 导入场景里 Idle / Walk_menacing；GLTFDocument 直读路径保留
	# 原名）——候选数组把两个名字都列上，导入场景与运行时回退两条路径都能命中。
	d.anim_map = {
		&"idle": ["Idle_loop", "Idle"],                          # 地面待机（张翼站立）
		&"move": ["Walk_menacing_loop", "Walk_menacing", "Walk"],  # 地面真迈步
		&"run": ["Walk_menacing_loop", "Walk_menacing", "Walk"],   # 无跑步动画，复用行走（缺这条会滑行）
		&"follow": ["Walk_menacing_loop", "Walk_menacing", "Walk"],
		&"fight": "Attack",                                      # 0.917s 前肢立起前扑
		&"dead": "AttackPose",                                   # 无死亡动画，张翼定格后缩小淡出
	}
	d.description = "四足带翼的黑曜石鳞巨龙。吐出爆炸火球轰击目标，溅射波及周围敌人。"
	d.skill_desc = "%s：原地朝目标方向喷吐烈焰 %.0f 秒，%.0f° 锥形最远 %.0f 米，持续灼烧路径上的敌人（CD %.0f 秒）。" % [
		d.breath_name, d.breath_duration, d.breath_half_arc_deg * 2.0, d.breath_range, d.breath_cooldown]
	return d


# ---- 小兵人设气泡台词（v14：SpeechBubble3D 随机低频取用）----
# 按 def.id 分「人设池」，每池三种心情：idle 日常闲聊 / work 干活·巡猎·赶路 / combat 战斗与逃跑。
# 只给玩家阵营的「小兵」配词：主角由玩家本人代言，野怪不配台词（挑台词时查不到池即静默）。
# 缺的心情池自动回落 idle 池（如流民只有赶路口白）。台词保持简短（≤12 字），气泡不遮画面。
const BUBBLE_LINES := {
	&"settler_warrior": { # 战士：双手斧野蛮人，豪爽
		&"idle": ["酒馆啥时候开张？", "斧刃钝了，得蹭蹭石头。", "吃饱才有力气挥斧！"],
		&"work": ["让开让开，大斧来了！", "这片林子的怪，包我身上。", "热身完毕，开练！"],
		&"combat": ["哈哈哈，来得好！", "一斧一个！", "谁与我大战三百回合？"],
	},
	&"settler_mage": {    # 法师：长杖学者，讲究
		&"idle": ["今日魔力充盈，宜施法。", "魔杖又积灰了……", "星辰的轨迹颇有意味。"],
		&"work": ["元素听话，怪不听话。", "保持专注，保持距离。", "这句咒语的发音很讲究。"],
		&"combat": ["退后，我要施法了！", "元素啊，听我号令！", "火球术……马上就学会！"],
	},
	&"settler_assassin": { # 刺客：双匕快手，机灵话少
		&"idle": ["影子是最好的搭档。", "嘘——听见金币声了吗？", "我的匕首说它饿了。"],
		&"work": ["先绕后，再出手。", "看好了，只示范一次。", "风声就是我的脚步。"],
		&"combat": ["眨眼的功夫就结束。", "背后交给我。", "快！再快！"],
	},
	&"settler_archer": {  # 游侠：手弩手，活泼爱练（v19 起原「射手」改称游侠）
		&"idle": ["弩弦松了，得紧一紧。", "今天的云像箭靶。", "准头是一箭箭练的。"],
		&"work": ["高处视野好，怪躲不掉。", "装填，瞄准，发射！", "又偏了半寸……"],
		&"combat": ["别跑，箭会追人。", "装填完毕！", "看箭！"],
	},
	&"colonist": {        # 村民：市井勤劳，家长里短
		&"idle": ["歇会儿，晒晒太阳。", "城里的日子有奔头。", "今年收成错不了。"],
		&"work": ["再砍两棵就满喽。", "这石头真沉……", "仓库快见底了，加把劲。", "一担柴，一担粮。"],
		&"combat": ["哎呀妈呀，快跑！", "怪物来了，救命！", "放下柴也得跑！"],
	},
	&"refugee": {         # 流民：赶路人，憧憬安家（只有赶路口白）
		&"idle": ["听说这里有空房……", "走了一路，腿都细了。", "要是能安家就好了。", "前面就是城墙了吧？"],
	},
}


## 取某个单位某心情的台词池（数组元素为 String）。查无此单位 / 此心情 → 空数组；
## 心情池缺失时回落该单位的 idle 池。
static func bubble_lines_for(def_id: StringName, mood: StringName) -> Array:
	var pools: Dictionary = BUBBLE_LINES.get(def_id, {})
	var arr: Array = pools.get(mood, [])
	if arr.is_empty() and mood != &"idle":
		arr = pools.get(&"idle", [])
	return arr


# ---- 主角（战士职业；后续扩展职业在此新增 hero_<class>_def）----

static func hero_warrior_def() -> HeroDef:
	var d := HeroDef.new()
	d.id = &"hero_warrior"; d.display_name = "战士"
	d.class_id = &"warrior"
	d.max_hp = 320.0
	d.move_speed = 6.0
	d.attack_damage = 18.0          # 兜底（实际用连招每段 damage）
	d.attack_range = 2.6
	d.attack_cooldown = 0.4
	d.mesh_color = Color(0.95, 0.78, 0.3)
	d.team = 0
	d.is_auto_fighter = true        # 正常 RTS 模式下自卫；主角模式下手动操作
	d.combo_window = 0.8
	d.respawn_at_base = true
	d.respawn_delay = 5.0
	# v34 回城疗伤：白天回城镇范围每秒回 2 血（320 血约 160s 回满，刻意「缓慢」；
	# 晚上守城期间不回——见 Pawn._try_town_regen 的夜晚门控）。
	d.regen_per_sec = 2.0
	# 3 段普攻：轻 - 轻 - 重（第 3 段更远 / 更痛 / 顿帧更长）
	d.combo_hits = [
		_combo_hit(1, 16.0, 0.07, 0.10, 0.18, 2.6, 0.9, 0.5, 0.04, &"combo_light", &"slash_arc", &"slash"),
		_combo_hit(2, 18.0, 0.07, 0.10, 0.18, 2.7, 1.0, 0.5, 0.04, &"combo_light", &"slash_arc", &"slash"),
		_combo_hit(3, 34.0, 0.12, 0.14, 0.30, 3.2, 1.2, 1.1, 0.09, &"combo_heavy", &"slash_arc", &"slash_heavy"),
	]
	# 技能 1：旋风斩（自身周围 AoE，持续多 tick）
	# 技能 2：冲锋斩（向前冲刺，沿途造伤）
	d.skills = [skill_whirlwind_def(), skill_charge_slash_def()]
	d.model_path = "res://assets/_PLACEHOLDER/characters/placeholder_hero.glb"
	# 同殖民者：只在美术层做朝向修正，移动、攻击判定仍使用 Pawn 的 -Z 前方。
	d.model_face_offset_deg = 180.0
	# 占位骑士 GLB 的两个手部挂点里躺着全部武器变体（1H/2H 剑 + 4 面盾）且默认全可见：
	# 不挑选就会「左手同时握剑又握盾、右手两把剑重叠」。战士 = 右手单手剑 + 左手一面骑士盾。
	d.model_weapon_main = &"1H_Sword"
	d.model_weapon_offhand = &"Rectangle_Shield"
	# v25：主角同样拥有技能树（升级得技能点；职业技根节点预点亮，Q/C 不受门禁）
	d.skill_tree_id = &"hero"
	return d


static func _combo_hit(step: int, dmg: float, windup: float, active: float, recovery: float,
		range: float, half_arc: float, lunge: float, hit_stop: float,
		anim_id: StringName, vfx_id: StringName, sfx_id: StringName) -> ComboHitDef:
	var h := ComboHitDef.new()
	h.step = step
	h.damage = dmg
	h.windup = windup
	h.active = active
	h.recovery = recovery
	h.range = range
	h.half_arc = half_arc
	h.lunge = lunge
	h.hit_stop = hit_stop
	h.anim_id = anim_id
	h.vfx_id = vfx_id
	h.sfx_id = sfx_id
	return h


static func skill_whirlwind_def() -> SkillDef:
	var s := SkillDef.new()
	s.id = &"whirlwind"; s.display_name = "旋风斩"
	s.target_kind = SkillDef.TargetKind.SELF_AOE
	s.cooldown = 6.0
	s.damage = 14.0
	s.windup = 0.2
	s.duration = 0.5
	s.recovery = 0.3
	s.radius = 3.6
	s.half_arc = PI                  # 全圆
	s.tick_interval = 0.12
	s.vfx_id = &"whirlwind_aura"
	s.sfx_id = &"whirlwind"
	s.anim_id = &"skill_aoe"
	s.icon_color = Color(0.5, 0.8, 1.0)
	return s


static func skill_charge_slash_def() -> SkillDef:
	var s := SkillDef.new()
	s.id = &"charge_slash"; s.display_name = "冲锋斩"
	s.target_kind = SkillDef.TargetKind.DIRECTIONAL_DASH
	s.cooldown = 8.0
	s.damage = 40.0
	s.windup = 0.15
	s.duration = 0.25
	s.recovery = 0.35
	s.dash_distance = 7.0
	s.radius = 2.5                   # 沿途判定半宽
	s.half_arc = 0.7
	s.tick_interval = 0.06
	s.vfx_id = &"charge_trail"
	s.sfx_id = &"charge"
	s.anim_id = &"skill_dash"
	s.icon_color = Color(1.0, 0.6, 0.3)
	return s
