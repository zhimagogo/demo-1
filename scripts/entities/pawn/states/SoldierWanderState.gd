class_name SoldierWanderState
extends PawnState
## 城内日常：在住家、酒馆、道路和公共空地间散步，到点后停留；途中可停下聊天。

const MIN_DURATION: float = 8.0
const MAX_DURATION: float = 14.0
const WAYPOINT_TIMEOUT: float = 8.0
const WANDER_SIGHT: float = 14.0

var _duration: float = 0.0
var _elapsed: float = 0.0
var _wp_timer: float = 0.0
var _pause_left: float = 0.0


func enter(_msg: Dictionary) -> void:
	_elapsed = 0.0
	_wp_timer = 0.0
	_pause_left = randf_range(0.5, 1.5)
	_duration = randf_range(MIN_DURATION, MAX_DURATION)
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")


func physics_update(delta: float) -> void:
	if is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return
	# v43：入夜立刻收步回待命（不再满城游荡）；天亮后由 idle 重新路由白天生活。
	if TimeManager.is_night():
		state_machine.transition_to("night_vigil")
		return
	pawn._try_city_regen(delta)
	_elapsed += delta
	var enemy = pawn.find_nearest_hostile(WANDER_SIGHT)
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return
	if _elapsed >= _duration:
		state_machine.transition_to("idle")
		return
	if _pause_left > 0.0:
		pawn.velocity = Vector3.ZERO
		pawn.play_anim(&"idle")
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_wander_point()
		return
	_wp_timer += delta
	pawn._steer_separation = pawn.compute_separation("player_unit", 1.6) * 3.0
	var arrived: bool = pawn.move_along_path(delta)
	pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
	if arrived or _wp_timer >= WAYPOINT_TIMEOUT or pawn.navigation_status == Pawn.NavigationStatus.UNREACHABLE:
		_pause_left = randf_range(1.5, 3.5)
		pawn.velocity = Vector3.ZERO
		pawn.play_anim(&"idle")


func _pick_wander_point() -> void:
	if state_machine.current_state != self:
		return
	_wp_timer = 0.0
	var city: CitySystem = pawn._get_city()
	var nav: NavSystem = pawn._get_nav_system()
	if city == null or nav == null:
		state_machine.transition_to("idle")
		return
	for _i in 10:
		var point := city.random_point_in_city(2.0)
		var roll := randf()
		var tavern: Building = (pawn as Soldier).find_nearest_tavern()
		if roll < 0.35 and is_instance_valid((pawn as Soldier).home):
			point = pawn.get_home_rest_point() + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		elif roll < 0.65 and is_instance_valid(tavern):
			var angle := randf() * TAU
			point = tavern.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(3.0, 5.0)
		elif roll < 0.9 and not nav.grid.road_cells.is_empty():
			point = nav.grid.grid_to_world(nav.grid.road_cells.keys().pick_random())
		point = nav.snap_to_walkable(point)
		if city.is_in_city(point) and nav.can_walk_segment(point, point):
			pawn.set_navigation_target(point, true)
			return
	_pause_left = 2.0
