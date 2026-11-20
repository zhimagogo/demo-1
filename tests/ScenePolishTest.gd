extends Node
## ============================================================================
## v40.1 场景表现专项：地标道具穿模 / 贴地 / 压路 / 植被压道具 / 小径端点回归
## ============================================================================
## 运行：godot --headless --path . tests/ScenePolishTest.tscn --fixed-fps 60
##
## 覆盖（阈值来自 task-7 验收标准）：
##   1) ThemedRegions 存在；遍历其直接子节点（六区域地标 + 城外路标 + 区域石碑）：
##      · 世界 AABB 的 min_y ∈ [-0.18, +0.22]；白名单：Wisp / Firefly 悬浮光点 [-0.6, +2.2]、
##        Ice 浮冰/冰晶 [-0.35, +1.2]、Lake_Pier 栈桥木桩入湖床 [-1.4, +1.2]、
##        Lake_Boat 湖上小船 [-0.2, +0.8]；Swamp_Boat 不豁免（Lead 要求抬到真正贴地）；
##      · 道具 XZ 中心在图内 |x|,|z| ≤ 126；
##      · 道具中心 WorldLayout.road_distance ≥ 2.0（木栈道白名单除外：它按设计沿探索
##        小径铺到祭坛前，见 WorldLayout.TRAIL_SEGMENTS 第 9 段）；
##   2) 非树类道具两两 XZ 重叠面积 < 1.2m²；树×树（AncientTree / DeadTree / FallenTree /
##      FallenLog / Reed）放宽到 30m²（树冠交叠属自然形态），但同区域古树树干 XZ 间距 ≥4.0m；
##      贴地贴片（雪斑 / 盐壳 / 泥潭 / 灰烬场 / 苔藓 / 浮冰 / 矿轨轨枕）互相叠放属设计，豁免；
##   3) 植被不压道具：从 DecorationScatter 的 MultiMesh 里按步长采样（每个 MM ≤200 实例，
##      覆盖整批实例而非只取开头），树 / 岩石 / 树干 / 金林冠 的实例 AABB 不得落进
##      道具 AABB 水平外扩 0.4m 且竖直相交的区域；草 / 花 / 麦浪 / 地被细节不参与判定。
##   4) 六条区域小径（TRAIL_SEGMENTS 末尾 6 段，与 ThemedRegions 的石碑映射同序）终点距
##      对应 landmark ∈ [7.5, 9.5]m（验证 v40.1 小径后撤改动）；
##   5) 若命令行带 --log-file，扫描加载日志不得含 SCRIPT ERROR / Parse Error / SHADER ERROR
##      （跑批时 run_all_tests.sh 另有统一判定；手动运行无 log-file 时打印 SKIP）。
##
## 任何路径都 quit（ThemedRegions 缺失也走 _finish，避免挂死整批）。
## ============================================================================

## 贴地贴片 / 轨道零件：互相叠放是设计（雪斑盖雪斑、轨枕托矿轨），豁免两两互穿。
const FLAT_PIECES: Array[String] = [
	"SnowPatch", "SaltCrust", "MudPool", "AshField", "Moss", "IceFloe",
	"Mine_Rail", "Mine_RailStop", "Mine_Sleeper",
]
## 树 / 苇丛类：冠幅大、允许更宽松的重叠上限。
const TREE_PIECES: Array[String] = ["AncientTree", "DeadTree", "FallenTree", "FallenLog", "Reed"]
## 悬浮光点（鬼火 / 萤火）：故意的漂浮光，min_y 放宽到 [-0.6, +2.2]（Lead v40.1 拍板）。
const FLOATING_LIGHT_PIECES: Array[String] = ["Wisp", "Firefly"]
## 水面浮冰 / 冰晶：浮冰飘在潭面（y≈0.34），min_y 放宽到 [-0.35, +1.2]。
## 沉船不在此列：Lead 拍板 Boat 必须真正贴地（目标 y≈-0.10），按普通道具 [-0.18, +0.22] 判定。
const ICE_PIECES: Array[String] = ["Ice"]
## v40.2 湖上码头：栈桥木桩本来就插进湖床（Lead 实测 min_y≈-1.10），放宽到 [-1.4, +1.2]；
## 它整座在水里，中心离任何道路都远，压路检查无意义（豁免）。
const PIER_PIECES: Array[String] = ["Lake_Pier"]
## v40.2 湖上小船：浮在水面 y≈0.12（船底略微入水），放宽到 [-0.2, +0.8]；
## 停泊在码头旁，同样在水里，压路检查豁免。
const LAKE_BOAT_PIECES: Array[String] = ["Lake_Boat"]
## 渲染层道具不需要「贴地」意义上的压路判定（木栈道沿小径铺设）。
const ROAD_EXEMPT_PIECES: Array[String] = ["Boardwalk"]

var _failures: int = 0
var _main: Node = null
var _props: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _skip(message: String) -> void:
	print("SKIP: ", message)


func _finish() -> void:
	print("SCENE POLISH: %d failure(s)" % _failures)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _run() -> void:
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	if packed == null:
		_check(false, "Main.tscn 可加载")
		await _finish()
		return
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame

	var world := _main.get_node_or_null("WorldRoot") as Node3D
	if world == null:
		_check(false, "WorldRoot 存在")
		await _finish()
		return
	# 冻结刷怪 / 资源再生：本测试只看静态场景摆放，不受单位与战斗干扰
	var spawner := world.get_node_or_null("WildlifeSpawner")
	if spawner != null:
		(spawner as Node).set_process(false)
	var growth := world.get_node_or_null("ResourceGrowthSystem")
	if growth != null:
		(growth as Node).set_process(false)
	# 等程序化内容（地标 / 植被 MultiMesh）全部就位
	for _i in 3:
		await get_tree().physics_frame

	var scenery := world.get_node_or_null("WorldScenery")
	var themed: Node3D = null
	if scenery != null:
		themed = scenery.get_node_or_null("ThemedRegions") as Node3D
	_check(themed != null, "WorldScenery/ThemedRegions 存在（区域地标已挂载）")
	if themed == null:
		await _finish()
		return

	_collect_props(themed)
	_check(_props.size() >= 120, "地标道具数量合理（%d 个有网格的道具）" % _props.size())
	_check_prop_grounding()
	_check_prop_overlap()
	_check_ancient_tree_spacing()
	_check_vegetation(world)
	_check_trails()
	_check_region_ambience(world)
	_check_log_clean()
	await _finish()


# ============================================================================
# 道具采集：ThemedRegions 直接子节点 → 合并子树网格的世界 AABB
# ============================================================================

func _collect_props(themed: Node3D) -> void:
	for child in themed.get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		var aabb := _subtree_world_aabb(node)
		if aabb.size == Vector3.ZERO:
			continue   # 灯 / 纯 Label 组合件（无网格）不参与几何判定
		var piece_name := String(node.name)
		_props.append({
			"name": piece_name,
			"aabb": aabb,
			"center": Vector2(aabb.get_center().x, aabb.get_center().z),
			"origin": Vector2(node.global_position.x, node.global_position.z),
			"flat": _contains_any(piece_name, FLAT_PIECES),
			"tree": _contains_any(piece_name, TREE_PIECES),
			"road_exempt": _contains_any(piece_name, ROAD_EXEMPT_PIECES),
			"light": _contains_any(piece_name, FLOATING_LIGHT_PIECES),
			"ice": _contains_any(piece_name, ICE_PIECES),
			"pier": _contains_any(piece_name, PIER_PIECES),
			"lake_boat": _contains_any(piece_name, LAKE_BOAT_PIECES),
		})


## Godot 4 的 AABB 没有 transform()：用 8 个角点变换后重新包围。
func _transform_aabb(box: AABB, xform: Transform3D) -> AABB:
	var result := AABB(xform * box.position, Vector3.ZERO)
	for i in 8:
		var corner := box.position + Vector3(
			box.size.x if (i & 1) != 0 else 0.0,
			box.size.y if (i & 2) != 0 else 0.0,
			box.size.z if (i & 4) != 0 else 0.0)
		result = result.merge(AABB(xform * corner, Vector3.ZERO))
	return result


## 合并节点子树里所有 MeshInstance3D 的世界 AABB（含模型缩放与旋转）。
func _subtree_world_aabb(root: Node) -> AABB:
	var result := AABB()
	var has_mesh := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				var box := _transform_aabb(mesh_instance.mesh.get_aabb(), mesh_instance.global_transform)
				result = box if not has_mesh else result.merge(box)
				has_mesh = true
		for child in node.get_children():
			stack.append(child)
	return result


func _contains_any(text: String, keywords: Array[String]) -> bool:
	for keyword in keywords:
		if text.contains(keyword):
			return true
	return false


# ============================================================================
# 1) 贴地 / 图内 / 不压路
# ============================================================================

func _check_prop_grounding() -> void:
	var sunken: Array[String] = []
	var floating: Array[String] = []
	var outside: Array[String] = []
	var on_road: Array[String] = []
	for entry in _props:
		var piece_name := String(entry["name"])
		var aabb: AABB = entry["aabb"]
		var center: Vector2 = entry["center"]
		var min_limit := -0.18
		var max_limit := 0.22
		if bool(entry["pier"]):
			min_limit = -1.4      # 栈桥木桩插入湖床
			max_limit = 1.2
		elif bool(entry["lake_boat"]):
			min_limit = -0.2      # 湖上小船浮在水面（船底略入水）
			max_limit = 0.8
		elif bool(entry["light"]):
			min_limit = -0.6      # 鬼火 / 萤火：故意悬浮的光点
			max_limit = 2.2
		elif bool(entry["ice"]):
			min_limit = -0.35     # 浮冰飘在潭面 / 冰晶贴地摆放
			max_limit = 1.2
		if aabb.position.y < min_limit - 0.001:
			sunken.append("%s min_y=%.2f" % [piece_name, aabb.position.y])
		elif aabb.position.y > max_limit + 0.001:
			floating.append("%s min_y=%.2f" % [piece_name, aabb.position.y])
		if absf(center.x) > 126.0 or absf(center.y) > 126.0:
			outside.append("%s (%.1f, %.1f)" % [piece_name, center.x, center.y])
		# 木栈道沿小径铺、矿轨/轨枕跨过小径都是地面装饰的合理走线；湖上码头/小船在水里，
		# 中心离任何道路都远，压路判定对它们无意义——三类一并豁免。
		if not bool(entry["road_exempt"]) and not bool(entry["flat"]) \
				and not bool(entry["pier"]) and not bool(entry["lake_boat"]):
			var road := WorldLayout.road_distance(center)
			if road < 2.0:
				on_road.append("%s 离路 %.2fm" % [piece_name, road])

	_check(sunken.is_empty(), "道具不埋地：min_y ≥ -0.18（%d 处）%s"
		% [sunken.size(), _head(sunken)])
	_check(floating.is_empty(), "道具不悬空：min_y ≤ +0.22（Wisp/Firefly 光点 +2.2、Ice +1.2、Pier/Boat 按水体语义；Swamp_Boat 不豁免；%d 处）%s"
		% [floating.size(), _head(floating)])
	_check(outside.is_empty(), "道具 XZ 中心在 256m 图内（|x|,|z| ≤ 126；%d 处）%s"
		% [outside.size(), _head(outside)])
	_check(on_road.is_empty(), "道具中心离道路 / 小径中心线 ≥2.0m（木栈道豁免；%d 处）%s"
		% [on_road.size(), _head(on_road)])
	print("INFO: 道具 %d 个（树/苇丛 %d、贴地贴片 %d、悬浮光点 %d、浮冰 %d）"
		% [_props.size(), _count_flag("tree"), _count_flag("flat"),
			_count_flag("light"), _count_flag("ice")])


func _count_flag(key: String) -> int:
	var count := 0
	for entry in _props:
		if bool(entry[key]):
			count += 1
	return count


# ============================================================================
# 2) 道具两两 XZ 互穿
# ============================================================================

func _check_prop_overlap() -> void:
	var violations: Array[String] = []
	var worst_area := 0.0
	var worst_pair := ""
	for i in _props.size():
		for j in range(i + 1, _props.size()):
			var a: Dictionary = _props[i]
			var b: Dictionary = _props[j]
			# 贴地贴片（雪斑 / 盐壳 / 灰烬场 / 苔藓 / 浮冰 / 矿轨轨枕）是地面装饰：
			# 垫在祭坛 / 冰晶下面、轨枕托着矿轨都属设计，不构成视觉穿模，任一方贴地即豁免。
			if bool(a["flat"]) or bool(b["flat"]):
				continue
			var area := _xz_overlap_area(a["aabb"], b["aabb"])
			if area <= 0.001:
				continue
			if area > worst_area:
				worst_area = area
				worst_pair = "%s × %s" % [a["name"], b["name"]]
			# 树×树：树冠交叠属自然形态（Lead 拍板 30m²）；树×道具仍按 1.2m² 严查穿模。
			var limit := 30.0 if (bool(a["tree"]) and bool(b["tree"])) else 1.2
			if area > limit:
				violations.append("%s × %s = %.2f m²" % [a["name"], b["name"], area])
	_check(violations.is_empty(),
		"道具 XZ 互穿 <1.2m²（树×树 <30m²；%d 处超限）%s"
			% [violations.size(), _head(violations)])
	if worst_pair != "":
		print("INFO: 道具互穿最大 %.2f m²（%s）" % [worst_area, worst_pair])


## 同区域古树树干 XZ 间距 ≥4.0m（树冠允许交叠到 30m²，但树干不能挤在一起）。
func _check_ancient_tree_spacing() -> void:
	var trees: Array[Dictionary] = []
	for entry in _props:
		if String(entry["name"]).contains("AncientTree"):
			trees.append(entry)
	var min_spacing := INF
	var worst_pair := ""
	for i in trees.size():
		for j in range(i + 1, trees.size()):
			var origin_a: Vector2 = trees[i]["origin"]
			var origin_b: Vector2 = trees[j]["origin"]
			var distance := origin_a.distance_to(origin_b)
			if distance < min_spacing:
				min_spacing = distance
				worst_pair = "%s ↔ %s" % [trees[i]["name"], trees[j]["name"]]
	_check(trees.size() < 2 or min_spacing >= 4.0 - 0.001,
		"同区域古树树干 XZ 间距 ≥4.0m（%d 棵，最小 %.2fm：%s）"
			% [trees.size(), min_spacing, worst_pair])


## 两个 AABB 在 XZ 平面上的重叠面积（m²）。
func _xz_overlap_area(a: AABB, b: AABB) -> float:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_z := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
	if overlap_x <= 0.0 or overlap_z <= 0.0:
		return 0.0
	return overlap_x * overlap_z


# ============================================================================
# 3) 植被不压道具
# ============================================================================

func _check_vegetation(world: Node3D) -> void:
	var scatter := world.get_node_or_null("Decorations/DecorationScatter")
	_check(scatter != null, "DecorationScatter 存在（植被压道具检查）")
	if scatter == null:
		return
	# 道具空间哈希：4m 格 + 邻格查询，避免 18 万植被实例 × 186 道具的全量两两比较
	var prop_grid := {}
	for index in _props.size():
		var aabb: AABB = _props[index]["aabb"]
		for cell in _cells_covering(aabb, 4.0):
			if not prop_grid.has(cell):
				prop_grid[cell] = []
			prop_grid[cell].append(index)

	var checked_multimeshes := 0
	var sampled := 0
	var violations: Array[String] = []
	var seen: Dictionary = {}
	for node in scatter.get_children():
		if not (node is MultiMeshInstance3D):
			continue
		var mmi := node as MultiMeshInstance3D
		if not _is_blocking_vegetation(String(mmi.name)):
			continue
		var multi := mmi.multimesh
		if multi == null or multi.mesh == null or multi.instance_count == 0:
			continue
		checked_multimeshes += 1
		var count := multi.instance_count
		# 步长采样：每个 MM 最多 200 个实例，覆盖整批而不是只取开头
		var step := maxi(1, int(ceil(float(count) / 200.0)))
		for i in range(0, count, step):
			sampled += 1
			var world_xform: Transform3D = mmi.global_transform * multi.get_instance_transform(i)
			var instance_aabb := _transform_aabb(multi.mesh.get_aabb(), world_xform)
			var center := instance_aabb.get_center()
			var base_cell := Vector2i(floori(center.x / 4.0), floori(center.z / 4.0))
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var key := base_cell + Vector2i(dx, dz)
					if not prop_grid.has(key):
						continue
					for prop_index in prop_grid[key]:
						var entry: Dictionary = _props[prop_index]
						var prop_aabb: AABB = entry["aabb"]
						if not _presses(instance_aabb, prop_aabb):
							continue
						var pair_key := "%s|%s" % [mmi.name, entry["name"]]
						if seen.has(pair_key):
							continue
						seen[pair_key] = true
						violations.append("%s 压 %s" % [mmi.name, entry["name"]])

	_check(violations.is_empty(),
		"树/岩石/树干不压地标道具（%d 个 MM、%d 个采样实例；%d 处相交）%s"
			% [checked_multimeshes, sampled, violations.size(), _head(violations)])
	print("INFO: 植被压道具检查：%d 个 MultiMesh、%d 个采样实例" % [checked_multimeshes, sampled])


## 树 / 岩石 / 树干 / 金林（Grove）类植被参与判定；草 / 花 / 麦浪 / 地被细节豁免。
func _is_blocking_vegetation(node_name: String) -> bool:
	var lower := node_name.to_lower()
	for keyword in ["tree", "rock", "trunk", "grove"]:
		if lower.contains(keyword):
			return true
	return false


## 植被实例是否「压」进道具：道具 AABB 水平外扩 0.4m，且两者竖直方向重叠 > 5cm。
func _presses(instance_aabb: AABB, prop_aabb: AABB) -> bool:
	var grown := AABB(
		prop_aabb.position - Vector3(0.4, 0.0, 0.4),
		prop_aabb.size + Vector3(0.8, 0.0, 0.8))
	var overlap_x := minf(instance_aabb.end.x, grown.end.x) - maxf(instance_aabb.position.x, grown.position.x)
	var overlap_z := minf(instance_aabb.end.z, grown.end.z) - maxf(instance_aabb.position.z, grown.position.z)
	if overlap_x <= 0.0 or overlap_z <= 0.0:
		return false
	var overlap_y := minf(instance_aabb.end.y, grown.end.y) - maxf(instance_aabb.position.y, grown.position.y)
	return overlap_y > 0.05


## AABB 覆盖的所有 4m 空间格（水平）。
func _cells_covering(aabb: AABB, cell_size: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x0 := floori(aabb.position.x / cell_size)
	var x1 := floori(aabb.end.x / cell_size)
	var z0 := floori(aabb.position.z / cell_size)
	var z1 := floori(aabb.end.z / cell_size)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			cells.append(Vector2i(x, z))
	return cells


# ============================================================================
# 4) 区域小径终点距 landmark ∈ [7.5, 9.5]m
# ============================================================================

func _check_trails() -> void:
	var segments := WorldLayout.TRAIL_SEGMENTS
	_check(segments.size() >= 14, "小径网络段数 ≥14（当前 %d）" % segments.size())
	var first := maxi(0, segments.size() - WorldRegions.count())
	var bad := 0
	var info: Array[String] = []
	for index in WorldRegions.count():
		var region := WorldRegions.all()[index]
		var region_id := String(region["id"])
		var landmark: Vector2 = region["landmark"]
		var segment: Array = segments[first + index]
		var end_point: Vector2 = segment[1]
		var distance := end_point.distance_to(landmark)
		var ok := distance >= 7.5 - 0.001 and distance <= 9.5 + 0.001
		if not ok:
			bad += 1
		info.append("%s ← 第 %d 段终点 (%.1f, %.1f) 距地标 %.2fm"
			% [region_id, first + index, end_point.x, end_point.y, distance])
	_check(bad == 0, "六条区域小径终点距 landmark ∈ [7.5, 9.5]m（%d/%d 达标）"
		% [WorldRegions.count() - bad, WorldRegions.count()])
	for line in info:
		print("INFO: ", line)


# ============================================================================
# 4.5) 区域环境粒子（v40.2 RegionAmbience）：存在 / 发射器 ≤8 / 总粒子 ≤1200
# ============================================================================

func _check_region_ambience(world: Node3D) -> void:
	var script_path := "res://scripts/decor/RegionAmbience.gd"
	if not ResourceLoader.exists(script_path):
		_skip("RegionAmbience 脚本尚未落地（%s）——环境粒子断言跳过，实现到位后自动转正式断言"
			% script_path)
		return
	var scenery := world.get_node_or_null("WorldScenery")
	var ambience: Node = null
	if scenery != null:
		ambience = scenery.get_node_or_null("RegionAmbience")
	_check(ambience != null, "WorldScenery/RegionAmbience 存在（六区域环境粒子已挂载）")
	if ambience == null:
		return
	var emitter_count := 0
	var particle_budget := 0
	var stack: Array[Node] = [ambience]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GPUParticles3D:
			emitter_count += 1
			particle_budget += (node as GPUParticles3D).amount
		for child in node.get_children():
			stack.append(child)
	_check(emitter_count >= 1 and emitter_count <= 8,
		"RegionAmbience 粒子发射器 1..8 个（当前 %d）" % emitter_count)
	_check(particle_budget <= 1200,
		"RegionAmbience 总粒子预算 ≤1200（当前 %d）" % particle_budget)
	print("INFO: RegionAmbience 发射器 %d 个，总粒子 %d（昼夜氛围粒子）"
		% [emitter_count, particle_budget])


# ============================================================================
# 5) 无头日志 0 脚本错误
# ============================================================================

func _check_log_clean() -> void:
	var log_path := ""
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--log-file" and i + 1 < args.size():
			log_path = args[i + 1]
			break
		if args[i].begins_with("--log-file="):
			log_path = args[i].split("=", true, 1)[1]
			break
	if log_path == "":
		# get_cmdline_args 在部分启动方式下拿不到 --log-file（引擎消费掉了）：
		# 退回 run_all_tests.sh 的既定日志约定 ${TMPDIR}/demo1-tests/<场景名>.log。
		var tmp_dir := OS.get_environment("TMPDIR")
		if tmp_dir == "":
			tmp_dir = "/tmp"
		var scene_name := String(get_tree().current_scene.scene_file_path.get_file().get_basename()) \
			if get_tree().current_scene != null else "ScenePolishTest"
		var guess := "%s/demo1-tests/%s.log" % [tmp_dir.trim_suffix("/"), scene_name]
		if FileAccess.file_exists(guess):
			log_path = guess
	if log_path == "":
		print("SKIP: 未提供 --log-file 且未找到既定日志路径，跳过加载日志扫描（跑批由 run_all_tests.sh 统一判定）")
		return
	if not FileAccess.file_exists(log_path):
		print("SKIP: 日志文件尚未落盘（%s）" % log_path)
		return
	var text := FileAccess.get_file_as_string(log_path)
	var bad_lines: Array[String] = []
	for line in text.split("\n"):
		if line.contains("SCRIPT ERROR") or line.contains("Parse Error") or line.contains("SHADER ERROR"):
			bad_lines.append(line.strip_edges())
	_check(bad_lines.is_empty(), "加载日志 0 条脚本 / 解析 / 着色器错误（%d 条）%s"
		% [bad_lines.size(), _head(bad_lines)])


# ============================================================================
# 工具
# ============================================================================

func _head(lines: Array[String]) -> String:
	if lines.is_empty():
		return ""
	var shown := lines.slice(0, mini(lines.size(), 16))
	return "；" + "；".join(PackedStringArray(shown))
