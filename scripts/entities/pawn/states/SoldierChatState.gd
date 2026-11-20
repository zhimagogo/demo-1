extends PawnState
## 双方预约后停步、相向交谈；命令、警报、受伤、敌人和同伴离开都会结束聊天。

var _elapsed: float = 0.0
var _initiator: bool = false
var _lines: Array = []
var _replied: bool = false


func enter(msg: Dictionary) -> void:
	_elapsed = 0.0
	_initiator = bool(msg.get("initiator", false))
	_lines = msg.get("lines", [])
	_replied = false
	pawn.velocity = Vector3.ZERO
	pawn._steer_separation = Vector3.ZERO
	pawn.play_anim(&"idle")
	if _initiator and not _lines.is_empty():
		pawn.speech_bubble.show_bubble(String(_lines[0]), 2.5)


func physics_update(delta: float) -> void:
	if is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return
	# v43：入夜结束白天双人聊天，回夜间待命（群聊走独立的 night_chat 契约）。
	if TimeManager.is_night():
		state_machine.transition_to("night_vigil")
		return
	var other = pawn.chat_partner
	var city: CitySystem = pawn._get_city()
	if not is_instance_valid(other) or other.is_dead_flag or other.chat_partner != pawn \
			or city == null or not city.is_in_city(pawn.global_position) or not city.is_in_city(other.global_position) \
			or pawn.global_position.distance_to(other.global_position) > GameDefs.SOLDIER_CHAT_RADIUS + 0.8 \
			or pawn.alert_active or pawn.stance == Pawn.Stance.HOLD \
			or pawn.health.ratio() < Soldier.TAVERN_EXIT_RATIO:
		state_machine.transition_to("idle")
		return
	var enemy = pawn.find_nearest_hostile(14.0)
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.look_at_target(other.global_position - pawn.global_position)
	pawn._try_city_regen(delta)
	_elapsed += delta
	if not _initiator and not _replied and _elapsed >= 2.8:
		_replied = true
		if _lines.size() > 1 and SpeechBubble3D.active_count() < SpeechBubble3D.MAX_CONCURRENT:
			pawn.speech_bubble.show_bubble(String(_lines[1]), 2.8)
	if _elapsed >= GameDefs.SOLDIER_CHAT_SECONDS:
		state_machine.transition_to("idle")


func exit() -> void:
	var other = pawn.chat_partner
	pawn.chat_partner = null
	pawn.chat_cooldown = randf_range(GameDefs.SOLDIER_CHAT_COOLDOWN.x, GameDefs.SOLDIER_CHAT_COOLDOWN.y)
	pawn.velocity = Vector3.ZERO
	pawn.speech_bubble.hide_now()
	if is_instance_valid(other) and other.chat_partner == pawn:
		other.chat_partner = null
