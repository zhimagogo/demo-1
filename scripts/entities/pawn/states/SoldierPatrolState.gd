class_name SoldierPatrolState
extends PawnState
## ============================================================================
## 士兵巡逻（白天出城猎杀）：每个士兵有固定「巡逻锚角」+ 半径偏好（由实例 id 散布），
## 多个士兵因此分布在主城外环的不同扇区，而非挤在同一圈——既避免重叠也让队形不那么单一。
## 触发离开：低血（回城）、入夜（收兵）、视野内遇敌（接战）。城外不回血。
## ============================================================================

const PATROL_SIGHT: float = 22.0      # 巡逻时索敌视野
const HEAL_THRESHOLD: float = 0.4     # 与 SoldierIdleState 一致
const WAYPOINT_TIMEOUT: float = 6.0   # 到不了下个巡逻点就换一个（防卡死）
const SEP_RADIUS: float = 1.8         # 与友军分离半径（单位互不物理碰撞，靠软件分离）

var _wp_timer: float = 0.0
var _patrol_angle: float = 0.0        # 该士兵固定的巡逻锚角（扇区中心）
var _patrol_radius: float = 0.0       # 该士兵偏好的巡逻半径（内圈/外圈）


func enter(_msg: Dictionary) -> void:
	_wp_timer = 0.0
	# 黄金角散布：实例 id → 0..1 → 角度，多人均匀分布在 [0, TAU) 上不同扇区
	_patrol_angle = fmod(absf(float(pawn.get_instance_id())) * 0.6180339887, 1.0) * TAU
	# 半径偏好：再加一个 0..1 的散布，决定该兵偏内圈还是外圈巡逻
	var rb: float = fmod(absf(float(pawn.get_instance_id())) * 0.4142135624, 1.0)
	_patrol_radius = rb
	pawn.play_anim(&"move")
	call_deferred("_pick_patrol_point")


func physics_update(delta: float) -> void:
	# 低血 → 回 idle（idle 会路由回城治疗）
	if pawn.health != null and pawn.health.ratio() < HEAL_THRESHOLD:
		state_machine.transition_to("idle")
		return
	# 入夜 → 收兵
	if _is_night() or (pawn as Soldier).wants_town_life():
		state_machine.transition_to("idle")
		return
	# 视野内遇敌 → 接战
	var enemy = pawn.find_nearest_hostile(PATROL_SIGHT)
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return
	# 推进；到点或超时换下一个巡逻点。移动前写入分离力，避免巡逻士兵堆叠。
	_wp_timer += delta
	pawn._steer_separation = pawn.compute_separation("player_unit", SEP_RADIUS) * 3.5
	var arrived: bool = pawn.move_along_path(delta)
	if arrived or _wp_timer >= WAYPOINT_TIMEOUT:
		_pick_patrol_point()
		_wp_timer = 0.0


## 选「该士兵锚角附近、主城外」的下一个巡逻点：小角度抖动 + 内/外圈半径偏好，
## 连续巡逻点彼此靠近 → 寻路不横穿主城；不同士兵锚角不同 → 队形分散。
func _pick_patrol_point() -> void:
	if state_machine.current_state != self:
		return
	var city: CitySystem = pawn._get_city()
	if city != null:
		for _i in 10:
			var a: float = _patrol_angle + randf_range(-0.7, 0.7)
			var r: float = city.city_half + lerp(4.0, 12.0, _patrol_radius) + randf_range(-1.5, 1.5)
			var p: Vector3 = Vector3(cos(a), 0.0, sin(a)) * r
			if not city.is_in_city(p):
				pawn.set_navigation_target(p)
				return
		# 兜底：城外任意点
		pawn.set_navigation_target(city.random_point_outside(city.city_half + 4.0, city.city_half + 12.0))
	else:
		var a := randf() * TAU
		pawn.set_navigation_target(pawn.global_position + Vector3(cos(a), 0.0, sin(a)) * 8.0)


func _is_night() -> bool:
	var h: int = TimeManager.hour
	return h >= 20 or h < 6
