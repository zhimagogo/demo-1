class_name SoldierNightVigilState
extends PawnState
## ============================================================================
## v43 夜间待命（night_vigil）：非编队 / 非驻守小兵入夜后不再满城巡逻游荡，
## 而是回城走到自己的待命点站定，像在等开战：
##   · 受伤（<95%）且场上有酒馆 → 先回馆疗伤，行程中不自动接战；无酒馆则靠城内回血；
##   · 抵达待命点后站定（可极慢换朝向），不会持续换点 / 满城移动；
##   · 附近同样站定的健康小兵会 2~3 人一组进入 night_chat 闲聊，聊完回各自待命点；
##   · 天亮（离夜）→ 回 idle 恢复白天巡逻 / 生活。
## v44：WildlifeSpawner 广播「今夜威胁方向」后，站定点从常规 night_post 切换为
## 城门内侧防御槽位（近战前排 / 远程后排、每行≤8、行距 2.4m、横向 2m），抵达后朝城外
## 站定；威胁解除 / 天亮自动恢复常规待命点。集结 / 集火 / 驻守 / 警报 / 战斗优先级不变。
## 优先级与白天 idle 完全一致：玩家集结（follow）> 疗伤 > 视野内接敌 > 威胁支援 >
## 驻守锚点 > 自主待命；玩家集火令由 FightState 的显式通道处理，仍最高。
## ============================================================================

const SIGHT := [16.0, 30.0, 9.0]        # 与 SoldierIdleState.STANCE_SIGHT 同口径
const SUPPORT_R := [30.0, 55.0, 14.0]   # 威胁支援半径（与 idle 同口径）
const IDLE_SIGHT: float = 18.0          # 夜晚索敌下限（不比白天更激进）
const POST_ARRIVE: float = 1.2          # 离待命点小于此距离视为到位
const POST_RETRY_SEC: float = 3.0       # 寻路不可达 / 卡住持续这么久才重选待命点
const CHAT_SCAN_MIN: float = 1.2        # 夜间社交扫描间隔（秒）
const CHAT_SCAN_MAX: float = 2.2
const HEAL_RADIUS_SCALE: float = 0.7    # 酒馆旁歇脚：馆占地外沿 + 光环内（与 idle 一致）
const SEP_RADIUS: float = 1.6           # 行军时的友军分离半径

var _post_retry_left: float = 0.0
var _scan_left: float = 0.0
var _gaze_left: float = 0.0


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")
	_post_retry_left = 0.0
	_scan_left = randf_range(CHAT_SCAN_MIN, CHAT_SCAN_MAX)
	_gaze_left = randf_range(6.0, 18.0)
	var soldier := pawn as Soldier
	if soldier != null:
		soldier.night_vigil_active = false
		# v44：有威胁方向时去城门内侧阵列槽位，否则回本夜常规待命点
		var post: Vector3 = _current_hold_point(soldier)
		pawn.set_navigation_target(post)


## 当前站定点：威胁部署激活时用城门内侧阵列槽位（近战前排 / 远程后排），
## 否则回本夜常规 night_post（家 / 酒馆 / 路边 / 城心）。
func _current_hold_point(soldier: Soldier) -> Vector3:
	if soldier.defense_active and soldier.ensure_defense_slot():
		return soldier.defense_slot
	return soldier.ensure_night_post()


func physics_update(delta: float) -> void:
	var soldier := pawn as Soldier
	if soldier == null:
		return
	# 1) 主角小队跟随最高优先（与 idle / 其它生活状态同规则）
	if is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return
	# 2) 天亮 / 离夜：回到白天巡逻 / 生活路由
	if not TimeManager.is_night():
		_leave_night(soldier)
		return
	# 3) 城内缓慢回血（士兵的城内休整不受 v34 夜晚门控；夜潮攻城时也能靠站城回血）
	pawn._try_city_regen(delta)
	# 4) 夜间疗伤：<95% 且场上有酒馆 → 回馆，馆旁站到 >=95%（行程中不自动接战）
	if _update_healing(delta, soldier):
		return
	# 5) 视野内有敌 → 接战（守城准备期清残敌 / 闯入城内的敌人，优先级与白天一致）
	var sight: float = float(SIGHT[clampi(pawn.stance, 0, 2)])
	var enemy = pawn.find_nearest_hostile(maxf(sight, IDLE_SIGHT * 0.5))
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return
	# 6) 威胁支援：附近友军 / 建筑遇袭 → 赶赴现场（与 idle 日间同规则）
	if pawn.alert_active:
		var alert_dist: float = pawn.global_position.distance_to(pawn.alert_pos)
		var support_r: float = float(SUPPORT_R[clampi(pawn.stance, 0, 2)])
		if alert_dist > 3.0 and alert_dist <= support_r:
			soldier.night_vigil_active = false
			pawn.set_navigation_target(pawn.alert_pos)
			pawn._steer_separation = pawn.compute_separation("player_unit", SEP_RADIUS) * 2.5
			pawn.move_along_path(delta)
			pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
			return
		pawn.alert_active = false   # 已到达或过远：不再追这条警报
	# 7) 驻守姿态：守在锚点不动（回锚点后站桩；与 idle 同规则）
	if pawn.stance == Pawn.Stance.HOLD:
		soldier.night_vigil_active = false
		var anchor_dist: float = pawn.global_position.distance_to(pawn.hold_anchor)
		if anchor_dist > 2.5:
			pawn.set_navigation_target(pawn.hold_anchor)
			pawn._steer_separation = pawn.compute_separation("player_unit", SEP_RADIUS) * 2.5
			pawn.move_along_path(delta)
			pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
		else:
			pawn.velocity = Vector3.ZERO
			pawn.move_and_slide()
			pawn.play_anim(&"idle")
		return
	# 8) 回自己的站定点（威胁部署时 = 城门内侧阵位；否则 = 城内待命点）
	var post: Vector3 = _current_hold_point(soldier)
	var flat: Vector3 = post - pawn.global_position
	flat.y = 0.0
	if flat.length() > POST_ARRIVE:
		soldier.night_vigil_active = false
		pawn.set_navigation_target(post)
		pawn._steer_separation = pawn.compute_separation("player_unit", SEP_RADIUS) * 2.5
		pawn.move_along_path(delta)
		pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
		# 站定点被新建筑 / 水系挡住导致不可达：3s 后重选（不会逐帧换点）
		if pawn.navigation_status == Pawn.NavigationStatus.UNREACHABLE \
				or pawn.navigation_status == Pawn.NavigationStatus.BLOCKED:
			_post_retry_left += delta
			if _post_retry_left >= POST_RETRY_SEC:
				_post_retry_left = 0.0
				if soldier.defense_active:
					# 阵位被新建建筑 / 水系占用：强制重建一次布局，按当前可走格重新吸附
					soldier.force_defense_slot_rebuild()
					soldier.ensure_defense_slot()
				else:
					soldier.night_post_valid = false
					soldier.ensure_night_post()
		else:
			_post_retry_left = 0.0
		return
	# 9) 已到位：站定待命；威胁部署时朝城外保持阵列朝向，否则偶尔极慢换个朝向
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"idle")
	soldier.night_vigil_active = true
	_post_retry_left = 0.0
	if soldier.defense_active and soldier.ensure_defense_slot():
		pawn.look_at_target(soldier.defense_outward)
	else:
		_gaze_left -= delta
		if _gaze_left <= 0.0:
			_gaze_left = randf_range(10.0, 24.0)
			var a: float = randf() * TAU
			pawn.look_at_target(Vector3(cos(a), 0.0, sin(a)))
	# 10) 夜间闲聊：招募附近 1~2 名同样站定的健康小兵（2~3 人一组）
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = randf_range(CHAT_SCAN_MIN, CHAT_SCAN_MAX)
	if not soldier._night_chat_ready():
		return
	var candidates: Array = []
	for node in pawn.nearby_group_members("player_unit", GameDefs.SOLDIER_NIGHT_CHAT_RADIUS):
		if node is Soldier and node != pawn and (node as Soldier)._night_chat_ready():
			candidates.append(node)
	if candidates.is_empty():
		return
	# 近的优先，尽量凑三人一组（try_night_chat_with 内部最多再招 2 名）
	candidates.sort_custom(_nearest_candidate_first)
	soldier.try_night_chat_with(candidates)


## sort_custom 回调：按到发起者的距离从近到远。
func _nearest_candidate_first(a, b) -> bool:
	var self_pos: Vector3 = pawn.global_position
	var da: float = self_pos.distance_squared_to((a as Node3D).global_position)
	var db: float = self_pos.distance_squared_to((b as Node3D).global_position)
	return da < db


## 夜间疗伤（v43）：血量 < TAVERN_EXIT_RATIO(95%) 且场上有酒馆即锁定最近酒馆；
## 走到馆旁（光环圈内）站定回血，>=95% 后清行程，下一帧继续回待命点。
## 返回 true 表示本帧已由疗伤行程接管（含赶路 / 馆旁站桩）。
func _update_healing(delta: float, soldier: Soldier) -> bool:
	if soldier == null or soldier.health == null:
		return false
	var ratio: float = soldier.health.ratio()
	# 行程失效清理（酒馆被拆）与达到出院线
	if soldier.healing_trip != null and not is_instance_valid(soldier.healing_trip):
		soldier.healing_trip = null
	if soldier.healing_trip != null and ratio >= Soldier.TAVERN_EXIT_RATIO:
		soldier.healing_trip = null
	# 夜间轻伤也先去酒馆（白天仍只有 <20% 触发，见 SoldierIdleState）
	if soldier.healing_trip == null and ratio < Soldier.TAVERN_EXIT_RATIO:
		soldier.healing_trip = soldier.find_nearest_tavern()
	if soldier.healing_trip == null:
		return false   # 无酒馆：待命点靠城内回血慢慢恢复
	var tavern: Building = soldier.healing_trip
	var flat: Vector3 = tavern.global_position - pawn.global_position
	flat.y = 0.0
	var stop_dist: float = 4.0
	if tavern.def != null:
		stop_dist = maxf(1.5, tavern.def.heal_radius * HEAL_RADIUS_SCALE)
	if flat.length() <= stop_dist:
		# 在馆旁站定回血（酒馆光环 + 城内回血）；到 95% 后下一帧解除行程
		soldier.night_vigil_active = false
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		pawn.play_anim(&"idle")
		pawn.look_at_target(flat)
		return true
	# 前往酒馆：全程不自动接战（Soldier.autofight_enabled 在 healing_trip 非空时返回 false）
	soldier.night_vigil_active = false
	pawn.set_navigation_target(tavern.global_position)
	pawn._steer_separation = pawn.compute_separation("player_unit", SEP_RADIUS) * 2.0
	pawn.move_along_path(delta)
	pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
	return true


## 离夜：清夜间标记后回 idle（白天路由会重新决定巡逻 / 城内生活）。
## 夜里因轻伤发起的回馆行程在天亮后交还白天规则：>=20% 时不再强制疗伤。
func _leave_night(soldier: Soldier) -> void:
	soldier.night_vigil_active = false
	soldier.night_post_valid = false
	if soldier.healing_trip != null:
		if not is_instance_valid(soldier.healing_trip):
			soldier.healing_trip = null
		elif soldier.health != null and soldier.health.ratio() >= Soldier.TAVERN_HEAL_THRESHOLD:
			soldier.healing_trip = null   # 天亮后不再强制轻伤疗伤（<20% 由白天规则接管）
	state_machine.transition_to("idle")
