extends Node
## 长时浸泡测试：加速跑主场景 N 个游戏日夜，收集脚本错误与终局状态。
## godot --headless --path . tests/SoakTest.tscn --fixed-fps 60
## 可调环境变量（可选）：SOAK_SECONDS（真实秒，默认 150）

const REAL_SECONDS: float = 150.0
const GAME_SPEED: float = 5.0

var _main: Node
var _elapsed: float = 0.0
var _errors: int = 0
var _frames: int = 0
var _settle_pick: int = 0   # v25 入住职业选择：浸泡模拟玩家轮换点选职业


## v25 流民入住职业选择：弹窗会暂停等玩家点选——浸泡测试模拟玩家自动选职业
## （否则入住流程停在弹窗，房屋永远等不到居民）。
func _on_soak_settle_choice(_refugee: Node, _house: Node) -> void:
	var picker := get_tree().get_first_node_in_group("settle_class_picker")
	if picker == null or not picker.get("is_open"):
		return
	var classes: Array = GameDefs.settler_def_ids()
	picker.call("_choose", classes[_settle_pick % classes.size()])
	_settle_pick += 1


## v31 守城准备：浸泡模拟玩家短暂布防后按下「准备守城」（否则昼夜时钟停在
## 入夜时刻，多日浸泡退化为无限长夜）。延时用真实秒（不受游戏倍速影响）。
func _on_soak_night_prep() -> void:
	await get_tree().create_timer(1.5, true, false, true).timeout
	if TimeManager.clock_frozen and GameManager.phase != GameManager.Phase.GAME_OVER:
		GameManager.request_night_defense()


func _ready() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	EventBus.settle_class_choice_required.connect(_on_soak_settle_choice)
	EventBus.night_prep_started.connect(_on_soak_night_prep)
	TimeManager.set_speed(GAME_SPEED)
	# 给玩家一点起步资源，让经济系统自然运转（造房→流民→村民→募兵）
	ResourceManager.add(GameDefs.WOOD, 400)
	ResourceManager.add(GameDefs.STONE, 250)
	ResourceManager.add(GameDefs.FOOD, 200)
	ResourceManager.add(GameDefs.GOLD, 200)
	_auto_build()
	# 监听脚本错误（push_error 计数）
	# 注：headless 下 SCRIPT ERROR 走 stderr；此处主要靠退出码与日志。
	print("[soak] start: %.0f real s @ %.0fx ≈ %.1f game days" % [
		REAL_SECONDS, GAME_SPEED, REAL_SECONDS * GAME_SPEED / TimeManager.seconds_per_day])


func _auto_build() -> void:
	# 模拟玩家：造 4 房 + 1 酒馆 + 2 段墙（v22 起无农田/市集/箭塔，小兵靠定居、低血回酒馆）
	var build := _main.get_node("WorldRoot/BuildSystem") as BuildSystem
	var defs := {}
	for d in GameDefs.building_defs():
		defs[d.id] = d
	var plan := [
		[&"house", Vector3(10.4, 0, 10.4)], [&"house", Vector3(14.4, 0, 10.4)],
		[&"house", Vector3(-10.4, 0, 10.4)], [&"house", Vector3(-14.4, 0, 10.4)],
		[&"tavern", Vector3(6.4, 0, -10.4)],
		[&"wall", Vector3(20.0, 0, 6.0)], [&"wall", Vector3(-20.0, 0, -6.0)],
	]
	for entry in plan:
		build.enter_build_mode(defs[entry[0]])
		build.try_place_at(entry[1])
		await get_tree().physics_frame
	build.exit_build_mode()
	print("[soak] auto-build done: houses/tavern/walls placed")


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	# 游戏结束出口：主城被攻破时游戏会暂停且不再恢复——浸泡的目的是稳定性
	# （无崩溃 / 节点数），不是平衡断言；记录终局状态后干净退出，防挂死到跑批超时。
	if GameManager.phase == GameManager.Phase.GAME_OVER:
		print("[soak] GAME OVER at day=%d %02d:00 (t=%.0fs) — sandbox outcome, stability metrics above stand"
			% [TimeManager.day, TimeManager.hour, _elapsed])
		print("SOAK DONE")
		get_tree().quit(0)
	# 模拟玩家：任何原因的暂停（入驻确认等）都自动点「继续」
	if TimeManager.time_scale <= 0.0 and GameManager.phase != GameManager.Phase.GAME_OVER:
		TimeManager.set_speed(GAME_SPEED)
	if _frames % 600 == 0:
		print("[soak] t=%.0fs day=%d %02d:00 nodes=%d enemies=%d speed=%.1f" % [
			_elapsed, TimeManager.day, TimeManager.hour,
			get_tree().get_node_count(),
			get_tree().get_nodes_in_group("enemy").size(),
			TimeManager.time_scale])
	if _elapsed < REAL_SECONDS:
		return
	# 终局状态采样
	var villagers := 0
	var soldiers := 0
	var enemies := 0
	var buildings := 0
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Colonist:
			villagers += 1
		elif n is Soldier:
			soldiers += 1
	for _e in get_tree().get_nodes_in_group("enemy"):
		enemies += 1
	for _b in get_tree().get_nodes_in_group("building"):
		buildings += 1
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
	print("[soak] %d game days elapsed" % TimeManager.day)
	print("[soak] villagers=%d soldiers=%d enemies=%d buildings=%d" % [villagers, soldiers, enemies, buildings])
	if hero != null:
		print("[soak] hero Lv.%d xp=%d kills=%d base_hp=%d" % [hero.level, hero.xp, hero.kill_count, GameManager.player_base_health])
	var quests := _main.get_node_or_null("WorldRoot/QuestSystem") as QuestSystem
	if quests != null:
		print("[soak] quest step %d / %d" % [quests.current_index + 1, quests.quests.size()])
	print("[soak] node count: %d" % get_tree().get_node_count())
	print("SOAK DONE")
	get_tree().quit(0)
