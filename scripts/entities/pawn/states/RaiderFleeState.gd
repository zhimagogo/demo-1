class_name RaiderFleeState
extends PawnState
## 野怪逃跑：掉头狂奔远离威胁，躲开 20m 后原地喘息回血，回到 70% 再入战场。
## 让野怪有「怕死」的生命感，也让追杀有 hunt 的节奏（追 or 放）。

const FLEE_SPEED_MULT: float = 1.5
const FLEE_DISTANCE: float = 22.0
const SAFE_RADIUS: float = 17.0
const RESUME_FLEE_RADIUS: float = 15.0
const THREAT_SCAN_INTERVAL: float = 0.2
const HEAL_PER_SEC: float = 9.0
const HEAL_TARGET_RATIO: float = 0.7
const WAYPOINT_TIMEOUT: float = 8.0
const MAX_REST: float = 20.0           # 兜底：别趴太久

var _wp_timer: float = 0.0
var _rest_timer: float = 0.0
var _base_speed: float = 0.0
var _resting: bool = false
var _threat: Node3D
var _threat_check_left: float = 0.0


func enter(msg: Dictionary) -> void:
	_wp_timer = 0.0
	_rest_timer = 0.0
	_resting = false
	_threat = null
	_threat_check_left = 0.0
	_base_speed = pawn.move_speed
	pawn.move_speed = _base_speed * FLEE_SPEED_MULT
	pawn.play_anim(&"run")
	# 逃跑方向：远离伤害来源（msg.threat）或远离主城
	var dir: Vector3 = Vector3.ZERO
	var threat = msg.get("threat", null)
	if threat != null and is_instance_valid(threat) and threat is Node3D:
		dir = pawn.global_position - (threat as Node3D).global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = pawn.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		var a := randf() * TAU
		dir = Vector3(cos(a), 0.0, sin(a))
	pawn.set_navigation_target(pawn.global_position + dir.normalized() * FLEE_DISTANCE, true)


func exit() -> void:
	if _base_speed > 0.0:
		pawn.move_speed = _base_speed


func physics_update(delta: float) -> void:
	# Safety checks deliberately bypass Raider's 11m combat clamp and city
	# exclusion. Real attackers remain dangerous across those AI boundaries.
	var radius := RESUME_FLEE_RADIUS if _resting else SAFE_RADIUS
	_threat_check_left -= delta
	if is_instance_valid(_threat) and (not pawn._valid_hostile_candidate(_threat, radius * radius)):
		_threat = null
	if _threat_check_left <= 0.0:
		_threat = pawn._find_nearest_in_group("player_unit", radius, true) as Node3D
		_threat_check_left = THREAT_SCAN_INTERVAL
	if is_instance_valid(_threat):
		if _resting:
			_resting = false
			_rest_timer = 0.0
			_pick_escape_point()
		_wp_timer += delta
		var arrived: bool = pawn.move_along_path(delta)
		pawn.play_anim(&"run" if pawn.velocity.length_squared() > 0.01 else &"idle")
		var failed: bool = pawn.navigation_status in [Pawn.NavigationStatus.UNREACHABLE, Pawn.NavigationStatus.BLOCKED]
		if arrived or _wp_timer >= WAYPOINT_TIMEOUT or (failed and _wp_timer >= 1.0):
			_wp_timer = 0.0
			_pick_escape_point()
		return
	_resting = true
	# 脱险：喘息回血
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"idle")
	_rest_timer += delta
	if pawn.health != null:
		pawn.health.heal(HEAL_PER_SEC * delta)
		if pawn.health.ratio() >= HEAL_TARGET_RATIO or _rest_timer >= MAX_REST:
			state_machine.transition_to("idle")
	else:
		state_machine.transition_to("idle")


func _pick_escape_point() -> void:
	var dir := Vector3.ZERO
	if is_instance_valid(_threat):
		dir = pawn.global_position - _threat.global_position
		dir.y = 0.0
	if dir.length_squared() < 0.01:
		var angle := randf() * TAU
		dir = Vector3(cos(angle), 0, sin(angle))
	pawn.set_navigation_target(pawn.global_position + dir.normalized() * FLEE_DISTANCE, true)
