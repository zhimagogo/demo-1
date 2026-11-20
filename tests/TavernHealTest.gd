extends Node
## ============================================================================
## v22 酒馆疗伤专项回归：
##   godot --headless --path . tests/TavernHealTest.tscn --log-file /private/tmp/a-tavern.log --fixed-fps 60
##
## 需求覆盖（金币经济 + 酒馆 + 采集屏蔽 + 赏金提升）：
##   0. 数据契约：建筑表 = 木墙/房屋/酒馆三种、造价纯金币；采集开关关闭；
##      开局资源纯金币；野怪赏金 10/45/200。
##   A. 酒馆光环：馆旁小兵快速回血（≥ heal_per_sec 的主体速率），
##      远离酒馆的对照小兵几乎不回血（城外无 regen）。
##   B. 低血回馆（<20%）：城外小兵自动放下巡逻、healing_trip 锁定酒馆、
##      行程中不自动接战；进圈后在馆旁休整，回满（≥95%）后解除行程恢复正常生活。
##   C. 战斗中低血撤退：fight 态 HP<20% 且场上有酒馆 → 立即脱战。
##   D. 无酒馆回落：低血小兵走旧的「回城休整」路径，healing_trip 保持 null。
##   E. 击杀掉落：enemy_died → CombatSystem 生成金币 LootDrop，金额 = def.loot_gold。
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
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	# 测试期停刷野怪 / 流民并清场：行为必须确定性
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
	# 白天固定（避免昼夜路由干扰）；补金币供测试建造
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	ResourceManager.add(GameDefs.GOLD, 1000)
	await get_tree().physics_frame

	# ================= 0. 数据契约 =================
	var ids: Array = []
	var tavern_def: BuildingDef
	var gold_only := true
	for d in GameDefs.building_defs():
		ids.append(d.id)
		if d.id == &"tavern":
			tavern_def = d
		for rid in d.cost:
			if rid != GameDefs.GOLD:
				gold_only = false
	_check(ids.size() == 5 and ids.has(&"dirt_road") and ids.has(&"wall") and ids.has(&"house") and ids.has(&"tavern")
			and ids.has(&"dragon_garden"),
		"建筑表包含木墙 / 房屋 / 酒馆 / 龙园 / 土路 (%s)" % str(ids))
	_check(not ids.has(&"farm") and not ids.has(&"market") and not ids.has(&"turret"),
		"farm/market/turret removed from building defs")
	_check(gold_only, "all building costs are gold-only")
	_check(tavern_def != null and tavern_def.is_tavern and tavern_def.heal_radius > 0.0
			and tavern_def.heal_per_sec >= 15.0, "tavern def carries heal aura params")
	_check(not GameDefs.HARVEST_INCOME_ENABLED, "harvest income disabled")
	var starting := GameDefs.starting_resources()
	_check(starting.size() == 1 and starting.has(GameDefs.GOLD), "starting resources are gold-only")
	_check(GameDefs.raider_def().loot_gold == 10 and GameDefs.raider_elite_def().loot_gold == 45
			and GameDefs.raider_boss_def().loot_gold == 200, "monster bounties raised (10/45/200)")

	# ================= A. 酒馆光环回血 =================
	var build := world.get_node("BuildSystem") as BuildSystem
	build.enter_build_mode(tavern_def)
	build.try_place_at(Vector3(8.0, 0.0, -4.0))
	build.exit_build_mode()
	await get_tree().physics_frame
	var taverns := get_tree().get_nodes_in_group("tavern")
	_check(taverns.size() == 1, "placed tavern registers in tavern group")
	var tavern: Building = taverns[0] if not taverns.is_empty() else null
	if tavern != null:
		var near: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(11.0, 0.0, -1.0))
		var far: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(30.0, 0.0, 30.0))
		await get_tree().physics_frame
		near.health.current_hp = 60.0
		far.health.current_hp = 60.0
		# 摆好位后钉在 rest 态（msg.at = 原地），消除巡逻路由干扰，纯量光环速率
		near.state_machine.transition_to("rest", {"at": near.global_position})
		far.state_machine.transition_to("rest", {"at": far.global_position})
		var near_d := near.global_position.distance_to(tavern.global_position)
		var far_d := far.global_position.distance_to(tavern.global_position)
		_check(near_d <= tavern_def.heal_radius and far_d > tavern_def.heal_radius,
			"control positions straddle heal radius (%.1fm / %.1fm)" % [near_d, far_d])
		for _i in 60:
			await get_tree().physics_frame
		var near_gain: float = near.health.current_hp - 60.0
		var far_gain: float = far.health.current_hp - 60.0
		_check(near_gain >= 15.0, "tavern aura heals nearby soldier (%.1f hp in 1s)" % near_gain)
		_check(far_gain <= 5.0, "soldier beyond radius barely heals (%.1f hp in 1s)" % far_gain)
		near.queue_free()
		far.queue_free()
		await get_tree().physics_frame

	# ================= B. 低血回馆（城外 <20% 触发 → 回馆休整 → 满血出院） =================
	if tavern != null and is_instance_valid(tavern):
		var s: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(34.0, 0.0, 34.0))
		await get_tree().physics_frame
		s.health.current_hp = s.health.max_hp * 0.1    # 10% < 20% 触发线
		s.state_machine.transition_to("idle")           # 手动喂路由入口（等待步正常路径）
		await get_tree().physics_frame
		await get_tree().physics_frame
		var soldier_b := s as Soldier
		_check(soldier_b.healing_trip == tavern and soldier_b.state_machine.current_state.name == "move",
			"low-hp outsider locks tavern trip and heads back (state=%s, trip=%s)" % [
				soldier_b.state_machine.current_state.name,
				"yes" if soldier_b.healing_trip != null else "null"])
		_check(not soldier_b.autofight_enabled(), "no auto-engage while on healing trip")
		# 瞬移到馆旁（真实行军太慢），再喂路由 → 应转入馆旁休整
		s.global_position = tavern.global_position + Vector3(4.0, 0.0, 0.0)
		s.state_machine.transition_to("idle")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(soldier_b.state_machine.current_state.name == "rest",
			"arriving soldier rests beside tavern (state=%s)" % soldier_b.state_machine.current_state.name)
		# 光环 20/s + 城内 regen：10% → ≥95% 约需 6s，给 12s 余量
		var healed := false
		for _i in 720:
			await get_tree().physics_frame
			if s.health.ratio() >= Soldier.TAVERN_EXIT_RATIO and soldier_b.healing_trip == null:
				healed = true
				break
		_check(healed, "soldier heals past exit ratio and clears healing trip")
		_check(soldier_b.healing_trip == null, "healing trip cleared after full recovery")
		s.queue_free()
		await get_tree().physics_frame

	# ================= C. 战斗中低血撤退 =================
	if tavern != null and is_instance_valid(tavern):
		var w: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(20.0, 0.0, 20.0))
		var dummy: Pawn = (spawner as Node).call("spawn_raider", Vector3(22.0, 0.0, 20.0), GameDefs.raider_def())
		await get_tree().physics_frame
		await get_tree().physics_frame
		w.state_machine.transition_to("fight", {"target": dummy})
		await get_tree().physics_frame
		_check(w.state_machine.current_state.name == "fight", "soldier engaged with dummy first")
		w.health.current_hp = w.health.max_hp * 0.1
		var disengaged := false
		for _i in 60:
			await get_tree().physics_frame
			if w.state_machine.current_state.name != "fight":
				disengaged = true
				break
		_check(disengaged, "soldier breaks off fight at <20% hp with tavern present")
		for _i in 3:
			await get_tree().physics_frame   # idle 路由在下一物理帧写入 healing_trip
		_check((w as Soldier).healing_trip == tavern, "fight break-off routes into tavern trip")
		w.queue_free()
		dummy.queue_free()
		await get_tree().physics_frame

	# ================= D. 无酒馆回落旧行为 =================
	if tavern != null and is_instance_valid(tavern):
		tavern.health.apply_damage(99999.0)   # 拆馆
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(get_tree().get_nodes_in_group("tavern").is_empty(), "tavern destroyed leaves group")
		var s2: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(34.0, 0.0, 34.0))
		await get_tree().physics_frame
		s2.health.current_hp = s2.health.max_hp * 0.1
		s2.state_machine.transition_to("idle")
		await get_tree().physics_frame
		await get_tree().physics_frame
		var st: String = s2.state_machine.current_state.name
		_check((s2 as Soldier).healing_trip == null and (st == "move" or st == "rest"),
			"without tavern low-hp soldier falls back to city rest (state=%s, trip=null)" % st)
		s2.queue_free()
		await get_tree().physics_frame

	# ================= E. 击杀掉落金币（爆币拆分：1~3 份，总额 = 赏金） =================
	# 注意：loot_drops 组的成员是容器节点，金币包是它的子节点——按容器子节点数计量。
	var victim: Pawn = (spawner as Node).call("spawn_raider", Vector3(26.0, 0.0, 26.0), GameDefs.raider_def())
	await get_tree().physics_frame
	var loot_container := get_tree().get_first_node_in_group("loot_drops") as Node
	var loot_before: int = loot_container.get_child_count() if loot_container != null else 0
	EventBus.enemy_died.emit(victim, hero)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var new_count: int = (loot_container.get_child_count() if loot_container != null else 0) - loot_before
	var gold_sum := 0
	if loot_container != null:
		for i in new_count:
			gold_sum += (loot_container.get_child(loot_before + i) as LootDrop).amount
	_check(new_count >= 1 and new_count <= 3, "kill bursts 1-3 coin drops (%d)" % new_count)
	_check(gold_sum == 10, "burst coins sum to raised bounty (gold x%d)" % gold_sum)
	victim.queue_free()

	print("TAVERN HEAL: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
