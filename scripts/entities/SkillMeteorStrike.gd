class_name SkillMeteorStrike
extends Node3D
## ============================================================================
## 陨石术落点实体（v33 元素法师）：PawnSkillComponent 吟唱结束时生成于
## 「吟唱开始瞬间锁定的目标位置」，生命周期 = 地面预警圈 → 陨石下落 → 落地结算 → 自毁。
##
## 关键玩法口径（契约 3.2）：**离开圈的敌人不受伤**——落地结算读的是受害者的
## 实时位置，不做受害者快照；预警期（telegraph 秒）就是留给敌人躲避的窗口。
##
## visual：VFXManager 的 meteor_telegraph（落点预警）/ meteor_fall（下落体）/
## meteor_impact（落地爆炸）；三者缺失或未注册时各自退回程序化兜底，
## headless 测试不依赖特效资源。
## ============================================================================

const FALL_LEAD: float = 0.45        # 落地前多少秒开始出现下落体（与 telegraph 取小值）
const FALL_HEIGHT: float = 13.0      # 下落起点高度（米）
const IMPACT_FADE: float = 0.30      # 落地后预警圈淡出时长
const RING_ALPHA: float = 0.26       # 预警圈不透明度（地面可读性）
const METEOR_COLOR := Color(1.0, 0.62, 0.22)   # 陨石暖橙
const RING_COLOR := Color(1.0, 0.42, 0.18)     # 预警圈红橙

var caster: Node3D = null              # 施法者（伤害归属；中途死亡不影响已落成的陨石）
var skill_def: PawnSkillDef = null     # 需要 radius / damage / telegraph

var _hostile_group: String = "enemy"   # 结算敌方分组（按施法阵营在 _ready 定死）
var _telegraph_left: float = 0.0       # 预警圈剩余秒数（归零即落地）
var _fade_left: float = 0.0
var _landed: bool = false
var _fall_started: bool = false
var _fall_from: Vector3 = Vector3.ZERO
var _fall_visual: Node3D = null        # VFX 下落体（或程序化兜底）
var _ring: MeshInstance3D = null       # 程序化地面预警圈（任何环境下都存在）
var _t: float = 0.0
static var _fallback_mesh: SphereMesh = null
static var _fallback_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("skill_meteor_strike")
	if skill_def == null:
		queue_free()
		return
	if caster is Pawn and (caster as Pawn).team_comp != null \
			and (caster as Pawn).team_comp.team == TeamComponent.Team.ENEMY:
		_hostile_group = "player_unit"
	_telegraph_left = maxf(skill_def.telegraph, 0.05)
	_build_ring()
	# 落点预警特效（按 AOE 实际半径撑开；vfx-dev 未注册时安静跳过，程序化圈仍在）
	VFXManager.spawn_effect(&"meteor_telegraph", global_position + Vector3(0.0, 0.05, 0.0), 0.0,
		{"lifetime": _telegraph_left + IMPACT_FADE + 0.2,
		"radius": skill_def.radius, "throttle_key": get_instance_id()})


func _physics_process(delta: float) -> void:
	_t += delta
	if not _landed:
		_telegraph_left -= delta
		_pulse_ring()
		if not _fall_started and _telegraph_left <= minf(FALL_LEAD, skill_def.telegraph):
			_begin_fall()
		_advance_fall()
		if _telegraph_left <= 0.0:
			_impact()
		return
	# 落地后：预警圈收缩淡出，随后自毁
	_fade_left -= delta
	if _ring != null:
		var k: float = clampf(_fade_left / maxf(IMPACT_FADE, 0.01), 0.0, 1.0)
		_ring.scale = Vector3(k, 1.0, k)
	if _fade_left <= 0.0:
		queue_free()


# ============================================================================
# 落地结算
# ============================================================================

func _impact() -> void:
	_landed = true
	_fade_left = IMPACT_FADE
	var d: PawnSkillDef = skill_def
	VFXManager.spawn_effect(&"meteor_impact", global_position + Vector3(0.0, 0.4, 0.0), 0.0,
		{"throttle_key": get_instance_id()})
	AudioManager.play_sfx(&"thunder", global_position)
	# 下落体使命完成（VFX 节点由 VFXManager 自行回收，这里只断开引用）
	_fall_visual = null
	_settle_area_damage(d)
	if _ring != null:
		var mat := _ring.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA * 1.6)


## 圈内结算：以**落地瞬间**的实际位置判定，走出圈的敌人自然免伤（躲避成立）。
func _settle_area_damage(d: PawnSkillDef) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var src: Node3D = caster if (caster != null and is_instance_valid(caster)) else null
	var r2: float = d.radius * d.radius
	for v in tree.get_nodes_in_group(_hostile_group):
		if not (v is Pawn) or not is_instance_valid(v):
			continue
		var victim := v as Pawn
		if victim.is_dead_flag:
			continue
		if _flat_dist_sq(global_position, victim.global_position) > r2:
			continue
		victim.take_damage(d.damage, src)
		VFXManager.spawn_hit_impact(victim.global_position + Vector3(0.0, 1.0, 0.0),
			METEOR_COLOR, &"hit_spark", victim.get_instance_id())


# ============================================================================
# 预警圈 / 下落体
# ============================================================================

## 地面预警圈：薄圆柱片（半径 = skill_def.radius），呼吸脉动 + 落地瞬间亮一档。
## 与 VFX 预警特效并存——程序化圈保证「任何环境下圈都在」，是躲避玩法的最低可读性。
func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "GroundRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = skill_def.radius
	cyl.bottom_radius = skill_def.radius
	cyl.height = 0.05
	_ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(RING_COLOR.r, RING_COLOR.g, RING_COLOR.b, RING_ALPHA)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.05, 0.0)
	add_child(_ring)


func _pulse_ring() -> void:
	if _ring == null:
		return
	var pulse := 1.0 + 0.03 * sin(_t * 9.0)
	_ring.scale = Vector3(pulse, 1.0, pulse)


## 下落体：优先用 VFXManager 的 meteor_fall（放到落点上空，由本节点逐帧压下来），
## 未注册 / 生成失败则用程序化火球兜底——表现可以缺，读感不能缺。
func _begin_fall() -> void:
	_fall_started = true
	_fall_from = global_position + Vector3.UP * FALL_HEIGHT
	var fx := VFXManager.spawn_effect(&"meteor_fall", _fall_from, 0.0,
		{"lifetime": maxf(minf(FALL_LEAD, skill_def.telegraph), 0.15) + 0.45,
		"throttle_key": get_instance_id()})
	if fx is Node3D:
		_fall_visual = fx as Node3D
	if _fall_visual == null:
		_fall_visual = _build_fallback_body()
	if _fall_visual != null:
		_fall_visual.global_position = _fall_from


func _advance_fall() -> void:
	if _fall_visual == null or not is_instance_valid(_fall_visual):
		_fall_visual = null
		return
	var window: float = maxf(minf(FALL_LEAD, skill_def.telegraph), 0.05)
	var k: float = clampf(1.0 - _telegraph_left / window, 0.0, 1.0)
	# 加速下坠（k²）：读起来是「砸下来」而不是匀速平移
	_fall_visual.global_position = _fall_from.lerp(global_position + Vector3.UP * 0.6, k * k)


func _build_fallback_body() -> Node3D:
	if _fallback_mesh == null:
		_fallback_mat = StandardMaterial3D.new()
		_fallback_mat.albedo_color = Color(1.0, 0.72, 0.3)
		_fallback_mat.emission_enabled = true
		_fallback_mat.emission = Color(1.0, 0.55, 0.18)
		_fallback_mat.emission_energy_multiplier = 2.2
		_fallback_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var sp := SphereMesh.new()
		sp.radius = maxf(skill_def.radius * 0.42, 0.6)
		sp.height = sp.radius * 2.0
		sp.material = _fallback_mat
		_fallback_mesh = sp
	var mi := MeshInstance3D.new()
	mi.name = "MeteorFallbackBody"
	mi.mesh = _fallback_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.name = "MeteorFallbackLight"
	light.light_color = Color(1.0, 0.58, 0.24)
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.shadow_enabled = false
	mi.add_child(light)
	# 作为落点实体的子节点：随落点一起自毁，不会在场景里留下无主火球
	add_child(mi)
	return mi


func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz
