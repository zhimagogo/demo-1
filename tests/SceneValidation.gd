extends Node
## 场景回归（v3 扩展）：godot --headless --path . tests/SceneValidation.tscn
## 实际渲染留图：godot --path . tests/SceneValidation.tscn -- --capture
## 覆盖：地图 / 寻路 / 湖泊（继承自 v2）+ 村民经济 / 兵营募兵 / 昼夜 / 天气 / 主角经验 / 姿态 / 新 UI。

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
	var world := _main.get_node("WorldRoot")
	var grid := world.get_node("GridSystem") as GridSystem
	var nav := world.get_node("NavSystem") as NavSystem
	var camera := world.get_node("IsometricCamera") as IsometricCamera
	var city := world.get_node("CitySystem") as CitySystem
	camera.edge_pan = false
	world.get_node("WildlifeSpawner").set_process(false)
	world.get_node("ResourceGrowthSystem").set_process(false)   # 冻结资源再生：42 个点的断言才稳定
	# v40 世界扩张：可玩面 128×128m → 256×256m（128×128 格 @2m，半宽 = MAP_HALF = 128m）
	_check(grid.grid_size == Vector2i(128, 128) and is_equal_approx(grid.half_x(), WorldLayout.MAP_HALF), "256×256 ground / grid bounds")
	_check(is_equal_approx(city.city_half, WorldLayout.CITY_HALF) and is_equal_approx(city.city_half, 26.0),
		"52×52 buildable city")
	_check(grid.terrain_cells.size() > 100, "lake registered in terrain grid")
	var blocked_resources := 0
	for resource: Node3D in get_tree().get_nodes_in_group("resource_node"):
		var cell := grid.world_to_grid(resource.global_position)
		if grid.terrain_cells.has(cell):
			blocked_resources += 1
	_check(blocked_resources == 0, "every resource is on dry land")
	_check(get_tree().get_nodes_in_group("resource_node").size() == 42, "42 unique harvestable resources")
	var lake_path := nav.get_world_path(Vector3(20, 0, -38), Vector3(84, 0, -38))
	# v6 路径平滑后航点数大幅减少，断言改为路径真实长度：
	# v43 湖泊东迁到 (52,-38)：两点直线距 64m 且被 34×24m 的湖阻隔，绕湖路径必然显著更长（>60m）。
	var lake_path_len := 0.0
	for i in range(1, lake_path.size()):
		lake_path_len += lake_path[i].distance_to(lake_path[i - 1])
	if lake_path.size() > 0:
		lake_path_len += lake_path[0].distance_to(Vector3(16, 0, -28))
	_check(lake_path.size() >= 2 and lake_path_len > 60.0, "path connects opposite lakeshores")
	var path_is_dry := not lake_path.is_empty()
	for point in lake_path:
		path_is_dry = path_is_dry and not grid.terrain_cells.has(grid.world_to_grid(point))
	_check(path_is_dry, "A* routes around lake")
	var lake_snap := nav.snap_to_walkable(Vector3(52, 0, -38))
	_check(not grid.terrain_cells.has(grid.world_to_grid(lake_snap)), "lake-center spawn snaps onto shore")
	# v40：旧断言点 (90,90) 在扩张后已属图内，改用真正越界的 (200,200) 验证点击吸附回图内
	var outside_path := nav.get_world_path(Vector3.ZERO, Vector3(200, 0, 200))
	_check(not outside_path.is_empty() and grid.is_inside(grid.world_to_grid(outside_path[outside_path.size() - 1])), "off-map click resolves inside map")
	_check(grid.can_place(grid.world_to_grid(Vector3(16, 0, 16)), Vector2i(3, 3)), "new city extension accepts house footprint")
	_check(not grid.can_place(grid.world_to_grid(Vector3(52, 0, -38)), Vector2i.ONE), "water rejects construction")
	_check(nav.path_grid.is_point_solid(grid.world_to_grid(Vector3.ZERO)), "castle foundation blocks paths")
	# 用实际物理查询核对湖内与地图外侧阻挡，而非只验证数据表。
	var lake_hit := _ray(world, Vector3(52, 1, -38), Vector3(72, 1, -38))
	_check(not lake_hit.is_empty(), "lake has physical collision for WASD movement")
	# v40：边界墙立在新地图边缘（±MAP_HALF+0.5），旧 ±64m 位置已属图内
	var edge_hit := _ray(world, Vector3(WorldLayout.MAP_HALF - 2.0, 1, 0), Vector3(WorldLayout.MAP_HALF + 4.0, 1, 0))
	_check(not edge_hit.is_empty(), "map boundary stops direct movement")
	# Tab 模式与实际角色移动仍走原有控制器。
	var controller := world.get_node("HeroController") as HeroController
	controller.enter_hero_mode()
	var hero := controller.hero
	var before := hero.global_position
	Input.action_press("move_down")
	for _i in 30:
		await get_tree().physics_frame
	Input.action_release("move_down")
	_check(hero.global_position.distance_to(before) > 0.5, "hero mode moves on expanded ground")
	hero.request_basic_attack()
	await get_tree().physics_frame
	_check(hero.state_machine.current_state.name == "hero_combo", "hero attack state still starts")
	controller.exit_hero_mode()
	_check(not SelectionManager.hero_mode_active and camera.follow_target == null, "RTS mode restores camera")
	# —— v3：新 UI 装配 ——
	var hud := _main.get_node_or_null("HUD")
	_check(hud != null and hud.get("minimap") != null, "HUD assembles minimap")
	_check(hud != null and hud.get("quest_panel") != null, "HUD assembles quest panel")
	_check(hud != null and hud.get("boss_banner") != null and hud.get("floating_labels") != null, "HUD assembles boss banner + damage numbers")
	# —— v3：任务链就绪 ——
	var quests := world.get_node("QuestSystem") as QuestSystem
	_check(quests != null and quests.quests.size() >= 8 and quests.current_index == 0, "quest chain ready at step 1 (%d quests)" % (quests.quests.size() if quests != null else -1))
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture(camera)
	await _check_build_and_settlement(world, camera)
	await _check_barracks_removed(world)
	await _check_squad_party_flow(world)
	await _check_walk_surface(world)
	await _check_daynight_and_weather(world)
	await _check_hero_xp_and_stance(hero)
	await _check_weapon_loadout(hero)
	await _check_tutorial_flow(world)
	await _check_pause_menu(world)
	print("SCENE VALIDATION: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _ray(world: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.hit_from_inside = true
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _check_build_and_settlement(world: Node3D, camera: IsometricCamera) -> void:
	camera.target_distance = 44
	camera.focus_on(Vector3.ZERO)
	await get_tree().process_frame
	var build := world.get_node("BuildSystem") as BuildSystem
	var house_def: BuildingDef
	for definition in GameDefs.building_defs():
		if definition.id == &"house":
			house_def = definition
	build.enter_build_mode(house_def)
	build.try_place_at(Vector3(16.4, 0, 16.4))
	build.exit_build_mode()
	var houses := get_tree().get_nodes_in_group("house")
	_check(houses.size() == 1, "house placement through actual build system")
	if houses.is_empty():
		return
	var house := houses[0] as Building
	_check(house.global_position.distance_to(Vector3(19, 0, 19)) < 0.1, "house occupies a 3x3 footprint inside the expanded city")
	var nav := world.get_node("NavSystem") as NavSystem
	_check(nav.path_grid.is_point_solid(house.cell), "new house updates navigation")
	# v43：房屋 3×3（6×6m）后，目标格 (19,19) 落在占地内 → 航点吸附到最近可走格；
	# 从吸附格再寻路必须是单点（同格到达保留安全落点，不能把单位送进房基）。
	var house_snap := nav.snap_to_walkable(Vector3(19, 0, 19))
	var adjacent_path := nav.get_world_path(house_snap, Vector3(19, 0, 19))
	_check(adjacent_path.size() == 1 and adjacent_path[0].is_equal_approx(house_snap), "same-cell approach retains safe arrival waypoint")
	var settlement := world.get_node("SettlementSystem") as SettlementSystem
	settlement.set_process(false)
	seed(42)
	settlement._spawn_refugee_for(house)
	_check(get_tree().get_nodes_in_group("refugee").size() == 1, "vacant house attracts refugee through PawnSpawner")
	TimeManager.set_speed(3.0)
	# v25 流民入住职业选择：流民抵房后不再随机觉醒，而是弹窗等玩家点选——
	# 这里模拟玩家点「战士」卡（picker._choose），验证暂停 / 模态 / 选择生效全链路。
	var settlement_hud := _main.get_node_or_null("HUD")
	var picker = settlement_hud.get("settle_picker") if settlement_hud != null else null
	var picked: bool = false
	for _i in 900:
		if picker != null and picker.get("is_open"):
			picked = true
			break
		if not house.has_vacancy():
			break   # 无 HUD 弹窗环境（理论上不发生）：回落随机觉醒
		await get_tree().physics_frame
	_check(picked, "settlement pauses with class picker for player choice (v25)")
	if picked:
		_check(TimeManager.time_scale <= 0.0 and SelectionManager.ui_modal_count >= 1,
			"class picker opens as modal and pauses the world")
		picker.call("_choose", &"settler_warrior")
		await get_tree().physics_frame
	for _i in 60:
		if not house.has_vacancy():
			break
		await get_tree().physics_frame
	_check(not house.has_vacancy() and is_instance_valid(house.resident), "refugee reaches house and becomes resident")
	_check(house.resident is Soldier, "settler converts to Soldier (random class combat unit)")
	if house.resident is Soldier:
		var settler := house.resident as Soldier
		_check(settler.def.id == &"settler_warrior", "settler class matches player choice: %s" % str(settler.def.id))
		_check(settler.def.unit_name != "" and settler.get_display_name() == settler.def.unit_name, "settler receives random name")
		_check(settler.home == house, "settler is assigned to the house (home)")
		_check(settler.state_machine != null and settler.state_machine.states.has("patrol")
			and settler.state_machine.states.has("wander") and settler.state_machine.states.has("rest"),
			"soldier life states registered (patrol/wander/rest)")
	# 新居民白天先在城内生活，随后与短时巡逻交替；不再要求定居后立即出城猎杀。
	var living := false
	for _i in 120:
		await get_tree().physics_frame
		if is_instance_valid(house.resident) and house.resident.state_machine != null:
			var st: String = house.resident.state_machine.current_state.name
			if st in ["wander", "rest", "chat", "move"]:
				living = true
				break
	_check(living, "settler starts a daytime town life routine")
	TimeManager.set_speed(1.0)


## v21/v22：建筑表契约——无兵营（v21）、无农田/市集/箭塔（v22），有木墙/房屋/酒馆；
## 造价统一金币；招募 UI 不存在；四职业小兵全部可成长（编译期即保证旧接口已删除）。
func _check_barracks_removed(world: Node3D) -> void:
	var ids: Array = []
	var gold_only: bool = true
	for definition in GameDefs.building_defs():
		ids.append(definition.id)
		for rid in definition.cost:
			if rid != GameDefs.GOLD:
				gold_only = false
	_check(not ids.has(&"barracks") and not ids.has(&"farm") and not ids.has(&"market")
			and not ids.has(&"turret"), "removed buildings stay out (barracks/farm/market/turret; %d remain)" % ids.size())
	_check(ids.has(&"wall") and ids.has(&"house") and ids.has(&"tavern"), "core buildings intact (wall/house/tavern)")
	_check(gold_only, "v22 all building costs are gold-only")
	var hud := _main.get_node_or_null("HUD")
	_check(hud != null and hud.get("recruit_menu") == null, "recruit menu no longer assembled in HUD")
	# 小兵全部来自流民定居：四职业 def 齐全且全部参与等级成长（近战/远程募兵兵种已删除）
	var settler_ids := GameDefs.settler_def_ids()
	_check(settler_ids.size() == 4, "exactly four settler class defs remain")
	_check(GameDefs.settler_warrior_def().can_level and GameDefs.settler_mage_def().can_level
			and GameDefs.settler_assassin_def().can_level and GameDefs.settler_archer_def().can_level,
			"all four settler classes participate in the level system")
	_check(not GameDefs.colonist_def().can_level and not GameDefs.refugee_def().can_level
			and not GameDefs.raider_def().can_level, "non-minion defs stay out of the level system")


## v10：编队（上限 4）/ G 集结 / T 集火 / 瞄准红描边 / 编队界面 / 夜晚回城驻防。
func _check_squad_party_flow(world: Node3D) -> void:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var controller := world.get_node("HeroController") as HeroController
	var hud := _main.get_node_or_null("HUD")
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	_check(hero != null and spawner != null and controller != null, "hero / spawner / controller available for squad flow")
	if hero == null or spawner == null or controller == null:
		return
	# 收掉定居测试残留的入驻提示（占模态 + 暂停），保证后续模态断言从干净状态起步
	if hud != null and hud.has_method("_dismiss_settlement_notice"):
		hud._dismiss_settlement_notice()
	TimeManager.set_speed(1.0)
	# 清理此前测试的敌人（避免集火 / 夜晚回城被无关战斗干扰）
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().physics_frame

	# —— 1) 士兵出生自动入编队，编队上限 4（+ 主角 = 5 人编制）——
	var party_before: int = hero.alive_party().size()
	var class_defs := [GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def(), GameDefs.settler_warrior_def(),
		GameDefs.settler_mage_def()]
	var spawned: Array = []
	for i in class_defs.size():
		var s: Pawn = (spawner as Node).call("spawn_soldier", class_defs[i], hero.global_position + Vector3(3.0 + float(i) * 1.5, 0.0, 0.0))
		spawned.append(s)
	await get_tree().physics_frame
	_check(hero.party.size() == Hero.SQUAD_MAX, "party auto-fills to cap 4 on soldier spawn (%d)" % hero.party.size())
	_check(hero.party.size() == party_before + (Hero.SQUAD_MAX - mini(party_before, Hero.SQUAD_MAX)), "auto-add stops at cap")
	# 小队成员列表已在 v17 并入主角面板（去冗余合并卡），必须列出全部编队成员
	# （HUD 晚于主角出生实例化——懒找主角曾缺失导致面板永远空）
	var hero_panel = hud.get("hero_panel") if hud != null else null
	_check(hero_panel != null and hero_panel._rows.size() == Hero.SQUAD_MAX,
		"hero panel squad rows list all party members (%d)" % (hero_panel._rows.size() if hero_panel != null else -1))

	# —— 2) G 集结：小队 = 编队成员，上限 4；再按 G 解散 ——
	controller._toggle_squad_rally()
	await get_tree().physics_frame
	_check(hero.squad.size() == Hero.SQUAD_MAX, "G rally recruits party members up to cap (%d)" % hero.squad.size())
	var all_following := true
	for m in hero.squad:
		if m.follow_leader != hero:
			all_following = false
	_check(all_following, "all rallied members follow the hero")
	controller._toggle_squad_rally()
	await get_tree().physics_frame
	_check(hero.squad.is_empty(), "G again disbands squad (members resume own AI)")

	# —— 3) 瞄准怪物：红描边 + 红准星（准星射线屏幕中心吸附）——
	_check(hud != null and hud.get("hero_panel") != null, "HUD assembles hero panel (squad merged, v17)")
	_check(hud != null and hud.get("party_panel") != null, "HUD assembles party panel")
	controller.enter_hero_mode()
	await get_tree().physics_frame
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var raider: Raider = (spawner as Node).call("spawn_raider", hero.global_position + Vector3(0.0, 0.0, -8.0), GameDefs.raider_def())
	await get_tree().physics_frame
	raider.global_position = hero.global_position + Vector3(0.0, 0.0, -8.0)   # 定位锚死，瞄准判定确定性
	var to_r := raider.global_position - hero.global_position
	to_r.y = 0.0
	tp.yaw = atan2(-to_r.x, -to_r.z)   # 与 Pawn.look_at_target 同公式：准星对准怪
	tp.pitch = atan2(1.0 - 1.55, to_r.length())   # 俯仰对准怪胸口，消除屏幕偏移
	for _i in 4:
		await get_tree().physics_frame   # 相机 transform 需 ≥2 帧收敛（真机时序坑）
	controller._refresh_crosshair_prompt()
	_check(controller._aim_enemy == raider, "crosshair snaps to aimed enemy")
	_check(raider.model_rig._outline_on, "aimed enemy gets red outline (inverted hull)")
	var aim_ring := raider.get_node_or_null("AimRing") as MeshInstance3D
	_check(aim_ring != null and aim_ring.visible, "aimed enemy shows red ground ring")
	var crosshair = hud.get("crosshair") if hud != null else null
	_check(crosshair != null and crosshair._enemy_mode, "crosshair turns red on enemy aim")

	# —— 4) T 集火：小队围攻目标至死，随后自动恢复自主 AI + 头顶集火箭头 ——
	# enter_hero_mode 已自动集结编队；若未集结（空小队）先按 G 集结
	if hero.squad.is_empty():
		controller._toggle_squad_rally()
	await get_tree().physics_frame
	controller._aim_enemy = raider
	controller._toggle_focus_fire()
	_check(hero.focus_target == raider, "T orders focus fire on aimed enemy")
	# 集火箭头（v11）：目标头顶倒锥箭头，自跟踪（process_frame 信号先于 _process 回调，多等几帧）
	for _i in 4:
		await get_tree().process_frame
	_check(controller._focus_marker != null and controller._focus_marker.target == raider,
		"focus marker attaches to focus target")
	_check(controller._focus_marker != null and controller._focus_marker.visible,
		"focus marker visible while focus active")
	var marker_height_ok: bool = controller._focus_marker != null \
		and controller._focus_marker.global_position.y > raider.global_position.y + 2.0
	_check(marker_height_ok, "focus marker hovers above target head")
	for _i in 12:
		await get_tree().physics_frame
	var fighting := 0
	for m in hero.squad:
		if m.state_machine != null and m.state_machine.current_state != null \
				and m.state_machine.current_state.name == "fight" and m.combat_target == raider:
			fighting += 1
	_check(fighting >= mini(hero.squad.size(), 2), "squad members converge on focus target (%d fighting)" % fighting)
	# 以无名来源击杀（不占用主角 kill_count——后续 hero_xp 测试有绝对值断言）
	raider.health.apply_damage(99999.0, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not hero.is_focus_alive(), "focus order auto-clears when target dies")
	for _i in 3:
		await get_tree().process_frame
	_check(controller._focus_marker == null or not controller._focus_marker.visible,
		"focus marker hides after target death")

	# —— 5) 编队界面：真暂停 + 模态 + 移出/补位 ——
	var party_panel = hud.get("party_panel") if hud != null else null
	if party_panel == null:
		_check(false, "party panel node reachable")
		return
	party_panel.open()
	await get_tree().process_frame
	_check(party_panel.is_open and SelectionManager.ui_modal_count >= 1, "party panel opens as modal (mouse freed)")
	_check(TimeManager.time_scale <= 0.0, "party panel pauses the world")
	_check(String(party_panel._count_label.text).contains("4/4"), "party panel shows 4/4 slots filled")
	hero.remove_party_member(hero.party[0])
	await get_tree().process_frame
	_check(hero.party.size() == 3, "party shrinks to 3 after removal")
	_check(hero.add_party_member(spawned[5]), "fifth soldier can backfill the freed slot")
	_check(hero.party.size() == 4, "party refills to 4")
	var esc_ev := InputEventAction.new()
	esc_ev.action = "cancel"
	esc_ev.pressed = true
	party_panel._unhandled_input(esc_ev)
	await get_tree().process_frame
	_check(not party_panel.is_open and SelectionManager.ui_modal_count == 0, "Esc closes party panel and releases modal")
	_check(TimeManager.time_scale > 0.0, "party panel close restores game speed")

	# —— 6) 夜晚回城：城外小兵回城游荡驻防 ——
	controller._toggle_squad_rally()   # 解散 → 成员按自主 AI 行动
	await get_tree().physics_frame
	# 场上可能有未入队的士兵（编队外），全部传送到城外远处统一验证
	var outsiders: Array = []
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Soldier and is_instance_valid(n) and not (n as Pawn).is_dead_flag:
			(n as Node3D).global_position = Vector3(52.0, 0.0, 52.0) + Vector3(randf() * 4.0, 0.0, randf() * 4.0)
			outsiders.append(n)
	TimeManager.game_seconds = 22.0 / 24.0 * TimeManager.seconds_per_day   # 深夜
	# v43：夜间行为从「回城 wander」改为 night_vigil 待命（task-2）——状态名不再是 move/wander，
	# 而是 night_vigil / night_chat（回待命点途中由 night_vigil 自己走路，不切 move 态）。
	# 判定核心：城外士兵不能原地停留，也不能继续白天 patrol/wander。
	await get_tree().create_timer(1.2).timeout
	var homing := 0
	var old_roam := 0
	var states := {}
	for n in outsiders:
		if n.state_machine != null and n.state_machine.current_state != null:
			var st: String = n.state_machine.current_state.name
			states[st] = int(states.get(st, 0)) + 1
			if st in ["move", "night_vigil", "night_chat", "idle", "rest"]:
				homing += 1
			if st in ["patrol", "wander"]:
				old_roam += 1
	_check(homing >= outsiders.size() - 1,
		"night: outside soldiers head home / stand at night posts (%d/%d, states=%s)" % [homing, outsiders.size(), str(states)])
	_check(old_roam == 0, "night: no soldier keeps daytime patrol/wander after dusk (%s)" % str(states))
	# 恢复白天与速度，交还后续测试
	TimeManager.game_seconds = 9.0 / 24.0 * TimeManager.seconds_per_day
	TimeManager.set_speed(1.0)
	await get_tree().create_timer(0.2).timeout
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()


## v11：行走面修复——资源点占格、远距跟随走 A*、卡位自愈、长距离行军可达。
func _check_walk_surface(world: Node3D) -> void:
	var grid := world.get_node("GridSystem") as GridSystem
	var nav := world.get_node("NavSystem") as NavSystem
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var controller := world.get_node("HeroController") as HeroController
	var hero: Hero = controller.hero
	_check(nav != null and grid != null, "nav / grid available for walk surface checks")
	if nav == null or grid == null or hero == null or spawner == null:
		return

	# —— 1) 资源点（树/石）占格：A* 视为障碍，路径不再穿过树干 ——
	var resources: Array = get_tree().get_nodes_in_group("resource_node")
	var solid_count := 0
	var sample_resource: ResourceNode = null
	for n in resources:
		if not is_instance_valid(n) or not (n is ResourceNode):
			continue
		if nav.path_grid.is_point_solid(grid.world_to_grid((n as Node3D).global_position)):
			solid_count += 1
	_check(solid_count >= 38, "resource cells registered solid in nav grid (%d)" % solid_count)
	# 挑一棵「孤树」验证占格生命周期（贴邻树的格子可能被邻居同时标记，切换断言会抖）
	for n in resources:
		if not is_instance_valid(n) or not (n is ResourceNode):
			continue
		var alone := true
		for n2 in resources:
			if n2 != n and is_instance_valid(n2) and n2 is Node3D \
					and (n2 as Node3D).global_position.distance_to((n as Node3D).global_position) < 4.5:
				alone = false
				break
		if alone:
			sample_resource = n as ResourceNode
			break
	if sample_resource != null:
		var res_cell := grid.world_to_grid(sample_resource.global_position)
		nav.set_resource_solid(sample_resource, false)
		var cleared: bool = not nav.path_grid.is_point_solid(res_cell)
		nav.set_resource_solid(sample_resource, true)
		_check(cleared and nav.path_grid.is_point_solid(res_cell),
			"resource solid toggles with regrow/deplete lifecycle")
	else:
		_check(false, "found an isolated resource for lifecycle toggle check")

	# —— 2) 小队跟随绕障（v11 混合导航回归）：成员隔着主城直线相望，
	#    旧纯 steering 会一头怼在城堡碰撞上永久卡住；现在应走 A* 绕过去归队。
	var member: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(),
		Vector3(-14.0, 0.0, 0.0))
	hero.global_position = Vector3(14.0, 0.0, 0.0)
	await get_tree().physics_frame
	# 清掉此前测试残留的编队，确保这位是唯一成员（槽位在主角身侧）
	for m in hero.squad.duplicate():
		hero._release_member(m)
	hero.squad.clear()
	hero.recruit_squad([member])
	await get_tree().physics_frame
	TimeManager.set_speed(3.0)
	var rejoined := false
	for _i in 700:   # ~35 游戏秒
		await get_tree().physics_frame
		if not is_instance_valid(member):
			break
		if member.global_position.distance_to(hero.global_position) < 6.0:
			rejoined = true
			break
	TimeManager.set_speed(1.0)
	_check(rejoined, "squad member paths AROUND castle to rejoin hero (no straight-line stuck)")
	if is_instance_valid(member):
		member.queue_free()

	# —— 3) 长距离行军可达性：横穿树林密集带，任何永久卡位都到不了终点 ——
	var marcher: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_archer_def(),
		Vector3(40.0, 0.0, 40.0))
	await get_tree().physics_frame
	var dest := Vector3(-40.0, 0.0, 40.0)
	TimeManager.set_speed(3.0)
	marcher.set_destination(dest)
	var arrived := false
	var progress := 0.0
	var total := marcher.global_position.distance_to(dest)
	for _i in 900:
		await get_tree().physics_frame
		if not is_instance_valid(marcher):
			break
		if marcher.global_position.distance_to(dest) < 3.0:
			arrived = true
			break
		progress = 1.0 - marcher.global_position.distance_to(dest) / total
	TimeManager.set_speed(1.0)
	_check(arrived or progress > 0.9, "long march through tree field completes (arrived=%s progress=%.0f%%)" % [arrived, progress * 100.0])
	if is_instance_valid(marcher):
		marcher.queue_free()


## v3：昼夜（太阳角度 / 夜间信号）与天气（湿地参数）。
func _check_daynight_and_weather(world: Node3D) -> void:
	var dnc := world.get_node_or_null("DayNightCycle") as DayNightCycle
	_check(dnc != null, "DayNightCycle node exists")
	if dnc == null:
		return
	# GDScript lambda 按值捕获 int —— 用引用类型（Dictionary）做计数器
	var counter := {"night": 0}
	EventBus.night_changed.connect(func(is_night: bool): counter["night"] += 1 if is_night else 0)
	# 推进到正午：太阳应高角度、能量充足
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.3).timeout
	var noon_energy: float = (world.get_node("Sun") as DirectionalLight3D).light_energy
	# 推进到深夜：太阳应熄灭、夜旗为真
	TimeManager.game_seconds = 23.5 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.3).timeout
	var night_energy: float = (world.get_node("Sun") as DirectionalLight3D).light_energy
	_check(noon_energy > 0.6 and night_energy < 0.08, "sun fades from noon to midnight (%.2f → %.2f)" % [noon_energy, night_energy])
	_check(dnc._is_night, "cycle flags midnight as night")
	_check(counter["night"] > 0, "night_changed broadcast on dusk crossing")
	# 回到白天继续后续测试
	TimeManager.game_seconds = 9.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.3).timeout
	# 天气：强制下雨 → 湿度上升、雨幕发射、强度爬升、风暴压暗阳光
	var weather := world.get_node_or_null("WeatherSystem") as WeatherSystem
	if weather != null:
		var sun := world.get_node("Sun") as DirectionalLight3D
		weather._apply_state(WeatherSystem.State.RAIN)
		await get_tree().create_timer(1.2).timeout
		_check(weather._wetness > 0.1, "rain raises ground wetness (%.2f)" % weather._wetness)
		_check(weather.rain_strength() > 0.25, "rain strength ramps up after onset (%.2f)" % weather.rain_strength())
		var rain_sun_energy: float = sun.light_energy
		weather._apply_state(WeatherSystem.State.CLEAR)
		await get_tree().create_timer(1.6).timeout
		_check(sun.light_energy > rain_sun_energy * 1.15,
			"storm dims the sun, clear sky restores it (%.2f rain → %.2f clear)" % [rain_sun_energy, sun.light_energy])
		await get_tree().create_timer(0.3).timeout
	else:
		_check(false, "WeatherSystem node exists")


## v3：主角经验（击杀归属）与士兵姿态 leash。
func _check_hero_xp_and_stance(hero: Hero) -> void:
	var xp_before: int = hero.xp
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var kills_before: int = hero.kill_count   # 增量式断言：前面段落（编队讨伐）也可能给主角记功
	var raider: Raider = (spawner as Node).call("spawn_raider", hero.global_position + Vector3(2.0, 0.0, 0.0), GameDefs.raider_def())
	await get_tree().physics_frame
	raider.health.apply_damage(9999.0, hero)
	await get_tree().physics_frame
	_check(hero.xp > xp_before, "hero gains xp on kill attribution (xp %d → %d)" % [xp_before, hero.xp])
	_check(hero.kill_count > kills_before, "hero kill count increments (%d → %d)" % [kills_before, hero.kill_count])
	# 士兵姿态：驻守 + 远锚点 → 应放弃追击
	var soldier_def := GameDefs.settler_warrior_def()
	var soldier: Pawn = (spawner as Node).call("spawn_soldier", soldier_def, hero.global_position + Vector3(3.0, 0.0, 0.0))
	await get_tree().physics_frame
	soldier.stance = Pawn.Stance.HOLD
	soldier.hold_anchor = soldier.global_position
	_check(soldier.should_break_engagement(soldier.global_position + Vector3(50.0, 0.0, 0.0)), "hold stance drops far targets")
	soldier.stance = Pawn.Stance.AGGRESSIVE
	_check(not soldier.should_break_engagement(soldier.global_position + Vector3(50.0, 0.0, 0.0)), "aggressive stance keeps chasing")
	# 野怪 def 完整性：精英 / 头目
	var elite := GameDefs.raider_elite_def()
	var boss := GameDefs.raider_boss_def()
	_check(elite.loot_gold >= 20 and elite.flee_hp_ratio > 0.0, "elite raider def tuned (loot/flee)")
	_check(boss.is_boss and boss.loot_gold >= 100 and boss.flee_hp_ratio == 0.0, "boss raider def tuned (boss flag/loot/no-flee)")


## v9：武器挂点筛选——占位 KayKit 角色把「同一只手可用的所有武器变体」都挂在同一个手部挂点下
## 且导入后默认全部可见：修复前主角左手同时显示副手剑 + 4 面盾（真机可见穿模重叠），右手 1H/2H 两把剑重叠。
## 这里既核对真实主角实例（走完 PawnDef → Pawn → PawnModelRig 全链路），
## 也用真实 PawnModelRig 逐个角色 def 核对「每只手最多一件可见武器」。
func _check_weapon_loadout(hero: Hero) -> void:
	var hero_slots := _visible_weapons(hero.model_rig)
	_check(hero_slots.size() == 2
			and String(hero_slots["handslot_r"]) == "1H_Sword"
			and String(hero_slots["handslot_l"]) == "Rectangle_Shield",
			"hero holds exactly one sword (right) + one shield (left): %s" % str(hero_slots))
	var spare_2h := _find_node_named(hero.model_rig, "2H_Sword") as VisualInstance3D
	var spare_offhand_sword := _find_node_named(hero.model_rig, "1H_Sword_Offhand") as VisualInstance3D
	_check(spare_2h != null and not spare_2h.visible and spare_offhand_sword != null and not spare_offhand_sword.visible,
			"hero spare weapons hidden (2H sword / offhand sword no longer overlap)")
	var defs := [
		GameDefs.hero_warrior_def(), GameDefs.colonist_def(), GameDefs.refugee_def(),
		GameDefs.raider_def(), GameDefs.raider_elite_def(), GameDefs.raider_boss_def(),
		GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def(),
	]
	for d in defs:
		var path: String = d.model_path
		if d.model_path_pool.size() > 0:
			path = d.model_path_pool[0]
		var rig := PawnModelRig.new()
		add_child(rig)
		var loaded: bool = rig.setup(path, d.model_scale, d.model_face_offset_deg,
				d.model_weapon_main, d.model_weapon_offhand)
		var slots := _visible_weapons(rig)
		var overloaded: Array = []
		for slot in slots:
			if String(slots[slot]).contains(","):
				overloaded.append("%s=[%s]" % [slot, slots[slot]])
		# KayKit 人形模型必须找到双手挂点（防挂点筛选回归）；怪物模型（Orc/Ghost 等）
		# 本就没有 handslot 节点——只要加载成功且不超载即合格。
		var monster_model: bool = _find_node_named(rig, "handslot_r") == null \
			and _find_node_named(rig, "handslot_l") == null
		_check(loaded and overloaded.is_empty() and (slots.size() == 2 or monster_model),
				"%s: at most one weapon per hand %s" % [d.id, str(slots)])
		rig.queue_free()
	# 流民统一兜帽模型且双手空空（v10）
	var ref_def := GameDefs.refugee_def()
	_check(ref_def.model_path.ends_with("placeholder_colonist_rogue_hooded.glb"),
			"refugee uses the hooded rogue model")
	var ref_rig := PawnModelRig.new()
	add_child(ref_rig)
	ref_rig.setup(ref_def.model_path, ref_def.model_scale, ref_def.model_face_offset_deg,
			ref_def.model_weapon_main, ref_def.model_weapon_offhand)
	var ref_slots := _visible_weapons(ref_rig)
	_check(String(ref_slots.get("handslot_r", "?")) == "" and String(ref_slots.get("handslot_l", "?")) == "",
			"refugee carries no weapons (both hands empty): %s" % str(ref_slots))
	ref_rig.queue_free()
	# 四职业武器与普攻距离契约（v10）：近战短 / 远程长
	_check(GameDefs.settler_warrior_def().attack_kind == PawnDef.AttackKind.MELEE
			and GameDefs.settler_warrior_def().attack_range <= 2.5, "warrior: melee with short range")
	_check(GameDefs.settler_assassin_def().attack_kind == PawnDef.AttackKind.MELEE
			and GameDefs.settler_assassin_def().attack_range < GameDefs.settler_warrior_def().attack_range,
			"assassin: melee, shortest reach of all classes")
	_check(GameDefs.settler_mage_def().attack_kind == PawnDef.AttackKind.RANGED
			and GameDefs.settler_mage_def().attack_range >= 10.0, "mage: ranged with longest reach")
	_check(GameDefs.settler_archer_def().attack_kind == PawnDef.AttackKind.RANGED
			and GameDefs.settler_archer_def().attack_range >= 9.0, "archer: ranged with mid-long reach")


## 读取模型两个手部挂点下「可见」的武器网格名（逗号分隔，便于一次断言看完两只手）。
func _visible_weapons(root: Node) -> Dictionary:
	var out := {}
	if root == null:
		return out
	for slot in ["handslot_l", "handslot_r"]:
		var node := _find_node_named(root, slot)
		if node == null:
			continue
		var names: Array = []
		for c in node.get_children():
			if c is VisualInstance3D and (c as VisualInstance3D).visible:
				names.append(String(c.name))
		out[slot] = ",".join(PackedStringArray(names))
	return out


func _find_node_named(n: Node, wanted: String) -> Node:
	if String(n.name) == wanted:
		return n
	for c in n.get_children():
		var r := _find_node_named(c, wanted)
		if r != null:
			return r
	return null


## v4：新手引导——步骤链 / 信号驱动自动推进 / 完成记忆 / 跳过 / HUD 浮层装配。
## 全程走真实入口（SelectionManager / BuildSystem / HeroController / Input 模拟），
## 验证玩家实际操作路径上的每一步引导都能被正确点亮。
func _check_tutorial_flow(world: Node3D) -> void:
	var tutorial := world.get_node_or_null("TutorialSystem") as TutorialSystem
	_check(tutorial != null and tutorial.steps.size() >= 9, "tutorial chain ready (9 steps)")
	if tutorial == null:
		return
	tutorial.advance_delay = 0.05   # 测试提速：跳过达成后的音效停顿
	_check(tutorial.state == TutorialSystem.State.IDLE, "tutorial stays idle when Main runs as child scene")
	# 引导期间野怪停刷（防慢玩家被夜袭灭家打断引导）——门禁函数直查 + 运行态复核
	var spawner := world.get_node_or_null("WildlifeSpawner")
	spawner.set_process(true)   # SceneValidation 主流程禁用了它，这里恢复以验证门禁
	tutorial.start()
	var gated: bool = spawner._tutorial_running()
	tutorial.skip()
	tutorial.clear_save()
	spawner.set_process(false)
	_check(gated, "wildlife spawner gated while tutorial runs")
	var hud := _main.get_node_or_null("HUD")
	_check(hud != null and hud.get("tutorial_overlay") != null, "HUD assembles tutorial overlay")

	var events := {"step": 0, "finished": 0, "skipped": 0}
	EventBus.tutorial_step_changed.connect(func(_i, _t): events["step"] += 1)
	EventBus.tutorial_finished.connect(func(): events["finished"] += 1)
	EventBus.tutorial_skipped.connect(func(): events["skipped"] += 1)

	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
	_check(hero != null, "hero available for tutorial flow")

	# 单击选中存活（历史 bug 回归）：真实事件管线 parse_input_event → GUI → 3D 拾取
	# （延迟到物理帧）→ unhandled。Godot4 拾取延迟使 SelectableComponent 的
	# set_input_as_handled 拦不住 SelectionController，松开时 clear() 曾把单击选中抹掉；
	# 且可选中碰撞圆柱原点半埋地下，点身体上半身拾取落空。
	# 单击选中存活（历史 bug 回归）：Godot4 的 3D 拾取延迟到物理帧，SelectableComponent
	# 的 set_input_as_handled 拦不住 SelectionController，松开时 clear() 曾把单击选中抹掉；
	# 且可选中碰撞圆柱原点半埋地下（y∈[-1,1]），点身体上半身拾取落空。
	# 白盒驱动 SelectionController 两条路径（Area3D 管线已在真机验证）。
	# 默认第三人称操控下 SelectionController 不响应点击——先切战术俯瞰再测 RTS 选择行为
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	await get_tree().physics_frame
	SelectionManager.clear()
	var selctrl := world.get_node("SelectionController")
	var sel_shape: CollisionShape3D = null
	for c in hero.selectable.get_children():
		if c is CollisionShape3D:
			sel_shape = c
			break
	_check(sel_shape != null and is_equal_approx(sel_shape.position.y, 1.0), "selectable cylinder covers body (offset to y=1)")
	var cam := get_viewport().get_camera_3d()
	var hero_screen := cam.unproject_position(hero.global_position + Vector3(0.0, 1.0, 0.0))
	_check(selctrl._selectable_under(hero_screen) == hero, "click helper detects hero under cursor")
	SelectionManager.select_only(hero)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = hero_screen
	selctrl._unhandled_input(press)
	var release := press.duplicate()
	release.pressed = false
	selctrl._unhandled_input(release)
	_check(SelectionManager.selected.has(hero), "single click on hero survives release (no clear)")
	# 点空地 press/release 仍应清空（原有取消选择行为）。
	# 落点选「离所有可选中单位投影最远的内缩角」，避免撞上测试早前生成的村民。
	var miss := Vector2.ZERO
	var best_clearance := -1.0
	for corner in [Vector2(80, 80), Vector2(1072, 80), Vector2(80, 1000), Vector2(1072, 1000)]:
		var clearance := 1e9
		for p in get_tree().get_nodes_in_group("selectable"):
			if is_instance_valid(p) and p is Node3D:
				var sp := cam.unproject_position((p as Node3D).global_position + Vector3(0, 1, 0))
				clearance = minf(clearance, sp.distance_to(corner))
		if clearance > best_clearance:
			best_clearance = clearance
			miss = corner
	press.position = miss
	selctrl._unhandled_input(press)
	release.position = miss
	selctrl._unhandled_input(release)
	_check(SelectionManager.selected.is_empty(), "click on empty ground still deselects")

	tutorial.start()
	_check(tutorial.state == TutorialSystem.State.RUNNING and tutorial.current_index == 0, "tutorial starts at welcome")
	# v7：信息步（欢迎/说明卡）必须占住鼠标模态并锁定操控——否则第三人称捕获指针、按钮点不了。
	# 先关掉早前定居测试残留的入驻提示（真机玩家点「继续」等价），保证计数从 0 起步。
	var hud_t := _main.get_node_or_null("HUD")
	if hud_t != null:
		hud_t._dismiss_settlement_notice()
		TimeManager.set_speed(1.0)
	_check(SelectionManager.ui_modal_count == 1 and tutorial.blocks_control(),
		"tutorial info step frees mouse and locks control")
	tutorial.advance()
	_check(tutorial.current_index == 1 and tutorial.current().id == &"move", "info step advances via button")
	await get_tree().physics_frame
	_check(SelectionManager.ui_modal_count == 0 and not tutorial.blocks_control(),
		"wait-input step restores mouse capture and control")
	# move 步（第三人称）：真实输入管线驱动 WASD
	controller.enter_hero_mode()
	await get_tree().physics_frame
	# 按住 6 个物理帧：单帧按下/松开可能在同一个毫秒内完成，
	# 引导的 _process 采样不到（headless 帧序抖动）。
	Input.action_press("move_up")
	for _i in 6:
		await get_tree().physics_frame
	Input.action_release("move_up")
	await get_tree().create_timer(0.3).timeout
	_check(tutorial.current_index == 2, "move step completes on move input")

	# first_blood 步（v22，替代原「亲手砍树」）：主角亲手击杀野怪（白盒发 enemy_died；
	# 真实战斗路径在 ThirdPersonTest / SettlerSkillTest 验证）
	var raider: Pawn = (world.get_node("PawnSpawner") as Node).call(
		"spawn_raider", Vector3(24.0, 0.0, 24.0), GameDefs.raider_def())
	await get_tree().physics_frame
	EventBus.enemy_died.emit(raider, hero)
	await get_tree().create_timer(0.3).timeout
	_check(tutorial.current_index == 3, "hero first kill completes tutorial step")

	# build_house 步：走近放置（第三人称建造距离 ≤ 20m）
	var build := world.get_node("BuildSystem") as BuildSystem
	var house_def: BuildingDef
	for definition in GameDefs.building_defs():
		if definition.id == &"house":
			house_def = definition
	hero.global_position = Vector3(-8, 0, 8)
	build.enter_build_mode(house_def)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _save_frame("scene-tutorial")
	build.try_place_at(Vector3(-16.4, 0, 16.4))
	build.exit_build_mode()
	await get_tree().create_timer(0.3).timeout
	_check(tutorial.current_index == 4, "house placement completes tutorial step")

	# settle 步（v21 信息步，替代原「兵营募兵」等待步）：点「下一步」推进
	_check(tutorial.current_index == 4 and tutorial.current().id == &"settle",
		"settle info step follows house placement")
	tutorial.advance()
	await get_tree().create_timer(0.3).timeout
	_check(tutorial.current_index == 5, "settle info step advances to tactics")

	# tactics 步（v42）：镜头收敛后玩家等不到「切战术俯瞰」→ 该步已改为信息步。
	_check(tutorial.current().id == &"tactics" and not tutorial.current().wait_input,
		"tactics step is informational after view-mode collapse (v42)")
	tutorial.advance()
	await get_tree().create_timer(0.3).timeout
	_check(tutorial.current_index == 6 and tutorial.current().id == &"rally",
		"tactics info step advances to rally")
	tutorial.advance()
	_check(tutorial.current_index == 7 and tutorial.current().id == &"combat", "rally info step advances")
	tutorial.advance()
	_check(tutorial.current_index == 8 and tutorial.current().id == &"finish", "combat info step advances")

	tutorial.advance()
	_check(tutorial.state == TutorialSystem.State.DONE and tutorial.saved_done, "tutorial finish writes completion memory")
	_check(events["finished"] == 1, "tutorial_finished broadcast once")
	tutorial.clear_save()
	_check(not tutorial.saved_done, "completion memory clearable (keeps dev machine clean)")

	tutorial.restart()
	_check(tutorial.state == TutorialSystem.State.RUNNING, "tutorial replayable via top bar button")
	tutorial.skip()
	_check(tutorial.state == TutorialSystem.State.DONE and events["skipped"] == 1, "skip ends tutorial and broadcasts once")
	tutorial.clear_save()

	# 游戏结束中止引导（历史 bug 回归）：基地陷落时引导浮层曾压在结算画面上。
	# 应静默中止：状态 DONE、不写完成记忆（重开一局仍能看到引导）。
	tutorial.restart()
	var skipped_before: int = events["skipped"]
	GameManager.request_game_over(false)
	# 游戏结束会把 Engine.time_scale 归零，普通 SceneTreeTimer 按缩放时间走会永不触发
	await get_tree().create_timer(0.1, true, false, true).timeout
	_check(tutorial.state == TutorialSystem.State.DONE and not tutorial.saved_done,
		"tutorial aborts quietly on game over (no completion memory)")
	_check(events["skipped"] == skipped_before + 1, "game over hides tutorial overlay via skipped broadcast")
	tutorial.clear_save()


## —— v8：Esc 暂停菜单 ——（引导流程收尾停在 GAME_OVER / time_scale=0，先复位再测）
func _check_pause_menu(world: Node3D) -> void:
	GameManager.change_phase(GameManager.Phase.BUILD)
	TimeManager.set_speed(1.0)
	var hud := _main.get_node_or_null("HUD")
	var menu: PauseMenu = hud.get("pause_menu") if hud != null else null
	_check(menu != null and not menu.is_open, "HUD assembles Esc pause menu (closed at start)")
	if menu == null:
		return

	var esc := InputEventAction.new()
	esc.action = "cancel"
	esc.pressed = true

	# —— 开：真暂停 + 模态计数 + 鼠标释放 + 裸暂停遮罩不叠加 ——
	var modal_before: int = SelectionManager.ui_modal_count
	TimeManager.set_speed(2.0)
	menu.open()
	_check(menu.is_open and is_equal_approx(TimeManager.time_scale, 0.0), "Esc menu pauses via time_scale")
	_check(SelectionManager.ui_modal_count == modal_before + 1, "Esc menu occupies ui_modal_count")
	await get_tree().physics_frame
	if SelectionManager.hero_mode_active:
		_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "mouse pointer freed while menu open (hero mode)")
	_check(hud != null and not hud.pause_overlay.visible, "bare pause overlay hidden while Esc menu open")

	# —— 关：恢复原倍速、归还模态计数 ——
	menu.close()
	_check(not menu.is_open and is_equal_approx(TimeManager.time_scale, 2.0), "closing restores previous speed")
	_check(SelectionManager.ui_modal_count == modal_before, "modal count returned after close")

	# —— 设置子页：不解除暂停；Esc 只收子页 ——
	menu.open()
	menu._open_settings_view()
	_check(menu.is_open and is_equal_approx(TimeManager.time_scale, 0.0) and menu._settings_box.visible,
		"settings sub-view opens without unpausing")
	menu._unhandled_input(esc)
	_check(not menu._settings_box.visible and menu.is_open, "Esc collapses settings sub-view back to buttons")
	menu._unhandled_input(esc)
	_check(not menu.is_open and is_equal_approx(TimeManager.time_scale, 2.0), "Esc toggles menu closed from button view")
	TimeManager.set_speed(1.0)

	# —— Esc 优先级链 1：建造模式 → Esc 归 BuildSystem ——
	var build := world.get_node("BuildSystem") as BuildSystem
	build.enter_build_mode(GameDefs.building_defs()[0])
	menu._unhandled_input(esc)
	_check(not menu.is_open, "Esc passes through while placing (menu stays closed)")
	build._unhandled_input(esc)
	_check(not build.is_building, "build mode consumes Esc to exit placement")

	# —— Esc 优先级链 2：引导进行中 → Esc 归 TutorialSystem（快捷跳过）——
	var tutorial := world.get_node("TutorialSystem") as TutorialSystem
	tutorial.start()
	menu._unhandled_input(esc)
	_check(not menu.is_open, "Esc passes through while tutorial runs (menu stays closed)")
	tutorial._unhandled_input(esc)
	_check(tutorial.state == TutorialSystem.State.DONE, "tutorial consumes Esc as quick-skip")
	tutorial.clear_save()
	TimeManager.set_speed(1.0)
	SelectionManager.ui_modal_count = 0   # 引导信息步的模态占用随跳过释放，此处兜底清零

	# —— v8：数字键 1~6 任意时刻直接进入/切换建造（旧 1/2/3 调速键挪至 - / =）——
	build.exit_build_mode()
	var num_key := InputEventKey.new()
	num_key.pressed = true
	num_key.physical_keycode = KEY_1
	build._unhandled_input(num_key)
	_check(build.is_building and build.current_def.id == &"wall", "digit 1 enters build mode directly (wall)")
	num_key.physical_keycode = KEY_2
	build._unhandled_input(num_key)
	_check(build.is_building and build.current_def.id == &"house", "digit 2 switches target while building")
	build._unhandled_input(esc)
	_check(not build.is_building, "Esc still exits build mode after digit entry")

	# —— 调速新键位：- / = 在 1×→2×→3× 循环并钳制 ——
	TimeManager.set_speed(1.0)
	var speed_up := InputEventAction.new()
	speed_up.action = "speed_up"
	speed_up.pressed = true
	var speed_down := InputEventAction.new()
	speed_down.action = "speed_down"
	speed_down.pressed = true
	_main._unhandled_input(speed_up)
	_check(is_equal_approx(TimeManager.time_scale, 2.0), "speed_up (=) steps 1x to 2x")
	_main._unhandled_input(speed_up)
	_main._unhandled_input(speed_up)
	_check(is_equal_approx(TimeManager.time_scale, 3.0), "speed_up clamps at 3x")
	_main._unhandled_input(speed_down)
	_check(is_equal_approx(TimeManager.time_scale, 2.0), "speed_down (-) steps back to 2x")

	# —— 模态守卫：Esc 菜单打开时数字键不进入建造 ——
	menu.open()
	num_key.physical_keycode = KEY_3
	build._unhandled_input(num_key)
	_check(not build.is_building, "digit keys ignored while pause menu open (modal guard)")
	menu.close()
	TimeManager.set_speed(1.0)


func _capture(camera: IsometricCamera) -> void:
	get_window().size = Vector2i(1600, 1000)
	# 战术镜头样张走等距相机：默认第三人称下它非 current，先切回战术俯瞰
	var world := camera.get_parent() as Node3D
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	await get_tree().process_frame
	# —— 白昼玩法镜头（HUD 全开）——
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.4).timeout
	camera.focus_on(Vector3.ZERO)
	camera.target_distance = 44
	await _save_frame("scene-gameplay")
	# —— 正午总览（HUD 关）——
	_main.get_node("HUD").hide()
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.4).timeout
	camera.target_distance = 100
	camera.focus_on(Vector3(0, 0, -3))
	await _save_frame("scene-overview")
	# —— 夜景（火炬 / 萤火虫 / 月色）——
	TimeManager.game_seconds = 22.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.5).timeout
	camera.target_distance = 44
	camera.focus_on(Vector3.ZERO)
	await _save_frame("scene-night")
	# —— 夜雨（v5）：同机位强雨——验证夜间雨丝可读 + 风暴夜不纯黑 ——
	var weather := _main.get_node("WorldRoot/WeatherSystem") as WeatherSystem
	weather._apply_state(WeatherSystem.State.RAIN)
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	weather._thunder_timer = 99.0
	await get_tree().create_timer(4.0).timeout
	TimeManager.game_seconds = 22.0 / 24.0 * TimeManager.seconds_per_day
	await _save_frame("scene-rain-night")
	weather._apply_state(WeatherSystem.State.CLEAR)
	await get_tree().create_timer(4.0).timeout
	# —— 雨天 vs 晴天（同机位对照，供 PixelCheck 湿度对比）——
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	weather._apply_state(WeatherSystem.State.RAIN)
	# 确定性的暴雨样张：强度拉满 + 冻结雷电（避免闪电/雷声随机污染对照）
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	weather._thunder_timer = 99.0
	await get_tree().create_timer(5.0).timeout
	camera.target_distance = 44
	camera.focus_on(Vector3(26, 0, 16))
	# 冻结太阳位置：雨天/晴天两张唯一变量 = 天气（否则 5 秒间太阳位移会污染对比）
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	await _save_frame("scene-rain")
	weather._apply_state(WeatherSystem.State.CLEAR)
	await get_tree().create_timer(6.5).timeout
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	await _save_frame("scene-after-rain")
	# Advance drying independently of the sun for a genuinely dry comparison.
	for _i in 600:
		weather._update_strength(0.1)
	weather._tick_apply()
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	await _save_frame("scene-dry")
	# —— 湖岸与林地（白天）——
	camera.target_distance = 48
	camera.focus_on(Vector3(35, 0, -27))
	await _save_frame("scene-lakeshore")
	camera.target_distance = 48
	camera.focus_on(Vector3(-32, 0, 28))
	await _save_frame("scene-grove")
	# —— 第三人称亲征视角（v7 默认主视角）——
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	tp.yaw = PI * 0.8   # 主角在主城东南，转身望向城堡
	tp.pitch = -0.22
	await get_tree().create_timer(0.4).timeout
	await _save_frame("scene-third-person")
	# —— 第三人称夜战氛围（城堡前 · 火炬）——
	TimeManager.game_seconds = 22.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.5).timeout
	await _save_frame("scene-third-person-night")
	_main.get_node("HUD").show()


func _save_frame(filename: String) -> void:
	for _i in 12:
		await get_tree().process_frame
	# v42：推拉改阻尼平滑后，截图前把实际视距对齐目标值——否则样张会停在过渡途中
	# （capture 段落会一帧内把 target_distance 从 44 拉到 100 拍总览图）。
	var cam := get_viewport().get_camera_3d()
	if cam is IsometricCamera:
		(cam as IsometricCamera).snap_distance()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s.png" % filename)
