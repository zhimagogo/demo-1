extends Node
## ============================================================================
## v44 夜防阵型交付截图（Lead 专用；窗口模式，无头模式只做结构自检）
##   bash tools/godot_locked.sh --path . tools/v44_defense_shot.tscn
## 输出：
##   artifacts/v44-night-defense-east.png   东门内侧夜防阵列（等距俯视，近战前排/远程后排）
##   artifacts/v44-night-defense-rows.png   从城外看阵型的低机位（排数/朝向更直观）
##
## 关键：直接 emit EventBus.night_threat_direction_changed(true, 1, 东门内侧点)，
## 与 WildlifeSpawner 真实选门后的行为完全同一条公共接口；不读私有字段。
## ============================================================================

const SHOT_DIR := "res://artifacts"
const SHOT_SIZE := Vector2i(1600, 1000)
const EAST_GATE := 1
const WAIT_SECONDS := 11.0
const MAX_FRAMES := 24000

var _main: Node = null
var _world: Node3D = null
var _hud: Node = null
var _iso: IsometricCamera = null
var _nav: NavSystem = null
var _city: CitySystem = null
var _spawner: Node = null
var _failures: int = 0
var _saved: Array[String] = []
var _frames: int = 0
var _melee: Array = []
var _ranged: Array = []
var _inside := Vector3.ZERO


func _ready() -> void:
	get_window().size = SHOT_SIZE
	call_deferred("_run")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("[v44] 截图工具超时强制退出")
		get_tree().quit(2)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _frames_wait(count: int) -> void:
	for _i in maxi(count, 1):
		await get_tree().process_frame


func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _frames_wait(20)

	_world = _main.get_node_or_null("WorldRoot") as Node3D
	_check(_world != null, "WorldRoot exists")
	if _world == null:
		get_tree().quit(1)
		return
	_hud = _main.get_node_or_null("HUD")
	_nav = _world.get_node_or_null("NavSystem") as NavSystem
	_city = _world.get_node_or_null("CitySystem") as CitySystem
	_spawner = get_tree().get_first_node_in_group("pawn_spawner")
	_check(_nav != null and _city != null and _spawner != null, "nav / city / spawner wired")
	if _nav == null or _city == null or _spawner == null:
		get_tree().quit(1)
		return

	var wildlife := _world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		(wildlife as Node).set_process(false)
	var settlement := _world.get_node_or_null("SettlementSystem")
	if settlement != null:
		(settlement as Node).set_process(false)
		(settlement as Node).set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemy.queue_free()

	var controller := _world.get_node_or_null("HeroController") as HeroController
	if controller != null:
		controller.exit_hero_mode()
	_iso = _world.get_node_or_null("IsometricCamera") as IsometricCamera
	_check(_iso != null, "IsometricCamera exists")
	if _iso == null:
		get_tree().quit(1)
		return
	_iso.edge_pan = false
	_iso._yaw_step = 0
	_iso.follow_target = null
	_iso.make_current()
	_iso.set_process(true)
	TimeManager.begin(12.0)
	TimeManager.set_speed(1.0)
	await _frames_wait(4)

	_spawn_defenders()
	var p := WorldLayout.gate_inside_point(EAST_GATE)
	_inside = _nav.snap_to_walkable(Vector3(p.x, 0.0, p.y))
	EventBus.night_threat_direction_changed.emit(true, EAST_GATE, _inside)
	TimeManager.begin(21.0)
	TimeManager.freeze_clock()
	TimeManager.set_speed(1.0)
	await get_tree().create_timer(WAIT_SECONDS, true, false, false).timeout
	await _frames_wait(10)

	_hide_world_ui()
	if headless:
		_check_formation()
		print("[v44] 无头模式：跳过截图（自检失败 %d 项）" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return

	# 等距俯视：能同时看到城门内侧两排
	await _capture_iso("v44-night-defense-east", Vector3(20.0, 0.0, 1.0), 30.0, 0)
	# 正交俯视：两排间距 2.4m 在俯视下最清楚（近战一排 / 远程一排）
	await _capture_topdown("v44-night-defense-top")

	# 城外低机位：从东南向西北看，近战/远程排数与朝向更直观
	await _capture_outside("v44-night-defense-rows", Vector3(39.0, 9.0, 15.0), Vector3(16.0, 0.0, 0.5))

	print("[v44] 截图完成，共 %d 张，自检失败 %d 项" % [_saved.size(), _failures])
	for path in _saved:
		print("  · %s" % path)
	get_tree().quit(0 if _failures == 0 else 1)


func _spawn_defenders() -> void:
	var melee_points: Array[Vector3] = [
		Vector3(10.0, 0.0, -8.0), Vector3(10.0, 0.0, 0.0), Vector3(10.0, 0.0, 8.0),
		Vector3(5.0, 0.0, -4.0), Vector3(5.0, 0.0, 4.0),
	]
	var ranged_points: Array[Vector3] = [
		Vector3(0.0, 0.0, -7.0), Vector3(0.0, 0.0, 7.0), Vector3(-5.0, 0.0, -2.0), Vector3(-5.0, 0.0, 2.0),
	]
	for point in melee_points:
		var s: Pawn = _spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
			_nav.snap_to_walkable(point))
		if s is Soldier:
			_melee.append(s)
	for point in ranged_points:
		var s: Pawn = _spawner.call("spawn_soldier", GameDefs.settler_archer_def(),
			_nav.snap_to_walkable(point))
		if s is Soldier:
			_ranged.append(s)
	for s in _melee + _ranged:
		(s as Soldier).night_chat_cooldown = 999.0
		(s as Soldier).speech_bubble.debug_set_timer(999.0)
	_check(_melee.size() == 5 and _ranged.size() == 4,
		"defenders spawned (melee=%d ranged=%d)" % [_melee.size(), _ranged.size()])


func _hide_world_ui() -> void:
	if _hud != null:
		_hud.visible = false
	_hide_health_bars(_world)
	if _city != null and _city.border_visible:
		_city.toggle_border()


func _hide_health_bars(node: Node) -> void:
	if node == null:
		return
	if node is HealthBar3D:
		(node as HealthBar3D).visible = false
		(node as HealthBar3D).set_process(false)
	for child in node.get_children():
		_hide_health_bars(child)


func _check_formation() -> void:
	var all: Array = _melee + _ranged
	var near := 0
	for s in all:
		var soldier := s as Soldier
		if soldier.defense_active and soldier.defense_slot_valid \
				and soldier.global_position.distance_to(_inside) <= 14.0:
			near += 1
	_check(near == all.size(), "all defenders deploy near east gate (%d/%d)" % [near, all.size()])
	if _melee.is_empty() or _ranged.is_empty():
		return
	var melee_x := 0.0
	for s in _melee:
		melee_x += (s as Soldier).global_position.x
	melee_x /= float(_melee.size())
	var ranged_x := 0.0
	for s in _ranged:
		ranged_x += (s as Soldier).global_position.x
	ranged_x /= float(_ranged.size())
	_check(melee_x > ranged_x + 1.5,
		"melee rank is closer to east gate than ranged rank (melee x=%.2f, ranged x=%.2f)"
			% [melee_x, ranged_x])
	var facing_ok := 0
	for s in all:
		var soldier := s as Soldier
		var f := -soldier.global_transform.basis.z
		f.y = 0.0
		if f.normalized().dot(WorldLayout.gate_outward_dir(EAST_GATE)) > 0.6:
			facing_ok += 1
	_check(facing_ok == all.size(), "defenders face outward (%d/%d)" % [facing_ok, all.size()])


func _capture_iso(name: String, focus: Vector3, distance: float, yaw_step: int) -> void:
	_iso._yaw_step = yaw_step
	_iso.target_distance = distance
	_iso.focus_on(focus)
	_iso.snap_distance()
	await _frames_wait(8)
	await RenderingServer.frame_post_draw
	_save_frame(name)


func _capture_topdown(name: String) -> void:
	var center := Vector3.ZERO
	var count := 0
	for s in _melee + _ranged:
		if is_instance_valid(s):
			center += (s as Node3D).global_position
			count += 1
	if count <= 0:
		return
	center /= float(count)
	center.y = 0.0
	var cam := Camera3D.new()
	cam.name = "V44TopCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 13.0
	_world.add_child(cam)
	cam.global_position = center + Vector3(0.0, 20.0, 0.0)
	cam.look_at(center, Vector3(0.0, 0.0, -1.0))
	cam.current = true
	await _frames_wait(8)
	await RenderingServer.frame_post_draw
	_save_frame(name)
	cam.queue_free()


func _capture_outside(name: String, eye: Vector3, target: Vector3) -> void:
	var cam := Camera3D.new()
	cam.name = "V44ShotCamera"
	cam.fov = 52.0
	_world.add_child(cam)
	cam.global_position = eye
	cam.look_at(target)
	cam.current = true
	await _frames_wait(8)
	await RenderingServer.frame_post_draw
	_save_frame(name)
	cam.queue_free()


func _save_frame(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	if image.save_png(path) == OK:
		_saved.append(path)
		print("[v44] 截图 %s（%dx%d）" % [path, image.get_width(), image.get_height()])
	else:
		_check(false, "保存截图 %s" % path)
