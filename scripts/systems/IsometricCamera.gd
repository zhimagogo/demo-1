class_name IsometricCamera
extends Camera3D
## ============================================================================
## 等距俯视相机（正向视角：网格与屏幕对齐，无 45° 斜置）
## - WASD + 屏幕边缘平移（在相机水平面，随视角旋转自适应）
## - 滚轮缩放（沿视线推拉，min~max 距离；v42 起阻尼平滑推拉，不再一格一格跳）
## - Q/E 按 90° 档旋转视角
## - 位置被 clamp 到地图边界
## ============================================================================

@export_group("Pan")
@export var pan_speed: float = 30.0
@export var edge_pan: bool = true
@export var edge_margin: int = 20
@export var bounds: AABB = AABB(Vector3(-30.0, 0.0, -30.0), Vector3(60.0, 40.0, 60.0))

@export_group("Zoom")
## 每档滚轮的目标视距变化。真实视距由 _distance 阻尼收敛到 target_distance：
## 因此单格滚轮也是「推拉动画」而不是瞬间跳 5m（v42 需求：推拉要平滑）。
@export var zoom_step: float = 4.0
## 视距收敛速率（1/s，帧率无关）：越大越跟手，越小越绵。
@export var zoom_smoothing: float = 9.0
@export var min_distance: float = 12.0
## v43：王城扩到 52×52m、湖泊东迁后，最远视距 55→68m 才能把城与湖一起框进画面；
## target_distance 默认 44 保留（旧测试 / 截图工具按 44 取景）。
@export var max_distance: float = 68.0
@export var target_distance: float = 44.0

@export_group("Rotate")
@export var rotate_steps: int = 4
var _yaw_step: int = 1   # 原版默认视角（上一版迭代定下的画面朝向，v3.1 曾误改为 0 已恢复；小地图动态随动，任意朝向都一致）

const BASE_PITCH: float = -50.0     # 俯视倾角
const BASE_YAW_DEG: float = 0.0     # 基础偏角：0=正向（网格对齐屏幕）；Q/E 仍可 90° 档旋转

var _focus: Vector3 = Vector3.ZERO  # 相机注视的地面点
var follow_offset := Vector3.ZERO    # 剧情关可把镜头略向前方取景
var follow_target: Node3D = null    # 俯视角主控（TOPDOWN）时跟随主角：禁 WASD/边缘平移，焦点 lerp 贴住目标
var _distance: float = 44.0          # 实际视距（每帧阻尼收敛到 target_distance；v42 平滑推拉）

# 震屏（v3）：Boss 登场 / 建筑被毁等重事件的打击感。衰减式随机偏移。
var _shake_strength: float = 0.0
var _shake_decay: float = 3.2


## 触发一次震屏。strength ≈ 最大偏移米数；duration 越长衰减越慢。
func shake(strength: float, duration: float = 0.5) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_decay = 3.2 / maxf(duration, 0.15)


func _ready() -> void:
	current = true
	_distance = target_distance
	_apply_transform()


## 立即把实际视距对齐目标值（跳过阻尼收敛）。截图 / 剧情定场 / 测试摆位用；
## 玩家滚轮不走这里 —— 那必须保留平滑推拉。
func snap_distance() -> void:
	_distance = target_distance
	_apply_transform()


func _process(delta: float) -> void:
	# 震屏强度指数衰减
	if _shake_strength > 0.005:
		_shake_strength *= exp(-delta * _shake_decay)
	else:
		_shake_strength = 0.0
	# v42 平滑推拉：滚轮只改目标视距，真实视距在这逐帧阻尼收敛（帧率无关）。
	# 早期版本直接把 target_distance 赋给相机位置 → 每格跳 5m，观感一格一格。
	_distance = lerpf(_distance, target_distance, 1.0 - exp(-delta * zoom_smoothing))
	var following := follow_target != null and is_instance_valid(follow_target) and SelectionManager.hero_mode_active
	if following:
		# 跟随主角：焦点 lerp 到主角 XZ（帧率无关）
		var tp: Vector3 = follow_target.global_position + follow_offset
		var k: float = 1.0 - exp(-delta * 8.0)
		_focus.x = lerpf(_focus.x, tp.x, k)
		_focus.z = lerpf(_focus.z, tp.z, k)
	else:
		_handle_pan(delta)
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	# UI 模态开启时（市民管理 / 技能树 / 暂停菜单…）滚轮缩放与 Q/E 视角旋转全部
	# 屏蔽——模态遮罩挡得住点击、挡不住滚轮（滚轮会穿透 STOP 遮罩落到这里）
	if SelectionManager.ui_modal_count > 0:
		return
	# 战术俯瞰专用：第三人称操控期间本相机非 current，滚轮/旋转全部让给 ThirdPersonCamera
	if not current:
		return
	if event.is_action_pressed("zoom_in"):
		_zoom_by(-1.0, event)
		return
	if event.is_action_pressed("zoom_out"):
		_zoom_by(1.0, event)
		return
	if SelectionManager.hero_mode_active:
		return   # 主角操控模式下 Q/E 让给技能，仅保留缩放
	if event.is_action_pressed("rotate_view_left"):
		_yaw_step = posmod(_yaw_step - 1, rotate_steps)
	elif event.is_action_pressed("rotate_view_right"):
		_yaw_step = posmod(_yaw_step + 1, rotate_steps)


## 滚轮只改「目标视距」，实际推拉由 _process 的阻尼收敛 —— 所以按一下鼠标也是一段动画。
## factor：高精度滚轮 / 触控板一次事件的滚动量（普通鼠标 = 1.0）；钳制到 0.25~4 防止
## 触控板惯性期一次滑出半张地图。
func _zoom_by(direction: float, event: InputEvent) -> void:
	var factor: float = 1.0
	if event is InputEventMouseButton:
		factor = clampf((event as InputEventMouseButton).factor, 0.25, 4.0)
	target_distance = clampf(
		target_distance + direction * zoom_step * factor, min_distance, max_distance)


func _handle_pan(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move := input_dir
	if edge_pan:
		var vp := get_viewport().get_visible_rect().size
		var mouse := get_viewport().get_mouse_position()
		if mouse.x < edge_margin:
			move.x -= 1.0
		elif mouse.x > vp.x - edge_margin:
			move.x += 1.0
		if mouse.y < edge_margin:
			move.y -= 1.0
		elif mouse.y > vp.y - edge_margin:
			move.y += 1.0
	if move == Vector2.ZERO:
		return
	var yaw: float = _current_yaw()
	# right 指向屏幕右；forward 指向屏幕下方（近相机一侧）。
	# get_vector 的 y 是 +下/-上，故 forward * move.y 直接得到正确的平移方向（W 上、S 下）。
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var speed_scaled := pan_speed * (_distance / 30.0)
	var vel := (right * move.x + forward * move.y) * speed_scaled
	_focus += vel * delta
	_focus.x = clamp(_focus.x, bounds.position.x, bounds.end.x)
	_focus.z = clamp(_focus.z, bounds.position.z, bounds.end.z)


func _apply_transform() -> void:
	var yaw_deg: float = BASE_YAW_DEG + float(_yaw_step) * (360.0 / float(rotate_steps))
	global_rotation_degrees = Vector3(BASE_PITCH, yaw_deg, 0.0)
	# 相机放在焦点上方+后方（basis.z 指向相机背后）；用阻尼后的实际视距 _distance
	global_position = _focus + global_transform.basis.z * _distance
	# 震屏：在目标位置上叠加衰减的随机偏移（不动 rotation，避免视角永久漂移）
	if _shake_strength > 0.005:
		global_position += Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength) * 0.4,
			randf_range(-_shake_strength, _shake_strength))


func _current_yaw() -> float:
	var yaw_deg: float = BASE_YAW_DEG + float(_yaw_step) * (360.0 / float(rotate_steps))
	return deg_to_rad(yaw_deg)


func focus_on(world_point: Vector3) -> void:
	_focus = Vector3(world_point.x, 0.0, world_point.z)


func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return _focus
	var t: float = -from.y / dir.y
	return from + dir * t


## 屏幕方向输入（WASD，x=右、y=下）→ 世界 XZ 单位向量（随当前视角旋转自适应）。
## 供主角模式直接操控。数学与 _handle_pan 的基底一致。
func input_to_world_dir(input_vec: Vector2) -> Vector3:
	if input_vec == Vector2.ZERO:
		return Vector3.ZERO
	var yaw: float = _current_yaw()
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var v := right * input_vec.x + forward * input_vec.y
	if v.length_squared() > 0.0001:
		v = v.normalized()
	return v
