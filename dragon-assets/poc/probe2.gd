extends SceneTree
## 龙模型落地探针 v2（dragon-poc）
## 用法：godot --headless --path . --script dragon-assets/poc/probe2.gd -- <glb/gltf 路径>
##
## 与 probe.gd 的差别（重要）：probe.gd 用 mi.global_transform 量包围盒，但在 SceneTree._init 期
## 挂树可能未生效（实测报 "Condition !is_inside_tree() is true"），global_transform 退化为 IDENTITY
## → 丢掉 GLTF 根节点的缩放，测出的尺寸偏小。本探针改为**手工沿父链累乘变换**（不依赖挂树），
## 并额外打印每个节点的 scale，便于核对「1.668× 差异」到底来自哪一层。

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else ""
	if path.is_empty():
		print("用法: --script dragon-assets/poc/probe2.gd -- <模型路径>")
		quit(1)
		return
	print("=== 探针 v2：", path)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), state)
	print("GLTFDocument.append_from_file err=", err)
	if err != OK:
		print("解析失败，退出")
		quit(1)
		return
	var root := doc.generate_scene(state)
	_report(root, state)


func _report(root: Node3D, state: GLTFState) -> void:
	print("模型根节点名: ", root.name, "  类型: ", root.get_class())
	_dump_transform(root, 0)

	var meshes: Array[MeshInstance3D] = []
	var skels: Array[Skeleton3D] = []
	_collect(root, meshes, skels)

	var tris := 0
	var surfaces := 0
	var first := true
	var aabb := AABB()
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
				var key := bm.resource_name if bm.resource_name != "" else "mat%d" % mats.size()
				mats[key] = Color(bm.albedo_color).to_html(false)
				if bm.albedo_texture != null:
					textured += 1
		# 沿父链累乘到 root（root 自身不含在链内，即「模型以自身原点为原点的局部尺寸」）
		var xf := _relative_transform(mi, root)
		var box := xf * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false

	print("MeshInstance3D 数: ", meshes.size(), " 表面数: ", surfaces)
	print("三角面数: ", tris)
	print("Skeleton3D 数: ", skels.size(), " 骨骼数: ", (skels[0].get_bone_count() if skels.size() > 0 else 0))
	if skels.size() > 0:
		var sk := skels[0]
		var names: PackedStringArray = []
		for i in mini(sk.get_bone_count(), 12):
			names.append(sk.get_bone_name(i))
		print("前 12 根骨骼: ", names)
	print("材质数: ", mats.size(), " 带 albedo 贴图的材质数: ", textured)
	print("材质 albedo: ", mats)
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			if m is BaseMaterial3D:
				var bm := m as BaseMaterial3D
				print("  surface ", s, " 材质 ", bm.resource_name, " albedo_color=", bm.albedo_color,
					" albedo_texture=", (bm.albedo_texture.resource_path if bm.albedo_texture != null else "<无>"),
					" tex_size=", (bm.albedo_texture.get_size() if bm.albedo_texture != null else Vector2i.ZERO),
					" transparent=", bm.transparency, " cull=", bm.cull_mode)
	# 逐顶点真值：mesh 的 ARRAY_VERTEX 原始 min/max（不信任 mesh.get_aabb() 的存储值，
	# 它在「骨架缩放 ≠ 1」的 FBX→glTF 转换产物上可能与骨骼空间不自洽）。
	var vmin := Vector3(INF, INF, INF)
	var vmax := Vector3(-INF, -INF, -INF)
	var vcount := 0
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			vcount += verts.size()
			for v in verts:
				vmin = Vector3(minf(vmin.x, v.x), minf(vmin.y, v.y), minf(vmin.z, v.z))
				vmax = Vector3(maxf(vmax.x, v.x), maxf(vmax.y, v.y), maxf(vmax.z, v.z))
	print("顶点数: ", vcount)
	print("顶点真值包围盒（mesh 空间）min=", vmin, " max=", vmax, " 尺寸=", vmax - vmin)
	print("mesh.get_aabb() 存储值: 位置=", meshes[0].get_aabb().position, " 尺寸=", meshes[0].get_aabb().size) if meshes.size() > 0 else null
	print("包围盒（模型局部，未含根变换）位置: ", aabb.position, " 尺寸: ", aabb.size, "（x 宽 / y 高 / z 长）")
	# 含根变换的世界尺寸（PawnModelRig 把 scene 挂在 rig 下，rig.scale=model_scale）
	var world := root.transform * aabb
	print("包围盒（含根变换）位置: ", world.position, " 尺寸: ", world.size)

	var aps: Array[AnimationPlayer] = []
	_collect_anim(root, aps)
	var total := 0
	for ap in aps:
		var names := ap.get_animation_list()
		total += names.size()
		print("AnimationPlayer[", ap.name, "] 动画 ", names.size(), " 条（库：", ap.get_animation_library_list(), "）：")
		for n in names:
			var a := ap.get_animation(n)
			var loop := "loop" if a.loop_mode != Animation.LOOP_NONE else "once"
			print("   - ", n, "  时长 ", "%.3fs" % a.length, " 轨道 ", a.get_track_count(), " ", loop)
	print("GLTFState 报告动画数: ", state.get_animations().size())
	print("动画总数: ", total)
	quit(0)


func _dump_transform(n: Node, depth: int) -> void:
	if depth > 3:
		return
	if n is Node3D:
		var n3 := n as Node3D
		print("  ".repeat(depth), "[", n.get_class(), "] ", n.name,
			" scale=", n3.scale, " origin=", n3.position, " rot_euler_deg=", n3.rotation_degrees)
	for c in n.get_children():
		_dump_transform(c, depth + 1)


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


func _relative_transform(n: Node3D, stop: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
