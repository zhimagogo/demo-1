class_name SoldierNightChatState
extends PawnState
## ============================================================================
## v43 夜间小群闲聊（night_chat）：2~3 名已经在城内待命点站定的小兵，
## 由其中一人发起后一起挪到小群中心附近（各自占一个环上小槽位）相向站立，
## 每 ~3s 轮流冒一句夜间台词（清剿战果 / 麦酒 / 守夜 / 明日打算 / 第 N 夜），
## 约 10.5~13.5s 后结束，各自回自己的待命点并进入 25~45s 夜间聊天冷却。
##
## v44 威胁部署（defense_active）下：**不离位**——原地相向冒泡，聊完仍站在自己
## 的城门内侧阵列槽位上（不走向小群中心），保证防御阵型不被打散。
##
## 与白天双人聊天的关系：SoldierChatState / chat_partner / try_chat_with 契约原样保留
## （RoadTownLifeTest 继续 PASS）；本状态只由 Soldier.try_night_chat_with 在夜间触发，
## 使用独立的 night_chat_group 共享组。命令 / 集结 / 驻守 / 警报 / 受伤 / 敌人
## 都会立即结束并回到 night_vigil（由其重新决定疗伤 / 接战 / 待命）。
## ============================================================================

const APPROACH_SEC: float = 2.5     # 走向小群中心的最长时间（超时原地站定）
const SLOT_RADIUS: float = 0.85     # 环绕小群中心的槽位半径（约 1.7m 面对面）
const SETTLE_DIST: float = 0.9      # 距自己的槽位小于此距离即站定
const BUBBLE_SEC: float = 2.6       # 每条台词气泡停留时长（MAX_CONCURRENT=3，留节流余量）

var _members: Array = []            # 本组初始成员快照（含自己）
var _host: bool = false             # 发起者（当前仅作调试 / 扩展用）
var _lines: Array = []              # 本组台词池
var _seconds: float = 12.0          # 本次群聊总时长
var _elapsed: float = 0.0
var _approach_left: float = 0.0
var _settled: bool = false
var _defense_hold: bool = false     # v44：进入时已处于部署状态（阵位原地聊，不离位）
var _center: Vector3 = Vector3.ZERO
var _slot: Vector3 = Vector3.ZERO
var _line_index: int = 0
var _next_line_at: float = 0.4


func enter(msg: Dictionary) -> void:
	_members = msg.get("members", [])
	_host = bool(msg.get("host", false))
	_lines = msg.get("lines", [])
	_seconds = float(msg.get("seconds", 12.0))
	_elapsed = 0.0
	_line_index = 0
	_next_line_at = 0.4
	_settled = false
	_approach_left = APPROACH_SEC
	pawn.velocity = Vector3.ZERO
	pawn._steer_separation = Vector3.ZERO
	pawn.play_anim(&"idle")
	var soldier := pawn as Soldier
	if soldier != null:
		soldier.night_vigil_active = false
		# 群聊期间关闭自动人设气泡，避免随机台词覆盖对话（exit 恢复）
		soldier.speech_bubble.debug_set_timer(999.0)
	# 小群中心 = 成员当前位置平均（进入时同步计算，成员之间不会移动）
	_center = Vector3.ZERO
	var count := 0
	for node in _members:
		if is_instance_valid(node) and node is Node3D:
			_center += (node as Node3D).global_position
			count += 1
	if count > 0:
		_center /= float(count)
	_center.y = 0.0
	# v44：威胁部署状态下不离位——原地相向冒泡，槽位就是当前站定的阵位。
	_defense_hold = soldier != null and soldier.defense_active
	if _defense_hold:
		_settled = true
		_approach_left = 0.0
		_slot = pawn.global_position
		_slot.y = 0.0
		return
	var my_index: int = _members.find(pawn)
	if my_index < 0:
		my_index = 0
	var total: int = maxi(_members.size(), 1)
	var angle: float = TAU * float(my_index) / float(total)
	_slot = _center + Vector3(cos(angle), 0.0, sin(angle)) * SLOT_RADIUS
	_slot.y = 0.0
	if pawn.global_position.distance_to(_slot) > SETTLE_DIST:
		pawn.set_navigation_target(_slot)


func physics_update(delta: float) -> void:
	var soldier := pawn as Soldier
	if soldier == null:
		return
	_elapsed += delta
	# 1) 玩家集结 / 集火通道最高优先（集火令由 FightState 显式处理）
	if is_instance_valid(pawn.follow_leader):
		state_machine.transition_to("follow", {"leader": pawn.follow_leader})
		return
	# 1b) v44：聊天途中威胁方向到达或解除 → 交回 night_vigil 重新列阵 / 回常规待命点。
	if soldier.defense_active != _defense_hold:
		state_machine.transition_to("night_vigil")
		return
	# 2) 天亮 / 离夜 → 回 night_vigil（其会立刻检测离夜并转回白天路由）
	if not TimeManager.is_night():
		state_machine.transition_to("night_vigil")
		return
	# 3) 驻守 / 警报：交回 night_vigil（它在待命逻辑里处理锚点与支援）
	if pawn.stance == Pawn.Stance.HOLD or pawn.alert_active:
		state_machine.transition_to("night_vigil")
		return
	# 4) 受伤中断：<95% 交回 night_vigil（夜间疗伤：有酒馆先回馆）
	if pawn.health == null or pawn.health.ratio() < Soldier.TAVERN_EXIT_RATIO:
		state_machine.transition_to("night_vigil")
		return
	var city: CitySystem = pawn._get_city()
	if city == null or not city.is_in_city(pawn.global_position):
		state_machine.transition_to("night_vigil")
		return
	# 5) 敌人出现 → 明确接战
	var enemy = pawn.find_nearest_hostile(14.0)
	if enemy != null:
		state_machine.transition_to("fight", {"target": enemy})
		return
	# 6) 组员离开 / 死亡 / 被打断 → 组会解散（各自回待命点并进冷却）
	if not _group_alive():
		state_machine.transition_to("night_vigil")
		return
	# 7) 走向小群中心（最多 2.5s，被挡就原地站定相向）
	if not _settled:
		var dist: float = pawn.global_position.distance_to(_slot)
		if dist > SETTLE_DIST and _approach_left > 0.0:
			pawn.set_navigation_target(_slot)
			pawn._steer_separation = pawn.compute_separation("player_unit", 1.2) * 1.5
			pawn.move_along_path(delta)
			pawn.play_anim(&"move" if pawn.velocity.length_squared() > 0.04 else &"idle")
			_approach_left -= delta
			return
		_settled = true
	# 8) 站定相向（面向小群中心 / 对面的人）
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"idle")
	var to_center: Vector3 = _center - pawn.global_position
	to_center.y = 0.0
	if to_center.length_squared() > 0.01:
		pawn.look_at_target(to_center)
	pawn._try_city_regen(delta)
	# 9) 轮流冒泡：每 ~3s 换一个人说一句（谁到点谁开口）
	if _elapsed >= _next_line_at:
		_next_line_at += GameDefs.SOLDIER_NIGHT_CHAT_LINE_INTERVAL
		if not _lines.is_empty():
			var speaker_index: int = _line_index % maxi(_members.size(), 1)
			if speaker_index == _members.find(pawn) \
					and not pawn.speech_bubble.is_showing() \
					and SpeechBubble3D.active_count() < SpeechBubble3D.MAX_CONCURRENT:
				var line_index: int = _line_index % _lines.size()
				pawn.speech_bubble.show_bubble(String(_lines[line_index]), BUBBLE_SEC)
			_line_index += 1
	# 10) 聊够时长各自收尾（回到待命点）
	if _elapsed >= _seconds:
		state_machine.transition_to("night_vigil")


## 组是否仍然完整：初始成员都活着、都还在 night_chat、都在彼此可聊距离内。
func _group_alive() -> bool:
	if _members.size() < 2:
		return false
	for node in _members:
		if node == pawn:
			continue
		if not is_instance_valid(node) or not (node is Soldier):
			return false
		var other := node as Soldier
		if other.is_dead_flag or not other.night_chat_group.has(pawn):
			return false
		if other.state_machine == null or other.state_machine.current_state == null:
			return false
		if String(other.state_machine.current_state.name) != "night_chat":
			return false
		if pawn.global_position.distance_to(other.global_position) > GameDefs.SOLDIER_NIGHT_CHAT_RADIUS + 2.5:
			return false
	return true


func exit() -> void:
	var soldier := pawn as Soldier
	if soldier != null:
		soldier.leave_night_chat()
		soldier.night_chat_cooldown = randf_range(GameDefs.SOLDIER_NIGHT_CHAT_COOLDOWN.x, GameDefs.SOLDIER_NIGHT_CHAT_COOLDOWN.y)
		soldier.night_vigil_active = false
		pawn.velocity = Vector3.ZERO
		pawn.speech_bubble.hide_now()
		# 恢复自动人设气泡（群聊期间被临时压住）
		pawn.speech_bubble.debug_set_timer(randf_range(4.0, 9.0))
