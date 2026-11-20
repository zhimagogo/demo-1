extends Node
## v29 龙模型 Rig / 描边结构探针（纯打印，不出图）：
##   godot --path . tools/v29_dragon_rig_probe.tscn
## 目的：查清「队伍绿标 / 红色瞄标 = 巨大绿色幽灵」的根因——
## 逐 MeshInstance3D 打印 skeleton 路径是否可解析 + 皮肤 / 描边副本的世界 AABB 对比。

var _main: Node
var _pet: DragonPet


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	_pet = spawner.call("spawn_dragon", GameDefs.dragon_obsidian_def(), Vector3(18.0, 0.0, -12.0))
	_pet.follow_leader = null
	for i in 10:
		await get_tree().physics_frame
	_dump("before outline")
	_pet.set_squad_mark(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_dump("after outline ON")
	_pet.set_squad_mark(false)
	await get_tree().physics_frame
	print("PROBE DONE")
	get_tree().quit()


func _dump(tag: String) -> void:
	print("==================== ", tag)
	var rig := _pet.get_node_or_null("ModelRig") as Node3D
	if rig == null:
		print("no rig")
		return
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var skel_path := mi.skeleton
			var resolved := mi.get_node_or_null(skel_path) if not skel_path.is_empty() else null
			var eff := resolved if resolved != null else _nearest_skeleton(mi)
			print("%s | path=%s | skeleton=%s | surfaces=%d | visible=%s | aabb_local=%s" % [
				String(mi.get_path()).replace("/root/", ""), String(skel_path),
				String(eff.get_path()) if eff != null else "<NONE>",
				mi.mesh.get_surface_count() if mi.mesh != null else -1,
				str(mi.visible), str(mi.get_aabb().size)])
		for c in n.get_children():
			stack.append(c)
	# 世界 AABB：皮肤本体 vs 描边副本
	var body := _merged_aabb(rig, "Outline_", false)
	var outline := _merged_aabb(rig, "Outline_", true)
	print("  BODY   world aabb pos=%s size=%s" % [str(body.position.round()), str(body.size.round())])
	print("  OUTL   world aabb pos=%s size=%s" % [str(outline.position.round()), str(outline.size.round())])


func _nearest_skeleton(n: Node) -> Skeleton3D:
	var p := n.get_parent()
	while p != null:
		if p is Skeleton3D:
			return p as Skeleton3D
		p = p.get_parent()
	return null


func _merged_aabb(root: Node3D, prefix: String, want_outline: bool) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var is_outline := String(mi.name).begins_with(prefix)
			if mi.mesh != null and is_outline == want_outline and mi.visible:
				var a: AABB = mi.global_transform * mi.get_aabb()
				if first:
					out = a
					first = false
				else:
					out = out.merge(a)
		for c in n.get_children():
			stack.append(c)
	return out
