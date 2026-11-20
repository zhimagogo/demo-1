class_name BuildSystem
extends Node3D
## 建造系统：选建筑 → 半透明预览吸附网格 → 左键放置 / R 旋转 / Esc·右键取消。
## v7 第三人称改造：
## - 操控模式下用准星（屏幕中心）投射地面网格，放置点距主角 ≤ BUILD_RANGE 才合法；
## - B 键开关建造模式（默认选中第一个建筑），建造中数字键 1~6 直接切换建筑；
## - 建造与第三人称操控共存（enter_build_mode 不再退出操控模式；若从战术俯瞰
##   进入建造则自动切回第三人称，统一「准星放置」手感）。
## - 战术俯瞰（RTS）模式保留原鼠标投射 + 点击菜单流程。

const BUILD_RANGE: float = 20.0   # 第三人称放置距离上限（准星落点距主角）

var grid: GridSystem
var city: CitySystem
var current_def: BuildingDef
var preview: BuildingPreview
var current_rotation: int = 0
var is_building: bool = false
var _road_painting: bool = false
var _last_road_cell := Vector2i(-9999, -9999)
var _stroke_cells: Dictionary = {}


func _ready() -> void:
	add_to_group("build_system")
	grid = get_parent().get_node_or_null("GridSystem")
	city = get_parent().get_node_or_null("CitySystem")
	EventBus.building_removed.connect(_on_building_removed)
	preview = BuildingPreview.new()
	preview.name = "Preview"
	add_child(preview)
	preview.hide_preview()


func enter_build_mode(def: BuildingDef) -> void:
	if def == null:
		return
	end_road_stroke()
	current_def = def
	current_rotation = 0
	is_building = true
	SelectionManager.build_mode_active = true
	# 建造与第三人称操控共存；战术俯瞰下进入建造 → 自动切回第三人称（准星放置）
	if not SelectionManager.hero_mode_active:
		var hc := get_tree().get_first_node_in_group("hero_controller") as HeroController
		if hc != null:
			hc.enter_hero_mode()
	preview.setup(def)
	EventBus.build_mode_entered.emit(def)
	# v17 去冗余：不再发「建造模式：xxx」日志——BuildMenu 标题栏同文同款提示
	# （「建造模式中：xxx · 准星对地左键放置 / R 旋转 / B·Esc 取消」）常驻可见，日志留给事件。


func exit_build_mode() -> void:
	end_road_stroke()
	if not is_building:
		return
	is_building = false
	current_def = null
	SelectionManager.build_mode_active = false
	preview.hide_preview()
	EventBus.build_mode_exited.emit()


func _unhandled_input(event: InputEvent) -> void:
	# 模态（Esc 菜单 / 招募菜单 / 入驻提示）或游戏结算期间不响应建造快捷键
	if SelectionManager.ui_modal_count > 0 or GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	# B 键：开关建造模式（默认第一个建筑；已在建造中则退出）
	if event.is_action_pressed("build_menu"):
		if is_building:
			exit_build_mode()
		else:
			var defs := GameDefs.building_defs()
			if not defs.is_empty():
				enter_build_mode(defs[0])
		get_viewport().set_input_as_handled()
		return
	# 数字键 1~6：任意时刻直接进入/切换对应建筑的建造模式（v8：不必先按 B；
	# 旧版 1/2/3 是调速键，与「选建筑」直觉冲突，调速已挪到 - / =）
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = event.physical_keycode - KEY_1
		if idx >= 0 and idx <= 5:
			var defs := GameDefs.building_defs()
			if idx < defs.size():
				# v37：已达数量上限的建筑（酒馆 / 龙园）不再进入建造模式——否则会掉进
				# 「左键放着放不下、又因建造模式不触发普攻」的死模式；这里只提示不切换。
				var def: BuildingDef = defs[idx]
				if build_limit_reached(def):
					EventBus.game_message.emit(build_limit_message(def), Color.ORANGE_RED)
					AudioManager.play_sfx(&"build_error")
				else:
					enter_build_mode(def)
			get_viewport().set_input_as_handled()
			return
	if not is_building:
		return
	if event.is_action_pressed("cancel"):
		exit_build_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_building"):
		current_rotation = (current_rotation + 1) % 4
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if current_def != null and current_def.is_road:
			begin_road_stroke(_aim_ground())
		else:
			try_place()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		exit_build_mode()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if get_tree().paused or TimeManager.time_scale <= 0.0 or SelectionManager.ui_modal_count > 0 or GameManager.phase == GameManager.Phase.GAME_OVER:
		end_road_stroke()
		return
	if not is_building or current_def == null:
		return
	var ground := _aim_ground()
	if ground == Vector3.INF:
		return
	var cell := grid.world_to_grid(ground)
	if _road_painting:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered == null or hovered.mouse_filter != Control.MOUSE_FILTER_STOP:
			paint_road_to(ground)
		else:
			_last_road_cell = Vector2i(-9999, -9999)
	var footprint := _rotated_footprint(current_def.footprint, current_rotation)
	var valid: bool = grid.is_inside(cell) and _can_place_footprint(cell, footprint) \
		and _footprint_in_city(cell, footprint) and ResourceManager.can_afford(current_def.cost) \
		and _within_build_range(ground) and not build_limit_reached(current_def)
	preview.global_position = grid.grid_to_world(cell) + _footprint_center_offset(footprint)
	preview.set_rotation_steps(current_rotation)   # 预览朝向随 R 键旋转，与放置后一致
	preview.set_valid(valid)
	if current_def.is_road:
		preview.set_road_connections(grid.road_connection_mask(cell))


## 松键即结束笔画，即使鼠标已移到 UI 上也不能漏掉释放事件。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		end_road_stroke()


func begin_road_stroke(ground: Vector3) -> void:
	end_road_stroke()
	if current_def == null or not current_def.is_road or ground == Vector3.INF:
		return
	_road_painting = true
	paint_road_to(ground)


## 四连通补格：快速拖过多个格子仍有连续路面，同一笔画重复经过不重复扣费。
func paint_road_to(ground: Vector3) -> void:
	if not _road_painting or current_def == null or not current_def.is_road or ground == Vector3.INF:
		return
	if TimeManager.time_scale <= 0.0 or SelectionManager.ui_modal_count > 0:
		end_road_stroke()
		return
	var target := grid.world_to_grid(ground)
	if not grid.is_inside(target) or not _footprint_in_city(target, Vector2i.ONE) or not _within_build_range(ground):
		_last_road_cell = Vector2i(-9999, -9999)
		return
	var point := target if _last_road_cell.x == -9999 else _last_road_cell
	while true:
		if not _stroke_cells.has(point):
			_stroke_cells[point] = true
			if not grid.has_road(point):
				try_place_at(grid.grid_to_world(point))
		if point == target:
			break
		var diff := target - point
		if absi(diff.x) >= absi(diff.y) and diff.x != 0:
			point.x += signi(diff.x)
		else:
			point.y += signi(diff.y)
	_last_road_cell = target


func end_road_stroke() -> void:
	_road_painting = false
	_last_road_cell = Vector2i(-9999, -9999)
	_stroke_cells.clear()


# ---- v37 数量上限（酒馆 / 龙园全场唯一）----

## 该建筑是否已达 max_count 上限。判定口径 = 场上存活实例数（BuildingDef.max_count ≤ 0 = 不限量），
## 建筑被拆后实时释放、可原地重建。预览着色、放置拦截、BuildMenu 卡片置灰统一走此处。
func build_limit_reached(def: BuildingDef) -> bool:
	return GameDefs.building_at_limit(get_tree(), def)


## 已达上限时的可读文案（放置拒绝 / 提示音共用）。
func build_limit_message(def: BuildingDef) -> String:
	if def == null:
		return "此处无法建造"
	return "「%s」全场只能建造 %d 座（已达上限）" % [def.display_name, def.max_count]


## 当前瞄准的地面点：操控模式 = 准星（屏幕中心）投影；战术俯瞰 = 鼠标位置投影。
## 无有效相机时返回 Vector3.INF（本帧不更新预览）。
func _aim_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam is IsometricCamera:
		return (cam as IsometricCamera).screen_to_ground(get_viewport().get_mouse_position())
	if cam is ThirdPersonCamera:
		var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
		return (cam as ThirdPersonCamera).screen_to_ground(center)
	return Vector3.INF


## 第三人称放置距离限制：准星落点（XZ）距主角不得超过 BUILD_RANGE。
## 战术俯瞰模式不做限制（全图放置，原行为）。
func _within_build_range(ground: Vector3) -> bool:
	if not SelectionManager.hero_mode_active:
		return true
	var hero: Node3D = null
	for u in get_tree().get_nodes_in_group("player_unit"):
		if u is Hero:
			hero = u
			break
	if hero == null:
		return true
	var flat := ground - hero.global_position
	flat.y = 0.0
	return flat.length() <= BUILD_RANGE


func try_place() -> void:
	var ground := _aim_ground()
	if ground == Vector3.INF:
		return
	try_place_at(ground)


## 世界位置入口，鼠标放置和场景回归共用全部占地、费用与事件逻辑。
## v37：数量上限（BuildingDef.max_count）在扣费**之前**判定——超限不扣钱、只提示。
func try_place_at(ground: Vector3) -> void:
	if current_def == null or grid == null:
		return
	if build_limit_reached(current_def):
		EventBus.game_message.emit(build_limit_message(current_def), Color.ORANGE_RED)
		AudioManager.play_sfx(&"build_error")
		VFXManager.spawn_effect(&"hit_ring", ground + Vector3(0.0, 0.3, 0.0), 0.0,
			{"color": Color(1.0, 0.42, 0.32)})
		return
	var cell := grid.world_to_grid(ground)
	if current_def.is_road and grid.has_road(cell):
		return
	var footprint := _rotated_footprint(current_def.footprint, current_rotation)
	var in_city := _footprint_in_city(cell, footprint)
	if not grid.is_inside(cell) or not _can_place_footprint(cell, footprint) or not in_city:
		EventBus.game_message.emit("只能在主城内建造" if not in_city else "此处无法建造", Color.ORANGE_RED)
		AudioManager.play_sfx(&"build_error")
		return
	if not _within_build_range(ground):
		EventBus.game_message.emit("太远了——走近一点再放置", Color.ORANGE_RED)
		AudioManager.play_sfx(&"build_error")
		return
	if not ResourceManager.pay(current_def.cost):
		AudioManager.play_sfx(&"build_error")
		return
	var b := Building.new()
	b.def = current_def
	# 多格占地：放在占地正中心而非左上格中心，使 2×2 房屋正压在 4 格正中（1×1 偏移为 0，行为不变）。
	b.position = grid.grid_to_world(cell) + _footprint_center_offset(footprint)
	# 应用建造旋转（绕 Y 轴 0/90/180/270°）：模型与碰撞盒随之转向，与预览朝向一致。
	# 1×1 占地建筑旋转后仍在本格内（墙薄板转 90° 即横向变纵向）。
	b.rotation = Vector3.ZERO if current_def.is_road else Vector3(0.0, deg_to_rad(current_rotation * 90.0), 0.0)
	b.cell = cell
	b.footprint = footprint
	var buildings := get_parent().get_node_or_null("Buildings")
	if buildings:
		buildings.add_child(b)
	else:
		get_parent().add_child(b)
	grid.place(cell, footprint, b)
	EventBus.building_placed.emit(b, cell)
	AudioManager.play_sfx(&"build_place", b.global_position)
	if current_def.is_road:
		return
	# v27：落成表现——地基尘土炸开 + 暗金冲击环（旧版 8 颗火星完全没有「建成了」的仪式感）
	VFXManager.spawn_effect(&"build_dust", b.global_position + Vector3(0.0, 0.8, 0.0), 0.0,
		{"amount": 16, "lifetime": 0.55, "throttle_key": b.get_instance_id()})
	VFXManager.spawn_effect(&"hit_ring", b.global_position + Vector3(0.0, 0.3, 0.0), 0.0,
		{"color": Color(0.85, 0.72, 0.5), "throttle_key": b.get_instance_id()})


func _on_building_removed(node: Node, _cell: Vector2i) -> void:
	if node is Building and grid != null:
		grid.remove((node as Building).cell, (node as Building).footprint)


func _rotated_footprint(base: Vector2i, rotation: int) -> Vector2i:
	if rotation % 2 == 0:
		return base
	return Vector2i(base.y, base.x)


## 多格占地中心相对左上格中心的偏移：1×1 为 0；2×2 为 (cell_size/2, 0, cell_size/2)，
## 让建筑/预览正压在占地正中，而非偏向左上格。
func _footprint_center_offset(fp: Vector2i) -> Vector3:
	return Vector3((fp.x - 1) * grid.cell_size * 0.5, 0.0, (fp.y - 1) * grid.cell_size * 0.5)


## footprint（从 cell 起向 +x/+y 扩展 footprint 格）整体是否落在主城内。
## 取占地矩形的世界 AABB 最小/最大角，交 CitySystem 校验。无主城系统时不限制（兼容）。
func _footprint_in_city(cell: Vector2i, footprint: Vector2i) -> bool:
	if city == null:
		return true
	var half := Vector3(grid.cell_size * 0.5, 0.0, grid.cell_size * 0.5)
	var min_world := grid.grid_to_world(cell) - half
	var last_cell := Vector2i(cell.x + footprint.x - 1, cell.y + footprint.y - 1)
	var max_world := grid.grid_to_world(last_cell) + half
	return city.contains_rect_xz(min_world, max_world)


## 道路还需核对真实可走格，不能铺进主城地基、资源碰撞或永久水域。
func _can_place_footprint(cell: Vector2i, footprint: Vector2i) -> bool:
	if not grid.can_place(cell, footprint):
		return false
	if current_def != null and current_def.is_road:
		var nav := get_tree().get_first_node_in_group("nav_system") as NavSystem
		return nav == null or nav.is_walkable_cell(cell)
	return true
