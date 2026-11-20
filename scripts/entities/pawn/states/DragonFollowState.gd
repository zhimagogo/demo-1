class_name DragonFollowState
extends PawnState
## ============================================================================
## 巨龙跟随态：**带缓冲半径的懒跟随** + 主角身边的自主守备（v32）。
##
## ① 缓冲半径 / 跟随半径（用户口径）：主角在 `BUFFER_RADIUS` 这个圈里怎么走，龙**原地不动**；
##    主角超出缓冲圈 → 龙才追到「跟随半径」（侧翼槽位 ≈ SLOT_DIST 米）附近，到位即停，
##    于是又回到缓冲状态。→ 龙不再像尾巴一样贴着玩家一顿一顿地挪。
## ② 站位在主角**右翼**（`FOLLOW_SIDE`×体型），避开第三人称「枢轴→相机」的视线走廊
##    （v29 实测：槽位压在走廊上会把画面糊死）；主角贴脸（< 个人空间）时龙侧移让位，
##    即使玩家自己走进龙怀里也不会被它的身体挡住准星。
## ③ 主角站定 → 槽位冻结为世界休整位（不随视角转、不随减速漂移重排）；朝向取主角朝向并
##    限速平滑（DragonPet 覆写 look_at_target）；大体重单位不瞬移。
##
## 目标（v32 三级优先级，见 DragonPet.pick_target）一出现 → 立即转战斗态：
##   玩家的目标 ＞ 正在打玩家的敌人 ＞ 主角圈内最近的敌人。
## 主角阵亡 / 失效 → 原地站定等待（不游荡、不追出圈）。
## ============================================================================

# ---- 站位（米；随体型线性外推——体型翻倍后旧站位会让龙压在玩家身上）----
# 公式：值(b) = BASE + PER_BODY × (b - 1)，b = def.body_scale。
const FOLLOW_BACK_BASE: float = 1.0        # 槽位在主角身后（b=1）
const FOLLOW_BACK_PER_BODY: float = 0.6
const FOLLOW_SIDE_BASE: float = 3.2        # 槽位在主角右翼（b=1）
const FOLLOW_SIDE_PER_BODY: float = 2.3    # b=2 的巨龙：右翼 5.5m / 身后 1.6m——翻倍后翼展 ~8m，
                                           # 站位太近会让翼尖扫过画面中心（实机样张实锤）
const SETTLE_DIST_BASE: float = 1.1        # 离槽位小于此距离视为就位（b=1）
const SETTLE_DIST_PER_BODY: float = 0.1    # 到位圈收紧：个人空间必须落在「槽位 - 到位」之外
const SETTLE_HYSTERESIS: float = 0.8       # 到位滞回：被挤开超过 SETTLE_DIST + 此值才重新 seek
const SEPARATION_RADIUS_BASE: float = 2.2  # 与小队成员 / 主角保持的距离（b=1）
const SEPARATION_RADIUS_PER_BODY: float = 1.4
const SEPARATION_WEIGHT: float = 5.0
# 个人空间：主角贴得比这更近 → 龙侧移让位（b=1 时 2.6m；b=2 巨龙 3.0m）。
# **必须小于「侧翼槽位距离 - 到位半径」**（b=2：4.71-1.2=3.51），否则龙会在
# 「站到槽位」与「让位退开」之间来回抖（v32 实测 drift 5.35m）。
const PERSONAL_SPACE_BASE: float = 2.6
const PERSONAL_SPACE_PER_BODY: float = 1.0  # 个人空间慢涨（涨太快会与侧翼槽位圈重叠 → 抖）
const PERSONAL_SPACE_HYSTERESIS: float = 1.4

# ---- 懒跟随（v32 用户口径）----
# 缓冲半径：主角在这个圈里怎么走，龙都不动；超出才追到「跟随半径」（= 侧翼槽位，
# b=2 巨龙约 4.7m）就位停住，于是又回到缓冲态。
const BUFFER_RADIUS: float = 15.0

# ---- 追赶 / 寻路 ----
# 追赶按「落后槽位多少」比例提速（不是超阈值才加速的开关式——开关式在阈值附近一冲一停）。
const CATCHUP_K: float = 0.30
const CATCHUP_MAX: float = 2.0
const NAV_SEEK_DIST: float = 6.0         # 距槽位超过此距离 → 走格子 A*（绕障）
const NAV_RETARGET_MOVE: float = 1.6     # 槽位挪动超过此距离才重新寻路（节流）
const ENGAGE_RANGE: float = 40.0         # 主角的目标在此距离内才扑上去（防跨图追杀）
const FORM_TURN_RATE: float = 2.6        # 队形朝向跟随主角朝向的限速（rad/s）
const REST_RELEASE_DIST: float = 1.0     # 主角离开休整锚点超过此距离才重排站位

var _last_nav_slot: Vector3 = Vector3.INF
var _form_dir: Vector3 = Vector3.ZERO       # 队形朝向（持久化，随主角朝向限速转）
var _rest_pos: Vector3 = Vector3.INF        # 站定时冻结的休整位（世界坐标）
var _rest_anchor: Vector3 = Vector3.INF     # 冻结时的主角位置
var _rest_valid: bool = false
var _settled: bool = false                  # 到位滞回状态
var _following: bool = false                # 懒跟随闸门：true = 正在追主角（出缓冲圈触发）
var _give_way: bool = false                 # 个人空间让位滞回状态


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	_last_nav_slot = Vector3.INF
	_rest_valid = false
	_rest_pos = Vector3.INF
	_settled = false
	_following = false
	_give_way = false
	pawn.combat_target = null       # 跟随态 = 未交战（血条 / 索敌分摊读这个字段）
	pawn.play_anim(&"idle")


func exit() -> void:
	if pawn != null and is_instance_valid(pawn):
		pawn.speed_multiplier = 1.0


func physics_update(delta: float) -> void:
	var leader = pawn.follow_leader
	if leader == null or not is_instance_valid(leader) or not (leader is Node3D):
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		pawn.play_anim(&"idle")
		return

	# ---- 目标（三级优先级）→ 转战斗态（玩家打谁龙打谁；没目标时自主守备主角身边）----
	var t = pawn.pick_target() if pawn.has_method("pick_target") else null
	if t != null:
		var dist_to_target: float = pawn.global_position.distance_to((t as Node3D).global_position)
		if dist_to_target <= ENGAGE_RANGE:
			state_machine.transition_to("dragon_fight", {"target": t})
			return

	var b: float = pawn.body_scale()
	var back_off: float = _grow(FOLLOW_BACK_BASE, FOLLOW_BACK_PER_BODY, b)
	var side_off: float = _grow(FOLLOW_SIDE_BASE, FOLLOW_SIDE_PER_BODY, b)
	var sep_radius: float = _grow(SEPARATION_RADIUS_BASE, SEPARATION_RADIUS_PER_BODY, b)
	var leader_pos: Vector3 = (leader as Node3D).global_position
	var dist_to_leader: float = pawn.global_position.distance_to(leader_pos)
	var personal_space: float = _grow(PERSONAL_SPACE_BASE, PERSONAL_SPACE_PER_BODY, b)

	# ---- 懒跟随闸门：出缓冲圈才开始跟；跟到「跟随半径」内即停（再次进入缓冲态）----
	var slot_dist: float = sqrt(back_off * back_off + side_off * side_off)
	if not _following and dist_to_leader > BUFFER_RADIUS:
		_following = true                  # 出缓冲圈 → 开始追

	var slot: Vector3 = _slot_position(leader, leader_pos, delta, back_off, side_off)
	var nav: NavSystem = pawn._get_nav_system()
	if nav != null and not nav.can_walk_segment(slot, slot):
		slot = nav.snap_to_walkable(slot)
	var to_slot: Vector3 = slot - pawn.global_position
	to_slot.y = 0.0
	var dist: float = to_slot.length()
	var settle_dist: float = _grow(SETTLE_DIST_BASE, SETTLE_DIST_PER_BODY, b)

	# 追赶倍率：按「落后槽位多少」比例提速（贴住槽位即 1.0×）
	pawn.speed_multiplier = clampf(
		1.0 + maxf(0.0, dist_to_leader - slot_dist) * CATCHUP_K, 1.0, CATCHUP_MAX)

	# 到位判定带滞回：进 settle 就停，被挤开 settle+H 才重新 seek
	if dist <= settle_dist:
		_settled = true
	elif dist > settle_dist + SETTLE_HYSTERESIS:
		_settled = false
	if _following and _settled:
		_following = false                 # 追到跟随半径（侧翼槽位）→ 回到缓冲态

	# 缓冲态（主角在圈内走自己的路）→ 原地站定，只做分离微调与朝向
	if not _following:
		_settled = true
		# 个人空间让位：**只在待命时**生效——玩家（或主角）贴脸时侧移让开，别挡视线。
		# 归位途中不抢舵：否则「让位退开」与「飞向槽位」互相拉扯，龙会在主角身边来回蹭
		# （v32 实测：归位被让位打断 → 600 帧都没站住）。
		if _give_way:
			_give_way = dist_to_leader < personal_space + PERSONAL_SPACE_HYSTERESIS
		else:
			_give_way = dist_to_leader < personal_space
		if _give_way:
			_step_aside(leader, leader_pos, delta, b)
			return
		pawn.velocity = pawn.compute_separation("hero_squad", sep_radius) \
			* SEPARATION_WEIGHT * 0.2
		pawn._steer_separation = Vector3.ZERO
		pawn.move_and_slide()
		var look: Vector3 = _leader_forward(leader)
		if look.length_squared() > 0.001:
			pawn.look_at_target(look)
		pawn.play_anim(&"idle")
		_last_nav_slot = Vector3.INF
		return

	if dist > NAV_SEEK_DIST * b or (nav != null and not nav.can_walk_segment(pawn.global_position, slot)):
		if _last_nav_slot.distance_squared_to(slot) > NAV_RETARGET_MOVE * NAV_RETARGET_MOVE:
			_last_nav_slot = slot
			pawn.set_navigation_target(slot, true)
		pawn._steer_separation = pawn.compute_separation("hero_squad", sep_radius) \
			* SEPARATION_WEIGHT * 0.5
		pawn.move_along_path(delta)
		_sync_move_anim()
		return

	# 近距 steering 贴身占位（补朝向：旧版这条分支只走位移不改朝向，龙会「横着平移」进槽位）
	_last_nav_slot = Vector3.INF
	var vel: Vector3 = (to_slot / maxf(dist, 0.0001)) * pawn.effective_move_speed()
	vel += pawn.compute_separation("hero_squad", sep_radius) * SEPARATION_WEIGHT
	var max_spd: float = pawn.effective_move_speed() * 1.25
	if vel.length_squared() > max_spd * max_spd:
		vel = vel.normalized() * max_spd
	pawn.velocity = vel
	if Vector2(vel.x, vel.z).length_squared() > 0.04:
		pawn.look_at_target(vel)
	pawn.move_and_slide()
	_sync_move_anim()


## 个人空间让位：沿「远离主角」的横向方向退开（不退到主角正后方视线走廊里），限速推进。
func _step_aside(leader, leader_pos: Vector3, delta: float, b: float) -> void:
	var away: Vector3 = pawn.global_position - leader_pos
	away.y = 0.0
	var base: Vector3 = _leader_forward(leader)
	if base.length_squared() < 0.001:
		base = Vector3.FORWARD
	if away.length_squared() < 0.0001:
		# 完全重叠：往主角右侧让（就是龙的固定站位侧）
		away = Vector3(-base.z, 0.0, base.x)
	# 只保留横向分量（+ 一点向后），避免退到主角正前方挡镜头
	var right := Vector3(-base.z, 0.0, base.x)
	var lateral: float = away.dot(right)
	if absf(lateral) < 0.35:
		lateral = 1.0 if lateral >= 0.0 else -1.0
	var dir: Vector3 = (right * signf(lateral) + base * 0.35).normalized()
	pawn.speed_multiplier = 1.0
	pawn.velocity = dir * pawn.effective_move_speed() * 0.85
	pawn.look_at_target(_leader_forward(leader) if base.length_squared() > 0.001 else dir)
	pawn.move_and_slide()
	_sync_move_anim()


## 体型线性外推：值(b) = base + per_body × (b - 1)（b=1 时即 base，老单位零变化）。
static func _grow(base: float, per_body: float, b: float) -> float:
	return base + per_body * (b - 1.0)


## 槽位：主角朝向（第三人称下 = 相机前方 = 视线走廊方向）的右侧 + 身后。
## 朝向基准取「主角朝向」而不是「主角移动方向」：龙的站位要避开的是**相机视线走廊**，
## 而第三人称走廊就是主角朝向；用移动方向时主角拐个弯，龙就可能绕到正后方糊住镜头。
## 主角站定 → 槽位冻结为世界休整位（不随视角转，也不随减速漂移重新排）。
func _slot_position(leader, leader_pos: Vector3, delta: float, back_off: float, side_off: float) -> Vector3:
	var lv := Vector3.ZERO
	if leader is Pawn:
		lv = (leader as Pawn).velocity
		lv.y = 0.0
	var base: Vector3 = _leader_forward(leader)
	if base.length_squared() < 0.001:
		base = _form_dir
	if base.length_squared() > 0.001:
		_form_dir = _rotate_toward(_form_dir, base, FORM_TURN_RATE * delta)
	if lv.length_squared() > 0.04:
		_rest_valid = false
		return leader_pos + _slot_offset(_form_dir, back_off, side_off)
	if not _rest_valid or leader_pos.distance_to(_rest_anchor) > REST_RELEASE_DIST:
		if _form_dir.length_squared() < 0.001:
			_form_dir = base
		_rest_anchor = leader_pos
		_rest_pos = leader_pos + _slot_offset(_form_dir, back_off, side_off)
		_rest_valid = true
	return _rest_pos


func _slot_offset(dir: Vector3, back_off: float, side_off: float) -> Vector3:
	var fwd := Vector3(dir.x, 0.0, dir.z)
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return -fwd * back_off + right * side_off


func _leader_forward(leader) -> Vector3:
	if not (leader is Node3D):
		return Vector3.ZERO
	var b: Basis = (leader as Node3D).global_transform.basis
	var f := -b.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.ZERO


func _rotate_toward(cur: Vector3, want: Vector3, max_rad: float) -> Vector3:
	var c := Vector3(cur.x, 0.0, cur.z)
	var w := Vector3(want.x, 0.0, want.z)
	if w.length_squared() < 0.0001:
		return c.normalized() if c.length_squared() > 0.0001 else Vector3.FORWARD
	if c.length_squared() < 0.0001:
		return w.normalized()
	c = c.normalized()
	w = w.normalized()
	var ang := c.signed_angle_to(w, Vector3.UP)
	if absf(ang) <= max_rad:
		return w
	return c.rotated(Vector3.UP, signf(ang) * max_rad).normalized()


## 动画按实际速度（抄 FollowState / HeroIdleState 同款判定）：
## 站定 idle / 常速步行 / 追赶 run（龙无跑步动画 → 行走动作同倍速快放，不滑步）。
func _sync_move_anim() -> void:
	var h := Vector2(pawn.velocity.x, pawn.velocity.z).length_squared()
	if h < 0.04:
		pawn.play_anim(&"idle")
	elif pawn.speed_multiplier > 1.05:
		pawn.play_anim(&"run", 0.12, pawn.speed_multiplier * 0.85)
	else:
		pawn.play_anim(&"follow")
