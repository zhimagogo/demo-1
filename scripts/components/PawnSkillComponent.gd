class_name PawnSkillComponent
extends Node
## ============================================================================
## 小兵职业技能组件（v19 四技能 / v33 多技能）：
## Pawn._setup_nodes 检测到 def.skill 时挂载；FightState / RangedFightState 每帧调用
## pawn.try_cast_combat_skill(target)，按优先级逐个试技能，CD 就绪且条件满足即施放。
##
## 施放优先级（契约 3.2）= def.extra_skills（进阶技能先手）在前 + [def.skill] 在后。
## 每个技能独立 CD（cooldown_left(id)）；瞬发技能直接结算（不打断既有战斗站位逻辑），
## 带前摇 / 滞空的技能走 SkillCastState：try_cast 只负责起手，
## 之后由状态每物理帧调 tick_cast(delta) 推进「前摇 → 执行 → 收招」，
## 收招结束回调 pawn.end_skill_cast()。
##
## 八个 kind 的执行口径：
## - 法师 · 暴风雪：目标地点落下 SkillBlizzardZone，逐跳伤害 + 减速
## - 战士 · 血怒：自身增益 6s，伤害 ×1.5 + 造成伤害 60% 吸血
## - 游侠 · 快速射击：三连射金箭，并给目标挂 3s 易伤
## - 刺客 · 背刺：闪现目标身后 1.1m 重击（CD 就绪时优先先手）
## - 狂战士 · 跳劈（v33）：前摇蓄力 → 跃向锁定落点（超出 cast_range 钳到上限，
##   距目标 < 1.2m 原地起跳）→ 落地圆形 AOE + 击飞控制
## - 元素法师 · 陨石术（v33）：原地吟唱 → 在吟唱开始锁定的位置生成 SkillMeteorStrike
##   （预警圈 telegraph 秒后落地，离开圈的敌人不受伤）
## - 狙击手 · 贯穿射击（v33）：瞬发 SkillPiercingShot，直线贯穿、每个目标只吃一次
## - 暗杀者 · 隐身（v33）：未隐身 且（血量低于逃生血线 或 目标距离 ∈ (2.5, approach_range]）
##   → pawn.apply_stealth()
## ============================================================================

const RAGE_AURA_NAME := "RageAura"       # 血怒光环节点名（测试断言用）
const GOLD_ARROW := Color(1.0, 0.85, 0.35)   # 游侠快速射击金箭弹体色
const BACKSTAB_BEHIND_DIST: float = 1.1  # 背刺落点：目标身后的距离（米）

# ---- v33 跳劈 / 隐身参数 ----
const LEAP_MIN_TIME: float = 0.25        # 滞空时长下限（贴脸起跳也要有滞空读感）
const LEAP_MAX_TIME: float = 0.9         # 滞空时长上限
const LEAP_INPLACE_DIST: float = 1.2     # 距目标 < 此值 = 原地起跳（垂直起落）
const LEAP_RANGE_FALLBACK: float = 8.0   # cast_range 未配置时的跃击距离上限
const STEALTH_MIN_RANGE: float = 2.5     # 隐身：比这更近（贴脸）不算「接近目标」
const PIERCE_SOURCE_HEIGHT: float = 1.05 # 贯穿弹出手高度（胸口）

## 施法阶段（仅带前摇的技能会离开 NONE）
enum CastPhase { NONE, WINDUP, LEAP_AIR, RECOVER }

var pawn: Pawn = null
var skill: PawnSkillDef = null                    # 主技能（def.skill；v19 调用口径不变）
var skills: Array[PawnSkillDef] = []              # 全部技能，按施放优先级排列

# 每个技能独立冷却：id(StringName) -> 剩余秒数
var _cd: Dictionary = {}
var _def_ref: PawnDef = null                      # 已展开技能表的 def（转职换 def 后重建）

# 快速射击连发队列
var _shots_left: int = 0
var _shot_timer: float = 0.0
var _shot_target: Node = null
var _shot_skill: PawnSkillDef = null              # 本次连射所属技能（伤害/间隔口径）
# 血怒状态
var _rage_left: float = 0.0
var _rage_base_damage: float = 0.0
var _rage_aura: GPUParticles3D = null
var _rage_skill: PawnSkillDef = null              # 生效中的血怒技能（倍率/吸血口径）
# 共享光环粒子资源（血怒光环按外观键缓存，运行期不重复 new 材质）
static var _aura_mesh: QuadMesh = null
static var _aura_ramp: GradientTexture1D = null

# ---- v33 施法状态 ----
var _casting: bool = false
var _phase: int = CastPhase.NONE
var _phase_left: float = 0.0
var _cast_skill: PawnSkillDef = null              # 本次施放的技能（前摇 → 收招全程锁定）
var _cast_target: Node = null                     # 本次施放的目标（施法瞬间锁定）
var _last_tick_physics_frame: int = -1            # 最近一次 tick_cast 的物理帧（兜底自驱判重）
var _leap_from: Vector3 = Vector3.ZERO
var _leap_to: Vector3 = Vector3.ZERO
var _leap_dir: Vector3 = Vector3.ZERO
var _leap_duration: float = 0.0
var _leap_elapsed: float = 0.0
var _leap_ground_y: float = 0.0                   # 起跳时的地面高度（被打断时放回地面）
var _leap_trail: GPUParticles3D = null
var _meteor_locked_pos: Vector3 = Vector3.ZERO    # 陨石落点（吟唱开始瞬间锁定）


func _ready() -> void:
	pawn = get_parent() as Pawn
	_ensure_skills()
	# 血怒吸血：监听全局伤害结算（去中心化），只认自己造成的伤害
	EventBus.damage_dealt.connect(_on_damage_dealt)


func _process(delta: float) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	# def 晚注入（测试直接 new Pawn 后补 def）/ 转职换 def 都能接管
	_ensure_skills()
	if pawn.is_dead_flag:
		# 死亡打断施法：不结算效果、解除锁定（SkillCastState.exit 也会兜一刀）
		if _casting:
			abort_cast()
		return
	_tick_cooldowns(delta)
	# 快速射击连发：按间隔逐箭射出（目标死了就中断）
	if _shots_left > 0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_fire_rapid_shot()
	# 血怒计时：到点还原伤害面板、撤光环
	if _rage_left > 0.0:
		_rage_left -= delta
		if _rage_left <= 0.0:
			_end_blood_rage()
	# 施法推进兜底：SkillCastState 每物理帧调 tick_cast()；若本物理帧没人调
	# （施法态未注册 / Pawn 侧 API 尚未落地），由 _process 自驱，避免技能卡死在前摇。
	if _casting and Engine.get_physics_frames() != _last_tick_physics_frame:
		_advance_cast(delta)


## 战斗状态每帧调用：按优先级逐个试技能，第一个 CD 就绪 + 条件满足即施放并返回 true
## （调用方本帧不再普攻）。全部不可用返回 false，原有走位与普攻逻辑不受影响。
func try_cast(target: Node) -> bool:
	_ensure_skills()
	if pawn == null or not is_instance_valid(pawn):
		return false
	if _casting:
		return false   # 前摇 / 滞空 / 收招中不接受第二次施法
	if pawn.is_dead_flag or pawn.attacker == null:
		return false
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	for d in skills:
		if d == null:
			continue
		if cooldown_left(d.id) > 0.0:
			continue
		# 技能树门禁：主技能走旧根节点语义，进阶技能走 unlocks_skill_id 精确匹配
		if not _skill_unlocked(d.id):
			continue
		if not _dispatch_cast(d, target):
			continue
		_cd[d.id] = maxf(d.cooldown, 0.0)
		return true
	return false


## 是否正在施法（前摇 / 跳劈滞空 / 收招）。
func is_casting() -> bool:
	return _casting


## 剩余冷却：skill_id 为空 = 主技能（兼容 v19 无参调用），否则取该技能自己的 CD。
func cooldown_left(skill_id: StringName = &"") -> float:
	if skill_id == &"":
		if skill != null:
			return float(_cd.get(skill.id, 0.0))
		var longest: float = 0.0
		for k in _cd.keys():
			longest = maxf(longest, float(_cd[k]))
		return longest
	return float(_cd.get(skill_id, 0.0))


## SkillCastState 每物理帧调用：推进「前摇 → 执行 → 收招」，收招结束回调 end_skill_cast。
func tick_cast(delta: float) -> void:
	_last_tick_physics_frame = Engine.get_physics_frames()
	_advance_cast(delta)


## 中途被打断（死亡 / 被抢占状态等）：不结算效果、解除技能锁定。
## 跳劈滞空被打断时把单位放回地面，避免浮空卡死。
func abort_cast() -> void:
	if not _casting:
		return
	if _phase == CastPhase.LEAP_AIR and pawn != null and is_instance_valid(pawn):
		var p: Vector3 = pawn.global_position
		p.y = _leap_ground_y
		pawn.global_position = p
		pawn.velocity = Vector3.ZERO
	_release_leap_trail()
	_clear_cast()
	_unlock_pawn()


## 血怒是否生效中（测试 / UI 用）。
func is_raging() -> bool:
	return _rage_left > 0.0


## 转职换 def 后重建技能表与冷却表（契约追加；Soldier.promote_to 调用）。
## 主技能 skill 同步刷新（保留该字段：既有测试与 UI 仍在读它）。
func sync_skills_from_def() -> void:
	_ensure_skills(true)


# ============================================================================
# 施法状态机（前摇 → 执行 → 收招）
# ============================================================================

## 推进一帧施法。返回后 _casting 可能已变 false（收招结束）。
func _advance_cast(delta: float) -> void:
	if not _casting:
		return
	if pawn == null or not is_instance_valid(pawn):
		_clear_cast()
		return
	_phase_left -= delta
	match _phase:
		CastPhase.WINDUP:
			if _phase_left <= 0.0:
				_execute_cast()
		CastPhase.LEAP_AIR:
			_advance_leap(delta)
		CastPhase.RECOVER:
			if _phase_left <= 0.0:
				_finish_cast()


## 前摇结束 → 执行：跳劈进入滞空，陨石在锁定落点生成落点实体，其余直接收招。
func _execute_cast() -> void:
	var d: PawnSkillDef = _cast_skill
	if d == null:
		_finish_cast()
		return
	match d.kind:
		PawnSkillDef.Kind.LEAP_SLAM:
			_begin_leap()
		PawnSkillDef.Kind.METEOR:
			_execute_meteor()
		_:
			_finish_cast()


## 收招结束：清状态 → 回调 Pawn（由 Pawn 决定回 fight 还是 idle）。
## 注意顺序：先清 _casting 再回调——end_skill_cast 会切状态并触发 SkillCastState.exit，
## 此时 is_casting() 必须已是 false，否则 exit 会把正常收招误判成打断。
func _finish_cast() -> void:
	_release_leap_trail()
	_clear_cast()
	if pawn != null and is_instance_valid(pawn) and pawn.has_method(&"end_skill_cast"):
		pawn.call(&"end_skill_cast")


func _clear_cast() -> void:
	_casting = false
	_phase = CastPhase.NONE
	_phase_left = 0.0
	_cast_skill = null
	_cast_target = null


## 起手一个带前摇的技能（跳劈 / 陨石）：锁定落点与目标 → 进施法态 → 播前摇表现。
## 契约追加：只有 Pawn.begin_skill_cast() **真的进入了施法态**才吃 CD——
## 已死亡 / 施法态未注册时它返回 false（受控由 Pawn.try_cast_combat_skill 的
## is_controlled() 守卫拦截），本函数原样返回 false（不吞 CD）。
func _start_windup_cast(d: PawnSkillDef, target: Node) -> bool:
	if not _windup_precondition(d, target):
		return false
	var tn := target as Node3D
	var to_target: Vector3 = tn.global_position - pawn.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.0001:
		pawn.look_at_target(to_target.normalized())
	# 落点在施法瞬间锁定（之后目标再移动也不改落点——这是「可躲避」的前提）
	if d.kind == PawnSkillDef.Kind.LEAP_SLAM:
		_leap_ground_y = pawn.global_position.y
		_leap_to = _clamped_leap_point(tn.global_position, d.cast_range)
	else:
		_meteor_locked_pos = Vector3(tn.global_position.x, pawn.global_position.y, tn.global_position.z)
	_casting = true
	_phase = CastPhase.WINDUP
	_phase_left = maxf(d.windup, 0.02)
	_cast_skill = d
	_cast_target = target
	# 交给 Pawn 切进 skill_cast 态（前摇 / 滞空 / 收招由本组件 tick_cast 推进）
	if pawn.has_method(&"begin_skill_cast"):
		if not bool(pawn.call(&"begin_skill_cast", d, target)):
			# 没进施法态：撤销起手（不结算、不吃 CD），交回状态机继续普攻
			_clear_cast()
			return false
	_last_tick_physics_frame = Engine.get_physics_frames()
	_play_windup_visual(d)
	return true


## 前摇技能的起手前提：目标必须还活着；陨石还要在施法距离内
## （跳劈例外——超出 cast_range 时把跃击落点钳到上限，等于「冲过去」）。
func _windup_precondition(d: PawnSkillDef, target: Node) -> bool:
	var health: HealthComponent = _target_health(target)
	if health == null or health.is_dead():
		return false
	if d.kind == PawnSkillDef.Kind.METEOR and d.cast_range > 0.0:
		return _center_dist(target as Node3D) <= d.cast_range
	return true


## 前摇表现：跳劈 = 脚下蓄力 + 举械；陨石 = 自身法阵吟唱（持续整个 windup）。
func _play_windup_visual(d: PawnSkillDef) -> void:
	match d.kind:
		PawnSkillDef.Kind.LEAP_SLAM:
			VFXManager.spawn_effect(&"leap_charge", pawn.global_position, 0.0,
				{"throttle_key": pawn.get_instance_id()})
			EventBus.floating_text.emit("跳劈！", Color(1.0, 0.6, 0.32),
				pawn.global_position + Vector3(0.0, 2.2, 0.0))
		PawnSkillDef.Kind.METEOR:
			# 吟唱法阵挂自身（lifetime 覆盖整个前摇，VFXManager 到期自动回收）
			VFXManager.spawn_effect(&"meteor_channel", pawn.global_position, 0.0,
				{"lifetime": maxf(d.windup, 0.3) + 0.25,
				"throttle_key": pawn.get_instance_id()})
			EventBus.floating_text.emit("陨石术！", Color(1.0, 0.7, 0.35),
				pawn.global_position + Vector3(0.0, 2.2, 0.0))
		_:
			pass
	pawn.play_anim(&"cast")
	AudioManager.play_sfx(&"charge", pawn.global_position)


# ============================================================================
# 狂战士 · 跳劈（前摇 → 抛物线滞空 → 落地 AOE + 击飞）
# ============================================================================

## 跃击落点：目标脚下；超出 cast_range 钳到上限；距目标 < 1.2m 原地起跳。
## cast_range 由调用方显式传入（起手时 _cast_skill 尚未赋值，不能从成员读）。
func _clamped_leap_point(target_pos: Vector3, cast_range: float) -> Vector3:
	var from: Vector3 = pawn.global_position
	var flat := Vector3(target_pos.x - from.x, 0.0, target_pos.z - from.z)
	var dist := flat.length()
	if dist < LEAP_INPLACE_DIST or dist < 0.0001:
		return Vector3(from.x, _leap_ground_y, from.z)
	var limit: float = cast_range if cast_range > 0.0 else LEAP_RANGE_FALLBACK
	if dist > limit:
		flat = flat * (limit / dist)
	return Vector3(from.x + flat.x, _leap_ground_y, from.z + flat.z)


## 进入滞空：时长 = 距离 / leap_speed（钳到 [0.25, 0.9]），拖尾挂自身。
func _begin_leap() -> void:
	_leap_from = pawn.global_position
	_leap_elapsed = 0.0
	var flat := Vector3(_leap_to.x - _leap_from.x, 0.0, _leap_to.z - _leap_from.z)
	var dist := flat.length()
	if dist < 0.05:
		_leap_dir = Vector3.ZERO
		_leap_duration = LEAP_MIN_TIME
	else:
		_leap_dir = flat.normalized()
		var speed: float = 16.0
		if _cast_skill != null:
			speed = maxf(_cast_skill.leap_speed, 0.1)
		_leap_duration = clampf(dist / speed, LEAP_MIN_TIME, LEAP_MAX_TIME)
	_phase = CastPhase.LEAP_AIR
	_phase_left = _leap_duration
	if _leap_trail == null or not is_instance_valid(_leap_trail):
		_leap_trail = VFXManager.attach_trail(pawn, &"leap_trail")
	pawn.play_anim(&"cast")


## 滞空推进：水平 lerp + sin 弧线顶点；到点即落地结算。
func _advance_leap(delta: float) -> void:
	_leap_elapsed += delta
	var k: float = clampf(_leap_elapsed / maxf(_leap_duration, 0.01), 0.0, 1.0)
	var height: float = 3.0
	if _cast_skill != null:
		height = _cast_skill.leap_height
	var pos: Vector3 = _leap_from.lerp(_leap_to, k)
	pos.y = _leap_from.y + sin(k * PI) * height
	var prev: Vector3 = pawn.global_position
	pawn.global_position = pos
	if delta > 0.0001:
		pawn.velocity = (pos - prev) / delta
	if _leap_dir.length_squared() > 0.001:
		pawn.look_at_target(_leap_dir)
	if k >= 1.0:
		_land_slam()


## 落地：冲击表现 + 圆形 AOE（伤害 + 击飞控制）→ 收招。
func _land_slam() -> void:
	var d: PawnSkillDef = _cast_skill
	if d == null:
		_finish_cast()
		return
	pawn.velocity = Vector3.ZERO
	_release_leap_trail()
	var center: Vector3 = pawn.global_position
	VFXManager.spawn_effect(&"slam_impact", center, 0.0)
	VFXManager.spawn_effect(&"slam_shockwave", center + Vector3(0.0, 0.06, 0.0), 0.0,
		{"scale": d.radius * 2.0, "throttle_key": pawn.get_instance_id()})
	AudioManager.play_sfx(&"hit_heavy", center)
	_slam_area(d, center)
	pawn.play_anim(&"fight")
	_phase = CastPhase.RECOVER
	_phase_left = maxf(d.recover, 0.0)
	if _phase_left <= 0.0:
		_finish_cast()


## 落地 AOE：半径内敌方各吃一次伤害，并被推离落点方向击飞（滞空 + 落地眩晕）。
func _slam_area(d: PawnSkillDef, center: Vector3) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var r2: float = d.radius * d.radius
	for v in tree.get_nodes_in_group(_hostile_group()):
		if not (v is Pawn) or not is_instance_valid(v):
			continue
		var victim := v as Pawn
		if victim.is_dead_flag:
			continue
		if _flat_dist_sq(center, victim.global_position) > r2:
			continue
		victim.take_damage(d.damage, pawn)
		VFXManager.spawn_hit_impact(victim.global_position + Vector3(0.0, 1.0, 0.0),
			Color(1.0, 0.72, 0.35), &"hit_spark", victim.get_instance_id())
		# 已被这一击打死的（尸体）不再击飞：死亡动画优先
		if victim.is_dead_flag:
			continue
		_apply_knockup(victim, center, d)


## 击飞：方向 = 远离落点（退化时用施法者正前方），参数全取技能 def。
func _apply_knockup(victim: Pawn, center: Vector3, d: PawnSkillDef) -> void:
	if not victim.has_method(&"apply_knockup"):
		return
	var dir: Vector3 = victim.global_position - center
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = -pawn.global_transform.basis.z
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	victim.call(&"apply_knockup", dir.normalized(), d.knockback_distance,
		d.knockback_height, d.airborne_time, d.stun_duration)


## 释放滞空拖尾（先停发射，粒子飞完再回收；节点销毁不影响已发射粒子留在世界里）。
func _release_leap_trail() -> void:
	if _leap_trail == null or not is_instance_valid(_leap_trail):
		_leap_trail = null
		return
	var trail := _leap_trail
	_leap_trail = null
	trail.emitting = false
	_free_later(trail, 0.8)


# ============================================================================
# 元素法师 · 陨石术（原地吟唱 → 锁定落点生成 SkillMeteorStrike）
# ============================================================================

## 吟唱结束：在「吟唱开始瞬间锁定的目标位置」生成落点实体（预警圈 → 落地结算）。
func _execute_meteor() -> void:
	var d: PawnSkillDef = _cast_skill
	if d == null:
		_finish_cast()
		return
	var strike := SkillMeteorStrike.new()
	strike.caster = pawn
	strike.skill_def = d
	var host: Node = pawn.get_parent() if pawn.get_parent() != null else pawn
	host.add_child(strike)
	strike.global_position = _meteor_locked_pos
	pawn.play_anim(&"cast")
	_phase = CastPhase.RECOVER
	_phase_left = maxf(d.recover, 0.0)
	if _phase_left <= 0.0:
		_finish_cast()


# ============================================================================
# 狙击手 · 贯穿射击（瞬发大号贯穿弹）
# ============================================================================

func _cast_piercing_shot(d: PawnSkillDef, target: Node) -> bool:
	if d.cast_range > 0.0 and _center_dist(target as Node3D) > d.cast_range:
		return false
	var health: HealthComponent = _target_health(target)
	if health == null or health.is_dead():
		return false
	var tn := target as Node3D
	var dir := Vector3(tn.global_position.x - pawn.global_position.x, 0.0,
		tn.global_position.z - pawn.global_position.z)
	if dir.length_squared() < 0.0001:
		dir = -pawn.global_transform.basis.z
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var start: Vector3 = pawn.global_position + Vector3(0.0, PIERCE_SOURCE_HEIGHT, 0.0)
	var shot := SkillPiercingShot.new()
	shot.source = pawn
	shot.skill_def = d
	shot.direction = dir
	var host: Node = pawn.get_parent() if pawn.get_parent() != null else pawn
	host.add_child(shot)
	shot.global_position = start
	pawn.look_at_target(dir)
	VFXManager.spawn_effect(&"pierce_muzzle", start, atan2(-dir.x, -dir.z),
		{"throttle_key": pawn.get_instance_id()})
	pawn.play_anim(&"shoot")
	EventBus.floating_text.emit("贯穿射击！", Color(1.0, 0.88, 0.45),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	AudioManager.play_sfx(&"arrow_shoot", pawn.global_position)
	return true


# ============================================================================
# 暗杀者 · 隐身（接近目标或逃生时释放）
# ============================================================================

## 条件：未隐身 且（血量比例 < escape_hp_ratio 或 目标距离 ∈ (2.5, approach_range]）。
func _cast_stealth(d: PawnSkillDef, target: Node) -> bool:
	if pawn.has_method(&"is_stealthed") and bool(pawn.call(&"is_stealthed")):
		return false
	# 隐身能力由 Pawn 提供（模型 shader 隐身态 + 索敌屏蔽 + 破隐监听）；缺失则视为不可用
	if not pawn.has_method(&"apply_stealth"):
		return false
	var ratio: float = 1.0
	if pawn.health != null:
		ratio = pawn.health.ratio()
	var dist: float = _center_dist(target as Node3D)
	var escaping: bool = d.escape_hp_ratio > 0.0 and ratio < d.escape_hp_ratio
	var approaching: bool = dist > STEALTH_MIN_RANGE and dist <= d.approach_range
	if not escaping and not approaching:
		return false
	if not bool(pawn.call(&"apply_stealth", d.stealth_duration)):
		return false
	EventBus.floating_text.emit("隐身！", Color(0.72, 0.55, 1.0),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	return true


# ============================================================================
# 法师 · 暴风雪
# ============================================================================

func _cast_blizzard(d: PawnSkillDef, target: Node) -> bool:
	# 施法距离：超出则交回状态机继续走位（返回 false 不消耗 CD）
	if d.cast_range > 0.0 and _center_dist(target) > d.cast_range:
		return false
	var center: Vector3 = (target as Node3D).global_position
	var zone := SkillBlizzardZone.new()
	zone.caster = pawn
	zone.skill_def = d
	# 挂到单位容器同级（跟随单位生命周期所在层；容器销毁时一并清理）
	var host: Node = pawn.get_parent() if pawn.get_parent() != null else pawn
	host.add_child(zone)
	zone.global_position = center
	# 施法者表现：冰蓝施法微光 + 举杖施法动作 + 飘字（旧版播近战挥砍，动作与施法不符）
	VFXManager.spawn_effect(&"cast_glow", pawn.global_position + Vector3(0.0, 1.25, 0.0), 0.0,
		{"color": Color(0.55, 0.8, 1.0), "throttle_key": pawn.get_instance_id()})
	VFXManager.spawn_effect(&"blizzard_ring", center, 0.0)
	pawn.play_anim(&"cast")
	EventBus.floating_text.emit("暴风雪！", Color(0.55, 0.82, 1.0),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	AudioManager.play_sfx(&"charge", pawn.global_position)
	return true


# ============================================================================
# 战士 · 血怒
# ============================================================================

func _cast_blood_rage(d: PawnSkillDef) -> bool:
	if _rage_left > 0.0:
		return false   # 怒中不再叠怒（不吃 CD）
	_rage_skill = d
	_rage_base_damage = pawn.attacker.damage
	pawn.attacker.damage = _rage_base_damage * d.damage_mult
	_rage_left = d.buff_duration
	# 表现：绯红爆发环 + 常驻血怒光环（持续粒子）+ 头顶血怒标记 + 飘字 + 仰天咆哮动作
	# （战士经 per-def anim_map 把 cast 覆盖为 Cheer 举臂吼叫；其余职业走通用施法动作）
	VFXManager.spawn_effect(&"rage_burst", pawn.global_position, 0.0)
	_attach_rage_aura()
	pawn.show_status_mark(&"rage", d.buff_duration)
	pawn.play_anim(&"cast")
	EventBus.floating_text.emit("血怒！", Color(1.0, 0.35, 0.3),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	AudioManager.play_sfx(&"charge", pawn.global_position)
	return true


func _end_blood_rage() -> void:
	_rage_left = 0.0
	if pawn != null and is_instance_valid(pawn) and pawn.attacker != null:
		pawn.attacker.damage = _rage_base_damage
	_rage_skill = null
	if _rage_aura != null and is_instance_valid(_rage_aura):
		_rage_aura.queue_free()
		_rage_aura = null


## v20 属性系统 · 面板重挂：宿主升级重算六维后调用。血怒中战士的「基础伤害」
## 基线要跟着新面板走（否则怒气结束会把攻击力还原到升级前的旧值）。
## v33：转职换 def 后也会走这里（Soldier.promote_to），顺带重建技能表，新技能立即可用。
func notify_stats_rebased() -> void:
	_ensure_skills()
	if _rage_left > 0.0 and pawn != null and is_instance_valid(pawn) and pawn.attacker != null:
		var d: PawnSkillDef = _rage_skill if _rage_skill != null else skill
		if d == null:
			return
		# 新基线 = 重算后的面板（Pawn._apply_stats_for_level 刚写完 attacker.damage）
		_rage_base_damage = pawn.attacker.damage
		pawn.attacker.damage = _rage_base_damage * d.damage_mult


## 血怒光环：常驻上升的绯红怒气粒子（挂 Pawn 本体，随行动移动）。
func _attach_rage_aura() -> void:
	if _rage_aura != null and is_instance_valid(_rage_aura):
		return
	var p := GPUParticles3D.new()
	p.name = RAGE_AURA_NAME
	p.amount = 34
	p.lifetime = 0.7
	p.one_shot = false
	p.local_coords = true          # 粒子随体：形成包裹自身的怒气柱
	p.fixed_fps = 30
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.55
	mat.direction = Vector3.UP
	mat.spread = 22.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.7
	mat.gravity = Vector3(0.0, 2.6, 0.0)   # 怒气上涌
	mat.scale_min = 0.6
	mat.scale_max = 1.3
	mat.color_ramp = _ensure_aura_ramp()
	p.process_material = mat
	p.draw_pass_1 = _ensure_aura_mesh()
	p.emitting = true
	p.position = Vector3(0.0, 0.65, 0.0)
	pawn.add_child(p)
	_rage_aura = p


static func _ensure_aura_ramp() -> GradientTexture1D:
	if _aura_ramp != null:
		return _aura_ramp
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.2, 0.0))
	grad.set_color(1, Color(0.55, 0.05, 0.05, 0.0))
	grad.add_point(0.2, Color(1.0, 0.42, 0.3, 0.95))
	grad.add_point(0.6, Color(0.9, 0.16, 0.12, 0.7))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	_aura_ramp = ramp
	return ramp


static func _ensure_aura_mesh() -> QuadMesh:
	if _aura_mesh != null:
		return _aura_mesh
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
	mesh.size = Vector2(0.16, 0.16)
	mesh.material = mat
	_aura_mesh = mesh
	return mesh


# ============================================================================
# 游侠 · 快速射击
# ============================================================================

func _cast_rapid_shot(d: PawnSkillDef, target: Node) -> bool:
	if d.cast_range > 0.0 and _center_dist(target) > d.cast_range:
		return false
	var health: HealthComponent = _target_health(target)
	if health == null or health.is_dead():
		return false
	# 易伤 debuff：出手即挂（3s，受到伤害 +30%），标记由目标自身头顶显示
	if target is Pawn:
		(target as Pawn).apply_vulnerable(d.vuln_mult, d.vuln_duration)
	_shots_left = d.shot_count
	_shot_timer = 0.0
	_shot_target = target
	_shot_skill = d
	pawn.play_anim(&"shoot")   # 起手即上射击动作（0.14s 连发间隔远短于动画，不逐箭重启）
	EventBus.floating_text.emit("快速射击！", Color(1.0, 0.85, 0.35),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	_fire_rapid_shot()   # 首箭即刻出手
	return true


func _fire_rapid_shot() -> void:
	if _shots_left <= 0:
		return
	var shot_skill: PawnSkillDef = _shot_skill if _shot_skill != null else skill
	if shot_skill == null:
		_shots_left = 0
		_shot_target = null
		return
	var target: Node = _shot_target
	if target == null or not is_instance_valid(target) or _target_health(target) == null \
			or _target_health(target).is_dead():
		_shots_left = 0
		_shot_target = null
		return
	pawn.attacker.launch_projectile(target, shot_skill.damage, GOLD_ARROW)
	_shots_left -= 1
	_shot_timer = shot_skill.shot_interval


# ============================================================================
# 刺客 · 背刺
# ============================================================================

func _cast_backstab(d: PawnSkillDef, target: Node) -> bool:
	# 背刺只对单位生效（要取「身后」朝向；打建筑没有背）
	if not (target is Pawn) or (target as Pawn).is_dead_flag:
		return false
	# 施法距离 = 背刺突进距离（比普攻 1.7m 大得多：7m 内说闪就闪）
	if d.cast_range > 0.0 and _center_dist(target) > d.cast_range:
		return false
	var health: HealthComponent = _target_health(target)
	if health == null or health.is_dead():
		return false
	var victim := target as Pawn
	var from: Vector3 = pawn.global_position
	# 落点 = 目标身后（沿目标面朝方向越过其身体），贴合模型半径防穿模
	var fwd: Vector3 = -victim.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else _flat_dir(victim.global_position, from)
	var behind: Vector3 = victim.global_position + fwd * (BACKSTAB_BEHIND_DIST + 0.35)
	behind.y = victim.global_position.y
	# 起点残影 → 闪现 → 转身面向目标背心
	VFXManager.spawn_effect(&"blink_ring", from + Vector3(0.0, 0.9, 0.0), 0.0)
	pawn.global_position = behind
	pawn.velocity = Vector3.ZERO
	pawn.look_at_target(_flat_dir(pawn.global_position, victim.global_position))
	# 重伤结算（易伤等增伤乘区由 HealthComponent.apply_damage 统一处理）
	health.apply_damage(d.damage, pawn)
	# 表现：落点紫环 + 交叉双匕弧（v28：两道反向扫动的细弧，双匕首「剪」的读感）
	# + 定向命中反馈 + 飘字 + 直刺动作
	VFXManager.spawn_effect(&"blink_ring", behind + Vector3(0.0, 0.9, 0.0), 0.0)
	VFXManager.spawn_effect(&"dagger_arc", behind + Vector3(0.0, 1.0, 0.0),
		pawn.rotation.y, {"spin_scale": -1.0})
	VFXManager.spawn_effect(&"dagger_arc", behind + Vector3(0.0, 1.0, 0.0),
		pawn.rotation.y + 0.35, {"spin_scale": 1.0})
	VFXManager.spawn_hit_impact(victim.global_position + Vector3(0.0, 1.05, 0.0),
		Color(0.72, 1.0, 0.9), &"hit_spark", victim.get_instance_id(),
		pawn.rotation.y)
	pawn.play_anim(&"stab")
	EventBus.floating_text.emit("背刺！", Color(0.8, 0.6, 1.0),
		pawn.global_position + Vector3(0.0, 2.2, 0.0))
	AudioManager.play_sfx(&"hit_heavy", pawn.global_position)
	return true


# ============================================================================
# 技能派发 / 技能表
# ============================================================================

## 按 kind 派发。返回 true = 已施放（调用方记 CD）。
func _dispatch_cast(d: PawnSkillDef, target: Node) -> bool:
	match d.kind:
		PawnSkillDef.Kind.BLIZZARD:
			return _cast_blizzard(d, target)
		PawnSkillDef.Kind.BLOOD_RAGE:
			return _cast_blood_rage(d)
		PawnSkillDef.Kind.RAPID_SHOT:
			return _cast_rapid_shot(d, target)
		PawnSkillDef.Kind.BACKSTAB:
			return _cast_backstab(d, target)
		PawnSkillDef.Kind.LEAP_SLAM:
			return _start_windup_cast(d, target)
		PawnSkillDef.Kind.METEOR:
			return _start_windup_cast(d, target)
		PawnSkillDef.Kind.PIERCING_SHOT:
			return _cast_piercing_shot(d, target)
		PawnSkillDef.Kind.STEALTH:
			return _cast_stealth(d, target)
	return false


## 展开技能表：优先级 = extra_skills（进阶技能先手）+ [def.skill]。
## def 变更（转职换 def）时重建；已存在的 CD 保留，新技能从头算。
func _ensure_skills(force: bool = false) -> void:
	if pawn == null or not is_instance_valid(pawn) or pawn.def == null:
		return
	if not force and pawn.def == _def_ref and not skills.is_empty():
		return
	_def_ref = pawn.def
	skill = pawn.def.skill
	var ordered: Array[PawnSkillDef] = []
	for s in pawn.def.all_skills():
		if s != null and s != skill:
			ordered.append(s)
	if skill != null:
		ordered.append(skill)
	skills = ordered
	for s in skills:
		if not _cd.has(s.id):
			_cd[s.id] = 0.0


func _tick_cooldowns(delta: float) -> void:
	if _cd.is_empty():
		return
	for k in _cd.keys():
		var left: float = float(_cd[k])
		if left > 0.0:
			_cd[k] = maxf(0.0, left - delta)


## 技能门禁：优先走 Pawn.is_skill_unlocked(id)（v33 多技能口径）；
## 该方法尚未落地时直接读技能树（与 Pawn 包装同一规则：无树 = true）。
func _skill_unlocked(skill_id: StringName) -> bool:
	if pawn == null or not is_instance_valid(pawn):
		return true
	if pawn.has_method(&"is_skill_unlocked"):
		return bool(pawn.call(&"is_skill_unlocked", skill_id))
	if pawn.skill_tree != null:
		return pawn.skill_tree.is_skill_unlocked(skill_id)
	return true


## 解除 Pawn 侧施法锁定（abort 路径专用：只解锁，不切状态——死亡/被打断时不能回 fight）。
func _unlock_pawn() -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	if pawn.has_method(&"set_skill_locked"):
		pawn.call(&"set_skill_locked", false)
	else:
		pawn.set(&"skill_locked", false)


# ============================================================================
# 工具
# ============================================================================

func _center_dist(target: Node3D) -> float:
	return pawn.global_position.distance_to(target.global_position)


func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


## 敌方分组：施法者是玩家阵营打 "enemy"，是敌方阵营（野怪）打 "player_unit"。
func _hostile_group() -> String:
	if pawn != null and is_instance_valid(pawn) and pawn.team_comp != null \
			and pawn.team_comp.team == TeamComponent.Team.ENEMY:
		return "player_unit"
	return "enemy"


func _flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD


func _target_health(target: Node) -> HealthComponent:
	if target == null or not is_instance_valid(target):
		return null
	return target.get_node_or_null("HealthComponent") as HealthComponent


## 延时回收（time_scale=0 的暂停期也照常计时，避免残留粒子节点）。
func _free_later(node: Node, sec: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tree := get_tree()
	if tree == null:
		node.queue_free()
		return
	var t := tree.create_timer(maxf(sec, 0.01), true, false, true)
	var cb := func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	t.timeout.connect(cb)


## 血怒吸血：自己造成的每一笔伤害按比例回血（EventBus.damage_dealt 广播）。
func _on_damage_dealt(_target: Node, amount: float, source: Node) -> void:
	if _rage_left <= 0.0 or source != pawn:
		return
	var d: PawnSkillDef = _rage_skill if _rage_skill != null else skill
	if d == null:
		return
	if pawn.health != null and not pawn.health.is_dead():
		pawn.health.heal(amount * d.lifesteal_ratio)
