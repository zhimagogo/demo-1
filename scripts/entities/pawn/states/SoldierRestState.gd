class_name SoldierRestState
extends PawnState
## ============================================================================
## 士兵休息（城内生活）：走到城内休息点后原地休整、持续回血。
## 离开条件：满血且白天 → 回 idle（idle 路由去巡逻）；满血且夜间 → 回 night_vigil 待命点。
## ============================================================================

const ARRIVE_DIST: float = 1.6     # 离休息点小于此距离则停下
const LINGER: float = 2.5          # 至少休息这么久再考虑离开（防抖，避免与 idle 之间抖动）

var _rest_point: Vector3
var _lingered: float = 0.0
var _reached: bool = false


func enter(msg: Dictionary) -> void:
	_reached = false
	_lingered = 0.0
	# v22：疗伤行程指定「在酒馆旁」休整（msg.at）；默认仍回自家门口的休息点
	if msg.has("at"):
		_rest_point = msg["at"]
	else:
		_rest_point = pawn.get_home_rest_point() if pawn is Soldier else pawn.global_position
	pawn.play_anim(&"idle")
	call_deferred("_goto_rest_point")


func _goto_rest_point() -> void:
	if state_machine.current_state != self:
		return
	if not _reached:
		pawn.set_navigation_target(_rest_point)


func physics_update(delta: float) -> void:
	# 城内回血（行走中 / 停下都生效，只要在城内）
	pawn._try_city_regen(delta)
	_lingered += delta
	# 单位互不物理碰撞：用软件分离力避免多个休整士兵堆在同一休息点
	var sep: Vector3 = pawn.compute_separation("player_unit", 1.6) * 2.5

	if not _reached:
		pawn._steer_separation = sep   # 行走中由 move_along_path 消费叠加
		var d: float = pawn.global_position.distance_to(_rest_point)
		if d <= ARRIVE_DIST or pawn.move_along_path(delta):
			_reached = true
		return

	# 已到位休息中：仅靠分离力微调位置（互相推开一点），其余静止回血
	pawn.velocity = sep
	pawn.move_and_slide()
	var full: bool = pawn.health != null and pawn.health.ratio() >= 0.999
	if _lingered < LINGER or not full:
		return   # 继续休息回血
	# 满血 + 休息够：白天回 idle 出城，夜间回 night_vigil 待命点站定（v43）
	if _is_night():
		state_machine.transition_to("night_vigil")
	else:
		state_machine.transition_to("idle")


func _is_night() -> bool:
	var h: int = TimeManager.hour
	return h >= 20 or h < 6
