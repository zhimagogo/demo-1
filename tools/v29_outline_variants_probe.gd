extends Node3D
## v29 描边（队伍绿标 / 瞄准红标）渲染变体探针：
##   godot --path . tools/v29_outline_variants_probe.tscn
## 逐项排除：本体单显 / 描边默认 / grow=0 / cull_back / 无深度测试 / 去掉 skeleton 绑定。
## 产出 artifacts/v29-outline-*.png

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
	print("outline meshes=", outlines.size(), " body=", body.name if body != null else "<none>")

	# ① 本体单显
	_show(outlines, false)
	await _shot("v29-outline-body-only.png")
	# ② 描边默认（grow 0.045 / cull_front）
	body.visible = false
	_show(outlines, true)
	await _shot("v29-outline-default.png")
	# ③ grow = 0
	for m in outlines:
		(m.material_override as StandardMaterial3D).grow = false
	await _shot("v29-outline-nogrow.png")
	# ④ cull_back
	for m in outlines:
		(m.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
	await _shot("v29-outline-cullback.png")
	# ⑤ 无深度测试 + cull_back
	for m in outlines:
		(m.material_override as StandardMaterial3D).no_depth_test = true
	await _shot("v29-outline-nodepth.png")
	# ⑥ 去掉 skeleton 绑定（应变成「跟随骨骼节点的静态网格」）
	for m in outlines:
		(m as MeshInstance3D).skeleton = NodePath()
	await _shot("v29-outline-noskel.png")
	# ⑦ 恢复 skeleton 绑定 + 补上 skin（glTF 蒙皮的 inverseBindMatrices 在 Skin 资源里）
	for m in outlines:
		var mm := m as MeshInstance3D
		mm.skeleton = body.skeleton
		mm.skin = body.skin
		mm.visible = true
	body.visible = true
	await _shot("v29-outline-withskin.png")
	body.visible = false
	await _shot("v29-outline-withskin-only.png")
	print("body.skin=", body.skin, " skeleton=", body.skeleton)
	print("PROBE DONE")
	get_tree().quit()


func _show(ms: Array, on: bool) -> void:
	for m in ms:
		if is_instance_valid(m):
			(m as MeshInstance3D).visible = on


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
	_cam.global_position = _pet.global_position + Vector3(8.0, 4.5, 8.0)
	_cam.look_at(_pet.global_position + Vector3(0.0, 1.4, 0.0), Vector3.UP)
	for i in 3:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s" % fname)
	print("saved ", fname)
