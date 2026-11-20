class_name SkillPiercingShot
extends Node3D
## ============================================================================
## 贯穿射击弹体（v33 狙击手）：PawnSkillComponent 瞬发时生成，沿施法瞬间锁定的
## 水平方向直线飞行，全程 pierce_length 米（或超时兜底），**沿途每个敌人只结算一次**。
##
## 命中判定：逐物理帧对「本帧位移线段」做点到线段距离（XZ 平面）——
## 高速弹体不会因为离散步进穿过目标（与 Projectile 的距离判定同思路，但支持横扫多目标）。
## 不参与任何物理重叠（无碰撞形状、无 monitoring），故不影响其它系统的物理查询。
##
## visual：VFXManager 的 pierce_trail（随体拖尾，attach_trail）+ pierce_hit（命中点），
## 弹体本体为程序化「大号发光弹」，缺特效资源时依然可读。
## ============================================================================

const HIT_PAD: float = 0.30           # 命中半径附加值（人体半径容差）
const BODY_LENGTH: float = 1.25       # 弹体长度（比普通箭矢粗长，读得出「贯穿弹」）
const BODY_SIZE: float = 0.16         # 弹体横截面边长
const SHOT_COLOR := Color(1.0, 0.86, 0.42)   # 青白金（与快速射击金箭同色系、更大更亮）

var source: Node = null               # 施法者（伤害归属；可能中途失效）
var skill_def: PawnSkillDef = null    # 需要 damage / pierce_length / pierce_radius / pierce_speed
var direction: Vector3 = Vector3.FORWARD   # 水平飞行方向（施法瞬间锁定，不制导）

var _hostile_group: String = "enemy"
var _traveled: float = 0.0
var _life: float = 0.0
var _max_dist: float = 26.0
var _max_life: float = 2.0
var _hit_ids: Dictionary = {}         # 已结算过的目标 instance_id（每个目标只吃一次）
static var _body_mesh: BoxMesh = null
static var _body_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("skill_piercing_shot")
	if skill_def == null:
		queue_free()
		return
	if source is Pawn and (source as Pawn).team_comp != null \
			and (source as Pawn).team_comp.team == TeamComponent.Team.ENEMY:
		_hostile_group = "player_unit"
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	_max_dist = maxf(skill_def.pierce_length, 1.0)
	var speed: float = maxf(skill_def.pierce_speed, 1.0)
	_max_life = _max_dist / speed + 0.4   # 超时兜底（速度被改小 / 帧率异常也不永存）
	_build_body()
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction, Vector3.UP)
	# 随体拖尾（长尾；节点销毁即消失，不占活动特效配额）
	VFXManager.attach_trail(self, &"pierce_trail")


func _physics_process(delta: float) -> void:
	if skill_def == null:
		queue_free()
		return
	_life += delta
	var step: float = maxf(skill_def.pierce_speed, 1.0) * delta
	if step > _max_dist - _traveled:
		step = maxf(_max_dist - _traveled, 0.0)
	var from: Vector3 = global_position
	var to: Vector3 = from + direction * step
	_sweep(from, to)
	global_position = to
	_traveled += step
	if _traveled >= _max_dist - 0.001 or _life >= _max_life:
		queue_free()


## 本帧位移线段上的命中结算：XZ 平面点到线段距离 ≤ 判定半径即命中，每个目标只中一次。
func _sweep(from: Vector3, to: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	var hit_radius: float = maxf(skill_def.pierce_radius, 0.1) + HIT_PAD
	var hit_r2: float = hit_radius * hit_radius
	var src: Node = source if (source != null and is_instance_valid(source)) else null
	for v in tree.get_nodes_in_group(_hostile_group):
		if not (v is Pawn) or not is_instance_valid(v):
			continue
		var victim := v as Pawn
		if victim.is_dead_flag:
			continue
		var key := victim.get_instance_id()
		if _hit_ids.has(key):
			continue
		var p := Vector2(victim.global_position.x, victim.global_position.z)
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		if p.distance_squared_to(closest) > hit_r2:
			continue
		_hit_ids[key] = true
		_hit(victim, src)


func _hit(victim: Pawn, src: Node) -> void:
	victim.take_damage(skill_def.damage, src)
	var at: Vector3 = victim.global_position + Vector3(0.0, 1.05, 0.0)
	VFXManager.spawn_effect(&"pierce_hit", at, 0.0, {"throttle_key": victim.get_instance_id()})
	VFXManager.spawn_hit_impact(at, SHOT_COLOR, &"hit_spark", victim.get_instance_id(),
		atan2(-direction.x, -direction.z))
	AudioManager.play_sfx(&"arrow_hit", at)


## 弹体本体：细长发光盒（本地 -Z 为前方，与 look_at 对齐）。
func _build_body() -> void:
	if _body_mesh == null:
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = SHOT_COLOR
		_body_mat.emission_enabled = true
		_body_mat.emission = SHOT_COLOR
		_body_mat.emission_energy_multiplier = 2.4
		_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var bx := BoxMesh.new()
		bx.size = Vector3(BODY_SIZE, BODY_SIZE, BODY_LENGTH)
		bx.material = _body_mat
		_body_mesh = bx
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _body_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 亮核（让贯穿弹在夜战里也读得出来）
	var light := OmniLight3D.new()
	light.name = "ShotLight"
	light.light_color = SHOT_COLOR
	light.light_energy = 1.5
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)
