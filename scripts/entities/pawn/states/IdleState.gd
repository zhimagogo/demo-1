class_name IdleState
extends PawnState
## 待命状态。开启自动战斗的单位会扫描附近敌人并自动迎击。


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")


func physics_update(_delta: float) -> void:
	# 小队成员：从 idle（如战斗结束）回到跟随态；follow 内部会自动接战近敌
	if pawn.follow_leader != null and is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return
	if pawn.autofight_enabled():
		var enemy = pawn.find_nearest_hostile()
		if enemy != null:
			state_machine.transition_to("fight", {"target": enemy})
