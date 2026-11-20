class_name PrologueStage
extends Node3D
## 序章的独立表现层。只增视觉标记与调色，不改变碰撞、导航占用和沙盒场景资源。
var _nav: NavSystem
var _hero: Hero
var _base: Node3D
var _route: MultiMeshInstance3D
var _capture_ring: MeshInstance3D
var _banner: Node3D
var _banner_mat: StandardMaterial3D
var _route_target: Node3D
var _route_tick := 0.0
var _ready_to_claim := false
var _time := 0.0

func setup(world: Node3D, nav: NavSystem, hero: Hero, base: Node3D) -> void:
	_nav = nav
	_hero = hero
	_base = base
	_style_world(world)
	_build_route()
	_build_claim_marker()
	_build_arrival(world)
	_redraw_route()

func _style_world(world: Node3D) -> void:
	# 收起草花与大块纯装饰树石；保留真实资源障碍，画面与寻路仍然一致。
	var scatter := world.get_node_or_null("Decorations/DecorationScatter")
	if scatter != null:
		var anchors: Array[Vector3] = [PrologueDirector.START_POS]
		anchors.append_array(PrologueDirector.RAIDER_ANCHORS)
		anchors.append(Vector3.ZERO)
		for child in scatter.get_children():
			if not child is MultiMeshInstance3D:
				continue
			var visual := child as MultiMeshInstance3D
			if String(child.name).contains("grass") or String(child.name).contains("flower"):
				# v40：MultiMesh.duplicate() 会把内部 buffer 一起复制，而本项目的草/花
				# MultiMesh 是用 set_instance_transform 逐实例写入的（buffer 未维护），
				# 直接 duplicate 会在序章加载时每块草刷一条「buffer 尺寸不一致」ERROR。
				# 这里改为按同一格式新建、只拷贝前 1/8 实例（与旧版「草/花只留 1/8」语义一致）。
				var src := visual.multimesh
				if src == null or src.instance_count <= 0:
					continue
				var keep := maxi(1, src.instance_count / 8)
				var thinned := MultiMesh.new()
				thinned.transform_format = src.transform_format
				thinned.use_colors = src.use_colors
				thinned.use_custom_data = src.use_custom_data
				thinned.mesh = src.mesh
				thinned.instance_count = keep
				for i in keep:
					thinned.set_instance_transform(i, src.get_instance_transform(i))
					if src.use_colors:
						thinned.set_instance_color(i, src.get_instance_color(i))
					if src.use_custom_data:
						thinned.set_instance_custom_data(i, src.get_instance_custom_data(i))
				visual.multimesh = thinned
				continue
			# 道路留白，两侧保留成簇树林作为框景；每个实例只在入场时筛选一次。
			var kept: Array[Transform3D] = []
			for i in visual.multimesh.instance_count:
				var transform := visual.multimesh.get_instance_transform(i)
				var point := Vector2(transform.origin.x, transform.origin.z)
				var clear := true
				for j in anchors.size() - 1:
					var start := Vector2(anchors[j].x, anchors[j].z)
					var end := Vector2(anchors[j + 1].x, anchors[j + 1].z)
					if point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, end)) < 6.5:
						clear = false
						break
				if clear:
					kept.append(transform)
			var filtered := MultiMesh.new()
			filtered.transform_format = MultiMesh.TRANSFORM_3D
			filtered.mesh = visual.multimesh.mesh
			filtered.instance_count = kept.size()
			for i in kept.size():
				filtered.set_instance_transform(i, kept[i])
			visual.multimesh = filtered

	var ground := world.get_node_or_null("GroundPlane/MeshInstance3D") as MeshInstance3D
	if ground != null and ground.material_override is ShaderMaterial:
		var material := ground.material_override.duplicate() as ShaderMaterial
		ground.material_override = material
		material.set_shader_parameter("albedo_grass_a", Color("688856"))
		material.set_shader_parameter("albedo_grass_b", Color("92a770"))
		material.set_shader_parameter("albedo_dirt", Color("d1bf94"))
		material.set_shader_parameter("cloud_amount", 0.25)
	var weather := world.get_node_or_null("WeatherSystem")
	if weather != null:
		weather.set_process(false)
	var cycle := world.get_node_or_null("DayNightCycle")
	if cycle != null:
		cycle.set_process(false)
	var sun := world.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-38, -32, 0)
		sun.light_color = Color("ffe8bd")
		sun.light_energy = 1.05
		sun.shadow_enabled = true
		sun.light_angular_distance = 0.6
	var environment := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if environment != null:
		# 复制资源，退出剧情后沙盒仍使用原场景的天气与环境。
		environment.environment = environment.environment.duplicate() as Environment
		var env := environment.environment
		env.ambient_light_color = Color("a8c3c7")
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.glow_enabled = false
		env.ssao_enabled = true
		env.ssao_intensity = 1.3
		env.fog_enabled = true
		env.fog_light_color = Color("b7cdca")
		env.fog_density = 0.0015

func _build_route() -> void:
	_route = MultiMeshInstance3D.new()
	_route.name = "GuidingTrail"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 0.025
	mesh.radial_segments = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 32
	mm.visible_instance_count = 0
	_route.multimesh = mm
	_route.material_override = _material(Color("f1d991"), true)
	_route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_route)

func _build_claim_marker() -> void:
	_capture_ring = MeshInstance3D.new()
	_capture_ring.name = "ClaimCircle"
	var ring := TorusMesh.new()
	ring.inner_radius = PrologueDirector.HOLD_RADIUS - 0.07
	ring.outer_radius = PrologueDirector.HOLD_RADIUS + 0.07
	ring.rings = 64
	ring.ring_segments = 6
	_capture_ring.mesh = ring
	_capture_ring.position = Vector3(0, 0.05, 0)
	_capture_ring.material_override = _material(Color("b3bca2"), true)
	_capture_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_capture_ring)
	_banner = Node3D.new()
	_banner.name = "RoyalStandard"
	_banner.position = Vector3(-4.6, 0, 2.8)
	add_child(_banner)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.08
	pole.height = 5
	_mesh(_banner, pole, Vector3(0, 2.5, 0), _material(Color("78674d")))
	var cloth := BoxMesh.new()
	cloth.size = Vector3(1.8, 1.0, 0.035)
	_banner_mat = _material(Color("586d71"))
	var flag := _mesh(_banner, cloth, Vector3(0.9, 2.2, 0), _banner_mat)
	flag.name = "Cloth"
	var crest := BoxMesh.new()
	crest.size = Vector3(0.14, 0.5, 0.045)
	_mesh(flag, crest, Vector3(0, 0, 0.03), _material(CampaignStyle.CREAM))

func _build_arrival(world: Node3D) -> void:
	# 起点用两座矮石墩与破旗建立归乡入口；尺寸小且位于行进线外。
	for side in [-1.0, 1.0]:
		var sf: float = side
		var at := _hero.position + Vector3(sf * 3.8, 0, 3.0)
		var stone := CylinderMesh.new()
		stone.top_radius = 0.45
		stone.bottom_radius = 0.6
		stone.height = 1.0 + (0.35 if sf > 0 else 0)
		stone.radial_segments = 5
		_mesh(self, stone, at + Vector3.UP * 0.5, _material(Color("8b9787")))
	# 远景保留现有场景的地标；这里不增实体障碍。
	var camera := world.get_node_or_null("IsometricCamera") as IsometricCamera
	var controller := world.get_node_or_null("HeroController") as HeroController
	if camera != null and controller != null:
		camera.target_distance = 38.0
		camera.fov = 60.0
		camera.follow_offset = Vector3(5, 0, -4)
		camera.set("_yaw_step", 0)
		controller.set_view_mode(SelectionManager.ViewMode.TOPDOWN)

func update_state(raiders: Array, ready_to_claim: bool, progress: float, complete: bool) -> void:
	var previous_target := _route_target
	_ready_to_claim = ready_to_claim
	_route_target = _base if ready_to_claim else null
	if not ready_to_claim and is_instance_valid(_hero):
		var best := INF
		for enemy in raiders:
			if not is_instance_valid(enemy) or (enemy as Pawn).is_dead_flag:
				continue
			var distance := _hero.position.distance_squared_to((enemy as Node3D).position)
			if distance < best:
				best = distance
				_route_target = enemy as Node3D
	if previous_target != _route_target:
		_redraw_route()
	if _capture_ring != null:
		_capture_ring.visible = ready_to_claim and not complete
		(_capture_ring.material_override as StandardMaterial3D).albedo_color = CampaignStyle.GOLD
	if _banner != null:
		_banner_mat.albedo_color = CampaignStyle.GOLD if ready_to_claim else Color("586d71")
		var cloth := _banner.get_node("Cloth") as MeshInstance3D
		cloth.position.y = lerpf(2.2, 4.3, progress)
	if complete:
		_route.multimesh.visible_instance_count = 0
		set_process(false)

func _process(delta: float) -> void:
	_time += delta
	_route_tick += delta
	if _ready_to_claim and _capture_ring != null:
		_capture_ring.scale = Vector3.ONE * (1.0 + sin(_time * 2.0) * 0.008)
	if _route_tick < 0.6:
		return
	_route_tick = 0
	_redraw_route()

func _redraw_route() -> void:
	_route.multimesh.visible_instance_count = 0
	if not is_instance_valid(_hero) or _hero.is_dead_flag or not is_instance_valid(_route_target) or _nav == null:
		return
	var target := _route_target.position
	if _ready_to_claim:
		# 终点落在收复圈靠主角的一侧，避开城堡本体的不可走地基。
		var away := (_hero.position - _base.position).normalized()
		target = _nav.snap_to_walkable(_base.position + away * 6.8)
	var path := _nav.get_world_path(_hero.position, target)
	var count := 0
	var distance := 1.5
	var from := _hero.position
	for point in path:
		var length := from.distance_to(point)
		if length < 0.01:
			continue
		while distance < length and count < 32:
			var at := from.lerp(point, distance / length)
			at.y = 0.08
			_route.multimesh.set_instance_transform(count, Transform3D(Basis.IDENTITY, at))
			count += 1
			distance += 1.6
		distance -= length
		from = point
		if count >= 32:
			break
	_route.multimesh.visible_instance_count = count

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = at
	item.material_override = material
	parent.add_child(item)
	return item
