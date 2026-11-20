extends Node
## v13 装饰「半球消散」回归：godot --headless --path . tests/DissolveZoneTest.tscn
## 覆盖：全局参数注册 / 判定半径边界 / 主角移动跟随 / 相机副球 / 开关 / 材质接入。
## 视觉部分（真的消散了没有）靠 artifacts/v13-dissolve-*-on/off.png 对照样张人工核验。

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var dissolve := get_node_or_null("/root/DecorationDissolve") as DecorationDissolveSystem
	_check(dissolve != null, "dissolve system runs as autoload (registers globals before any scene loads)")

	# ---- 全局 shader 参数：注册齐全（材质能编译的前提）----
	var names: Array = RenderingServer.global_shader_parameter_get_list()
	for key in [DecorationDissolveSystem.PARAM_HERO_POS, DecorationDissolveSystem.PARAM_CAM_POS,
			DecorationDissolveSystem.PARAM_RADIUS, DecorationDissolveSystem.PARAM_INNER,
			DecorationDissolveSystem.PARAM_STRENGTH, DecorationDissolveSystem.PARAM_CAM_RADIUS]:
		_check(names.has(key), "global shader param registered: %s" % key)
	_check(int(RenderingServer.global_shader_parameter_get_type(DecorationDissolveSystem.PARAM_HERO_POS)) == int(RenderingServer.GLOBAL_VAR_TYPE_VEC3),
		"hero pos global param is a vec3")
	_check(int(RenderingServer.global_shader_parameter_get_type(DecorationDissolveSystem.PARAM_RADIUS)) == int(RenderingServer.GLOBAL_VAR_TYPE_FLOAT),
		"radius global param is a float")

	if dissolve == null:
		print("DISSOLVE ZONE TEST: %d failure(s)" % _failures)
		get_tree().quit(_failures)
		return

	# ---- 主角被正确跟踪 ----
	var hero := dissolve.hero
	_check(hero != null and hero.name == "Hero", "dissolve system tracks the hero (got %s)" % (hero.name if hero != null else "<null>"))
	if hero == null:
		print("DISSOLVE ZONE TEST: %d failure(s)" % _failures)
		get_tree().quit(_failures)
		return
	hero.global_position = Vector3(6.0, 0.0, -26.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var chest: Vector3 = hero.global_position + Vector3.UP * 1.0

	# ---- 判定半径：球心最彻底 → 外半径处归零 ----
	var at_center: float = dissolve.dissolve_amount_at(chest)
	var at_inner: float = dissolve.dissolve_amount_at(chest + Vector3(dissolve.inner_radius, 0, 0))
	var at_mid: float = dissolve.dissolve_amount_at(chest + Vector3((dissolve.inner_radius + dissolve.radius) * 0.5, 0, 0))
	var at_edge: float = dissolve.dissolve_amount_at(chest + Vector3(dissolve.radius + 0.4, 0, 0))
	var at_far: float = dissolve.dissolve_amount_at(chest + Vector3(24.0, 0, 0))
	print("zone samples: center=%.3f inner=%.3f mid=%.3f edge=%.3f far=%.3f" % [at_center, at_inner, at_mid, at_edge, at_far])
	_check(at_center > 0.95, "hemisphere centre fully dissolved (%.2f)" % at_center)
	_check(at_inner >= 0.95, "inside inner radius fully dissolved (%.2f)" % at_inner)
	_check(at_mid > 0.05 and at_mid < 0.95, "falloff is gradual between inner and outer radius (%.2f)" % at_mid)
	_check(at_edge <= 0.001 and at_far <= 0.001, "outside the hemisphere decorations are untouched")
	_check(dissolve.covers(chest + Vector3(2.0, 0, 0)) and not dissolve.covers(chest + Vector3(9.0, 0, 0)),
		"covers() matches the configured radius")

	# ---- 跟随主角移动：判定区跟着走，旧位置自动恢复 ----
	var old_probe := chest + Vector3(3.0, 0, 0)
	_check(dissolve.covers(old_probe), "probe is inside the zone before the hero moves")
	hero.global_position = Vector3(6.0, 0.0, 40.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var new_chest: Vector3 = hero.global_position + Vector3.UP * 1.0
	_check(not dissolve.covers(old_probe), "zone follows the hero (old spot restored)")
	_check(dissolve.covers(new_chest + Vector3(2.0, 0, 0)), "zone is active at the hero's new position")
	var rs_hero: Variant = RenderingServer.global_shader_parameter_get(DecorationDissolveSystem.PARAM_HERO_POS)
	if rs_hero != null:
		# 注意：部分 Godot 构建里 global_shader_parameter_get 读取侧不返回值（返回 null），
		# 因此这里只在能读到的时候校验，读不到就跳过（渲染侧仍生效）。
		_check((rs_hero as Vector3).distance_to(new_chest) < 0.5, "global param follows the hero (%.2f m)" % (rs_hero as Vector3).distance_to(new_chest))
	else:
		print("SKIP: global_shader_parameter_get returns null on this build (render-side only)")

	# ---- 开关 ----
	dissolve.set_enabled(false)
	_check(dissolve.dissolve_amount_at(new_chest) <= 0.0, "disabled dissolve leaves every decoration visible")
	dissolve.set_enabled(true)
	_check(dissolve.dissolve_amount_at(new_chest) > 0.9, "re-enabling restores the zone")

	# ---- 材质接入：草 / 树 / 石头 / 通用装饰都换成了带消散的 shader ----
	var scatter := world.get_node("Decorations/DecorationScatter") as Node3D
	_check(scatter != null, "DecorationScatter node exists")
	var shader_paths: Dictionary = {}
	var mm_total: int = 0
	for child in scatter.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		mm_total += 1
		var mesh := mmi.multimesh.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat := mesh.surface_get_material(0)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			shader_paths[(mat as ShaderMaterial).shader.resource_path] = true
	var with_dissolve: int = 0
	for path in shader_paths:
		var sh: Shader = load(path)
		if sh != null and sh.code.contains("decor_dissolve.gdshaderinc"):
			with_dissolve += 1
	print("multimesh chunks=%d distinct shaders=%d dissolve-aware=%d" % [mm_total, shader_paths.size(), with_dissolve])
	_check(mm_total > 20, "decoration is scattered in many chunks (%d)" % mm_total)
	_check(with_dissolve >= 3, "grass/tree/stone/generic shaders include the dissolve library (%d)" % with_dissolve)
	for expected in ["res://assets/shaders/grass.gdshader", "res://assets/shaders/foliage.gdshader", "res://assets/shaders/stone.gdshader"]:
		_check(shader_paths.has(expected), "decoration uses %s" % expected.get_file())

	# ---- 判定区不应该把玩法物件卷进去（资源点 / 建筑是「实体」不是装饰）----
	var resource_nodes := get_tree().get_nodes_in_group("resource_node")
	_check(resource_nodes.size() > 0, "resource nodes still exist (%d)" % resource_nodes.size())
	var sample: Node3D = resource_nodes[0] as Node3D
	_check(not dissolve.covers(sample.global_position + Vector3.UP * 2.0),
		"test sample resource node is outside the hero's zone (gameplay objects untouched)")

	print("DISSOLVE ZONE TEST: %d failure(s)" % _failures)
	get_tree().quit(_failures)
