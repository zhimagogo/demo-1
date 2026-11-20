extends Node
## ============================================================================
## v40 世界扩张回归（128×128m → 256×256m）
## ============================================================================
## 运行：godot --headless --path . tests/WorldExpansionTest.tscn --fixed-fps 60
##
## 覆盖：
##   a) 网格：GridSystem 128×128 格 @2m（half_x()=128=MAP_HALF）；王城 v43 扩到 26m 半边长；
##   b) 地面物理：扩张环带 (120,120)/(−120,−120) 等竖直下射线打中 GroundPlane 顶面；
##      图外 (140,140)/(−140,−140) 无地面碰撞；
##   c) 主题区域数据：6 个唯一 id、圆域与地标都在图内、地标在岸上且不在王城、
##      区域相互重叠 ≤20%、region_at(landmark) 命中所属区域；
##   d) 导航：主城 → 六个区域地标 A* 可达（终点距 ≤12m）、四条路尽头在图内且贴路、
##      小径 14 段采样点都能吸附到可走格；
##   e) 绑定：小地图 _w2m(landmark) 落在画布内、王城在小地图中心；
##   f) WorldScenery 自动挂载 ThemedRegions / RegionTracker（脚本未落地时 SKIP）；
##   g) 加载性能护栏：实例化 → 首帧可操作 < 20s；打印节点数 / MultiMesh 实例总数
##      （只记录，不硬断言上限）。
##
## 任何路径都会 quit（关键节点缺失也走 _finish），避免 Parse Error / 早退挂死整批。
## ============================================================================

var _failures: int = 0
var _skips: int = 0
var _main: Node = null


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _skip(message: String) -> void:
	_skips += 1
	print("SKIP: ", message)


func _finish() -> void:
	print("WORLD EXPANSION: %d failure(s), %d skipped" % [_failures, _skips])
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	# ---- g) 加载性能计时：从实例化到首帧可操作 ----
	var started := Time.get_ticks_msec()
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	if packed == null:
		_check(false, "Main.tscn 可加载")
		await _finish()
		return
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var load_ms := Time.get_ticks_msec() - started

	var world := _main.get_node_or_null("WorldRoot") as Node3D
	if world == null:
		_check(false, "WorldRoot 存在")
		await _finish()
		return
	# 冻结后台系统：本测试只验证静态世界数据，避免刷怪 / 资源再生污染断言
	var spawner := world.get_node_or_null("WildlifeSpawner")
	if spawner != null:
		(spawner as Node).set_process(false)
	var growth := world.get_node_or_null("ResourceGrowthSystem")
	if growth != null:
		(growth as Node).set_process(false)

	var grid := world.get_node_or_null("GridSystem") as GridSystem
	var nav := world.get_node_or_null("NavSystem") as NavSystem
	var city := world.get_node_or_null("CitySystem") as CitySystem
	_check(grid != null and nav != null and city != null, "世界树关键系统齐备（GridSystem / NavSystem / CitySystem）")
	if grid == null or nav == null or city == null:
		await _finish()
		return

	_check_world_bounds(grid, city, world)
	_check_ground_physics(world)
	_check_region_data(city)
	await _check_navigation(grid, nav)
	await _check_region_bindings(world)
	_check_region_nodes(world)
	_check_load_performance(load_ms)
	await _finish()


# ============================================================================
# a) 网格 / 王城 / 相机边界
# ============================================================================

func _check_world_bounds(grid: GridSystem, city: CitySystem, world: Node3D) -> void:
	_check(grid.grid_size == Vector2i(128, 128), "世界网格 128×128 格（当前 %s）" % str(grid.grid_size))
	_check(is_equal_approx(grid.cell_size, 2.0), "网格单元 2m（当前 %.2fm）" % grid.cell_size)
	_check(is_equal_approx(grid.half_x(), WorldLayout.MAP_HALF) and is_equal_approx(grid.half_z(), WorldLayout.MAP_HALF),
		"网格半宽 = MAP_HALF = 128m（half_x=%.1f, half_z=%.1f）" % [grid.half_x(), grid.half_z()])
	_check(is_equal_approx(grid.half_x() * 2.0, 256.0), "可玩边长 256m（当前 %.0fm）" % (grid.half_x() * 2.0))
	_check(is_equal_approx(city.city_half, WorldLayout.CITY_HALF) and is_equal_approx(city.city_half, 26.0),
		"王城 v43 扩到 26m 半边长（52×52m，当前 %.1fm）" % city.city_half)
	var cam := world.get_node_or_null("IsometricCamera") as IsometricCamera
	if cam == null:
		_check(false, "IsometricCamera 存在")
		return
	var bounds := cam.bounds
	_check(bounds.position.x <= -120.0 and bounds.end.x >= 120.0
			and bounds.position.z <= -120.0 and bounds.end.z >= 120.0,
		"等距相机边界覆盖 256m 世界（x %.0f..%.0f, z %.0f..%.0f）"
			% [bounds.position.x, bounds.end.x, bounds.position.z, bounds.end.z])


# ============================================================================
# b) 地面物理：竖直射线打 GroundPlane
# ============================================================================

## 从 y=50 竖直下射到 y=-1：起点在所有碰撞体之上，终点在地面顶面（y=0）之下，
## 只可能命中 GroundPlane 的 256×256 碰撞盒（远山 / 装饰无碰撞体）。
func _cast_down(space: PhysicsDirectSpaceState3D, ground_point: Vector3) -> Dictionary:
	var from := Vector3(ground_point.x, 50.0, ground_point.z)
	var to := Vector3(ground_point.x, -1.0, ground_point.z)
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _check_ground_physics(world: Node3D) -> void:
	var ground := world.get_node_or_null("GroundPlane") as StaticBody3D
	_check(ground != null, "GroundPlane 存在")
	if ground == null:
		return
	var space := world.get_world_3d().direct_space_state
	# 扩张环带四角必须都有地面碰撞（旧的 128×128m 地面只有 ±64m，本项会红）
	for point in [Vector3(120, 0, 120), Vector3(-120, 0, -120),
			Vector3(120, 0, -120), Vector3(-120, 0, 120)]:
		var hit := _cast_down(space, point)
		var collider = hit.get("collider")
		_check(not hit.is_empty() and collider == ground,
			"扩张环带地面有物理碰撞 @(%.0f, %.0f)（命中=%s）" % [point.x, point.z, str(not hit.is_empty())])
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			_check(absf(hit_pos.y) <= 0.1, "地面顶面在 y≈0 @(%.0f, %.0f)（y=%.2f）"
				% [point.x, point.z, hit_pos.y])
	# 图外三个方向（正角 + 负角）都不得有地面碰撞
	for point in [Vector3(140, 0, 140), Vector3(-140, 0, -140), Vector3(140, 0, -140)]:
		var hit := _cast_down(space, point)
		_check(hit.is_empty(), "图外无地面碰撞 @(%.0f, %.0f)" % [point.x, point.z])


# ============================================================================
# c) 主题区域数据自洽
# ============================================================================

func _check_region_data(city: CitySystem) -> void:
	var regions := WorldRegions.all()
	_check(WorldRegions.count() == 6 and regions.size() == 6, "六个主题区域数据齐全（当前 %d）" % regions.size())
	var ids := {}
	for region in regions:
		ids[String(region["id"])] = true
	_check(ids.size() == regions.size(), "主题区域 id 唯一（%d 个）" % ids.size())
	var kinds := {}
	for region in regions:
		kinds[region["kind"]] = true
	for kind in [&"frost", &"mine", &"wheat", &"battle", &"forest", &"swamp"]:
		_check(kinds.has(kind), "主题区域类型齐全：%s" % String(kind))

	var max_overlap := 0.0
	for region in regions:
		var region_id := String(region["id"])
		var center: Vector2 = region["center"]
		var radius: float = float(region["radius"])
		var landmark: Vector2 = region["landmark"]
		_check(absf(center.x) + radius <= WorldLayout.MAP_HALF + 0.01
				and absf(center.y) + radius <= WorldLayout.MAP_HALF + 0.01,
			"%s 圆域完整落在 256m 图内（|x|+r=%.0f, |z|+r=%.0f）"
				% [region_id, absf(center.x) + radius, absf(center.y) + radius])
		_check(absf(landmark.x) <= WorldLayout.MAP_HALF and absf(landmark.y) <= WorldLayout.MAP_HALF,
			"%s 地标在图内（%.0f, %.0f）" % [region_id, landmark.x, landmark.y])
		_check(WorldLayout.water_distance(landmark) >= 0.5,
			"%s 地标在岸上（离水 %.2fm）" % [region_id, WorldLayout.water_distance(landmark)])
		_check(not city.is_in_city(Vector3(landmark.x, 0.0, landmark.y)), "%s 地标不在王城内" % region_id)
		_check(WorldRegions.normalized_distance(landmark, region) <= 1.0,
			"%s 地标落在自己的圆域内（归一化距离 %.2f）"
				% [region_id, WorldRegions.normalized_distance(landmark, region)])
		var at := WorldRegions.region_at(landmark)
		_check(String(at.get("id", "")) == region_id,
			"%s 地标 region_at 命中所属区域（当前 %s）" % [region_id, String(at.get("id", ""))])
		_check(WorldRegions.landmark_clearance(landmark),
			"%s 地标纳入植被避让核心区（8m 内不散布树石）" % region_id)
		_check(float(region["tint"]) > 0.0 and float(region["tint"]) <= 1.0,
			"%s 地面染色强度在 0..1 内（%.2f）" % [region_id, float(region["tint"])])
		_check(String(region["name"]) != "" and String(region["lore"]) != "",
			"%s 有中文区域名与故事文本" % region_id)
		_check(radius >= 20.0, "%s 区域半径足够大（%.0fm）" % [region_id, radius])

	for i in regions.size():
		for j in range(i + 1, regions.size()):
			max_overlap = maxf(max_overlap, _circle_overlap_ratio(regions[i], regions[j]))
	_check(max_overlap <= 0.2, "主题区域相互重叠 ≤20%%（最大 %.1f%%）" % (max_overlap * 100.0))


## 两个圆形区域的重叠面积 / 较小圆面积（0=不重叠，1=完全包含）。
func _circle_overlap_ratio(a: Dictionary, b: Dictionary) -> float:
	var center_a: Vector2 = a["center"]
	var center_b: Vector2 = b["center"]
	var radius_a: float = float(a["radius"])
	var radius_b: float = float(b["radius"])
	var d := center_a.distance_to(center_b)
	if d >= radius_a + radius_b:
		return 0.0
	if d <= absf(radius_a - radius_b):
		return 1.0
	var x := clampf((d * d + radius_a * radius_a - radius_b * radius_b) / (2.0 * d * radius_a), -1.0, 1.0)
	var y := clampf((d * d + radius_b * radius_b - radius_a * radius_a) / (2.0 * d * radius_b), -1.0, 1.0)
	var overlap_area := radius_a * radius_a * acos(x) + radius_b * radius_b * acos(y) \
		- 0.5 * sqrt(maxf((-d + radius_a + radius_b) * (d + radius_a - radius_b)
			* (d - radius_a + radius_b) * (d + radius_a + radius_b), 0.0))
	var smaller := minf(radius_a, radius_b)
	return overlap_area / (PI * smaller * smaller)


# ============================================================================
# d) 导航连通：四路尽头 / 主城 → 六地标 / 小径可吸附
# ============================================================================

func _check_navigation(grid: GridSystem, nav: NavSystem) -> void:
	# ---- 四路尽头：在图内、贴路、方位名与小地图罗盘一致（-Z=北、+X=东、+Z=南、-X=西）----
	var compass := ["南", "东", "北", "西"]
	for index in 4:
		var road_end := WorldLayout.road_end(index)
		_check(absf(road_end.x) <= WorldLayout.MAP_HALF and absf(road_end.y) <= WorldLayout.MAP_HALF,
			"%s 路尽头在图内（%.1f, %.1f）" % [compass[index], road_end.x, road_end.y])
		_check(WorldLayout.road_distance(road_end) < 3.5,
			"%s 路尽头贴着道路（离路 %.2fm）" % [compass[index], WorldLayout.road_distance(road_end)])
		_check(WorldLayout.road_end_name(index) == compass[index],
			"路尽头方位名与小地图罗盘一致：%d=%s（当前 %s）"
				% [index, compass[index], WorldLayout.road_end_name(index)])
		_check(not grid.terrain_cells.has(grid.world_to_grid(Vector3(road_end.x, 0.0, road_end.y))),
			"%s 路尽头不落在永久阻挡格（夜潮出生点可站）" % compass[index])
	_check(WorldLayout.road_end_name(4) == "南" and WorldLayout.road_end_name(7) == "西",
		"路尽头方位名按 4 取模回绕")

	# ---- 主城 → 六个区域地标：A* 非空、终点落在目标附近、路径不穿永久阻挡 ----
	var raw_origin := Vector3(0.0, 0.0, 20.0)
	var origin := nav.snap_to_walkable(raw_origin)
	var origin_snap := Vector2(origin.x, origin.z).distance_to(Vector2(raw_origin.x, raw_origin.z))
	_check(origin_snap <= 6.0, "主城近旁起点 (0,0,20) 可走（吸附 %.2fm）" % origin_snap)
	for region in WorldRegions.all():
		var region_id := String(region["id"])
		var landmark: Vector2 = region["landmark"]
		var target := Vector3(landmark.x, 0.0, landmark.y)
		var path := nav.get_world_path(origin, target)
		var reachable := not path.is_empty()
		var end_distance := INF
		if reachable:
			var last := path[path.size() - 1]
			end_distance = Vector2(last.x, last.z).distance_to(landmark)
		_check(reachable and end_distance <= 12.0,
			"主城 → %s 地标 A* 可达（%d 航点，终点距地标 %.2fm）"
				% [region_id, path.size(), end_distance])
		var dry := reachable
		for point in path:
			if grid.terrain_cells.has(grid.world_to_grid(point)):
				dry = false
				break
		_check(dry, "%s 路径全程避开永久阻挡（湖泊 / 河 / 崖）" % region_id)

	# ---- 小径网络：每段按 0/25/50/75/100% 采样，吸附后必须仍是可走格 ----
	var samples := 0
	var bad := 0
	var worst_snap := 0.0
	var worst_where := Vector2.ZERO
	for segment in WorldLayout.TRAIL_SEGMENTS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var tf: float = t
			var raw: Vector2 = a.lerp(b, tf)
			var snapped := nav.snap_to_walkable(Vector3(raw.x, 0.0, raw.y))
			var cell := grid.world_to_grid(snapped)
			samples += 1
			if not grid.is_inside(cell) or grid.terrain_cells.has(cell) or not nav.is_walkable_cell(cell):
				bad += 1
			var snap_distance := Vector2(snapped.x, snapped.z).distance_to(raw)
			if snap_distance > worst_snap:
				worst_snap = snap_distance
				worst_where = raw
	_check(WorldLayout.TRAIL_SEGMENTS.size() >= 14,
		"小径网络段数 ≥14（当前 %d）" % WorldLayout.TRAIL_SEGMENTS.size())
	_check(bad == 0, "小径 %d 个采样点全部吸附到可走格（%d 个异常，最远吸附 %.2fm @(%.0f,%.0f)）"
		% [samples, bad, worst_snap, worst_where.x, worst_where.y])


# ============================================================================
# e) 小地图绑定
# ============================================================================

func _check_region_bindings(world: Node3D) -> void:
	var hud := _main.get_node_or_null("HUD")
	_check(hud != null and hud.get("minimap") != null, "HUD 装配小地图")
	if hud == null:
		return
	var minimap = hud.get("minimap")
	if minimap == null:
		return
	# 固定战术俯瞰 + 0° 朝向：小地图旋转角确定，_w2m 结果可复现
	var controller := world.get_node_or_null("HeroController") as HeroController
	if controller != null:
		controller.exit_hero_mode()
	var iso := world.get_node_or_null("IsometricCamera") as IsometricCamera
	if iso != null:
		iso.make_current()
		iso._yaw_step = 0
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	minimap._refresh_rotation()
	var canvas_size: float = float(minimap.MAP_PX)
	var city_center: Vector2 = minimap._w2m(Vector2.ZERO)
	_check(city_center.distance_to(Vector2(canvas_size * 0.5, canvas_size * 0.5)) < 1.0,
		"王城映射到小地图中心（%.1f, %.1f）" % [city_center.x, city_center.y])
	for region in WorldRegions.all():
		var region_id := String(region["id"])
		var landmark: Vector2 = region["landmark"]
		var map_point: Vector2 = minimap._w2m(landmark)
		_check(map_point.x >= -0.5 and map_point.y >= -0.5
				and map_point.x <= canvas_size + 0.5 and map_point.y <= canvas_size + 0.5,
			"%s 地标落在小地图画布内（%.1f, %.1f / %.0f）"
				% [region_id, map_point.x, map_point.y, canvas_size])


# ============================================================================
# f) WorldScenery 自动挂载主题区域节点
# ============================================================================

func _check_region_nodes(world: Node3D) -> void:
	var scenery := world.get_node_or_null("WorldScenery")
	_check(scenery != null, "WorldScenery 节点存在（主题区域挂载点）")
	if scenery == null:
		return
	var entries := [
		["ThemedRegions", "res://scripts/decor/ThemedRegions.gd"],
		["RegionTracker", "res://scripts/systems/RegionTracker.gd"],
	]
	for entry in entries:
		var node_name: String = entry[0]
		var script_path: String = entry[1]
		if not ResourceLoader.exists(script_path):
			_skip("%s 脚本尚未落地（%s）——挂载检查跳过，实现到位后本项自动转为正式断言"
				% [node_name, script_path])
			continue
		var node: Node = null
		var found := scenery.get_node_or_null(node_name)
		if found != null:
			node = found
		_check(node != null, "WorldScenery 自动挂载 %s" % node_name)
		if node != null:
			var expected := load(script_path) as Script
			_check(node.get_script() == expected, "%s 使用预期脚本 %s" % [node_name, script_path])
			if node_name == "ThemedRegions":
				print("INFO: ThemedRegions 子节点数=%d" % node.get_child_count())


# ============================================================================
# g) 加载性能护栏（只记录，不硬断言节点 / 实例上限）
# ============================================================================

func _check_load_performance(load_ms: int) -> void:
	_check(load_ms < 20000, "实例化 → 首帧可操作耗时 %dms < 20s" % load_ms)
	var hero: Node = null
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if unit is Hero:
			hero = unit
			break
	_check(hero != null, "首帧可操作：主角已生成")
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var stats := {"nodes": 0, "instances": 0}
	_count_multimesh(_main, stats)
	print("INFO: 节点总数=%d，MultiMesh 节点=%d，MultiMesh 实例总数=%d"
		% [node_count, int(stats["nodes"]), int(stats["instances"])])


func _count_multimesh(node: Node, stats: Dictionary) -> void:
	if node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi != null:
			stats["nodes"] = int(stats["nodes"]) + 1
			stats["instances"] = int(stats["instances"]) + multi.instance_count
	for child in node.get_children():
		_count_multimesh(child, stats)
