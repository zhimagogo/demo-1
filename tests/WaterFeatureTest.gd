extends Node
## 水系专项回归（v12 需求 4，v43 视觉迭代更新）：瀑布 -> 水潭 -> 河流 -> 湖泊。
## 运行：godot --headless --path . tests/WaterFeatureTest.tscn --log-file /tmp/w-water.log --fixed-fps 60
##
## 覆盖：几何数学（与 WorldLayout 同源）/ 水面网格存在与包围盒 / 多股落水 / 湖心小岛 /
## 河道与崖体寻路登记 / 浅滩涉水点不阻挡 / 单位真的能过河 / 崖体物理碰撞可被射线命中 /
## v43 新增：湖岸谐波自然度、多股落水帘与落水点、岛屿纯视觉（不改阻挡）、shader uniform 有效性。
## v45 新增：水体调色统一走 WaterPalette、多层落水（后层/主帘/前层 + 唇口翻卷）、
## 水雾必须是小尺度 alpha 混合（防「硬白圆饼」回归）、3D 白沫丘、霜区浮冰 / 雪斑为不规则有机网格。

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
	for raider in get_tree().get_nodes_in_group("enemy"):
		raider.queue_free()
	await get_tree().physics_frame
	var grid := world.get_node("GridSystem") as GridSystem
	var nav := world.get_node("NavSystem") as NavSystem
	var feature := world.get_node_or_null("WorldScenery/WaterFeature") as WaterFeature
	_check(feature != null and grid != null and nav != null, "water feature / grid / nav are wired")
	if feature == null or grid == null or nav == null:
		_finish()
		return

	_check_geometry(feature)
	_check_meshes(feature)
	_check_v45_polish(world, feature)
	_check_lake_shape(grid, nav)
	_check_navigation(grid, nav, feature)
	await _check_cliff(feature)
	await _check_ford_crossing(world, nav, feature)
	_finish()


func _finish() -> void:
	print("WATER FEATURE TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 1) 几何数学（与 WorldLayout 同源，改河道只需改那里）----

func _check_geometry(feature: WaterFeature) -> void:
	var mid := WorldLayout.RIVER_PTS[1]
	var rv := WorldLayout.river_distance(mid)
	_check(rv.x < 0.02, "river_distance at polyline point ~ 0 (%.3f)" % rv.x)
	_check(absf(rv.y - WorldLayout.RIVER_HALF[1]) < 0.05,
		"river half width matches RIVER_HALF (%.2f vs %.2f)" % [rv.y, WorldLayout.RIVER_HALF[1]])
	_check(WorldLayout.is_river(mid, 0.0), "is_river true on the river centerline")
	_check(not WorldLayout.is_river(Vector2.ZERO, 0.0), "is_river false inside the city")
	_check(WorldLayout.lake_distance(WorldLayout.RIVER_PTS[WorldLayout.RIVER_PTS.size() - 1]) < 1.0,
		"river mouth ends inside the lake")
	var pool_mid := WorldLayout.POOL_CENTER
	_check(WorldLayout.pool_distance(pool_mid) < 0.2, "pool center is inside the plunge pool")
	_check(WorldLayout.is_water(pool_mid, 0.0), "is_water true at the plunge pool")
	# 河从潭里流出来：首点仍在潭内（WorldLayout / CityScaleTest 的口径），但河带网格要裁到潭岸外，
	# 否则两张 y≈0.30 的水面叠在一起会 z-fighting。
	_check(WorldLayout.pool_distance(WorldLayout.RIVER_PTS[0]) < 1.0,
		"river source stays inside the plunge pool (pool_sdf %.2f)" % WorldLayout.pool_distance(WorldLayout.RIVER_PTS[0]))
	# 瀑布立面参数化：唇口 = 横向中点 / 纵向 0；地图别处 = outside
	var lip_uv := WorldLayout.waterfall_uv(WorldLayout.WATERFALL_LIP)
	_check(absf(lip_uv.x - 0.5) < 0.02 and lip_uv.y < 0.02 and lip_uv.z < 0.5,
		"waterfall_uv maps the lip to lat 0.5 / along 0")
	var base_uv := WorldLayout.waterfall_uv(WorldLayout.WATERFALL_BASE)
	_check(base_uv.y > 0.9 and base_uv.z < 0.5, "waterfall_uv maps the plunge point to along ~ 1")
	_check(WorldLayout.waterfall_uv(Vector2.ZERO).z > 0.5, "waterfall_uv reports outside far from the wall")
	# 水面高度：河口要贴着湖面，避免出现台阶
	var mouth_y: float = feature.river_surface_y(WorldLayout.RIVER_PTS[WorldLayout.RIVER_PTS.size() - 1])
	var upper_y: float = feature.river_surface_y(WorldLayout.RIVER_PTS[0])
	var ford_y: float = feature.river_surface_y(WaterFeature.FORD_CENTER)
	_check(mouth_y < 0.14, "river surface reaches the lake level at the mouth (%.2f)" % mouth_y)
	_check(ford_y < 0.2 and ford_y < WorldLayout.WATER_HIGH_Y - 0.12,
		"ford dips the river into a shallow riffle (%.2f at the ford, %.2f upstream, %.2f nominal)"
			% [ford_y, upper_y, WorldLayout.WATER_HIGH_Y])
	_check(feature.river_samples().size() > 20, "river ribbon is sampled from the polyline")


# ---- 2) 水面网格与材质 ----

func _check_meshes(feature: WaterFeature) -> void:
	var names: Array[String] = []
	for n in get_tree().get_nodes_in_group("water_feature"):
		names.append(String((n as Node).name))
	for wanted in ["Water", "RiverWater", "PoolWater", "WaterfallCurtain", "CliffTopStream",
			"CliffLipSheet", "WaterfallFoam", "LakeIsland"]:
		_check(names.has(wanted), "water mesh present: %s" % wanted)
	_check(feature.river_mesh != null and feature.pool_mesh != null and feature.curtain_mesh != null,
		"river / pool / waterfall meshes built")
	if feature.river_mesh == null:
		return
	# 河道网格要覆盖整条折线（含末端延伸），否则河口会被湖面剔除区挖出洞
	var river_box := _world_aabb(feature.river_mesh)
	var tail: Vector2 = WorldLayout.RIVER_PTS[WorldLayout.RIVER_PTS.size() - 1]
	# 起点裁在水潭岸线外（河与潭共用 y≈0.30，重叠会 z-fighting）
	var first: Dictionary = feature.river_samples()[0]
	var outlet: Vector2 = first["p"]
	_check(WorldLayout.pool_distance(outlet) > 0.9,
		"river ribbon starts at/after the plunge pool shore, not inside it (pool_sdf %.2f)"
			% WorldLayout.pool_distance(outlet))
	_check(_xz_contains(river_box, tail), "river mesh covers the lake mouth")
	_check(river_box.size.z > 13.0, "river mesh spans the full reach (%.1fm)" % river_box.size.z)
	var pool_box := _world_aabb(feature.pool_mesh)
	_check(_xz_contains(pool_box, WorldLayout.POOL_CENTER), "pool disc covers POOL_CENTER")
	_check(pool_box.size.x > WorldLayout.POOL_RADII.x * 1.8 and pool_box.size.z > WorldLayout.POOL_RADII.y * 1.8,
		"pool disc is an ellipse of POOL_RADII (%.1f x %.1f)" % [pool_box.size.x, pool_box.size.z])
	# 所有潭面三角形须面向天空；外圈曾反向，背面剔除后露出绿色地面。
	var pool_arrays := feature.pool_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = pool_arrays[Mesh.ARRAY_VERTEX]
	var reversed_faces := 0
	for i in range(0, vertices.size(), 3):
		var winding := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		if winding.y > 0.00001:
			reversed_faces += 1
	_check(reversed_faces == 0, "entire pool surface faces upward, including outer ring (%d reversed)" % reversed_faces)
	var curtain_box := _world_aabb(feature.curtain_mesh)
	_check(curtain_box.size.y > 6.0, "waterfall curtain drops %.1fm" % curtain_box.size.y)
	_check(curtain_box.position.y + curtain_box.size.y > WorldLayout.WATERFALL_TOP_Y - 0.15,
		"curtain reaches the lip height")
	_check(_xz_contains(curtain_box, WorldLayout.WATERFALL_LIP), "curtain hangs under the lip")
	# v43 多股落水：至少 3 股，且每股票落水点都在潭内
	_check(feature.curtain_meshes.size() >= 3,
		"waterfall splits into multiple strands (%d)" % feature.curtain_meshes.size())
	var strands_in_pool := 0
	for i in WorldLayout.WATERFALL_STRANDS.size():
		if WorldLayout.pool_distance(WorldLayout.waterfall_strand_landing(i)) < 1.0:
			strands_in_pool += 1
	_check(strands_in_pool == WorldLayout.WATERFALL_STRANDS.size(),
		"every strand lands inside the plunge pool (%d/%d)" % [strands_in_pool, WorldLayout.WATERFALL_STRANDS.size()])
	# 材质：河道 / 水潭用独立 region 的 water_ground 材质，瀑布帘用 ws_phase=2 的立面材质
	var river_mat := feature.river_mesh.material_override as ShaderMaterial
	var pool_mat := feature.pool_mesh.material_override as ShaderMaterial
	var curtain_mat := feature.curtain_mesh.material_override as ShaderMaterial
	_check(river_mat != null and absf(float(river_mat.get_shader_parameter("ws_region_cut")) - 2.0) < 0.01,
		"river material is water_ground region 2")
	_check(pool_mat != null and absf(float(pool_mat.get_shader_parameter("ws_region_cut")) - 3.0) < 0.01,
		"pool material is water_ground region 3")
	_check(curtain_mat != null and float(curtain_mat.get_shader_parameter("ws_phase")) > 1.5,
		"waterfall curtain material uses ws_phase 2")
	var lake := _main.get_node_or_null("WorldRoot/Water") as MeshInstance3D
	_check(lake != null and lake.material_override is ShaderMaterial, "lake water node exists with a shader material")
	if lake != null and lake.material_override is ShaderMaterial:
		var lake_mat := lake.material_override as ShaderMaterial
		var island_arg = lake_mat.get_shader_parameter("lake_island_center")
		_check(island_arg is Vector2 and (island_arg as Vector2).distance_to(WorldLayout.LAKE_ISLAND_CENTER) < 0.01,
			"water shader island uniform follows WorldLayout")
		var sun_arg = lake_mat.get_shader_parameter("sun_dir")
		_check(sun_arg is Vector3, "water shader receives a live sun_dir uniform (glint / fresnel)")
		var strand_arg = lake_mat.get_shader_parameter("ws_strand_count")
		_check(strand_arg is int and int(strand_arg) == WorldLayout.WATERFALL_STRANDS.size(),
			"water shader receives all waterfall strands (%s)" % str(strand_arg))


# ---- 2c) v45 水体表现契约（防「白纱湖面 / 硬白圆饼 / 纯白纸片」回归）----

## 这组断言只锁「结构性事实」（调色来源 / 分层材质 / 粒子尺度与混合模式 / 网格有机度），
## 不锁具体美术数值，避免以后调色 / 调参就误报。视觉验收仍以 tools/water_shot 截图为准。
func _check_v45_polish(world: Node3D, feature: WaterFeature) -> void:
	var lake := world.get_node_or_null("Water") as MeshInstance3D
	var lake_mat: ShaderMaterial = null
	if lake != null:
		lake_mat = lake.material_override as ShaderMaterial
	var river_mat := feature.river_mesh.material_override as ShaderMaterial
	var pool_mat := feature.pool_mesh.material_override as ShaderMaterial
	# ① 调色收口：颜色只能来自 WaterPalette，避免又散落回实体脚本 / Main.tscn
	_check(_mat_color(lake_mat, "water_deep").is_equal_approx(WaterPalette.LAKE_DEEP),
		"lake deep color comes from WaterPalette")
	_check(_mat_color(river_mat, "water_shallow").is_equal_approx(WaterPalette.RIVER_SHALLOW),
		"river shallow color comes from WaterPalette")
	_check(_mat_color(pool_mat, "water_deep").is_equal_approx(WaterPalette.POOL_DEEP),
		"pool deep color comes from WaterPalette")
	# ② v45 新增的浅滩 / 白沫 / 岸树倒影 uniform 必须真的写到湖面材质
	for key in ["water_shelf", "water_foam", "water_reflect"]:
		_check(lake_mat != null and lake_mat.get_shader_parameter(key) is Color,
			"lake material carries v45 color uniform: %s" % key)
	# ③ 多层落水：后层 / 前层 / 唇口翻卷节点存在，且绘制顺序是「后层 → 主帘 → 前层」
	var back := _find_water_node("WaterfallFilmBack") as MeshInstance3D
	var front := _find_water_node("WaterfallFilmFront") as MeshInstance3D
	var crest := _find_water_node("WaterfallCrest") as MeshInstance3D
	_check(back != null and front != null and crest != null,
		"v45 waterfall lays out film-back / film-front / crest")
	if back != null and front != null:
		var back_mat := back.material_override as ShaderMaterial
		var front_mat := front.material_override as ShaderMaterial
		var main_mat := feature.curtain_mesh.material_override as ShaderMaterial
		_check(back_mat != null and front_mat != null and main_mat != null
			and back_mat.render_priority < main_mat.render_priority
			and main_mat.render_priority < front_mat.render_priority,
			"waterfall film layers draw back → main → front")
	# ④ 水雾：必须是「小尺度 + alpha 混合」——v45-base 的硬白圆饼 = 1.6~3.4m 加法 billboard
	var mist := _find_water_node("WaterfallMist") as GPUParticles3D
	_check(mist != null, "waterfall mist emitter exists")
	if mist != null:
		var ppm := mist.process_material as ParticleProcessMaterial
		_check(ppm != null and ppm.scale_max <= 2.0,
			"waterfall mist stays small (scale_max %.2f)" % (ppm.scale_max if ppm != null else -1.0))
		var quad := mist.draw_pass_1 as QuadMesh
		var mist_mat: StandardMaterial3D = null
		if quad != null:
			mist_mat = quad.material as StandardMaterial3D
		_check(mist_mat != null and mist_mat.blend_mode != BaseMaterial3D.BLEND_MODE_ADD,
			"waterfall mist uses alpha blending, not additive (no hard white discs)")
	# ⑤ 落水翻涌有 3D 白沫丘（不再只靠一张平面贴图）
	_check(_find_water_node("WaterfallFoamMound") != null, "3D foam mound added at the plunge point")
	# ⑥ 霜区浮冰 / 雪斑：v45 起是程序化不规则网格（原先 8 / 12 边形纯白圆盘）
	var themed := world.get_node_or_null("WorldScenery/ThemedRegions")
	var floes := 0
	var organic_floes := 0
	var snows := 0
	var organic_snows := 0
	if themed != null:
		for child in themed.get_children():
			var mi := child as MeshInstance3D
			if mi == null or not (mi.mesh is ArrayMesh):
				continue
			if String(mi.name).begins_with("Frost_IceFloe"):
				floes += 1
				if _mesh_vertex_count(mi.mesh as ArrayMesh) >= 48:
					organic_floes += 1
			elif String(mi.name).begins_with("Frost_SnowPatch"):
				snows += 1
				if _mesh_vertex_count(mi.mesh as ArrayMesh) >= 24:
					organic_snows += 1
	_check(floes >= 3 and organic_floes == floes,
		"frost ice floes are irregular meshes (%d/%d)" % [organic_floes, floes])
	_check(snows >= 5 and organic_snows == snows,
		"frost snow patches are irregular meshes (%d/%d)" % [organic_snows, snows])


func _mat_color(mat: ShaderMaterial, key: String) -> Color:
	if mat == null:
		return Color(0, 0, 0, 0)
	var value: Variant = mat.get_shader_parameter(key)
	if value is Color:
		return value
	return Color(0, 0, 0, 0)


func _find_water_node(node_name: String) -> Node:
	for n in get_tree().get_nodes_in_group("water_feature"):
		if String((n as Node).name) == node_name:
			return n
	return null


func _mesh_vertex_count(mesh: ArrayMesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return verts.size()


# ---- 2b) 湖岸自然度 + 湖心小岛（纯视觉，不改寻路 / 物理）----

func _check_lake_shape(grid: GridSystem, nav: NavSystem) -> void:
	# 岸线谐波：不能只是均匀椭圆——半径比例要在足够大的区间里变化
	var lo := INF
	var hi := -INF
	for i in 64:
		var s := WorldLayout.lake_shore_scale(TAU * float(i) / 64.0)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	_check(hi - lo > 0.16, "lake shoreline is irregular, not a uniform ellipse (scale %.2f..%.2f)" % [lo, hi])
	# 新城东沿与湖西岸仍保持净空
	var clearance := WorldLayout.LAKE_CENTER.x - WorldLayout.LAKE_RADII.x * hi - WorldLayout.CITY_HALF
	_check(clearance > 3.0, "lake west shore keeps %.1fm clear of the 52×52 city" % clearance)
	# 小岛：完全在湖里、且岛心所在格仍是永久阻挡（纯视觉，不改寻路）
	var island_lo := INF
	for i in 24:
		island_lo = minf(island_lo, 1.0 - WorldLayout.lake_distance(
			WorldLayout.island_shore_point(TAU * float(i) / 24.0)))
	_check(island_lo > 0.08,
		"island shore stays well inside the lake (closest %.2f from the lake shore)" % island_lo)
	var island_cell := grid.world_to_grid(Vector3(WorldLayout.LAKE_ISLAND_CENTER.x, 0.0,
		WorldLayout.LAKE_ISLAND_CENTER.y))
	_check(grid.terrain_cells.has(island_cell) and nav.path_grid.is_point_solid(island_cell),
		"island does not punch a hole in lake blocking / pathing")
	_check(WorldLayout.waterfall_uv(WorldLayout.WATERFALL_LIP).z < 0.5 and
		WorldLayout.lake_shore_point(PI).x > WorldLayout.CITY_HALF,
		"lake / waterfall geometry stays east of the city")


# ---- 3) 寻路登记：河道 / 水潭 / 崖体是永久阻挡，浅滩不是 ----

func _check_navigation(grid: GridSystem, nav: NavSystem, feature: WaterFeature) -> void:
	var river_cells := 0
	var river_blocked := 0
	for x in grid.grid_size.x:
		for z in grid.grid_size.y:
			var cell := Vector2i(x, z)
			var w := grid.grid_to_world(cell)
			var p := Vector2(w.x, w.z)
			var rv := WorldLayout.river_distance(p)
			if rv.x > rv.y:
				continue
			if WaterFeature.in_ford(p) or p.distance_to(WaterFeature.SHALLOW_CENTER) <= WaterFeature.SHALLOW_RADIUS:
				continue
			river_cells += 1
			if grid.terrain_cells.has(cell) and nav.path_grid.is_point_solid(cell):
				river_blocked += 1
	var ratio := float(river_blocked) / maxf(float(river_cells), 1.0)
	_check(river_cells > 5, "river covers a meaningful number of cells (%d)" % river_cells)
	_check(ratio > 0.9, "river cells are permanent terrain blockers (%.0f%%)" % (ratio * 100.0))
	_check(grid.terrain_cells.has(grid.world_to_grid(Vector3(WorldLayout.POOL_CENTER.x, 0, WorldLayout.POOL_CENTER.y))),
		"plunge pool cell is a permanent blocker (units never swim in it)")
	var ford_cell := grid.world_to_grid(Vector3(WaterFeature.FORD_CENTER.x, 0, WaterFeature.FORD_CENTER.y))
	_check(not grid.terrain_cells.has(ford_cell) and not nav.path_grid.is_point_solid(ford_cell),
		"ford cell stays walkable")
	var ford_axis := (WorldLayout.RIVER_PTS[1] - WorldLayout.RIVER_PTS[0]).normalized()
	var ford_normal := Vector2(-ford_axis.y, ford_axis.x)
	var open_lane := 0
	for k in range(-4, 5):
		var p := WaterFeature.FORD_CENTER + ford_normal * (float(k) * 2.0)
		var cell := grid.world_to_grid(Vector3(p.x, 0, p.y))
		if not nav.path_grid.is_point_solid(cell):
			open_lane += 1
	_check(open_lane >= 7, "ford keeps an open wading lane across the river (%d/9 cells)" % open_lane)
	# 河口浅滩把一部分湖格清成可涉水（LakeStuckTest 断言的 shallow_open 来源）
	var shallow_open := 0
	for x in grid.grid_size.x:
		for z in grid.grid_size.y:
			var cell := Vector2i(x, z)
			var w := grid.grid_to_world(cell)
			if WorldLayout.lake_distance(Vector2(w.x, w.z)) >= 1.0:
				continue
			if not grid.terrain_cells.has(cell):
				shallow_open += 1
	_check(shallow_open >= 5, "river-mouth shallow opens lake cells for wading (%d)" % shallow_open)
	# 崖体占地全部阻挡
	var cliff_blocked := 0
	var cliff_total := 0
	for step: Array in WaterFeature.CLIFF_STEPS:
		var cx: float = (step[0] + step[1]) * 0.5
		var cz: float = (step[2] + step[3]) * 0.5
		cliff_total += 1
		if grid.terrain_cells.has(grid.world_to_grid(Vector3(cx, 0, cz))):
			cliff_blocked += 1
	_check(cliff_blocked == cliff_total, "cliff footprint is blocked (%d/%d steps)" % [cliff_blocked, cliff_total])
	print("river blockers: %d/%d cells, ford lane open: %d/9, cleared scatter: %d"
		% [river_blocked, river_cells, open_lane, feature.cleared_scatter])
	if feature.scatter_readback:
		_check(feature.cleared_scatter > 0,
			"scatter instances standing in the new water are removed (%d)" % feature.cleared_scatter)
	else:
		print("SKIP: scattered vegetation cleanup needs a real renderer (headless MultiMesh readback unavailable)")


# ---- 4) 崖体物理碰撞 ----

func _check_cliff(feature: WaterFeature) -> void:
	var body := feature.cliff_body
	_check(body != null and body is StaticBody3D, "cliff StaticBody3D exists")
	if body == null:
		return
	_check(body.collision_layer == 1, "cliff body collides on layer 1 (world)")
	_check(get_tree().get_nodes_in_group("water_cliff").has(body), "cliff body is in group water_cliff")
	await get_tree().physics_frame
	var space := (get_viewport().world_3d).direct_space_state
	# 后山主体正上方竖直下射：命中 8.2m 台面
	var back := PhysicsRayQueryParameters3D.create(Vector3(58.0, 24.0, -80.5), Vector3(58.0, -2.0, -80.5), 1)
	var hit := space.intersect_ray(back)
	_check(not hit.is_empty(), "ray hits the north cliff rock body")
	if not hit.is_empty():
		_check(hit["collider"] == body, "cliff ray hits the registered cliff body")
		_check((hit["position"] as Vector3).y > WorldLayout.WATERFALL_TOP_Y - 1.0,
			"cliff top is near WATERFALL_TOP_Y (hit y=%.2f)" % (hit["position"] as Vector3).y)
	# 西翼岩肩（低矮、贴在落水帘西侧）挡住侧面绕行
	var low := PhysicsRayQueryParameters3D.create(Vector3(50.6, 5.0, -75.5), Vector3(50.6, -2.0, -75.5), 1)
	_check(not space.intersect_ray(low).is_empty(), "cliff wing blocks the west flank")
	# 唇口岩檐：从瀑顶上空下射应命中 8.2m 檐面（而不是穿到池子里）
	var lip := PhysicsRayQueryParameters3D.create(Vector3(58.0, 14.0, -72.9), Vector3(58.0, 0.5, -72.9), 1)
	var lip_hit := space.intersect_ray(lip)
	var lip_y := (lip_hit["position"] as Vector3).y if not lip_hit.is_empty() else -99.0
	_check(not lip_hit.is_empty() and lip_y > WorldLayout.WATERFALL_TOP_Y - 1.6,
		"cliff shelf carries the waterfall lip (hit y=%.2f)" % lip_y)


# ---- 5) 单位真的能从浅滩过河 ----

func _check_ford_crossing(world: Node3D, nav: NavSystem, _feature: WaterFeature) -> void:
	# v43：过河走廊横跨新河道（FORD_CENTER 两侧各 6.5m 的干地）
	var ford_axis := (WorldLayout.RIVER_PTS[1] - WorldLayout.RIVER_PTS[0]).normalized()
	var ford_normal := Vector2(-ford_axis.y, ford_axis.x)
	var west2 := WaterFeature.FORD_CENTER + ford_normal * 6.5
	var east2 := WaterFeature.FORD_CENTER - ford_normal * 6.5
	var west := Vector3(west2.x, 0.0, west2.y)
	var east := Vector3(east2.x, 0.0, east2.y)
	var path := nav.get_world_path(west, east)
	# 平滑后的路径可能只剩「目标点 + 精确落点」两个航点（起终点之间本来就一条直线可走），
	# 因此路径长度必须把「起点 → 首个航点」也算进去。
	var path_len := 0.0
	if not path.is_empty():
		path_len += path[0].distance_to(west)
	for i in range(1, path.size()):
		path_len += path[i].distance_to(path[i - 1])
	_check(path.size() >= 2 and path_len > 0.0 and path_len < 40.0,
		"navmesh returns a ford route across the river (%.1fm, %d pts)" % [path_len, path.size()])
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	_check(spawner != null, "pawn spawner available")
	if spawner == null:
		return
	var soldier: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), west)
	await get_tree().physics_frame
	if soldier == null:
		_check(false, "soldier spawned on the west bank")
		return
	soldier.set_destination(east)
	TimeManager.set_speed(3.0)
	var arrived := false
	var closest := soldier.global_position.distance_to(east)
	for i in 900:
		await get_tree().physics_frame
		if not is_instance_valid(soldier):
			break
		# 小兵白天会自主巡逻（SoldierIdleState 会改目标）：每 30 帧重申一次行军目标
		if i % 30 == 29:
			soldier.set_destination(east)
		closest = minf(closest, soldier.global_position.distance_to(east))
		if soldier.global_position.distance_to(east) < 3.0:
			arrived = true
			break
	TimeManager.set_speed(1.0)
	_check(arrived, "soldier wades across at the ford (closest %.1fm)" % closest)
	if is_instance_valid(soldier):
		soldier.queue_free()


# ---- 工具 ----

func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	return mi.global_transform * local


func _xz_contains(box: AABB, p: Vector2) -> bool:
	return p.x >= box.position.x - 0.5 and p.x <= box.position.x + box.size.x + 0.5 \
		and p.y >= box.position.z - 0.5 and p.y <= box.position.z + box.size.z + 0.5
