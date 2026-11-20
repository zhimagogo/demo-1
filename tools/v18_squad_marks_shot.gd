extends Node
## v18 交付留档工具：小队常驻绿标（绿色包边 + 脚下小绿圈）+ 拟真跟随队形实机样张。
##
## 运行（两次，一次在队一次解散，供人工对照）：
##   godot --path . tools/v18_squad_marks_shot.tscn                 # → artifacts/v18-squad-green-marks.png
##   godot --path . tools/v18_squad_marks_shot.tscn -- --disband    # → artifacts/v18-squad-marks-off.png
## 渲染级像素校验走极简探针（排除草地环境绿干扰）：
##   godot --path . tools/v18_marks_probe.tscn && godot --path . tools/v18_marks_probe.tscn -- --no-marks
##   godot --headless --path . --script tools/v18_marks_check.gd
##
## 画面：主角身后小队列队待命（绿色包边 + 脚下小绿圈），站定成员播 idle。
## 注意：同一进程连续抓两帧会拿到未刷新的旧纹理（实测逐字节相同），
## 故对照帧用独立进程 + --disband 参数生成。

var _main: Node


func _ready() -> void:
	var disband: bool = OS.get_cmdline_user_args().has("--disband")
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	var spawner := world.get_node("PawnSpawner")
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午顺光
	TimeManager.set_speed(0.0)   # 布景期冻结

	# ==== 布景：主角城外北侧空地，四职业小兵从身侧跑位集结 ====
	hero.global_position = Vector3(8.0, 0.0, -34.0)
	hero.release_squad()
	hero.set_party([])
	var party_defs := [GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def()]
	for i in party_defs.size():
		spawner.call("spawn_soldier", party_defs[i],
			hero.global_position + Vector3(3.0 + float(i) * 1.2, 0.0, 2.5))
	await get_tree().physics_frame

	# 进入亲征（自动编队集结）→ 小兵 2× 跑向主角身后槽位，就位后站定
	TimeManager.set_speed(1.0)
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.pitch = -0.36
	tp.target_distance = 6.2
	var settled := false
	for i in 420:
		await get_tree().physics_frame
		var all_close := true
		for m in hero.squad:
			if is_instance_valid(m) and (m as Node3D).global_position.distance_to(hero.global_position) > 3.5:
				all_close = false
		if all_close and i > 60:
			settled = true
			break
	print("squad settled: ", settled)

	# ==== 定格取景：队形在主角身后（相机一侧），绿标清晰 ====
	TimeManager.set_speed(0.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		var pause_overlay := hud.get("pause_overlay") as CanvasItem
		if pause_overlay != null:
			pause_overlay.visible = false   # 冻结会弹 P 遮罩，样张不需要
	if disband:
		# 对照帧：同机位解散（成员原地站定，绿标即刻撤下）
		hero.release_squad()
		# time_scale=0 下普通定时器不触发，用 ignore_time_scale 的真实时间定时器
		await get_tree().create_timer(0.5, true, false, true).timeout
	var filename := "v18-squad-marks-off" if disband else "v18-squad-green-marks"
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % filename)
	print("saved artifacts/%s.png" % filename)
	get_tree().quit()
