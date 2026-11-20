extends Node
## 头目生命周期测试：快进到第 2 天入夜 → 头目登场（boss_spawned）→ 讨伐（boss_died + 掉落）。
## godot --headless --path . tests/BossNightTest.tscn --fixed-fps 60

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	TimeManager.set_speed(3.0)
	# 快进到第 2 天 19:58（即将入夜；夜 2 = 头目夜）
	TimeManager.game_seconds = (1.0 * 24.0 + 19.97) / 24.0 * TimeManager.seconds_per_day
	var boss_spawned: Array = []
	EventBus.boss_spawned.connect(func(b): boss_spawned.append(b))
	var boss_died: Array = []
	EventBus.boss_died.connect(func(b): boss_died.append(b))
	# v31 守城准备：入夜先冻结昼夜时钟；模拟玩家按下「准备守城」后头目才登场
	# （DayNightCycle 每 0.1s 采样一次）
	var prepped := false
	for _i in 120:
		await get_tree().physics_frame
		if TimeManager.clock_frozen:
			prepped = true
			break
	_check(prepped, "night 2 enters defense prep (clock frozen)")
	GameManager.request_night_defense()
	for _i in 120:
		await get_tree().physics_frame
		if not boss_spawned.is_empty():
			break
	_check(not boss_spawned.is_empty(), "boss spawns after defense confirm on night 2")
	if boss_spawned.is_empty():
		_finish()
		return
	var boss: Node = boss_spawned[0]
	_check(boss != null and is_instance_valid(boss) and boss.def.is_boss, "boss def flagged (is_boss)")
	_check(boss.def.unit_name != "", "boss has a random name: %s" % boss.def.unit_name if boss != null else "")
	# HUD 头目横幅可见
	var hud := _main.get_node_or_null("HUD")
	var banner = hud.get("boss_banner") if hud != null else null
	_check(banner != null and banner.visible, "boss banner visible on HUD")
	# 主角瞬移到头目旁边击杀（验证掉落 + 战报 + 经验）
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
	_check(hero != null, "hero exists")
	if hero != null and is_instance_valid(boss):
		hero.global_position = boss.global_position + Vector3(4.0, 0.0, 0.0)
		var xp_before: int = hero.xp
		boss.health.apply_damage(99999.0, hero)
		for _i in 30:
			await get_tree().physics_frame
			if not boss_died.is_empty():
				break
		_check(not boss_died.is_empty(), "boss_died broadcast on kill")
		_check(hero.xp > xp_before, "hero gains boss xp (%d → %d)" % [xp_before, hero.xp])
		var container := get_tree().get_first_node_in_group("loot_drops")
		var loot: Array = container.get_children() if container != null else []
		# v22 金币多份爆出（头目 5~8 份）：按「头目位置附近」过滤本轮掉落，
		# 断言份数落在 5~8 且总和保住大额赏金（单份金额随拆分变小，不能再看单份）。
		var boss_pos: Vector3 = (boss as Node3D).global_position
		var piece_count := 0
		var gold_sum := 0
		for drop in loot:
			if drop.get("amount") == null or not (drop is Node3D):
				continue
			if (drop as Node3D).global_position.distance_to(boss_pos) > 4.0:
				continue
			piece_count += 1
			gold_sum += int(drop.get("amount"))
		_check(piece_count >= 5 and piece_count <= 8, "boss bursts 5~8 coins (got %d)" % piece_count)
		_check(gold_sum >= 100, "boss gold total preserved near boss (sum=%d)" % gold_sum)
	_finish()


func _finish() -> void:
	print("BOSS NIGHT TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
