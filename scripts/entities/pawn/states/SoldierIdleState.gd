class_name SoldierIdleState
extends PawnState
## ============================================================================
## 士兵待机 / 决策路由（完整昼夜日循环 + 三姿态 + 威胁响应）。
## 优先级：主角小队跟随 > 夜晚夜间待命 night_vigil（其内部再按疗伤 > 接敌 > 警报 > 驻守 >
## 待命点执行）> 白天：酒馆疗伤（v22 <20% 回馆）> 威胁支援 > 视野内接敌 > 城内生活 / 巡逻。
## 城内时自动回血（_try_city_regen）。本状态不滞留——每帧立即路由到具体行为状态。
## v10：夜间曾改为「回城游荡」；v43 起夜间改交 night_vigil（回城待命点站定 / 群聊，
## 不再满城 wander），天亮由 night_vigil 交回本状态恢复白天巡逻 / 生活。
## v22：低血（<20%）优先回酒馆疗伤（无酒馆回落旧「回城休整」行为），
## 恢复到 95% 以上才出院；疗伤行程中不接战（Soldier.autofight_enabled）。
## ============================================================================

const HEAL_THRESHOLD: float = 0.4     # 血量低于此比例回城治疗（无酒馆时的回落行为）
const IDLE_SIGHT: float = 18.0        # 待机时的索敌视野（小于自动战斗 40m，避免满图追）
# 三姿态：索敌视野 / 支援半径
const STANCE_SIGHT := [16.0, 30.0, 9.0]      # 防御 / 进攻 / 驻守
const STANCE_SUPPORT_R := [30.0, 55.0, 14.0] # 威胁支援响应半径
const ALERT_TIMEOUT: float = 10.0            # 威胁点过期时间


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")


func physics_update(delta: float) -> void:
	# 1) 在主角小队中 → 交由主角指挥（保留现有小队机制，follow 内部自动接战近敌）
	if pawn.follow_leader != null and is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return

	# 2) 夜晚（20:00~06:00，含 v31 守城准备期）→ 夜间待命
	# night_vigil 内部按同一优先级处理：疗伤 > 接敌 > 警报 > 驻守 > 回待命点站定 / 群聊；
	# 入夜后不再路由 wander / patrol，天亮由 night_vigil 交回本状态的白天路由。
	if TimeManager.is_night():
		state_machine.transition_to("night_vigil")
		return

	# 3) 城内回血（在城内才生效；城外不回血）
	pawn._try_city_regen(delta)

	# 4) 低血治疗：优先回酒馆（v22）；无酒馆回落「回城休整」
	if _route_healing():
		return

	# 5) 视野内有敌 → 战斗（视野随姿态放大 / 收缩）
	var sight: float = STANCE_SIGHT[clampi(pawn.stance, 0, 2)] if pawn.stance >= 0 else IDLE_SIGHT
	var enemy = pawn.find_nearest_hostile(maxf(sight, IDLE_SIGHT * 0.5))
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return

	# 6) 威胁支援：附近友军/建筑遇袭（threat_alert 写入 pawn.alert_pos）→ 赶赴现场
	if pawn.alert_active:
		var alert_dist: float = pawn.global_position.distance_to(pawn.alert_pos)
		var support_r: float = STANCE_SUPPORT_R[clampi(pawn.stance, 0, 2)]
		if alert_dist > 3.0 and alert_dist <= support_r:
			pawn.move_target = pawn.alert_pos
			state_machine.transition_to("move")
			return
		pawn.alert_active = false   # 已到达或过远：不再追这条警报

	# 7) 驻守姿态：守在锚点不动（回锚点后站桩）
	if pawn.stance == Pawn.Stance.HOLD:
		var anchor_dist: float = pawn.global_position.distance_to(pawn.hold_anchor)
		if anchor_dist > 2.5:
			pawn.move_target = pawn.hold_anchor
			state_machine.transition_to("move")
		else:
			pawn.play_anim(&"idle")
		return

	# 8) 白天：城内生活与有限时长的巡逻交替（夜晚已在步骤 2 交给 night_vigil）
	if pawn.wants_town_life():
		var city: CitySystem = pawn._get_city()
		if city != null and not city.is_in_city(pawn.global_position):
			# 白天还在城外 → 收兵回城（进城后再交给 wander）
			pawn.move_target = city.random_point_in_city()
			state_machine.transition_to("move")
		else:
			state_machine.transition_to("wander")
	else:
		state_machine.transition_to("patrol")


## 低血治疗路由（v22）。返回 true 表示本帧已切状态（调用方立即结束）。
## · 血量 < 20%：锁定最近酒馆进入疗伤行程（healing_trip）；没有酒馆则回落旧的回城休整。
## · 疗伤行程中：走到酒馆光环圈内就地 rest（光环 20/s + 城内回血）。
## · 血量 ≥ 95%：解除行程恢复正常生活（滞回防抖）。
## · 玩家集火/集结令由 follow 态与 FightState 的显式通道处理，优先级仍最高。
func _route_healing() -> bool:
	if pawn.health == null or not (pawn is Soldier):
		return false
	var soldier := pawn as Soldier
	var ratio: float = pawn.health.ratio()
	# 行程失效清理（酒馆被拆）与满血出院
	if soldier.healing_trip != null and not is_instance_valid(soldier.healing_trip):
		soldier.healing_trip = null
	if soldier.healing_trip != null and ratio >= Soldier.TAVERN_EXIT_RATIO:
		soldier.healing_trip = null
	# 低血触发：找一家酒馆
	if soldier.healing_trip == null and ratio < Soldier.TAVERN_HEAL_THRESHOLD:
		soldier.healing_trip = soldier.find_nearest_tavern()
	# 疗伤行程：走向酒馆 / 已在馆旁就地休整
	if soldier.healing_trip != null:
		var tavern := soldier.healing_trip
		var flat: Vector3 = tavern.global_position - pawn.global_position
		flat.y = 0.0
		if flat.length() <= tavern.def.heal_radius * 0.7:
			# 在馆旁歇脚：休整点取对角外推（footprint 半宽 2m + 余量），仍在光环圈内
			state_machine.transition_to("rest", {"at": tavern.global_position + Vector3(2.6, 0.0, 2.6)})
		else:
			pawn.move_target = tavern.global_position
			state_machine.transition_to("move")
		return true
	# 无酒馆的回落行为（v22 前旧逻辑）：低血回城 / 城内休整
	if ratio < HEAL_THRESHOLD:
		var city: CitySystem = pawn._get_city()
		if city != null and not city.is_in_city(pawn.global_position):
			pawn.move_target = city.random_point_in_city()
			state_machine.transition_to("move")
		else:
			state_machine.transition_to("rest")
		return true
	return false


## 夜间判定：20:00 ~ 06:00。
func _is_night() -> bool:
	var h: int = TimeManager.hour
	return h >= 20 or h < 6
