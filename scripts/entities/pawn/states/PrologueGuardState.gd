class_name PrologueGuardState
extends PawnState
## 剧情驻守：守住固定岗哨，玩家靠近或攻击才接战；失去目标后归位，不套用夜潮攻城。
var hero: Hero
var anchor := Vector3.ZERO
var _alerted := false
var _repath := 0.0

func enter(_msg: Dictionary) -> void:
	anchor = pawn.global_position
	pawn.avoids_city = false
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")

func physics_update(delta: float) -> void:
	if not is_instance_valid(hero):
		return
	_repath -= delta
	var alive := not hero.is_dead_flag
	var distance: float = pawn.global_position.distance_to(hero.global_position)
	var attacked: bool = pawn.health != null and pawn.health.last_attacker == hero
	if not _alerted and alive and (distance <= 6.5 or attacked):
		_alerted = true
		_repath = 0
	if _alerted and (not alive or hero.global_position.distance_to(anchor) > 15.0):
		_alerted = false
		pawn.combat_target = null
		_repath = 0
	if _alerted:
		pawn.combat_target = hero
		var direction: Vector3 = hero.global_position - pawn.global_position
		direction.y = 0
		if direction.length_squared() > 0.01:
			pawn.look_at_target(direction.normalized())
		if pawn.attacker != null and pawn.attacker.in_range(hero):
			pawn._stop_navigation_motion()
			pawn.play_anim(&"idle")
			if pawn.attacker.try_attack(hero):
				pawn.play_anim(&"fight")
			return
		_move_toward(hero.global_position, delta)
	elif pawn.global_position.distance_to(anchor) > 0.4:
		_move_toward(anchor, delta)
	else:
		pawn._stop_navigation_motion()
		pawn.play_anim(&"idle")

func _move_toward(target: Vector3, delta: float) -> void:
	if _repath <= 0:
		pawn.set_navigation_target(target)
		_repath = 0.4
	pawn._steer_separation = pawn.compute_separation("enemy", 1.6) * 2.0
	pawn.move_along_path(delta)
	pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.01 else &"idle")

func exit() -> void:
	pawn.combat_target = null
