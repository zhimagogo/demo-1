class_name WorldLayout
extends RefCounted
## 场景布局的公共约定。道路与湖岸公式同时用于着色、散布和碰撞。
##
## 水系（v12）：瀑布 → 河流 → 湖泊 是一条完整链路，几何真相只写在本文件：
##   ① 瀑布：北境崖壁 `WATERFALL_LIP`（瀑顶唇口）落到 `WATERFALL_BASE`（落水点），
##      立面沿唇口→落水点方向倾斜，`waterfall_zone()` 给出立面覆盖范围；
##   ② 水潭：瀑布下的半圆深潭 `POOL_CENTER` / `POOL_RADII`；
##   ③ 河流：`RIVER_PTS` 折线（首段在瀑下水潭、末点在湖中）自北向南汇入湖泊，
##      逐点半宽 `RIVER_HALF` 支持宽窄变化；`river_distance()` 返回 (距离, 半宽)。
## 着色（assets/shaders/water_surface.gdshaderinc）、水面网格（WorldScenery.gd）、
## 寻路阻挡三处都读本文件，因此改河道只需改这里的折线。
##
## v40 世界扩张：可玩边界 64 → 128 米（256×256 米、128×128 格 @2m）。
## 旧地图（±64m）内的地标（营地 / 废墟 / 采石场）保持原样，新增内容落在扩张环带
## （见 WorldRegions 的六个主题区域）。因此这里不做整体平移或缩放。
##
## v43 主城扩大 + 水系东迁（需求③a）：王城 20m → 26m 半边长（52×52m），原湖泊
## （中心 (37,-28)、半径 (15,11)）会被新城东侧压到岸边，因此整套水系（瀑布 → 水潭 →
## 河流 → 湖泊）整体东迁到城东：湖泊中心 (52,-38)、半径 (17,12)，湖西岸距城东沿
## 仍有 9m 净空（52-17=35 > 26）。水系视觉造型（WaterFeature / WorldScenery /
## ThemedRegions 的码头与霜区水景）由后续 water 任务按这套新坐标迭代。

const MAP_HALF: float = 128.0     # 256×256 米可玩边界
const CITY_HALF: float = 26.0     # 王城半边长：52×52m（城门火把 / 建造范围 / 小地图共用）
const LAKE_CENTER := Vector2(52.0, -38.0)
const LAKE_RADII := Vector2(17.0, 12.0)
## 湖岸谐波（v43 视觉迭代）：三阶正弦叠加把「均匀椭圆」打成有双湾与半岛的自然岸线。
## 振幅总和 ≈ 0.147 → 岸线在世界坐标上摆动 ±1.5~2.5m；与 water_surface.gdshaderinc、
## ground.gdshader 的 lake_sdf 完全同式（改这里三处同步，tests/CityScaleTest 只锁中心与半径）。
## 相位取 0（只有奇次谐波）：湖心 lake_distance 恰好 = 0（CityScaleTest / is_water 的口径），
## 同时岸线仍有北收南凸、东西双湾的不规则轮廓（振幅和 0.147 → 岸线 ±1.5~2.5m）。
const LAKE_HARMONICS: Array[float] = [0.075, 0.050, 0.022]   # 3 阶 / 7 阶 / 11 阶振幅
const LAKE_PHASES: Array[float] = [0.0, 0.0, 0.0]
## 湖心小岛（v43）：**纯视觉**——不进 terrain_cells、不加碰撞、不参与寻路，
## 只由 WaterFeature 造网格 + 水面着色挖洞；湖面对应格仍然是永久阻挡。
const LAKE_ISLAND_CENTER := Vector2(47.0, -36.0)
const LAKE_ISLAND_RADII := Vector2(4.6, 3.4)
const CAMP := Vector2(-31.0, 12.0)
const RUINS := Vector2(-40.0, -35.0)
const QUARRY := Vector2(39.0, 28.0)

# ---- 水系（瀑布 → 水潭 → 河流 → 湖泊）----
const WATERFALL_LIP := Vector2(58.0, -72.0)      # 瀑顶唇口（北境崖壁）
const WATERFALL_BASE := Vector2(56.0, -64.0)     # 落水点（水潭中心）
const WATERFALL_WIDTH: float = 9.0               # 立面横向宽度
const WATERFALL_TOP_Y: float = 8.2               # 唇口高度
## 多股落水（v43）：每条 = [横向 dx（米，0 = 主瀑 / 负西正东）, 顶端高度, 横向宽度, 流量系数, 亮度系数]。
## 两侧细流从崖壁中段岩台溢出（顶端高度更低）→ 分层落水；落水点 = WATERFALL_BASE + (dx, 0)。
const WATERFALL_STRANDS: Array = [
	[0.0, 8.2, 4.8, 1.00, 1.00],     # 主瀑：唇口全高、最宽最亮
	[-3.15, 6.5, 1.35, 0.82, 0.86],  # 西侧细流：中段岩台溢出
	[3.05, 7.1, 1.15, 0.74, 0.80],   # 东侧细流：更高一点、更细
]
const POOL_CENTER := Vector2(56.0, -64.0)
const POOL_RADII := Vector2(6.0, 5.0)
const POOL_DEPTH: float = 1.1                    # 潭底相对地表下沉（视觉）
const WATER_HIGH_Y: float = 0.30                 # 河 / 潭水面高度（高于湖面 0.06，避免共面闪烁）
# 河道折线：从瀑下水潭南侧一路向南汇入湖泊南岸（末点在湖内，靠着色淡出与湖水融合）
# v43：随湖泊东迁重排为带 S 弯的窄河（上游宽 2.0 → 入湖 1.5），首点仍在潭内（河从潭里流出来）。
const RIVER_PTS: Array[Vector2] = [
	Vector2(56.0, -61.5),
	Vector2(54.6, -55.8),
	Vector2(53.4, -50.6),
	Vector2(51.9, -45.2),
]
const RIVER_HALF: Array[float] = [2.0, 1.9, 1.7, 1.5]
const RIVER_BLOCK_PAD: float = 1.15              # 寻路阻挡 = 半宽 + 该余量（单位半径 + 转向余量）

## 地面 shader 的定长数组容量（改大时两边同步：本文件 + ground.gdshader）。
const SHADER_REGION_MAX: int = 8     # 主题区域染色槽位（当前 6 个区域）
const SHADER_TRAIL_MAX: int = 16     # 小径段槽位（旧地标 8 段 + 主题区域 6 段）

## 小径网络（a→b 折线段）：道路着色、道路距离、植被避让共用同一份数据。
## v40 起旧地标小径与「主路 → 主题区域」的探索小径都集中在这里；
## ground.gdshader 通过 trail_a / trail_b / trail_seg uniforms 读同一份数据（不再各写一套公式）。
const TRAIL_SEGMENTS: Array = [
	# ---- 旧地图内的地标小径（v12 起）----
	[Vector2(-25.0, -2.0), Vector2(-27.0, 6.0)],
	[Vector2(-27.0, 6.0), CAMP],
	[Vector2(-4.0, -30.0), Vector2(-20.0, -32.0)],
	[Vector2(-20.0, -32.0), RUINS],
	[Vector2(2.0, -25.0), Vector2(18.0, -20.0)],
	[Vector2(18.0, -20.0), Vector2(21.0, -26.0)],
	[Vector2(30.0, 2.0), Vector2(36.0, 14.0)],
	[Vector2(36.0, 14.0), QUARRY],
	# ---- v40 探索小径：主路 → 六个主题区域 ----
	# v40.1：终点统一在 landmark 前 8.5m 收住（正好停在区域石碑前），
	# 不再让土路从地标道具群中间穿过去（原先麦田/矿轨/断旗/纪念十字都压在路面上）。
	[Vector2(3.44, -60.0), Vector2(24.95, -52.72)],    # 北主路 → 霜语瀑布（水潭西岸，避开崖体）
	[Vector2(3.44, -60.0), Vector2(85.78, -81.82)],    # 北主路 → 星落矿坑（从崖体北侧绕过）
	[Vector2(72.0, -3.78), Vector2(85.99, 1.17)],      # 东主路 → 风吟麦海
	[Vector2(-4.94, 70.0), Vector2(1.24, 87.96)],      # 南主路 → 烬誓战场
	[Vector2(-70.0, 3.93), Vector2(-85.93, -1.33)],    # 西主路 → 雾隐密林
	[Vector2(-70.0, 3.93), Vector2(-84.37, 77.66)],    # 西主路 → 盐风沼地
]


## ---- 水系几何 ----

## 点到河道的距离与该处半宽：返回 Vector2(距离, 半宽)，与着色读同一套折线。
static func river_distance(p: Vector2) -> Vector2:
	var best_d := INF
	var best_w := RIVER_HALF[0]
	for i in RIVER_PTS.size() - 1:
		var a := RIVER_PTS[i]
		var b := RIVER_PTS[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a.lerp(b, t))
		if d < best_d:
			best_d = d
			best_w = lerpf(RIVER_HALF[i], RIVER_HALF[i + 1], t)
	return Vector2(best_d, best_w)


## 是否落在河面内（margin > 0 表示含岸线外扩）。
static func is_river(p: Vector2, margin: float = 0.0) -> bool:
	var r := river_distance(p)
	return r.x <= r.y + margin


## 瀑布立面参数化：x = 横向 -0.5..0.5，y = 纵向 0（瀑顶）→ 1（落水点），z > 0.5 = 不在立面内。
static func waterfall_uv(p: Vector2) -> Vector3:
	var axis := (WATERFALL_BASE - WATERFALL_LIP).normalized()
	var side := Vector2(-axis.y, axis.x)
	var along := (p - WATERFALL_LIP).dot(axis)
	var lat := (p - WATERFALL_LIP).dot(side)
	var length := WATERFALL_LIP.distance_to(WATERFALL_BASE)
	var outside := 0.0
	if along < -0.25 or along > length + 0.25 or absf(lat) > WATERFALL_WIDTH * 0.5:
		outside = 1.0
	return Vector3(lat / WATERFALL_WIDTH + 0.5, along / maxf(length, 0.01), outside)


## 水潭边缘距离（1.0 = 岸线，> 1 = 潭外）。
static func pool_distance(p: Vector2) -> float:
	var q := p - POOL_CENTER
	q.x /= POOL_RADII.x
	q.y /= POOL_RADII.y
	var angle := atan2(q.y, q.x)
	return q.length() + 0.05 * sin(angle * 4.0)


## 全部水域（湖 ∪ 河 ∪ 潭）的“离岸距离”：< 0 表示在水里，> 0 表示离岸米数。
static func water_distance(p: Vector2) -> float:
	var d := lake_distance(p)
	var r := river_distance(p)
	d = minf(d, r.x - r.y)
	d = minf(d, pool_distance(p) - 1.0)
	return d


static func is_water(p: Vector2, margin: float = 0.0) -> bool:
	return water_distance(p) < margin


static func lake_distance(p: Vector2) -> float:
	var q := (p - LAKE_CENTER) / LAKE_RADII
	var angle := atan2(q.y, q.x)
	return q.length() + lake_harmonic(angle)


## 湖岸谐波：角度（归一化坐标下的 atan2）→ 半径偏移量。着色器里有同式副本。
static func lake_harmonic(angle: float) -> float:
	return LAKE_HARMONICS[0] * sin(angle * 3.0 + LAKE_PHASES[0]) \
		+ LAKE_HARMONICS[1] * sin(angle * 7.0 + LAKE_PHASES[1]) \
		+ LAKE_HARMONICS[2] * sin(angle * 11.0 + LAKE_PHASES[2])


## 岸线半径比例：给定角度，湖岸在 LAKE_CENTER + dir * LAKE_RADII * scale 上。
## （WorldScenery 的岸边卵石 / 芦苇、码头落点、水面网格外扩都用它，别再各写一份正弦。）
static func lake_shore_scale(angle: float) -> float:
	return 1.0 - lake_harmonic(angle)


## 给定角度的湖岸点（世界 XZ）。
static func lake_shore_point(angle: float) -> Vector2:
	var scale := lake_shore_scale(angle)
	return LAKE_CENTER + Vector2(cos(angle) * LAKE_RADII.x, sin(angle) * LAKE_RADII.y) * scale


## 湖心小岛的边缘距离（1.0 = 岛岸，< 1 = 岛上；纯视觉，不参与寻路 / 碰撞）。
static func island_distance(p: Vector2) -> float:
	var q := (p - LAKE_ISLAND_CENTER) / LAKE_ISLAND_RADII
	var angle := atan2(q.y, q.x)
	return q.length() + island_harmonic(angle)


static func island_harmonic(angle: float) -> float:
	return 0.10 * sin(angle * 3.0 + 1.1) + 0.06 * sin(angle * 5.0 - 0.4)


static func island_shore_scale(angle: float) -> float:
	return 1.0 - island_harmonic(angle)


## 小岛岸线点（世界 XZ）。
static func island_shore_point(angle: float) -> Vector2:
	var scale := island_shore_scale(angle)
	return LAKE_ISLAND_CENTER + Vector2(cos(angle) * LAKE_ISLAND_RADII.x,
		sin(angle) * LAKE_ISLAND_RADII.y) * scale


## 第 i 股落水的顶端点（世界 XZ，唇口略向北收 0.12m 塞进岩檐下）。
static func waterfall_strand_top(i: int) -> Vector2:
	var entry: Array = WATERFALL_STRANDS[clampi(i, 0, WATERFALL_STRANDS.size() - 1)]
	return Vector2(WATERFALL_LIP.x + float(entry[0]), WATERFALL_LIP.y - 0.12)


## 第 i 股落水的落水点（世界 XZ = 潭内）。
static func waterfall_strand_landing(i: int) -> Vector2:
	var entry: Array = WATERFALL_STRANDS[clampi(i, 0, WATERFALL_STRANDS.size() - 1)]
	return Vector2(WATERFALL_BASE.x + float(entry[0]), WATERFALL_BASE.y)



static func road_distance(p: Vector2) -> float:
	var main_road := minf(absf(p.x - road_center_x(p.y)), absf(p.y - road_center_z(p.x)))
	return minf(main_road, trail_distance(p) + 0.8)


## 十字主路「南北向道路」在纵坐标 y 处的中心线 x（出城后随距离缓慢弯曲）。
static func road_center_x(y: float) -> float:
	return sin(y * 0.065) * smoothstep(18.0, 36.0, absf(y)) * 5.0


## 十字主路「东西向道路」在横坐标 x 处的中心线 z。
static func road_center_z(x: float) -> float:
	return sin(x * 0.07) * smoothstep(18.0, 36.0, absf(x)) * 4.0


## 四条道路尽头的离城距离：贴着地图边缘（MAP_HALF=128）但留出列队纵深，
## 保证 A* 128×128 格覆盖内且出生点可被吸附到可走格。
const ROAD_END_INSET: float = 121.0


## 四条道路的尽头（index：0=南 1=东 2=北 3=西）——道路延伸到地图边缘的出口，
## 夜潮怪物从这里成批涌出（v20）。
## v40 方位与其余系统统一：方位名按小地图罗盘（-Z=北、+X=东、+Z=南、-X=西）。
## 返回值为中心线坐标（Vector2 = x,z）。
static func road_end(index: int) -> Vector2:
	match index % 4:
		0: return Vector2(road_center_x(ROAD_END_INSET), ROAD_END_INSET)
		1: return Vector2(ROAD_END_INSET, road_center_z(ROAD_END_INSET))
		2: return Vector2(road_center_x(-ROAD_END_INSET), -ROAD_END_INSET)
		_: return Vector2(-ROAD_END_INSET, road_center_z(-ROAD_END_INSET))


## 道路尽头的方位名（播报用）。v40 与小地图罗盘对齐：-Z=北、+X=东、+Z=南、-X=西。
static func road_end_name(index: int) -> String:
	match index % 4:
		0: return "南"
		1: return "东"
		2: return "北"
		_: return "西"


## v44 城门内侧点（世界 XZ）：沿该方向道路中线，从城沿向城内退 inset 米。
## index 与 road_end / road_end_name 同口径：0=南(+Z) 1=东(+X) 2=北(-Z) 3=西(-X)。
## inset 取 2~4m 时点已落在城内；夜防阵列以它为「靠城门一侧」的基准。
static func gate_inside_point(index: int, inset: float = 2.5) -> Vector2:
	var d: float = CITY_HALF - maxf(0.5, inset)
	match index % 4:
		0: return Vector2(road_center_x(d), d)
		1: return Vector2(d, road_center_z(d))
		2: return Vector2(road_center_x(-d), -d)
		_: return Vector2(-d, road_center_z(-d))


## v44 城门朝外方向（单位向量，世界 XZ 平面）：夜防阵列用它判断「前排靠城门」
## 与士兵站定后的朝向（近战前排面朝城外）。
static func gate_outward_dir(index: int) -> Vector3:
	match index % 4:
		0: return Vector3(0.0, 0.0, 1.0)    # 南
		1: return Vector3(1.0, 0.0, 0.0)    # 东
		2: return Vector3(0.0, 0.0, -1.0)   # 北
		_: return Vector3(-1.0, 0.0, 0.0)   # 西


## v44 城门内侧切向（与朝外方向垂直，XZ 平面）：阵列横向排布轴。
static func gate_lateral_dir(index: int) -> Vector3:
	var out := gate_outward_dir(index)
	return Vector3(-out.z, 0.0, out.x)


## 夜潮集结点（v40）：地图扩到 256m 后道路尽头在 ±121m，若夜潮从尽头出发，
## 3.5m/s 的掠夺者要走 35~45 秒，而一夜只有 50 游戏秒——首波还没摸到城墙天就亮了。
## 因此夜潮（含头目）在「老地图边缘距离」的 62m 处集结：观感仍是城外大路压过来，
## 夜战节奏与 v39 一致。方向名仍按同一条道路（road_end_name）。
const NIGHT_WAVE_INSET: float = 62.0


static func night_wave_origin(index: int) -> Vector2:
	match index % 4:
		0: return Vector2(road_center_x(NIGHT_WAVE_INSET), NIGHT_WAVE_INSET)
		1: return Vector2(NIGHT_WAVE_INSET, road_center_z(NIGHT_WAVE_INSET))
		2: return Vector2(road_center_x(-NIGHT_WAVE_INSET), -NIGHT_WAVE_INSET)
		_: return Vector2(-NIGHT_WAVE_INSET, road_center_z(-NIGHT_WAVE_INSET))


## 到最近小径折线的距离（米）。
static func trail_distance(p: Vector2) -> float:
	var distance := INF
	for segment in TRAIL_SEGMENTS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var t := clampf((p - a).dot(b - a) / maxf(a.distance_squared_to(b), 0.0001), 0.0, 1.0)
		distance = minf(distance, p.distance_to(a.lerp(b, t)))
	return distance


## 旧地标避让（营地 / 废墟 / 采石场）＋ 主题区域地标核心区（v40）。
static func is_landmark(p: Vector2, margin: float = 0.0) -> bool:
	return p.distance_to(CAMP) < 5.0 + margin or p.distance_to(RUINS) < 6.0 + margin \
		or p.distance_to(QUARRY) < 6.0 + margin \
		or WorldRegions.landmark_clearance(p, margin)


## 把世界几何写进地面 / 水面材质。湖水 / 河水 / 潭水 / 瀑布立面共用同一份 uniform，
## 各网格只靠 ws_region_cut（0 全部 / 1 仅湖 / 2 仅河 / 3 仅潭）与 ws_phase 区分职责。
## v40：地面 shader 另外读 region_*（主题区域染色）与 trail_*（小径网）两组定长数组。
static func apply_shader_parameters(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter("lake_center", LAKE_CENTER)
	material.set_shader_parameter("lake_radii", LAKE_RADII)
	material.set_shader_parameter("map_half", MAP_HALF)
	if material.shader != null and material.shader.resource_path.ends_with("ground.gdshader") and not material.shader.resource_path.ends_with("water_ground.gdshader"):
		material.set_shader_parameter("city_half", CITY_HALF)
	# 河流：折线 + 逐点半宽（shader 侧数组定长 7，未用段用 river_seg 截断）
	var pts: Array[Vector2] = RIVER_PTS.duplicate()
	while pts.size() < 7:
		pts.append(RIVER_PTS[RIVER_PTS.size() - 1])
	var widths: Array[float] = RIVER_HALF.duplicate()
	while widths.size() < 7:
		widths.append(RIVER_HALF[RIVER_HALF.size() - 1])
	material.set_shader_parameter("river_pts", pts)
	material.set_shader_parameter("river_w", widths)
	material.set_shader_parameter("river_seg", RIVER_PTS.size() - 1)
	# 瀑布 / 水潭
	material.set_shader_parameter("ws_waterfall_a", WATERFALL_LIP)
	material.set_shader_parameter("ws_waterfall_b", WATERFALL_BASE)
	material.set_shader_parameter("ws_waterfall_len", WATERFALL_LIP.distance_to(WATERFALL_BASE))
	material.set_shader_parameter("ws_waterfall_width", WATERFALL_WIDTH)
	material.set_shader_parameter("ws_pool_center", POOL_CENTER)
	material.set_shader_parameter("ws_pool_radii", POOL_RADII)
	material.set_shader_parameter("ws_pool_depth", POOL_DEPTH)
	# v43 湖心小岛（纯视觉挖洞 / 浅滩环）与多股落水（白沫环、涟漪中心）
	material.set_shader_parameter("lake_island_center", LAKE_ISLAND_CENTER)
	material.set_shader_parameter("lake_island_radii", LAKE_ISLAND_RADII)
	var strand_dx := PackedFloat32Array()
	var strand_flow := PackedFloat32Array()
	for entry: Array in WATERFALL_STRANDS:
		strand_dx.append(float(entry[0]))
		strand_flow.append(float(entry[3]))
	material.set_shader_parameter("ws_strand_dx", strand_dx)
	material.set_shader_parameter("ws_strand_flow", strand_flow)
	material.set_shader_parameter("ws_strand_count", strand_dx.size())
	# v40 主题区域染色（跳过王城：城内保持原草色）
	var region_centers: Array[Vector2] = []
	var region_radii: Array[float] = []
	var region_colors: Array[Color] = []
	var region_strengths: Array[float] = []
	var region_landmarks: Array[Vector2] = []
	for region in WorldRegions.all():
		if region["kind"] == WorldRegions.KIND_CITY:
			continue
		var center: Vector2 = region["center"]
		var landmark: Vector2 = region["landmark"]
		region_centers.append(center)
		region_radii.append(float(region["radius"]))
		region_colors.append(region["ground"])
		region_strengths.append(float(region["tint"]))
		region_landmarks.append(landmark)
	var region_count := region_centers.size()
	while region_centers.size() < SHADER_REGION_MAX:
		region_centers.append(Vector2.ZERO)
		region_radii.append(1.0)
		region_colors.append(Color(0.0, 0.0, 0.0, 1.0))
		region_strengths.append(0.0)
		region_landmarks.append(Vector2.ZERO)
	material.set_shader_parameter("region_center", region_centers)
	material.set_shader_parameter("region_radius", region_radii)
	material.set_shader_parameter("region_color", region_colors)
	material.set_shader_parameter("region_strength", region_strengths)
	material.set_shader_parameter("region_landmark", region_landmarks)
	material.set_shader_parameter("region_count", region_count)
	# v40 小径网（旧地标 + 探索小径统一走 uniform，shader 不再各写一套折线常量）
	var trail_a: Array[Vector2] = []
	var trail_b: Array[Vector2] = []
	for segment in TRAIL_SEGMENTS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		trail_a.append(a)
		trail_b.append(b)
	var trail_count := trail_a.size()
	while trail_a.size() < SHADER_TRAIL_MAX:
		trail_a.append(Vector2.ZERO)
		trail_b.append(Vector2.ZERO)
	material.set_shader_parameter("trail_a", trail_a)
	material.set_shader_parameter("trail_b", trail_b)
	material.set_shader_parameter("trail_seg", trail_count)


## 给水面材质设定「负责哪一片水」。
## region: 0 全部 / 1 仅湖 / 2 仅河 / 3 仅潭。
static func set_water_region(material: ShaderMaterial, region: int) -> void:
	if material == null:
		return
	material.set_shader_parameter("ws_region_cut", float(region))
