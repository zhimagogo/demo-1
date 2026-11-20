extends Node
## ============================================================================
## v44B 夜潮 / 进攻中的野怪不撤退专项回归（用户反馈「撤退之后就打不到了」）
##   bash tools/godot_locked.sh --headless --path . tests/NightAssaultNoFleeTest.tscn \
##        --fixed-fps 60 --quit-after 20000 --log-file /private/tmp/monster-flee-noassault.log
##
## 覆盖：
##   ① 正控制：普通野怪（flee_chance=1.0 / flee_hp_ratio=0.5 / hp=20%）
##      should_flee_now()==true（逃跑机制本身仍工作，排除「全都不逃」的假通过）；
##   ② 同一只置 assaulting=true 后 should_flee_now()==false（夜潮赶路 / 交战中死战不退）；
##   ③ _sieging=true 同样 should_flee_now()==false（攻城死战契约不被破坏）；
##   ④ 端到端：spawn 一只 assaulting 低血野怪进 fight 跑 120 物理帧，
##      状态始终不是 raider_flee（也不叫 "flee"），且从未离开 fight；
##   ⑤ 已在逃跑的怪被 begin_night_assault 接管后立刻中止撤退、恢复攻城（v44 增强）。
##
## 输出保持 ASCII（headless 日志中文乱码）；全部走脚本 API，不依赖真实鼠标；
## 任何路径都会 quit（含 90s 看门狗）。
## ============================================================================

const WATCHDOG_SEC: float = 90.0
const FIGHT_FRAMES: int = 120

var _failures: int = 0
var _world: Node3D
var _spawner: Node


func _ready() -> void:
	# 看门狗：脚本若因 Parse Error / 卡住不 quit，也必须释放 godot 锁，避免拖死整批。
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	call_deferred("_run")


func _on_watchdog() -> void:
	push_error("FAIL: NightAssaultNoFleeTest watchdog timeout after %.0fs" % WATCHDOG_SEC)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


## 专用野怪 def：低伤害 + 可控血线 / 逃跑概率（不动 GameDefs 全局数值）。
func _monster_def(max_hp: float, flee_ratio: float, flee_chance: float) -> PawnDef:
	var d := PawnDef.new()
	d.team = TeamComponent.Team.ENEMY
	d.max_hp = max_hp
	d.attack_damage = 0.0
	d.flee_hp_ratio = flee_ratio
	d.flee_chance = flee_chance
	return d


## 不还手的木桩小兵（状态机停摆，避免干扰野怪状态断言）。
func _player_def() -> PawnDef:
	var d := PawnDef.new()
	d.is_auto_fighter = false
	d.max_hp = 10000.0
	return d


func _state_name(pawn) -> String:
	if pawn == null or not is_instance_valid(pawn) or pawn.state_machine == null \
			or pawn.state_machine.current_state == null:
		return ""
	return String(pawn.state_machine.current_state.name)


func _run() -> void:
	seed(20261018)
	# 近战命中会播 hit sfx；测试环境无音频资源，置空避免无谓报错（同 MonsterBehaviorStabilityTest）。
	AudioManager._streams[&"hit_1"] = null
	AudioManager._streams[&"hit_2"] = null
	TimeManager.begin(22)   # 夜里：assaulting / 攻城判定都要求 is_night()
	TimeManager.set_speed(1)

	_world = Node3D.new()
	add_child(_world)
	var grid := GridSystem.new()
	grid.name = "GridSystem"
	grid.grid_size = Vector2i(64, 64)
	grid.debug_visible = false
	_world.add_child(grid)
	var nav := NavSystem.new()
	_world.add_child(nav)
	var city := CitySystem.new()
	city.city_half = WorldLayout.CITY_HALF
	city.border_visible = false
	_world.add_child(city)
	var players := Node3D.new()
	_world.add_child(players)
	var enemies := Node3D.new()
	_world.add_child(enemies)
	_spawner = load("res://scripts/systems/PawnSpawner.gd").new()
	_world.add_child(_spawner)
	_spawner.configure(players, enemies)
	await get_tree().physics_frame

	# ---- ①~③ 判定层：正控制 + assaulting / _sieging 强制死战 ----
	var low_def := _monster_def(100.0, 0.5, 1.0)
	var r: Raider = _spawner.spawn_raider(Vector3(30.0, 0.0, -25.0), low_def)
	r.health.current_hp = 20.0   # 20% < flee_hp_ratio 0.5 → 到线
	_check(r.should_flee_now(), "positive control: low-hp plain raider rolls flee (chance 1.0)")
	_check(r.should_flee_now(), "flee roll stays stable (one roll per monster lifetime)")
	r.assaulting = true
	_check(not r.should_flee_now(), "assaulting night-wave raider never flees at low hp")
	r.assaulting = false
	_check(r.should_flee_now(), "clearing assaulting restores the low-hp flee roll")
	r._sieging = true
	_check(not r.should_flee_now(), "sieging raider still fights to the death")
	r._sieging = false
	r.queue_free()
	await get_tree().physics_frame

	# ---- ④ 端到端：assaulting 低血野怪进 fight 跑若干帧，绝不切逃跑 ----
	r = _spawner.spawn_raider(Vector3(30.0, 0.0, -25.0), _monster_def(100.0, 0.5, 1.0))
	var p: Pawn = _spawner.spawn_soldier(_player_def(), Vector3(33.0, 0.0, -25.0))
	p.state_machine.set_physics_process(false)
	r.health.current_hp = 20.0
	r.assaulting = true
	await get_tree().physics_frame
	_check(r.should_flee_now() == false, "probe raider is low hp + assaulting (flee gate closed)")
	r.state_machine.transition_to("fight", {"target": p})
	var fled := false
	var left_fight := 0
	for _i in FIGHT_FRAMES:
		await get_tree().physics_frame
		if not is_instance_valid(r) or r.state_machine == null or r.state_machine.current_state == null:
			break
		var state = r.state_machine.current_state
		if state is RaiderFleeState or _state_name(r) in ["flee", "raider_flee"]:
			fled = true
			break
		if not (state is FightState):
			left_fight += 1
	_check(not fled, "assaulting low-hp raider never enters the flee state over %d frames" % FIGHT_FRAMES)
	_check(_state_name(r) == "fight", "assaulting low-hp raider stays in fight after %d frames (state=%s)"
		% [FIGHT_FRAMES, _state_name(r)])
	_check(left_fight == 0, "assaulting low-hp raider never leaves fight (%d leaves)" % left_fight)
	r.queue_free()
	p.queue_free()
	await get_tree().physics_frame

	# ---- ⑤ 已在逃跑的怪被夜潮总攻接管：立刻中止撤退、恢复攻城 ----
	var core := Node3D.new()
	core.add_to_group("base_core")   # 迷你世界无主城：用空节点作 assault 目标
	_world.add_child(core)
	r = _spawner.spawn_raider(Vector3(30.0, 0.0, -25.0), _monster_def(100.0, 0.5, 1.0))
	p = _spawner.spawn_soldier(_player_def(), Vector3(33.0, 0.0, -25.0))
	p.state_machine.set_physics_process(false)
	r.health.current_hp = 20.0
	r.state_machine.transition_to("raider_flee", {"threat": p})
	_check(r.state_machine.current_state is RaiderFleeState,
		"probe starts in the flee state before the assault order")
	_check(r.should_flee_now(), "fleeing raider still has an open flee gate before the assault order (sanity)")
	r.begin_night_assault()
	_check(r.assaulting, "begin_night_assault sets the assaulting flag")
	_check(not (r.state_machine.current_state is RaiderFleeState),
		"begin_night_assault cancels an active flee state")
	_check(r._sieging and r.state_machine.current_state is FightState,
		"assault order resumes the siege fight toward the base core (state=%s)" % _state_name(r))
	_check(not r.should_flee_now(), "ordered raider keeps fighting to the death afterwards")
	r.queue_free()
	p.queue_free()
	core.queue_free()
	await get_tree().physics_frame

	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Pawn._combat_slots.clear()
	Pawn._spatial_buckets.clear()
	print("NIGHT ASSAULT NO FLEE TEST: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
