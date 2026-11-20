extends Node
## Deterministic regressions for navigation jitter, geometry and query cost.
class FocusLeader extends Node3D:
	var focus_target: Node
	func is_focus_alive() -> bool:
		return is_instance_valid(focus_target)

var failures: int = 0
var checks: int = 0
var landed_hits: Dictionary = {}
var world: Node3D
var grid: GridSystem
var nav: NavSystem
var spawner: Node

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: ", label)

func soldier(at: Vector3) -> Pawn:
	var d := PawnDef.new()
	d.attack_range = 2.2
	d.is_auto_fighter = false
	var p: Pawn = spawner.spawn_soldier(d, at)
	p.state_machine.set_physics_process(false)
	p.set_process(false)
	return p

func _damage_seen(victim: Node, _amount: float, source: Node) -> void:
	landed_hits[source] = int(landed_hits.get(source, 0)) + 1

func _run() -> void:
	# This fixture tests real damage, not sound playback. Avoid unfinished Ogg
	# playbacks when the accelerated headless fixture exits in under a second.
	AudioManager._streams[&"hit_1"] = null
	AudioManager._streams[&"hit_2"] = null
	world = Node3D.new()
	add_child(world)
	grid = GridSystem.new()
	grid.name = "GridSystem"
	grid.debug_visible = false
	world.add_child(grid)
	nav = NavSystem.new()
	world.add_child(nav)
	var players := Node3D.new()
	world.add_child(players)
	var enemies := Node3D.new()
	world.add_child(enemies)
	spawner = load("res://scripts/systems/PawnSpawner.gd").new()
	world.add_child(spawner)
	spawner.configure(players, enemies)
	await get_tree().physics_frame

	# Fast rally + 3x simulation used to bounce across an intermediate waypoint forever.
	var p := soldier(Vector3(15, 0, 15))
	p.move_speed = 32.0
	p._nav_path = PackedVector3Array([Vector3(15.8, 0, 15), Vector3(21, 0, 15)])
	p._nav_target = Vector3(21, 0, 15)
	p._nav_dirty = false
	Engine.time_scale = 3.0
	var arrived := false
	for i in 20:
		await get_tree().physics_frame
		if p.move_along_path(get_physics_process_delta_time()):
			arrived = true
			break
	check(arrived and p.global_position.distance_to(Vector3(21, 0, 15)) < 0.51,
		"accelerated pawn passes intermediate waypoint without oscillation")
	check(p.is_navigation_done(), "arrival marks the path complete")
	Engine.time_scale = 1.0

	var enemy_def := PawnDef.new()
	enemy_def.team = TeamComponent.Team.ENEMY
	var raider: Raider = spawner.spawn_raider(Vector3(-23, 0, 15), enemy_def)
	raider.state_machine.set_physics_process(false)
	raider.move_speed = 32.0
	raider._nav_path = PackedVector3Array([Vector3(-22.2, 0, 15), Vector3(-17, 0, 15)])
	raider._nav_target = Vector3(-17, 0, 15)
	raider._nav_dirty = false
	Engine.time_scale = 3.0
	var enemy_arrived := false
	for i in 20:
		await get_tree().physics_frame
		if raider.move_along_path(get_physics_process_delta_time()):
			enemy_arrived = true
			break
	check(enemy_arrived, "accelerated enemy passes waypoints without oscillation")
	raider.queue_free()
	Engine.time_scale = 1.0

	# Strong opposing crowd force cannot cancel path progress.
	p.global_position = Vector3(15, 0, 15)
	p.move_speed = 4.0
	p.set_navigation_target(Vector3(21, 0, 15), true)
	for i in 180:
		await get_tree().physics_frame
		p._steer_separation = Vector3(-20, 0, 0)
		p.move_along_path(get_physics_process_delta_time())
	check(p.global_position.x > 18.0, "crowd separation preserves forward progress")
	p.queue_free()
	await get_tree().physics_frame

	# Resource ownership must compose with another resource and terrain.
	var a := ResourceNode.new()
	a.position = Vector3(16, 0, 16)
	world.add_child(a)
	var b := ResourceNode.new()
	b.position = Vector3(16.2, 0, 16.2)
	world.add_child(b)
	var cell := grid.world_to_grid(Vector3(17, 0, 17))
	nav.set_resource_solid(a, false)
	check(nav.path_grid.is_point_solid(cell), "removing one resource preserves overlapping resource occupancy")
	b.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not nav.path_grid.is_point_solid(cell), "freeing the last resource releases occupancy")
	a.queue_free()
	await get_tree().physics_frame

	var protected := ResourceNode.new()
	protected.position = Vector3(0, 0, 0)
	world.add_child(protected)
	nav.set_resource_solid(protected, false)
	check(nav.path_grid.is_point_solid(grid.world_to_grid(Vector3.ZERO)), "resource release preserves permanent castle footprint")
	protected.queue_free()
	await get_tree().physics_frame

	# Real collision footprint + off-center start and endpoint near a wall.
	var bd := BuildingDef.new()
	bd.mesh_size = Vector3(3.8, 3, 3.8)
	bd.bakes_into_navmesh = true
	var building := Building.new()
	building.def = bd
	building.cell = grid.world_to_grid(Vector3(13, 0, 13))
	building.footprint = Vector2i(2, 2)
	building.position = Vector3(14, 0, 14)
	world.add_child(building)
	grid.place(building.cell, building.footprint, building)
	EventBus.building_placed.emit(building, building.cell)
	var start := Vector3(11.5, 0, 16.5)
	var goal := Vector3(21, 0, 11)
	var path := nav.get_world_path(start, goal)
	var previous := start
	var safe := not path.is_empty()
	for point in path:
		safe = safe and nav.can_walk_segment(previous, point)
		previous = point
	check(safe, "off-center route segments include pawn clearance around wall corners")
	var edge_path := nav.get_world_path(Vector3(21, 0, 15), Vector3(16.1, 0, 15))
	check(not edge_path.is_empty() and nav.can_walk_segment(edge_path[-1], edge_path[-1]),
		"exact endpoint touching an adjacent wall resolves to a safe arrival")
	p = soldier(start)
	p.global_position = start # exercise actual off-center start, bypass spawn snapping
	p.set_navigation_target(goal, true)
	var routed := false
	for i in 420:
		await get_tree().physics_frame
		if p.move_along_path(get_physics_process_delta_time()):
			routed = true
			break
	check(routed and p.global_position.distance_to(goal) < 0.51, "pawn physically walks around building from off-center start")
	p.queue_free()
	grid.remove(building.cell, building.footprint)
	EventBus.building_removed.emit(building, building.cell)
	building.queue_free()
	await get_tree().physics_frame

	# A whole occupied column separates two otherwise empty areas.
	for z in grid.grid_size.y:
		nav.path_grid.set_point_solid(Vector2i(20, z), true)
	nav._invalidate_frame_cache()
	p = soldier(Vector3(5, 0, 15))
	p.set_navigation_target(Vector3(15, 0, 15), true)
	var origin := p.global_position
	for i in 30:
		await get_tree().physics_frame
		p.move_along_path(get_physics_process_delta_time())
	check(p.global_position.distance_to(origin) < 0.01, "unreachable route waits instead of charging directly into obstacles")
	check(not p.is_navigation_done(), "unreachable route is not reported as arrived")
	var attempts := p.stat_repaths
	for i in 120:
		await get_tree().physics_frame
		p.move_along_path(get_physics_process_delta_time())
	check(p.stat_repaths - attempts <= 3, "unreachable retries are bounded to once per second")
	p.queue_free()
	for z in grid.grid_size.y:
		nav.path_grid.set_point_solid(Vector2i(20, z), false)
	nav._invalidate_frame_cache()
	await get_tree().physics_frame

	# Combat positions stay stable as new peers arrive, and remain in attack range.
	var target := soldier(Vector3(15, 0, -15))
	var peers: Array[Pawn] = []
	for i in 8:
		var peer := soldier(Vector3(15, 0, -23))
		peer.combat_target = target
		peers.append(peer)
	var slot := peers[1].get_combat_approach_position(target)
	var all_in_range := true
	for peer in peers:
		var pos := peer.get_combat_approach_position(target)
		peer.global_position = pos
		all_in_range = all_in_range and peer.attacker.in_range(target)
	check(all_in_range, "all combat slots remain in attack range including seventh/eighth attacker")
	target.health.max_hp = 10000
	target.health.current_hp = 10000
	EventBus.damage_dealt.connect(_damage_seen)
	var hold_positions: Array[Vector3] = []
	for peer in peers:
		hold_positions.append(peer.global_position)
		peer.state_machine.transition_to("fight", {"target": target})
		peer.state_machine.set_physics_process(true)
	for i in 120:
		await get_tree().physics_frame
	var all_attacked := true
	var still := true
	for i in peers.size():
		var peer := peers[i]
		all_attacked = all_attacked and landed_hits.has(peer)
		still = still and peer.global_position.distance_to(hold_positions[i]) < 0.05
		peer.state_machine.set_physics_process(false)
	check(all_attacked, "eight attackers all deliver real hits from their assigned slots")
	check(still, "stationary-target melee combat holds position instead of pacing")
	EventBus.damage_dealt.disconnect(_damage_seen)
	peers[0].combat_target = null
	for i in 15:
		await get_tree().physics_frame
	check(peers[1].get_combat_approach_position(target).distance_to(slot) < 0.01,
		"combat slot does not rotate when another attacker disengages")
	for peer in peers:
		peer.queue_free()
	target.queue_free()
	await get_tree().physics_frame

	# Automatic reacquisition must not immediately select the same failed target.
	p = soldier(Vector3(-23, 0, 15))
	var retry_target: Raider = spawner.spawn_raider(Vector3(-11, 0, 15), enemy_def)
	retry_target.state_machine.set_physics_process(false)
	p.state_machine.transition_to("fight", {"target": retry_target})
	var fight := p.state_machine.current_state as FightState
	fight._handle_stuck(retry_target)
	check(p.find_nearest_hostile(40) == null, "failed auto engagement yields instead of cycling back to the same target")
	p._on_navmesh_updated()
	check(p.find_nearest_hostile(40) == retry_target, "obstacle update clears failed-target cooldown immediately")
	var leader := FocusLeader.new()
	leader.focus_target = retry_target
	world.add_child(leader)
	p.follow_leader = leader
	p.state_machine.transition_to("fight", {"target": retry_target})
	fight = p.state_machine.current_state as FightState
	p.navigation_status = Pawn.NavigationStatus.BLOCKED
	check(not fight._handle_stuck(retry_target) and p.state_machine.current_state == fight,
		"blocked explicit focus order waits without idle/follow/fight state thrashing")
	p.queue_free()
	retry_target.queue_free()
	leader.queue_free()
	await get_tree().physics_frame

	# Moving combat targets can submit every frame without a path-query storm.
	p = soldier(Vector3(5, 0, 25))
	for i in 180:
		await get_tree().physics_frame
		p.set_navigation_target(Vector3(25 + sin(float(i) * 0.3), 0, 25))
		p.move_along_path(get_physics_process_delta_time())
	check(p.stat_repaths <= 13, "per-frame moving target updates are limited to four repaths per second")
	p.queue_free()
	await get_tree().physics_frame

	# Physical obstacle missing from the grid: honest blocked outcome, no fake arrival.
	var blocker := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 2)
	col.shape = shape
	col.position.y = 1.5
	blocker.add_child(col)
	blocker.position = Vector3(-15, 0, -15)
	world.add_child(blocker)
	p = soldier(Vector3(-19, 0, -15))
	p.set_navigation_target(Vector3(-11, 0, -15), true)
	for i in 420:
		await get_tree().physics_frame
		p.set_navigation_target(Vector3(-11 + sin(float(i) * 0.3) * 0.1, 0, -15))
		p.move_along_path(get_physics_process_delta_time())
	check(p.navigation_status == Pawn.NavigationStatus.BLOCKED and not p.is_navigation_done(),
		"unregistered physical obstruction reports blocked without fake arrival")
	check(p.stat_stuck_recoveries <= 3, "small target updates do not reset stall detection or restart blocked routes")
	p.queue_free()
	blocker.queue_free()
	await get_tree().physics_frame

	# Query sharing includes siege path-cost evaluation.
	var from := Vector3(-23, 0, -23)
	var to := Vector3(-9, 0, -15)
	nav._invalidate_frame_cache()
	var before := nav.stat_astar_queries
	for i in 100:
		nav.get_world_path(from, to)
		nav.get_path_length(from, to)
	check(nav.stat_astar_queries - before == 1, "100 route + cost queries share one AStar result")
	check(nav.get_path_length(from, from) < 0.01, "same-position path cost is zero")
	print("NAVIGATION STABILITY TEST: %d checks, %d failure(s)" % [checks, failures])
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# Fixtures own every pawn in this isolated world; release shared weak slots.
	Pawn._combat_slots.clear()
	Pawn._spatial_buckets.clear()
	landed_hits.clear()
	get_tree().quit(0 if failures == 0 else 1)
