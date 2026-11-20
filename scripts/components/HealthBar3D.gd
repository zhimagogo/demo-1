class_name HealthBar3D
extends Node3D
## 共享 Sprite3D 血条：完整对齐相机、按模型尺寸抬高、保持屏幕可读尺寸。
## 第三人称显示近处敌人及受伤/选中/跟随友军，战术视角显示范围内所有单位。
## 透过单位保持可读，第三人称不穿建筑；伤害残影短暂停留后收回。

const TEX_W := 80
const TEX_H := 10
const PIXEL_SIZE := 0.016
const FULL_W := TEX_W * PIXEL_SIZE
const FULL_H := TEX_H * PIXEL_SIZE
const RISE := 2.1
const TARGET_PIXELS := 72.0
const HERO_RANGE := 32.0
const ENEMY_RANGE := 26.0
const TACTICAL_RANGE := 85.0
const RECENT_CHANGE_SEC := 3.0
const CHIP_HOLD_SEC := 0.25
const CHIP_DRAIN_SPEED := 0.65
const OCCLUSION_INTERVAL := 0.15
const COLOR_BG := Color(0.035, 0.028, 0.025, 0.96)
const COLOR_EDGE := Color(0.20, 0.17, 0.13, 0.95)
const COLOR_HERO := Color(0.35, 1.0, 0.45)
const COLOR_ALLY := Color(0.40, 0.78, 1.0)
const COLOR_ENEMY := Color(1.0, 0.32, 0.30)
const COLOR_LOW := Color(1.0, 0.80, 0.18)
const COLOR_CHIP := Color(1.0, 0.83, 0.52)
const COLOR_FOCUS := Color(1.0, 0.70, 0.27)
const LOW_THRESHOLD := 0.30

static var _tex: Texture2D
var _edge: Sprite3D
var _bg: Sprite3D
var _chip: Sprite3D
var _fg: Sprite3D
var _health: HealthComponent
var _pawn: Pawn
var _base_color: Color = COLOR_ALLY
var _ratio := 1.0
var _chip_ratio := 1.0
var _chip_hold := 0.0
var _recent_change := 0.0
var _opacity := 0.0
var _emphasized := false
var _occluded := false
var _occlusion_left := 0.0
var _last_camera: Camera3D
var _head_height := RISE


func _ready() -> void:
	_ensure_tex()
	top_level = true
	visible = false
	_pawn = get_parent() as Pawn
	_health = get_parent().get_node_or_null("HealthComponent") as HealthComponent
	_edge = _new_sprite("Border", COLOR_EDGE, 1.10, 1.65, 8)
	_bg = _new_sprite("Slot", COLOR_BG, 1.06, 1.35, 9)
	_chip = _new_sprite("DamageTrail", COLOR_CHIP, 1.0, 1.0, 10)
	_fg = _new_sprite("Fill", _base_color, 1.0, 1.0, 11)
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
		_health.died.connect(_on_died)
		sync_health()
	_follow(get_viewport().get_camera_3d())


## Pawn._apply_def 在组件 ready 之后写入最大生命；同步初值避免出生残影。
func apply_color(is_hero: bool, team: int) -> void:
	_base_color = COLOR_HERO if is_hero else COLOR_ENEMY if team == TeamComponent.Team.ENEMY else COLOR_ALLY
	sync_health()


func sync_health() -> void:
	_ratio = clampf(_health.ratio(), 0.0, 1.0) if _health != null else 1.0
	_chip_ratio = _ratio
	_chip_hold = 0.0
	var model_scale := maxf(_pawn.def.model_scale, 0.85) if _pawn != null and _pawn.def != null else 1.0
	_head_height = RISE * model_scale
	if _pawn != null and _pawn.def != null and _pawn.def.hud_head_height > 0.0:
		# def 显式指定血条高度（供「静态 AABB 与实渲身高严重不符」的模型用，如 bocdagla 龙：
		# AABB 高 10.45 而实渲仅 ~5.68 单位，自动量测会把血条顶到半空）
		_head_height = _pawn.def.hud_head_height
	elif _pawn != null and _pawn.model_rig != null and _pawn.model_rig.has_model():
		# 只在模型配置时量一次；排除手持武器，长杖不应把血条顶到半空。
		_head_height = maxf(_head_height, _model_top(_pawn.model_rig, Transform3D.IDENTITY) + 0.28)
	_refresh_fill()


## 准星瞄准 / 集火复用 Pawn 的高亮生命周期，不另存一份目标。
func set_emphasized(on: bool) -> void:
	_emphasized = on


func head_height() -> float:
	return _head_height


func _model_top(node: Node, parent_transform: Transform3D) -> float:
	if node.name.begins_with("handslot") or node.name.begins_with("Outline"):
		return 0.0
	var local_transform := parent_transform
	if node is Node3D:
		local_transform *= (node as Node3D).transform
	var top := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).visible:
		var bounds: AABB = local_transform * (node as MeshInstance3D).get_aabb()
		top = bounds.end.y
	for child in node.get_children():
		top = maxf(top, _model_top(child, local_transform))
	return top


func _on_health_changed(cur: float, max_hp: float) -> void:
	var next := clampf(cur / max_hp if max_hp > 0.0 else 0.0, 0.0, 1.0)
	if next < _ratio:
		_chip_ratio = maxf(_chip_ratio, _ratio)
		_chip_hold = CHIP_HOLD_SEC
	elif next > _ratio:
		# 治疗立即清除旧伤害残影，避免把回复误读为掉血。
		_chip_ratio = next
		_chip_hold = 0.0
	if not is_equal_approx(next, _ratio):
		_recent_change = RECENT_CHANGE_SEC
	_ratio = next
	_refresh_fill()
	if cur <= 0.0:
		_on_died()


func _on_died() -> void:
	visible = false
	_opacity = 0.0
	_chip_ratio = _ratio
	_chip_hold = 0.0


func _process(delta: float) -> void:
	_recent_change = maxf(0.0, _recent_change - delta)
	if _chip_hold > 0.0:
		_chip_hold = maxf(0.0, _chip_hold - delta)
	else:
		_chip_ratio = move_toward(_chip_ratio, _ratio, delta * CHIP_DRAIN_SPEED)
	_refresh_fill()
	var cam := get_viewport().get_camera_3d()
	_follow(cam)
	var show_bar := _should_show(cam, delta)
	_opacity = move_toward(_opacity, 1.0 if show_bar else 0.0, delta * 8.0)
	# 死亡 / 无相机 / 屏幕后方立即收起，普通条件变化淡出。
	if _ratio <= 0.0 or (_pawn != null and (_pawn.is_dead_flag or not _pawn.is_visible_in_tree())) or cam == null:
		_opacity = 0.0
	elif cam.is_position_behind(global_position):
		_opacity = 0.0
	visible = _opacity > 0.001
	for sprite in [_edge, _bg, _chip, _fg]:
		var color: Color = sprite.modulate
		color.a = _opacity
		sprite.modulate = color


func _should_show(cam: Camera3D, delta: float) -> bool:
	if _pawn == null or _health == null or _pawn.is_dead_flag or _health.is_dead() or cam == null:
		return false
	if cam.is_position_behind(global_position):
		return false
	var viewport_size := get_viewport().get_visible_rect().size
	var screen := cam.unproject_position(global_position)
	if not Rect2(Vector2.ZERO, viewport_size).grow(60.0).has_point(screen):
		return false
	# 显示距离档位看「实际相机」：等距相机（战术俯瞰 / 俯视角主控）用战术档，
	# 越肩亲征用近距离语境档（受伤 / 交战 / 敌对等才显示）
	var tactical := SelectionManager.view_mode != SelectionManager.ViewMode.HERO
	var distance := cam.global_position.distance_to(_pawn.global_position)
	if tactical:
		return distance <= TACTICAL_RANGE
	var enemy := _pawn.team_comp != null and _pawn.team_comp.team == TeamComponent.Team.ENEMY
	var show_context := _ratio < 0.999 or _recent_change > 0.0 or _pawn.is_selected or _emphasized \
		or is_instance_valid(_pawn.follow_leader) or is_instance_valid(_pawn.combat_target) or enemy
	if not show_context or distance > (ENEMY_RANGE if enemy and not _emphasized else HERO_RANGE):
		return false
	# 稀疏物理查询，仅对屏内且需要展示的血条执行；单位层与拾取层不参与遮挡。
	if cam != _last_camera:
		_last_camera = cam
		_occlusion_left = 0.0
	_occlusion_left -= delta
	if _occlusion_left <= 0.0:
		_occlusion_left = OCCLUSION_INTERVAL
		var query := PhysicsRayQueryParameters3D.create(cam.global_position,
			_pawn.global_position + Vector3.UP * head_height() * 0.85, 1 | 8)
		query.exclude = [_pawn.get_rid()]
		_occluded = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	return not _occluded


func _follow(cam: Camera3D) -> void:
	var parent := get_parent() as Node3D
	if parent == null:
		return
	global_position = parent.global_position + Vector3.UP * head_height()
	if cam == null:
		return
	# 完整相机基底：填充左边缘在俯仰 / 横移 / 俯瞰下都与槽位严格重合。
	global_basis = cam.global_basis.orthonormalized()
	var viewport_size := get_viewport().get_visible_rect().size
	var viewport_height := maxf(viewport_size.y, 1.0)
	var depth := maxf(0.1, -(cam.global_transform.affine_inverse() * global_position).z)
	var view_span := cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * depth * tan(deg_to_rad(cam.fov) * 0.5)
	# KEEP_WIDTH 时 fov/size 对应水平跨度，先换算成垂直跨度。
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		view_span *= viewport_height / maxf(viewport_size.x, 1.0)
	var pixels := TARGET_PIXELS * clampf(viewport_height / 900.0, 0.75, 1.35)
	if _emphasized or (_pawn != null and _pawn.def != null and _pawn.def.is_boss):
		pixels *= 1.2
	var world_scale := clampf(pixels * view_span / viewport_height / FULL_W, 0.02, 2.5)
	scale = Vector3.ONE * world_scale
	_edge.modulate = COLOR_FOCUS if _emphasized else COLOR_EDGE


func _refresh_fill() -> void:
	if not is_instance_valid(_fg):
		return
	_set_fill(_fg, _ratio)
	_set_fill(_chip, _chip_ratio)
	_chip.visible = _chip_ratio > _ratio + 0.001
	_fg.visible = _ratio > 0.0
	var warning := clampf((LOW_THRESHOLD - _ratio) / LOW_THRESHOLD, 0.0, 1.0)
	_fg.modulate = _base_color.lerp(COLOR_LOW, warning * 0.65)


func _set_fill(sprite: Sprite3D, ratio: float) -> void:
	# 零血量隐藏网格而不使用零缩放（避免奇异变换）；左端始终固定。
	sprite.scale.x = maxf(ratio, 0.0001)
	sprite.position.x = -FULL_W * 0.5 * (1.0 - ratio)


func _new_sprite(sprite_name: String, color: Color, sx: float, sy: float, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = sprite_name
	sprite.texture = _tex
	sprite.pixel_size = PIXEL_SIZE
	sprite.modulate = color
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.render_priority = priority
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.scale = Vector3(sx, sy, 1.0)
	add_child(sprite)
	return sprite


static func _ensure_tex() -> void:
	if _tex != null:
		return
	var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_tex = ImageTexture.create_from_image(img)
