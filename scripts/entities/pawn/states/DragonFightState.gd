class_name DragonFightState
extends PawnState
## ============================================================================
## 巨龙战斗态：打「当前优先级最高的目标」（v32 三级优先级，见 DragonPet.pick_target）。
## - 每帧轮询 pick_target()：主角一有目标（集火令 T / 主角攻击目标）**立即转火**；
##   自主目标（主角没指定时自己挑的）出「主角圈」/死亡 → 自动换目标或回跟随态；
## - 吐息 CD 就绪且目标在锥形射程内 → 优先转入吐息态（技能 > 普攻）；
## - 普攻 = 站定朝目标吐火球（spawn_fireball，命中爆炸溅射）；
## - 追击 leash：主角跑远（> BREAK_WITH_MASTER_DIST）时放弃目标回主人身边——
##   「一直跟着玩家」优先于输出；自主目标的圈内 leash 由 pick_target 负责（11m 锁 / 13.75m 丢）。
## ============================================================================

const BREAK_WITH_MASTER_DIST: float = 26.0  # 距主角超过此距离：放弃目标回主人身边
const APPROACH_SETTLE: float = 0.8           # 到达环绕站位附近才站定吐球
const AIM_TOLERANCE_DEG: float = 18.0        # 朝向与目标夹角小于此值才吐球（v29 对准门槛）
const SEPARATION_RADIUS_BASE: float = 2.2   # ×def.body_scale（大体型龙不能贴人站）
const SEPARATION_WEIGHT: float = 4.0

var target: Node = null
var self_target: bool = false               # true = 自主索敌挑的（受主角圈 leash 约束）
var _last_target_pos: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
const RETARGET_DIST: float = 1.0
const RETARGET_TIMEOUT: float = 0.5


func enter(msg: Dictionary) -> void:
	target = msg.get("target", null)
	pawn.combat_target = target
	var pet := pawn as DragonPet
	self_target = pet != null and not pet.is_hero_target(target)
	_last_target_pos = Vector3.ZERO
	_retarget_timer = RETARGET_TIMEOUT
	pawn.play_anim(&"run")


func physics_update(delta: float) -> void:
	var pet := pawn as DragonPet
	if pet == null or pet.dragon_def == null:
		return

	# ---- 目标同步（v32 三级优先级）：主角换目标立即转火；自主目标出圈/死亡 → 换目标或回跟随 ----
	var live = pet.pick_target()
	if live == null:
		state_machine.transition_to("dragon_follow", {})
		return
	if live != target:
		target = live
		self_target = not pet.is_hero_target(target)   # 记下这一轮是「自主目标」还是「主角指定」
		pawn.combat_target = target
		_last_target_pos = Vector3.ZERO
		_retarget_timer = RETARGET_TIMEOUT

	# ---- 跟着主人优先：主角跑远就收手回队 ----
	var leader = pawn.follow_leader
	if leader != null and is_instance_valid(leader) and leader is Node3D:
		if pawn.global_position.distance_to((leader as Node3D).global_position) > BREAK_WITH_MASTER_DIST:
			state_machine.transition_to("dragon_follow", {})
			return

	var tn := target as Node3D
	var dist: float = pawn.global_position.distance_to(tn.global_position)

	# ---- 技能优先：吐息 CD 就绪且目标进入锥形射程 → 原地喷火 ----
	if pet.breath_ready() and dist <= pet.dragon_def.breath_range * 0.9:
		state_machine.transition_to("dragon_breath", {"target": target})
		return

	# ---- 普攻：站定吐火球（先限速转身对准，再出膛）----
	if dist <= pet.dragon_def.fireball_range:
		pawn.velocity = Vector3.ZERO
		pawn.move_and_slide()
		var aim: Vector3 = tn.global_position - pawn.global_position
		aim.y = 0.0
		if aim.length_squared() > 0.001:
			pawn.look_at_target(aim)          # DragonPet 覆写：限速转身（不瞬移）
		if pet.facing_error_deg(aim) > AIM_TOLERANCE_DEG:
			# 还在转（或目标绕到侧后）：站定瞄准，别从身侧横着吐球
			pawn.play_anim(&"idle")
			return
		if pet.fireball_ready():
			pet.spawn_fireball(target, aim)
			pawn.play_anim(&"fight")
		else:
			pawn.play_anim(&"idle")
		return

	# ---- 追击：走向环绕站位（与小队共用同一套分槽，避免围重叠）----
	_retarget_timer += delta
	var moved: float = tn.global_position.distance_to(_last_target_pos)
	if moved > RETARGET_DIST or _retarget_timer >= RETARGET_TIMEOUT:
		_update_nav_target()
		_retarget_timer = 0.0
	pawn._steer_separation = pawn.compute_separation("player_unit",
		SEPARATION_RADIUS_BASE * pawn.body_scale()) * SEPARATION_WEIGHT
	pawn.play_anim(&"idle" if pawn.navigation_status in [Pawn.NavigationStatus.UNREACHABLE, Pawn.NavigationStatus.BLOCKED] else &"run")
	pawn.move_along_path(delta)
	if pawn.navigation_status in [Pawn.NavigationStatus.UNREACHABLE, Pawn.NavigationStatus.BLOCKED]:
		# 绕不过去（隔墙 / 隔湖）：等主人自己打完，别对着墙喷
		state_machine.transition_to("dragon_follow", {})
		return


func _update_nav_target() -> void:
	if state_machine.current_state != self or target == null or not is_instance_valid(target):
		return
	var pos: Vector3 = pawn.get_combat_approach_position(target as Node3D)
	pawn.set_navigation_target(pos)
	_last_target_pos = (target as Node3D).global_position


func _on_navmesh_updated() -> void:
	_update_nav_target()


func exit() -> void:
	if pawn.combat_target == target:
		pawn.combat_target = null
