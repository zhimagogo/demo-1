extends Node3D
## v29 描边 A/B 探针（同一机位、同一帧姿态）：
##   godot --path . tools/v29_outline_ab.tscn
## A：队伍绿标（描边副本带 Skin，修复后）｜B：把描边副本的 Skin 清空（复现旧 bug）
## 产出 artifacts/v29-outline-ab-{a_skin,b_noskin}.png —— 肉眼可判「巨大绿色幽灵」是否真被修掉。

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
	var hud := _main.get_node_or_null("HUD")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	_pet = spawner.call("spawn_dragon", GameDefs.dragon_obsidian_def(), Vector3(18.0, 0.0, -12.0))
	_pet.follow_leader = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			(n as Hero).global_position = Vector3(80.0, 0.0, 80.0)
			(n as Hero).set_physics_process(false)
	for i in 20:
		await get_tree().physics_frame
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	var rig := _pet.get_node_or_null("ModelRig") as Node3D
	_pet.set_squad_mark(true)
	await get_tree().physics_frame
	var outlines: Array = rig.get("_outline_meshes")
	var body: MeshInstance3D = _find_body(rig)
	print("outline=", outlines.size(), " body.skin=", body.skin)
	var dup: MeshInstance3D = outlines[0] as MeshInstance3D
	print("dup.skin=", dup.skin, " dup.skeleton=", dup.skeleton)
	await _shot("v29-outline-ab-a_skin.png")
	dup.skin = null            # 复现旧 bug：只有 skeleton 路径、没有 inverseBindMatrices
	await _shot("v29-outline-ab-b_noskin.png")
	dup.skin = body.skin
	await _shot("v29-outline-ab-c_skin_again.png")
	print("AB DONE")
	get_tree().quit()


func _find_body(rig: Node) -> MeshInstance3D:
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and not String(n.name).begins_with("Outline"):
			return n as MeshInstance3D
		for c in n.get_children():
			stack.append(c)
	return null


func _shot(fname: String) -> void:
	_cam.global_position = _pet.global_position + Vector3(7.0, 2.2, -5.5)
	_cam.look_at(_pet.global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP)
	for i in 3:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s" % fname)
	print("saved ", fname)
