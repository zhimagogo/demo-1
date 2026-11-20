class_name HeroComboState
extends PawnState
## 主角普攻单段：三相位 windup → active → recovery。
## - windup：原地蓄力动画（不向前上步，出招不打断站位）
## - active：对前方扇形内敌人一次性造伤 + 斩击弧 / 命中迸发特效 + 音效 + 顿帧
## - recovery：收招；若有连招缓冲且还能下一段 → 继续，否则回 hero_idle

var _phase: int = 0              # 0=windup 1=active 2=recovery
var _timer: float = 0.0
var _hit: ComboHitDef
var _applied: bool = false
var _frozen: float = 0.0         # 顿帧剩余（命中停顿）


func enter(msg: Dictionary) -> void:
	var h := pawn as Hero
	var step := int(msg.get("step", 1))
	if h == null or h.hero_def == null or step < 1 or step > h.hero_def.combo_hits.size():
		state_machine.transition_to("hero_idle")
		return
	_hit = h.hero_def.combo_hits[step - 1]
	_phase = 0
	_timer = 0.0
	_applied = false
	_frozen = 0.0
	h.velocity = Vector3.ZERO
	if h.aim_dir.length_squared() > 0.001:
		h.look_at_target(h.aim_dir)
	var anim_id: StringName = _hit.anim_id
	if anim_id == &"":
		anim_id = &"combo_heavy" if step == h.hero_def.combo_hits.size() else &"combo_light"
	if h.animator != null:
		h.animator.play(anim_id, {})


func physics_update(delta: float) -> void:
	var h := pawn as Hero
	if h == null or _hit == null:
		return
	# 顿帧：冻结时间线
	if _frozen > 0.0:
		_frozen = max(0.0, _frozen - delta)
		h.velocity = Vector3.ZERO
		h.move_and_slide()
		return
	_timer += delta
	match _phase:
		0:  # windup：原地蓄力（不再向前突进；保留竖直速度：空中出招不瞬坠）
			var v := Vector3.ZERO
			v.y = h.velocity.y if not h.is_on_floor() else 0.0
			h.velocity = v
			h.move_and_slide()
			if _timer >= _hit.windup:
				_phase = 1
				_timer = 0.0
		1:  # active：命中一次
			h.velocity = Vector3.ZERO
			h.move_and_slide()
			if not _applied:
				_apply_hit(h)
				_applied = true
			if _timer >= _hit.active:
				_phase = 2
				_timer = 0.0
		2:  # recovery
			h.velocity = Vector3.ZERO
			h.move_and_slide()
			if _timer >= _hit.recovery:
				_finish(h)


func _apply_hit(h: Hero) -> void:
	var fwd := h.facing_dir()
	var targets := h.acquire_enemies_in_arc(h.global_position, fwd, _hit.range, _hit.half_arc)
	h.apply_damage_to(targets, _hit.damage)
	# 第三人称亲自采集：同一挥砍顺带砍伐扇形内的树木 / 岩石（即时入库，等同村民一次采集量）
	var nodes := h.harvest_nodes_in_arc(h.global_position, fwd, _hit.range + 0.6, _hit.half_arc + 0.25)
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var rn := n as ResourceNode
		var gained: int = rn.harvest_by(h)
		if gained > 0:
			EventBus.hero_harvested.emit(rn, rn.yield_resource, gained)
	# 斩击刀光（月牙弧面，朝攻击方向；第 3 段重击更粗更亮、带暖色）
	var vid: StringName = _hit.vfx_id
	if vid == &"":
		vid = &"slash_arc"
	if h.hero_def != null and _hit.step >= h.hero_def.combo_hits.size():
		vid = &"slash_arc_heavy"
	var rot_y := atan2(-fwd.x, -fwd.z)
	VFXManager.spawn_effect(vid, h.global_position + fwd * clampf(_hit.range * 0.32, 0.6, 1.15) + Vector3(0.0, 1.05, 0.0), rot_y)
	# v28：收招段重击落地震波——第 3 段（收招段）在脚下炸一圈金白冲击环
	if h.hero_def != null and _hit.step >= h.hero_def.combo_hits.size():
		VFXManager.spawn_effect(&"heavy_shock", h.global_position + Vector3(0.0, 0.2, 0.0), rot_y)
	# 命中反馈：定向火星锥 + 白闪 + 冲击环，落在真实命中点（目标体表，不是主角脚下）
	for t in targets:
		if is_instance_valid(t):
			var tn: Node3D = t
			VFXManager.spawn_hit_impact(_impact_point(h, tn.global_position), Color(1.0, 0.86, 0.45),
				&"hit_spark", "%d_%d" % [h.get_instance_id(), tn.get_instance_id()], rot_y)
	# 砍伐木屑 / 石屑（每个被砍资源节点）
	for n in nodes:
		if is_instance_valid(n):
			var nn: Node3D = n
			var rn := n as ResourceNode
			var chip := Color(0.85, 0.66, 0.42) if rn != null and rn.yield_resource == GameDefs.WOOD \
				else Color(0.82, 0.84, 0.88)
			VFXManager.spawn_hit_impact(_impact_point(h, nn.global_position, 1.25), chip,
				&"hit_spark", "%d_%d" % [h.get_instance_id(), nn.get_instance_id()])
	# 音效：命中敌人为主；只砍到资源时用伐木 / 采矿声
	var sid: StringName = _hit.sfx_id
	if targets.is_empty() and not nodes.is_empty():
		sid = &"chop_wood" if (nodes[0] as ResourceNode).yield_resource == GameDefs.WOOD else &"mine_stone"
	AudioManager.play_sfx(sid, h.global_position)
	# 顿帧（命中停顿）
	if _hit.hit_stop > 0.0 and (not targets.is_empty() or not nodes.is_empty()):
		_frozen = _hit.hit_stop


## 命中点：目标朝向攻击者一侧的体表、约胸口高度（既不是主角脚下，也不是目标中心）。
func _impact_point(h: Hero, target_pos: Vector3, height: float = 1.05) -> Vector3:
	var to := target_pos - h.global_position
	to.y = 0.0
	var p := target_pos + Vector3(0.0, height, 0.0)
	if to.length_squared() > 0.0001:
		p -= to.normalized() * 0.45
	return p


func _finish(h: Hero) -> void:
	# 有输入缓冲且还能连下一段 → 继续
	if h._pending_combo and h._combo_step < h.hero_def.combo_hits.size():
		h._pending_combo = false
		h._start_combo(h._combo_step + 1)
	else:
		h._pending_combo = false
		state_machine.transition_to("hero_idle")
