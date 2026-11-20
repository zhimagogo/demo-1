class_name Hero
extends Pawn
## ============================================================================
## 主角（战士职业）。继承 Pawn 的全部骨架（选中 / 队伍 / 寻路 / 自动战斗），
## 在此之上叠加：连招 / 技能、动作·特效·音效接口、小队、死亡复活。
## - 俯视角主控（TOPDOWN，v42 默认且玩家唯一可用）：WASD 按屏幕方向、鼠标落点瞄准
## - 第三人称亲征（HERO，v42 起玩家入口屏蔽，脚本接口保留）：WASD 相对相机移动、左键连招
## - 战术俯瞰 RTS（TACTICAL，v42 起玩家入口屏蔽）：可选中、右键下令；【不自动索敌】等玩家下令
## 职业扩展：新增 GameDefs.hero_<class>_def() + 一组 SkillDef 即可，无需改本类。
## ============================================================================

var hero_def: HeroDef
var animator: HeroAnimator

# 主角操控输入（由 HeroController 每帧写入，hero_idle 读取）
var desired_velocity: Vector3 = Vector3.ZERO
var aim_dir: Vector3 = Vector3.FORWARD
var _jump_pending: bool = false       # 跳跃请求（HeroController 置位，HeroIdleState 消费）

# ---- v26 驯龙：宠物龙的攻击目标来源（「玩家打谁他打谁」）----
# 主角每次亲手造成伤害（连招 / 技能 / RTS 下令普攻）都会刷新 attack_target，
# ATTACK_TARGET_TTL 秒内不再打它则目标过期；集火令（T）始终优先于本记录。
var attack_target: Node = null
var _attack_target_left: float = 0.0
const ATTACK_TARGET_TTL: float = 2.5


## 记录「主角正在打谁」（宠物龙据此同步攻击目标；无效目标忽略）。
func note_attack_target(t: Node) -> void:
	if t == null or not is_instance_valid(t):
		return
	var p := t as Pawn
	if p != null and p.is_dead_flag:
		return
	attack_target = t
	_attack_target_left = ATTACK_TARGET_TTL


## 宠物龙本帧应当攻击的目标：集火令（活着的）优先，其次保鲜期内的最近攻击目标。
## 返回 null = 主角当前没在打谁（龙只跟随不接战——宠物定位，绝不自主索敌）。
func live_pet_target() -> Node:
	if is_focus_alive():
		return focus_target
	if attack_target != null and is_instance_valid(attack_target) and _attack_target_left > 0.0:
		var p := attack_target as Pawn
		if p == null or not p.is_dead_flag:
			return attack_target
	return null


## 覆写自动索敌开关：战术俯瞰 RTS 下主角待命，不主动接敌——完全听玩家下令
## （右键指派攻击 / 切回主控亲自打）。亲征与俯视角主控下 hero_idle 本就不自动接战，
## 此覆写只拦 RTS 下 idle / move 状态的自动索敌分支。
func autofight_enabled() -> bool:
	if SelectionManager.view_mode == SelectionManager.ViewMode.TACTICAL:
		return false
	return is_auto_fighter


## 请求起跳（HeroController 在按下跳跃键时调用；由 HeroIdleState 在落地状态下消费）。
func request_jump() -> void:
	_jump_pending = true


## 消费跳跃请求（一次性）。返回 true 表示本次物理帧应当起跳。
func consume_jump() -> bool:
	var j := _jump_pending
	_jump_pending = false
	return j

# 连招
var _combo_step: int = 0                 # 0=未在连招；下一击起手为第 1 段
var _combo_window_left: float = 0.0
var _pending_combo: bool = false         # 连招中再次按攻击的输入缓冲

# 技能冷却（与 hero_def.skills 一一对应，存「剩余秒数」）
var _skill_cd: Array[float] = []

# 小队
var squad: Array = []                    # Array[Pawn]（跟随中的编队成员，上限 SQUAD_MAX）
# ---- v10：编队 / 集火 ----
const SQUAD_MAX: int = 4                 # 编队（小队）上限：4 名小兵 + 主角 = 5 人
var party: Array = []                    # 编队成员（Array[Soldier]；城镇可有很多小兵，但只能带 4 个）
var focus_target: Node = null            # 集火目标（按 T 下令：小队优先攻击它，直到它死亡才恢复自主 AI）

# ---- v3：击杀经验 / 等级成长 ----
# level / xp / gain_xp 已上移到 Pawn 基类（v20 小兵属性系统共用同一条成长管线），
# 主角只覆写曲线（xp_to_next）与升级结算（_level_up：+30 血 / 回满 / damage_mult / 称号）。
var kill_count: int = 0
# 等级称号：1 新兵 → 10 战神
const LEVEL_TITLES := ["新兵", "勇士", "百夫长", "精锐", "锋刃", "锐卫", "统领", "悍将", "传奇", "战神"]


## 升级所需经验：60 / 100 / 140 …（每级 +40；与小兵曲线 40/65/… 各走各的）。
func xp_to_next() -> int:
	return 60 + 40 * (level - 1)


## 主角不封顶：称号表到 10 级后保持「战神」，但等级与伤害继续成长。
func _level_cap() -> int:
	return 99999


## 当前称号（等级封顶 LEVEL_TITLES.size()）。
func hero_title() -> String:
	return LEVEL_TITLES[clampi(level, 1, LEVEL_TITLES.size()) - 1]


## 等级伤害倍率（连招与普攻伤害按此放大；每级 +12%）。
## v25：技能树「伤害强化」的累计加成并入本乘区（加点即时生效于攻击面板）。
func damage_mult() -> float:
	return 1.0 + 0.12 * float(level - 1) + skill_tree_damage_bonus()


## 主角升级后的生命上限公式：基础 320 + 30×(level-1)，再乘技能树「生命强化」加成。
## （树未加点时与旧「逐级 +30」完全等价；抽出公式供升级与加点两条路径共用。）
func _max_hp_formula() -> float:
	if hero_def == null:
		return health.max_hp if health != null else 320.0
	return (hero_def.max_hp + 30.0 * float(level - 1)) * (1.0 + skill_tree_hp_bonus())


## v25 技能树加点后的主角面板重算：覆盖士兵线的六维公式——
## 生命上限走 _max_hp_formula（血量差补入当前血），攻击走 damage_mult。
func _rebase_stats_for_tree() -> void:
	var old_max: float = health.max_hp if health != null else 0.0
	if health != null:
		health.max_hp = _max_hp_formula()
		var delta: float = health.max_hp - old_max
		if delta > 0.0:
			health.current_hp = clampf(health.current_hp + delta, health.current_hp, health.max_hp)
		health.health_changed.emit(health.current_hp, health.max_hp)
	if attacker != null and hero_def != null:
		attacker.damage = hero_def.attack_damage * damage_mult()


func _ready() -> void:
	if def == null:
		def = GameDefs.hero_warrior_def()
	is_hero_unit = true   # 标记主角：头顶血条用主角色（避免基类 is Hero 的循环依赖）
	super._ready()
	hero_def = def as HeroDef
	# 动画器接线（super._ready 已建好 Mesh、材质与 model_rig 骨骼挂载）
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if animator != null:
		animator.setup(mesh, model_rig)
	# HP 变化转发到 EventBus（供 HeroPanel）
	if health != null:
		health.health_changed.connect(func(c: float, m: float) -> void:
			EventBus.hero_hp_changed.emit(self, c, m))
	# 初始化技能冷却
	if hero_def != null:
		_skill_cd.resize(hero_def.skills.size())
		for i in _skill_cd.size():
			_skill_cd[i] = 0.0
	# 击杀经验：enemy_died 的 killer 归属由 HealthComponent.last_attacker 提供
	EventBus.enemy_died.connect(_on_enemy_killed)
	# 编队自动补位：新士兵出生（定居 / 兵营募兵）时编队未满则自动入队
	EventBus.pawn_spawned.connect(_on_pawn_spawned_for_party)
	EventBus.pawn_died.connect(_on_pawn_died_for_party)
	EventBus.hero_spawned.emit(self)


## 击杀结算：经验入账 + 升级判定；集火目标阵亡时自动解除集火令。
func _on_enemy_killed(enemy: Node, killer: Node) -> void:
	if focus_target == enemy:
		order_focus_fire(null)
		EventBus.game_message.emit("集火目标已被消灭，小队恢复自主作战", Color(0.7, 0.9, 0.7))
	if killer == null or not is_instance_valid(killer) or is_dead_flag:
		return
	# 归属链：直接击杀者，或击杀者是我小队成员（战功共享一半）
	var is_mine: bool = killer == self
	if not is_mine and killer is Pawn and (killer as Pawn).follow_leader == self:
		is_mine = true
	if not is_mine or enemy == null or not is_instance_valid(enemy):
		return
	kill_count += 1
	var xp_gain: int = 1
	if enemy.get("def") != null and enemy.def.xp_value > 0:
		xp_gain = enemy.def.xp_value
	if killer != self:
		# v34 小队经验共享：主角也是小队一员——队友 / 编外巨龙击杀时按同口径分 50%
		# （GameDefs.SQUAD_XP_SHARE_RATIO；与 Soldier 的共享分账同源）。
		xp_gain = GameDefs.squad_share_xp(xp_gain)
	gain_xp(xp_gain)


## 主角升级结算：+30 上限 / 回满血 / 攻击面板上升（damage_mult）+ 1 技能点。
## 不调 super（小兵的百分比六维成长线与此互斥，主角走自己的固定成长）。
func _level_up() -> void:
	level += 1
	skill_points += 1   # v25：每次升级 +1 技能点
	# 成长结算：+30 上限 / 回满血 / 攻击面板上升（damage_mult）
	if health != null:
		health.max_hp = _max_hp_formula()
		health.heal(health.max_hp)
		health.health_changed.emit(health.current_hp, health.max_hp)
	attacker.damage = hero_def.attack_damage * damage_mult()
	EventBus.hero_leveled.emit(self, level)
	EventBus.floating_text.emit("升级！Lv.%d %s（+1 技能点）" % [level, hero_title()], Color(1.0, 0.85, 0.3), global_position + Vector3(0.0, 2.4, 0.0))
	AudioManager.play_sfx(&"level_up")
	VFXManager.spawn_effect(&"whirlwind_aura", global_position, 0.0, {"lifetime": 0.7})
	# v27：升级金环 + 金屑（与 Pawn._level_up 同款表现，主角升级更有仪式感）
	VFXManager.spawn_effect(&"levelup_ring", global_position + Vector3(0.0, 0.2, 0.0), 0.0,
		{"throttle_key": get_instance_id()})
	VFXManager.spawn_effect(&"levelup_spark", global_position + Vector3(0.0, 1.0, 0.0), 0.0,
		{"throttle_key": get_instance_id()})
	EventBus.game_message.emit("主角升到 Lv.%d ·「%s」（+30 生命 · 伤害提升 · +1 技能点）" % [level, hero_title()], Color(1.0, 0.85, 0.3))


# ---- 节点构建 ----
func _setup_nodes() -> void:
	super._setup_nodes()
	# 主角动画器
	animator = HeroAnimator.new()
	animator.name = "HeroAnimator"
	add_child(animator)
	# 主角专属状态（state_machine 此时已在树中、_ready 已自动登记标准状态，故手动登记）
	state_machine.register_state("hero_idle", HeroIdleState.new())
	state_machine.register_state("hero_combo", HeroComboState.new())
	state_machine.register_state("hero_skill", HeroSkillState.new())


func _apply_def() -> void:
	super._apply_def()
	hero_def = def as HeroDef


# ---- 每帧：冷却 / 连招窗口倒计时 ----
func _process(delta: float) -> void:
	# v34 回城疗伤：白天在城镇范围内缓慢回血（晚上守城期间不回）
	_try_town_regen(delta)
	# v26 驯龙：攻击目标保鲜倒计时（过期后宠物龙不再追打旧目标）
	if _attack_target_left > 0.0:
		_attack_target_left = maxf(0.0, _attack_target_left - delta)
		if _attack_target_left <= 0.0:
			attack_target = null
	# 技能冷却
	if hero_def != null:
		for i in _skill_cd.size():
			if _skill_cd[i] > 0.0:
				_skill_cd[i] = max(0.0, _skill_cd[i] - delta)
				EventBus.skill_cooldown_changed.emit(self, i, skill_cd_ratio(i))
	# 连招递进窗口
	if _combo_window_left > 0.0:
		_combo_window_left = max(0.0, _combo_window_left - delta)
		if _combo_window_left == 0.0 and _combo_step != 0:
			_combo_step = 0
			EventBus.combo_step_changed.emit(self, 0)


# ---- 普攻连招 ----
func request_basic_attack() -> bool:
	if hero_def == null or is_dead_flag or state_machine == null:
		return false
	var cur = state_machine.current_state
	# 连招中：缓冲下一击
	if cur != null and cur.name == "hero_combo":
		_pending_combo = true
		return true
	# 仅在 hero_idle 可起手
	if cur == null or cur.name != "hero_idle":
		return false
	var step: int
	if _combo_window_left > 0.0 and _combo_step < hero_def.combo_hits.size():
		step = _combo_step + 1
	else:
		step = 1
	_start_combo(step)
	return true


func _start_combo(step: int) -> void:
	_combo_step = step
	_combo_window_left = hero_def.combo_window
	EventBus.combo_step_changed.emit(self, step)
	state_machine.transition_to("hero_combo", {"step": step})


# ---- 技能 ----
func request_skill(index: int) -> bool:
	if hero_def == null or is_dead_flag or state_machine == null:
		return false
	if index < 0 or index >= hero_def.skills.size():
		return false
	var cur = state_machine.current_state
	# 连招 / 技能进行中不可再放（简化）
	if cur != null and (cur.name == "hero_combo" or cur.name == "hero_skill"):
		return false
	if _skill_cd[index] > 0.0:
		return false
	_skill_cd[index] = hero_def.skills[index].cooldown
	EventBus.skill_cast.emit(self, index, hero_def.skills[index])
	EventBus.skill_cooldown_changed.emit(self, index, 0.0)
	state_machine.transition_to("hero_skill", {"index": index})
	return true


func skill_cd_ratio(index: int) -> float:
	if hero_def == null or index < 0 or index >= hero_def.skills.size():
		return 1.0
	var cd: float = hero_def.skills[index].cooldown
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - _skill_cd[index] / cd, 0.0, 1.0)


# ---- 战斗工具（去中心化伤害，仿 AttackerComponent）----
func facing_dir() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


## 取「以 center 为圆心、forward 朝向、range 内、half_arc 扇形内」的敌方列表。
func acquire_enemies_in_arc(center: Vector3, forward: Vector3, range: float, half_arc: float) -> Array:
	var out: Array = []
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	f = f.normalized()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var en: Node3D = e
		var to := en.global_position - center
		to.y = 0.0
		var dist: float = to.length()
		if dist > range:
			continue
		if dist > 0.001:
			if f.angle_to(to.normalized()) > half_arc:
				continue
		out.append(e)
	return out


## 对多个目标直接调用其 HealthComponent.apply_damage（去中心化）。
## 伤害按等级倍率放大（damage_mult）。
## v26：顺手把「离主角最近的那只」记为宠物龙攻击目标（玩家打谁龙打谁）。
func apply_damage_to(targets: Array, amount: float) -> void:
	var scaled: float = amount * damage_mult()
	var nearest: Node = null
	var nearest_d: float = INF
	for t in targets:
		if not is_instance_valid(t):
			continue
		var h: HealthComponent = t.get_node_or_null("HealthComponent")
		if h != null and not h.is_dead():
			h.apply_damage(scaled, self)
		var tn := t as Node3D
		if tn != null:
			var d: float = global_position.distance_squared_to(tn.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest = t
	if nearest != null:
		note_attack_target(nearest)


## 第三人称亲自采集：取前方扇形内的资源节点（普攻挥砍时一并砍树 / 敲石，即时入库）。
## 与 acquire_enemies_in_arc 同一套几何判定；range 加 0.6m 容差让贴身砍树更顺手。
func harvest_nodes_in_arc(center: Vector3, forward: Vector3, range: float, half_arc: float) -> Array:
	var out: Array = []
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		f = Vector3.FORWARD
	f = f.normalized()
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n):
			continue
		var node: Node3D = n
		var to := node.global_position - center
		to.y = 0.0
		var dist: float = to.length()
		if dist > range:
			continue
		if dist > 0.001:
			if f.angle_to(to.normalized()) > half_arc:
				continue
		out.append(n)
	return out


# ---- 小队 ----
func recruit_squad(members: Array) -> void:
	for m in members:
		if squad.size() >= SQUAD_MAX:
			break   # 小队上限 4：主角 + 4 名小兵 = 5 人编制
		if m == null or not is_instance_valid(m):
			continue
		if m == self or not (m is Pawn):
			continue
		if m in squad:
			continue
		if not m.is_in_group("player_unit"):   # 仅玩家阵营单位可入队
			continue
		squad.append(m)
		m.add_to_group("hero_squad")
		m.follow_leader = self
		m.squad_slot = squad.size() - 1
		m.set_squad_mark(true)   # v18：常驻绿色包边 + 脚下小绿圈（同一队伍标识）
		if m.health != null:
			m.health.died.connect(_on_member_died)
		if m.state_machine != null:
			# gather=true：集结必为「追赶期」——FollowState 用 2× 速度冲到主角周围槽位，
			# 就位一次后自动回落原速（满足「集结加速 100% 冲到位、跟随时原速」）。
			m.state_machine.transition_to("follow", {"leader": self, "slot": squad.size() - 1, "gather": true})
	# 重新分配 slot 编号（紧凑队形）
	_reassign_slots()
	EventBus.squad_changed.emit(self, squad.duplicate())


func release_squad() -> void:
	for m in squad:
		_release_member(m)
	squad.clear()
	EventBus.squad_changed.emit(self, [])


func _release_member(m) -> void:
	if m == null or not is_instance_valid(m):
		return
	m.remove_from_group("hero_squad")
	m.follow_leader = null
	m.set_squad_mark(false)   # 出队：撤下绿色包边与脚下绿圈
	if m.health != null and m.health.died.is_connected(_on_member_died):
		m.health.died.disconnect(_on_member_died)
	if m.state_machine != null and m.state_machine.current_state != null \
			and m.state_machine.current_state.name == "follow":
		m.state_machine.transition_to("idle")


func _reassign_slots() -> void:
	for i in squad.size():
		var m = squad[i]
		if is_instance_valid(m):
			m.squad_slot = i   # 持久槽位（follow 状态进出 / 战斗归来后仍保持队形）
		if is_instance_valid(m) and m.state_machine != null \
				and m.state_machine.current_state != null \
				and m.state_machine.current_state.name == "follow":
			m.state_machine.current_state.set("_slot", i)


func _on_member_died() -> void:
	# 信号无参数：统一清理已死亡 / 失效成员
	var alive: Array = []
	for m in squad:
		if is_instance_valid(m) and not m.is_dead_flag:
			alive.append(m)
		else:
			if is_instance_valid(m):
				m.remove_from_group("hero_squad")
				m.follow_leader = null
				m.set_squad_mark(false)   # 阵亡清理：撤下小队绿标
	if alive.size() != squad.size():
		squad = alive
		_reassign_slots()
		EventBus.squad_changed.emit(self, squad.duplicate())


# ---- 编队（v10：城镇可有很多小兵，但只能带 4 个；按 V 打开编队界面调整）----

## 新士兵出生（定居 / 兵营募兵）：编队未满自动补位。
func _on_pawn_spawned_for_party(pawn: Node) -> void:
	if pawn is Soldier and not party.has(pawn) and party.size() < SQUAD_MAX:
		party.append(pawn)
		EventBus.party_changed.emit(self, party.duplicate())

## 士兵死亡 / 失效：从编队移除。
func _on_pawn_died_for_party(pawn: Node) -> void:
	if party.has(pawn):
		party.erase(pawn)
		if squad.has(pawn):
			_release_member(pawn)
			squad.erase(pawn)
			_reassign_slots()
			EventBus.squad_changed.emit(self, squad.duplicate())
		EventBus.party_changed.emit(self, party.duplicate())

## 编队里还有效且存活的成员（G 集结 / HUD 显示用，顺手清理失效引用）。
func alive_party() -> Array:
	var out: Array = []
	var dead: Array = []
	for m in party:
		if is_instance_valid(m) and not m.is_dead_flag:
			out.append(m)
		else:
			dead.append(m)
	if not dead.is_empty():
		for m in dead:
			party.erase(m)
			if squad.has(m):
				squad.erase(m)
			if is_instance_valid(m):
				(m as Pawn).set_squad_mark(false)   # 失效成员：撤下小队绿标
		EventBus.party_changed.emit(self, party.duplicate())
	return out

## 加入编队。返回是否成功（已满 / 已在队 / 非士兵 → false）。
func add_party_member(m: Node) -> bool:
	if m == null or not is_instance_valid(m) or not (m is Soldier) or m.is_dead_flag:
		return false
	if party.has(m):
		return false
	if party.size() >= SQUAD_MAX:
		return false
	party.append(m)
	# 小队正在跟随时，新编队成员即刻入列跟随
	if squad.size() > 0 and not squad.has(m):
		recruit_squad([m])
	EventBus.party_changed.emit(self, party.duplicate())
	return true

## 移出编队（同时脱离小队）。
func remove_party_member(m: Node) -> void:
	if not party.has(m):
		return
	party.erase(m)
	if squad.has(m):
		_release_member(m)
		squad.erase(m)
		_reassign_slots()
		EventBus.squad_changed.emit(self, squad.duplicate())
	EventBus.party_changed.emit(self, party.duplicate())

## 整表替换编队（编队界面「一键组队」等）。
func set_party(members: Array) -> void:
	var cleaned: Array = []
	for m in members:
		if m is Soldier and is_instance_valid(m) and not m.is_dead_flag and not cleaned.has(m):
			cleaned.append(m)
			if cleaned.size() >= SQUAD_MAX:
				break
	# 被移出且正在跟随的成员脱离小队
	for m in party:
		if not cleaned.has(m) and squad.has(m):
			_release_member(m)
	party = cleaned
	_reassign_slots()
	EventBus.party_changed.emit(self, party.duplicate())


# ---- 集火（v10：按 T 下令小队围攻准星目标，直到它死亡才恢复各自行为 AI）----

## 下令集火：target 为空 = 取消当前集火令。
func order_focus_fire(target: Node) -> void:
	focus_target = target
	EventBus.squad_focus_changed.emit(self, target)

## 集火目标是否仍有效（活着才算）。
func is_focus_alive() -> bool:
	return focus_target != null and is_instance_valid(focus_target) \
		and focus_target is Pawn and not (focus_target as Pawn).is_dead_flag


# ---- 死亡 / 复活（覆盖 Pawn._on_died：不 queue_free）----
func _on_died() -> void:
	if is_dead_flag:
		return
	is_dead_flag = true
	desired_velocity = Vector3.ZERO
	EventBus.hero_died.emit(self)
	order_focus_fire(null)
	release_squad()
	if hero_def != null and hero_def.respawn_at_base:
		_start_respawn()
	else:
		GameManager.request_game_over(false)


func _start_respawn() -> void:
	# 禁用碰撞 + 隐藏，等待复活
	velocity = Vector3.ZERO
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = true
	visible = false
	set_process(false)
	if animator != null:
		animator.play(&"dead", {})
	if state_machine != null:
		state_machine.transition_to("hero_idle")
	EventBus.game_message.emit("主角倒下！%.0f 秒后在基地复活" % hero_def.respawn_delay, Color.ORANGE_RED)
	await get_tree().create_timer(hero_def.respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	global_position = _base_spawn_pos()
	if health != null:
		health.current_hp = health.max_hp
		health.health_changed.emit(health.current_hp, health.max_hp)
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = false
	visible = true
	is_dead_flag = false
	set_process(true)
	if state_machine != null:
		state_machine.transition_to("hero_idle")
	EventBus.game_message.emit("主角已复活！", Color(0.6, 1.0, 0.6))


func _base_spawn_pos() -> Vector3:
	var bases := get_tree().get_nodes_in_group("base_core")
	for b in bases:
		if is_instance_valid(b) and b is Node3D:
			return (b as Node3D).global_position + Vector3(3.0, 0.0, 0.0)
	return Vector3.ZERO


## v36：主角由玩家亲自操控，河 / 浅滩本来就没有物理碰撞、涉水是合法操作，
## 「阻挡格滞留自救」绝不自动搬移玩家角色。
func allows_terrain_rescue() -> bool:
	return false
