extends Node
## ============================================================================
## v38 序章专项探针（PrologueDirector + PrologueOverlay 自验收）：
##   headless（只看断言）：
##     bash tools/godot_locked.sh --headless --path . tools/v38_prologue_probe.tscn \
##         --fixed-fps 60 --log-file /tmp/v38-prologue-probe.log
##   带窗口（额外落两张截图）：
##     bash tools/godot_locked.sh --path . tools/v38_prologue_probe.tscn --fixed-fps 60
##
## 探测链（与 Lead 的 tests/LevelSelectTest.gd 同口径，这里只做「把 Main 当子节点」
## 的快速自检，不切场景）：
##   1. WorldRoot/PrologueDirector 存在且 objectives().size() == 2；
##   2. raiders().size() == 4（已死的不计，初始 4）；
##   3. WildlifeSpawner / SettlementSystem / BuildSystem 都不再 process；clock_frozen；
##   4. 逐只打死 4 名匪徒 → 目标①done；
##   5. 主角传送到城堡旁（先 snap_to_walkable）→ 停留 hold_seconds → finished + 星数；
##   6. LevelRuntime 进度里有星数 / 通关标记（收尾按备份还原，不污染真实进度）；
##   7. 结算层已弹出（is_overlay_open）。
##
## 任何路径都会 get_tree().quit(0/1)：解析错误以外的死循环不存在，跑批不会挂死。
## ============================================================================

const PROGRESS_PATH := "user://level_progress.cfg"
const START_POS := Vector3(-34.0, 0.0, 26.0)     # 与 PrologueDirector.START_POS 同值

var _failures: int = 0
var _main: Node
var _world: Node3D
var _director: Node
var _visual: bool = false
var _had_progress: bool = false
var _backup := PackedByteArray()


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_visual = DisplayServer.get_name() != "headless"
	_backup_progress()
	if _visual:
		get_window().size = Vector2i(1600, 900)
	else:
		print("headless: 跳过截图（只跑断言）")

	_check(LevelRuntime.select(LevelCatalog.PROLOGUE_ID), "LevelRuntime.select(prologue) 成功")
	_check(LevelRuntime.current_level().kind == LevelDef.Kind.PROLOGUE,
		"current_level() = 序章（Main 会走 PrologueDirector 分支）")

	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	_world = _main.get_node_or_null("WorldRoot") as Node3D
	_check(_world != null, "Main.tscn 世界树加载成功")
	if _world == null:
		_finish()
		return

	# ---- 1. PrologueDirector 接管（延迟初始化：轮询等待刷怪完成）----
	# 出生坐标在「第一次看到 4 只」的那一帧就记下来：之后怪会按 AI 游荡，
	# 间距断言必须用出生位（否则跑几帧就可能量到 3.8m 的假失败）。
	var waited := 0
	var spawn_positions: Array[Vector3] = []
	while waited < 300:
		_director = _main.get_node_or_null("WorldRoot/PrologueDirector")
		if _director != null:
			var live: Array = _director.call("raiders")
			if live.size() >= 4:
				for r in live:
					spawn_positions.append((r as Node3D).global_position)
				break
		await get_tree().process_frame
		waited += 1
	_check(_director != null, "WorldRoot/PrologueDirector 存在（序章由剧本驱动器接管）")
	if _director == null:
		_finish()
		return
	await _wait_process_frames(10)
	var objectives: Array = _director.call("objectives")
	_check(objectives.size() == 2, "objectives().size() == 2（实际 %d）" % objectives.size())
	_check(_check_objective_fields(objectives), "两条目标都带 id/text/have/need/done 五个字段")

	# ---- 开场视角截图（带窗口时）+ 主角落点自检 ----
	var hero := _find_hero()
	_check(hero != null, "主角在场（player_unit 组里按 Hero 类型筛）")
	if hero != null:
		var d_start: float = (hero as Node3D).global_position.distance_to(START_POS)
		_check(d_start <= 4.0, "主角在城外登场点就位（距锚点 %.2fm，吸附后允许 ≤4m）" % d_start)
		print("hero_pos=", (hero as Node3D).global_position)
	if _visual:
		await _snap("v38-prologue-start")

	# ---- 2. 4 名匪徒 ----
	var raiders: Array = _director.call("raiders")
	_check(raiders.size() == 4, "raiders().size() == 4（实际 %d）" % raiders.size())
	var spawn_gap := _min_pair_distance(spawn_positions)
	_check(spawn_positions.size() == 4 and spawn_gap >= 4.0,
		"4 名匪徒出生间隔 ≥4m（实测最小 %.2fm，不叠格）" % spawn_gap)
	for pos in spawn_positions:
		print("raider_spawn=", pos)

	# ---- 3. 沙盒系统被压掉 + 昼夜冻结 ----
	var wildlife := _world.get_node_or_null("WildlifeSpawner")
	var settlement := _world.get_node_or_null("SettlementSystem")
	var build := _world.get_node_or_null("BuildSystem")
	_check(wildlife != null and not wildlife.is_processing(), "WildlifeSpawner 停刷（is_processing=false）")
	_check(settlement != null and not settlement.is_processing(), "SettlementSystem 停拉流民（is_processing=false）")
	_check(build != null and not build.is_processing(), "BuildSystem 禁建造（is_processing=false）")
	_check(TimeManager.clock_frozen, "TimeManager.clock_frozen == true（不推进昼夜、不触发夜潮）")
	_check(TimeManager.hour == 10, "序章钉在上午十点（实际 %d 点）" % TimeManager.hour)
	var tutorial := _world.get_node_or_null("TutorialSystem") as TutorialSystem
	_check(tutorial != null and tutorial.state != TutorialSystem.State.RUNNING,
		"新手引导没有自动开始（suppress_autostart 生效）")
	var quest_card := _hud_panel("quest_panel")
	var build_bar := _hud_panel("build_menu")
	_check(quest_card != null and not quest_card.visible, "沙盒任务卡被藏起（避免与序章目标卡叠字）")
	_check(build_bar != null and not build_bar.visible, "沙盒建造条被藏起（建造已禁用）")

	# ---- 4. 清剿 4 名匪徒 → 目标①----
	var killed := 0
	for r in raiders:
		if not is_instance_valid(r):
			continue
		var hp := (r as Node).get_node_or_null("HealthComponent")
		if hp != null:
			hp.call("apply_damage", 9999.0, null)
			killed += 1
	_check(killed == 4, "对 4 名匪徒的 HealthComponent 施加致死伤害（%d 只）" % killed)
	await _wait_process_frames(40)
	objectives = _director.call("objectives")
	_check(bool(objectives[0]["done"]), "目标① 清剿匪徒 done == true（have=%d/need=%d）" % [
		int(objectives[0]["have"]), int(objectives[0]["need"])])
	_check(int(objectives[0]["have"]) == 4, "击杀计数 have == 4（进度文案：%s）" % String(objectives[0]["progress_text"]))
	_check(not bool(objectives[1]["done"]), "目标② 收复主城此刻仍未完成（顺序推进：还没进城堡）")
	_check(not bool(_director.get("finished")), "只清完匪徒还不算通关（finished 仍为 false）")

	# ---- 5. 主角进城堡 8m 内停留 hold_seconds → 通关 ----
	var nav := _world.get_node_or_null("NavSystem")
	var base_node := _world.get_node_or_null("BaseCore") as Node3D
	_check(nav != null and base_node != null, "NavSystem / BaseCore 都在场")
	if hero == null or nav == null or base_node == null:
		_finish()
		return
	var target: Vector3 = nav.call("snap_to_walkable", Vector3(5.0, 0.0, 5.0))
	(hero as Node3D).global_position = target
	var in_range: float = target.distance_to(base_node.global_position)
	_check(in_range <= 8.0, "传送点落在「城堡 8m 内」（实际 %.2fm）" % in_range)
	var hold: float = float(_director.get("hold_seconds"))
	print("hold_seconds=", hold, " target=", target)
	await get_tree().create_timer(hold * 0.5, true, false, true).timeout
	objectives = _director.call("objectives")
	_check(not bool(_director.get("finished")), "停留未满 %.1fs 时不提前通关（%.1fs 时仍为 false）" % [hold, hold * 0.5])
	await get_tree().create_timer(hold * 0.5 + 1.5, true, false, true).timeout
	_check(bool(_director.get("finished")), "停留满 hold_seconds → finished == true")
	_check(int(_director.get("awarded_stars")) >= 1,
		"awarded_stars >= 1（实际 %d：完成 1 + 未阵亡 1 + %.0fs 内完成 1）" % [
			int(_director.get("awarded_stars")), float(_director.call("elapsed_seconds"))])
	_check(int(_director.get("deaths")) == 0, "deaths == 0（探针里主角没有阵亡）")
	_check(float(_director.call("elapsed_seconds")) <= 90.0,
		"elapsed_seconds() = %.2f ≤ 90（拿到速度星）" % float(_director.call("elapsed_seconds")))
	objectives = _director.call("objectives")
	_check(bool(objectives[1]["done"]), "目标② 收复主城 done == true（文案：%s）" % String(objectives[1]["progress_text"]))

	# ---- 6. 进度落盘（收尾还原）----
	_check(int(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID)) >= 1,
		"LevelRuntime.stars_of(prologue) >= 1（实际 %d）" % LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID))
	_check(LevelRuntime.is_cleared(LevelCatalog.PROLOGUE_ID), "LevelRuntime.is_cleared(prologue) == true")

	# ---- 7. 结算层 + 冻结玩法 ----
	_check(bool(_director.call("is_overlay_open")), "is_overlay_open() == true（结算层已弹）")
	_check(TimeManager.time_scale <= 0.0, "通关后冻结玩法（time_scale = %.1f）" % TimeManager.time_scale)
	_check(SelectionManager.ui_modal_count >= 1,
		"通关占用 UI 模态（ui_modal_count = %d）" % SelectionManager.ui_modal_count)
	var overlay := _main.get_node_or_null("PrologueOverlay")
	_check(overlay != null, "Main/PrologueOverlay 随场景挂载")
	if overlay != null:
		for node_name in ["ObjectivePanel", "ObjectiveList", "TimerLabel", "ResultLayer",
				"ResultTitle", "ResultStars", "ResultStats", "MapButton", "RetryButton"]:
			_check(overlay.get_node_or_null(node_name) != null, "序章 HUD 节点存在：%s" % node_name)
		var result_title := overlay.get_node_or_null("ResultTitle") as Label
		var result_stars := overlay.get_node_or_null("ResultStars") as Label
		var result_stats := overlay.get_node_or_null("ResultStats") as Label
		var timer_label := overlay.get_node_or_null("TimerLabel") as Label
		_check(result_title != null and result_title.text == "序 章 完 成",
			"结算标题文本：%s" % (result_title.text if result_title != null else "<缺失>"))
		_check(result_stars != null and result_stars.text.count("★") == int(_director.get("awarded_stars")),
			"星格文本：%s" % (result_stars.text if result_stars != null else "<缺失>"))
		_check(result_stats != null and result_stats.text.contains("阵亡"),
			"战绩文本：%s" % (result_stats.text if result_stats != null else "<缺失>"))
		_check(timer_label != null and timer_label.text.contains("秒"),
			"目标卡计时文本：%s" % (timer_label.text if timer_label != null else "<缺失>"))

	# ---- 结算层截图（带窗口时）----
	if _visual:
		await _snap("v38-prologue-result")

	# ---- 附加：阵亡记账（需求 7）----
	# 通关后再把主角打倒：只验「阵亡会记一次、不会推翻已完成的结算」，
	# 复活链路本身是 Hero 既有逻辑（respawn_delay 5s，冻结中不推进）。
	var hero_hp := (hero as Node).get_node_or_null("HealthComponent")
	if hero_hp != null:
		hero_hp.call("apply_damage", 99999.0, null)
		await _wait_process_frames(5)
		_check(int(_director.get("deaths")) == 1, "主角阵亡记一次（deaths = %d）" % int(_director.get("deaths")))
		_check(bool(_director.call("is_overlay_open")), "阵亡不会推翻已弹出的结算层")

	_finish()


# ---- 收尾 ----

func _finish() -> void:
	_restore_progress()
	print("PROLOGUE PROBE: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _backup_progress() -> void:
	_had_progress = FileAccess.file_exists(PROGRESS_PATH)
	if _had_progress:
		_backup = FileAccess.get_file_as_bytes(PROGRESS_PATH)


## 还原真实进度存档（探针会真的通关记星，不能污染玩家进度）。
func _restore_progress() -> void:
	if _had_progress:
		var file := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	LevelRuntime.reload_progress()
	LevelRuntime.clear_selection()
	TimeManager.set_speed(1.0)
	TimeManager.clock_frozen = false
	SelectionManager.ui_modal_count = 0


# ---- 辅助 ----

func _find_hero() -> Node:
	for node in get_tree().get_nodes_in_group("player_unit"):
		if is_instance_valid(node) and node is Hero:
			return node
	return null


## 从 HUD（Main 下的 CanvasLayer）按属性名取面板（HUD 是代码建 UI，节点名不作契约）。
func _hud_panel(prop_name: String) -> Control:
	for child in _main.get_children():
		if not (child is CanvasLayer):
			continue
		var panel = child.get(prop_name)
		if panel is Control and is_instance_valid(panel):
			return panel as Control
	return null


func _check_objective_fields(list: Array) -> bool:
	for item in list:
		if not (item is Dictionary):
			return false
		var dict := item as Dictionary
		for key in ["id", "text", "have", "need", "done"]:
			if not dict.has(key):
				return false
	return true


func _min_pair_distance(points: Array[Vector3]) -> float:
	var smallest := INF
	for i in points.size():
		for j in range(i + 1, points.size()):
			smallest = minf(smallest, points[i].distance_to(points[j]))
	return 0.0 if smallest == INF else smallest


func _wait_process_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


## 截图（照抄 tools/bubble_shot.gd 惯例）：先等渲染链路收敛再抓帧。
func _snap(png_name: String) -> void:
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % png_name)
	print("saved artifacts/%s.png" % png_name)
