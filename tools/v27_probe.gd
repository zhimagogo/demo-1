extends Node3D
## v27 渲染隔离探针：固定相机 + 单枚特效，验证新 shader 是否真的在画。
## 运行：godot --path . tools/v27_probe.tscn → artifacts/v27-probe.png

func _ready() -> void:
	get_window().size = Vector2i(800, 600)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.2, 3.0)
	add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.15, 0.2)
	env.environment = e
	add_child(env)

	# 三枚并排：暴击星芒（新） / 冲击环（新参数） / 斧光（旧管线对照）
	VFXManager.spawn_effect(&"crit_burst", Vector3(-1.2, 1.0, 0.0), 0.0, {"lifetime": 10.0})
	VFXManager.spawn_effect(&"hit_ring", Vector3(0.0, 1.0, 0.0), 0.0,
		{"color": Color(0.85, 0.72, 0.5), "lifetime": 10.0})
	VFXManager.spawn_effect(&"axe_arc", Vector3(1.2, 1.0, 0.0), 0.0, {"lifetime": 10.0})
	VFXManager.debug_anim_progress = 0.45
	for _i in 10:
		await get_tree().process_frame
	print("active=", VFXManager.active_effect_count())
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/v27-probe.png")
	print("saved artifacts/v27-probe.png")
	get_tree().quit()
