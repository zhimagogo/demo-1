class_name WildlifeSpawner
extends Node3D
## ============================================================================
## 城外野怪刷新器（v20「夜潮攻城」→ v31「守城准备」版）。
## - 白天（06:00~18:00）：零散补刷普通掠夺者（维持 day_cap）
## - 傍晚（18:00~20:00）：完全停刷——天地渐暗，野外归于沉寂（大战前的宁静）
## - 夜晚（20:00 起）：先进入「守城准备期」——昼夜时钟冻结（TimeManager.clock_frozen，
##   游戏本身照常跑）：玩家清剿场上残敌、配置小队 / 布防，小兵清完怪自动回城待命
##   （SoldierIdleState 夜间路由）。HUD 亮出「准备守城」按钮，玩家按下
##   （GameManager.request_night_defense → night_defense_started）后：
##   时间恢复流动，随机选定「四条道路之一」成批刷出大股夜潮怪（v40 在 62m 处集结）
##   （批量随夜数成长；15% 概率带一名精英）直扑主城（assaulting 标记：
##   无概率 / 冷却 / 并发门控；中途被小兵打中会立即转火小兵，见 Raider._on_damaged）
## - 头目：每逢第 2/4/6…天开战，从同一道路的集结点额外刷一名「夜袭头目」
## - 野怪自身永不进城（Raider.avoids_city）；夜潮攻城由 assaulting 标记驱动
## ============================================================================

@export var max_monsters: int = 14         # 白天城外野怪数量上限（v40 扩图后上调）
@export var night_max_monsters: int = 28   # 夜晚上限（夜潮大部队压境）
@export var spawn_interval: float = 3.5    # 白天补刷间隔（秒，游戏时间）
@export var night_wave_interval: float = 9.0   # 夜潮批次间隔（秒，游戏时间）
@export var night_wave_base: int = 5       # 夜潮基础批量（实际 = base + 夜数，封顶）
@export var night_wave_cap: int = 11       # 夜潮单批数量封顶
@export var spawn_min_r: float = 40.0      # 白天出生环最小半径（须 ≥ 主城 half*√2≈36.8；v43：26m 半城 → 40m）
@export var spawn_max_r: float = 116.0     # 白天出生环最大半径（v40：贴到 128m 边界内）
@export var elite_chance: float = 0.15     # 每批带精英的概率
@export var boss_every_nights: int = 2     # 每 N 个夜晚出一次头目（第 N 天入夜时）

var _alive: int = 0
var _timer: float = 0.0
var _boss_alive: Node = null
var _night_gate: int = -1                  # 今夜出怪的道路尽头（-1 = 未选定；0南 1东 2北 3西）
var _night_gate_pos: Vector3 = Vector3.ZERO          # 道路尽头（播报文案 / 测试锚点）
var _night_wave_origin: Vector3 = Vector3.ZERO       # 夜潮实际集结点（v40：62m 处，保夜战节奏）
var _wave_timer: float = 0.0               # 夜潮批次计时
var _night_prep: bool = false              # v31 守城准备期：入夜时钟冻结，等玩家确认开战
var _prep_cleared: bool = false            # 准备期残敌已清空（「小兵回城待命」播报只发一次）


func _ready() -> void:
	# 复用 EventBus.enemy_spawned / enemy_died 维护存活计数（与 CombatSystem 各自独立计数，
	# 互不依赖：本计数用于刷怪限流，CombatSystem.enemies_alive 用于 HUD 显示）
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.night_changed.connect(_on_night_changed)
	EventBus.night_defense_started.connect(_on_night_defense_started)
	# v44：夜里新出生的小兵补发当前威胁方向（EventBus 无状态，晚到的单位也能去城门列阵）
	EventBus.pawn_spawned.connect(_on_pawn_spawned)


func _on_enemy_spawned(enemy: Node) -> void:
	_alive += 1
	if enemy.def != null and enemy.def.is_boss:
		_boss_alive = enemy


func _on_enemy_died(enemy: Node, _killer: Node) -> void:
	_alive = max(0, _alive - 1)
	if enemy != null and enemy == _boss_alive:
		_boss_alive = null


func _on_night_changed(is_night: bool) -> void:
	if not is_night:
		_dawn_cleanup()
		return
	if max_monsters <= 0:
		return
	if _tutorial_running():
		return   # 新手引导期间不进守城准备也不刷夜袭：给慢玩家一个纯净的引导气泡
	# v31 入夜 → 守城准备期：昼夜时钟冻结，夜潮延迟到玩家按下「准备守城」。
	# 玩家清剿残敌、配置小队 / 布防；确认后经 _on_night_defense_started 恢复时间并开战。
	_begin_night_prep()


func _process(delta: float) -> void:
	if _tutorial_running():
		# 首杀教学必须有目标，否则首次运行会卡在「杀怪」与「引导停刷」的互锁里。
		# 只维持一只普通怪；即使玩家磨到夜晚也能完成，夜潮仍由引导门禁挡住。
		var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
		if max_monsters > 0 and tutorial.needs_combat_target() and _alive < 1:
			_timer += delta
			if _timer >= spawn_interval:
				_timer = 0.0
				_spawn_one(GameDefs.raider_def())
		return
	if Raider.is_night_now():
		# 兜底：入夜时正被引导门禁跳过（night_changed 早退），引导结束后在这里
		# 补进准备期——而不是跳过整段直接刷怪；绝不把主城当出生点
		if _night_gate < 0:
			_begin_night_prep()
		if _night_prep:
			_update_night_prep()
			return   # 准备期：不补怪也不出夜潮，等玩家清完残敌、确认开战
		if _alive >= night_max_monsters:
			return
		# 夜潮：从今夜选定道路的集结点成批涌出，直扑主城
		_wave_timer += delta
		if _wave_timer >= night_wave_interval:
			_wave_timer = 0.0
			_spawn_night_wave()
	else:
		if Raider.is_dusk_now():
			return   # 傍晚完全停刷：大战前的宁静（既不补白天散怪，也不提前出夜潮）
		if _alive >= max_monsters:
			return
		_timer += delta
		if _timer >= spawn_interval:
			_timer = 0.0
			_spawn_one(GameDefs.raider_def())


# ---- v31 夜间守城准备 ----

## 进入守城准备期：选定今夜进攻的道路尽头（提前播报方向，供玩家布防）、
## 冻结昼夜时钟并广播 night_prep_started。幂等：同一夜重复调用不再重选门。
## v44：选门后额外广播「今夜威胁方向」，小兵据此到对应城门内侧列阵（近战前排 / 远程后排）。
func _begin_night_prep() -> void:
	if _night_prep:
		return
	if _night_gate < 0:
		_choose_night_gate()
	_night_prep = true
	_prep_cleared = false
	_wave_timer = 0.0
	TimeManager.freeze_clock()
	_emit_threat_direction(true)
	EventBus.night_prep_started.emit()
	EventBus.game_message.emit("夜幕降临，时间静止——清剿残敌、布防城镇！", Color(0.7, 0.6, 1.0))
	AudioManager.play_sfx(&"night_bell")
	EventBus.game_message.emit("斥候来报：今夜大股怪物将从%s方大道涌来，直扑主城！" % WorldLayout.road_end_name(_night_gate), Color(1.0, 0.45, 0.3))


## v44：广播今夜威胁方向（active=true 时 gate_inside 已吸附到城内可走格）。
## active=false 表示威胁解除 / 天亮，士兵恢复常规夜间待命点；信号是士兵唯一数据来源，
## 不允许士兵每帧去读本系统的私有字段。
func _emit_threat_direction(active: bool) -> void:
	if active and _night_gate >= 0:
		var p := WorldLayout.gate_inside_point(_night_gate)
		var inside := _snap(Vector3(p.x, 0.0, p.y))
		EventBus.night_threat_direction_changed.emit(true, _night_gate, inside)
	else:
		EventBus.night_threat_direction_changed.emit(false, -1, Vector3.ZERO)


## 夜里新出生的小兵：补发当前威胁方向，让晚到单位也能加入城门内侧阵列。
## 士兵在 _ready 的 super 之前就订阅信号，因此能收到这次补发。
func _on_pawn_spawned(pawn: Node) -> void:
	if not (pawn is Soldier):
		return
	if _night_gate < 0 or not TimeManager.is_night():
		return
	_emit_threat_direction(true)


## 准备期推进：场上残敌清空 → 广播 night_prep_cleared 并播报「回城待命」。
## 小兵的回城本身由 SoldierIdleState 的夜间路由自动完成（时钟停在 20:00 仍属夜间，
## 城外士兵收兵回城、进圈后游荡驻防）；准备期停刷，敌数只减不增，播报一次即够。
func _update_night_prep() -> void:
	if _prep_cleared:
		return
	if get_tree().get_nodes_in_group("enemy").is_empty():
		_prep_cleared = true
		EventBus.night_prep_cleared.emit()
		EventBus.game_message.emit("残敌已清——士兵们回城待命，随时可以迎战！", Color(0.55, 0.85, 0.55))


## 玩家确认开战（GameManager.request_night_defense）：时间恢复流动，夜潮立即压境。
## 头目夜（第 2/4/6…夜）在同一时刻进场；首波下一帧出，保持旧版「开打即见怪」节奏。
func _on_night_defense_started() -> void:
	if not _night_prep:
		return   # 非准备期收到（重复点击 / 测试直发）：幂等忽略
	_night_prep = false
	_prep_cleared = false
	TimeManager.unfreeze_clock()
	EventBus.game_message.emit("时间重新流动——大股怪物从%s方大道涌来，直扑主城！" % WorldLayout.road_end_name(_night_gate), Color(1.0, 0.45, 0.3))
	AudioManager.play_sfx(&"charge")
	var night_index: int = maxi(1, TimeManager.day)
	if night_index % boss_every_nights == 0:
		_spawn_boss()
	_wave_timer = night_wave_interval   # 开战即刻刷出第一波夜潮


func _tutorial_running() -> bool:
	var t := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	return t != null and t.state == TutorialSystem.State.RUNNING


# ---- 单只 / 群体 / 头目 ----

func _spawn_one(def: PawnDef) -> void:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_raider"):
		push_warning("WildlifeSpawner: PawnSpawner 未就绪，跳过野怪生成")
		return
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	(spawner as Node).call("spawn_raider", _pick_spawn_point(city), def)


## 选定今夜进攻的道路尽头（四选一，整夜固定）：0=南 1=东 2=北 3=西（v40 与小地图罗盘一致）。
func _choose_night_gate() -> void:
	_night_gate = randi() % 4
	var p := WorldLayout.road_end(_night_gate)
	_night_gate_pos = _snap(Vector3(p.x, 0.0, p.y))
	# v40：夜潮/头目在老地图边缘距离（62m）集结，避免从 121m 尽头走 40 秒导致「天亮了才到城下」。
	var q := WorldLayout.night_wave_origin(_night_gate)
	_night_wave_origin = _snap(Vector3(q.x, 0.0, q.y))


## 天亮清理：解除全部夜潮怪的 assaulting 标记（FightState 的天亮检查会把仍在
## 攻城的弹出城外，之后它们回到白天的城外游荡逻辑）。
## v31：同时兜底解除守城准备期（测试直接跳钟跨夜等场景），恢复昼夜时钟。
func _dawn_cleanup() -> void:
	_night_prep = false
	_prep_cleared = false
	TimeManager.unfreeze_clock()
	_night_gate = -1
	_wave_timer = 0.0
	_emit_threat_direction(false)   # v44：威胁解除 → 士兵恢复常规夜间待命点 / 白天逻辑
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Raider and is_instance_valid(e):
			(e as Raider).assaulting = false


## 夜潮批次（v20）：从今夜选定道路的集结点成批刷出大部队——沿道路向外侧
## 方向排纵深、横向铺开列队；出生即带 assaulting 标记直扑主城。
## 批量随夜数成长（夜 1：6 只；夜 6+：11 只封顶）；15% 概率由精英带头。
func _spawn_night_wave() -> void:
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_raider"):
		return
	var night_index: int = maxi(1, TimeManager.day)
	var wave_size: int = clampi(night_wave_base + night_index, 6, night_wave_cap)
	var has_elite := randf() <= elite_chance
	var count := wave_size - 1 if has_elite else wave_size
	var origin := _night_wave_origin if _night_wave_origin.length() > 0.01 else _night_gate_pos
	var out_dir: Vector3 = origin.normalized() if origin.length() > 0.01 else Vector3(1.0, 0.0, 0.0)
	var perp := Vector3(out_dir.z, 0.0, -out_dir.x)
	var cols: int = 4
	for i in count:
		var row: int = i / cols
		var col: int = i % cols
		var pos := origin + out_dir * (1.6 + float(row) * 2.2) \
			+ perp * ((float(col) - float(cols - 1) * 0.5) * 2.0)
		var r: Raider = (spawner as Node).call("spawn_raider", pos, GameDefs.raider_def())
		if r != null:
			r.begin_night_assault()
	if has_elite:
		var elite: Raider = (spawner as Node).call("spawn_raider", origin + out_dir * 1.2, GameDefs.raider_elite_def())
		if elite != null:
			elite.begin_night_assault()
		EventBus.game_message.emit("一支精英带头的大部队正沿%s方道路逼近城镇！" % WorldLayout.road_end_name(_night_gate), Color(1.0, 0.55, 0.4))


## 夜袭头目：大体型 + 高掉落 + 全场播报 + 震屏。击杀奖励由 CombatSystem 掉落（120 金）。
## v20 起与夜潮同出一门：从今夜选定道路的集结点进场，同样直扑主城。
func _spawn_boss() -> void:
	if _boss_alive != null and is_instance_valid(_boss_alive):
		return
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_raider"):
		return
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	var def := GameDefs.raider_boss_def()
	def.unit_name = GameDefs.random_boss_name()
	var at := _night_wave_origin if _night_wave_origin.length() > 0.01 else _night_gate_pos
	if _night_gate < 0:
		at = _pick_spawn_point(city, 34.0)
	var boss: Node = (spawner as Node).call("spawn_raider", at, def)
	if boss is Raider:
		(boss as Raider).begin_night_assault()
	EventBus.boss_spawned.emit(boss)
	EventBus.game_message.emit("第 %d 夜 · 夜袭头目【%s】带着杀意来了！" % [maxi(1, TimeManager.day), def.unit_name], Color(1.0, 0.35, 0.45))
	AudioManager.play_sfx(&"boss_spawn")
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.has_method("shake"):
		camera.call("shake", 0.55, 0.7)


func _snap(pos: Vector3) -> Vector3:
	var nav := get_tree().get_first_node_in_group("nav_system") as NavSystem
	return nav.snap_to_walkable(pos) if nav != null else pos


## 取一个「矩形主城外」的出生点：环上随机，落在矩形城内的候选重采（城是矩形非圆，圆环对角点会进角内）。
func _pick_spawn_point(city: CitySystem, min_r: float = -1.0) -> Vector3:
	var r_min := spawn_min_r if min_r < 0.0 else minf(spawn_min_r, min_r)
	if city != null:
		for _i in 12:
			var a := randf() * TAU
			var rad := randf_range(r_min, spawn_max_r)
			var p := Vector3(cos(a), 0.0, sin(a)) * rad
			if not city.is_in_city(p):
				return p
	# 无主城或重采失败：直接用环点（spawn_min_r 已 ≥ half*√2，基本不会进城）
	var angle := randf() * TAU
	var radius := randf_range(r_min, spawn_max_r)
	return Vector3(cos(angle), 0.0, sin(angle)) * radius
