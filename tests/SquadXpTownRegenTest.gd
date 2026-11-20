extends Node
## ============================================================================
## v34 专项回归：小队经验共享 + 主角/巨龙回城疗伤
##   godot --headless --path . tests/SquadXpTownRegenTest.tscn --log-file /private/tmp/a-squadxp.log --fixed-fps 60
##
## 覆盖：
##   1. 数据契约：SQUAD_XP_SHARE_RATIO=0.5、squad_share_xp 换算（10→5 / 25→12 / 1→1）；
##      主角回城回血 2/s、巨龙 4/s；龙不参与等级线（共享不分给龙经验）。
##   2. 小队经验共享（真实 enemy_died 归属链：apply_damage(source) → last_attacker）：
##      a) 主角击杀：主角全额 10，两名在队小兵各 +5，队外小兵 +0；
##      b) 队内小兵击杀：击杀者全额、另一队员 +5、主角 +5（主角侧 50% 旧契约保持）；
##      c) 队外小兵击杀：只有击杀者拿全额，小队全体 +0（不外溢也不分进）；
##      d) 编外巨龙击杀：主角 +5、在队小兵各 +5（龙是编外第 5 位，同队口径）；
##      e) 解散小队后：原队员击杀不再分给主角与其他原队员。
##   3. 回城疗伤（白天 + 城镇范围才回，晚上守城不回）：
##      a) 主角白天城内掉血后缓慢回血（≈2/s）；b) 城外不回；
##      c) 夜晚 22:00（守城期）不回；d) 跳回白天原地恢复回血；
##      e) 巨龙同规则（≈4/s；夜晚不回）。
##
## 输出保持 ASCII（headless 日志中文会乱码）；命令直接调 API，不依赖真实输入。
## ============================================================================

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


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	var hero := _find_hero()
	_check(hero != null and city != null and spawner != null, "0: hero / city / spawner exist")
	# 测试期停刷野怪 / 流民并清场：经验与回血断言必须确定性
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
	TimeManager.begin(9)
	await get_tree().physics_frame

	# ================= 1. 数据契约 =================
	_check(is_equal_approx(GameDefs.SQUAD_XP_SHARE_RATIO, 0.5),
		"1: squad xp share ratio is 50%")
	_check(GameDefs.squad_share_xp(10) == 5 and GameDefs.squad_share_xp(25) == 12
		and GameDefs.squad_share_xp(1) == 1,
		"1: share xp truncates with a floor of 1 (10->5 / 25->12 / 1->1)")
	_check(is_equal_approx(GameDefs.hero_warrior_def().regen_per_sec, 2.0),
		"1: hero town regen configured 2/s")
	var drag_d := GameDefs.dragon_def(&"dragon_obsidian")
	_check(drag_d != null and is_equal_approx(drag_d.regen_per_sec, 4.0),
		"1: dragon town regen configured 4/s")
	_check(drag_d != null and not drag_d.can_level,
		"1: dragon stays out of the level system (no xp for the pet)")

	# ================= 2. 小队经验共享 =================
	var half: float = city.city_half
	var in_city := Vector3(half * 0.25, 0.0, half * 0.25)
	hero.global_position = in_city
	var sa: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-30.0, 0.0, 30.0))
	var sb: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(-34.0, 0.0, 26.0))
	var solo: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(34.0, 0.0, -34.0))
	await get_tree().physics_frame
	hero.recruit_squad([sa, sb])
	_check(hero.squad.has(sa) and hero.squad.has(sb) and not hero.squad.has(solo),
		"2: two soldiers recruited into the squad, solo stays out")
	await get_tree().physics_frame

	# ---- a) 主角击杀：主角全额，队员各 50%，队外 0 ----
	_kill_dummy(spawner, hero, Vector3(-40.0, 0.0, -40.0))
	_check(hero.xp == 10, "2a: hero killer keeps full 10 xp (got %d)" % hero.xp)
	_check(sa.xp == 5 and sb.xp == 5,
		"2a: squad soldiers share 50%% each (%d / %d)" % [sa.xp, sb.xp])
	_check(solo.xp == 0, "2a: soldier outside the squad gets nothing")

	# ---- b) 队内小兵击杀：击杀者全额，队友与主角 50% ----
	_kill_dummy(spawner, sa, Vector3(-42.0, 0.0, -36.0))
	_check(sa.xp == 15, "2b: killer soldier keeps full xp (5+10=15, got %d)" % sa.xp)
	_check(sb.xp == 10, "2b: fellow squad soldier shares 50%% (5+5=10, got %d)" % sb.xp)
	_check(hero.xp == 15, "2b: hero still shares 50%% on minion kills (10+5=15, got %d)" % hero.xp)
	_check(solo.xp == 0, "2b: outsider unaffected")

	# ---- c) 队外小兵击杀：不外溢也不分进 ----
	_kill_dummy(spawner, solo, Vector3(40.0, 0.0, -38.0))
	_check(solo.xp == 10, "2c: solo killer keeps full xp (got %d)" % solo.xp)
	_check(sa.xp == 15 and sb.xp == 10 and hero.xp == 15,
		"2c: squad members gain nothing from an outsider kill")

	# ---- d) 编外巨龙击杀：同队口径分账，龙自己不吃经验 ----
	var dragon: DragonPet = spawner.call("spawn_dragon", GameDefs.dragon_def(&"dragon_obsidian"),
		Vector3(36.0, 0.0, 36.0))
	dragon.follow_leader = hero   # 与 DragonSystem._spawn_pet 相同的队属绑定
	await get_tree().physics_frame
	_kill_dummy(spawner, dragon, Vector3(38.0, 0.0, 40.0))
	_check(hero.xp == 20, "2d: hero shares 50%% on dragon kills (15+5=20, got %d)" % hero.xp)
	_check(sa.xp == 20 and sb.xp == 15,
		"2d: squad soldiers share dragon kills too (%d / %d)" % [sa.xp, sb.xp])
	_check(dragon.xp == 0 and dragon.level == 1, "2d: dragon gains no xp (pet has no level line)")

	# ---- e) 解散小队：原队员击杀不再分账 ----
	hero.release_squad()
	_check(not hero.squad.has(sa) and sa.follow_leader == null, "2e: squad released")
	_kill_dummy(spawner, sa, Vector3(-44.0, 0.0, -40.0))
	_check(sa.xp == 30, "2e: killer keeps full xp after release (20+10=30, got %d)" % sa.xp)
	_check(sb.xp == 15 and hero.xp == 20, "2e: released squad no longer shares")
	dragon.queue_free()
	sa.queue_free()
	sb.queue_free()
	solo.queue_free()
	await get_tree().physics_frame

	# ================= 3. 回城疗伤 =================
	hero.global_position = in_city
	var hp0: float = hero.health.current_hp
	hero.health.apply_damage(140.0, null)
	_check(hero.health.current_hp < hp0 - 120.0, "3: hero damaged for the regen checks")
	# a) 白天 + 城内 → 缓慢回血（≈2/s）
	var healed_a: float = await _regain(hero, 1.0)
	_check(healed_a >= 1.2 and healed_a <= 3.2,
		"3a: hero regens ~2/s inside town by day (%.2f)" % healed_a)
	# b) 城外 → 不回
	hero.global_position = Vector3(half + 40.0, 0.0, 0.0)
	hero.health.apply_damage(60.0, null)
	var healed_b: float = await _regain(hero, 1.0)
	_check(healed_b < 0.2, "3b: no regen outside town (%.2f)" % healed_b)
	# c) 夜晚（22:00，守城期）→ 城内也不回
	TimeManager.begin(22)
	await get_tree().physics_frame
	hero.global_position = in_city
	hero.health.apply_damage(60.0, null)
	var healed_c: float = await _regain(hero, 1.0)
	_check(healed_c < 0.2, "3c: no regen at night defense even inside town (%.2f)" % healed_c)
	# d) 跳回白天 → 原地恢复回血
	TimeManager.begin(9)
	await get_tree().physics_frame
	var healed_d: float = await _regain(hero, 1.0)
	_check(healed_d >= 1.2 and healed_d <= 3.2,
		"3d: hero regen resumes at daybreak (%.2f)" % healed_d)
	# e) 巨龙同规则（≈4/s，夜晚不回）
	var pet: DragonPet = spawner.call("spawn_dragon", GameDefs.dragon_def(&"dragon_obsidian"),
		Vector3(half * 0.5, 0.0, -half * 0.5))
	await get_tree().physics_frame
	pet.health.apply_damage(150.0, null)
	var healed_e: float = await _regain(pet, 1.0)
	_check(healed_e >= 2.5 and healed_e <= 5.5,
		"3e: dragon regens ~4/s inside town by day (%.2f)" % healed_e)
	TimeManager.begin(22)
	await get_tree().physics_frame
	pet.health.apply_damage(80.0, null)
	var healed_f: float = await _regain(pet, 1.0)
	_check(healed_f < 0.2, "3e: no dragon regen at night defense (%.2f)" % healed_f)
	pet.queue_free()

	# ================= 收尾 =================
	await get_tree().physics_frame
	print("RESULT: ", "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 工具 ----

## 造一只「木桩野怪」并让 killer 当场处决（apply_damage 归属 → enemy_died 同步广播）。
## 经验量沿用掠夺者默认 xp_value=10；同步处决避免士兵 AI 抢怪干扰归属断言。
func _kill_dummy(spawner: Node, killer: Node, at: Vector3) -> void:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 30.0
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	d.defense = 0.0
	d.crit_rate = 0.0
	var dummy: Pawn = spawner.call("spawn_raider", at, d)
	dummy.health.apply_damage(999.0, killer)


func _find_hero() -> Hero:
	for p in get_tree().get_nodes_in_group("player_unit"):
		if p is Hero and is_instance_valid(p):
			return p
	return null


## 等待 seconds 真实秒后返回单位回血量（受 Engine.time_scale 影响，测试全程 1×）。
func _regain(unit: Pawn, seconds: float) -> float:
	var before: float = unit.health.current_hp
	await get_tree().create_timer(seconds).timeout
	return unit.health.current_hp - before
