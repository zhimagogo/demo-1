class_name ResourceNode
extends StaticBody3D

const NatureAssetsScript = preload("res://scripts/decor/NatureAssets.gd")
## 世界可采集资源节点（树 / 石）。主角亲自挥砍（第三人称左键连招顺带采集）
## 或战术俯瞰下右键下令小人前来采集。储量耗尽后自动消失。
## v3：harvest_carry 支持村民「背包搬运」采集（不入库，回城再交）；
##     储量下降时模型逐渐缩小，采伐进度一眼可读。

@export var yield_resource: StringName = &"wood"
@export var yield_amount: int = 5
@export var total_reserve: int = 50
@export var mesh_color: Color = Color.FOREST_GREEN
@export var mesh_size: Vector3 = Vector3(0.8, 2.0, 0.8)

var _current: int = 0
var _rig_scale: float = 1.0        # 原始模型 scale（setup 后记录，缩放在此基础上）


func _ready() -> void:
	_current = total_reserve
	add_to_group("resource_node")
	_setup_nodes()
	# v11 行走面：占格登记（树 / 石物理拾取盒 ≥1.8m，A* 必须把它当障碍绕行；
	# 初始 42 点挂树时 NavSystem 可能尚未建表，由其初始化统一登记，这里对动态补苗生效）
	_sync_nav_solid(true)


func _setup_nodes() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var box := BoxMesh.new()
	box.size = mesh_size
	mesh.mesh = box
	mesh.position.y = mesh_size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = mesh_color
	mesh.material_override = mat
	add_child(mesh)
	# 采集逻辑和点击碰撞保持独立，使用与环境一致的树木/矿石外观。
	var rig := BuildingModelRig.new()
	rig.name = "ResourceModel"
	add_child(rig)
	var is_wood := yield_resource == &"wood"
	var model := "tree_single_A" if is_wood else "rock_single_B"
	# v7 第三人称：树 / 石头按近地视角真实比例缩小（原 3.7/7.0 是俯瞰可读性尺寸，
	# 近地视角下会变成巨木怪石），树 ~7m、石 ~1.5m 更亲切。
	if rig.setup("res://assets/_PLACEHOLDER/nature/%s.gltf" % model, 2.6 if is_wood else 4.5):
		mesh.visible = false
		_rig_scale = rig.scale.x
		if is_wood:
			NatureAssetsScript.style_tree(rig)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	# 点击命中盒比视觉尺寸放大：脚印最小 1.8m、高度 +0.6m——原 0.8m 宽的树干盒在
	# 常规缩放下仅 ~11px 宽，右键下令采集几乎点不中（新手引导聚光点 +2.5m 也在盒外）。
	# 视觉 mesh 不变，仅放大物理/拾取盒；v11 起这些格同步标进 A* 障碍（NavSystem.set_resource_solid）。
	var pick_size := Vector3(
		maxf(mesh_size.x, 1.8),
		mesh_size.y + 0.6,
		maxf(mesh_size.z, 1.8))
	shape.size = pick_size
	col.shape = shape
	col.position.y = pick_size.y * 0.5
	add_child(col)


## 即时入库采集（主角亲自挥砍：采一下立刻进账）。返回实际采集数量。
## v22：采集经济暂时屏蔽（GameDefs.HARVEST_INCOME_ENABLED=false）——
## 不入账、不消耗储量、不触发采空消失，树/石只作为场景障碍与景观存在。
func harvest_by(_pawn: Node) -> int:
	if not GameDefs.HARVEST_INCOME_ENABLED or _current <= 0:
		return 0
	var amt: int = min(yield_amount, _current)
	_current -= amt
	ResourceManager.add(yield_resource, amt)
	_refresh_visual()
	if _current <= 0:
		_deplete()
	return amt


## 搬运采集（村民：采下来的先背在身上，回主城入库）。返回实际采到的数量。
## v22：同 harvest_by，采集屏蔽期间一律返回 0。
func harvest_carry(_pawn: Node, want: int) -> int:
	if not GameDefs.HARVEST_INCOME_ENABLED or _current <= 0 or want <= 0:
		return 0
	var amt: int = min(min(want, yield_amount), _current)
	_current -= amt
	_refresh_visual()
	if _current <= 0:
		_deplete()
	return amt


## 剩余储量比例（供分配器挑「还值得采」的点）。
func remaining_ratio() -> float:
	return float(_current) / float(max(total_reserve, 1))


func is_depleted() -> bool:
	return _current <= 0


## 储量越少模型越小（最低 45%）：远处即可读出哪些点快采空了。
func _refresh_visual() -> void:
	var ratio := remaining_ratio()
	var s := _rig_scale * (0.45 + 0.55 * ratio)
	var rig := get_node_or_null("ResourceModel") as Node3D
	if rig != null:
		rig.scale = Vector3(s, s, s)


## 耗尽：缩小消失（tween 由 tree timer 驱动，与 DeadState 同思路）；先解开 A* 占格。
func _deplete() -> void:
	_sync_nav_solid(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.4)
	tween.tween_callback(queue_free)


## v11 行走面：把本资源点占据的格子标进 / 移出 A* 障碍。
func _sync_nav_solid(solid: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nav := tree.get_first_node_in_group("nav_system") as NavSystem
	if nav != null:
		nav.set_resource_solid(self, solid)
