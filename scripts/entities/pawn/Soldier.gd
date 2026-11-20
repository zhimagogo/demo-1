class_name Soldier
extends Pawn
## ============================================================================
## 士兵基类：玩家阵营的武装小兵。在 Pawn 骨架之上叠加「日常生活」自主 AI
## （白天短时巡逻与城内生活交替 / 低血回城治疗 / 夜间城内驻防闲逛）。
## v21 起小兵唯一来源 = 流民入住房屋觉醒的四职业（战士/法师/刺客/游侠，
## 见 SettlementSystem + GameDefs.settler_*_def）；兵营与近战/远程募兵兵种已删除。
## v3：三姿态（防御/进攻/驻守，stance 字段由 UI 修改）+ 威胁支援响应
## （threat_alert 写入 alert_pos，SoldierIdleState 路由赶赴）。
## 子类（SoldierMelee / SoldierRanged）只是近战/远程的行为载体；远程再替换 fight 状态。
## ============================================================================

var home: Building = null
var _alert_decay: float = 0.0
var town_life_active: bool = true
var town_life_left: float = 0.0
var patrol_left: float = 0.0
var chat_partner = null             # 先检查实例存活再转型，避免同伴释放后读取悬空对象
var chat_cooldown: float = 0.0
var _social_scan_left: float = 0.0

# ---- v22 酒馆疗伤：低血小兵优先回酒馆回血 ----
# 血量比例低于 TAVERN_HEAL_THRESHOLD（在城外/战斗中都会触发）即中断自主行为回馆；
# 恢复到 TAVERN_EXIT_RATIO 以上才「出院」恢复正常生活（滞回防抖，避免半血就往外跑）。
const TAVERN_HEAL_THRESHOLD: float = 0.2
const TAVERN_EXIT_RATIO: float = 0.95
var healing_trip: Building = null       # 正在前往/停留的酒馆（null = 不在疗伤行程中）

# ---- v43 夜间待命：非编队 / 非驻守小兵入夜回城站岗（night_vigil），可 2~3 人群聊 ----
# 待命点由 CitySystem 城内安全点 + instance_id 稳定分布（家附近 / 酒馆附近 / 路边 / 城心），
# 抵达后站定不再满城游荡；受伤（<95%）且有酒馆时先回馆回血再站岗。
var night_post: Vector3 = Vector3.ZERO   # 本夜待命点（世界坐标）
var night_post_valid: bool = false       # 待命点是否已选定（入夜/天亮时重置）
var night_vigil_active: bool = false     # 是否已抵达待命点站定（night_chat 招募门槛）
var night_chat_group: Array = []         # 同组闲聊的小兵（组内共享同一个 Array，exit 时移除自己）
var night_chat_cooldown: float = 0.0     # 夜间群聊冷却（25~45s，独于白天 chat_cooldown）
var _night_is_night: bool = false        # 昼夜状态兜底追踪（无 DayNightCycle 的测试世界也能重置）

# ---- v44 夜间威胁方向部署：到城门内侧列阵（近战前排 / 远程后排）----
# WildlifeSpawner 在守城准备期选门后经 EventBus.night_threat_direction_changed 广播；
# 士兵不读对方私有字段，只消费信号里的 gate_index / gate_inside。
const DEFENSE_ROW_MAX: int = 8              # 每行最多 8 人
const DEFENSE_ROW_SPACING: float = 2.4      # 行距（需求 2.2~2.6m）
const DEFENSE_LATERAL_SPACING: float = 2.0  # 横向间距（米）
# 同夜阵型布局缓存（class 级）：key = gate + 城门内侧点 + 可部署名单，名单不变就复用槽位，
# 避免阵型在战斗中被逐个死亡反复重排；换门 / 新兵加入（威胁重发）时才重建一次。
static var _defense_layout_key: String = ""
static var _defense_layout: Dictionary = {}   # instance_id(int) -> Vector3 slot
var defense_active: bool = false              # 今夜是否处于按威胁方向部署状态
var defense_gate_index: int = -1              # 0南/1东/2北/3西；-1 = 无威胁
var defense_inside: Vector3 = Vector3.ZERO    # 城门内侧世界点（信号携带，已吸附可走格）
var defense_outward: Vector3 = Vector3.ZERO   # 朝城外方向（站定朝向）
var defense_slot: Vector3 = Vector3.ZERO      # 本兵在阵列中的槽位
var defense_slot_valid: bool = false          # 槽位是否已解算（换门/新兵重发时重置）


## 最近的存活酒馆（无酒馆返回 null）。
func find_nearest_tavern() -> Building:
	var best: Building = null
	var best_dist := INF
	for b in get_tree().get_nodes_in_group("tavern"):
		if not is_instance_valid(b) or not (b is Building):
			continue
		var d: float = global_position.distance_to((b as Building).global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best


## 疗伤行程中不自动接战：赶路/养伤期间被沿途野怪拉走会死在半路
## （玩家集火令走 FightState 的显式下令通道，不受此限制）。
func autofight_enabled() -> bool:
	if healing_trip != null and is_instance_valid(healing_trip):
		return false
	return super.autofight_enabled()


func _ready() -> void:
	request_town_life()
	chat_cooldown = randf_range(3.0, 8.0)
	_night_is_night = TimeManager.is_night()
	# v44：威胁方向订阅必须早于 super._ready()——夜里新兵出生时 WildlifeSpawner 会在
	# pawn_spawned 回调里补发当前威胁方向，晚订阅会错过这次补发。
	EventBus.night_threat_direction_changed.connect(_on_night_threat_direction_changed)
	super._ready()
	# 威胁支援：友军/建筑遇袭时记下位置（idle 路由消费；超时自动作废）
	EventBus.threat_alert.connect(_on_threat_alert)
	# v43 昼夜切换：重置本夜待命点 / 夜间群聊冷却（DayNightCycle 广播；
	# 无昼夜循环的测试世界由 _update_daily_life 的状态兜底补发）
	EventBus.night_changed.connect(_on_night_changed)
	# v20 属性系统：击杀得经验（小兵成长线；主角击杀走 Hero 自己的经验结算，互不干扰）
	EventBus.enemy_died.connect(_on_enemy_killed_for_xp)


## v20 击杀经验：自己是最后一击归属者（HealthComponent.last_attacker）才入账。
## 经验量取被杀者的 def.xp_value（普通 8 / 精英 22 / 头目 80）；非成长单位直接忽略。
## v34 小队经验共享：只要在队（follow_leader 为主角），小队里**任何人**击杀——
## 主角亲手、其他队友、编外巨龙——自己都分到「击杀者经验的 50%」
## （GameDefs.SQUAD_XP_SHARE_RATIO）；击杀者本人仍拿全额（走上方 killer == self 分支）。
## 不在队的士兵（城内自主驻防等）击杀不外溢，别人击杀自己也分不到。
func _on_enemy_killed_for_xp(enemy: Node, killer: Node) -> void:
	if is_dead_flag or not can_level_up():
		return
	if enemy == null or not is_instance_valid(enemy) or enemy.get("def") == null:
		return
	var base_xp: int = maxi(1, enemy.def.xp_value)
	if killer == self:
		gain_xp(base_xp)
		return
	# 共享判定：击杀者是自己的小队长（主角），或与自己同队跟随的 Pawn（队友 / 巨龙）。
	var leader = follow_leader
	if killer == null or not is_instance_valid(killer) or leader == null or not is_instance_valid(leader):
		return
	var killer_p := killer as Pawn
	if killer == leader or (killer_p != null and killer_p.follow_leader == leader):
		gain_xp(GameDefs.squad_share_xp(base_xp))


func assign_home(value: Building) -> void:
	home = value


# ---- v25 转职（Lv.5 起二选一进阶；def.promotes_to 声明可选职业）----

## 是否满足转职条件：基础职业（promotes_to 非空）+ 等级达标 + 存活。
func can_promote() -> bool:
	return not is_dead_flag and def != null and not def.promotes_to.is_empty() \
		and level >= GameDefs.PROMOTE_LEVEL


## 转职进阶：def 整体换成进阶职业（保留姓名 / 等级 / 经验 / 技能树 / 血量比例），
## 六维与攻击参数按新 def + 当前等级重算，模型染色与字徽同步。
## 返回是否成功（条件不满足 / 进阶 id 不在该职业的可选列表 → false）。
func promote_to(advanced_id: StringName) -> bool:
	if not can_promote() or not def.promotes_to.has(advanced_id):
		return false
	var new_def: PawnDef = GameDefs.settler_advanced_def(advanced_id)
	if new_def == null:
		return false
	var keep_name := def.unit_name
	var hp_ratio: float = health.ratio() if health != null else 1.0
	def = new_def
	def.unit_name = keep_name            # 姓名 / 等级 / 经验保留（技能树按 v33 换树重分配）
	# ---- v33 转职换树：旧树已投入点数全额返还 → 换上进阶职业自己的技能树 ----
	# 必须先 reset_and_refund（读旧树的投入）再 set_tree_def（换布局清空）。
	var refunded := _rebind_skill_tree()
	_apply_stats_for_level()
	if health != null:
		# 血量按比例保留（转职不白嫖回血，也不惩罚掉血）
		health.current_hp = clampf(health.max_hp * hp_ratio, 1.0, health.max_hp)
		health.health_changed.emit(health.current_hp, health.max_hp)
	if attacker != null:
		attacker.attack_range = def.attack_range
		attacker.attack_cooldown = def.attack_cooldown
		attacker.attack_kind = def.attack_kind
		attacker.projectile_speed = def.projectile_speed
	if model_rig != null and model_rig.has_model():
		model_rig.apply_tint(def.model_tint)   # 模型按新职业染色（骑士偏银、狂战偏红…）
	var mat := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mat != null and mat.material_override is StandardMaterial3D:
		(mat.material_override as StandardMaterial3D).albedo_color = def.mesh_color
	# v33：转职后重建多技能列表 + 冷却表（新技能立刻可施放，主技能数值差异同步），
	# 并重挂面板基线（血怒等增益的伤害基准）
	if skill_comp != null:
		skill_comp.sync_skills_from_def()
		skill_comp.notify_stats_rebased()
	EventBus.soldier_promoted.emit(self, def)
	EventBus.floating_text.emit("转职！%s" % def.display_name, Color(0.85, 0.7, 1.0),
		global_position + Vector3(0.0, 2.5, 0.0))
	# v33：换树后广播（技能树面板刷新），有返还时飘字告知玩家「点数没白花」
	if skill_tree != null:
		EventBus.skill_tree_changed.emit(self)
		if refunded > 0:
			EventBus.floating_text.emit("技能点返还 +%d" % refunded, Color(0.55, 0.9, 1.0),
				global_position + Vector3(0.0, 2.9, 0.0))
	EventBus.game_message.emit("%s 转职为「%s」" % [keep_name, def.display_name], Color(0.85, 0.7, 1.0))
	AudioManager.play_sfx(&"level_up", global_position)
	return true


## 转职换树（v33）：把旧树已投入的技能点**全额**退回 skill_points，换上 def.skill_tree_id
## 指向的技能树。返回返还点数。
## 口径（Lead 裁决，契约 2.5）：**任何转职都清空已投入级数并全额返还**——沿用 generic 树的
## 老进阶职业（骑士 / 雷电法师 / 漫游射手 / 忍者）同样享受一次免费洗点，玩家不用记哪些职业会洗点。
## 新 def 未配树（skill_tree_id 为空）时保留原树——宁可少换树也不能让玩家丢树。
func _rebind_skill_tree() -> int:
	var new_tree_id: StringName = def.skill_tree_id if def != null else &""
	if new_tree_id == &"":
		return 0
	var new_tree_def: SkillTreeDef = GameDefs.skill_tree_def(new_tree_id)
	if new_tree_def == null:
		return 0
	if skill_tree == null:
		# 基础 def 无树、进阶 def 有树（理论少见）：直接建树，无可返还点数
		skill_tree = PawnSkillTree.new()
		skill_tree.tree_def = new_tree_def
		skill_tree.apply_pre_unlocks()
		return 0
	var refunded: int = skill_tree.reset_and_refund()   # 清空旧加点（预点亮不计入返还）
	skill_tree.set_tree_def(new_tree_def)               # 换布局（同 id 时布局一致，无副作用）
	skill_points += refunded
	return refunded


func get_home_rest_point() -> Vector3:
	if home != null and is_instance_valid(home):
		return home.global_position + home.global_transform.basis.z.normalized() * 1.45
	var city: CitySystem = _get_city()
	return city.random_point_in_city() if city != null else global_position


## 威胁播报：25~55m 内（按姿态）的战斗求助会吸引该士兵前去支援。
func _on_threat_alert(pos: Vector3, _victim: Node) -> void:
	if is_dead_flag or state_machine == null:
		return
	var dist: float = global_position.distance_to(pos)
	var support_r: float = [30.0, 55.0, 14.0][clampi(stance, 0, 2)]
	if dist > support_r:
		return
	alert_pos = pos
	alert_active = true
	_alert_decay = SoldierIdleState.ALERT_TIMEOUT


func _process(delta: float) -> void:
	# 警报有效期倒计时（防陈旧警报把士兵拉去老战场）
	if alert_active:
		_alert_decay -= delta
		if _alert_decay <= 0.0:
			alert_active = false
	_update_daily_life(delta)


## 昼夜切换重置：新的一夜重新选待命点，并给夜间群聊一点初始错峰；
## 天亮清掉夜间标记（状态层会在下一物理帧回到白天巡逻 / 生活）。
func _on_night_changed(is_night: bool) -> void:
	_night_is_night = is_night
	night_post_valid = false
	night_vigil_active = false
	if is_night:
		night_chat_cooldown = maxf(night_chat_cooldown, randf_range(1.5, 5.0))
	else:
		night_chat_cooldown = 0.0
		_clear_defense_deployment()   # v44：天亮兜底解除威胁部署（正常另有信号清除）


## v44 威胁方向信号：守城准备期由 WildlifeSpawner 选门后广播；active=false 为清除。
## 只消费信号里的 gate_index / gate_inside，不读刷怪器私有字段。
func _on_night_threat_direction_changed(active: bool, gate_index: int, gate_inside: Vector3) -> void:
	if not active or gate_index < 0:
		_clear_defense_deployment()
		return
	defense_active = true
	defense_gate_index = gate_index % 4
	defense_inside = gate_inside
	if defense_inside.length_squared() < 0.01:
		# 兜底：信号只给门号时按 WorldLayout 纯函数推导内侧点
		var p := WorldLayout.gate_inside_point(defense_gate_index)
		defense_inside = Vector3(p.x, 0.0, p.y)
	defense_outward = WorldLayout.gate_outward_dir(defense_gate_index)
	defense_slot_valid = false   # 换门 / 新兵补发时重新解算槽位


func _clear_defense_deployment() -> void:
	defense_active = false
	defense_gate_index = -1
	defense_inside = Vector3.ZERO
	defense_outward = Vector3.ZERO
	defense_slot_valid = false


func request_town_life() -> void:
	town_life_active = true
	town_life_left = randf_range(GameDefs.SOLDIER_TOWN_SECONDS.x, GameDefs.SOLDIER_TOWN_SECONDS.y)
	patrol_left = randf_range(GameDefs.SOLDIER_PATROL_SECONDS.x, GameDefs.SOLDIER_PATROL_SECONDS.y)
	_aggro_cache_frame = -100


func wants_town_life() -> bool:
	return town_life_active or TimeManager.is_night()


func _update_daily_life(delta: float) -> void:
	if is_dead_flag or state_machine == null or state_machine.current_state == null:
		return
	chat_cooldown = maxf(0.0, chat_cooldown - delta)
	night_chat_cooldown = maxf(0.0, night_chat_cooldown - delta)
	# 兜底：没有 DayNightCycle 的场景里 TimeManager 跳钟不会发 night_changed，
	# 这里比较昼夜状态补一次重置（与 EventBus 回调幂等）。
	var now_night := TimeManager.is_night()
	if now_night != _night_is_night:
		_on_night_changed(now_night)
	if is_instance_valid(follow_leader) or stance == Pawn.Stance.HOLD:
		return   # 玩家编队和驻守指令不被自主生活打断
	var state := String(state_machine.current_state.name)
	var city := _get_city()
	if city == null:
		return
	if TimeManager.is_night() and not town_life_active:
		request_town_life()
	if town_life_active:
		if city.is_in_city(global_position) and state in ["idle", "wander", "rest", "chat", "night_vigil", "night_chat"]:
			town_life_left = maxf(0.0, town_life_left - delta)
			if town_life_left <= 0.0 and not TimeManager.is_night():
				town_life_active = false
				_aggro_cache_frame = -100
	else:
		if state in ["patrol", "fight"]:
			patrol_left -= delta
			if patrol_left <= 0.0:
				request_town_life()
	_social_scan_left -= delta
	if _social_scan_left <= 0.0:
		_social_scan_left = randf_range(0.6, 1.0)
		if can_chat():
			for neighbor in nearby_group_members("player_unit", GameDefs.SOLDIER_CHAT_RADIUS):
				if neighbor is Soldier and try_chat_with(neighbor as Soldier):
					break


## 城内生活时不被城外游荡怪吸走；闯入城内的敌人仍会触发驻防。
func _valid_hostile_candidate(e: Node, range_sq: float, city: CitySystem = null) -> bool:
	if not super._valid_hostile_candidate(e, range_sq, city):
		return false
	var own_city := _get_city()
	if wants_town_life() and not is_instance_valid(follow_leader) and stance != Pawn.Stance.HOLD and own_city != null:
		return own_city.is_in_city((e as Node3D).global_position)
	return true


func can_chat() -> bool:
	if team_comp == null or team_comp.team != TeamComponent.Team.PLAYER:
		return false
	if TimeManager.is_night():
		return false   # 夜间走 night_chat 分组闲聊，不复用白天双人聊天契约
	if is_dead_flag or is_instance_valid(follow_leader) or stance == Pawn.Stance.HOLD \
			or alert_active or is_instance_valid(healing_trip) or is_instance_valid(chat_partner) \
			or chat_cooldown > 0.0 or health == null or health.ratio() < TAVERN_EXIT_RATIO:
		return false
	var city := _get_city()
	if city == null or not city.is_in_city(global_position) or state_machine == null or state_machine.current_state == null:
		return false
	return String(state_machine.current_state.name) in ["idle", "wander", "rest"]


func try_chat_with(other: Soldier) -> bool:
	if not is_instance_valid(other) or other == self or not can_chat() or not other.can_chat():
		return false
	if global_position.distance_to(other.global_position) > GameDefs.SOLDIER_CHAT_RADIUS:
		return false
	var nav := _get_nav_system()
	if nav != null and not nav.can_walk_segment(global_position, other.global_position):
		return false   # 隔墙 / 隔水不能聊天
	if find_nearest_hostile(14.0) != null or other.find_nearest_hostile(14.0) != null:
		return false
	if SpeechBubble3D.active_count() >= SpeechBubble3D.MAX_CONCURRENT \
			or speech_bubble.is_showing() or other.speech_bubble.is_showing():
		return false
	var lines: Array = GameDefs.SOLDIER_CHAT_LINES.pick_random()
	chat_partner = other
	other.chat_partner = self
	state_machine.transition_to("chat", {"initiator": true, "lines": lines})
	other.state_machine.transition_to("chat", {"initiator": false, "lines": lines})
	return true


# ---- v43 夜间待命点（城内安全点，按 instance_id 稳定分布）----

## 稳定哈希：instance_id → 0..1（同一小兵每夜选到同类型的点）。
func _night_hash(salt: float = 0.0) -> float:
	return fmod(absf(float(get_instance_id())) * 0.6180339887 + salt, 1.0)


## 格子是否可站（湖 / 建筑 / 资源点 / 主城地基都会被 A* 标成阻挡）。
func _night_post_walkable(nav: NavSystem, point: Vector3) -> bool:
	if nav == null or nav.grid == null:
		return true
	return nav.is_walkable_cell(nav.grid.world_to_grid(point))


## 已选待命点是否仍然有效（建筑新建 / 拆路后可能被占用）。
func _night_post_still_valid() -> bool:
	var city := _get_city()
	if city != null and not city.is_in_city(night_post):
		return false
	var nav := _get_nav_system()
	if nav != null and not _night_post_walkable(nav, night_post):
		return false
	return true


## 选定本夜待命点：家附近 / 酒馆附近 / 城内路边 / 城心（按 instance_id 稳定分布），
## 全部经 nav.snap_to_walkable + 可走格校验，避开建筑 / 水系 / 主城地基。
## 每夜只选一次（night_post_valid 缓存），抵达后不再换点。
func ensure_night_post() -> Vector3:
	if night_post_valid and _night_post_still_valid():
		return night_post
	night_post_valid = false
	var city := _get_city()
	var nav := _get_nav_system()
	if city == null:
		night_post = global_position
		night_post_valid = true
		return night_post
	var seed_value: float = absf(float(get_instance_id()))
	var angle: float = _night_hash() * TAU
	var kind: int = int(seed_value) % 4
	var tavern := find_nearest_tavern()
	var candidates: Array[Vector3] = []
	# 1) 家附近（住家门口外一点）
	if kind == 0 and is_instance_valid(home):
		candidates.append(home.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.6)
	# 2) 酒馆附近（馆旁光环圈内，但不挡住门）
	if kind == 1 and is_instance_valid(tavern):
		var tavern_r: float = 4.0
		if tavern.def != null:
			tavern_r = maxf(2.8, tavern.def.heal_radius * 0.55)
		candidates.append(tavern.global_position + Vector3(cos(angle), 0.0, sin(angle)) * tavern_r)
	# 3) 城内路边（有玩家土路时选一格路心）
	if kind == 2 and nav != null and nav.grid != null and not nav.grid.road_cells.is_empty():
		var road_keys: Array = nav.grid.road_cells.keys()
		var cell: Vector2i = road_keys[int(seed_value) % road_keys.size()]
		candidates.append(nav.grid.grid_to_world(cell))
	# 4) 城心内环（主城地基 ±4m 之外；snap 会再避开建筑）
	var inner_r: float = 6.0 + _night_hash(0.37) * 7.0
	candidates.append(Vector3(cos(angle), 0.0, sin(angle)) * inner_r)
	candidates.append(Vector3(cos(angle + 2.399), 0.0, sin(angle + 2.399)) * (6.0 + _night_hash(0.71) * 8.0))
	# 兜底候选：家 / 酒馆的另一个方位（尽量让点落在有意义的位置）
	if is_instance_valid(home):
		candidates.append(home.global_position + Vector3(cos(angle + 1.2), 0.0, sin(angle + 1.2)) * 3.2)
	if is_instance_valid(tavern):
		candidates.append(tavern.global_position + Vector3(cos(angle + 1.2), 0.0, sin(angle + 1.2)) * 4.2)
	for raw in candidates:
		var point: Vector3 = Vector3(raw.x, 0.0, raw.z)
		if nav != null:
			point = nav.snap_to_walkable(point)
			point.y = 0.0
		if city.is_in_city(point) and _night_post_walkable(nav, point):
			night_post = point
			night_post_valid = true
			return night_post
	# 最后兜底：城内随机点吸附（只发生一次，不作为逐帧换点来源）
	var fallback := city.random_point_in_city(3.0)
	fallback.y = 0.0
	if nav != null:
		fallback = nav.snap_to_walkable(fallback)
		fallback.y = 0.0
	night_post = fallback
	night_post_valid = true
	return night_post


# ---- v44 夜间威胁方向部署：城门内侧阵列（近战前排 / 远程后排）----

## 是否可加入今夜防御阵列：活着、不在主角小队、不处于驻守姿态。
func is_defense_deployable() -> bool:
	return not is_dead_flag and not is_instance_valid(follow_leader) and stance != Pawn.Stance.HOLD


## 是否远程兵（远程到后排；近战到前排）。
func is_ranged_combatant() -> bool:
	return def != null and def.attack_kind == PawnDef.AttackKind.RANGED


## 可部署名单签名：门号 + 城门内侧点 + 排序后的 instance_id。名单/门号不变就复用布局，
## 避免战斗里每死一个人就把整条阵型重排；换门或新兵补发威胁时才重建一次。
func _defense_roster_key() -> String:
	var ids: Array = []
	for node in get_tree().get_nodes_in_group("player_unit"):
		if is_instance_valid(node) and node is Soldier and (node as Soldier).is_defense_deployable():
			ids.append(int(node.get_instance_id()))
	ids.sort()
	var parts: Array = []
	for id in ids:
		parts.append(str(id))
	return "%d|%.2f,%.2f|%s" % [defense_gate_index, defense_inside.x, defense_inside.z, ",".join(parts)]


## 解算 / 复用本兵的防御槽位。返回 false 表示当前不在部署状态或本兵不在可部署名单里。
## 槽位：以城门内侧点为前排基准，沿「朝城内」方向按行距排行；近战行在前、远程行在后，
## 每行最多 8 人、横向 2m 居中；落点 nav.snap_to_walkable 且保持在城内。
func ensure_defense_slot() -> bool:
	if not defense_active or defense_gate_index < 0:
		defense_slot_valid = false
		return false
	if not defense_slot_valid:
		var key := _defense_roster_key()
		if key != _defense_layout_key:
			_rebuild_defense_layout(key)
		var id := get_instance_id()
		if not _defense_layout.has(id):
			return false
		defense_slot = _defense_layout[id]
		defense_outward = WorldLayout.gate_outward_dir(defense_gate_index)
		defense_slot_valid = true
	return true


## 重建今夜防御阵列布局（近战行先排，远程行接在后面）。静态缓存供所有士兵共享。
func _rebuild_defense_layout(key: String) -> void:
	_defense_layout = {}
	var melee: Array = []
	var ranged: Array = []
	for node in get_tree().get_nodes_in_group("player_unit"):
		if not is_instance_valid(node) or not (node is Soldier):
			continue
		var soldier := node as Soldier
		if not soldier.is_defense_deployable():
			continue
		if soldier.is_ranged_combatant():
			ranged.append(soldier)
		else:
			melee.append(soldier)
	melee.sort_custom(_defense_soldier_id_before)
	ranged.sort_custom(_defense_soldier_id_before)
	var outward := WorldLayout.gate_outward_dir(defense_gate_index)
	var lateral := WorldLayout.gate_lateral_dir(defense_gate_index)
	var next_row: int = _place_defense_rows(melee, 0, outward, lateral)
	_place_defense_rows(ranged, next_row, outward, lateral)
	_defense_layout_key = key


## sort_custom 回调：按 instance_id 升序（同夜名单稳定）。
func _defense_soldier_id_before(a, b) -> bool:
	return (a as Soldier).get_instance_id() < (b as Soldier).get_instance_id()


## 强制下一次重建今夜阵型布局（阵位被新建建筑占用 / 被挤到不可走格时用）。
## 只清静态 key，让 ensure_defense_slot 重新按当前寻路格吸附；已站定的其他兵不受影响。
func force_defense_slot_rebuild() -> void:
	_defense_layout_key = ""
	defense_slot_valid = false


## 把一组士兵按每行 <=8 人排进阵列，返回下一可用行号。
func _place_defense_rows(group: Array, start_row: int, outward: Vector3, lateral: Vector3) -> int:
	var nav := _get_nav_system()
	var city := _get_city()
	var row: int = start_row
	var index: int = 0
	while index < group.size():
		var count_in_row: int = mini(DEFENSE_ROW_MAX, group.size() - index)
		for col in count_in_row:
			var soldier := group[index + col] as Soldier
			var lateral_off: float = (float(col) - float(count_in_row - 1) * 0.5) * DEFENSE_LATERAL_SPACING
			var point: Vector3 = defense_inside - outward * (DEFENSE_ROW_SPACING * float(row)) \
				+ lateral * lateral_off
			point.y = 0.0
			if nav != null:
				point = nav.snap_to_walkable(point)
				point.y = 0.0
			point = _clamp_defense_point_in_city(point, city, outward, nav)
			_defense_layout[soldier.get_instance_id()] = point
		index += count_in_row
		row += 1
	return row


## 槽位吸附后若被挤到城外（贴边 / 弯道），沿朝城内方向回退到城内可走格。
func _clamp_defense_point_in_city(point: Vector3, city: CitySystem, outward: Vector3, nav: NavSystem) -> Vector3:
	for _i in 8:
		if city == null or city.is_in_city(point):
			return point
		point -= outward * 1.5
		point.y = 0.0
		if nav != null:
			point = nav.snap_to_walkable(point)
			point.y = 0.0
	return point


# ---- v43 夜间群聊：2~3 人围站、轮流冒泡、结束回各自待命点 ----

## 是否具备发起 / 加入夜间群聊的条件（双方共用同一契约）。
func _night_chat_ready() -> bool:
	if team_comp == null or team_comp.team != TeamComponent.Team.PLAYER:
		return false
	if not TimeManager.is_night():
		return false
	if is_dead_flag or is_instance_valid(follow_leader) or stance == Pawn.Stance.HOLD \
			or alert_active or is_instance_valid(healing_trip) or not night_chat_group.is_empty() \
			or night_chat_cooldown > 0.0 or health == null or health.ratio() < TAVERN_EXIT_RATIO:
		return false
	if not night_vigil_active:
		return false   # 必须已在待命点站定（不追着人聊天）
	var city := _get_city()
	if city == null or not city.is_in_city(global_position) or state_machine == null or state_machine.current_state == null:
		return false
	if String(state_machine.current_state.name) != "night_vigil":
		return false
	if speech_bubble.is_showing() or SpeechBubble3D.active_count() >= SpeechBubble3D.MAX_CONCURRENT:
		return false
	if find_nearest_hostile(14.0) != null:
		return false
	return true


## 发起夜间群聊：从 candidates 中招募 1~2 名附近同样待命的小兵（2~3 人一组）。
## 组内共享同一个 night_chat_group Array，退出时各自移除自己并进入 25~45s 冷却。
func try_night_chat_with(candidates: Array) -> bool:
	if not _night_chat_ready():
		return false
	if speech_bubble.is_showing() or SpeechBubble3D.active_count() >= SpeechBubble3D.MAX_CONCURRENT:
		return false
	var nav := _get_nav_system()
	var recruits: Array = []
	for node in candidates:
		if recruits.size() >= 2:
			break
		if not is_instance_valid(node) or not (node is Soldier) or node == self:
			continue
		var other := node as Soldier
		if not other._night_chat_ready():
			continue
		if global_position.distance_to(other.global_position) > GameDefs.SOLDIER_NIGHT_CHAT_RADIUS:
			continue
		if nav != null and not nav.can_walk_segment(global_position, other.global_position):
			continue   # 隔墙 / 隔水不能凑到一起
		recruits.append(other)
	if recruits.is_empty():
		return false
	var members: Array = [self]
	members.append_array(recruits)
	var group: Array = members.duplicate()
	var lines: Array = GameDefs.soldier_night_chat_lines(TimeManager.day)
	var seconds: float = randf_range(GameDefs.SOLDIER_NIGHT_CHAT_SECONDS.x, GameDefs.SOLDIER_NIGHT_CHAT_SECONDS.y)
	for member in members:
		var soldier := member as Soldier
		soldier.night_chat_group = group   # 组内共享引用：任一人退出会从所有人视线里移除
		soldier.state_machine.transition_to("night_chat", {
			"members": group.duplicate(),
			"host": soldier == self,
			"lines": lines,
			"seconds": seconds,
		})
	return true


## 退出夜间群聊：从共享组里移除自己（其余成员下一帧检测到组员离开后一起收尾）。
func leave_night_chat() -> void:
	var group: Array = night_chat_group
	night_chat_group = []
	var idx: int = group.find(self)
	if idx >= 0:
		group.remove_at(idx)


func _setup_nodes() -> void:
	super._setup_nodes()
	_install_life_states()


## 安装士兵日常生活状态：把 idle 换成决策路由，新增 patrol / rest / wander / chat，
## v43 追加夜间待命 night_vigil 与 2~3 人夜间群聊 night_chat。
## super._setup_nodes 已 add_child(state_machine) 且其 _ready 已自动登记 6 基础状态，
## 故用 PawnStateMachine.register_state 手动登记（替换当前 idle 时会平滑切到新状态并重入）。
func _install_life_states() -> void:
	state_machine.register_state("idle", SoldierIdleState.new())
	state_machine.register_state("patrol", SoldierPatrolState.new())
	state_machine.register_state("rest", SoldierRestState.new())
	state_machine.register_state("wander", SoldierWanderState.new())
	state_machine.register_state("chat", preload("res://scripts/entities/pawn/states/SoldierChatState.gd").new())
	state_machine.register_state("night_vigil", SoldierNightVigilState.new())
	state_machine.register_state("night_chat", SoldierNightChatState.new())
