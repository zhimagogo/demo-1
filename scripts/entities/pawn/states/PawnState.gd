class_name PawnState
extends Node
## Pawn 状态基类。字段故意不加类型注解，避免与子类/状态机的循环依赖。

var state_machine   # PawnStateMachine
var pawn            # Pawn（运行时为 CharacterBody3D 派生）


func enter(_msg: Dictionary) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func exit() -> void:
	pass
