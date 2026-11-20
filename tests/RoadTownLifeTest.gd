extends Node
## 土路施工、四邻拼接、真实寻路偏好、速度叠加与城内生活 / 双人社交回归。

var failures := 0
var checks := 0
var world: Node3D
var grid: GridSystem
var nav: NavSystem
var build: BuildSystem
var spawner: Node
var road_def: BuildingDef

func _ready() -> void:
	get_tree().create_timer(45.0, true, false, true).timeout.connect(func():
		push_error("FAIL: 道路生活测试超时")
		get_tree().quit(1))
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

func road_at(point: Vector3) -> Building:
	build.try_place_at(point)
	return grid.road_cells.get(grid.world_to_grid(point)) as Building

func clear_roads() -> void:
	for node in get_tree().get_nodes_in_group("road"):
		node.free()

func make_soldier(point: Vector3) -> Soldier:
	var soldier: Soldier = spawner.spawn_soldier(GameDefs.settler_warrior_def(), point)
	soldier.state_machine.set_physics_process(false)
	soldier.set_process(false)
	soldier.speech_bubble.debug_set_timer(999.0)
	return soldier

func _run() -> void:
	AudioManager._streams[&"build_place"] = null
	AudioManager._streams[&"build_error"] = null
	TimeManager.begin(10)
	GameManager.phase = GameManager.Phase.BUILD
	SelectionManager.ui_modal_count = 0
	ResourceManager.add(GameDefs.GOLD, 1000)
	world = Node3D.new()
	add_child(world)
	grid = GridSystem.new()
	grid.name = "GridSystem"
	grid.debug_visible = false
	world.add_child(grid)
	var city := CitySystem.new()
	city.name = "CitySystem"
	city.city_half = WorldLayout.CITY_HALF   # v43：与主城 52×52m 同步（26m 半宽）
	world.add_child(city)
	nav = NavSystem.new()
	world.add_child(nav)
	build = BuildSystem.new()
	build.name = "BuildSystem"
	world.add_child(build)
	build.set_process(false)
	var pawns := Node3D.new()
	world.add_child(pawns)
	var enemies := Node3D.new()
	world.add_child(enemies)
	spawner = load("res://scripts/systems/PawnSpawner.gd").new()
	world.add_child(spawner)
	spawner.configure(pawns, enemies)
	for d in GameDefs.building_defs():
		if d.is_road:
			road_def = d
	check(road_def != null and road_def.id == &"dirt_road" and not road_def.bakes_into_navmesh,
		"土路有独立定义且不是障碍")
	if road_def == null:
		get_tree().quit(1)
		return
	build.enter_build_mode(road_def)
	var anchor := Vector3(11, 0, 11)
	var cell := grid.world_to_grid(anchor)
	# 枚举全部 16 种四邻组合，并实际释放邻格验证连接回退。
	for mask in 16:
		clear_roads()
		var center := road_at(anchor)
		for i in 4:
			if mask & (1 << i):
				road_at(grid.grid_to_world(cell + grid.ROAD_NEIGHBORS[i]))
		check(center != null and center.road_connections == mask, "道路四邻样式 %d" % mask)
	check(nav.is_walkable_cell(cell) and not nav.road_grid.is_point_solid(cell), "道路不阻挡两套路径")
	check(not grid.can_place(cell, Vector2i.ONE), "道路占地避免重复建筑叠放")
	clear_roads()
	check(grid.road_cells.is_empty() and grid.can_place(cell, Vector2i.ONE), "直接拆路释放占地")
	check(is_equal_approx(nav.road_grid.get_point_weight_scale(cell), 1.2), "拆路恢复草地权重")
	var amount := ResourceManager.get_amount(GameDefs.GOLD)
	build.begin_road_stroke(Vector3(-17, 0, 11))
	build.paint_road_to(Vector3(-7, 0, 11))
	build.paint_road_to(Vector3(-7, 0, 17))
	build.paint_road_to(Vector3(-17, 0, 11))
	build.end_road_stroke()
	var count := grid.road_cells.size()
	check(count >= 9 and ResourceManager.get_amount(GameDefs.GOLD) == amount - count, "快速拖动补齐格子且重复经过不重复扣费")
	var before := grid.road_cells.size()
	build.paint_road_to(Vector3(17, 0, 17))
	check(grid.road_cells.size() == before, "松开后不继续铺路")
	amount = ResourceManager.get_amount(GameDefs.GOLD)
	build.try_place_at(Vector3(0, 0, 0))
	# v43：主城半宽 26m → 城外测试点必须 >26m（仍留在地图 ±32m 内，且模拟世界无湖/资源点）
	build.try_place_at(Vector3(WorldLayout.CITY_HALF + 3.0, 0, 11))
	check(ResourceManager.get_amount(GameDefs.GOLD) == amount, "主城地基和城外禁铺且不扣钱")
	clear_roads()
	# 1 格侧移道路比直穿草地更快；平滑必须保留上路和下路拐点。
	for x in range(-17, 18, 2):
		road_at(Vector3(x, 0, 13))
	var start := Vector3(-17, 0, 11)
	var goal := Vector3(17, 0, 11)
	var direct := nav.get_world_path(start, goal)
	var preferred := nav.get_world_path(start, goal, true)
	var on_road := false
	for point in preferred:
		if grid.has_road(grid.world_to_grid(point)):
			on_road = true
	check(on_road and preferred.size() > direct.size(), "友军路径保留道路绕行，普通路径仍直走")
	var soldier := make_soldier(Vector3(-15, 0, 13))
	check(is_equal_approx(soldier.effective_move_speed(), soldier.move_speed * 1.2), "小兵上路移速 +20%")
	soldier.speed_multiplier = 2.0
	soldier.apply_slow(0.5, 10.0)
	check(is_equal_approx(soldier.effective_move_speed(), soldier.move_speed * 2.0 * 0.5 * 1.2), "道路与集结 / 减速相乘且不改基础移速")
	soldier.global_position = start
	check(is_equal_approx(soldier.road_speed_multiplier(), 1.0), "小兵离路立即取消加速")
	var refugee: Refugee = spawner.spawn_refugee(Vector3(-13, 0, 13))
	refugee.state_machine.set_physics_process(false)
	check(refugee.prefers_roads() and is_equal_approx(refugee.road_speed_multiplier(), 1.2), "流民同样沿路且获得加速")
	var enemy_def := GameDefs.raider_def()
	var raider: Raider = spawner.spawn_raider(Vector3(-11, 0, 13), enemy_def)
	raider.state_machine.set_physics_process(false)
	check(not raider.prefers_roads() and is_equal_approx(raider.road_speed_multiplier(), 1.0), "敌人不享受友军道路加成")
	raider.free()
	refugee.free()
	soldier.free()
	clear_roads()
	# 实际走完整条道路，确认不是仅返回一条看似优选的路径。
	for x in range(-17, 18, 2):
		road_at(Vector3(x, 0, 13))
	soldier = make_soldier(start)
	soldier.set_navigation_target(goal, true)
	var road_frames := 0
	var arrived := false
	for i in 900:
		await get_tree().physics_frame
		arrived = soldier.move_along_path(1.0 / 60.0)
		if soldier.road_speed_multiplier() > 1.0:
			road_frames += 1
		if arrived:
			break
	check(arrived and road_frames > 100, "小兵实际沿道路行走并到达目标")
	soldier.global_position = Vector3(11, 0, 9)
	soldier.state_machine.transition_to("idle")
	soldier.state_machine.current_state.physics_update(1.0 / 60.0)
	check(soldier.state_machine.current_state.name == &"wander", "白天新居民也在城内生活")
	soldier.town_life_active = false
	soldier.patrol_left = 0.1
	soldier.state_machine.transition_to("patrol")
	soldier._process(0.2)
	soldier.state_machine.current_state.physics_update(0.1)
	check(soldier.town_life_active and soldier.state_machine.current_state.name == &"idle", "巡逻预算耗尽后回城生活")
	var other := make_soldier(Vector3(13, 0, 9))
	soldier.state_machine.transition_to("wander")
	other.state_machine.transition_to("wander")
	soldier.chat_cooldown = 0.0
	other.chat_cooldown = 0.0
	check(soldier.try_chat_with(other), "城内相遇小兵开始双人聊天")
	check(soldier.state_machine.current_state.name == &"chat" and other.state_machine.current_state.name == &"chat", "双方进入聊天并停步")
	check(soldier.speech_bubble.is_showing(), "发起者显示第一句对白")
	var s0 := soldier.global_position
	var s1 := other.global_position
	for i in 180:
		await get_tree().physics_frame
		soldier.state_machine.current_state.physics_update(1.0 / 60.0)
		other.state_machine.current_state.physics_update(1.0 / 60.0)
	check(soldier.global_position.distance_to(s0) < 0.01 and other.global_position.distance_to(s1) < 0.01, "聊天期间双方站定")
	check(other.speech_bubble.is_showing(), "同伴稍后接话")
	var leader := Node3D.new()
	world.add_child(leader)
	leader.position = Vector3(11, 0, 7)
	soldier.follow_leader = leader
	soldier.state_machine.current_state.physics_update(0.1)
	check(soldier.state_machine.current_state.name == &"follow" and soldier.chat_partner == null, "集结优先打断聊天")
	other.state_machine.current_state.physics_update(0.1)
	check(other.state_machine.current_state.name != &"chat" and other.chat_partner == null, "聊天预约双向释放")
	check(soldier.chat_cooldown > 0.0 and other.chat_cooldown > 0.0, "聊天结束后冷却防反复重聊")
	soldier.follow_leader = null
	leader.free()
	soldier.state_machine.transition_to("wander")
	other.state_machine.transition_to("wander")
	soldier.chat_cooldown = 0.0
	other.chat_cooldown = 0.0
	soldier.speech_bubble.hide_now()
	other.speech_bubble.hide_now()
	check(soldier.try_chat_with(other), "冷却解除后可再次聊天")
	other.free()
	soldier.state_machine.current_state.physics_update(0.1)
	check(soldier.state_machine.current_state.name != &"chat", "同伴直接释放后安全结束聊天")
	# 完整聊完、受伤中断、城外拒聊与驻守拒聊。
	other = make_soldier(soldier.global_position + Vector3(2, 0, 0))
	soldier.state_machine.transition_to("wander")
	other.state_machine.transition_to("wander")
	soldier.chat_cooldown = 0.0
	other.chat_cooldown = 0.0
	soldier.speech_bubble.hide_now()
	other.speech_bubble.hide_now()
	check(soldier.try_chat_with(other), "新同伴可建立聊天预约")
	for i in 370:
		await get_tree().physics_frame
		soldier.state_machine.current_state.physics_update(1.0 / 60.0)
		other.state_machine.current_state.physics_update(1.0 / 60.0)
	check(soldier.state_machine.current_state.name != &"chat" and other.state_machine.current_state.name != &"chat",
		"聊天自然结束并恢复日常")
	soldier.state_machine.transition_to("wander")
	other.state_machine.transition_to("wander")
	soldier.chat_cooldown = 0.0
	other.chat_cooldown = 0.0
	soldier.speech_bubble.hide_now()
	other.speech_bubble.hide_now()
	check(soldier.try_chat_with(other), "受伤中断测试建立会话")
	soldier.health.current_hp = soldier.health.max_hp * 0.5
	soldier.state_machine.current_state.physics_update(0.1)
	other.state_machine.current_state.physics_update(0.1)
	check(soldier.chat_partner == null and other.chat_partner == null, "受伤立刻结束双人聊天")
	soldier.health.current_hp = soldier.health.max_hp
	soldier.chat_cooldown = 0.0
	other.chat_cooldown = 0.0
	soldier.state_machine.transition_to("wander")
	other.state_machine.transition_to("wander")
	soldier.stance = Pawn.Stance.HOLD
	check(not soldier.try_chat_with(other), "驻守指令优先，驻守兵不擅自聊天")
	soldier.stance = Pawn.Stance.DEFENSIVE
	# v43：主城半宽 26m；把对话双方放到城外（>26m）验证拒聊，仍在测试地图 ±32m 内。
	soldier.global_position = Vector3(WorldLayout.CITY_HALF + 3.0, 0, 9)
	other.global_position = Vector3(WorldLayout.CITY_HALF + 5.0, 0, 9)
	check(not soldier.try_chat_with(other), "城外士兵不会停下闲聊")
	# 沿路权重缓存与现场状态同帧更新，清路后仍可穿行。
	var road_cell := grid.world_to_grid(Vector3(1, 0, 13))
	var tile = grid.road_cells.get(road_cell)
	if is_instance_valid(tile):
		tile.free()
	check(not grid.has_road(road_cell) and is_equal_approx(nav.road_grid.get_point_weight_scale(road_cell), 1.2)
		and nav.is_walkable_cell(road_cell), "同帧拆路恢复成本且保持可走")
	var amount_before_pause := ResourceManager.get_amount(GameDefs.GOLD)
	TimeManager.set_speed(0.0)
	build.begin_road_stroke(Vector3(-17, 0, -17))
	check(not build._road_painting and ResourceManager.get_amount(GameDefs.GOLD) == amount_before_pause,
		"暂停期间长按不施工、不扣费")
	TimeManager.set_speed(1.0)
	build.exit_build_mode()
	print("RoadTownLifeTest: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
