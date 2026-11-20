class_name MonsterIdleState
extends PawnState
## 野怪待机（决策路由）：夜袭判定 → 城外有目标则接战，否则去徘徊。
## 白天永不进主城——索敌已过滤城内目标（见 Pawn.avoids_city / _find_nearest_in_group）；
## 夜晚可通过 Raider.try_start_siege 发起攻城（临时解除避城，FightState 维护）。


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")


func physics_update(_delta: float) -> void:
	# 夜袭攻城判定（内部自带冷却与概率；非夜/冷却中为空操作）
	if pawn is Raider and (pawn as Raider).try_start_siege():
		return
	var enemy = pawn.find_nearest_hostile(Raider.AGGRO_RANGE)
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
	else:
		state_machine.transition_to("roam")
