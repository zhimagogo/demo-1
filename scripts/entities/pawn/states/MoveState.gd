class_name MoveState
extends PawnState
## 朝 move_target 沿 NavMesh 前进，到达后回到待命。

var _arrived: bool = false


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	_arrived = false
	# 殖民者与其它可选单位执行移动命令时使用跑步，而非慢步行。
	pawn.play_anim(&"run")
	# 延迟一帧设 target，避开 NavigationAgent 在 map 初始未同步时空路径的坑
	call_deferred("_set_target_deferred")


func _set_target_deferred() -> void:
	if state_machine.current_state != self:
		return
	if not _arrived:
		pawn.set_navigation_target(pawn.move_target, true)


func physics_update(_delta: float) -> void:
	if _arrived:
		return
	# 单位层不互相碰撞，行军时补软件分离力，避免同一指令终点堆叠。
	var group := "player_unit" if pawn.team_comp.team == TeamComponent.Team.PLAYER else "enemy"
	pawn._steer_separation = pawn.compute_separation(group, 1.5) * 3.5
	if pawn.move_along_path(_delta):
		_arrived = true
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		state_machine.transition_to("idle")
		return
	# 移动途中遇敌自动接战（Hero 在 RTS 俯瞰下待命，见 Hero.autofight_enabled）
	if pawn.autofight_enabled():
		var enemy = pawn.find_nearest_hostile()
		if enemy != null:
			state_machine.transition_to("fight", {"target": enemy})


func _on_navmesh_updated() -> void:
	# NavMesh 变化时重新规划到原目标
	if not _arrived:
		pawn.set_navigation_target(pawn.move_target, true)
