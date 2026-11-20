extends Node3D
## ============================================================================
## LevelSelect3D —— 3D 关卡选择地图（v39 远征界面）。
## 冷青底色、五座微缩岛屿、奶油色道路与正对镜头的关卡标签。
## WASD 自由走位；点击目标沿烘焙可走域执行 A*，桥头检查整格净空。
## 地图几何与导航共用岛轮廓及道路采样，界面单独使用 CampaignStyle。
##
## 对外契约（回归测试用）：
##   · signal level_entered(id)     真正进入一关时发出（切场景之前）；
##   · selected_id / refresh() / select_level(id) / try_enter_selected() / enter_level(id)；
##   · player_position / flag_world_position(id) / teleport_player(to)；
##   · 暂未开放的关卡可选中查看，但**绝不切场景**（只弹 Toast）。
##
## ★ 场景树只声明根节点 + 脚本，其余全部代码构建（工程范式）。
## ============================================================================

signal level_entered(id: StringName)

# ============================================================================
# 文案与路径
# ============================================================================

const BACK_SCENE := "res://scenes/main/MainMenu.tscn"
const LOCKED_TOAST := "该关卡暂未开放，敬请期待"
const ENTER_TEXT := "启程　→"
const LOCKED_TEXT := "暂 未 开 放"
const BACK_TEXT := "返回主页"
const TITLE_TEXT := "复国之路"
const HINT_ENTER := "按 E 进入关卡"
const HINT_LOCKED := "暂未开放 · 敬请期待"
const HINT_IDLE := "WASD 移动 · 左键点击地面走位 · 走到旗子旁选关"
const TOAST_HOLD := 1.6
const TOAST_FADE := 0.4

# ============================================================================
# 地图尺寸与几何（世界单位 = 米）
# ============================================================================

const MAP_SIZE := Vector2(40.0, 26.0)     # 归一化 0~1 映射到这么大的一块地
const ISLAND_DEPTH := 1.35                 # 板状岩体厚度（顶面 y=0 → 侧壁下沉）
const ISLAND_SIDE_GROW := 1.015           # 侧壁略微外扩，厚度在四周都露得出来
const ISLAND_SHADOW_Y := -1.55             # 最下面一层淡黑影（浮空感）
const ISLAND_SHADOW_GROW := 1.06
const ROAD_Y := 0.02
const ROAD_HALF_WIDTH := 0.72             # 道路可见半宽（米）
const ROAD_EDGE := 0.11                   # 道路两侧的暗色描边宽度（压出「路肩」）
const ROAD_WALK_RADIUS := ROAD_HALF_WIDTH + 0.5   # 可走半宽（= 可见宽度 + 网格腐蚀的一圈）
const ROAD_SAMPLES := 16                  # 每段控制点的 Catmull-Rom 采样数
const ROAD_STRIDE := 3                    # 可走判定用的道路点抽稀步长

# ---- 可行走网格 ----
const GRID_STEP := 0.5                    # 世界米
const GRID_MARGIN := 2.0                  # 地图外扩，避免边界特判
const GRID_EDGE_ERODE := true             # 腐蚀一圈（≈0.5m），角色不会贴到岛缘

# ---- 装饰撒点（与 2D 版同种子同规则）----
const DECO_SEED := 20261016
const DECO_MIN_DIST := 0.020              # 装饰之间最小归一化间距
const DECO_NODE_CLEAR := 0.058            # 旗子节点周围留空半径
const DECO_EDGE_MARGIN := 0.012           # 装饰离岛缘的最小归一化距离

# ============================================================================
# 配色（v38 关卡地图美术基准色板）
# ============================================================================

const BG_COLOR := Color(0.086, 0.157, 0.184)        # 冷青地图底色

const ROAD_COLOR := Color(0.949, 0.918, 0.839)      # #f2ead6 奶油色

const TREE_DARK := Color(0.259, 0.427, 0.243)       # 深橄榄
const TREE_LIGHT := Color(0.353, 0.549, 0.290)
const TREE_TRUNK := Color(0.286, 0.224, 0.161)
const ROCK_LIGHT := Color(0.561, 0.584, 0.611)
const ROCK_DARK := Color(0.373, 0.400, 0.435)
const COIN_GOLD := Color(0.969, 0.890, 0.361)       # #f7e35c
const COIN_EDGE := Color(0.706, 0.541, 0.129)
const ICE_LIGHT := Color(0.812, 0.878, 0.949)
const ICE_DARK := Color(0.639, 0.745, 0.878)
const HOUSE_WALL := Color(0.851, 0.690, 0.443)      # #d9b071 沙色
const HOUSE_ROOF := Color(0.753, 0.314, 0.227)      # #c0503a 红顶

# ============================================================================
# 相机与角色
# ============================================================================

const CAM_PITCH_DEG := 57.0          # 固定斜俯视俯角（等距感，无滚转）
const CAM_FOV := 34.0
const CAM_DIST_FAR := 58.0           # 默认：整张地图尽收眼底
const CAM_DIST_NEAR := 24.0          # 可选近距离推镜（滚轮）
const CAM_FOLLOW_SPEED := 5.0
const CAM_ZOOM_STEP := 3.0

## 主光方向（与 _setup_light 的 SunLight 朝向一致，用于侧壁烘焙光照）。
const LIGHT_DIR := Vector3(0.379, -0.788, -0.485)
const LIGHT_SIDE_MAX := 0.62         # 侧壁最大受光量（水平法线时的上限）

const HERO_MODEL := "res://assets/_PLACEHOLDER/characters/placeholder_hero.glb"
const HERO_HEIGHT := 1.5             # 模型统一缩放到这个身高（米）
const WALK_SPEED := 5.6
const SPRINT_SCALE := 1.7
const TURN_SPEED := 12.0
const NEAR_RADIUS := 3.5             # 进入这个距离 = 「走到旗子旁」
const FLAG_STOP_DIST := 2.5          # 点旗子时停在旗前多远
const ARRIVE_EPS := 0.04

## 动画名候选（glTF 导入器会剥 _loop 后缀，单名字会静默落空，必须给候选数组）。
const ANIM_CANDIDATES := {
	&"idle": ["Idle", "Unarmed_Idle", "2H_Melee_Idle"],
	&"walk": ["Walking_A", "Walking_B", "Walking_C", "Walk"],
	&"run": ["Running_A", "Running_B", "Running"],
}

# ---- 面板排版参数 ----
const PANEL_MARGIN := 28.0
const PANEL_PAD := 22.0
const FS_CHAPTER := 12
const FS_TITLE := 30
const FS_BODY := 13
const FS_STAR := 20

# ============================================================================
# 对外状态
# ============================================================================

## 当前选中的关卡 id（暂未开放的关卡也可以选中——只是不能进入）。
var selected_id: StringName = &""
## 角色当前位置（每帧同步，测试会读）。
var player_position: Vector3 = Vector3.ZERO

# ---- 场景节点 ----
var _camera: Camera3D = null
var _map_root: Node3D = null
var _island_root: Node3D = null
var _decor_root: Node3D = null
var _flag_root: Node3D = null
var _player: CharacterBody3D = null
var _visual: Node3D = null
var _anim_player: AnimationPlayer = null
var _anim_kind: StringName = &""
var _ui_layer: CanvasLayer = null
var _ui_root: Control = null

# ---- UI ----
var _theme: Theme = null
var _font: Font = null
var top_bar: Control = null
var title_label: Label = null
var total_stars_label: Label = null
var info_panel: Panel = null
var info_chapter_label: Label = null
var info_title_label: Label = null
var info_subtitle_label: Label = null
var info_desc_label: Label = null
var objectives_box: VBoxContainer = null
var star_hints_box: VBoxContainer = null
var star_row: HBoxContainer = null
var start_button: Button = null
var back_button: Button = null
var toast_label: Label = null
var hint_label: Label = null

var _info_divider: Control = null
var _info_dim: ColorRect = null
var _toast_tween: Tween = null

# ---- 地图数据 ----
var _island_polys: Array[PackedVector2Array] = []          # 每座岛顶面多边形（世界 XZ）
var _island_regions: Array[StringName] = []
var _road_paths: Array[PackedVector2Array] = []
var _road_points: PackedVector2Array = PackedVector2Array()  # 道路采样点（世界 XZ，抽稀过）
var _walkable := PackedByteArray()
var _grid_size := Vector2i.ZERO
var _grid_origin := Vector2.ZERO
var _decor_count := 0
var _flags: Dictionary = {}                                # StringName -> LevelFlag3D

# ---- 角色状态 ----
var _map_astar := AStarGrid2D.new()
var _walk_path := PackedVector2Array()
var _path_index := 0
var _map_caption: Label
var _route_caption: Label

var _move_target := Vector2(INF, INF)                      # 点击走位目标（世界 XZ）
var _facing := Vector2(0.0, 1.0)
var _near_id: StringName = &""

# ---- 相机状态 ----
var _cam_focus := Vector3.ZERO
var _cam_dist := CAM_DIST_FAR
var _cam_dist_target := CAM_DIST_FAR


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	_theme = CampaignStyle.theme()
	_font = CampaignStyle.font()

	_setup_environment()
	_setup_light()
	_setup_camera()
	_build_map()
	_build_flags()
	_build_player()
	_build_ui()

	var initial := LevelRuntime.selected_id
	if LevelCatalog.get_level(initial) == null:
		initial = LevelCatalog.PROLOGUE_ID
	selected_id = initial
	refresh()

	# 角色初始站在（当前选中那关的）旗子旁 —— 一进场就是「已走到旗子边」的状态
	teleport_player(flag_world_position(selected_id) + Vector3(1.5, 0.0, 1.5))
	_layout_ui()
	call_deferred("_layout_ui")
	_cam_focus = Vector3.ZERO
	_apply_camera(1.0)
	LevelRuntime.progress_changed.connect(_on_progress_changed)
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_layout_ui)


func _process(delta: float) -> void:
	_update_player(delta)
	player_position = _player.global_position if _player != null else Vector3.ZERO
	_update_proximity()
	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		try_enter_selected()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _point_on_ui(mb.position):
				return
			get_viewport().set_input_as_handled()
			_on_ground_clicked(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(-CAM_ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(CAM_ZOOM_STEP)


# ============================================================================
# 世界：环境 / 灯光 / 相机
# ============================================================================

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.sky = null
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.78, 0.88)
	env.ambient_light_energy = 0.65
	env.ssao_enabled = false          # 小地图以干净色块与方向投影建立层次
	env.ssr_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)   # 从左上打
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.light_angular_distance = 1.0                          # 小物件投影落在岛面与道路上
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(-24.0, 152.0, 0.0)  # 背侧补光，别让北墙死黑
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(sun)
	add_child(fill)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = CAM_FOV
	_camera.near = 1.0
	_camera.far = 400.0
	add_child(_camera)
	_camera.current = true
	_camera.h_offset = -3.8


# ============================================================================
# 地图：岛屿 / 道路 / 装饰
# ============================================================================

func _build_map() -> void:
	_map_root = Node3D.new()
	_map_root.name = "MapRoot"
	add_child(_map_root)
	_island_root = Node3D.new()
	_island_root.name = "Islands"
	_map_root.add_child(_island_root)
	_decor_root = Node3D.new()
	_decor_root.name = "Decor"
	_map_root.add_child(_decor_root)

	for island in _island_defs():
		_build_island(island)
	_build_roads()
	_build_decor()
	_build_walk_grid()
	_build_landmark()


func _build_landmark() -> void:
	var root := Node3D.new()
	root.name = "HomeKeep"
	root.position = _map_point(Vector2(0.47, 0.435))
	_map_root.add_child(root)
	var wall_mat := _flat_mat(Color("eee2bd"))
	var roof_mat := _flat_mat(Color("426778"))
	var keep := BoxMesh.new()
	keep.size = Vector3(1.5, 1.4, 1.25)
	_add_mesh(root, keep, Vector3(0, 0.7, 0), wall_mat)
	for x in [-0.85, 0.85]:
		for z in [-0.65, 0.65]:
			var xf: float = x
			var zf: float = z
			var tower := CylinderMesh.new()
			tower.top_radius = 0.32
			tower.bottom_radius = 0.35
			tower.height = 1.8
			tower.radial_segments = 6
			_add_mesh(root, tower, Vector3(xf, 0.9, zf), wall_mat)
			var roof := CylinderMesh.new()
			roof.top_radius = 0
			roof.bottom_radius = 0.48
			roof.height = 0.65
			roof.radial_segments = 6
			_add_mesh(root, roof, Vector3(xf, 2.1, zf), roof_mat)


func _build_island(island: Dictionary) -> void:
	var region: StringName = island["region"]
	var poly := _to_packed(island["points"])
	var world_poly := PackedVector2Array()
	for p in poly:
		world_poly.append(_to_world2(p))
	_island_polys.append(world_poly)
	_island_regions.append(region)

	var node := Node3D.new()
	node.name = "Island_" + String(region)
	_island_root.add_child(node)

	var c_top: Color = island["top"]
	var c_side: Color = island["side"]

	# ① 顶面（y=0，平涂 = 色板原色）
	var top_mi := MeshInstance3D.new()
	top_mi.name = "Top"
	top_mi.mesh = _polygon_mesh(world_poly, 0.0, Vector3.UP)
	top_mi.material_override = _flat_mat(c_top)
	node.add_child(top_mi)

	# ② 下沉的板状侧壁（顶面略外扩一点点，厚度在左右下缘都露得出来）
	var grown := _grow_poly(world_poly, ISLAND_SIDE_GROW)
	var side_mi := MeshInstance3D.new()
	side_mi.name = "Side"
	side_mi.mesh = _prism_sides(grown, 0.0, -ISLAND_DEPTH, c_side)
	side_mi.material_override = _vertex_color_mat()
	node.add_child(side_mi)

	# ③ 更下面一层淡黑影（浮空感）
	var shadow_mi := MeshInstance3D.new()
	shadow_mi.name = "ShadowPlate"
	shadow_mi.mesh = _polygon_mesh(_grow_poly(world_poly, ISLAND_SHADOW_GROW),
		ISLAND_SHADOW_Y, Vector3.UP)
	shadow_mi.material_override = _alpha_mat(Color(0.02, 0.03, 0.05, 0.35))
	node.add_child(shadow_mi)


## 奶油色道路：沿 Catmull-Rom 采样生成扁平条带（y=0.02），并缓存可走判定用的中心点。
func _build_roads() -> void:
	for road in _road_defs():
		var ctrl := PackedVector2Array()
		for p in road:
			var pv: Vector2 = p
			ctrl.append(_to_world2(pv))
		var pts := _smooth(ctrl, ROAD_SAMPLES)
		_road_paths.append(pts)
		_road_points.append(pts[0])
		var i := ROAD_STRIDE
		while i < pts.size():
			_road_points.append(pts[i])
			i += ROAD_STRIDE
		_road_points.append(pts[pts.size() - 1])

	# 道路画两层：先一层略宽的暗色「路肩」（低一点），再铺奶油色路面
	var edge_mesh := _road_mesh(ROAD_HALF_WIDTH + ROAD_EDGE, ROAD_Y - 0.008)
	if edge_mesh != null:
		var edge_mi := MeshInstance3D.new()
		edge_mi.name = "RoadEdge"
		edge_mi.mesh = edge_mesh
		edge_mi.material_override = _flat_mat(ROAD_COLOR.darkened(0.18))
		_map_root.add_child(edge_mi)
	var mesh := _road_mesh(ROAD_HALF_WIDTH, ROAD_Y)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Roads"
	mi.mesh = mesh
	mi.material_override = _flat_mat(ROAD_COLOR)
	_map_root.add_child(mi)


func _road_mesh(half_width: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for road in _road_defs():
		var ctrl := PackedVector2Array()
		for p in road:
			var pv: Vector2 = p
			ctrl.append(_to_world2(pv))
		_road_strip(st, _smooth(ctrl, ROAD_SAMPLES), half_width, y)
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh


## 把一条折线铺成三角带（y 略高于岛面的扁平条带）。
## ★ 每个采样点只算一对左右顶点（切线取前后两段的平均 = 斜接），
##   这样条带是连续的，不会在弯道外侧出现空隙（空隙会透出岛面/背景，看着像「掉点」）。
func _road_strip(st: SurfaceTool, pts: PackedVector2Array, half_width: float, y: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var prev := pts[maxi(i - 1, 0)]
		var next := pts[mini(i + 1, n - 1)]
		var tangent := next - prev
		if tangent.length_squared() < 0.000001:
			tangent = Vector2(0.0, 1.0)
		var side := Vector2(-tangent.y, tangent.x).normalized() * half_width
		left.append(pts[i] + side)
		right.append(pts[i] - side)
	for i in n - 1:
		_quad(st,
			Vector3(left[i].x, y, left[i].y),
			Vector3(left[i + 1].x, y, left[i + 1].y),
			Vector3(right[i + 1].x, y, right[i + 1].y),
			Vector3(right[i].x, y, right[i].y))


## 岛面装饰（固定种子撒点，只算一次）：树 / 岩 / 金币 / 冰棱 / 木屋。
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DECO_SEED
	var spec := _decor_spec()
	var nodes: Array = []
	for level in LevelCatalog.all():
		nodes.append(level.map_pos)
	var placed: Array = []
	for island in _island_defs():
		var region: StringName = island["region"]
		if not spec.has(region):
			continue
		var poly := _to_packed(island["points"])
		var quota: Dictionary = spec[region]
		for kind in quota:
			var want: int = quota[kind]
			var done := 0
			var guard := 0
			while done < want and guard < want * 80:
				guard += 1
				var p := _random_in_polygon(rng, poly)
				if p.x < 0.0:
					break
				if _too_close(p, placed, DECO_MIN_DIST):
					continue
				if _near_nodes(p, nodes, DECO_NODE_CLEAR):
					continue
				placed.append({"kind": kind, "pos": p, "variant": rng.randf()})
				done += 1
	for item in placed:
		_place_decor(item)
		_decor_count += 1


func _place_decor(item: Dictionary) -> void:
	var kind := StringName(item["kind"])
	var pos_n: Vector2 = item["pos"]
	var variant: float = item["variant"]
	var at := _to_world2(pos_n)
	var node := Node3D.new()
	node.name = "Deco_" + String(kind)
	node.position = Vector3(at.x, 0.0, at.y)
	node.rotation.y = variant * TAU
	_decor_root.add_child(node)

	var s := 0.86 + variant * 0.32
	match kind:
		&"tree":
			_build_tree(node, s)
		&"rock":
			_build_rock(node, s)
		&"coin":
			_build_coin(node, s)
		&"ice":
			_build_ice(node, s)
		_:
			_build_house(node, s)


## 针叶树：三层层叠圆锥（深橄榄 + 顶部亮侧）+ 树干。
func _build_tree(node: Node3D, s: float) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.08 * s
	trunk.bottom_radius = 0.10 * s
	trunk.height = 0.42 * s
	trunk.radial_segments = 6
	_add_mesh(node, trunk, Vector3(0.0, 0.21 * s, 0.0), _flat_mat(TREE_TRUNK))

	var tiers := [
		{"r": 0.46, "h": 0.72, "y": 0.36},
		{"r": 0.36, "h": 0.62, "y": 0.78},
		{"r": 0.25, "h": 0.52, "y": 1.16},
	]
	for i in tiers.size():
		var tier: Dictionary = tiers[i]
		var r: float = tier["r"] * s
		var h: float = tier["h"] * s
		var y: float = tier["y"] * s
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = r
		cone.height = h
		cone.radial_segments = 7
		cone.rings = 1
		var tint: Color = TREE_LIGHT if i == tiers.size() - 1 else TREE_DARK
		_add_mesh(node, cone, Vector3(0.0, y + h * 0.5, 0.0), _flat_mat(tint))


## 灰岩：小棱柱（六边，底略宽），顶面提亮。
func _build_rock(node: Node3D, s: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.26 * s
	mesh.bottom_radius = 0.40 * s
	mesh.height = 0.52 * s
	mesh.radial_segments = 6
	mesh.rings = 1
	_add_mesh(node, mesh, Vector3(0.0, 0.26 * s, 0.0), _flat_mat(ROCK_LIGHT))
	var cap := CylinderMesh.new()
	cap.top_radius = 0.24 * s
	cap.bottom_radius = 0.26 * s
	cap.height = 0.06 * s
	cap.radial_segments = 6
	cap.rings = 1
	_add_mesh(node, cap, Vector3(0.0, 0.54 * s, 0.0), _flat_mat(ROCK_DARK))


## 金币：亮金细圆柱（绿岛上密）。
func _build_coin(node: Node3D, s: float) -> void:
	var edge := CylinderMesh.new()
	edge.top_radius = 0.30 * s
	edge.bottom_radius = 0.30 * s
	edge.height = 0.04 * s
	edge.radial_segments = 16
	edge.rings = 1
	_add_mesh(node, edge, Vector3(0.0, 0.02, 0.0), _flat_mat(COIN_EDGE))
	var top := CylinderMesh.new()
	top.top_radius = 0.26 * s
	top.bottom_radius = 0.26 * s
	top.height = 0.06 * s
	top.radial_segments = 16
	top.rings = 1
	var mat := _flat_mat(COIN_GOLD)
	mat.emission_enabled = true
	mat.emission = COIN_GOLD * 0.25
	_add_mesh(node, top, Vector3(0.0, 0.06, 0.0), mat)


## 雪岛冰棱：细高锥（略微倾斜）。
func _build_ice(node: Node3D, s: float) -> void:
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.17 * s
	spike.height = 1.5 * s
	spike.radial_segments = 5
	spike.rings = 1
	var mi := _add_mesh(node, spike, Vector3(0.0, 0.72 * s, 0.0), _flat_mat(ICE_LIGHT))
	mi.rotation_degrees = Vector3(4.0, 0.0, 3.0)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.0
	shade.bottom_radius = 0.11 * s
	shade.height = 0.9 * s
	shade.radial_segments = 5
	shade.rings = 1
	_add_mesh(node, shade, Vector3(0.22 * s, 0.44 * s, 0.12 * s), _flat_mat(ICE_DARK))


## 木屋：小方块 + 红锥顶（+ 深色门）。
func _build_house(node: Node3D, s: float) -> void:
	var wall := BoxMesh.new()
	wall.size = Vector3(0.78, 0.6, 0.66) * s
	_add_mesh(node, wall, Vector3(0.0, 0.3 * s, 0.0), _flat_mat(HOUSE_WALL))
	var roof := CylinderMesh.new()
	roof.top_radius = 0.0
	roof.bottom_radius = 0.62 * s
	roof.height = 0.44 * s
	roof.radial_segments = 4
	roof.rings = 1
	var roof_mi := _add_mesh(node, roof, Vector3(0.0, 0.82 * s, 0.0), _flat_mat(HOUSE_ROOF))
	roof_mi.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	var door := BoxMesh.new()
	door.size = Vector3(0.2, 0.3, 0.06) * s
	_add_mesh(node, door, Vector3(0.0, 0.15 * s, -0.35 * s), _flat_mat(Color(0.325, 0.251, 0.180)))


# ============================================================================
# 可行走网格（岛屿多边形 ∪ 道路条带，生成时烘焙）
# ============================================================================

func _build_walk_grid() -> void:
	_grid_origin = Vector2(-MAP_SIZE.x * 0.5 - GRID_MARGIN, -MAP_SIZE.y * 0.5 - GRID_MARGIN)
	_grid_size = Vector2i(
		int(ceil((MAP_SIZE.x + GRID_MARGIN * 2.0) / GRID_STEP)) + 1,
		int(ceil((MAP_SIZE.y + GRID_MARGIN * 2.0) / GRID_STEP)) + 1)
	var raw := PackedByteArray()
	raw.resize(_grid_size.x * _grid_size.y)
	for gz in _grid_size.y:
		for gx in _grid_size.x:
			var p := _cell_center(gx, gz)
			var safe := _is_walkable_exact(p)
			# 多边形与曲线桥头的并集可能在半格内凹入；核对整格，避免中心可走但格内有缝。
			if safe:
				for direction in [Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1), Vector2(-1,0), Vector2(1,0), Vector2(-1,1), Vector2(0,1), Vector2(1,1)]:
					var offset: Vector2 = direction
					if not _is_walkable_exact(p + offset * GRID_STEP * 0.48):
						safe = false
						break
			raw[gz * _grid_size.x + gx] = 1 if safe else 0

	_walkable = raw.duplicate()
	if GRID_EDGE_ERODE:
		for gz in _grid_size.y:
			for gx in _grid_size.x:
				var idx := gz * _grid_size.x + gx
				if raw[idx] == 0:
					continue
				var keep := true
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var off: Vector2i = d
					var nx := gx + off.x
					var nz := gz + off.y
					if nx < 0 or nz < 0 or nx >= _grid_size.x or nz >= _grid_size.y:
						keep = false
						break
					if raw[nz * _grid_size.x + nx] == 0:
						keep = false
						break
				_walkable[idx] = 1 if keep else 0

	# 兜底：旗子落点附近强制可走（哪怕地缘侵蚀把它啃掉了）
	for level in LevelCatalog.all():
		_force_walkable(Vector2(_map_point(level.map_pos).x, _map_point(level.map_pos).z))

	_map_astar.region = Rect2i(Vector2i.ZERO, _grid_size)
	_map_astar.cell_size = Vector2(GRID_STEP, GRID_STEP)
	_map_astar.offset = _grid_origin + Vector2.ONE * GRID_STEP * 0.5
	_map_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_map_astar.update()
	for gz in _grid_size.y:
		for gx in _grid_size.x:
			_map_astar.set_point_solid(Vector2i(gx, gz), _walkable[gz * _grid_size.x + gx] == 0)


## 精确可行走谓词：落在任一岛屿多边形内，或离道路中心线足够近。
func _is_walkable_exact(p: Vector2) -> bool:
	for poly in _island_polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	for road in _road_paths:
		for i in road.size() - 1:
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, road[i], road[i + 1])) <= ROAD_WALK_RADIUS * ROAD_WALK_RADIUS:
				return true
	return false


## 运行期可行走判定 = 烘焙网格查表（网格由 _is_walkable_exact 生成 + 腐蚀一圈）。
func _is_walkable(p: Vector2) -> bool:
	var gx := int(floor((p.x - _grid_origin.x) / GRID_STEP))
	var gz := int(floor((p.y - _grid_origin.y) / GRID_STEP))
	if gx < 0 or gz < 0 or gx >= _grid_size.x or gz >= _grid_size.y:
		return false
	return _walkable[gz * _grid_size.x + gx] != 0 and _is_walkable_exact(p)


## 最近的可走点（角色被夹回地图时用）。
func _nearest_walkable(p: Vector2) -> Vector2:
	if _is_walkable(p):
		return p
	var gx := clampi(int(floor((p.x - _grid_origin.x) / GRID_STEP)), 0, _grid_size.x - 1)
	var gz := clampi(int(floor((p.y - _grid_origin.y) / GRID_STEP)), 0, _grid_size.y - 1)
	var best := p
	var best_d := INF
	for r in 40:
		var found := false
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var nx := gx + dx
				var nz := gz + dz
				if nx < 0 or nz < 0 or nx >= _grid_size.x or nz >= _grid_size.y:
					continue
				if _walkable[nz * _grid_size.x + nx] == 0:
					continue
				var c := _cell_center(nx, nz)
				var d := c.distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = c
					found = true
		if found:
			return best
	return best


func _cell_center(gx: int, gz: int) -> Vector2:
	return _grid_origin + Vector2(float(gx) + 0.5, float(gz) + 0.5) * GRID_STEP


## 从某个世界点出发能走到的格子数（自检用：验证五座岛确实被道路连成一片）。
func reachable_cells(from: Vector3) -> int:
	var start := _nearest_walkable(Vector2(from.x, from.z))
	var sx := int(floor((start.x - _grid_origin.x) / GRID_STEP))
	var sz := int(floor((start.y - _grid_origin.y) / GRID_STEP))
	if sx < 0 or sz < 0 or sx >= _grid_size.x or sz >= _grid_size.y:
		return 0
	var seen := PackedByteArray()
	seen.resize(_grid_size.x * _grid_size.y)
	var queue: Array[Vector2i] = [Vector2i(sx, sz)]
	seen[sz * _grid_size.x + sx] = 1
	var count := 0
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		count += 1
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var off: Vector2i = d
			var nx := c.x + off.x
			var nz := c.y + off.y
			if nx < 0 or nz < 0 or nx >= _grid_size.x or nz >= _grid_size.y:
				continue
			var idx := nz * _grid_size.x + nx
			if seen[idx] != 0 or _walkable[idx] == 0:
				continue
			seen[idx] = 1
			queue.append(Vector2i(nx, nz))
	return count


func _force_walkable(p: Vector2) -> void:
	var gx := int(floor((p.x - _grid_origin.x) / GRID_STEP))
	var gz := int(floor((p.y - _grid_origin.y) / GRID_STEP))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var nx := gx + dx
			var nz := gz + dz
			if nx < 0 or nz < 0 or nx >= _grid_size.x or nz >= _grid_size.y:
				continue
			_walkable[nz * _grid_size.x + nx] = 1


# ============================================================================
# 旗子
# ============================================================================

func _build_flags() -> void:
	_flag_root = Node3D.new()
	_flag_root.name = "Flags"
	add_child(_flag_root)
	for level in LevelCatalog.all():
		var flag := LevelFlag3D.new()
		flag.setup(level, LevelRuntime.stars_of(level.id))
		var at := _map_point(level.map_pos)
		flag.position = at
		_flag_root.add_child(flag)
		_flags[level.id] = flag


# ============================================================================
# 角色
# ============================================================================

func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "Player"
	_player.collision_layer = 16      # layer 5 = unit（本场景不需要碰撞，占位即可）
	_player.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Body"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.1
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.55, 0.0)
	_player.add_child(shape)
	add_child(_player)

	_visual = Node3D.new()
	_visual.name = "Visual"
	_player.add_child(_visual)
	if not _load_hero_model():
		_build_fallback_figure()
	_facing = Vector2(0.0, 1.0)


## 优先实例化 KayKit 骑士占位模型；失败返回 false（由调用方退化成程序化小人）。
func _load_hero_model() -> bool:
	if not ResourceLoader.exists(HERO_MODEL):
		return false
	var res: Resource = load(HERO_MODEL)
	if not (res is PackedScene):
		return false
	var model := (res as PackedScene).instantiate() as Node3D
	if model == null:
		return false
	# 美术朝向修正：模型面朝 +Z，而逻辑前方是本地 -Z（与 PawnDef.model_face_offset_deg 一致）
	model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_visual.add_child(model)
	_fit_model(model)
	_anim_player = _find_anim_player(model)
	_play_anim(&"idle")
	return true


## 把模型整体缩放到 HERO_HEIGHT 并把脚底对齐到 y=0。
func _fit_model(model: Node3D) -> void:
	var box := _model_aabb(model)
	if box.size.y <= 0.01:
		return
	var k := HERO_HEIGHT / box.size.y
	model.scale = Vector3(k, k, k)
	model.position.y = -box.position.y * k


func _model_aabb(model: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := model.global_transform.affine_inverse()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local := (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out


func _find_anim_player(root: Node) -> AnimationPlayer:
	for child in root.find_children("*", "AnimationPlayer", true, false):
		var ap := child as AnimationPlayer
		if ap != null:
			return ap
	return null


## 退化方案：胶囊身体 + 球头 + 朝前的小鼻块（一眼能看出朝向）。
func _build_fallback_figure() -> void:
	var body := CapsuleMesh.new()
	body.radius = 0.26
	body.height = 0.92
	_add_mesh(_visual, body, Vector3(0.0, 0.52, 0.0), _flat_mat(Color(0.29, 0.44, 0.65)))
	var head := SphereMesh.new()
	head.radius = 0.22
	head.height = 0.44
	_add_mesh(_visual, head, Vector3(0.0, 1.13, 0.0), _flat_mat(Color(0.91, 0.78, 0.63)))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.12, 0.10, 0.16)
	_add_mesh(_visual, nose, Vector3(0.0, 1.13, -0.22), _flat_mat(Color(0.82, 0.68, 0.53)))


func _play_anim(kind: StringName) -> void:
	if _anim_player == null or _anim_kind == kind:
		return
	if not ANIM_CANDIDATES.has(kind):
		return
	for cand in ANIM_CANDIDATES[kind]:
		var anim_name := String(cand)
		if _anim_player.has_animation(anim_name):
			_anim_player.play(anim_name)
			_anim_kind = kind
			return


# ============================================================================
# 每帧更新：移动 / 邻近判定 / 相机
# ============================================================================

func _update_player(delta: float) -> void:
	if _player == null:
		return
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	if not _is_walkable(pos):
		pos = _nearest_walkable(pos)          # 夹回最近可走点：绝不允许站在虚空里
		_player.global_position = Vector3(pos.x, 0.0, pos.y)

	# 相机相对方向（相机无偏航，等价于世界方向；写成基底投影以免日后加偏航时出错）
	var basis := _camera.global_transform.basis
	var right := Vector2(basis.x.x, basis.x.z)
	var fwd := Vector2(-basis.z.x, -basis.z.z)
	if right.length_squared() < 0.0001 or fwd.length_squared() < 0.0001:
		right = Vector2.RIGHT
		fwd = Vector2.UP
	right = right.normalized()
	fwd = fwd.normalized()

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := WALK_SPEED
	if Input.is_action_pressed("sprint"):
		speed *= SPRINT_SCALE

	var step := Vector2.ZERO
	var dir := Vector2.ZERO
	if input.length_squared() > 0.0001:
		_walk_path.clear()
		_move_target = Vector2(INF, INF)      # 手动输入取消点击寻路
		dir = (right * input.x + fwd * (-input.y)).normalized()
		step = dir * speed * delta
	elif _move_target.x < INF:
		var to := _move_target - pos
		var dist := to.length()
		if dist <= ARRIVE_EPS:
			_path_index += 1
			_move_target = _walk_path[_path_index] if _path_index < _walk_path.size() else Vector2(INF, INF)
		else:
			dir = to / dist
			step = dir * minf(dist, speed * delta)

	if step != Vector2.ZERO:
		_move_player_step(step)

	if dir.length_squared() > 0.0001:
		_facing = dir
		var want_yaw := atan2(-dir.x, -dir.y)     # 逻辑前方 = 本地 -Z
		_player.rotation.y = lerp_angle(_player.rotation.y, want_yaw,
			1.0 - exp(-TURN_SPEED * delta))

	var moving := step != Vector2.ZERO
	if Input.is_action_pressed("sprint") and moving:
		_play_anim(&"run")
	else:
		_play_anim(&"walk" if moving else &"idle")


## 走一步：越界时先尝试单轴滑动，再不行就停下（绝不掉进虚空）。
func _move_player_step(step: Vector2) -> void:
	var cur := Vector2(_player.global_position.x, _player.global_position.z)
	var want := cur + step
	var next := cur
	if _is_walkable(want):
		next = want
	else:
		var slide_x := Vector2(want.x, cur.y)
		var slide_z := Vector2(cur.x, want.y)
		if _is_walkable(slide_x):
			next = slide_x
		elif _is_walkable(slide_z):
			next = slide_z
	_player.global_position = Vector3(next.x, 0.0, next.y)


## 邻近判定：进入某旗子 NEAR_RADIUS 内 → 高亮 + 信息面板切换 + 自动选中 + 提示条。
func _update_proximity() -> void:
	if _player == null:
		return
	var pos := Vector2(_player.global_position.x, _player.global_position.z)
	var best: StringName = &""
	var best_d := NEAR_RADIUS * NEAR_RADIUS
	for id in _flags:
		var flag: LevelFlag3D = _flags[id]
		if not is_instance_valid(flag):
			continue
		var d := Vector2(flag.position.x, flag.position.z).distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best = id
	if best == _near_id:
		_update_hint()
		return
	_near_id = best
	for id in _flags:
		var flag: LevelFlag3D = _flags[id]
		if is_instance_valid(flag):
			flag.set_near(id == _near_id)
	if _near_id != &"":
		select_level(_near_id)                # 走到旗子旁 → 自动选中该关
	_update_hint()


func _update_hint() -> void:
	if hint_label == null:
		return
	if _near_id == &"":
		hint_label.text = HINT_IDLE
		return
	var level := LevelCatalog.get_level(_near_id)
	if level == null:
		hint_label.text = HINT_IDLE
	elif level.is_playable():
		hint_label.text = "「%s」 · %s" % [level.title, HINT_ENTER]
	else:
		hint_label.text = "「%s」 · %s" % [level.title, HINT_LOCKED]


func _update_camera(delta: float) -> void:
	if _camera == null or _player == null:
		return
	var vis := _visible_extent()
	var lim_x := maxf(0.0, (MAP_SIZE.x - vis.x) * 0.5)
	var lim_z := maxf(0.0, (MAP_SIZE.y - vis.y) * 0.5)
	var want := Vector3(
		clampf(_player.global_position.x, -lim_x, lim_x),
		0.0,
		clampf(_player.global_position.z, -lim_z, lim_z))
	var k := 1.0 - exp(-CAM_FOLLOW_SPEED * delta)
	_cam_focus = _cam_focus.lerp(want, k)
	_apply_camera(1.0 - exp(-CAM_FOLLOW_SPEED * 1.4 * delta))


func _apply_camera(k: float) -> void:
	if _camera == null:
		return
	_cam_dist = lerpf(_cam_dist, _cam_dist_target, clampf(k, 0.0, 1.0))
	var pitch := deg_to_rad(CAM_PITCH_DEG)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * _cam_dist
	_camera.h_offset = -3.8 * (_cam_dist / CAM_DIST_FAR)
	_camera.global_position = _cam_focus + offset
	_camera.look_at(_cam_focus, Vector3.UP)


func _visible_extent() -> Vector2:
	var aspect := 1.6
	var vp := get_viewport()
	if vp != null:
		var s := vp.get_visible_rect().size
		if s.y > 1.0:
			aspect = s.x / s.y
	var half_h := _cam_dist * tan(deg_to_rad(CAM_FOV * 0.5))
	var width := half_h * aspect * 2.0
	var depth := half_h * 2.0 / maxf(sin(deg_to_rad(CAM_PITCH_DEG)), 0.2)
	return Vector2(width, depth)


func _zoom_by(delta: float) -> void:
	_cam_dist_target = clampf(_cam_dist_target + delta, CAM_DIST_NEAR, CAM_DIST_FAR)


func _point_on_ui(px: Vector2) -> bool:
	if info_panel != null and info_panel.visible:
		var r := Rect2(info_panel.position, info_panel.size)
		if r.has_point(px):
			return true
	if title_label != null and Rect2(title_label.position, title_label.size).has_point(px):
		return true
	if total_stars_label != null and Rect2(total_stars_label.position, total_stars_label.size).has_point(px):
		return true
	if hint_label != null and hint_label.visible \
			and Rect2(hint_label.position, hint_label.size).has_point(px):
		return true
	if toast_label != null and toast_label.visible \
			and Rect2(toast_label.position, toast_label.size).has_point(px):
		return true
	return false


# ============================================================================
# 点击走位
# ============================================================================

func _on_ground_clicked(px: Vector2) -> void:
	if _camera == null:
		return
	var origin := _camera.project_ray_origin(px)
	var dir := _camera.project_ray_normal(px)
	if absf(dir.y) < 0.0001:
		return
	var t := -origin.y / dir.y
	if t <= 0.0:
		return
	var hit := origin + dir * t
	var at := Vector2(hit.x, hit.z)

	# 点到旗子：走到该旗子前 FLAG_STOP_DIST 米处
	for id in _flags:
		var flag: LevelFlag3D = _flags[id]
		if not is_instance_valid(flag):
			continue
		var f := Vector2(flag.position.x, flag.position.z)
		if at.distance_to(f) <= 1.6:
			var from := Vector2(_player.global_position.x, _player.global_position.z)
			var away := from - f
			if away.length_squared() < 0.01:
				away = Vector2(0.0, 1.0)
			walk_to(Vector3((f + away.normalized() * FLAG_STOP_DIST).x, 0.0,
				(f + away.normalized() * FLAG_STOP_DIST).y))
			return
	walk_to(Vector3(at.x, 0.0, at.y))


## 脚本 / 测试用：让角色走向某个世界坐标（不可走时夹到最近可走点）。
func walk_to(to: Vector3) -> void:
	var target := _nearest_walkable(Vector2(to.x, to.z))
	var from := Vector2(_player.position.x, _player.position.z)
	var start_cell := Vector2i(((from - _grid_origin) / GRID_STEP).floor())
	var end_cell := Vector2i(((target - _grid_origin) / GRID_STEP).floor())
	_walk_path = _map_astar.get_point_path(start_cell, end_cell)
	_path_index = 0
	if not _walk_path.is_empty():
		_walk_path.append(target)
	_move_target = _walk_path[0] if not _walk_path.is_empty() else Vector2(INF, INF)


func teleport_player(to: Vector3) -> void:
	if _player == null:
		return
	var at := _nearest_walkable(Vector2(to.x, to.z))
	_player.global_position = Vector3(at.x, 0.0, at.y)
	_move_target = Vector2(INF, INF)
	player_position = _player.global_position
	_walk_path.clear()
	_path_index = 0
	_update_proximity()


# ============================================================================
# 公开 API
# ============================================================================

## 某关旗子的世界坐标（旗杆落地点）。
func flag_world_position(id: StringName) -> Vector3:
	if _flags.has(id):
		var flag: LevelFlag3D = _flags[id]
		if is_instance_valid(flag):
			return flag.ground_position()
	var level := LevelCatalog.get_level(id)
	if level == null:
		return Vector3.ZERO
	return _map_point(level.map_pos)


## 某座岛的顶面是否包含某个世界点（自检 / 回归断言用）。
func island_contains(region: StringName, to: Vector3) -> bool:
	var p := Vector2(to.x, to.z)
	for i in _island_polys.size():
		if _island_regions[i] == region:
			return Geometry2D.is_point_in_polygon(p, _island_polys[i])
	return false


## 世界点是否可走（精确谓词：岛屿多边形 ∪ 道路条带）。
func is_walkable_point(to: Vector3) -> bool:
	return _is_walkable_exact(Vector2(to.x, to.z))


## 地图规模自检（工具 / 回归打印用）。
func map_report() -> Dictionary:
	return {
		"islands": _island_polys.size(),
		"flags": _flags.size(),
		"decor": _decor_count,
		"road_points": _road_points.size(),
		"grid": _grid_size,
		"walkable_cells": _walkable.count(1),
	}


## 全量刷新：星数汇总 + 每个旗子的状态/星数 + 信息面板。
func refresh() -> void:
	if total_stars_label != null:
		total_stars_label.text = "已获得 ★ %d / %d" % [
			LevelRuntime.total_stars(), LevelRuntime.total_capacity()]
	for id in _flags:
		var level := LevelCatalog.get_level(id)
		var flag: LevelFlag3D = _flags[id]
		if level == null or not is_instance_valid(flag):
			continue
		flag.setup(level, LevelRuntime.stars_of(id))
		flag.set_selected(id == selected_id)
	_refresh_info()


## 选中一关（含暂未开放的关卡——只查看简介，不进入）。
func select_level(id: StringName) -> void:
	var level := LevelCatalog.get_level(id)
	if level == null:
		return
	selected_id = id
	# 暂未开放的关卡会被 LevelRuntime 拒绝写会话（这是它的契约），这里忽略返回值
	LevelRuntime.select(id)
	for flag_id in _flags:
		var flag: LevelFlag3D = _flags[flag_id]
		if is_instance_valid(flag):
			flag.set_selected(flag_id == selected_id)
	_refresh_info()


## 进入当前选中的关卡；暂未开放 / 无效选择返回 false 且弹 Toast，绝不切场景。
func try_enter_selected() -> bool:
	var level := LevelCatalog.get_level(selected_id)
	if level == null:
		return false
	if not level.is_playable():
		_show_toast(LOCKED_TOAST)
		return false
	AudioManager.play_sfx(&"ui_click")
	level_entered.emit(level.id)
	return LevelRuntime.enter_level(level.id)


## 选中并进入指定关卡（等价于 select_level + try_enter_selected）。
func enter_level(id: StringName) -> bool:
	select_level(id)
	return try_enter_selected()


# ============================================================================
# UI 构建（覆盖层：LevelSelect3D → UILayer(CanvasLayer) → UIRoot(Control) → 各控件）
# ============================================================================

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	add_child(_ui_layer)

	_ui_root = Control.new()
	_ui_root.name = "UIRoot"
	_full_rect(_ui_root)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = _theme
	_ui_layer.add_child(_ui_root)

	_build_top_bar()
	_build_info_panel()
	_build_hint()
	_build_toast()


func _build_top_bar() -> void:
	top_bar = Control.new()
	top_bar.name = "TopBar"
	_full_rect(top_bar)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(top_bar)
	_map_caption = _make_label("MapCaption", 11, CampaignStyle.GOLD, false)
	_map_caption.text = "王 国 远 征　 /　世界地图"
	title_label = _make_label("TitleLabel", 36, CampaignStyle.CREAM, false)
	title_label.text = TITLE_TEXT
	title_label.add_theme_font_override("font", CampaignStyle.font(true))
	_route_caption = _make_label("RouteCaption", 12, CampaignStyle.MUTED, false)
	_route_caption.text = "循着旧日的道路，让王旗再次升起。"
	total_stars_label = _make_label("TotalStarsLabel", 14, CampaignStyle.GOLD, false)
	total_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_stars_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_stars_label.add_theme_stylebox_override("normal", CampaignStyle.box(CampaignStyle.INK, Color(CampaignStyle.GOLD, 0.25), 20))


func _build_info_panel() -> void:
	info_panel = Panel.new()
	info_panel.name = "InfoPanel"
	info_panel.add_theme_stylebox_override("panel", CampaignStyle.box(Color(CampaignStyle.PANEL, 0.97), Color(CampaignStyle.MUTED, 0.22), 5))
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(info_panel)

	info_chapter_label = _make_label("InfoChapterLabel", FS_CHAPTER, CampaignStyle.GOLD, false)
	info_title_label = _make_label("InfoTitleLabel", FS_TITLE, CampaignStyle.CREAM, true)
	info_subtitle_label = _make_label("InfoSubtitleLabel", FS_BODY, CampaignStyle.MUTED, true)
	info_desc_label = _make_label("InfoDescLabel", FS_BODY, Color(CampaignStyle.CREAM, 0.86), true)

	_info_divider = ColorRect.new()
	(_info_divider as ColorRect).color = Color(CampaignStyle.GOLD, 0.3)
	_info_divider.name = "InfoDivider"
	_ui_root.add_child(_info_divider)

	objectives_box = VBoxContainer.new()
	objectives_box.name = "ObjectivesBox"
	objectives_box.add_theme_constant_override("separation", 3)
	objectives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(objectives_box)

	star_hints_box = VBoxContainer.new()
	star_hints_box.name = "StarHintsBox"
	star_hints_box.add_theme_constant_override("separation", 3)
	star_hints_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(star_hints_box)

	star_row = HBoxContainer.new()
	star_row.name = "StarRow"
	star_row.add_theme_constant_override("separation", 4)
	star_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(star_row)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = ENTER_TEXT
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.add_theme_font_size_override("font_size", 16)
	CampaignStyle.primary(start_button)
	start_button.pressed.connect(_on_start_pressed)
	start_button.mouse_entered.connect(func() -> void: AudioManager.play_sfx(&"ui_hover"))
	_ui_root.add_child(start_button)

	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = BACK_TEXT
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.pressed.connect(_on_back_pressed)
	back_button.mouse_entered.connect(func() -> void: AudioManager.play_sfx(&"ui_hover"))
	_ui_root.add_child(back_button)

	# 暂未开放时的压暗遮罩（鼠标穿透，只做视觉压暗）
	_info_dim = ColorRect.new()
	_info_dim.name = "InfoDim"
	_info_dim.color = Color(0.03, 0.04, 0.06, 0.45)
	_info_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_dim.visible = false
	_ui_root.add_child(_info_dim)


func _build_hint() -> void:
	hint_label = Label.new()
	hint_label.name = "HintLabel"
	hint_label.text = HINT_IDLE
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", UIStyle.TEXT_MAIN)
	hint_label.add_theme_stylebox_override("normal", CampaignStyle.box(Color(CampaignStyle.INK, 0.94), Color(CampaignStyle.MUTED, 0.16), 4))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(hint_label)


func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.name = "ToastLabel"
	toast_label.text = LOCKED_TOAST
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 16)
	toast_label.add_theme_color_override("font_color", CampaignStyle.GOLD)
	toast_label.add_theme_stylebox_override("normal", CampaignStyle.box(Color(CampaignStyle.INK, 0.94), Color(CampaignStyle.MUTED, 0.16), 4))
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.visible = false
	_ui_root.add_child(toast_label)


func _make_label(node_name: String, font_size: int, color: Color, wrap: bool) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_root.add_child(label)
	return label


# ============================================================================
# 刷新：信息面板
# ============================================================================

func _refresh_info() -> void:
	var level := LevelCatalog.get_level(selected_id)
	if level == null or info_panel == null:
		return
	info_chapter_label.text = "%s　/　%s" % [level.chapter, "暂未开放" if level.is_coming_soon() else "自由探索" if level.kind == LevelDef.Kind.SANDBOX else "初次远征 · 约 2 分钟"]
	info_title_label.text = level.title
	info_subtitle_label.text = ""
	info_subtitle_label.visible = false
	info_desc_label.text = level.desc
	_fill_list(objectives_box, "此行目标", level.objectives, "· ")
	_fill_list(star_hints_box, "挑战勋章", level.star_hints, "★ ")
	star_hints_box.visible = level.star_hints.size() > 0
	_fill_stars(level, LevelRuntime.stars_of(level.id))

	var locked := not level.is_playable()
	start_button.text = LOCKED_TEXT if locked else ENTER_TEXT
	start_button.disabled = locked
	start_button.add_theme_color_override("font_color",
		CampaignStyle.MUTED if locked else CampaignStyle.INK)
	_info_dim.visible = false
	_layout_info_panel()


func _fill_list(box: VBoxContainer, title: String, items: PackedStringArray, bullet: String) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", FS_BODY)
	head.add_theme_color_override("font_color", CampaignStyle.GOLD)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	for item in items:
		var line := Label.new()
		line.text = bullet + item
		line.add_theme_font_size_override("font_size", FS_BODY)
		line.add_theme_color_override("font_color", CampaignStyle.CREAM)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(line)


func _fill_stars(level: LevelDef, stars: int) -> void:
	for child in star_row.get_children():
		star_row.remove_child(child)
		child.queue_free()
	if level.star_total <= 0:
		var none := Label.new()
		none.text = "本关不做星级判定"
		none.add_theme_font_size_override("font_size", FS_BODY)
		none.add_theme_color_override("font_color", CampaignStyle.MUTED)
		none.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_row.add_child(none)
		return
	for i in level.star_total:
		var glyph := Label.new()
		glyph.text = "★" if i < stars else "☆"
		glyph.add_theme_font_size_override("font_size", FS_STAR)
		glyph.add_theme_color_override("font_color",
			CampaignStyle.GOLD if i < stars else Color(CampaignStyle.MUTED, 0.75))
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star_row.add_child(glyph)
	var tail := Label.new()
	tail.text = "%d / %d" % [clampi(stars, 0, level.star_total), level.star_total]
	tail.add_theme_font_size_override("font_size", FS_BODY)
	tail.add_theme_color_override("font_color", CampaignStyle.MUTED)
	tail.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_row.add_child(tail)


# ============================================================================
# 排版
# ============================================================================

func _view_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1152.0, 648.0)
	return vp.get_visible_rect().size


func _layout_ui() -> void:
	if info_panel == null:
		return
	_layout_top()
	_layout_info_panel()
	_layout_bottom()


func _layout_top() -> void:
	var m := PANEL_MARGIN
	var vs := _view_size()
	_map_caption.position = Vector2(m, 24)
	_map_caption.size = Vector2(300, 20)
	title_label.position = Vector2(m - 2, 47)
	title_label.size = Vector2(290, 54)
	_route_caption.position = Vector2(m, 110)
	_route_caption.size = Vector2(340, 24)
	total_stars_label.position = Vector2(vs.x - m - 170, 26)
	total_stars_label.size = Vector2(170, 36)


func _layout_bottom() -> void:
	var vs := _view_size()
	var left := info_panel.position.x + info_panel.size.x + 20.0
	var w := maxf(220.0, vs.x - left - PANEL_MARGIN)
	hint_label.size = Vector2(w, 40)
	hint_label.position = Vector2(left, vs.y - 66)
	toast_label.size = Vector2(minf(380, w), 42)
	toast_label.position = Vector2(left + (w - toast_label.size.x) * 0.5, vs.y - 120)


func _layout_info_panel() -> void:
	if info_panel == null:
		return
	var vs := _view_size()
	var panel_w := clampf(vs.x * 0.245, 286.0, 336.0)
	var panel := Rect2(Vector2(PANEL_MARGIN, 158), Vector2(panel_w, maxf(440, vs.y - 186)))
	info_panel.position = panel.position
	info_panel.size = panel.size
	_info_dim.position = panel.position
	_info_dim.size = panel.size
	var cx := panel.position.x + PANEL_PAD
	var cw := panel.size.x - PANEL_PAD * 2.0
	var y := panel.position.y + 20
	y = _place(info_chapter_label, cx, y, cw, 22, 5)
	y = _place(info_title_label, cx, y, cw, 46, 12)
	y = _place(info_desc_label, cx, y, cw, _measure(info_desc_label.text, FS_BODY, cw), 18)
	y = _place(_info_divider, cx, y, cw, 1, 16)
	y = _place(objectives_box, cx, y, cw, objectives_box.get_combined_minimum_size().y, 16)
	if star_hints_box.visible:
		y = _place(star_hints_box, cx, y, cw, star_hints_box.get_combined_minimum_size().y, 14)
	y = _place(star_row, cx, y, cw, star_row.get_combined_minimum_size().y, 12)
	var by := maxf(panel.end.y - 66, y + 4)
	var bw := (cw - 8) * 0.58
	start_button.position = Vector2(cx, by)
	start_button.size = Vector2(bw, 44)
	back_button.position = Vector2(cx + bw + 8, by)
	back_button.size = Vector2(cw - bw - 8, 44)


func _place(node: Control, x: float, y: float, w: float, h: float, gap: float) -> float:
	var height := maxf(h, 1.0)
	node.position = Vector2(x, y)
	node.size = Vector2(w, height)
	return y + height + gap


## 自动换行文本的高度估算：按字体实测宽度算行数（中文逐字断行，估算足够准）。
func _measure(text: String, font_size: int, width: float) -> float:
	if _font == null:
		return 0.0
	if text == "":
		return _font.get_height(font_size)
	var line_h := _font.get_height(font_size)
	var lines := 0
	for para in text.split("\n"):
		var w := _font.get_string_size(para, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var n := 1 if w <= 0.0 else int(ceil(w / maxf(1.0, width - 2.0)))
		lines += maxi(n, 1)
	return float(lines) * line_h + 2.0


func _full_rect(control: Control) -> void:
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func _vertical_gradient(top: Color, bottom: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([top, bottom])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	return tex


# ============================================================================
# 交互
# ============================================================================

func _on_start_pressed() -> void:
	try_enter_selected()


func _on_back_pressed() -> void:
	AudioManager.play_sfx(&"ui_click")
	TimeManager.set_speed(1.0)
	get_tree().change_scene_to_file(BACK_SCENE)


func _on_progress_changed(_id: StringName, _stars: int) -> void:
	refresh()


func _show_toast(text: String) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_ignore_time_scale(true)
	_toast_tween.tween_interval(TOAST_HOLD)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, TOAST_FADE)
	_toast_tween.tween_callback(func() -> void: toast_label.visible = false)


# ============================================================================
# 数据定义（v38 关卡地图美术基准：岛屿轮廓 / 装饰配额 / 道路控制点）
# ============================================================================

## 五座漂浮岛的配色与轮廓（归一化坐标，每座 10~12 点的不规则块状）。
static func _island_defs() -> Array:
	return [
		{
			"region": LevelDef.REGION_ROCK,
			"top": Color(0.561, 0.584, 0.612),      # #8f959c
			"side": Color(0.337, 0.357, 0.392),     # #565b64
			"points": [
				Vector2(0.150, 0.148), Vector2(0.176, 0.086), Vector2(0.252, 0.056),
				Vector2(0.336, 0.074), Vector2(0.402, 0.096), Vector2(0.446, 0.168),
				Vector2(0.420, 0.230), Vector2(0.352, 0.262), Vector2(0.262, 0.252),
				Vector2(0.188, 0.208),
			],
		},
		{
			"region": LevelDef.REGION_FOREST,
			"top": Color(0.184, 0.561, 0.455),      # #2f8f74
			"side": Color(0.110, 0.373, 0.302),     # #1c5f4d
			"points": [
				Vector2(0.452, 0.192), Vector2(0.468, 0.122), Vector2(0.536, 0.090),
				Vector2(0.618, 0.086), Vector2(0.676, 0.128), Vector2(0.694, 0.206),
				Vector2(0.658, 0.272), Vector2(0.586, 0.302), Vector2(0.512, 0.280),
				Vector2(0.460, 0.240),
			],
		},
		{
			"region": LevelDef.REGION_DESERT,
			"top": Color(0.878, 0.663, 0.373),      # #e0a95f
			"side": Color(0.690, 0.459, 0.184),     # #b0752f
			"points": [
				Vector2(0.730, 0.312), Vector2(0.742, 0.212), Vector2(0.798, 0.156),
				Vector2(0.878, 0.132), Vector2(0.952, 0.166), Vector2(0.988, 0.248),
				Vector2(0.962, 0.328), Vector2(0.888, 0.378), Vector2(0.798, 0.370),
				Vector2(0.744, 0.344),
			],
		},
		{
			"region": LevelDef.REGION_GREEN,        # 最大的一座
			"top": Color(0.435, 0.749, 0.478),      # #6fbf7a
			"side": Color(0.239, 0.478, 0.290),     # #3d7a4a
			"points": [
				Vector2(0.230, 0.462), Vector2(0.246, 0.392), Vector2(0.302, 0.346),
				Vector2(0.372, 0.326), Vector2(0.456, 0.340), Vector2(0.536, 0.368),
				Vector2(0.612, 0.418), Vector2(0.640, 0.490), Vector2(0.586, 0.548),
				Vector2(0.496, 0.586), Vector2(0.384, 0.598), Vector2(0.306, 0.556),
			],
		},
		{
			"region": LevelDef.REGION_SNOW,
			"top": Color(0.906, 0.937, 0.973),      # #e7eff8
			"side": Color(0.714, 0.776, 0.855),     # #b6c6da
			"points": [
				Vector2(0.612, 0.758), Vector2(0.634, 0.678), Vector2(0.700, 0.638),
				Vector2(0.792, 0.630), Vector2(0.872, 0.666), Vector2(0.932, 0.728),
				Vector2(0.946, 0.816), Vector2(0.896, 0.882), Vector2(0.810, 0.912),
				Vector2(0.714, 0.898), Vector2(0.644, 0.844),
			],
		},
	]


## 奶油色道路控制点（归一化）：与 2D 版逐点一致（绿↔岩↔林↔沙、绿↔雪 + 短岔路）。
static func _road_defs() -> Array:
	return [
		# 绿岛 → 岩岛（左上主干）
		[Vector2(0.335, 0.455), Vector2(0.318, 0.340), Vector2(0.302, 0.248), Vector2(0.300, 0.165)],
		# 岩岛 → 森林岛（顶部横干）
		[Vector2(0.300, 0.165), Vector2(0.362, 0.178), Vector2(0.432, 0.206),
			Vector2(0.502, 0.216), Vector2(0.565, 0.205)],
		# 森林岛 → 沙漠岛（右上主干）
		[Vector2(0.565, 0.205), Vector2(0.648, 0.176), Vector2(0.720, 0.200),
			Vector2(0.792, 0.238), Vector2(0.855, 0.275)],
		# 绿岛 → 雪岛（右下主干）
		[Vector2(0.335, 0.455), Vector2(0.452, 0.520), Vector2(0.560, 0.600),
			Vector2(0.662, 0.690), Vector2(0.745, 0.760)],
		# 短岔路：岩岛与绿岛之间的缺口里向右下分叉
		[Vector2(0.316, 0.288), Vector2(0.352, 0.300), Vector2(0.396, 0.306)],
	]


## 每座岛的装饰配额（固定种子撒点，只撒在岛内）。
static func _decor_spec() -> Dictionary:
	return {
		LevelDef.REGION_GREEN: {&"tree": 19, &"coin": 6, &"house": 3},
		LevelDef.REGION_FOREST: {&"tree": 26, &"house": 5, &"rock": 4, &"coin": 9},
		LevelDef.REGION_ROCK: {&"rock": 14, &"tree": 5},
		LevelDef.REGION_DESERT: {&"rock": 12, &"house": 3, &"tree": 4},
		LevelDef.REGION_SNOW: {&"ice": 16, &"tree": 7, &"rock": 5},
	}


# ============================================================================
# 坐标与几何工具
# ============================================================================

## 归一化坐标（0~1）→ 世界坐标（y=0）。x 向右、y 向下 = 屏幕观感（南侧为 +Z）。
func _map_point(normalized: Vector2) -> Vector3:
	return Vector3((normalized.x - 0.5) * MAP_SIZE.x, 0.0, (normalized.y - 0.5) * MAP_SIZE.y)


## 归一化坐标 → 世界 XZ（平面运算用）。
func _to_world2(normalized: Vector2) -> Vector2:
	return Vector2((normalized.x - 0.5) * MAP_SIZE.x, (normalized.y - 0.5) * MAP_SIZE.y)


func _to_packed(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		var pv: Vector2 = p
		out.append(pv)
	return out


func _polygon_centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / float(maxi(poly.size(), 1))


## 以质心为中心整体外扩（板状侧影 / 影子板用）。
func _grow_poly(poly: PackedVector2Array, k: float) -> PackedVector2Array:
	var c := _polygon_centroid(poly)
	var out := PackedVector2Array()
	for p in poly:
		out.append(c + (p - c) * k)
	return out


## 顶面网格：以质心为扇心的三角扇，法线显式给出（不依赖绕序）。
func _polygon_mesh(poly: PackedVector2Array, y: float, normal: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := _polygon_centroid(poly)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		_add_tri(st, Vector3(c.x, y, c.y), Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), normal)
	return st.commit()


## 侧壁网格：每边一个四边形；顶点色 = 色板暗色 × 烘焙光照因子（平涂材质下仍看得出体积）。
func _prism_sides(poly: PackedVector2Array, y_top: float, y_bottom: float,
		color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := _polygon_centroid(poly)
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var mid := (a + b) * 0.5
		var outward := mid - c
		if outward.length_squared() < 0.000001:
			continue
		var out_n := outward.normalized()
		var nrm := Vector3(out_n.x, 0.0, out_n.y)
		var shade := _side_shade(out_n.x, out_n.y)
		var tint := Color(color.r * shade, color.g * shade, color.b * shade)
		var a_t := Vector3(a.x, y_top, a.y)
		var b_t := Vector3(b.x, y_top, b.y)
		var lower_a := c + (a - c) * 0.88
		var lower_b := c + (b - c) * 0.88
		var a_b := Vector3(lower_a.x, y_bottom, lower_a.y)
		var b_b := Vector3(lower_b.x, y_bottom, lower_b.y)
		_add_tri_c(st, a_t, b_t, b_b, nrm, tint)
		_add_tri_c(st, a_t, b_b, a_b, nrm, tint)
	return st.commit()


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_tri(st, a, c, b, Vector3.UP)
	_add_tri(st, a, d, c, Vector3.UP)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	for v in [a, b, c]:
		var vv: Vector3 = v
		st.set_normal(normal)
		st.set_uv(Vector2(vv.x, vv.z))
		st.add_vertex(vv)


## 带顶点色的三角面（侧壁烘焙光照用）。
func _add_tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
		tint: Color) -> void:
	for v in [a, b, c]:
		var vv: Vector3 = v
		st.set_normal(normal)
		st.set_color(tint)
		st.set_uv(Vector2(vv.x, vv.z))
		st.add_vertex(vv)


## 单件网格 + 材质挂到父节点，返回 MeshInstance3D。
func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _flat_mat(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## 侧壁与阴影板使用平涂材质；岛面和道路已校正绕序，可接收真实物体投影。
func _flat_unshaded(color: Color) -> StandardMaterial3D:
	return _flat_mat(color, true)


## 顶点色平涂材质（侧壁烘焙光照用；顶点色 = 色板颜色 × 光照因子）。
func _vertex_color_mat() -> StandardMaterial3D:
	var mat := _flat_unshaded(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	return mat


## 侧壁烘焙光照因子：按侧壁朝向着色（与 DirectionalLight3D 同向，
## 南 / 西墙偏亮、北 / 东墙偏暗），在平涂前提下保留板状棱柱的体积感。
func _side_shade(nx: float, nz: float) -> float:
	var lit := maxf(0.0, -(LIGHT_DIR.x * nx + LIGHT_DIR.z * nz))
	return clampf(0.80 + 0.30 * (lit / LIGHT_SIDE_MAX), 0.0, 1.0)


func _alpha_mat(color: Color) -> StandardMaterial3D:
	var mat := _flat_mat(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Catmull-Rom 采样：把折线控制点连成平滑曲线（道路用）。
func _smooth(ctrl: PackedVector2Array, per_seg: int) -> PackedVector2Array:
	if ctrl.size() < 2:
		return ctrl
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in range(n - 1):
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		for s in range(per_seg):
			var t := float(s) / float(per_seg)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(ctrl[n - 1])
	return out


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ---- 装饰撒点（固定种子，只在岛内，与 2D 版同规则）----

## 在多边形内（留出边缘余量）随机取一点；取不到返回 (-1,-1)。
func _random_in_polygon(rng: RandomNumberGenerator, poly: PackedVector2Array) -> Vector2:
	var box := _bounds(poly)
	for _i in 120:
		var p := Vector2(
			rng.randf_range(box.position.x, box.end.x),
			rng.randf_range(box.position.y, box.end.y))
		if _inside_with_margin(p, poly, DECO_EDGE_MARGIN):
			return p
	return Vector2(-1.0, -1.0)


## 点 + 周围 8 个方向的小偏移全部在多边形内 = 该点离岛缘还有余量。
func _inside_with_margin(p: Vector2, poly: PackedVector2Array, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(p, poly):
		return false
	for i in 8:
		var a := TAU * float(i) / 8.0
		if not Geometry2D.is_point_in_polygon(p + Vector2(cos(a), sin(a)) * margin, poly):
			return false
	return true


func _too_close(p: Vector2, placed: Array, min_dist: float) -> bool:
	for item in placed:
		var q: Vector2 = item["pos"]
		if p.distance_squared_to(q) < min_dist * min_dist:
			return true
	return false


func _near_nodes(p: Vector2, nodes: Array, clear: float) -> bool:
	for n in nodes:
		var q: Vector2 = n
		if p.distance_squared_to(q) < clear * clear:
			return true
	return false


func _bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
