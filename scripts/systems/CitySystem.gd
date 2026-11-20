class_name CitySystem
extends Node3D
## ============================================================================
## 主城区域系统：以基地（世界原点）为中心的轴对齐矩形安全区。
## 职责：① 建造合法性（仅城内可建）② 野怪屏障（野怪不进城索敌/追击）
##      ③ 士兵城内生活锚点（回血点 / 闲逛点 / 休息点）④ 可视边界框。
## 纯空间查询、不依赖格子；通过分组 "city_system" 供任意节点懒加载取回
## （get_tree().get_first_node_in_group("city_system")）。
## ============================================================================

@export var city_half: float = 26.0          # 半边长（米）；主城 XZ 范围 [-half,+half]，52×52m = 26×26 格
## v43：王城 20m → 26m 半边长（需求③a 城池与房屋比例扩大）；Main.tscn 与 WorldLayout.CITY_HALF 同步。
## 主城是矩形而非圆：野怪环采样 min_r 必须 ≥ half*√2 ≈ 36.8（WildlifeSpawner.spawn_min_r=40）。
@export var border_color: Color = Color(0.4, 0.9, 1.0, 0.85)
@export var border_visible: bool = true

var _border_mesh: ImmediateMesh
var _border_node: MeshInstance3D


func _ready() -> void:
	add_to_group("city_system")
	_build_border()


# ---- 空间查询 ----

## 世界坐标是否在主城内（仅看 XZ 平面）。
func is_in_city(pos: Vector3) -> bool:
	return absf(pos.x) <= city_half and absf(pos.z) <= city_half


## Project out of the nearest side, with a buffer for navigation/arrival tolerance.
func outside_point(pos: Vector3, margin: float = 1.0) -> Vector3:
	var result := pos
	var edge := city_half + margin
	if absf(pos.x) > edge or absf(pos.z) > edge:
		return result
	if absf(pos.x) >= absf(pos.z):
		result.x = edge * (-1.0 if pos.x < 0.0 else 1.0)
	else:
		result.z = edge * (-1.0 if pos.z < 0.0 else 1.0)
	return result


## Segment/rectangle slab test, including corners. Outside endpoints alone
## do not guarantee that a smoothed path stays outside a rectangular city.
func segment_crosses_city(a: Vector3, b: Vector3, margin: float = 0.0) -> bool:
	var low := 0.0
	var high := 1.0
	var edge := city_half + margin
	for axis in [0, 2]:
		var start: float = a[axis]
		var diff: float = b[axis] - start
		if absf(diff) < 0.00001:
			if absf(start) > edge:
				return false
		else:
			var t1 := (-edge - start) / diff
			var t2 := (edge - start) / diff
			low = maxf(low, minf(t1, t2))
			high = minf(high, maxf(t1, t2))
			if low > high:
				return false
	return true


## 世界 AABB（XZ min/max）是否整体落在城内（供 BuildSystem 校验多格 footprint）。
func contains_rect_xz(world_min: Vector3, world_max: Vector3) -> bool:
	return world_min.x >= -city_half and world_max.x <= city_half \
		and world_min.z >= -city_half and world_max.z <= city_half


## 主城包围盒（XZ）。
func bounds_aabb() -> AABB:
	return AABB(Vector3(-city_half, 0.0, -city_half), Vector3(city_half * 2.0, 0.0, city_half * 2.0))


## 城内随机点（避开边界 margin 米，防止贴墙卡碰撞）。
func random_point_in_city(margin: float = 2.0) -> Vector3:
	var r := maxf(0.0, city_half - margin)
	return Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))


## 城外圆环随机点（min_r..max_r 半径），用于野怪出生 / 士兵城外巡逻。
## 注意：主城是矩形而非圆，圆环上对角方向的点会落进矩形角内（half*√2 ≈ 19.8 > half），
## 故对落在矩形内的点拒绝重采；min_r 应 ≥ half*√2 才能基本一次命中。
func random_point_outside(min_r: float, max_r: float) -> Vector3:
	for _i in 12:
		var a := randf() * TAU
		var r := randf_range(min_r, max_r)
		var p := Vector3(cos(a), 0.0, sin(a)) * r
		if not is_in_city(p):
			return p
	# 兜底：取必然在矩形外的角外侧点
	return Vector3(city_half + 3.0, 0.0, city_half + 3.0)


## pos 附近（step_min..step_max 距离）的城外随机点：供野怪在城外「小步局部漫游」，
## 避免跨越大半个圆环导致寻路横穿主城。落在城内的候选被拒绝重采。
func random_outside_near(pos: Vector3, step_min: float = 4.0, step_max: float = 9.0) -> Vector3:
	for _i in 10:
		var a := randf() * TAU
		var r := randf_range(step_min, step_max)
		var p := pos + Vector3(cos(a), 0.0, sin(a)) * r
		if not is_in_city(p):
			return p
	# 兜底：沿「原点→pos」方向退到矩形外（pos 在城内时也能推出城）
	var out_dir := Vector3(pos.x, 0.0, pos.z)
	if out_dir.length_squared() < 0.01:
		out_dir = Vector3(1.0, 0.0, 0.0)
	else:
		out_dir = out_dir.normalized()
	# 矩形非圆：沿方向 (dx,dz) 退到城外需 r > half/max(|dx|,|dz|)（对角方向要退更远，
	# 否则会落进矩形角内）。加 buffer 确保在外。
	var r_out := city_half / maxf(absf(out_dir.x), absf(out_dir.z)) + 3.0
	return out_dir * r_out


## 任意点投影到主城边界（城外点取最近边界点；城内点取最近边界点）。
func nearest_border_point(pos: Vector3) -> Vector3:
	return Vector3(clampf(pos.x, -city_half, city_half), 0.0, clampf(pos.z, -city_half, city_half))


# ---- 可视边界 ----

func toggle_border() -> void:
	border_visible = not border_visible
	if _border_node:
		_border_node.visible = border_visible


func _build_border() -> void:
	_border_mesh = ImmediateMesh.new()
	_border_node = MeshInstance3D.new()
	_border_node.name = "CityBorder"
	_border_node.mesh = _border_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = border_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_node.material_override = mat
	_border_node.visible = border_visible
	add_child(_border_node)
	_redraw_border()


func _redraw_border() -> void:
	_border_mesh.clear_surfaces()
	_border_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var h := city_half
	var y := 0.05
	# 矩形四边
	_border_mesh.surface_add_vertex(Vector3(-h, y, -h))
	_border_mesh.surface_add_vertex(Vector3( h, y, -h))
	_border_mesh.surface_add_vertex(Vector3( h, y, -h))
	_border_mesh.surface_add_vertex(Vector3( h, y,  h))
	_border_mesh.surface_add_vertex(Vector3( h, y,  h))
	_border_mesh.surface_add_vertex(Vector3(-h, y,  h))
	_border_mesh.surface_add_vertex(Vector3(-h, y,  h))
	_border_mesh.surface_add_vertex(Vector3(-h, y, -h))
	_border_mesh.surface_end()
