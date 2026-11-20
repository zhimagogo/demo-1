class_name BuildingModelRig
extends Node3D
## ============================================================================
## 建筑静态模型挂载组件（占位美术通道）。
## 运行时加载 .gltf/.glb 模型并挂到建筑本体之下；建筑无动画，故比 PawnModelRig 精简
## （去掉动画映射 / AnimationPlayer 逻辑）。
##
## 关键架构支点（务必保持）：NavSystem 用 PARSED_GEOMETRY_STATIC_COLLIDERS，
## NavMesh 只烘焙 CollisionShape3D、完全不读视觉 MeshInstance3D。所以建筑视觉模型
## 是「皮」——可任意 scale / offset，不污染寻路与单位碰撞（碰撞仍由 Building 的
## CollisionShape3D + mesh_size 负责）。若有人改 NavSystem 的 parsed_geometry_type，
## 这层解耦立刻失效（视觉变实心障碍、烘焙成本爆炸），故此依赖在此钉死。
##
## 与 PawnModelRig 刻意隔离：Pawn 走含动画的 PawnModelRig；本组件建筑专用。
## 两者各自维护 _load_glb_scene / _clear_top_level 副本，避免跨类调私有方法 + 隐式耦合。
##
## 加载策略同 PawnModelRig：优先 load()（编辑器自动导入的 PackedScene），
##   失败回退 GLTFDocument 运行时解析（.gltf + 外部 .bin + png 相对 URI 也能解析）。
## ============================================================================

var _model_root: Node3D = null
## v43 需求①：可复位入住染色记录。每项对应一个已 duplicate 的 surface：
##   { mi: MeshInstance3D, index: int, original: Material,
##     dup: BaseMaterial3D, base_color: Color,
##     base_emission_enabled: bool, base_emission: Color }
## 只在记录为空时采集（clear_occupancy_tint 后才会重新采集）——因此入住 / 空房来回切换
## 不会每次重复 duplicate 材质，也不会污染共享 atlas 材质。
var _tint_records: Array[Dictionary] = []
var _tint_color: Color = Color.WHITE


func has_model() -> bool:
	return _model_root != null


## 加载并挂载建筑模型。path 为空 / 加载失败返回 false（调用方保持 BoxMesh 占位）。
## model_scale: 整体缩放；face_offset_deg: 绕 Y 旋转修正（门朝相机）；height_offset: 垂直偏移（修正悬浮原点）。
func setup(path: String, model_scale: float = 1.0, face_offset_deg: float = 0.0, height_offset: float = 0.0) -> bool:
	clear_model()
	if path.is_empty():
		return false
	var scene := _load_glb_scene(path)
	if scene == null:
		push_warning("BuildingModelRig: 加载返回 null: %s" % path)
		return false
	_model_root = scene
	# 偏移放在 Rig 容器自身（而非导入模型根节点）：clear_model 时只需复位容器变换，
	# 无需触碰加载的 scene 内部；_clear_top_level 的递归根点也统一在容器子树。
	scale = Vector3.ONE * model_scale
	rotation = Vector3(0.0, deg_to_rad(face_offset_deg), 0.0)
	position.y = height_offset
	add_child(scene)
	# 防御性处理：外部场景若错误标记 top_level，会脱离建筑本体而停在世界原点。
	_clear_top_level(scene)
	return true


## 清理当前模型，支持运行时换装 / 定义重载。Rig 自身的本地变换（scale/rotation/position）同步复位。
func clear_model() -> void:
	# 模型即将整体释放，染色记录里的 MeshInstance / 材质副本随之失效；先丢弃记录，
	# 避免之后 clear_occupancy_tint 去访问已释放的模型。
	_tint_records.clear()
	_tint_color = Color.WHITE
	if is_instance_valid(_model_root):
		remove_child(_model_root)
		_model_root.queue_free()
	_model_root = null
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	position = Vector3.ZERO


# ---- 导入场景兼容 ----

## 整体染色（市集货栈色等）。逐 surface 复制材质后乘 albedo，
## 绝不直接改共享材质（会污染所有用该模型的建筑）。
func apply_tint(tint: Color) -> void:
	if _model_root == null or tint.is_equal_approx(Color.WHITE):
		return
	_apply_tint_recursive(_model_root, tint)


func _apply_tint_recursive(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var dm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dm.albedo_color = (mat as BaseMaterial3D).albedo_color * tint
					mi.set_surface_override_material(i, dm)
	for c in n.get_children():
		_apply_tint_recursive(c, tint)


# ---- v43 需求①：可复位入住染色（已入住暖色 / 空房还原）----
#
# 与上面的 apply_tint 的区别：apply_tint 一次性叠加、不可撤销；入住状态会随住户
# 出生 / 死亡 / 迁出反复切换，必须有可复位的接口：
#   · 首次 set_occupancy_tint 时逐 surface 记录「原始材质」并只 duplicate 一次；
#   · 之后重复 set 只改颜色（乘色 + 叠加 emission），不再产生新材质；
#   · clear_occupancy_tint 把原始材质放回 override（原始为 null 则清掉 override 还原默认），
#     共享 atlas 材质本体从未被改写，其它建筑完全不受影响。

## 应用 / 更新入住染色。tint 乘到每个 surface 的原始 albedo；emission 叠加暖自发光
## （Color.BLACK = 不改原材质的自发光）。无模型（BoxMesh 占位）时静默返回，
## 占位壳由调用方（Building）自行同步 albedo。
func set_occupancy_tint(tint: Color, emission: Color = Color.BLACK) -> void:
	if _model_root == null:
		return
	_tint_color = tint
	if _tint_records.is_empty():
		_collect_occupancy_tint_records(_model_root)
	var add_emission: bool = emission.r > 0.0 or emission.g > 0.0 or emission.b > 0.0
	for rec in _tint_records:
		var mi = rec["mi"]
		# 只做 is_instance_valid：模型子树可能在 setup / clear_model 期间被替换。
		if not is_instance_valid(mi):
			continue
		var dm := rec["dup"] as BaseMaterial3D
		if dm == null:
			continue
		dm.albedo_color = (rec["base_color"] as Color) * tint
		var base_emission := rec["base_emission"] as Color
		dm.emission_enabled = add_emission or bool(rec["base_emission_enabled"])
		dm.emission = Color(base_emission.r + emission.r, base_emission.g + emission.g,
			base_emission.b + emission.b, 1.0)


## 还原入住染色（空房 / 住户离开 / 拆房时调用）。恢复的是首次染色时记录到的原始材质，
## 不是白色——蓝顶小屋等自带配色回到原样。再次染色会重新采集一份副本。
func clear_occupancy_tint() -> void:
	if _tint_records.is_empty():
		_tint_color = Color.WHITE
		return
	for rec in _tint_records:
		var mi = rec["mi"]
		if is_instance_valid(mi):
			(mi as MeshInstance3D).set_surface_override_material(int(rec["index"]), rec["original"] as Material)
	_tint_records.clear()
	_tint_color = Color.WHITE


## 当前入住染色（未染色 = Color.WHITE）。测试查询用。
func occupancy_tint_color() -> Color:
	return _tint_color


## 是否处于染色状态（有记录且非白色）。
func has_occupancy_tint() -> bool:
	return not _tint_records.is_empty() and not _tint_color.is_equal_approx(Color.WHITE)


func _collect_occupancy_tint_records(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				# 原始材质 = 已有的 surface override（本组件 apply_tint 可能已经挂过）
				# 否则 = mesh 自带的共享材质。record 里 original 为 null 表示「原本没有 override」，
				# clear 时写回 null 让 surface 恢复到 mesh 自带材质——不留任何占用 override 的痕迹。
				var override_mat := mi.get_surface_override_material(i)
				var src_mat: Material = override_mat if override_mat != null else mesh.surface_get_material(i)
				if not (src_mat is BaseMaterial3D):
					continue
				var src := src_mat as BaseMaterial3D
				var dm := src.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(i, dm)
				_tint_records.append({
					"mi": mi,
					"index": i,
					"original": override_mat,
					"dup": dm,
					"base_color": src.albedo_color,
					"base_emission_enabled": src.emission_enabled,
					"base_emission": src.emission,
				})
	for c in n.get_children():
		_collect_occupancy_tint_records(c)


## 递归关掉 n 子树里所有 Node3D 的 top_level（top_level=true 会忽略父变换、脱离实体停在原点）。
func _clear_top_level(n: Node) -> int:
	var cnt := 0
	if n is Node3D and (n as Node3D).is_set_as_top_level():
		(n as Node3D).set_as_top_level(false)
		cnt += 1
	for c in n.get_children():
		cnt += _clear_top_level(c)
	return cnt


## 加载 .gltf/.glb 为场景。优先编辑器导入的 PackedScene，回退运行时 GLTFDocument 解析
## （.gltf + 外部 .bin + png 的相对 URI 由 append_from_file 以 .gltf 所在目录为基址解析）。
static func _load_glb_scene(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return res.instantiate() as Node3D
	# 回退：运行时解析原始 glTF（不依赖编辑器导入缓存）
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("BuildingModelRig: 解析模型失败 %s (err=%d)" % [path, err])
		return null
	return doc.generate_scene(state)
