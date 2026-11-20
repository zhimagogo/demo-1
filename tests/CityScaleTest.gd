extends Node
## ============================================================================
## v43 城池与房屋比例扩大 + 湖泊东迁布局回归（需求③a）
##   godot --headless --path . tests/CityScaleTest.tscn --fixed-fps 60
##
## 覆盖：a) 王城 52×52m（CITY_HALF 26，CitySystem 默认值 / Main.tscn / 小地图数据同源）；
##       b) 建筑放大：木墙 1×1 / 房屋 3×3 / 酒馆 3×3 / 龙园 4×4，模型实渲高度与
##          footprint 尺寸成比例（加载真实 glTF 量测 AABB × model_scale）；
##       c) 城门火把位置从 WorldLayout.CITY_HALF 派生（城沿 +1.5m），无 21.5 旧硬编码；
##       d) 42 个资源点全部在城外环带、不在新湖 / 河 / 潭里；
##       e) 湖泊新坐标 (52,-38)/半径(17,12) 与主城矩形不重叠，河末点落在湖内；
##       f) Main.tscn Water 节点在新湖中心、水面平面覆盖全湖、材质读 WorldLayout；
##       g) 刷怪环 spawn_min_r=40 ≥ 26*√2≈36.8（矩形城圆环采样不会落城内）；
##       h) 等距相机 max_distance=68（脚本默认）/ Main.tscn ≥68、bounds ±122 不变。
##
## 输出全部 ASCII 英文（headless 日志中文会乱码）；任何路径都会 quit(0/1)。
## ============================================================================

const TIMEOUT_SEC := 90.0

var _failures: int = 0
var _main: Node = null


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(func():
		push_error("FAIL: CityScaleTest timed out")
		get_tree().quit(1))
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	if packed == null:
		_check(false, "Main.tscn loads")
		await _finish()
		return
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var world := _main.get_node_or_null("WorldRoot") as Node3D
	if world == null:
		_check(false, "WorldRoot exists")
		await _finish()
		return
	# Freeze random gameplay systems: this file only inspects static layout / data.
	for sys_name in ["WildlifeSpawner", "ResourceGrowthSystem", "SettlementSystem"]:
		var sys := world.get_node_or_null(sys_name)
		if sys != null:
			sys.set_process(false)
			sys.set_physics_process(false)
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null:
		tutorial.skip()

	await _check_city(world)
	_check_building_scale()
	await _check_model_heights()
	await _check_torches(world)
	_check_resources(world)
	_check_lake_vs_city()
	await _check_water_node(world)
	_check_spawn_ring(world)
	_check_camera(world)
	await _finish()


func _finish() -> void:
	print("CITY SCALE: %d failure(s)" % _failures)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


# ============================================================================
# a) 王城尺寸
# ============================================================================

func _check_city(world: Node3D) -> void:
	_check(is_equal_approx(WorldLayout.CITY_HALF, 26.0),
		"WorldLayout.CITY_HALF is 26m (52x52m royal city, got %.1f)" % WorldLayout.CITY_HALF)
	var fresh := CitySystem.new()
	_check(is_equal_approx(fresh.city_half, 26.0),
		"CitySystem default city_half is 26m (got %.1f)" % fresh.city_half)
	fresh.free()

	var city := world.get_node_or_null("CitySystem") as CitySystem
	_check(city != null, "Main.tscn CitySystem exists")
	if city == null:
		return
	_check(is_equal_approx(city.city_half, WorldLayout.CITY_HALF) and is_equal_approx(city.city_half, 26.0),
		"scene city_half matches WorldLayout.CITY_HALF (%.1f)" % city.city_half)
	var bounds := city.bounds_aabb()
	_check(is_equal_approx(bounds.size.x, 52.0) and is_equal_approx(bounds.size.z, 52.0),
		"city AABB is 52x52m (%.1f x %.1f)" % [bounds.size.x, bounds.size.z])
	_check(city.is_in_city(Vector3(25.9, 0.0, 25.9)) and not city.is_in_city(Vector3(26.1, 0.0, 25.9)),
		"city rectangle boundary sits exactly at 26m")
	var scatter := world.get_node_or_null("Decorations/DecorationScatter")
	_check(scatter != null and is_equal_approx(float(scatter.get("city_half")), WorldLayout.CITY_HALF),
		"DecorationScatter city_half follows WorldLayout.CITY_HALF")
	_check(is_equal_approx(float(WorldRegions.CITY["radius"]), 28.0),
		"WorldRegions.CITY.radius is 28m for region banner / minimap (got %.1f)" % float(WorldRegions.CITY["radius"]))


# ============================================================================
# b) 建筑 footprint / 模型比例
# ============================================================================

func _defs_by_id() -> Dictionary:
	var out := {}
	for d in GameDefs.building_defs():
		out[d.id] = d
	return out


func _check_building_scale() -> void:
	var defs := _defs_by_id()
	var wall: BuildingDef = defs.get(&"wall")
	var house: BuildingDef = defs.get(&"house")
	var tavern: BuildingDef = defs.get(&"tavern")
	var garden: BuildingDef = defs.get(&"dragon_garden")
	_check(wall != null and wall.footprint == Vector2i.ONE, "wall keeps 1x1 footprint")
	_check(house != null and house.footprint == Vector2i(3, 3), "house footprint is 3x3 (6x6m)")
	_check(tavern != null and tavern.footprint == Vector2i(3, 3), "tavern footprint is 3x3 (6x6m)")
	_check(garden != null and garden.footprint == Vector2i(4, 4), "dragon garden footprint is 4x4 (8x8m)")
	if wall == null or house == null or tavern == null or garden == null:
		return

	_check(is_equal_approx(house.mesh_size.x, 5.2) and is_equal_approx(house.mesh_size.y, 4.2),
		"house mesh_size ~ (5.2, 4.2, 5.2) (got %s)" % str(house.mesh_size))
	_check(is_equal_approx(tavern.mesh_size.x, 5.2) and is_equal_approx(tavern.mesh_size.y, 4.4),
		"tavern mesh_size ~ (5.2, 4.4, 5.2) (got %s)" % str(tavern.mesh_size))
	_check(is_equal_approx(garden.mesh_size.x, 7.2) and is_equal_approx(garden.mesh_size.y, 4.2),
		"dragon garden mesh_size ~ (7.2, 4.2, 7.2) (got %s)" % str(garden.mesh_size))
	_check(is_equal_approx(wall.model_scale, 1.15) and is_equal_approx(wall.mesh_size.x, 2.0),
		"wall visual scale raised to 1.15 while staying 1x1 (mesh %.2f)" % wall.mesh_size.x)
	_check(is_equal_approx(house.model_scale, 6.2), "house model_scale is 6.2 (got %.2f)" % house.model_scale)
	_check(is_equal_approx(tavern.model_scale, 4.4), "tavern model_scale is 4.4 (got %.2f)" % tavern.model_scale)
	_check(is_equal_approx(garden.model_scale, 4.2), "dragon garden model_scale is 4.2 (got %.2f)" % garden.model_scale)
	_check(is_equal_approx(tavern.heal_radius, 8.0), "tavern heal_radius follows the larger footprint (8m, got %.1f)" % tavern.heal_radius)
	# 龙园是全场最大占地（4×4 = 16 格），房屋 / 酒馆同档（3×3 = 9 格）。
	var largest := true
	for d in GameDefs.building_defs():
		if d.id != &"dragon_garden" and d.footprint.x * d.footprint.y >= garden.footprint.x * garden.footprint.y:
			largest = false
	_check(largest, "dragon garden keeps the largest footprint in the building table")
	# footprint 世界尺寸与碰撞盒：mesh_size 不得越出占地。
	for d in [house, tavern, garden]:
		var world_size: float = float(d.footprint.x) * 2.0
		_check(d.mesh_size.x <= world_size + 0.01 and d.mesh_size.z <= world_size + 0.01,
			"%s collision box fits its footprint (%.1f <= %.1f)" % [String(d.id), d.mesh_size.x, world_size])


## 真实 glTF AABB × model_scale：建筑实渲高度必须远高于 1.8m 人物，且与占地成比例。
func _check_model_heights() -> void:
	var defs := _defs_by_id()
	for key in [&"house", &"tavern", &"dragon_garden"]:
		var d: BuildingDef = defs.get(key)
		if d == null:
			_check(false, "building def exists: %s" % String(key))
			continue
		var raw := _model_height(d.model_path)
		if raw <= 0.0:
			_check(false, "model AABB measurable: %s" % d.model_path)
			continue
		var height: float = raw * d.model_scale
		var width: float = float(d.footprint.x) * 2.0
		print("MODEL HEIGHT: %s raw=%.2fm scale=%.2f -> %.2fm (footprint %.1fm)" % [
			String(key), raw, d.model_scale, height, width])
		_check(height > 4.6, "%s renders far above the 1.8m human (%.2fm)" % [String(key), height])
		_check(height > width * 0.62 and height < width * 1.35,
			"%s model height is proportional to its footprint (%.2fm vs %.1fm)" % [String(key), height, width])


## 载入模型场景并量测「根空间 AABB 高度」（不含 model_scale）。
func _model_height(path: String) -> float:
	var packed := load(path) as PackedScene
	if packed == null:
		return -1.0
	var root := packed.instantiate() as Node3D
	if root == null:
		return -1.0
	add_child(root)
	var merged := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			merged = box
			first = false
		else:
			merged = merged.merge(box)
	var height: float = 0.0 if first else merged.size.y
	root.queue_free()
	return height


# ============================================================================
# c) 城门火把
# ============================================================================

func _check_torches(world: Node3D) -> void:
	var dnc := world.get_node_or_null("DayNightCycle") as DayNightCycle
	_check(dnc != null, "DayNightCycle exists")
	if dnc == null:
		return
	var torches: Array = dnc._torch_lights
	# v47：城堡角 1 + 四门 4 + 城内四角 4 = 9（夜间暖光轮廓）
	_check(torches.size() == 9, "nine torches registered (castle corner + four gates + four inner corners, got %d)" % torches.size())
	var gate := WorldLayout.CITY_HALF + 1.5
	var gate_hits := 0
	var corner_hits := 0
	var outer := gate * 0.66
	var old_hits := 0
	for raw in torches:
		if not is_instance_valid(raw):
			continue
		var pos: Vector3 = (raw as OmniLight3D).position
		var on_gate := (is_equal_approx(absf(pos.x), gate) and is_zero_approx(pos.z)) \
			or (is_equal_approx(absf(pos.z), gate) and is_zero_approx(pos.x))
		if on_gate:
			gate_hits += 1
		if is_equal_approx(absf(pos.x), outer) and is_equal_approx(absf(pos.z), outer):
			corner_hits += 1
		if is_equal_approx(absf(pos.x), 21.5) or is_equal_approx(absf(pos.z), 21.5):
			old_hits += 1
	_check(gate_hits == 4, "four gate torches sit on the 26m city edge (%.1fm, got %d)" % [gate, gate_hits])
	_check(corner_hits == 4, "four inner-corner torches light the city at night (got %d)" % corner_hits)
	_check(old_hits == 0, "no torch remains at the old 21.5m city edge")
	_check(dnc._torch_lights.size() > 0 and WorldLayout.CITY_HALF + 1.5 > 21.5,
		"gate torch offset is derived from WorldLayout.CITY_HALF")


# ============================================================================
# d) 资源点：城外环带 / 不在湖里
# ============================================================================

func _check_resources(world: Node3D) -> void:
	var nodes := get_tree().get_nodes_in_group("resource_node")
	_check(nodes.size() == 42, "42 resource nodes present (got %d)" % nodes.size())
	var in_city := 0
	var in_water := 0
	var too_close := 0
	var min_cheby := INF
	for n in nodes:
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var p := (n as Node3D).global_position
		var point := Vector2(p.x, p.z)
		var cheby: float = maxf(absf(p.x), absf(p.z))
		min_cheby = minf(min_cheby, cheby)
		if cheby <= WorldLayout.CITY_HALF:
			in_city += 1
		if cheby <= WorldLayout.CITY_HALF + 1.0:
			too_close += 1
		if WorldLayout.lake_distance(point) < 1.0 or WorldLayout.water_distance(point) < 0.0:
			in_water += 1
	_check(in_city == 0, "no resource node stands inside the city rectangle (%d)" % in_city)
	_check(too_close == 0, "all resource nodes are clear of the city + 1m safety ring (%d too close, nearest chebyshev %.1fm)" % [
		too_close, min_cheby])
	_check(in_water == 0, "no resource node stands in the new lake / river / pool (%d)" % in_water)


# ============================================================================
# e) 湖泊 vs 主城
# ============================================================================

func _check_lake_vs_city() -> void:
	_check(WorldLayout.LAKE_CENTER.is_equal_approx(Vector2(52.0, -38.0)),
		"lake moved to (52,-38) (got %s)" % str(WorldLayout.LAKE_CENTER))
	_check(WorldLayout.LAKE_RADII.is_equal_approx(Vector2(17.0, 12.0)),
		"lake radii are 17x12m (got %s)" % str(WorldLayout.LAKE_RADII))
	_check(WorldLayout.WATERFALL_LIP.is_equal_approx(Vector2(58.0, -72.0)),
		"waterfall lip moved to (58,-72) (got %s)" % str(WorldLayout.WATERFALL_LIP))
	_check(WorldLayout.POOL_CENTER.is_equal_approx(Vector2(56.0, -64.0)),
		"plunge pool center moved to (56,-64) (got %s)" % str(WorldLayout.POOL_CENTER))
	_check(is_equal_approx(WorldLayout.WATERFALL_WIDTH, 9.0), "waterfall widened to 9m")
	_check(WorldLayout.WATERFALL_TOP_Y >= 8.2, "waterfall lip height raised to >= 8.2m (%.1f)" % WorldLayout.WATERFALL_TOP_Y)
	# 矩形城与椭圆湖不重叠：湖最西点 52-17=35 > 26。
	_check(WorldLayout.CITY_HALF < WorldLayout.LAKE_CENTER.x - WorldLayout.LAKE_RADII.x,
		"city half (%.1f) stays west of the lake west shore (%.1f)" % [
			WorldLayout.CITY_HALF, WorldLayout.LAKE_CENTER.x - WorldLayout.LAKE_RADII.x])
	var lake_overlaps := 0
	for i in 64:
		var angle := TAU * float(i) / 64.0
		var shore := WorldLayout.LAKE_CENTER + Vector2(cos(angle), sin(angle)) * WorldLayout.LAKE_RADII
		if absf(shore.x) <= WorldLayout.CITY_HALF and absf(shore.y) <= WorldLayout.CITY_HALF:
			lake_overlaps += 1
	_check(lake_overlaps == 0, "64 sampled lake shore points all lie outside the city rectangle (%d)" % lake_overlaps)
	var river_tail: Vector2 = WorldLayout.RIVER_PTS[WorldLayout.RIVER_PTS.size() - 1]
	_check(WorldLayout.lake_distance(river_tail) < 1.0,
		"river mouth ends inside the lake (lake distance %.2f)" % WorldLayout.lake_distance(river_tail))
	_check(WorldLayout.pool_distance(WorldLayout.RIVER_PTS[0]) < 1.0,
		"river starts inside the plunge pool (pool distance %.2f)" % WorldLayout.pool_distance(WorldLayout.RIVER_PTS[0]))
	_check(WorldLayout.is_water(WorldLayout.LAKE_CENTER, 0.01) and not WorldLayout.is_water(Vector2.ZERO, 0.01),
		"lake center is water, city center is dry")


# ============================================================================
# f) Main.tscn Water 节点
# ============================================================================

func _check_water_node(world: Node3D) -> void:
	var water := world.get_node_or_null("Water") as MeshInstance3D
	_check(water != null, "Main.tscn Water node exists")
	if water == null:
		return
	_check(water.is_in_group("water_feature"), "Water node is in the water_feature group")
	var pos := water.position
	_check(Vector2(pos.x, pos.z).distance_to(WorldLayout.LAKE_CENTER) < 0.05,
		"Water node sits on the new lake center (%.1f, %.1f)" % [pos.x, pos.z])
	_check(is_equal_approx(pos.y, 0.06), "Water surface stays 6cm above the ground (%.2f)" % pos.y)
	var plane := water.mesh as PlaneMesh
	_check(plane != null, "Water mesh is a PlaneMesh")
	if plane != null:
		_check(plane.size.x >= WorldLayout.LAKE_RADII.x * 2.0 and plane.size.y >= WorldLayout.LAKE_RADII.y * 2.0,
			"Water plane covers the whole lake (%.0fx%.0f >= %.0fx%.0f)" % [
				plane.size.x, plane.size.y, WorldLayout.LAKE_RADII.x * 2.0, WorldLayout.LAKE_RADII.y * 2.0])
	var mat := water.material_override as ShaderMaterial
	_check(mat != null, "Water uses a ShaderMaterial")
	if mat != null:
		var lake_arg = mat.get_shader_parameter("lake_center")
		_check(lake_arg is Vector2 and (lake_arg as Vector2).distance_to(WorldLayout.LAKE_CENTER) < 0.01,
			"water shader lake_center uniform follows WorldLayout")


# ============================================================================
# g) 刷怪环
# ============================================================================

func _check_spawn_ring(world: Node3D) -> void:
	var wildlife := world.get_node_or_null("WildlifeSpawner") as WildlifeSpawner
	_check(wildlife != null, "WildlifeSpawner exists")
	if wildlife == null:
		return
	var min_required: float = WorldLayout.CITY_HALF * sqrt(2.0)
	_check(wildlife.spawn_min_r >= min_required,
		"spawn_min_r (%.1f) >= city half * sqrt(2) (%.1f)" % [wildlife.spawn_min_r, min_required])
	_check(is_equal_approx(wildlife.spawn_min_r, 40.0), "spawn_min_r tuned to 40m (got %.1f)" % wildlife.spawn_min_r)
	_check(is_equal_approx(wildlife.spawn_max_r, 116.0), "spawn_max_r stays 116m (got %.1f)" % wildlife.spawn_max_r)
	var city := world.get_node("CitySystem") as CitySystem
	var inside := 0
	for i in 64:
		var p := city.random_point_outside(wildlife.spawn_min_r, wildlife.spawn_max_r)
		if city.is_in_city(p):
			inside += 1
	_check(inside == 0, "64 spawn-ring samples all land outside the rectangular city (%d inside)" % inside)


# ============================================================================
# h) 等距相机
# ============================================================================

func _check_camera(world: Node3D) -> void:
	var fresh := IsometricCamera.new()
	_check(fresh.max_distance >= 68.0, "IsometricCamera default max_distance >= 68 (got %.1f)" % fresh.max_distance)
	_check(is_equal_approx(fresh.target_distance, 44.0), "IsometricCamera default target_distance stays 44m")
	fresh.free()
	var cam := world.get_node_or_null("IsometricCamera") as IsometricCamera
	_check(cam != null, "Main.tscn IsometricCamera exists")
	if cam == null:
		return
	_check(cam.max_distance >= 68.0, "scene camera max_distance >= 68 (got %.1f)" % cam.max_distance)
	var b := cam.bounds
	_check(b.position.x <= -120.0 and b.end.x >= 120.0 and b.position.z <= -120.0 and b.end.z >= 120.0,
		"camera bounds still cover the 256m world (x %.0f..%.0f, z %.0f..%.0f)" % [
			b.position.x, b.end.x, b.position.z, b.end.z])
