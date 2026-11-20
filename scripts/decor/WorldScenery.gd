extends Node3D
## 地标、远山与环境碰撞；世界主干仍由 Main.tscn 声明。
## 草地保持 y=0，远山仅位于可玩边界外。湖泊同时登记到格子与物理空间。

var _rng := RandomNumberGenerator.new()
var _materials: Dictionary = {}
var _fire_light: OmniLight3D


func _ready() -> void:
	_rng.seed = 90210
	var world := get_parent()
	for path in ["GroundPlane/MeshInstance3D", "Water"]:
		var visual := world.get_node(path) as MeshInstance3D
		WorldLayout.apply_shader_parameters(visual.material_override as ShaderMaterial)
	var grid := world.get_node("GridSystem") as GridSystem
	_build_terrain_collision(grid)
	_build_backdrop()
	_build_plaza()
	_build_gates()
	_build_camp()
	_build_ruins()
	_build_quarry()
	_build_shore()
	_build_water_feature()
	# v40 主题区域（地标道具）与区域叙事追踪器。用「存在才加载」的方式接线，
	# 便于两条独立工作线并行开发：脚本缺失时静默跳过，不阻塞主场景加载。
	_build_themed_regions()
	_build_region_tracker()
	_build_region_ambience()
	# v36：湖面碰撞盒必须等水系登记完 terrain_cells 之后再建（见 _build_lake_collision_boxes），
	# 否则河口浅滩会出现「寻路可走、物理却是隐形墙」的矛盾格，单位被卡进湖里。
	_build_lake_collision_boxes(grid)


func _process(_delta: float) -> void:
	if _fire_light != null:
		var t := Time.get_ticks_msec() * 0.001
		_fire_light.light_energy = 1.6 + sin(t * 7.0) * 0.18 + sin(t * 11.0) * 0.1


func _material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var key := color.to_html() + str(glowing)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	_materials[key] = material
	return material


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, glowing: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color, glowing)
	node.position = pos
	parent.add_child(node)
	return node


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, pos, color)


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, top: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 8
	return _mesh(parent, mesh, pos, color)


func _group(node_name: String, point: Vector2 = Vector2.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = Vector3(point.x, 0.0, point.y)
	add_child(node)
	return node


func _collision_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos
	parent.add_child(collision)


## 湖泊先登记进 terrain_cells（NavSystem 的 A* 图与 WaterFeature 的浅滩清理都读它），
## 地图边界墙在此立起；湖面碰撞盒延后到 _build_lake_collision_boxes() 创建。
func _build_terrain_collision(grid: GridSystem) -> void:
	var body := StaticBody3D.new()
	body.name = "LakeAndMapBoundary"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	if grid != null:
		for x in grid.grid_size.x:
			for z in grid.grid_size.y:
				var cell := Vector2i(x, z)
				var point := grid.grid_to_world(cell)
				if WorldLayout.lake_distance(Vector2(point.x, point.z)) < 1.0:
					grid.terrain_cells[cell] = true
	var h := WorldLayout.MAP_HALF
	for side in [-1.0, 1.0]:
		_collision_box(body, Vector3(side * (h + 0.5), 2, 0), Vector3(1, 4, h * 2 + 2))
		_collision_box(body, Vector3(0, 2, side * (h + 0.5)), Vector3(h * 2, 4, 1))


## v36 修复（单位卡进湖里）：湖面物理碰撞盒此前在浅滩清理之前就建好了，
## WaterFeature._register_terrain() 清出的河口浅滩格于是变成「A* 认为可走、
## 物理却是隐形墙」的矛盾格——路径把单位引进去、出生吸附把单位放进去之后，
## 单位嵌在静态碰撞盒里永久卡死，重算路径也救不回来（寻路认为它站得好好的）。
## 现在按 terrain_cells 的最终状态建盒：被清成可走的浅滩格不再有碰撞。
func _build_lake_collision_boxes(grid: GridSystem) -> void:
	if grid == null:
		return
	var body := get_node_or_null("LakeAndMapBoundary") as StaticBody3D
	if body == null:
		return
	for raw_cell in grid.terrain_cells:
		var cell: Vector2i = raw_cell
		var point := grid.grid_to_world(cell)
		if WorldLayout.lake_distance(Vector2(point.x, point.z)) < 1.0:
			_collision_box(body, point + Vector3(0, 1.5, 0), Vector3(grid.cell_size, 3, grid.cell_size))


func _build_backdrop() -> void:
	var backdrop := _group("DistantRidges")
	# v40.1 表现打磨：
	# ① 地面网格从 1024 缩到 560（见 Main.tscn），边缘在地平线附近不再是一整块「悬空绿板」；
	# ② 地面之下铺一张巨大雾毯（受光/受雾的深绿灰），远景读作「雾里的原野」而不是虚空；
	# ③ 远山两环（近环 164~182m / 远环 232~268m）都用乘算色调压成冷绿灰，
	#    去掉 KayKit 山体自带的黄色草顶（截图上像一排漂浮的黄色花盆）。
	var haze := MeshInstance3D.new()
	haze.name = "DistantHaze"
	var haze_mesh := PlaneMesh.new()
	haze_mesh.size = Vector2(2400, 2400)
	haze.mesh = haze_mesh
	var haze_mat := StandardMaterial3D.new()
	haze_mat.albedo_color = Color(0.32, 0.41, 0.36)
	haze_mat.roughness = 1.0
	haze_mat.metallic = 0.0
	haze.material_override = haze_mat
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	haze.position = Vector3(0.0, -0.55, 0.0)
	backdrop.add_child(haze)
	var mountain_scene := load("res://assets/_PLACEHOLDER/nature/mountain_A_grass.gltf") as PackedScene
	var hill_scene := load("res://assets/_PLACEHOLDER/nature/hills_A_trees.gltf") as PackedScene
	var near_tint := Color(0.46, 0.56, 0.52)
	for i in 56:
		var a := float(i) / 56.0 * TAU + _rng.randf_range(-0.03, 0.03)
		var extent := _rng.randf_range(164.0, 182.0) / maxf(absf(cos(a)), absf(sin(a)))
		var mountain := mountain_scene.instantiate() as Node3D
		mountain.position = Vector3(cos(a), 0, sin(a)) * extent
		mountain.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(14.0, 22.0)
		mountain.scale = Vector3(s, s * _rng.randf_range(0.7, 1.05), s)
		backdrop.add_child(mountain)
		_tint_gltf(mountain, near_tint)
		if i % 2 == 0:
			var hill := hill_scene.instantiate() as Node3D
			hill.position = mountain.position * 0.86
			hill.rotation.y = _rng.randf() * TAU
			hill.scale = Vector3(10, 6, 10)
			backdrop.add_child(hill)
			_tint_gltf(hill, near_tint.darkened(0.08))
	var far_tint := Color(0.34, 0.44, 0.41)
	for i in 40:
		var a := float(i) / 40.0 * TAU + _rng.randf_range(-0.04, 0.04)
		var extent := _rng.randf_range(232.0, 268.0) / maxf(absf(cos(a)), absf(sin(a)))
		var mountain := mountain_scene.instantiate() as Node3D
		mountain.position = Vector3(cos(a), 0, sin(a)) * extent
		mountain.rotation.y = _rng.randf() * TAU
		var s := _rng.randf_range(20.0, 30.0)
		mountain.scale = Vector3(s, s * _rng.randf_range(0.7, 1.2), s)
		backdrop.add_child(mountain)
		_tint_gltf(mountain, far_tint)


## 给 glTF 场景的每个 MeshInstance3D 套一层「乘算色调」材质：保留原贴图明暗细节，
## 只把 albedo 乘上 tint。远山环带靠它压掉 KayKit 山体自带的黄色草顶。
func _tint_gltf(root: Node3D, tint: Color) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null:
			continue
		var mat := src.duplicate() as StandardMaterial3D
		mat.albedo_color = tint
		mat.roughness = 1.0
		mat.metallic = 0.0
		mi.material_override = mat


func _build_plaza() -> void:
	var plaza := _group("CastleCourtyard")
	# 城内留作玩家布路；保留庭院灯，不再预铺石板。
	for x in [-5.6, 5.6]:
		for z in [-5.6, 5.6]:
			_lantern(plaza, Vector3(x, 0, z), 1.8)


func _lantern(parent: Node3D, at: Vector3, height: float) -> void:
	_cylinder(parent, at + Vector3(0, height * 0.5, 0), 0.09, height, Color("574c3e"))
	_cylinder(parent, at + Vector3(0, 0.15, 0), 0.24, 0.3, Color("868371"))
	var glass := BoxMesh.new()
	glass.size = Vector3(0.29, 0.36, 0.29)
	_mesh(parent, glass, at + Vector3(0, height, 0), Color("ffd995"), true)
	_cylinder(parent, at + Vector3(0, height + 0.26, 0), 0.28, 0.17, Color("4b5c59"), 0.08)


func _build_gates() -> void:
	# v43：城半宽 26m → 城门锚点从 21.5m 挪到 27.5m（城门火把 / 路标 / 栅栏同一套换算）。
	var gate_z := 27.5
	for i in 4:
		var gate := _group("TownApproach_%d" % i)
		gate.rotation.y = i * PI * 0.5
		for side in [-1.0, 1.0]:
			var pos := Vector3(side * 3.2, 0, gate_z)
			_box(gate, pos + Vector3(0, 0.45, 0), Vector3(0.9, 0.9, 0.9), Color("8c907b"))
			_lantern(gate, pos + Vector3(0, 0.9, 0), 2.4)
			_box(gate, pos + Vector3(side * 0.6, 2.8, 0), Vector3(1.0, 1.25, 0.07), Color("437f9a"))
			for j in 3:
				var fence_pos := Vector3(side * (4.2 + j * 1.6), 0, gate_z)
				_cylinder(gate, fence_pos + Vector3(0, 0.5, 0), 0.10, 1.0, Color("72634a"))
				for y in [0.4, 0.8]:
					_box(gate, fence_pos + Vector3(side * 0.7, y, 0), Vector3(1.55, 0.12, 0.1), Color("908062"))


func _build_camp() -> void:
	var camp := _group("WayfarerCamp", WorldLayout.CAMP)
	# 两张斜面组成帆布帐篷，开口向小路。
	for side in [-1.0, 1.0]:
		var canvas := _box(camp, Vector3(-1.8 + side * 0.65, 1.0, -1.2), Vector3(0.10, 2.4, 3.0), Color("d6ba7b"))
		canvas.rotation.z = side * 0.57
		_cylinder(camp, Vector3(-1.8, 1.1, -1.2 + side * 1.55), 0.065, 2.2, Color("63513c"))
	for i in 11:
		var a := float(i) / 11.0 * TAU
		_cylinder(camp, Vector3(1.5 + cos(a) * 0.85, 0.15, 1.0 + sin(a) * 0.85), 0.23, 0.3, Color("919180"))
	for i in 3:
		var log_node := _cylinder(camp, Vector3(1.5, 0.22 + i * 0.06, 1), 0.14, 1.3, Color("63452f"))
		log_node.rotation = Vector3(PI * 0.5, i * PI / 3.0, 0)
	var flame := SphereMesh.new()
	flame.radius = 0.28
	flame.height = 0.95
	_mesh(camp, flame, Vector3(1.5, 0.65, 1), Color("ffac46"), true)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(1.5, 1.3, 1)
	_fire_light.light_color = Color("ffc875")
	_fire_light.omni_range = 6.0
	camp.add_child(_fire_light)
	for i in 4:
		var crate := _box(camp, Vector3(-3.5 + i * 0.65, 0.3, 2.2), Vector3(0.55, 0.6, 0.55), Color("a18151"))
		crate.rotation.y = _rng.randf_range(-0.15, 0.15)


func _build_ruins() -> void:
	var ruins := _group("OldWatchtowerRuins", WorldLayout.RUINS)
	var stone := Color("959b8a")
	for side in [-1.0, 1.0]:
		for level in 5:
			_box(ruins, Vector3(side * 2.1, level * 0.65 + 0.325, -1.2), Vector3(1.1, 0.61, 1.2), stone.darkened(level * 0.015))
	_box(ruins, Vector3(0, 3.4, -1.2), Vector3(5.4, 0.55, 1.3), stone)
	for i in 16:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.5, 5.5)
		var block := _box(ruins, Vector3(cos(a) * r, 0.24, sin(a) * r), Vector3(0.9, 0.45, 0.7), stone.darkened(_rng.randf() * 0.2))
		block.rotation.y = a


func _build_quarry() -> void:
	var quarry := _group("StonecuttersRest", WorldLayout.QUARRY)
	for i in 7:
		var height := _rng.randf_range(1.2, 3.5)
		var boulder := _cylinder(quarry, Vector3(-4 + i * 1.3, height * 0.5 - 0.1, -2.5), 1.3, height, Color("9d9b88"), 0.7)
		boulder.rotation.y = _rng.randf() * TAU
	for i in 4:
		_box(quarry, Vector3(-1.5 + i * 0.9, 0.35, 1.5), Vector3(0.8, 0.7, 0.8), Color("bbb39a"))
	_lantern(quarry, Vector3(3, 0, 1), 2.0)


## v43 湖岸：按 WorldLayout.lake_shore_scale 的新谐波岸线铺石头，并补一层「岸边小景」——
## 卵石堆 / 芦苇 / 倒木 / 湖灯，让湖不再只是一圈石头围着的椭圆水面（纯视觉）。
func _build_shore() -> void:
	var shore := _group("LakeshoreStones")
	var center := WorldLayout.LAKE_CENTER
	var rock_colors: Array[Color] = [Color("b7b39a"), Color("a8a68f"), Color("c2bda1")]
	# ① 环湖卵石：按新岸线谐波摆放（不再假设均匀椭圆）
	for i in 90:
		var a := float(i) / 90.0 * TAU + _rng.randf_range(-0.02, 0.02)
		var scale := WorldLayout.lake_shore_scale(a) + _rng.randf_range(0.015, 0.085)
		var point := center + Vector2(cos(a) * WorldLayout.LAKE_RADII.x,
			sin(a) * WorldLayout.LAKE_RADII.y) * scale
		var rock := _cylinder(shore, Vector3(point.x, 0.12, point.y), _rng.randf_range(0.22, 0.62),
			_rng.randf_range(0.22, 0.5), rock_colors[i % 3], 0.16)
		rock.rotation.y = a
	# ② 成堆的卵石 / 大石（每 5 个点挑一处堆 3 块）
	for i in 14:
		var a := float(i) / 14.0 * TAU + _rng.randf_range(-0.05, 0.05)
		var scale := WorldLayout.lake_shore_scale(a) + _rng.randf_range(0.03, 0.10)
		var base := center + Vector2(cos(a) * WorldLayout.LAKE_RADII.x,
			sin(a) * WorldLayout.LAKE_RADII.y) * scale
		for k in 3:
			var off := Vector2(_rng.randf_range(-0.9, 0.9), _rng.randf_range(-0.9, 0.9))
			var boulder := _cylinder(shore, Vector3(base.x + off.x, 0.16, base.y + off.y),
				_rng.randf_range(0.3, 0.62), _rng.randf_range(0.24, 0.55), Color("a9a691"), 0.2)
			boulder.rotation = Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.0, TAU),
				_rng.randf_range(-0.15, 0.15))
	# ③ 芦苇丛：浅水里成片长（模型入水半截，露出水面的部分读作芦苇）
	var reed_scene := load("res://assets/_PLACEHOLDER/nature/waterplant_A.gltf") as PackedScene
	var lily_scene := load("res://assets/_PLACEHOLDER/nature/waterlily_B.gltf") as PackedScene
	for i in 26:
		var a := _rng.randf_range(0.0, TAU)
		# 芦苇偏西 / 南岸（城对岸），北岸留给码头与瀑布下游
		if i % 4 == 0:
			a = _rng.randf_range(PI * 0.35, PI * 0.95)
		var scale := WorldLayout.lake_shore_scale(a) + _rng.randf_range(0.005, 0.06)
		var q := center + Vector2(cos(a) * WorldLayout.LAKE_RADII.x, sin(a) * WorldLayout.LAKE_RADII.y) * scale
		if reed_scene != null and i % 3 != 0:
			_place_prop(shore, reed_scene, q, _rng.randf_range(0.9, 1.6), 0.06)
		elif lily_scene != null:
			_place_prop(shore, lily_scene, q, _rng.randf_range(0.8, 1.4), 0.08)
	# ④ 倒木：湖西岸一根横卧的枯木（半截伸进浅水），再加一根细枝
	var log_node := _cylinder(shore, Vector3(37.6, 0.34, -33.2), 0.28, 5.4, Color("6d563c"))
	log_node.rotation = Vector3(PI * 0.5, 0.9, 0.06)
	var log_branch := _cylinder(shore, Vector3(35.4, 0.28, -36.4), 0.16, 2.8, Color("5b4630"))
	log_branch.rotation = Vector3(PI * 0.5, -0.35, 0.10)
	# ⑤ 湖灯：西岸 / 南岸各一盏（夜里湖面有暖色倒影点）
	_lantern(shore, Vector3(36.4, 0, -29.6), 2.2)
	_lantern(shore, Vector3(41.2, 0, -24.9), 2.0)


## 岸边小景放置：贴水面的道具压到 y（芦苇 / 睡莲半沉）。
func _place_prop(parent: Node3D, scene: PackedScene, at: Vector2, scale_mul: float, y: float) -> void:
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	node.position = Vector3(at.x, y, at.y)
	node.rotation.y = _rng.randf_range(0.0, TAU)
	node.scale = Vector3.ONE * scale_mul
	parent.add_child(node)


## v12 北境水系（瀑布 → 水潭 → 河流 → 湖泊）。必须在这里就位：WorldScenery 排在
## NavSystem 之前，WaterFeature._ready() 会把河道 / 水潭 / 崖体写进 GridSystem.terrain_cells，
## NavSystem 建 A* 图时才能读到（与湖泊永久阻挡同一套做法）。
func _build_water_feature() -> void:
	var feature := WaterFeature.new()
	feature.name = "WaterFeature"
	feature.world_root = get_parent()
	add_child(feature)


## v40 主题区域地标：scripts/decor/ThemedRegions.gd（独立工作线）。
## 用「存在才加载」接线，脚本尚未落地时静默跳过，不阻塞主场景加载。
func _build_themed_regions() -> void:
	var path := "res://scripts/decor/ThemedRegions.gd"
	if not ResourceLoader.exists(path):
		return
	var script := load(path) as Script
	if script == null:
		return
	var node := script.new() as Node3D
	if node == null:
		return
	node.name = "ThemedRegions"
	add_child(node)


## v40.2 区域氛围粒子：scripts/decor/RegionAmbience.gd（独立工作线）。
func _build_region_ambience() -> void:
	var path := "res://scripts/decor/RegionAmbience.gd"
	if not ResourceLoader.exists(path):
		return
	var script := load(path) as Script
	if script == null:
		return
	var node := script.new() as Node3D
	if node == null:
		return
	node.name = "RegionAmbience"
	add_child(node)


## v40 区域发现 / 故事播报：scripts/systems/RegionTracker.gd（独立工作线）。
func _build_region_tracker() -> void:
	var path := "res://scripts/systems/RegionTracker.gd"
	if not ResourceLoader.exists(path):
		return
	var script := load(path) as Script
	if script == null:
		return
	var node := script.new() as Node
	if node == null:
		return
	node.name = "RegionTracker"
	add_child(node)
