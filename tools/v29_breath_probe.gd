extends Node3D
## v29 吐息特效隔离探针（不接战斗状态机，直接锁向喷火）：
##   godot --path . tools/v29_breath_probe.tscn
## 产出 artifacts/v29-breath-{top,side,front,far}.png + 火焰像素量测（锥内暖色像素 / 亮度）。

var _main: Node
var _pet: DragonPet
var _cam: Camera3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem"]:
		var node := world.get_node_or_null(n)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	var hud := _main.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			(n as Hero).global_position = Vector3(70.0, 0.0, 70.0)
			(n as Hero).set_physics_process(false)
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	# 选一块开阔地：主城正南的草地上（远离树丛，便于判读火舌）
	_pet = spawner.call("spawn_dragon", GameDefs.dragon_obsidian_def(), Vector3(6.0, 0.0, 16.0))
	_pet.follow_leader = null
	for i in 12:
		await get_tree().physics_frame
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true

	# 锁向正南（本地 -Z）喷火：目标桩放在正前方 10m
	var stake := Node3D.new()
	add_child(stake)
	stake.global_position = _pet.global_position + Vector3(0.0, 0.0, -10.0)
	_pet.rotation.y = 0.0
	# 探针：把吐息时长拉长到 30s，喷吐期间可以做逐层隔离（正式值 2.0s）
	_pet.dragon_def.breath_duration = 30.0
	_pet._breath_cd_left = 0.0
	_pet.state_machine.transition_to("dragon_breath", {"target": stake})
	for i in 30:
		await get_tree().physics_frame
	var st = _pet.state_machine.current_state
	print("state=", st.name, " firing=", st.call("is_firing") if st.has_method("is_firing") else "?",
		" pet=", str(_pet.global_position.round()), " facing=", str(_pet.facing_dir().round()))
	print("layers=", _count_layers())

	await _shot(Vector3(3.2, 1.7, -1.6), Vector3(0.0, 1.3, -2.6), "v29-breath-close.png")
	await _shot(Vector3(6.0, 1.3, -4.0), Vector3(0.0, 1.1, -5.5), "v29-breath-close2.png")
	# 逐层隔离：只留一层，看各自的实际形态 / 分布
	var layers: Array = []
	for c in _pet.get_children():
		if c is GPUParticles3D:
			layers.append(c)
	for c in layers:
		print("  layer ", c.name, " pos=", str((c as GPUParticles3D).position),
			" emitting=", (c as GPUParticles3D).emitting,
			" dir=", str(((c as GPUParticles3D).process_material as ParticleProcessMaterial).direction),
			" spread=", ((c as GPUParticles3D).process_material as ParticleProcessMaterial).spread,
			" v=", ((c as GPUParticles3D).process_material as ParticleProcessMaterial).initial_velocity_min,
			" lifetime=", (c as GPUParticles3D).lifetime,
			" global=", str((c as GPUParticles3D).global_position.round()))
	for i in layers.size():
		for j in layers.size():
			(layers[j] as GPUParticles3D).visible = (i == j)
		await _frames(3)
		await _shot(Vector3(6.0, 1.3, -4.0), Vector3(0.0, 1.1, -5.5), "v29-breath-layer%d.png" % i)
	for c in layers:
		(c as GPUParticles3D).visible = true
	await _shot(Vector3(0.01, 20.0, 0.01), Vector3(0.0, 0.0, -5.0), "v29-breath-top.png")
	await _shot(Vector3(11.0, 3.0, -5.0), Vector3(0.0, 1.0, -6.0), "v29-breath-side.png")
	await _shot(Vector3(2.5, 2.0, 7.0), Vector3(0.0, 1.0, -6.0), "v29-breath-behind.png")
	await _shot(Vector3(6.0, 1.6, -8.5), Vector3(0.0, 1.2, -2.0), "v29-breath-front.png")
	# ---- 火球：侧机位抓「出膛飞行」与「命中爆炸」 ----
	_pet.dragon_def.breath_duration = 2.0
	_pet._breath_cd_left = 60.0
	_pet.state_machine.transition_to("dragon_follow", {})
	var mob: Pawn = spawner.call("spawn_raider", _pet.global_position + Vector3(0.0, 0.0, -11.0),
		GameDefs.raider_def())
	mob.global_position = _pet.global_position + Vector3(0.0, 0.0, -11.0)
	await _frames(3)
	_pet._fire_cd_left = 0.0
	_pet.spawn_fireball(mob, Vector3(0.0, 0.0, -1.0))
	await _frames(14)
	await _shot(Vector3(7.5, 2.0, -4.0), Vector3(0.0, 1.3, -7.0), "v29-fireball-flight.png")
	for i in 60:
		await get_tree().physics_frame
		if get_tree().get_nodes_in_group("projectiles").is_empty():
			break
	await _frames(3)
	await _shot(Vector3(7.5, 2.0, -4.0), Vector3(0.0, 1.3, -7.0), "v29-fireball-impact.png")
	print("PROBE DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _count_layers() -> int:
	var n := 0
	for c in _pet.get_children():
		if c is GPUParticles3D:
			n += 1
	return n


func _shot(offset: Vector3, look_offset: Vector3, fname: String) -> void:
	_cam.global_position = _pet.global_position + offset
	_cam.look_at(_pet.global_position + look_offset, Vector3.UP)
	for i in 3:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s" % fname)
	print("saved ", fname)
