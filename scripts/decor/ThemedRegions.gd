class_name ThemedRegions
extends Node3D
## ============================================================================
## v40 主题区域地标（六个区域的主地标 + 氛围道具 + 城郊路标 / 区域入口石碑）
## ============================================================================
## 区域数据唯一真相：scripts/defs/WorldRegions.gd（本脚本只读 region 字典，绝不改写）。
## WorldScenery._build_themed_regions() 在运行时 load() 本脚本并挂到 WorldScenery 下
## （节点名 ThemedRegions）；脚本缺失时静默跳过——因此这里不得依赖任何
## 「必须先于自己就绪」的节点，也不改 GridSystem.terrain_cells。
##
## 布置约定：
##   · 主地标压在 WorldRegions 的 landmark 点上；氛围道具围绕地标核心空地
##     （v40.1 起 landmark_clearance = 11m，植被在这片空地避让）。
##   · 全部是纯视觉装饰：不建 CollisionShape3D、不写寻路格、不挡怪物出生点。
##   · 节点结构刻意保持「一层平铺」：每个道具都是 ThemedRegions 的直接子节点，
##     一组多部件道具（祭坛 / 立灯 / 矿轨矿车 / 船 …）用容器节点包住，
##     这样几何体检（AABB / 互穿 / 接地）直接以「一个道具」为单位。
##   · v40.1 几何修复：每个道具建完后统一 _ground_fit（按世界 AABB 把 min_y 贴到
##     目标高度，旋转后的旗 / 梯 / 倒木同样适用），再按区域跑 _separate_props
##     （树按主干间距、非树按 XZ 重叠面积推离、压路的沿远离小径方向挪开）。
##     这样以后往区域里加道具也不容易再穿模。
##   · 每个区域只点 1 盏 OmniLight3D；火光 / 鬼火闪烁统一由本脚本唯一的 _process 驱动。
##   · 模型加载沿用 DecorationScatter / BuildingModelRig 的「load() 优先、
##     GLTFDocument 回退」；.gltf 必须与其 .bin + hexagons_medieval.png 同目录
##     （glTF 内部 URI 是写死的相对路径，不能改名 / 不能拆开）。
## ============================================================================

const BUILDING_DIR := "res://assets/_PLACEHOLDER/medieval_hexagon_buildings/"
const PROP_DIR := "res://assets/_PLACEHOLDER/medieval_hexagon_props/"
const NATURE_DIR := "res://assets/_PLACEHOLDER/nature/"

## 地标核心空地半径（米），与 WorldRegions.landmark_clearance 同口径（v40.1 = 11m）。
const LANDMARK_CLEARANCE := 11.0
## 道具离道路 / 小径中心线的最小距离（米）：路面视觉宽度约 2.2m，再留一点草肩。
const ROAD_CLEARANCE := 2.6
## 几何修复时把道具“推离路心”的目标距离（比验收线 2.0m 多留余量）。
const ROAD_SAFE := 2.4
## 道具离水面（湖 / 河 / 潭）边缘的最小距离（米）。
const WATER_CLEARANCE := 0.8
## 接地目标：道具世界 AABB 的 min_y 统一贴到这个高度（略高于地面避免 z-fighting）。
const FIT_MIN_Y := 0.01
## 两棵树的最小主干中心间距（米）。树冠允许交叠，树干不允许。
const TREE_MIN_GAP := 4.6
## 非树道具两两 XZ 重叠面积上限（m²，验收线 1.0，施工时压到 0.6）。
const OVERLAP_TARGET := 0.6
## Label3D 的字形像素尺寸：字高 = font_size * pixel_size。
const LABEL_PIXEL_SIZE := 0.006
## 区域入口石碑的落点：地标前方 7.2m（小径终点在 8.5m 处，石碑正好立在路尾），
## 向路侧偏 2m。
const STELE_FORWARD := 7.2
const STELE_SIDE := 2.0

## 石碑第二行的短标语（kind -> 文案）。区域 subtitle 是整句故事文本，
## 刻在 1.3m 宽的石板上会溢出，因此石碑只用这条六字以内的风味短句。
const REGION_TAGS := {
	"frost": "北境 · 不冻之潭",
	"mine": "东北 · 紫铁流光",
	"wheat": "东境 · 风车未停",
	"battle": "南境 · 断旗不降",
	"forest": "西境 · 旧名回响",
	"swamp": "西南 · 驼铃不散",
}

## 几何体检汇总用的分类关键词（与 tests/ScenePolishTest 的豁免口径保持一致）：
## 树类之间允许树冠交叠；贴地贴片 / 木栈道不参与互穿 / 压路判定。
const TREE_LIKE_KEYWORDS := ["AncientTree", "DeadTree", "FallenTree", "FallenLog", "Reed"]
const FLAT_LIKE_KEYWORDS := ["SnowPatch", "SaltCrust", "MudPool", "AshField", "Moss", "IceFloe",
	"Mine_Rail", "Mine_RailStop", "Mine_Sleeper"]
const ROAD_EXEMPT_KEYWORDS := ["SnowPatch", "SaltCrust", "MudPool", "AshField", "Moss", "IceFloe",
	"Boardwalk"]

var _rng := RandomNumberGenerator.new()
## 名字去重计数：同一 base 的第 2 个起加 _02/_03 后缀。
var _name_counts: Dictionary = {}
## 模型模板缓存：path -> 未入树的 Node3D 模板（放置时 duplicate()）。
var _templates: Dictionary = {}
## 纯色装饰材质缓存（走 NatureAssets.dissolve_material，主角贴近时半透明）。
var _solid_materials: Dictionary = {}
## 自发光材质缓存（冰晶 / 矿石 / 余烬 / 符文 / 鬼火这类小件）。
var _glow_materials: Dictionary = {}
## 霜区浮冰材质（v45）：半透明冰蓝 + 微发光，懒创建后复用。
var _ice_material_cached: StandardMaterial3D = null
## 中文字体（懒加载 UIStyle.make_font()，与 HUD 用同一套字体链）。
var _font: Font = null
## 闪烁灯：{light, base, amp, speed, phase}，统一由 _process 驱动。
var _flickers: Array[Dictionary] = []
## v40.2 缓慢自转件（风车扇叶）：{node, axis, speed}，统一由 _process 驱动。
var _spinners: Array[Dictionary] = []
var _clock := 0.0
var _light_count := 0
## 当前区域内随机落点的已占用位置（避免随机道具叠在一起；精确互穿交给 _separate_props）。
var _spots: Array[Vector2] = []
## 六个区域几何体检的累计最差值（最后打一行汇总，方便回归排查）。
var _worst_min_y := INF
var _worst_overlap := 0.0
var _worst_road := INF


func _ready() -> void:
	# 固定随机种子：每次进世界的地标细节完全一致，截图 / 回归可复现。
	_rng.seed = 402197
	# ⑥ 先立区域石碑：区域道具做互穿推离时，石碑是「锚点」，只会让道具让开它。
	_build_region_steles()
	for region in WorldRegions.all():
		if region["kind"] == WorldRegions.KIND_CITY:
			continue
		_spots.clear()
		_build_region(region)
		_polish_region(region)
	_build_city_signposts()
	_build_lake_dock()
	set_process(not _flickers.is_empty() or not _spinners.is_empty())
	print("[ThemedRegions] 主题区域地标就绪：%d 个区域 / %d 个直接子节点 / %d 盏灯 / %d 份模型模板 / %d 个自转件；" % [
		WorldRegions.count(), get_child_count(), _light_count, _templates.size(), _spinners.size()] \
		+ "几何体检：最差 min_y=%.3f / 最大非树互穿=%.2f m² / 最小路距=%.2f m。" % [
		_worst_min_y, _worst_overlap, _worst_road])


func _process(delta: float) -> void:
	_clock += delta
	for entry in _flickers:
		var light: OmniLight3D = entry["light"]
		if not is_instance_valid(light):
			continue
		var base: float = entry["base"]
		var amp: float = entry["amp"]
		var speed: float = entry["speed"]
		var phase: float = entry["phase"]
		var t := _clock * speed + phase
		# 双频叠加：火光不会呈现机械的正弦节奏。
		light.light_energy = base + sin(t) * amp + sin(t * 2.37 + 1.1) * amp * 0.45
	for entry in _spinners:
		var spinner: Node3D = entry["node"]
		if not is_instance_valid(spinner):
			continue
		var axis: Vector3 = entry["axis"]
		var speed: float = entry["speed"]
		spinner.rotate_object_local(axis, speed * delta)


func _exit_tree() -> void:
	# 模板节点不在树里，不会随场景释放，需要显式回收。
	for key in _templates:
		var template: Node3D = _templates[key]
		if is_instance_valid(template):
			template.free()
	_templates.clear()


# ============================================================================
# 区域分发
# ============================================================================

func _build_region(region: Dictionary) -> void:
	var kind: StringName = region["kind"]
	if kind == WorldRegions.KIND_FROST:
		_build_frost(region)
	elif kind == WorldRegions.KIND_MINE:
		_build_mine(region)
	elif kind == WorldRegions.KIND_WHEAT:
		_build_wheat(region)
	elif kind == WorldRegions.KIND_BATTLE:
		_build_battle(region)
	elif kind == WorldRegions.KIND_FOREST:
		_build_forest(region)
	elif kind == WorldRegions.KIND_SWAMP:
		_build_swamp(region)
	else:
		push_warning("ThemedRegions: 未识别的地标类型 %s（跳过 %s）" % [kind, region.get("id", "")])


# ============================================================================
# 北境 · 霜语瀑布：水潭西岸的许愿祭坛（冰蓝自发光 / 雪斑 / 木栈道 / 冷色灯笼）
# ============================================================================

func _build_frost(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]
	var front := _region_front(region)
	var trail_end := center - front * 8.5

	# ① 许愿祭坛（地标核心 / 锚点）：三级石台 + 石碗 + 许愿球 + 四面符文 + 四根矮冰柱
	_mark(_build_frost_altar(center + Vector2(0.8, -0.6), accent), &"anchor", true)

	# ② 木栈道：从「小径终点」斜着铺到祭坛前（不再正压在土路上），成组一个容器。
	var boardwalk := _piece("Frost_Boardwalk", Vector3.ZERO)
	var walk_start := trail_end.lerp(center + Vector2(0.8, -0.6), 0.38)
	var walk_end := trail_end.lerp(center + Vector2(0.8, -0.6), 0.92)
	var walk_dir := (walk_end - walk_start).normalized()
	var plank_yaw := _yaw_align_z(walk_dir)
	for i in 5:
		var t := float(i) / 4.0
		var plank_pos := walk_start.lerp(walk_end, t)
		var plank := _part_box(boardwalk, Vector3(plank_pos.x, 0.08, plank_pos.y),
			Vector3(1.9, 0.12, 0.55), Color("6d5a44"))
		plank.rotation.y = plank_yaw + _rng.randf_range(-0.03, 0.03)

	# ③ 许愿石堆：五块大小不一的卵石，围在祭坛外圈
	for i in 5:
		var stone_pos := _safe_ring_point(center, 2.8, 4.8, 1.5)
		if not stone_pos.is_finite():
			continue
		var stone_h := _rng.randf_range(0.45, 1.05)
		var stone_r := _rng.randf_range(0.35, 0.75)
		var stone_mesh := _cylinder_mesh(stone_r, stone_h, stone_r * _rng.randf_range(0.55, 0.85), 7)
		_mesh_piece("Frost_CairnStone", stone_mesh, Vector3(stone_pos.x, stone_h * 0.5, stone_pos.y),
			_solid(Color("8fa2ad").darkened(_rng.randf_range(0.0, 0.25)), 0.95),
			_rng.randf() * TAU, Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12)))

	# ④ 冰晶丛：淡蓝自发光棱柱（倾斜后由 _ground_fit 兜底贴地）
	for i in 7:
		var crystal_pos := _safe_ring_point(center, 2.0, 6.6, 1.4)
		if not crystal_pos.is_finite():
			continue
		var crystal_h := _rng.randf_range(0.7, 2.5)
		var crystal_r := _rng.randf_range(0.16, 0.46)
		var crystal_mesh := _cylinder_mesh(crystal_r, crystal_h, 0.02, 5)
		_mesh_piece("Frost_IceCrystal", crystal_mesh, Vector3(crystal_pos.x, crystal_h * 0.5, crystal_pos.y),
			_glow(Color("b6e0ff"), 1.0), _rng.randf() * TAU,
			Vector3(_rng.randf_range(-0.22, 0.22), 0.0, _rng.randf_range(-0.22, 0.22)), false)

	# ⑤ 冷色灯笼：三盏立在栈道与祭坛之间
	var lantern_spots: Array[Vector2] = [
		Vector2(28.9, -54.2),
		Vector2(37.4, -52.7),
		Vector2(31.8, -56.4),
	]
	for i in lantern_spots.size():
		_build_lantern("Frost_Lantern", lantern_spots[i], _rng.randf() * TAU,
			Color("3f5d6b"), Color("a8e4ff"), 2.5 + 0.15 * float(i))

	# ⑥ 雪斑：贴地薄圆片，暗示终年不化的薄雪（间距由 _safe_ring_point 控制）
	for i in 5:
		var snow_pos := _safe_ring_point(center, 2.4, 7.0, 2.4)
		if not snow_pos.is_finite():
			continue
		var snow_r := _rng.randf_range(0.7, 1.5)
		# v45：薄雪堆（不规则边缘 + 圆丘起伏 + 压暗的冷白），不再是纯白 8 边形圆盘
		_mesh_piece("Frost_SnowPatch", _frost_snow_mesh(snow_r, _rng.randf_range(0.05, 0.085)),
			Vector3(snow_pos.x, 0.04, snow_pos.y), _solid(Color("eef3f6"), 1.0),
			_rng.randf() * TAU, Vector3.ZERO, false)

	# ⑦ 水潭浮冰：贴着潭面漂（水面高 WATER_HIGH_Y=0.30），白名单不参与接地归一。
	# v43：水潭随瀑布迁到 (56,-64)（半轴 6×5），浮冰随之搬到潭西 / 潭南水面。
	var floes: Array[Vector2] = [Vector2(51.7, -63.5), Vector2(52.1, -65.1), Vector2(51.8, -61.9)]
	for floe_pos in floes:
		# v45：不规则有机轮廓 + 倒角厚度 + 冰蓝半透 / 微发光（不再是纯白 12 边形圆盘）
		var floe := _mesh_piece("Frost_IceFloe", _frost_floe_mesh(0.86),
			Vector3(floe_pos.x, 0.30, floe_pos.y), _ice_material(),
			_rng.randf() * TAU, Vector3.ZERO, false)
		# 吃水线压到水面下 3cm：侧壁下半截沉在水里，形成一圈深色水下暗缘
		_mark(floe, &"fit_min_y", 0.27)
		# 锚定：贴地贴片不参与压路判定，但不能被互穿推离推到岸上（v45 实锤：浮冰会被推到草皮）
		_mark(floe, &"anchor", true)
	# ⑦b 潭西岸的霜景小件（冰晶 / 雪斑）：低矮棱面冰晶丛（不再是纯白圆锥）+ 贴地雪堆
	var bank_crystals: Array[Vector2] = [Vector2(48.8, -66.4), Vector2(49.5, -63.9)]
	for crystal_pos in bank_crystals:
		_build_frost_crystal_cluster(Vector3(crystal_pos.x, 0.0, crystal_pos.y))
	# 小片雪斑：贴着潭北岸的草皮（原先 3 片半径 0.8~1.4m 的纯白圆盘在太阳下像漂浮的冰面）
	var bank_snow: Array[Vector2] = [Vector2(48.4, -62.3), Vector2(47.7, -65.2)]
	for i in bank_snow.size():
		var snow_pos: Vector2 = bank_snow[i]
		var patch := _mesh_piece("Frost_SnowPatch", _frost_snow_mesh(_rng.randf_range(0.46, 0.68),
			_rng.randf_range(0.035, 0.06)),
			Vector3(snow_pos.x, 0.035, snow_pos.y), _solid(Color("eef3f6"), 1.0),
			_rng.randf() * TAU, Vector3.ZERO, false)
		_mark(patch, &"anchor", true)

	# ⑧ 一盏冰蓝区域灯（祭坛上方），把核心区从冷色草地里「挑」出来
	_add_light(center + Vector2(0.8, -0.6), 3.0, accent, 14.0, 1.15, false, 0.0, 1.0, 0.0)


## 霜区专用：薄雪堆网格（v45）。不规则噪声轮廓 + 两圈收拢的圆丘 + 面法线明暗，
## 让雪斑读作「地上积起来的一小堆雪」而不是一张纯白圆纸。
func _frost_snow_mesh(radius: float, height: float) -> ArrayMesh:
	var seg := 18
	var ph := _rng.randf_range(0.0, TAU)
	var ph2 := _rng.randf_range(0.0, TAU)
	var outline: Array[Vector2] = []
	for k in seg:
		var a := TAU * float(k) / float(seg)
		var r := radius * (1.0 + 0.22 * sin(a * 3.0 + ph) + 0.14 * sin(a * 5.0 + ph2)
			+ 0.09 * sin(a * 9.0 - ph) + 0.05 * sin(a * 13.0 + ph2)) 			* _rng.randf_range(0.88, 1.06)
		outline.append(Vector2(cos(a) * r, sin(a) * r))
	var outer: Array[Vector3] = []
	var mid: Array[Vector3] = []
	var inner: Array[Vector3] = []
	for k in seg:
		var p := outline[k]
		outer.append(Vector3(p.x, 0.004, p.y))
		mid.append(Vector3(p.x * 0.72, height * 0.55, p.y * 0.72))
		inner.append(Vector3(p.x * 0.36, height * 0.88, p.y * 0.36))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in seg:
		var k2 := (k + 1) % seg
		_add_snow_quad(st, inner[k2], inner[k], mid[k], mid[k2])
		_add_snow_quad(st, mid[k2], mid[k], outer[k], outer[k2])
	var apex := Vector3(_rng.randf_range(-0.10, 0.10) * radius, height * 1.0,
		_rng.randf_range(-0.10, 0.10) * radius)
	for k in seg:
		_add_snow_tri(st, apex, inner[k], inner[(k + 1) % seg])
	return st.commit() as ArrayMesh


func _add_snow_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_snow_tri(st, a, b, c)
	_add_snow_tri(st, a, c, d)


## 雪面三角形：法线强制朝上（圆丘才有明暗层次）。
## 注意：绕序必须与池面 _add_flat_tri 同一套（Godot 正面约定），只翻法线不翻绕序——
## 翻绕序会把整个雪斑变成背面剔除掉（v45 实锤：雪斑完全不可见）。
func _add_snow_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	if n.y < 0.0:
		n = -n
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)


## 霜区专用：浮冰网格（v45）。不规则有机轮廓（三阶谐波 + 抖动）+ 倒角 + 侧壁厚度，
## 顶点色分层：顶面冰蓝偏白 → 倒角高光 → 侧壁深蓝，配合 _ice_material 的半透明微发光。
func _frost_floe_mesh(radius: float) -> ArrayMesh:
	var seg := 16
	var ph := _rng.randf_range(0.0, TAU)
	var ph2 := _rng.randf_range(0.0, TAU)
	var outline: Array[Vector2] = []
	for k in seg:
		var a := TAU * float(k) / float(seg)
		var rough := (1.0 + 0.22 * sin(a * 3.0 + ph) + 0.13 * sin(a * 5.0 + ph2)
			+ 0.08 * sin(a * 9.0 - ph))
		# 破碎边：个别顶点向内咬掉一块，避免读成一块规整的圆形塑料片
		if k == 3 or k == 10:
			rough *= 0.72
		var r := radius * rough * _rng.randf_range(0.86, 1.06)
		outline.append(Vector2(cos(a) * r, sin(a) * r))
	# 薄冰：顶面 4.5cm、倒角 1.2cm、侧壁到 -4.5cm（下半截沉在水面下 = 暗缘）
	var top_y := 0.045
	var bevel_y := 0.012
	var bottom_y := -0.045
	var c_top := Color(0.60, 0.78, 0.92)
	var c_apex := Color(0.74, 0.88, 0.97)
	var c_bevel := Color(0.90, 0.97, 1.0)
	var c_side := Color(0.26, 0.45, 0.66)
	var c_bottom := Color(0.14, 0.28, 0.44)
	var top: Array[Vector3] = []
	var inner: Array[Vector3] = []
	var bevel: Array[Vector3] = []
	var wall: Array[Vector3] = []
	for k in seg:
		var p := outline[k]
		inner.append(Vector3(p.x * 0.58, top_y + 0.008, p.y * 0.58))
		top.append(Vector3(p.x * 0.86, top_y, p.y * 0.86))
		bevel.append(Vector3(p.x, bevel_y, p.y))
		wall.append(Vector3(p.x * 0.92, bottom_y, p.y * 0.92))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex := Vector3(_rng.randf_range(-0.10, 0.10) * radius, top_y + 0.014,
		_rng.randf_range(-0.10, 0.10) * radius)
	for k in seg:
		var k2 := (k + 1) % seg
		_add_ice_tri(st, apex, c_apex, inner[k], c_apex, inner[k2], c_apex, Vector3.UP)
		_add_ice_tri(st, inner[k], c_top, top[k], c_top, top[k2], c_top, Vector3.UP)
		_add_ice_tri(st, inner[k], c_top, top[k2], c_top, inner[k2], c_top, Vector3.UP)
		var mid := Vector3((top[k].x + bevel[k].x) * 0.5, 0.55, (top[k].z + bevel[k].z) * 0.5)
		_add_ice_tri(st, top[k], c_bevel, bevel[k], c_bevel, bevel[k2], c_bevel, mid.normalized())
		_add_ice_tri(st, top[k], c_bevel, bevel[k2], c_bevel, top[k2], c_bevel, mid.normalized())
		var out := Vector3((bevel[k].x + wall[k].x) * 0.5, 0.0, (bevel[k].z + wall[k].z) * 0.5)
		_add_ice_tri(st, bevel[k], c_side, wall[k], c_side, wall[k2], c_side, out.normalized())
		_add_ice_tri(st, bevel[k], c_side, wall[k2], c_side, bevel[k2], c_side, out.normalized())
	var bottom_apex := Vector3(0.0, bottom_y - 0.006, 0.0)
	for k in seg:
		_add_ice_tri(st, wall[k], c_bottom, bottom_apex, c_bottom, wall[(k + 1) % seg], c_bottom,
			Vector3.DOWN)
	return st.commit() as ArrayMesh


## 冰面三角形：法线按面算，并沿 hint 方向修正（cull_disabled，绕序不影响可见性）。
func _add_ice_tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3,
		cc: Color, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	if n.dot(hint) < 0.0:
		n = -n
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(pair[1])
		st.add_vertex(pair[0])


## 霜区专用：低矮棱面冰晶丛（v45）。3 根不规则棱柱，根部埋进地面 / 水面，
## 冰蓝半透 + 微发光（复用 _ice_material），不再是一根纯白自发光圆锥。
func _build_frost_crystal_cluster(at: Vector3) -> Node3D:
	var node := _piece("Frost_IceCrystal", at)
	var shards: Array = [
		[0.30, 0.62, Vector2(0.06, 0.02), 0.35],
		[0.22, 0.44, Vector2(-0.09, 0.05), 2.30],
		[0.15, 0.28, Vector2(0.10, -0.06), 4.15],
	]
	for i in shards.size():
		var item: Array = shards[i]
		var radius: float = item[0]
		var height: float = item[1]
		var lean: Vector2 = item[2]
		var yaw: float = item[3]
		var shard := _part(node, _frost_crystal_mesh(radius, height, lean),
			Vector3(cos(yaw) * radius * 0.9, 0.0, sin(yaw) * radius * 0.9), _ice_material())
		shard.rotation.y = yaw
		shard.rotation.z = _rng.randf_range(-0.10, 0.10)
	# 根部埋进地面（-0.10）：低矮、贴地、没有悬空的白色锥尖
	_mark(node, &"fit_min_y", -0.10)
	_mark(node, &"anchor", true)
	return node


## 冰晶棱柱网格（局部坐标，底部在 y = -0.06）：六棱 + 3 圈收分 + 倾斜尖顶，
## 顶点色从根部深蓝到尖端冰白，面法线按外法线修正（材质 CULL_DISABLED）。
func _frost_crystal_mesh(radius: float, height: float, lean: Vector2) -> ArrayMesh:
	var seg := 6
	var ph := _rng.randf_range(0.0, TAU)
	var rings: Array = [[1.0, -0.06], [0.80, 0.24], [0.52, 0.58], [0.24, 0.84]]
	var c_base := Color(0.26, 0.44, 0.62)
	var c_mid := Color(0.52, 0.72, 0.88)
	var c_tip := Color(0.86, 0.94, 1.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for ring in rings:
		var rf: float = ring[0]
		var hf: float = float(ring[1]) * height
		var row: Array[Vector3] = []
		for k in seg:
			var a := TAU * float(k) / float(seg) + ph * 0.15
			var r := radius * rf * (1.0 + 0.13 * sin(a * 3.0 + ph) + 0.07 * sin(a * 5.0 - ph))
			row.append(Vector3(cos(a) * r + lean.x * hf * 0.55,
				hf, sin(a) * r + lean.y * hf * 0.55))
		rows.append(row)
	for r in 2:
		var lower: Array[Vector3] = rows[r]
		var upper: Array[Vector3] = rows[r + 1]
		for k in seg:
			var k2 := (k + 1) % seg
			var hint := Vector3((lower[k].x + upper[k].x) * 0.5, 0.25,
				(lower[k].z + upper[k].z) * 0.5).normalized()
			_add_ice_tri(st, lower[k], c_base, upper[k], c_mid, upper[k2], c_mid, hint)
			_add_ice_tri(st, lower[k], c_base, upper[k2], c_mid, lower[k2], c_mid, hint)
	var last: Array[Vector3] = rows[3]
	var apex := Vector3(lean.x * height * 0.75, height * 1.06, lean.y * height * 0.75)
	for k in seg:
		var k2 := (k + 1) % seg
		var up_hint := Vector3(last[k].x, 0.7, last[k].z).normalized()
		_add_ice_tri(st, last[k], c_tip, apex, c_tip, last[k2], c_tip, up_hint)
	return st.commit() as ArrayMesh


## 霜语瀑布的许愿祭坛：叠石台 + 石碗 + 冰蓝许愿球 + 四面符文石 + 四根矮冰柱。
func _build_frost_altar(pos: Vector2, accent: Color) -> Node3D:
	var altar := _piece("Frost_Altar", Vector3(pos.x, 0.0, pos.y))
	_part_cylinder(altar, Vector3(0, 0.22, 0), 2.15, 0.44, Color("7e8f9a"), 2.0, 8)
	_part_cylinder(altar, Vector3(0, 0.62, 0), 1.65, 0.36, Color("8fa2ad"), 1.5, 8)
	_part_cylinder(altar, Vector3(0, 0.96, 0), 1.15, 0.32, Color("a2b4be"), 1.0, 8)
	# 石碗 + 许愿球
	_part_cylinder(altar, Vector3(0, 1.24, 0), 0.72, 0.24, Color("93a6b0"), 0.50, 8)
	_part_sphere(altar, Vector3(0, 1.62, 0), 0.34, accent, -1.0, 2.4)
	# 四面符文石：淡蓝自发光薄片，朝向台外
	for i in 4:
		var angle := float(i) * TAU / 4.0 + PI * 0.25
		var rune := _part_box(altar, Vector3(cos(angle) * 1.45, 0.86, sin(angle) * 1.45),
			Vector3(0.42, 0.55, 0.10), Color("c6ecff"), 2.0)
		rune.rotation.y = -angle + PI * 0.5
	# 四根矮冰柱：把祭坛围成一个「仪式圈」
	for i in 4:
		var angle2 := float(i) * TAU / 4.0
		_part_cylinder(altar, Vector3(cos(angle2) * 2.5, 0.5, sin(angle2) * 2.5),
			0.22, 0.9, Color("c6ecff"), 0.03, 5, 1.4)
	return altar


# ============================================================================
# 东北 · 星落矿坑：矿洞入口 + 矿轨矿车 + 紫色发光矿石簇 + 木箱木桶 + 矿灯
# ============================================================================

func _build_mine(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]
	var front := _region_front(region)
	var perp := Vector2(-front.y, front.x)
	# 模型正面（+Z）朝向探索小径来向：旅人从矿轨那头走过来正好看见洞口。
	var face_yaw := atan2(-front.x, -front.y)

	# ① 矿洞入口（KayKit building_mine_blue）：整片区域的视觉主角 / 锚点
	_mark(_model(BUILDING_DIR, "building_mine_blue", "Mine_Entrance", center, 4.0, face_yaw, 0.0),
		&"anchor", true)

	# ② 矿轨 + 矿车：缩到洞口前 4.5m（v40.1：原 11m 会横穿小径），整组装进一个容器。
	var track := _piece("Mine_Track", Vector3.ZERO)
	var rail_dir := -front   # 从洞口指向小径
	var rail_center := center + rail_dir * 6.15
	var rail_yaw := _yaw_align_z(rail_dir)
	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		var rail_pos := rail_center + perp * (0.55 * side)
		var rail := _part_box(track, Vector3(rail_pos.x, 0.10, rail_pos.y),
			Vector3(0.14, 0.16, 4.5), Color("5a5148"))
		rail.rotation.y = rail_yaw
	for i in 4:
		var sleeper_pos := center + rail_dir * (4.3 + float(i) * 0.7)
		var sleeper := _part_box(track, Vector3(sleeper_pos.x, 0.05, sleeper_pos.y),
			Vector3(1.55, 0.10, 0.36), Color("4a3f34"))
		sleeper.rotation.y = rail_yaw
	# 矿车：车斗 + 四轮 + 斗里的紫矿（轮底落在轨面 y≈0.18 上）
	var cart_pos := center + rail_dir * 4.9
	_part_box(track, Vector3(cart_pos.x, 0.83, cart_pos.y), Vector3(1.15, 0.62, 1.55), Color("5a5148"))
	_part_box(track, Vector3(cart_pos.x, 1.15, cart_pos.y), Vector3(1.25, 0.08, 1.65), Color("6b6258"))
	for sx_f in [-1.0, 1.0]:
		for sz_f in [-1.0, 1.0]:
			var sx: float = sx_f
			var sz: float = sz_f
			var wheel_pos: Vector2 = cart_pos + perp * (0.62 * sx) + rail_dir * (0.50 * sz)
			var wheel := _part_cylinder(track, Vector3(wheel_pos.x, 0.48, wheel_pos.y),
				0.30, 0.12, Color("3f3a34"), 0.30, 8)
			wheel.rotation.z = PI * 0.5
	_part_sphere(track, Vector3(cart_pos.x, 1.20, cart_pos.y), 0.32, Color("8a5cff"), 0.24, 1.7)

	# ③ 紫色发光矿石簇：矿洞内溢出的紫光（区域 accent），散在洞口外围
	for i in 6:
		var ore_pos := _safe_ring_point(center, 2.2, 7.2, 1.6)
		if not ore_pos.is_finite():
			continue
		var ore_h := _rng.randf_range(0.45, 1.75)
		var ore_r := _rng.randf_range(0.16, 0.44)
		_mesh_piece("Mine_StarOre", _cylinder_mesh(ore_r, ore_h, 0.02, 5),
			Vector3(ore_pos.x, ore_h * 0.5, ore_pos.y), _glow(Color("8a5cff"), 1.7),
			_rng.randf() * TAU, Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3)), false)

	# ④ 采矿杂物：洞口两侧成组摆放，同类之间留 ≥2.2m（互穿由 _separate_props 兜底）
	var crate_data: Array = [
		[1.2, 4.6], [0.3, 5.6], [2.4, 5.9],
	]
	for entry in crate_data:
		var crate_local: Array = entry
		_model(PROP_DIR, "crate_A_small", "Mine_Crate",
			_mouth_point(center, front, perp, float(crate_local[0]), float(crate_local[1])), 3.5, _rng.randf() * TAU)
	_model(PROP_DIR, "crate_A_big", "Mine_CrateBig", _mouth_point(center, front, perp, 1.0, -3.6), 3.2, 0.8)
	_model(PROP_DIR, "crate_long_A", "Mine_CrateLong", _mouth_point(center, front, perp, 1.6, -5.2), 3.5, 2.1)
	_model(PROP_DIR, "crate_long_A", "Mine_CrateLong", _mouth_point(center, front, perp, 4.0, 4.9), 3.5, -0.7)
	_model(PROP_DIR, "barrel", "Mine_Barrel", _mouth_point(center, front, perp, 3.4, 3.4), 3.0, 0.9)
	_model(PROP_DIR, "barrel", "Mine_Barrel", _mouth_point(center, front, perp, 0.4, -2.6), 3.0, 2.4)
	_model(PROP_DIR, "wheelbarrow", "Mine_Wheelbarrow", _mouth_point(center, front, perp, 5.2, 6.6), 3.2, 2.2)
	_model(PROP_DIR, "pallet", "Mine_Pallet", _mouth_point(center, front, perp, 4.8, -3.8), 3.4, 1.1)
	_model(PROP_DIR, "resource_stone", "Mine_Rubble", _mouth_point(center, front, perp, 5.6, 3.2), 4.5, 0.4)
	_model(PROP_DIR, "sack", "Mine_Sack", _mouth_point(center, front, perp, 0.2, 4.0), 3.4, 1.9)
	# 梯子靠在洞口外壁（不放轨道上）
	var ladder := _model(PROP_DIR, "ladder", "Mine_Ladder", _mouth_point(center, front, perp, 3.0, -7.0), 3.0, 1.2)
	if ladder != null:
		ladder.rotation.x = -0.24

	# ⑤ 两盏矿灯（暖色），照出洞口前的工作面
	var lamp_spots: Array[Vector2] = [
		_mouth_point(center, front, perp, 2.6, 3.6),
		_mouth_point(center, front, perp, 3.2, -4.6),
	]
	for i in lamp_spots.size():
		_build_lantern("Mine_Lantern", lamp_spots[i], _rng.randf() * TAU,
			Color("4a3f34"), Color("ffbe6e"), 2.2 + 0.2 * float(i))

	# ⑥ 洞口紫光（区域 accent）
	_add_light(center, 2.4, accent, 13.0, 1.45, false, 0.0, 1.0, 0.0)


# ============================================================================
# 东境 · 风吟麦海：风车 + 成排农田 + 稻草人 + 干草堆 + 栅栏 + 金色灯笼
# ============================================================================

func _build_wheat(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]
	var front := _region_front(region)
	var face_yaw := atan2(-front.x, -front.y)

	# ① 风车（地标核心 / 锚点）。目录文档记的「y 起 -0.5」是只量了风叶网格
	#    （building_windmill_top_fan）——整场景实测 y 从 0 到 1.46，不需要 +0.5 偏移，
	#    加了反而会整座浮空。风车周围 4m 内不放别的道具。
	var windmill_pos := center + Vector2(0.6, 1.6)
	var windmill := _model(BUILDING_DIR, "building_windmill_blue", "Wheat_Windmill", windmill_pos, 4.2, face_yaw, 0.0)
	if windmill != null:
		_mark(windmill, &"anchor", true)
		# v40.2：扇叶节点绕本地 Z 轴缓慢旋转（gltf 扇面在 XY 平面，无内置动画）。
		var fan := windmill.find_child("building_windmill_top_fan_blue", true, false) as Node3D
		if fan != null:
			_spinners.append({"node": fan, "axis": Vector3(0.0, 0.0, 1.0), "speed": 0.45})

	# ② 成排农田：2 行 × 3 列，scale 1.5（v40.1：原 2.2 太大互相压），行/列间距 5m
	for row in 2:
		for col in 3:
			var plot := Vector2(89.5 + float(col) * 5.0, 10.0 + float(row) * 5.0)
			_model(BUILDING_DIR, "building_grain", "Wheat_Field", plot, 1.5,
				face_yaw + _rng.randf_range(-0.05, 0.05), 0.02)

	# ③ 栅栏：两段连续围栏（同一直线端点相接），贴地由 _ground_fit 归零
	var fence_yaw_x := _yaw_align_z(Vector2(1.0, 0.0))
	for i in 3:
		_model(BUILDING_DIR, "fence_wood_straight", "Wheat_Fence",
			Vector2(89.0 + float(i) * 3.0, 17.9), 2.6, fence_yaw_x)
	for i in 3:
		_model(BUILDING_DIR, "fence_wood_straight", "Wheat_Fence",
			Vector2(84.3, 9.5 + float(i) * 3.0), 2.6, 0.0)

	# ④ 稻草人：立在两行农田之间的走道上，远离风车
	_build_scarecrow(Vector2(92.0, 12.5), face_yaw + PI)
	_build_scarecrow(Vector2(97.0, 12.5), face_yaw - 0.3)

	# ⑤ 干草堆：三捆躺倒的草卷，堆在麦场南口
	var hay_spots: Array[Vector2] = [Vector2(100.5, 18.5), Vector2(102.5, 16.8), Vector2(98.5, 20.2)]
	for i in hay_spots.size():
		_mesh_piece("Wheat_HayBale", _cylinder_mesh(0.75, 1.5, -1.0, 10),
			Vector3(hay_spots[i].x, 0.75, hay_spots[i].y), _solid(Color("c9a758"), 0.95),
			0.35 + float(i) * 0.7, Vector3(0.0, 0.0, PI * 0.5))

	# ⑥ 金色灯笼：麦场入口 / 南口 / 东口各一盏
	var lantern_spots: Array[Vector2] = [Vector2(87.4, 6.0), Vector2(93.2, 19.4), Vector2(101.9, 9.2)]
	for i in lantern_spots.size():
		_build_lantern("Wheat_Lantern", lantern_spots[i], _rng.randf() * TAU,
			Color("5b4a32"), Color("ffd88a"), 2.6 + 0.2 * float(i))

	# ⑦ 风车边的麻袋 + 水井（都在风车 4m 净空之外）
	_model(PROP_DIR, "sack", "Wheat_Sack", Vector2(90.2, 6.8), 3.2, 0.7)
	_model(PROP_DIR, "sack", "Wheat_Sack", Vector2(97.8, 9.2), 3.2, 2.3)
	_model(BUILDING_DIR, "building_well_blue", "Wheat_Well", Vector2(100.2, 6.4), 2.7, face_yaw + 0.6, 0.0)

	# ⑧ 暖金区域灯（风车下方）
	_add_light(windmill_pos, 3.4, accent, 12.0, 1.2, false, 0.0, 1.0, 0.0)


# ============================================================================
# 南境 · 烬誓战场：断旗与歪旗杆 + 墓碑阵 + 破碎城墙 + 武器架 + 焦木余烬
# ============================================================================

func _build_battle(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]

	# ① 折断的红旗与歪旗杆：五面旗，一面倒地、三面歪斜、一面还立着。
	#    位置避开三面断墙的占地（断墙是锚点，旗子是可动件）。
	var flag_data: Array = [
		[Vector2(1.2, 95.6), 1.2, Vector3(0.0, 0.0, -0.35), 8.0],
		[Vector2(2.0, 97.5), 2.4, Vector3(0.0, 0.0, 1.30), 8.5],
		[Vector2(3.2, 99.6), -0.6, Vector3(-0.50, 0.0, 0.0), 7.5],
		[Vector2(2.6, 93.4), 0.9, Vector3(0.0, 0.0, 0.62), 8.0],
		[Vector2(7.6, 87.4), 2.8, Vector3(0.04, 0.0, 0.0), 9.0],
	]
	for entry in flag_data:
		var flag_pos: Vector2 = entry[0]
		var yaw: float = entry[1]
		var tilt: Vector3 = entry[2]
		var flag_scale: float = entry[3]
		var flag := _model(PROP_DIR, "flag_red", "Battle_BrokenFlag", flag_pos, flag_scale, yaw)
		if flag != null:
			flag.rotation = Vector3(tilt.x, yaw, tilt.z)

	# ② 墓碑阵：五块歪斜的石碑 + 一座纪念十字（地标中心 / 锚点）
	for i in 5:
		var grave_pos := _safe_ring_point(center, 2.8, 5.6, 1.6)
		if not grave_pos.is_finite():
			continue
		_mesh_piece("Battle_Gravestone", _box_mesh(Vector3(0.85, 1.15, 0.22)),
			Vector3(grave_pos.x, 0.52, grave_pos.y), _solid(Color("777263"), 0.97),
			_rng.randf() * TAU, Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.18, 0.18)))
	var cross := _piece("Battle_MemorialCross", Vector3(center.x, 0.0, center.y))
	_part_box(cross, Vector3(0, 0.95, 0), Vector3(0.22, 1.9, 0.22), Color("6e6a5c"))
	_part_box(cross, Vector3(0, 1.35, 0), Vector3(0.92, 0.20, 0.22), Color("6e6a5c"))
	_mark(cross, &"anchor", true)

	# ③ 破碎城墙：三段半塌的墙体，围着战场东 / 北 / 西三面
	var wall_data: Array = [
		[Vector2(8.6, 92.8), 0.7],
		[Vector2(8.0, 99.6), -0.4],
		# v40.1：原 (0.4, 91.6) 的墙体 AABB 中心离南主路只有 ~1.8m；墙体 AABB 旋转后
		# 约 6×6m，离其他断墙太近会互相穿，因此放到战场东北角空地 (14, 103)。
		[Vector2(14.0, 103.0), 1.9],
	]
	for entry in wall_data:
		var wall_pos: Vector2 = entry[0]
		var wall_yaw: float = entry[1]
		# 断墙是大件地标：标成锚点，让旗 / 焦木 / 军械这些小家伙让开它，
		# 避免互穿修复把整面墙推回小径里（v40.1 曾把 _03 推到离路 1.64m）。
		var wall := _model(BUILDING_DIR, "building_destroyed", "Battle_RuinWall", wall_pos, 3.2, wall_yaw)
		if wall != null:
			wall.set_meta(&"anchor", true)

	# ④ 遗落的军械：武器架 / 箭靶 / 箭桶 / 梯子（都避开断墙占地）
	_model(PROP_DIR, "weaponrack", "Battle_WeaponRack", Vector2(4.4, 94.4), 4.0, 0.4)
	_model(PROP_DIR, "weaponrack", "Battle_WeaponRack", Vector2(1.0, 96.2), 4.0, 2.4)
	_model(PROP_DIR, "target", "Battle_Target", Vector2(5.6, 89.8), 3.5, 0.2)
	_model(PROP_DIR, "bucket_arrows", "Battle_ArrowBucket", Vector2(4.2, 92.6), 3.5, 0.9)
	var battle_ladder := _model(PROP_DIR, "ladder", "Battle_Ladder", Vector2(7.0, 97.2), 3.2, 2.6)
	if battle_ladder != null:
		battle_ladder.rotation.z = 0.22

	# ⑤ 焦木：三根烧黑的横木
	var log_data: Array = [
		[Vector2(0.6, 95.2), 0.8],
		[Vector2(4.6, 86.8), 2.1],
		[Vector2(4.8, 102.2), 1.2],
	]
	for entry in log_data:
		var log_pos: Vector2 = entry[0]
		var log_yaw: float = entry[1]
		var log_len := _rng.randf_range(2.2, 2.9)
		_mesh_piece("Battle_CharredLog", _cylinder_mesh(0.26, log_len, 0.20, 6),
			Vector3(log_pos.x, 0.26, log_pos.y), _solid(Color("2b241f"), 0.99),
			log_yaw, Vector3(0.0, 0.0, PI * 0.5))

	# ⑥ 余烬：橙色自发光小球（不灭的烬誓）
	var ember_spots: Array[Vector2] = [Vector2(1.2, 95.0), Vector2(4.6, 87.4), Vector2(3.2, 91.6), Vector2(5.2, 101.6)]
	for i in ember_spots.size():
		var ember_r := 0.20 + 0.04 * float(i)
		_mesh_piece("Battle_Ember", _sphere_mesh(ember_r, ember_r * 1.4, 8, 4),
			Vector3(ember_spots[i].x, 0.16, ember_spots[i].y), _glow(Color("ff8a4a"), 3.0),
			0.0, Vector3.ZERO, false)

	# ⑦ 焦土斑：三小块（v40.1：原 r=3.4 的大圆盘像一块黑饼）。
	#    命名保留 "AshField" 关键词——ScenePolishTest 把 AshField 归入贴地贴片，
	#    豁免两两互穿与压路判定（斑点垫在道具脚下属设计）。
	var ash_spots: Array[Vector3] = [Vector3(2.0, 0.0, 93.4), Vector3(6.6, 0.0, 96.6), Vector3(3.6, 0.0, 100.2)]
	for i in ash_spots.size():
		var ash_r := 1.0 + 0.25 * float(i)
		_mesh_piece("Battle_AshField", _disc_mesh(ash_r, 0.04, 8),
			Vector3(ash_spots[i].x, 0.03, ash_spots[i].z), _solid(Color("3a322a"), 0.99),
			_rng.randf() * TAU, Vector3.ZERO, false)

	# ⑧ 一盏闪烁的橙色火灯（唯一闪烁光源，_process 统一驱动）
	_add_light(center, 2.3, accent, 12.0, 1.5, true, 0.5, 6.3, 0.4)


# ============================================================================
# 西境 · 雾隐密林：苔封石祭坛（绿色符文）+ 立石阵 + 蘑菇群 + 古树环 + 萤火
# ============================================================================

func _build_forest(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]
	var altar_pos := center + Vector2(-0.5, -2.4)

	# ① 苔封石祭坛（地标核心 / 锚点）：三层叠石 + 树灵光球 + 四面绿符文
	_mark(_build_forest_altar(altar_pos, accent), &"anchor", true)

	# ② 立石阵：七根风化立石围成不完整的环（苔藓灰绿），固定角度保证互不重叠
	for i in 7:
		var angle := float(i) * TAU / 7.0 + _rng.randf_range(-0.10, 0.10)
		var radius := 4.6 + float(i % 3) * 0.7
		var stone_pos := altar_pos + Vector2(cos(angle), sin(angle)) * radius
		if not _decor_ok(stone_pos):
			continue
		var stone_h := _rng.randf_range(2.0, 3.6)
		var stone_r := _rng.randf_range(0.45, 0.75)
		_mesh_piece("Forest_StandingStone", _cylinder_mesh(stone_r, stone_h, stone_r * _rng.randf_range(0.45, 0.7), 5),
			Vector3(stone_pos.x, stone_h * 0.5, stone_pos.y),
			_solid(Color("6f7a63").darkened(_rng.randf_range(0.0, 0.2)), 0.97),
			_rng.randf() * TAU, Vector3(_rng.randf_range(-0.13, 0.13), 0.0, _rng.randf_range(-0.13, 0.13)))

	# ③ 蘑菇群：六朵低模蘑菇（草原 / 林下都有），环上按间距取样
	for i in 6:
		var mushroom_pos := _safe_ring_point(altar_pos, 2.5, 6.0, 1.6)
		if not mushroom_pos.is_finite():
			continue
		_build_mushroom(mushroom_pos, _rng.randf_range(0.8, 1.6))

	# ④ 古树环：8 棵按等角分布（v40.1：原随机环会让树干互相穿），
	#    相邻主干的弦长 2×10.5×sin(π/8) ≈ 8.0m ≥ 4.6m。
	for i in 8:
		var angle := float(i) * TAU / 8.0 + _rng.randf_range(-0.07, 0.07)
		var tree_pos := altar_pos + Vector2(cos(angle), sin(angle)) * (10.5 + _rng.randf_range(-0.4, 0.4))
		var tree_name := "trees_B_large" if i % 2 == 0 else "trees_A_large"
		var tree := _model(NATURE_DIR, tree_name, "Forest_AncientTree", tree_pos,
			_rng.randf_range(2.4, 3.2), _rng.randf() * TAU)
		if tree != null:
			tree.set_meta(&"tree", true)

	# ⑤ 萤火：四颗漂浮的绿色光点（不落地）
	var firefly_angles: Array[float] = [0.4, 1.8, 3.5, 5.1]
	for i in firefly_angles.size():
		var fly_pos := altar_pos + Vector2(cos(firefly_angles[i]), sin(firefly_angles[i])) * (2.2 + float(i) * 0.55)
		var height := 0.9 + 0.35 * float(i)
		_mesh_piece("Forest_Firefly", _sphere_mesh(0.10, 0.10, 6, 3),
			Vector3(fly_pos.x, height, fly_pos.y), _glow(accent, 2.6),
			0.0, Vector3.ZERO, false)

	# ⑥ 倒伏的枯木：两根横躺的苔木
	var fallen_spots: Array[Vector2] = [altar_pos + Vector2(-4.6, 2.6), altar_pos + Vector2(4.4, -2.0)]
	for i in fallen_spots.size():
		_mesh_piece("Forest_FallenLog", _cylinder_mesh(0.32, 3.2, 0.24, 6),
			Vector3(fallen_spots[i].x, 0.32, fallen_spots[i].y), _solid(Color("4e5745"), 0.97),
			_rng.randf() * TAU, Vector3(0.0, 0.0, PI * 0.5))

	# ⑦ 林心一盏绿色区域灯
	_add_light(altar_pos, 2.2, accent, 12.0, 1.1, false, 0.0, 1.0, 0.0)


## 雾隐密林的苔封石祭坛：三层叠石 + 树灵光球 + 四面绿符文 + 一圈苔痕。
func _build_forest_altar(pos: Vector2, accent: Color) -> Node3D:
	var altar := _piece("Forest_Altar", Vector3(pos.x, 0.0, pos.y))
	_part_box(altar, Vector3(0, 0.22, 0), Vector3(2.2, 0.44, 1.6), Color("6b7461"))
	_part_box(altar, Vector3(0, 0.60, 0), Vector3(1.7, 0.34, 1.25), Color("74806a"))
	_part_box(altar, Vector3(0, 0.93, 0), Vector3(1.2, 0.32, 0.9), Color("7d8a70"))
	# 树灵光球
	_part_sphere(altar, Vector3(0, 1.34, 0), 0.28, accent, -1.0, 2.6)
	# 四面绿符文：贴在叠石外侧
	for i in 4:
		var angle := float(i) * TAU / 4.0
		var rune := _part_box(altar, Vector3(cos(angle) * 1.02, 1.02, sin(angle) * 0.78),
			Vector3(0.42, 0.30, 0.07), accent, 2.2)
		rune.rotation.y = -angle + PI * 0.5
	# 祭坛脚下的苔痕
	var moss := _part_disc(altar, Vector3(0, 0.02, 0), 1.9, Color("4a5c3c"), 0.03, 14)
	moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return altar


func _build_mushroom(pos: Vector2, scale_v: float) -> void:
	var mushroom := _piece("Forest_Mushroom", Vector3(pos.x, 0.0, pos.y))
	mushroom.rotation.y = _rng.randf() * TAU
	_part_cylinder(mushroom, Vector3(0, 0.17 * scale_v, 0), 0.07 * scale_v, 0.34 * scale_v,
		Color("d8cfb4"), 0.05 * scale_v, 6)
	_part_sphere(mushroom, Vector3(0, 0.38 * scale_v, 0), 0.22 * scale_v,
		Color("c96a4f"), 0.16 * scale_v, -1.0, 8, 4)


# ============================================================================
# 西南 · 盐风沼地：半沉木船 + 枯树 + 盐壳白斑 + 芦苇 + 青绿色鬼火
# ============================================================================

func _build_swamp(region: Dictionary) -> void:
	var center: Vector2 = region["landmark"]
	var accent: Color = region["accent"]

	# ① 半沉的木船（锚点）：船身抬高到 min_y ≈ -0.10，船帮加高加厚，
	#    船底自带一小片浅色盐泥洼地（作为船的子部件，不另算一个道具，避免互穿）。
	var boat_pos := center + Vector2(-2.2, -1.8)
	_mark(_build_boat(boat_pos, 0.55), &"fit_min_y", -0.10)

	# ② 枯树：三棵只剩枝干的死树
	_build_dead_tree(center + Vector2(-4.5, -4.0), 0.7, 4.4)
	_build_dead_tree(center + Vector2(4.0, 3.5), 2.2, 3.6)
	_build_dead_tree(center + Vector2(-1.5, 5.8), 4.1, 4.0)

	# ③ 树桩与被伐倒的枯树（复用 nature 的 cut 模型）
	_model(NATURE_DIR, "tree_single_B_cut", "Swamp_Stump", center + Vector2(2.0, -2.8), 4.5, 1.3)
	_model(NATURE_DIR, "tree_single_B_cut", "Swamp_Stump", center + Vector2(-5.4, 3.2), 5.0, 3.6)
	# v40.1：trees_A_cut 是一整片「被砍倒的树桩」贴图，远看像满地红棕色小棍，弃用；
	# 改用两根程序化倒木（灰褐色，贴地），保留「被伐倒」的叙事。
	var fallen_log_data: Array = [
		[center + Vector2(6.2, -1.5), 0.9],
		[center + Vector2(-7.2, -1.0), 2.6],
	]
	for entry in fallen_log_data:
		var fallen_pos: Vector2 = entry[0]
		var fallen_yaw: float = entry[1]
		_mesh_piece("Swamp_FallenLog", _cylinder_mesh(0.30, 3.2, 0.22, 6),
			Vector3(fallen_pos.x, 0.32, fallen_pos.y), _solid(Color("554c40"), 0.97),
			fallen_yaw, Vector3(0.0, 0.0, PI * 0.5))

	# ④ 盐壳：三块小盐霜（v40.1：原纯白大圆片像白饼；颜色压向沼泽地面色 #a9ac96），
	#    并与 terrain-scatter 的 salt 斑保持 ≥2m 间距——直接读它的 MultiMesh 实例位置来避让。
	var scatter_salt := _collect_scatter_points("salthollow_salt", center, 14.0)
	var salt_spots: Array[Vector2] = []
	for i in 3:
		var salt_r := _rng.randf_range(0.5, 1.0)
		var salt_pos := _pick_salt_point(center, salt_r, scatter_salt, salt_spots)
		if not salt_pos.is_finite():
			continue
		salt_spots.append(salt_pos)
		_mesh_piece("Swamp_SaltCrust", _disc_mesh(salt_r, 0.035, 7),
			Vector3(salt_pos.x, 0.035, salt_pos.y), _solid(Color("9aa088"), 1.0),
			_rng.randf() * TAU, Vector3.ZERO, false)

	# ⑤ 芦苇：六丛程序化灰绿细秆（v40.1：waterplant_C 贴图偏红棕，放大 4~5.5 倍后
	#    像一地红棍，弃用模型芦苇；程序化细秆颜色更贴沼泽，且数量补到 6 丛、位置分散）。
	var reed_cluster_spots: Array[Vector2] = [
		center + Vector2(-4.8, -6.2),
		center + Vector2(-1.0, 8.0),
		center + Vector2(4.2, 1.2),
		center + Vector2(-7.0, 3.4),
		center + Vector2(2.8, -5.8),
		center + Vector2(6.4, 5.2),
	]
	for i in reed_cluster_spots.size():
		_build_reed_cluster(reed_cluster_spots[i], _rng.randf() * TAU)

	# ⑥ 青绿色鬼火：四颗悬在枯树与船之间的幽光
	var wisp_spots: Array[Vector2] = [
		center + Vector2(-2.2, -1.8),
		center + Vector2(4.0, 3.5),
		center + Vector2(-4.5, -4.0),
		center + Vector2(0.8, 5.0),
	]
	for i in wisp_spots.size():
		var wisp_height := 0.8 + 0.30 * float(i)
		_mesh_piece("Swamp_Wisp", _sphere_mesh(0.18, 0.26, 6, 3),
			Vector3(wisp_spots[i].x, wisp_height, wisp_spots[i].y), _glow(accent, 2.8),
			0.0, Vector3.ZERO, false)

	# ⑦ 商队遗物：一只翻倒的木桶与一个破麻袋
	var barrel := _model(PROP_DIR, "barrel", "Swamp_Barrel", center + Vector2(2.6, 0.8), 3.0, 1.6)
	if barrel != null:
		barrel.rotation.z = 0.5
	_model(PROP_DIR, "sack", "Swamp_Sack", center + Vector2(-2.9, 0.6), 3.2, 2.1)

	# ⑧ 一盏轻微呼吸的青绿鬼火灯（第二个闪烁光源）
	_add_light(center, 1.8, accent, 11.0, 1.0, true, 0.32, 1.7, 2.1)


## 半沉的木船：两根加高加厚的船舷 + 船底 + 两块座板 + 两支桨 + 船下盐泥洼地。
## 整体埋进盐泥 0.10m（由 fit_min_y = -0.10 控制），船身主体仍然清楚地露出地面。
func _build_boat(pos: Vector2, yaw: float) -> Node3D:
	var boat := _piece("Swamp_Boat", Vector3(pos.x, 0.0, pos.y))
	boat.rotation.y = yaw
	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		var hull := _part_box(boat, Vector3(0.68 * side, 0.52, 0), Vector3(0.26, 1.05, 3.4), Color("5c4a35"))
		hull.rotation.z = -0.30 * side
	_part_box(boat, Vector3(0, 0.18, 0), Vector3(1.45, 0.14, 3.4), Color("4a3b2a"))
	_part_box(boat, Vector3(0, 0.56, 0.9), Vector3(1.35, 0.10, 0.34), Color("6b563c"))
	_part_box(boat, Vector3(0, 0.56, -0.9), Vector3(1.35, 0.10, 0.34), Color("6b563c"))
	# 桨顺着船身放在座板上（不穿船帮）
	var oar_a := _part_box(boat, Vector3(0.20, 0.66, 0.5), Vector3(0.10, 0.07, 2.3), Color("7a6547"))
	oar_a.rotation = Vector3(0.0, 0.12, 0.0)
	var oar_b := _part_box(boat, Vector3(-0.20, 0.66, -0.5), Vector3(0.10, 0.07, 2.3), Color("7a6547"))
	oar_b.rotation = Vector3(0.0, -0.10, 0.0)
	# 船下的盐泥洼地：作为船体子部件，按船体当前 AABB 反算局部高度，
	# 使整船接地（min_y = -0.10）之后泥面刚好贴在 y≈0.02 的地面上。
	var hull_box := _world_aabb(boat)
	var mud := _part(boat, _disc_mesh(1.6, 0.04, 10),
		Vector3(0.0, 0.14 + hull_box.position.y, 0.0), _solid(Color("6a6d5c"), 0.99))
	mud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return boat


## 一棵只剩枝干与两根枯枝的死树。
func _build_dead_tree(pos: Vector2, yaw: float, height: float) -> void:
	var tree := _piece("Swamp_DeadTree", Vector3(pos.x, 0.0, pos.y))
	tree.rotation.y = yaw
	_part_cylinder(tree, Vector3(0, height * 0.5, 0), 0.34, height, Color("5b5147"), 0.10, 6)
	for i in 2:
		var side: float = 1.0 if i == 0 else -1.0
		var branch := _part_cylinder(tree, Vector3(0.1 * side, height * (0.52 + 0.2 * float(i)), 0),
			0.09, 1.9, Color("4e453c"), 0.03, 5)
		branch.rotation = Vector3(0.15 * side, float(i) * 2.1, 0.95 * side)


## 一丛干枯的细秆芦苇（程序化，补足模型芦苇之间的密度）。
func _build_reed_cluster(pos: Vector2, yaw: float) -> void:
	var cluster := _piece("Swamp_ReedCluster", Vector3(pos.x, 0.0, pos.y))
	cluster.rotation.y = yaw
	for i in 4:
		var blade := _part_cylinder(cluster,
			Vector3(_rng.randf_range(-0.35, 0.35), 0.62, _rng.randf_range(-0.35, 0.35)),
			0.05, _rng.randf_range(0.9, 1.7), Color("9a9268"), 0.01, 4)
		blade.rotation = Vector3(_rng.randf_range(-0.22, 0.22), 0.0, _rng.randf_range(-0.22, 0.22))


# ============================================================================
# 城郊路标（四门 ±21.5m）与区域入口石碑（探索小径到达点附近）
# ============================================================================

## 四座城门外的出城路标。位置贴在主路外侧（不压路面），牌面朝向城内——
## 旅人出城时正好读到「这条路的尽头是什么」。

# ============================================================================
# 湖上码头 + 小船（v40.2，纯视觉；湖面/湖床已有碰撞与寻路阻挡，不新增碰撞）
# ============================================================================

func _build_lake_dock() -> void:
	# v43：湖泊东迁到 (52,-38)、半轴 (17,12)（含三阶谐波岸线），东岸约 x≈69.1（z≈-40.6）。
	# 栈桥落点用 WorldLayout.lake_shore_point 反算，木板从岸上伸进湖 4.5m。
	var shore := WorldLayout.lake_shore_point(deg_to_rad(-12.0))
	var dock := _piece("Lake_Pier", Vector3(shore.x + 1.2, 0.0, shore.y))
	# 桥面木板（沿 -X 伸入湖面；y=0.52 高于水面 0.06）
	for i in 7:
		var plank := _part_box(dock, Vector3(-0.7 - float(i) * 0.72, 0.52, 0.0),
			Vector3(0.66, 0.10, 1.9), Color("6d5638"))
		plank.rotation.y = _rng.randf_range(-0.02, 0.02)
	# 两根纵梁
	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		_part_box(dock, Vector3(-2.7, 0.40, 0.72 * side), Vector3(5.4, 0.16, 0.18), Color("4e3f2c"))
	# 四根入水木桩（桩插进湖床，min_y 为负属预期）
	for x in [0.2, -2.2, -4.6]:
		for side_f in [-1.0, 1.0]:
			var side2: float = side_f
			_part_cylinder(dock, Vector3(x, -0.15, 0.95 * side2), 0.13, 1.9, Color("4a3b2a"), 0.10, 6)
	# 系船桩 + 系绳（绳从桩斜拉到船头）
	_part_cylinder(dock, Vector3(-4.9, 0.95, 0.0), 0.14, 1.1, Color("54422e"), 0.05, 6)
	var rope := _part_box(dock, Vector3(-6.0, 0.32, -0.55), Vector3(2.4, 0.045, 0.045), Color("8a7753"))
	rope.rotation = Vector3(0.0, 0.55, -0.12)
	# 岸端灯 + 渔具小件（都落在新东岸干地上，不悬空 / 不入水）
	_build_lantern("Lake_Pier_Lantern", Vector2(shore.x + 2.5, shore.y + 1.7), 0.0,
		Color("4a3b2a"), Color("ffc97a"), 2.2)
	_model(PROP_DIR, "crate_A_small", "Lake_Pier_Crate", Vector2(shore.x + 0.9, shore.y - 1.5), 2.2, 0.7)
	_model(PROP_DIR, "sack", "Lake_Pier_Sack", Vector2(shore.x + 1.8, shore.y + 2.6), 2.0, 1.9)
	# 小船：浮在湖面、泊在栈桥南侧（离岸约 7m 的深水区，与栈桥 AABB 错开 2m 以上不互穿，
	# 也让小船在俯视角下完整露出来，不被桥面挡住）
	_build_rowboat(Vector2(shore.x - 6.6, shore.y - 4.4), -0.62)


## 一只低模小木船：船底 + 两侧船帮 + 首尾封板 + 座板 + 双桨。
func _build_rowboat(pos: Vector2, yaw: float) -> void:
	var boat := _piece("Lake_Boat", Vector3(pos.x, 0.12, pos.y))
	boat.rotation.y = yaw
	_part_box(boat, Vector3(0, 0.10, 0), Vector3(1.25, 0.16, 2.9), Color("4f3e2b"))
	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		var hull := _part_box(boat, Vector3(0.58 * side, 0.34, 0), Vector3(0.16, 0.52, 2.9), Color("5f4a33"))
		hull.rotation.z = -0.22 * side
	_part_box(boat, Vector3(0, 0.36, -1.32), Vector3(1.12, 0.42, 0.16), Color("5a4732"))
	_part_box(boat, Vector3(0, 0.40, 1.32), Vector3(0.92, 0.50, 0.16), Color("5a4732"))
	_part_box(boat, Vector3(0, 0.42, -0.42), Vector3(1.05, 0.09, 0.30), Color("6b563c"))
	_part_box(boat, Vector3(0, 0.42, 0.62), Vector3(1.05, 0.09, 0.30), Color("6b563c"))
	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		var oar := _part_box(boat, Vector3(0.72 * side, 0.30, 0.1), Vector3(0.09, 0.06, 2.2), Color("7a6547"))
		oar.rotation = Vector3(0.10, 0.22 * side, 0.0)


func _build_city_signposts() -> void:
	var gold := Color("f2cc40")
	# v43：城半宽 26m → 出城路标从 ±21.5m 挪到 ±27.5m（与 WorldScenery._build_gates 同口径）。
	# 侧向偏移沿用原比例：北/东/西 2.9m，南门 3.87m（牌子挂在路的另一侧）。
	var gate_z := 27.5
	var signs: Array = [
		[Vector2(WorldLayout.road_center_x(-gate_z) + 2.9, -gate_z), 0.0, "北门 · 出城\n霜语瀑布 · 星落矿坑"],
		[Vector2(gate_z, WorldLayout.road_center_z(gate_z) + 2.9), -PI * 0.5, "东门 · 出城\n风吟麦海"],
		[Vector2(WorldLayout.road_center_x(gate_z) - 3.87, gate_z), PI, "南门 · 出城\n烬誓战场"],
		[Vector2(-gate_z, WorldLayout.road_center_z(-gate_z) - 2.9), PI * 0.5, "西门 · 出城\n雾隐密林 · 盐风沼地"],
	]
	for entry in signs:
		var sign_pos: Vector2 = entry[0]
		var sign_yaw: float = entry[1]
		var sign_text: String = entry[2]
		_build_signpost(sign_pos, sign_yaw, sign_text, gold)


## 六块区域入口石碑：落在「地标前方 7.2m、路侧偏 2m」——小径在 8.5m 处收尾，
## 石碑正好立在路尾一侧；牌面朝向小径来向，旅人一进区域就能读到。
func _build_region_steles() -> void:
	var trail_segments := WorldLayout.TRAIL_SEGMENTS
	var first_trail := maxi(0, trail_segments.size() - WorldRegions.count())
	var index := 0
	for region in WorldRegions.all():
		if region["kind"] == WorldRegions.KIND_CITY:
			continue
		var landmark: Vector2 = region["landmark"]
		var accent: Color = region["accent"]
		var title := _short_region_name(String(region["name"]))
		var tag: String = String(REGION_TAGS.get(String(region["kind"]), ""))
		var front := Vector2(1.0, 0.0)
		var trail_index := first_trail + index
		if trail_index >= 0 and trail_index < trail_segments.size():
			var segment: Array = trail_segments[trail_index]
			var a: Vector2 = segment[0]
			var b: Vector2 = segment[1]
			if a.distance_squared_to(b) > 0.0001:
				front = (b - a).normalized()
		var stele_pos := _stele_position(landmark, front)
		# 牌面朝向小径来向：从石碑指向小径起点。
		var approach := landmark - front * 30.0
		var yaw := atan2(approach.x - stele_pos.x, approach.y - stele_pos.y)
		_build_stele(stele_pos, yaw, title, tag, accent)
		index += 1


## 石碑落点：地标前方 7.2m，再在左右各 2m 中挑「离道路更远、且不落水」的一侧。
func _stele_position(landmark: Vector2, front: Vector2) -> Vector2:
	var perp := Vector2(-front.y, front.x)
	var best := landmark - front * STELE_FORWARD
	var best_score := -INF
	for side_f in [1.0, -1.0]:
		var side: float = side_f
		var candidate := landmark - front * STELE_FORWARD + perp * (STELE_SIDE * side)
		var score := WorldLayout.road_distance(candidate)
		if WorldLayout.water_distance(candidate) > WATER_CLEARANCE:
			score += 1.5
		if score > best_score:
			best_score = score
			best = candidate
	return best


## 区域短名：把「北境 · 霜语瀑布」压成「霜语瀑布」（石碑和路标只写地名）。
func _short_region_name(full_name: String) -> String:
	var parts := full_name.split("·")
	if parts.size() >= 2:
		return parts[1].strip_edges()
	return full_name


func _build_signpost(pos: Vector2, yaw: float, text: String, accent: Color) -> void:
	var sign := _mark(_piece("City_Signpost", Vector3(pos.x, 0.0, pos.y)), &"anchor", true)
	sign.rotation.y = yaw
	_part_cylinder(sign, Vector3(0, 1.5, 0), 0.12, 3.0, Color("4a3a29"), -1.0, 8)
	_part_box(sign, Vector3(0, 2.55, 0), Vector3(2.5, 1.10, 0.14), Color("6b5334"))
	_part_box(sign, Vector3(0, 3.14, 0), Vector3(2.7, 0.10, 0.24), Color("4a3a29"))
	_part_sphere(sign, Vector3(0, 2.0, 0.16), 0.15, accent, -1.0, 2.4)
	_label3d(sign, text, Vector3(0, 2.55, 0.09), 0.0, accent, 46)
	_ground_fit(sign, FIT_MIN_Y)


func _build_stele(pos: Vector2, yaw: float, title: String, tag: String, accent: Color) -> void:
	var stele := _mark(_piece("Region_Stele", Vector3(pos.x, 0.0, pos.y)), &"anchor", true)
	stele.rotation.y = yaw
	_part_cylinder(stele, Vector3(0, 0.16, 0), 0.95, 0.32, Color("6f7364"), 0.85, 8)
	_part_box(stele, Vector3(0, 1.18, 0), Vector3(1.32, 1.78, 0.24), Color("8b9081"))
	_part_box(stele, Vector3(0, 2.10, 0), Vector3(1.46, 0.16, 0.32), Color("7a7f70"))
	# 顶部符文晶片：竖起来的发光小圆盘（区域强调色）
	var crystal := _part_cylinder(stele, Vector3(0, 2.16, 0.17), 0.13, 0.06, accent, -1.0, 6, 1.2)
	crystal.rotation.x = PI * 0.5
	_label3d(stele, title + "\n" + tag, Vector3(0, 1.28, 0.14), 0.0, accent, 38)
	_ground_fit(stele, FIT_MIN_Y)


# ============================================================================
# 通用组合件
# ============================================================================

## 一盏立灯：木杆 + 发光灯箱 + 灯帽（共 3 个部件）。
func _build_lantern(piece_name: String, pos: Vector2, yaw: float, pole_color: Color, glow_color: Color, height: float) -> void:
	var lantern := _piece(piece_name, Vector3(pos.x, 0.0, pos.y))
	lantern.rotation.y = yaw
	_part_cylinder(lantern, Vector3(0, height * 0.5, 0), 0.09, height, pole_color)
	_part_box(lantern, Vector3(0, height - 0.18, 0), Vector3(0.28, 0.34, 0.28), glow_color, 1.9)
	_part_cylinder(lantern, Vector3(0, height + 0.08, 0), 0.26, 0.14, pole_color, 0.08, 6)


## 一座稻草人：立柱 + 横木 + 布衣 + 草头 + 草帽（共 5 个部件）。
func _build_scarecrow(pos: Vector2, yaw: float) -> void:
	var scarecrow := _piece("Wheat_Scarecrow", Vector3(pos.x, 0.0, pos.y))
	scarecrow.rotation.y = yaw
	_part_cylinder(scarecrow, Vector3(0, 1.2, 0), 0.09, 2.4, Color("6b5334"))
	_part_box(scarecrow, Vector3(0, 1.78, 0), Vector3(1.5, 0.10, 0.10), Color("6b5334"))
	_part_box(scarecrow, Vector3(0, 1.50, 0), Vector3(0.62, 0.85, 0.30), Color("b59a63"))
	_part_sphere(scarecrow, Vector3(0, 2.06, 0), 0.26, Color("d9c79a"), 0.30, -1.0, 8, 4)
	_part_cylinder(scarecrow, Vector3(0, 2.26, 0), 0.42, 0.10, Color("6a5a3a"), 0.12, 8)


# ============================================================================
# v40.1 几何修复：接地 / 互穿推离 / 压路推离（通用，和具体区域无关）
# ============================================================================

## 一个区域的道具全部建完后跑一次：接地 → 树间距 → 互穿推离 → 压路推离 → 再消重叠。
func _polish_region(region: Dictionary) -> void:
	var landmark: Vector2 = region["landmark"]
	var props := _collect_nearby_props(landmark)
	_fit_props(props)
	_separate_trees(props)
	# 多轮收敛：互穿 → 树距 → 压路；道路推离放最后（路面是硬约束），
	# 下一轮的互穿修复会把「被路推挤到一起」的道具再分开。
	for _cycle in 5:
		_resolve_overlaps(props, OVERLAP_TARGET, 4)
		_separate_trees(props)
		_push_props_off_road(props)
		if _region_geometry_ok(props):
			break
	_push_props_off_road(props)
	_accumulate_stats(props)


## 区域几何是否已达标（用于让收敛循环提前结束）：路面 ≥2.1m、非树互穿 ≤0.8m²。
func _region_geometry_ok(props: Array[Dictionary]) -> bool:
	for i in props.size():
		var a: Dictionary = props[i]
		if not a["anchor"] and WorldLayout.road_distance((a["rect"] as Rect2).get_center()) < 2.1:
			return false
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if a["tree"] and b["tree"]:
				continue
			var overlap := (a["rect"] as Rect2).intersection(b["rect"] as Rect2)
			if overlap.has_area() and overlap.get_area() > 0.8:
				return false
	return true


## 收集「本区域 + 附近锚点（石碑）」的道具记录。锚点不会被推离，只让别的道具让开。
func _collect_nearby_props(landmark: Vector2) -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	for child in get_children():
		if not (child is Node3D):
			continue
		var node := child as Node3D
		if node is OmniLight3D:
			continue
		var box := _world_aabb(node)
		if box.size == Vector3.ZERO:
			continue
		var center := Vector2(box.get_center().x, box.get_center().z)
		if center.distance_to(landmark) > 30.0:
			continue
		props.append({
			"node": node,
			"rect": Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z)),
			"tree": node.has_meta(&"tree"),
			"anchor": node.has_meta(&"anchor"),
		})
	return props


## 统一接地：把每个道具世界 AABB 的 min_y 贴到目标高度。
## 旋转后的道具（歪旗 / 斜梯 / 倒木 / 船）同样有效；fit_min_y 元数据可覆盖默认值。
func _fit_props(props: Array[Dictionary]) -> void:
	for entry in props:
		var node: Node3D = entry["node"]
		var target := float(node.get_meta(&"fit_min_y", FIT_MIN_Y))
		_ground_fit(node, target)


## 按世界 AABB 把节点的最低点平移到 target_min_y。
func _ground_fit(node: Node3D, target_min_y: float = FIT_MIN_Y) -> float:
	var box := _world_aabb(node)
	if box.size == Vector3.ZERO:
		return 0.0
	var delta := target_min_y - box.position.y
	if absf(delta) < 0.0001:
		return 0.0
	node.position.y += delta   # 所有道具都直接挂在 ThemedRegions（世界原点）下
	return delta


## 合并节点子树里所有 MeshInstance3D 的世界 AABB（Label3D / 灯光不计）。
func _world_aabb(node: Node) -> AABB:
	var box := AABB()
	var has_geometry := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var visual := current as MeshInstance3D
			if visual.mesh != null:
				var world_box: AABB = visual.global_transform * visual.mesh.get_aabb()
				if has_geometry:
					box = box.merge(world_box)
				else:
					box = world_box
					has_geometry = true
		for child in current.get_children():
			stack.append(child)
	return box if has_geometry else AABB()


## 树与树：主干中心距 ≥ TREE_MIN_GAP（树冠允许轻微交叠）。
func _separate_trees(props: Array[Dictionary]) -> void:
	for i in props.size():
		var a: Dictionary = props[i]
		if not a["tree"]:
			continue
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if not b["tree"]:
				continue
			var ca := (a["rect"] as Rect2).get_center()
			var cb := (b["rect"] as Rect2).get_center()
			var distance := ca.distance_to(cb)
			if distance >= TREE_MIN_GAP:
				continue
			var direction := cb - ca
			if direction.length() < 0.001:
				direction = Vector2(1.0, 0.0)
			direction = direction.normalized()
			var push := (TREE_MIN_GAP - distance) * 0.5 + 0.02
			if not a["anchor"]:
				_move_prop(a, -direction * push)
			if not b["anchor"]:
				_move_prop(b, direction * push)


## 道具两两：XZ 重叠面积 > max_area 时推开（锚点不动；树×非树只推树）。
## 推离方向会挑「让被推道具离道路更远」的一侧，避免互穿修复把道具推回小径。
func _resolve_overlaps(props: Array[Dictionary], max_area: float, rounds: int) -> void:
	for _round in rounds:
		var moved := false
		for i in props.size():
			var a: Dictionary = props[i]
			for j in range(i + 1, props.size()):
				var b: Dictionary = props[j]
				if a["tree"] and b["tree"]:
					continue   # 树×树交给 _separate_trees（树冠允许轻微交叠）
				if a["anchor"] and b["anchor"]:
					continue
				var ra: Rect2 = a["rect"]
				var rb: Rect2 = b["rect"]
				if not ra.intersects(rb):
					continue
				var overlap := ra.intersection(rb)
				if not overlap.has_area() or overlap.get_area() <= max_area:
					continue
				# 树 × 非树：只把树推开，道具（含石碑锚点）原位不动。
				if a["tree"] or b["tree"]:
					var tree_entry: Dictionary = a if a["tree"] else b
					var other_center := (b["rect"] as Rect2).get_center() if a["tree"] else (a["rect"] as Rect2).get_center()
					var tree_center := (tree_entry["rect"] as Rect2).get_center()
					var away := tree_center - other_center
					if away.length() < 0.001:
						away = Vector2(1.0, 0.0)
					away = away.normalized()
					_move_prop(tree_entry, away * (minf(overlap.size.x, overlap.size.y) + 0.15))
					moved = true
					continue
				var ca := ra.get_center()
				var cb := rb.get_center()
				# 两个候选分离轴（X / Z）：方向都保证 a、b 彼此远离。
				# 只在这两个合法方向里挑「让被推道具离道路更远」的那个——
				# 绝不能简单翻符号（翻符号会变成把道具推向对方，v40.1 实测过）。
				var candidates: Array[Vector2] = []
				if not is_equal_approx(ca.x, cb.x):
					var mag_x := overlap.size.x * 0.5 + 0.02
					candidates.append(Vector2(1.0 if cb.x > ca.x else -1.0, 0.0) * mag_x)
				if not is_equal_approx(ca.y, cb.y):
					var mag_z := overlap.size.y * 0.5 + 0.02
					candidates.append(Vector2(0.0, 1.0 if cb.y > ca.y else -1.0) * mag_z)
				if candidates.is_empty():
					candidates.append(Vector2(0.6, 0.0))
				var chosen: Vector2 = candidates[0]
				var chosen_score := -INF
				for push in candidates:
					var score: float
					if a["anchor"]:
						score = WorldLayout.road_distance(cb + push * 2.0)
					elif b["anchor"]:
						score = WorldLayout.road_distance(ca - push * 2.0)
					else:
						score = minf(WorldLayout.road_distance(ca - push), WorldLayout.road_distance(cb + push))
					if score > chosen_score:
						chosen_score = score
						chosen = push
				if a["anchor"]:
					_move_prop(b, chosen * 2.0)
				elif b["anchor"]:
					_move_prop(a, -chosen * 2.0)
				else:
					_move_prop(a, -chosen)
					_move_prop(b, chosen)
				moved = true
		if not moved:
			return


## 压路推离：中心 road_distance < ROAD_SAFE 的道具，沿「最能远离道路」的方向挪开。
func _push_props_off_road(props: Array[Dictionary]) -> void:
	for entry in props:
		if entry["anchor"]:
			continue
		for _attempt in 10:
			var rect: Rect2 = entry["rect"]
			var center := rect.get_center()
			if WorldLayout.road_distance(center) >= ROAD_SAFE:
				break
			var best_dir := Vector2.ZERO
			var best_distance := WorldLayout.road_distance(center)
			for i in 16:
				var angle := float(i) * TAU / 16.0
				var direction := Vector2(cos(angle), sin(angle))
				var candidate := center + direction * 0.6
				var distance := WorldLayout.road_distance(candidate)
				if distance > best_distance + 0.001:
					best_distance = distance
					best_dir = direction
			if best_dir == Vector2.ZERO:
				break
			_move_prop(entry, best_dir * 0.6)


## 移动道具（同时更新记录里的 XZ AABB）。
func _move_prop(entry: Dictionary, delta: Vector2) -> void:
	var node: Node3D = entry["node"]
	node.position.x += delta.x
	node.position.z += delta.y
	var rect: Rect2 = entry["rect"]
	entry["rect"] = Rect2(rect.position + delta, rect.size)


## 累计几何体检最差值（用于最后一行汇总，不做任何修改）。
## 统计口径与 tests/ScenePolishTest 一致：树类之间允许树冠交叠，贴地贴片 / 木栈道
## 不参与互穿与压路判定，这样日志里的数字就是验收时真正会卡的数字。
func _accumulate_stats(props: Array[Dictionary]) -> void:
	for i in props.size():
		var a: Dictionary = props[i]
		var box := _world_aabb(a["node"])
		if box.size != Vector3.ZERO:
			_worst_min_y = minf(_worst_min_y, box.position.y)
		var center := (a["rect"] as Rect2).get_center()
		if not _name_has_any(String(a["node"].name), ROAD_EXEMPT_KEYWORDS):
			_worst_road = minf(_worst_road, WorldLayout.road_distance(center))
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if _name_has_any(String(a["node"].name), FLAT_LIKE_KEYWORDS) 				or _name_has_any(String(b["node"].name), FLAT_LIKE_KEYWORDS):
				continue
			if _name_has_any(String(a["node"].name), TREE_LIKE_KEYWORDS) \
				and _name_has_any(String(b["node"].name), TREE_LIKE_KEYWORDS):
				continue
			var overlap := (a["rect"] as Rect2).intersection(b["rect"] as Rect2)
			if overlap.has_area():
				_worst_overlap = maxf(_worst_overlap, overlap.get_area())


## 名字里是否包含任一关键词（几何体检分类用）。
func _name_has_any(piece_name: String, keywords: Array) -> bool:
	for keyword in keywords:
		if piece_name.contains(String(keyword)):
			return true
	return false


# ============================================================================
# 节点 / 网格 / 材质 基础工具
# ============================================================================

func _unique_name(base: String) -> String:
	var count: int = int(_name_counts.get(base, 0)) + 1
	_name_counts[base] = count
	return base if count == 1 else "%s_%02d" % [base, count]


## 给节点打元数据标记（anchor / tree / fit_min_y），并返回节点方便链式书写。
func _mark(node: Node3D, key: StringName, value: Variant) -> Node3D:
	node.set_meta(key, value)
	return node


## 空容器：一个「道具组」（多部件组合件），直接挂在 ThemedRegions 下。
func _piece(piece_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = _unique_name(piece_name)
	node.position = pos
	add_child(node)
	return node


## 单片网格道具（单部件），同样直接挂在 ThemedRegions 下。
func _mesh_piece(piece_name: String, mesh: Mesh, pos: Vector3, material: Material,
		yaw: float = 0.0, tilt: Vector3 = Vector3.ZERO, cast_shadow: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = _unique_name(piece_name)
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.rotation = Vector3(tilt.x, yaw + tilt.y, tilt.z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


## 区域小径的单位方向（从探索小径起点指向区域地标）。
func _region_front(region: Dictionary) -> Vector2:
	var all_regions := WorldRegions.all()
	var index := 0
	for i in all_regions.size():
		if all_regions[i]["id"] == region["id"]:
			index = i
			break
	var trail_segments := WorldLayout.TRAIL_SEGMENTS
	var trail_index := maxi(0, trail_segments.size() - WorldRegions.count()) + index
	if trail_index < trail_segments.size():
		var segment: Array = trail_segments[trail_index]
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		if a.distance_squared_to(b) > 0.0001:
			return (b - a).normalized()
	return Vector2(1.0, 0.0)


## 「洞口局部系」：along = 沿洞口正面推出去的距离（米），side = 沿侧面（perp）的偏移。
## 用于矿洞入口这类有正面朝向的建筑——直接写世界坐标容易把道具插进建筑占地里。
func _mouth_point(center: Vector2, front: Vector2, perp: Vector2, along: float, side: float) -> Vector2:
	return center - front * along + perp * side


## 让节点的本地 +Z 轴对准 dir（XZ 平面）——KayKit 建筑与 Label3D 的正面都是 +Z。
func _yaw_align_z(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder_mesh(bottom_radius: float, height: float, top_radius: float = -1.0, segments: int = 8) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = maxf(bottom_radius, 0.01)
	mesh.top_radius = mesh.bottom_radius if top_radius < 0.0 else maxf(top_radius, 0.01)
	mesh.height = maxf(height, 0.01)
	mesh.radial_segments = maxi(segments, 3)
	return mesh


func _sphere_mesh(radius: float, height: float = -1.0, segments: int = 8, rings: int = 5) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(radius, 0.01)
	mesh.height = mesh.radius * 2.0 if height < 0.0 else maxf(height, 0.01)
	mesh.radial_segments = maxi(segments, 3)
	mesh.rings = maxi(rings, 2)
	return mesh


func _disc_mesh(radius: float, thickness: float = 0.05, segments: int = 16) -> CylinderMesh:
	return _cylinder_mesh(radius, thickness, radius, segments)


## 纯色装饰材质（走消散 shader，主角贴脸时不会糊住视线）。
func _solid(color: Color, roughness: float = 0.92) -> ShaderMaterial:
	var key := "%s_%.2f" % [color.to_html(), roughness]
	if _solid_materials.has(key):
		return _solid_materials[key] as ShaderMaterial
	var material := NatureAssets.dissolve_material(color, roughness, 1.15)
	_solid_materials[key] = material
	return material


## 自发光材质：冰晶 / 矿石 / 符文 / 余烬 / 鬼火这类「光点」小件不做消散（不挡视线）。
func _glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "%s_%.1f" % [color.to_html(), energy]
	if _glow_materials.has(key):
		return _glow_materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	_glow_materials[key] = material
	return material


## 霜区专用：浮冰材质（v45）。半透明冰蓝 + 微发光 + 边缘冷光（rim），避免纯白过曝成纸片；
## 顶点色参与反照率（顶面偏白 / 倒角亮蓝 / 侧壁深蓝），所以打开 vertex_color_use_as_albedo。
func _ice_material() -> StandardMaterial3D:
	if _ice_material_cached != null:
		return _ice_material_cached
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.60, 0.78, 0.93, 0.88)
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.16
	material.metallic = 0.0
	material.rim_enabled = true
	material.rim = 0.55
	material.rim_tint = 0.80
	material.emission_enabled = true
	material.emission = Color(0.28, 0.54, 0.78)
	material.emission_energy_multiplier = 0.15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ice_material_cached = material
	return material


## 组合件里的盒体。
func _part_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float = -1.0) -> MeshInstance3D:
	return _part(parent, _box_mesh(size), pos, _material_for(color, energy))


## 组合件里的圆柱 / 棱柱（bottom_radius > top_radius 即为尖晶体）。
func _part_cylinder(parent: Node3D, pos: Vector3, bottom_radius: float, height: float, color: Color,
		top_radius: float = -1.0, segments: int = 8, energy: float = -1.0) -> MeshInstance3D:
	return _part(parent, _cylinder_mesh(bottom_radius, height, top_radius, segments), pos, _material_for(color, energy))


## 组合件里的球体。
func _part_sphere(parent: Node3D, pos: Vector3, radius: float, color: Color, height: float = -1.0,
		energy: float = -1.0, segments: int = 8, rings: int = 5) -> MeshInstance3D:
	return _part(parent, _sphere_mesh(radius, height, segments, rings), pos, _material_for(color, energy))


## 组合件里的贴地圆片。
func _part_disc(parent: Node3D, pos: Vector3, radius: float, color: Color,
		thickness: float = 0.05, segments: int = 16) -> MeshInstance3D:
	return _part(parent, _disc_mesh(radius, thickness, segments), pos, _material_for(color, -1.0))


func _material_for(color: Color, energy: float) -> Material:
	return _solid(color) if energy < 0.0 else _glow(color, energy)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	parent.add_child(node)
	return node


## 区域灯：每区域只建 1 盏；flicker=true 的灯登记进 _flickers 由 _process 统一驱动。
func _add_light(pos: Vector2, height: float, color: Color, light_range: float, energy: float,
		flicker: bool, amp: float, speed: float, phase: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = _unique_name("RegionLight")
	light.light_color = color
	light.omni_range = light_range
	light.light_energy = energy
	light.shadow_enabled = false
	light.position = Vector3(pos.x, height, pos.y)
	add_child(light)
	_light_count += 1
	if flicker:
		_flickers.append({"light": light, "base": energy, "amp": amp, "speed": speed, "phase": phase})
	return light


## 中英文混排 label。font 用项目字体链（UIStyle.make_font），缺字回退系统字体。
func _label3d(parent: Node3D, text: String, pos: Vector3, yaw: float, color: Color, font_size: int) -> Label3D:
	var label := Label3D.new()
	if _font == null:
		_font = UIStyle.make_font()
	label.font = _font
	label.text = text
	label.font_size = font_size
	label.pixel_size = LABEL_PIXEL_SIZE
	# v40.1.1：描边宽度按字号比例（原固定 14 在 30~34px 字号下会吃掉字形，路标/石碑远看发黑）。
	label.outline_size = maxi(4, int(float(font_size) * 0.16))
	label.outline_modulate = Color(0.05, 0.045, 0.035, 1.0)
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.no_depth_test = false
	label.width = 900.0
	label.position = pos
	label.rotation.y = yaw
	parent.add_child(label)
	return label


# ============================================================================
# 模型加载（load() 优先、GLTFDocument 回退）与落点合法性
# ============================================================================

## 放置一个 KayKit 模型道具；模型缺失时返回 null（调用方跳过，不阻塞地标）。
func _model(dir: String, res_name: String, piece_name: String, pos: Vector2,
		model_scale: float, yaw: float, y_off: float = 0.0) -> Node3D:
	var node := _instantiate_model(dir, res_name)
	if node == null:
		return null
	node.name = _unique_name(piece_name)
	node.position = Vector3(pos.x, y_off, pos.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * model_scale
	_strip_collisions(node)
	add_child(node)
	return node


func _instantiate_model(dir: String, res_name: String) -> Node3D:
	var path := dir + res_name + ".gltf"
	var template: Node3D = null
	if _templates.has(path):
		template = _templates[path] as Node3D
	else:
		template = _load_model_scene(path)
		if template == null:
			push_warning("ThemedRegions: 区域道具模型缺失 %s" % path)
			return null
		_templates[path] = template
	if not is_instance_valid(template):
		return null
	return template.duplicate() as Node3D


func _load_model_scene(path: String) -> Node3D:
	# 优先走编辑器导入的 PackedScene（.gltf + .bin + png atlas 由导入器打包）。
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return (res as PackedScene).instantiate() as Node3D
	# 回退：运行时解析原始 glTF（外部 .bin / png 以 .gltf 所在目录为基址）。
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file(path, state)
	if err != OK:
		push_warning("ThemedRegions: 解析 glTF 失败 %s（err=%d）" % [path, err])
		return null
	return document.generate_scene(state)


## 纯视觉兜底：即使源模型误带碰撞体也一律摘除（不挡寻路 / 物理）。
func _strip_collisions(node: Node) -> void:
	for child in node.get_children():
		_strip_collisions(child)
		if child is CollisionShape3D or child is CollisionObject3D:
			node.remove_child(child)
			child.queue_free()


## 从 DecorationScatter 的 MultiMesh 实例里收集某个斑块的名字前缀、且在 radius 内的 XZ 位置。
## 用途：让本脚本的地表小贴片避开 terrain-scatter 铺的同类斑块（例如盐壳 vs salt）。
func _collect_scatter_points(name_keyword: String, center: Vector2, radius: float) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var scatter := _find_scatter_node()
	if scatter == null:
		return points
	for child in scatter.get_children():
		var multi := child as MultiMeshInstance3D
		if multi == null or multi.multimesh == null:
			continue
		if not String(multi.name).contains(name_keyword):
			continue
		var multimesh := multi.multimesh
		for index in multimesh.instance_count:
			var origin := multimesh.get_instance_transform(index).origin
			var point := Vector2(origin.x, origin.z)
			if point.distance_to(center) <= radius:
				points.append(point)
	return points


## 找 DecorationScatter：Main.tscn 里它挂在 WorldRoot/Decorations 下（不是 WorldScenery 的兄弟），
## 因此从当前场景根做一次递归查找；找不到就跳过避让（本脚本的盐壳只在 landmark 8m 内，
## 而 terrain-scatter 的 _valid_region 会避开 landmark 13m 外，本身已有 ≥5m 间距兜底）。
func _find_scatter_node() -> Node:
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	return _find_child_named(root, "DecorationScatter")


func _find_child_named(node: Node, target: String) -> Node:
	if String(node.name) == target:
		return node
	for child in node.get_children():
		var found := _find_child_named(child, target)
		if found != null:
			return found
	return null


## 盐壳选点：环形采样 + 与已有盐壳 ≥2.4m + 与 terrain-scatter salt 斑中心 ≥2m（含双方半径）。
func _pick_salt_point(center: Vector2, salt_radius: float, scatter_salt: Array[Vector2], placed: Array[Vector2]) -> Vector2:
	for _attempt in 14:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(2.4, 7.6)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		if not _decor_ok(point):
			continue
		var spaced := true
		for other in placed:
			if point.distance_to(other) < 2.4:
				spaced = false
				break
		if not spaced:
			continue
		for other in scatter_salt:
			# 散布盐斑半径约 0.5×scale（≤0.75m）：中心距 ≥ 2.0 + 0.75 + 自身半径
			if point.distance_to(other) < 2.0 + 0.75 + salt_radius:
				spaced = false
				break
		if not spaced:
			continue
		return point
	return Vector2.INF


## 围绕 center 取一个可用落点；带间距约束（避免随机道具叠放）。
## 十次采样都不可用则返回 Vector2.INF（调用方跳过）。
func _safe_ring_point(center: Vector2, r_min: float, r_max: float, min_gap: float = 1.4) -> Vector2:
	for _attempt in 10:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(r_min, r_max)
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		if not _decor_ok(point):
			continue
		var spaced := true
		for spot in _spots:
			if point.distance_to(spot) < min_gap:
				spaced = false
				break
		if not spaced:
			continue
		_spots.append(point)
		return point
	return Vector2.INF


## 装饰落点合法性：不越地图边界、不压主路 / 小径、不落水。
func _decor_ok(point: Vector2) -> bool:
	var limit := WorldLayout.MAP_HALF - 2.5
	if absf(point.x) > limit or absf(point.y) > limit:
		return false
	if WorldLayout.road_distance(point) < ROAD_CLEARANCE:
		return false
	if WorldLayout.water_distance(point) < WATER_CLEARANCE:
		return false
	return true
