extends Node
## v36 湖泊卡位修复回归。
## 运行：godot --headless --path . tests/LakeStuckTest.tscn --fixed-fps 60
##
## 背景：河口浅滩的湖格被 WaterFeature 从寻路里清掉，但湖面物理碰撞盒在浅滩清理
## 「之前」就已建好，形成「A* 认为可走、物理却是隐形墙」的矛盾格——路径把单位引
## 进去 / 出生吸附把单位放进去之后，单位嵌在静态碰撞盒里永久卡在湖里，重算路径
## 也救不回来；另外跳劈击飞的抛物线直写坐标（无视物理），会把湖岸边的怪拍进
## 湖面碰撞盒。本测试验证三层修复：
##   ① 湖面碰撞盒与寻路阻挡逐格一致（可走格无隐形墙、阻挡格有实体碰撞）；
##   ② 击飞落点被裁剪回岸上（不落水、落地后能正常行走）；
##   ③ 已滞留阻挡格的单位在 ~2s 内被自动搬回最近可走格（兜底自救），主角除外。

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
	(world.get_node("WildlifeSpawner") as Node).set_process(false)
	(world.get_node("ResourceGrowthSystem") as Node).set_process(false)
	for raider in get_tree().get_nodes_in_group("enemy"):
		raider.queue_free()
	var grid := world.get_node("GridSystem") as GridSystem
	var nav := world.get_node("NavSystem") as NavSystem
	await _check_lake_consistency(grid)
	await _check_knockup_clamp(grid, nav)
	await _check_terrain_rescue(grid, nav)
	_check_hero_rescue_excluded()
	print("LakeStuckTest finished, failures=%d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


# ---- ① 湖面碰撞盒与寻路阻挡逐格一致 ----

func _check_lake_consistency(grid: GridSystem) -> void:
	await get_tree().physics_frame
	var space := (get_viewport().world_3d).direct_space_state
	var checked := 0
	var mismatches := 0
	var shallow_open := 0
	for x in grid.grid_size.x:
		for z in grid.grid_size.y:
			var cell := Vector2i(x, z)
			var p := grid.grid_to_world(cell)
			if WorldLayout.lake_distance(Vector2(p.x, p.z)) >= 1.0:
				continue
			checked += 1
			var blocked: bool = grid.terrain_cells.has(cell)
			if not blocked:
				shallow_open += 1
			# 从上向下的竖直短射线：起点在所有碰撞体之上（盒高 3m），终点 y=0.5
			# 停在地面之上——只可能命中 LakeAndMapBoundary 的湖面碰撞盒顶面。
			# （水平贴格射线会从盒内出发，hit_from_inside=false 时永远打不中。）
			var has_box := not space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 6.0, p.z), Vector3(p.x, 0.5, p.z), 1)).is_empty()
			if has_box != blocked:
				mismatches += 1
				if mismatches <= 8:
					push_warning("lake cell %s mismatch: nav_blocked=%s physics_box=%s" % [cell, blocked, has_box])
	_check(checked > 100, "lake ellipse covers a meaningful cell count (%d)" % checked)
	_check(mismatches == 0, "lake collision boxes match nav blocking exactly (%d/%d mismatched)" % [mismatches, checked])
	_check(shallow_open >= 5, "river-mouth shallow stays wadeable in nav (%d open cells)" % shallow_open)


# ---- ② 击飞落点裁剪：不落水、不嵌碰撞 ----

func _check_knockup_clamp(grid: GridSystem, nav: NavSystem) -> void:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null:
		_check(false, "pawn spawner available")
		return
	# v43：湖泊东迁到 (52,-38)，西岸在 z=-38 处约 x≈34.8；取离岸 1.8m 的干地作起点。
	var shore := Vector3(33.0, 0.0, -38.0)
	_check(nav.is_walkable_cell(grid.world_to_grid(shore)), "knockup test starts on walkable ground")
	var victim: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), shore)
	await get_tree().physics_frame
	if victim == null or not is_instance_valid(victim):
		_check(false, "knockup victim spawned on the lakeshore")
		return
	var toward_lake := (Vector3(WorldLayout.LAKE_CENTER.x, 0.0, WorldLayout.LAKE_CENTER.y) - shore)
	toward_lake.y = 0.0
	victim.apply_knockup(toward_lake.normalized(), 3.2, 2.6, 0.55, 1.1)
	# 0.55s 滞空（≈33 帧）+ 余量；1.1s 落地眩晕期间位置冻结，读数稳定
	for i in 60:
		await get_tree().physics_frame
	var landing := victim.global_position
	_check(nav.is_walkable_cell(grid.world_to_grid(landing)),
		"knockup victim lands on walkable ground (cell %s)" % grid.world_to_grid(landing))
	# v43：湖岸改用三阶谐波，2m 格子的可走性判据仍是「格心不在湖里」——因此这里
	# ① 断言落点所在格心是干地（= 没有湖面碰撞盒，这是 v36 的真正契约）；
	# ② 再留 0.9 的软线，保证落点没有扎进水里（谐波岸线允许半个格子的岸边余量）。
	var landing_cell := grid.world_to_grid(landing)
	var cell_center := grid.grid_to_world(landing_cell)
	_check(WorldLayout.lake_distance(Vector2(cell_center.x, cell_center.z)) >= 1.0,
		"knockup victim lands on a dry-lake cell (cell %s, lake_sdf=%.2f)"
			% [landing_cell, WorldLayout.lake_distance(Vector2(cell_center.x, cell_center.z))])
	_check(WorldLayout.lake_distance(Vector2(landing.x, landing.z)) >= 0.93,
		"knockup victim does not land in the water (lake_sdf=%.2f at %.1f,%.1f)"
			% [WorldLayout.lake_distance(Vector2(landing.x, landing.z)), landing.x, landing.z])
	# 落地后必须还能正常离开（没有嵌进任何静态碰撞盒）
	var leave := Vector3(26.0, 0.0, -38.0)
	victim.set_destination(leave)
	var escaped := false
	for i in 300:
		await get_tree().physics_frame
		if not is_instance_valid(victim):
			break
		# 士兵白天会自主巡逻改目标：每 30 帧重申一次行军目标
		if i % 30 == 29:
			victim.set_destination(leave)
		if victim.global_position.distance_to(leave) < 3.0:
			escaped = true
			break
	_check(escaped and is_instance_valid(victim), "knockup victim can walk away after landing (no embed)")
	if is_instance_valid(victim):
		victim.queue_free()


# ---- ③ 滞留自救：嵌进湖里的单位被搬回岸上 ----

func _check_terrain_rescue(grid: GridSystem, nav: NavSystem) -> void:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null:
		_check(false, "pawn spawner available (rescue)")
		return
	var victim: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(33.0, 0.0, -38.0))
	await get_tree().physics_frame
	if victim == null or not is_instance_valid(victim):
		_check(false, "rescue victim spawned")
		return
	# 模拟历史 bug / 任意直写坐标路径：把单位直接放进湖心（嵌进碰撞盒）
	victim.global_position = Vector3(WorldLayout.LAKE_CENTER.x, 0.0, WorldLayout.LAKE_CENTER.y)
	_check(not nav.is_walkable_cell(grid.world_to_grid(victim.global_position)), "victim starts inside a blocked lake cell")
	var rescued := false
	for i in 360: # 6s @60fps，覆盖 2s 滞留判定 + AI 干扰余量
		await get_tree().physics_frame
		if not is_instance_valid(victim):
			break
		if nav.is_walkable_cell(grid.world_to_grid(victim.global_position)):
			rescued = true
			break
	_check(rescued and is_instance_valid(victim), "pawn stuck in the lake auto-rescues onto walkable ground")
	if is_instance_valid(victim):
		_check(victim.stat_terrain_rescues >= 1, "terrain rescue counter incremented (%d)" % victim.stat_terrain_rescues)
		victim.queue_free()


# ---- ④ 主角不被自动搬移 ----

func _check_hero_rescue_excluded() -> void:
	var hero = null
	for u in get_tree().get_nodes_in_group("player_unit"):
		if is_instance_valid(u) and u is Hero:
			hero = u
			break
	_check(hero != null and hero.allows_terrain_rescue() == false,
		"hero wading is legal and never auto-teleported")
