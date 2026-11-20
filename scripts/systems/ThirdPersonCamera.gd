class_name ThirdPersonCamera
extends Camera3D
## ============================================================================
## 第三人称正后背相机（默认主视角，v12 抬高 + 广角 + 去肩偏）：
## - 跟随主角：枢轴抬到主角头上（PIVOT_HEIGHT），相机沿视线正后方拉出——
##   肩部偏移为 0 → 主角严格居于准星正下方（不再像越肩那样侧偏到画面一侧）
## - yaw/pitch 由 HeroController 写入（本类不直接读输入）；鼠标滚轮缩放跟随距离
## - 相机碰撞收缩：枢轴→相机位置的射线被世界几何（layer 1）挡住时拉近，防穿墙穿树
## - shake() 与 IsometricCamera 同签名：Boss 登场 / 雷击等 duck-typing 震屏调用天然兼容
## - screen_to_ground() / aim 射线：准星（屏幕中心）→ 世界，第三人称建造 / 指挥共用
## ============================================================================

const BASE_FOV: float = 78.0           # 默认视场角（广角；启动即生效）
const PIVOT_HEIGHT: float = 1.95       # 枢轴高度（主角头顶附近：抬高视角、俯视感更强）
const SHOULDER_OFFSET: float = 0.0     # 肩部偏移归零 = 正后背视角（主角居中，不要左右偏置）
const PITCH_LIMIT_UP: float = 70.0     # 上仰极限（度）
const PITCH_LIMIT_DOWN: float = 62.0   # 下俯极限（度）
const SENSITIVITY: float = 0.0023      # 鼠标灵敏度（弧度/像素）
const MIN_DISTANCE: float = 2.4        # 最近跟随距离（正后方 + 抬高枢轴，不会与主角模型穿模）
const MAX_DISTANCE: float = 10.0       # 最远跟随距离
const COLLISION_MASK: int = 1          # 只与世界几何（layer 1）做穿模收缩，不撞单位（layer 5）

var yaw: float = 0.0                  # 水平视角（弧度；同时驱动主角朝向）
var pitch: float = -0.42               # 垂直视角（弧度；约 -24°，明显俯视起步）
var hero: Hero = null                 # 跟随的主角
var target_distance: float = 5.2      # 期望跟随距离（滚轮调节；略微加长抵消广角压迫感）
var _distance: float = 5.2            # 实际距离（含碰撞收缩，平滑收敛）

# 震屏（与 IsometricCamera 同参数语义）
var _shake_strength: float = 0.0
var _shake_decay: float = 3.2


func _ready() -> void:
	fov = BASE_FOV
	near = 0.1
	current = false   # 由 HeroController 在进入第三人称操控时置 current
	_distance = target_distance


## 触发一次震屏。strength ≈ 最大偏移米数；duration 越长衰减越慢。
func shake(strength: float, duration: float = 0.5) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_decay = 3.2 / maxf(duration, 0.15)


func _process(delta: float) -> void:
	# 震屏强度指数衰减（与等距相机一致）
	if _shake_strength > 0.005:
		_shake_strength *= exp(-delta * _shake_decay)
	else:
		_shake_strength = 0.0

	# 跟随距离平滑收敛到目标（滚轮缩放的阻尼感）
	_distance = lerpf(_distance, target_distance, 1.0 - exp(-delta * 10.0))

	# 先定姿态（yaw/pitch），再沿视线后方布置相机 → 相机永远看向枢轴前方
	global_rotation = Vector3(pitch, yaw, 0.0)

	var pivot: Vector3
	if hero != null and is_instance_valid(hero):
		pivot = hero.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
		# 死亡时镜头缓缓拉远放平，看主角倒地
		if hero.is_dead_flag:
			pitch = lerpf(pitch, -0.12, 1.0 - exp(-delta * 2.0))
	else:
		# 主角尚未生成：先停在主城旁等待接线
		pivot = Vector3(0.0, PIVOT_HEIGHT, 6.0)

	# 肩部偏移：正后背视角下为 0（主角严格居于准星正下方）。
	# 常量保留为「可调项」：历史上 0.42 的越肩偏移会让主角侧偏到画面一侧。
	var right := global_transform.basis.x
	pivot += right * SHOULDER_OFFSET

	var back := global_transform.basis.z   # 相机后方（basis.z 指向背后）
	var desired := pivot + back * _distance

	# 碰撞收缩：枢轴→期望位置的射线被世界挡住 → 相机贴到命中点前 0.25m（留鼻梁余量）
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot, desired, COLLISION_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	var final_pos: Vector3 = desired
	if hit and not hit.is_empty():
		var to_hit: float = (hit.position as Vector3).distance_to(pivot)
		if to_hit < _distance:
			final_pos = pivot + back * maxf(to_hit - 0.25, 0.35)

	global_position = final_pos
	if _shake_strength > 0.005:
		global_position += Vector3(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength) * 0.4,
			randf_range(-_shake_strength, _shake_strength))


## 鼠标相对位移 → 视角（由 HeroController 转发，集中在此做钳制）。
## 灵敏度倍率实时读 GameSettings（设置面板拖动滑杆立即生效，无需推送）。
func add_look_delta(relative: Vector2) -> void:
	var sens := SENSITIVITY * GameSettings.look_sensitivity()
	yaw -= relative.x * sens
	pitch -= relative.y * sens
	pitch = clampf(pitch, -deg_to_rad(PITCH_LIMIT_UP), deg_to_rad(PITCH_LIMIT_DOWN))


func _unhandled_input(event: InputEvent) -> void:
	# UI 模态开启时（市民管理 / 技能树 / 暂停菜单…）滚轮全部屏蔽——
	# 模态遮罩挡得住点击、挡不住滚轮（Control 须在 _gui_input 里 accept_event()
	# 才吃滚轮，ColorRect 没有 → 滚轮会穿到 _unhandled_input，市民管理开着还能缩放）
	if SelectionManager.ui_modal_count > 0:
		return
	# 滚轮缩放跟随距离（仅在当前相机时响应；战术模式下滚轮归等距相机）
	if not current:
		return
	if event.is_action_pressed("zoom_in"):
		target_distance = maxf(MIN_DISTANCE, target_distance - 0.9)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("zoom_out"):
		target_distance = minf(MAX_DISTANCE, target_distance + 0.9)
		get_viewport().set_input_as_handled()


## 视线水平前进方向（yaw 平面投影；供 WASD 移动 / 主角朝向计算）。
func forward_flat() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


## 准星射线（屏幕中心）原点与方向。供交互 / 建造 / 指挥统一取「玩家正在看哪」。
func aim_ray() -> Dictionary:
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	return {
		"from": project_ray_origin(center),
		"dir": project_ray_normal(center),
	}


func screen_to_ground(screen_pos: Vector2) -> Vector3:
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)
	# 上仰视线（屏幕上缘射线朝天上）：与地面无交点或交点在背后。
	# 返回沿水平方向外推的远点，让视野框/建造投影正确张开到地图边界而不是塌缩成负坐标。
	if dir.y > -0.0001:
		var flat := Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() < 0.0001:
			flat = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
		return from + flat.normalized() * 240.0
	var t: float = -from.y / dir.y
	return from + dir * t
