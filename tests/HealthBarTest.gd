extends Node
## godot --headless --path . tests/HealthBarTest.tscn --fixed-fps 60
## 可视验收：godot --path . tests/HealthBarTest.tscn -- --capture
var _failures := 0
var _checks := 0
var _main: Node
var _cam: Camera3D
var _actors: Array[Pawn] = []


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)


func _freeze(pawn: Pawn) -> void:
	pawn.set_physics_process(false)
	pawn.state_machine.set_physics_process(false)
	if pawn.model_rig.anim_player != null:
		pawn.model_rig.anim_player.pause()
	pawn.speech_bubble.set_process(false)
	pawn.speech_bubble.hide_now()


func _tick(delta: float = 0.2) -> void:
	for pawn in _actors:
		pawn.health_bar._process(delta)


func _width(bar: HealthBar3D) -> float:
	var left := _cam.unproject_position(bar.to_global(Vector3(-HealthBar3D.FULL_W * 0.5, 0, 0)))
	var right := _cam.unproject_position(bar.to_global(Vector3(HealthBar3D.FULL_W * 0.5, 0, 0)))
	return right.distance_to(left)


func _run() -> void:
	get_window().size = Vector2i(1440, 900)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	TimeManager.begin(12)
	TimeManager.set_speed(1.0)
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	controller.set_process(false)
	controller.set_physics_process(false)
	world.get_node("IsometricCamera").set_process(false)
	world.get_node("ThirdPersonCamera").set_process(false)
	(_main.get_node("HUD") as CanvasLayer).visible = false
	var hero := controller.hero
	hero.release_squad()
	for pawn in get_tree().get_nodes_in_group("player_unit") + get_tree().get_nodes_in_group("enemy"):
		if pawn is Pawn:
			_freeze(pawn)
	var spawner := world.get_node("PawnSpawner")
	var ally: Pawn = spawner.spawn_soldier(GameDefs.settler_warrior_def(), Vector3(-2, 0, -24))
	var enemy: Pawn = spawner.spawn_raider(Vector3(2, 0, -24))
	var boss: Pawn = spawner.spawn_raider(Vector3(6, 0, -24), GameDefs.raider_boss_def())
	hero.global_position = Vector3(-6, 0, -24)
	_actors = [hero, ally, enemy, boss]
	for pawn in _actors:
		_freeze(pawn)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	world.add_child(_cam)
	_cam.global_position = Vector3(0, 4, -13)
	_cam.look_at(Vector3(0, 2, -24))
	_cam.current = true
	SelectionManager.hero_mode_active = true
	await get_tree().physics_frame
	_tick()
	_check(not hero.health_bar.visible, "full-health hero stays clear in third-person")
	_check(not ally.health_bar.visible, "idle full-health ally stays clear in third-person")
	_check(enemy.health_bar.visible, "nearby full-health enemy remains readable")
	_check(boss.health_bar.visible, "nearby boss bar visible")
	_check(boss.health_bar.global_position.y - boss.global_position.y >= HealthBar3D.RISE * boss.def.model_scale, "boss bar follows model height")
	_check(boss.health_bar.head_height() >= boss.health_bar._model_top(boss.model_rig, Transform3D.IDENTITY) + 0.27, "boss bar clears actual model bounds")
	_check(is_equal_approx(enemy.health_bar._ratio, 1.0), "definition HP applied after ready synchronizes bar")
	_check(is_equal_approx(ally.health_bar._base_color.r, HealthBar3D.COLOR_ALLY.r), "ally faction color")
	_check(is_equal_approx(enemy.health_bar._base_color.g, HealthBar3D.COLOR_ENEMY.g), "enemy faction color")
	_check(is_equal_approx(hero.health_bar._base_color.g, HealthBar3D.COLOR_HERO.g), "hero color")

	ally.set_selected(true)
	_tick()
	_check(ally.health_bar.visible, "selection reveals full-health ally")
	ally.set_selected(false)
	ally.follow_leader = hero
	_tick()
	_check(ally.health_bar.visible, "gathered member retains bar")
	ally.follow_leader = null
	ally.combat_target = enemy
	_tick()
	_check(ally.health_bar.visible, "engaged ally retains bar")
	ally.combat_target = null
	# v20 属性系统：战士有防御（受伤 × 80/(80+防)），要打到「半血」需按防御补偿入参
	# （本套测的是血条可视化，不是战斗数值——让落点精确 50% 才是断言本意）。
	ally.health.apply_damage(ally.health.max_hp * 0.5 / ally.defense_factor())
	_tick(0.05)
	var bar := ally.health_bar
	_check(bar.visible and is_equal_approx(bar._ratio, 0.5), "damage reveals accurate half-health fill")
	_check(bar._chip.visible and is_equal_approx(bar._chip_ratio, 1.0), "damage holds previous HP briefly")
	_tick(0.3)
	_tick(0.2)
	_check(bar._chip_ratio < 1.0 and bar._chip_ratio > 0.5, "damage trail drains toward current HP")
	_tick(1.0)
	_check(not bar._chip.visible and is_equal_approx(bar._chip_ratio, 0.5), "damage trail completes")
	ally.health.heal(ally.health.max_hp)
	_tick(0.1)
	_check(bar.visible and not bar._chip.visible and is_equal_approx(bar._ratio, 1.0), "healing clears trail and briefly retains bar")
	_tick(3.5)
	_check(not bar.visible, "fully healed idle ally returns to hidden")

	# 同上：按防御补偿，落点保持原意图的「剩 20% 低血警示区」
	ally.health.apply_damage(ally.health.max_hp * 0.8 / ally.defense_factor())
	_tick()
	_check(bar._fg.modulate.r > bar._base_color.r, "low health changes toward warning color")
	var fg_left := bar._fg.to_global(Vector3(-HealthBar3D.FULL_W * 0.5, 0, 0))
	var slot_left := bar.to_global(Vector3(-HealthBar3D.FULL_W * 0.5, 0, 0))
	_check(_cam.unproject_position(fg_left).distance_to(_cam.unproject_position(slot_left)) < 0.01, "fill left edge locks to slot")
	var old_width := _width(bar)
	_cam.global_position += Vector3(0, 3, 10)
	_cam.look_at(Vector3(0, 2, -24))
	_cam.rotate_object_local(Vector3.FORWARD, 0.15)
	ally.rotation.y = 1.8
	_tick()
	fg_left = bar._fg.to_global(Vector3(-HealthBar3D.FULL_W * 0.5, 0, 0))
	slot_left = bar.to_global(Vector3(-HealthBar3D.FULL_W * 0.5, 0, 0))
	_check(_cam.unproject_position(fg_left).distance_to(_cam.unproject_position(slot_left)) < 0.01, "turning unit / tilted camera keeps fill aligned")
	_check(absf(_width(bar) - old_width) < 0.2, "camera distance does not inflate or shrink screen bar")
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_tick()
	_check(absf(_width(bar) - old_width) < 0.2, "horizontal FOV sizing retains pixel width")
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 24.0
	_tick()
	_check(absf(_width(bar) - old_width) < 0.2, "orthographic bar sizing retains pixel width")
	_cam.size = 30.0
	_tick()
	_check(absf(_width(bar) - old_width) < 0.2, "orthographic zoom retains pixel width")
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.global_position = Vector3(0, 4, -13)
	_cam.look_at(Vector3(0, 2, -24))
	enemy.set_aim_highlight(true)
	_tick()
	_check(enemy.health_bar._emphasized and enemy.health_bar._edge.modulate.g > 0.5, "aim / focus highlights bar border")
	_check(_width(enemy.health_bar) > old_width * 1.15, "priority target bar slightly larger")
	enemy.set_aim_highlight(false)
	_tick()
	_check(not enemy.health_bar._emphasized, "aim highlight removal restores bar")

	# 实体墙体遮挡，第三人称隐藏，俯瞰保持 RTS 信息；拆墙后自动恢复。
	var wall := StaticBody3D.new()
	wall.collision_layer = 8
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 10, 0.8)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = Vector3(0, 4, -18)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_tick(0.3)
	_check(not enemy.health_bar.visible and not bar.visible, "third-person bars do not reveal units through wall")
	SelectionManager.hero_mode_active = false
	_tick()
	_check(enemy.health_bar.visible and hero.health_bar.visible, "tactical mode retains overview through buildings")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	SelectionManager.hero_mode_active = true
	_tick(0.3)
	_check(enemy.health_bar.visible, "wall removal restores enemy bar")

	var original := enemy.global_position
	enemy.global_position = Vector3(0, 0, -70)
	_tick()
	_check(not enemy.health_bar.visible, "distant enemy bar culled")
	enemy.global_position = _cam.global_position + _cam.global_basis.z * 3.0
	_tick()
	_check(not enemy.health_bar.visible, "behind-camera bar hidden")
	enemy.global_position = original
	_tick()
	enemy.health.apply_damage(enemy.health.max_hp * 2.0)
	_check(not enemy.health_bar.visible, "fatal damage hides bar in same signal")
	enemy.health.heal(enemy.health.max_hp)
	_tick()
	_check(not enemy.health_bar.visible, "healing a corpse cannot restore its bar")
	hero.health.apply_damage(50.0)
	_tick()
	_check(hero.health_bar.visible, "injured hero reveals overhead bar")
	hero.is_dead_flag = true
	hero.health_bar._on_died()
	hero.is_dead_flag = false
	hero.health.current_hp = hero.health.max_hp * 0.5
	hero.health.health_changed.emit(hero.health.current_hp, hero.health.max_hp)
	_tick()
	_check(hero.health_bar.visible and is_equal_approx(hero.health_bar._ratio, 0.5), "revived hero restores accurate bar")
	ally.visible = false
	_tick()
	_check(not bar.visible, "hidden model cannot leave floating bar")
	ally.visible = true

	if "--capture" in OS.get_cmdline_user_args():
		_actors.erase(enemy)
		enemy.queue_free()
		await get_tree().process_frame
		await _capture(world, controller, hero, ally, boss, spawner)
	print("HealthBarTest: %d checks, %d failures" % [_checks, _failures])
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _failures > 0 else 0)


func _capture(world: Node3D, controller: HeroController, hero: Hero, ally: Pawn, boss: Pawn, spawner: Node) -> void:
	# 用真实第三人称相机与 HUD 出样张，不用测试专用相机代替实机。
	var normal: Pawn = spawner.spawn_raider(Vector3(2, 0, -24))
	_freeze(normal)
	_actors.append(normal)
	normal.health.apply_damage(normal.health.max_hp * 0.3)
	boss.health.apply_damage(boss.health.max_hp * 0.6)
	hero.global_position = Vector3(0, 0, -15)
	ally.global_position = Vector3(-2, 0, -17)
	ally.follow_leader = hero
	ally.set_selected(false)
	controller.exit_hero_mode()
	controller.enter_hero_mode()
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	tp.set_process(true)
	tp.yaw = 0.0
	tp.pitch = -0.16
	tp.target_distance = 6.0
	(_main.get_node("HUD") as CanvasLayer).visible = true
	controller.set_process(true)
	hero.order_focus_fire(boss)
	controller._update_enemy_highlights()
	for i in 100:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/health-bars-third-person.png")
	controller.exit_hero_mode()
	controller.set_process(false)
	(_main.get_node("HUD") as CanvasLayer).visible = false
	_cam.current = true
	_cam.global_position = Vector3(0, 9, -8)
	_cam.look_at(Vector3(0, 1, -23))
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/health-bars-tactical.png")
	print("Saved health-bars-third-person.png / health-bars-tactical.png")
