class_name Pawn
extends CharacterBody3D
## ============================================================================
## Pawn 基类：玩家殖民者 / 入侵敌人共用骨架。
## 子节点（代码构建）：MeshInstance3D / CollisionShape3D / HealthComponent /
##   TeamComponent / [SelectableComponent] / AttackerComponent / SelectionRing / StateMachine
## ============================================================================

@export var def: PawnDef

# 组件引用
var health: HealthComponent
var team_comp: TeamComponent
var selectable: SelectableComponent
var attacker: AttackerComponent
var state_machine: PawnStateMachine
var nav_agent: NavigationAgent3D
var model_rig: PawnModelRig          # 骨骼模型 + 动画挂载（占位美术通道；无模型时不影响逻辑）
var health_bar: HealthBar3D          # 头顶血条（_setup_nodes 创建，_apply_def 注入阵营色）
var speech_bubble: SpeechBubble3D    # 头顶人设气泡（随机低频台词；台词池在 GameDefs.BUBBLE_LINES）
var is_hero_unit: bool = false       # 是否主角实例（Hero._ready 置 true；供血条着色，避免基类 is Hero 的循环依赖）
# 手动管理格子路径：建筑会即时更新 NavSystem 的 A* 占用格，不需要运行时重烘焙 NavMesh。
# nav_agent 节点保留为将来接入 Godot avoidance 的扩展点；当前路径由 NavSystem 统一提供。
var _nav_path: PackedVector3Array = PackedVector3Array()
var _nav_idx: int = 0
var _nav_target: Vector3 = Vector3.ZERO
var _nav_dirty: bool = false
var _nav_repath_left: float = 0.0
const NAV_REPATH_INTERVAL: float = 0.25
const NAV_FAILED_RETRY_INTERVAL: float = 1.0
# Arrival and failure are distinct: never pretend a blocked pawn reached its goal.
enum NavigationStatus { MOVING, ARRIVED, UNREACHABLE, BLOCKED }
var navigation_status: NavigationStatus = NavigationStatus.MOVING
const STUCK_SAMPLE_SEC: float = 0.8
const STUCK_MIN_MOVE: float = 0.25
const STUCK_MAX_HITS: int = 2
var _stuck_sample_t: float = 0.0
var _stuck_sample_pos: Vector3 = Vector3.ZERO
var _stuck_hits: int = 0
var _stuck_snapped: bool = false
var _stuck_last_remaining: float = INF
var _stuck_sample_waypoint: Vector3 = Vector3.INF
var stat_repaths: int = 0
var stat_stuck_recoveries: int = 0
var stat_terrain_rescues: int = 0   # v36：从水面 / 阻挡格自动搬回岸上的次数

# 移动 / 状态
var move_target: Vector3 = Vector3.ZERO
var move_speed: float = 4.0
## 状态可写的临时移动速度倍率（默认 1.0 = 原速，其它状态完全不受影响）。
## 目前只有集结追赶期的 FollowState 会置 2.0，离开 follow 时必须还原（见 FollowState.exit）。
var speed_multiplier: float = 1.0
var is_selected: bool = false
var is_dead_flag: bool = false
var is_auto_fighter: bool = true
var follow_leader = null              # 主角小队跟随目标（Hero）；为 null 表示不在小队中
var squad_slot: int = 0               # 小队槽位编号（Hero 编队 / 重排时维护；FollowState 持久读取）
var avoids_city: bool = false         # 野怪=true：不索敌城内目标、追击中目标进城则脱战（永不进主城）
var can_be_targeted_by_enemies: bool = true # 流民等非战斗角色不会被野怪锁定
var combat_target: Node = null        # 当前交战目标：供自动索敌分摊压力与战斗站位分槽使用
# ---- v19 状态效果（减速 / 易伤）与职业技能 ----
var skill_comp: PawnSkillComponent = null   # 职业技能组件（def.skill 非空才挂载；否则恒 null）
var _slow_factor: float = 1.0         # 减速期的移速乘数（1 = 未减速）
var _slow_left: float = 0.0           # 减速剩余秒数
var _vuln_mult: float = 1.0           # 易伤期的受伤乘数（1 = 未易伤）
var _vuln_left: float = 0.0           # 易伤剩余秒数
var _buff_marks: BuffMarks3D = null   # 头顶状态标记（首次挂 buff 时懒创建）

# ---- v20 属性系统：等级 / 经验 / 六维 ----
# 血量 / 攻击 / 移速分别落在 health.max_hp / attacker.damage / move_speed（升级时重算），
# 防御与暴击没有现成组件承载，存本类变量。等级成长只对 def.can_level 的小兵生效；
# 主角覆写 xp_to_next/_level_up 走自己的成长线（称号 / +30 血 / damage_mult）。
var level: int = 1
var xp: int = 0
var defense_stat: float = 0.0         # 当前防御力（基础值 × 等级成长）
var crit_stat: float = 0.0            # 当前暴击率（0~CRIT_CAP；AttackerComponent 掷骰）
# 小兵成长曲线（主角不适用）：升级所需经验、每级六维成长、暴击封顶。
const LEVEL_XP_BASE: int = 40         # 1→2 级所需经验（之后每级 +25）
const LEVEL_XP_STEP: int = 25
const MAX_LEVEL: int = 10             # 小兵等级封顶（与主角称号表同规模）
const GROWTH_HP: float = 0.12         # 每级生命 +12%（v24：夜潮 6~11 只/9s 压力下加厚）
const GROWTH_ATTACK: float = 0.10     # 每级攻击 +10%（v24：Lv.10 ≈ ×1.9，成长有感）
const GROWTH_DEFENSE: float = 0.10    # 每级防御 +10%
const GROWTH_SPEED: float = 0.015     # 每级移速 +1.5%（腿程微成长）
const GROWTH_CRIT: float = 0.010      # 每级暴击率 +1%（v24：0.5% 无感，翻倍；Lv.10 +9%）
const CRIT_CAP: float = 0.75          # 暴击率封顶（含成长）
const DEFENSE_K: float = 80.0         # 减伤常数：受伤 × K/(K+防御)。防御 40 → 减伤 33%

# ---- v25 技能树 / 技能点 ----
# def.skill_tree_id 非空的单位（主角 + 定居四职业小兵）拥有技能树：
# 每次升级 +1 技能点，可在技能树界面（市民管理进入）点亮分支强化角色。
var skill_points: int = 0             # 可用技能点（升级获得，加点消耗）
var skill_tree: PawnSkillTree = null  # 技能树运行时状态（_apply_def 按 def 创建）


## 是否拥有技能树（UI 据此决定是否显示「技能树」入口）。
func has_skill_tree() -> bool:
	return skill_tree != null


## 技能树累计攻击伤害加成（0.15 = +15%；无树 = 0）。六维重算时乘入攻击面板。
func skill_tree_damage_bonus() -> float:
	return skill_tree.damage_bonus() if skill_tree != null else 0.0


## 技能树累计生命上限加成（无树 = 0）。
func skill_tree_hp_bonus() -> float:
	return skill_tree.hp_bonus() if skill_tree != null else 0.0


## 加点统一入口：校验（有树 / 有点 / 未满级 / 前置满足）→ 扣点 → 加级 → 面板重算。
## 返回是否成功（UI 的加点按钮调用；失败原因可用 skill_tree.invest_block_reason 查询）。
func try_invest_skill_point(node_id: StringName) -> bool:
	if skill_tree == null or is_dead_flag:
		return false
	if not skill_tree.invest(node_id, skill_points):
		return false
	skill_points -= 1
	_rebase_stats_for_tree()
	var n := skill_tree.node(node_id)
	if n != null:
		EventBus.floating_text.emit("%s Lv.%d" % [n.display_name, skill_tree.rank(node_id)],
			Color(0.55, 0.9, 1.0), global_position + Vector3(0.0, 2.5, 0.0))
	AudioManager.play_sfx(&"level_up", global_position)
	EventBus.skill_tree_changed.emit(self)
	return true


## 技能树加点后的面板重算：士兵线复用六维重算（血量差补入当前血），主角覆写走自己的公式。
func _rebase_stats_for_tree() -> void:
	var old_max: float = health.max_hp if health != null else 0.0
	_apply_stats_for_level()
	if health != null:
		var delta: float = health.max_hp - old_max
		if delta > 0.0:
			health.current_hp = clampf(health.current_hp + delta, health.current_hp, health.max_hp)
		health.health_changed.emit(health.current_hp, health.max_hp)
	# 血怒中的战士：面板基线重挂（与升级同款处理）
	if skill_comp != null:
		skill_comp.notify_stats_rebased()


## 是否允许自动索敌接战（IdleState / MoveState 每帧询问）。
## 基类直接看 is_auto_fighter；Hero 覆写：战术俯瞰 RTS 下主角待命，完全等玩家下令。
func autofight_enabled() -> bool:
	return is_auto_fighter


# ---- v19 状态效果（减速 / 易伤）与职业技能 ----

const HIT_REACT_THROTTLE: float = 0.5   # 受击动画的最小间隔（秒）
var _hit_react_left: float = 0.0        # 受击动画节流剩余

## 状态效果倒计时（独立于各状态机的 _physics_process，任何状态下都推进）。
func _physics_process(_delta: float) -> void:
	if _hostile_retry_left > 0.0:
		_hostile_retry_left = maxf(0.0, _hostile_retry_left - _delta)
	if _hit_react_left > 0.0:
		_hit_react_left = maxf(0.0, _hit_react_left - _delta)
	if _slow_left > 0.0:
		_slow_left -= _delta
		if _slow_left <= 0.0:
			_slow_left = 0.0
			_slow_factor = 1.0
	if _vuln_left > 0.0:
		_vuln_left -= _delta
		if _vuln_left <= 0.0:
			_vuln_left = 0.0
			_vuln_mult = 1.0
	# v33 隐身倒计时：到期自动解除（造成伤害提前破隐走 EventBus 回调）
	if _stealth_active:
		_stealth_left -= _delta
		if _stealth_left <= 0.0:
			break_stealth()
	# v36：滞留在湖 / 河 / 崖等阻挡格里的单位自动搬回最近可走格（兜底自救）
	_check_terrain_rescue(_delta)


## 施加减速：取更慢的系数、取更长的剩余时间（暴风雪逐跳刷新用）。
func apply_slow(factor: float, duration: float) -> void:
	if is_dead_flag or factor >= 1.0 or duration <= 0.0:
		return
	var cur: float = _slow_factor if _slow_left > 0.0 else 1.0
	_slow_factor = clampf(minf(cur, factor), 0.05, 1.0)
	_slow_left = maxf(_slow_left, duration)
	show_status_mark(&"slow", _slow_left)


## 施加易伤（受到伤害乘数提升）：取更高乘数、取更长的剩余时间。
func apply_vulnerable(mult: float, duration: float) -> void:
	if is_dead_flag or mult <= 1.0 or duration <= 0.0:
		return
	var cur: float = _vuln_mult if _vuln_left > 0.0 else 1.0
	_vuln_mult = maxf(cur, mult)
	_vuln_left = maxf(_vuln_left, duration)
	show_status_mark(&"vuln", _vuln_left)


## 当前受伤乘数（HealthComponent.apply_damage 统一读取；未易伤 = 1.0）。
func incoming_damage_mult() -> float:
	return _vuln_mult if _vuln_left > 0.0 else 1.0


func slow_active() -> bool:
	return _slow_left > 0.0 and _slow_factor < 1.0


func vuln_active() -> bool:
	return _vuln_left > 0.0 and _vuln_mult > 1.0


## 显示一枚头顶状态标记（slow / vuln / rage；到期由 BuffMarks3D 自隐藏）。
func show_status_mark(id: StringName, duration: float) -> void:
	if _buff_marks == null or not is_instance_valid(_buff_marks):
		_buff_marks = BuffMarks3D.new()
		_buff_marks.name = "BuffMarks3D"
		add_child(_buff_marks)
	_buff_marks.show_mark(id, duration)


## 战斗状态每帧调用：职业技能 CD 就绪即瞬发（无技能 / 未就绪返回 false 不影响普攻）。
## v25.1：职业技能需先在技能树点亮「职业技」根节点（主角走 Q/C 管线，不经此门禁）。
## v33：施法锁定中 / 受控（击飞眩晕）中一律不施法。
func try_cast_combat_skill(target: Node) -> bool:
	if skill_comp == null or skill_locked or is_controlled():
		return false
	if skill_tree != null and not skill_tree.skill_unlocked():
		return false
	return skill_comp.try_cast(target)


## 职业技当前是否已解锁（UI / 测试用；无树 = 视为解锁）。
func combat_skill_unlocked() -> bool:
	return skill_tree == null or skill_tree.skill_unlocked()


# ============================================================================
# v33 进阶职业技能宿主接口
# ============================================================================

# ---- 技能门禁 ----

## 指定技能是否已解锁（多技能门禁，PawnSkillComponent.try_cast 逐个询问）。
## 无树（野怪 / 无技能单位）= true；有树走 skill_tree.is_skill_unlocked（精确 id 匹配）。
func is_skill_unlocked(skill_id: StringName) -> bool:
	if skill_tree == null:
		return true
	return skill_tree.is_skill_unlocked(skill_id)


# ---- 施法态锁定 ----

## 施法锁：前摇 / 收招期间为 true——普攻与二次施法让位，玩家能看到「正在读条」。
var skill_locked: bool = false
var _cast_target = null               # 本次施法的目标（end_skill_cast 回接战用）


func is_skill_locked() -> bool:
	return skill_locked


## 置施法锁（供 PawnSkillComponent / SkillCastState 内部调用；外部请走 begin/end_skill_cast）。
func set_skill_locked(value: bool) -> void:
	skill_locked = value


## 开始施法：上锁 + 切到 skill_cast 状态（由 PawnSkillComponent.try_cast 调用）。
## 返回是否**真的进入了施法态**：施法状态未注册（状态脚本缺失）/ 已死亡 → false，
## 且此时不置锁——调用方（技能组件）据此决定是否消耗 CD，不会白吃冷却或被永久锁死。
func begin_skill_cast(skill: PawnSkillDef, target: Node) -> bool:
	if is_dead_flag or state_machine == null or not state_machine.states.has("skill_cast"):
		return false
	skill_locked = true
	_cast_target = target
	state_machine.transition_to("skill_cast", {"skill": skill, "target": target})
	return true


## 结束施法：解锁；目标仍有效 → 回战斗态，否则回待命。
## 只有仍停在施法态时才自动跳转（被击飞 / 死亡打断后不抢状态机的当前状态）。
func end_skill_cast() -> void:
	skill_locked = false
	var t = _cast_target
	_cast_target = null
	if is_dead_flag or state_machine == null or state_machine.current_state == null:
		return
	if String(state_machine.current_state.name) != "skill_cast":
		return
	if t != null and is_instance_valid(t) and not (t is Pawn and (t as Pawn).is_dead_flag):
		state_machine.transition_to("fight", {"target": t})
	else:
		state_machine.transition_to("idle")


# ---- 击飞 / 眩晕（控制效果）----
# 控制期由 StunnedState 每物理帧调 tick_control 推进：滞空段直接写 global_position 走
# 抛物线（水平匀速 + sin 弧抬升），落地后原地眩晕倒计时，结束回 idle 交还自主 AI。
var _control_air_left: float = 0.0        # 滞空剩余秒数
var _control_air_total: float = 0.0       # 滞空总时长（抛物线归一化用）
var _control_stun_left: float = 0.0       # 落地后眩晕剩余秒数
var _control_elapsed: float = 0.0         # 已滞空时间
var _control_origin: Vector3 = Vector3.ZERO     # 起跳点（水平位移基准）
var _control_flat_vel: Vector3 = Vector3.ZERO   # 水平速度（m/s，XZ 平面）
var _control_height: float = 0.0          # 抛物线顶点高度（米）
var _control_ground_y: float = 0.0        # 落地高度（起跳时的 y）


## 施加击飞 + 眩晕（跳劈等控制技能调用）。
## dir：击飞方向（XZ 平面）；distance / height：水平位移与弧线高度；
## airborne：滞空秒数；stun：落地后眩晕秒数。
func apply_knockup(dir: Vector3, distance: float, height: float, airborne: float, stun: float) -> void:
	if is_dead_flag:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.000001:
		flat = global_transform.basis.z   # 方向非法：默认向本地 +Z（逻辑后方）掀飞
	flat = flat.normalized()
	# v36 修复：抛物线是直写坐标、不与物理碰撞，落点先按寻路格裁剪——否则湖边跳劈
	# 会把怪拍进湖面 / 崖体 / 建筑格的静态碰撞盒里，落地即永久卡死。
	var safe_distance := _clamp_knockup_distance(flat, maxf(distance, 0.0))
	_control_origin = global_position
	_control_ground_y = global_position.y
	_control_air_total = maxf(airborne, 0.05)
	_control_air_left = _control_air_total
	_control_elapsed = 0.0
	_control_height = maxf(height, 0.0)
	_control_flat_vel = flat * (safe_distance / _control_air_total)
	_control_stun_left = maxf(stun, 0.0)
	velocity = Vector3.ZERO
	_steer_separation = Vector3.ZERO
	# 击飞打断施法：解锁 + 通知技能组件中止（不结算效果，CD 亦不回滚）
	skill_locked = false
	if skill_comp != null and skill_comp.has_method("abort_cast"):
		skill_comp.call("abort_cast")
	if state_machine != null:
		state_machine.transition_to("stunned")


## 控制推进（StunnedState 每物理帧调用）。返回 false = 击飞 + 眩晕全部结束。
func tick_control(delta: float) -> bool:
	if is_dead_flag:
		return false
	if _control_air_left > 0.0:
		_control_elapsed += delta
		_control_air_left = maxf(0.0, _control_air_left - delta)
		var t: float = clampf(_control_elapsed / _control_air_total, 0.0, 1.0)
		# 抛物线：水平按速度直推，竖直用 sin(πt) 弧（起落在同一水平面）
		var pos: Vector3 = _control_origin + _control_flat_vel * _control_elapsed
		pos.y = _control_ground_y + sin(PI * t) * _control_height
		global_position = pos
		velocity = Vector3.ZERO
		if _control_air_left <= 0.0:
			# 落地：精确落回起跳水平面（sin 弧终点可能差一点点）
			global_position = Vector3(pos.x, _control_ground_y, pos.z)
		return true
	if _control_stun_left > 0.0:
		_control_stun_left = maxf(0.0, _control_stun_left - delta)
		velocity = Vector3.ZERO
		return _control_stun_left > 0.0
	return false


## 击飞落点裁剪（v36）：沿击飞方向小步试探，把水平位移截到最后一个「可站立格」
## 再减半格余量为止。判定与寻路同一套阻挡口径（湖 / 河 / 崖 / 建筑 / 资源 /
## 主城地基都站不得），保证抛物线终点不嵌进任何静态碰撞体。
func _clamp_knockup_distance(flat: Vector3, distance: float) -> float:
	if distance <= 0.05:
		return distance
	var nav := _get_nav_system()
	if nav == null or nav.grid == null:
		return distance
	var origin := global_position
	var clamped := 0.0
	var traveled := 0.4 # 半格一步：既不会跳过窄障碍，也把查询控制在个位数
	while traveled <= distance + 0.001:
		var probe: Vector3 = origin + flat * traveled
		if not nav.is_walkable_cell(nav.grid.world_to_grid(probe)):
			break
		clamped = traveled
		traveled += 0.4
	# 留出 0.4m（≈胶囊半径）边距，防止落在可走格边缘时侧面嵌入相邻阻挡格
	return maxf(clamped - 0.4, 0.0)


# ---- v36 湖泊 / 阻挡格滞留自救 ----
# 击飞抛物线（直写坐标）或历史 bug 可能把单位放进永久阻挡格里：物理上嵌在静态
# 碰撞盒中、寻路也走不出去。这里做一道兜底——连续滞留且几乎没动的单位被搬回
# 最近可走格并立即重算路径；正在涉水通过的（位移明显）与玩家亲自操控的主角不触发。
var _terrain_stuck_cell: Vector2i = Vector2i(9999, 9999)
var _terrain_stuck_time: float = 0.0
var _terrain_stuck_pos: Vector3 = Vector3.ZERO
const TERRAIN_RESCUE_DWELL: float = 2.0   # 连续滞留判定秒数
const TERRAIN_RESCUE_MOVE: float = 0.5    # 滞留期间的最大位移（超过视为正在涉水通过）


## 是否允许自动搬离水面 / 阻挡格。主角覆写为 false：玩家亲自操控，河 / 浅滩
## 本就没有物理碰撞，涉水是合法操作，绝不能自动搬移玩家角色。
func allows_terrain_rescue() -> bool:
	return true


func _check_terrain_rescue(delta: float) -> void:
	if is_dead_flag or is_controlled() or not allows_terrain_rescue():
		_terrain_stuck_cell = Vector2i(9999, 9999)
		return
	var nav := _get_nav_system()
	if nav == null or nav.grid == null:
		return
	var grid := nav.grid
	var cell := grid.world_to_grid(global_position)
	if grid.is_inside(cell) and not grid.is_occupied(cell):
		_terrain_stuck_cell = Vector2i(9999, 9999)
		return
	if cell != _terrain_stuck_cell:
		_terrain_stuck_cell = cell
		_terrain_stuck_time = 0.0
		_terrain_stuck_pos = global_position
		return
	_terrain_stuck_time += delta
	if _terrain_stuck_time < TERRAIN_RESCUE_DWELL:
		return
	_terrain_stuck_time = 0.0
	if global_position.distance_to(_terrain_stuck_pos) > TERRAIN_RESCUE_MOVE:
		# 还在明显移动 = 正在涉水穿过，不搬
		_terrain_stuck_pos = global_position
		return
	var safe := nav.snap_to_walkable(global_position)
	_terrain_stuck_cell = Vector2i(9999, 9999)
	if safe.distance_squared_to(global_position) <= 0.04:
		return
	global_position = safe
	velocity = Vector3.ZERO
	_steer_separation = Vector3.ZERO
	stat_terrain_rescues += 1
	# 立即作废旧路径并请求重算，避免朝湖心旧航点继续走
	_nav_dirty = true
	_nav_repath_left = 0.0
	navigation_status = NavigationStatus.MOVING
	_reset_stuck_tracking()


## 是否处于眩晕中（击飞滞空 + 落地眩晕都算——被砸飞的单位本帧同样无法行动）。
func is_stunned() -> bool:
	return _control_air_left > 0.0 or _control_stun_left > 0.0


## 是否被控制（滞空或眩晕中）。控制类技能 / AI 判定统一用它。
func is_controlled() -> bool:
	return _control_air_left > 0.0 or _control_stun_left > 0.0


# ---- 隐身（暗杀者）----
# 规则：造成伤害即破隐（监听 EventBus.damage_dealt，source == self）；**受到伤害不破隐**
# （隐身是逃生手段，被打一下就现形等于废技）；到期自动解除。
# 视觉由 PawnModelRig.set_stealth 接管，索敌由 can_be_seen_by_enemies() 接管
# （_valid_hostile_candidate 用它判断，敌方 0.2s 索敌缓存命中时也会立刻失效）。
var _stealth_active: bool = false              # 是否处于隐身态
var _stealth_left: float = 0.0                 # 剩余秒数
var _stealth_prev_targetable: bool = true      # 进入前的 can_be_targeted_by_enemies（结束恢复）
var _stealth_trail: Node3D = null              # 持续期微光拖尾（attach_trail 产物，结束即释放）


func is_stealthed() -> bool:
	return _stealth_active


## 敌方是否能索敌到自己（隐身 / 不可锁定 = 看不到）。索敌方一律走这里判断。
func can_be_seen_by_enemies() -> bool:
	return can_be_targeted_by_enemies and not _stealth_active


## 进入隐身：已隐身 / 已死亡 / 时长 <= 0 → false。
## 成功：置不可锁定 + 模型转隐身外观 + 起手特效 + 挂持续微光拖尾。
func apply_stealth(duration: float) -> bool:
	if is_dead_flag or _stealth_active or duration <= 0.0:
		return false
	_stealth_active = true
	_stealth_left = duration
	_stealth_prev_targetable = can_be_targeted_by_enemies
	can_be_targeted_by_enemies = false
	VFXManager.spawn_effect(&"stealth_enter", global_position + Vector3(0.0, 1.0, 0.0), rotation.y,
		{"throttle_key": get_instance_id()})
	if model_rig != null:
		model_rig.set_stealth(true)
	_stealth_trail = VFXManager.attach_trail(self, &"stealth_shimmer")
	return true


## 立即解除隐身（造成伤害 / 到期 / 主动取消）。未隐身时为空操作。
func break_stealth() -> void:
	if not _stealth_active:
		return
	_stealth_active = false
	_stealth_left = 0.0
	can_be_targeted_by_enemies = _stealth_prev_targetable
	if model_rig != null:
		model_rig.set_stealth(false)
	if _stealth_trail != null and is_instance_valid(_stealth_trail):
		_stealth_trail.queue_free()   # 持续微光随破隐消失（拖尾是 Pawn 子节点，不会残留）
	_stealth_trail = null
	VFXManager.spawn_effect(&"stealth_break", global_position + Vector3(0.0, 1.0, 0.0), rotation.y,
		{"throttle_key": get_instance_id()})


## 造成伤害即破隐（受击不破隐——只有自己打出去的伤害才算）。
func _on_damage_dealt_stealth(_target: Node, _amount: float, source: Node) -> void:
	if source == self and _stealth_active:
		break_stealth()


# ---- v20 属性系统：等级 / 经验 / 六维 ----

## 升级所需经验：40 / 65 / 90 …（每级 +25）。主角覆写为自己的曲线（60 / 100 / …）。
func xp_to_next() -> int:
	return LEVEL_XP_BASE + LEVEL_XP_STEP * (level - 1)


## 等级封顶（主角覆写为不封顶——称号表到 10 级后保持「战神」但等级可继续涨）。
func _level_cap() -> int:
	return MAX_LEVEL


## 经验入账（小兵由 Soldier 击杀结算驱动；主角沿用本入口，升级逻辑各自覆写）。
## 支持一次大额经验连升多级；已到等级封顶时经验直接丢弃（不累积）。
func gain_xp(amount: int) -> void:
	if amount <= 0 or level >= _level_cap():
		return
	xp += amount
	while xp >= xp_to_next() and level < _level_cap():
		xp -= xp_to_next()
		_level_up()
	if level >= _level_cap():
		xp = 0


## 小兵升级结算（主角覆写走自己的 +30 血 / damage_mult / 称号线）。
func _level_up() -> void:
	level += 1
	skill_points += 1   # v25：每次升级 +1 技能点（技能树加点用）
	var old_max: float = health.max_hp if health != null else def.max_hp
	_apply_stats_for_level()
	# 成长出的生命差补进当前血（受伤的兵升级不会被「白涨上限不涨血」）
	if health != null:
		health.current_hp = clampf(health.current_hp + (health.max_hp - old_max),
			health.current_hp, health.max_hp)
		health.health_changed.emit(health.current_hp, health.max_hp)
	EventBus.pawn_leveled.emit(self, level)
	EventBus.floating_text.emit("升级！Lv.%d（+1 技能点）" % level, Color(1.0, 0.85, 0.3),
		global_position + Vector3(0.0, 2.3, 0.0))
	# v27：升级表现——金色冲击环上浮 + 金屑升腾（升级从此「看得见」）
	VFXManager.spawn_effect(&"levelup_ring", global_position + Vector3(0.0, 0.2, 0.0), 0.0,
		{"throttle_key": get_instance_id()})
	VFXManager.spawn_effect(&"levelup_spark", global_position + Vector3(0.0, 1.0, 0.0), 0.0,
		{"throttle_key": get_instance_id()})
	AudioManager.play_sfx(&"level_up", global_position)
	# 血怒中的战士：面板基线重挂（否则怒气结束会还原到升级前的攻击力）
	if skill_comp != null:
		skill_comp.notify_stats_rebased()


## 按当前等级从 def 基础值重算六维（出生 level=1 时即基础值本身）。
## 血量 / 攻击 / 移速写回既有组件字段；防御 / 暴击存本类变量供结算查询。
## v25：攻击与生命上限再乘技能树累计加成（无树 / 未加点 = 1×，不影响旧数值契约）。
func _apply_stats_for_level() -> void:
	if def == null:
		return
	var lv := float(level - 1)
	var tree_hp := 1.0 + skill_tree_hp_bonus()
	var tree_dmg := 1.0 + skill_tree_damage_bonus()
	if health != null:
		health.max_hp = def.max_hp * (1.0 + GROWTH_HP * lv) * tree_hp
	if attacker != null:
		attacker.damage = def.attack_damage * (1.0 + GROWTH_ATTACK * lv) * tree_dmg
	move_speed = def.move_speed * (1.0 + GROWTH_SPEED * lv)
	defense_stat = def.defense * (1.0 + GROWTH_DEFENSE * lv)
	crit_stat = clampf(def.crit_rate + GROWTH_CRIT * lv, 0.0, CRIT_CAP)


## 受击减伤乘数（HealthComponent.apply_damage 读取）：防御 0 = 1.0（不减伤）。
func defense_factor() -> float:
	return DEFENSE_K / (DEFENSE_K + maxf(defense_stat, 0.0))


## 当前暴击率（AttackerComponent 掷骰用；0 = 永不暴击）。
func crit_chance() -> float:
	return crit_stat


## 暴击伤害倍率（普攻/技能投射物统一读取 def.crit_multiplier）。
func crit_multiplier() -> float:
	return def.crit_multiplier if def != null else 2.0


## 是否参与等级成长（UI 据此决定是否显示经验行；主角走 Hero 专属面板）。
func can_level_up() -> bool:
	return def != null and def.can_level

# ---- v3：AI 行为扩展 ----
enum Stance { DEFENSIVE = 0, AGGRESSIVE = 1, HOLD = 2 }   # 士兵姿态（索敌视野 / 追击 leash）
const STANCE_NAMES := ["防御", "进攻", "驻守"]
var stance: int = Stance.DEFENSIVE     # 当前姿态（UI 可改；SoldierIdleState 读取）
var hold_anchor: Vector3 = Vector3.ZERO  # 驻守锚点（进入驻守姿态时的站位，离开 8m 即脱离追击）
var _sieging: bool = false             # 夜袭攻城：临时解除避城限制（FightState 进入/退出维护）
var alert_pos: Vector3 = Vector3.ZERO  # 威胁响应目标点（threat_alert 写入；idle 态消费）
var alert_active: bool = false

var _city: CitySystem                 # 懒加载缓存：城内回血 / 野怪避城查询（分组 "city_system"）
var _steer_separation: Vector3 = Vector3.ZERO   # 状态写入：move_along_path 前叠加的单位间分离力（软件避让，见 compute_separation）
var _nav_sys: NavSystem               # 懒加载缓存：NavSystem 引用（repath 高频调用，避免每次查分组）

# ---- v6 寻路/群体性能优化 ----
# 索敌缓存：移动 / 待机 / 徘徊状态每帧索敌，但敌人分布 0.2s 内基本不变；
# 实例级缓存把 N 个单位每秒的真实扫描从 60N 次降到 5N 次。
const AGGRO_CACHE_FRAMES := 12        # 索敌结果缓存帧数（0.2s @60fps）
var _avoided_hostile: WeakRef
var _hostile_retry_left: float = 0.0
var _aggro_cache: Node = null
var _aggro_cache_frame: int = -100
var _aggro_cache_range: float = -1.0
# 战斗站位：每目标弱引用槽位表，已有成员不因增减人数重新分槽。
# 位置缓存 0.2s；分配只扫描本目标的槽位，不遍历或排序全场单位。
const APPROACH_CACHE_FRAMES := 12
var _approach_target_id: int = 0
var _approach_cache_frame: int = -100
var _approach_cache_pos: Vector3 = Vector3.ZERO
var _approach_slot: int = -1
var _approach_slot_key: String = ""
static var _combat_slots: Dictionary = {} # team/target -> weak target + weak owners
static var _combat_slots_prune_frame: int = -600
# 单位空间索引（静态共享）：每物理帧惰性重建一次 O(N)，compute_separation 从
# 「遍历全组」降为「查 3×3 邻桶」；大群集结 / 攻城时总成本从 O(N²)/帧 降为 O(N)/帧。
const SPATIAL_CELL: float = 4.0       # 桶边长 4m ≥ 2× 最大分离半径，邻桶查询一次覆盖
static var _spatial_buckets: Dictionary = {}
static var _spatial_stamp: int = -1
# 交战计数缓存（静态共享）：combat_target 已被几名友军锁定。原来每次索敌对每个
# 候选敌都遍历全组（O(候选×N)）；现每物理帧统一统计一次，全 Pawn 共享 O(N)。
static var _engage_counts: Dictionary = {}
static var _engage_stamp: int = -1


func _ready() -> void:
	_setup_nodes()
	_apply_def()
	# 初始移动目标设为自身位置，避免朝原点跑
	move_target = global_position

	# 单位碰撞层：自身在 layer 5（unit，bit4 = 16）。注意 Godot 的 collision_layer 是位掩码：
	# layer N 的值 = 1<<(N-1)，故 layer 5 = 16（曾误写成 5 = layer1+layer3，导致单位被 NavMesh
	# 烘焙成障碍 + 单位互相碰撞卡死）。mask = world(1) | structure(8) = 9，碰世界/建筑/基地；
	# 不含 16 → 单位间互不物理碰撞（avoidance 二阶段再补体积感）。
	collision_layer = 16
	collision_mask = 1 | 8

	# 格子占用更新时，让当前状态 repath（建筑放置/摧毁后路径刷新）
	var ns := get_tree().get_first_node_in_group("nav_system") as NavSystem
	if ns != null:
		ns.navmesh_updated.connect(_on_navmesh_updated)

	# 分组与事件
	if team_comp.team == TeamComponent.Team.PLAYER:
		add_to_group("selectable")
		add_to_group("player_unit")
		is_auto_fighter = def.is_auto_fighter if def != null else true
		EventBus.pawn_spawned.emit(self)
	elif team_comp.team == TeamComponent.Team.ENEMY:
		add_to_group("enemy")
		is_auto_fighter = true
		EventBus.enemy_spawned.emit(self)

	health.died.connect(_on_died)
	# 受击反馈动画（插播 Hit_A / HitReact）：同一单位节流，避免群体围殴时动作抽搐
	health.damaged.connect(_on_damaged_hit_react)
	# v33 隐身「造成伤害即破隐」：常驻监听（未隐身时一次布尔判断即返回，成本可忽略；
	# 与 PawnSkillComponent 同款做法——避免在 damage_dealt 发射过程中增删连接）
	EventBus.damage_dealt.connect(_on_damage_dealt_stealth)


# ---- 节点构建 ----
func _setup_nodes() -> void:
	# Mesh
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.name = "MeshInstance3D"
	mesh.position.y = 0.8
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mesh.material_override = mat
	add_child(mesh)

	# Collision
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	col.shape = shape
	col.name = "CollisionShape3D"
	col.position.y = 0.8   # capsule 中心抬高，使底部对齐脚下（原点）
	add_child(col)

	# Health
	health = HealthComponent.new()
	health.name = "HealthComponent"
	add_child(health)

	# Team
	team_comp = TeamComponent.new()
	team_comp.name = "TeamComponent"
	add_child(team_comp)

	# Selectable（仅玩家阵营）
	if def == null or def.team == TeamComponent.Team.PLAYER:
		selectable = SelectableComponent.new()
		selectable.name = "SelectableComponent"
		var sel_col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.6
		cyl.height = 2.0
		# 圆柱上移至身体中段：Pawn 原点在脚底，不上移则形状半埋地下（只覆盖 y∈[-1,1]），
		# 点击单位上半身（视觉身体 y∈[0,1.8]）会落空。
		sel_col.position = Vector3(0.0, 1.0, 0.0)
		sel_col.shape = cyl
		selectable.add_child(sel_col)
		add_child(selectable)

	# Attacker
	attacker = AttackerComponent.new()
	attacker.name = "AttackerComponent"
	add_child(attacker)

	# 职业技能组件（v19）：仅 def.skill 非空的单位（四职业定居小兵）挂载
	if def != null and def.skill != null:
		skill_comp = PawnSkillComponent.new()
		skill_comp.name = "PawnSkillComponent"
		add_child(skill_comp)

	# SelectionRing
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.7
	ring_mesh.bottom_radius = 0.7
	ring_mesh.height = 0.05
	ring.mesh = ring_mesh
	ring.name = "SelectionRing"
	ring.position.y = 0.05
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color.YELLOW
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.visible = false
	add_child(ring)

	# AimRing：准星瞄准 / 集火目标的红色标记环（v10；与黄色选中环区分）
	var aim_ring := MeshInstance3D.new()
	var aim_mesh := CylinderMesh.new()
	aim_mesh.top_radius = 0.85
	aim_mesh.bottom_radius = 0.85
	aim_mesh.height = 0.04
	aim_ring.mesh = aim_mesh
	aim_ring.name = "AimRing"
	aim_ring.position.y = 0.04
	var aim_mat := StandardMaterial3D.new()
	aim_mat.albedo_color = Color(1.0, 0.22, 0.18, 0.42)
	aim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_ring.material_override = aim_mat
	aim_ring.visible = false
	add_child(aim_ring)

	# StateMachine（先加状态，再挂到树，保证 _ready 时状态就绪）
	state_machine = PawnStateMachine.new()
	state_machine.name = "StateMachine"
	_add_state("idle", IdleState.new())
	_add_state("move", MoveState.new())
	_add_state("harvest", HarvestState.new())
	_add_state("fight", FightState.new())
	_add_state("follow", FollowState.new())   # 主角小队跟随态（任意 Pawn 均可被编入小队）
	# v33 施法态（skills-dev 的 SkillCastState）：前摇 / 收招 / 跳劈滞空由它推进。
	# 初始注册在挂树前完成（_ready 自动登记），子类后续 register_state 不影响它。
	_add_state("skill_cast", SkillCastState.new())
	# v33 受控态（击飞 + 眩晕）：由 apply_knockup 进入，tick_control 推进
	_add_state("stunned", StunnedState.new())
	_add_state("dead", DeadState.new())
	add_child(state_machine)

	# NavigationAgent3D 仅保留扩展点；路径由 NavSystem 的格子 A* 负责。
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.4
	nav_agent.target_desired_distance = 0.5
	nav_agent.path_max_distance = 3.0
	nav_agent.radius = 0.4
	nav_agent.avoidance_enabled = false
	nav_agent.use_3d_avoidance = false
	add_child(nav_agent)

	# 骨骼模型挂载点（占位美术通道）；_apply_def 时按 def.model_path 加载模型
	model_rig = PawnModelRig.new()
	model_rig.name = "ModelRig"
	add_child(model_rig)

	# 头顶血条（Sprite3D billboard，监听 HealthComponent 自动更新；颜色由 _apply_def 注入）
	health_bar = HealthBar3D.new()
	health_bar.name = "HealthBar3D"
	add_child(health_bar)

	# 头顶人设气泡（v14）：随机低频冒出台词；无台词池的单位（主角/野怪）永不冒泡
	speech_bubble = SpeechBubble3D.new()
	speech_bubble.name = "SpeechBubble3D"
	add_child(speech_bubble)


func _add_state(state_name: String, state: PawnState) -> void:
	state.name = state_name
	state_machine.add_child(state)


func _apply_def() -> void:
	if def == null:
		return
	# v25 技能树：def 声明了树的单位在此创建运行时状态（转职换 def 不换树，仅创建一次）
	if def.skill_tree_id != &"" and skill_tree == null:
		skill_tree = PawnSkillTree.new()
		skill_tree.tree_def = GameDefs.skill_tree_def(def.skill_tree_id)
		skill_tree.apply_pre_unlocks()
	# v20 六维重算：血量/攻击/移速/防御/暴击统一从「def 基础值 × 等级成长」得出
	# （出生 level=1 = 基础值本身），升级时同一入口重算。
	_apply_stats_for_level()
	if health != null:
		health.current_hp = health.max_hp   # 出生满血（升级走 _level_up 只补差值）
	team_comp.team = def.team
	attacker.attack_range = def.attack_range
	attacker.attack_cooldown = def.attack_cooldown
	attacker.attack_kind = def.attack_kind
	attacker.projectile_speed = def.projectile_speed
	var mat := ($MeshInstance3D as MeshInstance3D).material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = def.mesh_color
	# 骨骼模型：有路径则加载并隐藏占位胶囊（加载失败保持胶囊，逻辑不受影响）
	# 配了 model_path_pool 的（如殖民者）：每个实例随机抽一个 → 外观多样化
	var model_path := def.model_path
	if def.model_path_pool.size() > 0:
		model_path = def.model_path_pool.pick_random()
	if model_path != "" and model_rig != null:
		# 武器挂点：只留 def 指定的那件武器，避免占位模型「手上叠一堆剑盾」（见 PawnDef 注释）
		if model_rig.setup(model_path, def.model_scale, def.model_face_offset_deg,
				def.model_weapon_main, def.model_weapon_offhand, def.anim_map, def.is_flying_unit):
			# 攻击动画播放速度（攻速匹配：动画时长 > 攻击间隔的兵种按倍速播）
			model_rig.attack_anim_speed = clampf(def.attack_anim_speed, 0.5, 2.5)
			var placeholder := get_node_or_null("MeshInstance3D") as MeshInstance3D
			if placeholder != null:
				placeholder.visible = false
			# 整体染色（精英怪 / 头目 / 兵种区分；白色不染）
			model_rig.apply_tint(def.model_tint)
	# 头顶血条按「角色 / 阵营」着色（此时 team 已由上方 team_comp.team = def.team 设定）
	if health_bar != null:
		health_bar.apply_color(is_hero_unit, team_comp.team)
	# 半径盒随体型同步放大（v32；def.body_scale=1.0 时整段空转，老单位零影响）
	_apply_body_scale()


# ---- 半径盒（碰撞 / 拾取 / 导航 / 选择环）体型同步 ----

## 当前体型倍率（def.body_scale；无 def 或非法值回落 1.0）。
func body_scale() -> float:
	if def != null and def.body_scale > 0.0:
		return def.body_scale
	return 1.0


## 按 def.body_scale 同步放大「半径盒」：碰撞胶囊 / 占位胶囊 / 拾取圆柱 / 导航半径
## / 选中·瞄准环。形状中心随高度同步抬高（胶囊底仍贴脚底），只改尺寸不改逻辑。
func _apply_body_scale() -> void:
	var s := body_scale()
	if is_equal_approx(s, 1.0):
		return
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is CapsuleShape3D:
		var cap := (col.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		cap.radius *= s
		cap.height *= s
		col.shape = cap
		col.position.y *= s
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh != null and mesh.mesh is CapsuleMesh:
		var cm := (mesh.mesh as CapsuleMesh).duplicate() as CapsuleMesh
		cm.radius *= s
		cm.height *= s
		mesh.mesh = cm
		mesh.position.y *= s
	if selectable != null:
		for c in selectable.get_children():
			var sc := c as CollisionShape3D
			if sc == null or not (sc.shape is CylinderShape3D):
				continue
			var cyl := (sc.shape as CylinderShape3D).duplicate() as CylinderShape3D
			cyl.radius *= s
			cyl.height *= s
			sc.shape = cyl
			sc.position.y *= s
	if nav_agent != null:
		nav_agent.radius *= s
	# 脚下的选中黄盘 / 集火红盘：半径同步（否则 2× 龙踩的还是人形小圈）
	for ring_name in ["SelectionRing", "AimRing"]:
		var ring := get_node_or_null(ring_name) as MeshInstance3D
		if ring != null and ring.mesh is CylinderMesh:
			var rm := (ring.mesh as CylinderMesh).duplicate() as CylinderMesh
			rm.top_radius *= s
			rm.bottom_radius *= s
			ring.mesh = rm


# ---- 外部接口 ----

## UI 显示名：个体名（村民姓名）优先，其次 def 名。
func get_display_name() -> String:
	if def != null and def.unit_name != "":
		return def.unit_name
	if def != null:
		return def.display_name
	return "单位"


## 姿态追击 leash（FightState / RangedFightState 每帧调用）：
## 返回 true = 该放弃当前目标了（超出姿态允许的追击范围）。
## 防御：目标离自己 34m 外不追（守城墙）; 进攻：无 leash。
## 驻守：目标跑出锚点 12m 守备圈、或自己被引离锚点 9m → 脱离。
func should_break_engagement(target_pos: Vector3) -> bool:
	if team_comp == null or team_comp.team != TeamComponent.Team.PLAYER:
		return false   # 敌方 / 中立不吃玩家姿态
	match stance:
		Stance.DEFENSIVE:
			return global_position.distance_to(target_pos) > 34.0
		Stance.HOLD:
			return global_position.distance_to(hold_anchor) > 9.0 \
				or hold_anchor.distance_to(target_pos) > 12.0
	return false


## 播放骨骼动画（按项目状态/动作 key，见 PawnModelRig.ANIM_CANDIDATES）。无模型时静默跳过。
## speed：循环动画的播放倍率（v29 巨龙追赶 1.6× 时行走动作同倍速快放，不滑步）；默认 1.0。
func play_anim(key: StringName, blend: float = 0.12, speed: float = 1.0) -> void:
	if model_rig != null:
		model_rig.play(key, blend, speed)


## 受击反馈：插播受击动画（Hit_A / HitReact）。只在死亡外、节流窗口外、
## 且当前播的是循环动画（待机 / 移动）时触发——不打断攻击 / 施法 / 死亡动作。
func _on_damaged_hit_react(_amount: float, _source: Node) -> void:
	if is_dead_flag or _hit_react_left > 0.0:
		return
	if model_rig == null or not model_rig.has_anim(&"hit"):
		return
	if not model_rig.is_playing_loop():
		return
	_hit_react_left = HIT_REACT_THROTTLE
	model_rig.play(&"hit", 0.1)


func set_destination(pos: Vector3) -> void:
	move_target = pos
	if state_machine != null:
		state_machine.transition_to("move")


# ---- 单位间分离（software separation）----
# 单位互不物理碰撞（layer 5 mask 不含 16，见 _setup_nodes）：靠软件分离力避免堆叠。
# 需要避让的移动状态在调用 move_along_path 前写入 _steer_separation，move_along_path
# 内部经 _slide_with_separation 叠加到 velocity 并消费；不写则零（不影响其它状态）。

## 计算与同组 nearby 单位的分离合力（XZ 平面）：越近推力越大，半径外为 0。返回值近似方向×强度。
## v6：经静态空间桶索引查邻域（每帧惰性重建 O(N)），不再遍历全组——
## 大群单位移动时分离力总成本从 O(N²)/帧 降为 O(N)/帧。
func compute_separation(group: String, radius: float) -> Vector3:
	_ensure_spatial_index()
	if _spatial_buckets.is_empty():
		# 索引不可用（无场景树等）：退回全组遍历，保证行为正确
		return _compute_separation_bruteforce(group, radius)
	var steer := Vector3.ZERO
	var base := Vector2i(floori(global_position.x / SPATIAL_CELL), floori(global_position.z / SPATIAL_CELL))
	var span := ceili(radius / SPATIAL_CELL)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := base + Vector2i(dx, dz)
			if not _spatial_buckets.has(key):
				continue
			var bucket: Array = _spatial_buckets[key]
			for other in bucket:
				if not is_instance_valid(other) or other == self or not (other is Node3D) or not other.is_in_group(group):
					continue
				var d: Vector3 = global_position - (other as Node3D).global_position
				d.y = 0.0
				var dd: float = d.length()
				if dd > 0.0001 and dd < radius:
					steer += (d / dd) * ((radius - dd) / radius)   # 线性衰减：贴脸≈1，到边≈0
	return steer


## 日常社交复用空间桶，附近没人时不遍历全场小兵。
func nearby_group_members(group: String, radius: float) -> Array[Pawn]:
	_ensure_spatial_index()
	var result: Array[Pawn] = []
	var base := Vector2i(floori(global_position.x / SPATIAL_CELL), floori(global_position.z / SPATIAL_CELL))
	var span := ceili(radius / SPATIAL_CELL)
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for other in _spatial_buckets.get(base + Vector2i(dx, dz), []):
				if is_instance_valid(other) and other != self and other is Pawn and other.is_in_group(group) \
						and global_position.distance_squared_to(other.global_position) <= radius * radius:
					result.append(other as Pawn)
	return result


func _compute_separation_bruteforce(group: String, radius: float) -> Vector3:
	var steer := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(group):
		if other == self or not is_instance_valid(other) or not (other is Node3D):
			continue
		var d: Vector3 = global_position - (other as Node3D).global_position
		d.y = 0.0
		var dd: float = d.length()
		if dd > 0.0001 and dd < radius:
			steer += (d / dd) * ((radius - dd) / radius)
	return steer


## 每物理帧惰性重建一次单位空间桶（首个查询者触发）。死亡单位不入桶。
static func _ensure_spatial_index() -> void:
	var frame := Engine.get_physics_frames()
	if _spatial_stamp == frame:
		return
	_spatial_stamp = frame
	_spatial_buckets.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for group in ["player_unit", "enemy"]:
		for u in tree.get_nodes_in_group(group):
			if u is Pawn and is_instance_valid(u) and not (u as Pawn).is_dead_flag:
				var p: Vector3 = (u as Pawn).global_position
				var key := Vector2i(floori(p.x / SPATIAL_CELL), floori(p.z / SPATIAL_CELL))
				if not _spatial_buckets.has(key):
					_spatial_buckets[key] = []
				(_spatial_buckets[key] as Array).append(u)


## 当前有效移动速度 = move_speed × speed_multiplier × 减速乘数（默认均 1.0，即原速）。
## 寻路 / 直线推进都走这里：集结追赶期的 2× 与暴风雪的减速都不会漏掉任何一个分支。
func effective_move_speed() -> float:
	return move_speed * speed_multiplier * _slow_factor * road_speed_multiplier()


## 只有流民与友方小兵享受道路；不改写成长、集结或减速基值，离路立刻恢复。
func prefers_roads() -> bool:
	return (self is Soldier or self is Refugee) and team_comp != null and team_comp.team == TeamComponent.Team.PLAYER


func road_speed_multiplier() -> float:
	if not prefers_roads() or not is_inside_tree():
		return 1.0
	var nav := _get_nav_system()
	if nav != null and nav.grid != null and nav.grid.has_road(nav.grid.world_to_grid(global_position)):
		return GameDefs.ROAD_SPEED_MULTIPLIER
	return 1.0


## 叠加分离力后执行 move_and_slide（并消费 _steer_separation），同时限速避免寻路+分离叠加超速。
func _slide_with_separation() -> void:
	velocity += _steer_separation
	_steer_separation = Vector3.ZERO
	var max_spd := effective_move_speed() * 1.3
	if velocity.length_squared() > max_spd * max_spd:
		velocity = velocity.normalized() * max_spd
	move_and_slide()


## 持久战斗站位：固定六角相位、外圈微量错位但仍在射程内。
## 同伴离场只释放自己的槽位，已有单位不重新旋转列阵。结果缓存 0.2s。
func get_combat_approach_position(target: Node3D) -> Vector3:
	if target == null or attacker == null:
		return global_position
	var frame := Engine.get_physics_frames()
	var tid := target.get_instance_id()
	if _approach_target_id == tid and frame - _approach_cache_frame <= APPROACH_CACHE_FRAMES:
		return _approach_cache_pos
	# Assign a persistent weakly-owned slot. Peer arrivals/deaths leave existing
	# slots unchanged; no per-pawn full-group sort and no rotating formations.
	if frame - _combat_slots_prune_frame >= 600:
		_combat_slots_prune_frame = frame
		for old_key in _combat_slots.keys():
			if _combat_slots[old_key]["target"].get_ref() == null:
				_combat_slots.erase(old_key)
	var key := str(team_comp.team) + ":" + str(tid)
	if not _combat_slots.has(key):
		_combat_slots[key] = {"target": weakref(target), "owners": {}}
	var owners: Dictionary = _combat_slots[key]["owners"]
	if _approach_slot_key != key or _approach_slot < 0 or not owners.has(_approach_slot) or owners[_approach_slot].get_ref() != self:
		_approach_slot_key = key
		_approach_slot = 0
		while owners.has(_approach_slot):
			var occupant = owners[_approach_slot].get_ref()
			if occupant == null or occupant.is_dead_flag or occupant.combat_target != target:
				break
			_approach_slot += 1
		owners[_approach_slot] = weakref(self)
	const SLOTS_PER_RING := 6
	var ring: int = _approach_slot / SLOTS_PER_RING
	var phase := fmod(float(tid) * 0.6180339887, 1.0) * TAU
	var angle := phase + TAU * float(_approach_slot % SLOTS_PER_RING) / float(SLOTS_PER_RING) + float(ring) * 0.47
	# Extra rings must remain inside attack range, otherwise the pawn reaches
	# its slot, cannot attack, then endlessly runs in place.
	var radius := attacker.preferred_standoff_distance(target) + minf(float(ring) * 0.12, attacker.attack_range * 0.1)
	var pos: Vector3 = target.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	_approach_target_id = tid
	_approach_cache_frame = frame
	_approach_cache_pos = pos
	return pos


# ---- 导航接口（供状态机调用）----
func set_navigation_target(pos: Vector3, force_repath: bool = false) -> void:
	if not force_repath and _nav_target.distance_squared_to(pos) <= 0.0025:
		return
	var goal_change := _nav_target.distance_squared_to(pos)
	if navigation_status == NavigationStatus.BLOCKED and goal_change < 1.0 and not force_repath:
		# Small combat-slot jitter is still the same failed order.
		return
	var new_goal := goal_change > 16.0 or navigation_status == NavigationStatus.ARRIVED or (force_repath and navigation_status == NavigationStatus.BLOCKED)
	_nav_target = pos
	_nav_dirty = true
	if force_repath:
		_nav_repath_left = 0.0
	if new_goal:
		_reset_stuck_tracking()
	# Small moving-target updates must not continually reset stall detection.
	if navigation_status != NavigationStatus.UNREACHABLE:
		navigation_status = NavigationStatus.MOVING


func is_navigation_done() -> bool:
	return navigation_status == NavigationStatus.ARRIVED and not _nav_dirty


## Navigate with bounded steering and a delta-aware braking distance. One step
## cannot overshoot a waypoint at 3x simulation / rally / upgraded move speed.
func move_along_path(delta: float) -> bool:
	_nav_repath_left = maxf(0.0, _nav_repath_left - delta)
	if _nav_dirty and _nav_repath_left <= 0.0:
		_nav_dirty = false
		_recompute_path()
	if navigation_status == NavigationStatus.BLOCKED:
		_stop_navigation_motion()
		return false
	if _nav_path.is_empty():
		_stop_navigation_motion()
		navigation_status = NavigationStatus.UNREACHABLE
		# Stay still on disconnected terrain. Rate-limited retries allow dynamic
		# obstacles to recover without N pawns issuing A* every frame.
		_nav_dirty = true
		return false
	if _nav_idx >= _nav_path.size():
		_stop_navigation_motion()
		return navigation_status == NavigationStatus.ARRIVED
	var next := _nav_path[_nav_idx]
	var dir := next - global_position
	dir.y = 0.0
	while dir.length_squared() < 0.09 and _nav_idx < _nav_path.size() - 1:
		_nav_idx += 1
		next = _nav_path[_nav_idx]
		dir = next - global_position
		dir.y = 0.0
		_stuck_last_remaining = INF
	if _nav_idx == _nav_path.size() - 1 and dir.length_squared() < 0.25:
		_nav_idx = _nav_path.size()
		navigation_status = NavigationStatus.ARRIVED
		_stop_navigation_motion()
		_reset_stuck_tracking()
		return true
	var dist := dir.length()
	if dist < 0.0001:
		_stop_navigation_motion()
		return false
	var forward := dir / dist
	var speed := minf(effective_move_speed(), dist / maxf(delta, 0.000001))
	# Crowd avoidance is lateral-biased and bounded; it cannot overpower the
	# seek force and create a stationary equilibrium or backwards oscillation.
	var sep := _steer_separation.limit_length(speed * 0.35 * minf(dist / 1.5, 1.0))
	var along := sep.dot(forward)
	sep -= forward * along
	sep += forward * clampf(along, -speed * 0.15, 0.0)
	_steer_separation = Vector3.ZERO
	velocity = forward * speed + sep
	look_at_target(forward)
	_slide_with_separation()
	_update_stuck_recovery(delta)
	return false


func _stop_navigation_motion() -> void:
	velocity = Vector3.ZERO
	_steer_separation = Vector3.ZERO
	move_and_slide()


func _reset_stuck_tracking() -> void:
	_stuck_sample_t = 0.0
	_stuck_sample_pos = global_position
	_stuck_hits = 0
	_stuck_snapped = false
	_stuck_last_remaining = INF
	_stuck_sample_waypoint = Vector3.INF


## Sample BOTH displacement and distance-to-waypoint progress. Sliding back
## and forth along a wall no longer counts as successful movement. Do not skip
## obstacle-routing waypoints: skipping may drive straight across the wall.
func _update_stuck_recovery(delta: float) -> void:
	_stuck_sample_t += delta
	if _stuck_sample_t < STUCK_SAMPLE_SEC:
		return
	_stuck_sample_t = 0.0
	var moved := Vector2(global_position.x - _stuck_sample_pos.x, global_position.z - _stuck_sample_pos.z).length()
	_stuck_sample_pos = global_position
	var point := _nav_path[_nav_idx]
	var remaining := Vector2(point.x - global_position.x, point.z - global_position.z).length()
	var closing := _stuck_last_remaining - remaining
	if point.distance_squared_to(_stuck_sample_waypoint) > 1.0:
		closing = INF # genuinely different route segment
	_stuck_sample_waypoint = point
	_stuck_last_remaining = remaining
	# Severe slows legitimately move less than 0.25m per sample.
	var threshold := minf(STUCK_MIN_MOVE, effective_move_speed() * STUCK_SAMPLE_SEC * 0.2)
	if moved >= threshold and closing >= threshold * 0.5:
		_stuck_hits = 0
		_stuck_snapped = false
		return
	_stuck_hits += 1
	if _stuck_hits < STUCK_MAX_HITS:
		return
	_stuck_hits = 0
	stat_stuck_recoveries += 1
	if not _stuck_snapped:
		_stuck_snapped = true
		_nav_dirty = true
		_nav_repath_left = 0.0
		return
	navigation_status = NavigationStatus.BLOCKED
	_nav_dirty = false # discard a queued update to the same failed route
	_stop_navigation_motion()


func _recompute_path() -> void:
	stat_repaths += 1
	var ns := _get_nav_system()
	_nav_path = ns.get_world_path(global_position, _nav_target, prefers_roads()) if ns != null else PackedVector3Array([_nav_target])
	_nav_idx = 0
	navigation_status = NavigationStatus.MOVING if not _nav_path.is_empty() else NavigationStatus.UNREACHABLE
	_nav_repath_left = NAV_REPATH_INTERVAL if not _nav_path.is_empty() else NAV_FAILED_RETRY_INTERVAL


func _get_nav_system() -> NavSystem:
	if _nav_sys == null or not is_instance_valid(_nav_sys):
		_nav_sys = get_tree().get_first_node_in_group("nav_system") as NavSystem
	return _nav_sys


func _on_navmesh_updated() -> void:
	if not is_inside_tree():
		return   # 场景退出过程中拆路也会更新导航，不访问已离树单位的世界变换
	_hostile_retry_left = 0.0
	_aggro_cache_frame = -100
	_nav_dirty = true
	_nav_repath_left = 0.0 # occupancy changes invalidate unsafe paths immediately
	navigation_status = NavigationStatus.MOVING
	_reset_stuck_tracking()
	if state_machine != null and state_machine.current_state != null:
		if state_machine.current_state.has_method("_on_navmesh_updated"):
			state_machine.current_state._on_navmesh_updated()


func assign_work(target: Node) -> void:
	if state_machine != null:
		state_machine.transition_to("harvest", {"target": target})


func assign_attack(target: Node) -> void:
	if state_machine != null:
		state_machine.transition_to("fight", {"target": target})


func take_damage(amount: float, source: Node = null) -> void:
	health.apply_damage(amount, source)


func set_selected(sel: bool) -> void:
	is_selected = sel
	var ring := get_node_or_null("SelectionRing")
	if ring != null:
		ring.visible = sel


# ---- 瞄准 / 集火高亮（v10：红色描边 + 脚下红环）----
# HeroController 在准星对准怪物或下令集火时调用；描边走 PawnModelRig 的反转外壳，
# 无骨骼模型（胶囊占位）时复制占位胶囊兜底。
var _aim_outline: MeshInstance3D = null


func set_aim_highlight(on: bool) -> void:
	if health_bar != null:
		health_bar.set_emphasized(on)
	var ring := get_node_or_null("AimRing")
	if ring != null:
		ring.visible = on
	if model_rig != null and model_rig.has_model():
		model_rig.set_outline(on)
		return
	# 无骨骼模型：给占位胶囊加一层放大描边壳
	if on and _aim_outline == null:
		var src := get_node_or_null("MeshInstance3D") as MeshInstance3D
		if src != null and src.mesh != null:
			_aim_outline = MeshInstance3D.new()
			_aim_outline.name = "AimOutline"
			_aim_outline.mesh = src.mesh
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.22, 0.18, 0.95)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_FRONT
			mat.grow = true
			mat.grow_amount = 0.05
			_aim_outline.material_override = mat
			_aim_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_aim_outline.visible = false
			src.get_parent().add_child(_aim_outline)
			_aim_outline.position = src.position
	if _aim_outline != null:
		_aim_outline.visible = on


# ---- v18：小队常驻标识（绿色包边 + 脚下小绿圈）----
# 入队（Hero.recruit_squad）开、出队 / 阵亡（_release_member 等清理口）关，
# 常驻表达「这是我一个队伍的小兵」。描边走 PawnModelRig 的反转外壳管线
# （与瞄准 / 集火红描边同一套，只是常驻绿色；玩家单位不会被 set_aim_highlight
# 红描边，二者不会互相争抢）。脚下小绿圈为 TorusMesh 环带，与黄色选中盘 /
# 红色集火盘区分。无骨骼模型（占位胶囊）时只有绿圈，描边跳过。
const SQUAD_MARK_GREEN := Color(0.35, 1.0, 0.45)   # 与主角血条同款「队伍绿」
const SQUAD_RING_OUTER := 0.42                      # 默认脚圈外半径（人形）；大体型走 def.squad_ring_radius
var _squad_ring: MeshInstance3D = null


func set_squad_mark(on: bool) -> void:
	if on and _squad_ring == null:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		# v29：圈半径按体型（def.squad_ring_radius）——巨龙等大体型单位沿用 0.42 的圈会被
		# 身体整个盖住，队伍标等于不存在。
		var outer: float = SQUAD_RING_OUTER
		if def != null and def.squad_ring_radius > 0.0:
			outer = def.squad_ring_radius
		torus.inner_radius = outer * 0.81
		torus.outer_radius = outer
		ring.mesh = torus
		ring.name = "SquadRing"
		ring.position = Vector3(0.0, 0.045, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(SQUAD_MARK_GREEN.r, SQUAD_MARK_GREEN.g, SQUAD_MARK_GREEN.b, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		_squad_ring = ring
	if _squad_ring != null:
		_squad_ring.visible = on
	if model_rig != null and model_rig.has_model():
		model_rig.set_outline(on, SQUAD_MARK_GREEN)


func set_dead(d: bool) -> void:
	is_dead_flag = d


func look_at_target(dir: Vector3) -> void:
	if dir.length_squared() > 0.001:
		# atan2(-x,-z) 让 -Z 轴（Godot 的前方约定 forward）指向 dir。若用 atan2(x,z) 会让 +Z 指向 dir，
		# 导致 facing(-basis.z) = -dir，单位背对目标 —— 主角普攻扇形、小队「身后」槽位都会朝反方向。
		rotation.y = atan2(-dir.x, -dir.z)


# ---- 主城 / 城内回血 ----

## 懒加载主城系统引用（分组 "city_system"）。
func _get_city() -> CitySystem:
	if _city == null:
		_city = get_tree().get_first_node_in_group("city_system") as CitySystem
	return _city


## 城内持续回血（士兵「城内生活」）。仅在主城内、且 def 配置了 regen_per_sec 时生效；
## 城外不回血。供士兵的城内状态（idle/rest/wander）每帧调用。
func _try_city_regen(delta: float) -> void:
	if is_dead_flag or health == null or def == null or def.regen_per_sec <= 0.0:
		return
	var city := _get_city()
	if city != null and city.is_in_city(global_position):
		health.heal(def.regen_per_sec * delta)


## v34 回城疗伤（主角 / 巨龙专用）：白天回到城镇范围内缓慢回血（def.regen_per_sec），
## **晚上守城时不回**——入夜（20:00~06:00，含守城准备期与夜潮攻城）一律停血，
## 防止守城战里靠城内站位白嫖回复。由 Hero / DragonPet 的 _process 每帧驱动。
## 与士兵的 _try_city_regen 分立：士兵的城内休整回血不受夜晚门控（夜间本就回城过夜）。
func _try_town_regen(delta: float) -> void:
	if is_dead_flag or health == null or def == null or def.regen_per_sec <= 0.0:
		return
	if delta <= 0.0 or health.current_hp >= health.max_hp:
		return   # 暂停（time_scale=0）/ 满血：不回也不刷 health_changed 信号
	if TimeManager.is_night():
		return
	var city := _get_city()
	if city != null and city.is_in_city(global_position):
		health.heal(def.regen_per_sec * delta)


# ---- 索敌 ----
## 索敌入口（带 0.2s 实例缓存）。移动 / 待机 / 徘徊状态每帧调用索敌，
## 但敌人分布短时间基本不变；缓存让 N 个单位每秒的真实扫描从 60N 次降到 5N 次。
## 缓存的目标已失效（死亡释放）时自动视为未命中并重算。
func find_nearest_hostile(max_range: float = 40.0) -> Node:
	var frame := Engine.get_physics_frames()
	if _aggro_cache_range == max_range and frame - _aggro_cache_frame <= AGGRO_CACHE_FRAMES:
		if _aggro_cache == null:
			return null
		if _valid_hostile_candidate(_aggro_cache, max_range * max_range, _get_city() if avoids_city else null):
			return _aggro_cache
	var found := _find_nearest_in_group_cached(max_range)
	_aggro_cache = found
	_aggro_cache_frame = frame
	_aggro_cache_range = max_range
	return found


## Failed automatic engagements briefly yield to other targets. Explicit focus
## orders bypass this scan, and obstacle changes permit an immediate retry.
func avoid_hostile_temporarily(target: Node, duration: float = 3.0) -> void:
	_avoided_hostile = weakref(target)
	_hostile_retry_left = duration
	_aggro_cache_frame = -100


func _find_nearest_in_group_cached(max_range: float) -> Node:
	if team_comp.team == TeamComponent.Team.PLAYER:
		return _find_nearest_in_group("enemy", max_range)
	else:
		return _find_nearest_in_group("player_unit", max_range)


func _find_nearest_in_group(group: String, max_range: float, ignore_city: bool = false) -> Node:
	var best: Node = null
	var best_score: float = INF
	var city := _get_city() if avoids_city and not ignore_city else null   # 野怪：跳过城内目标（不追进城）
	var max_range_sq := max_range * max_range
	for e in get_tree().get_nodes_in_group(group):
		if _valid_hostile_candidate(e, max_range_sq, city):
			var en: Node3D = e
			var dist_sq: float = global_position.distance_squared_to(en.global_position)
			var dist: float = sqrt(dist_sq)
			# 每个已交战友军增加等效 7m 路程：近敌仍有优势，但有多个目标时会自然分兵。
			var score := dist + float(_hostile_engagement_count(e)) * 7.0
			if score < best_score:
				best_score = score
				best = e
	return best


## Cached hits must satisfy the same rules as a fresh scan. This is O(1),
## retaining the scan throttle while reacting to border crossings and deaths.
func _valid_hostile_candidate(e: Node, range_sq: float, city: CitySystem = null) -> bool:
	if not is_instance_valid(e) or not e is Node3D:
		return false
	if _hostile_retry_left > 0.0 and _avoided_hostile != null and _avoided_hostile.get_ref() == e:
		return false
	if e is Pawn:
		# v33：隐身 / 不可锁定单位看不到（缓存命中时同一判定，隐身即刻失效）
		if e.is_dead_flag or (team_comp.team == TeamComponent.Team.ENEMY and not e.can_be_seen_by_enemies()):
			return false
	var pos: Vector3 = (e as Node3D).global_position
	return global_position.distance_squared_to(pos) <= range_sq and (city == null or not city.is_in_city(pos))


## 目标「已被几名友军锁定」（索敌分摊用）。v6：每物理帧统一统计一次全图
## combat_target 计数（静态缓存全 Pawn 共享），替代原先「每候选遍历全组」的嵌套开销。
func _hostile_engagement_count(hostile: Node) -> int:
	var frame := Engine.get_physics_frames()
	if _engage_stamp != frame:
		_engage_stamp = frame
		_engage_counts.clear()
		var tree := get_tree()
		if tree != null:
			for group in ["player_unit", "enemy"]:
				for unit in tree.get_nodes_in_group(group):
					if unit is Pawn:
						var ct = (unit as Pawn).combat_target
						if ct != null and is_instance_valid(ct):
							var id := ct.get_instance_id()
							_engage_counts[id] = _engage_counts.get(id, 0) + 1
	return _engage_counts.get(hostile.get_instance_id(), 0)


func _on_died() -> void:
	if is_dead_flag:
		return
	# v33：死亡清掉施法锁 / 控制 / 隐身（隐身拖尾与模型材质随之释放）
	skill_locked = false
	_control_air_left = 0.0
	_control_stun_left = 0.0
	break_stealth()
	if team_comp.team == TeamComponent.Team.PLAYER:
		EventBus.pawn_died.emit(self)
		if not is_hero_unit:
			AudioManager.play_sfx(&"die_unit", global_position)
	else:
		# 击杀归属：最后攻击者（主角经验 / 战报统计用）
		EventBus.enemy_died.emit(self, health.last_attacker if health != null else null)
	if state_machine != null:
		state_machine.transition_to("dead")
