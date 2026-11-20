extends SceneTree
## 龙模型落地探针（Lead 独立验证用）
## 用法：godot --headless --path . --script dragon-assets/poc/probe.gd -- <glb 路径>
## 只读打印客观事实：网格 / 三角面 / 骨骼 / 动画名 / 包围盒 / 材质与贴图。

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://dragon-assets/poc/quaternius_dragon_evolved_polypizza.glb"
	print("=== 探针：", path)
	var packed := load(path) as PackedScene
	if packed == null:
		# 回退：GLTFDocument 运行时解析
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
		print("GLTFDocument 回退 err=", err)
		if err != OK:
			print("加载失败，退出")
			quit(1)
			return
		var root_node := doc.generate_scene(state)
		_report(root_node, state.get_animations().size())
		quit(0)
		return
	var root := packed.instantiate()
	_report(root, -1)
	quit(0)


func _report(root: Node3D, anim_hint: int) -> void:
	# 注意：extends SceneTree 时没有 add_child，必须挂到 tree root 上才能拿到 global_transform
	get_root().add_child(root)
	var meshes: Array[MeshInstance3D] = []
	var skels: Array[Skeleton3D] = []
	_collect(root, meshes, skels)

	var tris := 0
	var surfaces := 0
	var aabb := AABB()
	var first := true
	var mats := {}
	var textured := 0
	for mi in meshes:
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				mats[bm.resource_name if bm.resource_name != "" else "mat%d" % mats.size()] = Color(bm.albedo_color).to_html(false)
				if bm.albedo_texture != null:
					textured += 1
		var box := mi.get_aabb()
		var world := mi.global_transform * box
		aabb = world if first else aabb.merge(world)
		first = false

	print("MeshInstance3D 数: ", meshes.size(), " 表面数: ", surfaces)
	print("三角面数: ", tris)
	print("Skeleton3D 数: ", skels.size(), " 骨骼数: ", (skels[0].get_bone_count() if skels.size() > 0 else 0))
	print("材质数: ", mats.size(), " 带 albedo 贴图的材质数: ", textured)
	print("材质 albedo: ", mats)
	print("包围盒位置: ", aabb.position, " 尺寸: ", aabb.size, "（x 宽 / y 高 / z 长）")

	var aps: Array[AnimationPlayer] = []
	_collect_anim(root, aps)
	var total := 0
	for ap in aps:
		var names := ap.get_animation_list()
		total += names.size()
		print("AnimationPlayer[", ap.name, "] 动画 ", names.size(), " 条：")
		for n in names:
			var a := ap.get_animation(n)
			print("   - ", n, "  时长 ", "%.2fs" % a.length, " 轨道 ", a.get_track_count())
	if anim_hint >= 0:
		print("（GLTFState 报告动画数: ", anim_hint, "）")
	print("动画总数: ", total)


func _collect(n: Node, meshes: Array[MeshInstance3D], skels: Array[Skeleton3D]) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	if n is Skeleton3D:
		skels.append(n)
	for c in n.get_children():
		_collect(c, meshes, skels)


func _collect_anim(n: Node, aps: Array[AnimationPlayer]) -> void:
	if n is AnimationPlayer:
		aps.append(n)
	for c in n.get_children():
		_collect_anim(c, aps)
