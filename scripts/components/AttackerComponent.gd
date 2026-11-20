class_name AttackerComponent
extends Node
## 攻击能力组件：伤害 / 射程 / 冷却。
## try_attack(target) 内部调用目标 HealthComponent.apply_damage。
## owner 位置取 get_parent()（要求挂在 Node3D 下）。

@export var damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
# 攻击类型：MELEE 即时伤害 / RANGED 生成飞行投射物（见 _spawn_projectile）
@export var attack_kind: int = PawnDef.AttackKind.MELEE
@export var projectile_speed: float = 16.0

const SELF_RADIUS: float = 0.4   # owner（Pawn/Building）的近似碰撞半径
const MAX_ACTIVE_PROJECTILES: int = 72

var _cooldown_left: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = max(0.0, _cooldown_left - delta)


func try_attack(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _cooldown_left > 0.0:
		return false
	var health: HealthComponent = _get_health(target)
	if health == null or health.is_dead():
		return false
	if not in_range(target):
		return false
	# 按 attack_kind 分叉：近战即时伤害 / 远程生成飞行投射物（暴击在各自分支掷骰）
	if attack_kind == PawnDef.AttackKind.RANGED:
		_spawn_projectile(target)
	else:
		var rolled: Array = _roll_crit(damage)
		health.apply_damage(rolled[0], get_parent())
		if rolled[1]:
			_emit_crit_feedback(target)
		AudioManager.play_sfx(&"hit_1" if randf() < 0.5 else &"hit_2", (target as Node3D).global_position)
		_spawn_melee_vfx(target)
	# v26 驯龙：主角 RTS 态下令普攻也计入「玩家打谁」（宠物龙同步目标；其他单位无此方法）
	if get_parent().has_method("note_attack_target"):
		get_parent().call("note_attack_target", target)
	_cooldown_left = attack_cooldown
	return true


# ---- v20 属性系统 · 暴击 ----

## 暴击掷骰：owner（小兵 Pawn）实现了 crit_chance() 且掷中 → 按暴击倍率放大。
## 返回 [伤害, 是否暴击]；非 Pawn owner（箭塔）与无暴击率单位原样返回。
## 主角 crit_stat 默认 0（HeroDef 未配暴击），连招走 Hero.apply_damage_to 不经此处。
func _roll_crit(base: float) -> Array:
	var o := get_parent()
	if o is Pawn:
		var p := o as Pawn
		if p.crit_chance() > 0.0 and randf() < p.crit_chance():
			return [base * p.crit_multiplier(), true]
	return [base, false]


## 暴击命中反馈：目标头顶橙红「暴击！」飘字（伤害数字本身走 damage_dealt，
## 暴击的大数值自动命中 FloatingLabels 的金色大字分支）+ 金色星芒炸开（v27）。
func _emit_crit_feedback(target: Node) -> void:
	if target is Node3D and is_instance_valid(target):
		var tn := target as Node3D
		EventBus.floating_text.emit("暴击！", Color(1.0, 0.45, 0.2),
			tn.global_position + Vector3(0.0, 2.05, 0.0))
		# 会心星芒：与飘字同点位爆开，暴击读感从「一行字」升级为「一次可感知的重击」
		VFXManager.spawn_effect(&"crit_burst", tn.global_position + Vector3(0.0, 1.2, 0.0), 0.0,
			{"throttle_key": "%d_%d" % [get_parent().get_instance_id() if get_parent() != null else 0, tn.get_instance_id()]})


## 近战攻击特效：按职业分派挥击弧光 + 命中点「火星 + 冲击环」。
## 只在真正出招的这一帧调用（受 attack_cooldown 约束），不会每帧生成。
func _spawn_melee_vfx(target: Node) -> void:
	var owner_node := get_parent() as Node3D
	if owner_node == null or not (target is Node3D):
		return
	var tn := target as Node3D
	var profile := VFXManager.attack_profile(_owner_def())
	var key := "%d_%d" % [owner_node.get_instance_id(), tn.get_instance_id()]
	# v28：定向喷溅朝向 =「攻击者 → 目标」水平角（与武器朝向无关，命中喷溅永远向外喷）
	var to_target := tn.global_position - owner_node.global_position
	to_target.y = 0.0
	var hit_yaw: float = 0.0
	if to_target.length_squared() > 0.0001:
		hit_yaw = atan2(-to_target.x, -to_target.z)
	# 挥击弧光：只有 Pawn 才有挥砍动作（建筑如箭塔只出命中火花）
	if owner_node is Pawn and profile["arc"] != &"":
		var fwd := _flat_forward(owner_node)
		var rot_y := atan2(-fwd.x, -fwd.z)
		var arc_id: StringName = profile["arc"]
		var pos := owner_node.global_position + fwd * float(profile["arc_dist"]) \
			+ Vector3(0.0, float(profile["arc_height"]), 0.0)
		if profile["arc_double"]:
			# 刺客双匕首：左右手各一道窄弧，扫动方向相反
			var perp := Vector3(fwd.z, 0.0, -fwd.x)
			VFXManager.spawn_effect(arc_id, pos + perp * 0.24, rot_y + 0.22, {"spin_scale": -1.0})
			VFXManager.spawn_effect(arc_id, pos - perp * 0.24, rot_y - 0.22, {"spin_scale": 1.0})
		else:
			VFXManager.spawn_effect(arc_id, pos, rot_y)
	VFXManager.spawn_hit_impact(_impact_point(owner_node.global_position, tn.global_position),
		profile["impact_color"], profile["impact"], key, hit_yaw)


## 命中点：目标朝向攻击者一侧的体表、约胸口高度（避免特效落在目标中心或攻击者脚下）。
func _impact_point(from: Vector3, target_pos: Vector3, height: float = 1.05) -> Vector3:
	var to := target_pos - from
	to.y = 0.0
	var p := target_pos + Vector3(0.0, height, 0.0)
	if to.length_squared() > 0.0001:
		p -= to.normalized() * 0.45
	return p


## 水平朝向（Pawn 逻辑前方 = 本地 -Z）。
func _flat_forward(node: Node3D) -> Vector3:
	var f := -node.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


## owner 的 PawnDef（建筑 / 无 def 单位返回 null → 走通用档案）。
func _owner_def() -> PawnDef:
	var o := get_parent()
	if o is Pawn and (o as Pawn).def != null:
		return (o as Pawn).def
	return null


## 远程攻击：生成一支追踪目标的箭矢，命中后才结算伤害。
func _spawn_projectile(target: Node) -> void:
	var profile := VFXManager.attack_profile(_owner_def())
	_spawn_projectile_ex(target, damage, profile["proj_tint"])


## 职业技能投射物入口（v19）：以覆盖伤害 / 弹体颜色生成一支职业档案外观的箭矢
## （游侠快速射击的金箭等），尾迹 / 命中爆散 / 枪口闪光仍按职业档案分派。
func launch_projectile(target: Node, dmg: float, tint: Color) -> void:
	_spawn_projectile_ex(target, dmg, tint)


func _spawn_projectile_ex(target: Node, dmg: float, tint: Color) -> void:
	var owner_node: Node3D = get_parent()
	var profile := VFXManager.attack_profile(_owner_def())
	var p := Projectile.new()
	# v20 暴击：发射瞬间掷骰定伤（命中时由 Projectile 按 is_crit 补飘字反馈）
	var rolled: Array = _roll_crit(dmg)
	p.damage = rolled[0]
	p.is_crit = rolled[1]
	p.speed = projectile_speed
	p.target = target
	p.source = owner_node
	# 投射物外观 / 尾迹 / 命中爆散按职业档案分派（游侠 = 白色速度线，法师 = 紫色法术弹）
	p.trail_effect = profile["trail"]
	p.impact_effect = profile["impact"]
	p.impact_color = profile["impact_color"]
	p.visual_kind = int(profile["visual_kind"])
	p.body_color = tint
	# 投射物容器（Main 建 "Projectiles" 并入 "projectiles" 分组）；兜底挂到 owner 父节点
	var container := get_tree().get_first_node_in_group("projectiles")
	if container != null and container.get_child_count() >= MAX_ACTIVE_PROJECTILES:
		return
	if container != null:
		container.add_child(p)
	else:
		owner_node.get_parent().add_child(p)
	# 挂树后再设全局位置/速度（挂树前 global_position 等于 local，会被父节点 transform 覆盖）
	p.global_position = owner_node.global_position + Vector3(0, Projectile.SOURCE_HEIGHT, 0)
	var dir: Vector3 = target.global_position - p.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.0001:
		p._velocity = dir.normalized() * projectile_speed
	else:
		p._velocity = Vector3.FORWARD * projectile_speed
	# 出招瞬间：枪口十字星 / 法杖蓄力微光（只在真正发射的这一帧）
	var fwd := _flat_forward(owner_node)
	var rot_y := atan2(-fwd.x, -fwd.z)
	var muzzle_id: StringName = profile["muzzle"]
	if muzzle_id != &"":
		VFXManager.spawn_effect(muzzle_id, owner_node.global_position + fwd * float(profile["muzzle_dist"])
			+ Vector3(0.0, float(profile["muzzle_height"]), 0.0), rot_y,
			{"throttle_key": owner_node.get_instance_id()})
	var cast_id: StringName = profile["cast"]
	if cast_id != &"":
		# 施法微光走档案独立的高度 / 距离（法师举杖过头，与枪口闪光的持弩高度分开调）
		VFXManager.spawn_effect(cast_id, owner_node.global_position + fwd * float(profile.get("cast_dist", 0.45))
			+ Vector3(0.0, float(profile.get("cast_height", profile["muzzle_height"])), 0.0), rot_y,
			{"throttle_key": owner_node.get_instance_id()})
	AudioManager.play_sfx(&"arrow_shoot", owner_node.global_position)


func in_range(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var owner_node: Node3D = get_parent()
	var target_node: Node3D = target
	# 表面到表面距离：中心距扣减双方近似半径。
	# 让单位贴在大型障碍（基地/建筑）边缘时仍判定可达。
	var center_dist: float = owner_node.global_position.distance_to(target_node.global_position)
	return center_dist - SELF_RADIUS - _estimate_radius(target_node) <= attack_range


## 返回近战单位应在目标周围保持的站位半径（中心到中心）。
## 让状态机可以为多个攻击者分配不同落点，而不是全部寻路到目标中心。
func preferred_standoff_distance(target: Node) -> float:
	if target == null or not is_instance_valid(target):
		return attack_range
	return SELF_RADIUS + _estimate_radius(target) + attack_range * 0.78


## 估算目标碰撞半径：从其 CollisionShape3D 推断（Box 取 max(x,z)/2，Cylinder 取 radius）。
func _estimate_radius(node: Node) -> float:
	if node is StaticBody3D:
		for c in node.get_children():
			if not (c is CollisionShape3D):
				continue
			var shape: Shape3D = (c as CollisionShape3D).shape
			if shape is BoxShape3D:
				var sz: Vector3 = (shape as BoxShape3D).size
				return max(sz.x, sz.z) * 0.5
			if shape is CylinderShape3D:
				return (shape as CylinderShape3D).radius
	return 0.4   # 默认 Pawn 胶囊半径


func _get_health(node: Node) -> HealthComponent:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null("HealthComponent")
