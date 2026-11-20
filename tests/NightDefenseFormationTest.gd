extends Node
## ============================================================================
## v44A 夜间威胁方向部署专项回归（按威胁方向部署到城门内侧，近战前排/远程后排）
##   bash tools/godot_locked.sh --headless --path . tests/NightDefenseFormationTest.tscn \
##        --fixed-fps 60 --quit-after 20000 --log-file /private/tmp/v44-defense.log
##
## 覆盖：
##   ① WildlifeSpawner 在守城准备期广播威胁方向（gate index + 城门内侧点，点在城内）；
##   ② 4 近战 + 3 远程全部到东门内侧 12m 内，槽位在城内可走格；
##   ③ 远程平均纵深 > 近战平均纵深 + 1.5m（近战前排 / 远程后排）；
##   ④ 全员朝城外站定（forward dot outward > 0.6）；
##   ⑤ 部署状态下夜间群聊不离位（原地相向冒泡，位置/阵位不变）；
##   ⑥ 天亮威胁清除 → defense_active/slot 清空，恢复白天生活。
##
## 输出保持 ASCII（headless 日志中文乱码）；命令直接调 API，不依赖真实鼠标；
## 物理帧统一 await get_tree().physics_frame。任何路径都会 quit（含 180s 看门狗）。
## ============================================================================

const WATCHDOG_SEC: float = 180.0
const EAST_GATE: int = 1

var _failures: int = 0
var _main: Node
var _world: Node3D
var _spawner: Node
var _city: CitySystem
var _nav: NavSystem
var _east_inside: Vector3 = Vector3.ZERO
var _east_outward: Vector3 = Vector3.ZERO
var _melee: Array = []
var _ranged: Array = []
var _all: Array = []

# WildlifeSpawner 广播捕获
var _threat_seen: bool = false
var _threat_gate: int = -1
var _threat_inside: Vector3 = Vector3.ZERO


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	call_deferred("_run")


func _on_watchdog() -> void:
	push_error("FAIL: NightDefenseFormationTest watchdog timeout after %.0fs" % WATCHDOG_SEC)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _on_threat_signal(active: bool, gate_index: int, gate_inside: Vector3) -> void:
	if not active:
		return
	_threat_seen = true
	_threat_gate = gate_index
	_threat_inside = gate_inside


func _state_of(pawn) -> String:
	if pawn == null or not is_instance_valid(pawn) or pawn.state_machine == null \
			or pawn.state_machine.current_state == null:
		return ""
	return String(pawn.state_machine.current_state.name)


func _wait_physics_frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _all_settled(list: Array) -> bool:
	for s in list:
		if not is_instance_valid(s):
			return false
		var soldier := s as Soldier
		if not soldier.defense_active or not soldier.defense_slot_valid:
			return false
		if _state_of(soldier) != "night_vigil" or not soldier.night_vigil_active:
			return false
		if soldier.global_position.distance_to(soldier.defense_slot) > 1.6:
			return false
	return true


func _any_in_chat(list: Array) -> bool:
	for s in list:
		if _state_of(s) == "night_chat":
			return true
	return false


func _finish() -> void:
	print("NIGHT DEFENSE FORMATION: %d failure(s)" % _failures)
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
	if _spawner == null or _city == null or _nav == null:
		push_error("FAIL: required world systems missing")
		get_tree().quit(1)
		return
	var settlement := _world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	EventBus.night_threat_direction_changed.connect(_on_threat_signal)
	ResourceManager.add(GameDefs.GOLD, 1000)
	TimeManager.set_speed(1.0)
	TimeManager.unfreeze_clock()
	TimeManager.begin(12)
	await _wait_physics_frames(3)

	# ================= WorldLayout 纯函数契约 =================
	var east_xz := WorldLayout.gate_inside_point(EAST_GATE)
	var east_probe := Vector3(east_xz.x, 0.0, east_xz.y)
	_check(WorldLayout.gate_outward_dir(EAST_GATE).is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"WorldLayout gate_outward_dir(east) = +X")
	_check(WorldLayout.gate_outward_dir(0).is_equal_approx(Vector3(0.0, 0.0, 1.0))
			and WorldLayout.gate_outward_dir(2).is_equal_approx(Vector3(0.0, 0.0, -1.0))
			and WorldLayout.gate_outward_dir(3).is_equal_approx(Vector3(-1.0, 0.0, 0.0)),
		"WorldLayout gate_outward_dir covers south/north/west")
	_check(_city.is_in_city(east_probe), "WorldLayout gate_inside_point(east) lands inside city")
	_check(absf(east_probe.x - (WorldLayout.CITY_HALF - 2.5)) < 0.5,
		"gate_inside_point sits one inset inside the city edge (x=%.2f)" % east_probe.x)
	_east_inside = _nav.snap_to_walkable(east_probe)
	_east_inside.y = 0.0
	_east_outward = WorldLayout.gate_outward_dir(EAST_GATE)

	# ================= 白天散布 4 近战 + 3 远程 =================
	var melee_points := [
		Vector3(-8.0, 0.0, 10.0), Vector3(-2.0, 0.0, 13.0),
		Vector3(5.0, 0.0, 12.0), Vector3(11.0, 0.0, 7.0),
	]
	var ranged_points := [
		Vector3(-6.0, 0.0, -8.0), Vector3(2.0, 0.0, -11.0), Vector3(12.0, 0.0, -4.0),
	]
	for p in melee_points:
		var soldier := _spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
			_nav.snap_to_walkable(p)) as Soldier
		if soldier != null:
			soldier.speech_bubble.debug_set_timer(999.0)
			_melee.append(soldier)
			_all.append(soldier)
	for p in ranged_points:
		var soldier := _spawner.call("spawn_soldier", GameDefs.settler_mage_def(),
			_nav.snap_to_walkable(p)) as Soldier
		if soldier != null:
			soldier.speech_bubble.debug_set_timer(999.0)
			_ranged.append(soldier)
			_all.append(soldier)
	await _wait_physics_frames(2)
	_check(_melee.size() == 4 and _ranged.size() == 3,
		"spawned 4 melee + 3 ranged soldiers (%d/%d)" % [_melee.size(), _ranged.size()])
	_check((_melee[0] as Soldier).is_ranged_combatant() == false
			and (_ranged[0] as Soldier).is_ranged_combatant() == true,
		"attack_kind classification matches melee/ranged defs")

	# ================= 入夜：WildlifeSpawner 选门并广播威胁方向 =================
	TimeManager.begin(21)   # 跨过 20:00 → 守城准备期，spawner 选门并广播威胁方向
	await _wait_physics_frames(15)
	_check(TimeManager.is_night(), "clock is night at 21:00 (hour=%d)" % TimeManager.hour)
	_check(_threat_seen and _threat_gate >= 0 and _threat_gate < 4,
		"WildlifeSpawner broadcasts threat gate on night prep (gate=%d)" % _threat_gate)
	_check(_threat_seen and _city.is_in_city(_threat_inside),
		"broadcast gate_inside point is inside the city")

	# 为可读性固定到东门（测试直接 emit 同一公共信号；战斗/警报优先级不变）。
	EventBus.night_threat_direction_changed.emit(true, EAST_GATE, _east_inside)
	await _wait_physics_frames(2)
	for s in _all:
		(s as Soldier).night_chat_cooldown = 999.0   # 先抑制群聊，阵型断言期间保持朝向城外

	var settled := false
	for _i in 1500:   # up to 25s（从城内各处走到东门内侧）
		if _all_settled(_all):
			settled = true
			break
		await get_tree().physics_frame
	_check(settled, "all 7 soldiers converge to east-gate defense slots")
	if not settled:
		await _finish()
		return

	# ================= ① 城门内侧区域 / 槽位安全 =================
	var near_gate := 0
	var slots_in_city := 0
	for s in _all:
		var soldier := s as Soldier
		if soldier.global_position.distance_to(_east_inside) <= 12.0:
			near_gate += 1
		if _city.is_in_city(soldier.defense_slot) \
				and _nav.is_walkable_cell(_nav.grid.world_to_grid(soldier.defense_slot)):
			slots_in_city += 1
	_check(near_gate == _all.size(),
		"all deployed soldiers stand within 12m of gate inside (%d/%d)" % [near_gate, _all.size()])
	_check(slots_in_city == _all.size(),
		"all defense slots are inside-city walkable cells (%d/%d)" % [slots_in_city, _all.size()])

	# ================= ② 近战前排 / 远程后排 =================
	var melee_depth_sum := 0.0
	var ranged_depth_sum := 0.0
	var melee_count := 0
	var ranged_count := 0
	var facing_ok := 0
	for s in _all:
		var soldier := s as Soldier
		# 纵深 = 沿「城门朝外方向」的入城深度（近战 0 起排，远程在后排）+ 少量横向扩散不计入纵深。
		var depth: float = (soldier.global_position - _east_inside).dot(-_east_outward)
		if soldier.is_ranged_combatant():
			ranged_depth_sum += depth
			ranged_count += 1
		else:
			melee_depth_sum += depth
			melee_count += 1
		var forward: Vector3 = -soldier.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001 and forward.normalized().dot(_east_outward) > 0.6:
			facing_ok += 1
	var melee_avg: float = melee_depth_sum / maxf(1.0, float(melee_count))
	var ranged_avg: float = ranged_depth_sum / maxf(1.0, float(ranged_count))
	_check(melee_count == 4 and ranged_count == 3,
		"melee/ranged counts preserved after deployment (melee=%d, ranged=%d)" % [melee_count, ranged_count])
	_check(ranged_avg > melee_avg + 1.5,
		"ranged rank sits behind melee rank (melee avg depth=%.2fm, ranged avg depth=%.2fm)" % [
			melee_avg, ranged_avg])
	_check(facing_ok == _all.size(),
		"all deployed soldiers face the gate outward direction (%d/%d)" % [facing_ok, _all.size()])

	# ================= ⑤ 部署状态下的夜间群聊：原地相向、不离位 =================
	var chat_trio: Array = [_melee[0], _melee[1], _melee[2]]
	for s in chat_trio:
		(s as Soldier).night_chat_cooldown = 0.0
		(s as Soldier).speech_bubble.hide_now()
		var st = (s as Soldier).state_machine.current_state
		if st != null:
			st.set("_scan_left", 0.0)
	await _wait_physics_frames(3)
	var chat_in_place := _any_in_chat(chat_trio)
	_check(chat_in_place, "night chat can start while deployed at defense slots")
	var before_pos: Dictionary = {}
	var chat_members: Array = []
	for s in chat_trio:
		var soldier := s as Soldier
		before_pos[soldier.get_instance_id()] = soldier.global_position
		if _state_of(soldier) == "night_chat":
			chat_members.append(soldier)
	await _wait_physics_frames(120)   # 2s：聊天期间不能走向小群中心
	var stay_ok := true
	for soldier in chat_members:
		var sid: int = (soldier as Soldier).get_instance_id()
		var moved: float = -1.0
		if before_pos.has(sid):
			moved = (soldier as Soldier).global_position.distance_to(before_pos[sid])
		if moved < 0.0 or moved > 0.5:
			stay_ok = false
	for s in chat_trio:
		var soldier := s as Soldier
		# 站定判定与 night_vigil 同口径（POST_ARRIVE=1.2m），聊天期间不得离位。
		if soldier.defense_active and soldier.global_position.distance_to(soldier.defense_slot) > 1.6:
			stay_ok = false
	_check(stay_ok and chat_members.size() >= 2,
		"deployed night chat stays in formation slots (members=%d)" % chat_members.size())
	var chat_ended := false
	for _i in 1080:   # up to 18s
		if not _any_in_chat(_all):
			chat_ended = true
			break
		await get_tree().physics_frame
	var back_in_slots := false
	for _i in 600:   # up to 10s
		if _all_settled(_all):
			back_in_slots = true
			break
		await get_tree().physics_frame
	_check(chat_ended and back_in_slots, "deployed night chat ends back in formation slots")

	# ================= ⑥ 天亮：威胁解除、阵位清空、恢复白天生活 =================
	TimeManager.unfreeze_clock()
	TimeManager.begin(6)
	await _wait_physics_frames(12)
	_check(not TimeManager.is_night(), "dawn: clock is day again (hour=%d)" % TimeManager.hour)
	var cleared := false
	for _i in 480:   # up to 8s
		var done := true
		for s in _all:
			var soldier := s as Soldier
			if soldier.defense_active or soldier.defense_slot_valid:
				done = false
				break
		if done:
			cleared = true
			break
		await get_tree().physics_frame
	_check(cleared, "dawn clears defense deployment (defense_active/slot_valid false)")
	var day_life := false
	for _i in 360:   # up to 6s
		for s in _all:
			var st := _state_of(s)
			if st == "wander" or st == "patrol" or st == "rest":
				day_life = true
				break
		if day_life:
			break
		await get_tree().physics_frame
	_check(day_life, "day life resumes after threat clears (wander/patrol/rest)")

	await _finish()
