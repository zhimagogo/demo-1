extends Node
## ============================================================================
## v23 金币「爆出」掉落专项回归：
##   godot --headless --path . tests/LootBurstTest.tscn --log-file /tmp/loot.log --fixed-fps 60
##
## 需求覆盖（怪物死亡金币「爆出来」+ 抛物线弹跳 + 停留后磁吸 + 多份拆分 + 无缩小）：
##   0. 拆分契约：总金额不变地拆成 N 份（向下均分 + 余数逐份 +1），每份 ≥1。
##   1. 普通怪随机爆 1~3 份，单次总额 == def.loot_gold。
##   2. 抛物线弹跳：明显抛物弧（峰值 0.55~1.35m）→ 带姿态落停（最低下沿贴地 0~0.06，
##      不穿地不悬浮，慢速自转中下沿恒定），全场水平散布 ≤ 3.0m（「距离不要太远」）。
##   3. 停留后自动磁吸：主角站在 6m 外不动，金币停留 1.5s 后主动飞向主角并入账（金额精确，
##      且结算时刻晚于停留时长下限，防止「落地即吸」）。
##   3b. 硬保护窗口：玩家就站在金币堆上，落地 1.5s 内不得被贴身直捡提前吃掉（先看动画再结算）。
##   4. 拾取不缩小：金币根节点 scale 全程恒为 1（旧版拾取缩小动画已删），结算即消失。
##   5. 头目爆 5~8 份，总额 == 头目赏金。
##   6. 吸附目标只认玩家与小兵：旁边只有村民时金币不被吸走；小兵到场即被吸走入账。
##
## 输出保持 ASCII（headless 日志中文会乱码）；命令直接调 API，不依赖真实输入。
## ============================================================================

var _failures: int = 0
var _main: Node
var _hero: Hero = null


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _gold() -> int:
	return ResourceManager.get_amount(&"gold")


## 在指定位置生成一只野怪并立即击杀（killer=主角），返回出生后位置。
func _kill_raider(at: Vector3, def: PawnDef = null) -> Vector3:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var raider: Raider = spawner.call("spawn_raider", at, def)
	await get_tree().physics_frame
	var pos: Vector3 = raider.global_position
	raider.health.apply_damage(99999.0, _hero)
	return pos


## 收集掉落点附近（半径内）当前存在的金币节点（金币出生簇 ≤0.3m，先于移动前快照）。
func _coins_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var container := get_tree().get_first_node_in_group("loot_drops")
	if container == null:
		return out
	for drop in container.get_children():
		if not is_instance_valid(drop) or not (drop is Node3D):
			continue
		if (drop as Node3D).global_position.distance_to(pos) <= radius:
			out.append(drop)
	return out


func _sum_amounts(coins: Array) -> int:
	var total := 0
	for c in coins:
		total += int(c.get("amount"))
	return total


## 清空场上全部遗留金币（小节隔离：遗留币会被后序的玩家/小兵磁吸收走，污染金额断言）。
func _clear_loot() -> void:
	var container := get_tree().get_first_node_in_group("loot_drops")
	if container != null:
		for drop in container.get_children():
			if is_instance_valid(drop):
				drop.free()
	await _wait_frames(2)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	# 测试期停刷野怪 / 流民，清空既有敌人：掉落数量必须确定性
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
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			_hero = n
	_check(_hero != null, "hero exists")
	if _hero == null:
		_finish()
		return
	# 默认把主角拖到远处：需要「无人认领」的场景（后续按节再挪回）
	_hero.global_position = Vector3(-30.0, 0.0, -30.0)
	await _wait_frames(2)

	# ================= 0. 拆分契约：总额不变 =================
	var combat := get_tree().get_first_node_in_group("combat_system")
	for case in [[10, 3], [200, 7], [10, 1], [45, 3], [200, 5]]:
		var shares: Array = combat._split_bounty(int(case[0]), int(case[1]))
		var total := 0
		var min_share := 1 << 30
		for s in shares:
			total += int(s)
			min_share = mini(min_share, int(s))
		_check(total == int(case[0]) and shares.size() == int(case[1]) and min_share >= 1,
			"split %d into %d keeps total (got %s)" % [case[0], case[1], str(shares)])

	# ================= 1. 普通怪随机爆 1~3 份，总额不变 =================
	var normal_def: PawnDef = GameDefs.raider_def()
	var normal_bounty: int = normal_def.loot_gold
	var counts_seen: Array = []
	for i in 5:
		var death_pos: Vector3 = await _kill_raider(Vector3(20.0 + i * 6.0, 0.0, 8.0), normal_def)
		var coins := _coins_near(death_pos, 1.5)
		counts_seen.append(coins.size())
		_check(coins.size() >= 1 and coins.size() <= 3,
			"kill #%d bursts 1~3 coins (got %d)" % [i + 1, coins.size()])
		_check(_sum_amounts(coins) == normal_bounty,
			"kill #%d total preserved (%d == %d)" % [i + 1, _sum_amounts(coins), normal_bounty])
		await _wait_frames(2)

	# ================= 2. 抛物线弹跳 + 距离约束 =================
	var fly_pos: Vector3 = await _kill_raider(Vector3(30.0, 0.0, 30.0), normal_def)
	var fly_coins := _coins_near(fly_pos, 1.5)
	var rec := {}
	for c in fly_coins:
		rec[c.get_instance_id()] = {"coin": c, "peak": 0.0}
	for _i in 85:
		await get_tree().physics_frame
		for id in rec:
			var r: Dictionary = rec[id]
			if is_instance_valid(r["coin"]):
				r["peak"] = maxf(r["peak"], (r["coin"] as Node3D).global_position.y)
	var all_ok := true
	for id in rec:
		var r: Dictionary = rec[id]
		var c = r["coin"]
		if not is_instance_valid(c):
			all_ok = false
			continue
		var final_pos: Vector3 = (c as Node3D).global_position
		var spread := Vector2(final_pos.x - fly_pos.x, final_pos.z - fly_pos.z).length()
		if float(r["peak"]) < 0.55 or float(r["peak"]) > 1.35:
			all_ok = false
		# 防穿模契约：停驻金币最低下沿必须在地面上方（允许 5mm 浮点容差）且贴近地面（不悬浮）
		var bottom: float = (c as Node3D).call("bottom_height")
		if bottom < -0.005 or bottom > 0.06:
			all_ok = false
		if spread > 3.0:
			all_ok = false
	_check(all_ok and not rec.is_empty(),
		"coins arc up (peak 0.55~1.35m), rest tilted snug on ground (bottom 0~0.06, no clipping) and stay within 3.0m")

	# ================= 5. 头目爆 5~8 份，总额不变 =================
	await _clear_loot()
	var boss_def: PawnDef = GameDefs.raider_boss_def()
	var boss_pos: Vector3 = await _kill_raider(Vector3(30.0, 0.0, 44.0), boss_def)
	var boss_coins := _coins_near(boss_pos, 1.5)
	_check(boss_coins.size() >= 5 and boss_coins.size() <= 8,
		"boss bursts 5~8 coins (got %d)" % boss_coins.size())
	_check(_sum_amounts(boss_coins) == boss_def.loot_gold,
		"boss total preserved (%d == %d)" % [_sum_amounts(boss_coins), boss_def.loot_gold])

	# ================= 6a. 村民不抢金币（吸附只认玩家/小兵） =================
	await _clear_loot()
	var col_pos: Vector3 = await _kill_raider(Vector3(20.0, 0.0, 30.0), normal_def)
	spawner.call("spawn_colonist", col_pos + Vector3(0.8, 0.0, 0.0))
	await _wait_frames(2)
	var villager_coins := _coins_near(col_pos, 1.5)
	_check(not villager_coins.is_empty(), "villager scenario has coins to observe")
	await _wait_frames(210)   # 3.5s：远超停留时长，村民一直站在旁边
	var villager_kept := true
	for c in villager_coins:
		if not is_instance_valid(c) or c.get("_collected") == true:
			villager_kept = false
	_check(villager_kept, "coins ignore villagers (stay put with only a colonist nearby)")

	# ================= 6b. 附近最近的小兵会被吸走 =================
	var gold_before: int = _gold()
	spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), col_pos + Vector3(1.2, 0.0, 0.0))
	var soldier_frames: int = await _wait_all_collected(villager_coins, 480)
	_check(soldier_frames >= 0, "coins magnet to nearby soldier")
	_check(_gold() - gold_before == normal_bounty,
		"soldier pickup credits exact bounty (%d)" % (_gold() - gold_before))

	# ================= 3. 停留后磁吸主角（主角不动，6m 外防贴身直捡） =================
	await _clear_loot()
	_hero.global_position = Vector3(36.0, 0.0, 26.0)
	await _wait_frames(2)
	var hero_pos: Vector3 = await _kill_raider(Vector3(30.0, 0.0, 26.0), normal_def)
	await _wait_frames(2)
	gold_before = _gold()
	var hero_coins := _coins_near(hero_pos, 1.5)
	var hero_frames: int = await _wait_all_collected(hero_coins, 480)
	_check(hero_frames >= 0, "coins magnet to standing hero 6m away")
	_check(hero_frames >= 130,
		"coins rest ~1.5s before homing (collected after %.2fs >= 2.17s)" % (hero_frames / 60.0))
	_check(_gold() - gold_before == normal_bounty,
		"hero pickup credits exact bounty (%d)" % (_gold() - gold_before))

	# ================= 3b. 硬保护窗口：站在金币堆上也必须等满 1.5s =================
	# 复现：玩家就站在掉落点，旧版贴身直捡会在落地瞬间吃掉金币、看不到弹跳动画。
	await _clear_loot()
	_hero.global_position = Vector3(32.0, 0.0, 34.0)   # 主角就站在爆点上
	await _wait_frames(2)
	var at_pos: Vector3 = await _kill_raider(_hero.global_position, normal_def)
	await _wait_frames(2)
	var at_coins := _coins_near(at_pos, 1.5)
	_check(not at_coins.is_empty(), "at-hero scenario has coins to observe")
	await _wait_frames(60)   # 1.0s：仍在硬保护窗口内（落地约 0.5~0.9s + 剩余停留）
	var still_resting := true
	for c in at_coins:
		if not is_instance_valid(c) or c.get("_collected") == true:
			still_resting = false
	_check(still_resting, "coins survive full 1.5s window even with hero standing on them (no early eat)")
	var at_frames: int = await _wait_all_collected(at_coins, 480)
	_check(at_frames >= 0, "coins eventually collected after window (hero on pile)")
	# 理论最短 = 最短滞空 0.45s + 停留 1.5s ≈ 1.95s；卡 1.8s 下限（旧行为落地即吃 ~0.03s 必挂）
	_check(at_frames + 62 >= 108,
		"at-pile collection happens no earlier than rest window (%.2fs >= 1.8s)" % ((at_frames + 62) / 60.0))

	# ================= 4. 拾取不缩小（根 scale 恒 1，结算即消失） =================
	await _clear_loot()
	var ns_pos: Vector3 = await _kill_raider(Vector3(40.0, 0.0, 26.0), normal_def)
	await _wait_frames(2)
	var shrink_coins := _coins_near(ns_pos, 1.5)
	var min_root_scale := 10.0
	var all_freed := false
	for _i in 480:
		await get_tree().physics_frame
		var live := 0
		for c in shrink_coins:
			if is_instance_valid(c):
				live += 1
				min_root_scale = minf(min_root_scale, (c as Node3D).scale.x)
		if live == 0:
			all_freed = true
			break
	_check(all_freed, "coins free immediately on collect (no lingering shrink tween)")
	_check(min_root_scale >= 0.95,
		"root scale never shrinks during life (min=%.2f)" % min_root_scale)

	_finish()


## 等待快照里的金币全部被结算消失（磁吸/直捡任一路径），返回经过的物理帧数（-1 = 超时未收完）。
func _wait_all_collected(coins: Array, max_frames: int) -> int:
	for i in max_frames:
		await get_tree().physics_frame
		var live := 0
		for c in coins:
			if is_instance_valid(c) and c.get("_collected") != true:
				live += 1
		if live == 0:
			return i + 1
	return -1


func _finish() -> void:
	print("LOOT BURST TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
