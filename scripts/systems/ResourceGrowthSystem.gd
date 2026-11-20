class_name ResourceGrowthSystem
extends Node
## ============================================================================
## 资源再生（v3 经济可持续）：资源点被采空后，野外会按稀缺度重新长出新的树 / 矿。
## - 每 REGROW_INTERVAL 秒检查一次：场上资源点低于 TARGET_COUNT 时补一株
## - 补点位置：城外（>24m）、湖外、不压建筑格 / 道路，且远离主城中心 18~56m 环带
## - 种类按稀缺度补：哪种少补哪种，木石长期均衡
## 42 个初始点在 Main.tscn 静态摆放；本系统只做「动态补充」，不负责初始布局。
## ============================================================================

const TARGET_COUNT: int = 42
const REGROW_INTERVAL: float = 18.0
const RESERVE_MIN: int = 40
const RESERVE_MAX: int = 70


func _ready() -> void:
	add_to_group("resource_growth")


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REGROW_INTERVAL:
		return
	_timer = 0.0
	var nodes := get_tree().get_nodes_in_group("resource_node")
	if nodes.size() >= TARGET_COUNT:
		return
	var spot := _pick_spot()
	if spot == Vector3.INF:
		return
	_spawn_node(_scarcer_kind(), spot)


var _timer: float = 0.0


## 哪种资源更少就补哪种。
func _scarcer_kind() -> StringName:
	var wood: int = 0
	var stone: int = 0
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n):
			continue
		if (n as Node).get("yield_resource") == &"wood":
			wood += 1
		else:
			stone += 1
	return &"wood" if wood <= stone else &"stone"


## 随机挑一个合法出生点（12 次重采样）：城外环带 + 干地 + 不压建筑 / 资源点。
## 返回 Vector3.INF 表示这次没找到（下个周期再试）。
func _pick_spot() -> Vector3:
	var grid := get_tree().get_first_node_in_group("grid_system") as GridSystem
	for _i in 12:
		var a := randf() * TAU
		var r := randf_range(24.0, 56.0)
		var p := Vector3(cos(a), 0.0, sin(a)) * r
		# 水域（湖 ∪ 河道 ∪ 水潭）里不补苗：v12 起河道 / 水潭与湖同属一片水系
		if WorldLayout.water_distance(Vector2(p.x, p.z)) < 0.6:
			continue
		# 主路上不长（贴着走可以，压着不行）
		if WorldLayout.road_distance(Vector2(p.x, p.z)) < 2.2:
			continue
		# 建筑格 / 地形阻挡上不长
		if grid == null:
			return p
		var cell := grid.world_to_grid(p)
		if not grid.is_inside(cell) or grid.terrain_cells.has(cell) or grid.is_occupied(cell):
			continue
		# 别贴着已有资源点（保持散布）
		var too_close := false
		for n in get_tree().get_nodes_in_group("resource_node"):
			if is_instance_valid(n) and n is Node3D and (n as Node3D).global_position.distance_to(p) < 5.0:
				too_close = true
				break
		if too_close:
			continue
		return p
	return Vector3.INF


func _spawn_node(kind: StringName, at: Vector3) -> void:
	var container := get_parent().get_node_or_null("ResourceNodes") as Node3D
	if container == null:
		return
	var node := ResourceNode.new()
	node.name = "Resource_Regrow_%d" % (Time.get_ticks_msec() % 100000)
	node.yield_resource = kind
	node.total_reserve = randi_range(RESERVE_MIN, RESERVE_MAX)
	node.mesh_color = Color(0.2, 0.55, 0.2) if kind == &"wood" else Color(0.55, 0.55, 0.58)
	node.mesh_size = Vector3(0.8, 2.2, 0.8) if kind == &"wood" else Vector3(1, 1, 1)
	node.position = at
	container.add_child(node)
	# 新苗从小长大（弹性动画，与收割缩水对称）
	node.scale = Vector3(0.05, 0.05, 0.05)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
