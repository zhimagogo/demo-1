class_name VillagerFleeState
extends PawnState
## 村民逃跑：丢下一半货物，撒腿跑回主城方向；安全后喘口气继续干活。
## 村民不战斗——活着回来，经济才转得动。

const FLEE_SPEED_MULT: float = 1.45    # 逃命比干活快 45%（但仍可能被截杀）
const SAFE_RADIUS: float = 16.0        # 敌人离开该距离才算脱险
const SETTLE_TIME: float = 2.5         # 到达安全点后再观望这么久
const WAYPOINT_TIMEOUT: float = 8.0


var _threat = null
var _settle_timer: float = 0.0
var _wp_timer: float = 0.0
var _base_speed: float = 0.0


func enter(msg: Dictionary) -> void:
	_threat = msg.get("threat", null)
	_settle_timer = 0.0
	_wp_timer = 0.0
	var v := pawn as Colonist
	if v != null:
		v.drop_half_carry()
	# 逃命加速：保存原速，exit 恢复
	_base_speed = pawn.move_speed
	pawn.move_speed = _base_speed * FLEE_SPEED_MULT
	pawn.play_anim(&"run")
	call_deferred("_pick_flee_point")


func exit() -> void:
	if _base_speed > 0.0:
		pawn.move_speed = _base_speed


func physics_update(delta: float) -> void:
	_wp_timer += delta
	# 还能看见敌人 → 继续跑 / 重选逃离点
	var enemy = pawn.find_nearest_hostile(SAFE_RADIUS)
	if enemy != null:
		_threat = enemy
		_settle_timer = 0.0
		var arrived = pawn.move_along_path(delta)
		if arrived or _wp_timer >= WAYPOINT_TIMEOUT:
			_pick_flee_point()
			_wp_timer = 0.0
		return
	# 脱险：喘口气（原地警戒）
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"idle")
	pawn._try_city_regen(delta)
	_settle_timer += delta
	if _settle_timer >= SETTLE_TIME:
		state_machine.transition_to("idle")


func _pick_flee_point() -> void:
	# 逃跑方向：远离威胁 + 朝主城偏置（往家里跑，路上有士兵和城墙护着）
	var from_threat := Vector3.ZERO
	if _threat != null and is_instance_valid(_threat) and _threat is Node3D:
		from_threat = pawn.global_position - (_threat as Node3D).global_position
		from_threat.y = 0.0
	if from_threat.length_squared() < 0.01:
		from_threat = -pawn.global_position
		from_threat.y = 0.0
	if from_threat.length_squared() < 0.01:
		from_threat = Vector3(1.0, 0.0, 0.0)
	from_threat = from_threat.normalized()
	var to_home = -pawn.global_position
	to_home.y = 0.0
	to_home = to_home.normalized() if to_home.length_squared() > 0.01 else from_threat
	var dir: Vector3 = (from_threat * 0.6 + to_home * 0.4).normalized()
	pawn.set_navigation_target(pawn.global_position + dir * 22.0, true)
