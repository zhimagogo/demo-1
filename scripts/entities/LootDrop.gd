class_name LootDrop
extends Node3D
## v23 金币「爆出」掉落：怪物死亡 → 金币带随机初速抛物线飞出 → 落地弹跳几下（距离刻意收着）→
## 停留一小会儿 → 自动磁吸到玩家（主角）或附近最近的小兵身上结算。
## 总金额不变，由 CombatSystem 拆成多份注入多个本节点（普通 1~3 份 / 头目 5~8 份）。
## 注意：拾取即结算消失，**不再有缩小淡出动画**（用户明确要求去掉）。
## 落地后有 **1.5s 硬保护窗口**：期间任何拾取路径（贴身直捡/磁吸）都不结算，
## 保证弹跳 + 慢转动画完整可见，不会「刚掉下来就被吃掉」。

enum Phase { DELAY, FLY, REST, HOMING }

@export var resource_id: StringName = &"gold"
@export var amount: int = 5
@export var spawn_delay: float = 0.0   # 多枚金币错峰出场延迟（喷泉感，CombatSystem 设置）
@export var ground_y: float = 0.0      # 掉落点地面高度（野怪脚底，弹跳/停驻的基准面）

# —— 抛物线 + 弹跳（距离不要太远：全场位移约 ≤2.5m）——
const GRAVITY := 15.0
const H_SPEED_MIN := 1.1               # 水平初速（决定飞多远）
const H_SPEED_MAX := 2.3
const V_SPEED_MIN := 3.0               # 竖直初速（决定弹多高）
const V_SPEED_MAX := 4.4
const BOUNCE_KEEP_V := 0.45            # 触地反弹保留的竖直速度比例
const BOUNCE_KEEP_H := 0.7             # 触地反弹保留的水平速度比例
const REST_BOUNCE_V := 1.0             # 反弹后竖直速度低于此值 → 就地停住
const FLY_FLOOR_Y := 0.28              # 飞行/弹跳期触地平面：斜立金币最高下沿（r0.276×sin70°≈0.26）仍不插地
                                       # 停驻高度不设常量——按当前姿态由 _rest_height() 求贴地落差

# —— 停留 + 磁吸 ——
const REST_DELAY := 1.5                # 落地停稳后再停留的时长（「一小会儿」）
const RESCAN_INTERVAL := 0.3           # 未找到吸附目标时的重扫间隔
const MAGNET_RADIUS := 12.0            # 吸附搜索半径（玩家 / 小兵）
const HERO_BIAS := 0.75                # 主角距离加权 <1 → 势均时金币优先飞向玩家（亲征爽感）
const MAGNET_ACCEL_MIN := 30.0         # 吸附加速度下限（逐币随机 → 到达时间天然错峰）
const MAGNET_ACCEL_MAX := 46.0
const MAGNET_MAX_SPEED := 16.0
const CATCH_DIST := 0.7                # 距目标小于该值即结算
const PICKUP_RADIUS := 2.2             # 贴身直捡半径（仅在停满 REST_DELAY 后生效，硬保 1.5s 动画窗口）

const LIFETIME := 25.0

var _phase: int = Phase.DELAY
var _vel := Vector3.ZERO
var _delay_left := 0.0
var _rest_left := 0.0
var _rescan_left := 0.0
var _age := 0.0
var _collected := false
var _target: Node3D = null
var _homing_speed := 2.5
var _homing_accel := 38.0
var _visual: Node3D                    # 仅旋转/缩放视觉件，根节点 scale 恒为 1（无缩小动画的契约基础）
var _mesh: MeshInstance3D              # 金币网格（带随机倾斜，停驻时按姿态求贴地落差）
var _spin_axis := Vector3.FORWARD


func _ready() -> void:
	_delay_left = spawn_delay
	_build_visual()
	if _delay_left <= 0.0:
		_launch()
	else:
		_visual.visible = false


## 组装金币外观：小金币圆柱 + 发光金材质（视觉件带随机尺寸差，更有机）。
func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var mesh := MeshInstance3D.new()
	var coin := CylinderMesh.new()
	coin.top_radius = 0.24
	coin.bottom_radius = 0.24
	coin.height = 0.09
	mesh.mesh = coin
	mesh.rotation_degrees = Vector3(randf_range(-70.0, 70.0), randf() * 360.0, randf_range(-70.0, 70.0))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.GOLD
	material.metallic = 0.75
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(0.75, 0.48, 0.04)
	mesh.material_override = material
	_visual.add_child(mesh)
	_mesh = mesh
	_visual.scale = Vector3.ONE * randf_range(0.85, 1.15)
	# 出场小弹跳（飞出途中完成，属出场动效而非拾取动画）
	_visual.scale = Vector3.ONE * 0.4
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * randf_range(0.85, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spin_axis = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()


func _launch() -> void:
	_phase = Phase.FLY
	var ang := randf() * TAU
	var hs := randf_range(H_SPEED_MIN, H_SPEED_MAX)
	_vel = Vector3(cos(ang) * hs, randf_range(V_SPEED_MIN, V_SPEED_MAX), sin(ang) * hs)


func _physics_process(delta: float) -> void:
	if _collected:
		return
	_age += delta
	match _phase:
		Phase.DELAY:
			_delay_left -= delta
			if _delay_left <= 0.0:
				_visual.visible = true
				_launch()
			return
		Phase.FLY:
			_tick_fly(delta)
		Phase.REST:
			_tick_rest(delta)
		Phase.HOMING:
			_tick_homing(delta)
	if _age >= LIFETIME and _phase != Phase.HOMING:
		queue_free()


## 飞行 + 落地弹跳：重力抛物线，触地按保留比例反弹，弹不动了就地停住。
## 飞行期不结算——落地弹跳动画必须完整可见（硬保护 1.5s，见 _tick_rest）。
func _tick_fly(delta: float) -> void:
	_vel.y -= GRAVITY * delta
	global_position += _vel * delta
	_visual.rotate(_spin_axis, delta * 9.0)
	if global_position.y <= ground_y + FLY_FLOOR_Y and _vel.y < 0.0:
		global_position.y = ground_y + FLY_FLOOR_Y
		var bounce_v := -_vel.y * BOUNCE_KEEP_V
		if bounce_v < REST_BOUNCE_V:
			_settle()
			return
		_vel.y = bounce_v
		# 水平速度衰减 + 轻微随机偏转（弹跳更有机、不会一条直线滑走）
		_vel.x *= BOUNCE_KEEP_H
		_vel.z *= BOUNCE_KEEP_H
		var turn := randf_range(-0.5, 0.5)
		var cs := cos(turn)
		var sn := sin(turn)
		var vx := _vel.x
		_vel.x = vx * cs - _vel.z * sn
		_vel.z = vx * sn + _vel.z * cs


## 落地停稳（弹跳耗尽）：按当前姿态贴地 + 慢速自转停驻，随后开始找磁吸目标。
func _settle() -> void:
	_phase = Phase.REST
	_vel = Vector3.ZERO
	_rest_left = REST_DELAY
	_rescan_left = 0.0
	# 姿态贴地：保留落地的随机翻滚姿态（平躺贴得低、斜立站得高），按圆柱几何求
	# 「中心到最低下沿」的精确落差落到贴地高度——不穿模也不悬浮。
	# 飞行期触地面（FLY_FLOOR_Y）按斜立最坏情况抬高防弹跳穿模，停驻这 0.1s 补落到位。
	var tw := create_tween()
	tw.tween_property(self, "position:y", ground_y + _rest_height(), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 当前姿态下的贴地中心高度：圆柱（半厚 h、半径 r，轴 A）最低下沿 = h·|A_y| + r·√(1−A_y²)。
func _rest_height() -> float:
	var axis := (_visual.quaternion * _mesh.quaternion) * Vector3.UP
	var s := _visual.scale.x
	var ay := absf(axis.y)
	return 0.045 * s * ay + 0.24 * s * sqrt(maxf(0.0, 1.0 - ay * ay)) + 0.015


## 当前姿态下金币最低点的世界高度（测试防穿模契约用）。
func bottom_height() -> float:
	return global_position.y - _rest_height() + 0.015


## 停留期：带姿态慢速自转等 1.5s（**硬保护窗口：期间贴身直捡/磁吸都不结算**，
## 保证弹跳 + 旋转动画完整可见），停满后才开始找吸附目标；目标出现即进入磁吸。
func _tick_rest(delta: float) -> void:
	_rest_left -= delta
	_visual.rotation.y += delta * 1.6
	if _rest_left > 0.0:
		return
	_try_proximity_pickup()
	if _collected:
		return
	_rescan_left -= delta
	if _rescan_left > 0.0:
		return
	_rescan_left = RESCAN_INTERVAL
	_target = _find_magnet_target()
	if _target != null:
		_homing_speed = randf_range(2.0, 3.5)
		_homing_accel = randf_range(MAGNET_ACCEL_MIN, MAGNET_ACCEL_MAX)
		_phase = Phase.HOMING


## 磁吸：朝目标胸口加速冲刺（越吸越快），到达即结算；目标半路死亡则回停留态重扫。
func _tick_homing(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _is_unit_dead(_target):
		_target = null
		_phase = Phase.REST
		_rescan_left = 0.0
		return
	var aim: Vector3 = _target.global_position + Vector3.UP * 0.9
	var to := aim - global_position
	_homing_speed = minf(_homing_speed + _homing_accel * delta, MAGNET_MAX_SPEED)
	global_position += to.normalized() * _homing_speed * delta
	_visual.rotation.y += delta * 14.0
	if to.length() <= CATCH_DIST:
		_collect()


## 主角/小兵贴身直捡——只在停满 REST_DELAY 后生效（调用方已保证在硬保护窗口外）。
func _try_proximity_pickup() -> void:
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if not (unit is Node3D) or not is_instance_valid(unit):
			continue
		if not (unit is Hero or unit is Soldier):
			continue
		if global_position.distance_to((unit as Node3D).global_position) <= PICKUP_RADIUS:
			_collect()
			return


## 磁吸目标：搜索半径内的主角与四职业小兵，取「加权最近」（主角打 0.75 折优先）。
func _find_magnet_target() -> Node3D:
	var best: Node3D = null
	var best_d := MAGNET_RADIUS
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if not (unit is Node3D) or not is_instance_valid(unit):
			continue
		if not (unit is Hero or unit is Soldier):
			continue
		if _is_unit_dead(unit):
			continue
		var d := global_position.distance_to((unit as Node3D).global_position)
		if unit is Hero:
			d *= HERO_BIAS
		if d < best_d:
			best_d = d
			best = unit
	return best


func _is_unit_dead(unit: Node) -> bool:
	var flag = unit.get("is_dead_flag")
	return flag != null and flag


## 结算：入账 + 音效 + 飘字 + 金色星屑迸一下，立即消失。**没有缩小动画**（v23 用户要求去掉）。
func _collect() -> void:
	if _collected:
		return
	_collected = true
	ResourceManager.add(resource_id, amount)
	AudioManager.play_sfx(&"coin", global_position)
	EventBus.floating_text.emit("+%d 金币" % amount, Color(1.0, 0.88, 0.25), global_position + Vector3.UP * 0.4)
	# v27：入袋星屑——金币被吸走的瞬间在胸口炸一下金色小星（拾取反馈从「一行字」变「一次闪光」）
	VFXManager.spawn_effect(&"coin_sparkle", global_position + Vector3.UP * 0.6, 0.0,
		{"throttle_key": "%d_%d" % [get_instance_id(), randi()]})
	queue_free()
