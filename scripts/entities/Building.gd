class_name Building
extends StaticBody3D
## 已放置建筑。
## - 可被攻击（HealthComponent）
## - 产出建筑定时给 ResourceManager 增加资源
## - 酒馆（is_tavern）对馆旁友方小兵持续回血（v22）

@export var def: BuildingDef
var health: HealthComponent
var cell: Vector2i = Vector2i(-1, -1)   # 所占网格坐标（供 building_removed 信号回传）
var footprint: Vector2i = Vector2i.ONE  # 实际占地（含建造时旋转后的宽深），供格子寻路增删障碍
var resident: Pawn = null                # 房屋住户；每栋房屋当前提供一个床位

## v43 需求①：已入住房屋的视觉状态（纯表现层——不碰产出 / 床位 / 拆除 / 寻路 footprint）。
## 已入住 = 强暖色乘色（蓝屋顶一眼变暖棕/红）+ 暖自发光 + 门口小灯笼 + 夜间门口暖光；
## 空房 / 住户消失 = 还原原始材质、熄灯、收灯笼。
## 乘色偏「红多绿少蓝极少」：蓝屋顶乘完会明显偏暖棕，白墙偏金橙（纯 1.55/0.88/0.48 实测
## 在蓝屋顶上会偏橄榄绿、一眼不够暖，故把 G/B 压得更低）。
const OCCUPIED_TINT: Color = Color(1.8, 0.62, 0.25)
const OCCUPIED_EMISSION: Color = Color(0.21, 0.11, 0.035)
const OCCUPIED_LIGHT_NIGHT_ENERGY: float = 1.8
const OCCUPIED_LIGHT_RANGE: float = 4.5
const OCCUPIED_LIGHT_COLOR: Color = Color(1.0, 0.66, 0.36)
## 入住标记：门口小灯笼（唯一的低成本暖色标记；白天也亮，夜间由暖光补光）。
const OCCUPIED_LANTERN_COLOR: Color = Color(1.0, 0.62, 0.24)
## 门口挂点的竖向比例 / 前向外移距离（相对模型实际包围盒；v43 建筑随城池放大后固定米数
## 会陷进墙体，故按模型 AABB 推导，见 _occupancy_anchor）。
const OCCUPIED_LIGHT_HEIGHT_RATIO: float = 0.32
const OCCUPIED_LIGHT_FRONT_PAD: float = 0.55
const OCCUPIED_LANTERN_HEIGHT_RATIO: float = 0.44
const OCCUPIED_LANTERN_FRONT_PAD: float = 0.14

var _produce_timer: float = 0.0
var road_connections: int = 0
var _occupancy_light: OmniLight3D = null   # 门口暖光（节点只建一次，切换只改 visible / energy）
var _occupancy_lantern: MeshInstance3D = null   # 门口小灯笼（节点只建一次，切换只改 visible）
var _occupied_visual: bool = false         # 当前外观是否处于已入住态
var _placeholder_base_color: Color = Color.WHITE   # 占位 BoxMesh 的原始 albedo（可复位基础）
var _placeholder_base_valid: bool = false


func _ready() -> void:
	_setup_nodes()
	_apply_def()
	add_to_group("road" if def != null and def.is_road else "building")
	if _is_house():
		add_to_group("house")
	if _is_tavern():
		add_to_group("tavern")
	if _is_dragon_garden():
		add_to_group("dragon_garden")
	# collision_layer = 1：参与地面物理碰撞。bakes_into_navmesh 控制格子寻路是否把该建筑视为障碍
	# （墙、房屋、酒馆均为 true，单位须绕行）。
	collision_layer = 1 if (def != null and def.bakes_into_navmesh) else 0
	collision_mask = 1
	# 物理本体不参与点击拾取（历史遗留自兵营时代；保持 false 避免碰撞体抢输入事件）。
	input_ray_pickable = false
	# 房屋即使被改成零产出也要跑 _process：入住视觉（住户死亡当帧复位 / 昼夜暖光）靠它维持。
	var need_process: bool = _has_producer() or _is_tavern() or _is_house()
	set_process(need_process)


func _setup_nodes() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	mesh.mesh = BoxMesh.new()
	add_child(mesh)

	# 物理碰撞体（与 mesh 同尺寸）：NavMesh 烘焙前提 + 单位撞墙
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = BoxShape3D.new()
	add_child(col)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	add_child(health)
	health.died.connect(_on_died)

	# 建筑静态模型挂载点（所有建筑都有；_apply_def 按需加载并隐藏 BoxMesh 占位皮）
	var rig := BuildingModelRig.new()
	rig.name = "ModelRig"
	add_child(rig)

	# v43 需求①：只有房屋需要入住暖光 / 小灯笼（其他建筑零开销）；节点只建一次，
	# 入住 / 空房 / 昼夜只切换 visible 与 light_energy —— 绝不在 _process 里重建节点。
	if _is_house():
		_ensure_occupancy_light()
		_ensure_occupancy_lantern()


func _apply_def() -> void:
	if def == null:
		return
	if def.is_road:
		var road_mesh := $MeshInstance3D as MeshInstance3D
		var plane := PlaneMesh.new()
		plane.size = Vector2(def.mesh_size.x, def.mesh_size.z)
		road_mesh.mesh = plane
		road_mesh.position.y = 0.035
		road_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var road_mat := ShaderMaterial.new()
		road_mat.shader = preload("res://assets/shaders/dirt_road.gdshader")
		road_mesh.material_override = road_mat
		($CollisionShape3D as CollisionShape3D).disabled = true
		health.max_hp = def.max_hp
		health.current_hp = def.max_hp
		return
	var mesh := $MeshInstance3D as MeshInstance3D
	(mesh.mesh as BoxMesh).size = def.mesh_size
	mesh.position.y = def.mesh_size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = def.mesh_color
	mesh.material_override = mat
	_placeholder_base_valid = false   # 新材质 → 入住染色重新记录基础色

	# 同步碰撞体尺寸/位置（与 mesh 对齐）
	var col := $CollisionShape3D as CollisionShape3D
	(col.shape as BoxShape3D).size = def.mesh_size
	col.position.y = def.mesh_size.y * 0.5

	health.max_hp = def.max_hp
	health.current_hp = def.max_hp

	# 静态模型：有 model_path 则加载并隐藏 BoxMesh 占位皮；失败 / 无路径则保持 BoxMesh。
	# 碰撞体（CollisionShape3D）尺寸不变 → 格子寻路（按 footprint）、单位碰撞、占地全不受影响。
	var model_rig := get_node_or_null("ModelRig") as BuildingModelRig
	if model_rig != null:
		if def.model_path != "" and model_rig.setup(def.model_path, def.model_scale, def.model_face_offset_deg, def.model_height_offset):
			var placeholder := $MeshInstance3D as MeshInstance3D
			if placeholder != null:
				placeholder.visible = false
		else:
			model_rig.clear_model()   # 加载失败 / 无路径 → 回退 BoxMesh 占位
	# def 重设 / 模型重挂后同步入住外观（例如入住后才热更 def，暖色与暖光要挂到新模型上）
	_refresh_occupancy_visual()


func update_road_connections(mask: int) -> void:
	road_connections = mask
	var visual := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if visual != null and visual.material_override is ShaderMaterial:
		(visual.material_override as ShaderMaterial).set_shader_parameter("connections", mask)


func _process(delta: float) -> void:
	if def == null:
		return
	if _has_producer():
		_produce_timer += delta
		if _produce_timer >= def.producer_interval:
			_produce_timer = 0.0
			ResourceManager.add(def.producer_resource, def.producer_amount)
	if _is_tavern():
		_tavern_heal(delta)
	if _is_house():
		_update_occupancy_visual()


## 酒馆回血光环（v22）：heal_radius 内的友方小兵每秒回 heal_per_sec 血。
## 只作用于 Soldier（主角有自己的成长/复活线，流民非战斗单位不驻留馆旁）。
func _tavern_heal(delta: float) -> void:
	if def.heal_per_sec <= 0.0 or def.heal_radius <= 0.0:
		return
	var amount: float = def.heal_per_sec * delta
	for u in get_tree().get_nodes_in_group("player_unit"):
		if u is Soldier and is_instance_valid(u) and not (u as Soldier).is_dead_flag:
			var s := u as Soldier
			if global_position.distance_to(s.global_position) <= def.heal_radius:
				var was_hurt: bool = s.health.current_hp < s.health.max_hp
				s.health.heal(amount)
				# v27：治疗荧光——正在回血的士兵身上冒绿色光点（节流 1.2s/人，满血不冒）
				if was_hurt and s.health.current_hp > 0.0:
					VFXManager.spawn_effect(&"heal_mote", s.global_position + Vector3(0.0, 0.8, 0.0), 0.0,
						{"throttle_key": s.get_instance_id(), "throttle_time": 1.2})


func _has_producer() -> bool:
	return def != null and def.producer_amount > 0 and String(def.producer_resource) != ""


func _is_house() -> bool:
	return def != null and def.id == &"house"


func _is_tavern() -> bool:
	return def != null and def.is_tavern


func _is_dragon_garden() -> bool:
	return def != null and def.is_dragon_garden


func has_vacancy() -> bool:
	return _is_house() and (resident == null or not is_instance_valid(resident))


func assign_resident(pawn: Pawn) -> void:
	if not has_vacancy() or pawn == null:
		return
	resident = pawn
	# 住户离树（士兵死亡 queue_free / 被移除）→ 立即恢复空房外观。tree_exiting 在节点
	# 仍有效时触发；节点真正释放后 Godot 自动断开该连接，无需额外清理。
	if not pawn.tree_exiting.is_connected(_on_resident_tree_exiting):
		pawn.tree_exiting.connect(_on_resident_tree_exiting)
	if pawn is Soldier:
		(pawn as Soldier).assign_home(self)
	_refresh_occupancy_visual()


## 是否已入住（公开查询，供测试 / UI）：住户死亡当帧起即视为空房，
## 不必等尸体 0.6s 缩小淡出后 queue_free。已释放引用只经 is_instance_valid 判断。
func is_occupied() -> bool:
	if not _is_house() or resident == null:
		return false
	if not is_instance_valid(resident):
		return false
	return not resident.is_dead_flag


## 住户离树回调：只清引用 + 复位视觉，不读取住户数据（避免访问正在释放的实例）。
func _on_resident_tree_exiting() -> void:
	resident = null
	_refresh_occupancy_visual()


## 每帧维持入住外观：住户死亡当帧回空房色（尸体还要淡出 0.6s 才真正释放），
## 已入住时按昼夜切换门口暖光。只在状态变化时写视觉，不重建任何节点。
func _update_occupancy_visual() -> void:
	var occupied := is_occupied()
	if occupied != _occupied_visual:
		_refresh_occupancy_visual()
	elif occupied:
		_sync_occupancy_light()


## 根据当前住户状态整体复位视觉：静态模型（可复位染色）/ 占位 BoxMesh albedo /
## 门口小灯笼 / 门口暖光。
func _refresh_occupancy_visual() -> void:
	_occupied_visual = is_occupied()
	if _is_house():
		# def 在 _ready 后才赋值时的补建（正常路径已在 _setup_nodes 建好）
		_ensure_occupancy_light()
		_ensure_occupancy_lantern()
		# 模型尺寸可能在 setup / def 重设后变化：每次刷新按实际包围盒重挂门口挂点。
		if _occupancy_light != null and is_instance_valid(_occupancy_light):
			_occupancy_light.position = _occupancy_anchor(
				OCCUPIED_LIGHT_HEIGHT_RATIO, OCCUPIED_LIGHT_FRONT_PAD)
		if _occupancy_lantern != null and is_instance_valid(_occupancy_lantern):
			_occupancy_lantern.position = _occupancy_anchor(
				OCCUPIED_LANTERN_HEIGHT_RATIO, OCCUPIED_LANTERN_FRONT_PAD)
	_apply_placeholder_tint(_occupied_visual)
	var rig := get_node_or_null("ModelRig") as BuildingModelRig
	if rig != null:
		if _occupied_visual:
			rig.set_occupancy_tint(OCCUPIED_TINT, OCCUPIED_EMISSION)
		else:
			rig.clear_occupancy_tint()
	if _occupancy_lantern != null and is_instance_valid(_occupancy_lantern):
		_occupancy_lantern.visible = _occupied_visual
	_sync_occupancy_light()


## 占位 BoxMesh 的 albedo 与静态模型同步变色（模型加载失败 / 无 model_path 时的回退皮）。
## 还原用首次记录的基础色，不写死 def.mesh_color。
func _apply_placeholder_tint(occupied: bool) -> void:
	if def == null or def.is_road:
		return
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if not _placeholder_base_valid:
		_placeholder_base_color = mat.albedo_color
		_placeholder_base_valid = true
	mat.albedo_color = _placeholder_base_color * (OCCUPIED_TINT if occupied else Color.WHITE)


## 门口挂点：从模型实际包围盒推「正面（+Z 门面）外沿」——高度按比例、Z 向外移一点。
## 无模型（占位 BoxMesh / 模型未挂）时用 def.mesh_size 近似，保证任何路径都有合理挂点。
## v43 房屋/酒馆随城池比例放大后写死米数会陷进墙体，故不采用固定 offset。
func _occupancy_anchor(height_ratio: float, front_pad: float) -> Vector3:
	var bounds := _model_local_bounds()
	var front_z: float = 1.0
	var base_y: float = 0.0
	var height: float = 1.0
	if bounds.size != Vector3.ZERO:
		front_z = bounds.end.z
		base_y = bounds.position.y
		height = bounds.size.y
	elif def != null:
		front_z = def.mesh_size.z * 0.5
		height = def.mesh_size.y
	return Vector3(0.0, base_y + height * height_ratio, front_z + front_pad)


## 模型在「建筑本地空间」里的合并 AABB（用于门口挂点；只读视觉网格，不影响碰撞 / 寻路）。
func _model_local_bounds() -> AABB:
	var rig := get_node_or_null("ModelRig") as BuildingModelRig
	if rig == null or not rig.has_model():
		return AABB()
	var meshes: Array[Node] = []
	_collect_mesh_instances(rig, meshes)
	var min_p := Vector3.INF
	var max_p := -Vector3.INF
	var found := false
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var gb: AABB = mi.global_transform * mi.mesh.get_aabb()
		for i in 8:
			var local := to_local(gb.get_endpoint(i))
			min_p = min_p.min(local)
			max_p = max_p.max(local)
			found = true
	return AABB(min_p, max_p - min_p) if found else AABB()


func _collect_mesh_instances(root: Node, out: Array[Node]) -> void:
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		_collect_mesh_instances(c, out)


## 门口暖光节点：懒建一次（房屋专用）。def 在 _ready 之后才赋值也能补建，但绝不每帧重建。
func _ensure_occupancy_light() -> void:
	if _occupancy_light != null and is_instance_valid(_occupancy_light):
		return
	var light := OmniLight3D.new()
	light.name = "OccupancyLight"
	light.position = _occupancy_anchor(OCCUPIED_LIGHT_HEIGHT_RATIO, OCCUPIED_LIGHT_FRONT_PAD)
	light.light_color = OCCUPIED_LIGHT_COLOR
	light.omni_range = OCCUPIED_LIGHT_RANGE
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.visible = false
	add_child(light)
	_occupancy_light = light


## 门口小灯笼：入住房屋唯一的额外暖色标记（低成本：单个低模球 + 自发光材质，无贴图 / 无灯光）。
## 节点只建一次，白天也亮；夜间由 OccupancyLight 在门口再补一圈暖光。
func _ensure_occupancy_lantern() -> void:
	if _occupancy_lantern != null and is_instance_valid(_occupancy_lantern):
		return
	var lantern := MeshInstance3D.new()
	lantern.name = "OccupancyLantern"
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.30
	sphere.radial_segments = 10
	sphere.rings = 5
	lantern.mesh = sphere
	lantern.position = _occupancy_anchor(OCCUPIED_LANTERN_HEIGHT_RATIO, OCCUPIED_LANTERN_FRONT_PAD)
	lantern.scale = Vector3(1.0, 1.15, 1.0)
	lantern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = OCCUPIED_LANTERN_COLOR
	# 自发光保证白天也醒目（不依赖夜间暖光）；能量压在 2.0，别把门口烧成白块。
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.48, 0.12)
	mat.emission_energy_multiplier = 2.0
	lantern.material_override = mat
	lantern.visible = false
	add_child(lantern)
	_occupancy_lantern = lantern


## 门口暖光：仅「房屋 + 已入住 + 夜间（TimeManager.is_night()）」亮；白天 / 空房熄灭。
func _sync_occupancy_light() -> void:
	var light := _occupancy_light
	if light == null or not is_instance_valid(light):
		return
	var on: bool = _occupied_visual and _is_house() and TimeManager.is_night()
	if light.visible != on:
		light.visible = on
	light.light_energy = OCCUPIED_LIGHT_NIGHT_ENERGY if on else 0.0


func _on_died() -> void:
	var name_str: String = def.display_name if def != null else "建筑"
	EventBus.game_message.emit("建筑被摧毁：%s" % name_str, Color.ORANGE_RED)
	AudioManager.play_sfx(&"building_destroyed", global_position)
	# v27：倒塌尘爆——大股尘土 + 暗金冲击环（旧版一小撮火星毫无「塌了」的分量）
	VFXManager.spawn_effect(&"build_dust", global_position + Vector3(0.0, 1.2, 0.0), 0.0,
		{"amount": 30, "lifetime": 0.8, "throttle_key": get_instance_id()})
	VFXManager.spawn_effect(&"hit_ring", global_position + Vector3(0.0, 0.4, 0.0), 0.0,
		{"color": Color(0.85, 0.72, 0.5), "throttle_key": get_instance_id()})
	# queue_free 前发信号，NavSystem 立即开放对应的格子占用。
	EventBus.building_removed.emit(self, cell)
	queue_free()
