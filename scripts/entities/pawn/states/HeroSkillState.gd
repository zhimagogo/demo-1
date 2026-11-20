class_name HeroSkillState
extends PawnState
## 主角技能：按 SkillDef.target_kind 派发执行。
## - SELF_AOE：自身周围持续 AoE（多 tick 造伤 + 旋转光环）
## - DIRECTIONAL_DASH：沿朝向快速冲刺 + 位移全程逐帧扫掠造伤（每个敌人至多吃一次）+ 拖尾
## - PROJECTILE / BUFF：预留分支（本次仅占位 TODO，为弓箭手 / 法师扩展）
## 三相位 windup → active(duration) → recovery。

var _skill: SkillDef
var _phase: int = 0
var _timer: float = 0.0
var _tick_timer: float = 0.0
var _dir: Vector3 = Vector3.FORWARD
var _spin: float = 0.0            # 旋风斩刀光的方位角（每个 tick 递增，绕身扫一圈）
var _dash_prev_pos: Vector3       # 冲锋上一物理帧位置（扫掠伤害的线段起点）
var _dash_hit_ids: Dictionary = {}  # 本次冲锋已命中的敌人（instance_id → true），每个只吃一次伤害


func enter(msg: Dictionary) -> void:
	var h := pawn as Hero
	var index := int(msg.get("index", 0))
	if h == null or h.hero_def == null or index < 0 or index >= h.hero_def.skills.size():
		state_machine.transition_to("hero_idle")
		return
	_skill = h.hero_def.skills[index]
	_phase = 0
	_timer = 0.0
	_tick_timer = 0.0
	# 朝向：优先鼠标方向，否则当前朝向
	_dir = h.aim_dir.normalized() if h.aim_dir.length_squared() > 0.001 else h.facing_dir()
	h.look_at_target(_dir)
	h.velocity = Vector3.ZERO
	var anim_id: StringName = _skill.anim_id
	if anim_id == &"":
		anim_id = _default_anim()
	if h.animator != null:
		h.animator.play(anim_id, {})


func _default_anim() -> StringName:
	match _skill.target_kind:
		SkillDef.TargetKind.SELF_AOE: return &"skill_aoe"
		SkillDef.TargetKind.DIRECTIONAL_DASH: return &"skill_dash"
		_: return &"skill_aoe"


func physics_update(delta: float) -> void:
	var h := pawn as Hero
	if h == null or _skill == null:
		return
	_timer += delta
	match _phase:
		0:  # windup
			h.velocity = Vector3.ZERO
			h.move_and_slide()
			if _timer >= _skill.windup:
				_phase = 1
				_timer = 0.0
				_on_active_start(h)
		1:  # active
			_active_update(h, delta)
			if _timer >= _skill.duration:
				_phase = 2
				_timer = 0.0
		2:  # recovery
			h.velocity = Vector3.ZERO
			h.move_and_slide()
			if _timer >= _skill.recovery:
				state_machine.transition_to("hero_idle")


func _on_active_start(h: Hero) -> void:
	match _skill.target_kind:
		SkillDef.TargetKind.SELF_AOE:
			var vid: StringName = _skill.vfx_id
			if vid == &"":
				vid = &"whirlwind_aura"
			VFXManager.spawn_effect(vid, h.global_position, 0.0, {"lifetime": _skill.duration})
			AudioManager.play_sfx(_skill.sfx_id, h.global_position)
			_spin = 0.0
			_spawn_spin_slash(h)      # 起手一道刀光，之后每个 tick 再补一道 → 旋风斩的连续扫击感
		SkillDef.TargetKind.DIRECTIONAL_DASH:
			var vid: StringName = _skill.vfx_id
			if vid == &"":
				vid = &"charge_trail"
			VFXManager.spawn_effect(vid, h.global_position, h.rotation.y)
			AudioManager.play_sfx(_skill.sfx_id, h.global_position)
			# 冲锋斩：起手一道顺朝向的重击刀光
			VFXManager.spawn_effect(&"slash_arc_heavy", h.global_position + _dir * 1.0 + Vector3(0.0, 1.05, 0.0),
				atan2(-_dir.x, -_dir.z))
			# 扫掠伤害从起点开始：记下起始位置并清空命中名单
			_dash_prev_pos = h.global_position
			_dash_hit_ids.clear()
		# TODO：PROJECTILE（弓箭手）/ BUFF（法师）将来扩展
		_: pass


## 旋风斩：刀光绕主角扫一圈（每 tick 换一个方位，弧面本身自带扫动）。
## 弧面距离按技能半径外推（半径 × 0.58 ≈ 弧面外沿贴到伤害圈边）——
## 旧版固定 1.15m，刀光明显小于 whirlwind_aura 的伤害范围，看着「转了个寂寞」。
func _spawn_spin_slash(h: Hero) -> void:
	_spin += 2.35
	var dir := Vector3(sin(_spin), 0.0, cos(_spin))
	var ring_dist: float = clampf(_skill.radius * 0.58, 0.9, 2.6)
	VFXManager.spawn_effect(&"slash_arc", h.global_position + dir * ring_dist + Vector3(0.0, 1.0, 0.0),
		atan2(-dir.x, -dir.z), {"spin_scale": 1.0 if fmod(_spin, TAU) < PI else -1.0})


func _active_update(h: Hero, delta: float) -> void:
	match _skill.target_kind:
		SkillDef.TargetKind.SELF_AOE:
			_tick_timer += delta
			if _tick_timer >= _skill.tick_interval:
				_tick_timer = 0.0
				var targets := h.acquire_enemies_in_arc(h.global_position, Vector3.FORWARD, _skill.radius, PI)
				h.apply_damage_to(targets, _skill.damage)
				_spawn_spin_slash(h)
				# v28：旋风斩逐跳命中反馈——每个被卷进的敌人身上定向喷火星
				# （旧版只有伤害数字没有命中表现，旋风「转了个寂寞」的另一半原因）
				for t in targets:
					if not is_instance_valid(t):
						continue
					var tn: Node3D = t
					var away: Vector3 = tn.global_position - h.global_position
					away.y = 0.0
					if away.length_squared() < 0.0001:
						continue
					VFXManager.spawn_hit_impact(tn.global_position + Vector3(0.0, 1.05, 0.0),
						Color(0.72, 0.9, 1.0), &"hit_spark",
						"%d_%d" % [h.get_instance_id(), tn.get_instance_id()],
						atan2(-away.x, -away.z))
		SkillDef.TargetKind.DIRECTIONAL_DASH:
			var dash_speed: float = _skill.dash_distance / maxf(_skill.duration, 0.02)
			h.velocity = _dir * dash_speed
			h.move_and_slide()
			_dash_sweep_damage(h)
		_: pass


## 冲锋扫掠伤害：把上一物理帧到当前位置的位移线段整段纳入判定（点到线段距离），
## 线段旁 `_skill.radius * 0.5` 半宽内的敌人**每个只吃一次伤害**——
## 位移的一整串都有伤害，不再依赖稀疏 tick 取样（高速冲刺漏判 / 已越过者判不到）。
func _dash_sweep_damage(h: Hero) -> void:
	var from := _dash_prev_pos
	var to := h.global_position
	_dash_prev_pos = to
	var half_width: float = _skill.radius * 0.5
	for e in h.get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or _dash_hit_ids.has(e.get_instance_id()):
			continue
		var en: Node3D = e
		if _dist_xz_to_segment(en.global_position, from, to) > half_width:
			continue
		_dash_hit_ids[e.get_instance_id()] = true
		h.apply_damage_to([e], _skill.damage)
		# 命中反馈：定向火星锥 + 白闪 + 冲击环落在目标体表（沿冲锋方向喷溅，v28）
		var sweep_yaw := atan2(-_dir.x, -_dir.z)
		VFXManager.spawn_hit_impact(en.global_position + Vector3(0.0, 1.05, 0.0),
			Color(1.0, 0.6, 0.3), &"hit_spark",
			"%d_%d" % [h.get_instance_id(), e.get_instance_id()], sweep_yaw)


## 点 p 到线段 ab 的水平距离（忽略高度差，与 acquire_enemies_in_arc 同一套 XZ 判定口径）。
func _dist_xz_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := Vector3(p.x - a.x, 0.0, p.z - a.z)
	var ba := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var denom := ba.length_squared()
	var t := 0.0 if denom < 0.0001 else clampf(pa.dot(ba) / denom, 0.0, 1.0)
	return (pa - ba * t).length()
