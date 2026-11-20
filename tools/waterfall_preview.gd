extends Node
## 同机位留档：godot --path . tools/waterfall_preview.tscn -- --label=before
## 固定昼夜后留档；水雾通过预热保证暂停画面也有稳定形态。

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	get_window().size = Vector2i(1600, 900)
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
	var main := load("res://scenes/main/Main.tscn").instantiate() as Node
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	(world.get_node("HeroController") as HeroController).exit_hero_mode()
	world.get_node("IsometricCamera").set_process(false)
	main.get_node("HUD").visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	TimeManager.begin(11)
	(world.get_node("DayNightCycle") as DayNightCycle)._process(0.2)
	TimeManager.set_speed(0.0)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 62.0
	# v43：瀑布迁到 (58,-72)/(56,-64)，相机按新坐标重新取景（多股落水 + 分层崖壁）
	await _snap(cam, Vector3(50, 7.6, -43.5), Vector3(57, 4, -65.5), label + "-front")
	await _snap(cam, Vector3(77, 10.5, -49), Vector3(57.5, 3.6, -65), label + "-side")
	await _snap(cam, Vector3(24, 32, -20), Vector3(56, 0, -47), label + "-overview")
	TimeManager.begin(23)
	(world.get_node("DayNightCycle") as DayNightCycle)._process(0.2)
	TimeManager.set_speed(0.0)
	await _snap(cam, Vector3(50, 7.6, -43.5), Vector3(57, 4, -65.5), label + "-night")
	# 恢复运行，检查水帘、白沫和粒子的动画推进。
	TimeManager.begin(11)
	TimeManager.set_speed(1.0)
	await _snap(cam, Vector3(50, 7.6, -43.5), Vector3(57, 4, -65.5), label + "-motion")
	get_tree().quit()

func _snap(cam: Camera3D, eye: Vector3, target: Vector3, label: String) -> void:
	cam.global_position = eye
	cam.look_at(target)
	await get_tree().create_timer(1.0, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/waterfall-%s.png" % label)
	print("Saved waterfall-", label)
