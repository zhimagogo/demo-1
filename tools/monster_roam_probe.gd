extends Node
## Real models/world/collisions at city boundary and leash; 12 simulated seconds.
## godot --path . tools/monster_roam_probe.tscn --fixed-fps 60
## Screenshots only when running with a display; headless writes metrics.
var main: Node
var monsters: Array[Raider] = []
var transitions: Array[int] = []
var fast_flips: Array[int] = []
var last_states: Array[PawnState] = []
var last_switch: Array[int] = []
var start_positions: Array[Vector3] = []
var max_home_distance: Array[float] = []
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	seed(20261002)
	AudioManager._streams[&"hit_1"] = null
	AudioManager._streams[&"hit_2"] = null
	main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	for name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem"]:
		world.get_node(name).set_process(false)
	TimeManager.begin(12)
	TimeManager.set_speed(1)
	TimeManager.set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	controller.set_process(false)
	controller.hero.release_squad()
	controller.hero.state_machine.set_physics_process(false)
	controller.hero.global_position = Vector3(-10, 0, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := main.get_node("HUD")
	hud.visible = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = Vector3(42, 24, 35)
	camera.look_at(Vector3(24, 0, 12))
	camera.current = true
	camera.fov = 60
	var spawner := world.get_node("PawnSpawner")
	var pd := PawnDef.new()
	pd.is_auto_fighter = false
	pd.max_hp = 10000
	pd.attack_damage = 0
	var border_target: Pawn = spawner.spawn_soldier(pd, Vector3(20.1, 0, 5))
	border_target.global_position = Vector3(20.1, 0, 5)
	border_target.state_machine.set_physics_process(false)
	var spawn_positions := [Vector3(23, 0, 5), Vector3(21, 0, 19), Vector3(24, 0, 25)]
	for i in spawn_positions.size():
		var d := GameDefs.raider_def()
		d.model_path_pool = []
		d.model_path = "res://assets/_PLACEHOLDER/monsters/" + ["Orc.gltf", "Ninja.gltf", "GreenBlob.gltf"][i]
		d.attack_damage = 0
		d.flee_hp_ratio = 0
		var r: Raider = spawner.spawn_raider(spawn_positions[i], d)
		if i == 2:
			r.global_position = Vector3(43, 0, 25)
			r.state_machine.transition_to("fight", {"target": border_target})
		monsters.append(r)
		transitions.append(0)
		fast_flips.append(0)
		last_states.append(r.state_machine.current_state)
		last_switch.append(-100)
		start_positions.append(r.global_position)
		max_home_distance.append(0)
	var visual := DisplayServer.get_name() != "headless"
	for frame in 720:
		await get_tree().physics_frame
		# The outside target enters town after 4s. Do not teleport monsters:
		# subsequent retreat and roaming use normal state-machine processing.
		if frame == 240:
			border_target.global_position.x = 19.8
		for i in monsters.size():
			var r := monsters[i]
			max_home_distance[i] = maxf(max_home_distance[i], r.global_position.distance_to(r.home_position))
			var state := r.state_machine.current_state
			if state != last_states[i]:
				transitions[i] += 1
				if frame - last_switch[i] <= 2:
					fast_flips[i] += 1
				last_switch[i] = frame
				last_states[i] = state
		if visual and frame in [180, 660]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://artifacts/monster-stability/world-%d.png" % frame)
	for i in monsters.size():
		var r := monsters[i]
		var moved := r.global_position.distance_to(start_positions[i])
		print("ROAM_PROBE|monster_%d|switches=%d|rapid_flips=%d|displacement=%.3f|home_dist=%.3f|max_home_dist=%.3f" % [
			i, transitions[i], fast_flips[i], moved, r.global_position.distance_to(r.home_position), max_home_distance[i]])
		if fast_flips[i] > 1 or moved < 1.0 or r.global_position.distance_to(r.home_position) > Raider.LEASH_RANGE:
			failures += 1
	print("MONSTER ROAM PROBE: %d failure(s)" % failures)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Pawn._combat_slots.clear()
	Pawn._spatial_buckets.clear()
	get_tree().quit(0 if failures == 0 else 1)
