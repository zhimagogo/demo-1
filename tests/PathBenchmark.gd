extends Node
## ============================================================================
## 寻路性能基准：真实世界 + 大规模单位混战 / 采集 / 攻城压力下测量物理帧耗时
## 与 NavSystem 寻路统计（A* 次数 / 同帧缓存命中 / 路径平滑压缩比）。
##
## godot --headless --path . tests/PathBenchmark.tscn --fixed-fps 60
##
## 输出行格式 BENCHMARK|<metric>|<value>，便于脚本化对比优化前后。
## 用法（对比基线）：临时还原旧版 NavSystem.gd/Pawn.gd 再跑一遍即可。
## ============================================================================

const RUN_SECONDS: float = 45.0     # 采样时长（真实秒，time_scale=1 保证物理测量干净）
const WARMUP_SECONDS: float = 5.0   # 预热：场景搭建 / 单位入场不计入统计

const VILLAGERS := 24
const SOLDIERS_MELEE := 10
const SOLDIERS_RANGED := 6
const RAIDERS_ROAM := 12
const RAIDERS_SIEGE := 12

# Measure each physics callback frame directly. Performance monitors refresh
# coarsely in headless runs and can repeat a startup spike across many samples.
class FrameStart extends Node:
	var stamp_usec: int = 0
	func _physics_process(_delta: float) -> void:
		stamp_usec = Time.get_ticks_usec()

var _frame_start: FrameStart
var _main: Node
var _running: bool = false
var _elapsed: float = 0.0
var _samples: Array[float] = []
var _siege_targets: Array = []
var _siegers: Array = []


func _ready() -> void:
	_frame_start = FrameStart.new()
	_frame_start.process_physics_priority = -1000
	add_child(_frame_start)
	process_physics_priority = 1000
	seed(20261001)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# 冻结外部噪声源：随机刷怪 / 资源再生 / 流民迁入（保持单位数可控可复现）
	(_main.get_node("WorldRoot/WildlifeSpawner") as Node).set_process(false)
	(_main.get_node("WorldRoot/ResourceGrowthSystem") as Node).set_process(false)
	(_main.get_node("WorldRoot/SettlementSystem") as Node).set_process(false)
	TimeManager.set_speed(1.0)
	TimeManager.begin(22) # 入夜：同时校准 hour 与 game_seconds
	await _auto_build()
	_spawn_units()
	_running = true
	print("[bench] world ready: %d villagers, %d soldiers, %d roam raiders, %d siege raiders" % [
		VILLAGERS, SOLDIERS_MELEE + SOLDIERS_RANGED, RAIDERS_ROAM, RAIDERS_SIEGE])


## 模拟玩家布局：房屋 / 酒馆 + 一段 U 形城墙（给攻城制造绕行与破墙场景）。
func _auto_build() -> void:
	var build := _main.get_node("WorldRoot/BuildSystem") as BuildSystem
	var defs := {}
	for d in GameDefs.building_defs():
		defs[d.id] = d
	var plan: Array = [
		[&"house", Vector3(10.4, 0, 10.4)], [&"house", Vector3(14.4, 0, 10.4)],
		[&"house", Vector3(-10.4, 0, 10.4)], [&"house", Vector3(-14.4, 0, 10.4)],
		[&"house", Vector3(10.4, 0, -10.4)], [&"house", Vector3(14.4, 0, -10.4)],
		[&"tavern", Vector3(6.4, 0, -10.4)],
		# v37 起酒馆全场唯一：这一座会被数量上限拒绝（静默跳过，不报错）；保留以覆盖「超限放置」路径
		[&"tavern", Vector3(-6.4, 0, -10.4)],
		[&"wall", Vector3(16.0, 0, 0.0)], [&"wall", Vector3(-16.0, 0, 0.0)],
		[&"wall", Vector3(0.0, 0, -16.0)],
	]
	# U 形城墙：正面包住主城，只在东北留口（攻城野怪必须绕到口或破墙）
	for x in range(-6, 7, 2):
		plan.append([&"wall", Vector3(float(x) * 2.0 + 0.4, 0, 18.0)])
	for z in range(2, 10, 2):
		plan.append([&"wall", Vector3(-12.4, 0, 18.0 - float(z) * 2.0)])
		plan.append([&"wall", Vector3(12.4, 0, 18.0 - float(z) * 2.0)])
	for entry in plan:
		build.enter_build_mode(defs[entry[0]])
		build.try_place_at(entry[1])
		await get_tree().physics_frame
	build.exit_build_mode()
	# 收集攻城可用目标（建筑 + 主城），供野怪轮转锁定
	for b in get_tree().get_nodes_in_group("building"):
		_siege_targets.append(b)
	for bc in get_tree().get_nodes_in_group("base_core"):
		_siege_targets.append(bc)


func _spawn_units() -> void:
	# PawnSpawner 无 class_name（项目惯例：分组查找 + duck typing），用 call() 调用
	var spawner: Node = _main.get_node("WorldRoot/PawnSpawner")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240601   # 固定种子：每次运行的世界布局与单位行为可复现对比
	# 村民：城内散布，自主「采集→搬运→入库」经济循环（持续产生资源点寻路）
	for i in VILLAGERS:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.0, 16.0)
		spawner.call("spawn_colonist", Vector3(cos(a) * r, 0, sin(a) * r))
	# 士兵：城内一圈，白天出城巡逻自动接战（追击产生高频 repath）
	for i in SOLDIERS_MELEE:
		var a := TAU * float(i) / float(SOLDIERS_MELEE)
		spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(cos(a) * 14.0, 0, sin(a) * 14.0))
	for i in SOLDIERS_RANGED:
		var a := TAU * float(i) / float(SOLDIERS_RANGED)
		spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(cos(a) * 10.0, 0, sin(a) * 10.0))
	# 游荡野怪：城外东北象限，徘徊 + 接战城外士兵
	for i in RAIDERS_ROAM:
		var a := rng.randf_range(-0.4, 0.9)
		var r := rng.randf_range(26.0, 40.0)
		spawner.call("spawn_raider", Vector3(cos(a) * r, 0, sin(a) * r), GameDefs.raider_def())
	# 攻城野怪：城南弧线入场，直接推入攻城（打 U 形墙内的建筑/主城）
	for i in RAIDERS_SIEGE:
		var a := rng.randf_range(2.2, 3.6)
		var r := rng.randf_range(26.0, 34.0)
		var raider: Raider = spawner.call("spawn_raider", Vector3(cos(a) * r, 0, sin(a) * r), GameDefs.raider_def())
		_siegers.append(raider)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	# 攻城野怪的目标维持：目标被打掉 / 失效则换下一个（模拟不间断攻城压力）
	if not _siegers.is_empty() and int(_elapsed * 2.0) != int((_elapsed - delta) * 2.0):
		_keep_sieging()
	if _elapsed >= WARMUP_SECONDS:
		# Wall time across all physics callbacks, including Pawn.move_and_slide.
		_samples.append(float(Time.get_ticks_usec() - _frame_start.stamp_usec) / 1000000.0)
	if _elapsed >= RUN_SECONDS:
		_report()


func _keep_sieging() -> void:
	for raider in _siegers:
		if not is_instance_valid(raider):
			continue
		var r := raider as Raider
		if r.is_dead_flag:
			continue
		var fighting: bool = r.state_machine.current_state != null \
			and (r.state_machine.current_state is FightState or r.state_machine.current_state is RangedFightState)
		if fighting and r.combat_target != null and is_instance_valid(r.combat_target):
			continue
		# 目标丢失：按攻城语义重新锁定（优先仍存活的建筑，其次主城）
		var pick = null
		for t in _siege_targets:
			if is_instance_valid(t):
				pick = t
				break
		if pick != null:
			r.state_machine.transition_to("fight", { "target": pick, "siege": true })


func _report() -> void:
	var nav := get_tree().get_first_node_in_group("nav_system") as NavSystem
	_samples.sort()
	var total := 0.0
	for s in _samples:
		total += s
	var avg_ms := total / maxf(float(_samples.size()), 1.0) * 1000.0
	var p95_ms := _samples[clampi(int(_samples.size() * 0.95), 0, _samples.size() - 1)] * 1000.0
	var max_ms := _samples[_samples.size() - 1] * 1000.0
	var alive_units := get_tree().get_nodes_in_group("player_unit").size() \
		+ get_tree().get_nodes_in_group("enemy").size()
	print("BENCHMARK|physics_avg_ms|%.4f" % avg_ms)
	print("BENCHMARK|physics_p95_ms|%.4f" % p95_ms)
	print("BENCHMARK|physics_max_ms|%.4f" % max_ms)
	print("BENCHMARK|samples|%d" % _samples.size())
	print("BENCHMARK|alive_units|%d" % alive_units)
	if nav != null:
		# 旧版 NavSystem 无统计字段（get 返回 null）：容错输出，便于 baseline 对比
		var queries: int = int(nav.get("stat_astar_queries") if "stat_astar_queries" in nav else 0)
		var hits: int = int(nav.get("stat_cache_hits") if "stat_cache_hits" in nav else 0)
		var raw_wp: int = int(nav.get("stat_waypoints_raw") if "stat_waypoints_raw" in nav else 0)
		var smooth_wp: int = int(nav.get("stat_waypoints_smoothed") if "stat_waypoints_smoothed" in nav else 0)
		print("BENCHMARK|astar_queries|%d" % queries)
		print("BENCHMARK|cache_hits|%d" % hits)
		print("BENCHMARK|waypoints_raw|%d" % raw_wp)
		print("BENCHMARK|waypoints_smoothed|%d" % smooth_wp)
	print("BENCHMARK DONE")
	_running = false
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
