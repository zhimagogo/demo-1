extends Node
## ============================================================================
## v43 需求①：已入住房屋视觉专项回归（空房 / 已入住 / 住户消失 三态）
##   bash tools/godot_locked.sh --headless --path . tests/HouseOccupancyTest.tscn \
##        --log-file /tmp/house-occupied.log --fixed-fps 60
##
## 覆盖：
##   0. 空房基线：is_occupied=false、模型无染色、门口 OmniLight 关闭且不投影（range 4~5m）。
##   1. 入住：暖色乘色 + 暖自发光、门口暖光夜间亮（不重建节点）。
##   2. 昼间：暖光熄灭，但已入住暖色保持。
##   3. 住户 queue_free：材质恢复原始 albedo（不污染共享 atlas）、无残留 surface override、
##      暖光熄灭、房屋可再次招租。
##   4. 住户死亡：死亡当帧即回空房外观（is_dead_flag 路径），尸体真正 queue_free 后仍然空房。
##   5. 占位 BoxMesh：albedo 同步暖色并在空房时还原。
##   6. 带住户拆房：房屋先释放、住户后释放，全程只经 is_instance_valid 判断，不得访问已释放实例。
##
## 输出保持 ASCII（headless 日志中文会乱码）；直接调 API，不依赖真实鼠标输入。
## ============================================================================

var _failures: int = 0
var _finished: bool = false
var _main: Node


func _ready() -> void:
	call_deferred("_watchdog")
	call_deferred("_run")


## 看门狗：GDScript 运行时错误 / 并行类缓存污染会让 _run 协程中途停摆、永不 quit，
## 进而带挂整批测试。这里 120s 后强制 quit(1)（外层还会加 --quit-after 兜底）。
func _watchdog() -> void:
	await get_tree().create_timer(120.0, true, false, true).timeout
	if _finished:
		return
	_failures += 1
	push_error("FAIL: watchdog timeout - test did not reach _finish()")
	print("HOUSE OCCUPANCY: %d failure(s) (watchdog)" % _failures)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


## 先等物理帧（队列释放 / 状态机落地）再等 idle 帧（_process 里的昼夜暖光同步）。
func _wait(physics: int = 1, idle: int = 1) -> void:
	for _i in physics:
		await get_tree().physics_frame
	for _i in idle:
		await get_tree().process_frame


func _finish() -> void:
	_finished = true
	print("HOUSE OCCUPANCY: %d failure(s)" % _failures)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _run() -> void:
	# ---------------- 启动主场景（同其余回归场景的取世界方式） ----------------
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var build := world.get_node_or_null("BuildSystem") as BuildSystem
	# 停刷野怪 / 流民并清场：入住状态必须确定性，不能被袭击或自动迁入干扰
	var wildlife := world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	# 夜间 + 补金币（建造房屋）；TimeManager.hour 由其 _process 从 game_seconds 换算
	TimeManager.game_seconds = 22.0 / 24.0 * TimeManager.seconds_per_day
	ResourceManager.add(GameDefs.GOLD, 1000)
	await _wait(2, 2)
	_check(TimeManager.is_night(), "clock pinned to night before warm-light checks")
	if spawner == null or build == null:
		_check(false, "pawn spawner / BuildSystem available")
		_finish()
		return

	# ---------------- 找房屋 def（数值可能被并行任务调整，只取实际 def 字段） ----------------
	var house_def: BuildingDef = null
	for d in GameDefs.building_defs():
		var bd := d as BuildingDef
		if bd != null and bd.id == &"house":
			house_def = bd
	_check(house_def != null and house_def.model_path != "", "house def with glTF model found")
	if house_def == null:
		_finish()
		return

	# ---------------- 0. 空房基线 ----------------
	build.enter_build_mode(house_def)
	build.try_place_at(Vector3(8.0, 0.0, 8.0))
	build.exit_build_mode()
	await _wait(2, 2)
	var houses := get_tree().get_nodes_in_group("house")
	_check(houses.size() == 1, "one house placed via BuildSystem (%d)" % houses.size())
	if houses.is_empty():
		_finish()
		return
	var house := houses[0] as Building
	var rig := house.get_node_or_null("ModelRig") as BuildingModelRig
	var light := house.get_node_or_null("OccupancyLight") as OmniLight3D
	var lantern := house.get_node_or_null("OccupancyLantern") as MeshInstance3D
	_check(rig != null, "house has BuildingModelRig")
	_check(rig != null and rig.has_model(), "house glTF model loaded in headless")
	_check(light != null, "house owns a reusable OccupancyLight node")
	_check(light != null and not light.shadow_enabled, "occupancy light casts no shadow")
	_check(light != null and light.omni_range >= 4.0 and light.omni_range <= 5.0,
		"occupancy light range within 4-5m (%.1f)" % (light.omni_range if light != null else 0.0))
	_check(lantern != null and lantern is MeshInstance3D, "house owns a reusable OccupancyLantern marker")
	if lantern != null:
		_check(lantern.position.z > 1.0 and lantern.position.y > 0.8,
			"lantern anchor sits outside the front wall (y %.2f z %.2f)" % [lantern.position.y, lantern.position.z])
	_check(Building.OCCUPIED_TINT.r >= 1.4 and Building.OCCUPIED_TINT.b <= 0.6,
		"occupied tint is strongly warm (r %.2f g %.2f b %.2f)" % [
			Building.OCCUPIED_TINT.r, Building.OCCUPIED_TINT.g, Building.OCCUPIED_TINT.b])
	_check(Building.OCCUPIED_EMISSION.r >= 0.16,
		"occupied emission is strong enough (r %.2f)" % Building.OCCUPIED_EMISSION.r)
	_check(not house.is_occupied() and house.has_vacancy(), "new house is empty")
	_check(rig != null and not rig.has_occupancy_tint(), "empty house model is untinted")
	_check(light != null and not light.visible and light.light_energy == 0.0,
		"empty house door light is off")
	_check(lantern != null and not lantern.visible, "empty house lantern marker is hidden")
	var base_albedos: Array[Color] = []
	if rig != null:
		_collect_albedos(rig, base_albedos)
	_check(base_albedos.size() > 0, "house surfaces readable for tint checks (%d)" % base_albedos.size())

	# ---------------- 1. 入住（夜间）：暖色 + 暖光 ----------------
	var first: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
		house.global_position + Vector3(3.0, 0.0, 3.0)) as Pawn
	await _wait(2, 1)
	if first == null or not is_instance_valid(first):
		_check(false, "test soldier spawned")
		_finish()
		return
	house.assign_resident(first)
	await _wait(1, 2)
	_check(house.is_occupied(), "house reports occupied after assign_resident")
	_check(house.resident == first, "house resident points at assigned soldier")
	_check(not house.has_vacancy(), "occupied house has no vacancy")
	_check(rig != null and rig.has_occupancy_tint(), "occupied house model is tinted")
	_check(rig != null and rig.occupancy_tint_color().is_equal_approx(Building.OCCUPIED_TINT),
		"occupied tint equals warm Building.OCCUPIED_TINT")
	_check(rig != null and _has_warm_emission(rig), "occupied house materials carry warm emission")
	var occupied_albedos: Array[Color] = []
	if rig != null:
		_collect_albedos(rig, occupied_albedos)
	_check(_albedos_differ(base_albedos, occupied_albedos), "occupied surfaces differ from empty baseline")
	_check(light != null and light.visible and light.light_energy >= 1.0,
		"occupied house door light is on at night (energy %.2f)" % (light.light_energy if light != null else 0.0))
	_check(lantern != null and lantern.visible, "occupied house lantern marker is visible")
	if lantern != null:
		var lmat := lantern.material_override as StandardMaterial3D
		_check(lmat != null and lmat.emission_enabled and lmat.emission.r > 0.2,
			"occupied lantern carries warm emissive material")

	# ---------------- 2. 昼间：暖光熄灭、暖色 + 灯笼保留 ----------------
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day
	await _wait(1, 3)
	_check(not TimeManager.is_night(), "clock moved to noon")
	_check(light != null and not light.visible and light.light_energy == 0.0,
		"door light is off in daytime")
	_check(rig != null and rig.has_occupancy_tint(), "occupancy tint persists by day")
	_check(lantern != null and lantern.visible, "lantern marker stays visible by day (daytime color cue)")

	# ---------------- 3. 共享 atlas 隔离：隔壁空房不受染色影响 ----------------
	build.enter_build_mode(house_def)
	build.try_place_at(Vector3(-8.0, 0.0, 8.0))
	build.exit_build_mode()
	await _wait(2, 2)
	var all_houses := get_tree().get_nodes_in_group("house")
	_check(all_houses.size() == 2, "second (empty) house placed (%d)" % all_houses.size())
	var empty_house: Building = null
	for h in all_houses:
		if is_instance_valid(h) and h != house:
			empty_house = h as Building
	if empty_house != null:
		var empty_rig := empty_house.get_node_or_null("ModelRig") as BuildingModelRig
		var empty_albedos: Array[Color] = []
		if empty_rig != null:
			_collect_albedos(empty_rig, empty_albedos)
		_check(_albedos_equal(base_albedos, empty_albedos),
			"empty neighbour keeps original shared atlas colors (no pollution)")
		var empty_light := empty_house.get_node_or_null("OccupancyLight") as OmniLight3D
		_check(empty_light != null and not empty_light.visible,
			"empty neighbour house shows no door light")
		var empty_lantern := empty_house.get_node_or_null("OccupancyLantern") as MeshInstance3D
		_check(empty_lantern != null and not empty_lantern.visible,
			"empty neighbour house shows no lantern marker")
	else:
		_check(false, "second empty house found")

	# ---------------- 4. 住户 queue_free → 恢复空房 ----------------
	first.queue_free()
	await _wait(2, 3)
	_check(not house.is_occupied() and house.resident == null, "releasing resident empties the house")
	_check(house.has_vacancy(), "emptied house offers vacancy again")
	_check(rig != null and not rig.has_occupancy_tint(), "model tint cleared after resident release")
	_check(light != null and not light.visible and light.light_energy == 0.0,
		"door light off after resident release")
	_check(lantern != null and not lantern.visible, "lantern marker hidden after resident release")
	var restored_albedos: Array[Color] = []
	if rig != null:
		_collect_albedos(rig, restored_albedos)
	_check(_albedos_equal(base_albedos, restored_albedos),
		"surface albedo restored to empty baseline")
	_check(rig != null and _count_surface_overrides(rig) == 0,
		"no leftover surface overrides after clear")

	# ---------------- 5. 住户死亡 → 当帧空房外观，尸体释放后仍空房 ----------------
	var second: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
		house.global_position + Vector3(-3.0, 0.0, 3.0)) as Pawn
	await _wait(2, 1)
	if second == null or not is_instance_valid(second):
		_check(false, "second test soldier spawned")
		_finish()
		return
	house.assign_resident(second)
	await _wait(1, 2)
	_check(house.is_occupied(), "second resident moves in")
	second.health.apply_damage(999999.0)
	await _wait(2, 3)
	_check(not house.is_occupied(), "resident death immediately empties the visual (dead-flag path)")
	_check(rig != null and not rig.has_occupancy_tint(), "model tint cleared on resident death")
	_check(light != null and not light.visible, "door light off on resident death")
	_check(lantern != null and not lantern.visible, "lantern marker hidden on resident death")
	var freed: bool = false
	for _i in 180:
		await get_tree().physics_frame
		if not is_instance_valid(second):
			freed = true
			break
	_check(freed, "dead resident eventually queue_free (legacy shrink death)")
	await _wait(2, 2)
	_check(house.resident == null, "house drops the freed resident reference")
	_check(not house.is_occupied() and house.has_vacancy(), "house stays empty after resident freed")

	# ---------------- 6. 占位 BoxMesh：albedo 同步染色 / 还原 ----------------
	var ph_def := house_def.duplicate() as BuildingDef
	ph_def.model_path = ""   # 无模型 → 回退占位 BoxMesh（走 Building._apply_def 的同一条路径）
	var ph_house := Building.new()
	ph_house.def = ph_def
	ph_house.position = Vector3(10.0, 0.0, -6.0)
	var buildings := world.get_node_or_null("Buildings")
	if buildings != null:
		buildings.add_child(ph_house)
	else:
		world.add_child(ph_house)
	await _wait(2, 2)
	var ph_mesh := ph_house.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var ph_mat: StandardMaterial3D = null
	if ph_mesh != null:
		ph_mat = ph_mesh.material_override as StandardMaterial3D
	_check(ph_mat != null, "placeholder BoxMesh keeps its StandardMaterial3D when model_path is empty")
	if ph_mat != null:
		_check(ph_mat.albedo_color.is_equal_approx(house_def.mesh_color),
			"placeholder starts at def mesh_color")
	var ph_soldier: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
		Vector3(12.0, 0.0, -6.0)) as Pawn
	await _wait(2, 1)
	if ph_soldier == null or not is_instance_valid(ph_soldier):
		_check(false, "placeholder test soldier spawned")
		_finish()
		return
	ph_house.assign_resident(ph_soldier)
	await _wait(1, 2)
	_check(ph_house.is_occupied(), "placeholder house reports occupied")
	if ph_mat != null:
		_check(ph_mat.albedo_color.is_equal_approx(house_def.mesh_color * Building.OCCUPIED_TINT),
			"placeholder BoxMesh albedo tinted while occupied")
	ph_soldier.queue_free()
	await _wait(2, 3)
	if ph_mat != null:
		_check(ph_mat.albedo_color.is_equal_approx(house_def.mesh_color),
			"placeholder BoxMesh albedo restored when empty")

	# ---------------- 7. 带住户拆房：房屋先释放、住户后释放不得访问已释放实例 ----------------
	var third: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(),
		ph_house.global_position + Vector3(3.0, 0.0, 0.0)) as Pawn
	await _wait(2, 1)
	if third == null or not is_instance_valid(third):
		_check(false, "third test soldier spawned")
		_finish()
		return
	ph_house.assign_resident(third)
	await _wait(1, 2)
	ph_house.health.apply_damage(999999.0)   # 真实拆除路径：HP 归零 → queue_free
	await _wait(2, 3)
	_check(not is_instance_valid(ph_house), "demolished occupied house is freed")
	# 房屋已释放、住户仍存活：住户侧对 home 的一切访问都必须先 is_instance_valid
	if third is Soldier:
		var rest: Vector3 = (third as Soldier).get_home_rest_point()
		_check(rest.length() < 10000.0, "resident queries home rest point after house freed safely")
	else:
		_check(false, "resident is a Soldier before house demolition check")
	third.queue_free()
	await _wait(2, 2)
	_check(not is_instance_valid(third), "resident freed after its house was demolished")

	_finish()


# ---- 材质采样辅助（只读，不改任何材质） ----

func _collect_albedos(root: Node, out: Array[Color]) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i) as BaseMaterial3D
				if mat != null:
					out.append(mat.albedo_color)
	for c in root.get_children():
		_collect_albedos(c, out)


func _albedos_equal(a: Array[Color], b: Array[Color]) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _albedos_differ(a: Array[Color], b: Array[Color]) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return true
	return false


func _has_warm_emission(root: Node) -> bool:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i) as BaseMaterial3D
				if mat != null and mat.emission_enabled and mat.emission.r > 0.02:
					return true
	for c in root.get_children():
		if _has_warm_emission(c):
			return true
	return false


func _count_surface_overrides(root: Node) -> int:
	var n: int = 0
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				if mi.get_surface_override_material(i) != null:
					n += 1
	for c in root.get_children():
		n += _count_surface_overrides(c)
	return n
