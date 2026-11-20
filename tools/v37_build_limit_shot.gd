extends Node
## ============================================================================
## v37 建筑数量上限样张：酒馆已建成后，BuildMenu 的酒馆卡置灰 + 造价芯片显「满」，
## 建造模式下的 ghost 恒为红色（超限不可放）。
##
##   bash tools/godot_locked.sh --path . tools/v37_build_limit_shot.tscn --resolution 1280x720
##
## 产出（artifacts/，抓帧为窗口像素）：
##   v37-limit-tavern-card.png   已建成 1 座酒馆 → 酒馆卡置灰「满」（当前仍选中酒馆建造模式，ghost 红）
##   v37-limit-wall-selected.png 切到木墙建造模式：木墙卡金边高亮可建，酒馆卡保持置灰
##
## 只做展示与截图，不改任何玩法状态；退出码恒为 0（截图失败仅打印）。
## ============================================================================

const SHOT_DIR := "res://artifacts/"
const WATCHDOG_SEC := 120.0
const TAVERN_SPOT := Vector3(8.0, 0.0, -4.0)

var _elapsed: float = 0.0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > WATCHDOG_SEC:
		print("[v37] watchdog timeout, quit")
		get_tree().quit(1)


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR + name
	var err := img.save_png(path)
	print("[v37] shot ", path, " -> ", "OK" if err == OK else "ERR %d" % err)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await _wait(4)
	var world := _main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem"]:
		var s := world.get_node_or_null(n)
		if s != null:
			s.set_process(false)
			s.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null:
		tutorial.skip()
	TimeManager.game_seconds = 11.0 / 24.0 * TimeManager.seconds_per_day   # 正午，画面明亮
	ResourceManager.add(GameDefs.GOLD, 1000)
	await _wait(4)

	var build := world.get_node("BuildSystem") as BuildSystem
	var menu: BuildMenu = null
	for c in _main.get_children():
		if c.get("build_menu") != null:
			menu = c.get("build_menu") as BuildMenu
			break
	var tavern_def: BuildingDef = null
	var wall_def: BuildingDef = null
	for d in GameDefs.building_defs():
		if d.id == &"tavern":
			tavern_def = d
		elif d.id == &"wall":
			wall_def = d

	# 建 1 座酒馆 → 达到上限（第二座起被拒）
	build.enter_build_mode(tavern_def)
	build.try_place_at(TAVERN_SPOT)
	await _wait(4)
	# 再次进入酒馆建造模式：ghost 应为红色（超限），卡片同步置灰显「满」
	build.enter_build_mode(tavern_def)
	await _wait(8)
	if menu != null:
		var btn := menu.get_card_button(&"tavern")
		print("[v37] tavern card disabled=", btn.disabled if btn != null else "null",
			" limit_reached=", build.build_limit_reached(tavern_def),
			" preview_valid=", build.preview.is_valid)
	await _shot("v37-limit-tavern-card.png")

	# 切到木墙：不限量建筑照常高亮可建，酒馆卡仍是灰的（对照）
	build.enter_build_mode(wall_def)
	await _wait(8)
	await _shot("v37-limit-wall-selected.png")

	print("[v37] shots done")
	get_tree().quit(0)
