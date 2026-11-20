class_name WorldRegions
extends RefCounted
## ============================================================================
## 世界主题区域数据（v40 · 256×256 米世界）
## ============================================================================
## 这里是区域「唯一真相」：名称 / 故事 / 圆心半径 / 地面配色 / 地标点 / 散布风格。
## 读取方（改动本文件即可同步全链路）：
##   · WorldLayout.apply_shader_parameters → 地面区域染色（region_* uniforms）
##   · WorldLayout.is_landmark           → 植被避让区域地标核心区
##   · DecorationScatter                 → 分区域植被与地表小装饰
##   · ThemedRegions                     → 区域地标道具（风车 / 矿坑 / 断旗 / 祭坛 …）
##   · Minimap                           → 区域色块与名字
##   · RegionTracker                     → 进入区域时的发现播报与故事文本
##
## 方位约定（与小地图罗盘一致）：-Z = 北，+X = 东，+Z = 南，-X = 西。
## 注意：旧版 road_end_name 把 +Z 叫「北」与小地图相反，v40 已统一为 -Z = 北。
## 六个主题区域都放在旧地图（±64m）之外的扩张环带上，主城与旧地标位置保持不变。
## ============================================================================

const KIND_CITY := &"city"
const KIND_FROST := &"frost"
const KIND_MINE := &"mine"
const KIND_WHEAT := &"wheat"
const KIND_BATTLE := &"battle"
const KIND_FOREST := &"forest"
const KIND_SWAMP := &"swamp"

## 王城：不算「主题区域」（不参与地面染色 / 植被改造），只用于区域播报与小地图标签。
const CITY := {
	"id": &"city",
	"name": "王城 · 最后一座城",
	"subtitle": "王国最后的灯火，四面八方的流民都往这里走。",
	"center": Vector2(0.0, 0.0),
	"radius": 28.0,   # v43：王城 52×52m → 区域播报 / 小地图标签半径 24→28
	"kind": KIND_CITY,
	"ground": Color(0.36, 0.48, 0.25, 1.0),
	"tint": 0.0,
	"accent": Color(0.95, 0.80, 0.25, 1.0),
	"lore": "城墙上的火把一夜不熄。有人说，只要这座城还亮着，王国就不算亡。",
	"landmark": Vector2(0.0, 0.0),
}

## 六个主题区域。字段说明：
##   id        稳定标识（存档 / 播报 / 测试用，不要改名）
##   name      进入区域时 HUD 横幅显示的名字
##   subtitle  一句话风味文案（横幅副标题）
##   center    区域圆心（世界 XZ，米）
##   radius    影响半径（地面染色 / 植被密度 / 发现判定共用）
##   kind      区域类型（散布与地标构建器按它分支）
##   ground    地面草地染色目标色（与 ground.gdshader 的 grass 混色）
##   tint      染色强度 0~1（越大越压过原本草色）
##   accent    强调色（小地图 / 地标灯光 / 粒子）
##   lore      首次踏入时的故事文本（消息日志）
##   landmark  地标核心点：植被在此 8m 内避让，ThemedRegions 在此造主地标
const REGIONS: Array[Dictionary] = [
	{
		"id": &"frostfall",
		"name": "北境 · 霜语瀑布",
		"subtitle": "瀑布终年不冻，水声像有人在低声念着旧日的名字。",
		"center": Vector2(44.0, -60.0),
		"radius": 24.0,
		"kind": KIND_FROST,
		"ground": Color(0.52, 0.68, 0.78, 1.0),
		"tint": 0.72,
		"accent": Color(0.70, 0.90, 1.00, 1.0),
		"lore": "据说王国最后一位霜语者把自己的名字溶进了这条河。潭水终年泛着冰蓝的光；旅人若在水边喊出故人的名字，回声会慢半拍——那是霜语者在替你应答。",
		"landmark": Vector2(33.0, -50.0),
	},
	{
		"id": &"starfall",
		"name": "东北 · 星落矿坑",
		"subtitle": "坠星砸开的矿脉，铁里裹着不会熄灭的紫光。",
		"center": Vector2(94.0, -84.0),
		"radius": 30.0,
		"kind": KIND_MINE,
		"ground": Color(0.40, 0.35, 0.48, 1.0),
		"tint": 0.78,
		"accent": Color(0.74, 0.58, 1.00, 1.0),
		"lore": "三百年前一颗星落在东岭，砸出这口深坑。矿工挖出的铁矿石夜里会自己发光，打成的剑锋利得能切开月光。矿脉枯了以后，坑底仍夜夜响起敲石声。",
		"landmark": Vector2(94.0, -84.0),
	},
	{
		"id": &"windwheat",
		"name": "东境 · 风吟麦海",
		"subtitle": "旧王国的粮仓，风车至今还在转。",
		"center": Vector2(94.0, 4.0),
		"radius": 30.0,
		"kind": KIND_WHEAT,
		"ground": Color(0.76, 0.62, 0.26, 1.0),
		"tint": 0.70,
		"accent": Color(1.00, 0.84, 0.44, 1.0),
		"lore": "王国尚在时，这里的麦子能养活十座城。如今农人散了，风车却没人敢停——老人们说，风车停下的那天，最后一批守粮人的魂就会迷路。",
		"landmark": Vector2(94.0, 4.0),
	},
	{
		"id": &"embersworn",
		"name": "南境 · 烬誓战场",
		"subtitle": "断旗、焦土与不肯散去的余烬。",
		"center": Vector2(4.0, 96.0),
		"radius": 30.0,
		"kind": KIND_BATTLE,
		"ground": Color(0.43, 0.32, 0.24, 1.0),
		"tint": 0.74,
		"accent": Color(1.00, 0.44, 0.26, 1.0),
		"lore": "「烬誓之战」打了七天七夜。败军把军旗折断插进土里，发誓来世再战。焦土至今不长麦子，只长一种红得像炭的花。夜里能听见铁器相击，走近却只有风。",
		"landmark": Vector2(4.0, 96.0),
	},
	{
		"id": &"mistwood",
		"name": "西境 · 雾隐密林",
		"subtitle": "树比人记得更久，雾里全是旧名字。",
		"center": Vector2(-94.0, -4.0),
		"radius": 30.0,
		"kind": KIND_FOREST,
		"ground": Color(0.19, 0.34, 0.18, 1.0),
		"tint": 0.68,
		"accent": Color(0.52, 0.92, 0.64, 1.0),
		"lore": "密林里的树会记住每个进入者的名字。樵夫带走了斧头，带不走的是挂在枝头低声回响的呼唤。林心有一座苔封的石祭坛，供着无名的树灵。",
		"landmark": Vector2(-94.0, -4.0),
	},
	{
		"id": &"salthollow",
		"name": "西南 · 盐风沼地",
		"subtitle": "干涸的古湖床，枯树与盐壳之间的路会自己走。",
		"center": Vector2(-86.0, 86.0),
		"radius": 30.0,
		"kind": KIND_SWAMP,
		"ground": Color(0.33, 0.40, 0.33, 1.0),
		"tint": 0.74,
		"accent": Color(0.60, 0.92, 0.78, 1.0),
		"lore": "古湖干涸后留下一片盐壳与枯树。传说盐风里裹着一支商队的名字：谁在沼地里听见驼铃，循声走去，就会走上三百年前的旧商道——再也没回来。",
		"landmark": Vector2(-86.0, 86.0),
	},
]


## 全部主题区域（不含王城）。返回的是 const 字典，调用方**只读**，不要改写。
static func all() -> Array[Dictionary]:
	return REGIONS


static func count() -> int:
	return REGIONS.size()


## 按 id 取区域；未找到返回 {}。
static func find(id: StringName) -> Dictionary:
	for region in REGIONS:
		if region["id"] == id:
			return region
	if id == CITY["id"]:
		return CITY
	return {}


## 点所在的区域（含王城）；都不在则返回 {}。
## 重叠区域取「离圆心最近」的一个（霜语瀑布与湖泊北岸有轻微交叠）。
static func region_at(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_ratio := INF
	for region in REGIONS:
		var radius: float = region["radius"]
		var center: Vector2 = region["center"]
		var ratio := pos.distance_to(center) / maxf(radius, 0.01)
		if ratio <= 1.0 and ratio < best_ratio:
			best = region
			best_ratio = ratio
	if not best.is_empty():
		return best
	var city_center: Vector2 = CITY["center"]
	if pos.distance_to(city_center) <= float(CITY["radius"]):
		return CITY
	return {}


## 区域类型；不在主题区域内（含王城）返回 &"meadow"（默认草原散布）。
static func biome_at(pos: Vector2) -> StringName:
	var region := region_at(pos)
	if region.is_empty():
		return &"meadow"
	return region["kind"]


## 地标核心区：区域地标 / 小地标附近，植被散布必须避让，防止树石压住道具。
## v40.1：8 → 11m。地标道具群（麦田/矿箱/断旗/沉船）外缘可到 ~11m，
## 8m 净空时仍会出现树冠压麦田、树干穿残墙；11m 与 ThemedRegions 的 8m 摆位净空叠加后
## 实际植被避让约 12.5m（DecorationScatter 另留 1.5m 余量）。
static func landmark_clearance(pos: Vector2, margin: float = 0.0) -> bool:
	for region in REGIONS:
		var landmark: Vector2 = region["landmark"]
		if pos.distance_to(landmark) < 11.0 + margin:
			return true
	return false


## 区域内的「归一化距离」：0 = 圆心，1 = 边缘，>1 = 圈外。
static func normalized_distance(pos: Vector2, region: Dictionary) -> float:
	if region.is_empty():
		return INF
	var center: Vector2 = region["center"]
	return pos.distance_to(center) / maxf(float(region["radius"]), 0.01)


## 小地图 / 播报用：进入某点会看到的地名（主题区域 > 王城 > 空串）。
static func display_name_at(pos: Vector2) -> String:
	var region := region_at(pos)
	return "" if region.is_empty() else String(region["name"])
