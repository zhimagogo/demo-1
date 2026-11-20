extends Node
## 第三人称 / 俯视角专项回归（v7，v15 扩三态，v42 镜头收敛）：
##   godot --headless --path . tests/ThirdPersonTest.tscn
## 覆盖：v42 默认俯视角主控（第三人称 / 战术俯瞰玩家入口屏蔽，Tab 不再换镜头）/
## 脚本接口仍可进第三人称与战术俯瞰 / RTS 下主角待命不自动索敌 /
## 俯视角主控 WASD 屏幕方向移动 / 准星射线与提示 / 建造距离限制 /
## 跳跃重力 / G 集结小队 / 震屏兼容。

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
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	var hero := controller.hero as Hero
	_check(hero != null and tp != null and iso != null, "world wires third-person stack")

	# ---- 默认视角（v42）：启动即俯视角主控，等距相机跟随主角 ----
	_check(SelectionManager.view_mode == SelectionManager.ViewMode.TOPDOWN,
		"game starts in top-down control mode")
	_check(SelectionManager.hero_mode_active, "top-down still counts as control mode")
	_check(iso.current and not tp.current and iso.follow_target == hero,
		"iso camera is current and follows the hero")
	_check(hero.state_machine.current_state.name == "hero_idle", "hero enters control idle state")

	# ---- Tab 屏蔽（v42）：玩家只剩俯视角主控 → 按 Tab 不换镜头（脚本接口保留）----
	controller.cycle_view_mode()
	await get_tree().physics_frame
	_check(SelectionManager.view_mode == SelectionManager.ViewMode.TOPDOWN and iso.current,
		"Tab no longer leaves top-down while other camera modes are masked")

	# 本文件的第三人称段落直接走脚本接口取景（玩家入口已屏蔽，实现仍保留）
	controller.enter_hero_mode()
	await get_tree().physics_frame
	_check(tp.current and not iso.current and tp.hero == hero,
		"enter_hero_mode still wires the third-person camera (script API)")

	# ---- 相机跟随：主角移动，相机保持在身后 ----
	Input.action_press("move_up")
	for _i in 20:
		await get_tree().physics_frame
	Input.action_release("move_up")
	var cam_dist: float = tp.global_position.distance_to(hero.global_position + Vector3(0, ThirdPersonCamera.PIVOT_HEIGHT, 0))
	_check(cam_dist < ThirdPersonCamera.MAX_DISTANCE + 1.0, "camera follows behind hero (boom %.1fm)" % cam_dist)

	# ---- 视角转动：add_look_delta 改变 yaw/pitch 并带钳制 ----
	var yaw_before: float = tp.yaw
	tp.add_look_delta(Vector2(300.0, 0.0))
	_check(not is_equal_approx(tp.yaw, yaw_before), "mouse delta turns camera yaw")
	tp.add_look_delta(Vector2(0.0, -99999.0))
	_check(tp.pitch <= ThirdPersonCamera.PITCH_LIMIT_UP + 0.01, "pitch clamped at up limit")
	tp.add_look_delta(Vector2(0.0, 99999.0))
	_check(tp.pitch >= -ThirdPersonCamera.PITCH_LIMIT_DOWN - 0.01, "pitch clamped at down limit")
	tp.pitch = -0.2

	# ---- 跳跃：request_jump → HeroIdleState 消费 → 竖直速度 ----
	_check(hero.is_on_floor(), "hero starts grounded")
	hero.request_jump()
	await get_tree().physics_frame
	_check(hero.velocity.y > 1.0, "jump request converts to vertical velocity (%.1f)" % hero.velocity.y)
	for _i in 60:
		await get_tree().physics_frame
		if hero.is_on_floor():
			break
	_check(hero.is_on_floor() and absf(hero.velocity.y) < 0.5, "gravity lands hero back on ground")

	# ---- 亲自挥砍：采集经济屏蔽（v22）——连招仍可打在树上，但不再入账 ----
	var tree: Node3D = null
	var best := INF
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: float = node.global_position.distance_to(hero.global_position)
		if d < best:
			best = d
			tree = node
	_check(tree != null and best < 40.0, "harvestable resource near hero (%.1fm)" % best)
	_check(not GameDefs.HARVEST_INCOME_ENABLED, "v22 harvest income disabled by flag")
	if tree != null:
		var wood_before: int = ResourceManager.get_amount(GameDefs.WOOD)
		var harvested := {"n": 0}
		var sig := func(_node, rid: StringName, amt: int):
			if rid == GameDefs.WOOD:
				harvested["n"] += amt
		EventBus.hero_harvested.connect(sig)
		# 走到树旁并对准它（第三人称真实路径：转向 + 朝向）。
		# 注意：yaw 写入后相机 transform 在下一渲染帧才应用，HeroController 又在物理帧
		# 读 forward_flat() 写 aim_dir —— 必须跨帧等待让链路收敛，否则扇形朝旧方向挥空。
		var to_tree := tree.global_position - hero.global_position
		to_tree.y = 0.0
		hero.global_position = tree.global_position - to_tree.normalized() * 2.2
		tp.yaw = atan2(-to_tree.x, -to_tree.z)
		tp.pitch = -0.18
		hero.aim_dir = to_tree.normalized()
		for _i in 6:
			await get_tree().physics_frame
		var attack_ok := hero.request_basic_attack()
		for _i in 45:
			await get_tree().physics_frame
		EventBus.hero_harvested.disconnect(sig)
		_check(attack_ok and hero.state_machine.current_state.name == "hero_idle",
			"combo starts and returns to control idle")
		_check(harvested["n"] == 0, "chopping yields no resources while harvesting disabled")
		_check(ResourceManager.get_amount(GameDefs.WOOD) == wood_before,
			"wood stock unchanged while harvesting disabled")

	# ---- 准星提示：采集屏蔽期树/石不再给「挥砍采集」提示（v22）----
	var prompt_info := {"kind": &"", "text": ""}
	var sig2 := func(_t, prompt: String, kind: StringName):
		prompt_info["kind"] = kind
		prompt_info["text"] = prompt
	EventBus.crosshair_target_changed.connect(sig2)
	for _i in 3:
		await get_tree().physics_frame
	controller._refresh_crosshair_prompt()
	await get_tree().process_frame
	EventBus.crosshair_target_changed.disconnect(sig2)
	_check(prompt_info["kind"] != &"resource",
		"crosshair no longer flags resources as harvestable (disabled)")

	# ---- 建造距离限制：远处拒绝 / 近处成功 ----
	var build := world.get_node("BuildSystem") as BuildSystem
	var wall_def: BuildingDef
	for definition in GameDefs.building_defs():
		if definition.id == &"wall":
			wall_def = definition
	hero.global_position = Vector3(0, 0, 12)
	build.enter_build_mode(wall_def)
	var walls_before := get_tree().get_nodes_in_group("building").filter(func(b): return (b as Building).def.id == &"wall").size()
	build.try_place_at(Vector3(18, 0, -18))    # 距 hero ≈ 35m：超 BUILD_RANGE，且城内合法
	var walls_mid := get_tree().get_nodes_in_group("building").filter(func(b): return (b as Building).def.id == &"wall").size()
	_check(walls_mid == walls_before, "build rejected beyond third-person range")
	build.try_place_at(Vector3(4, 0, 16))      # 距 hero ≈ 5.7m：合法
	var walls_after := get_tree().get_nodes_in_group("building").filter(func(b): return (b as Building).def.id == &"wall").size()
	_check(walls_after == walls_before + 1, "build accepted within range")
	build.exit_build_mode()

	# ---- 建造模式与操控共存：B 键进入建造不退出第三人称 ----
	_check(SelectionManager.hero_mode_active, "build mode coexists with third-person control")

	# v21：兵营 E 募兵已移除（原「E 交互弹招募菜单」段落删除）；
	# 招募 UI 不再装配也在此回归——HUD 不得残留 recruit_menu。
	var hud_v21 := _main.get_node_or_null("HUD")
	_check(hud_v21 != null and hud_v21.get("recruit_menu") == null,
		"recruit menu no longer assembled after barracks removal")

	# ---- G 集结 / 解散 ----
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var soldier: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), hero.global_position + Vector3(3, 0, 0))
	await get_tree().physics_frame
	controller._toggle_squad_rally()
	_check(hero.squad.size() == 1, "G rally recruits soldiers into squad")
	controller._toggle_squad_rally()
	_check(hero.squad.size() == 0, "G again disbands squad")
	soldier.queue_free()

	# ---- 战术俯瞰：脚本接口仍可进入（v42 玩家 Tab 入口已屏蔽），相机交接 + 主角待命 ----
	controller.exit_hero_mode()
	await get_tree().physics_frame
	_check(SelectionManager.view_mode == SelectionManager.ViewMode.TACTICAL
		and not SelectionManager.hero_mode_active and iso.current and not tp.current,
		"exit_hero_mode still enters RTS overview (script API)")

	# ---- RTS 俯瞰下主角不自动索敌：身边刷怪也保持待命，等玩家下令 ----
	var enemy: Pawn = (spawner as Node).call("spawn_raider", hero.global_position + Vector3(6, 0, 0), GameDefs.raider_def())
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _i in 30:
		await get_tree().physics_frame
	_check(hero.state_machine.current_state.name == "idle",
		"hero stays idle in RTS mode with enemy nearby (no auto-engage, awaits orders)")
	# 玩家仍可下令：选中主角 → 指派攻击 → 进入 fight（「等玩家操控」不是「不能打」）
	SelectionManager.select_only(hero)
	SelectionManager.issue_attack(enemy)
	await get_tree().physics_frame
	_check(hero.state_machine.current_state.name == "fight",
		"player attack order still engages hero in RTS mode")
	(enemy as Pawn).health.apply_damage(99999.0)   # 收尾：击杀试验怪，主角回 idle
	for _i in 20:
		await get_tree().physics_frame
	SelectionManager.clear()

	controller.set_view_mode(SelectionManager.ViewMode.TOPDOWN)
	await get_tree().physics_frame
	_check(SelectionManager.view_mode == SelectionManager.ViewMode.TOPDOWN
		and SelectionManager.hero_mode_active and iso.current and not tp.current
		and iso.follow_target == hero,
		"script API returns to top-down control (iso camera follows hero)")
	_check(hero.state_machine.current_state.name == "hero_idle",
		"TOPDOWN control enters hero idle state")
	_check(Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED,
		"TOPDOWN keeps mouse free for cursor aiming")

	# ---- v42 平滑推拉：滚轮只改目标视距，实际视距由阻尼逐帧收敛（不再一格一跳）----
	var dist_before: float = float(iso.get("_distance"))
	var target_before: float = iso.target_distance
	var wheel_out := InputEventMouseButton.new()
	wheel_out.button_index = MOUSE_BUTTON_WHEEL_UP   # zoom_out → 视距变大
	wheel_out.pressed = true
	wheel_out.factor = 1.0
	iso._unhandled_input(wheel_out)
	_check(is_equal_approx(iso.target_distance, target_before + iso.zoom_step),
		"wheel moves the target distance by exactly one zoom step")
	_check(is_equal_approx(float(iso.get("_distance")), dist_before),
		"wheel does not teleport the actual distance (smoothing runs in _process)")
	await get_tree().create_timer(0.8).timeout
	_check(absf(float(iso.get("_distance")) - iso.target_distance) < 0.2,
		"camera distance converges smoothly to the new target")
	# 截图 / 定场接口：snap_distance 立即对齐（不影响玩家滚轮的平滑推拉）
	iso.target_distance = 30.0
	iso.snap_distance()
	var snap_focus: Vector3 = iso.get("_focus")
	_check(is_equal_approx(float(iso.get("_distance")), 30.0)
		and absf(iso.global_position.distance_to(snap_focus) - 30.0) < 0.05,
		"snap_distance jumps straight to the target for stills")
	iso.target_distance = 44.0
	iso.snap_distance()

	# ---- 俯视角主控移动：WASD 按等距相机屏幕方向（input_to_world_dir 同一基底）----
	var pos_before := hero.global_position
	var expect_dir: Vector3 = iso.input_to_world_dir(Vector2(0, -1))   # W = 屏幕上方
	Input.action_press("move_up")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release("move_up")
	var moved: Vector3 = hero.global_position - pos_before
	moved.y = 0.0
	_check(moved.length() > 1.0 and moved.normalized().dot(expect_dir) > 0.9,
		"TOPDOWN WASD moves hero along iso screen basis (%.1fm)" % moved.length())

	# 战术俯瞰期间主角被下令转身（模拟右键下令移动）→ 切回后相机 yaw 必须对齐主角朝向，
	# 否则按 WASD 移动时视角朝旧方向歪掉（v7 真机反馈 bug 的回归线）
	hero.rotation.y = deg_to_rad(137.0)
	await get_tree().physics_frame
	controller.enter_hero_mode()
	await get_tree().physics_frame
	_check(SelectionManager.view_mode == SelectionManager.ViewMode.HERO
		and SelectionManager.hero_mode_active and tp.current,
		"script API enters third-person control")
	var f := hero.facing_dir()
	var expected_yaw: float = atan2(-f.x, -f.z)
	_check(absf(angle_difference(tp.yaw, expected_yaw)) < 0.05,
		"camera yaw re-aligns to hero facing after tactical round-trip")

	# ---- 震屏 duck-typing 兼容 ----
	tp.shake(0.3, 0.3)
	_check(true, "third-person camera accepts duck-typed shake")

	print("THIRD PERSON TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
