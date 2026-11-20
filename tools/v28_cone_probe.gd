extends Node3D
## v28 定向喷溅验证：两束火星锥相向喷射（左束朝 +X / 右束朝 -X）。
## 运行：godot --path . tools/v28_cone_probe.tscn → artifacts/v28-cone-probe.png

func _ready() -> void:
	get_window().size = Vector2i(900, 600)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.4, 0.0)
	add_child(cam)
	cam.current = true
	# 相机朝 -Z 看，两束锥在相机前方左右对称：左束喷向画面右（+X），右束喷向画面左（-X）
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 20.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.18)
	env.environment = e
	add_child(env)

	# +X 方向（yaw = atan2(-1, 0) = -PI/2）；不做寿命覆盖——one_shot 粒子的
	# lifetime 同时是发射时长，覆盖成 5s 会把 12 颗火星摊成 5 秒慢慢吐
	VFXManager.spawn_effect(&"hit_spark_cone", Vector3(-2.0, 1.0, -3.0), -PI / 2.0)
	# -X 方向（yaw = atan2(1, 0) = +PI/2）
	VFXManager.spawn_effect(&"hit_spark_cone", Vector3(2.0, 1.0, -3.0), PI / 2.0)
	# 对照组：旧版全向火星（真实游戏同款）
	VFXManager.spawn_effect(&"hit_spark", Vector3(0.0, 1.0, -3.0))
	# 白闪对照（网格类，寿命可安全覆盖定格）
	VFXManager.spawn_effect(&"impact_flash", Vector3(0.0, 0.3, -3.0), 0.0, {"lifetime": 5.0})
	VFXManager.debug_anim_progress = 0.5
	for _i in 20:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/v28-cone-probe.png")
	print("saved artifacts/v28-cone-probe.png")
	get_tree().quit()
