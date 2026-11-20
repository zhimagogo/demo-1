extends Node
## v33 定义层临时探针（Lead 自检用，跑完即删）：数据契约 + 技能树门禁 + 返还逻辑。
## 用法：bash tools/godot_locked.sh --headless --path . tools/v33_defs_probe.tscn

var _fails: int = 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)


func _ready() -> void:
	# 1. 四个新技能 def
	var ls := GameDefs.skill_leap_slam_def()
	var mt := GameDefs.skill_meteor_def()
	var ps := GameDefs.skill_piercing_shot_def()
	var st := GameDefs.skill_stealth_def()
	_check(ls.kind == PawnSkillDef.Kind.LEAP_SLAM and ls.cooldown > 0.0 and ls.radius > 0.0
		and ls.stun_duration > 0.0 and ls.knockback_distance > 0.0, "leap_slam def")
	_check(mt.kind == PawnSkillDef.Kind.METEOR and mt.windup > 0.0 and mt.telegraph > 0.0
		and mt.damage >= 40.0, "meteor def")
	_check(ps.kind == PawnSkillDef.Kind.PIERCING_SHOT and ps.pierce_length >= 20.0
		and ps.damage > 0.0, "piercing_shot def")
	_check(st.kind == PawnSkillDef.Kind.STEALTH and st.stealth_duration > 0.0
		and st.escape_hp_ratio > 0.0, "stealth def")

	# 2. 进阶 def 挂载 extra_skills + 专属树
	var map := {
		&"settler_berserker": [&"leap_slam", &"settler_berserker_tree"],
		&"settler_elementalist": [&"meteor", &"settler_elementalist_tree"],
		&"settler_sniper": [&"piercing_shot", &"settler_sniper_tree"],
		&"settler_slayer": [&"stealth", &"settler_slayer_tree"],
	}
	for adv_id in map.keys():
		var d: PawnDef = GameDefs.settler_advanced_def(adv_id)
		var want: Array = map[adv_id]
		_check(d != null and d.all_skills().size() == 2 and d.has_skill_id(want[0]),
			"%s 持有主技能 + %s" % [adv_id, want[0]])
		_check(d.skill_tree_id == want[1], "%s 树 id = %s" % [adv_id, want[1]])
	# 骑士等未加新技能的进阶职业保持单技能 + generic 树（不回归）
	var kn: PawnDef = GameDefs.settler_advanced_def(&"settler_knight")
	_check(kn.all_skills().size() == 1 and kn.skill_tree_id == &"generic", "knight 不受影响")

	# 3. 树结构 + 门禁
	for adv_id in map.keys():
		var d: PawnDef = GameDefs.settler_advanced_def(adv_id)
		var tree := GameDefs.skill_tree_def(d.skill_tree_id)
		_check(tree.node(&"advanced_skill") != null
			and tree.node(&"advanced_skill").unlocks_skill_id == map[adv_id][0],
			"%s 树含 advanced_skill 节点" % d.skill_tree_id)
	_check(GameDefs.skill_tree_def(&"generic").node(&"advanced_skill") == null, "generic 树无新节点")

	# 4. 运行时：门禁 + 返还
	var rt := PawnSkillTree.new()
	rt.tree_def = GameDefs.skill_tree_def(&"settler_slayer_tree")
	rt.apply_pre_unlocks()
	_check(not rt.is_skill_unlocked(&"backstab") and not rt.is_skill_unlocked(&"stealth"),
		"未加点：主技能与新技能都锁着")
	var pts := 5
	_check(rt.invest(&"class_skill", pts) and rt.invest(&"advanced_skill", pts), "两点可加")
	_check(rt.is_skill_unlocked(&"backstab") and rt.is_skill_unlocked(&"stealth"), "点亮后双技能解锁")
	_check(not rt.is_skill_unlocked(&"meteor"), "别的职业的技能仍然锁着")
	rt.invest(&"damage", pts)
	_check(rt.points_spent() == 3, "已花 3 点（points_spent=%d）" % rt.points_spent())
	var refund := rt.reset_and_refund()
	_check(refund == 3 and rt.points_spent() == 0 and rt.rank(&"class_skill") == 0
		and not rt.is_skill_unlocked(&"stealth"), "返还 %d 点且节点全清" % refund)
	# 换树：进阶 → 换另一棵进阶树
	rt.set_tree_def(GameDefs.skill_tree_def(&"settler_sniper_tree"))
	_check(rt.tree_def.id == &"settler_sniper_tree" and rt.rank(&"advanced_skill") == 0,
		"换树后布局与加点都重置")
	# 旧树（generic）语义保持：gate 根节点门禁
	var old_tree := PawnSkillTree.new()
	old_tree.tree_def = GameDefs.skill_tree_def(&"generic")
	_check(not old_tree.is_skill_unlocked(&"whatever") and not old_tree.skill_unlocked(),
		"generic 树仍是 gate 根节点语义")
	old_tree.invest(&"class_skill", 1)
	_check(old_tree.is_skill_unlocked(&"whatever") and old_tree.skill_unlocked(),
		"generic 树点亮根节点后解锁")

	print("PROBE_RESULT fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
