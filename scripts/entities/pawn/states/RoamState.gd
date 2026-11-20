class_name RoamState
extends PawnState
## Persistent local roaming, city escape and leash retreat. A retreat completes
## before acquiring another enemy; rejected waypoints use a bounded retry.
const WAYPOINT_TIMEOUT: float = 5.0
const RETRY_INTERVAL: float = 1.0
const MAX_CANDIDATES: int = 6
var _wp_timer: float = 0.0
var _retry_left: float = 0.0
var _escaping_city: bool = false
var _returning_home: bool = false
var _has_waypoint: bool = false

func enter(_msg: Dictionary) -> void:
	_wp_timer = 0.0
	_retry_left = 0.0
	_has_waypoint = false
	var city: CitySystem = pawn._get_city()
	_escaping_city = city != null and city.is_in_city(pawn.global_position)
	_returning_home = pawn is Raider and pawn.is_beyond_leash()
	call_deferred("_pick_roam_point")

func physics_update(delta: float) -> void:
	var city: CitySystem = pawn._get_city()
	if city != null and city.is_in_city(pawn.global_position) and not _escaping_city:
		_escaping_city = true
		_has_waypoint = false
	if _escaping_city and city != null and not city.segment_crosses_city(pawn.global_position, pawn.global_position, 1.0):
		_escaping_city = false
		_has_waypoint = false
	if pawn is Raider:
		if pawn.is_beyond_leash() and not _returning_home:
			_returning_home = true
			_has_waypoint = false
		elif _returning_home and pawn.global_position.distance_to(pawn.home_position) <= Raider.LEASH_RETURN_RANGE:
			_returning_home = false
			_has_waypoint = false
	# Night assault remains authorized across both local boundaries.
	if pawn is Raider and pawn.try_start_siege():
		return
	if not _escaping_city and not _returning_home:
		var enemy = pawn.find_nearest_hostile(Raider.AGGRO_RANGE)
		if enemy != null:
			state_machine.transition_to("fight", {"target": enemy})
			return
	_retry_left = maxf(0.0, _retry_left - delta)
	if not _has_waypoint:
		pawn._stop_navigation_motion()
		pawn.play_anim(&"idle")
		if _retry_left <= 0.0:
			_pick_roam_point()
		return
	_wp_timer += delta
	var arrived: bool = pawn.move_along_path(delta)
	pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.01 else &"idle")
	if arrived or _wp_timer >= WAYPOINT_TIMEOUT or pawn.navigation_status in [Pawn.NavigationStatus.BLOCKED, Pawn.NavigationStatus.UNREACHABLE]:
		_has_waypoint = false
		_retry_left = RETRY_INTERVAL if not arrived else 0.0

func _pick_roam_point() -> void:
	if state_machine.current_state != self:
		return
	var city: CitySystem = pawn._get_city()
	var nav: NavSystem = pawn._get_nav()
	var origin: Vector3 = pawn.global_position
	_has_waypoint = false
	for i in MAX_CANDIDATES:
		var candidate: Vector3
		if _escaping_city and city != null:
			candidate = city.outside_point(origin, 3.0 + float(i))
		elif _returning_home and pawn is Raider:
			candidate = pawn.home_position
			if i > 0:
				candidate += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		else:
			var angle := randf() * TAU
			candidate = origin + Vector3(cos(angle), 0, sin(angle)) * randf_range(4, 9)
		if nav != null:
			candidate = nav.snap_to_walkable(candidate)
		if city != null and city.segment_crosses_city(candidate, candidate, 0.7):
			continue
		if pawn is Raider and not _escaping_city and candidate.distance_to(pawn.home_position) > Raider.LEASH_RANGE - 1.0:
			continue
		if candidate.distance_squared_to(origin) < 0.25:
			continue
		var route := nav.get_world_path(origin, candidate) if nav != null else PackedVector3Array([candidate])
		if route.is_empty():
			continue
		var safe := true
		var previous := origin
		for point in route:
			if city != null and not _escaping_city and city.segment_crosses_city(previous, point, 0.5):
				safe = false
				break
			previous = point
		if not safe:
			continue
		pawn.set_navigation_target(candidate, true)
		_has_waypoint = true
		_wp_timer = 0.0
		_retry_left = 0.0
		return
	pawn._stop_navigation_motion()
	pawn.play_anim(&"idle")
	_retry_left = RETRY_INTERVAL
