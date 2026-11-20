extends Node
## 集结加速 / 到位停住 / 跟随原速 专项回归（v12）：
##   godot --headless --path . tests/RallyFollowTest.tscn --log-file /private/tmp/a-rally.log --fixed-fps 60
##
## 覆盖需求「集合时加速 100% 然后移动到玩家周围、停住（不要在地上搓）、跟随时原速」：
##  1. G 集结后 4 名近战兵 5 秒内全部进入主角 6m 范围（集结追赶期 2× 有效）。
##  2. 追赶期实测平均速度 > 1.4× 原速（证明加速真实发生，不是走运）。
##  3. 到位后 2 秒内每名成员的位移 < 0.15m（停住不搓）。
##  4. 主角再移动 20m：持续跟随回落 1× 原速（最大瞬时速度 < 1.2× move_speed）。
##  5. 主角站定 3 秒：成员不因分离力散射（与主角距离不增长）。
##
## 输出保持 ASCII（headless 日志中文会乱码）；headless 无真实输入，移动 / 集结直接调 API。

const SOLDIER_COUNT: int = 4
const RALLY_DIST: float = 16.0          # 小兵出生距主角的距离（> GATHER_START_DIST，触发追赶期）
const ARRIVE_DIST: float = 6.0          # 验收：全员进入主角 6m
const CHASE_MAX_FRAMES: int = 300       # 追赶上限 5s @60fps
const SETTLE_GRACE_FRAMES: int = 90     # 全员到位后再等 1.5s，让最后一次分离推挤收敛
const SETTLE_CHECK_FRAMES: int = 120    # 随后量 2s 内的位移
const FOLLOW_MAX_FRAMES: int = 420      # 跟随 20m 上限 7s
const STAND_FRAMES: int = 180           # 主角站定 3s

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _pos_xz(n: Node3D) -> Vector3:
	var v: Vector3 = n.global_position
	v.y = 0.0
	return v


func _dist_xz(a: Node3D, b: Node3D) -> float:
	return _pos_xz(a).distance_to(_pos_xz(b))


func _vel_xz(p: Pawn) -> Vector3:
	var v: Vector3 = p.velocity
	v.y = 0.0
	return v


## 与最近的队友的 XZ 距离（用于把「分离力叠加」的帧从速度采样里剔除）。
func _nearest_mate_dist(s: Pawn, all: Array) -> float:
	var best := INF
	for o in all:
		if o == s:
			continue
		best = minf(best, _dist_xz(s as Node3D, o as Node3D))
	return best


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	# 测试期不刷野怪 / 不刷流民定居：小队必须专心跟队，不能被拉去接战或改编队
	var wildlife := world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().physics_frame
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	_check(hero != null and SelectionManager.hero_mode_active, "hero is in third-person control mode")

	# ---- 布景：主角站城外南侧空地，4 名近战兵在 16m 外一字排开 ----
	var hero_home := Vector3(0, 0, 16)
	hero.global_position = hero_home
	hero.velocity = Vector3.ZERO
	hero.set_party([])   # 清掉任何既有编队，保证下面 4 名小兵全部入队
	await get_tree().physics_frame
	var base_speed: float = GameDefs.settler_warrior_def().move_speed
	var soldiers: Array = []
	for i in SOLDIER_COUNT:
		var def := GameDefs.settler_warrior_def()
		var at := Vector3(float(i) * 2.2 - 2.2, 0.0, hero_home.z + RALLY_DIST)
		var s: Pawn = spawner.call("spawn_soldier", def, at)
		soldiers.append(s)
	for _i in 3:
		await get_tree().physics_frame
	var spawned_ok: bool = true
	for s in soldiers:
		if s == null or not is_instance_valid(s):
			spawned_ok = false
	_check(spawned_ok and hero.party.size() == SOLDIER_COUNT,
		"4 soldiers spawned and auto-fill the party (%d)" % hero.party.size())

	# ---- G 集结（真路径：HeroController._toggle_squad_rally）----
	var start_pos: Dictionary = {}
	var travel: Dictionary = {}
	var prev: Dictionary = {}
	for s in soldiers:
		start_pos[s] = _pos_xz(s)
		travel[s] = 0.0
		prev[s] = _pos_xz(s)
	controller._toggle_squad_rally()
	var squad_ok: bool = hero.squad.size() == SOLDIER_COUNT
	var state_ok: bool = true
	var mult_ok: bool = true
	for s in soldiers:
		if not hero.squad.has(s):
			squad_ok = false
		if s.state_machine.current_state.name != "follow":
			state_ok = false
		if s.speed_multiplier < FollowState.GATHER_SPEED_MULT - 0.001:
			mult_ok = false
	_check(squad_ok, "G rally recruits all 4 soldiers into the squad")
	_check(state_ok, "every member enters follow state on rally")
	_check(mult_ok, "rally chase phase starts at %.1fx speed multiplier" % FollowState.GATHER_SPEED_MULT)

	# ---- 追赶：记录每名成员的路径长度与到位帧 ----
	var arrive_frame: Dictionary = {}
	var frames: int = 0
	while frames < CHASE_MAX_FRAMES:
		await get_tree().physics_frame
		frames += 1
		var all_in: bool = true
		for s in soldiers:
			var p: Vector3 = _pos_xz(s)
			travel[s] = float(travel[s]) + p.distance_to(prev[s])
			prev[s] = p
			if not arrive_frame.has(s) and _dist_xz(s, hero) <= ARRIVE_DIST:
				arrive_frame[s] = frames
			if not arrive_frame.has(s):
				all_in = false
		if all_in:
			break
	var ticks: float = float(Engine.physics_ticks_per_second)
	_check(arrive_frame.size() == SOLDIER_COUNT,
		"all %d soldiers reach the hero within 5s (%d arrived, %d frames used)"
			% [SOLDIER_COUNT, arrive_frame.size(), frames])

	# ---- 追赶期平均速度：路径长度 / 到位耗时 ----
	var chase_sum := 0.0
	var chase_detail := ""
	for s in soldiers:
		var f: int = int(arrive_frame.get(s, frames))
		var t: float = maxf(float(f) / ticks, 0.001)
		var v: float = float(travel[s]) / t
		chase_sum += v
		chase_detail += " %.2f" % v
	var chase_avg: float = chase_sum / float(SOLDIER_COUNT)
	print("CHASE AVG SPEED:", chase_detail)
	_check(chase_avg > 1.4 * base_speed,
		"rally chase average speed %.2f m/s > 1.4x base %.2f m/s" % [chase_avg, base_speed])

	# ---- 到位停住：稳定期后量 2s 内的最大位移 ----
	for _i in SETTLE_GRACE_FRAMES:
		await get_tree().physics_frame
	var settle_from: Dictionary = {}
	var settle_drift: Dictionary = {}
	for s in soldiers:
		settle_from[s] = _pos_xz(s)
		settle_drift[s] = 0.0
	for _i in SETTLE_CHECK_FRAMES:
		await get_tree().physics_frame
		for s in soldiers:
			settle_drift[s] = maxf(float(settle_drift[s]), _pos_xz(s).distance_to(settle_from[s]))
	var worst_drift := 0.0
	var drift_detail := ""
	for s in soldiers:
		worst_drift = maxf(worst_drift, float(settle_drift[s]))
		drift_detail += " %.3f" % float(settle_drift[s])
	print("SETTLED DRIFT (m, 2s):", drift_detail)
	_check(worst_drift < 0.15,
		"settled members hold still, no ground rubbing (worst drift %.3f m < 0.15 m)" % worst_drift)
	var closest := INF
	for s in soldiers:
		closest = minf(closest, _dist_xz(s, hero))
	_check(closest < ARRIVE_DIST, "squad stays in formation around hero (closest %.2f m)" % closest)

	# ---- 持续跟随回落原速：主角瞬移 20m ----
	# 采样口径：逐物理帧取速度（含分离力叠加），并同时记录真实位移量证明「确实在跑」。
	# 另单独统计「不与队友重叠的帧」（分离力为 0）作为对照列，便于分辨超速来源。
	var max_speed: Dictionary = {}
	var max_clean: Dictionary = {}
	var travelled: Dictionary = {}
	var prev2: Dictionary = {}
	for s in soldiers:
		max_speed[s] = 0.0
		max_clean[s] = 0.0
		travelled[s] = 0.0
		prev2[s] = _pos_xz(s)
	hero.global_position = hero_home + Vector3(0, 0, 20)
	hero.velocity = Vector3.ZERO
	var follow_frames: int = 0
	var formed: int = 0
	while follow_frames < FOLLOW_MAX_FRAMES:
		await get_tree().physics_frame
		follow_frames += 1
		var all_close: bool = true
		for s in soldiers:
			max_speed[s] = maxf(float(max_speed[s]), _vel_xz(s).length())
			if _nearest_mate_dist(s, soldiers) >= FollowState.SEPARATION_RADIUS:
				max_clean[s] = maxf(float(max_clean[s]), _vel_xz(s).length())
			var p: Vector3 = _pos_xz(s)
			travelled[s] = float(travelled[s]) + p.distance_to(prev2[s])
			prev2[s] = p
			if _dist_xz(s, hero) > ARRIVE_DIST:
				all_close = false
		if all_close:
			formed += 1
			if formed > 30:
				break
		else:
			formed = 0
	var worst_speed := 0.0
	var speed_detail := ""
	var clean_detail := ""
	var travel_detail := ""
	var least_travel := INF
	for s in soldiers:
		worst_speed = maxf(worst_speed, float(max_speed[s]))
		least_travel = minf(least_travel, float(travelled[s]))
		speed_detail += " %.2f" % float(max_speed[s])
		clean_detail += " %.2f" % float(max_clean[s])
		travel_detail += " %.1f" % float(travelled[s])
	print("FOLLOW MAX SPEED ALL FRAMES (m/s):", speed_detail)
	print("FOLLOW MAX SPEED NO-OVERLAP FRAMES (m/s):", clean_detail)
	print("FOLLOW TRAVELLED (m):", travel_detail)
	_check(formed > 30, "squad re-forms within %.0fs after hero moves 20m" % (float(FOLLOW_MAX_FRAMES) / ticks))
	_check(least_travel > 10.0, "every member actually followed the hero (min travel %.1f m)" % least_travel)
	_check(worst_speed < 1.2 * base_speed,
		"sustained follow uses 1x base speed (max %.2f m/s < %.2f m/s)"
			% [worst_speed, 1.2 * base_speed])
	var mult_back: bool = true
	for s in soldiers:
		if s.speed_multiplier > 1.001:
			mult_back = false
	_check(mult_back, "speed multiplier falls back to 1x after the squad is gathered")

	# ---- 主角站定 3 秒：不散射 ----
	var dist0: Dictionary = {}
	for s in soldiers:
		dist0[s] = _dist_xz(s, hero)
	for _i in STAND_FRAMES:
		await get_tree().physics_frame
	var worst_growth := -INF
	var growth_detail := ""
	for s in soldiers:
		var d: float = _dist_xz(s, hero) - float(dist0[s])
		worst_growth = maxf(worst_growth, d)
		growth_detail += " %.2f" % d
	print("STAND STILL DIST GROWTH (m):", growth_detail)
	_check(worst_growth < 0.3,
		"members do not scatter while hero stands still (worst growth %.2f m)" % worst_growth)

	print("RALLY FOLLOW TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
