extends Node
## ============================================================================
## v33 进阶职业技能专项回归（test-dev）：
##   bash tools/godot_locked.sh --headless --path . tests/AdvancedSkillTest.tscn \
##        --log-file /private/tmp/a-adv.log --fixed-fps 60
##
## 覆盖 docs/v33_skill_design.md 第 5 节（冻结契约）：
##   1. 数据契约：4 个新技能 def 的 id/kind/CD/关键参数；4 个进阶职业 all_skills()
##      长度 2 且含新技能；四棵进阶树 id 与 advanced_skill 节点；基础四职业仍 generic。
##   2. 技能门禁：未点 class_skill / advanced_skill 时 is_skill_unlocked() 为假、
##      公共施法入口不发；点亮后逐级解锁。
##   3. 转职返还：Lv.5 花掉 N 点后 promote_to() → 点数全额退回、节点归零、换进阶树、
##      skill_tree_changed 已广播、返还的点可重新分配。
##   4. 跳劈：前摇后落地，圈内多目标同帧 34 伤 + 击飞（is_controlled / 抬升 ≥1m /
##      水平位移 ≈ knockback_distance 3.2m / 控制时长 = 滞空 0.55s + 眩晕 1.1s），圈外零伤。
##   5. 陨石：吟唱无伤 → 落点锁定在吟唱开始位置 → 预警圈 → 圈内 55 高伤；
##      吟唱期走出圈的木桩无伤（躲避成立）。
##   6. 贯穿：同一直线上 3 个木桩各恰好一次 26 伤、线外木桩零伤、远靶 > 20m。
##   7. 隐身：is_stealthed / can_be_seen_by_enemies / model_rig.stealth_active /
##      敌方索敌扫不到 / 受击不破隐 / 造成伤害即刻破隐 / 到期自动解除。
##   8. 特效：14 个 v33 特效 id 全部注册且可生成（TRAIL 型走 attach_trail）。
##   9. 跑批回归：与 tools/run_all_tests.sh 同批复跑，记录见 docs/v33_acceptance.md。
##
## 约定：日志保持 ASCII（headless 中文会乱码）；退出码 = 失败数；
##       任何路径都会 quit——除正常收尾外，_process 看门狗兜底（脚本中途报错也不挂死跑批）。
## ============================================================================

const WATCHDOG_FRAMES: int = 60 * 300     # 300 游戏秒（--fixed-fps 60）后强制失败退出
const SECTIONS_EXPECTED: int = 8          # 已实现的用例分节数（1~3 数据/门禁/返还 + 4~8 技能/特效）

var _failures: int = 0
var _main: Node
var _frames: int = 0
var _finished: bool = false
var _sections: Array[String] = []
var _hits: Array = []                     # 伤害结算流水（区分技能伤害与普攻：按 amount 精确匹配）
var _record_hits: bool = false


func _ready() -> void:
	call_deferred("_run")


## 看门狗：脚本任何一段报错都不会让场景失去 quit 路径（否则会挂死整批跑批）。
func _process(_delta: float) -> void:
	if _finished:
		return
	_frames += 1
	if _frames > WATCHDOG_FRAMES:
		_finished = true
		push_error("FAIL: watchdog timeout after %d frames" % WATCHDOG_FRAMES)
		print("RESULT: 1 FAILURES (watchdog)")
		get_tree().quit(1)


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
		wildlife.set_physics_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	TimeManager.set_speed(1.0)
	VFXManager.reset_stats()
	_check(spawner != null, "main scene ready (pawn_spawner found)")

	# 伤害结算记录器：按 amount 精确区分「技能伤害」与普攻（普攻数值与技能不同），
	# 这样即使施法者随后恢复自动接战也不会污染「恰好 55 / 恰好 26」的断言。
	var on_damage := func(target: Node, amount: float, source: Node) -> void:
		if not _record_hits:
			return
		var tid := 0
		if is_instance_valid(target):
			tid = target.get_instance_id()
		var sid := 0
		if source != null and is_instance_valid(source):
			sid = source.get_instance_id()
		_hits.append({"tid": tid, "amount": amount, "sid": sid})
	EventBus.damage_dealt.connect(on_damage)
	_record_hits = true

	await _section_data()
	await _section_gate(spawner)
	await _section_promote(spawner)
	await _section_leap(spawner)
	await _section_meteor(spawner)
	await _section_pierce(spawner)
	await _section_stealth(spawner)
	await _section_vfx()

	_record_hits = false
	if EventBus.damage_dealt.is_connected(on_damage):
		EventBus.damage_dealt.disconnect(on_damage)
	await get_tree().physics_frame
	_finish()


func _finish() -> void:
	_finished = true
	_check(_sections.size() == SECTIONS_EXPECTED,
		"all %d sections completed (done=%d %s)" % [SECTIONS_EXPECTED, _sections.size(), str(_sections)])
	print("RESULT: ", "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures)
	get_tree().quit(mini(_failures, 120))


# ============================================================================
# 1. 数据契约（契约 2.1 / 2.2 / 2.3 / 2.4 / 2.5）
# ============================================================================

func _section_data() -> void:
	var leap: PawnSkillDef = GameDefs.skill_leap_slam_def()
	var meteor: PawnSkillDef = GameDefs.skill_meteor_def()
	var pierce: PawnSkillDef = GameDefs.skill_piercing_shot_def()
	var stealth: PawnSkillDef = GameDefs.skill_stealth_def()
	_check(leap != null and meteor != null and pierce != null and stealth != null,
		"1: four v33 skill defs exist")

	if leap != null:
		_check(leap.id == &"leap_slam" and leap.kind == PawnSkillDef.Kind.LEAP_SLAM,
			"1: leap_slam id/kind")
		_check(leap.display_name == "跳劈", "1: leap_slam display name")
		_check(is_equal_approx(leap.cooldown, 14.0) and is_equal_approx(leap.cast_range, 8.0) \
				and is_equal_approx(leap.damage, 34.0),
			"1: leap_slam cd 14 / range 8 / dmg 34")
		_check(is_equal_approx(leap.windup, 0.55) and is_equal_approx(leap.recover, 0.30) \
				and is_equal_approx(leap.radius, 3.4),
			"1: leap_slam windup 0.55 / recover 0.30 / aoe r3.4")
		_check(is_equal_approx(leap.knockback_distance, 3.2) and is_equal_approx(leap.knockback_height, 2.6) \
				and is_equal_approx(leap.airborne_time, 0.55) and is_equal_approx(leap.stun_duration, 1.1),
			"1: leap_slam knockback 3.2/2.6 airborne 0.55 stun 1.1")

	if meteor != null:
		_check(meteor.id == &"meteor" and meteor.kind == PawnSkillDef.Kind.METEOR,
			"1: meteor id/kind")
		_check(meteor.display_name == "陨石术", "1: meteor display name")
		_check(is_equal_approx(meteor.cooldown, 16.0) and is_equal_approx(meteor.cast_range, 11.0) \
				and is_equal_approx(meteor.damage, 55.0),
			"1: meteor cd 16 / range 11 / dmg 55")
		_check(is_equal_approx(meteor.windup, 1.0) and is_equal_approx(meteor.recover, 0.35) \
				and is_equal_approx(meteor.telegraph, 1.1),
			"1: meteor windup 1.0 / recover 0.35 / telegraph 1.1")
		_check(is_equal_approx(meteor.radius, 4.2), "1: meteor aoe r4.2")

	if pierce != null:
		_check(pierce.id == &"piercing_shot" and pierce.kind == PawnSkillDef.Kind.PIERCING_SHOT,
			"1: piercing_shot id/kind")
		_check(pierce.display_name == "贯穿射击", "1: piercing_shot display name")
		_check(is_equal_approx(pierce.cooldown, 12.0) and is_equal_approx(pierce.cast_range, 18.0) \
				and is_equal_approx(pierce.damage, 26.0),
			"1: piercing_shot cd 12 / range 18 / dmg 26")
		_check(is_equal_approx(pierce.pierce_length, 26.0) and is_equal_approx(pierce.pierce_radius, 1.0) \
				and is_equal_approx(pierce.pierce_speed, 26.0),
			"1: piercing_shot length 26 / radius 1.0 / speed 26")

	if stealth != null:
		_check(stealth.id == &"stealth" and stealth.kind == PawnSkillDef.Kind.STEALTH,
			"1: stealth id/kind")
		_check(stealth.display_name == "隐身", "1: stealth display name")
		_check(is_equal_approx(stealth.cooldown, 18.0) and is_equal_approx(stealth.cast_range, 0.0) \
				and is_equal_approx(stealth.damage, 0.0),
			"1: stealth cd 18 / self-cast / dmg 0")
		_check(is_equal_approx(stealth.stealth_duration, 5.0) and is_equal_approx(stealth.escape_hp_ratio, 0.35) \
				and is_equal_approx(stealth.approach_range, 7.0),
			"1: stealth duration 5 / escape 0.35 / approach 7")

	# ---- 四个进阶职业：extra_skills + 专属树 ----
	var advanced: Array = [
		[&"settler_berserker", &"blood_rage", &"leap_slam", &"settler_berserker_tree"],
		[&"settler_elementalist", &"blizzard", &"meteor", &"settler_elementalist_tree"],
		[&"settler_sniper", &"rapid_shot", &"piercing_shot", &"settler_sniper_tree"],
		[&"settler_slayer", &"backstab", &"stealth", &"settler_slayer_tree"],
	]
	for row in advanced:
		var adv_id: StringName = row[0]
		var main_id: StringName = row[1]
		var new_id: StringName = row[2]
		var tree_id: StringName = row[3]
		var adv: PawnDef = GameDefs.settler_advanced_def(adv_id)
		_check(adv != null and adv.all_skills().size() == 2 and adv.has_skill_id(new_id),
			"1: %s all_skills() = 2 incl %s" % [String(adv_id), String(new_id)])
		_check(adv != null and adv.extra_skills.size() == 1 and adv.extra_skills[0] != null \
				and adv.extra_skills[0].id == new_id,
			"1: %s extra_skills = [%s]" % [String(adv_id), String(new_id)])
		_check(adv != null and adv.skill != null and adv.skill.id == main_id,
			"1: %s keeps main skill %s" % [String(adv_id), String(main_id)])
		_check(adv != null and adv.skill_tree_id == tree_id and adv.promotes_to.is_empty(),
			"1: %s tree id = %s" % [String(adv_id), String(tree_id)])

	# 未挂新技能的进阶职业（骑士 / 雷电法师 / 漫游射手 / 忍者）保持单技能 + generic 树
	for plain_id in [&"settler_knight", &"settler_storm_mage", &"settler_wanderer", &"settler_ninja"]:
		var plain: PawnDef = GameDefs.settler_advanced_def(plain_id)
		_check(plain != null and plain.all_skills().size() == 1 and plain.skill_tree_id == &"generic",
			"1: %s stays single-skill on generic tree" % String(plain_id))

	# ---- 四棵进阶树的节点布局 ----
	for row in advanced:
		var main_id: StringName = row[1]
		var new_id: StringName = row[2]
		var tree_id: StringName = row[3]
		var tree := GameDefs.skill_tree_def(tree_id)
		_check(tree != null and tree.id == tree_id and tree.gate_node_id == &"class_skill",
			"1: tree %s gated on class_skill" % String(tree_id))
		if tree == null:
			continue
		var root := tree.node(&"class_skill")
		_check(root != null and root.max_rank == 1 and root.unlocks_skill \
				and root.unlocks_skill_id == main_id,
			"1: %s class_skill unlocks %s" % [String(tree_id), String(main_id)])
		var adv_node := tree.node(&"advanced_skill")
		_check(adv_node != null and adv_node.max_rank == 1 and adv_node.branch == 1 \
				and adv_node.unlocks_skill_id == new_id \
				and adv_node.requires_node == &"class_skill" and adv_node.requires_rank == 1,
			"1: %s advanced_skill unlocks %s behind class_skill" % [String(tree_id), String(new_id)])
		var dmg_node := tree.node(&"damage")
		_check(dmg_node != null and dmg_node.branch == 2 and dmg_node.max_rank == 5 \
				and is_equal_approx(dmg_node.damage_per_rank, 0.05) \
				and dmg_node.requires_node == &"class_skill" and dmg_node.requires_rank == 1,
			"1: %s damage branch 5 ranks +5%% behind class_skill" % String(tree_id))
		var hp_node := tree.node(&"vitality")
		_check(hp_node != null and hp_node.branch == 3 and hp_node.max_rank == 5 \
				and is_equal_approx(hp_node.hp_per_rank, 0.06) \
				and hp_node.requires_node == &"damage" and hp_node.requires_rank == 1,
			"1: %s vitality branch 5 ranks +6%% behind damage" % String(tree_id))

	# 通用树零变化（基础四职业继续走旧 gate 语义）
	var generic := GameDefs.skill_tree_def(&"generic")
	_check(generic != null and generic.node(&"advanced_skill") == null,
		"1: generic tree has no advanced_skill node")
	_check(generic != null and generic.node(&"class_skill") != null \
			and generic.node(&"class_skill").unlocks_skill_id == &"",
		"1: generic tree root keeps legacy unlocks_skill semantics")
	for cid in GameDefs.settler_def_ids():
		var base: PawnDef = GameDefs.settler_def(cid)
		_check(base != null and base.all_skills().size() == 1 and base.extra_skills.is_empty() \
				and base.skill_tree_id == &"generic",
			"1: base class %s unchanged (1 skill, generic tree)" % String(cid))

	# ---- PawnSkillTree 运行时（纯数据，不起场景）----
	var rt := PawnSkillTree.new()
	rt.set_tree_def(GameDefs.skill_tree_def(&"settler_slayer_tree"))
	_check(not rt.is_skill_unlocked(&"backstab") and not rt.is_skill_unlocked(&"stealth"),
		"1: fresh advanced tree locks both skills")
	_check(rt.invest(&"class_skill", 5) and rt.is_skill_unlocked(&"backstab") \
			and not rt.is_skill_unlocked(&"stealth"),
		"1: class_skill node unlocks the main skill only")
	_check(rt.invest(&"advanced_skill", 5) and rt.is_skill_unlocked(&"stealth"),
		"1: advanced_skill node unlocks the new skill")
	_check(not rt.is_skill_unlocked(&"meteor"), "1: another class skill stays locked")
	_check(rt.points_spent() == 2, "1: points_spent counts 2 invested ranks")
	var refunded: int = rt.reset_and_refund()
	_check(refunded == 2 and rt.points_spent() == 0 and rt.rank(&"class_skill") == 0 \
			and not rt.is_skill_unlocked(&"stealth"),
		"1: reset_and_refund returns %d and clears every rank" % refunded)
	rt.set_tree_def(GameDefs.skill_tree_def(&"settler_sniper_tree"))
	_check(rt.tree_def != null and rt.tree_def.id == &"settler_sniper_tree" \
			and rt.rank(&"advanced_skill") == 0 and not rt.is_skill_unlocked(&"piercing_shot"),
		"1: set_tree_def swaps layout and resets ranks")

	# ---- 主角树预点亮不计入 points_spent（契约 2.4）----
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	_check(hero != null and hero.skill_tree != null and hero.skill_tree.rank(&"class_skill") == 1,
		"1: hero tree root pre-unlocked")
	_check(hero != null and hero.skill_tree != null and hero.skill_tree.points_spent() == 0,
		"1: pre-unlocked root costs no points")

	_sections.append("1-data")


# ============================================================================
# 2. 技能门禁（契约 2.4 / 3.1）
# ============================================================================

func _section_gate(spawner: Node) -> void:
	if spawner == null:
		_check(false, "2: spawner missing")
		_sections.append("2-gate")
		return
	var cases: Array = [
		[&"settler_berserker", &"blood_rage", &"leap_slam", Vector3(-30.0, 0.0, 34.0)],
		[&"settler_elementalist", &"blizzard", &"meteor", Vector3(-10.0, 0.0, 34.0)],
		[&"settler_sniper", &"rapid_shot", &"piercing_shot", Vector3(10.0, 0.0, 34.0)],
		[&"settler_slayer", &"backstab", &"stealth", Vector3(30.0, 0.0, 34.0)],
	]
	var index := 0
	for row in cases:
		var adv_id: StringName = row[0]
		var main_id: StringName = row[1]
		var new_id: StringName = row[2]
		var at: Vector3 = row[3]
		var pawn: Pawn = spawner.call("spawn_soldier", GameDefs.settler_advanced_def(adv_id), at)
		var dummy: Pawn = _spawn_dummy(spawner, at + Vector3(0.0, 0.0, 5.0), 900.0)
		await get_tree().physics_frame
		_check(pawn != null and pawn.skill_comp != null,
			"2[%d]: %s has a skill component" % [index, String(adv_id)])
		if pawn != null and pawn.skill_comp != null and dummy != null:
			# 全新进阶小兵：主技能与进阶技能都锁着——
			# 公共施法入口（FightState 走的 try_cast_combat_skill）必须不发。
			_check(not pawn.is_skill_unlocked(main_id) and not pawn.is_skill_unlocked(new_id),
				"2[%d]: main + new skill locked before any point" % index)
			_check(not pawn.try_cast_combat_skill(dummy),
				"2[%d]: gated cast entry refuses to fire while locked" % index)
			# 点亮「职业技」根节点：主技能解锁，进阶技能仍锁
			pawn.skill_points = 1
			_check(pawn.try_invest_skill_point(&"class_skill"),
				"2[%d]: invest class_skill node" % index)
			_check(pawn.is_skill_unlocked(main_id),
				"2[%d]: main skill %s unlocked" % [index, String(main_id)])
			_check(not pawn.is_skill_unlocked(new_id),
				"2[%d]: new skill %s still locked" % [index, String(new_id)])
			# 点亮「进阶技能」节点：新技能解锁
			pawn.skill_points = 1
			_check(pawn.try_invest_skill_point(&"advanced_skill"),
				"2[%d]: invest advanced_skill node" % index)
			_check(pawn.is_skill_unlocked(new_id),
				"2[%d]: new skill %s unlocked" % [index, String(new_id)])
		await _cleanup(pawn, dummy)
		index += 1

	# 基础职业回归：generic 树仍按「职业技」根节点门禁（行为零变化）
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-30.0, 0.0, 0.0))
	await get_tree().physics_frame
	if warrior != null:
		_check(not warrior.is_skill_unlocked(&"blood_rage"),
			"2: base warrior class skill locked (legacy gate semantics)")
		warrior.skill_points = 1
		_check(warrior.try_invest_skill_point(&"class_skill") and warrior.is_skill_unlocked(&"blood_rage"),
			"2: base warrior class skill unlocked after root node")
	await _cleanup(warrior, null)

	_sections.append("2-gate")


# ============================================================================
# 3. 转职返还（契约 2.4 / 0.2 硬需求 2）
# ============================================================================

func _section_promote(spawner: Node) -> void:
	if spawner == null:
		_check(false, "3: spawner missing")
		_sections.append("3-promote")
		return
	var w: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(0.0, 0.0, 34.0))
	await get_tree().physics_frame
	if w == null:
		_check(false, "3: promote subject spawned")
		_sections.append("3-promote")
		return
	w.gain_xp(310)   # Lv.5（+4 技能点），与 CitizenManageTest 同口径
	_check(w.level == 5 and w.skill_points == 4,
		"3: warrior reaches Lv.5 with 4 points (lv=%d pts=%d)" % [w.level, w.skill_points])
	_check(w.try_invest_skill_point(&"class_skill") and w.try_invest_skill_point(&"damage") \
			and w.try_invest_skill_point(&"damage"),
		"3: spend 3 points on the base tree")
	_check(w.skill_tree.points_spent() == 3, "3: points_spent tracks the 3 invested ranks")

	var events: Array = []
	var on_changed := func(p: Node) -> void: events.append(p)
	EventBus.skill_tree_changed.connect(on_changed)
	_check(w.promote_to(&"settler_berserker"), "3: Lv.5 warrior promotes to berserker")
	if EventBus.skill_tree_changed.is_connected(on_changed):
		EventBus.skill_tree_changed.disconnect(on_changed)

	_check(w.def.id == &"settler_berserker" and w.level == 5 and w.has_skill_tree(),
		"3: def swapped to berserker, level kept")
	_check(w.skill_tree != null and w.skill_tree.tree_def != null \
			and w.skill_tree.tree_def.id == &"settler_berserker_tree",
		"3: skill tree swapped to the advanced tree")
	_check(w.skill_points == 4, "3: refund restores the full 4 points (got %d)" % w.skill_points)
	_check(w.skill_tree.points_spent() == 0 and w.skill_tree.rank(&"class_skill") == 0 \
			and w.skill_tree.rank(&"damage") == 0,
		"3: all invested ranks cleared on promote")
	_check(not w.is_skill_unlocked(&"leap_slam"),
		"3: new skill locked until re-invested after promote")
	_check(w.def.all_skills().size() == 2 and w.def.has_skill_id(&"leap_slam"),
		"3: promoted def carries the new skill")
	_check(events.size() >= 1, "3: skill_tree_changed broadcast on promote (%d)" % events.size())

	# 返还的点数必须真的能重新分配（玩家重新规划进阶树）
	_check(w.try_invest_skill_point(&"class_skill") and w.try_invest_skill_point(&"advanced_skill"),
		"3: refunded points can be re-invested")
	_check(w.is_skill_unlocked(&"leap_slam") and w.skill_points == 2,
		"3: leap_slam unlocked after re-investing (pts=%d)" % w.skill_points)

	await _cleanup(w, null)
	_sections.append("3-promote")


# ============================================================================
# 工具
# ============================================================================

## 木桩野怪：低攻（别把小兵打死）、不死逃、够血撑完断言。
## 六维防御 / 暴击归零，后续伤害断言才能精确到点（v20.3 起怪物也有六维）。
func _spawn_dummy(spawner: Node, at: Vector3, hp: float) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = hp
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	d.defense = 0.0
	d.crit_rate = 0.0
	return spawner.call("spawn_raider", at, d)


func _cleanup(a: Node, b: Node) -> void:
	if a != null and is_instance_valid(a):
		a.queue_free()
	if b != null and is_instance_valid(b):
		b.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


# ============================================================================
# 4. 跳劈（契约 5.4）：前摇 → 跃击锁定落点 → 圆形 AOE + 击飞控制
# ============================================================================

func _section_leap(spawner: Node) -> void:
	if spawner == null:
		_check(false, "4: spawner missing")
		_sections.append("4-leap")
		return
	var base := Vector3(-40.0, 0.0, 26.0)
	var pawn: Pawn = _spawn_caster(spawner, &"settler_berserker", base, "4")
	await get_tree().physics_frame
	if pawn == null or pawn.skill_comp == null:
		_check(false, "4: berserker spawned with a skill component")
		_sections.append("4-leap")
		return
	# 三只木桩挤在一起（落点取哪只，另两只都在 3.4m 半径内），第四只在 12m 外
	var bodies: Array = [
		_spawn_anchor(spawner, base + Vector3(0.0, 0.0, 4.0), 900.0),
		_spawn_anchor(spawner, base + Vector3(1.2, 0.0, 4.6), 900.0),
		_spawn_anchor(spawner, base + Vector3(-1.2, 0.0, 4.6), 900.0),
		_spawn_anchor(spawner, base + Vector3(0.0, 0.0, 12.0), 900.0),
	]
	var labels: Array = ["T", "A", "B", "C"]
	await get_tree().physics_frame
	var samples: Array = []
	for i in bodies.size():
		var body := bodies[i] as Pawn
		if body == null:
			continue
		samples.append({
			"label": labels[i], "pawn": body, "hp0": body.health.current_hp,
			"drop": -1.0, "drop_frame": -1, "ground_y": body.global_position.y,
			"origin": body.global_position, "pos_at_hit": Vector3.INF, "pos_ready": false,
			"max_lift": 0.0, "max_disp": 0.0, "ctrl_frames": 0,
		})
	_check(samples.size() == 4, "4: four dummies placed for the leap slam (%d)" % samples.size())
	if samples.size() < 2:
		await _cleanup(pawn, null)
		_sections.append("4-leap")
		return
	var casted := pawn.try_cast_combat_skill(bodies[0] as Pawn)
	_check(casted, "4: berserker starts the leap slam (explicit cast order)")
	var hit_frame := -1
	var center := Vector3.ZERO
	var frames := 0
	while frames < 420:
		for s in samples:
			var raw = s["pawn"]
			if not is_instance_valid(raw):
				continue
			var p := raw as Pawn
			var hp: float = p.health.current_hp
			if float(s["drop"]) < 0.0 and hp < float(s["hp0"]) - 0.001:
				s["drop"] = float(s["hp0"]) - hp
				s["drop_frame"] = frames
				if hit_frame < 0:
					hit_frame = frames
					center = pawn.global_position   # 落地帧的施法者位置 = AOE 圆心
			if p.is_controlled():
				s["ctrl_frames"] = int(s["ctrl_frames"]) + 1
			s["max_lift"] = maxf(float(s["max_lift"]), p.global_position.y - float(s["ground_y"]))
			var o: Vector3 = s["origin"]
			s["max_disp"] = maxf(float(s["max_disp"]),
				Vector2(p.global_position.x - o.x, p.global_position.z - o.z).length())
		if hit_frame == frames:
			# 落地帧快照：击飞位移下一物理帧才推进，此刻位置 = 判定时刻位置
			for s in samples:
				var raw2 = s["pawn"]
				if is_instance_valid(raw2):
					s["pos_at_hit"] = (raw2 as Pawn).global_position
					s["pos_ready"] = true
		if hit_frame >= 0 and frames > hit_frame + 150:
			break
		frames += 1
		await get_tree().physics_frame

	_check(hit_frame > 30,
		"4: first damage lands only after the windup (hit at frame %d, windup = 33 frames)" % hit_frame)
	_check(pawn.skill_comp.cooldown_left(&"leap_slam") > 0.0,
		"4: leap_slam consumed its cooldown")
	var inside: Array = []
	var outside: Array = []
	for s in samples:
		if not bool(s["pos_ready"]):
			continue
		var pos: Vector3 = s["pos_at_hit"]
		var d: float = Vector2(pos.x - center.x, pos.z - center.z).length()
		if d <= 3.4 - 0.3:
			inside.append(s)
		elif d >= 3.4 + 0.3:
			outside.append(s)
	_check(inside.size() >= 2,
		"4: at least two dummies stood inside the 3.4m slam radius (%d)" % inside.size())
	var drops_ok := true
	var simultaneous := true
	var ctrl_ok := true
	var duration_ok := true
	var lift_ok := true
	var disp_ok := true
	var details: Array = []
	for s in inside:
		if not is_equal_approx(float(s["drop"]), 34.0):
			drops_ok = false
		if int(s["drop_frame"]) != hit_frame:
			simultaneous = false
		var secs: float = float(s["ctrl_frames"]) / 60.0
		if int(s["ctrl_frames"]) <= 0:
			ctrl_ok = false
		if secs < 1.2 or secs > 2.3:
			duration_ok = false
		if float(s["max_lift"]) < 1.8 or float(s["max_lift"]) > 2.9:
			lift_ok = false
		if float(s["max_disp"]) < 2.8 or float(s["max_disp"]) > 3.6:
			disp_ok = false
		details.append("%s drop=%.1f lift=%.2f disp=%.2f ctrl=%.2fs"
			% [String(s["label"]), float(s["drop"]), float(s["max_lift"]),
			float(s["max_disp"]), secs])
	_check(drops_ok, "4: every victim inside takes exactly 34 damage [%s]" % " | ".join(details))
	_check(simultaneous, "4: the whole circle is hit in the same physics frame")
	_check(ctrl_ok, "4: knocked-up victims report is_controlled()")
	_check(duration_ok, "4: control spans airborne 0.55s + stun 1.1s (1.2~2.3s window)")
	_check(lift_ok, "4: sin arc lifts victims to knockback_height 2.6m (1.8~2.9)")
	_check(disp_ok, "4: horizontal knockback equals knockback_distance 3.2m (2.8~3.6)")
	var outside_clean := true
	for s in outside:
		if float(s["drop"]) >= 0.0:
			outside_clean = false
	_check(outside_clean and outside.size() >= 1,
		"4: dummy outside the radius takes no damage (%d outside)" % outside.size())
	await _cleanup(pawn, null)
	for b in bodies:
		await _cleanup(b, null)
	_sections.append("4-leap")


# ============================================================================
# 5. 陨石术（契约 5.5）：吟唱无伤 → 落点锁定 → 预警圈 → 圈内高伤；走出圈无伤
# ============================================================================

func _section_meteor(spawner: Node) -> void:
	if spawner == null:
		_check(false, "5: spawner missing")
		_sections.append("5-meteor")
		return
	var base := Vector3(14.0, 0.0, 26.0)
	var pawn: Pawn = _spawn_caster(spawner, &"settler_elementalist", base, "5")
	await get_tree().physics_frame
	if pawn == null or pawn.skill_comp == null:
		_check(false, "5: elementalist spawned with a skill component")
		_sections.append("5-meteor")
		return
	var victim: Pawn = _spawn_anchor(spawner, base + Vector3(0.0, 0.0, 8.0), 900.0)
	var dodger: Pawn = _spawn_anchor(spawner, base + Vector3(2.0, 0.0, 8.8), 900.0)
	await get_tree().physics_frame
	if victim == null or dodger == null:
		_check(false, "5: meteor dummies spawned")
		await _cleanup(pawn, null)
		_sections.append("5-meteor")
		return
	var victim_hp0: float = victim.health.current_hp
	var dodger_hp0: float = dodger.health.current_hp
	var lock_pos: Vector3 = victim.global_position      # 吟唱瞬间锁定的落点
	var dodger_start: Vector3 = dodger.global_position
	_check(dodger_start.distance_to(lock_pos) < 3.9,
		"5: dodger starts inside the 4.2m circle (%.1fm)" % dodger_start.distance_to(lock_pos))
	_hits.clear()
	var casted := pawn.try_cast_combat_skill(victim)
	_check(casted, "5: elementalist starts the meteor channel (explicit cast order)")
	# 契约口径：落点在吟唱开始瞬间锁定，所以「走出圈」要在 windup（1.0s）里完成
	for _i in 12:
		await get_tree().physics_frame
	dodger.global_position = lock_pos + Vector3(0.0, 0.0, 18.0)
	_check(dodger.global_position.distance_to(lock_pos) > 10.0,
		"5: dodger walks out of the circle during the channel")
	var strike: Node = null
	var frames := 0
	while frames < 150:
		strike = get_tree().get_first_node_in_group("skill_meteor_strike")
		if strike != null:
			break
		frames += 1
		await get_tree().physics_frame
	_check(strike != null,
		"5: telegraph entity spawns after the channel (group skill_meteor_strike)")
	_check(is_equal_approx(victim.health.current_hp, victim_hp0),
		"5: channeling deals no damage before the impact")
	var strike_3d := strike as Node3D
	if strike_3d != null:
		var off: float = strike_3d.global_position.distance_to(lock_pos)
		_check(off < 1.5,
			"5: landing point is locked where the target stood at channel start (%.2fm off)" % off)
	var gone := false
	frames = 0
	while frames < 180:
		if get_tree().get_first_node_in_group("skill_meteor_strike") == null:
			gone = true
			break
		frames += 1
		await get_tree().physics_frame
	_check(gone, "5: meteor lands and the strike entity frees itself")
	_check(_hits_on(victim, pawn, 55.0) >= 1,
		"5: dummy inside the circle takes the 55-damage meteor hit")
	_check(_hits_on(dodger, pawn, 55.0) == 0 and is_equal_approx(dodger.health.current_hp, dodger_hp0),
		"5: dummy that walked out of the circle takes no meteor damage")
	await _cleanup(pawn, null)
	await _cleanup(victim, null)
	await _cleanup(dodger, null)
	_sections.append("5-meteor")


# ============================================================================
# 6. 贯穿射击（契约 5.6）：直线 3 目标各恰好一次 26 伤、线外无伤、远靶 > 20m
# ============================================================================

func _section_pierce(spawner: Node) -> void:
	if spawner == null:
		_check(false, "6: spawner missing")
		_sections.append("6-pierce")
		return
	var base := Vector3(-40.0, 0.0, -22.0)
	var pawn: Pawn = _spawn_caster(spawner, &"settler_sniper", base, "6")
	await get_tree().physics_frame
	if pawn == null or pawn.skill_comp == null:
		_check(false, "6: sniper spawned with a skill component")
		_sections.append("6-pierce")
		return
	var origin: Vector3 = pawn.global_position
	_freeze_ai(pawn)   # 贯穿是瞬发：冻结 AI，保证由测试显式下令开火
	var aim: Pawn = _spawn_anchor(spawner, origin + Vector3(0.0, 0.0, 7.0), 900.0)
	await get_tree().physics_frame
	if aim == null:
		_check(false, "6: aim dummy spawned")
		await _cleanup(pawn, null)
		_sections.append("6-pierce")
		return
	# 弹道 = 施法者 → 开火目标的水平方向；其余木桩按此方向摆位，避免格子吸附造成斜线
	var to_aim := Vector3(aim.global_position.x - origin.x, 0.0, aim.global_position.z - origin.z)
	_check(to_aim.length() > 4.0, "6: aim dummy stands in front of the sniper (%.1fm)" % to_aim.length())
	var dir: Vector3 = to_aim.normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var mid: Pawn = _spawn_anchor(spawner, origin + dir * 14.5, 900.0)
	var far: Pawn = _spawn_anchor(spawner, origin + dir * 22.5, 900.0)
	var off: Pawn = _spawn_anchor(spawner, origin + dir * 14.5 + right * 4.0, 900.0)
	await get_tree().physics_frame
	if mid == null or far == null or off == null:
		_check(false, "6: pierce dummies spawned")
		await _cleanup(pawn, null)
		await _cleanup(aim, null)
		_sections.append("6-pierce")
		return
	# 静止靶：把格子吸附挪过的位置精确钉在弹道上（判定是「点到线段距离 ≤ 1.3m」）
	aim.global_position = Vector3(origin.x + dir.x * 7.0, aim.global_position.y, origin.z + dir.z * 7.0)
	mid.global_position = Vector3(origin.x + dir.x * 14.5, mid.global_position.y, origin.z + dir.z * 14.5)
	far.global_position = Vector3(origin.x + dir.x * 22.5, far.global_position.y, origin.z + dir.z * 22.5)
	off.global_position = Vector3(origin.x + dir.x * 14.5 + right.x * 4.0, off.global_position.y,
		origin.z + dir.z * 14.5 + right.z * 4.0)
	await get_tree().physics_frame
	var far_dist: float = origin.distance_to(far.global_position)
	_check(far_dist > 20.0, "6: farthest dummy on the line stands beyond 20m (%.1fm)" % far_dist)
	var off_hp0: float = off.health.current_hp
	_hits.clear()
	var casted := pawn.try_cast_combat_skill(aim)
	_check(casted, "6: sniper fires the piercing shot (explicit cast order)")
	var shot_seen := false
	var frames := 0
	while frames < 150:
		if get_tree().get_first_node_in_group("skill_piercing_shot") != null:
			shot_seen = true
			break
		frames += 1
		await get_tree().physics_frame
	_check(shot_seen, "6: piercing shot entity exists (group skill_piercing_shot)")
	frames = 0
	while frames < 150:
		if get_tree().get_first_node_in_group("skill_piercing_shot") == null:
			break
		frames += 1
		await get_tree().physics_frame
	var n_aim := _hits_on(aim, pawn, 26.0)
	var n_mid := _hits_on(mid, pawn, 26.0)
	var n_far := _hits_on(far, pawn, 26.0)
	_check(n_aim == 1 and n_mid == 1 and n_far == 1,
		"6: all 3 dummies on the line take exactly one 26-damage pierce hit (%d/%d/%d)"
		% [n_aim, n_mid, n_far])
	_check(_hits_on(off, pawn, 26.0) == 0 and is_equal_approx(off.health.current_hp, off_hp0),
		"6: off-line dummy takes no pierce damage")
	await _cleanup(pawn, null)
	for b in [aim, mid, far, off]:
		await _cleanup(b, null)
	_sections.append("6-pierce")


# ============================================================================
# 7. 隐身（契约 5.7）：索敌失效 / 受击不破隐 / 造成伤害破隐 / 到期解除
# ============================================================================

func _section_stealth(spawner: Node) -> void:
	if spawner == null:
		_check(false, "7: spawner missing")
		_sections.append("7-stealth")
		return
	var base := Vector3(50.0, 0.0, 46.0)
	var pawn: Pawn = _spawn_caster(spawner, &"settler_slayer", base, "7")
	await get_tree().physics_frame
	if pawn == null or pawn.skill_comp == null:
		_check(false, "7: slayer spawned with a skill component")
		_sections.append("7-stealth")
		return
	# 冻结 AI：否则它会在隐身起手后立刻用「背刺」抢攻，造成伤害反手破隐
	_freeze_ai(pawn)
	# 目标放在 2.5~7m：隐身契约的「接近触发」区间（<2.5m 满血不会触发）
	var enemy: Pawn = _spawn_anchor(spawner, base + Vector3(0.0, 0.0, 5.0), 900.0)
	await get_tree().physics_frame
	if enemy == null:
		_check(false, "7: enemy dummy spawned")
		await _cleanup(pawn, null)
		_sections.append("7-stealth")
		return
	# 对照组：未隐身时敌方索敌扫得到（否则「扫不到」的断言没有意义）
	_check(enemy.find_nearest_hostile(12.0) == pawn,
		"7: control - the enemy spots the slayer before stealth")
	_hits.clear()
	var casted := pawn.try_cast_combat_skill(enemy)
	_check(casted, "7: slayer casts stealth while closing in (5m)")
	_check(pawn.is_stealthed(), "7: is_stealthed() true right after the cast")
	_check(not pawn.can_be_seen_by_enemies(), "7: can_be_seen_by_enemies() false")
	_check(pawn.model_rig != null and pawn.model_rig.stealth_active(),
		"7: model rig reports the stealth look")
	_check(enemy.find_nearest_hostile(12.0) != pawn,
		"7: enemy scan no longer finds the stealthed slayer")
	_check(int(VFXManager.stat_spawned_by_id.get(&"stealth_enter", 0)) >= 1,
		"7: stealth_enter effect fired on cast")
	# 受伤不破隐（隐身是逃生手段）
	pawn.take_damage(10.0, enemy)
	await get_tree().physics_frame
	_check(pawn.is_stealthed(), "7: taking damage does NOT break stealth")
	# 造成伤害立即破隐：真实伤害路径（木桩掉血 → damage_dealt(source = slayer)）
	enemy.take_damage(5.0, pawn)
	await get_tree().physics_frame
	_check(not pawn.is_stealthed(), "7: dealing damage breaks stealth immediately")
	_check(pawn.can_be_seen_by_enemies(), "7: visible again after the break")
	_check(int(VFXManager.stat_spawned_by_id.get(&"stealth_break", 0)) >= 1,
		"7: stealth_break effect fired on break")
	# 到期自动解除：用短时长直接调宿主接口，避免为 5s 时长空等
	_check(pawn.apply_stealth(0.6), "7: stealth can be re-applied after the break")
	var expired := await _wait_until(func(): return not pawn.is_stealthed(), 120)
	_check(expired, "7: stealth expires automatically")
	_check(pawn.can_be_seen_by_enemies(), "7: visible again after expiry")
	await _cleanup(pawn, null)
	await _cleanup(enemy, null)
	_sections.append("7-stealth")


# ============================================================================
# 8. 特效（契约 5.8）：14 个 v33 特效 id 全部注册且可生成
# ============================================================================

func _section_vfx() -> void:
	var spawn_ids: Array = [&"leap_charge", &"slam_impact", &"slam_shockwave",
		&"meteor_channel", &"meteor_telegraph", &"meteor_fall", &"meteor_impact",
		&"pierce_muzzle", &"pierce_hit", &"stealth_enter", &"stealth_break"]
	var trail_ids: Array = [&"leap_trail", &"pierce_trail", &"stealth_shimmer"]
	var pos := Vector3(0.0, 30.0, 0.0)
	VFXManager.reset_stats()
	var unregistered: Array = []
	var failed: Array = []
	for id in spawn_ids:
		if not VFXManager._defs.has(id):
			unregistered.append(String(id))
		if VFXManager.spawn_effect(id, pos, 0.0) == null:
			failed.append(String(id))
		await get_tree().physics_frame
	var host := Node3D.new()
	add_child(host)
	var trails_missing: Array = []
	for id in trail_ids:
		if not VFXManager._defs.has(id):
			unregistered.append(String(id))
		if VFXManager.attach_trail(host, id) == null:
			trails_missing.append(String(id))
	_check(unregistered.is_empty(),
		"8: all 14 v33 effect ids are registered in VFXManager._defs (missing=%s)" % str(unregistered))
	_check(failed.is_empty(),
		"8: 11 spawn-type effect ids build a node (failed=%s)" % str(failed))
	_check(trails_missing.is_empty(),
		"8: 3 TRAIL-type effect ids attach a GPUParticles3D (failed=%s)" % str(trails_missing))
	var zero: Array = []
	for id in spawn_ids:
		if int(VFXManager.stat_spawned_by_id.get(id, 0)) <= 0:
			zero.append(String(id))
	_check(zero.is_empty(),
		"8: stat_spawned_by_id counted every spawn-type effect (zero=%s)" % str(zero))
	_check(host.get_child_count() == 3,
		"8: all 3 trails are attached to the host (%d)" % host.get_child_count())
	host.queue_free()
	await get_tree().physics_frame
	_sections.append("8-vfx")


# ============================================================================
# 工具（T5b）
# ============================================================================

## 施法者：关掉自动接战，施法时机完全由测试显式下令，行为可复现。
func _spawn_caster(spawner: Node, adv_id: StringName, at: Vector3, tag: String) -> Pawn:
	var d: PawnDef = GameDefs.settler_advanced_def(adv_id)
	if d == null:
		_check(false, "%s: advanced def exists (%s)" % [tag, String(adv_id)])
		return null
	d.is_auto_fighter = false
	var pawn: Pawn = spawner.call("spawn_soldier", d, at)
	if pawn == null:
		_check(false, "%s: %s spawn failed" % [tag, String(adv_id)])
		return null
	pawn.is_auto_fighter = false
	_unlock_advanced_skills(pawn, tag)
	return pawn


## 点亮进阶树两个技能节点（class_skill → advanced_skill）。
func _unlock_advanced_skills(pawn: Pawn, tag: String) -> bool:
	if pawn == null or not pawn.has_skill_tree():
		_check(false, "%s: caster owns a skill tree" % tag)
		return false
	pawn.skill_points = 2
	var ok := pawn.try_invest_skill_point(&"class_skill") \
		and pawn.try_invest_skill_point(&"advanced_skill")
	_check(ok, "%s: class_skill + advanced_skill nodes lit" % tag)
	return ok


## 冻结自主 AI：`SoldierIdleState` 不看 `is_auto_fighter`，视野内有敌就会进战斗并自动施法
## （瞬发技能会抢在测试的显式施法之前，例如狙击手先放贯穿、暗杀者先放背刺破隐）。
## 只冻结状态机：施法推进交给 PawnSkillComponent._process 兜底，
## 宿主级计时（隐身倒计时等）仍在 Pawn._physics_process 里照常跑。
func _freeze_ai(pawn: Pawn) -> void:
	if pawn != null and pawn.state_machine != null:
		pawn.state_machine.set_physics_process(false)


## 静止木桩：不动（move_speed 0）+ 不还手 + 高血 + 零防零暴击。
## 伤害断言因此精确到点；击飞由 StunnedState 直接写位置，不受移速影响。
func _spawn_anchor(spawner: Node, at: Vector3, hp: float) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = hp
	d.attack_damage = 0.0
	d.flee_hp_ratio = 0.0
	d.defense = 0.0
	d.crit_rate = 0.0
	d.move_speed = 0.0
	d.is_auto_fighter = false
	return spawner.call("spawn_raider", at, d)


## 某木桩吃到的「指定数值 + 指定来源」伤害次数（技能伤害与普攻数值不同，可精确区分）。
func _hits_on(victim: Pawn, caster: Pawn, amount: float) -> int:
	if victim == null or not is_instance_valid(victim):
		return 0
	var vid: int = victim.get_instance_id()
	var cid := 0
	if caster != null and is_instance_valid(caster):
		cid = caster.get_instance_id()
	var n := 0
	for h in _hits:
		if int(h["tid"]) != vid:
			continue
		if not is_equal_approx(float(h["amount"]), amount):
			continue
		if cid != 0 and int(h["sid"]) != cid:
			continue
		n += 1
	return n


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if pred.call():
			return true
		await get_tree().physics_frame
	return pred.call()
