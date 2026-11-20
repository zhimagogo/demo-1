extends Node
## ============================================================================
## v20 小兵属性系统专项回归：
##   godot --headless --path . tests/PawnStatsTest.tscn --log-file /private/tmp/a-stats.log --fixed-fps 60
##
## 需求覆盖（六维：等级/经验 + 血量 + 攻击 + 防御 + 移速 + 暴击率）：
##   0. 数据契约：六种小兵（兵营近战/远程 + 定居四职业）各按风格配防御/暴击基础值、
##      开启 can_level；主角/村民/流民/野怪不参与小兵成长线。
##   1. 出生基础值：level=1 时六维 == def 基础值（不偏移）。
##   2. 击杀得经验：真实击杀链（apply_damage 归属 → enemy_died → Soldier 结算入账）。
##   3. 升级成长：gain_xp 跨过阈值 → 六维按成长曲线重算 + 血量差补入 + pawn_leveled 广播；
##      一次大额经验连升多级并封顶（Lv.MAX，经验清零不再累积）。
##   4. 防御减伤：受伤 × K/(K+防御)，高防御保底 1 点；防御 0 的单位不受影响。
##   5. 暴击：crit_stat=1 必暴击（近战即时伤害 / 远程投射物均按暴击倍率放大并带标记），
##      crit_stat=0 永不暴击。
##   6. 主角回归：Hero 复用 Pawn 的 level/xp/gain_xp 管线，但曲线与升级结算保持
##      自己的旧契约（60/100/…、+30 血回满、damage_mult）。
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
	# 测试期停刷野怪 / 流民，清空既有敌人：属性行为必须确定性
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

	# ================= 0. 数据契约：六维按兵种风格分配 =================
	# v21：兵营「近战兵/远程兵」已删除，小兵 = 流民定居觉醒的四职业
	var warrior_d := GameDefs.settler_warrior_def()
	var mage_d := GameDefs.settler_mage_def()
	var assassin_d := GameDefs.settler_assassin_def()
	var archer_d := GameDefs.settler_archer_def()
	var soldier_defs := [warrior_d, mage_d, assassin_d, archer_d]
	for d in soldier_defs:
		_check(d.can_level, "%s participates in the level system" % d.id)
		_check(d.defense > 0.0 and d.crit_rate > 0.0 and d.crit_rate <= Pawn.CRIT_CAP,
			"%s has styled defense (%.0f) and crit (%.0f%%)"
			% [d.id, d.defense, d.crit_rate * 100.0])
		_check(d.max_hp > 0.0 and d.attack_damage > 0.0 and d.move_speed > 0.0,
			"%s has positive hp/attack/speed base values" % d.id)
	# 风格分化：战士防御全职业最高（重装）；法师单发攻击最高（玻璃大炮）；
	# 刺客暴击率最高（暴击流）；游侠移速最快（灵巧射手）
	var max_def_owner: PawnDef = warrior_d
	var max_atk_owner: PawnDef = mage_d
	var max_crit_owner: PawnDef = assassin_d
	var max_spd_owner: PawnDef = archer_d
	for d in soldier_defs:
		if d.defense > max_def_owner.defense:
			max_def_owner = d
		if d.attack_damage > max_atk_owner.attack_damage:
			max_atk_owner = d
		if d.crit_rate > max_crit_owner.crit_rate:
			max_crit_owner = d
		if d.move_speed > max_spd_owner.move_speed:
			max_spd_owner = d
	_check(max_def_owner == warrior_d, "warrior owns the highest defense (%.0f)" % warrior_d.defense)
	_check(max_atk_owner == mage_d, "mage owns the highest attack (%.0f)" % mage_d.attack_damage)
	_check(max_crit_owner == assassin_d, "assassin owns the highest crit (%.0f%%)" % [assassin_d.crit_rate * 100.0])
	_check(max_spd_owner == archer_d, "ranger owns the highest move speed (%.2f)" % archer_d.move_speed)
	# 非小兵不走成长线：主角 / 村民 / 流民 / 野怪 can_level=false（主角有自己的成长线）
	for d in [GameDefs.hero_warrior_def(), GameDefs.colonist_def(), GameDefs.refugee_def(), GameDefs.raider_def()]:
		_check(not d.can_level, "%s stays out of the minion level system" % d.id)
	# v20.3 怪物六维契约：三档怪物接入防御/暴击，档位随威胁递增；
	# 战士仍是全场防御标杆（28 > 头目 20），「小兵比怪更能扛」的身份不倒。
	var raider_d := GameDefs.raider_def()
	var elite_d := GameDefs.raider_elite_def()
	var boss_d := GameDefs.raider_boss_def()
	_check(raider_d.defense < elite_d.defense and elite_d.defense < boss_d.defense,
		"monster defense tiers up with threat (%.0f < %.0f < %.0f)"
		% [raider_d.defense, elite_d.defense, boss_d.defense])
	_check(boss_d.crit_rate > elite_d.crit_rate and elite_d.crit_rate > raider_d.crit_rate,
		"monster crit tiers up with threat (%.0f%% / %.0f%% / %.0f%%)"
		% [raider_d.crit_rate * 100.0, elite_d.crit_rate * 100.0, boss_d.crit_rate * 100.0])
	_check(warrior_d.defense > boss_d.defense,
		"warrior remains the defense benchmark above the boss (%.0f > %.0f)"
		% [warrior_d.defense, boss_d.defense])
	_check(raider_d.xp_value < elite_d.xp_value and elite_d.xp_value < boss_d.xp_value,
		"monster xp tiers up (kill rewards %d/%d/%d)"
		% [raider_d.xp_value, elite_d.xp_value, boss_d.xp_value])

	# ================= 1. 出生基础值（level=1 == def 基础值）=================
	var melee: Pawn = spawner.call("spawn_soldier", warrior_d, Vector3(24.0, 0.0, 24.0))
	await get_tree().physics_frame
	_check(melee.level == 1 and melee.xp == 0, "fresh soldier starts at Lv.1 with 0 xp")
	_check(is_equal_approx(melee.health.max_hp, warrior_d.max_hp),
		"base hp matches def (%.0f)" % melee.health.max_hp)
	_check(is_equal_approx(melee.attacker.damage, warrior_d.attack_damage),
		"base attack matches def (%.0f)" % melee.attacker.damage)
	_check(is_equal_approx(melee.move_speed, warrior_d.move_speed),
		"base move speed matches def (%.2f)" % melee.move_speed)
	_check(is_equal_approx(melee.defense_stat, warrior_d.defense),
		"base defense matches def (%.0f)" % melee.defense_stat)
	_check(is_equal_approx(melee.crit_chance(), warrior_d.crit_rate),
		"base crit matches def (%.0f%%)" % [melee.crit_chance() * 100.0])

	# ================= 2. 击杀得经验（真实击杀链）=================
	# 用远程游侠在远处打木桩：近战环形站位相位按 instance_id 取角，杀伤时序会随
	# 脚本编译布局漂移（v20 实锤）；远程走射程判定，不受站位相位影响、完全确定。
	# 与第 1 节的战士样本（25,25）隔开 60m+，互不卷入对方战斗（战士不进怒、面板干净）。
	var hunter: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(-25.0, 0.0, -25.0))
	await get_tree().physics_frame
	var dummy: Pawn = _spawn_dummy(spawner, Vector3(-25.0, 0.0, -31.0), 10.0)
	await get_tree().physics_frame
	hunter.assign_attack(dummy)
	var killed := await _wait_until(func(): return not is_instance_valid(dummy) or dummy.is_dead_flag, 300)
	_check(killed, "2: soldier kills the dummy via real combat chain")
	if killed:
		_check(hunter.xp == GameDefs.raider_def().xp_value,
			"2: killer gains the victim's xp_value (%d)" % hunter.xp)
		_check(hunter.level == 1, "2: xp below threshold keeps Lv.1")
	hunter.queue_free()
	await get_tree().physics_frame

	# ================= 3. 升级成长 + 封顶 =================
	# 保险：若样本战士意外进过战斗（血怒 ×1.5 面板），先等增益结束再量面板
	if melee.skill_comp != null:
		await _wait_until(func(): return not melee.skill_comp.is_raging(), 400)
	var leveled_events: Array = []
	EventBus.pawn_leveled.connect(func(p, lv): leveled_events.append([p, lv]))
	var hp_before: float = melee.health.current_hp
	var xp_need: int = melee.xp_to_next()
	melee.gain_xp(xp_need - melee.xp)   # 精确补到阈值
	_check(melee.level == 2 and melee.xp == 0, "3: crossing threshold levels up to Lv.2")
	_check(leveled_events.size() == 1 and leveled_events[0][0] == melee and leveled_events[0][1] == 2,
		"3: pawn_leveled broadcast with new level")
	# v24：成长倍率从 Pawn 常量推导（调参不再需要同步改测试）
	_check(is_equal_approx(melee.health.max_hp, warrior_d.max_hp * (1.0 + Pawn.GROWTH_HP)),
		"3: Lv.2 hp = base +%.0f%% (%.1f)" % [Pawn.GROWTH_HP * 100.0, melee.health.max_hp])
	_check(is_equal_approx(melee.attacker.damage, warrior_d.attack_damage * (1.0 + Pawn.GROWTH_ATTACK)),
		"3: Lv.2 attack = base +%.0f%% (%.2f)" % [Pawn.GROWTH_ATTACK * 100.0, melee.attacker.damage])
	_check(is_equal_approx(melee.move_speed, warrior_d.move_speed * (1.0 + Pawn.GROWTH_SPEED)),
		"3: Lv.2 speed = base +%.1f%% (%.3f)" % [Pawn.GROWTH_SPEED * 100.0, melee.move_speed])
	_check(is_equal_approx(melee.defense_stat, warrior_d.defense * (1.0 + Pawn.GROWTH_DEFENSE)),
		"3: Lv.2 defense = base +%.0f%% (%.1f)" % [Pawn.GROWTH_DEFENSE * 100.0, melee.defense_stat])
	_check(is_equal_approx(melee.crit_chance(), warrior_d.crit_rate + Pawn.GROWTH_CRIT),
		"3: Lv.2 crit = base +%.1f%% abs (%.3f)" % [Pawn.GROWTH_CRIT * 100.0, melee.crit_chance()])
	_check(melee.health.current_hp >= hp_before + (melee.health.max_hp - warrior_d.max_hp) - 0.01,
		"3: level-up hp gain fills the growth delta (%.1f -> %.1f)"
		% [hp_before, melee.health.current_hp])
	# 一次大额经验连升多级 → 封顶 Lv.MAX、经验清零
	melee.gain_xp(100000)
	_check(melee.level == Pawn.MAX_LEVEL, "3: huge xp caps at Lv.%d (now Lv.%d)" % [Pawn.MAX_LEVEL, melee.level])
	_check(melee.xp == 0, "3: xp is discarded at level cap")
	var lv9 := float(Pawn.MAX_LEVEL - 1)
	_check(is_equal_approx(melee.health.max_hp, warrior_d.max_hp * (1.0 + Pawn.GROWTH_HP * lv9)),
		"3: Lv.MAX hp = base x1.9 (%.1f)" % melee.health.max_hp)
	_check(is_equal_approx(melee.defense_stat, warrior_d.defense * (1.0 + Pawn.GROWTH_DEFENSE * lv9)),
		"3: Lv.MAX defense scales the same curve (%.1f)" % melee.defense_stat)
	melee.queue_free()
	await get_tree().physics_frame

	# ================= 4. 防御减伤 =================
	var tank: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-24.0, 0.0, 24.0))
	await get_tree().physics_frame
	var hp0: float = tank.health.current_hp
	tank.health.apply_damage(100.0, null)
	var loss: float = hp0 - tank.health.current_hp
	_check(is_equal_approx(loss, 100.0 * tank.defense_factor()),
		"4: damage reduced by defense factor (%.1f of 100, factor %.3f)" % [loss, tank.defense_factor()])
	_check(loss < 100.0 and loss > 50.0, "4: warrior tank mitigates a meaningful slice (defense %.0f)" % tank.defense_stat)
	# 保底 1 点：防御拉满也不无敌
	tank.defense_stat = 100000.0
	var hp1: float = tank.health.current_hp
	tank.health.apply_damage(100.0, null)
	_check(is_equal_approx(hp1 - tank.health.current_hp, 1.0),
		"4: floor of 1 damage prevents invincibility")
	tank.queue_free()
	# 防御 0 的单位（野怪）不吃减伤
	var dummy_b: Pawn = _spawn_dummy(spawner, Vector3(-24.0, 0.0, 30.0), 600.0)
	await get_tree().physics_frame
	var hp2: float = dummy_b.health.current_hp
	dummy_b.health.apply_damage(50.0, null)
	_check(is_equal_approx(hp2 - dummy_b.health.current_hp, 50.0),
		"4: zero-defense unit takes full damage")
	dummy_b.queue_free()
	await get_tree().physics_frame

	# ================= 5. 暴击 =================
	# 近战：必暴击（crit_stat=1）→ 伤害按暴击倍率放大。
	# 关掉自动索敌：冷却必须留给本节直接调用的 try_attack（避免状态机先出手消耗掉）。
	var stabber: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(30.0, 0.0, 24.0))
	stabber.is_auto_fighter = false
	await get_tree().physics_frame
	var dummy_c: Pawn = _spawn_dummy(spawner, Vector3(30.0, 0.0, 25.2), 600.0)
	await get_tree().physics_frame
	stabber.crit_stat = 1.0
	stabber.attacker._cooldown_left = 0.0
	var hp3: float = dummy_c.health.current_hp
	stabber.attacker.try_attack(dummy_c)
	var crit_loss: float = hp3 - dummy_c.health.current_hp
	_check(is_equal_approx(crit_loss, stabber.attacker.damage * stabber.crit_multiplier()),
		"5: forced crit multiplies melee damage x%.1f (%.1f)" % [stabber.crit_multiplier(), crit_loss])
	# 副手验证：暴击率 0 → 永不暴击（连打 12 次均为面板伤害）
	stabber.crit_stat = 0.0
	stabber.attacker._cooldown_left = 0.0
	var hp4: float = dummy_c.health.current_hp
	stabber.attacker.try_attack(dummy_c)
	_check(is_equal_approx(hp4 - dummy_c.health.current_hp, stabber.attacker.damage),
		"5: zero crit chance never crits (exact panel damage)")
	# 远程：暴击在发射瞬间定伤，投射物带 is_crit 标记（同样关自动索敌保住冷却）
	var sniper: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(-30.0, 0.0, -24.0))
	sniper.is_auto_fighter = false
	await get_tree().physics_frame
	var dummy_d: Pawn = _spawn_dummy(spawner, Vector3(-30.0, 0.0, -24.8), 600.0)
	await get_tree().physics_frame
	sniper.crit_stat = 1.0
	sniper.attacker._cooldown_left = 0.0
	sniper.attacker.try_attack(dummy_d)
	var crit_proj: Projectile = null
	for p in _projectiles():
		if p.source == sniper:
			crit_proj = p
			break
	_check(crit_proj != null and crit_proj.is_crit,
		"5: forced crit flags the projectile")
	if crit_proj != null:
		_check(is_equal_approx(crit_proj.damage, sniper.attacker.damage * sniper.crit_multiplier()),
			"5: projectile carries multiplied crit damage (%.1f)" % crit_proj.damage)
	stabber.queue_free()
	sniper.queue_free()
	dummy_c.queue_free()
	dummy_d.queue_free()
	await get_tree().physics_frame

	# ================= 6. 主角回归（复用管线但保持旧契约）=================
	var hero := _find_hero()
	_check(hero != null, "6: hero exists in main scene")
	if hero != null:
		_check(hero.level == 1 and hero.xp_to_next() == 60, "6: hero curve stays 60/100/...")
		var hero_hp0: float = hero.health.max_hp
		hero.gain_xp(60)
		_check(hero.level == 2 and hero.xp == 0, "6: hero levels up through the shared pipeline")
		_check(is_equal_approx(hero.health.max_hp, hero_hp0 + 30.0),
			"6: hero keeps flat +30 hp per level (%.0f)" % hero.health.max_hp)
		_check(is_equal_approx(hero.attacker.damage, hero.def.attack_damage * hero.damage_mult()),
			"6: hero attack still follows damage_mult (%.2f)" % hero.attacker.damage)
		_check(hero.xp_to_next() == 100, "6: hero next threshold is 100")

	# ================= 收尾 =================
	await get_tree().physics_frame
	print("RESULT: ", "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 工具 ----

## 造一只「木桩野怪」：低攻（别把小兵打死）、不死逃（flee=0）、血量可注入。
func _spawn_dummy(spawner: Node, at: Vector3, hp: float) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = hp
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	# v20.3 起怪物也有六维——木桩必须归零防御/暴击，伤害断言才能精确到点
	d.defense = 0.0
	d.crit_rate = 0.0
	return spawner.call("spawn_raider", at, d)


func _find_hero() -> Hero:
	for p in get_tree().get_nodes_in_group("player_unit"):
		if p is Hero and is_instance_valid(p):
			return p
	return null


func _projectiles() -> Array:
	var out: Array = []
	var container := get_tree().get_first_node_in_group("projectiles")
	if container == null:
		return out
	for c in container.get_children():
		if c is Projectile and is_instance_valid(c):
			out.append(c as Projectile)
	return out


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()
