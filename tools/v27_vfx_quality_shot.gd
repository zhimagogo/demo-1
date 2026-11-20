extends Node
## v27 交付留档工具：特效品质 + 丰富度样张（暴击星芒 / 升级金环 / 治疗荧光 / 死亡魂魄 /
## 建造尘环，与挥击刀光同框）。
##
## 运行：
##   godot --path . tools/v27_vfx_quality_shot.tscn   # → artifacts/v27-vfx-quality.png
##
## 构图要点：所有展示位排在屏幕中偏右（避开左上任务卡）；每处特效点让到单位身侧 /
## 上方——billboard 材质会被前景身体遮挡（EffectDef.no_depth_test 未接 shader 材质），
## 摆位必须「特效在单位旁边，不在单位身后」。

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
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day

	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	hero.global_position = Vector3(0.6, 0.0, -38.5)
	hero.velocity = Vector3.ZERO
	hero.release_squad()
	hero.set_party([])
	controller.enter_hero_mode()
	var hero_placeholder := hero.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if hero_placeholder != null:
		hero_placeholder.visible = false
	if hero.model_rig != null:
		hero.model_rig.visible = false
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.yaw = PI
	tp.pitch = -0.3
	tp.target_distance = 3.6

	# 展示位（世界 +X = 画面左）：战士+木桩（暴击）在中右，法师（升级）居中，
	# 游侠（治疗）中左，刺客（建造）左，濒死野怪（魂魄）最左但不进任务卡遮罩
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-5.2, 0.0, ROW_Z + 0.6))
	var mage: Pawn = spawner.call("spawn_soldier", GameDefs.settler_mage_def(), Vector3(-1.6, 0.0, ROW_Z))
	var healer: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(1.8, 0.0, ROW_Z - 0.4))
	var assassin: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(), Vector3(3.0, 0.0, ROW_Z + 0.7))
	var dummy_w: Pawn = _spawn_dummy(spawner, Vector3(-3.4, 0.0, ROW_Z + 2.4))
	var dying: Pawn = _spawn_dummy(spawner, Vector3(4.6, 0.0, ROW_Z + 1.4))
	for _i in 6:
		await get_tree().physics_frame

	# 先全部冻结摆位（确定性构图），再触发特效——单位不再走位遮挡
	for p: Pawn in [warrior, mage, healer, assassin, dummy_w, dying]:
		_freeze(p)

	# ① 暴击星芒：战士强制暴击出斧（斧光 + 星芒 + 命中火星同帧）
	_face(warrior, dummy_w)
	warrior.crit_stat = 1.0
	warrior.attacker._cooldown_left = 0.0
	warrior.attacker.try_attack(dummy_w)
	warrior.play_anim(&"fight")
	# ② 升级金环：法师灌经验升级（金环上浮 + 金屑）
	mage.gain_xp(mage.xp_to_next())
	# ③ 治疗荧光：游侠身侧（右肩外）冒绿色光点
	VFXManager.spawn_effect(&"heal_mote", healer.global_position + Vector3(0.9, 0.9, -0.3), 0.0,
		{"lifetime": 3.0})
	# ④ 死亡魂魄：野怪击杀 → 青白光点从尸身升起
	dying.health.apply_damage(9999.0, null)
	# ⑤ 建造尘环：刺客身前空地（画面上靠镜头一侧）落尘土 + 暗金环
	VFXManager.spawn_effect(&"build_dust", assassin.global_position + Vector3(-0.6, 0.5, -1.4), 0.0,
		{"amount": 26, "lifetime": 3.0})
	VFXManager.spawn_effect(&"hit_ring", assassin.global_position + Vector3(-0.6, 0.2, -1.4), 0.0,
		{"color": Color(0.85, 0.72, 0.5), "lifetime": 3.0})
	# 展示位加长寿命：暴击星芒 / 升级金环由组件内部触发（默认 0.45/0.6s，等不到截图），
	# 按同款 def 各补一枚长寿命版供定格（真实短寿命版已照常在触发点炸过）
	VFXManager.spawn_effect(&"crit_burst", dummy_w.global_position + Vector3(0.0, 1.3, 0.0), 0.0,
		{"lifetime": 3.0})
	VFXManager.spawn_effect(&"levelup_ring", mage.global_position + Vector3(0.0, 1.15, 0.0), 0.0,
		{"lifetime": 3.0})

	# 网格类特效统一锁在同一进度（星芒旋开 / 金环上浮 / 刀光扫动）
	for _i in 10:
		await get_tree().physics_frame
	VFXManager.debug_anim_progress = 0.45
	for p: Pawn in [warrior, mage, healer, assassin]:
		if p.model_rig != null and p.model_rig.anim_player != null:
			p.model_rig.anim_player.speed_scale = 0.0
	# 粒子类（治疗荧光 / 死亡魂魄 / 建造尘土）不可冻结——定格前再补一轮新鲜的
	VFXManager.spawn_effect(&"heal_mote", healer.global_position + Vector3(0.9, 1.1, -0.3), 0.0,
		{"lifetime": 3.0})
	VFXManager.spawn_effect(&"build_dust", assassin.global_position + Vector3(-0.6, 0.45, -1.4), 0.0,
		{"amount": 22, "lifetime": 3.0})
	print("crit=", int(VFXManager.stat_spawned_by_id.get(&"crit_burst", 0)) >= 1,
		" levelup=", int(VFXManager.stat_spawned_by_id.get(&"levelup_ring", 0)) >= 1,
		" wisp=", int(VFXManager.stat_spawned_by_id.get(&"death_wisp", 0)) >= 1)

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
	img.save_png("res://artifacts/v27-vfx-quality.png")
	print("saved artifacts/v27-vfx-quality.png")
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
