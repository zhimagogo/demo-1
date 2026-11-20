extends Node
## ============================================================================
## v25 市民管理 / 入住职业选择 / 转职 / 技能树 专项回归：
##   godot --headless --path . tests/CitizenManageTest.tscn --fixed-fps 60
##
## 需求覆盖：
##   0. 数据契约：8 个进阶职业 def（名称 / 不可再转 / 有技能树）；通用技能树
##      两分支各 5 级（伤害 +5%/级，生命 +6%/级，生命需伤害 ≥1 级）；
##      主角 + 四职业有技能树，村民 / 流民 / 野怪没有。
##   A. 流民入住职业选择：抵房后弹窗（真暂停 + 模态），玩家点选后按所选职业定居。
##   B. 转职：Lv.5 门槛、二选一、保留姓名 / 等级 / 经验 / 技能树、血量比例保留、
##      进阶后不可再转。
##   C. 小兵技能树：升级 +1 技能点；伤害 / 生命分支按级生效；前置与满级拦截。
##   D. 主角技能树：damage_mult 并入树加成；生命上限公式含树加成。
##   E. 市民管理界面：独立入口按钮（不与既有面板重叠）；列表含编队内外全部市民；
##      主角行；转职按钮；技能树面板开合与编队界面共存。
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


## 递归收集文本包含 needle 的 Label / Button（UI 内容断言用）。
func _collect_text_nodes(node: Node, needle: String, out: Array) -> void:
	if node is Label and (node as Label).text.contains(needle):
		out.append(node)
	elif node is Button and (node as Button).text.contains(needle):
		out.append(node)
	for c in node.get_children():
		_collect_text_nodes(c, needle, out)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var hud := _main.get_node_or_null("HUD")
	# 测试期停刷野怪 / 流民、清空敌人：行为确定性
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
	TimeManager.set_speed(1.0)
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	_check(hero != null and spawner != null and hud != null, "main scene ready (hero / spawner / hud)")

	# ================= 0. 数据契约 =================
	var expect_adv := {
		&"settler_warrior": ["狂战士", "骑士"],
		&"settler_mage": ["元素法师", "雷电法师"],
		&"settler_archer": ["狙击手", "漫游射手"],
		&"settler_assassin": ["暗杀者", "忍者"],
	}
	for base_id in expect_adv.keys():
		var ids: Array[StringName] = GameDefs.settler_advanced_ids(base_id)
		_check(ids.size() == 2, "base %s has two advanced classes" % String(base_id))
		var names: Array = []
		for adv_id in ids:
			var adv: PawnDef = GameDefs.settler_advanced_def(adv_id)
			if adv == null:
				_check(false, "advanced def exists: %s" % String(adv_id))
				continue
			names.append(adv.display_name)
			_check(adv.promotes_to.is_empty(), "advanced %s cannot promote again" % String(adv_id))
			# v33：挂 extra_skills 的进阶职业（狂战士/元素法师/狙击手/暗杀者）走专属技能树，
			# 其余四个进阶职业仍沿用 generic 树。
			var expected_tree: StringName = &"generic"
			if not adv.extra_skills.is_empty():
				expected_tree = StringName("%s_tree" % String(adv_id))
			_check(adv.skill_tree_id == expected_tree and adv.can_level,
				"advanced %s keeps skill tree + leveling (tree=%s)"
				% [String(adv_id), String(expected_tree)])
			var base_d: PawnDef = GameDefs.settler_def(base_id)
			_check(adv.attack_kind == base_d.attack_kind,
				"advanced %s keeps base attack kind" % String(adv_id))
		var expected: Array = expect_adv[base_id]
		_check(names.has(expected[0]) and names.has(expected[1]),
			"base %s promotes to %s (got %s)" % [String(base_id), str(expected), str(names)])

	var tree := GameDefs.skill_tree_def(&"generic")
	_check(tree != null and tree.nodes.size() == 3, "generic tree: skill root + two branches")
	var root_node: SkillNodeDef = tree.node(&"class_skill")
	var dmg_node: SkillNodeDef = tree.node(&"damage")
	var hp_node: SkillNodeDef = tree.node(&"vitality")
	_check(root_node != null and root_node.unlocks_skill and root_node.max_rank == 1,
		"tree root is the class-skill unlock node (1 rank)")
	_check(tree.gate_node_id == &"class_skill", "tree gates combat skill on the root node")
	_check(dmg_node != null and dmg_node.max_rank == 5 and is_equal_approx(dmg_node.damage_per_rank, 0.05)
			and dmg_node.requires_node == &"class_skill",
		"damage branch: 5 ranks, +5% attack per rank, requires skill root")
	_check(hp_node != null and hp_node.max_rank == 5 and is_equal_approx(hp_node.hp_per_rank, 0.06)
			and hp_node.requires_node == &"damage",
		"vitality branch: 5 ranks, +6% max hp per rank, requires damage rank 1")
	var hero_tree := GameDefs.skill_tree_def(&"hero")
	_check(hero_tree.node(&"class_skill") != null and hero_tree.node(&"class_skill").pre_unlocked,
		"hero tree root pre-unlocked (Q/C skills never gated)")
	_check(GameDefs.hero_warrior_def().skill_tree_id == &"hero", "hero def has skill tree")
	for cid in GameDefs.settler_def_ids():
		_check(GameDefs.settler_def(cid).skill_tree_id == &"generic",
			"settler %s def has skill tree" % String(cid))
	_check(GameDefs.colonist_def().skill_tree_id == &"" and GameDefs.refugee_def().skill_tree_id == &"" \
		and GameDefs.raider_def().skill_tree_id == &"",
		"colonist / refugee / raider have no skill tree")

	# ================= A. 流民入住职业选择 =================
	var build := world.get_node("BuildSystem") as BuildSystem
	var house_def: BuildingDef
	for definition in GameDefs.building_defs():
		if definition.id == &"house":
			house_def = definition
	build.enter_build_mode(house_def)
	build.try_place_at(Vector3(16.4, 0, 16.4))
	build.exit_build_mode()
	var houses := get_tree().get_nodes_in_group("house")
	_check(houses.size() == 1, "house placed for settle choice test")
	if not houses.is_empty() and hero != null:
		var house := houses[0] as Building
		var refugee: Pawn = spawner.call("spawn_refugee", house.global_position + Vector3(1.5, 0.0, 0.0))
		_check(refugee != null, "refugee spawned for choice flow")
		var settled_names: Array = []
		var on_settled := func(resident_name: String, _house: Node) -> void:
			settled_names.append(resident_name)
		EventBus.resident_settled.connect(on_settled)
		EventBus.refugee_arrived.emit(refugee, house)
		var picker = hud.get("settle_picker") if hud != null else null
		_check(picker != null and picker.get("is_open"), "class picker opens on refugee arrival")
		_check(TimeManager.time_scale <= 0.0, "class picker pauses the world")
		_check(SelectionManager.ui_modal_count >= 1, "class picker holds ui modal")
		_check(house.has_vacancy(), "house still vacant while awaiting choice")
		picker.call("_choose", &"settler_mage")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(not house.has_vacancy() and is_instance_valid(house.resident),
			"settler moves in after player choice")
		_check(house.resident is Soldier and (house.resident as Pawn).def.id == &"settler_mage",
			"settler class matches picked mage")
		_check(not is_instance_valid(refugee), "refugee freed after settling")
		_check(settled_names.size() == 1, "resident_settled emitted exactly once")
		_check(not picker.get("is_open"), "picker closes after choice")
		if hud.has_method("_dismiss_settlement_notice"):
			hud.call("_dismiss_settlement_notice")   # 收掉入住确认（暂停模态）
		EventBus.resident_settled.disconnect(on_settled)
		TimeManager.set_speed(1.0)

	# ================= B. 转职 =================
	if hero != null and spawner != null:
		var w: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-25.0, 0.0, -25.0))
		w.def.unit_name = "铁柱"
		w.gain_xp(310)   # 40+65+90+115 → Lv.5（+4 技能点）
		_check(w.level == 5, "warrior reaches Lv.5 via xp (%d)" % w.level)
		_check(w.skill_points == 4, "level ups granted 4 skill points (%d)" % w.skill_points)
		_check(w.try_invest_skill_point(&"class_skill"), "unlock class skill before promote")
		_check(w.try_invest_skill_point(&"damage"), "invest 1 damage point before promote")
		var promoted_events: Array = []
		var on_promoted := func(pawn: Node, new_def: Resource) -> void:
			promoted_events.append([pawn, new_def])
		EventBus.soldier_promoted.connect(on_promoted)
		# 先打掉一部分血：转职应按比例保留血量
		(w.health as HealthComponent).apply_damage(60.0, null)
		var ratio_before: float = w.health.ratio()
		# v33 统一返还口径：任何转职都清空已投入级数，并把花掉的点数全额退回
		var spent_before: int = w.skill_tree.points_spent()
		var points_left_before: int = w.skill_points
		_check(w.promote_to(&"settler_sniper") == false, "cannot promote to a class outside own branch")
		_check(w.promote_to(&"settler_knight"), "Lv.5 warrior promotes to knight")
		_check(w.def.id == &"settler_knight" and w.def.display_name == "骑士", "def swapped to knight")
		_check(w.def.unit_name == "铁柱" and w.get_display_name() == "铁柱", "name preserved on promote")
		_check(w.level == 5 and w.has_skill_tree() and w.skill_tree.points_spent() == 0
			and w.skill_tree.rank(&"class_skill") == 0 and w.skill_tree.rank(&"damage") == 0,
			"level preserved + all ranks cleared on promote")
		_check(w.skill_points == points_left_before + spent_before,
			"promote refunds every invested point (%d + %d = %d, got %d)"
			% [points_left_before, spent_before, points_left_before + spent_before, w.skill_points])
		_check(absf(w.health.ratio() - ratio_before) < 0.02,
			"hp ratio preserved on promote (%.2f vs %.2f)" % [w.health.ratio(), ratio_before])
		_check(w.health.max_hp > GameDefs.settler_warrior_def().max_hp * (1.0 + Pawn.GROWTH_HP * 4.0),
			"knight max hp above warrior base at same level")
		_check(promoted_events.size() == 1, "soldier_promoted emitted once")
		_check(w.can_promote() == false and w.promote_to(&"settler_berserker") == false,
			"advanced class cannot promote again")
		var low: Pawn = spawner.call("spawn_soldier", GameDefs.settler_mage_def(), Vector3(25.0, 0.0, -25.0))
		low.gain_xp(195)   # → Lv.4
		_check(low.level == 4 and low.can_promote() == false, "Lv.4 cannot promote yet")
		_check(low.promote_to(&"settler_elementalist") == false, "promote rejected below Lv.5")
		EventBus.soldier_promoted.disconnect(on_promoted)
		w.queue_free()
		low.queue_free()

	# ================= C. 小兵技能树（职业技先点出来） =================
	if hero != null and spawner != null:
		var s: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-25.0, 0.0, 25.0))
		_check(s.has_skill_tree(), "settler owns a skill tree")
		_check(s.skill_points == 0, "fresh settler has 0 skill points")
		_check(not s.combat_skill_unlocked(), "fresh settler's class skill is locked (must be unlocked on tree)")
		_check(s.try_cast_combat_skill(s) == false, "locked class skill cannot cast")
		_check(s.try_invest_skill_point(&"vitality") == false, "vitality locked before any damage rank")
		s.gain_xp(40)   # → Lv.2，+1 技能点
		_check(s.level == 2 and s.skill_points == 1, "level up grants 1 skill point")
		_check(s.try_invest_skill_point(&"damage") == false, "damage branch locked before skill root")
		_check(s.try_invest_skill_point(&"class_skill"), "unlock class skill root with a point")
		_check(s.combat_skill_unlocked(), "class skill unlocked after investing root node")
		var dmg_before: float = s.attacker.damage
		s.skill_points = 1
		_check(s.try_invest_skill_point(&"damage"), "invest damage rank 1 after skill root")
		_check(is_equal_approx(s.attacker.damage / dmg_before, 1.05),
			"damage rank 1 gives +5%% attack (%.2f->%.2f)" % [dmg_before, s.attacker.damage])
		_check(s.try_invest_skill_point(&"vitality") == false, "cannot invest without points")
		s.skill_points = 2
		var hp_mid: float = s.health.max_hp
		var cur_mid: float = s.health.current_hp
		_check(s.try_invest_skill_point(&"vitality"), "vitality unlocked after damage rank 1")
		_check(is_equal_approx(s.health.max_hp / hp_mid, 1.06),
			"vitality rank 1 gives +6%% max hp (%.1f->%.1f)" % [hp_mid, s.health.max_hp])
		_check(s.health.current_hp == cur_mid + (s.health.max_hp - hp_mid),
			"hp gain from tree fills into current hp")
		# 满级拦截：灌满点数，把伤害点到 5 级后不可再点
		s.skill_points = 10
		for _i in 6:
			s.try_invest_skill_point(&"damage")
		_check(s.skill_tree.rank(&"damage") == 5, "damage branch caps at rank 5")
		_check(s.try_invest_skill_point(&"damage") == false, "cannot invest beyond max rank")
		_check(is_equal_approx(s.skill_tree.damage_bonus(), 0.25), "damage bonus totals +25% at cap")
		var fresh: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(), Vector3(25.0, 0.0, 25.0))
		_check(fresh.attacker.damage > 0.0 and fresh.skill_tree != null
			and fresh.skill_tree.points_spent() == 0, "fresh spawn stats unaffected by empty tree")
		s.queue_free()
		fresh.queue_free()

	# ================= D. 主角技能树（根节点预点亮，Q/C 不受门禁） =================
	if hero != null:
		_check(hero.skill_tree != null and hero.skill_tree.rank(&"class_skill") == 1,
			"hero tree root pre-unlocked at spawn (no point spent)")
		var lv0: int = hero.level
		hero.gain_xp(hero.xp_to_next())   # 恰好升 1 级
		_check(hero.level == lv0 + 1 and hero.skill_points == 1, "hero level up grants 1 skill point")
		var hero_dmg_before: float = hero.attacker.damage
		var hero_hp_before: float = hero.health.max_hp
		var hero_mult_before: float = 1.0 + 0.12 * float(hero.level - 1)
		_check(hero.try_invest_skill_point(&"damage"), "hero invests damage rank 1")
		_check(is_equal_approx(hero.attacker.damage / hero_dmg_before,
			(hero_mult_before + 0.05) / hero_mult_before),
			"hero attack panel includes tree bonus (+5% additive into damage_mult)")
		hero.skill_points = 1
		_check(hero.try_invest_skill_point(&"vitality"), "hero invests vitality rank 1")
		_check(is_equal_approx(hero.health.max_hp / hero_hp_before, 1.06),
			"hero max hp includes tree bonus (+6%)")
		_check(is_equal_approx(hero.health.max_hp,
			(hero.hero_def.max_hp + 30.0 * float(hero.level - 1)) * 1.06),
			"hero hp formula = (320 + 30×(lv-1)) × tree bonus")
		_check(is_equal_approx(hero.damage_mult(), 1.0 + 0.12 * float(hero.level - 1) + 0.05),
			"hero damage_mult = level growth + tree bonus")

	# ================= E. 市民管理界面 =================
	if hero != null and spawner != null and hud != null:
		# 清场：收掉 A 段定居的市民、清空编队——面板断言需要确定性的成员基数
		if not houses.is_empty() and houses[0] is Building:
			var old_resident = (houses[0] as Building).resident
			if old_resident != null and is_instance_valid(old_resident):
				old_resident.queue_free()
		hero.set_party([])
		await get_tree().physics_frame

		# 入口按钮存在且不与既有面板重叠
		var btn = hud.get("citizen_button")
		var mmap = hud.get("minimap")
		var selp = hud.get("selection_panel")
		_check(btn != null and btn.visible, "citizen entry button assembled and visible")
		if btn != null and mmap != null:
			_check(not (btn as Control).get_global_rect().intersects((mmap as Control).get_global_rect()),
				"citizen button does not overlap minimap")
		if btn != null and selp != null:
			_check(not (btn as Control).get_global_rect().intersects((selp as Control).get_global_rect()),
				"citizen button does not overlap selection panel")

		# 造 3 名市民：自动入编队后移出 1 名 → 2 在队 / 1 自主
		var citizens: Array = []
		for i in 3:
			var d := GameDefs.settler_def(GameDefs.settler_def_ids()[i % 4])
			var c: Pawn = spawner.call("spawn_soldier", d, hero.global_position + Vector3(4.0 + float(i) * 1.6, 0.0, 0.0))
			c.def.unit_name = "市民%d" % i
			citizens.append(c)
		await get_tree().physics_frame
		hero.remove_party_member(citizens[2])
		await get_tree().physics_frame
		var panel = hud.get("party_panel")
		_check(panel != null, "citizen panel assembled (party_panel slot)")
		panel.call("open")
		await get_tree().process_frame
		_check(panel.get("is_open") and SelectionManager.ui_modal_count >= 1, "citizen panel opens as modal")
		_check(TimeManager.time_scale <= 0.0, "citizen panel pauses the world")

		# 滚轮屏蔽：模态遮罩挡得住点击、挡不住滚轮（Control 不 accept_event 的滚轮
		# 会穿到 _unhandled_input）——相机侧按 ui_modal_count 守卫，滚轮不得改视距
		var tp_cam: Node = world.get_node_or_null("ThirdPersonCamera")
		var iso_cam: Node = world.get_node_or_null("IsometricCamera")
		var tp_d0: float = tp_cam.get("target_distance") if tp_cam != null else 0.0
		var iso_d0: float = iso_cam.get("target_distance") if iso_cam != null else 0.0
		for wheel_btn in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var wheel_ev := InputEventMouseButton.new()
			wheel_ev.button_index = wheel_btn
			wheel_ev.pressed = true
			wheel_ev.position = Vector2(80, 80)   # 落在遮罩上（面板卡片之外）
			Input.parse_input_event(wheel_ev)
		await get_tree().process_frame
		await get_tree().process_frame
		var tp_same: bool = tp_cam == null or is_equal_approx(tp_cam.get("target_distance"), tp_d0)
		var iso_same: bool = iso_cam == null or is_equal_approx(iso_cam.get("target_distance"), iso_d0)
		_check(tp_same and iso_same,
			"wheel zoom blocked while citizen panel open (tp %s / iso %s)" % [tp_same, iso_same])
		_check(String(panel.get("_count_label").text).contains("2/4"), "panel shows 2/4 party members")
		var roster = panel.get("_roster_box")
		_check(roster != null and roster.get_children().size() == 3,
			"roster lists ALL citizens incl. in-party (%d)" % (roster.get_children().size() if roster != null else -1))
		var in_party_tags: Array = []
		_collect_text_nodes(roster, "［在队］", in_party_tags)
		_check(in_party_tags.size() == 2, "in-party citizens tagged (%d)" % in_party_tags.size())
		var hero_box = panel.get("_hero_row_box")
		var hero_pts: Array = []
		_collect_text_nodes(hero_box, "技能点", hero_pts)
		_check(hero_box != null and hero_box.get_children().size() > 0 and not hero_pts.is_empty(),
			"hero row shows skill points")

		# 转职按钮：Lv.5 市民出现两个进阶按钮，点击即转
		var officer: Pawn = citizens[0]
		officer.gain_xp(310)
		_check(officer.level == 5, "citizen reaches Lv.5 for promotion UI")
		panel.call("_refresh")
		var promote_btns: Array = []
		_collect_text_nodes(roster, "转职·", promote_btns)
		_check(promote_btns.size() == 2, "Lv.5 base citizen shows two promote buttons (%d)" % promote_btns.size())
		if not promote_btns.is_empty():
			(promote_btns[0] as Button).pressed.emit()
			await get_tree().process_frame
			_check(officer.def.promotes_to.is_empty(), "promote button applied advanced class")
			panel.call("_refresh")
			var done_tags: Array = []
			_collect_text_nodes(roster, "已进阶", done_tags)
			_check(done_tags.size() >= 1, "promoted citizen marked as advanced")

		# 技能树面板：行内按钮进入，Esc 语义关闭后回到市民管理
		var tree_btns: Array = []
		_collect_text_nodes(roster, "技能树", tree_btns)
		_check(tree_btns.size() >= 3, "every citizen row has skill tree entry (%d)" % tree_btns.size())
		var tree_panel = hud.get("skill_tree_panel")
		_check(tree_panel != null, "skill tree panel assembled")
		if not tree_btns.is_empty() and tree_panel != null:
			(tree_btns[0] as Button).pressed.emit()
			await get_tree().process_frame
			_check(tree_panel.get("is_open") and tree_panel.get("pawn") == officer,
				"skill tree opens for clicked citizen")
			var invest_btns: Array = []
			_collect_text_nodes(tree_panel, "加点", invest_btns)
			_check(invest_btns.size() >= 2, "each tree node has an invest button (%d)" % invest_btns.size())
			# 模拟 Esc 关闭：回到仍开着的市民管理（世界保持暂停）
			var esc_ev := InputEventAction.new()
			esc_ev.action = "cancel"
			esc_ev.pressed = true
			tree_panel.call("_unhandled_input", esc_ev)
			await get_tree().process_frame
			_check(not tree_panel.get("is_open") and panel.get("is_open"),
				"Esc closes skill tree back to citizen panel")
			_check(TimeManager.time_scale <= 0.0, "world stays paused while citizen panel open")
		panel.call("close")
		await get_tree().process_frame
		_check(not panel.get("is_open") and SelectionManager.ui_modal_count == 0,
			"closing citizen panel releases modal")
		_check(TimeManager.time_scale > 0.0, "closing citizen panel restores speed")

		# 正向对照：面板关闭后滚轮恢复缩放（守卫只针对模态开启期间）。
		# v42：玩家默认俯视角主控 → 当前相机是 IsometricCamera；第三人称仅在脚本接口下 current。
		# 断言按「当前相机」取，两种模式都成立。
		# 注意本项目滚轮方向是「下滚拉近」：zoom_out 绑 WHEEL_UP(4)、zoom_in 绑 WHEEL_DOWN(5)。
		var zoom_cam: Node = get_viewport().get_camera_3d()
		var zoom_d0: float = zoom_cam.get("target_distance") if zoom_cam != null else 0.0
		var wheel_go := InputEventMouseButton.new()
		wheel_go.button_index = MOUSE_BUTTON_WHEEL_UP   # → zoom_out，视距应变大
		wheel_go.pressed = true
		wheel_go.position = Vector2(80, 80)
		Input.parse_input_event(wheel_go)
		await get_tree().process_frame
		await get_tree().process_frame
		if zoom_cam != null:
			_check(zoom_cam.get("target_distance") > zoom_d0,
				"wheel zoom works again after panel closed (%.2f -> %.2f)" %
				[zoom_d0, zoom_cam.get("target_distance")])
			zoom_cam.set("target_distance", zoom_d0)   # 还原视距，不污染后续段落

		# 独立入口按钮：点击打开市民管理（等同 V）
		if btn != null:
			(btn as Button).pressed.emit()
			await get_tree().process_frame
			_check(panel.get("is_open"), "citizen entry button opens the panel")
			panel.call("close")
			await get_tree().process_frame

		for c in citizens:
			if is_instance_valid(c):
				c.queue_free()

	# 收尾：清掉定居残留的市民，交还环境
	if not houses.is_empty() and houses[0] is Building and is_instance_valid((houses[0] as Building).resident):
		var resid = (houses[0] as Building).resident
		if is_instance_valid(resid):
			resid.queue_free()
	print("CITIZEN MANAGE TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
