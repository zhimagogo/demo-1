extends Node
## ============================================================================
## v38 真实入口全链路探针（Lead 验收；场景切换是 headless 回归的盲区）：
##   主菜单 →（点「开始游戏」）→ 3D 关卡地图 →（小人走到序章旗 + 按 E）→ 序章
##        →（清匪徒 + 收复主城）→ 结算层 →（点「返回关卡地图」）→ 3D 关卡地图
##
## 用法：bash tools/godot_locked.sh --headless --path . tools/v38_e2e_probe.tscn --fixed-fps 60
##
## 与 tests/LevelSelectTest.tscn 的分工：那个测「组装与状态契约」（实例化关卡地图 / 序章），
## 本探针测「用户真的这么点会怎样」——三次真实 change_scene 全链路。
## 会真实写 user://level_progress.cfg，收尾按备份还原，绝不污染玩家进度。
## 任何路径都必须 quit（跑批护栏靠退出码）。
## ============================================================================

const MENU_SCENE := "res://scenes/main/MainMenu.tscn"
const MAP_SCENE := "res://scenes/main/LevelSelect3D.tscn"
const MAIN_SCENE := "res://scenes/main/Main.tscn"
const PROGRESS_PATH := "user://level_progress.cfg"

var _had_progress := false
var _backup := PackedByteArray()
var _boot_frames := 0


func _ready() -> void:
	_had_progress = FileAccess.file_exists(PROGRESS_PATH)
	if _had_progress:
		_backup = FileAccess.get_file_as_bytes(PROGRESS_PATH)
	# _ready 里父节点正在装配子节点，add_child / change_scene 都必须等这一帧结束
	_boot.call_deferred()


## 看门狗：正常路径下本节点会被 change_scene 销毁；没被销毁 = 启动失败，兜底退出。
func _process(_delta: float) -> void:
	_boot_frames += 1
	if _boot_frames > 600:
		push_error("FAIL: 探针启动失败（Runner 未接管），兜底退出")
		print("E2E ENTRY: 1 failure(s)")
		get_tree().quit(1)


func _boot() -> void:
	# 本节点是当前场景，change_scene 会销毁它 —— 真正的跑批节点挂 /root 下
	var runner := Runner.new()
	runner.had_progress = _had_progress
	runner.backup = _backup
	get_tree().root.add_child(runner)
	get_tree().change_scene_to_file(MENU_SCENE)


## 跑批节点：不在 current_scene 子树下，三次场景切换都不会销毁它。
class Runner extends Node:
	var had_progress := false
	var backup := PackedByteArray()
	var _failures: int = 0

	func _check(condition: bool, message: String) -> void:
		if condition:
			print("PASS: ", message)
		else:
			_failures += 1
			push_error("FAIL: " + message)

	func _ready() -> void:
		_run.call_deferred()

	## 等场景切到指定路径；超时返回 false。
	func _await_scene(path: String, max_frames: int = 900) -> bool:
		var tree := get_tree()
		for _i in max_frames:
			await tree.process_frame
			var scene := tree.current_scene
			if scene != null and scene.scene_file_path == path:
				# 再等两帧让场景 _ready / 延迟初始化跑完
				await tree.process_frame
				await tree.process_frame
				return true
		return false

	func _find(root: Node, node_name: String) -> Node:
		var direct := root.get_node_or_null(node_name)
		return direct if direct != null else root.find_child(node_name, true, false)

	func _run() -> void:
		var tree := get_tree()
		# ① 主菜单：真的点「开始游戏」
		_check(await _await_scene(MENU_SCENE), "真实启动落在主菜单")
		var menu := tree.current_scene
		var start_button := _find(menu, "StartButton") as Button
		_check(start_button != null, "主菜单有「开始游戏」按钮")
		if start_button == null:
			_finish()
			return
		start_button.emit_signal("pressed")

		# ② 关卡地图：小人走到序章旗旁 → 按 E 进入
		_check(await _await_scene(MAP_SCENE), "「开始游戏」进入 3D 关卡地图")
		var map := tree.current_scene
		if map == null or map.scene_file_path != MAP_SCENE:
			_finish()
			return
		var flag_at: Vector3 = map.call("flag_world_position", LevelCatalog.PROLOGUE_ID)
		map.call("teleport_player", flag_at)
		for _i in 25:
			await tree.process_frame
		_check(map.get("selected_id") == LevelCatalog.PROLOGUE_ID,
			"走到序章旗旁自动选中序章（selected_id=%s）" % map.get("selected_id"))
		var hint := _find(map, "HintLabel") as Label
		_check(hint != null and hint.text.contains("E"), "旗旁提示条提示按 E 进入")
		var entered: bool = map.call("try_enter_selected")
		_check(entered, "按 E / 点「进入关卡」返回 true")

		# ③ 序章：清匪徒 + 收复主城 → 结算
		_check(await _await_scene(MAIN_SCENE), "从关卡地图进入序章世界")
		var main := tree.current_scene
		if main == null or main.scene_file_path != MAIN_SCENE:
			_finish()
			return
		var director: Node = null
		for _i in 240:
			director = main.get_node_or_null("WorldRoot/PrologueDirector")
			if director != null and int(director.call("raiders").size()) >= 4:
				break
			await tree.process_frame
		_check(director != null, "序章由 PrologueDirector 接管")
		if director == null:
			_finish()
			return
		director.set("hold_seconds", 0.2)   # 测试提速（判定逻辑不变）
		for r in director.call("raiders"):
			if is_instance_valid(r):
				var hp := (r as Node).get_node_or_null("HealthComponent")
				if hp != null:
					hp.call("apply_damage", 9999.0, null)
		var world := main.get_node("WorldRoot")
		var nav := world.get_node_or_null("NavSystem")
		var hero: Node = null
		for n in tree.get_nodes_in_group("player_unit"):
			if n is Hero:
				hero = n
				break
		_check(hero != null, "序章里主角在场")
		if hero != null and nav != null:
			(hero as Node3D).global_position = nav.call("snap_to_walkable", Vector3(5.0, 0.0, 5.0))
		var done := false
		for _i in 300:
			await tree.process_frame
			if bool(director.get("finished")):
				done = true
				break
		_check(done, "清完匪徒 + 收复主城 → 序章通关")
		_check(LevelRuntime.is_cleared(LevelCatalog.PROLOGUE_ID), "通关写进关卡进度")

		# ④ 结算层「返回关卡地图」
		var overlay := main.get_node_or_null("PrologueOverlay")
		if overlay == null:
			overlay = tree.get_first_node_in_group("prologue_overlay")
		_check(overlay != null, "序章结算层存在")
		var map_button: Button = null
		if overlay != null:
			map_button = _find(overlay, "MapButton") as Button
		_check(map_button != null, "结算层有「返回关卡地图」按钮")
		if map_button == null:
			_finish()
			return
		map_button.emit_signal("pressed")
		_check(await _await_scene(MAP_SCENE), "结算层「返回关卡地图」回到 3D 关卡地图")
		var back := tree.current_scene
		_check(back != null and back.scene_file_path == MAP_SCENE, "回到地图后当前场景正确")
		_check(not SelectionManager.build_mode_active and SelectionManager.ui_modal_count == 0,
			"回到地图后全局状态干净（无建造态残留 / 模态计数归零）")
		_check(is_equal_approx(TimeManager.time_scale, 1.0), "回到地图后倍速复位为 1.0")

		_restore_progress()
		_finish()

	func _restore_progress() -> void:
		if had_progress:
			var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
			if f != null:
				f.store_buffer(backup)
				f.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
		LevelRuntime.reload_progress()
		LevelRuntime.clear_selection()
		TimeManager.set_speed(1.0)
		TimeManager.clock_frozen = false
		SelectionManager.ui_modal_count = 0

	func _finish() -> void:
		print("E2E ENTRY: %d failure(s)" % _failures)
		get_tree().quit(0 if _failures == 0 else 1)
