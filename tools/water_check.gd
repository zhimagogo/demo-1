extends Node
## v12 水系巡检工具（不参与游戏运行）：
##   godot --path . tools/water_check.tscn        # 载入游戏 + 水系 shader，输出截图
##   godot --headless --path . tools/water_check.tscn   # 无头：只做资源/参数巡检
##
## 职责：
##   1. 触发 water_surface 着色库（湖泊 / 河流 / 瀑布三个 shader）编译载入，暴露 shader 语法错误；
##   2. 巡检 Main.tscn 的 Water 节点是否已切到 water_ground.gdshader 且 region=1；
##   3. 生成 artifacts/v12-integration-water.png（瀑布 + 河流 + 湖泊同框的远景机位）。

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)


func _run() -> void:
	# ---- 1. shader 载入巡检 ----
	var ground_sh: Shader = load("res://assets/shaders/water_ground.gdshader")
	var fall_sh: Shader = load("res://assets/shaders/waterfall.gdshader")
	var inc: Resource = load("res://assets/shaders/water_surface.gdshaderinc")
	_check(ground_sh != null, "water_ground.gdshader loads")
	_check(fall_sh != null, "waterfall.gdshader loads")
	_check(inc != null, "water_surface.gdshaderinc loads")
	if ground_sh != null:
		_check(ground_sh.code.contains("water_surface.gdshaderinc"), "ground shader includes the water library")
	if fall_sh != null:
		_check(fall_sh.code.contains("waterfall_surface"), "waterfall shader uses the cascade function")

	# ---- 2. 世界与水面节点巡检 ----
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var water := world.get_node_or_null("Water") as MeshInstance3D
	_check(water != null, "Water node exists")
	if water != null:
		var mat := water.material_override as ShaderMaterial
		_check(mat != null and mat.shader == ground_sh, "Water uses water_ground.gdshader")
		if mat != null:
			_check(absf(float(mat.get_shader_parameter("ws_region_cut")) - 1.0) < 0.01, "Water region cut = 1 (lake only)")
		var plane := water.mesh as PlaneMesh
		_check(plane != null and plane.size.x >= 46.0, "Water plane covers the river mouth (%.0fm)" % (plane.size.x if plane != null else 0.0))

	# ---- 3. 水系几何巡检（与 shader 同一份 WorldLayout 真相）----
	var mid: Vector2 = WorldLayout.RIVER_PTS[0].lerp(WorldLayout.RIVER_PTS[1], 0.5)
	var rv: Vector2 = WorldLayout.river_distance(mid)
	_check(rv.x < 0.05, "river centre distance ~0 (%.3f)" % rv.x)
	_check(rv.y > 1.5, "river half width sane (%.2f)" % rv.y)
	_check(WorldLayout.is_river(mid), "river centre is water")
	_check(not WorldLayout.is_river(Vector2.ZERO), "city centre is not river")
	_check(WorldLayout.lake_distance(WorldLayout.RIVER_PTS[WorldLayout.RIVER_PTS.size() - 1]) < 1.0,
		"river mouth is inside the lake")
	_check(WorldLayout.water_distance(WorldLayout.POOL_CENTER) < 0.0, "pool centre is water")
	_check(WorldLayout.waterfall_uv(WorldLayout.WATERFALL_LIP).z < 0.5, "waterfall lip is inside the cascade face")

	# ---- 4. 截图 ----
	if DisplayServer.get_name() == "headless":
		print("headless: skip capture")
		_finish()
		return
	# 正午定格：只写 game_seconds 不够——DayNightCycle 读的是 TimeManager.hour，
	# 而 hour 只在 _process 里随 game_seconds 重算（冻结 time_scale 后不再推进），
	# 所以必须用 begin() 同时校准 hour 与 game_seconds。
	TimeManager.begin(11)
	TimeManager.set_speed(0.0)
	await get_tree().create_timer(0.5, true, false, true).timeout
	print("capture time: hour=%d game_seconds=%.0f" % [TimeManager.hour, TimeManager.game_seconds])
	var hud := main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.global_position = Vector3(24.0, 13.0, -8.0)
	cam.look_at(Vector3(44.0, 3.0, -45.0))
	cam.current = true
	await _snap("v12-integration-water")
	var cam2 := Camera3D.new()
	cam2.fov = 70.0
	world.add_child(cam2)
	cam2.global_position = Vector3(44.0, 6.0, -30.0)
	cam2.look_at(Vector3(45.0, 3.0, -50.0))
	cam2.current = true
	await _snap("v12-integration-waterfall")
	# 河面近景（低机位贴着河看）——用于确认河道着色 / 白沫方向正确
	var cam3 := Camera3D.new()
	cam3.fov = 58.0
	world.add_child(cam3)
	cam3.global_position = Vector3(38.0, 2.6, -31.0)
	cam3.look_at(Vector3(45.5, 1.0, -39.0))
	cam3.current = true
	await _snap("v12-integration-river")
	_finish()


func _snap(name: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % name)
	print("saved artifacts/%s.png" % name)


func _finish() -> void:
	print("water_check: %d failure(s)" % _failures)
	get_tree().quit(_failures)
