class_name FollowState
extends PawnState
## ============================================================================
## 小队跟随状态（v18 主人命令最高优先 + 拟真跟随）。
## - 槽位持久化：slot 缺省读 Pawn.squad_slot（Hero 编队 / 重排时维护）——
##   战斗 / 待机后回到 follow 不再全员回落 0 号槽（旧版全员挤同一点 = 互推踱步的根源）。
## - 拟真队形：队形朝向跟随队长【移动方向】（限速平滑旋转），不再用队长瞬时朝向——
##   主角第三人称永远面向相机，转身（转视角）时旧算法会让整个队形绕着主角旋转、
##   成员不停重走（「踱步」主因之一）。队长停下后槽位冻结为世界坐标「休整位」，
##   成员就地站定；队长在 REST_RELEASE_DIST 内小挪动也不重新列队。
## - 动画按实际速度：站定播 idle、常速跟随播步行、集结追赶（2×）播跑步——
##   不再「站着播走路循环」（旧版原地踏步观感的来源之一）。
## - 集结令（gather=true）附带短暂停火期：RALLY_BREAKOFF_SEC 内不自动接战，
##   先归队列阵（主人「集合」命令优先于就近索敌）；集火令仍最高优先，不受停火影响。
## - 集结追赶期 2× 速度、就位后永久回落 1×（v12 契约不变）；
##   到位停住（速度硬置零 + 滞回 + 分离死区/上限）不再原地「搓」。
## - 远距（> NAV_SEEK_DIST）走格子 A* 绕障；近距 steering 贴身；卡位自愈见 Pawn。
## ============================================================================

const SETTLE_DIST: float = 1.3        # 离槽位小于此距离则「到位」：不再 seek（原地待命 + 仅做分离）
const SETTLE_HYSTERESIS: float = 0.9  # 到位滞回：被挤开超过 SETTLE_DIST + 此值才重新 seek（防到位后原地搓动）
const GATHER_SPEED_MULT: float = 2.0  # 集结追赶期速度倍率（+100%）
const GATHER_START_DIST: float = 10.0 # 进入 follow 时距主角超过此距离 → 判定为集结追赶期
const GATHER_DONE_DIST: float = SETTLE_DIST + 1.0  # 离槽位进入此距离视为「已就位」→ 速度永久回落 1×
const ENGAGE_RANGE: float = 7.0       # 此范围内有敌则自动接战
const SEPARATION_RADIUS: float = 1.5  # 与其它小队成员小于此距离则互相推开
const SEPARATION_WEIGHT: float = 5.0  # 分离力强度
const SEPARATION_DEADZONE: float = 0.12 # 分离死区：合力小于此值（重叠略小于 SEPARATION_RADIUS）直接置零
const SEPARATION_MAX_RATIO: float = 0.15 # 分离力上限 = 当前有效速度 × 此值（跟随时总速度 ≤ 1.15× 原速）
const NAV_SEEK_DIST: float = 5.5      # 距槽位超过此距离 → 走格子 A*（绕障）
const NAV_RETARGET_MOVE: float = 1.6  # 槽位挪动超过此距离才重新寻路（节流）
const STEER_STUCK_SEC: float = 1.2    # 贴身期无进展时长 → 临时切回寻路绕行
const RALLY_BREAKOFF_SEC: float = 2.5 # 集结令停火期：此秒数内不自动接战、先归队（集火令不受限）
const LEADER_MOVE_EPS: float = 0.6    # 队长水平速度超过此值 = 行进中（低于 = 停下，冻结休整位）
const FORM_TURN_RATE: float = 2.6     # 行进中队形朝向的最大角速度（rad/s，平滑旋转防甩尾）
const REST_RELEASE_DIST: float = 3.0  # 队长偏离休整锚点超过此距离才重新列队


var _slot: int = 0
var _angle_jitter: float = 0.0
var _radius_jitter: float = 0.0
var _last_nav_slot: Vector3 = Vector3.INF   # 上次寻路时的槽位位置（节流基准）
var _steer_stuck_t: float = 0.0             # 贴身 steering 卡位计时
var _steer_stuck_pos: Vector3 = Vector3.ZERO
var _nav_escape_frames: int = 0             # >0 = 贴身卡位后的强制寻路窗口（物理帧）
var _chasing: bool = false                  # 集结追赶期：2× 速度冲向槽位；就位一次后永久回落 1×
var _settled: bool = false                  # 已到位（带滞回）：到位后不再 seek，只留被动滑移
var _rally_breakoff_t: float = 0.0          # 集结停火期剩余秒数（>0 = 只归队不接战）
var _form_dir: Vector3 = Vector3.ZERO       # 队形朝向（平滑后的队长移动方向，XZ）
var _rest_valid: bool = false               # 队长停下后是否已冻结休整位
var _rest_anchor: Vector3 = Vector3.INF     # 冻结休整位时的队长位置
var _rest_pos: Vector3 = Vector3.INF        # 我的休整位（世界坐标，冻结不动）


func enter(msg: Dictionary) -> void:
	# 槽位优先取 msg（Hero.recruit_squad 显式分派），缺省回落 Pawn.squad_slot——
	# 战斗 / 待机后经 idle 路由回 follow 时不再传 slot，保持队形不散（旧版全员回落 0 号）。
	_slot = int(msg.get("slot", pawn.squad_slot))
	# 基于 slot 的确定性「抖动」种子（不加 Pawn 字段，每成员稳定且各异）
	var s: float = float(_slot + 1) * 1.357
	_angle_jitter = (sin(s) * 0.5) * 0.6      # 约 ±0.3 rad
	_radius_jitter = cos(s * 1.7) * 0.5       # ±0.5 m
	pawn.velocity = Vector3.ZERO
	_last_nav_slot = Vector3.INF
	_steer_stuck_t = 0.0
	_nav_escape_frames = 0
	_steer_stuck_pos = pawn.global_position
	# ---- 集结追赶期判定（「集结时加速 100% 冲到位，跟随时原速」）----
	# G 集结 / 进入操控模式走 recruit_squad(msg.gather=true) → 必为追赶期；
	# 从战斗或自主 AI 回到 follow 时若距主角超过 GATHER_START_DIST 也按追赶期处理（快速归队），
	# 否则直接 1× 原速跟随。就位一次后 _chasing 永久为 false（除非重新集结 / 重新进入 follow）。
	var leader = pawn.follow_leader if pawn.follow_leader != null else msg.get("leader")
	var dist_to_leader: float = INF
	if leader != null and is_instance_valid(leader) and leader is Node3D:
		dist_to_leader = pawn.global_position.distance_to((leader as Node3D).global_position)
	_chasing = bool(msg.get("gather", false)) or dist_to_leader > GATHER_START_DIST
	_settled = false
	_sync_speed_multiplier()
	# 集结令附带停火期：先归队列阵，不被沿途近敌拉走（「集合」是主人命令，最高优先之一）
	_rally_breakoff_t = RALLY_BREAKOFF_SEC if bool(msg.get("gather", false)) else 0.0
	# 队形朝向初值：队长在动 → 移动方向；否则队长朝向（仅作休整槽位的展开基准）
	_form_dir = _leader_dir_hint(leader)
	_rest_valid = false
	_rest_anchor = Vector3.INF
	_rest_pos = Vector3.INF
	pawn.play_anim(&"idle")


func exit() -> void:
	# 集结倍率不得泄漏到战斗 / 巡逻 / 采集等其它状态
	if pawn != null and is_instance_valid(pawn):
		pawn.speed_multiplier = 1.0


## 追赶期 2×、稳态 1×（写入 Pawn.speed_multiplier，寻路与 steering 两个分支共用）。
func _sync_speed_multiplier() -> void:
	pawn.speed_multiplier = GATHER_SPEED_MULT if _chasing else 1.0


## 小队成员间的分离力（软件避让）。两条约束保证「停得住、跟得原速」：
## ① **静止死区**：合力低于 SEPARATION_DEADZONE 直接置零，避免到位后成员互相微量推挤、一帧帧「搓」；
## ② **上限比例**：合力不超过当前有效速度的 SEPARATION_MAX_RATIO——互相让位时总速度最多 1.15× 原速，
##   不会被分离力顶到 Pawn 的 1.3× 限速上限（「跟随时原速」的字面要求）。
func _separation_force() -> Vector3:
	var sep: Vector3 = pawn.compute_separation("hero_squad", SEPARATION_RADIUS) * SEPARATION_WEIGHT
	var mag: float = sep.length()
	if mag < SEPARATION_DEADZONE * SEPARATION_WEIGHT:
		return Vector3.ZERO
	var cap: float = pawn.effective_move_speed() * SEPARATION_MAX_RATIO
	if mag > cap:
		sep = sep * (cap / mag)
	return sep


func physics_update(delta: float) -> void:
	var leader = pawn.follow_leader
	if leader == null or not is_instance_valid(leader):
		state_machine.transition_to("idle")
		return

	# ---- 1) 队长集火令（最高优先）----
	# 目标活着就全员优先围攻（FightState 对集火目标不做姿态 leash / 距离脱战）；
	# 正在打其它目标的成员由 FightState / RangedFightState 每帧轮询转火，这里只管 follow 态。
	var focus = leader.get("focus_target") if leader.has_method("is_focus_alive") else null
	if focus != null and leader.call("is_focus_alive"):
		if state_machine.current_state == null or state_machine.current_state.name != "fight" \
				or pawn.combat_target != focus:
			state_machine.transition_to("fight", {"target": focus})
		return

	# ---- 2) 集结停火期倒计时 ----
	if _rally_breakoff_t > 0.0:
		_rally_breakoff_t = maxf(0.0, _rally_breakoff_t - delta)

	# ---- 3) 近敌自动接战（停火期内让位给「先归队」），结束后经 idle 路由回 follow ----
	if _rally_breakoff_t <= 0.0 and pawn.is_auto_fighter:
		var enemy = pawn.find_nearest_hostile(ENGAGE_RANGE)
		if enemy != null:
			state_machine.transition_to("fight", {"target": enemy})
			return

	var leader_pos: Vector3 = leader.global_position
	var target_pos: Vector3 = _follow_target(leader, leader_pos, delta)
	var nav: NavSystem = pawn._get_nav_system()
	if nav != null and not nav.can_walk_segment(target_pos, target_pos):
		target_pos = nav.snap_to_walkable(target_pos)
	var to_target: Vector3 = target_pos - pawn.global_position
	to_target.y = 0.0
	var dist: float = to_target.length()

	# ---- 就位滞回 + 集结完成判定（每帧一次，阈值不重叠）----
	if dist <= SETTLE_DIST:
		_settled = true
		_nav_escape_frames = 0        # 到位即结束逃逸窗口，本帧转入「停住」分支
	elif dist > SETTLE_DIST + SETTLE_HYSTERESIS:
		_settled = false              # 被推离 / 主角走远：重新 seek
	if _chasing and dist <= GATHER_DONE_DIST:
		_chasing = false              # 集结完成：此后持续跟随一律 1× 原速
		_sync_speed_multiplier()

	# ---- 远距 / 贴身卡位逃逸：格子寻路接近槽位（绕墙绕树绕湖）----
	if _nav_escape_frames > 0:
		_nav_escape_frames -= 1
	var blocked_shortcut: bool = not _settled and nav != null and not nav.can_walk_segment(pawn.global_position, target_pos)
	if dist > NAV_SEEK_DIST or _nav_escape_frames > 0 or blocked_shortcut:
		if _last_nav_slot.distance_squared_to(target_pos) > NAV_RETARGET_MOVE * NAV_RETARGET_MOVE:
			_last_nav_slot = target_pos
			pawn.set_navigation_target(target_pos, true)
		# 寻路期同样叠加成员分离力，避免队伍在航点上叠罗汉
		pawn._steer_separation = _separation_force()
		pawn.move_along_path(delta)
		_sync_move_anim()
		# 寻路推进有位移即视为脱困成功
		if _nav_escape_frames > 0 and pawn.global_position.distance_to(_steer_stuck_pos) > 0.4:
			_nav_escape_frames = 0
		return

	# ---- 已到位：停住（不再 seek 槽位）----
	# 只保留「被动滑移」：与队友重叠到死区以上时被分离力推开一帧，其余时刻速度硬置零，
	# 因此在主角周围站定时不会出现原地慢慢搓动。
	if _settled:
		_last_nav_slot = Vector3.INF   # 下次离开近距时强制重新寻路
		var sep_hold: Vector3 = _separation_force()
		pawn.velocity = Vector3.ZERO
		# v28 硬化：站定时的被动滑移设最小推力门槛（0.35 m/s，覆盖 --fixed-fps 批处理
		# 环境下的残余微推力）——slot 间距落在分离力死区之上的微推力会让成员持续蹭开
		# （主角原地转身 2s 漂 6-10cm，间歇性踩爆「转身零踱步」契约）；低于门槛直接
		# 吞掉，真实重叠（队友叠进来）的推力远超门槛，照常滑开不叠罗汉。
		if sep_hold.length_squared() < 0.1225:
			pawn._steer_separation = Vector3.ZERO
			pawn.move_and_slide()
		else:
			pawn._steer_separation = sep_hold
			pawn._slide_with_separation()
		_steer_stuck_t = 0.0
		_steer_stuck_pos = pawn.global_position
		_sync_move_anim()
		return

	# ---- 近距：steering 贴身占位（原行为）----
	_last_nav_slot = Vector3.INF   # 离开远距模式，下次进入时强制重新寻路
	var vel := Vector3.ZERO
	if dist > SETTLE_DIST:
		vel = (to_target / maxf(dist, 0.0001)) * pawn.effective_move_speed()
	# 成员间分离（去重叠）：走 Pawn 静态空间桶索引（O(邻域)），
	# hero_squad 成员必属 player_unit 组，故桶内可查；语义与旧的逐成员遍历一致。
	vel += _separation_force()
	# 限速，避免 seek + 分离叠加超速
	var max_spd: float = pawn.effective_move_speed() * 1.25
	if vel.length_squared() > max_spd * max_spd:
		vel = vel.normalized() * max_spd

	pawn.velocity = vel
	pawn.move_and_slide()
	_sync_move_anim()
	# 贴身期卡位检测：想走（有速度指令）却没挪窝 → 临时切回寻路模式绕出去
	if vel.length_squared() > 0.2:
		_steer_stuck_t += delta
		if _steer_stuck_t >= STEER_STUCK_SEC:
			if pawn.global_position.distance_to(_steer_stuck_pos) < 0.5:
				_nav_escape_frames = 75   # ~1.25s 寻路逃逸窗口
			_steer_stuck_t = 0.0
			_steer_stuck_pos = pawn.global_position
	else:
		_steer_stuck_t = 0.0
		_steer_stuck_pos = pawn.global_position


# ---- 拟真队形 ----

## 本帧的槽位目标点：
## - 队长行进中：队形朝向 = 平滑后的队长【移动方向】，槽位随队长平移（部队跟着走）；
## - 队长停下：把当前槽位冻结为休整位（世界坐标），成员就地站定不再重排——
##   主角原地转身（第三人称朝向 = 相机朝向）不会带动队形旋转，彻底消除「围着主角踱步」；
##   队长偏离锚点超过 REST_RELEASE_DIST（真走远了）才按新位置重新列队。
func _follow_target(leader, leader_pos: Vector3, delta: float) -> Vector3:
	var lv := Vector3.ZERO
	if leader is Pawn:
		lv = (leader as Pawn).velocity
	lv.y = 0.0
	if lv.length() > LEADER_MOVE_EPS:
		_form_dir = _rotate_toward(_form_dir, lv.normalized(), FORM_TURN_RATE * delta)
		_rest_valid = false   # 行进中休整位作废
		return leader_pos + _slot_offset(_form_dir)
	if not _rest_valid or leader_pos.distance_to(_rest_anchor) > REST_RELEASE_DIST:
		var base := _form_dir
		if base.length_squared() < 0.001:
			base = _leader_dir_hint(leader)
		_rest_anchor = leader_pos
		_rest_pos = leader_pos + _slot_offset(base)
		_rest_valid = true
	return _rest_pos


## 槽位相对队长的偏移：身后松散扇形（每 3 人一圈，半径随圈数增长，角度散开 + 抖动）。
func _slot_offset(dir: Vector3) -> Vector3:
	var fwd := Vector3(dir.x, 0.0, dir.z)
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var ring: int = _slot / 3
	var in_ring: int = _slot % 3
	var radius: float = 1.7 + float(ring) * 1.3 + _radius_jitter
	var a: float = (float(in_ring) - 1.0) * 0.9 + _angle_jitter + float(ring) * 0.4
	var right := Vector3(-fwd.z, 0.0, fwd.x)         # fwd 的右侧
	var back := -fwd                                  # 身后
	var offset := (back * cos(a) + right * sin(a)) * radius
	return Vector3(offset.x, 0.0, offset.z)


## 队形朝向提示：队长在动取移动方向，否则取其朝向（仅用于休整槽位的展开基准）。
func _leader_dir_hint(leader) -> Vector3:
	if leader is Pawn:
		var lv: Vector3 = (leader as Pawn).velocity
		lv.y = 0.0
		if lv.length_squared() > 0.0001:
			return lv.normalized()
	if leader is Node3D:
		var b: Basis = (leader as Node3D).global_transform.basis
		var f := -b.z
		f.y = 0.0
		if f.length_squared() > 0.001:
			return f.normalized()
	return Vector3.FORWARD


## 把 cur 向 want 旋转至多 max_rad 弧度（XZ 平面），队形转向的限速平滑。
func _rotate_toward(cur: Vector3, want: Vector3, max_rad: float) -> Vector3:
	var c := Vector3(cur.x, 0.0, cur.z)
	var w := Vector3(want.x, 0.0, want.z)
	if w.length_squared() < 0.0001:
		return c.normalized() if c.length_squared() > 0.0001 else Vector3.FORWARD
	w = w.normalized()
	if c.length_squared() < 0.0001:
		return w
	c = c.normalized()
	var ang: float = c.angle_to(w)
	if ang <= max_rad or ang < 0.0001:
		return w
	var side: float = c.cross(w).y
	var sign := 1.0 if side >= 0.0 else -1.0
	return c.rotated(Vector3.UP, sign * minf(ang, max_rad)).normalized()


## 动画跟随实际速度：站定播 idle（站着不再播走路循环）、常速播步行、追赶期（倍速）播跑步。
func _sync_move_anim() -> void:
	var h := Vector2(pawn.velocity.x, pawn.velocity.z).length_squared()
	if h < 0.04:
		pawn.play_anim(&"idle")
	elif pawn.speed_multiplier > 1.05:
		pawn.play_anim(&"run")
	else:
		pawn.play_anim(&"follow")
