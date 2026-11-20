extends Node
## v19 交付留档工具：四职业小兵技能同屏样张（暴风雪 / 血怒 / 快速射击易伤 / 背刺）。
##
## 运行：
##   godot --path . tools/v19_skill_shot.tscn    # → artifacts/v19-settler-skills.png
##
## 布景：城外北侧空地一排四职业小兵各对一只木桩野怪直接施放技能
## （不走 AI 走位，保证构图确定）：法师暴风雪落雪减速、战士血怒红环光环、
## 游侠三连金箭 + 目标易伤标记、刺客瞬移背刺到目标身后。定格后截图。

const ROW_Z: float = -30.0

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

	# 布景：主角在场地后方当参照，相机拉高俯视整排技能
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero
	hero.global_position = Vector3(0.0, 0.0, -40.0)
	hero.velocity = Vector3.ZERO
	hero.release_squad()
	hero.set_party([])
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.yaw = PI            # 相机看向 +Z（技能展示区）
	tp.pitch = -0.52
	tp.target_distance = 10.5

	# 四职业小兵 + 各自的木桩（高血低攻不逃）
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-15.0, 0.0, ROW_Z))
	var mage: Pawn = spawner.call("spawn_soldier", GameDefs.settler_mage_def(), Vector3(-5.0, 0.0, ROW_Z))
	var archer: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(5.0, 0.0, ROW_Z))
	var assassin: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(), Vector3(15.0, 0.0, ROW_Z))
	var dummy_w: Pawn = _spawn_dummy(spawner, Vector3(-15.0, 0.0, ROW_Z + 2.5))
	var dummy_m: Pawn = _spawn_dummy(spawner, Vector3(-5.0, 0.0, ROW_Z + 7.0))
	var dummy_a: Pawn = _spawn_dummy(spawner, Vector3(5.0, 0.0, ROW_Z + 7.0))
	var dummy_s: Pawn = _spawn_dummy(spawner, Vector3(15.0, 0.0, ROW_Z + 4.5))
	for _i in 6:
		await get_tree().physics_frame

	# 直接施放四个技能（构象确定：不依赖 AI 走位时机）
	warrior.skill_comp.try_cast(dummy_w)
	mage.skill_comp.try_cast(dummy_m)
	archer.skill_comp.try_cast(dummy_a)
	assassin.skill_comp.try_cast(dummy_s)

	# 等技能表现展开：暴风雪首跳减速标记 / 金箭命中 / 光环升起
	for _i in 50:
		await get_tree().physics_frame
	_freeze(warrior); _freeze(mage); _freeze(archer); _freeze(assassin)
	_freeze(dummy_w); _freeze(dummy_m); _freeze(dummy_a); _freeze(dummy_s)
	print("skills cast: rage=", warrior.skill_comp.is_raging(),
		" zone=", get_tree().get_first_node_in_group("skill_blizzard_zone") != null,
		" vuln=", dummy_a.vuln_active(),
		" slow=", dummy_m.slow_active(),
		" backstab_pos=", assassin.global_position)

	# 定格取景
	TimeManager.set_speed(0.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		var pause_overlay := hud.get("pause_overlay") as CanvasItem
		if pause_overlay != null:
			pause_overlay.visible = false
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/v19-settler-skills.png")
	print("saved artifacts/v19-settler-skills.png")
	get_tree().quit()


func _spawn_dummy(spawner: Node, at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 600.0
	d.attack_damage = 2.0
	d.flee_hp_ratio = 0.0
	return spawner.call("spawn_raider", at, d)


## 冻结单位：本体与状态机都停（与 CombatVfxTest 同款），只留技能表现继续播。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)
