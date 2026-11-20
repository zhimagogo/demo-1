extends Node
## Real AI state transitions around city/leash boundaries; navigation-only tests
## cannot catch a roam/fight loop that cancels movement every other frame.
var failures := 0
var checks := 0
var world: Node3D
var city: CitySystem
var nav: NavSystem
var spawner: Node

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func monster(at: Vector3) -> Raider:
	var d := PawnDef.new()
	d.team = TeamComponent.Team.ENEMY
	d.max_hp = 10000
	d.attack_damage = 0
	d.flee_hp_ratio = 0
	var r: Raider = spawner.spawn_raider(at, d)
	r.state_machine.set_physics_process(false)
	return r

func player(at: Vector3) -> Pawn:
	var d := PawnDef.new()
	d.is_auto_fighter = false
	d.max_hp = 10000
	var p: Pawn = spawner.spawn_soldier(d, at)
	p.state_machine.set_physics_process(false)
	p.global_position = at
	return p

func _run() -> void:
	seed(20261002)
	AudioManager._streams[&"hit_1"] = null
	AudioManager._streams[&"hit_2"] = null
	TimeManager.begin(12)
	TimeManager.set_speed(1)
	world = Node3D.new()
	add_child(world)
	var grid := GridSystem.new()
	grid.name = "GridSystem"
	grid.grid_size = Vector2i(64, 64)
	grid.debug_visible = false
	world.add_child(grid)
	nav = NavSystem.new()
	world.add_child(nav)
	city = CitySystem.new()
	city.city_half = WorldLayout.CITY_HALF   # v43：与主城 52×52m 同步（26m 半宽）；下列边界坐标同步 +6m
	city.border_visible = false
	world.add_child(city)
	var players := Node3D.new()
	world.add_child(players)
	var enemies := Node3D.new()
	world.add_child(enemies)
	spawner = load("res://scripts/systems/PawnSpawner.gd").new()
	world.add_child(spawner)
	spawner.configure(players, enemies)
	await get_tree().physics_frame

	var r := monster(Vector3(23, 0, 35))
	var p := player(Vector3(42, 0, 35))
	r.global_position = Vector3(40, 0, 35) # outside its spawn leash
	r.state_machine.transition_to("fight", {"target": p})
	var transitions := 0
	for i in 60:
		await get_tree().physics_frame
		var before: PawnState = r.state_machine.current_state
		before.physics_update(1.0 / 60.0)
		if before != r.state_machine.current_state:
			transitions += 1
	check(transitions <= 2, "outside leash returns home without roam/fight cycling (%d switches)" % transitions)
	check(r.global_position.x < 39, "leashed monster makes actual progress toward its home")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	r = monster(Vector3(27, 0, 0))
	p = player(Vector3(26.1, 0, 0))
	check(r.find_nearest_hostile() == p, "city-edge target initially acquired")
	p.global_position.x = 25.9
	check(r.find_nearest_hostile() == null, "cached target immediately rejected after entering city")
	r.global_position.x = 25.9
	p.global_position.x = 27.1
	check(r.find_nearest_hostile() == null, "monster inside city escapes before acquiring an outside target")
	r.global_position = Vector3(27, 0, 0)
	p.global_position = Vector3(26.1, 0, 0)
	var safe_slots := true
	var occupied: Dictionary = {}
	var peers: Array[Raider] = []
	for slot in 6:
		var peer := monster(Vector3(27, 0, float(slot)))
		peer.combat_target = p
		var approach := peer.get_combat_approach_position(p)
		occupied[peer._approach_slot] = true
		safe_slots = safe_slots and not city.is_in_city(approach)
		peers.append(peer)
	check(safe_slots and occupied.size() == 6, "six distinct melee approach slots stay outside city for a boundary target")
	for peer in peers:
		peer.queue_free()
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	r = monster(Vector3(27, 0, 25))
	r.state_machine.transition_to("roam")
	await get_tree().process_frame
	var safe_roam := true
	var bounded_roam := true
	for i in 120:
		r.global_position = Vector3(27, 0, 25)
		r.state_machine.current_state.call("_pick_roam_point")
		var path := nav.get_world_path(r.global_position, r._nav_target)
		var prev := r.global_position
		for point in path:
			for k in 21:
				safe_roam = safe_roam and not city.is_in_city(prev.lerp(point, float(k) / 20.0))
			prev = point
		bounded_roam = bounded_roam and r._nav_target.distance_to(r.home_position) <= Raider.LEASH_RANGE
	check(safe_roam, "corner roaming routes avoid crossing the city interior")
	check(bounded_roam, "roaming destinations remain within spawn leash")
	for i in 100:
		r.state_machine.current_state.call("_pick_roam_point")
		bounded_roam = bounded_roam and r._nav_target.distance_to(r.home_position) <= Raider.LEASH_RANGE
		r.global_position = r._nav_target
	check(bounded_roam, "consecutive roaming steps cannot drift beyond the leash")
	check(city.segment_crosses_city(Vector3(27, 0, 25), Vector3(25, 0, 27)), "city segment test catches a corner crossing")
	check(not city.segment_crosses_city(Vector3(27, 0, 25), Vector3(27, 0, 31), 0.5), "city segment test allows parallel outside travel")
	r.global_position = Vector3(27, 0, 25)
	p = player(Vector3(32, 0, 27))
	r.state_machine.transition_to("fight", {"target": p})
	var new_order := Vector3(36, 0, 36)
	r.state_machine.transition_to("idle")
	r.set_navigation_target(new_order, true)
	await get_tree().process_frame
	check(r._nav_target.distance_to(new_order) < 0.01, "deferred combat callback cannot overwrite a later navigation order")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# Complete a city escape before reacquiring; completing only half of the
	# retreat is the other source of boundary oscillation.
	r = monster(Vector3(31, 0, 0))
	p = player(Vector3(29, 0, 0))
	r.global_position = Vector3(25.9, 0, 0)
	r.state_machine.transition_to("roam")
	await get_tree().process_frame
	r.global_position.x = 26.1
	r.state_machine.current_state.physics_update(1.0 / 60.0)
	check(r.state_machine.current_state is RoamState, "city escape holds until reaching the outside safety buffer")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# A target outside another edge can still require a route through town.
	r = monster(Vector3(27, 0, 23))
	p = player(Vector3(23, 0, 27))
	r.state_machine.transition_to("fight", {"target": p})
	await get_tree().process_frame
	r.state_machine.current_state.physics_update(1.0 / 60.0)
	check(r.state_machine.current_state is RoamState and r.find_nearest_hostile() == null,
		"local pursuit rejects city-crossing route and yields without reacquiring the target")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# Cache validity is independent of its 0.2s scan throttle.
	r = monster(Vector3(35, 0, -25))
	p = player(Vector3(36, 0, -25))
	check(r.find_nearest_hostile() == p, "cache probe acquires a live target")
	p.is_dead_flag = true
	check(r.find_nearest_hostile() == null, "cached corpse is immediately rejected")
	p.is_dead_flag = false
	r._aggro_cache_frame = -100
	r.find_nearest_hostile()
	p.global_position.x = 55
	check(r.find_nearest_hostile() == null, "cached target leaving aggro range is immediately rejected")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# Flee safety is a wider radius than combat acquisition (17m vs 11m).
	r = monster(Vector3(29, 0, -25))
	p = player(Vector3(29, 0, -38))
	r.health.current_hp = 100
	r.state_machine.transition_to("raider_flee", {"threat": p})
	var hp := r.health.current_hp
	r.state_machine.current_state.physics_update(1.0 / 60.0)
	check(r.health.current_hp == hp and r.velocity.length() > 0, "fleeing monster does not rest with a threat 13m away")
	p.global_position = r.global_position + Vector3(18, 0, 0)
	r.state_machine.current_state.physics_update(0.21)
	var resting_hp := r.health.current_hp
	p.global_position = r.global_position + Vector3(16, 0, 0)
	r.state_machine.current_state.physics_update(0.21)
	check(r.health.current_hp > resting_hp and r.velocity.length() == 0, "resting monster stays settled when threat oscillates near the safety edge")
	p.global_position = r.global_position + Vector3(14, 0, 0)
	var resumed_hp := r.health.current_hp
	r.state_machine.current_state.physics_update(0.21)
	check(r.health.current_hp == resumed_hp and r.velocity.length() > 0, "closer threat resumes fleeing instead of sliding with idle animation")
	r.state_machine.transition_to("idle")
	check(is_equal_approx(r.move_speed, r.def.move_speed), "leaving flee restores original movement speed")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# ---- v35 逃跑概率签：低血是否逃跑由一次性掷签决定（flee_chance）
	# ---- v44 进攻意图（assaulting / _sieging）强制死战，低血也不许撤退 ----
	r = monster(Vector3(29, 0, -25))
	r.def.flee_hp_ratio = 0.3
	r.def.flee_chance = 1.0
	r.health.current_hp = 20
	check(r.should_flee_now() and r.should_flee_now(), "flee_chance 1.0 keeps deterministic low-hp flee")
	r._flee_will = -1
	r.def.flee_chance = 0.0
	check(not r.should_flee_now() and not r.should_flee_now(), "flee_chance 0.0 never flees at low hp")
	r._flee_will = -1
	r.def.flee_chance = 0.5
	var will: bool = r.should_flee_now()
	var stable_will := true
	for i in 10:
		stable_will = stable_will and r.should_flee_now() == will
	check(stable_will, "flee will is rolled once and never re-rolled per monster")
	r.health.current_hp = 9000
	check(not r.should_flee_now(), "healthy monster stays in the fight")
	r.health.current_hp = 20
	check(r.should_flee_now() == will, "dropping to low hp again reuses the first roll")
	r._sieging = true
	check(not r.should_flee_now(), "sieging monsters fight to the death regardless of roll")
	r._sieging = false
	r.assaulting = true
	check(not r.should_flee_now(), "assaulting night-wave monsters never flee at low hp")
	r.assaulting = false
	r.queue_free()
	await get_tree().physics_frame

	# FightState 低血门端到端：掷中怂签才切 raider_flee，死战签留在 fight
	r = monster(Vector3(29, 0, -25))
	p = player(Vector3(32, 0, -25))
	r.def.flee_hp_ratio = 0.3
	r.def.flee_chance = 1.0
	r.health.current_hp = 20
	r.state_machine.transition_to("fight", {"target": p})
	r.state_machine.current_state.physics_update(1.0 / 60.0)
	check(r.state_machine.current_state is RaiderFleeState, "fight exits into raider_flee when the roll says run")
	r.state_machine.transition_to("idle")
	r.def.flee_chance = 0.0
	r._flee_will = -1
	r.state_machine.transition_to("fight", {"target": p})
	r.state_machine.current_state.physics_update(1.0 / 60.0)
	check(r.state_machine.current_state is FightState, "fight holds when the roll says stand and die")
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	TimeManager.begin(22)
	r = monster(Vector3(30, 0, 30))
	p = player(Vector3(33, 0, 30))
	var other := player(Vector3(27, 0, 30))
	r.assaulting = true
	r._on_damaged(1, p)
	check(r.combat_target == p, "siege first hit immediately retaliates")
	var retargets := 0
	for i in 24:
		var before: Node = r.combat_target
		r._on_damaged(1, other if i % 2 == 0 else p)
		if before != r.combat_target:
			retargets += 1
	check(retargets == 0, "multiple attackers do not turn the monster back and forth (%d retargets)" % retargets)
	p.is_dead_flag = true
	r._on_damaged(1, other)
	check(r.combat_target == other, "retaliation can replace a dead target immediately")
	r.queue_free()
	p.queue_free()
	other.queue_free()
	await get_tree().physics_frame

	# ---- v35 攻城怪被打还手：stuck 不得切回建筑，附近无玩家单位才恢复攻城 ----
	r = monster(Vector3(30, 0, 30))
	p = player(Vector3(33, 0, 30))
	var wall := StaticBody3D.new()
	wall.add_to_group("building")
	world.add_child(wall)
	wall.global_position = Vector3(27, 0, 30)
	r.assaulting = true
	r.state_machine.transition_to("fight", {"target": p, "siege": true})
	var assault_fight: FightState = r.state_machine.current_state
	var kept: bool = assault_fight._handle_stuck(p)
	check(not kept and r.state_machine.current_state == assault_fight and assault_fight.target == p,
		"sieging raider stuck while fighting a player unit keeps retaliating (no building retarget)")
	p.global_position = Vector3(60, 0, 60)
	var resumed_siege: bool = assault_fight._handle_stuck(p)
	check(resumed_siege and assault_fight.target == wall,
		"sieging raider resumes the assault once no player unit remains in reach")
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Pawn._combat_slots.clear()
	Pawn._spatial_buckets.clear()
	print("MONSTER BEHAVIOR STABILITY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
