class_name PawnStateMachine
extends Node
## Pawn 状态机容器。各状态作为子节点，节点名即状态名（idle/move/...）。
## 通过 transition_to(state_name, msg) 切换。

var pawn                        # Pawn（get_parent()）
var states: Dictionary = {}     # String -> PawnState
var current_state: PawnState = null


func _ready() -> void:
	pawn = get_parent()
	for child in get_children():
		if child is PawnState:
			states[child.name] = child
			child.state_machine = self
			child.pawn = pawn
	# 进入初始状态
	current_state = states.get("idle")
	if current_state != null:
		current_state.enter({})


func _physics_process(delta: float) -> void:
	if current_state != null and pawn != null:
		current_state.physics_update(delta)


func transition_to(state_name: String, msg: Dictionary = {}) -> void:
	if not states.has(state_name):
		return
	if current_state != null:
		current_state.exit()
	current_state = states[state_name]
	current_state.enter(msg)


## 手动登记一个状态（用于 super._setup_nodes 之后才新增 / 替换的状态）。
## _ready 的自动登记只覆盖当时已 add 的子节点；Hero/Soldier/Raider 在 super 之后才安装
## 专属状态，必须走这里。若替换的是「当前正在运行的状态」，会平滑切到新状态并重入 enter，
## 避免持有已被 queue_free 的旧节点。
func register_state(state_name: String, state_node) -> void:
	var old := get_node_or_null(state_name)
	var was_current: bool = current_state != null and current_state == old
	if old != null:
		if was_current:
			old.exit()
		remove_child(old)
		old.queue_free()
	state_node.name = state_name
	add_child(state_node)
	states[state_name] = state_node
	state_node.state_machine = self
	state_node.pawn = pawn
	if was_current:
		current_state = state_node
		state_node.enter({})
