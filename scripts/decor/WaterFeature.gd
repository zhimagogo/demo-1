class_name WaterFeature
extends Node3D
## ============================================================================
## 北境水系景观（v12 起，v43 需求③b 全面视觉迭代）：瀑布 → 水潭 → 河流 → 湖泊。
##
## 几何真相全部来自 WorldLayout（Lead 锁死，改河道只需改那里），本文件只负责
## 「把几何变成看得见、走得通、撞得到的东西」：
##   ① 水面网格：河道条带（沿 RIVER_PTS 采样 + 逐点半宽）、水潭椭圆盘、多股落水帘；
##      湖泊水面仍由 Main.tscn 的 Water 节点承担（region=1）；
##   ② 瀑布立面（v43 三股落水：主瀑 + 东西两条细流）+ 分层崖壁湿岩 + 北境崖体与物理碰撞；
##   ③ 寻路登记：河道 / 水潭 / 崖体写进 GridSystem.terrain_cells（永久阻挡），
##      并在河道中段留一处「浅滩涉水点 ford」、河口留一处「潭口浅滩」让单位能涉水；
##   ④ 河岸装饰（卵石 / 芦苇 / 浅滩踏石）、湖心小岛（纯视觉）与「落在水里的散布植被」清理；
##   ⑤ 落水点白沫环 / 扩散涟漪 / 水雾飞溅粒子，夜间与雨天亮度颜色由 _process 同步。
##
## 着色：水面材质 = water_ground.gdshader + WorldLayout.set_water_region()；
## 瀑布 = waterfall.gdshader；湿岩 = cliff_rock.gdshader；白沫 = waterfall_foam.gdshader。
## 水域相关材质经 WorldLayout.apply_shader_parameters()，与着色器读同一份 uniform。
##
## 节点位置：由 WorldScenery._ready() 在 NavSystem 之前创建，故 terrain_cells
## 在 NavSystem 建 A* 图之前就已写好（与湖泊同一套做法）。
## ============================================================================

# ---- 网格造型常量 ----
const RIVER_SUBDIV: int = 8               # 每段折线的采样数
const RIVER_EXTEND: float = 1.2           # 末端延伸：河口淡出用（湖面不再沿河道挖洞，v43）
const RIVER_EDGE_INSET: float = 0.86      # 内圈顶点相对半宽的比例（河岸倒角窄一点，别在水边留亮线）
const RIVER_EDGE_DROP: float = 0.09       # 外圈顶点下压量
const LAKE_MOUTH_Y: float = 0.07          # 河口水面高度（贴合湖面 0.06，避免台阶）
const FORD_WATER_Y: float = 0.15          # 浅滩处水面下压后的高度（可涉水的视觉）
const CURTAIN_ROWS: int = 40              # 瀑布立面纵向细分
const CURTAIN_COLS: int = 32              # 瀑布立面横向细分
# v45 多层落水：主帘前后各叠一层薄水膜（更窄 / 更淡 / 流速不同 → 视差与层次）
const FILM_ROWS: int = 24                 # 薄水膜纵向细分
const FILM_COLS: int = 18                 # 薄水膜横向细分
const CREST_ROWS: int = 5                 # 唇口翻卷过渡带纵向细分
const CREST_COLS: int = 26                # 唇口翻卷过渡带横向细分
const POOL_SEGMENTS: int = 48             # 水潭盘边数
const POOL_EDGE_SCALE: float = 1.035      # 水潭盘外圈略大于着色边缘（软边落在盘内）

# ---- 浅滩涉水点（唯一不登记阻挡的过河缺口，位于 RIVER_PTS[0]→[1] 中段）----
# v43：随河流东迁重算。RIVER_PTS[0] 仍在潭内（河从潭里流出来，见 WorldLayout 注释），
# 河带网格在潭岸处裁剪；功能性浅滩放在首段中点，两岸都是陆地。
const FORD_CENTER := Vector2(55.3, -58.65)
const FORD_HALF_LEN: float = 4.8          # 沿过河方向半长（两端各到对岸陆地）
const FORD_RADIUS: float = 2.7            # 过河走廊半宽
# ---- 河口浅滩：河与湖交汇处的湿地浅滩（清阻挡做落脚点，lake 格也被清成可涉水）----
const SHALLOW_CENTER := Vector2(52.6, -48.4)
const SHALLOW_RADIUS: float = 3.8

# 河滩顶点色（内 → 外）：贴着水面的湿泥 → 湿沙 → 干沙
const BAND_COLORS: Array[Color] = [
	Color(0.37, 0.34, 0.27), Color(0.49, 0.46, 0.37), Color(0.48, 0.49, 0.32, 0.0),
]

# ---- 北境崖体占地（矩形；石阶 + 岩块堆出 WATERFALL_TOP_Y 高差）----
# v43：随瀑布迁到 (58,-72)。崖体在唇口以北，东西两翼夹住落水帘，正面墙体后退 0.5m，
# 唇口由一道出挑岩檐（CLIFF_SHELF）承托 → 水面从檐下翻出，避免水帘「浮在墙前」。
const CLIFF_X0: float = 48.0
const CLIFF_X1: float = 66.0
const CLIFF_Z0: float = -84.0
const CLIFF_Z1: float = -70.8

# 崖体石阶：[x0, x1, z0, z1, y0, y1]；北境主体包住瀑顶唇口，东西两翼夹住落水帘
const CLIFF_STEPS: Array = [
	# 北境主体（瀑布后方）：后山 8.2m ＋ 瀑顶平台 8.2m（顶部水道就铺在这层）
	[50.0, 66.0, -84.0, -77.4, 0.0, 8.2],
	[52.0, 64.5, -77.4, -73.6, 0.0, 8.2],
	# 主瀑正壁：退到唇口以北，唇口靠出挑岩檐（CLIFF_SHELF_CENTER）承托
	[52.6, 63.6, -73.6, -72.5, 0.0, 7.85],
	# 东西两翼：低矮的岩肩夹住落水帘，破掉整面直墙
	[48.0, 53.2, -80.0, -71.0, 0.0, 5.4],
	[63.0, 68.0, -80.0, -71.0, 0.0, 6.0],
]
# 唇口岩檐（出挑到 lip 线，水面从檐下翻出）：[中心, 尺寸]
const CLIFF_SHELF_CENTER := Vector3(58.0, 8.02, -73.0)
const CLIFF_SHELF_SIZE := Vector3(9.6, 0.38, 2.15)
# 两侧细流的出水岩台：[中心, 尺寸]
const STRAND_LEDGES: Array = [
	[Vector3(54.85, 6.42, -71.95), Vector3(2.2, 0.30, 1.2)],
	[Vector3(61.0, 7.0, -71.9), Vector3(2.0, 0.30, 1.1)],
]
# 瀑顶水道（岩槽里的山溪）与唇口翻水的落点
# v45：抬高到崖顶岩帽之上（岩帽视觉顶点 ≈ TOP_Y+0.08），否则水面会被岩体顶盖吃掉。
const TOP_STREAM_CENTER := Vector3(58.0, WorldLayout.WATERFALL_TOP_Y + 0.10, -75.8)
const TOP_STREAM_SIZE := Vector2(6.6, 3.3)
const LIP_SHEET_CENTER := Vector3(58.0, WorldLayout.WATERFALL_TOP_Y + 0.105, -73.1)
const LIP_SHEET_SIZE := Vector2(8.4, 2.2)
# 落水点 3D 白沫丘：[中心 xz 偏移, 半径, 高度]
const FOAM_MOUNDS: Array = [
	[Vector2(0.0, 0.0), 1.10, 0.075],
	[Vector2(-3.15, 0.0), 0.55, 0.040],
	[Vector2(3.05, 0.0), 0.50, 0.035],
]
# 水景粒子种类（v45）：决定发射盒 / 速度 / 重力 / 贴图 / 混合模式
const SPRAY_MIST: int = 0        # 贴地翻涌的柔软水雾（alpha 混合）
const SPRAY_WISP: int = 1        # 高处飘散的水汽（更淡、更慢）
const SPRAY_DROP: int = 2        # 细小飞溅水滴（抛物线落回）
const SPRAY_SPARK: int = 3       # 落水点白色水花（少量加法提亮）

var world_root: Node3D = null
var grid: GridSystem = null
var cliff_body: StaticBody3D = null
var river_mesh: MeshInstance3D = null
var pool_mesh: MeshInstance3D = null
var curtain_mesh: MeshInstance3D = null
var foam_mesh: MeshInstance3D = null
var island_node: Node3D = null
# 多股落水帘（[0] = 主瀑，测试断言 >= 3 股）
var curtain_meshes: Array[MeshInstance3D] = []
# 诊断（测试与交付回报读这两个计数）
var blocked_cells: int = 0
var cleared_scatter: int = 0
var scatter_readback: bool = false    # 本机是否支持 MultiMesh 实例回读（无头模式为 false）

var _rng := RandomNumberGenerator.new()
var _mat_river: ShaderMaterial
var _mat_pool: ShaderMaterial
var _mat_lake: ShaderMaterial
var _mat_rock_variants: Array[ShaderMaterial] = []
var _mat_bank: StandardMaterial3D
var _mat_curtain: ShaderMaterial           # 主帘（render_priority 0）
var _mat_curtain_back: ShaderMaterial      # 后层薄水膜（-2，先画）
var _mat_curtain_front: ShaderMaterial     # 前层薄水膜（+2，后画）
var _mat_curtain_crest: ShaderMaterial     # 唇口翻卷过渡带（+3）
var _mat_foam: ShaderMaterial              # 落水白沫平面
var _mat_foam_mound: ShaderMaterial        # 3D 白沫丘（同一 shader，gain / 排序不同）
var _mat_feed_stream: ShaderMaterial       # 瀑顶水道
var _mat_feed_lip: ShaderMaterial          # 唇口翻水薄片
var _mat_island_grass: Material
var _mat_island_sand: ShaderMaterial   # 水下沙洲（v45：登记夜色，夜里不能发亮）
var _mat_island_rock: ShaderMaterial   # 岛体岩石（同上）
var _spray_materials: Array[StandardMaterial3D] = []
# 每帧同步夜色 / 雨强 / 太阳方向的材质（只为水面与落水帘，不含岩体：岩体由 shader 自带夜色）
var _time_materials: Array[ShaderMaterial] = []
var _sun_dir := Vector3(0.35, 0.86, 0.38)
var _sun_color := Color(1.0, 0.95, 0.84)
var _sun_energy := 1.0


func _ready() -> void:
	add_to_group("water_feature")
	_rng.seed = 20260930
	if world_root == null:
		world_root = get_parent()
	if world_root != null:
		grid = world_root.get_node_or_null("GridSystem") as GridSystem
	_mat_river = _make_water_material(2)      # 仅河
	_mat_pool = _make_water_material(3)       # 仅潭
	# v45：水体调色统一收口到 WaterPalette（湖 / 河 / 潭的颜色只在那里改）。
	# 落水帘 = 主帘 + 前后两层薄水膜 + 唇口翻卷；分层靠 render_priority 强制绘制顺序。
	_mat_curtain = _make_curtain_material(0)
	_mat_curtain_back = _make_curtain_material(-2)
	_mat_curtain_front = _make_curtain_material(2)
	_mat_curtain_crest = _make_curtain_material(3)
	_mat_bank = StandardMaterial3D.new()      # 河岸卵石滩：压掉水与草地之间的硬直线
	_mat_bank.albedo_color = Color(0.50, 0.47, 0.40)
	_mat_bank.roughness = 1.0
	_mat_bank.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_bank.vertex_color_use_as_albedo = true   # 顶点色：靠水压暗成湿泥 → 向外过渡到干沙
	# 岛顶草地：不用 StandardMaterial3D（它不吃 night_dim，夜里会被月光打成惨白的「冰面」），
	# 改用与崖体同一套 cliff_rock shader（自带夜色 / 雨天压暗），只是颜色换成草绿。
	_mat_island_grass = _make_rock_material(0.0, Color(0.30, 0.45, 0.22), Color(0.30, 0.45, 0.22), 0.18)

	# 湖泊水面材质（Main.tscn 的 Water 节点）：这里只是拿引用，供日光高光 / 夜色同步。
	var lake := world_root.get_node_or_null("Water") as MeshInstance3D if world_root != null else null
	if lake != null and lake.material_override is ShaderMaterial:
		_mat_lake = lake.material_override as ShaderMaterial
		# 湖面材质定义在 Main.tscn 里（region=1）；这里只覆盖颜色，不改节点 / 材质归属。
	WaterPalette.apply_all(_mat_lake, _mat_river, _mat_pool)
	_build_river()
	_build_pool()
	_build_waterfall()
	_build_cliff()
	_build_spray()
	_build_bank_strip()
	_build_banks()
	_build_lake_island()
	_register_time_materials()
	_register_terrain()
	_clear_scatter_in_water()
	# DecorationScatter 的区域植被是 call_deferred 创建的（晚于本节点 _ready）——再排一次清理，
	# 否则北境霜区的针叶林会直接长在新水潭 / 瀑布落水区里（v43 首版截图实锤）。
	_clear_scatter_in_water.call_deferred()


func _process(_delta: float) -> void:
	# 自建材质不在 DayNightCycle / WeatherSystem 的既有引用里，这里按同口径同步夜色与雨强；
	# v43 再补一份太阳方向 / 颜色（水面镜面高光与天空反射靠它，夜间自然变成月光）。
	var night := 0.0
	var daylight := 0.0
	var sun := world_root.get_node_or_null("Sun") as DirectionalLight3D if world_root != null else null
	var dnc := world_root.get_node_or_null("DayNightCycle") if world_root != null else null
	if dnc != null and dnc.has_method("daylight_factor"):
		daylight = dnc.call("daylight_factor")
		night = 1.0 - clampf(daylight * 1.4, 0.0, 1.0)
	if sun != null:
		# DirectionalLight3D 沿本地 -Z 照射，因此 +Z 指向光源（太阳 / 月亮方向）。
		_sun_dir = sun.global_transform.basis.z.normalized()
		_sun_color = sun.light_color
		_sun_energy = clampf(sun.light_energy, 0.0, 4.0)
	var rain := 0.0
	var weather := world_root.get_node_or_null("WeatherSystem") if world_root != null else null
	if weather != null and weather.has_method("rain_strength"):
		rain = weather.call("rain_strength")
	for mat in _time_materials + _mat_rock_variants:
		if mat == null:
			continue
		mat.set_shader_parameter("night_dim", night)
		mat.set_shader_parameter("rain_amount", rain)
	for mat in _time_materials:
		if mat == null:
			continue
		mat.set_shader_parameter("sun_dir", _sun_dir)
		mat.set_shader_parameter("sun_color", _sun_color)
		mat.set_shader_parameter("sun_strength", 0.55 + _sun_energy * 0.45)

	for mat in _spray_materials:
		# v45：水雾走 alpha 混合，夜里不能压得太暗（会变成一团灰烟）——只往冷蓝偏。
		mat.albedo_color = Color(0.86, 0.94, 0.98).lerp(Color(0.48, 0.62, 0.80), night)

	# v45：湖心岛夜里要读成「暗色剪影 + 一点冷边」，不能被月光打成浅灰蓝盘。
	# cliff_rock 自带的 night mix 只乘 0.5~0.7，水平草面在强月光下仍然偏亮，
	# 因此岛顶草 / 岛体岩 / 水下沙洲再各自把底色向冷暗蓝收敛一档（只动岛专用材质）。
	var island_night := Color(0.005, 0.010, 0.018)
	var grass := _mat_island_grass as ShaderMaterial
	if grass != null:
		grass.set_shader_parameter("rock_color", Color(0.30, 0.45, 0.22).lerp(island_night, night))
		grass.set_shader_parameter("rock_moss", Color(0.30, 0.45, 0.22).lerp(island_night, night))
	if _mat_island_rock != null:
		_mat_island_rock.set_shader_parameter("rock_color", Color(0.46, 0.44, 0.39).lerp(island_night, night))
		_mat_island_rock.set_shader_parameter("rock_moss", Color(0.30, 0.44, 0.22).lerp(island_night, night))
	if _mat_island_sand != null:
		_mat_island_sand.set_shader_parameter("rock_color", Color(0.46, 0.42, 0.31).lerp(island_night, night))
		_mat_island_sand.set_shader_parameter("rock_moss", Color(0.40, 0.44, 0.26).lerp(island_night, night))


# ---- 材质 ----

func _make_water_material(region: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water_ground.gdshader") as Shader
	WorldLayout.apply_shader_parameters(mat)
	WorldLayout.set_water_region(mat, region)
	return mat


func _make_rock_material(phase: float, color: Color = Color(0.45, 0.42, 0.37),
		moss: Color = Color(0.30, 0.38, 0.24), wet: float = 0.42) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/waterfall.gdshader" if phase > 1.5 else "res://assets/shaders/cliff_rock.gdshader") as Shader
	WorldLayout.apply_shader_parameters(mat)
	mat.set_shader_parameter("ws_phase", phase)
	mat.set_shader_parameter("rock_color", color)
	mat.set_shader_parameter("rock_moss", moss)
	mat.set_shader_parameter("rock_wet", wet)
	return mat


## 落水帘材质（v45）：全部走 waterfall.gdshader，靠 render_priority 强制「后层 → 主帘 → 前层 → 卷边」
## 的绘制顺序；ws_phase=2 是水系回归（WaterFeatureTest）沿用的立面材质标记。
func _make_curtain_material(priority: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/waterfall.gdshader") as Shader
	WorldLayout.apply_shader_parameters(mat)
	mat.set_shader_parameter("ws_phase", 2.0)
	mat.render_priority = priority
	return mat


## 瀑顶溢流材质（v45）：waterfall_feed.gdshader。stream / lip 两处用法不同 → 各自一份材质，
## 前缘白沫 / 岸边白沫 / 水道宽度按用途给值。
func _make_feed_material(lip_foam: float, edge_foam: float, half_width: float,
		flow: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/waterfall_feed.gdshader") as Shader
	WorldLayout.apply_shader_parameters(mat)
	mat.set_shader_parameter("feed_flow", flow)
	mat.set_shader_parameter("feed_lip_foam", lip_foam)
	mat.set_shader_parameter("feed_edge_foam", edge_foam)
	mat.set_shader_parameter("feed_lip_z", WorldLayout.WATERFALL_LIP.y)
	mat.set_shader_parameter("feed_half_width", half_width)
	mat.set_shader_parameter("feed_center_x", WorldLayout.WATERFALL_LIP.x)
	return mat


## 每帧同步夜色 / 雨强 / 太阳方向的材质清单（所有自建水系材质都在这里登记一次）。
func _register_time_materials() -> void:
	_time_materials.clear()
	for mat in [_mat_river, _mat_pool, _mat_curtain, _mat_curtain_back, _mat_curtain_front,
			_mat_curtain_crest, _mat_foam, _mat_foam_mound, _mat_feed_stream, _mat_feed_lip,
			_mat_island_grass, _mat_island_sand, _mat_island_rock, _mat_lake]:
		if mat != null:
			_time_materials.append(mat)


# ---- ① 河道水面（沿折线的带状网格）----

func _build_river() -> void:
	var samples := river_samples()
	if samples.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev: Array[Vector3] = []
	for i in samples.size():
		var s: Dictionary = samples[i]
		var p: Vector2 = s["p"]
		var dir: Vector2 = s["dir"]
		var half: float = s["half"]
		var nrm := Vector2(-dir.y, dir.x)
		var y := lerpf(WorldLayout.WATER_HIGH_Y - 0.012, river_surface_y(p),
			smoothstep(0.88, 1.16, WorldLayout.pool_distance(p)))
		var inner := half * RIVER_EDGE_INSET
		var cur: Array[Vector3] = [
			Vector3(p.x + nrm.x * half, y - RIVER_EDGE_DROP, p.y + nrm.y * half),
			Vector3(p.x + nrm.x * inner, y, p.y + nrm.y * inner),
			Vector3(p.x - nrm.x * inner, y, p.y - nrm.y * inner),
			Vector3(p.x - nrm.x * half, y - RIVER_EDGE_DROP, p.y - nrm.y * half),
		]
		if i > 0:
			for k in 3:
				_add_flat_quad(st, prev[k], prev[k + 1], cur[k + 1], cur[k])
		prev = cur
	river_mesh = _add_mesh("RiverWater", st.commit(), _mat_river, false)
	river_mesh.add_to_group("water_feature")


## 河道采样：折线细分 → 末端延伸 → 起点裁到水潭岸线外 → 中心差分求方向。
## 返回 [{p:Vector2, half:float, dir:Vector2}]。
func river_samples() -> Array:
	var pts: Array[Vector2] = []
	var halves: Array[float] = []
	var n := WorldLayout.RIVER_PTS.size()
	for i in n - 1:
		for k in RIVER_SUBDIV:
			if i > 0 and k == 0:
				continue
			var t := float(k) / float(RIVER_SUBDIV)
			pts.append(WorldLayout.RIVER_PTS[i].lerp(WorldLayout.RIVER_PTS[i + 1], t))
			halves.append(lerpf(WorldLayout.RIVER_HALF[i], WorldLayout.RIVER_HALF[i + 1], t))
	pts.append(WorldLayout.RIVER_PTS[n - 1])
	halves.append(WorldLayout.RIVER_HALF[n - 1])
	# 末段延伸：着色把「折线端点半径内」的湖面剔除掉，河道网格必须盖住那块区域
	var tail := (WorldLayout.RIVER_PTS[n - 1] - WorldLayout.RIVER_PTS[n - 2]).normalized()
	for k in 2:
		pts.append(WorldLayout.RIVER_PTS[n - 1] + tail * RIVER_EXTEND * (0.5 + 0.5 * float(k)))
		halves.append(WorldLayout.RIVER_HALF[n - 1] * (1.0 - 0.07 * float(k)))
	# 起点插值到潭岸的淡出带，不直接丢掉整段采样（否则潭口会露出一条草地）。
	var start := 0
	for i in pts.size():
		if WorldLayout.pool_distance(pts[i]) > 0.97:
			start = i
			break
	if start > 0:
		var lo := 0.0
		var hi := 1.0
		for _k in 16:
			var mid := (lo + hi) * 0.5
			if WorldLayout.pool_distance(pts[start - 1].lerp(pts[start], mid)) < 0.97:
				lo = mid
			else:
				hi = mid
		pts[start] = pts[start - 1].lerp(pts[start], hi)
		halves[start] = lerpf(halves[start - 1], halves[start], hi)
	var out: Array = []
	for i in range(start, pts.size()):
		var a: Vector2 = pts[maxi(i - 1, start)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var dir := b - a
		if dir.length_squared() < 0.0001:
			dir = Vector2(0.0, 1.0)
		out.append({"p": pts[i], "half": halves[i], "dir": dir.normalized()})
	return out


## 河道水面高度：靠近湖口时贴合湖面（0.06 附近），浅滩处下压成可涉水的浅水。
func river_surface_y(p: Vector2) -> float:
	var shore := clampf(inverse_lerp(1.60, 1.00, WorldLayout.lake_distance(p)), 0.0, 1.0)
	var y := lerpf(WorldLayout.WATER_HIGH_Y, LAKE_MOUTH_Y, smoothstep(0.0, 1.0, shore))
	var ford := smoothstep(FORD_RADIUS + 2.4, FORD_RADIUS * 0.3, p.distance_to(FORD_CENTER))
	return lerpf(y, FORD_WATER_Y, ford)


# ---- ② 水潭水面（椭圆盘）----

func _build_pool() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := POOL_SEGMENTS
	var y := WorldLayout.WATER_HIGH_Y
	var rings: Array[float] = [0.72, 1.0]
	var ring_y: Array[float] = [y - 0.015, y - 0.025]
	var center := Vector3(WorldLayout.POOL_CENTER.x, y, WorldLayout.POOL_CENTER.y)
	var rows: Array = []
	for r in rings.size():
		var row: Array[Vector3] = []
		for k in seg:
			var a := float(k) / float(seg) * TAU
			# 与 WorldLayout.pool_distance 同一条边缘曲线（含 4 次正弦起伏）
			var rad := rings[r] * POOL_EDGE_SCALE * (1.0 - 0.05 * sin(a * 4.0))
			row.append(Vector3(
				WorldLayout.POOL_CENTER.x + cos(a) * WorldLayout.POOL_RADII.x * rad,
				ring_y[r],
				WorldLayout.POOL_CENTER.y + sin(a) * WorldLayout.POOL_RADII.y * rad))
		rows.append(row)
	var row0: Array[Vector3] = rows[0]
	var row1: Array[Vector3] = rows[1]
	for k in seg:
		var k2 := (k + 1) % seg
		_add_flat_tri(st, center, row0[k], row0[k2])
		_add_flat_quad(st, row0[k2], row0[k], row1[k], row1[k2])
	pool_mesh = _add_mesh("PoolWater", st.commit(), _mat_pool, false)
	pool_mesh.add_to_group("water_feature")


# ---- ③ 瀑布立面（v43 多股落水 → v45 多层落水 / 唇口翻卷 / 不规则入水）----

func _build_waterfall() -> void:
	for i in WorldLayout.WATERFALL_STRANDS.size():
		var entry: Array = WorldLayout.WATERFALL_STRANDS[i]
		var dx: float = entry[0]
		var top_y: float = entry[1]
		var width: float = entry[2]
		var flow: float = entry[3]
		var bright: float = entry[4]
		# 主瀑顶端塞进唇口岩檐下（北 0.12m）；两侧细流从出水岩台前缘翻出。
		var top := Vector3(WorldLayout.WATERFALL_LIP.x + dx,
			top_y, WorldLayout.WATERFALL_LIP.y - 0.12 if i == 0 else WorldLayout.WATERFALL_LIP.y + 0.55)
		var bottom := Vector3(WorldLayout.WATERFALL_BASE.x + dx, WorldLayout.WATER_HIGH_Y + 0.015,
			WorldLayout.WATERFALL_BASE.y)
		# 立面法线（朝上 / 朝南）：多层水膜沿它前后错开，避免读成「一张平铺的纸」
		var slope_dir := (bottom - top).normalized()
		var nrm3 := Vector3.RIGHT.cross(slope_dir).normalized()
		if nrm3.y < 0.0:
			nrm3 = -nrm3

		var mesh := _build_curtain_mesh(top, bottom, width, i, bright, 1.0, 1.0, 1.0,
			CURTAIN_ROWS, CURTAIN_COLS)
		var node_name := "WaterfallCurtain" if i == 0 else "WaterfallCurtain_%s" % ("W" if dx < 0.0 else "E")
		var mi := _add_mesh(node_name, mesh, _mat_curtain, false)
		mi.set_meta("strand_flow", flow)
		mi.add_to_group("water_feature")
		curtain_meshes.append(mi)
		if i == 0:
			curtain_mesh = mi

		# 后层薄水膜：更窄、更暗、更慢（透过主帘看 = 一层挂在后面的水膜）
		var back_off := -nrm3 * 0.26 + Vector3(-0.10, 0.0, 0.0)
		var back_mesh := _build_curtain_mesh(top + back_off, bottom + back_off,
			width * (0.86 if i == 0 else 0.78), i + 7, bright * 0.94, 0.72, 0.46, 0.72,
			FILM_ROWS, FILM_COLS)
		var back := _add_mesh("WaterfallFilmBack" if i == 0 else "WaterfallFilmBack_%d" % i,
			back_mesh, _mat_curtain_back, false)
		back.add_to_group("water_feature")

		if i == 0:
			# 前层薄水膜：更窄、更淡、跑得更快（视差），只铺主瀑下半段，避免从唇口上沿露出去
			var front_off := nrm3 * 0.16 + Vector3(0.10, 0.0, 0.0)
			var front_mesh := _build_curtain_mesh(top + front_off - Vector3(0.0, 0.30, 0.0),
				bottom + front_off, width * 0.72, i + 11, bright, 1.55, 0.30, 1.04,
				FILM_ROWS, FILM_COLS)
			var front := _add_mesh("WaterfallFilmFront", front_mesh, _mat_curtain_front, false)
			front.add_to_group("water_feature")
			# 唇口翻卷：从岩檐上的水面卷下来接到帘顶（破掉「一块悬空亮板」的直切线）
			var crest_mesh := _build_crest_mesh(top, width, bright)
			var crest := _add_mesh("WaterfallCrest", crest_mesh, _mat_curtain_crest, false)
			crest.add_to_group("water_feature")


## 单股落水帘：v 向上→下（y 线性），水平沿唇口→落水点以 pow(v,1.65) 加速外抛；
## v45：底缘按列长成不规则水舌并下探入水（不再是一条水平硬切线）。
## 顶点色四通道见 waterfall.gdshader（r 亮度 / g 流速 / b 不透明度 / a 明暗）。
func _build_curtain_mesh(top: Vector3, bottom: Vector3, width: float, strand: int, bright: float,
		flow: float, opacity: float, shade: float, rows: int, cols: int) -> ArrayMesh:
	var dir := Vector2(bottom.x - top.x, bottom.z - top.z)
	var axis := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.0, 1.0)
	var tint := Color(bright, flow, opacity, shade)
	var half_w := width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid_rows: Array = []
	for r in rows + 1:
		var v := float(r) / float(rows)
		var progress := pow(v, 1.65)
		# 中心线：唇口 → 落水点，越往下越向外抛（底部急流扇开）
		var center := Vector2(top.x, top.z).lerp(Vector2(bottom.x, bottom.z), progress)
		# 深度方向低频摆动（曲面落水帘），两端为 0 → 唇口与落水点位置严格不变
		center += axis * (sin(v * 9.0 + float(strand) * 1.7) * 0.10 * sin(PI * v))
		# 横向宽度：溢流口紧凑、底部扇开；加一点逐行的宽窄起伏
		var w := half_w * lerpf(0.72, 1.0, v) * (1.0 + 0.02 * sin(v * 17.0 + float(strand) * 2.1))
		var y := lerpf(top.y, bottom.y, v) + sin(v * 13.0 + float(strand)) * 0.03 * sin(PI * v)
		# 底缘水舌：最后 16% 逐列下探（部分探到水下），把水平切线打碎
		var tongue_mix := smoothstep(0.84, 1.0, v)
		var line: Array[Vector3] = []
		for c in cols + 1:
			var lat := float(c) / float(cols) * 2.0 - 1.0
			var p := Vector3(center.x, y, center.y) + Vector3(lat * w, 0.0, 0.0)
			# 横向的薄厚起伏：让帘面不是一块平板（只动 y，毫米级）
			p.y += sin(lat * 5.0 + v * 4.0 + float(strand)) * 0.025
			var tongue := 0.5 + 0.5 * sin(lat * 4.3 + float(strand) * 2.7 + v * 2.0)
			p.y -= tongue_mix * (0.06 + tongue * 0.24)
			p.z -= tongue_mix * sin(lat * 6.1 + float(strand)) * 0.16
			line.append(p)
		grid_rows.append(line)
	for r in rows:
		var a: Array[Vector3] = grid_rows[r]
		var b: Array[Vector3] = grid_rows[r + 1]
		for c in cols:
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			var nrm := (a[c + 1] - a[c]).cross(b[c] - a[c]).normalized()
			_add_water_tri(st, nrm, a[c], Vector2(u0, v0), a[c + 1], Vector2(u1, v0),
				b[c + 1], Vector2(u1, v1), tint)
			_add_water_tri(st, nrm, a[c], Vector2(u0, v0), b[c + 1], Vector2(u1, v1),
				b[c], Vector2(u0, v1), tint)
	return st.commit() as ArrayMesh


## 唇口翻卷过渡带（v45）：从岩檐上的水面（略高于水线）卷下来接到主帘顶端，
## 逐行渐变 + 略微收窄 → 读作「水从唇口翻出去」，而不是一张悬空的亮板。
func _build_crest_mesh(top: Vector3, width: float, bright: float) -> ArrayMesh:
	var half_w := width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in CREST_ROWS + 1:
		var q := float(r) / float(CREST_ROWS)     # 0 = 岩檐水面，1 = 帘顶
		var z := top.z - 0.32 * pow(1.0 - q, 1.45)
		var y := top.y + 0.045 * pow(1.0 - q, 1.9)
		var w := half_w * (0.88 - 0.16 * q)
		var line: Array[Vector3] = []
		for c in CREST_COLS + 1:
			var lat := float(c) / float(CREST_COLS) * 2.0 - 1.0
			var p := Vector3(top.x + lat * w,
				y + sin(lat * 4.0 + q * 6.0) * 0.02, z)
			line.append(p)
		grid.append(line)
	for r in CREST_ROWS:
		var a: Array[Vector3] = grid[r]
		var b: Array[Vector3] = grid[r + 1]
		for c in CREST_COLS:
			var u0 := float(c) / float(CREST_COLS)
			var u1 := float(c + 1) / float(CREST_COLS)
			var v0 := float(r) / float(CREST_ROWS)
			var v1 := float(r + 1) / float(CREST_ROWS)
			var nrm := (a[c + 1] - a[c]).cross(b[c] - a[c]).normalized()
			var tint := Color(bright, 1.05, 0.86, 1.02)
			_add_water_tri(st, nrm, a[c], Vector2(u0, v0), a[c + 1], Vector2(u1, v0),
				b[c + 1], Vector2(u1, v1), tint)
			_add_water_tri(st, nrm, a[c], Vector2(u0, v0), b[c + 1], Vector2(u1, v1),
				b[c], Vector2(u0, v1), tint)
	return st.commit() as ArrayMesh


func _add_water_tri(st: SurfaceTool, nrm: Vector3, a: Vector3, ua: Vector2,
		b: Vector3, ub: Vector2, c: Vector3, uc: Vector2, tint: Color) -> void:
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(nrm)
		st.set_uv(pair[1])
		st.set_color(tint)
		st.add_vertex(pair[0])


## 常驻水景粒子（v45 重做）：柔软水雾 + 细小抛物线飞溅 + 落水点白沫丘。
## 预算：主瀑 118+42+64+34 / 两侧细流各 26+16 = 342 颗，低于 400 的上限；
## billboard 尺度 0.45~1.55m（v45-base 的 1.6~3.4m 是「硬白圆饼」的根源）。
func _build_spray() -> void:
	_mat_foam = ShaderMaterial.new()
	_mat_foam.shader = load("res://assets/shaders/waterfall_foam.gdshader")
	WorldLayout.apply_shader_parameters(_mat_foam)
	_mat_foam.set_shader_parameter("foam_gain", 0.42)
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.2, 4.8)
	foam_mesh = _add_mesh("WaterfallFoam", plane, _mat_foam, false)
	foam_mesh.position = Vector3(WorldLayout.WATERFALL_BASE.x, WorldLayout.WATER_HIGH_Y + 0.055,
		WorldLayout.WATERFALL_BASE.y)
	foam_mesh.add_to_group("water_feature")
	# 3D 白沫丘：同一份白沫 shader，抬高 + 聚拢在落水点，给落水一个「体积」
	_mat_foam_mound = _mat_foam.duplicate() as ShaderMaterial
	_mat_foam_mound.set_shader_parameter("foam_gain", 0.24)
	_mat_foam_mound.render_priority = 1
	_build_foam_mounds()
	# 水雾：主瀑一大一小两层（贴地翻涌 + 高处飘散），两侧细流各一层
	_make_spray("WaterfallMist", 128, 3.4, Vector2(0.55, 1.35), 0.14, SPRAY_MIST, Vector2.ZERO)
	_make_spray("WaterfallMistHigh", 42, 4.6, Vector2(0.50, 1.15), 0.08, SPRAY_WISP, Vector2.ZERO)
	# 飞溅：细小、短暂、抛物线落回（不再是发光大圆球）
	_make_spray("WaterfallDroplets", 64, 0.62, Vector2(0.05, 0.13), 0.55, SPRAY_DROP, Vector2.ZERO)
	_make_spray("WaterfallPlungeSpray", 34, 0.50, Vector2(0.05, 0.15), 0.30, SPRAY_SPARK, Vector2.ZERO)
	for i in range(1, WorldLayout.WATERFALL_STRANDS.size()):
		var landing := WorldLayout.waterfall_strand_landing(i)
		var offset := landing - WorldLayout.WATERFALL_BASE
		_make_spray("WaterfallMist_%d" % i, 26, 2.8, Vector2(0.42, 1.05), 0.11, SPRAY_MIST, offset)
		_make_spray("WaterfallDroplets_%d" % i, 16, 0.55, Vector2(0.04, 0.10), 0.42, SPRAY_DROP, offset)


## 单支水景粒子。尺度 / 速度 / 重力 / 贴图 / 混合模式按 kind 取，近处按距离淡出。
func _make_spray(node_name: String, amount: int, lifetime: float, size_range: Vector2,
		opacity: float, kind: int, xz_offset: Vector2) -> void:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.visibility_aabb = AABB(Vector3(-8.0, -2.0, -7.0), Vector3(16.0, 12.0, 14.0))
	particles.position = Vector3(WorldLayout.WATERFALL_BASE.x + xz_offset.x,
		WorldLayout.WATER_HIGH_Y + 0.25, WorldLayout.WATERFALL_BASE.y + xz_offset.y)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.direction = Vector3(0.0, 1.0, 0.35)
	var additive := false
	var texture_path := "res://assets/vfx/textures/smoke_04.png"
	match kind:
		SPRAY_WISP:
			particles.position.y += 1.5
			process.emission_box_extents = Vector3(2.6, 1.0, 0.95)
			process.spread = 46.0
			process.initial_velocity_min = 0.35
			process.initial_velocity_max = 1.05
			process.gravity = Vector3(0.10, 0.28, 0.12)
			process.damping_min = 0.15
			process.damping_max = 0.35
			texture_path = "res://assets/vfx/textures/smoke_06.png"
		SPRAY_DROP:
			particles.position.y += 0.05
			process.emission_box_extents = Vector3(1.9, 0.16, 0.65)
			process.spread = 68.0
			process.initial_velocity_min = 2.0
			process.initial_velocity_max = 4.4
			process.gravity = Vector3(0.0, -9.8, 0.0)
			texture_path = "res://assets/vfx/textures/light_01.png"
		SPRAY_SPARK:
			particles.position.y += 0.30
			process.emission_box_extents = Vector3(1.4, 0.12, 0.55)
			process.spread = 55.0
			process.initial_velocity_min = 0.9
			process.initial_velocity_max = 2.4
			process.gravity = Vector3(0.0, -6.5, 0.0)
			texture_path = "res://assets/vfx/textures/light_01.png"
			additive = true
		_:
			process.emission_box_extents = Vector3(2.3, 0.42, 0.85)
			process.spread = 52.0
			process.initial_velocity_min = 0.18
			process.initial_velocity_max = 0.72
			process.gravity = Vector3(0.06, 0.16, 0.10)
			process.radial_accel_min = 0.10
			process.radial_accel_max = 0.42
			process.damping_min = 0.05
			process.damping_max = 0.18
	process.scale_min = size_range.x
	process.scale_max = size_range.y
	process.angle_min = 0.0
	process.angle_max = 360.0
	if kind != SPRAY_DROP:
		process.angular_velocity_min = -8.0
		process.angular_velocity_max = 8.0
	# 生命周期渐变：淡入 → 保持 → 淡出（雾更平缓，飞溅更快消失）
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 0))
	if kind == SPRAY_MIST or kind == SPRAY_WISP:
		gradient.add_point(0.18, Color(1, 1, 1, opacity))
		gradient.add_point(0.55, Color(1, 1, 1, opacity * 0.72))
		gradient.add_point(0.85, Color(1, 1, 1, opacity * 0.22))
	else:
		gradient.add_point(0.10, Color(1, 1, 1, opacity))
		gradient.add_point(0.55, Color(1, 1, 1, opacity * 0.55))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(texture_path)
	mat.albedo_color = Color(0.86, 0.94, 0.98)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 近处淡出：镜头贴近时水雾不糊镜头（2.6m 内完全消失，7m 外正常）
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 2.6
	mat.distance_fade_max_distance = 7.0
	_spray_materials.append(mat)
	var mesh := QuadMesh.new()
	mesh.material = mat
	particles.draw_pass_1 = mesh
	add_child(particles)
	particles.add_to_group("water_feature")


## 落水点 3D 白沫丘（v45）：程序化低穹顶 + 噪声轮廓，让落水有体积而不是一张白贴图。
func _build_foam_mounds() -> void:
	for i in FOAM_MOUNDS.size():
		var item: Array = FOAM_MOUNDS[i]
		var off: Vector2 = item[0]
		var radius: float = item[1]
		var height: float = item[2]
		var center := Vector3(WorldLayout.WATERFALL_BASE.x + off.x,
			WorldLayout.WATER_HIGH_Y + 0.02, WorldLayout.WATERFALL_BASE.y + off.y)
		var mound := _add_mesh("WaterfallFoamMound" if i == 0 else "WaterfallFoamMound_%d" % i,
			_build_foam_mound_mesh(radius, height, float(i) * 2.3), _mat_foam_mound, false)
		mound.position = center
		mound.add_to_group("water_feature")


## 白沫丘网格：3 圈低穹顶 + 外圈裙边（压到水面下），轮廓按正弦扰动成不规则沫堆。
## UV 统一给 (0.5, 0.5)：白沫 shader 的 UV 边缘淡出只给平面用，沫丘不参与。
func _build_foam_mound_mesh(radius: float, height: float, phase: float) -> ArrayMesh:
	var seg := 26
	var rings: Array = [[1.0, 0.0], [0.74, 0.58], [0.38, 0.90]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for ring in rings:
		var rf: float = ring[0]
		var hf: float = ring[1]
		var row: Array[Vector3] = []
		for k in seg:
			var a := float(k) / float(seg) * TAU
			var wob := 1.0 + 0.22 * sin(a * 3.0 + phase) + 0.12 * sin(a * 7.0 - phase * 1.7) + 0.05 * sin(a * 13.0 + phase * 0.7)
			var r := radius * rf * wob
			row.append(Vector3(cos(a) * r, height * hf, sin(a) * r))
		rows.append(row)
	var skirt: Array[Vector3] = []
	for k in seg:
		var a := float(k) / float(seg) * TAU
		var wob := 1.0 + 0.22 * sin(a * 3.0 + phase) + 0.12 * sin(a * 7.0 - phase * 1.7) + 0.05 * sin(a * 13.0 + phase * 0.7)
		var r := radius * 1.05 * wob
		skirt.append(Vector3(cos(a) * r, -0.055, sin(a) * r))
	for k in seg:
		var k2 := (k + 1) % seg
		_add_mound_tri(st, skirt[k], rows[0][k], rows[0][k2])
		_add_mound_tri(st, skirt[k], rows[0][k2], skirt[k2])
	for r in 2:
		var lower: Array[Vector3] = rows[r]
		var upper: Array[Vector3] = rows[r + 1]
		for k in seg:
			var k2 := (k + 1) % seg
			_add_mound_tri(st, lower[k], upper[k], upper[k2])
			_add_mound_tri(st, lower[k], upper[k2], lower[k2])
	var last: Array[Vector3] = rows[2]
	var apex := Vector3(0.0, height * 1.03, 0.0)
	for k in seg:
		_add_mound_tri(st, last[k], apex, last[(k + 1) % seg])
	return st.commit() as ArrayMesh


func _add_mound_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (c - a).cross(b - a).normalized()
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(v)


# ---- ④ 北境崖体（石阶 + 瀑顶水道 + 唇口岩檐）与物理碰撞 ----

func _build_cliff() -> void:
	var rock := Node3D.new()
	rock.name = "NorthCliffRock"
	add_child(rock)
	cliff_body = StaticBody3D.new()
	cliff_body.name = "NorthCliff"
	cliff_body.collision_layer = 1
	cliff_body.collision_mask = 0
	cliff_body.add_to_group("water_cliff")
	add_child(cliff_body)
	for i in CLIFF_STEPS.size():
		var step: Array = CLIFF_STEPS[i]
		var x0: float = step[0]
		var x1: float = step[1]
		var z0: float = step[2]
		var z1: float = step[3]
		var y0: float = step[4]
		var y1: float = step[5]
		var size := Vector3(x1 - x0, y1 - y0, z1 - z0)
		var center := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		# 主体前沿略收进 0.10m，避免八角岩面顶穿落水帘；碰撞仍覆盖完整崖体。
		var visual_size := size
		var visual_center := center
		if i < 4:
			visual_center.z -= size.z * 0.05
			visual_size.z *= 0.90
		_cliff_block(rock, visual_center, visual_size, _rock_variant(i))
		# 物理挡板（layer 1，与地面 / 建筑同层）：A* 之外再兜一层，防分离力把单位挤进岩体
		var shape := BoxShape3D.new()
		shape.size = size
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = center
		cliff_body.add_child(col)
	# 唇口岩檐：出挑到 WATERFALL_LIP 一线，水从檐下翻出（视觉承接顶部水道）
	_cliff_block(rock, CLIFF_SHELF_CENTER, CLIFF_SHELF_SIZE, _rock_variant(2))
	# 两侧细流的出水岩台
	for i in STRAND_LEDGES.size():
		var item: Array = STRAND_LEDGES[i]
		var ledge := _cliff_block(rock, item[0], item[1], _rock_variant(i + 1))
		ledge.rotation.y = _rng.randf_range(-0.06, 0.06)
	# 瀑顶水道的材质（v45）：stream 只给很轻的岸边白沫，lip（唇口翻水）给明显的白沫前缘
	_mat_feed_stream = _make_feed_material(0.06, 0.22, TOP_STREAM_SIZE.x * 0.5, 1.45)
	_mat_feed_lip = _make_feed_material(0.42, 0.10, LIP_SHEET_SIZE.x * 0.5, 1.75)
	# 瀑顶水道水面（v45）：不规则山溪（两侧岸线噪声 + 靠近唇口加速下压），不再是矩形水板
	var stream := _add_mesh("CliffTopStream", _build_feed_ribbon(), _mat_feed_stream, false)
	stream.position = TOP_STREAM_CENTER
	stream.add_to_group("water_feature")
	# 唇口翻水的薄水片：把顶部水道与落水帘在视觉上接起来（檐顶 → 帘顶），前缘带白沫
	var lip := _add_mesh("CliffLipSheet", _build_lip_apron(), _mat_feed_lip, false)
	lip.position = LIP_SHEET_CENTER
	lip.add_to_group("water_feature")
	# 瀑顶水道两侧的岩岸 / 卵石压边：把水面夹进岩石里（破掉「泳池板」的直边）
	_build_stream_banks(rock)
	# 瀑顶平台两侧的压顶岩石：只在中间留溢流口（破掉直线）
	_cliff_block(rock, Vector3(53.4, 8.05, -72.6), Vector3(2.2, 1.2, 1.6), _rock_variant(1))
	_cliff_block(rock, Vector3(62.6, 7.95, -72.5), Vector3(2.4, 1.3, 1.7), _rock_variant(2))
	# 南立面扶壁：高低错落的出挑岩块，把直墙切成有层次的岩壁
	var buttress := [
		[Vector3(51.4, 3.4, -71.8), Vector3(2.8, 4.2, 1.6)],
		[Vector3(64.4, 3.8, -71.9), Vector3(2.6, 4.6, 1.8)],
		[Vector3(56.6, 1.9, -72.1), Vector3(2.2, 2.4, 1.4)],
		[Vector3(59.8, 2.2, -72.0), Vector3(2.0, 2.6, 1.3)],
	]
	for i in buttress.size():
		var item: Array = buttress[i]
		var blk := _cliff_block(rock, item[0], item[1], _rock_variant(i + 1))
		blk.rotation.y = _rng.randf_range(-0.08, 0.08)
	# 分层岩带：细长的水平岩层，读出「一层层叠起来的崖壁」
	var strata := [
		[Vector3(52.4, 2.35, -71.9), Vector3(5.4, 0.55, 1.2)],
		[Vector3(63.4, 2.75, -71.95), Vector3(5.0, 0.5, 1.15)],
		[Vector3(53.6, 4.35, -71.85), Vector3(4.4, 0.45, 1.05)],
		[Vector3(62.2, 4.75, -71.9), Vector3(4.2, 0.42, 1.0)],
		[Vector3(55.2, 5.85, -71.9), Vector3(3.2, 0.4, 0.95)],
	]
	for i in strata.size():
		var item: Array = strata[i]
		var band := _cliff_block(rock, item[0], item[1], _rock_variant(i % 4))
		band.rotation.y = _rng.randf_range(-0.05, 0.05)
	# 天然岩块 / 山体：把石阶盒子的直角打散成岩体轮廓（纯装饰，不登记阻挡）
	_dress_cliff(rock)


## 瀑顶山溪网格（v45，局部坐标，position 由节点设置）：两侧岸线按噪声摆动，
## 越靠近唇口水面略降 + 收窄（加速翻卷），读作岩槽里的活水而不是矩形水板。
func _build_feed_ribbon() -> ArrayMesh:
	var rows := 10
	var cols := 14
	var half_w := TOP_STREAM_SIZE.x * 0.5
	var half_len := TOP_STREAM_SIZE.y * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in rows + 1:
		var t := float(r) / float(rows)          # 0 = 上游，1 = 靠近唇口
		var z := -half_len + TOP_STREAM_SIZE.y * t
		var y := -0.030 * smoothstep(0.30, 1.0, t) + sin(t * 8.0) * 0.008
		var w := half_w * (1.0 - 0.07 * smoothstep(0.40, 1.0, t))
		var line: Array[Vector3] = []
		for c in cols + 1:
			var u := float(c) / float(cols)
			var lat := u * 2.0 - 1.0
			# 岸线噪声：两侧不是直线（岩岸 / 卵石压边会盖住这条边）
			var rough := sin(lat * 2.4 + t * 5.0 + 1.7) * 0.11 + sin(lat * 5.7 - t * 2.2) * 0.05
			var p := Vector3(lat * w * (1.0 + rough * (0.35 + 0.65 * absf(lat))), y, z)
			p.z += sin(lat * 4.0 + t * 3.0) * 0.045
			line.append(p)
		grid.append(line)
	for r in rows:
		var a: Array[Vector3] = grid[r]
		var b: Array[Vector3] = grid[r + 1]
		for c in cols:
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			_add_feed_tri(st, a[c], Vector2(u0, v0), a[c + 1], Vector2(u1, v0),
				b[c + 1], Vector2(u1, v1), b[c], Vector2(u0, v1))
	return st.commit() as ArrayMesh


## 唇口翻水薄片（v45，局部坐标）：从水道前缘到唇口，边缘按噪声羽化、前缘略下压，
## 配合 waterfall_feed 的唇口白沫，把水道和落水帘顶连起来。
func _build_lip_apron() -> ArrayMesh:
	var rows := 7
	var cols := 18
	var half_w := LIP_SHEET_SIZE.x * 0.5
	var half_len := LIP_SHEET_SIZE.y * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array = []
	for r in rows + 1:
		var t := float(r) / float(rows)          # 0 = 上游，1 = 唇口前缘
		var z := -half_len + LIP_SHEET_SIZE.y * t
		# 与水道的接缝同高（-0.035），向唇口继续下压（水面加速），两侧边缘沿 z 轻微起伏
		var y := -0.035 - 0.020 * smoothstep(0.25, 1.0, t) + sin(t * 7.0 + 0.8) * 0.006
		# 宽度从水道（0.70）向唇口张开到全宽：与水道接缝处宽度对齐，不再有突变的直角边
		var w := half_w * lerpf(0.70, 1.0, smoothstep(0.0, 1.0, t))
		var line: Array[Vector3] = []
		for c in cols + 1:
			var u := float(c) / float(cols)
			var lat := u * 2.0 - 1.0
			var rough := sin(lat * 2.1 + t * 4.2 + 0.4) * 0.16 + sin(lat * 6.3 - t * 1.8) * 0.07
			var p := Vector3(lat * w * (1.0 + rough * (0.30 + 0.70 * absf(lat))), y, z)
			p.z += sin(lat * 5.0 + t * 2.5) * 0.05
			line.append(p)
		grid.append(line)
	for r in rows:
		var a: Array[Vector3] = grid[r]
		var b: Array[Vector3] = grid[r + 1]
		for c in cols:
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			_add_feed_tri(st, a[c], Vector2(u0, v0), a[c + 1], Vector2(u1, v0),
				b[c + 1], Vector2(u1, v1), b[c], Vector2(u0, v1))
	return st.commit() as ArrayMesh


## 溢流薄片的三角形（法线朝上；UV 给流向着色备用）。
func _add_feed_tri(st: SurfaceTool, a: Vector3, ua: Vector2, b: Vector3, ub: Vector2,
		c: Vector3, uc: Vector2, d: Vector3, ud: Vector2) -> void:
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(Vector3.UP)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])
	for pair in [[a, ua], [c, uc], [d, ud]]:
		st.set_normal(Vector3.UP)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## 瀑顶水道两侧的岩岸 / 卵石压边（v45）：把水面夹进岩石里，破掉「泳池板」的直边。
func _build_stream_banks(rock: Node3D) -> void:
	var banks: Array = [
		[Vector3(53.9, 8.24, -77.1), Vector3(1.5, 0.55, 1.1)],
		[Vector3(53.8, 8.30, -76.0), Vector3(1.3, 0.75, 1.0)],
		[Vector3(54.0, 8.22, -74.9), Vector3(1.2, 0.45, 0.9)],
		[Vector3(54.1, 8.26, -74.2), Vector3(1.0, 0.50, 0.8)],
		[Vector3(62.1, 8.25, -77.0), Vector3(1.4, 0.60, 1.0)],
		[Vector3(62.2, 8.31, -75.9), Vector3(1.3, 0.80, 1.0)],
		[Vector3(62.0, 8.22, -74.9), Vector3(1.2, 0.45, 0.9)],
		[Vector3(61.9, 8.27, -74.2), Vector3(1.0, 0.55, 0.8)],
	]
	for i in banks.size():
		var item: Array = banks[i]
		var blk := _cliff_block(rock, item[0], item[1], _rock_variant(i + 1))
		blk.rotation.y = _rng.randf_range(-0.15, 0.15)
	var pebble := load("res://assets/_PLACEHOLDER/nature/rock_single_A.gltf") as PackedScene
	var boulder := load("res://assets/_PLACEHOLDER/nature/rock_single_B.gltf") as PackedScene
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		var t := float(i / 2) / 4.0
		var z := lerpf(-77.2, -74.2, t) + _rng.randf_range(-0.2, 0.2)
		var x := WorldLayout.WATERFALL_LIP.x + side * _rng.randf_range(3.25, 3.80)
		var scene: PackedScene = pebble if i % 3 != 0 else boulder
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		node.position = Vector3(x, 8.24, z)
		node.rotation = Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0)
		var sc := _rng.randf_range(0.45, 0.85)
		node.scale = Vector3(sc, sc * _rng.randf_range(0.6, 0.9), sc)
		rock.add_child(node)


## 不规则岩块；碰撞由 _build_cliff 单独登记，这里只管视觉。
func _cliff_block(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	# 八边形截面 + 三层错位岩面：保留原碰撞盒，视觉改为有裂面和圆钝转角的岩层。
	# v43：12 边截面 + 更强的半径抖动（0.86~1.12），把原先「大方盒子」的直角轮廓打散成岩体。
	var footprint: Array[Vector2] = []
	for i in 12:
		var a := TAU * float(i) / 12.0 + 0.13
		var r := _rng.randf_range(0.86, 1.12)
		footprint.append(Vector2(cos(a) * r, sin(a) * r))
	var rows: Array = []
	for level in 3:
		var row: Array[Vector3] = []
		var inset := 0.84 if level == 2 else 1.0
		for q in footprint:
			var jitter := _rng.randf_range(0.94, 1.09)
			var y: float = [-0.5, 0.05, 0.5][level]
			if level == 2:
				y += _rng.randf_range(-0.055, 0.035)
			row.append(Vector3(q.x * size.x * 0.5 * inset * jitter, y * size.y,
				q.y * size.z * 0.5 * inset * jitter))
		rows.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in 2:
		var lower: Array[Vector3] = rows[level]
		var upper: Array[Vector3] = rows[level + 1]
		for k in 12:
			var k2 := (k + 1) % 12
			_add_rock_face(st, lower[k], upper[k2], upper[k])
			_add_rock_face(st, lower[k], lower[k2], upper[k2])
	var top: Array[Vector3] = rows[2]
	for k in 12:
		_add_rock_face(st, Vector3(0, size.y * 0.51, 0), top[k], top[(k + 1) % 12])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = center
	mi.rotation.y = _rng.randf_range(-0.18, 0.18)
	parent.add_child(mi)
	return mi


func _add_rock_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	_add_tri(st, (c - a).cross(b - a).normalized(), a, b, c)


## 石阶换色：深浅灰相间 + 局部苔重的岩面，避免整座崖体一个色块。
func _rock_variant(index: int) -> ShaderMaterial:
	if _mat_rock_variants.is_empty():
		_mat_rock_variants = [
			_make_rock_material(0.0, Color(0.56, 0.54, 0.50), Color(0.38, 0.47, 0.27), 0.20),  # 浅灰
			_make_rock_material(0.0, Color(0.46, 0.44, 0.41), Color(0.33, 0.42, 0.24), 0.24),  # 中灰
			_make_rock_material(0.0, Color(0.37, 0.36, 0.34), Color(0.29, 0.38, 0.22), 0.28),  # 深灰
			_make_rock_material(0.0, Color(0.50, 0.48, 0.43), Color(0.40, 0.49, 0.26), 0.18),  # 带苔
		]
	return _mat_rock_variants[index % _mat_rock_variants.size()]


## 崖体表面点缀：岩块堆在坡脚与两翼、岩缝植被与苔藓平台（只做视觉，不加碰撞）。
func _dress_cliff(rock: Node3D) -> void:
	var outcrops: Array = [
		[Vector3(49.0, 1.2, -71.6), Vector3(2.6, 2.2, 2.2)],
		[Vector3(50.6, 2.9, -72.4), Vector3(2.6, 2.9, 2.2)],
		[Vector3(49.6, 4.2, -73.6), Vector3(2.7, 2.4, 2.0)],
		[Vector3(65.6, 1.2, -71.6), Vector3(3.0, 2.2, 2.4)],
		[Vector3(64.6, 3.0, -72.6), Vector3(2.6, 3.0, 2.2)],
		[Vector3(66.0, 4.4, -73.4), Vector3(2.6, 2.4, 2.0)],
		[Vector3(52.2, 6.6, -74.2), Vector3(2.4, 1.9, 2.6)],
		[Vector3(63.4, 6.9, -74.4), Vector3(2.6, 2.0, 2.6)],
	]
	for i in outcrops.size():
		var data: Array = outcrops[i]
		var outcrop := _cliff_block(rock, data[0], data[1], _rock_variant(i + 1))
		outcrop.rotation.y = _rng.randf_range(-0.22, 0.22)
	# 稀疏岩缝植被，集中在两翼湿润平台与出水岩台旁，避开溢流口。
	var plant := load("res://assets/_PLACEHOLDER/nature/waterplant_A.gltf") as PackedScene
	for spot: Vector3 in [Vector3(50.2, 5.5, -72.6), Vector3(51.2, 7.1, -73.8),
			Vector3(64.2, 6.1, -72.7), Vector3(65.0, 7.4, -73.9), Vector3(55.4, 7.9, -74.6),
			Vector3(61.4, 7.8, -74.7)]:
		for k in 3:
			var leaves := plant.instantiate() as Node3D
			leaves.position = spot + Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.4, 0.4))
			leaves.scale = Vector3.ONE * _rng.randf_range(1.4, 2.2)
			leaves.rotation.y = _rng.randf_range(0, TAU)
			rock.add_child(leaves)
	var boulder_a := load("res://assets/_PLACEHOLDER/nature/rock_single_A.gltf") as PackedScene
	var boulder_b := load("res://assets/_PLACEHOLDER/nature/rock_single_B.gltf") as PackedScene
	# 远山岩脊：同一套 cliff_rock 材质的岩块向后堆叠，颜色与崖体连续（不用山体资产，免黄色草顶）。
	var ridge: Array = [
		[Vector3(50.6, 6.4, -81.0), Vector3(8.0, 3.2, 5.0), -0.12],
		[Vector3(63.4, 6.6, -81.6), Vector3(6.8, 3.0, 4.6), 0.18],
		[Vector3(57.2, 6.0, -84.4), Vector3(10.4, 2.6, 4.2), 0.05],
		[Vector3(54.4, 8.4, -82.2), Vector3(5.0, 1.8, 3.4), -0.20],
		[Vector3(60.2, 8.2, -82.6), Vector3(4.4, 1.6, 3.0), 0.24],
	]
	for i in ridge.size():
		var item: Array = ridge[i]
		var block := _cliff_block(rock, item[0], item[1], _rock_variant(i + 2))
		block.rotation.y = float(item[2])
	# 岩块：两翼坡脚 + 台阶转角 + 潭边，遮住盒子直边
	var spots := [
		Vector3(49.6, 2.2, -73.4), Vector3(51.2, 4.4, -74.6), Vector3(48.6, 1.1, -76.4),
		Vector3(64.6, 2.2, -73.2), Vector3(63.4, 4.5, -74.4), Vector3(66.4, 1.2, -76.0),
		Vector3(53.4, 7.1, -76.4), Vector3(62.4, 7.0, -76.8), Vector3(57.4, 7.15, -77.4),
		Vector3(52.4, 2.9, -73.6), Vector3(61.6, 3.2, -74.0),
		Vector3(50.2, 1.2, -70.9), Vector3(65.8, 1.0, -70.8), Vector3(54.2, 1.0, -71.4),
		Vector3(61.0, 1.3, -71.6), Vector3(47.6, 0.9, -72.2), Vector3(67.4, 1.1, -72.4),
		Vector3(53.2, 0.6, -68.6), Vector3(59.4, 0.6, -68.4),
	]
	for i in spots.size():
		var scene := boulder_b if i % 2 == 0 else boulder_a
		if scene == null:
			continue
		var node := scene.instantiate() as Node3D
		node.position = spots[i]
		node.rotation = Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.25, 0.25))
		var sc := _rng.randf_range(1.6, 2.6)
		node.scale = Vector3(sc, sc * _rng.randf_range(0.7, 1.0), sc)
		rock.add_child(node)


## 河岸砾石滩：沿河道两侧铺一条比水面更宽的浅色砾石带，并环水潭一圈。
## 直接治「水与草地之间一条突兀直线」：ground shader 的湿泥带只负责压暗，成不了滩。
func _build_bank_strip() -> void:
	var samples := river_samples()
	if samples.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每侧三列：内列沉到水下、中列贴水面、外列压到地表（做出河滩坡度）
	for sign_f in [-1.0, 1.0]:
		var prev: Array[Vector3] = []
		for i in samples.size():
			var s: Dictionary = samples[i]
			var p: Vector2 = s["p"]
			var dir: Vector2 = s["dir"]
			var half: float = s["half"]
			if WorldLayout.lake_distance(p) < 1.25:
				prev = []          # 入湖段不再铺滩（否则会盖在湖面上）
				continue
			var nrm := Vector2(-dir.y, dir.x)
			var y := minf(river_surface_y(p), WorldLayout.WATER_HIGH_Y)
			var cur: Array[Vector3] = [
				Vector3(p.x + nrm.x * sign_f * (half * 0.92), maxf(y - 0.34, 0.03),
					p.y + nrm.y * sign_f * (half * 0.92)),
				Vector3(p.x + nrm.x * sign_f * (half + 0.5), 0.05, p.y + nrm.y * sign_f * (half + 0.5)),
				Vector3(p.x + nrm.x * sign_f * (half + 1.5), 0.02, p.y + nrm.y * sign_f * (half + 1.5)),
			]
			if not prev.is_empty():
				for k in 2:
					if sign_f > 0.0:
						_add_bank_quad(st, prev[k], prev[k + 1], cur[k + 1], cur[k], k)
					else:
						_add_bank_quad(st, prev[k + 1], prev[k], cur[k], cur[k + 1], k)
			prev = cur
	# 水潭外圈砾石环
	var seg := 40
	var prev_ring: Array[Vector3] = []
	var ring_r: Array[float] = [0.98, 1.24]
	var ring_y: Array[float] = [maxf(WorldLayout.WATER_HIGH_Y - 0.34, 0.03), 0.02]
	for k in seg + 1:
		var a := float(k % seg) / float(seg) * TAU
		var edge := 1.0 - 0.05 * sin(a * 4.0) + 0.025 * sin(a * 9.0)
		var q := WorldLayout.POOL_CENTER + Vector2(cos(a) * WorldLayout.POOL_RADII.x, sin(a) * WorldLayout.POOL_RADII.y) * edge
		var cur_ring: Array[Vector3] = []
		for r in 2:
			var pt := WorldLayout.POOL_CENTER + (q - WorldLayout.POOL_CENTER) * ring_r[r]
			cur_ring.append(Vector3(pt.x, ring_y[r], pt.y))
		var bank_p := Vector2(cur_ring[0].x, cur_ring[0].z)
		var rv := WorldLayout.river_distance(bank_p)
		if not prev_ring.is_empty() and not _in_cliff(bank_p) and rv.x > rv.y + 0.3:
			_add_bank_quad(st, prev_ring[0], prev_ring[1], cur_ring[1], cur_ring[0], 1)
		prev_ring = cur_ring
	# 湖岸浅沙环：只在湖西 / 湖东近岸铺一圈，破掉湖面与草地的硬边
	var lake_prev: Array[Vector3] = []
	for k in 72:
		var a := float(k) / 72.0 * TAU
		var outer := WorldLayout.lake_shore_point(a)
		var inner := WorldLayout.LAKE_CENTER + (outer - WorldLayout.LAKE_CENTER) * 0.955
		var cur: Array[Vector3] = [
			Vector3(inner.x, maxf(WorldLayout.WATER_HIGH_Y - 0.26, 0.03), inner.y),
			Vector3(outer.x, 0.035, outer.y),
			Vector3(WorldLayout.LAKE_CENTER.x + (outer.x - WorldLayout.LAKE_CENTER.x) * 1.10, 0.015,
				WorldLayout.LAKE_CENTER.y + (outer.y - WorldLayout.LAKE_CENTER.y) * 1.10),
		]
		if not lake_prev.is_empty():
			_add_bank_quad(st, lake_prev[0], lake_prev[1], cur[1], cur[0], 1)
			_add_bank_quad(st, lake_prev[1], lake_prev[2], cur[2], cur[1], 2)
		lake_prev = cur
	var strip := _add_mesh("RiverBankGravel", st.commit(), _mat_bank, false)
	strip.add_to_group("water_feature")


# ---- ⑤ 河岸装饰（卵石 / 芦苇 / 浅滩踏石）----

func _build_banks() -> void:
	var banks := Node3D.new()
	banks.name = "RiverBanks"
	add_child(banks)
	var pebble_scene := load("res://assets/_PLACEHOLDER/nature/rock_single_A.gltf") as PackedScene
	var boulder_scene := load("res://assets/_PLACEHOLDER/nature/rock_single_B.gltf") as PackedScene
	var reed_scene := load("res://assets/_PLACEHOLDER/nature/waterplant_A.gltf") as PackedScene
	var lily_scene := load("res://assets/_PLACEHOLDER/nature/waterlily_B.gltf") as PackedScene
	var samples := river_samples()
	for i in samples.size():
		if i % 2 == 1 and _rng.randf() < 0.5:
			continue
		var s: Dictionary = samples[i]
		var p: Vector2 = s["p"]
		var dir: Vector2 = s["dir"]
		var half: float = s["half"]
		var nrm := Vector2(-dir.y, dir.x)
		for side in [-1.0, 1.0]:
			var side_f: float = side
			if _rng.randf() < 0.6:
				var off := half + _rng.randf_range(0.35, 1.9)
				var q := p + nrm * (side_f * off)
				if WorldLayout.pool_distance(q) < 1.06 or WorldLayout.lake_distance(q) < 1.04:
					continue
				var scene := pebble_scene if _rng.randf() < 0.7 else boulder_scene
				if scene != null:
					_place_scene(banks, scene, q, _rng.randf_range(0.8, 2.1))
			if _rng.randf() < 0.35:
				var q2 := p + nrm * (side_f * (half + _rng.randf_range(0.05, 0.7)))
				if WorldLayout.pool_distance(q2) < 1.02 or WorldLayout.lake_distance(q2) < 1.0:
					continue
				# 芦苇贴着岸线长，水潭边也撒一些
				_place_scene(banks, reed_scene, q2, _rng.randf_range(0.7, 1.4))
	# 水潭周边：芦苇 + 睡莲
	for i in 26:
		var a := float(i) / 26.0 * TAU
		var rad := 1.06 + _rng.randf_range(0.0, 0.3)
		var q := WorldLayout.POOL_CENTER + Vector2(cos(a) * WorldLayout.POOL_RADII.x * rad,
			sin(a) * WorldLayout.POOL_RADII.y * rad)
		if _in_cliff(q):
			continue
		if _rng.randf() < 0.55:
			_place_scene(banks, reed_scene, q, _rng.randf_range(0.8, 1.5))
		else:
			_place_scene(banks, lily_scene, q, _rng.randf_range(0.9, 1.6))
	# 浅滩踏石：让「可以过河」在视觉上读得出来（三块露出水面的石头排在过河线上）
	var ford_axis := _ford_axis()
	for k in 3:
		var t := (float(k) - 1.0) * 1.5
		var q := FORD_CENTER + ford_axis * t
		_place_scene(banks, boulder_scene if k == 1 else pebble_scene, q, 1.5 if k == 1 else 1.2)


func _place_scene(parent: Node3D, scene: PackedScene, at: Vector2, scale_mul: float) -> void:
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	node.position = Vector3(at.x, 0.0, at.y)
	node.rotation.y = _rng.randf_range(0.0, TAU)
	node.scale = Vector3.ONE * scale_mul
	parent.add_child(node)


# ---- ④b 湖心小岛（纯视觉：不写 terrain_cells、不加碰撞、不参与寻路）----

func _build_lake_island() -> void:
	island_node = Node3D.new()
	island_node.name = "LakeIsland"
	island_node.position = Vector3(WorldLayout.LAKE_ISLAND_CENTER.x, 0.0, WorldLayout.LAKE_ISLAND_CENTER.y)
	add_child(island_node)
	island_node.add_to_group("water_feature")
	_mat_island_rock = _make_rock_material(0.0, Color(0.46, 0.44, 0.39), Color(0.30, 0.44, 0.22), 0.62)
	var rock_mat: ShaderMaterial = _mat_island_rock
	# 水下沙洲同样走 cliff_rock shader（夜里不会被月光提亮成一块白斑）
	_mat_island_sand = _make_rock_material(0.0, Color(0.46, 0.42, 0.31), Color(0.40, 0.44, 0.26), 0.45)
	var sand_mat: ShaderMaterial = _mat_island_sand
	# ① 水下沙洲：比岛体宽一圈、只到水面下 2cm——透过浅水读作「岛周围变浅的沙底」
	var sand := MeshInstance3D.new()
	sand.name = "IslandSandbar"
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sseg := 28
	var sand_ring: Array[Vector3] = []
	for k in sseg:
		var a := float(k) / float(sseg) * TAU
		var sc := WorldLayout.island_shore_scale(a) * 1.55
		sand_ring.append(Vector3(cos(a) * WorldLayout.LAKE_ISLAND_RADII.x * sc, 0.025,
			sin(a) * WorldLayout.LAKE_ISLAND_RADII.y * sc))
	for k in sseg:
		_add_flat_tri(sst, Vector3(0.0, 0.03, 0.0), sand_ring[(k + 1) % sseg], sand_ring[k])
	sand.mesh = sst.commit()
	sand.material_override = sand_mat
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	island_node.add_child(sand)
	# ② 岩体：水下湿岩裙（-0.5）→ 出水岩台（0.18）→ 岛缘岩脊（0.46），三层谐波抖动
	var seg := 32
	var bands: Array = [[1.30, -0.50], [1.12, 0.06], [0.96, 0.30], [0.82, 0.46]]
	var rings: Array = []
	for band in bands:
		var row: Array[Vector3] = []
		for k in seg:
			var a := float(k) / float(seg) * TAU
			var rough := 1.0 + 0.035 * sin(a * 7.0 + 0.6) + 0.02 * sin(a * 13.0)
			var sc := WorldLayout.island_shore_scale(a) * float(band[0]) * rough
			row.append(Vector3(cos(a) * WorldLayout.LAKE_ISLAND_RADII.x * sc, float(band[1]),
				sin(a) * WorldLayout.LAKE_ISLAND_RADII.y * sc))
		rings.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in 3:
		var lower: Array[Vector3] = rings[b]
		var upper: Array[Vector3] = rings[b + 1]
		for k in seg:
			var k2 := (k + 1) % seg
			_add_rock_face(st, lower[k], upper[k2], upper[k])
			_add_rock_face(st, lower[k], lower[k2], upper[k2])
	var top_ring: Array[Vector3] = rings[3]
	var top_center := Vector3(0.0, 0.50, 0.0)
	for k in seg:
		_add_flat_tri(st, top_center, top_ring[(k + 1) % seg], top_ring[k])
	var island_mesh := MeshInstance3D.new()
	island_mesh.name = "IslandRock"
	island_mesh.mesh = st.commit()
	island_mesh.material_override = rock_mat
	island_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	island_node.add_child(island_mesh)
	# ③ 岛顶草盘：嵌在岩脊里的一层草地（略高于岩台，边缘不外露）
	var grass := MeshInstance3D.new()
	grass.name = "IslandGrass"
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gseg := 26
	var grings: Array[Vector3] = []
	for k in gseg:
		var a := float(k) / float(gseg) * TAU
		var sc := WorldLayout.island_shore_scale(a) * 0.62
		grings.append(Vector3(cos(a) * WorldLayout.LAKE_ISLAND_RADII.x * sc, 0.53,
			sin(a) * WorldLayout.LAKE_ISLAND_RADII.y * sc))
	for k in gseg:
		_add_flat_tri(gst, Vector3(0.0, 0.56, 0.0), grings[(k + 1) % gseg], grings[k])
	grass.mesh = gst.commit()
	grass.material_override = _mat_island_grass
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	island_node.add_child(grass)
	# ④ 岛缘岩石 + 芦苇 + 两棵小树（全部纯视觉，不参与寻路 / 碰撞）
	var boulder_a := load("res://assets/_PLACEHOLDER/nature/rock_single_A.gltf") as PackedScene
	var boulder_b := load("res://assets/_PLACEHOLDER/nature/rock_single_B.gltf") as PackedScene
	var reed_scene := load("res://assets/_PLACEHOLDER/nature/waterplant_A.gltf") as PackedScene
	var tree_scene := load("res://assets/_PLACEHOLDER/nature/tree_single_A.gltf") as PackedScene
	var shrub_scene := load("res://assets/_PLACEHOLDER/nature/tree_single_B.gltf") as PackedScene
	for k in 13:
		var a := float(k) / 13.0 * TAU + _rng.randf_range(-0.10, 0.10)
		var sc := WorldLayout.island_shore_scale(a) * _rng.randf_range(0.88, 1.0)
		var local := Vector3(cos(a) * WorldLayout.LAKE_ISLAND_RADII.x * sc, 0.0,
			sin(a) * WorldLayout.LAKE_ISLAND_RADII.y * sc)
		if k % 3 == 0:
			_place_local(island_node, reed_scene, local + Vector3(0, 0.20, 0), _rng.randf_range(1.4, 2.1))
		else:
			var scene := boulder_b if k % 2 == 0 else boulder_a
			_place_local(island_node, scene, local + Vector3(0, 0.20, 0), _rng.randf_range(1.5, 2.4))
	for k in 4:
		var a := float(k) / 4.0 * TAU + 0.4
		var local := Vector3(cos(a) * WorldLayout.LAKE_ISLAND_RADII.x * 0.42, 0.50,
			sin(a) * WorldLayout.LAKE_ISLAND_RADII.y * 0.42)
		_place_local(island_node, reed_scene, local, _rng.randf_range(1.0, 1.4))
	_place_local(island_node, tree_scene, Vector3(1.1, 0.52, -0.5), _rng.randf_range(2.0, 2.3))
	_place_local(island_node, shrub_scene, Vector3(-1.4, 0.50, 0.8), _rng.randf_range(1.1, 1.3))
	_place_local(island_node, boulder_a, Vector3(-0.4, 0.46, -1.2), 1.1)


func _place_local(parent: Node3D, scene: PackedScene, local: Vector3, scale_mul: float) -> void:
	if scene == null:
		return
	var node := scene.instantiate() as Node3D
	if node == null:
		return
	node.position = local
	node.rotation.y = _rng.randf_range(0.0, TAU)
	node.scale = Vector3.ONE * scale_mul
	parent.add_child(node)


# ---- ⑥ 寻路登记（永久地形阻挡，与湖泊同一套做法）----

func _register_terrain() -> void:
	if grid == null:
		return
	blocked_cells = 0
	for x in grid.grid_size.x:
		for z in grid.grid_size.y:
			var cell := Vector2i(x, z)
			var w := grid.grid_to_world(cell)
			var p := Vector2(w.x, w.z)
			# 浅滩涉水点 / 河口浅滩：唯一不阻挡的过水缺口（湖岸误占的格一并清掉）
			if in_ford(p) or p.distance_to(SHALLOW_CENTER) <= SHALLOW_RADIUS:
				grid.terrain_cells.erase(cell)
				continue
			var block := false
			if _in_cliff(p):
				block = true
			elif WorldLayout.pool_distance(p) < 1.0:
				block = true
			else:
				var rv := WorldLayout.river_distance(p)
				if rv.x <= rv.y + WorldLayout.RIVER_BLOCK_PAD:
					block = true
			if block:
				grid.terrain_cells[cell] = true
				blocked_cells += 1


## 过河方向（垂直于河道）与浅滩走廊。
static func _ford_axis() -> Vector2:
	var dir := (WorldLayout.RIVER_PTS[1] - WorldLayout.RIVER_PTS[0]).normalized()
	return Vector2(-dir.y, dir.x)


## 是否落在浅滩过河走廊内（以 FORD_CENTER 为中心的胶囊）。
static func in_ford(p: Vector2) -> bool:
	var axis := _ford_axis()
	var a := FORD_CENTER - axis * FORD_HALF_LEN
	var b := FORD_CENTER + axis * FORD_HALF_LEN
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a.lerp(b, t)) <= FORD_RADIUS


static func _in_cliff(p: Vector2) -> bool:
	return p.x >= CLIFF_X0 and p.x <= CLIFF_X1 and p.y >= CLIFF_Z0 and p.y <= CLIFF_Z1


# ---- ⑦ 清理落在水里的散布植被（DecorationScatter 只避湖，不避新河道 / 水潭 / 崖体）----

func _clear_scatter_in_water() -> void:
	cleared_scatter = 0
	if world_root == null:
		return
	var scatter := world_root.get_node_or_null("Decorations/DecorationScatter")
	if scatter == null:
		return
	# 只扫与本水系相交的分块（MultiMesh 按 16m 分块，整图逐实例遍历没有必要）
	var zone := AABB(Vector3(CLIFF_X0 - 8.0, -2.0, CLIFF_Z0 - 2.0),
		Vector3(CLIFF_X1 - CLIFF_X0 + 16.0, 10.0, 48.0))
	for child in scatter.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		# 分块名尾部就是 16m 分块坐标（MultiMesh.get_aabb() 在无头模式下返回零盒，不能用）
		if mm.instance_count == 0 or not _chunk_in_zone(String(mmi.name), zone):
			continue
		if not _multimesh_readable(scatter):
			return
		var dead := Basis().scaled(Vector3.ZERO)
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			if not _in_clear_zone(Vector2(t.origin.x, t.origin.z)):
				continue
			mm.set_instance_transform(i, Transform3D(dead, t.origin))
			cleared_scatter += 1


## MultiMesh 实例能否回读（无头模式用 dummy 渲染驱动，get_instance_transform 一律返回零变换）。
## 不能回读时直接跳过清理——真正的观感问题只在有渲染器的运行里出现。
func _multimesh_readable(parent: Node) -> bool:
	for child in parent.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.instance_count == 0:
			continue
		var mm := mmi.multimesh
		for i in mini(mm.instance_count, 8):
			var t := mm.get_instance_transform(i)
			# dummy 渲染驱动把每个实例都读成单位 / 零变换，真渲染器读回真实摆放
			if t.origin.length_squared() > 0.0001 or not is_equal_approx(t.basis.determinant(), 1.0):
				scatter_readback = true
				return true
		scatter_readback = false
		return false
	return false


## 该 16m 分块是否与本水系相交（按分块名尾部的块坐标判断）。
func _chunk_in_zone(mmi_name: String, zone: AABB) -> bool:
	var parts := mmi_name.split("_")
	if parts.size() < 2 or not parts[parts.size() - 2].is_valid_int() or not parts[parts.size() - 1].is_valid_int():
		return true
	var cx := parts[parts.size() - 2].to_int()
	var cz := parts[parts.size() - 1].to_int()
	var x0 := int(floor(zone.position.x / 16.0))
	var x1 := int(floor((zone.position.x + zone.size.x) / 16.0))
	var z0 := int(floor(zone.position.z / 16.0))
	var z1 := int(floor((zone.position.z + zone.size.z) / 16.0))
	return cx >= x0 and cx <= x1 and cz >= z0 and cz <= z1


func _in_clear_zone(p: Vector2) -> bool:
	# v43：1.8m 岸边净空——0.4m 时树冠会盖在水面上、树干像泡在水里（多股瀑布 + 潭边最明显）
	return WorldLayout.water_distance(p) < 1.8 or _in_cliff(p)


# ---- SurfaceTool 小工具（顶点顺序按 Godot 正面朝 +Y 的顺时针约定）----

func _add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	_add_tri(st, Vector3.UP, a, b, c)


func _add_tri(st: SurfaceTool, nrm: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(nrm)
		st.add_vertex(v)


## 河滩四边形：按「离水远近」给顶点色（内列湿泥深、外列干沙浅），水面边缘不再有一条亮线。
func _add_bank_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, band: int) -> void:
	var wet := BAND_COLORS[clampi(band, 0, BAND_COLORS.size() - 1)]
	var dry := BAND_COLORS[clampi(band + 1, 0, BAND_COLORS.size() - 1)]
	_add_tri_colored(st, a, wet, b, dry, c, dry)
	_add_tri_colored(st, a, wet, c, dry, d, wet)


func _add_tri_colored(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color,
		c: Vector3, cc: Color) -> void:
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(Vector3.UP)
		st.set_color(pair[1])
		st.add_vertex(pair[0])


func _add_flat_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_tri(st, Vector3.UP, a, b, c)
	_add_tri(st, Vector3.UP, a, c, d)


func _add_mesh(node_name: String, mesh: Mesh, mat: Material, cast_shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
