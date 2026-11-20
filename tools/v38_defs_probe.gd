extends Node
## v38 定义层探针（Lead 自检用）：关卡目录契约 + 关卡会话/进度落盘 + 主菜单入口接线。
## 用法：bash tools/godot_locked.sh --headless --path . tools/v38_defs_probe.tscn
##
## 只碰数据层与菜单装配，不切场景（切场景的端到端链路是 tests/LevelSelectTest.tscn）。
## 探测会写真实的 user://level_progress.cfg，收尾按备份还原，绝不污染玩家进度。

const PROGRESS_PATH := "user://level_progress.cfg"

var _fails: int = 0
var _had_progress: bool = false
var _backup := PackedByteArray()


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_fails += 1
		print("FAIL: ", msg)


func _ready() -> void:
	_backup_progress()
	_check_catalog()
	_check_runtime()
	_check_progress_io()
	_check_menu_wiring()
	_restore_progress()
	print("PROBE_RESULT fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _check_catalog() -> void:
	var levels := LevelCatalog.all()
	_check(levels.size() == 5, "关卡目录 5 关（实际 %d）" % levels.size())
	var ids := {}
	var prologue_count := 0
	var sandbox_count := 0
	var coming := 0
	var regions := [LevelDef.REGION_GREEN, LevelDef.REGION_FOREST, LevelDef.REGION_DESERT,
		LevelDef.REGION_SNOW, LevelDef.REGION_ROCK]
	for level in levels:
		_check(not ids.has(level.id), "关卡 id 唯一：%s" % level.id)
		ids[level.id] = true
		_check(level.title != "" and level.chapter != "" and level.desc != "",
			"关卡有标题/章节/简介：%s" % level.id)
		_check(level.map_pos.x >= 0.0 and level.map_pos.x <= 1.0
			and level.map_pos.y >= 0.0 and level.map_pos.y <= 1.0,
			"地图坐标归一化：%s → %s" % [level.id, level.map_pos])
		_check(regions.has(level.region), "岛屿配色 id 合法：%s → %s" % [level.id, level.region])
		_check(level.objectives.size() >= 1, "关卡至少 1 条目标说明：%s" % level.id)
		match level.kind:
			LevelDef.Kind.PROLOGUE:
				prologue_count += 1
			LevelDef.Kind.SANDBOX:
				sandbox_count += 1
			_:
				coming += 1
				_check(level.scene_path == "" and not level.is_playable(),
					"暂未开放关卡不可进入：%s" % level.id)
		if level.is_playable():
			_check(ResourceLoader.exists(level.scene_path),
				"可玩关卡场景存在：%s → %s" % [level.id, level.scene_path])
	_check(prologue_count == 1 and sandbox_count == 1 and coming == 3,
		"关卡构成 = 1 序章 + 1 沙盒 + 3 暂未开放（%d/%d/%d）" % [prologue_count, sandbox_count, coming])

	var prologue := LevelCatalog.prologue()
	_check(prologue != null and prologue.star_total == 3 and prologue.star_hints.size() == 3,
		"序章 3 星上限 + 3 条星级条件")
	_check(prologue != null and prologue.chip_text(0) == "0/3" and prologue.chip_text(5) == "3/3",
		"星数芯片钳制正确")
	var sandbox := LevelCatalog.sandbox()
	_check(sandbox != null and sandbox.star_total == 0 and sandbox.chip_text(0) == "测试",
		"沙盒关无星级判定，芯片显示「测试」")
	_check(LevelCatalog.get_level(&"nope") == null, "未知关卡 id 返回 null")


func _check_runtime() -> void:
	LevelRuntime.clear_selection()
	_check(LevelRuntime.selected_id == &"" and LevelRuntime.current_level().id == LevelCatalog.SANDBOX_ID,
		"空选择 → 按沙盒关跑（旧行为不变）")
	_check(LevelRuntime.select(LevelCatalog.PROLOGUE_ID), "选中序章成功")
	_check(LevelRuntime.current_level().id == LevelCatalog.PROLOGUE_ID, "current_level() 返回序章")
	_check(not LevelRuntime.select(&"ch1") and not LevelRuntime.select(&"nope"),
		"暂未开放 / 未知关卡拒绝选中")
	_check(LevelRuntime.selected_id == LevelCatalog.PROLOGUE_ID, "拒绝的选中不改状态")
	LevelRuntime.clear_selection()
	_check(LevelRuntime.selected_id == &"" and LevelRuntime.current_level().id == LevelCatalog.SANDBOX_ID,
		"清空选择后回落沙盒")


func _check_progress_io() -> void:
	LevelRuntime.reset_progress()
	_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) == 0
		and not LevelRuntime.is_cleared(LevelCatalog.PROLOGUE_ID), "重置后无星无通关")
	LevelRuntime.record_result(LevelCatalog.PROLOGUE_ID, 2)
	_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) == 2
		and LevelRuntime.is_cleared(LevelCatalog.PROLOGUE_ID), "记 2 星 + 通关标记")
	LevelRuntime.record_result(LevelCatalog.PROLOGUE_ID, 1)
	_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) == 2, "进度只增不减（重打 1 星不回退）")
	LevelRuntime.record_result(LevelCatalog.PROLOGUE_ID, 9)
	_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) == 3, "星数按关卡上限钳制（9 → 3）")
	_check(FileAccess.file_exists(PROGRESS_PATH), "进度已落盘 user://level_progress.cfg")
	LevelRuntime.reset_progress()
	LevelRuntime.reload_progress()
	_check(LevelRuntime.stars_of(LevelCatalog.PROLOGUE_ID) == 0, "落盘 - 重读 round-trip 一致")
	_check(LevelRuntime.total_capacity() == 21, "总星上限 = 序章3 + 三章各6（实际 %d）" % LevelRuntime.total_capacity())


func _check_menu_wiring() -> void:
	_check(LevelCatalog.LEVEL_SELECT_SCENE == "res://scenes/main/LevelSelect3D.tscn"
		and ResourceLoader.exists(LevelCatalog.LEVEL_SELECT_SCENE), "关卡选择地图场景存在")
	var menu: Control = load("res://scenes/main/MainMenu.tscn").instantiate()
	add_child(menu)
	_check(menu.get_node_or_null("MenuFlow/ButtonBox/StartButton") != null
		and menu.get_node_or_null("MenuFlow/ButtonBox/TestLevelButton") != null
		and menu.get_node_or_null("MenuFlow/ButtonBox/SettingsButton") != null
		and menu.get_node_or_null("MenuFlow/ButtonBox/QuitButton") != null,
		"主菜单四个入口齐全（开始 / 测试关卡 / 设置 / 退出）")
	_check(menu.LEVEL_SELECT_SCENE == LevelCatalog.LEVEL_SELECT_SCENE
		and menu.GAME_SCENE == LevelCatalog.MAIN_SCENE, "主菜单场景常量与关卡目录一致")
	menu.queue_free()


func _backup_progress() -> void:
	_had_progress = FileAccess.file_exists(PROGRESS_PATH)
	if _had_progress:
		_backup = FileAccess.get_file_as_bytes(PROGRESS_PATH)


func _restore_progress() -> void:
	if _had_progress:
		var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_backup)
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROGRESS_PATH))
	LevelRuntime.reload_progress()
	LevelRuntime.clear_selection()
