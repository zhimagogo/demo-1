class_name Raider
extends Pawn
## ============================================================================
## 城外野怪。未指定 def 时用默认掠夺者定义。
## 行为（v3 全面升级；v20 夜潮攻城）：
## - 白天：城外徘徊 + 接战城外玩家单位（avoids_city=true，永不误入主城）
## - 夜晚：可以发起「夜袭攻城」——锁定最近的玩家建筑 / 主城，破城而入（临时解除避城）
## - 夜潮（v20）：WildlifeSpawner 入夜从四条道路尽头之一成批刷出的大部队带
##   assaulting 标记——无概率 / 冷却 / 并发门控，直取主城持续推进；
##   中途被小兵打中会立即转火小兵（见 _on_damaged），杀完继续向主城推进
## - 低血：按 def.flee_hp_ratio 掉头逃跑（夜袭攻城 / 夜潮总攻中一律死战不退），
##   脱战回血后再来；v35 起 flee_chance 概率化——低血时一次性掷签，少数怂怪才跑；
##   v44 起「带进攻意图」= 强制死战：assaulting（夜潮赶路 / 交战）与 _sieging 同权
##   （见 should_flee_now）——进攻中的怪绝不撤退，玩家永远打得到
## - 精英 / 头目变体由 WildlifeSpawner 按 def 注入（体型 / 染色 / 掉落不同）
## ============================================================================

const AGGRO_RANGE: float = 11.0
const LEASH_RANGE: float = 16.0
const LEASH_RETURN_RANGE: float = 12.0  # 回到内圈后才重新接战，避免追击边缘反复折返
const SIEGE_MIN_DELAY: float = 18.0     # 两次夜袭尝试的最短间隔
const SIEGE_MAX_DELAY: float = 34.0
const SIEGE_SIGHT: float = 70.0         # 夜袭目标搜索半径
const SIEGE_PATH_CANDIDATES: int = 6    # 夜袭目标 A* 路程评估候选上限（直线 top-K，防对全部建筑跑 A*）

var _nav_sys_cache: NavSystem = null    # NavSystem 引用缓存（攻城评估用，免重复组查找）
var home_position: Vector3
var siege_cooldown: float = 8.0         # 初始缓一缓，入夜别秒袭
var _process_enabled: bool = true
var assaulting: bool = false            # v20 夜潮总攻标记：出生即锁定主城、无门控持续推进
var _flee_will: int = -1                # v35「怕死签」：-1 未掷；0=死战；1=会逃（本生命周期不重掷）


## 低血逃跑判定（v35 概率化；v44 进攻意图强制死战）：血量跌破 def.flee_hp_ratio 时按
## def.flee_chance **一次性掷签**决定这只怪怕不怕死——多数怪死战到底（近战小兵不再被迫
## 满地图追杀 1.5× 速的逃跑怪），少数怂怪照旧掉头跑、脱战回血再来。掷签终身有效：
## 回血再战 / 再次低血都沿用首次结果，性格稳定不临阵变卦。
## **带进攻意图的怪一律死战**：夜潮总攻（assaulting，出生即锁定主城，赶路 / 交战中
## 低血也不许跑）与攻城（_sieging）同权返回 false——否则低血抽到逃跑签就掉头跑远，
## 玩家追不上、攻势也断掉（v44 用户反馈「撤退之后就打不到了」）。未配血线
## （flee_hp_ratio<=0，头目）同样不逃。FightState 低血门每帧调用本函数（唯一门控，
## 不要在外面复制条件）。
func should_flee_now() -> bool:
	if _sieging or assaulting or def == null or def.flee_hp_ratio <= 0.0 or health == null:
		return false
	if health.ratio() > def.flee_hp_ratio:
		return false
	if _flee_will < 0:
		_flee_will = 1 if randf() < clampf(def.flee_chance, 0.0, 1.0) else 0
	return _flee_will == 1


func _ready() -> void:
	if def == null:
		def = GameDefs.raider_def()
	home_position = global_position
	super._ready()
	# v20 被打反击：受击（仍存活）即响应——被小兵打中就转火小兵
	health.damaged.connect(_on_damaged)
	# 头目随身光环：暗紫点光（夜袭头目一眼可辨）
	if def.is_boss:
		var glow := OmniLight3D.new()
		glow.name = "BossGlow"
		glow.light_color = Color(0.85, 0.3, 1.0)
		glow.omni_range = 5.0
		glow.light_energy = 1.2
		glow.position.y = 1.2
		add_child(glow)


func _process(delta: float) -> void:
	# 夜袭冷却推进（roam/idle 都会用到）
	if siege_cooldown > 0.0:
		siege_cooldown = max(0.0, siege_cooldown - delta)


func find_nearest_hostile(max_range: float = AGGRO_RANGE) -> Node:
	# Local combat is forbidden while retreating out of town or back to home.
	# Reject before consulting the shared aggro cache.
	if not _sieging:
		var city := _get_city()
		if is_beyond_leash() or (city != null and city.is_in_city(global_position)):
			return null
	return super.find_nearest_hostile(minf(max_range, AGGRO_RANGE))


func get_combat_approach_position(target: Node3D) -> Vector3:
	var pos := super.get_combat_approach_position(target)
	var city := _get_city()
	if not _sieging and city != null:
		pos = city.outside_point(pos, 0.7)
	return pos


func is_beyond_leash() -> bool:
	return global_position.distance_to(home_position) > LEASH_RANGE


## 是否处于夜间（20:00 ~ 06:00）。v34 起委托 TimeManager.is_night（全局统一口径）。
static func is_night_now() -> bool:
	return TimeManager.is_night()


## 是否处于傍晚（18:00 ~ 20:00）：天地渐暗，野外完全停刷的过渡时段（v20）。
static func is_dusk_now() -> bool:
	var h: int = TimeManager.hour
	return h >= 18 and h < 20


## 夜潮总攻令（WildlifeSpawner 夜晚批次出生时下发）：置 assaulting 标记并立即
## 锁定主城发起攻城。杀完中途拦截的小兵后，idle/roam 的 try_start_siege 会经
## 同一分支立刻恢复推进——「持续朝主城进攻」的闭环。
## v44：assaulting 起 should_flee_now 恒 false（进攻中的怪不撤退）。若调用时该怪
## 正处于逃跑状态（低血逃跑后又被总攻接管），先中止撤退回 idle，再走总攻攻城。
func begin_night_assault() -> void:
	assaulting = true
	siege_cooldown = 0.0
	if state_machine != null and state_machine.current_state is RaiderFleeState:
		state_machine.transition_to("idle")
	try_start_siege()


## 夜袭决策（roam / idle 每帧低频试探）：入夜 + 冷却结束 + 掷中概率 →
## 锁定最近的玩家建筑 / 主城发起攻城。返回 true 表示已切入攻城。
func try_start_siege() -> bool:
	if TimeManager.clock_frozen:
		return false   # v31 守城准备期（时间静止）：残敌按兵不动，等玩家开战令
	if _sieging or not is_night_now() or siege_cooldown > 0.0:
		return false
	# v20 夜潮总攻：带 assaulting 标记的怪物不吃概率 / 冷却 / 并发上限，
	# 直取主城（HQ）。被小兵打断杀死小兵后也从这里立刻恢复推进。
	if assaulting:
		var core := _pick_assault_target()
		if core != null:
			state_machine.transition_to("fight", {"target": core, "siege": true})
			return true
		return false
	# 夜袭强度曲线：夜 1 只有 1/4 的袭击意愿（小股试探），夜 3 起全速攻城。
	# 同时全场并发攻城人数封顶（2 + 夜数一半）：夜里城墙外始终留有游荡野怪。
	var night_index: int = maxi(1, TimeManager.day)
	var willingness: float = clampf(float(night_index) / 3.0, 0.25, 1.0)
	if randf() > 0.003 * willingness:
		return false
	if _active_sieger_count() >= 2 + night_index / 2:
		return false
	var target := _pick_siege_target()
	if target == null:
		return false
	siege_cooldown = randf_range(SIEGE_MIN_DELAY, SIEGE_MAX_DELAY)
	state_machine.transition_to("fight", {"target": target, "siege": true})
	return true


## 当前正在攻城的野怪数（并发封顶用；每个野怪每帧调用，扫描 16 个敌人成本可忽略）。
func _active_sieger_count() -> int:
	var count := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Raider and is_instance_valid(e) and (e as Pawn)._sieging:
			count += 1
	return count


## 可攻目标选择：建筑（墙 / 塔 / 房屋…）与主城二选一。夜里城墙内外都能打。
## v2 路径评估：先用直线距离筛出 top-K 候选，再用 NavSystem.get_path_length 的
## 真实 A* 路程选最优——隔湖 / 被墙隔开的目标直线近但路程远，直接挑直线最近
## 会让野怪锁定一个要绕大半张地图、甚至永远到不了的目标。
## 全部候选 INF（被完全围死）时 fallback 到直线最近的候选：目标不可达 ≠ 不能打，
## 墙就是用来挡的，打它总是对的（吸附逻辑带单位走到墙外，FightState 的 stuck
## 检测会触发换目标打墙破口）。注意 try_start_siege 已被 randf 概率门控
## （约每秒每野怪 0.2 次），top-K 内的 A* 成本可接受。
func _pick_siege_target() -> Node3D:
	# 第一步：直线距离收集 SIEGE_SIGHT 视野内的全部候选
	var candidates: Array = []   # [{ "node": Node3D, "dist": float }]
	for b in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var d: float = global_position.distance_to((b as Node3D).global_position)
		if d < SIEGE_SIGHT:
			candidates.append({"node": b, "dist": d})
	for bc in get_tree().get_nodes_in_group("base_core"):
		if not is_instance_valid(bc) or not (bc is Node3D):
			continue
		var d: float = global_position.distance_to((bc as Node3D).global_position)
		if d < SIEGE_SIGHT:
			candidates.append({"node": bc, "dist": d})
	if candidates.is_empty():
		return null
	# 直线近者优先评估；真实路程不可能比直线短，top-K 之外的直接淘汰
	candidates.sort_custom(func(x, y): return x["dist"] < y["dist"])
	var nav: NavSystem = _get_nav()
	if nav == null:
		return candidates[0]["node"]   # 无寻路系统兜底：沿用直线最近
	var best: Node3D = null
	var best_path: float = INF
	for i in range(mini(SIEGE_PATH_CANDIDATES, candidates.size())):
		var node: Node3D = candidates[i]["node"]
		if not is_instance_valid(node):
			continue
		var path_len: float = nav.get_path_length(global_position, node.global_position)
		if path_len < best_path:
			best_path = path_len
			best = node
	if best == null:
		# 全部候选不可达（被墙完全围死）→ 打直线最近的：破口即是出路
		return candidates[0]["node"]
	return best


## 夜潮总攻目标：主城（HQ）优先——「怪会持续朝主城进攻」；无主城的场景
## （部分测试环境）回退到常规攻城目标选择。
func _pick_assault_target() -> Node3D:
	for bc in get_tree().get_nodes_in_group("base_core"):
		if is_instance_valid(bc) and bc is Node3D:
			return bc
	return _pick_siege_target()


## 被打反击（v20）：**攻城赶路中**被小兵打中 → 立即进入交战状态，优先打小兵。
## 只在带进攻意图时生效（夜潮 assaulting / 已在攻城 _sieging）——「中间被小兵打」
## 指的正是在向主城推进的途中；白天城外游荡怪维持旧的近身接战规则，
## 测试里当「木桩」用的普通野怪也保持被动，不还手。
## 只对「玩家方单位（士兵 / 主角）」反击：建筑（箭塔）伤害不打断推进
## （攻城卡墙换目标的职责在 FightState 的 stuck 检测），敌方误伤不管。
func _on_damaged(_amount: float, source: Node) -> void:
	if not (assaulting or _sieging):
		return   # 不在进攻途中：不因受击改写行为（白天游荡 / 木桩语义）
	if source == null or not is_instance_valid(source) or not (source is Pawn):
		return
	var attacker := source as Pawn
	if is_dead_flag or attacker.is_dead_flag:
		return
	if attacker.team_comp == null or attacker.team_comp.team != TeamComponent.Team.PLAYER:
		return
	if state_machine == null or state_machine.current_state == null:
		return
	# 低血逃跑中不反击：怕死优先，脱战回血后再来（RaiderFleeState 自己管重返）
	if state_machine.current_state is RaiderFleeState:
		return
	# 已在打这个目标：不重复切状态（每次受击都重进 fight 会原地抖动）
	var cur = state_machine.current_state
	if cur is FightState and is_instance_valid(cur.target) and cur.target is Pawn:
		var committed := cur.target as Pawn
		# Keep a viable opponent instead of switching on every incoming hit.
		# A dead, unreachable or distant opponent may be replaced immediately.
		if not committed.is_dead_flag and global_position.distance_squared_to(committed.global_position) <= LEASH_RANGE * LEASH_RANGE \
				and navigation_status not in [NavigationStatus.BLOCKED, NavigationStatus.UNREACHABLE]:
			return
	# 进攻意图保留：追小兵允许跟进城内（杀完经 idle→try_start_siege 恢复推进）
	state_machine.transition_to("fight", {"target": attacker, "siege": true})


## NavSystem 引用（攻城目标路程评估用）：按分组查找并缓存，失效时重查。
func _get_nav() -> NavSystem:
	if _nav_sys_cache == null or not is_instance_valid(_nav_sys_cache):
		_nav_sys_cache = get_tree().get_first_node_in_group("nav_system") as NavSystem
	return _nav_sys_cache


func _setup_nodes() -> void:
	super._setup_nodes()
	avoids_city = true
	# 安装野怪专属状态（idle 决策路由 + 城外徘徊 + 低血逃跑）。super 已建好 state_machine
	# 并自动登记 6 基础状态；此处用 register_state 替换 idle、新增 roam / flee。
	state_machine.register_state("idle", MonsterIdleState.new())
	state_machine.register_state("roam", RoamState.new())
	state_machine.register_state("raider_flee", RaiderFleeState.new())
