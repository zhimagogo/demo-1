class_name LevelFlag3D
extends Node3D
## ============================================================================
## LevelFlag3D —— 3D 关卡选择地图上的「旗子」关卡节点（v38 关卡系统 · 3D 版）。
##
## 细旗杆、燕尾旗、锁与地面选中环全部由代码构建。
## 旗面固定朝 +Z；关卡名及状态文字始终朝向镜头，缩放后仍可读。
## 金色标记当前选中与已通关；灰青色表示暂未开放。
##
## 锚点约定：本节点的原点 = 旗杆落地点（世界 Y=0），LevelSelect3D 把它钉在关卡地图坐标上，
## 因此 ground_position() 与 LevelDef.map_pos → 世界坐标的换算完全一致。
## ============================================================================

# ---- 配色（v38 关卡地图美术基准色板）----
const FLAG_CLEARED := Color(0.941, 0.788, 0.271)    # #f0c945 金（已通关）
const FLAG_SELECTED := Color(0.937, 0.780, 0.416)   # 暖金（当前选中）
const FLAG_PLAYABLE := Color(0.247, 0.624, 0.373)   # #3f9f5f 绿（可挑战）
const FLAG_LOCKED := Color(0.42, 0.51, 0.54)     # 灰青（暂未开放）
const POLE_COLOR := Color(0.231, 0.247, 0.278)      # #3b3f47 细深色旗杆
const CHIP_BG := Color(0.169, 0.196, 0.259)         # #2b3242 深藏青芯片
const CHIP_EDGE := Color(0.35, 0.41, 0.52)
const CHIP_TEXT := Color(0.97, 0.98, 1.0)           # 白字
const GLOW_GOLD := Color(0.95, 0.80, 0.38)          # 选中金环
const GROUND_SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const LOCK_BODY := Color(0.82, 0.85, 0.89)          # 浅灰小锁
const LOCK_DARK := Color(0.55, 0.59, 0.65)

# ---- 几何（米）----
const POLE_HEIGHT := 2.42
const POLE_RADIUS := 0.045
const PENNANT_TOP := 2.42
const PENNANT_MID := 2.18
const PENNANT_TAIL := 1.94
const PENNANT_TIP := 0.88          # 旗尖伸出的长度
const PENNANT_NOTCH := 0.56        # 燕尾缺口深度
const CHIP_CENTER := Vector3(2.32, 2.20, 0.0)
const CHIP_SIZE := Vector3(2.60, 1.00, 0.10)
const CROWN_SIZE := 0.50
const LABEL_FONT_SIZE := 48
const LABEL_PIXEL_SIZE := 0.0125
const LOCK_CENTER := Vector3(0.46, 2.12, 0.02)
const RING_RADIUS := 1.18
const RING_Y := 0.03
const FLOAT_AMPLITUDE := 0.09      # 浮动振幅（米）
const SCALE_HI := 1.10             # 选中 / 靠近时放大倍率
const ANIM_SPEED := 8.0            # 缩放插值速度

## 关卡定义（setup 注入）。
var level: LevelDef = null
## 已得星数（set_stars / setup 注入）。
var stars: int = 0

var _selected := false
var _near := false
var _time := 0.0
var _scale_now := 1.0
var _built := false
var _body: Node3D = null           # 浮动 / 缩放主体
var _ground: Node3D = null         # 贴地装饰（不浮动）
var _pennant_mat: StandardMaterial3D = null
var _chip_label: Label3D = null
var _ring: Node3D = null
var _lock: Node3D = null
var _shadow_disc: MeshInstance3D = null


## 注入关卡定义与已得星数（LevelSelect3D.refresh 每次刷新都会调）。
func setup(def: LevelDef, star_count: int) -> void:
	level = def
	stars = star_count
	if def != null:
		name = "Flag_" + String(def.id)
	_build()
	_apply_visual()
	_refresh_chip()


## 玩家在地图上点亮的关卡（金色光环 + 放大 + 浮动）。
func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_apply_visual()


## 角色走到旗子旁（与选中同款高亮，但可以由多面旗同时处于 near 之外的单选逻辑控制）。
func set_near(on: bool) -> void:
	if _near == on:
		return
	_near = on
	_apply_visual()


## 更新芯片星数（不改选中 / 靠近状态）。
func set_stars(n: int) -> void:
	stars = n
	_refresh_chip()


## 旗杆落地点（世界坐标）—— 关卡地图上这一关的「插旗点」。
func ground_position() -> Vector3:
	return global_position


## 当前旗色（自检 / 回归断言用）。
func flag_color() -> Color:
	return _flag_color()


## 芯片文案（自检用）。
func chip_text() -> String:
	if level == null:
		return "测试"
	return level.chip_text(stars)


# ============================================================================
# 状态
# ============================================================================

func _flag_color() -> Color:
	if level == null or level.is_coming_soon():
		return FLAG_LOCKED
	if _selected:
		return FLAG_SELECTED
	if stars > 0 or LevelRuntime.is_cleared(level.id):
		return FLAG_CLEARED
	return FLAG_PLAYABLE


func _is_active() -> bool:
	return _selected or _near


func _apply_visual() -> void:
	if _chip_label != null:
		_chip_label.modulate = CampaignStyle.GOLD if _is_active() else CampaignStyle.MUTED if level != null and level.is_coming_soon() else CampaignStyle.CREAM
	if _pennant_mat != null:
		_pennant_mat.albedo_color = _flag_color()
	if _ring != null:
		_ring.visible = _is_active()
	if _shadow_disc != null:
		_shadow_disc.visible = not _is_active()
	if _lock != null:
		_lock.visible = level != null and level.is_coming_soon()


func _refresh_chip() -> void:
	if _chip_label != null:
		_chip_label.text = (level.title + "\n" if level != null else "") + ("暂未开放" if level != null and level.is_coming_soon() else "自由探索" if level != null and level.kind == LevelDef.Kind.SANDBOX else "★ " + chip_text())


func _process(delta: float) -> void:
	if _body == null:
		return
	_time += delta
	var target := SCALE_HI if _is_active() else 1.0
	_scale_now = lerpf(_scale_now, target, 1.0 - exp(-ANIM_SPEED * delta))
	_body.scale = Vector3(_scale_now, _scale_now, _scale_now)
	if _is_active():
		_body.position.y = (sin(_time * 2.6) * 0.5 + 0.5) * FLOAT_AMPLITUDE
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, 1.0 - exp(-ANIM_SPEED * delta))


# ============================================================================
# 构建（只做一次）
# ============================================================================

func _build() -> void:
	if _built:
		return
	_built = true

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_ground = Node3D.new()
	_ground.name = "Ground"
	add_child(_ground)

	_build_pole()
	_build_pennant()
	_build_chip()
	_build_lock()
	_build_ground()


func _build_pole() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = POLE_RADIUS
	mesh.bottom_radius = POLE_RADIUS
	mesh.height = POLE_HEIGHT
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Pole"
	mi.mesh = mesh
	mi.position = Vector3(0.0, POLE_HEIGHT * 0.5, 0.0)
	mi.material_override = _mat(POLE_COLOR)
	_body.add_child(mi)


## 燕尾三角旗：自制面片（局部 XY 平面，法线朝 +Z 正对相机，双面可见）。
func _build_pennant() -> void:
	var shape := [
		Vector2(0.06, PENNANT_TOP),
		Vector2(PENNANT_TIP, PENNANT_MID - 0.02),
		Vector2(PENNANT_NOTCH, PENNANT_MID),
		Vector2(PENNANT_TIP, PENNANT_MID + 0.02),
		Vector2(0.06, PENNANT_TAIL),
	]
	# 以中左点为扇心三角化（该形状关于它是星形多边形）
	var hub := Vector2(0.06, PENNANT_MID)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := shape.size()
	for i in n:
		var a: Vector2 = shape[i]
		var b: Vector2 = shape[(i + 1) % n]
		_add_tri(st, hub, a, b, Vector3.BACK)
	var mesh := st.commit()

	# 旗面是手工面片，同样用平涂材质：颜色 = 状态色原色，不受绕序 / 光照影响
	_pennant_mat = _mat(_flag_color())
	_pennant_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pennant_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mi := MeshInstance3D.new()
	mi.name = "Pennant"
	mi.mesh = mesh
	mi.material_override = _pennant_mat
	_body.add_child(mi)


## 星数芯片：深藏青方板 + 金皇冠 + 白字「n/上限」。
func _build_chip() -> void:
	# 悬浮文字始终正对镜头；远岛也能读到名字与开放状态。
	_chip_label = Label3D.new()
	_chip_label.name = "ChipLabel"
	_chip_label.font = CampaignStyle.font(true)
	_chip_label.font_size = 36
	_chip_label.pixel_size = 0.019
	_chip_label.modulate = CampaignStyle.CREAM
	_chip_label.outline_size = 10
	_chip_label.outline_modulate = Color(CampaignStyle.INK, 0.96)
	_chip_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_chip_label.no_depth_test = true
	_chip_label.position = Vector3(0, 3.75, 0)
	_body.add_child(_chip_label)
	_refresh_chip()



func _build_lock() -> void:
	_lock = Node3D.new()
	_lock.name = "Lock"
	_body.add_child(_lock)

	var body := BoxMesh.new()
	body.size = Vector3(0.46, 0.36, 0.12)
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body
	body_mi.position = LOCK_CENTER
	body_mi.material_override = _mat(LOCK_BODY)
	_lock.add_child(body_mi)

	var bar := BoxMesh.new()
	bar.size = Vector3(0.36, 0.09, 0.09)
	var bar_mi := MeshInstance3D.new()
	bar_mi.mesh = bar
	bar_mi.position = LOCK_CENTER + Vector3(0.0, 0.26, 0.0)
	bar_mi.material_override = _mat(LOCK_DARK)
	_lock.add_child(bar_mi)

	for side_f in [-1.0, 1.0]:
		var side: float = side_f
		var post := BoxMesh.new()
		post.size = Vector3(0.09, 0.22, 0.09)
		var post_mi := MeshInstance3D.new()
		post_mi.mesh = post
		post_mi.position = LOCK_CENTER + Vector3(0.135 * side, 0.14, 0.0)
		post_mi.material_override = _mat(LOCK_DARK)
		_lock.add_child(post_mi)


## 贴地装饰：常驻一层暗色落影盘；选中 / 靠近时换成金色光环（半透明盘 + 金环）。
func _build_ground() -> void:
	_shadow_disc = _disc(0.52, GROUND_SHADOW, RING_Y * 0.6)
	_ground.add_child(_shadow_disc)

	_ring = Node3D.new()
	_ring.name = "SelectRing"
	_ring.visible = false
	_ground.add_child(_ring)

	var outer := _disc(RING_RADIUS, Color(GLOW_GOLD, 0.18), RING_Y)
	_ring.add_child(outer)
	var inner := _disc(RING_RADIUS * 0.72, Color(GLOW_GOLD, 0.26), RING_Y + 0.004)
	_ring.add_child(inner)

	var band := TorusMesh.new()
	band.inner_radius = RING_RADIUS - 0.05
	band.outer_radius = RING_RADIUS + 0.05
	band.rings = 8
	band.ring_segments = 36
	var band_mi := MeshInstance3D.new()
	band_mi.name = "RingBand"
	band_mi.mesh = band
	band_mi.position = Vector3(0.0, RING_Y + 0.01, 0.0)
	band_mi.material_override = _mat(Color(GLOW_GOLD, 0.8))
	_ring.add_child(band_mi)


# ---- 小工具 ----

func _disc(radius: float, color: Color, y: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.012
	mesh.radial_segments = 40
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, y, 0.0)
	mi.material_override = _mat(color)
	return mi


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _add_tri(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, normal: Vector3) -> void:
	_add_vert(st, a, normal)
	_add_vert(st, b, normal)
	_add_vert(st, c, normal)


func _add_vert(st: SurfaceTool, p: Vector2, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(p.x, p.y))
	st.add_vertex(Vector3(p.x, p.y, 0.0))
