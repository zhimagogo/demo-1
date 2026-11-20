extends Node
## ============================================================================
## v43 夜间待命专项回归（需求②：夜晚未开战小兵待命氛围）
##   bash tools/godot_locked.sh --headless --path . tests/NightVigilTest.tscn \
##        --fixed-fps 60 --quit-after 20000 --log-file /private/tmp/night-vigil-1.log
##
## 覆盖：
##   ① 夜晚（20:00，v31 守城准备期时钟冻结）不出现 patrol / wander 满城跑；
##   ② 收敛后所有人停在待命点，3s 内位移很小（不乱换点）；
##   ③ 出现 2~3 人 night_chat 群聊（AI 自发），且 3 人一组可成立、聊完回待命点并进冷却；
##   ④ 受伤（<95%）小兵夜间先去酒馆，进入馆旁半径并实际回血；
##   ⑤ 天亮（06:00）后不再有 night_vigil / night_chat，恢复白天生活。
##
## 输出保持 ASCII（headless 日志中文乱码）；命令直接调 API，不依赖真实鼠标；
## 物理帧统一 await get_tree().physics_frame。任何路径都会 quit（含 150s 看门狗）。
## ============================================================================

const WATCHDOG_SEC: float = 150.0

var _failures: int = 0
var _main: Node
var _world: Node3D
var _spawner: Node
var _city: CitySystem
var _nav: NavSystem
var _build: BuildSystem
var _tavern: Building
var _soldiers: Array = []


func _ready() -> void:
	# 看门狗：脚本若因 Parse Error / 卡住不 quit，也必须释放 godot 锁，避免拖死整批。
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	call_deferred("_run")


func _on_watchdog() -> void:
	push_error("FAIL: NightVigilTest watchdog timeout after %.0fs" % WATCHDOG_SEC)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _state_of(pawn) -> String:
	if pawn == null or not is_instance_valid(pawn) or pawn.state_machine == null \
			or pawn.state_machine.current_state == null:
		return ""
	return String(pawn.state_machine.current_state.name)


func _all_states() -> Array:
	var names: Array = []
	for s in _soldiers:
		if is_instance_valid(s):
			names.append(_state_of(s))
	return names


func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


## 是否全员已在待命点站定（状态 = night_vigil 且 night_vigil_active）。
func _all_settled(list: Array) -> bool:
	for s in list:
		if not is_instance_valid(s):
			return false
		if _state_of(s) != "night_vigil" or not (s as Soldier).night_vigil_active:
			return false
	return true


## 是否全员已不在夜间群聊 / 夜间待命（天亮后检查用）。
func _no_night_states(list: Array) -> bool:
	for s in list:
		var st := _state_of(s)
		if st == "night_vigil" or st == "night_chat":
			return false
	return true


func _any_in_chat(list: Array) -> bool:
	for s in list:
		if _state_of(s) == "night_chat":
			return true
	return false


func _any_bubble(list: Array) -> bool:
	for s in list:
		if is_instance_valid(s) and (s as Soldier).speech_bubble.is_showing():
			return true
	return false


func _any_day_life(list: Array) -> bool:
	for s in list:
		var st := _state_of(s)
		if st == "wander" or st == "patrol" or st == "rest":
			return true
	return false


func _finish() -> void:
	print("NIGHT VIGIL: %d failure(s)" % _failures)
	if is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	_world = _main.get_node("WorldRoot") as Node3D
	_spawner = get_tree().get_first_node_in_group("pawn_spawner")
	_city = get_tree().get_first_node_in_group("city_system") as CitySystem
	_nav = get_tree().get_first_node_in_group("nav_system") as NavSystem
	_build = _world.get_node("BuildSystem") as BuildSystem
	if _spawner == null or _city == null or _nav == null or _build == null:
		push_error("FAIL: required world systems missing")
		get_tree().quit(1)
		return
	# 测试期停刷野怪 / 流民并清场：夜晚行为必须确定性（不被打断）。
	var wildlife := _world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
		wildlife.set("max_monsters", 0)   # v44：关闭自动威胁方向，本测试只验常规夜间待命
	var settlement := _world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	ResourceManager.add(GameDefs.GOLD, 1000)
	TimeManager.set_speed(1.0)
	TimeManager.unfreeze_clock()
	TimeManager.begin(12)   # 白天布景（建造酒馆用；随后跳到夜间）
	await _wait_physics_frames(3)

	# ================= 布景：一座城内酒馆 =================
	var tavern_def: BuildingDef = null
	for d in GameDefs.building_defs():
		if d.id == &"tavern":
			tavern_def = d
	_check(tavern_def != null, "tavern def available")
	if tavern_def == null:
		await _finish()
		return
	var tavern_pos := Vector3(_city.city_half * 0.42, 0.0, -_city.city_half * 0.28)
	tavern_pos = _nav.snap_to_walkable(tavern_pos)
	tavern_pos.y = 0.0
	_build.enter_build_mode(tavern_def)
	_build.try_place_at(tavern_pos)
	_build.exit_build_mode()
	await _wait_physics_frames(3)
	var taverns := get_tree().get_nodes_in_group("tavern")
	_check(taverns.size() == 1, "tavern placed inside city (count=%d)" % taverns.size())
	if taverns.is_empty():
		await _finish()
		return
	_tavern = taverns[0] as Building

	# ================= 入夜：20:00 + v31 守城准备期（时钟冻结但仍是夜晚） =================
	TimeManager.begin(20)
	TimeManager.freeze_clock()
	await _wait_physics_frames(12)   # 等 DayNightCycle 跨夜广播 night_changed(true)
	_check(TimeManager.is_night() and TimeManager.clock_frozen,
		"night prep: clock frozen but still night (hour=%d)" % TimeManager.hour)
	# v44：显式清掉威胁方向，本测试固定验证「无威胁信号时的常规 night_vigil 待命」。
	EventBus.night_threat_direction_changed.emit(false, -1, Vector3.ZERO)
	await _wait_physics_frames(2)

	# 城内 5 名小兵（聚在城心附近，保证夜间可以凑成闲聊小组）
	var spawn_points := [
		Vector3(-3.0, 0.0, 8.0), Vector3(0.0, 0.0, 8.5), Vector3(3.0, 0.0, 8.0),
		Vector3(-1.0, 0.0, 11.0), Vector3(4.0, 0.0, 11.0),
	]
	for p in spawn_points:
		var point: Vector3 = _nav.snap_to_walkable(p)
		var soldier := _spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), point) as Soldier
		if soldier != null:
			soldier.speech_bubble.debug_set_timer(999.0)   # 抑制自动人设气泡，专注待命行为
			_soldiers.append(soldier)
	await _wait_physics_frames(2)
	_check(_soldiers.size() == 5, "spawned 5 soldiers at night (count=%d)" % _soldiers.size())
	# 稳定性检查前先压住夜间群聊，避免测位移时有人走去聊天。
	for s in _soldiers:
		(s as Soldier).night_chat_cooldown = 999.0

	# ================= ① 夜晚不再 patrol / wander 满城跑 =================
	var bad_states: Array = []
	for _i in 180:   # 3s
		await get_tree().physics_frame
		for st in _all_states():
			if st == "patrol" or st == "wander":
				if not bad_states.has(st):
					bad_states.append(st)
	_check(bad_states.is_empty(), "no patrol/wander at night (saw=%s)" % str(bad_states))

	# ================= ② 收敛到待命点后位置稳定 =================
	var settled := false
	for _i in 720:   # up to 12s
		if _all_settled(_soldiers):
			settled = true
			break
		await get_tree().physics_frame
	_check(settled, "all soldiers settle into night vigil posts")
	await _wait_physics_frames(12)   # 让残余滑行彻底停下
	var before: Array = []
	for s in _soldiers:
		before.append((s as Soldier).global_position)
	await _wait_physics_frames(180)   # 3s（chat 冷却已压住）
	var max_drift: float = 0.0
	for i in _soldiers.size():
		var s := _soldiers[i] as Soldier
		max_drift = maxf(max_drift, s.global_position.distance_to(before[i]))
	_check(max_drift < 0.25, "night posts stay stable for 3s (max drift=%.3fm)" % max_drift)

	# ================= ③ AI 自发 2~3 人夜间群聊 =================
	# 把前 3 名小兵放到相邻待命点（确定性），其余两人冷却压住不加入。
	var trio: Array = [_soldiers[0], _soldiers[1], _soldiers[2]]
	var trio_spawn := [
		Vector3(-2.0, 0.0, 9.0), Vector3(2.0, 0.0, 9.0), Vector3(0.0, 0.0, 12.0),
	]
	var trio_posts := [
		Vector3(-1.2, 0.0, 9.0), Vector3(1.2, 0.0, 9.0), Vector3(0.0, 0.0, 10.6),
	]
	for i in 3:
		var s := trio[i] as Soldier
		s.global_position = _nav.snap_to_walkable(trio_spawn[i])
		s.night_post = _nav.snap_to_walkable(trio_posts[i])
		s.night_post.y = 0.0
		s.night_post_valid = true
		s.night_chat_cooldown = 999.0
		s.state_machine.transition_to("night_vigil")
	var trio_ready := false
	for _i in 600:   # up to 10s
		if _all_settled(trio):
			trio_ready = true
			break
		await get_tree().physics_frame
	_check(trio_ready, "trio settles at adjacent night posts")
	# 同一物理帧内解除冷却并让三人的扫描计时器归零：树序第一名会一次招满三人。
	for s in trio:
		(s as Soldier).night_chat_cooldown = 0.0
		var st = (s as Soldier).state_machine.current_state
		if st != null:
			st.set("_scan_left", 0.0)
	await _wait_physics_frames(2)
	var ai_group_size: int = 0
	var ai_in_chat: int = 0
	for s in trio:
		var soldier := s as Soldier
		if _state_of(soldier) == "night_chat":
			ai_in_chat += 1
			ai_group_size = maxi(ai_group_size, soldier.night_chat_group.size())
	_check(ai_in_chat >= 2 and ai_group_size >= 2 and ai_group_size <= 3,
		"AI forms a 2-3 person night chat (members=%d, group=%d)" % [ai_in_chat, ai_group_size])
	# 群聊期间自动人设气泡被压住，对话气泡能正常出现。
	var bubble_seen := false
	for _i in 360:   # up to 6s
		if _any_bubble(trio):
			bubble_seen = true
			break
		await get_tree().physics_frame
	_check(bubble_seen, "night chat members show speech bubbles in turn")
	# 聊完（10.5~13.5s）回各自待命点并进入 25~45s 冷却。
	var chat_ended := false
	for _i in 1080:   # up to 18s
		if not _any_in_chat(_soldiers):
			chat_ended = true
			break
		await get_tree().physics_frame
	var cooled := true
	for s in trio:
		if (s as Soldier).night_chat_cooldown <= 0.0:
			cooled = false
	_check(chat_ended and cooled, "night chat ends and members enter cooldown")

	# ================= ③b 三人一组可成立（显式调用同一 API，排除 AI 竞争） =================
	var back_at_posts := false
	for _i in 960:   # up to 16s
		if _all_settled(trio):
			back_at_posts = true
			break
		await get_tree().physics_frame
	_check(back_at_posts, "night chat members return to their own posts")
	# 同步解除冷却并立即发起：中间没有物理帧，AI 来不及抢跑。
	for s in trio:
		(s as Soldier).night_chat_cooldown = 0.0
		(s as Soldier).speech_bubble.hide_now()
	var trio_chat_ok: bool = (trio[0] as Soldier).try_night_chat_with([trio[1], trio[2]])
	_check(trio_chat_ok, "three-person night chat can be started")
	var three_in_chat := true
	var three_group_size := 0
	for s in trio:
		if _state_of(s) != "night_chat":
			three_in_chat = false
		three_group_size = maxi(three_group_size, (s as Soldier).night_chat_group.size())
	_check(three_in_chat and three_group_size == 3,
		"all three soldiers join the same night chat (group=%d)" % three_group_size)
	var three_ended := false
	for _i in 1080:   # up to 18s
		if not _any_in_chat(_soldiers):
			three_ended = true
			break
		await get_tree().physics_frame
	_check(three_ended, "three-person night chat finishes cleanly")

	# ================= ④ 受伤小兵夜间先去酒馆回血 =================
	var hurt_point: Vector3 = _nav.snap_to_walkable(Vector3(_city.city_half * 0.62, 0.0, 2.0))
	var hurt := _spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), hurt_point) as Soldier
	await _wait_physics_frames(2)
	_check(hurt != null, "injured soldier spawned")
	if hurt != null:
		hurt.speech_bubble.debug_set_timer(999.0)
		hurt.health.current_hp = hurt.health.max_hp * 0.5
		var start_hp: float = hurt.health.current_hp
		var locked := false
		for _i in 360:   # up to 6s
			if (hurt as Soldier).healing_trip == _tavern:
				locked = true
				break
			await get_tree().physics_frame
		_check(locked, "injured soldier at night locks the nearest tavern trip")
		var reached_radius := false
		for _i in 1200:   # up to 20s
			if is_instance_valid(_tavern) \
					and hurt.global_position.distance_to(_tavern.global_position) <= _tavern.def.heal_radius:
				reached_radius = true
				break
			await get_tree().physics_frame
		var healed_amount: float = 0.0
		var heal_frames: int = 0
		for _i in 120:   # up to 2s after entering the aura
			await get_tree().physics_frame
			heal_frames += 1
			healed_amount = hurt.health.current_hp - start_hp
			if healed_amount >= 10.0:
				break
		_check(reached_radius and healed_amount >= 10.0,
			"injured soldier reaches tavern radius and heals (in %.1fs, +%.1f hp)" % [
				float(heal_frames) / 60.0, healed_amount])
		_check(not hurt.autofight_enabled(), "healing trip keeps auto-engage disabled")

	# ================= ⑤ 天亮恢复白天生活 =================
	TimeManager.unfreeze_clock()
	TimeManager.begin(6)
	await _wait_physics_frames(12)
	_check(not TimeManager.is_night(), "dawn: clock is day again (hour=%d)" % TimeManager.hour)
	var night_states_gone := false
	for _i in 480:   # up to 8s
		var all_pawns: Array = _soldiers.duplicate()
		if hurt != null and is_instance_valid(hurt):
			all_pawns.append(hurt)
		if _no_night_states(all_pawns):
			night_states_gone = true
			break
		await get_tree().physics_frame
	_check(night_states_gone, "no night_vigil / night_chat after dawn")
	var day_life := false
	for _i in 360:   # up to 6s
		if _any_day_life(_soldiers):
			day_life = true
			break
		await get_tree().physics_frame
	_check(day_life, "day life resumes after dawn (wander/patrol/rest)")

	await _finish()
