class_name FightState
extends PawnState
## 战斗状态：目标在射程外则沿 NavMesh 靠近，在射程内则站定攻击。
## 站定/攻击判定统一用 AttackerComponent.in_range（表面距离），
## 这样大型障碍（基地/建筑）即使物理上靠不到中心，贴边也能打到。
## 目标失效时尝试重新索敌，否则回待命。
## v3：夜袭攻城（siege，临时无视避城）、低血逃跑、士兵姿态追击 leash。

var target   # Node（敌方单位/建筑）
var _last_target_pos: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
var _sieging: bool = false         # 本轮进入时是否带攻城标记（exit 时还原 pawn._sieging）
const RETARGET_DIST: float = 1.0     # 目标移动超过此距离才 repath
const RETARGET_TIMEOUT: float = 0.5  # 兜底超时强制 repath
const SLOT_SETTLE_DIST: float = 0.65 # 到达自己的环绕站位后才站定攻击
const SEPARATION_RADIUS: float = 1.5
const CHASE_REPATH_LEASH: float = 44.0   # 追击中心距上限（防跨图追杀）
const STUCK_SAMPLE_INTERVAL: float = 2.5  # stuck 采样周期
const STUCK_MIN_CLOSING: float = 1.0      # 一个采样周期内中心距至少缩减此值才算有进展
const STUCK_SPEED_EPS: float = 0.5        # 速度低于此视为「想走走不动」（排除正常走路）
const STUCK_WALL_BREAK_RANGE: float = 12.0 # 破口搜索：身边此直线距离内找挡路的建筑

var _city_route_blocked: bool = false
var _holding_attack: bool = false
var _stuck_check_timer: float = 0.0   # 距上次 stuck 采样经过的时间
var _stuck_last_dist: float = -1.0    # 上次采样时与目标的中心距（<0 = 尚无基准）


func enter(msg: Dictionary) -> void:
	target = msg.get("target", null)
	_holding_attack = false
	_city_route_blocked = false
	_sieging = bool(msg.get("siege", false))
	pawn._sieging = pawn._sieging or _sieging
	pawn.combat_target = target
	_last_target_pos = Vector3.ZERO
	_retarget_timer = RETARGET_TIMEOUT   # 进入即立即设一次
	_reset_stuck_tracking()
	# 攻击动画只在真正命中时触发；追击阶段应保持跑步动画。
	pawn.play_anim(&"run")
	call_deferred("_update_nav_target")


func physics_update(delta: float) -> void:
	# 主人集火令最高优先（v18）：正在打其它目标（自动索敌接上的）也必须立即转火，
	# 不能等当前目标死掉才理睬新命令——「小兵不听话」的主因之一。
	var order: Node = _live_focus_order()
	if order != null and order != target:
		state_machine.transition_to("fight", {"target": order})
		return
	# v22 小兵低血撤退：玩家小兵血量 < 20% 且场上有酒馆 → 立即脱战回馆疗伤
	# （排在集火令之后：玩家直接命令仍是最高优先；回 idle 由 SoldierIdleState 路由去酒馆）
	if pawn is Soldier and pawn.health != null \
			and pawn.health.ratio() < Soldier.TAVERN_HEAL_THRESHOLD \
			and (pawn as Soldier).find_nearest_tavern() != null:
		state_machine.transition_to("idle")
		return
	# 目标死亡即视为失效（野怪尸体要 1.7s 动画+溶解后才 queue_free，
	# 若只看 is_instance_valid 会对着尸体空挥 1.7s 才回队——听令手感明显迟滞）
	if target == null or not is_instance_valid(target) or _target_dead(target):
		# 小队成员目标失效 / 已击杀：回队长身边重新列队听令。
		# 不再走 40m 全图索敌（旧版会顺手追打远处无关敌人，脱离指挥 = 不听话）；
		# follow 态的 7m 近敌自动接战仍保留，防身职责不变。
		if pawn.follow_leader != null and is_instance_valid(pawn.follow_leader):
			state_machine.transition_to("follow", {"leader": pawn.follow_leader})
			return
		if pawn is Soldier and (pawn as Soldier).wants_town_life():
			state_machine.transition_to("idle")
			return
		var enemy = pawn.find_nearest_hostile()
		if enemy != null:
			target = enemy
			pawn.combat_target = target
			_reset_stuck_tracking()   # 换目标：stuck 基准作废重立
		else:
			state_machine.transition_to("idle")
			return

	# v33 隐身：当前目标隐身（看不到）→ 立即脱战回 idle，由 idle 决策路由重新索敌
	# （索敌侧 _valid_hostile_candidate 同样跳过隐身目标，不会「对着空气挥」）。
	if _target_invisible(target):
		state_machine.transition_to("idle")
		return

	# 夜袭攻城中天亮了 → 撤退（idle/roam 会把他们弹出城外）
	if _sieging and not Raider.is_night_now():
		state_machine.transition_to("idle")
		return

	# 野怪不进城（夜袭攻城例外）：① 自己若已身处城内（追击时寻路贴边误入）立刻脱战
	# ② 目标撤回主城也脱战。两者都回 idle → RoamState 把它弹出城外，杜绝穿城。
	if pawn.avoids_city and not pawn._sieging:
		var city: CitySystem = pawn._get_city()
		if city != null and (city.is_in_city(pawn.global_position) or city.is_in_city((target as Node3D).global_position)):
			state_machine.transition_to("idle")
			return
		if pawn is Raider and (pawn as Raider).is_beyond_leash():
			state_machine.transition_to("roam")
			return

	# 低血逃跑（非攻城、非头目、掷中「怕死签」才跑）：掉头就跑，脱战回血再来。
	# v35 概率化：血量到线后按 def.flee_chance 一次性掷签（见 Raider.should_flee_now），
	# 多数怪死战到底——近战小兵不再被迫追杀跑得比自己快的逃跑怪
	if pawn is Raider and (pawn as Raider).should_flee_now():
		state_machine.transition_to("raider_flee", {"threat": target})
		return

	# 玩家士兵姿态 leash：防御不追远敌 / 驻守不离锚点（v10：集火令例外——追到死为止）
	if not _is_focus_target(target) and pawn.should_break_engagement((target as Node3D).global_position):
		state_machine.transition_to("idle")
		return

	# 职业技能（v19）：CD 就绪优先释放——刺客背刺 7m 内先手突进、战士血怒接战即怒；
	# 未就绪 / 不满足条件返回 false，不影响原有走位与普攻逻辑
	if pawn.try_cast_combat_skill(target):
		return

	var tn: Node3D = target
	var approach_pos: Vector3 = pawn.get_combat_approach_position(tn)
	var to_slot: Vector3 = approach_pos - pawn.global_position
	to_slot.y = 0.0
	# 站定攻击判定（表面距离 + 分槽站位）：贴在大型障碍边缘也算可达，且不与友军重叠。
	if pawn.attacker != null and pawn.attacker.in_range(target) and (_holding_attack or to_slot.length() <= SLOT_SETTLE_DIST or pawn.is_navigation_done()):
		_holding_attack = true
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		var dir: Vector3 = tn.global_position - pawn.global_position
		dir.y = 0.0
		if dir.length() > 0.001:
			pawn.look_at_target(dir.normalized())
		# 攻击冷却期站定呼吸（挥击动画播放期间此请求自动让位，见 PawnModelRig.play；
		# 挥击播完回落 idle——两次出招之间不再定格在收招姿势）
		pawn.play_anim(&"idle")
		if pawn.attacker.try_attack(target):
			pawn.play_anim(&"fight")
		return

	_holding_attack = false
	# 追击中心距上限：目标跑太远（或自己被拉扯出战场）就放弃（集火令 / 攻城例外）。
	# 攻城目标是不会跑的建筑 / 主城——夜潮大部队从四条道路尽头（~57m）出发，
	# 跨半张地图压向主城正是它的使命，不能被判成「跨图追杀」而原地折返（v20）。
	if not pawn._sieging and not _is_focus_target(target) \
			and pawn.global_position.distance_to(tn.global_position) > CHASE_REPATH_LEASH + pawn.attacker.attack_range:
		state_machine.transition_to("idle")
		return

	# 未在射程：按距离/超时双触发 repath，沿 NavMesh 靠近
	_retarget_timer += delta
	var moved: float = tn.global_position.distance_to(_last_target_pos)
	if moved > RETARGET_DIST or _retarget_timer >= RETARGET_TIMEOUT:
		_update_nav_target()
		_retarget_timer = 0.0
	if _city_route_blocked:
		pawn.avoid_hostile_temporarily(target)
		state_machine.transition_to("roam")
		return
	# ---- stuck 检测：路径存在却被墙 / 湖角 / 建筑卡住（站桩或原地蹭）----
	# 每 STUCK_SAMPLE_INTERVAL 秒采样一次：期间与目标中心距几乎没缩 + 不在射程 +
	# 速度接近 0（想走走不动）→ 判定卡住，按阵营换目标或脱战。
	# 此刻 velocity 仍是上一帧 move_and_slide 后的值，能如实反映「被挡住」。
	_stuck_check_timer += delta
	if _stuck_check_timer >= STUCK_SAMPLE_INTERVAL:
		var center_dist: float = pawn.global_position.distance_to(tn.global_position)
		var has_baseline: bool = _stuck_last_dist >= 0.0
		var closing: float = _stuck_last_dist - center_dist
		_stuck_last_dist = center_dist
		_stuck_check_timer = 0.0
		if has_baseline and closing < STUCK_MIN_CLOSING \
				and (pawn.attacker == null or not pawn.attacker.in_range(target)) \
				and pawn.velocity.length() < STUCK_SPEED_EPS:
			if _handle_stuck(tn):
				return
	var group := "player_unit" if pawn.team_comp.team == TeamComponent.Team.PLAYER else "enemy"
	pawn._steer_separation = pawn.compute_separation(group, SEPARATION_RADIUS) * 3.5
	pawn.play_anim(&"idle" if pawn.navigation_status in [Pawn.NavigationStatus.UNREACHABLE, Pawn.NavigationStatus.BLOCKED] else &"run")
	pawn.move_along_path(delta)
	if pawn.navigation_status == Pawn.NavigationStatus.BLOCKED:
		_handle_stuck(tn)


func _update_nav_target() -> void:
	if state_machine.current_state != self:
		return
	if target == null or not is_instance_valid(target):
		return
	var pos: Vector3 = pawn.get_combat_approach_position(target as Node3D)
	if pawn.avoids_city and not pawn._sieging:
		var city: CitySystem = pawn._get_city()
		var nav: NavSystem = pawn._get_nav_system()
		if city != null and nav != null and (pawn._nav_dirty or pawn._nav_target.distance_squared_to(pos) > 0.0025):
			_city_route_blocked = false
			var previous: Vector3 = pawn.global_position
			for point in nav.get_world_path(previous, pos):
				if city.segment_crosses_city(previous, point):
					_city_route_blocked = true
					break
				previous = point
			if _city_route_blocked:
				return
	pawn.set_navigation_target(pos)
	_last_target_pos = (target as Node3D).global_position


func _on_navmesh_updated() -> void:
	_update_nav_target()


## 目标是否已死（尸体未释放也算：野怪死亡有 1.7s 动画+溶解期）。
func _target_dead(t) -> bool:
	return t is Pawn and (t as Pawn).is_dead_flag


## 目标是否隐身不可见（v33）。隐身期脱战——看不见的目标不该继续被追打。
func _target_invisible(t) -> bool:
	return t is Pawn and not (t as Pawn).can_be_seen_by_enemies()


## 重置 stuck 采样基准（进入状态 / 换目标 / 响应之后调用）。
func _reset_stuck_tracking() -> void:
	_stuck_check_timer = 0.0
	_stuck_last_dist = -1.0


## 队长当前有效的集火令（无令 / 不在队 / 队长失效 → null）。
func _live_focus_order() -> Node:
	var leader = pawn.follow_leader
	if leader == null or not is_instance_valid(leader):
		return null
	if not leader.has_method("is_focus_alive") or not leader.call("is_focus_alive"):
		return null
	return leader.get("focus_target")


## 是否为队长的集火目标（Hero.focus_target）：集火令不受姿态 leash / 追击距离限制，
## 小队会追杀它直到它死亡（v10）。
func _is_focus_target(t) -> bool:
	return t != null and _live_focus_order() == t


## stuck 响应：攻城野怪（pawn._sieging）重新评估攻城目标——换到不同目标就打它
## （被完全围死时 _pick_siege_target 会选到挡路的墙，破口后 navmesh_updated 自动
## repath 进城）；换到的仍是原目标则改打「身边 STUCK_WALL_BREAK_RANGE 米内直线
## 最近的建筑」（通常正是挡路的墙段）。v35 例外：当前正与玩家单位交战时不切回
## 建筑（保持还手，见分支内注释）。其他单位（士兵 / 普通野怪）放弃目标回
## idle，让各自的 idle 决策路由重新选路。返回 true 表示已切状态，调用方须立即
## 结束本帧逻辑。
func _handle_stuck(old_target: Node3D) -> bool:
	_reset_stuck_tracking()
	if _is_focus_target(old_target):
		# Keep the explicit order and wait for target movement / obstacle changes.
		# Cycling idle -> follow -> fight every frame would look like twitching.
		pawn.play_anim(&"idle")
		return false
	if pawn is Raider and pawn._sieging:
		# v35「被打要还手」优先于冲城：正在与玩家单位（Pawn）交战的攻城怪 stuck 时
		# **不得切回建筑目标**——被围死 / 追不上远程风筝兵恰恰是最常 stuck 的场景，
		# 一换回攻城就成了「不理打它的人、一味冲城」。改为重新索敌换最近的玩家
		# 单位（围殴者总在近旁）；附近确实没有玩家单位（风筝兵跑出索敌圈）才
		# 落到下方分支恢复攻城推进。
		if old_target is Pawn and not _target_dead(old_target):
			var near_foe = pawn.find_nearest_hostile()
			if near_foe != null:
				if near_foe != old_target:
					target = near_foe
					pawn.combat_target = near_foe
					_reset_stuck_tracking()
					_update_nav_target()
				return false   # 保持 / 换玩家单位目标，仍在本状态内重试追击
		var new_target: Node3D = (pawn as Raider)._pick_siege_target()
		if new_target != null and is_instance_valid(new_target) and new_target != old_target:
			state_machine.transition_to("fight", {"target": new_target, "siege": true})
			return true
		var blocker: Node3D = _nearest_blocking_building()
		if blocker != null and blocker != old_target:
			state_machine.transition_to("fight", {"target": blocker, "siege": true})
			return true
	pawn.avoid_hostile_temporarily(old_target)
	if pawn is Raider and pawn._sieging:
		(pawn as Raider).siege_cooldown = maxf((pawn as Raider).siege_cooldown, 3.0)
	state_machine.transition_to("idle")
	return true


## 找「自己身边 STUCK_WALL_BREAK_RANGE 米内直线最近的建筑」作为破口目标
## （挡在进攻路线上的通常就是墙）。找不到返回 null。
func _nearest_blocking_building() -> Node3D:
	var best: Node3D = null
	var best_dist: float = STUCK_WALL_BREAK_RANGE
	for b in pawn.get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var d: float = pawn.global_position.distance_to((b as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best


func exit() -> void:
	if pawn.combat_target == target:
		pawn.combat_target = null
	if _sieging:
		pawn._sieging = false
		_sieging = false
