class_name SkillBlizzardZone
extends Node3D
## ============================================================================
## 暴风雪技能场（v19 法师）：PawnSkillComponent 施放后在目标地点生成的
## 持续性 AoE 区域——地面冰蓝指示圈 + 顶部暴雪粒子帘，按 tick_interval 对圈内
## 敌方单位结算伤害并施加减速（slow_factor / slow_duration，逐跳刷新）。
## duration 结束后淡出并自毁；施法者死亡不影响已落成的暴风雪继续生效。
## ============================================================================

const FADE_SEC: float = 0.45          # 末段淡出时长（粒子停发、指示圈收缩）
const RING_ALPHA: float = 0.22        # 地面指示圈透明度
const FROST_COLOR := Color(0.55, 0.80, 1.00)

var caster: Node3D = null             # 施法者（伤害归属）
var skill_def: PawnSkillDef = null

var _hostile_group: String = "enemy"  # 结算敌方分组（按施法阵营在 setup 期定死）
var _life_left: float = 0.0
var _tick_left: float = 0.0
var _fade_left: float = 0.0
var _ring: MeshInstance3D = null
var _snow: GPUParticles3D = null
var _t: float = 0.0
static var _snow_mesh: QuadMesh = null


func _ready() -> void:
	add_to_group("skill_blizzard_zone")
	if skill_def == null:
		queue_free()
		return
	if caster is Pawn and (caster as Pawn).team_comp != null \
			and (caster as Pawn).team_comp.team == TeamComponent.Team.ENEMY:
		_hostile_group = "player_unit"
	_life_left = skill_def.duration
	_tick_left = 0.0   # 首跳立即结算
	_build_ring()
	_build_snow()


func _process(delta: float) -> void:
	_t += delta
	if _life_left > 0.0:
		_life_left -= delta
		# 指示圈呼吸脉动（战场可读性）
		if _ring != null:
			var pulse := 1.0 + 0.04 * sin(_t * 5.0)
			_ring.scale = Vector3(pulse, 1.0, pulse)
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left = skill_def.tick_interval
			_tick()
		if _life_left <= 0.0:
			_life_left = 0.0
			_begin_fade()
	elif _fade_left > 0.0:
		_fade_left -= delta
		if _ring != null:
			var k := maxf(_fade_left / FADE_SEC, 0.0)
			_ring.scale = Vector3(k, 1.0, k)
		if _fade_left <= 0.0:
			queue_free()


## 单跳结算：圈内敌方单位受伤 + 减速，脚下各冒一枚小冰环（节流）。
func _tick() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var radius: float = skill_def.radius
	var radius_sq := radius * radius
	var src: Node3D = caster if (caster != null and is_instance_valid(caster)) else null
	for v in tree.get_nodes_in_group(_hostile_group):
		if not (v is Pawn) or not is_instance_valid(v) or (v as Pawn).is_dead_flag:
			continue
		var victim := v as Pawn
		if global_position.distance_squared_to(victim.global_position) > radius_sq:
			continue
		victim.take_damage(skill_def.damage, src)
		victim.apply_slow(skill_def.slow_factor, skill_def.slow_duration)
		VFXManager.spawn_effect(&"hit_ring", victim.global_position + Vector3(0.0, 0.25, 0.0), 0.0,
			{"color": FROST_COLOR, "throttle_key": victim.get_instance_id(), "throttle_time": 0.30})


func _begin_fade() -> void:
	_fade_left = FADE_SEC
	if _snow != null:
		_snow.emitting = false


# ---- 视觉构建 ----

## 地面冰蓝指示圈：薄圆柱片 + 半透明 unshaded，一眼读出 AoE 边界。
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "GroundRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = skill_def.radius
	cyl.bottom_radius = skill_def.radius
	cyl.height = 0.06
	_ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(FROST_COLOR.r, FROST_COLOR.g, FROST_COLOR.b, RING_ALPHA)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.06, 0.0)
	add_child(_ring)


## 暴雪粒子帘：区域上方持续落雪（盒发射 + 向下重力，随区域本地坐标）。
func _build_snow() -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "BlizzardSnow"
	_snow.amount = clampi(int(skill_def.radius * 26.0), 40, 160)
	_snow.lifetime = 1.15
	_snow.one_shot = false
	_snow.local_coords = true
	_snow.fixed_fps = 30
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(skill_def.radius, 0.35, skill_def.radius)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 12.0
	mat.initial_velocity_min = 3.2
	mat.initial_velocity_max = 5.2
	mat.gravity = Vector3(0.0, -6.5, 0.0)   # 落雪带轻微漂移下坠
	mat.angular_velocity_min = -60.0
	mat.angular_velocity_max = 60.0
	mat.scale_min = 0.5
	mat.scale_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.94, 1.0, 0.0))
	grad.set_color(1, Color(0.55, 0.75, 1.0, 0.0))
	grad.add_point(0.15, Color(0.92, 0.97, 1.0, 0.95))
	grad.add_point(0.6, Color(0.72, 0.87, 1.0, 0.75))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	_snow.process_material = mat
	_snow.draw_pass_1 = _ensure_snow_mesh()
	_snow.position = Vector3(0.0, skill_def.radius * 0.9 + 1.6, 0.0)   # 雪帘悬在区域上空
	_snow.emitting = true
	_snow.custom_aabb = AABB(
		Vector3.ONE * -(skill_def.radius + 2.0),
		Vector3.ONE * (skill_def.radius + 2.0) * 2.0)
	add_child(_snow)


static func _ensure_snow_mesh() -> QuadMesh:
	if _snow_mesh != null:
		return _snow_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.13, 0.13)
	mesh.material = mat
	_snow_mesh = mesh
	return mesh
