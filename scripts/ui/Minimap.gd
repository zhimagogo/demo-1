class_name Minimap
extends PanelContainer
## 小地图（v6 图标化）：右下角战场态势图。
## **随相机朝向旋转**（Q/E 转视角时地图同步转）， rim 上有「北」方位标（compass 图标，
## 缺图回退「N」）——保证「屏幕上方 = 小地图上方」永远一致（v3.0 固定北向上，而默认
## 相机其实是旋转 90° 的（屏幕上方=西），两者差 90° 就是朝向 bug 的根源）。
## 纯 2D 绘制：湖泊 / 城区 / 资源点 / 建筑 / 单位 / 敌我 / 相机视野框 + 暗金边框角饰。
## 左键点按 / 拖动 → 联动主镜头跳转（映射含旋转变换的逆）。

const MAP_PX: float = 176.0            # 地图画布边长（面板 = 画布 + 主题内边距×2）
const UPDATE_HZ: float = 12.0
const CORNER_LEN: float = 15.0         # 四角金色角饰的臂长
# v40 主题区域层：色块透明度 / 当前区域名小字字号（≤9，铭牌内显示）
const REGION_FILL_ALPHA: float = 0.14
const REGION_LABEL_FONT_SIZE: int = 9

var _canvas: Control
var _dragging: bool = false
var _accum: float = 0.0
var _pulse: float = 0.0
var _rot: float = 0.0                  # 当前地图旋转角（弧度，= 相机 yaw；y-down 下正值=顺时针）
var _center: Vector2 = Vector2.ZERO    # 画布中心


func _ready() -> void:
	# 布局（v3.1 修复）：面板总尺寸 = 画布 176 + 主题内边距 10×2 = 196，锚点区间必须 ≥ 该值
	const PANEL_PAD: float = 10.0
	var panel_size: float = MAP_PX + PANEL_PAD * 2.0
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -(panel_size + 12.0)
	offset_top = -(panel_size + 12.0)
	offset_right = -12.0
	offset_bottom = -12.0
	custom_minimum_size = Vector2(panel_size, panel_size)

	# 暗金边框：内边距与主题一致（10），保证画布尺寸与朝向数学完全不受本次美化影响
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.11, 0.09, 0.07, 0.95)
	frame.border_color = UIStyle.BORDER_GOLD
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(6)
	frame.set_content_margin_all(int(PANEL_PAD))
	add_theme_stylebox_override("panel", frame)

	# 左上角铭牌底板样式（缓存一次，绘制期复用）
	_plate_style = StyleBoxFlat.new()
	_plate_style.bg_color = Color(0.10, 0.09, 0.07, 0.85)
	_plate_style.border_color = Color(0.62, 0.50, 0.28, 0.9)
	_plate_style.set_border_width_all(1)
	_plate_style.set_corner_radius_all(4)

	_center = Vector2(MAP_PX * 0.5, MAP_PX * 0.5)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	_canvas.clip_contents = true          # 越界绘制（视野框钳制点等）裁掉，不溢出面板
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)


func _process(delta: float) -> void:
	_accum += delta
	_pulse += delta
	if _accum >= 1.0 / UPDATE_HZ:
		_accum = 0.0
		_refresh_rotation()
		_canvas.queue_redraw()
	if _dragging:
		_focus_to_mouse()


## 相机朝向 → 地图旋转角。相机 yaw=0（正北朝上）时地图不转；Q/E 每 90° 同步转。
func _refresh_rotation() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var yaw_deg: float = cam.global_rotation_degrees.y
	_rot = deg_to_rad(yaw_deg)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_refresh_rotation()
			_focus_to_mouse()
			AudioManager.play_sfx(&"ui_click")
	elif event is InputEventMouseMotion and _dragging:
		_focus_to_mouse()


func _focus_to_mouse() -> void:
	# 只在战术俯瞰下拉镜头：主控模式下镜头属于主角（第三人称跟随 / 俯视角跟随），
	# 小地图点击若改 _focus 会被跟随逻辑拉回，产生「扯一下又弹回」的抖动
	if SelectionManager.view_mode != SelectionManager.ViewMode.TACTICAL:
		return
	var cam := get_viewport().get_camera_3d() as IsometricCamera
	if cam == null:
		return
	var local := _canvas.get_local_mouse_position()
	var world := _px_to_world(local)
	cam.focus_on(Vector3(world.x, 0.0, world.y))
	cam.follow_target = null


# ---- 坐标换算（含旋转变换）----

## 世界坐标 → 未旋转地图坐标（北在上）。
func _world_to_map_base(p: Vector2) -> Vector2:
	return Vector2(
		(p.x + WorldLayout.MAP_HALF) / (WorldLayout.MAP_HALF * 2.0) * MAP_PX,
		(p.y + WorldLayout.MAP_HALF) / (WorldLayout.MAP_HALF * 2.0) * MAP_PX)


## 地图坐标 → 世界坐标（未旋转）。
func _map_base_to_world(p: Vector2) -> Vector2:
	return Vector2(
		p.x / MAP_PX * WorldLayout.MAP_HALF * 2.0 - WorldLayout.MAP_HALF,
		p.y / MAP_PX * WorldLayout.MAP_HALF * 2.0 - WorldLayout.MAP_HALF)


## 世界 → 旋转后的地图点（绘制用）：先北向映射，再绕中心转 _rot（屏幕上=顺时针）。
func _w2m(p: Vector2) -> Vector2:
	return (_world_to_map_base(p) - _center).rotated(_rot) + _center


## 旋转后的地图点 → 世界（点击用）：逆旋转。
func _px_to_world(p: Vector2) -> Vector2:
	var base := (p - _center).rotated(-_rot) + _center
	return _map_base_to_world(base)


# ---- 绘制 ----

func _draw_map() -> void:
	var c := _canvas
	# 底色：草地（旋转步进 90°，方形底永远铺满）
	c.draw_rect(Rect2(0, 0, MAP_PX, MAP_PX), Color(0.16, 0.22, 0.12, 0.9))
	# v40 六个主题区域：半透明色块 + accent 细描边 + 中心圆点（画在底图与湖泊/城区之间）
	_draw_regions(c)
	# 湖泊：同一条湖岸曲线（近似椭圆 + 顶点扰动）
	var lake_c := _w2m(WorldLayout.LAKE_CENTER)
	var lake_r := Vector2(
		WorldLayout.LAKE_RADII.x / (WorldLayout.MAP_HALF * 2.0) * MAP_PX,
		WorldLayout.LAKE_RADII.y / (WorldLayout.MAP_HALF * 2.0) * MAP_PX)
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		var wob := WorldLayout.lake_shore_scale(a)
		pts.append(lake_c + (Vector2(cos(a), sin(a)) * lake_r * wob).rotated(_rot))
	c.draw_colored_polygon(pts, Color(0.16, 0.32, 0.4, 0.95))
	# 城区：半透明方框（旋转后按四角多边形画）
	var city_min := Vector2(-WorldLayout.CITY_HALF, -WorldLayout.CITY_HALF)
	var city_max := Vector2(WorldLayout.CITY_HALF, WorldLayout.CITY_HALF)
	var city_pts := PackedVector2Array([
		_w2m(city_min), _w2m(Vector2(city_max.x, city_min.y)),
		_w2m(city_max), _w2m(Vector2(city_min.x, city_max.y))])
	c.draw_colored_polygon(city_pts, Color(0.75, 0.68, 0.42, 0.10))
	c.draw_polyline(PackedVector2Array([city_pts[0], city_pts[1], city_pts[2], city_pts[3], city_pts[0]]),
		Color(0.8, 0.72, 0.45, 0.35), 1.0)
	# 城外保留探索主路，城内只显示玩家实际铺出的道路。
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		c.draw_line(_w2m(direction * WorldLayout.CITY_HALF), _w2m(direction * WorldLayout.MAP_HALF),
			Color(0.5, 0.42, 0.28, 0.4), 1.5)
	for road in get_tree().get_nodes_in_group("road"):
		if not is_instance_valid(road) or road.is_queued_for_deletion():
			continue
		var point := Vector2(road.global_position.x, road.global_position.z)
		var road_color := Color(0.66, 0.48, 0.28, 0.95)
		c.draw_circle(_w2m(point), 0.85, road_color)
		for i in GridSystem.ROAD_NEIGHBORS.size():
			if road.road_connections & (1 << i):
				var offset := Vector2(GridSystem.ROAD_NEIGHBORS[i])
				c.draw_line(_w2m(point), _w2m(point + offset), road_color, 1.4)

	# 资源点
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var p := _w2m(Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z))
		var is_wood: bool = (n as Node).get("yield_resource") == &"wood"
		c.draw_circle(p, 1.6, Color(0.3, 0.62, 0.3) if is_wood else Color(0.55, 0.55, 0.58))

	# 建筑
	for b in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b) or not (b is Node3D):
			continue
		var p := _w2m(Vector2((b as Node3D).global_position.x, (b as Node3D).global_position.z))
		var bdef = (b as Node).get("def")
		var col := UIStyle.building_accent(bdef.id if bdef != null else &"")
		c.draw_rect(Rect2(p - Vector2(2.4, 2.4), Vector2(4.8, 4.8)), col)

	# 主城：金色星点
	var base_px := _w2m(Vector2.ZERO)
	c.draw_circle(base_px, 3.6, Color(1.0, 0.85, 0.3))
	c.draw_circle(base_px, 1.6, Color(0.6, 0.45, 0.1))

	# 单位（敌我）
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var p := _w2m(Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z))
		var is_boss: bool = (e as Node).get("def") != null and (e as Node).def.is_boss
		if is_boss:
			var pulse: float = 3.6 + 1.4 * sin(_pulse * 6.0)
			c.draw_circle(p, pulse, Color(1.0, 0.25, 0.35, 0.55))
			c.draw_circle(p, 3.0, Color(1.0, 0.3, 0.4))
		else:
			c.draw_circle(p, 2.2, Color(0.95, 0.35, 0.3))
	for u in get_tree().get_nodes_in_group("player_unit"):
		if not is_instance_valid(u) or not (u is Node3D):
			continue
		var p := _w2m(Vector2((u as Node3D).global_position.x, (u as Node3D).global_position.z))
		if u is Hero:
			# 主角：金色菱形
			var d := PackedVector2Array([p + Vector2(0, -4.2), p + Vector2(3.4, 0), p + Vector2(0, 4.2), p + Vector2(-3.4, 0)])
			c.draw_colored_polygon(d, Color(1.0, 0.88, 0.35))
		elif u is Colonist:
			c.draw_circle(p, 1.8, Color(0.9, 0.92, 0.95))
		elif u is Soldier:
			c.draw_circle(p, 2.2, Color(0.42, 0.62, 0.95))

	# 相机视野框：闭合四边形 + 极淡填充（v3.1 修复：旧版漏了闭合边 → 画成三条边的开口梯形；
	# 且按「到原点距离」径向钳制，相机移到地图角落时白框被错误拉向原点变形）
	var view_corners := get_view_corners_map()
	if view_corners.size() == 5:
		c.draw_colored_polygon(view_corners, Color(1.0, 1.0, 1.0, 0.05))
		c.draw_polyline(view_corners, Color(1.0, 1.0, 1.0, 0.5), 1.2)

	# 夜色罩纱（夜里地图整体压暗，氛围一致）
	if TimeManager.hour >= 20 or TimeManager.hour < 6:
		c.draw_rect(Rect2(0, 0, MAP_PX, MAP_PX), Color(0.05, 0.05, 0.15, 0.35))

	# v40 当前区域名（小字铭牌；压在夜色罩纱之上，保证夜里也读得清）
	_draw_region_label(c)

	# 暗金角饰：四角 L 形描边 + 一圈内衬细线（先画，内容压在上面不影响判读）
	_draw_corner_ornaments(c)

	# 「北」方位标：位于旋转后的正北方向 rim 上（金色小三角 + rosette）
	# rosette 用 compass 真图标（随地图一起旋转，图标自身「上」= 地图正北）；缺图回退「N」。
	var north_dir := Vector2(0, -1).rotated(_rot)
	var rim: Vector2 = _center + north_dir * (MAP_PX * 0.5 - 7.0)
	var tri := PackedVector2Array([
		rim + north_dir * 4.0,
		rim + north_dir.rotated(2.2) * 3.0,
		rim + north_dir.rotated(-2.2) * 3.0])
	c.draw_colored_polygon(tri, Color(1.0, 0.88, 0.35))
	var rose_c: Vector2 = rim - north_dir * 7.5
	c.draw_circle(rose_c, 8.0, Color(0.1, 0.09, 0.07, 0.9))
	c.draw_arc(rose_c, 8.0, 0.0, TAU, 28, Color(0.62, 0.50, 0.28, 0.9), 1.0, true)
	var compass_tex := IconDB.get_texture(&"compass")
	if compass_tex != null:
		c.draw_set_transform(rose_c, _rot, Vector2.ONE)
		c.draw_texture_rect(compass_tex, Rect2(Vector2(-6.0, -6.0), Vector2(12.0, 12.0)), false,
			Color(1.0, 0.88, 0.35))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		if _font == null:
			_font = UIStyle.make_font()
		c.draw_string(_font, rose_c - Vector2(3.5, -4.0), "N",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 0.88, 0.35))

	# 左上角「地图」小铭牌：map 图标（缺图则整块不画，不留空底板）
	var map_tex := IconDB.get_texture(&"map")
	if map_tex != null:
		c.draw_style_box(_plate_style, Rect2(4.0, 4.0, 22.0, 20.0))
		c.draw_texture_rect(map_tex, Rect2(8.0, 7.0, 14.0, 14.0), false, Color(1.0, 0.88, 0.35, 0.9))


## 四角金饰 + 内衬细线：纯装饰，不参与任何坐标 / 命中判定。
func _draw_corner_ornaments(c: Control) -> void:
	var inset := 4.0
	var col := Color(0.93, 0.78, 0.38, 0.55)
	var far := MAP_PX - inset
	var corners := [
		[Vector2(inset, inset + CORNER_LEN), Vector2(inset, inset), Vector2(inset + CORNER_LEN, inset)],
		[Vector2(far - CORNER_LEN, inset), Vector2(far, inset), Vector2(far, inset + CORNER_LEN)],
		[Vector2(far, far - CORNER_LEN), Vector2(far, far), Vector2(far - CORNER_LEN, far)],
		[Vector2(inset + CORNER_LEN, far), Vector2(inset, far), Vector2(inset, far - CORNER_LEN)],
	]
	for pts in corners:
		c.draw_polyline(PackedVector2Array(pts), col, 2.0)
	c.draw_rect(Rect2(inset - 1.0, inset - 1.0, MAP_PX - inset * 2.0 + 2.0, MAP_PX - inset * 2.0 + 2.0),
		Color(0.62, 0.50, 0.28, 0.35), false, 1.0)


# ---- v40 主题区域层（数据源：scripts/defs/WorldRegions.gd）----

## 六个区域的半透明色块 + 强调色描边 + 中心圆点。圆形随地图旋转不变，
## 只需把圆心做 _w2m 变换；半径按「世界米 → 地图像素」换算（与湖泊/城区同一比例）。
func _draw_regions(c: Control) -> void:
	var px_per_m: float = MAP_PX / (WorldLayout.MAP_HALF * 2.0)
	for region in WorldRegions.all():
		var center: Vector2 = region["center"]
		var radius_px: float = float(region["radius"]) * px_per_m
		var center_px := _w2m(center)
		var ground: Color = region["ground"]
		var accent: Color = region["accent"]
		c.draw_circle(center_px, radius_px, Color(ground.r, ground.g, ground.b, REGION_FILL_ALPHA))
		c.draw_arc(center_px, radius_px, 0.0, TAU, 28, Color(accent.r, accent.g, accent.b, 0.5), 1.0, true)
		c.draw_circle(center_px, 1.8, Color(accent.r, accent.g, accent.b, 0.85))


## 当前相机/主角所在区域的地名（小字铭牌 + 强调色圆点）。
## 发现状态由 RegionTracker（独立工作线）提供；它尚未落地时视为全部已发现。
func _draw_region_label(c: Control) -> void:
	var region := _current_region()
	if region.is_empty() or not _region_discovered(region):
		return
	if _font == null:
		_font = UIStyle.make_font()
	var text := String(region["name"])
	var accent: Color = region["accent"]
	var text_w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_LABEL_FONT_SIZE).x
	var box := Rect2(4.0, 44.0, text_w + 22.0, 14.0)
	c.draw_style_box(_plate_style, box)
	c.draw_circle(Vector2(box.position.x + 7.0, box.position.y + 7.0), 2.2, Color(accent.r, accent.g, accent.b, 0.9))
	c.draw_string(_font, Vector2(box.position.x + 13.0, box.position.y + 10.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, REGION_LABEL_FONT_SIZE, Color(0.93, 0.86, 0.68, 0.95))


## 当前观察点所在的区域：战术俯瞰看相机焦点，其余模式看主角（相机在主角身后几米）。
func _current_region() -> Dictionary:
	return WorldRegions.region_at(_current_world_xz())


func _current_world_xz() -> Vector2:
	if SelectionManager.view_mode != SelectionManager.ViewMode.TACTICAL:
		for n in get_tree().get_nodes_in_group("player_unit"):
			if not is_instance_valid(n) or not (n is Hero):
				continue
			var hero := n as Node3D
			if hero != null:
				return Vector2(hero.global_position.x, hero.global_position.z)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.ZERO
	return Vector2(cam.global_position.x, cam.global_position.z)


## 区域是否已发现：RegionTracker 提供 is_discovered(id) 时按它过滤，否则全部显示。
func _region_discovered(region: Dictionary) -> bool:
	var tracker := get_tree().get_first_node_in_group("region_tracker")
	if tracker == null:
		return true
	if tracker.has_method("is_discovered"):
		return bool(tracker.call("is_discovered", region["id"]))
	return true


# 字体类型用 Font 基类：UIStyle.make_font() 已改为返回 Font（OFL 开源中文字体落地后仍是 Font），
# 只有图标缺失、回退画「N」字标时才会用到。
var _font: Font = null
var _plate_style: StyleBoxFlat = null

## 相机可见地面四角 → 旋转后的地图坐标（闭合五点：首尾相同）。
## 钳制策略：按地图 AABB 逐轴钳（±MAP_HALF-1），而非径向钳——
## 相机在地图任意位置（含角落）视野框都保持完整四边形，越界部分贴地图边缘。
## 供绘制与 MinimapOrientation 回归测试共用同一份数学。
func get_view_corners_map() -> PackedVector2Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return PackedVector2Array()
	var vp_size := get_viewport().get_visible_rect().size
	var out := PackedVector2Array()
	for corner in [Vector2(0, 0), Vector2(vp_size.x, 0), Vector2(vp_size.x, vp_size.y), Vector2(0, vp_size.y)]:
		var g: Vector3 = cam.screen_to_ground(corner)
		var flat := Vector2(g.x, g.z)
		var m := WorldLayout.MAP_HALF - 1.0
		flat.x = clampf(flat.x, -m, m)
		flat.y = clampf(flat.y, -m, m)
		out.append(_w2m(flat))
	if out.size() == 4:
		out.append(out[0])   # 闭合：draw_polyline 不自动回接首点
	return out
