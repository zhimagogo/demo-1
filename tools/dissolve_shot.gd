extends Node
## v13 交付留档：主角周围「半球消散」对照样张（不参与游戏运行）。
##
## 运行：godot --path . tools/dissolve_shot.tscn
## 输出：
##   artifacts/v13-dissolve-on.png    主角站在树丛/草丛里，半球内装饰已消散
##   artifacts/v13-dissolve-off.png   同一机位、同一帧数，消散关闭（对照）
##
## 两张图同机位、同时间、同姿态，只有 `hero_dissolve_strength` 不同 —— 便于直接对比。

const SHOTS := [
	{"name": "v13-dissolve-forest", "hero": Vector3(6.0, 0.0, -26.0), "cam": Vector3(6.0, 4.4, -33.5), "look": Vector3(6.0, 1.2, -26.0), "fov": 62.0},
	{"name": "v13-dissolve-grove", "hero": Vector3(-40.0, 0.0, 40.0), "cam": Vector3(-40.0, 4.6, 33.0), "look": Vector3(-40.0, 1.4, 40.0), "fov": 62.0},
]

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	TimeManager.begin(11)
	TimeManager.set_speed(0.0)
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	# 切战术俯瞰：不想要越肩相机跟着主角，改用固定机位对照
	controller.exit_hero_mode()
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	iso.set_process(false)

	# 消散系统是 autoload（必须在任何场景材质加载前注册 global uniform）
	var dissolve := get_node_or_null("/root/DecorationDissolve") as DecorationDissolveSystem
	print("dissolve system: ", dissolve != null)

	for shot in SHOTS:
		hero.global_position = shot["hero"]
		hero.velocity = Vector3.ZERO
		var cam := Camera3D.new()
		cam.fov = float(shot["fov"])
		world.add_child(cam)
		cam.global_position = shot["cam"]
		cam.look_at(shot["look"])
		cam.current = true
		if dissolve != null:
			dissolve.set_enabled(true)
		for _i in 12:
			await get_tree().physics_frame
		await _snap("%s-on" % shot["name"])
		if dissolve != null:
			dissolve.set_enabled(false)
		await _snap("%s-off" % shot["name"])
		if dissolve != null:
			dissolve.set_enabled(true)
		cam.queue_free()

	# 半球判定数值汇总（客观留档）
	if dissolve != null:
		hero.global_position = SHOTS[0]["hero"]
		await get_tree().physics_frame
		var chest: Vector3 = hero.global_position + Vector3.UP * 1.0
		for probe in [Vector3.ZERO, Vector3(1.0, 0, 0), Vector3(2.5, 0, 0), Vector3(4.0, 0, 0), Vector3(7.0, 0, 0)]:
			var at: Vector3 = chest + probe
			print("  hero+%s -> dissolve %.3f" % [probe, dissolve.dissolve_amount_at(at)])
	get_tree().quit()


func _snap(name: String) -> void:
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % name)
	print("saved artifacts/%s.png" % name)
