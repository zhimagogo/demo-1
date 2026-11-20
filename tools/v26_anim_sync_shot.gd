extends Node
## v26 交付留档工具：动画 ↔ 特效同步样张（五单位同框，各自定格在挥击/施法中段）。
##
## 运行：
##   godot --path . tools/v26_anim_sync_shot.tscn   # → artifacts/v26-anim-vfx-sync.png
##
## 布景（左→右，浅弧一排，各自面向身前木桩）：战士（2H 斧 2H_Slice + 土黄斧光）/
## 法师（举杖 Spellcast_Shoot + 杖头奥术微光 + 紫色法弹）/ 游侠（举弩 1H_Ranged_Shoot +
## 枪口十字星 + 白色速度线弩箭）/ 刺客（双持 Dualwield_Slice + 双匕青白弧）/
## 掠夺者（兽爪 Punch，**无剑光弧**，目标身上只溅命中火星）。
## 全部走真实攻击管线（attacker.try_attack）出特效；动画播到中段后 speed_scale=0
## 定格姿态，网格特效用 debug_anim_progress 定格在同一瞬间。

const ROW_Z: float = -34.0

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	var spawner := world.get_node("PawnSpawner")
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午顺光

	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	hero.global_position = Vector3(1.4, 0.0, -38.5)
	hero.velocity = Vector3.ZERO
	hero.release_squad()
	hero.set_party([])
	controller.enter_hero_mode()
	# 第三人称相机的枢轴是主角本体（永远在画面中心）→ 直接隐藏主角模型当隐形脚架
	var hero_placeholder := hero.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if hero_placeholder != null:
		hero_placeholder.visible = false
	if hero.model_rig != null:
		hero.model_rig.visible = false
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.yaw = PI
	tp.pitch = -0.24
	tp.target_distance = 3.6

	# 五单位浅弧 + 各自木桩（高血不还手；间距 3.5m 保证一镜收下）
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-5.6, 0.0, ROW_Z))
	var mage: Pawn = spawner.call("spawn_soldier", GameDefs.settler_mage_def(), Vector3(-2.1, 0.0, ROW_Z - 0.4))
	var archer: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(0.0, 0.0, ROW_Z - 0.6))
	var assassin: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(), Vector3(4.9, 0.0, ROW_Z - 0.4))
	var raider: Pawn = spawner.call("spawn_raider", Vector3(8.4, 0.0, ROW_Z), GameDefs.raider_def())
	var dummy_w: Pawn = _spawn_dummy(spawner, Vector3(-5.6, 0.0, ROW_Z + 2.0))
	var dummy_m: Pawn = _spawn_dummy(spawner, Vector3(-2.1, 0.0, ROW_Z + 4.6))
	var dummy_a: Pawn = _spawn_dummy(spawner, Vector3(0.0, 0.0, ROW_Z + 4.8))
	var dummy_s: Pawn = _spawn_dummy(spawner, Vector3(4.9, 0.0, ROW_Z + 1.8))
	var dummy_r: Pawn = _spawn_dummy(spawner, Vector3(8.4, 0.0, ROW_Z + 1.5))
	for _i in 6:
		await get_tree().physics_frame

	# 全员面向各自目标，直接走真实攻击管线（配对特效 + 命中反馈同帧生成）
	_face(warrior, dummy_w)
	_face(mage, dummy_m)
	_face(archer, dummy_a)
	_face(assassin, dummy_s)
	_face(raider, dummy_r)
	warrior.attacker.try_attack(dummy_w)
	warrior.play_anim(&"fight")
	mage.attacker.try_attack(dummy_m)
	mage.play_anim(&"shoot")
	archer.attacker.try_attack(dummy_a)
	archer.play_anim(&"shoot")
	assassin.attacker.try_attack(dummy_s)
	assassin.play_anim(&"fight")

	# 播到动作中段（约 0.2s）后把动画速度归零定格姿态，网格特效统一锁在同一进度
	for _i in 13:
		await get_tree().physics_frame
	VFXManager.debug_anim_progress = 0.42
	for p: Pawn in [warrior, mage, archer, assassin]:
		if p.model_rig != null and p.model_rig.anim_player != null:
			p.model_rig.anim_player.speed_scale = 0.0
		_freeze(p)
	for d: Pawn in [dummy_w, dummy_m, dummy_a, dummy_s, dummy_r]:
		_freeze(d)
	# 掠夺者延后出手：命中火星是实时粒子（0.34s 寿命），晚 6 帧触发 → 截图时正好炸开
	raider.attacker.try_attack(dummy_r)
	raider.play_anim(&"fight")
	for _i in 6:
		await get_tree().physics_frame
	if raider.model_rig != null and raider.model_rig.anim_player != null:
		raider.model_rig.anim_player.speed_scale = 0.0
	_freeze(raider)
	print("poses: warrior=", warrior.model_rig.anim_player.current_animation,
		" mage=", mage.model_rig.anim_player.current_animation,
		" archer=", archer.model_rig.anim_player.current_animation,
		" assassin=", assassin.model_rig.anim_player.current_animation,
		" raider=", raider.model_rig.anim_player.current_animation)

	# 定格取景
	TimeManager.set_speed(0.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		var pause_overlay := hud.get("pause_overlay") as CanvasItem
		if pause_overlay != null:
			pause_overlay.visible = false
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/v26-anim-vfx-sync.png")
	print("saved artifacts/v26-anim-vfx-sync.png")
	get_tree().quit()


func _face(p: Node3D, target: Node3D) -> void:
	var dir: Vector3 = target.global_position - p.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		p.look_at_target(dir.normalized())


func _spawn_dummy(spawner: Node, at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 600.0
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	return spawner.call("spawn_raider", at, d)


## 冻结单位：本体与状态机都停（与 CombatVfxTest 同款）。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)
