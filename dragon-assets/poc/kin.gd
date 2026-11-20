extends Node3D
## 龙模型「朝向 / 迈步方向」运动学探针（dragon-poc）
## 用法：godot --headless --path . dragon-assets/poc/kin.tscn -- --model <路径>
##
## 为什么不用肉眼猜：模型的「前方」必须用**骨架运动学**判定——头部/前肢在一次攻击里
## 朝哪个 -Z/+Z 方向探出、行走动画里腿朝哪个方向迈。这里直接播放动画、按采样点读
## Skeleton3D 的 bone global pose（skeleton 局部空间），再乘骨架→模型根的相对变换，
## 得到「模型局部空间」里的坐标——正好是 PawnModelRig 挂到 rig 下时模型自身坐标系。

var _model_path := "res://dragon-assets/poc/bocdagla/upload/Dragon2.glb"

# 关注的骨骼关键词 → 用于自动识别头 / 尾 / 前后腿（不硬编码全名，靠前缀匹配）
const WATCH_PREFIXES := ["Head", "Tail", "Neck", "LegFront", "LegBack", "Body", "Wing"]

var _root: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--model" and i + 1 < args.size():
			_model_path = args[i + 1]
	print("=== 运动学探针：", _model_path)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(_model_path), st) != OK:
		print("解析失败")
		get_tree().quit(1)
		return
	_root = doc.generate_scene(st)
	add_child(_root)
	_sk = _find(_root, "Skeleton3D") as Skeleton3D
	_ap = _find(_root, "AnimationPlayer") as AnimationPlayer
	if _sk == null or _ap == null:
		print("缺骨架或动画，退出")
		get_tree().quit(1)
		return

	var to_model := _relative_transform(_sk, _root)
	print("骨架→模型根 变换: basis_scale=", to_model.basis.get_scale(), " origin=", to_model.origin)

	# ---- 1. 全骨骼静止位姿（模型局部空间）----
	print("\n---- 骨骼静止位姿（模型局部空间 xyz，单位=模型自身单位）----")
	for i in _sk.get_bone_count():
		var bn := _sk.get_bone_name(i)
		var p: Vector3 = (to_model * _sk.get_bone_global_pose(i)).origin
		var mark := ""
		for pre in WATCH_PREFIXES:
			if bn.begins_with(pre):
				mark = "  ←"
				break
		if mark != "" or i < 6:
			print("  [%2d] %-22s x=%+8.3f y=%+8.3f z=%+8.3f%s" % [i, bn, p.x, p.y, p.z, mark])

	# ---- 2. 蒙皮后真实包围盒（GPU 同一套数学：pose * rest⁻¹ 加权求和）----
	# 这条同时回答两个问题：① 渲染出来到底多大（决定 model_scale）；
	# ② 骨骼到底有没有真的形变网格（各帧 AABB 若互不相同 = 蒙皮生效）。
	print("\n---- 蒙皮后包围盒（模型空间，含 Armature 缩放）----")
	var rest_box := _skinned_aabb(to_model)
	print("静止位姿: 位置=", rest_box.position, " 尺寸=", rest_box.size)
	# 尺寸校准：项目 KayKit 人类模型（hero/colonist）在同一口径下的身高
	print("\n---- 逐动画蒙皮包围盒（8 采样取并集）----")
	for an in _ap.get_animation_list():
		var anim := _ap.get_animation(an)
		var acc := AABB()
		var firstb := true
		var frames := []
		for s in 8:
			var t := anim.length * float(s) / 7.0
			_ap.play(an)
			_ap.seek(t, true)
			await get_tree().process_frame
			await get_tree().process_frame
			var b := _skinned_aabb(to_model)
			frames.append(b.size)
			acc = b if firstb else acc.merge(b)
			firstb = false
		_ap.stop()
		print("  %-20s 并集尺寸=(%.3f, %.3f, %.3f)  最低点y=%+.3f  最高点y=%+.3f" % [
			an, acc.size.x, acc.size.y, acc.size.z, acc.position.y, acc.position.y + acc.size.y])
		var s0: Vector3 = frames[0]
		var diff := 0.0
		for f in frames:
			diff = maxf(diff, (f - s0).length())
		print("      逐帧尺寸变化（形变证据）: 相对首帧最大差 %.3f" % diff)

	# ---- 3. 逐动画：关注骨骼的位移幅度（哪个骨骼在动、朝哪个轴动）----
	print("\n---- 逐动画骨骼位移幅度（模型空间，逐 8 采样取 min/max）----")
	for an in _ap.get_animation_list():
		var anim2 := _ap.get_animation(an)
		await _sample_report(an, anim2.length, to_model)

	get_tree().quit(0)


## 蒙皮后 AABB：逐顶点按 4 骨骼权重套 pose*rest⁻¹（与 GPU 顶点着色器同一公式）。
func _skinned_aabb(to_model: Transform3D) -> AABB:
	var skin := []
	for j in _sk.get_bone_count():
		skin.append(_sk.get_bone_global_pose(j) * _sk.get_bone_rest(j).affine_inverse())
	var first := true
	var out := AABB()
	for mi in _meshes(_root):
		if mi.mesh == null:
			continue
		var to_sk := _relative_transform(mi, _sk)   # 网格→骨架空间
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for i in verts.size():
				var v := Vector3.ZERO
				if bones.size() >= (i + 1) * 4:
					for k in 4:
						var w := weights[i * 4 + k]
						if w <= 0.0:
							continue
						v += (skin[bones[i * 4 + k]] * verts[i]) * w
				else:
					v = verts[i]   # 无蒙皮数据：原样
				var p := to_model * (to_sk * v)
				var pb := AABB(p, Vector3.ZERO)
				out = pb if first else out.merge(pb)
				first = false
	return out


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var r: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r


func _sample_report(an: String, length: float, to_model: Transform3D) -> void:
	const N := 8
	var idxs := {}
	for pre in WATCH_PREFIXES:
		for i in _sk.get_bone_count():
			if _sk.get_bone_name(i).begins_with(pre):
				idxs[i] = _sk.get_bone_name(i)
	var mins := {}
	var maxs := {}
	var series := {}   # bone → Array[Vector3]
	_ap.play(an)
	for s in N:
		var t := length * float(s) / float(N - 1) if N > 1 else 0.0
		_ap.seek(t, true)
		await get_tree().process_frame
		await get_tree().process_frame
		for i in idxs:
			var p: Vector3 = (to_model * _sk.get_bone_global_pose(i)).origin
			if not mins.has(i):
				mins[i] = p
				maxs[i] = p
				series[i] = []
			mins[i] = Vector3(minf(mins[i].x, p.x), minf(mins[i].y, p.y), minf(mins[i].z, p.z))
			maxs[i] = Vector3(maxf(maxs[i].x, p.x), maxf(maxs[i].y, p.y), maxf(maxs[i].z, p.z))
			(series[i] as Array).append(p)
	_ap.stop()
	# 只打印「确实动了」的骨骼（幅度 > 0.05）
	print("\n[动画] ", an, "  时长 %.2fs" % length)
	var moved := []
	for i in idxs:
		var d: Vector3 = (maxs[i] as Vector3) - (mins[i] as Vector3)
		if maxf(d.x, maxf(d.y, d.z)) > 0.05:
			moved.append([i, d])
	moved.sort_custom(func(a, b): return maxf(a[1].x, maxf(a[1].y, a[1].z)) > maxf(b[1].x, maxf(b[1].y, b[1].z)))
	for e in moved:
		var i: int = e[0]
		var d: Vector3 = e[1]
		print("   %-22s Δx=%6.3f Δy=%6.3f Δz=%6.3f" % [idxs[i], d.x, d.y, d.z])
		var line := "      轨迹 z: "
		for p in series[i]:
			line += "%+.2f " % p.z
		print(line)
		var line2 := "      轨迹 y: "
		for p in series[i]:
			line2 += "%+.2f " % p.y
		print(line2)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _relative_transform(n: Node3D, stop: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
