class_name LawnInteraction
extends Node
## 主角拨草：世界格保留短时弯曲记忆，64² 滚动小贴图供所有草簇一次采样。
## 只更新被踩过的少量格子，不扫描 MultiMesh 实例；暂停与调速均随游戏时间。
const FIELD_RESOLUTION := 64
const CELL_SIZE := 0.50
const FIELD_METERS := FIELD_RESOLUTION * CELL_SIZE
const BEND_RADIUS := 1.40
const RECOVERY_SECONDS := 0.80  # 完整回弹时长：到此衰减到 1%，低于清理阈值
const UPDATE_INTERVAL := 1.0 / 30.0
const TELEPORT_DISTANCE := 6.0
const EMPTY := Color(0.5, 0.5, 0.0, 1.0)

var hero: Hero
var _material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _cells: Dictionary = {}  # 世界格 → Vector3(弯曲向量 x/z, 压低强度)
var _origin_cell := Vector2i.ZERO
var _last_position := Vector3.INF
var _heading := Vector2(0.0, -1.0)
var _update_elapsed := 0.0


func setup(material: ShaderMaterial) -> void:
	_material = material
	_image = Image.create(FIELD_RESOLUTION, FIELD_RESOLUTION, false, Image.FORMAT_RGBA8)
	_image.fill(EMPTY)
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("bend_field", _texture)
	_material.set_shader_parameter("bend_field_size", FIELD_METERS)
	_material.set_shader_parameter("bend_radius", BEND_RADIUS)
	_material.set_shader_parameter("bend_enabled", false)


func _process(delta: float) -> void:
	if delta <= 0.0 or _material == null:
		return
	if not is_instance_valid(hero):
		hero = null
		for node in get_tree().get_nodes_in_group("player_unit"):
			if node is Hero:
				hero = node as Hero
				break
	var valid := is_instance_valid(hero) and not hero.is_dead_flag
	var position := hero.global_position if valid else _last_position
	# 脚边即时接触每渲染帧同步；历史场 30Hz 更新，减少 CPU / 贴图上传开销。
	var contact := valid and position.y < 0.65
	_material.set_shader_parameter("bend_body_position", position if position.is_finite() else Vector3.ZERO)
	_material.set_shader_parameter("bend_body_active", contact)
	_update_elapsed += delta
	if _update_elapsed < UPDATE_INTERVAL:
		return
	# 起跳离地后不继续压地面，已有草痕仍正常回弹。无主角时不在原点造假足迹。
	advance(_update_elapsed, position, contact)
	_update_elapsed = 0.0


## 测试/取景可手动推进；运行时只由本节点 _process 调用。
func advance(delta: float, position: Vector3, contact: bool = true) -> void:
	if delta <= 0.0 or _material == null:
		return
	var moved := Vector2.ZERO
	if position.is_finite() and _last_position.is_finite():
		moved = Vector2(position.x - _last_position.x, position.z - _last_position.z)
		if moved.length() > TELEPORT_DISTANCE:
			_cells.clear()
			moved = Vector2.ZERO
	if moved.length_squared() > 0.000001:
		_heading = _heading.lerp(moved.normalized(), 1.0 - exp(-delta * 18.0)).normalized()
		# 正反向折返时 lerp 中点可为零，直接采用实际运动方向。
		if _heading.length_squared() < 0.01:
			_heading = moved.normalized()
	var decay := pow(0.01, delta / RECOVERY_SECONDS)
	for cell: Vector2i in _cells.keys():
		var state: Vector3 = _cells[cell] * decay
		if state.z < 0.012:
			_cells.erase(cell)
		else:
			_cells[cell] = state
	if position.is_finite():
		# 正常移动沿小段补印，低帧率/3x 调速仍连续；传送已在上面截断，不连出长走廊。
		var steps := clampi(ceili(moved.length() / (CELL_SIZE * 0.75)), 1, 32)
		for i in range(1, steps + 1):
			var p := position - Vector3(moved.x, 0, moved.y) * (1.0 - float(i) / float(steps))
			if contact:
				_stamp(Vector2(p.x, p.z))
		_last_position = position
		_origin_cell = Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE)) - Vector2i.ONE * (FIELD_RESOLUTION / 2)
	_render_field()
	_material.set_shader_parameter("bend_enabled", not _cells.is_empty())
	_material.set_shader_parameter("bend_origin", Vector2(_origin_cell) * CELL_SIZE)
	_material.set_shader_parameter("bend_body_position", position if position.is_finite() else Vector3.ZERO)
	_material.set_shader_parameter("bend_body_direction", _heading)
	_material.set_shader_parameter("bend_body_active", contact and position.is_finite())


func _stamp(center: Vector2) -> void:
	var lo := Vector2i(((center - Vector2.ONE * BEND_RADIUS) / CELL_SIZE).floor())
	var hi := Vector2i(((center + Vector2.ONE * BEND_RADIUS) / CELL_SIZE).floor())
	var side := Vector2(-_heading.y, _heading.x)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var key := Vector2i(x, y)
			var offset := (Vector2(key) + Vector2.ONE * 0.5) * CELL_SIZE - center
			var distance := offset.length()
			if distance >= BEND_RADIUS:
				continue
			var pressure := 1.0 - smoothstep(BEND_RADIUS * 0.16, BEND_RADIUS, distance)
			var split := offset.dot(side)
			var direction := (offset / maxf(distance, 0.01) * 0.55 + side * (split / sqrt(split * split + 0.035)) * 0.85 + _heading * 0.16).normalized()
			var state := Vector3(direction.x * pressure, direction.y * pressure, pressure)
			var previous: Vector3 = _cells.get(key, Vector3.ZERO)
			if pressure >= previous.z:
				_cells[key] = state


func _render_field() -> void:
	_image.fill(EMPTY)
	for cell: Vector2i in _cells.keys():
		var pixel := cell - _origin_cell
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= FIELD_RESOLUTION or pixel.y >= FIELD_RESOLUTION:
			_cells.erase(cell)
			continue
		var state: Vector3 = _cells[cell]
		_image.set_pixelv(pixel, Color(state.x * 0.5 + 0.5, state.y * 0.5 + 0.5, state.z, 1.0))
	_texture.update(_image)


## 查询世界点所在格的实际记忆，用于生命周期/暂停/传送验证。
func state_at(point: Vector3) -> Vector3:
	var key := Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
	return _cells.get(key, Vector3.ZERO)
