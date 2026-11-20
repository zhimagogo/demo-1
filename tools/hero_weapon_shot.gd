extends Node
## 交付留档工具：真实对局里的「主角武器挂点」对照样张（不参与游戏运行）。
##
## 一张图并排两个主角模型（同一 GLB、同一 Idle 定格姿势、同一机位光照）：
##   左 = 真实主角实例：走 PawnDef.model_weapon_* → Pawn → PawnModelRig 完整链路（修复后的样子）
##   右 = 模型原样：apply_weapon_loadout(KEEP_ALL)，即修复前「一只手叠着全部剑盾」的样子
## 机位用工具自建相机：游戏内两台相机都看不清手（第三人称主角永远背对镜头、战术俯瞰俯角 -55°），
## 这里只摆一台平视近景相机，同场景 / 同光照 / 同真实主角实例，不改游戏内相机行为。
## 另存一张默认第三人称亲征视角的实机帧。
##
## 运行：godot --path . tools/hero_weapon_shot.tscn [-- --label=xxx]
## 输出：artifacts/hero-weapon-<label>.png / artifacts/hero-weapon-<label>-thirdperson.png


var _label := "after"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	get_window().size = Vector2i(1400, 900)
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	# 冻结与画面无关的运行时系统，让样张可复现
	world.get_node("WildlifeSpawner").set_process(false)
	world.get_node("ResourceGrowthSystem").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	controller.exit_hero_mode()          # 退出亲征模式：主角站定不再吃输入
	iso.edge_pan = false
	iso.set_process(false)
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午：光线干净
	var hud := main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	await get_tree().physics_frame

	# 机位方向：主角朝镜头站定（aim_dir 与朝向同时写，避免 HeroIdleState 下一物理帧转回去）
	var to_camera := Vector3(0.707, 0.0, -0.707).normalized()
	var screen_right := (-to_camera).cross(Vector3.UP)
	hero.aim_dir = to_camera
	hero.look_at_target(hero.global_position + to_camera * 3.0)

	# 右侧对照模型：同一 GLB 的「模型原样」（修复前 = 没有武器挂点筛选）
	var hero_def := GameDefs.hero_warrior_def()
	var ref_rig := PawnModelRig.new()
	ref_rig.name = "WeaponRefRig"
	world.add_child(ref_rig)
	ref_rig.setup(hero_def.model_path, hero_def.model_scale, hero_def.model_face_offset_deg)
	ref_rig.apply_weapon_loadout(PawnModelRig.KEEP_ALL, PawnModelRig.KEEP_ALL)
	ref_rig.global_position = hero.global_position + screen_right * 2.3
	ref_rig.rotation.y = hero.global_rotation.y + deg_to_rad(hero_def.model_face_offset_deg)

	# 工具自建平视相机（挂世界，不改游戏内相机行为）
	var shot_cam := Camera3D.new()
	shot_cam.fov = 32.0
	world.add_child(shot_cam)
	var mid := hero.global_position + screen_right * 1.15 + Vector3(0.0, 1.05, 0.0)
	shot_cam.global_position = mid + to_camera * 7.2 + Vector3(0.0, 0.55, 0.0)
	shot_cam.look_at(mid)
	shot_cam.current = true

	# 让姿态收敛（HeroIdleState 每物理帧写朝向），随后把两个 AnimationPlayer 定格在同一帧
	for i in 40:
		hero.aim_dir = to_camera
		hero.look_at_target(hero.global_position + to_camera * 3.0)
		await get_tree().physics_frame
	var t := 0.9
	hero.model_rig.anim_player.seek(t, true)
	ref_rig.anim_player.seek(t, true)
	hero.model_rig.anim_player.pause()
	ref_rig.anim_player.pause()
	ref_rig.rotation.y = hero.global_rotation.y + deg_to_rad(hero_def.model_face_offset_deg)

	await get_tree().create_timer(0.6).timeout
	for i in 4:
		hero.aim_dir = to_camera
		await get_tree().physics_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/hero-weapon-%s.png" % _label)
	print("saved artifacts/hero-weapon-%s.png" % _label)

	# 默认第三人称亲征视角（真实主视角）再留一张：对照模型与工具相机先撤掉
	ref_rig.queue_free()
	shot_cam.queue_free()
	hero.model_rig.anim_player.play()
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.yaw = PI * 0.75
	tp.pitch = -0.30
	tp.target_distance = 3.4
	await get_tree().create_timer(1.2).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/hero-weapon-%s-thirdperson.png" % _label)
	print("saved artifacts/hero-weapon-%s-thirdperson.png" % _label)
	get_tree().quit()
