class_name PrologueDirector
extends Node
## ============================================================================
## 序章「故土残火」剧本驱动器（v38）。
##
## 序章跑的就是现有沙盒世界（res://scenes/main/Main.tscn）：Main.gd._setup_level()
## 判定「当前关卡 = LevelDef.Kind.PROLOGUE」后 new 出本节点挂到 world_root 下，
## 再调 setup(world_root, main)，之后一切由本节点接管：
##   ① 压掉沙盒系统：野怪停刷 / 流民停拉 / 建造禁用 / 新手引导不自动开始；
##   ② 时间钉在上午十点（TimeManager.begin(10) + clock_frozen → 不推进昼夜、
##      不入夜、不触发夜潮，干净的白日舞台）；
##   ③ 主角从城外西北登场（起点经 NavSystem.snap_to_walkable 吸附后传送，
##      第三人称相机硬跟随、自然收敛）；
##   ④ 起点到城堡之间刷 4 只削弱匪徒（走 PawnSpawner 唯一创建入口，间隔 ≥4m）；
##   ⑤ 两条目标推进：清剿 4 名匪徒 → 收复主城（城堡 8m 内连续停留 hold_seconds）；
##   ⑥ 两条达成 → 记星（完成 1 / 全程未阵亡 +1 / 90 秒内 +1）→ LevelRuntime.record_result
##      → 冻结玩法（time_scale = 0 + 占用一个 UI 模态）→ 弹 PrologueOverlay 结算层；
##   ⑦ 出口两个：返回关卡地图 / 再打一次。
##
## 测试钩子（Lead 的 tests/LevelSelectTest.gd 按名取）：
##   finished: bool / awarded_stars: int / hold_seconds: float / deaths: int
##   objectives() / raiders() / elapsed_seconds() / is_overlay_open()
## ============================================================================

const RAIDER_TOTAL: int = 4
const HOLD_RADIUS: float = 8.0            # 「收复主城」判定半径（米）
const PAR_SECONDS: float = 90.0           # 三星的用时门槛（秒）
const MIN_RAIDER_SPACING: float = 4.0     # 匪徒彼此最小间隔（防叠格出生）
const UI_REFRESH_INTERVAL: float = 0.1    # 计时器刷新节流（秒）
const SCRIPT_HOUR: int = 10               # 剧本时刻：上午十点

## 主角登场点：城外西北（距主城约 43m，隔着 4 只匪徒一路打进城）。
const START_POS := Vector3(-34.0, 0.0, 26.0)

## 4 只匪徒的固定锚点：登场点 → 城堡之间的一条斜线，全部落在城外（|x| > 14），
## 相邻间距 4.3~4.7m（≥4m 不叠格）。落点仍要过 snap_to_walkable + 二次分离。
const RAIDER_ANCHORS: Array[Vector3] = [
	Vector3(-21.0, 0.0, 17.0),
	Vector3(-18.5, 0.0, 13.5),
	Vector3(-16.5, 0.0, 9.5),
	Vector3(-15.0, 0.0, 5.0),
]

# ---- 测试钩子（公开状态，测试直接读）----
var finished: bool = false                # 是否已通关
var awarded_stars: int = 0                # 本次通关获得的星数（1~3）
var hold_seconds: float = 1.5             # 「收复主城」需要的停留时长
var deaths: int = 0                       # 本局主角阵亡次数

var _world_root: Node3D
var _main: Node
var _nav: NavSystem
var _spawner: Node                         # PawnSpawner（该脚本没有 class_name，按名取 + call）
var _hero: Hero
var _base: Node3D
var _stage: PrologueStage
var _overlay: PrologueOverlay

var _raiders: Array = []                  # 已刷出的 4 只（保持顺序）
var _killed: int = 0                      # 其中已阵亡的数量
var _elapsed: float = 0.0                 # 本局用时（游戏秒；暂停时不累加）
var _hold_time: float = 0.0               # 当前连续停留时长
var _kill_done: bool = false
var _hold_done: bool = false
var _ui_accum: float = 0.0
var _ui_dirty: bool = true
var _setup_done: bool = false
var _modal_expected: int = -1             # UI 模态占位的「期望计数」（-1 = 未占位）


## 完成广播（参数 = 星数）。
## 注意：`var finished: bool` 与同名 `signal finished` 在 GDScript 里是硬 Parse Error
## （实测：Variable "finished" has the same name as a previously declared signal），
## 而测试钩子 `finished` 必须是布尔量，故这里改用运行期 user signal：
## `director.connect(&"finished", cb)` / `get_signal_list()` 同样可见、可连、可发。
func _init() -> void:
	add_user_signal(&"finished", [{"name": "stars", "type": TYPE_INT}])
	set_process(false)                    # setup 完成前不推进剧本


# ---- 入口 ----

## Main.gd 在 add_child 之后调用；内部延迟初始化（等物理/导航就绪），全程安全。
func setup(world_root: Node3D, main: Node) -> void:
	_world_root = world_root
	_main = main
	# Main._ready() 末尾才调到本函数：此时世界树已就绪，但 NavSystem 的 A* 阻挡格
	# 与容器归属仍在收尾，故延后两帧物理再摆位/刷怪（测试会轮询等待）。
	_begin.call_deferred()


func _begin() -> void:
	if _setup_done:
		return
	if _world_root == null or not is_instance_valid(_world_root):
		push_warning("PrologueDirector: 未收到有效的 world_root，序章未启动")
		return
	_setup_done = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_nav = _world_root.get_node_or_null("NavSystem") as NavSystem
	_spawner = _world_root.get_node_or_null("PawnSpawner")
	_base = _world_root.get_node_or_null("BaseCore") as Node3D
	_hero = _find_hero()
	_suppress_sandbox()
	_setup_time()
	_setup_overlay()
	_place_hero()
	_spawn_raiders()
	_stage = PrologueStage.new()
	_stage.name = "PrologueStage"
	_world_root.add_child(_stage)
	_stage.setup(_world_root, _nav, _hero, _base)
	if not EventBus.hero_died.is_connected(_on_hero_died):
		EventBus.hero_died.connect(_on_hero_died)
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.set_objectives(objectives())
		_overlay.set_timer(0.0)
	_announce_opening()
	set_process(true)


func _find_hero() -> Hero:
	var controller := _world_root.get_node_or_null("HeroController")
	if controller != null:
		var ref = controller.get("hero")
		if ref is Hero and is_instance_valid(ref):
			return ref as Hero
	# 兜底：player_unit 组里除主角还有 BaseCore，必须按 Hero 类型筛
	for node in get_tree().get_nodes_in_group("player_unit"):
		if is_instance_valid(node) and node is Hero:
			return node as Hero
	return null


# ---- ① 压掉沙盒系统 ----

func _suppress_sandbox() -> void:
	# 野怪停刷：白天零散补刷与夜潮批次都挂在 _process 上
	var wildlife := _world_root.get_node_or_null("WildlifeSpawner") as WildlifeSpawner
	if wildlife != null:
		wildlife.set_process(false)
		wildlife.set_physics_process(false)
	# 流民停拉：SettlementSystem 只在 _process 里定期找空房刷人
	var settlement := _world_root.get_node_or_null("SettlementSystem") as SettlementSystem
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	# 建造禁用：先退出建造态（否则预览幽灵留在场上），再关 process 与 unhandled_input
	var build := _world_root.get_node_or_null("BuildSystem") as BuildSystem
	if build != null:
		if build.is_building:
			build.exit_build_mode()
		build.set_process(false)
		build.set_process_unhandled_input(false)
	# 新手引导：不自动开始、已在跑的静默中止；不写 user://tutorial.cfg
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null:
		tutorial.suppress_autostart()


# ---- ② 时间 ----

func _setup_time() -> void:
	TimeManager.begin(SCRIPT_HOUR)         # 上午十点：光照充足的白日舞台
	TimeManager.clock_frozen = true        # 只冻结昼夜时钟：不入夜 → 夜潮 / 攻城判定全部失效
	TimeManager.set_speed(1.0)             # 从暂停菜单 / 关卡地图进来可能残留 0 倍速


## 序章的昼夜时钟由剧本钉死（每帧兜底）。
## 为什么不能只在 _setup_time 里设一次：DayNightCycle 在昼夜切换时广播 night_changed(false)，
## WildlifeSpawner._dawn_cleanup() 收到就 TimeManager.unfreeze_clock()——场景刚起来那几个
## 0.1s 内（开场 hour 从 0/6 跳到 10）必然会触发一次，把序章冻好的时钟解冻。
## 正常帧这里只是读一个布尔量；只有被外部解冻的那一帧才重设。
func _keep_clock_pinned() -> void:
	if TimeManager.clock_frozen:
		return
	TimeManager.begin(SCRIPT_HOUR)
	TimeManager.clock_frozen = true


# ---- ③ 开场摆位 ----

func _place_hero() -> void:
	if _hero == null or not is_instance_valid(_hero):
		push_warning("PrologueDirector: 未找到主角，开场摆位跳过")
		return
	_hero.global_position = _snap(START_POS)   # 直写坐标必须先吸附，否则可能嵌进湖面/碰撞盒
	_hero.desired_velocity = Vector3.ZERO
	_face_camera_to_base()


## 让第三人称相机朝向主城（主角朝向由 HeroController 每帧写 aim_dir 跟随相机前方）。
## 注意：yaw 写完后 transform 下一渲染帧才应用，脚本化截图要跨 ≥2 帧。
func _face_camera_to_base() -> void:
	if _hero == null or _base == null:
		return
	var controller := _world_root.get_node_or_null("HeroController")
	if controller == null:
		return
	var cam = controller.get("camera")
	if cam == null or not is_instance_valid(cam) or not (cam is ThirdPersonCamera):
		return
	var dir := _base.global_position - _hero.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	# ThirdPersonCamera: global_rotation = (pitch, yaw, 0)，视线前方 = -Z
	# → (-sin(yaw), 0, -cos(yaw)) = dir  ⇒  yaw = atan2(-dir.x, -dir.z)
	(cam as ThirdPersonCamera).yaw = atan2(-dir.x, -dir.z)


# ---- ④ 匪徒 ----

func _spawn_raiders() -> void:
	if _spawner == null:
		push_warning("PrologueDirector: 缺少 PawnSpawner，匪徒未生成")
		return
	var pawn_def := _prologue_raider_def()
	var placed: Array[Vector3] = []
	for anchor in RAIDER_ANCHORS:
		var at := _separate(_snap(anchor), placed)
		placed.append(at)
		# PawnSpawner 是唯一的单位创建入口（内部会再吸附一次，幂等）
		var spawned = _spawner.call("spawn_raider", at, pawn_def)
		if not (spawned is Raider) or not is_instance_valid(spawned):
			push_warning("PrologueDirector: 匪徒生成失败，跳过锚点 %s" % at)
			continue
		var raider := spawned as Raider
		var guard := PrologueGuardState.new()
		guard.hero = _hero
		raider.state_machine.register_state("prologue_guard", guard)
		raider.state_machine.transition_to("prologue_guard")
		_raiders.append(raider)
		raider.health.died.connect(_on_raider_died)


## 序章匪徒：复制掠夺者 def 再削弱 —— 1 级主角（320 血 / 连招 16·18·34）能一对一打赢。
## 形象、数值集中在 GameDefs；驻守状态只在序章安装，不影响白天野怪与夜潮。
func _prologue_raider_def() -> PawnDef:
	return GameDefs.prologue_raider_def()


## 保证与已放置的匪徒间隔 ≥ MIN_RAIDER_SPACING：冲突时沿「远离主城」方向退 2m 再吸附。
func _separate(at: Vector3, placed: Array[Vector3]) -> Vector3:
	var away := at - (_base.global_position if _base != null else Vector3.ZERO)
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(0.0, 0.0, 1.0)
	away = away.normalized()
	var out := at
	for step in 8:
		var clear := true
		for other in placed:
			if out.distance_to(other) < MIN_RAIDER_SPACING:
				clear = false
				break
		if clear:
			break
		out = _snap(at + away * (2.0 * float(step + 1)))
	return out


func _snap(raw: Vector3) -> Vector3:
	if _nav == null:
		return raw
	return _nav.snap_to_walkable(raw)


# ---- ⑤ 目标链 ----

func objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({
		"id": &"clear_raiders",
		"text": "清剿城下匪徒",
		"have": _killed,
		"need": RAIDER_TOTAL,
		"done": _kill_done,
		"progress_text": "%d / %d" % [_killed, RAIDER_TOTAL],
	})
	out.append({
		"id": &"retake_base",
		"text": "重立王旗",
		"have": 1 if _hold_done else 0,
		"need": 1,
		"done": _hold_done,
		"progress_text": "王旗已立" if _hold_done else "城堡旁停留" if _kill_done else "先清剿匪徒",
	})
	return out


## 场上仍存活的匪徒实例（已释放的靠 is_instance_valid 过滤）。
func raiders() -> Array:
	var out: Array = []
	for raider in _raiders:
		if is_instance_valid(raider):
			out.append(raider)
	return out


func elapsed_seconds() -> float:
	return _elapsed


func is_overlay_open() -> bool:
	if _overlay == null or not is_instance_valid(_overlay):
		return false
	return _overlay.result_open


func _process(delta: float) -> void:
	_keep_clock_pinned()                   # 昼夜时钟钉死在上午十点（外部解冻即按回）
	if finished:
		return
	# 兜底：主城陷落 / 全局结束 → 剧情不再推进
	if GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	_elapsed += delta
	_update_objectives(delta)
	_refresh_hud(delta)


func _update_objectives(delta: float) -> void:
	# ① 清剿（死亡数在 _on_raider_died 里累加，这里只做状态收敛 + 播报）
	if not _kill_done and _killed >= RAIDER_TOTAL:
		_killed = RAIDER_TOTAL
		_kill_done = true
		_ui_dirty = true
		AudioManager.play_sfx(&"quest_done")
		EventBus.game_message.emit("城下的匪徒清空了。", Color(0.6, 1.0, 0.6))
	# ② 收复主城：主角在城堡 HOLD_RADIUS 内连续停留 hold_seconds（离开即清零）
	if not _hold_done and _kill_done:
		var in_range := false
		if _hero != null and is_instance_valid(_hero) and not _hero.is_dead_flag and _base != null:
			in_range = _hero.global_position.distance_to(_base.global_position) <= HOLD_RADIUS
		if in_range:
			_hold_time += delta
			if _hold_time >= hold_seconds:
				_hold_done = true
				_ui_dirty = true
				AudioManager.play_sfx(&"quest_done")
				EventBus.game_message.emit("王旗重新插上要塞。", UIStyle.GOLD)
		elif _hold_time > 0.0:
			_hold_time = 0.0
	# 清剿后完成连续占领 → 通关
	if _kill_done and _hold_done:
		_complete()


func _refresh_hud(delta: float) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _ui_dirty:
		_ui_dirty = false
		_overlay.refresh_objectives(objectives())
	_ui_accum += delta
	if _ui_accum >= UI_REFRESH_INTERVAL:
		_ui_accum = 0.0
		_overlay.set_timer(_elapsed)
		_overlay.set_capture(clampf(_hold_time / hold_seconds, 0, 1), _hold_time > 0, _kill_done)
		if _stage != null:
			_stage.update_state(raiders(), _kill_done, clampf(_hold_time / hold_seconds, 0, 1), finished)


func _on_raider_died() -> void:
	_killed += 1
	_ui_dirty = true


func _on_hero_died(_hero_node: Node) -> void:
	# 主角阵亡：走现有复活逻辑（Hero 自己处理），这里只记账 —— 丢的是「未阵亡」那颗星
	deaths += 1
	_ui_dirty = true


# ---- ⑥ 通关结算 ----

func _complete() -> void:
	if finished:
		return
	finished = true
	if _stage != null:
		_stage.update_state([], true, 1.0, true)
	awarded_stars = _compute_stars()
	LevelRuntime.record_result(LevelCatalog.PROLOGUE_ID, awarded_stars, true)
	AudioManager.play_sfx(&"level_up")
	EventBus.game_message.emit("序章完成！获得 %d 星。" % awarded_stars, UIStyle.GOLD)
	# 冻结玩法：时间停走 + 占用一个 UI 模态（鼠标交还玩家、相机与操控让位）
	_hold_ui_modal()
	TimeManager.set_speed(0.0)
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.refresh_objectives(objectives())
		_overlay.set_timer(_elapsed)
		_overlay.show_result(awarded_stars, _elapsed, deaths)
	emit_signal(&"finished", awarded_stars)


func _compute_stars() -> int:
	var stars := 1                          # 完成序章 = 1 星
	if deaths == 0:
		stars += 1                          # 全程未阵亡 +1 星
	if _elapsed <= PAR_SECONDS:
		stars += 1                          # 90 秒内完成 +1 星
	var level := LevelCatalog.prologue()
	return clampi(stars, 1, level.star_total if level != null else 3)


# ---- ⑦ 出口 ----

func _setup_overlay() -> void:
	_overlay = PrologueOverlay.new()
	_overlay.name = "PrologueOverlay"
	# 挂 Main 下（不是 WorldRoot 下）：结算层是 2D 浮层，测试按 Main/PrologueOverlay 取
	var host: Node = _main if _main != null and is_instance_valid(_main) else self
	host.add_child(_overlay)
	_overlay.map_requested.connect(_exit_to_level_select)
	_overlay.retry_requested.connect(_retry_prologue)
	_hide_sandbox_hud()


## 剧情关使用轻量目标与生命技能条，隐藏沙盒经营信息；暂停菜单和准星继续复用。
func _hide_sandbox_hud() -> void:
	for prop in ["quest_panel", "build_menu", "top_bar", "hero_panel", "minimap", "citizen_button", "event_log"]:
		var panel := _hud_child(prop)
		if panel != null:
			panel.visible = false


## 按属性名从 HUD（Main 下的 CanvasLayer）取面板：HUD 是纯代码建 UI，节点名不作契约。
func _hud_child(prop_name: String) -> Control:
	if _main == null or not is_instance_valid(_main):
		return null
	for child in _main.get_children():
		if not (child is CanvasLayer):
			continue
		var panel = child.get(prop_name)
		if panel is Control and is_instance_valid(panel):
			return panel as Control
	return null


func _exit_to_level_select() -> void:
	AudioManager.play_sfx(&"ui_click")
	_leave_cleanup()
	LevelRuntime.enter_level_select(LevelCatalog.LEVEL_SELECT_SCENE)


func _retry_prologue() -> void:
	AudioManager.play_sfx(&"ui_click")
	_leave_cleanup()
	get_tree().change_scene_to_file(LevelCatalog.MAIN_SCENE)


## 离开序章前的收尾：恢复倍速 + 归还 UI 模态占位。
func _leave_cleanup() -> void:
	TimeManager.set_speed(1.0)
	_release_ui_modal()


# ---- UI 模态占位（期望值比较式，绝不泄漏计数）----

func _hold_ui_modal() -> void:
	if _modal_expected >= 0:
		return                              # 已占位：重复调用不会重复 +1
	_modal_expected = SelectionManager.ui_modal_count + 1
	SelectionManager.ui_modal_count = _modal_expected


func _release_ui_modal() -> void:
	if _modal_expected < 0:
		return
	var expected := _modal_expected
	_modal_expected = -1
	# 期望值比较式：只有当前计数仍等于「本节点占位后的期望值」时，才整体写回占位前的值；
	# 期间别的模态也动过计数（说明它自己会归还）→ 退化为只减自己那一份，绝不回写陈旧快照。
	if SelectionManager.ui_modal_count == expected:
		SelectionManager.ui_modal_count = expected - 1
	else:
		SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)


# ---- 播报 ----

func _announce_opening() -> void:
	EventBus.game_message.emit("十年了……要塞的旗子换了颜色。", UIStyle.TEXT_MAIN)
