class_name RangedFightState
extends PawnState
## ============================================================================
## 远程兵战斗状态（风筝）：在攻击射程内尽量保持距离输出。
## 三档行为：
##   1) 射程内且敌人未近身（surface_dist ∈ [kite_safe_range, attack_range]）→ 站定射击
##   2) 被近身（surface_dist < kite_safe_range）→ 反向移动拉开距离，边退边射（风筝）
##   3) 射程外 → 沿 NavMesh 靠近（同 FightState）
## 风筝走 steering 不走 NavMesh（同 FollowState 理由）：贴身短距机动，
## 物理 collision_mask=1|8 已能挡墙防穿模；被逼墙角则原地硬射。
## 目标失效时尝试重新索敌，否则回待命。
## ============================================================================

var target   # Node（敌方单位/建筑）
var _last_target_pos: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
const RETARGET_DIST: float = 1.0      # 目标移动超过此距离才 repath
const RETARGET_TIMEOUT: float = 0.5   # 兜底超时强制 repath
const SELF_RADIUS: float = 0.4        # 自身近似碰撞半径（与 AttackerComponent 一致）
const KITE_DIR_DEADZONE: float = 0.01  # 风筝方向分量小于此则视为被逼墙，原地射
const STUCK_SAMPLE_INTERVAL: float = 2.5  # stuck 采样周期（与 FightState 同款）
const STUCK_MIN_CLOSING: float = 1.0      # 一个采样周期内中心距至少缩减此值才算有进展
const STUCK_SPEED_EPS: float = 0.5        # 速度低于此视为「想走走不动」（排除正常走路）

var _stuck_check_timer: float = 0.0   # 距上次 stuck 采样经过的时间
var _stuck_last_dist: float = -1.0    # 上次采样时与目标的中心距（<0 = 尚无基准）


func enter(msg: Dictionary) -> void:
	target = msg.get("target", null)
	pawn.combat_target = target
	_last_target_pos = Vector3.ZERO
	_retarget_timer = RETARGET_TIMEOUT   # 进入即立即设一次
	_reset_stuck_tracking()
	# 追击阶段保持跑步动画；射击动作由下方每次真正的出手触发（旧版在这里播一次
	# 近战挥砍——接敌前就「空挥一刀」，而真正射击时反而没有任何动作）
	pawn.play_anim(&"run")
	call_deferred("_update_nav_target")


func physics_update(delta: float) -> void:
	# 主人集火令最高优先（v18）：正在打其它目标也必须立即转火（与 FightState 同规则）
	var order: Node = _live_focus_order()
	if order != null and order != target:
		state_machine.transition_to("fight", {"target": order})
		return
	# v22 小兵低血撤退：与 FightState 同规则（集火令之后；<20% 且有酒馆 → 回馆疗伤）
	if pawn is Soldier and pawn.health != null \
			and pawn.health.ratio() < Soldier.TAVERN_HEAL_THRESHOLD \
			and (pawn as Soldier).find_nearest_tavern() != null:
		state_machine.transition_to("idle")
		return
	# 目标死亡即视为失效（与 FightState 同规则：不等尸体 1.7s 溶解释放）
	if target == null or not is_instance_valid(target) or _target_dead(target):
		# 小队成员目标失效 / 已击杀：回队长身边重新列队听令（不做 40m 全图索敌，
		# 与 FightState 同规则；follow 态的近敌自动接战仍保留防身）
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

	# v33 隐身：当前目标隐身（看不到）→ 立即脱战回 idle（与 FightState 同规则）
	if _target_invisible(target):
		state_machine.transition_to("idle")
		return

	var tn: Node3D = target
	# 玩家士兵姿态 leash：防御不追远敌 / 驻守不离锚点（v10：集火令例外，与 FightState 同规则）
	var is_focus: bool = _is_focus_target(target)
	if not is_focus and pawn.should_break_engagement(tn.global_position):
		state_machine.transition_to("idle")
		return

	# 职业技能（v19）：CD 就绪优先释放——法师进射程即落暴风雪、游侠接战先手三连射；
	# 未就绪 / 超出施法距离返回 false，不影响原有风筝与普攻逻辑
	if pawn.try_cast_combat_skill(target):
		return

	var center_dist: float = pawn.global_position.distance_to(tn.global_position)
	var surface_dist: float = center_dist - SELF_RADIUS
	var attack_range: float = pawn.attacker.attack_range
	var kite_safe: float = _kite_safe_range()

	# ---- 档 1：射程内、敌人未近身 → 站定射击 ----
	if surface_dist <= attack_range and surface_dist >= kite_safe:
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		_face_target()
		# 冷却期站定呼吸（射击动画播放期间此请求自动让位，见 PawnModelRig.play）
		pawn.play_anim(&"idle")
		if pawn.attacker.try_attack(target):
			pawn.play_anim(&"shoot")   # 出手即上射击动作，与枪口闪光 / 弹体同帧起步
		return

	# ---- 档 2：被近身 → 反向风筝（边退边射）----
	if surface_dist < kite_safe:
		var flee: Vector3 = pawn.global_position - tn.global_position
		flee.y = 0.0
		if flee.length_squared() > KITE_DIR_DEADZONE:
			pawn.velocity = flee.normalized() * pawn.effective_move_speed()   # 减速同样作用于后撤
			pawn.move_and_slide()   # 物理碰撞挡墙（mask=1|8）
		else:
			pawn.velocity = Vector3.ZERO   # 被逼墙角：原地硬射
			pawn.move_and_slide()
		_face_target()
		# 后撤移动动画（射击动画播放期间让位；播完自动回落跑步，不再滑行定格）
		pawn.play_anim(&"run")
		if pawn.attacker.try_attack(target):   # 仍在射程内（kite_safe < attack_range），try_attack 内 in_range 放行
			pawn.play_anim(&"shoot")
		return

	# ---- 档 3：射程外 → 沿 NavMesh 靠近（同 FightState）----
	_retarget_timer += delta
	var moved: float = tn.global_position.distance_to(_last_target_pos)
	if moved > RETARGET_DIST or _retarget_timer >= RETARGET_TIMEOUT:
		_update_nav_target()
		_retarget_timer = 0.0
	# ---- stuck 检测：射程外沿路靠近却被墙 / 湖角卡住 ----
	# 远程兵没有破墙职责，统一脱战回 idle（让 idle 决策路由重新选路）。
	# 此刻 velocity 仍是上一帧 move_and_slide 后的值，能如实反映「被挡住」。
	_stuck_check_timer += delta
	if _stuck_check_timer >= STUCK_SAMPLE_INTERVAL:
		var sample_dist: float = pawn.global_position.distance_to(tn.global_position)
		var has_baseline: bool = _stuck_last_dist >= 0.0
		var closing: float = _stuck_last_dist - sample_dist
		_stuck_last_dist = sample_dist
		_stuck_check_timer = 0.0
		if has_baseline and closing < STUCK_MIN_CLOSING \
				and (pawn.attacker == null or not pawn.attacker.in_range(target)) \
				and pawn.velocity.length() < STUCK_SPEED_EPS:
			_reset_stuck_tracking()
			state_machine.transition_to("idle")
			return
	pawn.move_along_path(delta)
	if pawn.navigation_status == Pawn.NavigationStatus.BLOCKED:
		pawn.play_anim(&"idle")
		if not _is_focus_target(target):
			pawn.avoid_hostile_temporarily(target)
			state_machine.transition_to("idle")


func _kite_safe_range() -> float:
	# 从 def 读；未设则取 attack_range * 0.55 兜底
	if pawn.def != null and pawn.def.kite_safe_range > 0.0:
		return pawn.def.kite_safe_range
	return pawn.attacker.attack_range * 0.55


func _face_target() -> void:
	var dir: Vector3 = (target as Node3D).global_position - pawn.global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		pawn.look_at_target(dir.normalized())


func _update_nav_target() -> void:
	if state_machine.current_state != self:
		return
	if target == null or not is_instance_valid(target):
		return
	var pos: Vector3 = (target as Node3D).global_position
	pawn.set_navigation_target(pos)
	_last_target_pos = pos


func _on_navmesh_updated() -> void:
	_update_nav_target()


## 重置 stuck 采样基准（进入状态 / 换目标 / 响应之后调用）。
func _reset_stuck_tracking() -> void:
	_stuck_check_timer = 0.0
	_stuck_last_dist = -1.0


## 目标是否已死（尸体未释放也算）。与 FightState 同一实现。
func _target_dead(t) -> bool:
	return t is Pawn and (t as Pawn).is_dead_flag


## 目标是否隐身不可见（v33）。与 FightState 同一实现。
func _target_invisible(t) -> bool:
	return t is Pawn and not (t as Pawn).can_be_seen_by_enemies()


## 队长当前有效的集火令（与 FightState 同一实现，v18）。
func _live_focus_order() -> Node:
	var leader = pawn.follow_leader
	if leader == null or not is_instance_valid(leader):
		return null
	if not leader.has_method("is_focus_alive") or not leader.call("is_focus_alive"):
		return null
	return leader.get("focus_target")


## 是否为队长的集火目标（与 FightState 同一实现，v10）。
func _is_focus_target(t) -> bool:
	return t != null and _live_focus_order() == t


func exit() -> void:
	if pawn.combat_target == target:
		pawn.combat_target = null
