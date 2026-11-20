class_name Refugee
extends Pawn
## 尚未入驻的流民：只会前往分配的房屋，不能工作、战斗，也不会被野怪锁定。

const RefugeeArriveStateScript = preload("res://scripts/entities/pawn/states/RefugeeArriveState.gd")

var destination_house: Building = null


func _ready() -> void:
	if def == null:
		def = GameDefs.refugee_def()
	can_be_targeted_by_enemies = false
	super._ready()
	add_to_group("refugee")


func _setup_nodes() -> void:
	super._setup_nodes()
	state_machine.register_state("idle", RefugeeArriveStateScript.new())


func travel_to(house: Building) -> void:
	destination_house = house
	if state_machine != null:
		state_machine.transition_to("idle")
