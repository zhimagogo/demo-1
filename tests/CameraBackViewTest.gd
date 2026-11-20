extends Node
## 主视角专项回归（v12）：正后背 + 抬高 + 广角。
##   godot --headless --path . tests/CameraBackViewTest.tscn --log-file /private/tmp/b-cam.log --fixed-fps 60
##
## 覆盖需求「主视角抬高一点，广角增大一些，用正后背视角，不要像现在一样侧偏」：
##  1. 默认参数：fov >= 76、SHOULDER_OFFSET <= 0.02、PIVOT_HEIGHT >= 1.85、跟随距离加长。
##  2. 启动即俯视（pitch <= -0.35）且 pitch 双向钳制不回归。
##  3. 正后背：yaw=0 时主角在相机空间的 |x| < 0.35m，屏幕投影 x 与视口中心差 < 12px。
##  4. 准星仍落在主角前方地面（screen_to_ground(视口中心) 距主角 < 25m、y ≈ 0）→ 建造可用。
##  5. 俯视到极限连续 10 帧，相机不穿到地面以下（global_position.y > 0.5）。
##  6. 滚轮拉到最近（MIN_DISTANCE）不与主角模型穿模（相机-枢轴间距 >= 2m）。
##
## 输出保持 ASCII（headless 日志中文会乱码）。

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_check(hero != null and tp != null and vp_size.x > 0.0 and vp_size.y > 0.0,
		"third-person stack wired (viewport %.0fx%.0f)" % [vp_size.x, vp_size.y])
	# v42：玩家默认镜头是俯视角主控；本测试专测第三人称相机，走脚本接口直接取景。
	controller.enter_hero_mode()
	await get_tree().physics_frame
	_check(tp.current and SelectionManager.hero_mode_active,
		"third-person camera engages via script API (v42 player default is top-down)")

	# ---- 1. 默认参数：抬高 / 广角 / 正后背 / 距离 ----
	print("CAMERA: fov=%.1f pivot=%.2f shoulder=%.2f pitch=%.3f dist=%.2f min=%.1f max=%.1f" % [
		tp.fov, ThirdPersonCamera.PIVOT_HEIGHT, ThirdPersonCamera.SHOULDER_OFFSET,
		tp.pitch, tp.target_distance, ThirdPersonCamera.MIN_DISTANCE, ThirdPersonCamera.MAX_DISTANCE])
	_check(tp.fov >= 76.0, "wide fov by default (%.1f >= 76)" % tp.fov)
	_check(tp.fov <= 80.0, "fov inside the requested band (%.1f <= 80)" % tp.fov)
	_check(ThirdPersonCamera.SHOULDER_OFFSET <= 0.02,
		"no shoulder offset: straight back view (offset %.3f <= 0.02)" % ThirdPersonCamera.SHOULDER_OFFSET)
	_check(ThirdPersonCamera.PIVOT_HEIGHT >= 1.85,
		"pivot raised above the old 1.55 chest height (%.2f >= 1.85)" % ThirdPersonCamera.PIVOT_HEIGHT)
	_check(ThirdPersonCamera.PIVOT_HEIGHT <= 2.05,
		"pivot stays inside the requested band (%.2f <= 2.05)" % ThirdPersonCamera.PIVOT_HEIGHT)
	_check(tp.target_distance >= 5.0 and tp.target_distance <= 5.4,
		"follow distance lengthened to offset the wide fov (%.2f m)" % tp.target_distance)
	_check(ThirdPersonCamera.MIN_DISTANCE >= 2.35 and ThirdPersonCamera.MAX_DISTANCE >= 9.9,
		"zoom range widened (min %.2f / max %.2f)" % [ThirdPersonCamera.MIN_DISTANCE, ThirdPersonCamera.MAX_DISTANCE])

	# ---- 2. 启动俯视 + 双向钳制 ----
	_check(tp.pitch <= -0.35, "default pitch looks down (%.3f rad <= -0.35)" % tp.pitch)
	tp.add_look_delta(Vector2(0.0, -99999.0))
	var upper: float = deg_to_rad(ThirdPersonCamera.PITCH_LIMIT_DOWN)
	_check(absf(tp.pitch - upper) < 0.01,
		"pitch clamps at the near extreme (%.3f rad)" % tp.pitch)
	tp.add_look_delta(Vector2(0.0, 99999.0))
	var lower: float = -deg_to_rad(ThirdPersonCamera.PITCH_LIMIT_UP)
	_check(absf(tp.pitch - lower) < 0.01,
		"pitch clamps at the far extreme (%.3f rad)" % tp.pitch)
	tp.pitch = -0.42   # 回到默认俯视
	tp.yaw = 0.0

	# ---- 3. 正后背：主角落在相机轴线与画面中线上 ----
	for _i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
	var cam_space_x: float = absf((tp.global_transform.affine_inverse() * hero.global_position).x)
	_check(cam_space_x < 0.35,
		"hero sits on the camera axis, no lateral offset (|x| %.3f m < 0.35)" % cam_space_x)
	var vp_center: Vector2 = vp_size * 0.5
	var chest: Vector3 = hero.global_position + Vector3(0.0, ThirdPersonCamera.PIVOT_HEIGHT, 0.0)
	var hero_screen: Vector2 = tp.unproject_position(chest)
	var dx: float = absf(hero_screen.x - vp_center.x)
	_check(dx < 12.0, "hero projects onto the vertical centre line (dx %.1f px < 12)" % dx)

	# ---- 4. 准星仍指向主角前方地面（建造 / 交互依赖屏幕中心射线）----
	var ground: Vector3 = tp.screen_to_ground(vp_center)
	var to_ground := ground - hero.global_position
	to_ground.y = 0.0
	_check(absf(ground.y) < 0.05, "crosshair ray lands on the ground plane (y %.3f)" % ground.y)
	_check(ground.distance_to(hero.global_position) < 25.0,
		"crosshair ground point stays near the hero (%.1f m < 25)" % ground.distance_to(hero.global_position))
	_check(to_ground.dot(hero.facing_dir()) > 0.0,
		"crosshair ground point is in front of the hero (build placement usable)")

	# ---- 5. 俯视到极限不穿地 ----
	tp.pitch = -deg_to_rad(ThirdPersonCamera.PITCH_LIMIT_DOWN)
	for _i in 10:
		await get_tree().physics_frame
		await get_tree().process_frame
	print("CAMERA STEEP: y=%.2f dist=%.2f" % [tp.global_position.y, tp.global_position.distance_to(chest)])
	_check(tp.global_position.y > 0.5,
		"camera never sinks below the ground at full pitch-down (y %.2f > 0.5)" % tp.global_position.y)

	# ---- 6. 最近距离不穿模：主角 capsule 高约 1.8m，相机贴到最近也不应与模型重叠 ----
	tp.pitch = -0.42
	tp.target_distance = ThirdPersonCamera.MIN_DISTANCE
	for _i in 40:
		await get_tree().physics_frame
		await get_tree().process_frame
	var gap: float = tp.global_position.distance_to(chest)
	print("CAMERA CLOSEST: gap=%.2f" % gap)
	_check(gap >= 2.0, "closest zoom keeps the camera clear of the hero model (%.2f m >= 2.0)" % gap)

	print("CAMERA BACK VIEW TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
