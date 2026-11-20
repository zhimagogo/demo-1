class_name RefugeeArriveState
extends PawnState
## 流民抵达状态。使用导航走到房屋门口；抵达后由 SettlementSystem 转成士兵。

var _sent: bool = false


func enter(_msg: Dictionary) -> void:
	_sent = false
	pawn.play_anim(&"run")
	call_deferred("_set_destination")


func _set_destination() -> void:
	var house: Building = pawn.get("destination_house") as Building
	if house != null and is_instance_valid(house):
		pawn.set_navigation_target(house.global_position + house.global_transform.basis.z.normalized() * 1.45)


func physics_update(delta: float) -> void:
	var house: Building = pawn.get("destination_house") as Building
	if house == null or not is_instance_valid(house):
		return
	pawn._steer_separation = pawn.compute_separation("player_unit", 1.4) * 2.0
	if pawn.move_along_path(delta) and not _sent:
		_sent = true
		EventBus.refugee_arrived.emit(pawn, house)


func _on_navmesh_updated() -> void:
	_set_destination()
