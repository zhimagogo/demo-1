extends Node
## v18 渲染探针：在「纯灰地面 + 单个小兵」的极简环境里验证小队绿标真实画出。
## 运行（两次对照）：
##   godot --path . tools/v18_marks_probe.tscn               # → artifacts/v18-probe-marks.png
##   godot --path . tools/v18_marks_probe.tscn -- --no-marks # → artifacts/v18-probe-plain.png
## 灰底上任何「绿主导」像素都只能来自绿标（包边描边 / 脚下小绿圈）。

func _ready() -> void:
	var with_marks: bool = not OS.get_cmdline_user_args().has("--no-marks")
	get_window().size = Vector2i(900, 640)

	# 灰色地面（避免草地的环境绿干扰判定）
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.38, 0.38, 0.40)
	ground.material_override = gmat
	ground.position = Vector3.ZERO
	add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.0
	add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.global_position = Vector3(0.0, 1.15, 3.4)
	cam.look_at(Vector3(0.0, 0.95, 0.0))

	# 单个小兵（战士职业，挂真实 KayKit 模型）
	var soldier := SoldierMelee.new()
	soldier.def = GameDefs.settler_warrior_def()
	add_child(soldier)
	soldier.global_position = Vector3.ZERO
	soldier.look_at_target(Vector3(0.0, 0.0, 1.0))   # 面向相机
	for i in 10:
		await get_tree().process_frame
	if with_marks:
		soldier.set_squad_mark(true)
	for i in 15:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var filename := "v18-probe-plain" if not with_marks else "v18-probe-marks"
	img.save_png("res://artifacts/%s.png" % filename)
	print("saved artifacts/%s.png  marks=%s  outline_on=%s  ring_vis=%s"
		% [filename, with_marks,
			soldier.model_rig._outline_on if soldier.model_rig != null else false,
			soldier.get_node_or_null("SquadRing") != null
				and (soldier.get_node("SquadRing") as MeshInstance3D).visible])
	get_tree().quit()
