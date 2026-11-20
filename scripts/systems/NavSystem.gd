class_name NavSystem
extends Node
## ============================================================================
## 运行时寻路系统。
##
## 世界是平面格子，建筑也严格吸附到 GridSystem，因此使用 AStarGrid2D 比运行时重烘焙
## 整张 3D NavMesh 更合适：建造/摧毁只修改受影响的几个格子，复杂度固定且不会分配
## Recast 的体素数据。对外保留 navmesh_updated 信号，避免 Pawn 状态机依赖具体实现。
##
## v6 寻路性能优化（三层）：
## 1. 同帧路径缓存：同一物理帧内相同 (起点格, 终格) 的查询直接复用 A* 结果——
##    攻城群冲同一目标 / 村民群赴同一资源点时，同帧 N 次查询只算 1 次。
## 2. 路径平滑（string-pulling）：A* 逐格航点经「格心连线视线检测」贪心拉直为
##    少量长直段。航点数骤降 → 每帧航点推进 / 朝向计算成本同步骤降，且单位走
##    斜线更自然（不再沿格心锯齿扭动）。
## 3. BFS 格吸附：最近可走格搜索从「逐环全扫」（最坏累积 O(地图边长²)）改为
##    8 邻域 BFS 分层扩散（每格只入队一次），湖心 / 建筑密集区吸附不再有尖峰。
## ============================================================================

signal navmesh_updated

const PAWN_CLEARANCE: float = 0.45 # capsule radius + collision margin

const CLEARANCE_OFFSETS: Array[Vector3] = [
	Vector3(-PAWN_CLEARANCE, 0, -PAWN_CLEARANCE), Vector3(-PAWN_CLEARANCE, 0, PAWN_CLEARANCE),
	Vector3(PAWN_CLEARANCE, 0, -PAWN_CLEARANCE), Vector3(PAWN_CLEARANCE, 0, PAWN_CLEARANCE),
]
const SMOOTH_MAX_LOS_STEPS: int = 512   # 单次视线检测的格子步数上限（防异常数据死循环）

var grid: GridSystem
var path_grid: AStarGrid2D
var road_grid: AStarGrid2D
var _road_frame_cache: Dictionary = {}
var _road_frame_smoothed: Dictionary = {}

# ---- 性能：同帧缓存与统计 ----
var _frame_cache: Dictionary = {}      # Vector4i(起格x, 起格y, 终格x, 终格y) -> Array[Vector2i] 原始格路径；平滑按需缓存
var _frame_lengths: Dictionary = {}
var _frame_smoothed: Dictionary = {}
var _obstacle_cells: Dictionary = {} # owner instance id -> registered cells
var _solid_counts: Dictionary = {} # overlapping dynamic obstacle reference counts
var _permanent_cells: Dictionary = {} # castle foundation; terrain remains in GridSystem
var stat_world_checks: int = 0
var _cache_frame: int = -1             # 缓存所属物理帧号；跨帧或占用变化即整体失效
var stat_astar_queries: int = 0        # 累计真实 A* 查询次数（性能诊断）
var stat_cache_hits: int = 0           # 累计同帧缓存命中次数（性能诊断）
var stat_waypoints_raw: int = 0        # 平滑前航点累计（诊断：看平滑压缩比）
var stat_waypoints_smoothed: int = 0   # 平滑后航点累计


func _ready() -> void:
	add_to_group("nav_system")
	grid = get_parent().get_node_or_null("GridSystem") as GridSystem
	if grid == null:
		push_error("NavSystem: 未找到 GridSystem，无法初始化格子寻路")
		return
	_setup_path_grid()
	EventBus.road_changed.connect(_on_roads_changed)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_removed.connect(_on_building_removed)


func _setup_path_grid() -> void:
	path_grid = AStarGrid2D.new()
	path_grid.region = Rect2i(Vector2i.ZERO, grid.grid_size)
	path_grid.cell_shape = AStarGrid2D.CELL_SHAPE_SQUARE
	# 禁止擦角穿过两块相邻建筑之间的尖角；与 Pawn 的 0.4 半径相匹配。
	path_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	path_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	path_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	path_grid.update()
	road_grid = AStarGrid2D.new()
	road_grid.region = path_grid.region
	road_grid.diagonal_mode = path_grid.diagonal_mode
	road_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	road_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	road_grid.update()
	# 草地成本 1.2、道路成本 1：与实际 +20% 移速一致，启发式仍是可采纳的下界。
	for x in grid.grid_size.x:
		for y in grid.grid_size.y:
			var c := Vector2i(x, y)
			road_grid.set_point_weight_scale(c, 1.0 if grid.has_road(c) else GameDefs.ROAD_SPEED_MULTIPLIER)
	for cell: Vector2i in grid.terrain_cells:
		path_grid.set_point_solid(cell, true)
		road_grid.set_point_solid(cell, true)
	# 主城在 Main._ready 中登记，先按其固定 4×4 地基预留，避免路径穿过城堡。
	var base_cell := grid.world_to_grid(Vector3.ZERO) - Vector2i(2, 2)
	for dx in 4:
		for dz in 4:
			_permanent_cells[base_cell + Vector2i(dx, dz)] = true
			path_grid.set_point_solid(base_cell + Vector2i(dx, dz), true)
			road_grid.set_point_solid(base_cell + Vector2i(dx, dz), true)
	# 系统后于 Buildings 容器创建；兼容热加载或未来预置建筑。
	for node in get_tree().get_nodes_in_group("building"):
		if node is Building:
			_set_building_solid(node as Building, true)
	# v11 行走面修复：资源点（树 / 石）的物理拾取盒 ≥1.8m 却不占格子——
	# 平滑后的长直段会径直穿过树干格，单位撞上去就永久卡住。把资源点周围
	# 「单位挤不过去」的格心标成障碍（初始 42 点在此统一登记；动态补苗 /
	# 采空由 ResourceNode 调 set_resource_solid 增量维护）。
	for node in get_tree().get_nodes_in_group("resource_node"):
		if node is ResourceNode:
			set_resource_solid(node as ResourceNode, true)


## 返回世界 XZ 平面路径。终点落在建筑内时，自动寻找到它最近的可抵达格，
## 让攻击/采集单位停在建筑或目标的外沿，而非卡在碰撞体上。
func get_world_path(from_world: Vector3, to_world: Vector3, prefer_roads: bool = false) -> PackedVector3Array:
	var result := PackedVector3Array()
	if path_grid == null or grid == null:
		result.append(to_world)
		return result
	var start := _nearest_walkable_cell(grid.world_to_grid(from_world), grid.world_to_grid(to_world))
	var target := _nearest_walkable_cell(grid.world_to_grid(to_world), start)
	if start == Vector2i(-1, -1) or target == Vector2i(-1, -1):
		return result
	var cells := _query_smoothed_cell_path(start, target, prefer_roads and not grid.road_cells.is_empty())
	if cells.is_empty():
		return result
	# Cached smoothing assumes cell centers. An off-center pawn cannot safely skip
	# its start anchor if that shortcut cuts a wall corner.
	var start_pos := grid.grid_to_world(start)
	if cells.size() > 1 and ((prefer_roads and from_world.distance_squared_to(start_pos) > 0.04) or not can_walk_segment(from_world, grid.grid_to_world(cells[1]))):
		result.append(start_pos)
	for i in range(1, cells.size()):
		result.append(grid.grid_to_world(cells[i]))
	var requested := grid.world_to_grid(to_world)
	var target_pos := grid.grid_to_world(target)
	if requested == target:
		# Exact points near a cell boundary may overlap an adjacent obstacle.
		# Keep precision when safe; otherwise use the safe center arrival point.
		var exact := Vector3(to_world.x, 0.0, to_world.z)
		var anchor := result[result.size() - 1] if not result.is_empty() else from_world
		if can_walk_segment(anchor, exact):
			if result.is_empty() or result[result.size() - 1].distance_squared_to(exact) > 0.01:
				result.append(exact)
		elif result.is_empty():
			result.append(target_pos)
	elif result.is_empty():
		result.append(target_pos)
	return result


## 起终点之间的实际 A* 路径长度（米）；不可达返回 INF。
## 供 AI 评估目标「路程成本」：攻城选目标时，直线近但隔湖 / 绕墙的目标路程远，
## 按真实路径距离选择可避免野怪锁定一个要绕大半张地图才能到的目标。
func get_path_length(from_world: Vector3, to_world: Vector3) -> float:
	if path_grid == null or grid == null:
		return from_world.distance_to(to_world)
	var start := _nearest_walkable_cell(grid.world_to_grid(from_world), grid.world_to_grid(to_world))
	var target := _nearest_walkable_cell(grid.world_to_grid(to_world), start)
	if start == Vector2i(-1, -1) or target == Vector2i(-1, -1):
		return INF
	_query_cell_path(start, target)
	return float(_frame_lengths.get(Vector4i(start.x, start.y, target.x, target.y), INF))


## 同帧共享原始格路径与长度；移动路径另走按需平滑。
func _query_cell_path(start: Vector2i, target: Vector2i, prefer_roads: bool = false) -> Array[Vector2i]:
	var frame := Engine.get_physics_frames()
	if _cache_frame != frame:
		_cache_frame = frame
		_frame_cache.clear()
		_frame_lengths.clear()
		_frame_smoothed.clear()
		_road_frame_cache.clear()
		_road_frame_smoothed.clear()
	var cache: Dictionary = _road_frame_cache if prefer_roads else _frame_cache
	var key := Vector4i(start.x, start.y, target.x, target.y)
	if cache.has(key):
		stat_cache_hits += 1
		var cached: Array[Vector2i] = cache[key]
		return cached
	stat_astar_queries += 1
	var ids: Array[Vector2i] = (road_grid if prefer_roads else path_grid).get_id_path(start, target, false)
	if ids.is_empty():
		if not prefer_roads:
			_frame_lengths[key] = INF
		cache[key] = ids
		return ids
	var length := 0.0
	for i in range(1, ids.size()):
		length += Vector2(ids[i] - ids[i - 1]).length() * grid.cell_size
	if not prefer_roads:
		_frame_lengths[key] = length
	cache[key] = ids
	return ids


## Siege scoring needs only length, so smoothing is lazy and shared only when
## somebody actually requests a movement route for this pair.
func _query_smoothed_cell_path(start: Vector2i, target: Vector2i, prefer_roads: bool = false) -> Array[Vector2i]:
	var ids := _query_cell_path(start, target, prefer_roads)
	if ids.is_empty():
		return ids
	var key := Vector4i(start.x, start.y, target.x, target.y)
	var cache: Dictionary = _road_frame_smoothed if prefer_roads else _frame_smoothed
	if cache.has(key):
		return cache[key]
	# 道路路线只合并共线段，保留路口拐点，避免普通视线平滑把沿路路径削成草地捷径。
	var smoothed := _smooth_road_cell_path(ids) if prefer_roads else _smooth_cell_path(ids)
	stat_waypoints_raw += ids.size()
	stat_waypoints_smoothed += smoothed.size()
	cache[key] = smoothed
	return smoothed


func _smooth_road_cell_path(ids: Array[Vector2i]) -> Array[Vector2i]:
	if ids.size() <= 2:
		return ids
	var out: Array[Vector2i] = [ids[0]]
	var anchor := 0
	for i in range(1, ids.size() - 1):
		if ids[i] - ids[i - 1] != ids[i + 1] - ids[i] or not _line_walkable(ids[anchor], ids[i + 1]):
			out.append(ids[i])
			anchor = i
	out.append(ids[ids.size() - 1])
	return out


## 用于出生点修正：出生在建筑占地上时，挪到最近的可走格中心。
func snap_to_walkable(raw: Vector3) -> Vector3:
	if path_grid == null or grid == null:
		return raw
	var cell := _nearest_walkable_cell(grid.world_to_grid(raw), grid.world_to_grid(raw))
	return grid.grid_to_world(cell) if cell != Vector2i(-1, -1) else raw


## 格子是否可供单位站立（图内且 A* 上非阻挡：湖 / 河 / 崖 / 建筑 / 资源 / 主城地基）。
## v36：击飞落点裁剪与「单位滞留水里」自救共用此判定，与寻路完全同口径。
func is_walkable_cell(cell: Vector2i) -> bool:
	return _is_walkable_cell(cell)


func _on_building_placed(node: Node, _cell: Vector2i) -> void:
	if node is Building and node.def != null and node.def.is_road:
		return   # 道路由 road_changed 更新成本，不重复广播障碍变化
	if node is Building:
		_set_building_solid(node as Building, true)
		_invalidate_frame_cache()
		navmesh_updated.emit()


func _on_building_removed(node: Node, _cell: Vector2i) -> void:
	if node is Building and node.def != null and node.def.is_road:
		return
	if node is Building:
		_set_building_solid(node as Building, false)
		_invalidate_frame_cache()
		navmesh_updated.emit()


## 占用变化后同帧缓存立即失效：旧占用下算出的路径不能再被本帧后续查询复用。
func _invalidate_frame_cache() -> void:
	_frame_cache.clear()
	_frame_lengths.clear()
	_frame_smoothed.clear()
	_road_frame_cache.clear()
	_road_frame_smoothed.clear()
	_cache_frame = -1


func _set_building_solid(building: Building, solid: bool) -> void:
	if path_grid == null or building.def == null or not building.def.bakes_into_navmesh:
		return
	var cells: Array[Vector2i] = []
	if solid:
		for dx in building.footprint.x:
			for dz in building.footprint.y:
				var cell := building.cell + Vector2i(dx, dz)
				if grid.is_inside(cell):
					cells.append(cell)
	_set_obstacle_cells(building, cells)


## Reference-counted ownership: removing a resource/building must not erase
## another resource, the castle or permanent terrain. No full-world rescans.
func _set_obstacle_cells(owner_node: Node, cells: Array[Vector2i]) -> void:
	var id := owner_node.get_instance_id()
	_release_obstacle(id)
	if cells.is_empty():
		return
	_obstacle_cells[id] = cells
	for cell in cells:
		_solid_counts[cell] = int(_solid_counts.get(cell, 0)) + 1
		path_grid.set_point_solid(cell, true)
		road_grid.set_point_solid(cell, true)
	var cleanup := _on_obstacle_exiting.bind(id)
	if not owner_node.tree_exiting.is_connected(cleanup):
		owner_node.tree_exiting.connect(cleanup)


func _release_obstacle(id: int) -> bool:
	if not _obstacle_cells.has(id):
		return false
	for cell: Vector2i in _obstacle_cells[id]:
		var count := int(_solid_counts.get(cell, 0)) - 1
		if count > 0:
			_solid_counts[cell] = count
		else:
			_solid_counts.erase(cell)
		var solid := count > 0 or grid.terrain_cells.has(cell) or _permanent_cells.has(cell)
		path_grid.set_point_solid(cell, solid)
		road_grid.set_point_solid(cell, solid)
	_obstacle_cells.erase(id)
	return true


func _on_obstacle_exiting(id: int) -> void:
	if is_inside_tree() and _release_obstacle(id):
		_invalidate_frame_cache()
		navmesh_updated.emit()


# ---- v11 行走面：资源点占格 ----

## 资源点采用实际拾取盒 XZ 半宽 + 0.65m 单位与转向余量登记格心。
## 方形盒的角也占格；每个资源单独持有格子，重叠、采空和直接释放均正确清理。
func set_resource_solid(node: ResourceNode, solid: bool) -> void:
	if path_grid == null or grid == null or node == null or not is_instance_valid(node):
		return
	var cells: Array[Vector2i] = []
	if solid:
		var center := node.global_position
		var half := Vector2(maxf(node.mesh_size.x, 1.8), maxf(node.mesh_size.z, 1.8)) * 0.5
		half += Vector2.ONE * 0.65 # capsule + turning margin; box, not circular footprint
		var lo := grid.world_to_grid(center - Vector3(half.x, 0, half.y))
		var hi := grid.world_to_grid(center + Vector3(half.x, 0, half.y))
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.y, hi.y + 1):
				var cell := Vector2i(x, z)
				var point := grid.grid_to_world(cell)
				if grid.is_inside(cell) and absf(point.x - center.x) <= half.x and absf(point.z - center.z) <= half.y:
					cells.append(cell)
	_set_obstacle_cells(node, cells)
	_invalidate_frame_cache()
	navmesh_updated.emit()


# ---- 最近可走格：8 邻域 BFS 分层扩散 ----

const _NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


## 搜索最近可走格。8 邻域 BFS 按切比雪夫距离分层扩散（与旧的逐环扫描同语义），
## 每格只入队一次，最坏也只访问全图各一格——大湖 / 建筑密集区不再有环扫尖峰。
## 同层（= 同切比雪夫半径的环）内取离 preference（来路一侧）最近的岸边格，保持原语义。
func _nearest_walkable_cell(requested: Vector2i, preference: Vector2i) -> Vector2i:
	if path_grid == null:
		return Vector2i(-1, -1)
	if _is_walkable_cell(requested):
		return requested
	var bounded := Vector2i(clampi(requested.x, 0, grid.grid_size.x - 1), clampi(requested.y, 0, grid.grid_size.y - 1))
	if _is_walkable_cell(bounded):
		return bounded
	var visited := { bounded: true }
	var layer: Array[Vector2i] = [bounded]
	while not layer.is_empty():
		var best := Vector2i(-1, -1)
		var best_distance := INF
		var next_layer: Array[Vector2i] = []
		for cell in layer:
			if _is_walkable_cell(cell):
				var distance := Vector2(cell).distance_squared_to(Vector2(preference))
				if distance < best_distance:
					best_distance = distance
					best = cell
			for dir in _NEIGHBORS_8:
				var n: Vector2i = cell + dir
				if not visited.has(n) and path_grid.is_in_boundsv(n):
					visited[n] = true
					next_layer.append(n)
		if best != Vector2i(-1, -1):
			return best
		layer = next_layer
	return Vector2i(-1, -1)


func _is_walkable_cell(cell: Vector2i) -> bool:
	return path_grid.is_in_boundsv(cell) and not path_grid.is_point_solid(cell)


# ---- 路径平滑（string-pulling）----

## 格心连线是否全程可走（Amanatides-Woo 栅格遍历）。对角穿越角点时检查两个
## 侧格 + 对角格，与 A* 的 DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES「禁擦角」语义一致，
## 保证平滑后的每一段都能不穿墙地走出来。
func _line_walkable(a: Vector2i, b: Vector2i) -> bool:
	return can_walk_segment(grid.grid_to_world(a), grid.grid_to_world(b))


## Test the swept pawn footprint, not just a zero-width center line. Four
## corner traces conservatively cover the capsule with its collision margin.
## Used only for route construction and short squad steering (no physics rays).
func can_walk_segment(a: Vector3, b: Vector3) -> bool:
	stat_world_checks += 1
	for offset in CLEARANCE_OFFSETS:
		if not _trace_walkable(a + offset, b + offset):
			return false
	return true


func _trace_walkable(a: Vector3, b: Vector3) -> bool:
	var start := grid.world_to_grid(a)
	var end := grid.world_to_grid(b)
	if not _is_walkable_cell(start) or not _is_walkable_cell(end):
		return false
	var origin := Vector2((a.x + grid.half_x()) / grid.cell_size, (a.z + grid.half_z()) / grid.cell_size)
	var diff := Vector2(b.x - a.x, b.z - a.z) / grid.cell_size
	var step_x := 1 if diff.x >= 0.0 else -1
	var step_y := 1 if diff.y >= 0.0 else -1
	var inv_x := absf(1.0 / diff.x) if absf(diff.x) > 0.000001 else INF
	var inv_y := absf(1.0 / diff.y) if absf(diff.y) > 0.000001 else INF
	var tx := (float(start.x + 1) - origin.x if step_x > 0 else origin.x - float(start.x)) * inv_x if inv_x != INF else INF
	var ty := (float(start.y + 1) - origin.y if step_y > 0 else origin.y - float(start.y)) * inv_y if inv_y != INF else INF
	var cell := start
	for i in SMOOTH_MAX_LOS_STEPS:
		if cell == end:
			return true
		if absf(tx - ty) < 0.000001:
			if not _is_walkable_cell(cell + Vector2i(step_x, 0)) or not _is_walkable_cell(cell + Vector2i(0, step_y)):
				return false
			cell += Vector2i(step_x, step_y)
			tx += inv_x
			ty += inv_y
		elif tx < ty:
			cell.x += step_x
			tx += inv_x
		else:
			cell.y += step_y
			ty += inv_y
		if not _is_walkable_cell(cell):
			return false
	return false


## string-pulling 平滑：从锚点贪心扩展到最远的视线可达航点，把逐格 A* 路径
## 压缩为少量长直段。每个航点至多被一次成功 + 一次失败的视线检测覆盖，
## 均摊 O(航点数 × 平均视线长)，64×64 图上远低于一次 A* 的成本。
func _smooth_cell_path(ids: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = [ids[0]]
	var i := 0
	var size := ids.size()
	while i < size - 1:
		var furthest := i + 1
		var j := i + 2
		while j < size:
			if _line_walkable(ids[i], ids[j]):
				furthest = j
				j += 1
			else:
				break
		out.append(ids[furthest])
		i = furthest
	return out


## 铺路 / 拆路同帧更新路径成本，所有单位立即作废旧路径；不改变任何障碍占用。
func _on_roads_changed(owner_grid: Node, cell: Vector2i, present: bool) -> void:
	if owner_grid != grid or road_grid == null or not road_grid.is_in_boundsv(cell):
		return
	road_grid.set_point_weight_scale(cell, 1.0 if present else GameDefs.ROAD_SPEED_MULTIPLIER)
	_invalidate_frame_cache()
	navmesh_updated.emit()
