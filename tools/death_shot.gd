extends Node
## v16 交付留档：怪物死亡「动画 + 贴图溶解」样张（不参与游戏运行）。
##
## 运行：godot --path . tools/death_shot.tscn
## 输出：artifacts/v16-death-dissolve.png —— 三只野怪处于死亡三阶段：
##   左：刚倒地（Death_A 播放中）· 中：烧蚀过半 · 右：溶解殆尽。


var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	TimeManager.begin(11)          # 正午，光线充足
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	var hero := controller.hero as Hero
	if hero != null:
		hero.visible = false      # 样张只看野怪
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	(world.get_node("IsometricCamera") as IsometricCamera).set_process(false)

	# 固定机位：正对野怪一排，平视略带俯角看清烧蚀边缘
	const ROW_Z := -20.0
	const SPACING := 3.0
	const N := 3
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	var center_x := float(N - 1) * 0.5 * SPACING
	cam.global_position = Vector3(center_x, 2.2, ROW_Z + 6.4)
	cam.look_at(Vector3(center_x, 0.9, ROW_Z))
	cam.current = true

	# 三只野怪错峰击杀：snap 时刻恰好呈现 倒地中(0.2s) / 烧蚀过半(~0.61) / 溶解殆尽(~0.9+)
	var spawner := world.get_node("PawnSpawner")
	var defs := [GameDefs.raider_def(), GameDefs.raider_elite_def(), GameDefs.raider_def()]
	var raiders: Array[Pawn] = []
	for i in N:
		var at := Vector3(float(i) * SPACING, 0.0, ROW_Z)
		var r: Pawn = spawner.call("spawn_raider", at, defs[i])
		r.look_at_target(cam.global_position - at)   # 面向镜头倒下
		raiders.append(r)
		await get_tree().physics_frame

	# 右（先杀）→ 中 → 左（最后杀）：右溶解最久
	raiders[2].health.apply_damage(99999.0)
	for _i in 42:
		await get_tree().physics_frame   # 0.7s
	raiders[1].health.apply_damage(99999.0)
	for _i in 36:
		await get_tree().physics_frame   # 0.6s
	raiders[0].health.apply_damage(99999.0)
	for _i in 18:
		await get_tree().physics_frame   # 0.3s → 左 0.3s / 中 0.9s(溶解 t≈0) / 右 1.5s(溶解 t≈0.61)

	await _snap("v16-death-dissolve")
	get_tree().quit()


func _snap(art_name: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % art_name)
	print("SNAP saved: artifacts/%s.png (%dx%d)" % [art_name, img.get_width(), img.get_height()])
