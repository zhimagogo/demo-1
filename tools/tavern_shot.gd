extends Node
## v22 酒馆样张：主城内摆一座酒馆 + 一名休整小兵，第三人称视角抓帧。
##   godot --path . tools/tavern_shot.tscn   →  artifacts/v22-tavern.png

var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	# 停刷 + 白天正午
	var wildlife := world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	TimeManager.game_seconds = 11.0 / 24.0 * TimeManager.seconds_per_day
	ResourceManager.add(GameDefs.GOLD, 1000)

	# 建酒馆 + 城墙一段，摆一名小兵在馆旁休整
	var build := world.get_node("BuildSystem") as BuildSystem
	var tavern_def: BuildingDef
	for d in GameDefs.building_defs():
		if d.id == &"tavern":
			tavern_def = d
	build.enter_build_mode(tavern_def)
	build.try_place_at(Vector3(8.0, 0.0, -4.0))
	build.exit_build_mode()
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var soldier: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(11.0, 0.0, -1.0))
	await get_tree().physics_frame
	soldier.health.current_hp = soldier.health.max_hp * 0.35
	soldier.state_machine.transition_to("idle")
	await get_tree().physics_frame

	# 第三人称相机望向酒馆
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	hero.global_position = Vector3(14.0, 0.0, 4.0)
	var to := (Vector3(8.0, 0.0, -4.0) - hero.global_position) * 0.5 + Vector3(0.0, 1.2, 0.0)
	tp.yaw = atan2(-to.x, -to.z)
	tp.pitch = -0.22
	tp.target_distance = 8.0
	await get_tree().create_timer(1.2).timeout
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/v22-tavern.png")
	print("tavern shot saved")
	get_tree().quit()
