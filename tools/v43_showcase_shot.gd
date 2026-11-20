extends Node
## ============================================================================
## v43 三项需求交付截图工具（Lead 专用；窗口模式，无头模式只做结构自检）
##   bash tools/godot_locked.sh --path . tools/v43_showcase_shot.tscn
## 输出：
##   artifacts/v43-city-day-overview.png   52×52m 新城 + 放大房屋/酒馆/土路
##   artifacts/v43-house-occupied.png      已入住暖色房屋 vs 空房对照
##   artifacts/v43-night-vigil-wide.png    夜晚城内待命氛围（暖窗 / 火炬 / 站定小兵）
##   artifacts/v43-night-vigil-chat.png    2~3 人夜间闲聊特写
##   artifacts/v43-water-overview.png      新湖泊 + 瀑布全景（与世界水系任务互为对照）
##
## 注意：
##  - 抓帧前 ≥4 个 process 帧 + frame_post_draw；相机视距用 snap_distance 立即对齐。
##  - 无头模式跳过截图，只检查世界/城市/建筑/夜间状态接口后 quit。
##  - 任何路径都会 quit；另挂看门狗，防止脚本异常导致 godot 进程挂死。
## ============================================================================

const SHOT_DIR := "res://artifacts"
const SHOT_SIZE := Vector2i(1600, 1000)
const MAX_FRAMES := 30000

var _main: Node = null
var _world: Node3D = null
var _hud: Node = null
var _iso: IsometricCamera = null
var _spawner: Node = null
var _build: BuildSystem = null
var _failures: int = 0
var _saved: Array[String] = []
var _frames: int = 0
var _soldiers: Array = []
var _occupied_houses: Array = []
var _empty_houses: Array = []


func _ready() -> void:
	get_window().size = SHOT_SIZE
	call_deferred("_run")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		push_error("[v43] 截图工具超时（%d 帧）强制退出" % MAX_FRAMES)
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
	_spawner = get_tree().get_first_node_in_group("pawn_spawner")
	_build = _world.get_node_or_null("BuildSystem") as BuildSystem
	_check(_spawner != null and _build != null, "pawn spawner / build system wired")
	if _spawner == null or _build == null:
		get_tree().quit(1)
		return

	# 停刷怪 / 流民，清场：截图不展示战斗，入住状态可控。
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

	# 俯视等距相机取景（exits hero mode：建造无 20m 距离限制）。
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

	_build_town()
	await get_tree().physics_frame
	await _frames_wait(10)
	_spawn_town_soldiers()
	await get_tree().physics_frame
	await _frames_wait(10)
	_hide_world_ui()

	if headless:
		_check_structure()
		print("[v43] 无头模式：跳过截图（自检失败 %d 项）" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
		return

	if _hud != null:
		_hud.visible = false

	# ---- 1) 新城白昼全景 ----
	await _capture("v43-city-day-overview", Vector3(0.0, 0.0, 0.0), 46.0)

	# ---- 2) 已入住 vs 空房特写（东侧两栋） ----
	await _capture("v43-house-occupied", Vector3(16.0, 0.0, -11.0), 20.0)

	# ---- 3) 夜晚待命氛围 ----
	TimeManager.begin(21.0)
	TimeManager.freeze_clock()   # 钉在 21:00（不影响 AI 物理推进），避免 clock 走到天亮
	TimeManager.set_speed(1.0)
	await _wait_seconds(7.0)
	_force_night_chat_if_needed()
	var chat_center := _find_night_chat_center()
	if chat_center != Vector3.INF:
		await _capture("v43-night-vigil-chat", chat_center, 16.0)
	await _capture("v43-night-vigil-wide", Vector3(0.0, 0.0, -6.0), 42.0)

	# ---- 4) 新水系白昼全景（供三项需求合并验收） ----
	TimeManager.unfreeze_clock()
	TimeManager.begin(12.0)
	TimeManager.set_speed(1.0)
	await _wait_seconds(1.2)
	await _capture("v43-water-overview", Vector3(54.0, 0.0, -52.0), 58.0)

	print("[v43] 截图完成，共 %d 张，自检失败 %d 项" % [_saved.size(), _failures])
	for path in _saved:
		print("  · %s" % path)
	get_tree().quit(0 if _failures == 0 else 1)


# ============================================================================
# 城内小样：土路十字 + 5 栋房屋 + 酒馆；3 栋入住、2 栋空房
# ============================================================================

func _build_town() -> void:
	ResourceManager.add(GameDefs.GOLD, 5000)
	var house_def: BuildingDef = null
	var tavern_def: BuildingDef = null
	var road_def: BuildingDef = null
	for d in GameDefs.building_defs():
		match d.id:
			&"house": house_def = d
			&"tavern": tavern_def = d
			&"dirt_road": road_def = d
	_check(house_def != null and tavern_def != null and road_def != null, "building defs available")
	if house_def == null or tavern_def == null or road_def == null:
		return

	# 先放建筑，再铺十字土路（避免路面被建筑占格打断时留下缺口）。
	# 直接用 current_def + try_place_at：enter_build_mode 会自动切第三人称并受 20m
	# 建造距离限制，截图工具需要保持等距相机全城取景。
	var house_spots: Array[Vector3] = [
		Vector3(11.0, 0.0, -11.0),
		Vector3(11.0, 0.0, 11.0),
		Vector3(-11.0, 0.0, -11.0),
		Vector3(-11.0, 0.0, 11.0),
		Vector3(21.0, 0.0, -11.0),
	]
	_build.current_def = house_def
	_build.current_rotation = 0
	for spot in house_spots:
		_build.try_place_at(spot)
	_build.current_def = tavern_def
	_build.try_place_at(Vector3(-21.0, 0.0, 11.0))

	# 十字土路：南北 / 东西两段，中间城堡占格自动跳过。
	_build.current_def = road_def
	_build.begin_road_stroke(Vector3(0.0, 0.0, -25.0))
	_build.paint_road_to(Vector3(0.0, 0.0, 25.0))
	_build.end_road_stroke()
	_build.begin_road_stroke(Vector3(-25.0, 0.0, 0.0))
	_build.paint_road_to(Vector3(25.0, 0.0, 0.0))
	_build.end_road_stroke()
	_build.current_def = null

	var houses: Array = []
	for node in get_tree().get_nodes_in_group("house"):
		if node is Building and is_instance_valid(node):
			houses.append(node)
	_check(houses.size() >= 3, "houses placed (%d)" % houses.size())
	# 入住对照：选离东侧 (11,-11) 最近的一栋入住，其余三栋入住形成暖色群，
	# 剩余（至少一栋）保持空房，供白昼 / 夜晚画面对照。
	var occupied_targets: Array[Vector3] = [
		Vector3(11.0, 0.0, -11.0), Vector3(11.0, 0.0, 11.0), Vector3(-11.0, 0.0, -11.0),
	]
	var pool := houses.duplicate()
	for target in occupied_targets:
		var best: Building = null
		var best_d := INF
		for node in pool:
			var b := node as Building
			var d: float = b.global_position.distance_squared_to(target)
			if d < best_d:
				best_d = d
				best = b
		if best != null:
			_occupied_houses.append(best)
			pool.erase(best)
	for node in pool:
		_empty_houses.append(node as Building)
	if _occupied_houses.is_empty() and not houses.is_empty():
		_occupied_houses.append(houses[0])
		_empty_houses.erase(houses[0])


func _spawn_town_soldiers() -> void:
	# 3 个住进东侧/北侧房屋（入住颜色来源），另外 3 个无家士兵用于夜间群聊。
	var homes: Array = _occupied_houses.duplicate()
	if homes.is_empty():
		for node in get_tree().get_nodes_in_group("house"):
			homes.append(node)
	for i in mini(homes.size(), 3):
		var home := homes[i] as Building
		var soldier: Pawn = _spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
			home.global_position + Vector3(0.0, 0.0, 3.2))
		if soldier != null:
			home.assign_resident(soldier)
			_soldiers.append(soldier)
	for i in 3:
		var p := Vector3(-4.0 + float(i) * 4.0, 0.0, -4.0)
		var soldier: Pawn = _spawner.call("spawn_soldier", GameDefs.settler_mage_def(), p)
		if soldier != null:
			_soldiers.append(soldier)
	_check(_soldiers.size() >= 4, "town soldiers spawned (%d)" % _soldiers.size())


# ============================================================================
# 夜晚群聊：优先等 AI 自发形成 2~3 人群聊（最多 20s），不强行改状态机（截图工具不参与回归）
# ============================================================================

func _force_night_chat_if_needed() -> void:
	# v43 截图工具：优先等待 AI 自发群聊（最多 20s）；不强行改状态机（强行跨状态
	# 转换会被 Soldier._update_daily_life 的昼夜兜底打断，导致画面里变成白天双人 chat）。
	for _i in 20:
		if _find_night_chat_center() != Vector3.INF:
			return
		await _wait_seconds(1.0)
	print("[v43] WARN: no AI night_chat formed within 20s; skip chat close-up (wide shot still captured)")


## 截图干净：隐藏世界内血条 / 主城边框线（HUD 另外整层隐藏）。
func _hide_world_ui() -> void:
	_hide_health_bars(_world)
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	if city != null and city.border_visible:
		city.toggle_border()


func _hide_health_bars(node: Node) -> void:
	if node == null:
		return
	if node is HealthBar3D:
		(node as HealthBar3D).visible = false
		(node as HealthBar3D).set_process(false)
	for child in node.get_children():
		_hide_health_bars(child)


func _find_night_chat_center() -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for s in _soldiers:
		if not is_instance_valid(s) or not (s is Soldier):
			continue
		var st: Node = (s as Soldier).state_machine
		if st == null or st.current_state == null:
			continue
		if String(st.current_state.name) == "night_chat":
			total += (s as Soldier).global_position
			count += 1
	if count < 2:
		return Vector3.INF
	return total / float(count)


# ============================================================================
# 抓帧
# ============================================================================

func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, false).timeout


func _capture(name: String, focus: Vector3, distance: float) -> void:
	_iso.target_distance = distance
	_iso.focus_on(focus)
	_iso.snap_distance()
	TimeManager.set_speed(0.0)   # 定格：单位 / AI / 粒子不再推进，水面 TIME 继续
	await _frames_wait(8)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, name]
	var err := image.save_png(path)
	if err == OK:
		_saved.append(path)
		print("[v43] 截图 %s（%dx%d）" % [path, image.get_width(), image.get_height()])
	else:
		_check(false, "保存截图 %s（err=%d）" % [path, err])
	TimeManager.set_speed(1.0)


# ============================================================================
# 无头结构自检
# ============================================================================

func _check_structure() -> void:
	_check(is_equal_approx(WorldLayout.CITY_HALF, 26.0), "city half is 26m (%.1f)" % WorldLayout.CITY_HALF)
	_check(get_tree().get_nodes_in_group("house").size() >= 3, "town houses exist")
	_check(get_tree().get_nodes_in_group("tavern").size() == 1, "tavern exists")
	_check(not _occupied_houses.is_empty(), "at least one occupied house")
	for b in _occupied_houses:
		if is_instance_valid(b):
			_check((b as Building).is_occupied(), "occupied house visual state (%s)" % b.name)
			break
	for b in _empty_houses:
		if is_instance_valid(b):
			_check(not (b as Building).is_occupied(), "empty house visual state (%s)" % b.name)
			break
	_check(TimeManager.is_night() == false, "daylight baseline")
