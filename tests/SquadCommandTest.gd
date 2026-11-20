extends Node
## ============================================================================
## v18 小队指令优先级 / 常驻绿标 / 拟真跟随 专项回归：
##   godot --headless --path . tests/SquadCommandTest.tscn --log-file /private/tmp/a-squad.log --fixed-fps 60
##
## 需求覆盖：
##  A. 主人命令（集火 / 集结）最高优先：
##     1) 成员正在打别的目标时下达集火令 → 必须立即转火（FightState 轮询活令）；
##     2) 集火目标死亡 → 回队长身边重新列队，不再 40m 顺手追打无关敌人；
##     3) 集结令（G）可以打断正在进行的战斗（短暂停火期先归队）。
##  B. 小队常驻绿标：入队 = 绿色包边 + 脚下小绿圈常驻；出队 / 解散即撤下。
##  C. 拟真跟随：
##     4) 槽位持久化——战斗 / 待机后回到 follow 不再全员回落 0 号槽；
##     5) 队长（主角）原地转身（转相机视角）不再带动队形旋转 → 成员零踱步；
##     6) 站定播 idle、集结追赶播 run（不再站着播走路循环）。
##
## 输出保持 ASCII（headless 日志中文会乱码）；headless 无真实输入，命令直接调 API。
## ============================================================================

const SOLDIER_COUNT: int = 3
const HERO_HOME := Vector3(0.0, 0.0, 40.0)   # 城外（城市 ±14m）南侧空地，远离野怪刷新
const SPAWN_OFF := Vector3(0.0, 0.0, 12.0)   # 小兵出生偏移（> GATHER_START_DIST → 追赶期）

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _pos_xz(n: Node3D) -> Vector3:
	var v: Vector3 = n.global_position
	v.y = 0.0
	return v


func _dist_xz(a: Node3D, b: Node3D) -> float:
	return _pos_xz(a).distance_to(_pos_xz(b))


## 造一只「木桩野怪」：低攻（别把小队打死）、不死逃（flee=0）、够血撑到断言完成。
func _spawn_dummy(spawner: Node, at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 60.0
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	return spawner.call("spawn_raider", at, d)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	# 测试期停刷野怪 / 流民，清空既有敌人：指令行为必须确定性
	var wildlife := world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await get_tree().physics_frame

	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	hero.global_position = HERO_HOME
	hero.velocity = Vector3.ZERO
	hero.set_party([])
	await get_tree().physics_frame

	# ---- 布景：3 名近战兵在 12m 外（> 10m 追赶阈值）----
	var soldiers: Array = []
	for i in SOLDIER_COUNT:
		var at := HERO_HOME + SPAWN_OFF + Vector3(float(i) * 1.8 - 1.8, 0.0, 0.0)
		soldiers.append(spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), at))
	for _i in 3:
		await get_tree().physics_frame
	_check(hero.party.size() == SOLDIER_COUNT, "3 soldiers spawned and auto-fill the party")

	# ---- A0：G 集结（真路径）----
	controller._toggle_squad_rally()
	_check(hero.squad.size() == SOLDIER_COUNT, "G rally recruits all soldiers")
	var saw_run: bool = false
	var settled_all: bool = false
	for f in 360:
		await get_tree().physics_frame
		var all_close := true
		for s in soldiers:
			var p := s as Pawn
			if _dist_xz(p, hero) > 3.5:
				all_close = false
			if p.model_rig != null and p.model_rig._current == &"run":
				saw_run = true
		if all_close and f > 30:
			settled_all = true
			break
	_check(settled_all, "squad gathers around the hero (chase + settle)")
	_check(saw_run, "rally chase plays run animation (2x phase)")

	# ---- C6：站定播 idle（不再站着播走路循环）----
	for _i in 60:
		await get_tree().physics_frame
	var anim_idle: bool = true
	for s in soldiers:
		var p := s as Pawn
		if p.model_rig == null or p.model_rig._current != &"idle":
			anim_idle = false
	_check(anim_idle, "settled members play idle animation (no walking-in-place)")

	# ---- C4：槽位持久化（战斗 / 待机后回 follow 槽位不丢）----
	var slot_set: Dictionary = {}
	for s in soldiers:
		var p := s as Pawn
		if p.state_machine.current_state.name == "follow":
			slot_set[int(p.state_machine.current_state.get("_slot"))] = true
	_check(slot_set.size() == SOLDIER_COUNT, "each member holds a distinct slot (%d)" % slot_set.size())
	for s in soldiers:
		(s as Pawn).state_machine.transition_to("idle")   # 模拟「战斗结束回到 idle 路由」
	for _i in 6:
		await get_tree().physics_frame
	var slot_kept: bool = true
	for s in soldiers:
		var p := s as Pawn
		if p.state_machine.current_state.name != "follow" \
				or int(p.state_machine.current_state.get("_slot")) != p.squad_slot:
			slot_kept = false
	_check(slot_kept, "slot survives idle round-trip (reads Pawn.squad_slot)")

	# ---- C5：队长原地转身不带动队形（旧算法槽位随朝向旋转 → 成员围着主角踱步）----
	# v34 夹具修正：抓基线前先等队形**真正静止**（连续 20 帧位移 < 0.5mm）。
	# 旧版只等固定 60 帧——「3.5m 内即 break」的集结判定下成员仍在向槽位收敛，
	# 残差收敛运动会随任何初始条件微移（脚本改动 / RNG）落进或跳出 0.05m 阈值，
	# 呈双稳态假失败（v34 实测：无关脚本改动让 drift 在 0.000 与 0.06~0.10 间翻转）。
	await _wait_squad_settled(soldiers)
	var rot_from: Dictionary = {}
	for s in soldiers:
		rot_from[s] = _pos_xz(s as Node3D)
	var yaw_turned: float = 0.0
	for i in 120:
		tp.yaw += 0.35 if i % 2 == 0 else -0.35   # 来回猛转视角 = 主角持续转身
		yaw_turned += 0.35
		await get_tree().physics_frame
	var rot_drift: float = 0.0
	for s in soldiers:
		rot_drift = maxf(rot_drift, _pos_xz(s as Node3D).distance_to(rot_from[s] as Vector3))
	_check(yaw_turned > 1.0 and rot_drift < 0.05,
		"hero spinning in place does not pace the squad (drift %.3f m over 2s)" % rot_drift)

	# ---- B：小队常驻绿标（绿色包边 + 脚下小绿圈）----
	var marks_on: bool = true
	for s in soldiers:
		var p := s as Pawn
		var ring := p.get_node_or_null("SquadRing") as MeshInstance3D
		if ring == null or not ring.visible or not (ring.mesh is TorusMesh):
			marks_on = false
		else:
			var c: Color = (ring.material_override as StandardMaterial3D).albedo_color
			if c.g < 0.8 or c.g <= c.r or c.g <= c.b:
				marks_on = false
		if p.model_rig == null or not p.model_rig._outline_on:
			marks_on = false
		elif p.model_rig._outline_meshes.size() > 0:
			var oc: Color = ((p.model_rig._outline_meshes[0] as MeshInstance3D) \
				.material_override as StandardMaterial3D).albedo_color
			if oc.g < 0.8 or oc.g <= oc.r or oc.g <= oc.b:
				marks_on = false
	_check(marks_on, "squad members wear persistent green outline + green foot ring")

	# ---- A1：集火令打断进行中的战斗（正在打 A，令出必转火 B）----
	# A 放 30m：仍在旧版 40m「顺手索敌」范围内（证明不再乱追），又不会在断言窗口内
	# 逼近到 7m 自卫接战圈干扰「回队」判定。
	var m0 := soldiers[0] as Pawn
	var enemy_a := _spawn_dummy(spawner, HERO_HOME + Vector3(30.0, 0.0, 0.0))
	var enemy_b := _spawn_dummy(spawner, HERO_HOME + Vector3(0.0, 0.0, -16.0))
	await get_tree().physics_frame
	m0.assign_attack(enemy_a)   # 直接下令打 A（RTS 指派同款入口）
	for _i in 20:
		await get_tree().physics_frame
	_check(m0.state_machine.current_state.name == "fight" and m0.combat_target == enemy_a,
		"member engages assigned target A first")
	hero.order_focus_fire(enemy_b)   # 主人集火令：B
	var switched: bool = false
	for _i in 30:
		await get_tree().physics_frame
		if m0.combat_target == enemy_b and m0.state_machine.current_state.name == "fight":
			switched = true
			break
	_check(switched, "focus order interrupts an ongoing fight (switches A -> B)")
	# 其余成员（follow 态）也应全员转火 B
	var all_on_b: bool = true
	for s in soldiers:
		var p := s as Pawn
		if p.combat_target != enemy_b:
			all_on_b = false
	_check(all_on_b, "whole squad obeys the focus order")

	# ---- A2：集火目标死亡 → 回队长身边列队，不追 40m 内的无关敌人 ----
	# FightState 把 is_dead_flag 视为即刻失效（不等尸体 1.7s 溶解释放），
	# 击杀瞬间小队就应动身归队。
	enemy_b.take_damage(99999.0, hero)
	for _i in 20:
		await get_tree().physics_frame
	var back_to_follow: bool = true
	for s in soldiers:
		var p := s as Pawn
		if p.state_machine.current_state.name != "follow" or p.combat_target != null:
			back_to_follow = false
	_check(back_to_follow and not hero.is_focus_alive(),
		"squad returns to the leader after the focus target dies (no 40m retarget)")

	# ---- B2 / A3：解散撤绿标；集结令打断进行中的战斗 ----
	controller._toggle_squad_rally()   # 解散
	_check(hero.squad.size() == 0, "G toggles squad off")
	var marks_off: bool = true
	for s in soldiers:
		var p := s as Pawn
		var ring := p.get_node_or_null("SquadRing") as MeshInstance3D
		if ring != null and ring.visible:
			marks_off = false
		if p.model_rig != null and p.model_rig._outline_on:
			marks_off = false
	_check(marks_off, "green marks removed after disband")
	# 此节验证巡逻小兵接战后仍服从集结；城内休闲者不再主动追逐城外木桩。
	for s in soldiers:
		(s as Soldier).town_life_active = false
		(s as Soldier)._aggro_cache_frame = -100
	enemy_a.take_damage(99999.0, hero)   # 清掉 A，换近身木桩 D
	var dummy := _spawn_dummy(spawner, HERO_HOME + Vector3(2.5, 0.0, 0.0))
	var fighting: bool = false
	for _i in 90:
		await get_tree().physics_frame
		var any_fight := false
		for s in soldiers:
			if (s as Pawn).state_machine.current_state.name == "fight":
				any_fight = true
		if any_fight:
			fighting = true
			break
	_check(fighting, "free soldiers engage a nearby enemy on their own")
	controller._toggle_squad_rally()   # 集结令：正在打也必须先归队
	var broke_off: bool = false
	for _i in 12:
		await get_tree().physics_frame
	var all_follow: bool = true
	for s in soldiers:
		if (s as Pawn).state_machine.current_state.name != "follow":
			all_follow = false
	broke_off = all_follow
	for _i in 60:   # 停火期内保持归队（不被身边敌人立即拉回战斗）
		await get_tree().physics_frame
		for s in soldiers:
			if (s as Pawn).state_machine.current_state.name != "follow":
				broke_off = false
	_check(broke_off, "rally order breaks off combat (hold-fire window keeps them in formation)")

	# ---- 清理 ----
	hero.order_focus_fire(null)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			(e as Pawn).take_damage(99999.0, hero)
	print("SQUAD COMMAND TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


## 等队形静止：连续 20 个物理帧全员位移 < 0.5mm 即认为收敛完成（上限 600 帧兜底）。
## v34 C5 夹具用——在「向槽位收敛未完成」时抓基线会把残差收敛运动误判成踱步。
func _wait_squad_settled(soldiers: Array) -> void:
	var still_frames: int = 0
	var prev: Dictionary = {}
	for s in soldiers:
		prev[s] = _pos_xz(s as Node3D)
	for _i in 600:
		await get_tree().physics_frame
		var max_step: float = 0.0
		for s in soldiers:
			var now := _pos_xz(s as Node3D)
			max_step = maxf(max_step, now.distance_to(prev[s] as Vector3))
			prev[s] = now
		if max_step < 0.0005:
			still_frames += 1
			if still_frames >= 20:
				return
		else:
			still_frames = 0
