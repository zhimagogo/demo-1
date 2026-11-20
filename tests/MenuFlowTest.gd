extends Node
## ============================================================================
## 主菜单全链路回归（headless 可跑）：
##   godot --headless --path . tests/MenuFlowTest.tscn
##
## 阶段 A：主菜单装配（按钮/设置浮层）、设置面板交互、GameSettings 临时文件
##         round-trip 与 Master 总线应用、主菜单 Esc 收设置浮层。
## 阶段 B：真实 change_scene_to_file 进入 Main 对局——测试节点本身会被场景切换
##         销毁，因此先在 /root 下挂一个观察者节点存活过切换，在新场景里验证：
##         主按钮直入 Demo、首次首杀真实刷怪与击杀推进、夜间教学保护、Esc 优先级与返回。
## 测试会写 GameSettings 的真实存档路径（改即保存），先备份、收尾原样还原。
## ============================================================================

const MENU_SCENE_PATH := "res://scenes/main/MainMenu.tscn"
const GAME_SCENE_PATH := "res://scenes/main/Main.tscn"
const TUTORIAL_PATH := "user://tutorial.cfg"
const TMP_SETTINGS := "user://test_settings_tmp.cfg"

var _failures: int = 0
var _menu: Control


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	# ---- 入口契约：主场景必须是主菜单 ----
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	_check(main_scene == MENU_SCENE_PATH, "project main scene is MainMenu")

	# ---- 主菜单装配 ----
	_menu = load(MENU_SCENE_PATH).instantiate()
	add_child(_menu)
	await get_tree().process_frame
	await get_tree().process_frame
	for node_path in ["MenuFlow/ButtonBox/StartButton", "MenuFlow/ButtonBox/SettingsButton",
			"MenuFlow/ButtonBox/QuitButton", "SettingsLayer", "MenuFlow/TitleBox/GameTitle"]:
		_check(_menu.get_node_or_null(node_path) != null, "menu builds %s" % node_path)
	_check(_menu.start_button.get_signal_connection_list("pressed").size() >= 1, "start button wired to handler")
	_check(_menu.GAME_SCENE == GAME_SCENE_PATH, "start goes to Main scene")
	_check(not _menu.settings_layer.visible, "settings layer hidden initially")
	# 流式布局防重叠回归（历史 bug：双锚点布局在不同分辨率/字体行高下标题与按钮重合）：
	# 标题组与按钮组同处一个 VBox 流，任意画布尺寸下按钮组顶沿必须低于标题组底沿 ≥30px
	var title_box: Control = _menu.get_node_or_null("MenuFlow/TitleBox")
	var button_box: Control = _menu.get_node_or_null("MenuFlow/ButtonBox")
	if title_box == null or button_box == null:
		_check(false, "menu flow containers present")
	else:
		_check(button_box.global_position.y - (title_box.global_position.y + title_box.size.y) >= 30.0,
			"menu flow layout keeps >=30px gap between title block and buttons")

	# ---- 设置浮层：开 → Esc 收起 ----
	_menu._open_settings()
	await get_tree().process_frame
	_check(_menu.settings_layer.visible, "settings opens from main menu")
	var esc := InputEventAction.new()
	esc.action = "cancel"
	esc.pressed = true
	_menu._unhandled_input(esc)
	_check(not _menu.settings_layer.visible, "Esc collapses settings layer on main menu")

	# ---- GameSettings：备份真实存档 → 临时文件 round-trip → 应用链路 → 还原 ----
	var real_path: String = GameSettings.SETTINGS_PATH
	var had_save := FileAccess.file_exists(real_path)
	var backup := FileAccess.get_file_as_bytes(real_path) if had_save else PackedByteArray()

	GameSettings.load_settings(TMP_SETTINGS)   # 文件不存在 → 全部缺省
	_check(is_equal_approx(GameSettings.master_volume(), 0.8), "defaults apply when no save exists")
	GameSettings.set_master_volume(0.35)
	GameSettings.set_look_sensitivity(1.5)
	var bus := AudioServer.get_bus_index("Master")
	_check(bus >= 0 and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.35),
		"master volume applied to Master bus")
	GameSettings.save_settings(TMP_SETTINGS)
	GameSettings.load_settings(TMP_SETTINGS)
	_check(is_equal_approx(GameSettings.master_volume(), 0.35) and is_equal_approx(GameSettings.look_sensitivity(), 1.5),
		"settings persist across save/load round-trip")
	GameSettings.reset_defaults()
	_check(is_equal_approx(GameSettings.master_volume(), 0.8) and is_equal_approx(GameSettings.look_sensitivity(), 1.0),
		"reset restores defaults")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))
	if had_save:
		var restore := FileAccess.open(real_path, FileAccess.WRITE)
		restore.store_buffer(backup)
		restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(real_path))
	GameSettings.load_settings()   # 内存态复原（真实存档或缺省）

	# ---- 阶段 B：真实场景切换进对局（观察者挂 /root 存活过切换）----
	# 引导自动开始的判据是「首次运行」记忆：先清掉本机的 tutorial.cfg，
	# 保证断言不依赖宿主机器状态（真机跳过引导会写记忆）
	var had_tutorial := FileAccess.file_exists(TUTORIAL_PATH)
	var tutorial_backup := FileAccess.get_file_as_bytes(TUTORIAL_PATH) if had_tutorial else PackedByteArray()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TUTORIAL_PATH))
	var watcher := Watcher.new()
	watcher.had_tutorial = had_tutorial
	watcher.tutorial_backup = tutorial_backup
	watcher.base_failures = _failures
	get_tree().root.add_child(watcher)
	# 故意保留上一局序章选择，确认主按钮确实覆盖它并直接进入 Demo。
	LevelRuntime.select(LevelCatalog.PROLOGUE_ID)
	_menu.start_button.pressed.emit()
	# 场景切换后本测试节点随之销毁，后续断言全部由 Watcher 接管


## 观察者节点：不在 current_scene 子树下，change_scene_to_file 不会销毁它。
class Watcher extends Node:
	var had_tutorial: bool = false
	var tutorial_backup := PackedByteArray()
	var base_failures: int = 0
	var _failures: int = 0
	var _frames: int = 0
	var _phase2_started: bool = false


	func _check(condition: bool, message: String) -> void:
		if condition:
			print("PASS: ", message)
		else:
			_failures += 1
			push_error("FAIL: " + message)


	func _process(_delta: float) -> void:
		if _phase2_started:
			return
		_frames += 1
		var tree := get_tree()
		var scene := tree.current_scene
		if scene != null and scene.scene_file_path == "res://scenes/main/Main.tscn":
			_phase2_started = true
			_run_phase2.call_deferred()
		elif _frames > 1500:
			_phase2_started = true
			_check(false, "scene change to Main never completed (timeout)")
			_finish()
		elif _frames % 300 == 0:
			print("...waiting for scene change, frame %d" % _frames)


	func _run_phase2() -> void:
		var tree := get_tree()
		var main := tree.current_scene
		_check(main != null and main.get_node_or_null("WorldRoot") != null, "Main world tree loaded from menu")

		_check(LevelRuntime.is_running(LevelCatalog.SANDBOX_ID)
			and main.get_node_or_null("WorldRoot/PrologueDirector") == null, "开始游戏覆盖旧关卡选择并直入 Demo")

		# 引导在真实入口下应自动开始（current_scene 判据）——等待若干帧让延迟自启跑完
		var tutorial: TutorialSystem = main.get_node_or_null("WorldRoot/TutorialSystem")
		var waited := 0
		while (tutorial == null or tutorial.state != TutorialSystem.State.RUNNING) and waited < 120:
			await tree.process_frame
			waited += 1
		_check(tutorial != null and tutorial.state == TutorialSystem.State.RUNNING,
			"tutorial auto-starts when entering Main via menu")

		await _check_first_run_spawning(main, tutorial)

		var hud := main.get_node_or_null("HUD")
		var menu: PauseMenu = hud.get("pause_menu") if hud != null else null
		_check(menu != null and not menu.is_open, "HUD with pause menu ready in new scene")
		if menu == null:
			_finish()
			return

		_check(not menu.get("_level_map_button").visible, "Demo 暂停菜单不显示选关入口")

		var esc := InputEventAction.new()
		esc.action = "cancel"
		esc.pressed = true

		# Esc 优先级链：引导进行中 → 让位 TutorialSystem（快捷跳过），菜单不弹
		menu._unhandled_input(esc)
		_check(not menu.is_open, "Esc defers to running tutorial (menu stays closed)")
		if tutorial != null:
			tutorial._unhandled_input(esc)
			_check(tutorial.state == TutorialSystem.State.DONE, "tutorial consumes Esc as skip after menu passes through")
			tutorial.clear_save()
		for _i in 30:
			await tree.process_frame
		_check(main.get_node("WorldRoot/WildlifeSpawner").get("_alive") > 1, "跳过引导后恢复正常白天补刷")

		# 引导结束后：Esc 菜单正常开（暂停 + 模态）→ 关（恢复）
		TimeManager.set_speed(1.0)
		var modal_before: int = SelectionManager.ui_modal_count
		menu._unhandled_input(esc)
		_check(menu.is_open and is_equal_approx(TimeManager.time_scale, 0.0)
			and SelectionManager.ui_modal_count == modal_before + 1,
			"Esc opens pause menu in real game scene (pauses + modal)")
		menu._unhandled_input(esc)
		_check(not menu.is_open and is_equal_approx(TimeManager.time_scale, 1.0)
			and SelectionManager.ui_modal_count == modal_before,
			"Esc closes menu and restores speed/modal")
		SelectionManager.ui_modal_count = 0

		# —— 返回主菜单：全局状态清理 + 真实场景切换回主菜单 ——
		TimeManager.set_speed(2.0)   # 故意留一个非 1 倍速，验证回主菜单时被复位
		SelectionManager.build_mode_active = true   # 故意留建造态，验证被清理
		menu.open()
		menu._return_to_main_menu()
		var back := 0
		while (tree.current_scene == null or tree.current_scene.scene_file_path != "res://scenes/main/MainMenu.tscn") and back < 600:
			await tree.process_frame
			back += 1
		_check(tree.current_scene != null and tree.current_scene.scene_file_path == MENU_SCENE_PATH,
			"return-to-menu changes scene back to MainMenu")
		_check(not SelectionManager.build_mode_active and SelectionManager.ui_modal_count == 0,
			"return-to-menu clears build flag and modal count")
		_check(is_equal_approx(TimeManager.time_scale, 1.0),
			"return-to-menu resets time scale to 1.0 (menu runs on real time)")
		_finish()


	## 首次运行必须靠真实刷怪与死亡链通过首杀教学，不能由测试手动造怪或伪发死亡信号。
	func _check_first_run_spawning(main: Node, tutorial: TutorialSystem) -> void:
		if tutorial == null:
			return
		var wildlife: WildlifeSpawner = main.get_node("WorldRoot/WildlifeSpawner")
		var enemies: Node3D = main.get_node("WorldRoot/Enemies")
		for _i in 240:
			await get_tree().process_frame
		_check(enemies.get_child_count() == 0, "欢迎信息卡期间不刷怪")
		tutorial.advance_delay = 0.01
		tutorial.advance()
		Input.action_press("move_up")
		for _i in 10:
			await get_tree().physics_frame
		Input.action_release("move_up")
		_check(tutorial.current().id == &"first_blood", "实际移动后进入首杀教学")
		for _i in 270:
			await get_tree().process_frame
		_check(enemies.get_child_count() == 1 and wildlife._alive == 1, "首次首杀教学自动提供一只野怪")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://artifacts/demo-start")
			get_viewport().get_texture().get_image().save_png("res://artifacts/demo-start/first-blood.png")
		# 慢玩家走到夜晚仍须能完成教学，且不进入夜潮准备或生成攻城怪。
		TimeManager.begin(20)
		for enemy in enemies.get_children():
			(enemy as Raider).health.apply_damage(10000.0)
		wildlife.spawn_interval = 0.1
		for _i in 30:
			await get_tree().process_frame
		_check(wildlife._alive == 1 and not wildlife._night_prep and not TimeManager.clock_frozen,
			"首杀目标意外死亡后夜间仍能补刷，且没有夜潮")
		for enemy in enemies.get_children():
			if (enemy as Raider).health.is_dead():
				continue
			_check(not (enemy as Raider).assaulting, "教学目标不是攻城怪")
			(enemy as Raider).health.apply_damage(10000.0, main.get("hero"))
		for _i in 10:
			await get_tree().process_frame
		_check(tutorial.current().id == &"build_house", "真实击杀自动推进到建房教学")
		for _i in 30:
			await get_tree().process_frame
		_check(wildlife._alive == 0 and not wildlife._night_prep, "首杀完成后恢复教学保护")
		# 恢复欢迎步供后续 Esc 优先级验证；退出教学后白天自然补刷应正常。
		TimeManager.begin(6)
		tutorial.start()


	func _finish() -> void:
		if had_tutorial:
			var restore := FileAccess.open(TUTORIAL_PATH, FileAccess.WRITE)
			restore.store_buffer(tutorial_backup)
			restore.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TUTORIAL_PATH))
		var total: int = base_failures + _failures
		print("MENU FLOW: %d failure(s)" % total)
		get_tree().quit(0 if total == 0 else 1)
