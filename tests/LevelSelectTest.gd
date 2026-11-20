extends Node
## ============================================================================
## v38 关卡系统回归（headless 可跑）：
##   godot --headless --path . tests/LevelSelectTest.tscn
##
## 阶段 A：关卡目录契约（五关、id 唯一、只有序章+测试关卡可玩、暂未开放无场景路径、
##         场景路径真实存在、芯片文案）。
## 阶段 B：主菜单入口（「测试关卡」按钮存在、开始游戏直入 Demo，关卡地图资源仍保留）。
## 阶段 C：关卡选择地图装配（必需节点齐全、节点按钮数 = 关卡数、暂未开放关不可进入、
##         可玩关可进入）。
## 阶段 D：真实切场景 → 进入序章：PrologueDirector 接管、沙盒系统被压掉、昼夜时钟冻结、
##         新手引导不自动开始；打死 4 名匪徒 → 目标①；主角走到城堡 → 通关结算 + 记星。
##
## 测试会写真实的 user://level_progress.cfg（通关记星），先备份、收尾原样还原。
## 任何路径都必须 quit（跑批靠退出码 + 日志判定）。
## ============================================================================

const MENU_SCENE := "res://scenes/main/MainMenu.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/main/LevelSelect3D.tscn"
const PROLOGUE_SCENE := "res://scenes/main/Main.tscn"
const PROGRESS_PATH := "user://level_progress.cfg"

var _failures: int = 0
var _had_progress: bool = false
var _progress_backup := PackedByteArray()


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_backup_progress()
	_check_catalog()
	_check_main_menu()
	await _check_level_select()
	await _enter_prologue()


# ---- 阶段 A：目录契约 ----

func _check_catalog() -> void:
	var levels := LevelCatalog.all()
	_check(levels.size() == 5, "关卡目录共 5 关（实际 %d）" % levels.size())

	var seen := {}
	for level in levels:
		_check(level.id != &"" and not seen.has(level.id), "关卡 id 唯一：%s" % level.id)
		seen[level.id] = true
		_check(level.title != "" and level.chapter != "", "关卡有章节与标题：%s" % level.id)
		if level.is_playable():
			_check(ResourceLoader.exists(level.scene_path),
				"可玩关卡的场景路径存在：%s → %s" % [level.id, level.scene_path])
		else:
			_check(level.scene_path == "", "不可进入的关卡不配场景路径：%s" % level.id)

	var prologue := LevelCatalog.prologue()
	_check(prologue != null and prologue.kind == LevelDef.Kind.PROLOGUE, "目录里有且仅有序章是 PROLOGUE")
	_check(prologue != null and prologue.is_playable() and prologue.scene_path == PROLOGUE_SCENE,
		"序章指向主世界场景（复用世界树跑剧本）")
	_check(prologue != null and prologue.objectives.size() >= 2 and prologue.star_total == 3,
		"序章有 2 条目标与 3 星上限")
	var sandbox := LevelCatalog.sandbox()
	_check(sandbox != null and sandbox.kind == LevelDef.Kind.SANDBOX and sandbox.is_playable(),
		"测试关卡（沙盒）可玩")
	_check(sandbox != null and sandbox.chip_text(0) == "测试", "沙盒关卡芯片显示「测试」而不是星数")
	_check(prologue != null and prologue.chip_text(0) == "0/3" and prologue.chip_text(9) == "3/3",
		"星数芯片按上限钳制（0/3 · 9→3/3）")

	var coming := 0
	for level in levels:
		if level.is_coming_soon():
			coming += 1
	_check(coming == 3, "后续 3 章标记为暂未开放（实际 %d）" % coming)


# ---- 阶段 B：主菜单入口 ----

func _check_main_menu() -> void:
	var menu: Control = load(MENU_SCENE).instantiate()
	add_child(menu)
	_check(menu.get_node_or_null("MenuFlow/ButtonBox/TestLevelButton") != null,
		"主菜单有「测试关卡」入口按钮")
	_check(menu.get_node_or_null("MenuFlow/ButtonBox/StartButton") != null,
		"主菜单保留「开始游戏」主按钮")
	_check(menu.LEVEL_SELECT_SCENE == LEVEL_SELECT_SCENE and ResourceLoader.exists(LEVEL_SELECT_SCENE),
		"暂时屏蔽的关卡地图资源仍存在")
	_check(menu.GAME_SCENE == PROLOGUE_SCENE, "开始游戏与测试关卡共用 Demo 主世界场景")
	menu.queue_free()


# ---- 阶段 C：关卡选择地图 ----

func _check_level_select() -> void:
	var screen: Node3D = load(LEVEL_SELECT_SCENE).instantiate()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	for node_path in ["TopBar", "TitleLabel", "TotalStarsLabel",
			"InfoPanel", "InfoChapterLabel", "InfoTitleLabel", "InfoSubtitleLabel", "InfoDescLabel",
			"ObjectivesBox", "StarHintsBox", "StarRow", "StartButton", "BackButton", "ToastLabel",
			"HintLabel"]:
		_check(_find(screen, node_path) != null, "关卡地图构建 %s" % node_path)
	_check(screen is Node3D, "关卡地图是 3D 场景（Node3D 根）")
	_check(not screen.find_children("*", "Camera3D", true, false).is_empty(), "3D 地图有相机")
	_check(not screen.find_children("*", "CanvasLayer", true, false).is_empty(),
		"3D 地图有覆盖 UI 层（CanvasLayer）")

	# 暂未开放：可选中查看，但不能进入
	screen.select_level(&"ch2")
	await get_tree().process_frame
	var start_button := _find(screen, "StartButton") as Button
	_check(start_button != null and start_button.disabled, "选中暂未开放的关卡 → 主按钮置灰")
	_check(screen.try_enter_selected() == false, "暂未开放的关卡拒绝进入（try_enter_selected=false）")
	_check(get_tree().current_scene != null and get_tree().current_scene.scene_file_path != LEVEL_SELECT_SCENE,
		"拒绝进入后没有发生场景切换")
	_check(LevelRuntime.enter_level(&"ch1") == false, "enter_level 对暂未开放的关卡同样拒绝")
	_check(LevelRuntime.selected_id != &"ch1", "拒绝的关卡不会被写进会话选择")

	# 可玩关：按钮可点
	screen.select_level(LevelCatalog.PROLOGUE_ID)
	await get_tree().process_frame
	_check(start_button != null and not start_button.disabled, "选中序章 → 主按钮可点")
	_check(_find(screen, "BackButton") as Button != null, "关卡地图有返回主页按钮")

	_check(LevelRuntime.select(&"nosuchlevel") == false, "目录里不存在的关卡 id 无法选中")

	# 3D 地图：每关都要在场景里有真实世界坐标的旗子；角色要能走到序章旗旁自动选中
	for level in LevelCatalog.all():
		var at: Vector3 = screen.call("flag_world_position", level.id)
		_check(absf(at.x) > 0.001 or absf(at.z) > 0.001, "关卡 %s 在地图上有旗子世界坐标 %s" % [level.id, at])
	if screen.has_method("teleport_player") and screen.has_method("flag_world_position"):
		screen.call("teleport_player", screen.call("flag_world_position", LevelCatalog.PROLOGUE_ID))
		for _i in 20:
			await get_tree().process_frame
		_check(screen.selected_id == LevelCatalog.PROLOGUE_ID, "角色走到序章旗旁 → 自动选中序章")
		var hint := _find(screen, "HintLabel") as Label
		_check(hint != null and hint.text.contains("E"), "旗旁提示条给出「按 E 进入关卡」（实际：%s）"
			% (hint.text if hint != null else "<无 HintLabel>"))
	else:
		_check(false, "3D 关卡地图提供 teleport_player / flag_world_position 测试钩子")

	# 远岛点击必须沿路绕行，途中不得穿过虚空（回归原直线走位会卡岛缘的问题）。
	for destination in [&"ch1", &"ch2", &"ch3", LevelCatalog.PROLOGUE_ID]:
		var target: Vector3 = screen.call("flag_world_position", destination)
		screen.call("walk_to", target)
		var arrived := false
		var safe := true
		for _frame in 1600:
			await get_tree().process_frame
			var position: Vector3 = screen.get("player_position")
			if safe and not bool(screen.call("is_walkable_point", position)):
				print("越界位置：", position, " 目标：", destination)
				safe = false
			if position.distance_to(target) < 0.4:
				arrived = true
				break
		_check(arrived and safe, "跨岛前往 %s：抵达=%s 安全=%s 距离=%.2f 路点=%s" % [destination, arrived, safe, (screen.get("player_position") as Vector3).distance_to(target), screen.get("_move_target")])

	for far_point in [Vector3(-500, 0, -500), Vector3(500, 0, 500)]:
		screen.call("walk_to", far_point)
		var route: PackedVector2Array = screen.get("_walk_path")
		_check(not route.is_empty(), "点击地图外空白区域仍能吸附到可走终点，不请求越界 A* 格子")

	screen.queue_free()
	await get_tree().process_frame


## 兼容两种装配：根节点直接子节点，或包在 CanvasLayer 里（3D 关卡地图的覆盖 UI）。
func _find(root: Node, node_name: String) -> Node:
	var direct := root.get_node_or_null(node_name)
	if direct != null:
		return direct
	return root.find_child(node_name, true, false)


# ---- 阶段 D：真实进入序章（切场景后由 Watcher 接管断言）----

func _enter_prologue() -> void:
	_check(LevelRuntime.select(LevelCatalog.PROLOGUE_ID), "选中序章成功")
	var watcher := Watcher.new()
	watcher.test = self
	watcher.base_failures = _failures
	watcher.had_progress = _had_progress
	watcher.progress_backup = _progress_backup
	get_tree().root.add_child(watcher)
	var started := LevelRuntime.enter_level(LevelCatalog.PROLOGUE_ID)
	_check(started, "enter_level 进入序章返回 true")
	# 场景切换后本测试节点被销毁，剩余断言全部由 Watcher 接管


## 观察者：不在 current_scene 子树下，change_scene_to_file 不会销毁它。
class Watcher extends Node:
	var test: Node
	var base_failures: int = 0
	var had_progress: bool = false
	var progress_backup := PackedByteArray()
	var _failures: int = 0
	var _frames: int = 0
	var _started: bool = false

	func _check(condition: bool, message: String) -> void:
		if condition:
			print("PASS: ", message)
		else:
			_failures += 1
			push_error("FAIL: " + message)

	func _process(_delta: float) -> void:
		if _started:
			return
		_frames += 1
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://scenes/main/Main.tscn":
			_started = true
			_run.call_deferred()
		elif _frames > 1500:
			_started = true
			_check(false, "场景切换进入序章从未完成（超时）")
			_finish()

	func _run() -> void:
		var tree := get_tree()
		var main := tree.current_scene
		_check(main != null and main.get_node_or_null("WorldRoot") != null, "序章世界树已加载")

		# 等待 PrologueDirector 完成 setup（它可能延迟若干帧）
		var director: Node = null
		var waited := 0
		while waited < 240:
			director = main.get_node_or_null("WorldRoot/PrologueDirector")
			if director != null and director.get("finished") != null:
				break
			await tree.process_frame
			waited += 1
		_check(director != null, "序章由 PrologueDirector 接管（节点存在）")
		if director == null:
			_finish()
			return
		# setup 内部有延迟初始化（刷怪要等导航/物理就绪）：等世界被真正切成剧情关舞台
		var settle := 0
		while int(director.call("raiders").size()) < 4 and settle < 240:
			await tree.process_frame
			settle += 1
		for _i in 10:
			await tree.process_frame

		# 世界被切成剧情关舞台
		var world := main.get_node("WorldRoot")
		var wildlife := world.get_node_or_null("WildlifeSpawner")
		var settlement := world.get_node_or_null("SettlementSystem")
		var build := world.get_node_or_null("BuildSystem")
		_check(wildlife != null and not wildlife.is_processing(), "序章里野怪刷新器被停掉（不刷怪）")
		_check(settlement != null and not settlement.is_processing(), "序章里流民系统被停掉（不拉人）")
		_check(build != null and not build.is_processing(), "序章里建造系统被停掉（不能建房）")
		_check(TimeManager.clock_frozen, "序章冻结昼夜时钟（天色钉在白天、不触发夜潮）")
		var tutorial := world.get_node_or_null("TutorialSystem") as TutorialSystem
		_check(tutorial != null and tutorial.state != TutorialSystem.State.RUNNING,
			"序章不叠加沙盒新手引导")

		# 剧情守卫原地驻守；绕过敌人到城堡不能预先占城。
		var stage := world.get_node_or_null("PrologueStage")
		_check(stage != null, "序章独立表现层装配完成")
		_check(SelectionManager.view_mode == SelectionManager.ViewMode.TOPDOWN, "序章默认俯视主控")
		var test_hero: Hero = null
		for unit in tree.get_nodes_in_group("player_unit"):
			if is_instance_valid(unit) and unit is Hero:
				test_hero = unit as Hero
		var level_nav := world.get_node_or_null("NavSystem") as NavSystem
		if test_hero != null and level_nav != null:
			var original := test_hero.global_position
			test_hero.global_position = level_nav.snap_to_walkable(Vector3(5, 0, 5))
			for _frame in 110:
				await tree.physics_frame
			_check(not bool(director.call("objectives")[1]["done"]), "未清剿匪徒时，提前靠近城堡不能重立王旗")
			test_hero.global_position = original

		# 目标①：清剿 4 名匪徒
		var raiders: Array = director.call("raiders")
		_check(raiders.size() == 4, "序章刷出 4 名匪徒（实际 %d）" % raiders.size())
		var objectives: Array = director.call("objectives")
		_check(objectives.size() == 2, "序章有 2 条目标")
		for r in raiders:
			if not is_instance_valid(r):
				continue
			var hp := (r as Node).get_node_or_null("HealthComponent")
			if hp != null:
				hp.call("apply_damage", 9999.0, null)
		for _i in 40:
			await tree.process_frame
		objectives = director.call("objectives")
		_check(objectives.size() == 2 and bool(objectives[0]["done"]),
			"打死 4 名匪徒 → 目标①达成")

		# 目标②：主角走到城堡 8m 内并停留 hold_seconds
		var nav := world.get_node_or_null("NavSystem")
		var hero: Node = null
		for n in tree.get_nodes_in_group("player_unit"):
			if n is Hero:
				hero = n
				break
		_check(hero != null, "序章里主角在场")
		if hero != null and nav != null:
			(hero as Node3D).global_position = nav.call("snap_to_walkable", Vector3(5.0, 0.0, 5.0))
		var hold: float = float(director.get("hold_seconds"))
		await tree.create_timer(hold + 1.5, true, false, true).timeout

		_check(bool(director.get("finished")), "走到城堡 → 序章通关")
		_check(int(director.get("awarded_stars")) >= 1, "通关至少记 1 星（实际 %d）" % int(director.get("awarded_stars")))
		_check(int(director.get("deaths")) == 0, "测试里主角未阵亡")
		_check(bool(director.call("is_overlay_open")), "通关后弹出序章结算层")
		_check(LevelRuntime.is_cleared(LevelCatalog.PROLOGUE_ID), "通关记录写入进度（is_cleared）")
		_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) >= 1, "进度里有星数记录")

		var overlay: Node = main.get_node_or_null("PrologueOverlay")
		if overlay == null:
			overlay = tree.get_first_node_in_group("prologue_overlay")
		if overlay != null:
			for node_path in ["ObjectivePanel", "ObjectiveList", "TimerLabel", "ResultLayer",
					"ResultTitle", "ResultStars", "ResultStats", "MapButton", "RetryButton"]:
				_check(overlay.get_node_or_null(node_path) != null, "序章 HUD 构建 %s" % node_path)
		else:
			_check(false, "序章 HUD（PrologueOverlay）随场景挂载")

		_restore_progress()
		_finish()

	## 还原真实进度存档（测试会真的通关记星，不能污染玩家进度）。
	func _restore_progress() -> void:
		var global_path := ProjectSettings.globalize_path(PROGRESS_PATH)
		if had_progress:
			var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(progress_backup)
				f.close()
		else:
			DirAccess.remove_absolute(global_path)
		LevelRuntime.clear_selection()
		LevelRuntime.reload_progress()
		TimeManager.set_speed(1.0)
		TimeManager.clock_frozen = false
		SelectionManager.ui_modal_count = 0

	func _finish() -> void:
		var total: int = base_failures + _failures
		print("LEVEL SYSTEM: %d failure(s)" % total)
		get_tree().quit(0 if total == 0 else 1)


# ---- 进度存档备份 ----

func _backup_progress() -> void:
	_had_progress = FileAccess.file_exists(PROGRESS_PATH)
	if _had_progress:
		_progress_backup = FileAccess.get_file_as_bytes(PROGRESS_PATH)
