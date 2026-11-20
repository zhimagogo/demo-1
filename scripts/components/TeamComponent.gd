class_name TeamComponent
extends Node
## 阵营组件。0=Player 1=Enemy 2=Neutral。

enum Team { PLAYER, ENEMY, NEUTRAL }

@export var team: int = Team.PLAYER


func is_enemy_of(other: Node) -> bool:
	var other_team: TeamComponent = _get_team(other)
	if other_team == null:
		return false
	if team == Team.NEUTRAL or other_team.team == Team.NEUTRAL:
		return false
	return team != other_team.team


static func are_enemies(a: int, b: int) -> bool:
	if a == Team.NEUTRAL or b == Team.NEUTRAL:
		return false
	return a != b


func _get_team(node: Node) -> TeamComponent:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null("TeamComponent")
