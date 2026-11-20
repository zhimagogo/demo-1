extends Node
## v10 交付留档工具：小队 / 编队 / 集火系统对照样张（不参与游戏运行）。
##
## 运行：godot --path . tools/v10_squad_shot.tscn
## 输出：
##   artifacts/v10-classes.png      五个模型并排：流民（兜帽空手）+ 战士/法师/刺客/射手（各自武器）
##   artifacts/v10-hero-hud.png     第三人称实机：红准星 + 怪物红描边 + 小队面板（血量/集火行）
##   artifacts/v10-party-panel.png  编队界面（4 槽位 + 城镇小兵列表）

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	controller.exit_hero_mode()
	iso.edge_pan = false
	iso.set_process(false)
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午
	TimeManager.set_speed(0.0)   # 冻结世界：AI / 动画定格可复现
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	var spawner := world.get_node("PawnSpawner")

	# ==== 样张 1：流民 + 四职业并排（各自武器挂点）====
	if hud != null:
		hud.visible = false
	var to_camera := Vector3(0.0, 0.0, -1.0)
	var row_start := Vector3(-6.0, 0.0, -30.0)   # 城外北侧空地
	var defs := [
		GameDefs.refugee_def(), GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def(),
	]
	var rigs: Array = []
	for i in defs.size():
		var pawn: Pawn = spawner.call("spawn_soldier", defs[i], row_start + Vector3(float(i) * 3.0, 0.0, 0.0))
		# refugee_def 走 spawn_soldier 也会得到 Soldier 行为（工具只求外观，直接摆姿即可）
		pawn.look_at_target(to_camera)
		if pawn.model_rig != null and pawn.model_rig.anim_player != null:
			pawn.model_rig.anim_player.pause()
		rigs.append(pawn)
	var shot_cam := Camera3D.new()
	shot_cam.fov = 38.0
	world.add_child(shot_cam)
	var mid := row_start + Vector3(6.0, 1.0, 0.0)
	shot_cam.global_position = mid + to_camera * 10.5 + Vector3(0.0, 1.1, 0.0)
	shot_cam.look_at(mid)
	shot_cam.current = true
	await _snap("v10-classes")
	for r in rigs:
		(r as Node).queue_free()
	shot_cam.queue_free()

	# ==== 样张 2：第三人称实机（红准星 / 红描边 / 小队面板）====
	if hud != null:
		hud.visible = true
	TimeManager.set_speed(1.0)
	hero.global_position = Vector3(8.0, 0.0, -34.0)
	# 样张 1 的摆拍单位曾把编队占满（上限 4）——先清空编队/小队，让本阶段的四人入队
	hero.release_squad()
	hero.set_party([])
	# 编队四人（四职业各一）+ 集结
	var party_defs := [GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def()]
	for i in party_defs.size():
		spawner.call("spawn_soldier", party_defs[i], hero.global_position + Vector3(2.0 + float(i) * 1.2, 0.0, 1.5))
	await get_tree().physics_frame
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var raider: Raider = spawner.call("spawn_raider", hero.global_position + Vector3(0.0, 0.0, -8.0), GameDefs.raider_def())
	await get_tree().physics_frame
	var to_r := raider.global_position - hero.global_position
	to_r.y = 0.0
	tp.yaw = atan2(-to_r.x, -to_r.z)
	tp.pitch = atan2(1.0 - 1.55, to_r.length())
	tp.target_distance = 4.2
	for i in 8:
		await get_tree().physics_frame
	controller._refresh_crosshair_prompt()
	controller._aim_enemy = raider
	controller._toggle_focus_fire()
	TimeManager.set_speed(0.0)   # 定格：小队围攻姿态 + 红描边稳定
	# 第 4 参才是 ignore_time_scale（create_timer 签名坑）；time_scale=0 时普通定时器永不触发
	await get_tree().create_timer(1.0, true, false, true).timeout
	# 定格后再刷一次准星（相机 transform 已完全收敛、怪也停稳）→ 红准星稳定入画
	controller._refresh_crosshair_prompt()
	# 工具冻结（set_speed 0）会弹出 P 键暂停遮罩——样张不需要它，隐藏掉
	(hud.get("pause_overlay") as CanvasItem).visible = false
	await _snap("v10-hero-hud")

	# ==== 样张 3：编队界面 ====
	TimeManager.set_speed(1.0)
	var party_panel = hud.get("party_panel")
	party_panel.open()
	(hud.get("pause_overlay") as CanvasItem).visible = false   # 编队真暂停同样会弹 P 遮罩，隐藏
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("v10-party-panel")
	party_panel.close()
	get_tree().quit()


func _snap(filename: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % filename)
	print("saved artifacts/%s.png" % filename)
