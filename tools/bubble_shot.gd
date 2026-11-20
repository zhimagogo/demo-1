extends Node
## v14 交付留档：小兵人设气泡样张（不参与游戏运行）。
##
## 运行：godot --path . tools/bubble_shot.tscn
## 输出：artifacts/v14-bubbles.png —— 五个不同人设的小兵同时冒出各自的台词气泡。
##
## 注意：气泡动画走 _process 的 delta，因此本工具不能像 dissolve_shot 那样
## set_speed(0) 冻结世界——改为关 WildlifeSpawner + 冻结单位物理，让气泡正常淡入。

const ROW_Z := -20.0
const SPACING := 2.6

# 人设 × 代表台词（与 GameDefs.BUBBLE_LINES 同源风格，展示宽度差异）。
# def 直接实例化（const 不能持运行期工厂结果，故放函数里构建）。
func _cast() -> Array:
	return [
		{"def": GameDefs.settler_warrior_def(), "line": "我顶前面，你们输出！"},
		{"def": GameDefs.settler_archer_def(), "line": "装填，瞄准，发射！"},
		{"def": GameDefs.settler_warrior_def(), "line": "一斧一个！"},
		{"def": GameDefs.settler_mage_def(), "line": "退后，我要施法了！"},
		{"colonist": true, "line": "再砍两棵就满喽。"},
	]

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	TimeManager.begin(11)          # 正午，光线充足
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	var hero := controller.hero as Hero
	if hero != null:
		hero.visible = false      # 样张只看小兵
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	iso.set_process(false)

	# 固定人像机位：正对小兵一排，略微俯视看到头顶气泡
	var cast := _cast()
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.global_position = Vector3(float(cast.size() - 1) * 0.5 * SPACING, 2.6, ROW_Z + 6.2)
	cam.look_at(Vector3(float(cast.size() - 1) * 0.5 * SPACING, 1.7, ROW_Z))
	cam.current = true

	var spawner := world.get_node("PawnSpawner")
	for i in cast.size():
		var at := Vector3(float(i) * SPACING, 0.0, ROW_Z)
		var pawn: Pawn
		if cast[i].get("colonist", false):
			pawn = spawner.call("spawn_colonist", at)   # 村民走正牌入口（随机姓名 / 货包视觉）
		else:
			pawn = spawner.call("spawn_soldier", cast[i]["def"], at)
		pawn.set_physics_process(false)
		var sm: Variant = pawn.get("state_machine")
		if sm is Node:
			(sm as Node).set_physics_process(false)
		pawn.look_at_target(cam.global_position - at)   # 面向镜头
		var bubble := pawn.get_node("SpeechBubble3D") as SpeechBubble3D
		bubble.show_bubble(String(cast[i]["line"]), 20.0)

	for _i in 45:   # 淡入 0.16s + 弹出过冲 0.2s，多等几帧到稳定态
		await get_tree().physics_frame
	await _snap("v14-bubbles")
	get_tree().quit()


func _snap(name: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % name)
	print("saved artifacts/%s.png" % name)
