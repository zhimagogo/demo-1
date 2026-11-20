extends Node
## ============================================================================
## v19 定居小兵职业技能专项回归：
##   godot --headless --path . tests/SettlerSkillTest.tscn --log-file /private/tmp/a-skill.log --fixed-fps 60
##
## 需求覆盖（四职业各一个技能，全部带 CD + 特效/显示）：
##   0. 数据契约：四职业技能定义齐全、CD > 0、类型正确；
##      游侠基础被动 = 移速比其他小怪快 25%（全职业最快）。
##   A. 法师 · 暴风雪：接战自动施放，生成暴风雪区域（指示圈 + 落雪粒子），
##      场内敌人逐跳掉血 + 减速（effective_move_speed 下降），CD 期间不可再施放，
##      场到期自动销毁。
##   B. 战士 · 血怒：接战自动施放，6s 内伤害面板 ×1.5，造成伤害按 60% 吸血，
##      有 RageAura 光环 + 头顶标记，到期后面板还原、吸血停止。
##   C. 游侠 · 快速射击：接战自动施放，三连金箭，目标挂 3s 易伤
##      （受伤 +30%：10 点实伤变 13），易伤到期自动解除。
##   D. 刺客 · 背刺：CD 就绪时先手释放——伤害首次落下时刺客上一帧还在 3m 外
##      （即瞬移先手而非走近普攻），落点在目标身后、贴身相邻、单次重伤 ≥ 30，
##      双向闪现环特效，CD 期间不可再施放。
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
	# 测试期停刷野怪 / 流民，清空既有敌人：技能行为必须确定性
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
	VFXManager.reset_stats()

	# ================= 0. 数据契约 + 游侠被动 =================
	var mage_def := GameDefs.settler_mage_def()
	var warrior_def := GameDefs.settler_warrior_def()
	var archer_def := GameDefs.settler_archer_def()
	var assassin_def := GameDefs.settler_assassin_def()
	for d in [mage_def, warrior_def, archer_def, assassin_def]:
		_check(d.skill != null and d.skill.cooldown > 0.0 and d.skill.display_name != "",
			"%s has a skill with positive cooldown" % d.id)
	_check(mage_def.skill.kind == PawnSkillDef.Kind.BLIZZARD, "mage skill kind = BLIZZARD")
	_check(warrior_def.skill.kind == PawnSkillDef.Kind.BLOOD_RAGE, "warrior skill kind = BLOOD_RAGE")
	_check(archer_def.skill.kind == PawnSkillDef.Kind.RAPID_SHOT, "archer skill kind = RAPID_SHOT")
	_check(assassin_def.skill.kind == PawnSkillDef.Kind.BACKSTAB, "assassin skill kind = BACKSTAB")
	_check(mage_def.skill.radius >= 4.0, "blizzard radius is clearly large (%.1fm)" % mage_def.skill.radius)
	_check(assassin_def.skill.cast_range > assassin_def.attack_range,
		"backstab reach (%.1fm) exceeds melee attack range (%.1fm)"
		% [assassin_def.skill.cast_range, assassin_def.attack_range])
	# 游侠基础被动：移速比其他小怪快 25%（对齐战士基准 4.0×1.25=5.0，且全职业最快）
	_check(archer_def.move_speed >= warrior_def.move_speed * 1.25,
		"ranger passive: move speed 25%% faster than baseline (%.2f >= %.2f)"
		% [archer_def.move_speed, warrior_def.move_speed * 1.25])
	_check(archer_def.move_speed > assassin_def.move_speed and archer_def.move_speed > mage_def.move_speed,
		"ranger passive: fastest of all settler classes (%.2f m/s)" % archer_def.move_speed)

	# ================= A. 法师 · 暴风雪 =================
	var mage: Pawn = _spawn_field_soldier(spawner, GameDefs.settler_mage_def(), Vector3(30.0, 0.0, 30.0))
	_unlock_class_skill(mage)
	var dummy_a: Pawn = _spawn_dummy(spawner, Vector3(30.0, 0.0, 22.0), 600.0)
	await get_tree().physics_frame
	var zone_spawned: bool = await _wait_until(func():
		return get_tree().get_first_node_in_group("skill_blizzard_zone") != null, 240)
	_check(zone_spawned, "A: mage casts blizzard on engage (zone spawned)")
	var zone := get_tree().get_first_node_in_group("skill_blizzard_zone") as SkillBlizzardZone
	if zone != null:
		var z := zone as SkillBlizzardZone
		var ring := z.get_node_or_null("GroundRing") as MeshInstance3D
		var snow := z.get_node_or_null("BlizzardSnow") as GPUParticles3D
		_check(ring != null and ring.visible, "A: blizzard ground ring visible (area indicator)")
		_check(snow != null and snow.emitting, "A: blizzard snowfall particles emitting")
	var slowed := await _wait_until(func(): return dummy_a.slow_active(), 180)
	_check(slowed, "A: enemy inside blizzard gets slowed")
	if slowed:
		_check(dummy_a.effective_move_speed() < dummy_a.move_speed,
			"A: slow reduces effective move speed (%.2f < %.2f)"
			% [dummy_a.effective_move_speed(), dummy_a.move_speed])
	var took_damage := await _wait_until(func(): return dummy_a.health.current_hp < dummy_a.health.max_hp, 180)
	_check(took_damage, "A: blizzard ticks damage the enemy")
	_check(mage.skill_comp != null and mage.skill_comp.cooldown_left() > 0.0,
		"A: blizzard enters cooldown after cast")
	_check(not mage.skill_comp.try_cast(dummy_a), "A: blizzard blocked while on cooldown")
	var zone_gone := await _wait_until(func():
		return get_tree().get_first_node_in_group("skill_blizzard_zone") == null, 320)
	_check(zone_gone, "A: blizzard zone auto-frees after duration")
	_cleanup(mage, dummy_a)

	# ================= B. 战士 · 血怒 =================
	var warrior: Pawn = _spawn_field_soldier(spawner, GameDefs.settler_warrior_def(), Vector3(-30.0, 0.0, 30.0))
	_unlock_class_skill(warrior)
	var dummy_b: Pawn = _spawn_dummy(spawner, Vector3(-30.0, 0.0, 27.0), 900.0)
	await get_tree().physics_frame
	var raging := await _wait_until(func(): return warrior.skill_comp.is_raging(), 240)
	_check(raging, "B: warrior enters blood rage on engage")
	if raging:
		var base_dmg: float = warrior_def.attack_damage
		_check(is_equal_approx(warrior.attacker.damage, base_dmg * 1.5),
			"B: rage raises attack panel x1.5 (%.1f -> %.1f)" % [base_dmg, warrior.attacker.damage])
		var aura := warrior.get_node_or_null("RageAura") as GPUParticles3D
		_check(aura != null and aura.emitting, "B: rage aura particles attached and emitting")
		var marks := warrior.get_node_or_null("BuffMarks3D") as BuffMarks3D
		_check(marks != null and marks.is_mark_visible(&"rage"), "B: rage status mark shown overhead")
		# 吸血：先打掉一半血，再模拟自己造成 20 点伤害 → 应回 12（60%）
		warrior.health.apply_damage(warrior.health.max_hp * 0.5, null)
		var hp_before: float = warrior.health.current_hp
		EventBus.damage_dealt.emit(dummy_b, 20.0, warrior)
		await get_tree().physics_frame
		_check(is_equal_approx(warrior.health.current_hp, hp_before + 12.0),
			"B: rage lifesteals 60%% of dealt damage (%.1f -> %.1f)"
			% [hp_before, warrior.health.current_hp])
	# 等怒气结束：面板还原、光环撤下、吸血停止
	var rage_over := await _wait_until(func(): return not warrior.skill_comp.is_raging(), 520)
	_check(rage_over, "B: blood rage expires after its duration")
	if rage_over:
		_check(is_equal_approx(warrior.attacker.damage, warrior_def.attack_damage),
			"B: attack panel restored after rage (%.1f)" % warrior.attacker.damage)
		_check(warrior.get_node_or_null("RageAura") == null, "B: rage aura freed after rage ends")
		var hp_before2: float = warrior.health.current_hp
		EventBus.damage_dealt.emit(dummy_b, 20.0, warrior)
		await get_tree().physics_frame
		_check(is_equal_approx(warrior.health.current_hp, hp_before2),
			"B: no lifesteal outside rage")
	_cleanup(warrior, dummy_b)

	# ================= C. 游侠 · 快速射击 =================
	var archer: Pawn = _spawn_field_soldier(spawner, GameDefs.settler_archer_def(), Vector3(-30.0, 0.0, -30.0))
	_unlock_class_skill(archer)
	var dummy_c: Pawn = _spawn_dummy(spawner, Vector3(-30.0, 0.0, -38.0), 600.0)
	await get_tree().physics_frame
	# 统计快速射击金箭（弹体金色 + 来源游侠；普攻弹体为职业档案淡黄色）
	var gold_ids: Dictionary = {}
	for _i in 150:
		for p in _projectiles():
			if p.source == archer and is_equal_approx(p.body_color.g, 0.85) \
					and p.body_color.b < 0.5 and p.body_color.r > 0.9:
				gold_ids[p.get_instance_id()] = true
		if dummy_c.vuln_active() and gold_ids.size() >= 3 and _i > 40:
			break
		await get_tree().physics_frame
	_check(gold_ids.size() >= 3, "C: rapid shot fires 3 golden arrows (%d seen)" % gold_ids.size())
	var vulned := await _wait_until(func(): return dummy_c.vuln_active(), 120)
	_check(vulned, "C: rapid shot applies vulnerability to the enemy")
	if vulned:
		_check(is_equal_approx(dummy_c.incoming_damage_mult(), 1.3),
			"C: vulnerability amplifies incoming damage x1.3")
		var hp_before: float = dummy_c.health.current_hp
		dummy_c.health.apply_damage(10.0, null)
		_check(is_equal_approx(hp_before - dummy_c.health.current_hp, 13.0),
			"C: 10 damage becomes 13 under vulnerability (%.1f dealt)"
			% [hp_before - dummy_c.health.current_hp])
		var vm := dummy_c.get_node_or_null("BuffMarks3D") as BuffMarks3D
		_check(vm != null and vm.is_mark_visible(&"vuln"), "C: vulnerability mark shown on enemy")
	_check(archer.skill_comp.cooldown_left() > 0.0, "C: rapid shot enters cooldown")
	var vuln_gone := await _wait_until(func(): return not dummy_c.vuln_active(), 300)
	_check(vuln_gone and is_equal_approx(dummy_c.incoming_damage_mult(), 1.0),
		"C: vulnerability expires after 3s")
	_cleanup(archer, dummy_c)

	# ================= D. 刺客 · 背刺 =================
	var assassin: Pawn = _spawn_field_soldier(spawner, GameDefs.settler_assassin_def(), Vector3(30.0, 0.0, -30.0))
	_unlock_class_skill(assassin)
	var dummy_d: Pawn = _spawn_dummy(spawner, Vector3(30.0, 0.0, -36.5), 600.0)
	await get_tree().physics_frame
	var spawn_dist: float = assassin.global_position.distance_to(dummy_d.global_position)
	# 逐帧监控：记录「伤害首次落下」前一帧的距离——先手背刺必须来自 3m 之外的瞬移
	var prev_dist: float = spawn_dist
	var first_drop: float = 0.0
	var hit_dist: float = -1.0
	var behind_dot: float = -9.0
	for _i in 240:
		var hp_now: float = dummy_d.health.current_hp
		if hp_now < dummy_d.health.max_hp:
			first_drop = dummy_d.health.max_hp - hp_now
			hit_dist = prev_dist
			var fwd: Vector3 = -dummy_d.global_transform.basis.z
			fwd.y = 0.0
			var rel: Vector3 = assassin.global_position - dummy_d.global_position
			rel.y = 0.0
			behind_dot = fwd.normalized().dot(rel.normalized()) if rel.length() > 0.001 else -9.0
			break
		prev_dist = assassin.global_position.distance_to(dummy_d.global_position)
		await get_tree().physics_frame
	_check(first_drop >= 30.0, "D: backstab lands heavy damage (%.0f)" % first_drop)
	_check(hit_dist > 3.0, "D: opener damage arrives from beyond melee reach (%.1fm = blink first)"
		% hit_dist)
	_check(assassin.global_position.distance_to(dummy_d.global_position) < 2.2,
		"D: assassin ends up adjacent behind the target (%.1fm)"
		% assassin.global_position.distance_to(dummy_d.global_position))
	_check(behind_dot > 0.0, "D: strike lands on the target's back side (dot=%.2f)" % behind_dot)
	_check(int(VFXManager.stat_spawned_by_id.get(&"blink_ring", 0)) >= 2,
		"D: blink rings spawned at departure and arrival")
	_check(assassin.skill_comp.cooldown_left() > 0.0, "D: backstab enters cooldown")
	_check(not assassin.skill_comp.try_cast(dummy_d), "D: backstab blocked while on cooldown")
	_cleanup(assassin, dummy_d)

	# ================= 收尾 =================
	await get_tree().physics_frame
	print("RESULT: ", "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 工具 ----

## 造一只「木桩野怪」：低攻（别把小兵打死）、不死逃（flee=0）、够血撑到断言完成。
## v25.1 职业技门禁：新兵需在技能树点亮「职业技」根节点才能施放技能——
## 直接发 1 点技能点点亮（不升级，六维面板不动，后续伤害断言不受影响）。
func _unlock_class_skill(pawn: Pawn) -> void:
	pawn.skill_points += 1
	if not pawn.try_invest_skill_point(&"class_skill"):
		push_error("FAIL: unlock class_skill node for %s" % str(pawn.def.id))

## v41 城内生活：小兵出生默认「在城里过日子」，城外的游荡怪不吸引他（会直接回城）。
## 本测试把兵摆在城外打木桩，需要显式关掉城内生活，让他进入巡逻 / 接战。
func _spawn_field_soldier(spawner: Node, def: PawnDef, at: Vector3) -> Pawn:
	var pawn: Pawn = spawner.call("spawn_soldier", def, at)
	pawn.town_life_active = false
	return pawn


func _spawn_dummy(spawner: Node, at: Vector3, hp: float) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = hp
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	# v20.3 起怪物也有六维——木桩必须归零防御/暴击，伤害断言才能精确到点
	d.defense = 0.0
	d.crit_rate = 0.0
	return spawner.call("spawn_raider", at, d)


func _projectiles() -> Array:
	var out: Array = []
	var container := get_tree().get_first_node_in_group("projectiles")
	if container == null:
		return out
	for c in container.get_children():
		if c is Projectile and is_instance_valid(c):
			out.append(c as Projectile)
	return out


func _cleanup(a: Node, b: Node) -> void:
	if a != null and is_instance_valid(a):
		a.queue_free()
	if b != null and is_instance_valid(b):
		b.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()
