extends Node
## v23 交付留档：金币「爆出」掉落样张（不参与游戏运行）。
##
## 运行：godot --path . tools/loot_shot.tscn
## 输出两张：
##   artifacts/v23-loot-burst.png —— 爆发期：普通怪金币抛物线腾空 + 头目金币落地散布
##   artifacts/v23-loot-magnet.png —— 磁吸期：停留结束，金币集体飞向站立的主角


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
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	(world.get_node("IsometricCamera") as IsometricCamera).set_process(false)

	# 固定机位：俯角看清抛物线弧与地面散布
	const CENTER := Vector3(0.0, 0.0, -24.0)
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_position = CENTER + Vector3(0.0, 4.6, 8.2)
	cam.look_at(CENTER + Vector3(0.0, 0.4, 0.0))
	cam.current = true

	var spawner := world.get_node("PawnSpawner")
	var hero: Hero = controller.hero
	hero.global_position = CENTER + Vector3(3.4, 0.0, 2.2)   # 站在爆点旁 → 停留期结束后的磁吸目标
	hero.look_at_target(CENTER - hero.global_position)

	# 头目先杀（金币先落地散布），两只普通怪晚 0.35s 杀（金币还在抛物线空中段）
	var boss: Pawn = spawner.call("spawn_raider", CENTER + Vector3(-0.6, 0.0, 0.0), GameDefs.raider_boss_def())
	var mob_a: Pawn = spawner.call("spawn_raider", CENTER + Vector3(-4.6, 0.0, 1.4), GameDefs.raider_def())
	var mob_b: Pawn = spawner.call("spawn_raider", CENTER + Vector3(-6.2, 0.0, -1.2), GameDefs.raider_def())
	for r: Pawn in [boss, mob_a, mob_b]:
		await get_tree().physics_frame
	boss.health.apply_damage(99999.0, hero)
	for _i in 21:   # 0.35s
		await get_tree().physics_frame
	mob_a.health.apply_damage(99999.0, hero)
	mob_b.health.apply_damage(99999.0, hero)
	for _i in 18:   # 再 0.3s → 普通币腾空中段 / 头目币触地散布
		await get_tree().physics_frame
	await _snap("v23-loot-burst")

	# 再等 ~1.9s：停留（1.5s）结束 → 金币集体磁吸飞向主角
	for _i in 114:
		await get_tree().physics_frame
	await _snap("v23-loot-magnet")
	get_tree().quit()


func _snap(art_name: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % art_name)
	print("SNAP saved: artifacts/%s.png (%dx%d)" % [art_name, img.get_width(), img.get_height()])
