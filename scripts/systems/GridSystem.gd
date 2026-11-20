class_name GridSystem
extends Node3D
## 方形网格系统：世界↔网格坐标转换、占用查询、debug 网格线。
## 网格中心对齐世界原点，cell∈[0,grid_size)，世界范围 [-half, +half]。

@export var cell_size: float = 2.0
@export var grid_size: Vector2i = Vector2i(32, 32)
@export var debug_visible: bool = true

var _occupants: Dictionary = {}   # Vector2i -> Building
var terrain_cells: Dictionary = {}   # 永久地形阻挡，与可拆除建筑分开保存
var road_cells: Dictionary = {}      # Vector2i -> Building；道路不是寻路障碍
const ROAD_NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var _debug_mesh: ImmediateMesh
var _debug_node: MeshInstance3D


func _ready() -> void:
	add_to_group("grid_system")
	_build_debug()
	if _debug_node:
		_debug_node.visible = debug_visible


func half_x() -> float:
	return float(grid_size.x) * cell_size * 0.5


func half_z() -> float:
	return float(grid_size.y) * cell_size * 0.5


func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_pos.x + half_x()) / cell_size),
		floori((world_pos.z + half_z()) / cell_size)
	)


func grid_to_world(cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5) * cell_size - half_x(),
		y,
		(float(cell.y) + 0.5) * cell_size - half_z()
	)


func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y


func is_occupied(cell: Vector2i) -> bool:
	return _occupants.has(cell) or terrain_cells.has(cell)


func can_place(cell: Vector2i, footprint: Vector2i) -> bool:
	for dx in footprint.x:
		for dy in footprint.y:
			var c := Vector2i(cell.x + dx, cell.y + dy)
			if not is_inside(c) or is_occupied(c):
				return false
	return true


func place(cell: Vector2i, footprint: Vector2i, building: Node) -> void:
	for dx in footprint.x:
		for dy in footprint.y:
			_occupants[Vector2i(cell.x + dx, cell.y + dy)] = building
	if building is Building and building.def != null and building.def.is_road:
		road_cells[cell] = building
		building.tree_exiting.connect(_on_road_exiting.bind(cell, building.get_instance_id()))
		_refresh_roads_near(cell)
		EventBus.road_changed.emit(self, cell, true)


func remove(cell: Vector2i, footprint: Vector2i) -> void:
	for dx in footprint.x:
		for dy in footprint.y:
			_occupants.erase(Vector2i(cell.x + dx, cell.y + dy))
	if road_cells.has(cell):
		road_cells.erase(cell)
		_refresh_roads_near(cell)
		EventBus.road_changed.emit(self, cell, false)


func has_road(cell: Vector2i) -> bool:
	var road = road_cells.get(cell)
	return is_instance_valid(road) and not road.is_queued_for_deletion()


## 位序固定为北、东、南、西；16 种邻接组合覆盖独立、尽头、直线、转角、丁字与十字。
func road_connection_mask(cell: Vector2i) -> int:
	var mask := 0
	for i in ROAD_NEIGHBORS.size():
		if has_road(cell + ROAD_NEIGHBORS[i]):
			mask |= 1 << i
	return mask


func _refresh_roads_near(cell: Vector2i) -> void:
	var cells: Array[Vector2i] = [cell]
	for offset in ROAD_NEIGHBORS:
		cells.append(cell + offset)
	for point in cells:
		if has_road(point):
			road_cells[point].update_road_connections(road_connection_mask(point))


## 直接释放道路也必须撤销占地、邻接与路径权重；旧实例不能误删同格新道路。
func _on_road_exiting(cell: Vector2i, owner_id: int) -> void:
	var road = road_cells.get(cell)
	if is_instance_valid(road) and road.get_instance_id() == owner_id:
		remove(cell, Vector2i.ONE)


func toggle_debug() -> void:
	debug_visible = not debug_visible
	if _debug_node:
		_debug_node.visible = debug_visible


func _build_debug() -> void:
	_debug_mesh = ImmediateMesh.new()
	_debug_node = MeshInstance3D.new()
	_debug_node.name = "GridDebug"
	_debug_node.mesh = _debug_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_node.material_override = mat
	add_child(_debug_node)
	_redraw_debug()


func _redraw_debug() -> void:
	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var hx := half_x()
	var hz := half_z()
	var y := 0.02
	for x in grid_size.x + 1:
		var fx := float(x) * cell_size - hx
		_debug_mesh.surface_add_vertex(Vector3(fx, y, -hz))
		_debug_mesh.surface_add_vertex(Vector3(fx, y, hz))
	for yy in grid_size.y + 1:
		var fz := float(yy) * cell_size - hz
		_debug_mesh.surface_add_vertex(Vector3(-hx, y, fz))
		_debug_mesh.surface_add_vertex(Vector3(hx, y, fz))
	_debug_mesh.surface_end()
