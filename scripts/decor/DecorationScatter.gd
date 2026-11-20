class_name DecorationScatter
extends Node3D

const NatureAssetsScript = preload("res://scripts/decor/NatureAssets.gd")
## ============================================================================
## 程序化装饰散布：树/石/水草用 Medieval-Hexagon nature 模型（MultiMesh），
## 草坪用分根弯叶实体网格（lawn.gdshader），区域高草仍用 grass.gdshader。固定 seed 可复现。
## 全部无 CollisionShape3D——纯视觉，不污染 A* 寻路（地形碰撞由 WorldScenery 单独负责）。
## 加载策略同 BuildingModelRig：load() 优先（编辑器导入的 PackedScene），
##   失败回退 GLTFDocument 运行时解析（.gltf + 外部 .bin + png 相对 URI 也能解析）。
## v40：世界扩到 256×256 米，另按 WorldRegions 的六个主题区域追加分区植被
##   （独立 MultiMesh + 每区专属材质），新素材缺失时自动回退现有模型。
## ============================================================================

@export_group("散布量")
@export var tree_count: int = 240
@export var rock_count: int = 130
@export var grass_count: int = 320000
@export var waterplant_count: int = 100
@export var flower_count: int = 3600

@export_group("区域")
@export var seed_value: int = 1337
@export var map_half: float = WorldLayout.MAP_HALF - 2.0
@export var city_half: float = WorldLayout.CITY_HALF

const NATURE_DIR := "res://assets/_PLACEHOLDER/nature/"

# 散布档位：决定 _valid 的约束
const PLACE_LAND := 0        # 树/石：避城内 / 湖 / 主干道 / 资源点
const PLACE_GRASS := 1       # 草：可进城边缘、近资源点，仅避湖与主城核心
const PLACE_WATER_EDGE := 2  # 水草：只在湖边环

var _lawn_rock_clearance: Dictionary = {}  # 8m 桶内的岩石椭圆净空，直接记录 CPU 变换
const LAWN_CLEARANCE_BUCKET := 8.0

var lawn_interaction: LawnInteraction
var _lawn_material: ShaderMaterial
var _lawn_mask_image: Image
var _lawn_mask_texture: ImageTexture
var _lawn_grid: GridSystem
var _lawn_mask_dirty := false
const LAWN_MASK_PIXELS_PER_CELL := 4

var _rng := RandomNumberGenerator.new()
var _resource_points: Array[Vector2] = []   # 资源点 XZ，散布时避开
var _prop_rects: Dictionary = {}            # 道具 XZ 包围盒空间桶：Vector2i → Array[Rect2]


func _ready() -> void:
	_rng.seed = seed_value
	_gather_resource_points()
	# 林冠在城外成簇分布，复用低模资产，远近尺寸有层次。
	for m in ["tree_single_A", "trees_A_medium", "trees_B_large"]:
		_scatter_model(m, _divide(tree_count, 3), PLACE_LAND, 2.7, 4.3, 0.0)
	for m in ["rock_single_A", "rock_single_B"]:
		_scatter_model(m, _divide(rock_count, 2), PLACE_LAND, 3.0, 7.0, 0.0)
	for m in ["waterplant_A", "waterlily_B"]:
		_scatter_model(m, _divide(waterplant_count, 2), PLACE_WATER_EDGE, 2.0, 4.5, 0.08)
	_scatter_grass()
	_scatter_flowers()
	_scatter_golden_grove()
	# v40 第六个主题区域的分区植被（放在最后：不改变上面既有散布的随机序列）。
	# 延后一帧：Main.tscn 里 WorldScenery 排在装饰之后，它的 _ready 才实例化
	# ThemedRegions 道具；延后一轮才能在散布时读到道具 AABB 做精确净空（树不穿建筑）。
	_scatter_regions.call_deferred()


# ---- 通用模型散布 ----

func _scatter_model(res_name: String, count: int, place: int, s_min: float, s_max: float, y_off: float) -> void:
	if count <= 0:
		return
	var mesh := _load_mesh(res_name)
	if mesh == null:
		push_warning("DecorationScatter: 模型缺失 %s" % res_name)
		return
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 25:
		tries += 1
		var pos := _sample_pos(place)
		if not pos.is_finite():
			continue
		var yaw := _rng.randf_range(0.0, TAU)
		var s := _rng.randf_range(s_min, s_max)
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos + Vector3(0, y_off, 0))
		transforms.append(t)
		if res_name.begins_with("rock_"):
			_register_lawn_rock(mesh, t)
	_build_multimesh("MM_" + res_name, mesh, transforms, place != PLACE_WATER_EDGE)


# ---- v46 短草坪：分层抖动采样 + 分根弯叶 + 不透明材质 ----

func _scatter_grass() -> void:
	if grass_count <= 0:
		return
	var mesh := _make_lawn_clump()
	_lawn_material = ShaderMaterial.new()
	_lawn_material.shader = preload("res://assets/shaders/lawn.gdshader")
	_lawn_material.set_shader_parameter("city_half", city_half)
	var ground := get_parent().get_parent().get_node_or_null("GroundPlane/MeshInstance3D") as MeshInstance3D
	if ground != null and ground.material_override is ShaderMaterial:
		var ground_mat := ground.material_override as ShaderMaterial
		_lawn_material.set_shader_parameter("ground_color_a", ground_mat.get_shader_parameter("albedo_grass_a"))
		_lawn_material.set_shader_parameter("ground_color_b", ground_mat.get_shader_parameter("albedo_grass_b"))
	mesh.surface_set_material(0, _lawn_material)
	lawn_interaction = LawnInteraction.new()
	lawn_interaction.name = "LawnInteraction"
	add_child(lawn_interaction)
	lawn_interaction.setup(_lawn_material)
	# 独立随机源：调草量不再打乱树木、花朵与主题区域的布局。
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4601
	var transforms: Array[Transform3D] = []
	var side := maxi(1, ceili(sqrt(float(grass_count))))
	var step := map_half * 2.0 / float(side)
	for z in side:
		for x in side:
			var point := Vector2(-map_half + (float(x) + rng.randf_range(0.12, 0.88)) * step,
				-map_half + (float(z) + rng.randf_range(0.12, 0.88)) * step)
			if not _lawn_allowed(point):
				continue
			var scale_h := rng.randf_range(0.82, 1.18)
			var scale_y := rng.randf_range(0.80, 1.22)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale_h, scale_y, scale_h))
			transforms.append(Transform3D(basis, Vector3(point.x, 0.005, point.y)))
	_build_multimesh("MM_grass", mesh, transforms, false)
	for child in get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with("MM_grass_"):
			child.visibility_range_end = 112.0
	_setup_lawn_mask.call_deferred()


func _lawn_allowed(point: Vector2) -> bool:
	var edge := maxf(absf(point.x), absf(point.y))
	# 城内不再挖掉整块草；城堡基座留出净空，玩家道路由动态遮罩负责。
	if edge < 5.8:
		return false
	if edge > city_half and WorldLayout.road_distance(point) < 2.65:
		return false
	if WorldLayout.lake_distance(point) < 1.16 or WorldLayout.water_distance(point) < 0.65:
		return false
	if WorldLayout.is_landmark(point, 1.0):
		return false
	# 保留专属区域地貌，冷区/麦田/沼泽等由原有区域草层接管。
	var keeper := 1.0
	match WorldRegions.biome_at(point):
		WorldRegions.KIND_MINE: keeper = 0.03
		WorldRegions.KIND_BATTLE: keeper = 0.08
		WorldRegions.KIND_WHEAT: keeper = 0.12
		WorldRegions.KIND_SWAMP: keeper = 0.20
		WorldRegions.KIND_FROST: keeper = 0.10
	if _pos_hash(point) > keeper:
		return false
	for resource in _resource_points:
		if point.distance_squared_to(resource) < 1.0:
			return false
	var key := Vector2i(floori(point.x / LAWN_CLEARANCE_BUCKET), floori(point.y / LAWN_CLEARANCE_BUCKET))
	for rect: Rect2 in _lawn_rock_clearance.get(key, []):
		var normalized := (point - rect.get_center()) / (rect.size * 0.5)
		if normalized.length_squared() < 1.0:
			return false
	return true


func _register_lawn_rock(mesh: Mesh, transform: Transform3D) -> void:
	var bounds := transform * mesh.get_aabb()
	var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.42)
	var lo := Vector2i((rect.position / LAWN_CLEARANCE_BUCKET).floor())
	var hi := Vector2i((rect.end / LAWN_CLEARANCE_BUCKET).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var key := Vector2i(x, y)
			if not _lawn_rock_clearance.has(key):
				_lawn_rock_clearance[key] = []
			_lawn_rock_clearance[key].append(rect)


func _make_lawn_clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 46046
	# 每簇 12 叶，每叶 5 三角；加宽叶腹与短圆冠，默认俯视下仍能读出单片叶形。
	for i in 12:
		var angle := float(i) * 2.399963
		var radius := sqrt((float(i) + 0.5) / 12.0) * 0.29
		var root := Vector3(cos(angle), 0.0, sin(angle)) * radius
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0, sin(yaw))
		var lean := Vector3(-sin(yaw), 0, cos(yaw)) * rng.randf_range(0.05, 0.13)
		var height := rng.randf_range(0.36, 0.56)
		var width := rng.randf_range(0.055, 0.080)
		var middle := root + Vector3.UP * height * 0.53 + lean * 0.22
		var shoulder := root + Vector3.UP * height * 0.88 + lean * 0.70
		var tip := root + Vector3.UP * height + lean
		var vertices: Array[Vector3] = [root - side * width * 0.55, root + side * width * 0.55,
			middle - side * width, middle + side * width,
			shoulder - side * width * 0.67, shoulder + side * width * 0.67, tip]
		var uv: Array[Vector2] = [Vector2(0.22, 0), Vector2(0.78, 0),
			Vector2(0, 0.53), Vector2(1, 0.53), Vector2(0.16, 0.88), Vector2(0.84, 0.88), Vector2(0.5, 1)]
		var tint := rng.randf()
		for index in [0, 2, 1, 1, 2, 3, 2, 4, 3, 3, 4, 5, 4, 6, 5]:
			st.set_normal(Vector3.UP)
			st.set_color(Color((float(i) + 0.5) / 12.0, tint, 0, 1))
			st.set_uv(uv[index])
			st.set_uv2(Vector2(root.x, root.z))
			st.add_vertex(vertices[index])
	st.index()
	return st.commit()


# 128×128 网格 → 512×512 单通道遮罩；只在建筑/道路变化时更新，不逐帧扫描实例。
func _setup_lawn_mask() -> void:
	_lawn_grid = get_tree().get_first_node_in_group("grid_system") as GridSystem
	if _lawn_grid == null:
		return
	_lawn_mask_image = Image.create(_lawn_grid.grid_size.x * LAWN_MASK_PIXELS_PER_CELL,
		_lawn_grid.grid_size.y * LAWN_MASK_PIXELS_PER_CELL, false, Image.FORMAT_L8)
	_lawn_mask_texture = ImageTexture.create_from_image(_lawn_mask_image)
	_lawn_material.set_shader_parameter("lawn_mask", _lawn_mask_texture)
	_lawn_material.set_shader_parameter("mask_origin", Vector2(-_lawn_grid.half_x(), -_lawn_grid.half_z()))
	_lawn_material.set_shader_parameter("mask_size", Vector2(_lawn_grid.half_x(), _lawn_grid.half_z()) * 2.0)
	_lawn_material.set_shader_parameter("mask_enabled", true)
	EventBus.building_placed.connect(_on_lawn_building_changed)
	EventBus.building_removed.connect(_on_lawn_building_changed)
	EventBus.road_changed.connect(_on_lawn_road_changed)
	_refresh_lawn_mask()


func _on_lawn_building_changed(building: Node, _cell: Vector2i) -> void:
	if is_instance_valid(building) and not building.tree_exiting.is_connected(_queue_lawn_mask):
		building.tree_exiting.connect(_queue_lawn_mask, CONNECT_ONE_SHOT)
	_queue_lawn_mask()


func _on_lawn_road_changed(_grid: Node, _cell: Vector2i, _present: bool) -> void:
	_queue_lawn_mask()


func _queue_lawn_mask() -> void:
	if _lawn_mask_dirty:
		return
	_lawn_mask_dirty = true
	_refresh_lawn_mask.call_deferred()


func _refresh_lawn_mask() -> void:
	_lawn_mask_dirty = false
	if _lawn_mask_image == null or not is_instance_valid(_lawn_grid):
		return
	_lawn_mask_image.fill(Color.BLACK)
	var pixels_per_m := float(LAWN_MASK_PIXELS_PER_CELL) / _lawn_grid.cell_size
	var origin := Vector2(-_lawn_grid.half_x(), -_lawn_grid.half_z())
	var image_rect := Rect2i(Vector2i.ZERO, _lawn_mask_image.get_size())
	var surfaces := get_tree().get_nodes_in_group("building") + get_tree().get_nodes_in_group("road")
	for node in surfaces:
		if not node is Building or node.is_queued_for_deletion():
			continue
		var building := node as Building
		if not _lawn_grid.is_inside(building.cell):
			continue
		var corner := _lawn_grid.grid_to_world(building.cell) - Vector3.ONE * _lawn_grid.cell_size * 0.5
		var lo := Vector2(corner.x, corner.z) - Vector2.ONE * 0.30
		var hi := Vector2(corner.x, corner.z) + Vector2(building.footprint) * _lawn_grid.cell_size + Vector2.ONE * 0.30
		var start := Vector2i(((lo - origin) * pixels_per_m).floor())
		var end := Vector2i(((hi - origin) * pixels_per_m).ceil())
		_lawn_mask_image.fill_rect(Rect2i(start, end - start).intersection(image_rect), Color.WHITE)
	_lawn_mask_texture.update(_lawn_mask_image)


func _make_grass_clump(blades: int = 5, height: float = 0.48, half_width: float = 0.09) -> Mesh:
	# 多叉三角草簇：N 片尖三角绕 Y 均匀分布，每片高度/宽度带确定性抖动，
	# 比 3 叉更密实、更像塞尔达式的团状草丛；UV.y 底 0 → 尖 1 供 shader 摆动与渐变。
	# v40：参数化——麦浪用更高更细的变体、芦苇用 3 叉细高变体，共用同一份程序化几何。
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var half_w := half_width
	var h := height
	for i in blades:
		var ang := float(i) * TAU / float(blades)
		# 按叶片序号做确定性抖动，避免多片草机械对称
		var jh := 0.85 + 0.25 * fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var blade_h := h * jh
		var blade_w := half_w * (0.8 + 0.4 * fposmod(sin(float(i) * 78.233) * 43758.5453, 1.0))
		var side_v := Vector3(cos(ang), 0.0, -sin(ang))   # 各三角的横向轴
		var bl := -side_v * blade_w
		var br := side_v * blade_w
		var top := Vector3(0.0, blade_h, 0.0)
		verts.append(bl)
		uvs.append(Vector2(0.0, 0.0))
		verts.append(br)
		uvs.append(Vector2(1.0, 0.0))
		verts.append(top)
		uvs.append(Vector2(0.5, 1.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---- 花甸与暖色阔叶林 ----

func _scatter_flowers() -> void:
	for color in [Color("f3db85"), Color("eee8cf"), Color("bba2d2")]:
		var mesh := SphereMesh.new()
		mesh.radius = 0.11
		mesh.height = 0.12
		mesh.radial_segments = 5
		mesh.rings = 2
		# 花朵也是「挡视线的小装饰」→ 换成语义等价的消散材质（v13）
		mesh.material = NatureAssetsScript.dissolve_material(color, 1.0, 1.4)
		var transforms: Array[Transform3D] = []
		for _i in flower_count:
			if transforms.size() >= flower_count / 3:
				break
			var pos := _sample_pos(PLACE_GRASS)
			if not pos.is_finite():
				continue
			# 南部花甸及靠城的低草带，避开道路与资源采集位。
			if pos.z < 16.0 and _rng.randf() > 0.12:
				continue
			pos.y = _rng.randf_range(0.23, 0.52)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _rng.randf_range(0.8, 1.5)), pos))
		_build_multimesh("Flowers_" + color.to_html(), mesh, transforms, false)


func _scatter_golden_grove() -> void:
	var trunk := CylinderMesh.new()
	trunk.bottom_radius = 0.16
	trunk.top_radius = 0.10
	trunk.height = 2.0
	trunk.radial_segments = 6
	# 金叶林同样是可走近的装饰：树干/树冠都换成消散材质（v13）
	trunk.material = NatureAssetsScript.dissolve_material(Color("74614c"), 0.95, 1.6)
	for color in [Color("b9bd67"), Color("d1b15f"), Color("81a668")]:
		var crown := SphereMesh.new()
		crown.radius = 1.3
		crown.height = 3.2
		crown.radial_segments = 7
		crown.rings = 3
		crown.material = NatureAssetsScript.dissolve_material(color, 0.95, 0.9)
		var trunks: Array[Transform3D] = []
		var crowns: Array[Transform3D] = []
		for _i in 180:
			if trunks.size() >= 38:
				break
			var point := Vector3(_rng.randf_range(-58, -23), 0, _rng.randf_range(22, 58))
			if not _valid(point, PLACE_LAND):
				continue
			var s := _rng.randf_range(0.85, 1.55)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
			trunks.append(Transform3D(basis, point + Vector3(0, s, 0)))
			crowns.append(Transform3D(basis, point + Vector3(0, 3.1 * s, 0)))
		_build_multimesh("GroveTrunks_" + color.to_html(), trunk, trunks, true)
		_build_multimesh("GroveCanopy_" + color.to_html(), crown, crowns, true)


# ---- 散布工具 ----

func _build_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D], cast_shadow: bool) -> void:
	# 按 16m 分块，离开镜头的草地/树林可独立剔除，扩图后不必整图一起绘制。
	var chunks: Dictionary = {}
	for transform in transforms:
		var key := Vector2i(floori(transform.origin.x / 16.0), floori(transform.origin.z / 16.0))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(transform)
	for key: Vector2i in chunks:
		var instances: Array = chunks[key]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [node_name, key.x, key.y]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = instances.size()
		for i in instances.size():
			mm.set_instance_transform(i, instances[i])
		mmi.multimesh = mm
		mmi.extra_cull_margin = 1.0
		add_child(mmi)


## v47 画质分级：按档位限制草 / 装饰 MultiMesh 的可视距离。
## 只「收」不「放」——已有的 112m 草、158m 外环林带不会被高档无意拉远；
## 低档把远距离层提前剔除，省的是顶点与阴影光栅化带宽。
func apply_render_quality(grass_range: float, decor_range: float) -> void:
	apply_visibility_ranges(self, grass_range, decor_range)


## 静态入口：便于回归测试与外部复用（不依赖具体场景树结构）。
static func apply_visibility_ranges(root: Node, grass_range: float, decor_range: float) -> void:
	for child in root.get_children():
		if not (child is MultiMeshInstance3D):
			continue
		var mmi := child as MultiMeshInstance3D
		var is_grass := String(mmi.name).begins_with("MM_grass_")
		var target := grass_range if is_grass else decor_range
		if target <= 0.0:
			continue
		if mmi.visibility_range_end <= 0.0 or mmi.visibility_range_end > target:
			mmi.visibility_range_end = target
			mmi.visibility_range_end_margin = minf(12.0, target * 0.12)
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _sample_pos(place: int) -> Vector3:
	for _i in 30:
		var x := _rng.randf_range(-map_half, map_half)
		var z := _rng.randf_range(-map_half, map_half)
		var pos := Vector3(x, 0.0, z)
		if _valid(pos, place):
			return pos
	return Vector3(INF, INF, INF)   # 多次拒绝则放弃本次


func _valid(pos: Vector3, place: int) -> bool:
	var point := Vector2(pos.x, pos.z)
	var cheby := maxf(absf(pos.x), absf(pos.z))
	var lake := WorldLayout.lake_distance(point)
	if place == PLACE_WATER_EDGE:
		return lake > 0.84 and lake < 0.98
	if lake < 1.16 or WorldLayout.road_distance(point) < 2.7:
		return false
	# 河道 / 水潭同样不长树石草（v12 水系）：water_distance < 0 即在水里，
	# 留 0.6m 岸边余量避免树冠压到水面。湖面已由上一行覆盖，此处补河与潭。
	if WorldLayout.water_distance(point) < 0.6:
		return false
	if WorldLayout.is_landmark(point, 1.0):
		return false
	var fringe := 0.7 + 1.5 * (0.5 + 0.5 * sin(pos.x * 0.42) * cos(pos.z * 0.39))
	if cheby < city_half + (fringe if place == PLACE_GRASS else 3.0 + fringe):
		return false
	for p in _resource_points:
		if point.distance_to(p) < (1.3 if place == PLACE_GRASS else 3.2):
			return false
	if place == PLACE_GRASS:
		# v40 分区地表：矿坑 / 战场 / 麦海 / 沼地的野草显著变稀（区域专属植被另行散布）。
		# 用位置哈希做确定性稀疏（不消耗 _rng → 不改变其它散布的随机序列）。
		var keeper := 1.0
		match WorldRegions.biome_at(point):
			WorldRegions.KIND_MINE: keeper = 0.10
			WorldRegions.KIND_BATTLE: keeper = 0.25
			WorldRegions.KIND_WHEAT: keeper = 0.30
			WorldRegions.KIND_SWAMP: keeper = 0.45
			WorldRegions.KIND_FROST: keeper = 0.65
			WorldRegions.KIND_FOREST: keeper = 0.90
		if keeper < 1.0 and _pos_hash(point) > keeper:
			return false
	if place == PLACE_LAND:
		# 东南草甸开阔，北/西侧形成较密的林带；波形取样产生林间空隙。
		var density := 0.5 + sin(pos.x * 0.14) * cos(pos.z * 0.12) * 0.3
		if pos.x > 12.0 and pos.z > 12.0:
			density *= 0.25
		return _rng.randf() < density
	return true


func _divide(total: int, parts: int) -> int:
	return maxi(1, int(round(float(total) / float(parts))))


func _gather_resource_points() -> void:
	# 读取已就位的资源点位置（ResourceNode 在 _ready 里 add_to_group；本节点须在树顺序上
	# 晚于 ResourceNodes 容器——Main.tscn 已保证 Decorations 排在 ResourceNodes 之后）
	for n in get_tree().get_nodes_in_group("resource_node"):
		var n3 := n as Node3D
		if n3 != null:
			_resource_points.append(Vector2(n3.global_position.x, n3.global_position.z))


# ============================================================================
# v40 分区散布：六个主题区域（WorldRegions 是圆心/半径/配色/地标的唯一真相）
# ----------------------------------------------------------------------------
# 每区独立 MultiMesh + 专属材质（不共享网格材质，避免串色）；全部走本节点固定 seed 的
# _rng → 可复现。避让统一在 _valid_region：水域 / 道路 / 城内 / 资源点 / 地标核心区
# （WorldLayout.is_landmark 已含 WorldRegions 的地标 8m 避让）。
# 新素材（tree_single_B / trees_A_large / trees_*_cut / rock_single_C~E …）由
# regions-builder 陆续下载，这里一律先判断存在性，缺失就回退到现有模型。
# ============================================================================

## 各区域通用素材候选（preferred 缺失时回退 fallbacks）。
const TREE_CANDIDATES := ["tree_single_B", "trees_A_large", "trees_A_small", "trees_B_medium", "trees_B_small"]
const TREE_FALLBACKS := ["tree_single_A", "trees_A_medium", "trees_B_large"]
const CUT_TREE_CANDIDATES := ["tree_cut", "trees_cut", "trees_A_cut", "trees_B_cut", "tree_single_B_cut"]
## 树桩点缀专用：优先用细小的 cut 模型（lead 反馈：大 cut 模型像「棕色大圆锥 + 粉红底环」）
const STUMP_CANDIDATES := ["tree_single_A_cut", "tree_single_B_cut"]
const ROCK_CANDIDATES := ["rock_single_C", "rock_single_D", "rock_single_E"]
const ROCK_FALLBACKS := ["rock_single_A", "rock_single_B"]

## 道具 AABB 空间桶边长（米）：ThemedRegions 的 186 个道具按 8m 桶登记，
## 散布时只查落点所在桶 → 精确避让道具又不拖慢 1.6 万次取样。
const PROP_BUCKET: float = 8.0


func _scatter_regions() -> void:
	# 先登记道具包围盒（ThemedRegions 若尚未就绪则退化为 13m 地标净空）
	_gather_themed_props()
	_scatter_forest_region(WorldRegions.find(&"mistwood"))
	_scatter_frost_region(WorldRegions.find(&"frostfall"))
	_scatter_wheat_region(WorldRegions.find(&"windwheat"))
	_scatter_battle_region(WorldRegions.find(&"embersworn"))
	_scatter_mine_region(WorldRegions.find(&"starfall"))
	_scatter_swamp_region(WorldRegions.find(&"salthollow"))
	_scatter_outer_ring()


# ---- v40.1 外围环带植被（130~158m，纯视觉、无玩法、不加草）----
# 可玩边界 128m 与远山环带 164~182m 之间原本是一条秃边；这里补一圈深色树 + 岩石，
# 让边缘/高空视角看不到「地图外空带」。命名按约定：MM_outer_trees / MM_outer_rocks。
const OUTER_INNER: float = 130.0
const OUTER_OUTER: float = 158.0
const OUTER_TREE_COUNT: int = 260
const OUTER_ROCK_COUNT: int = 120


func _scatter_outer_ring() -> void:
	# v40.2：拆 3 个模型变体（v1/v2/v3），避免环带一圈同一棵树重复
	_scatter_outer_variants("MM_outer_trees",
		_resolve_models(["trees_A_large", "trees_B_large", "tree_single_B"],
			["tree_single_A", "trees_A_medium"]),
		OUTER_TREE_COUNT, Color(0.12, 0.20, 0.13), Color(0.26, 0.40, 0.27), 3.0, 6.0, true)
	_scatter_outer_variants("MM_outer_rocks",
		_resolve_models(["rock_single_C", "rock_single_E", "rock_single_D"],
			["rock_single_A", "rock_single_B"]),
		OUTER_ROCK_COUNT, Color(0.36, 0.36, 0.34), Color(0.56, 0.55, 0.51), 2.0, 5.0, false)


## 环带多变体散布：v1 用基础名 MM_outer_trees/MM_outer_rocks，后续加 _v2/_v3 后缀。
func _scatter_outer_variants(base_name: String, models: Array, count: int,
		deep: Color, light: Color, s_min: float, s_max: float, cast_shadow: bool) -> void:
	if models.is_empty() or count <= 0:
		return
	var variants := mini(models.size(), 3)
	var per := maxi(1, int(round(float(count) / float(variants))))
	for v in variants:
		var target := count - per * (variants - 1) if v == 0 else per
		if target <= 0:
			continue
		var mesh := _load_mesh_tinted(models[v], deep, light)
		if mesh == null:
			push_warning("DecorationScatter: 外围环带模型缺失 %s" % models[v])
			continue
		var node_name := base_name if v == 0 else "%s_v%d" % [base_name, v + 1]
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < target and tries < target * 20:
			tries += 1
			var pos := _outer_pos()
			if not pos.is_finite():
				continue
			var yaw := _rng.randf_range(0.0, TAU)
			var s := _rng.randf_range(s_min, s_max)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
		_build_multimesh(node_name, mesh, transforms, cast_shadow)


## 环带采样：切比雪夫距离 130~158m，避开道路 / 水面（外围本来也没有，兜底防御）。
func _outer_pos() -> Vector3:
	for _i in 30:
		var x := _rng.randf_range(-OUTER_OUTER, OUTER_OUTER)
		var z := _rng.randf_range(-OUTER_OUTER, OUTER_OUTER)
		var cheby := maxf(absf(x), absf(z))
		if cheby < OUTER_INNER:
			continue
		var point := Vector2(x, z)
		if WorldLayout.is_water(point, 1.0):
			continue
		if WorldLayout.road_distance(point) < 4.0:
			continue
		return Vector3(x, 0.0, z)
	return Vector3(INF, INF, INF)


# ---- 雾隐密林：高密度古树 + 蘑菇群 / 蕨类 ----

func _scatter_forest_region(region: Dictionary) -> void:
	_scatter_region_models(region, 150, TREE_CANDIDATES, TREE_FALLBACKS,
		Color(0.10, 0.22, 0.12), Color(0.28, 0.44, 0.20), 3.0, 5.2, 0.0, true, 0.0, 0.96)
	_scatter_mushrooms(region, 150)
	_scatter_ferns(region, 300)
	# v40.1 区域专属草色层：解决「主题色被绿草冲淡」
	_scatter_region_grass(region, 1300, Color("2c4a2a"), Color("5f8a4a"))


# ---- 霜语瀑布：冷色针叶林 + 冰晶簇 + 雪斑 ----

func _scatter_frost_region(region: Dictionary) -> void:
	_scatter_region_models(region, 60, TREE_CANDIDATES, TREE_FALLBACKS,
		Color(0.22, 0.36, 0.42), Color(0.52, 0.68, 0.74), 2.6, 4.2, 0.0, true, 0.0, 0.98)
	_scatter_ice_crystals(region, 140)
	_scatter_ground_patches(region, 80, Color("dbe6e8"), 0.5, 1.2, "snow", 0.06)
	_scatter_region_grass(region, 2200, Color("5f8f8a"), Color("bfe3e3"))


# ---- 风吟麦海：金色麦浪（程序化高草簇，成片分布）+ 少量草垛 ----

func _scatter_wheat_region(region: Dictionary) -> void:
	if region.is_empty():
		return
	var mesh := _make_grass_clump(6, 1.05, 0.10)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/grass.gdshader")
	# 草 shader 的颜色是 source_color：代码里的 Color 会自动转线性，与地面染色同一空间。
	mat.set_shader_parameter("color_bottom", Color("7a5f24"))
	mat.set_shader_parameter("color_top", Color("f0cf63"))
	mat.set_shader_parameter("wind_scale", 0.42)
	mat.set_shader_parameter("deg_sway_pitch", 22.0)
	mat.set_shader_parameter("dissolve_scale", 3.0)
	mat.set_shader_parameter("dissolve_tint", Color("f0dfa0"))
	mesh.surface_set_material(0, mat)
	var transforms: Array[Transform3D] = []
	# v40.1：总实例预算收紧，麦浪 6000 → 5000（仍在 4000~6000 区间），单簇加宽加高补偿密度
	var target := 5000
	var tries := 0
	while transforms.size() < target and tries < target * 8:
		tries += 1
		var pos := _region_pos(region, 0.0, 0.98)
		if not pos.is_finite():
			continue
		# 成片麦浪：低频噪声决定这一小片有没有麦子，空出来的窄带就是田垄。
		var patch := 0.5 + 0.5 * sin(pos.x * 0.31 + 1.7) * cos(pos.z * 0.27 - 0.6)
		if _rng.randf() > 0.18 + 0.82 * patch:
			continue
		var yaw := _rng.randf() * TAU
		var s := _rng.randf_range(0.85, 1.35)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
	_build_multimesh("MM_%s_wheat" % String(region["id"]), mesh, transforms, false)
	_scatter_hay_bales(region, 26)


func _scatter_hay_bales(region: Dictionary, count: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.62
	mesh.height = 0.95
	mesh.radial_segments = 7
	mesh.rings = 1
	mesh.material = NatureAssetsScript.dissolve_material(Color("c9a855"), 0.96, 1.1)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 30:
		tries += 1
		var pos := _region_pos(region, 0.15, 0.95)
		if not pos.is_finite():
			continue
		var s := _rng.randf_range(0.85, 1.25)
		# 圆柱默认立着：绕 X 转 90° 放倒成草垛，再按随机朝向摆放
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * s)
		transforms.append(Transform3D(basis, pos + Vector3(0.0, 0.6 * s, 0.0)))
	_build_multimesh("MM_%s_hay" % String(region["id"]), mesh, transforms, true)


# ---- 烬誓战场：枯树 / 焦土暗斑 / 红色余烬花 ----

func _scatter_battle_region(region: Dictionary) -> void:
	# v40.2：*_cut 是扁平树桩盘、放大后的站姿树又像「棕色大圆锥」——枯树改为
	# SurfaceTool 程序化低模枯树（主干 + 3~4 斜枝，约 56 tri，焦黑灰褐）。
	_scatter_deadtrees(region, 34, Color("3a332d"), 0.9, 1.4)
	_scatter_stumps(region, 8, Color(0.20, 0.18, 0.15), Color(0.33, 0.30, 0.26))
	# 焦土斑先铺，余烬花再依着斑块位置成簇生长（不再满地随机撒）
	var scorch := _scatter_ground_patches(region, 60, Color("3a332c"), 0.8, 1.8, "scorch", 0.05)
	_scatter_embers(region, 45, scorch)
	_scatter_region_grass(region, 2200, Color("5a4a2a"), Color("b09a55"))


# ---- v40.2 程序化枯树（主干 + 3~4 斜枝，约 56 tri）----

## 生成一份低模枯树网格：主干 2 段 + 3~4 根斜枝 + 小枝，用 SurfaceTool 合并圆柱段。
## variant（0/1/2）决定枝干布局；三个变体在所有区域复用 → MultiMesh 只需 3 份网格。
func _make_deadtree_mesh(variant: int, color: Color) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021700 + variant * 7919
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_h := rng.randf_range(2.4, 3.4)
	var base_r := rng.randf_range(0.20, 0.28)
	var lean := Vector3(rng.randf_range(-0.30, 0.30), 0.0, rng.randf_range(-0.30, 0.30))
	var p0 := Vector3.ZERO
	var p1 := Vector3(0.0, trunk_h * 0.55, 0.0) + lean * 0.35
	var p2 := Vector3(0.0, trunk_h, 0.0) + lean
	# 主干：两段渐细（下段封底，避免贴地看到空心）
	_add_cylinder_between(st, p0, p1, base_r, base_r * 0.72, 5, true)
	_add_cylinder_between(st, p1, p2, base_r * 0.72, base_r * 0.38, 5, false)
	# 斜枝：从主干上半段向外上方伸出，长度随高度递减
	var branches := 3 + (variant % 2)
	for i in branches:
		var t := 0.35 + 0.5 * float(i) / float(maxi(branches - 1, 1))
		var origin := p1.lerp(p2, t)
		var yaw := rng.randf() * TAU
		var pitch := rng.randf_range(0.30, 0.70)
		var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)).normalized()
		var seg_len := rng.randf_range(0.95, 1.55) * (1.0 - 0.10 * float(i))
		var tip := origin + dir * seg_len
		var r := base_r * 0.45
		_add_cylinder_between(st, origin, tip, r, r * 0.22, 3, false)
		# 隔一根主枝补小枝，把轮廓打碎（仍保持低模）
		if i % 2 == 0:
			var twig := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.1, 0.5), rng.randf_range(-0.6, 0.6))).normalized()
			var twig_from := origin.lerp(tip, 0.72)
			_add_cylinder_between(st, twig_from, twig_from + twig * seg_len * 0.45, r * 0.55, 0.01, 3, false)
	st.set_material(NatureAssetsScript.dissolve_material(color, 0.95, 1.1))
	return st.commit()


## 在两点之间追加一段低模圆台（sides 边；cap_start 控制起点封口）。
func _add_cylinder_between(st: SurfaceTool, from: Vector3, to: Vector3,
		r0: float, r1: float, sides: int, cap_start: bool) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = r0
	cyl.top_radius = r1
	cyl.height = length
	cyl.radial_segments = sides
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = cap_start
	st.append_from(cyl, 0, Transform3D(_basis_y_to(axis / length), (from + to) * 0.5))


## 构造把本地 +Y 旋转到 dir 的正交基（圆柱默认沿 Y 轴，用它斜插枝干）。
func _basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT
	if absf(y.dot(ref)) > 0.9:
		ref = Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## 区域枯树散布：3 个变体平分数量，命名 MM_<region>_deadtree_v1..v3，仍 16m 分块。
func _scatter_deadtrees(region: Dictionary, count: int, color: Color,
		s_min: float, s_max: float) -> void:
	if region.is_empty() or count <= 0:
		return
	var variants := 3
	var per := maxi(1, int(round(float(count) / float(variants))))
	for v in variants:
		var target := count - per * (variants - 1) if v == 0 else per
		if target <= 0:
			continue
		var mesh := _make_deadtree_mesh(v, color)
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < target and tries < target * 25:
			tries += 1
			# 枝条外伸约 1.5m：道具净空给到 2.6m，避免 ScenePolishTest 判定压道具
			var pos := _region_pos(region, 0.02, 0.98, 3.2, 2.6)
			if not pos.is_finite():
				continue
			var yaw := _rng.randf_range(0.0, TAU)
			var s := _rng.randf_range(s_min, s_max)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
		_build_multimesh("MM_%s_deadtree_v%d" % [String(region["id"]), v + 1], mesh, transforms, true)


## 少量 *_cut 树桩点缀（v40.1）：只铺低矮小尺寸，避免变成「满地棕色圆饼」。
func _scatter_stumps(region: Dictionary, count: int, deep: Color, light: Color) -> void:
	if region.is_empty() or count <= 0:
		return
	var models := _resolve_models(STUMP_CANDIDATES, CUT_TREE_CANDIDATES)
	if models.is_empty():
		return
	var per := maxi(1, int(round(float(count) / float(models.size()))))
	for m in models:
		var mesh := _load_stump_mesh(m, deep, light)
		if mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < per and tries < per * 25:
			tries += 1
			var pos := _region_pos(region, 0.05, 0.98, 3.2, 1.2)
			if not pos.is_finite():
				continue
			var yaw := _rng.randf_range(0.0, TAU)
			# 缩小：cut 模型在 >2 倍时像「棕色大圆锥」，只保留低矮树桩
			var s := _rng.randf_range(1.2, 2.0)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
		_build_multimesh("MM_%s_stump_%s" % [String(region["id"]), m], mesh, transforms, true)


func _scatter_embers(region: Dictionary, count: int, scorch: Array[Vector3]) -> void:
	if region.is_empty():
		return
	# v40.1：130 → 45 个，半径缩到 0.08（实例缩放后约 0.06~0.12m），
	# 只在焦土斑附近成簇冒头（不再满地棕色小方块），颜色提亮成橙红自发光。
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.10
	mesh.radial_segments = 5
	mesh.rings = 2
	mesh.material = _glow_material(Color("ff9a5a"), Color("ff5a1e"), 3.0, 0.45)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 40:
		tries += 1
		var base: Vector3
		if not scorch.is_empty():
			# 依着一块焦土，落在斑块边缘 0.25~1.15m 内
			var anchor: Vector3 = scorch[_rng.randi_range(0, scorch.size() - 1)]
			var ang := _rng.randf() * TAU
			base = anchor + Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(0.25, 1.15)
		else:
			base = _region_pos(region, 0.1, 0.98)
		if not base.is_finite():
			continue
		# 远离小径（3m）与水面；道具净空 0.8m
		if not _valid_region(base, 3.0, 0.8):
			continue
		base.y = _rng.randf_range(0.10, 0.24)
		var s := _rng.randf_range(0.75, 1.5)
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), base))
	_build_multimesh("MM_%s_ember" % String(region["id"]), mesh, transforms, false)


# ---- 星落矿坑：裸岩 + 紫色发光矿晶（草量在 _valid 里已大幅压低）----

func _scatter_mine_region(region: Dictionary) -> void:
	_scatter_region_models(region, 120, ROCK_CANDIDATES, ROCK_FALLBACKS,
		Color(0.34, 0.31, 0.36), Color(0.52, 0.48, 0.56), 2.6, 5.2, 0.0, true)
	_scatter_ore_crystals(region, 140)
	_scatter_region_grass(region, 1100, Color("4a4a42"), Color("8a8a78"))


func _scatter_ore_crystals(region: Dictionary, count: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.20
	mesh.height = 0.85
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.material = _glow_material(Color("b98cff"), Color("7a3cff"), 1.4, 0.35)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 30:
		tries += 1
		var pos := _region_pos(region, 0.1, 0.98)
		if not pos.is_finite():
			continue
		# 每株矿晶随机倾斜，簇内高低错落
		var tilt := Basis(Vector3.RIGHT, _rng.randf_range(-0.35, 0.35)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.35, 0.35))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * tilt
		var s := _rng.randf_range(0.55, 1.35)
		transforms.append(Transform3D(basis.scaled(Vector3.ONE * s), pos + Vector3(0.0, 0.36 * s, 0.0)))
	_build_multimesh("MM_%s_ore_crystal" % String(region["id"]), mesh, transforms, false)


# ---- 盐风沼地：枯树 + 芦苇 + 盐壳白斑 ----

func _scatter_swamp_region(region: Dictionary) -> void:
	# v40.2：枯树改程序化低模（灰褐盐枯木），少量树桩点缀
	_scatter_deadtrees(region, 24, Color("4e463a"), 0.85, 1.3)
	_scatter_stumps(region, 8, Color(0.26, 0.24, 0.20), Color(0.40, 0.37, 0.31))
	_scatter_reeds(region, 450)
	_scatter_ground_patches(region, 80, Color("c6c8b4"), 0.7, 1.5, "salt", 0.045)
	_scatter_region_grass(region, 2200, Color("46503c"), Color("8a9a6a"))


func _scatter_reeds(region: Dictionary, count: int) -> void:
	if region.is_empty():
		return
	# v40.1：1400 → 450 个；几何改成 3 片细长薄片（宽 ≤0.06m，缩放后高 0.8~1.6m），
	# 颜色改灰绿 / 枯黄，避免出现「遍地棕色小盒子」。
	var mesh := _make_grass_clump(3, 1.2, 0.03)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/grass.gdshader")
	mat.set_shader_parameter("color_bottom", Color("55604a"))
	mat.set_shader_parameter("color_top", Color("a8a882"))
	mat.set_shader_parameter("deg_sway_pitch", 24.0)
	mat.set_shader_parameter("wind_scale", 0.52)
	mat.set_shader_parameter("dissolve_scale", 3.2)
	mesh.surface_set_material(0, mat)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 14:
		tries += 1
		var pos := _region_pos(region, 0.05, 0.98, 3.0, 0.8)
		if not pos.is_finite():
			continue
		# 芦苇成簇：低频噪声决定密度，避免整片均匀
		var patch := 0.5 + 0.5 * sin(pos.x * 0.37 - 0.8) * cos(pos.z * 0.33 + 1.1)
		if _rng.randf() > 0.2 + 0.8 * patch:
			continue
		var yaw := _rng.randf() * TAU
		var s := _rng.randf_range(0.68, 1.32)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
	_build_multimesh("MM_%s_reed" % String(region["id"]), mesh, transforms, false)


# ---- 区域专属草色层（v40.1：把主题色铺进草丛，解决「区域染色被绿草冲淡」）----

## 用 grass.gdshader 的 color_bottom/color_top 给区域铺一层专属颜色的草簇。
## 与基础草共用同一套风动逻辑，但颜色随区域（霜蓝 / 焦黄 / 矿灰 / 沼绿 / 林深绿）。
func _scatter_region_grass(region: Dictionary, count: int, bottom: Color, top: Color) -> void:
	if region.is_empty() or count <= 0:
		return
	var mesh := _make_grass_clump(5, 0.5, 0.075)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/grass.gdshader")
	# 草 shader 的颜色是 source_color：代码里的 Color 会自动转线性，与地面染色同一空间。
	mat.set_shader_parameter("color_bottom", bottom)
	mat.set_shader_parameter("color_top", top)
	mat.set_shader_parameter("wind_scale", 0.34)
	mat.set_shader_parameter("deg_sway_pitch", 26.0)
	mat.set_shader_parameter("dissolve_scale", 3.4)
	mesh.surface_set_material(0, mat)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 8:
		tries += 1
		var pos := _region_pos(region, 0.0, 0.99, 2.8, 0.8)
		if not pos.is_finite():
			continue
		var yaw := _rng.randf() * TAU
		var s := _rng.randf_range(0.7, 1.2)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
	_build_multimesh("MM_%s_grass" % String(region["id"]), mesh, transforms, false)


# ---- 程序化小件 ----

func _scatter_mushrooms(region: Dictionary, count: int) -> void:
	var cap := SphereMesh.new()
	cap.radius = 0.20
	cap.height = 0.16
	cap.radial_segments = 6
	cap.rings = 2
	cap.material = NatureAssetsScript.dissolve_material(Color("d9c8a8"), 0.92, 1.8)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.045
	stem.bottom_radius = 0.065
	stem.height = 0.26
	stem.radial_segments = 4
	stem.material = NatureAssetsScript.dissolve_material(Color("e8e2d2"), 0.95, 2.0)
	var caps: Array[Transform3D] = []
	var stems: Array[Transform3D] = []
	var tries := 0
	while caps.size() < count and tries < count * 25:
		tries += 1
		var pos := _region_pos(region)
		if not pos.is_finite():
			continue
		var yaw := _rng.randf() * TAU
		var s := _rng.randf_range(0.7, 1.4)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
		caps.append(Transform3D(basis, pos + Vector3(0.0, 0.30 * s, 0.0)))
		stems.append(Transform3D(basis, pos + Vector3(0.0, 0.13 * s, 0.0)))
	_build_multimesh("MM_%s_mushroom_cap" % String(region["id"]), cap, caps, false)
	_build_multimesh("MM_%s_mushroom_stem" % String(region["id"]), stem, stems, false)


func _scatter_ferns(region: Dictionary, count: int) -> void:
	var mesh := _make_grass_clump(4, 0.42, 0.13)
	mesh.surface_set_material(0, NatureAssetsScript.dissolve_material(Color("3f6a34"), 0.95, 2.0))
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 20:
		tries += 1
		var pos := _region_pos(region)
		if not pos.is_finite():
			continue
		var yaw := _rng.randf() * TAU
		var s := _rng.randf_range(0.8, 1.6)
		transforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos))
	_build_multimesh("MM_%s_fern" % String(region["id"]), mesh, transforms, false)


func _scatter_ice_crystals(region: Dictionary, count: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.18
	mesh.height = 0.8
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.material = _glow_material(Color("bfe8ff"), Color("6fb8ff"), 0.9, 0.25)
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 30:
		tries += 1
		var base := _region_pos(region, 0.05, 0.95)
		if not base.is_finite():
			continue
		# 每簇 1~3 根冰晶，围绕落点散开，高低错落
		var blades := _rng.randi_range(1, 3)
		for _b in blades:
			var offset := Vector3(_rng.randf_range(-0.45, 0.45), 0.0, _rng.randf_range(-0.45, 0.45))
			var tilt := Basis(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, _rng.randf_range(-0.4, 0.4))
			var basis := Basis(Vector3.UP, _rng.randf() * TAU) * tilt
			var s := _rng.randf_range(0.5, 1.3)
			transforms.append(Transform3D(basis.scaled(Vector3.ONE * s), base + offset + Vector3(0.0, 0.34 * s, 0.0)))
	_build_multimesh("MM_%s_ice" % String(region["id"]), mesh, transforms, false)


## 贴地薄片（雪斑 / 焦土 / 盐壳）：程序化扇形圆盘，顶点轻微起伏避免与地面共面闪烁。
## v40.1：斑块数量/尺寸大幅下调、颜色贴近地面 tint，并用「已放位置列表」做最小间距拒绝采样，
## 避免大块白/黑圆饼互相叠压。返回落点数组（余烬花据此成簇）。
func _scatter_ground_patches(region: Dictionary, count: int, color: Color,
		s_min: float, s_max: float, tag: String, y_off: float = 0.06,
		road_clear: float = 3.0) -> Array[Vector3]:
	var placed: Array[Vector3] = []
	if region.is_empty():
		return placed
	var mesh := _make_ground_disc()
	mesh.surface_set_material(0, NatureAssetsScript.dissolve_material(color, 0.97, 1.6))
	# 斑块基准半径约 0.5m：平均半径 = 平均缩放 × 0.5，最小间距 ≥ 1.4 × 平均半径
	var avg_radius := (s_min + s_max) * 0.5 * 0.5
	var min_gap := 1.4 * avg_radius
	var transforms: Array[Transform3D] = []
	var tries := 0
	while transforms.size() < count and tries < count * 24:
		tries += 1
		var pos := _region_pos(region, 0.0, 1.0, road_clear, 0.8)
		if not pos.is_finite():
			continue
		var yaw := _rng.randf() * TAU
		# 非均匀缩放 → 不规则椭圆斑块
		var sx := _rng.randf_range(s_min, s_max)
		var sz := _rng.randf_range(s_min, s_max)
		var too_close := false
		for prev in placed:
			if Vector2(prev.x - pos.x, prev.z - pos.z).length() < min_gap:
				too_close = true
				break
		if too_close:
			continue
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sx, 1.0, sz))
		transforms.append(Transform3D(basis, pos + Vector3(0.0, y_off, 0.0)))
		placed.append(pos)
	_build_multimesh("MM_%s_%s" % [String(region["id"]), tag], mesh, transforms, false)
	return placed


func _make_ground_disc(segments: int = 7) -> Mesh:
	var verts := PackedVector3Array()
	var ring: Array[Vector3] = []
	for i in segments:
		var a := TAU * float(i) / float(segments)
		var r := 0.42 + 0.08 * fposmod(sin(float(i) * 27.13) * 43758.5453, 1.0)
		ring.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in segments:
		var pa: Vector3 = ring[i]
		var pb: Vector3 = ring[(i + 1) % segments]
		pa.y = 0.006 * sin(float(i) * 3.7)
		pb.y = 0.006 * sin(float(i + 1) * 3.7)
		# 逆时针（从上方看）→ 法线朝 +Y；材质 cull_back 才不会把斑块剃掉
		verts.append(Vector3.ZERO)
		verts.append(pb)
		verts.append(pa)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _glow_material(albedo: Color, emission: Color, energy: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat


# ---- 道具净空（ThemedRegions 的 AABB 精确避让）----

## 收集 ThemedRegions 道具的 XZ 包围盒，登记到 8m 空间桶。
## 优先按分组 "themed_regions" 取；Main.tscn 里装饰排在 WorldScenery 之前，
## 分组可能还没登记时按节点名兜底（只读，不依赖其内部结构）。
func _gather_themed_props() -> void:
	_prop_rects.clear()
	var root := get_tree().get_first_node_in_group("themed_regions")
	if root == null:
		var world := get_parent().get_parent() if get_parent() != null else null
		if world != null:
			root = world.get_node_or_null("WorldScenery/ThemedRegions")
	if root == null:
		return
	for child in root.get_children():
		var aabbs: Array[AABB] = []
		_collect_mesh_aabbs(child, aabbs)
		if aabbs.is_empty():
			continue
		var box := aabbs[0]
		for i in range(1, aabbs.size()):
			box = box.merge(aabbs[i])
		_register_prop_rect(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))


func _collect_mesh_aabbs(node: Node, out: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(mi.global_transform * mi.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, out)


func _register_prop_rect(rect: Rect2) -> void:
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return
	var min_x := floori(rect.position.x / PROP_BUCKET)
	var max_x := floori((rect.position.x + rect.size.x) / PROP_BUCKET)
	var min_y := floori(rect.position.y / PROP_BUCKET)
	var max_y := floori((rect.position.y + rect.size.y) / PROP_BUCKET)
	for by in range(min_y, max_y + 1):
		for bx in range(min_x, max_x + 1):
			var key := Vector2i(bx, by)
			if not _prop_rects.has(key):
				_prop_rects[key] = []
			(_prop_rects[key] as Array).append(rect)


## 落点是否落在某道具包围盒（外扩 pad）内。
func _prop_blocked(point: Vector2, pad: float) -> bool:
	if _prop_rects.is_empty():
		return false
	var key := Vector2i(floori(point.x / PROP_BUCKET), floori(point.y / PROP_BUCKET))
	var bucket: Variant = _prop_rects.get(key)
	if bucket == null:
		return false
	for rect in bucket:
		if (rect as Rect2).grow(pad).has_point(point):
			return true
	return false


# ---- 分区散布工具 ----

## 区域内的候选点：归一化半径 inner..outer 的圆环内随机取样，并做全部避让检查。
## road_clear = 离路最小净空（米）；prop_pad = 道具包围盒外扩容差（树冠越大给越大）。
func _region_pos(region: Dictionary, inner: float = 0.0, outer: float = 1.0,
		road_clear: float = 2.6, prop_pad: float = 0.8) -> Vector3:
	if region.is_empty():
		return Vector3(INF, INF, INF)
	var center: Vector2 = region["center"]
	var radius: float = float(region["radius"])
	var lo := inner * inner
	var hi := outer * outer
	for _i in 40:
		var angle := _rng.randf() * TAU
		var r := sqrt(_rng.randf_range(lo, hi)) * radius
		var point := center + Vector2(cos(angle), sin(angle)) * r
		var pos := Vector3(point.x, 0.0, point.y)
		if _valid_region(pos, road_clear, prop_pad):
			return pos
	return Vector3(INF, INF, INF)


## 区域植被避让：水域 / 道路 / 城内 / 资源点 / 地标核心区 / 道具包围盒 / 地图边界。
func _valid_region(pos: Vector3, road_clear: float = 2.6, prop_pad: float = 0.8) -> bool:
	var point := Vector2(pos.x, pos.z)
	var cheby := maxf(absf(pos.x), absf(pos.z))
	if cheby > map_half:
		return false
	# 湖 / 河 / 水潭：留 0.8m 岸线余量（与主散布一致）
	if WorldLayout.is_water(point, 0.8):
		return false
	# 主路 + 小径
	if WorldLayout.road_distance(point) < road_clear:
		return false
	# 王城与城边缓冲
	if cheby < city_half + 3.0:
		return false
	# 旧地标 + 区域地标核心区：landmark_clearance 已扩到 11m，这里再留 2m 道具余量
	if WorldLayout.is_landmark(point, 2.0):
		return false
	for p in _resource_points:
		if point.distance_to(p) < 2.6:
			return false
	# ThemedRegions 道具净空（矿箱 / 断旗 / 风车 / 祭坛 / 栈道…），树冠大件再外扩
	if _prop_blocked(point, prop_pad):
		return false
	return true


## 优先新素材；一个都没下载好时回退到现有模型（regions-builder 是异步工作线）。
func _resolve_models(preferred: Array, fallbacks: Array) -> Array[String]:
	var out: Array[String] = []
	for m in preferred:
		if _has_asset(String(m)):
			out.append(String(m))
	if out.is_empty():
		for m in fallbacks:
			if _has_asset(String(m)):
				out.append(String(m))
	if out.is_empty():
		for m in fallbacks:
			out.append(String(m))
	return out


## 区域树 / 岩石通用散布：count 按模型均分，每个模型一份 tinted 网格 + MultiMesh。
func _scatter_region_models(region: Dictionary, count: int, preferred: Array, fallbacks: Array,
		deep: Color, light: Color, s_min: float, s_max: float, y_off: float = 0.0,
		cast_shadow: bool = true, inner: float = 0.0, outer: float = 1.0,
		road_clear: float = 3.2, prop_pad: float = 1.6, stone_bark: bool = false) -> void:
	if count <= 0 or region.is_empty():
		return
	var models := _resolve_models(preferred, fallbacks)
	if models.is_empty():
		return
	var per := maxi(1, int(round(float(count) / float(models.size()))))
	for m in models:
		var mesh: Mesh = null
		if stone_bark:
			mesh = _load_dead_tree_mesh(m, deep, light)
		else:
			mesh = _load_mesh_tinted(m, deep, light)
		if mesh == null:
			push_warning("DecorationScatter: 区域模型缺失 %s" % m)
			continue
		var transforms: Array[Transform3D] = []
		var tries := 0
		while transforms.size() < per and tries < per * 20:
			tries += 1
			var pos := _region_pos(region, inner, outer, road_clear, prop_pad)
			if not pos.is_finite():
				continue
			var yaw := _rng.randf_range(0.0, TAU)
			var s := _rng.randf_range(s_min, s_max)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s)
			transforms.append(Transform3D(basis, pos + Vector3(0.0, y_off, 0.0)))
		_build_multimesh("MM_%s_%s" % [String(region["id"]), m], mesh, transforms, cast_shadow)


## 位置哈希（0~1，确定性）：区域地表稀疏化用，不消耗 _rng。
func _pos_hash(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)



# ---- gltf 加载（取 mesh 做 MultiMesh 模板）----

## 模型路径解析：优先 .gltf（现有素材），再试 .glb（新下载素材可能是二进制）；都没有返回空串。
func _asset_path(res_name: String) -> String:
	for ext in [".gltf", ".glb"]:
		var path: String = NATURE_DIR + res_name + String(ext)
		if ResourceLoader.exists(path):
			return path
	return ""


func _has_asset(res_name: String) -> bool:
	return _asset_path(res_name) != ""


## 原始模型网格（未做任何材质风格化）：从 .gltf/.glb 里取第一个 MeshInstance3D 的 mesh。
func _load_mesh_base(res_name: String) -> Mesh:
	var path := _asset_path(res_name)
	if path == "":
		return null
	var scene := _load_glb_scene(path)
	if scene == null:
		return null
	var mi := _find_mesh(scene)
	var mesh := mi.mesh if mi != null else null
	scene.free()   # 仅取 mesh 资源引用，丢弃实例节点
	return mesh


func _load_mesh(res_name: String) -> Mesh:
	var mesh := _load_mesh_base(res_name)
	# 树冠 / 石头换成带「主角半球消散」的 shader（v13）：材质挂在 mesh 资源上，
	# MultiMesh 的所有实例共用，判定由 DecorationDissolveSystem 的全局 shader 参数驱动。
	if mesh != null and res_name.begins_with("tree"):
		mesh = NatureAssetsScript.forest_mesh(mesh)
	elif mesh != null and res_name.begins_with("rock"):
		mesh = NatureAssetsScript.stone_mesh(mesh)
	return mesh


## 枯树专用网格（v40.1）：站姿树强制走 stone 材质（灰褐、无绿叶），
## 读作焦木 / 盐枯木；与树桩共用同一套「去粉色贴图」思路。
func _load_dead_tree_mesh(res_name: String, deep: Color, light: Color) -> Mesh:
	var raw := _load_mesh_base(res_name)
	if raw == null:
		return null
	var mesh := NatureAssetsScript.stone_mesh(raw)
	for surface in mesh.get_surface_count():
		var mat := mesh.surface_get_material(surface) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("stone_deep", deep)
			mat.set_shader_parameter("stone_light", light)
	return mesh


## 树桩专用网格（v40.1）：强制走 stone 材质 → 丢掉 cut 模型贴图里的粉红底环，
## 只剩灰褐色石块般的明暗变化；再按区域压深色调。
func _load_stump_mesh(res_name: String, deep: Color, light: Color) -> Mesh:
	var raw := _load_mesh_base(res_name)
	if raw == null:
		return null
	var mesh := NatureAssetsScript.stone_mesh(raw)
	for surface in mesh.get_surface_count():
		var mat := mesh.surface_get_material(surface) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("stone_deep", deep)
			mat.set_shader_parameter("stone_light", light)
	return mesh


## 载入模型并套用区域配色（v40 分区散布）：
## 树 / 水草改 foliage 的 forest_deep / forest_light，石头改 stone_deep / stone_light，
## 其它材质换成通用消散材质——都在 mesh 副本上改，绝不污染导入资源本身。
func _load_mesh_tinted(res_name: String, deep: Color, light: Color) -> Mesh:
	var source := _load_mesh(res_name)
	if source == null:
		return null
	var mesh := source.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var mat := mesh.surface_get_material(surface) as ShaderMaterial
		if mat == null:
			mesh.surface_set_material(surface, NatureAssetsScript.dissolve_material(deep.lerp(light, 0.4), 0.95, 1.1))
			continue
		if mat.shader == NatureAssetsScript.FOLIAGE_SHADER:
			mat.set_shader_parameter("forest_deep", deep)
			mat.set_shader_parameter("forest_light", light)
		elif mat.shader == NatureAssetsScript.STONE_SHADER:
			mat.set_shader_parameter("stone_deep", deep)
			mat.set_shader_parameter("stone_light", light)
		else:
			mesh.surface_set_material(surface, NatureAssetsScript.dissolve_material(deep.lerp(light, 0.4), 0.95, 1.1))
	return mesh


static func _load_glb_scene(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return (res as PackedScene).instantiate() as Node3D
	# 回退：运行时解析原始 glTF（.gltf + 外部 .bin + png 相对 URI 以 .gltf 所在目录为基址）
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("DecorationScatter: 解析模型失败 %s (err=%d)" % [path, err])
		return null
	return doc.generate_scene(state)


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null
