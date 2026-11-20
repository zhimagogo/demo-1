extends Node
## ============================================================================
## v20 夜潮攻城回归（v31 起入夜先进「守城准备期」）：
## ① 白天零散刷怪正常出怪（正控制：刷新器本身在工作）
## ② 傍晚（18:00~20:00）完全停刷
## ③ 入夜进入守城准备：昼夜时钟冻结、夜潮延迟；随机选定「四条道路尽头之一」并
##    提前播报方向；玩家确认（request_night_defense）后时间恢复，从该路口成批
##    刷出大部队（>=5 只），全部带 assaulting 标记直扑主城
## ④ 夜潮怪持续朝主城推进（一段时间后与主城的平均距离显著缩小）
## ⑤ 中途被小兵打中 → 立即转火小兵；小兵阵亡 → 立刻恢复攻城（再锁主城）
## ⑥ 天亮后夜潮状态清理（_night_gate 复位、assaulting 全部清零、时钟解冻兜底）
## godot --headless --path . tests/NightAssaultTest.tscn --fixed-fps 60
## ============================================================================

var _failures: int = 0
var _main: Node
var _spawner: Node


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)


func _set_clock(day: int, hour: float) -> void:
	TimeManager.game_seconds = (float(day - 1) * 24.0 + hour) / 24.0 * TimeManager.seconds_per_day


func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemy").size()


## 当前存活的夜潮怪（assaulting 标记）。
func _wave_raiders() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Raider and is_instance_valid(e) and (e as Raider).assaulting:
			out.append(e)
	return out


func _avg_dist_to(units: Array, point: Vector3) -> float:
	var total: float = 0.0
	var n: int = 0
	for u in units:
		if is_instance_valid(u):
			total += (u as Node3D).global_position.distance_to(point)
			n += 1
	return total / n if n > 0 else INF


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	TimeManager.set_speed(3.0)
	_spawner = _main.get_node("WorldRoot/WildlifeSpawner")

	# ---- ① 白天出怪（正控制）----
	var day_spawned := false
	for _i in 240:   # ~12 游戏秒
		await get_tree().physics_frame
		if _enemy_count() > 0:
			day_spawned = true
			break
	_check(day_spawned, "day spawner produces scattered raiders")

	# ---- ② 傍晚停刷 ----
	# 注意时钟换算：seconds_per_day=120 → 1 游戏小时 = 5 游戏秒；傍晚窗口 18:00~20:00
	# 只有 10 游戏秒。18:15 起等 8 游戏秒（18:33），确保全程留在窗口内。
	_set_clock(1, 18.25)
	await get_tree().physics_frame
	_check(Raider.is_dusk_now(), "clock sits in dusk window (18:00~20:00)")
	var dusk_count: int = _enemy_count()
	for _i in 160:   # 8 游戏秒（18:15 → 18:33），覆盖 2 个白天补刷间隔
		await get_tree().physics_frame
	_check(_enemy_count() <= dusk_count, "dusk spawns nothing (count %d -> %d)" % [dusk_count, _enemy_count()])

	# ---- ③ 入夜：先进入守城准备期（v31 时间静止），确认后才刷夜潮 ----
	_set_clock(1, 19.983)   # 19:59，跨过 20:00 触发 night_changed(true)
	var gate_seen := false
	for _i in 120:
		await get_tree().physics_frame
		if int(_spawner.get("_night_gate")) >= 0:
			gate_seen = true
			break
	_check(gate_seen, "night gate (road end) chosen on nightfall")
	var gate: int = int(_spawner.get("_night_gate"))
	var gate_pos: Vector3 = _spawner.get("_night_gate_pos")
	var expect := WorldLayout.road_end(gate)
	_check(gate >= 0 and gate <= 3, "gate index in 0..3 (%d)" % gate)
	_check(absf(gate_pos.x - expect.x) < 3.0 and absf(gate_pos.z - expect.y) < 3.0,
		"gate pos snaps to road end %d (got %s want %s)" % [gate, gate_pos, expect])
	_check(WorldLayout.road_distance(Vector2(gate_pos.x, gate_pos.z)) < 3.5, "gate sits on a road")
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	_check(city != null and not city.is_in_city(gate_pos), "gate outside city")

	# v40 夜战节奏：夜潮/头目不在 ±121m 的道路尽头出生，而是从老地图边缘距离的
	# 62m 集结点出发（WorldLayout.NIGHT_WAVE_INSET）——否则 3.5m/s 要走 35~45 秒，
	# 一夜只有 50 游戏秒，首波还没摸到城墙天就亮了。
	var wave_origin: Vector3 = _spawner.get("_night_wave_origin")
	_check(WorldLayout.road_distance(Vector2(wave_origin.x, wave_origin.z)) < 3.5,
		"night wave origin sits on a road (%.1f, %.1f)" % [wave_origin.x, wave_origin.z])
	_check(wave_origin.distance_to(gate_pos) > 40.0,
		"night wave origin is the 62m rally point, not the map-edge gate (%.1fm apart)"
			% wave_origin.distance_to(gate_pos))

	# v31 守城准备：入夜时钟冻结、夜潮延迟；按下「准备守城」后时间恢复、夜潮才来
	_check(TimeManager.clock_frozen, "nightfall freezes the day clock (defense prep)")
	_check(bool(_spawner.get("_night_prep")), "spawner enters night prep state")
	var prep_wave_free := false
	for _i in 30:   # ~1.5 游戏秒：确认准备期真的不出怪（不只是没到点）
		await get_tree().physics_frame
		if not _wave_raiders().is_empty():
			prep_wave_free = true
			break
	_check(not prep_wave_free, "no assault wave spawns during prep")
	GameManager.request_night_defense()
	await get_tree().physics_frame
	_check(not TimeManager.clock_frozen, "defense confirm unfreezes the day clock")
	_check(not bool(_spawner.get("_night_prep")), "spawner leaves prep state on confirm")
	# 非准备期的重复请求应被幂等忽略（时钟不得再次冻结/报错）
	GameManager.request_night_defense()
	await get_tree().physics_frame
	_check(not TimeManager.clock_frozen, "repeat defense request is ignored outside prep")

	var wave: Array = []
	for _i in 120:
		await get_tree().physics_frame
		wave = _wave_raiders()
		if wave.size() >= 5:
			break
	_check(wave.size() >= 5, "night wave batch spawns >=5 raiders (got %d)" % wave.size())
	var targeting_base: int = 0
	var near_gate: int = 0
	var sieging: int = 0
	var where: String = ""
	for r in wave:
		var ra := r as Raider
		if ra.combat_target != null and is_instance_valid(ra.combat_target) \
				and ra.combat_target.is_in_group("base_core"):
			targeting_base += 1
		# v40：实际出生点是 62m 集结点 wave_origin（gate_pos 仍是道路尽头播报锚点）
		if ra.global_position.distance_to(wave_origin) < 12.0:
			near_gate += 1
		if ra._sieging:
			sieging += 1
		where += "(%.1f,%.1f) " % [ra.global_position.x, ra.global_position.z]
	var wave_n: int = mini(5, wave.size())
	_check(targeting_base >= wave_n, "wave raiders target the base core (%d/%d)" % [targeting_base, wave.size()])
	_check(sieging >= wave_n, "wave raiders carry siege flag (%d/%d)" % [sieging, wave.size()])
	_check(near_gate >= wave_n, "wave raiders spawn at the 62m night-wave origin (%d/%d, origin=(%.1f,%.1f), at %s)" \
		% [near_gate, wave.size(), wave_origin.x, wave_origin.z, where])

	# ---- ④ 持续朝主城推进 ----
	var base := get_tree().get_first_node_in_group("base_core") as Node3D
	var d0: float = _avg_dist_to(wave, base.global_position)
	for _i in 240:   # ~12 游戏秒：足够走 ~40m，但还没贴上主城
		await get_tree().physics_frame
	var d1: float = _avg_dist_to(wave, base.global_position)
	_check(d0 - d1 > 8.0, "wave marches toward base (avg dist %.1f -> %.1f)" % [d0, d1])

	# ---- ⑤ 中途被小兵打 → 转火小兵；小兵死 → 恢复攻城 ----
	# 主角挪去远处角落：杀完小兵后的再索敌（11m）不能顺手锁到主角，
	# 必须走「回 idle → 夜潮总攻 → 再锁主城」的恢复路径
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			(n as Hero).global_position = Vector3(46.0, 0.0, 46.0)
	var probe: Raider = null
	for r in wave:
		var ra := r as Raider
		if is_instance_valid(ra) and ra.assaulting and ra.health != null and ra.health.ratio() > 0.5 \
				and ra.combat_target != null and is_instance_valid(ra.combat_target) \
				and ra.combat_target.is_in_group("base_core"):
			probe = ra
			break
	_check(probe != null, "a healthy wave raider is assaulting base for retaliation probe")
	if probe == null:
		_finish()
		return
	var pawn_spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var soldier: Pawn = (pawn_spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(),
		probe.global_position + Vector3(6.0, 0.0, 0.0))
	probe.health.apply_damage(5.0, soldier)
	var st = probe.state_machine.current_state
	_check(st is FightState and st.target == soldier, "hit by soldier -> immediately fights the soldier")
	# 小兵阵亡 → 杀完小兵立刻恢复向主城推进
	soldier.health.apply_damage(99999.0, probe)
	var resumed := false
	for _i in 40:
		await get_tree().physics_frame
		if not is_instance_valid(probe):
			break
		var st2 = probe.state_machine.current_state
		if st2 is FightState and st2.target != null and is_instance_valid(st2.target) \
				and st2.target.is_in_group("base_core"):
			resumed = true
			break
	_check(resumed, "after the soldier dies the raider resumes its assault on the base")

	# ---- ⑥ 天亮清理 ----
	_set_clock(2, 5.983)   # 05:59，跨过 06:00 触发 night_changed(false)
	var dawn := false
	for _i in 120:
		await get_tree().physics_frame
		if int(_spawner.get("_night_gate")) < 0:
			dawn = true
			break
	_check(dawn, "dawn resets the night gate")
	var any_assault: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Raider and is_instance_valid(e) and (e as Raider).assaulting:
			any_assault += 1
	_check(any_assault == 0, "dawn clears all assaulting flags (%d remain)" % any_assault)
	_finish()


func _finish() -> void:
	print("NIGHT ASSAULT TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
