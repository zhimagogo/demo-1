extends Node
## 自动行走演示：主角走 L 形、停步回弹，再折返；用真实 HeroIdleState 移动和动画。
var _hero: Hero
var _elapsed := 0.0
var _running := false
var _world: Node3D

func _ready() -> void:
	get_tree().create_timer(90.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")

func _run() -> void:
	get_window().size = Vector2i(1280, 800)
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_world = main.get_node("WorldRoot") as Node3D
	for sys_name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem", "HeroController"]:
		_world.get_node(sys_name).set_process(false)
		_world.get_node(sys_name).set_physics_process(false)
	main.get_node("HUD").hide()
	TimeManager.begin(12.0)
	TimeManager.clock_frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hero = main.get("hero") as Hero
	_hero.global_position = Vector3(8, 0, 10)
	_hero.velocity = Vector3.ZERO
	var camera := Camera3D.new()
	camera.fov = 52.0
	camera.far = 200.0
	add_child(camera)
	var focus := Vector3(12, 0, 13)
	camera.position = focus + Vector3(0, 10, 9)
	camera.look_at(focus)
	camera.make_current()
	_running = true

func _physics_process(delta: float) -> void:
	if not _running: return
	_elapsed += delta
	var destination := Vector3(8, 0, 10)
	var walking := false
	if _elapsed >= 1.0 and _elapsed < 3.1:
		destination = Vector3(16, 0, 10)
		walking = true
	elif _elapsed >= 3.1 and _elapsed < 4.8:
		destination = Vector3(16, 0, 16)
		walking = true
	elif _elapsed >= 4.8 and _elapsed < 7.6:
		destination = _hero.global_position
	elif _elapsed >= 7.6 and _elapsed < 9.8:
		destination = Vector3(8, 0, 16)
		walking = true
	else:
		destination = _hero.global_position
	var offset := destination - _hero.global_position
	offset.y = 0
	_hero.desired_velocity = offset.normalized() * 4.0 if walking and offset.length() > 0.12 else Vector3.ZERO
	if _hero.desired_velocity.length() > 0.01:
		_hero.look_at_target(destination)
	if _elapsed >= 12.2:
		print("GRASS WALK COMPLETE: hero=%s active_cells=%d" % [str(_hero.global_position), (_world.get_node("Decorations/DecorationScatter") as DecorationScatter).lawn_interaction._cells.size()])
		get_tree().quit()
