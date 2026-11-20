extends Node3D
## 龙模型「实际渲染尺寸 + 朝向」标定探针（dragon-poc）
## 用法：godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --out res://dragon-assets/poc/preview_scale_check.png
##
## 为什么用渲染量测而不是套蒙皮公式：手工套 GPU 的 pose*rest⁻¹ 在本资产上与静态网格不自洽，
## 所以尺寸标定改用**最不可争辩的口径**——正交相机渲染 + 像素量测：
##   正交相机竖直视野 = size 米，视口高 H 像素 → 每像素 = size / H 米。
##   量出模型不透明像素的竖直跨度 → 直接得到「它在世界里有多高（米）」。
## 参照物：KayKit 占位人类 placeholder_colonist.glb（def 里 model_scale=1.0），
## 用**完全相同的相机**渲一张，量出米数 → 两者比值 = 「龙有几倍人高」。
##
## 朝向判据：侧视（相机在 +X 朝 -X 看）+ 两个彩色标记球：
##   红球在世界 +Z(2.2, 0.35, +2.2 旁) / 蓝球在 -Z。**头在哪一侧，模型就朝哪个方向。**
##   该视图下世界 +Z 落在屏幕**左侧**、+Y 朝上、-Z 落右侧（rotation Y=90° 的固定结果）。

const DRAGON := "res://dragon-assets/poc/bocdagla/upload/Dragon2.glb"
const HUMAN := "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"

var _vp: SubViewport
var _cam: Camera3D
var _cam_size := 6.5
var _px := 700


func _ready() -> void:
	var args := _parse_args()
	var scale_s: float = float(args.get("scale", "0.40"))
	var out: String = args.get("out", "res://dragon-assets/poc/preview_scale_check.png")
	var anim: String = args.get("anim", "Idle_loop")
	var model: String = args.get("model", DRAGON)
	var with_markers: bool = args.get("markers", "0") == "1"
	_cam_size = float(args.get("camsize", str(_cam_size)))

	_build_stage()
	print("=== 尺寸标定：正交竖直视野 %.2f m / 视口高 %d px → 1px = %.5f m；屏幕左=世界+Z 右=世界-Z" % [
		_cam_size, _px, _cam_size / float(_px)])

	# ---- 人类参照（先量，量完移走）----
	var human := _load_model(HUMAN)
	var hbox := _place(human, 1.0, Vector3(0, 0, 0))
	var human_px := 0
	if with_markers == false:
		human_px = await _measure()
	print("[人类参照] model_scale=1.0  静态尺寸=%s  渲染世界高度=%.3f m（%d px）" % [
		hbox, human_px * _cam_size / float(_px), human_px])
	human.visible = false

	# ---- 龙 ----
	var dragon := _load_model(model)
	var dbox := _place(dragon, scale_s, Vector3.ZERO)
	_play(dragon, anim)
	print("[龙] %s" % model)
	print("     model_scale=%.3f  静态尺寸=%s（模型自身单位）" % [scale_s, dbox])
	var dragon_px := await _measure()
	var dragon_h := dragon_px * _cam_size / float(_px)
	print("     渲染世界高度=%.3f m（%d px）" % [dragon_h, dragon_px])
	if human_px > 0:
		var hh := human_px * _cam_size / float(_px)
		print("     ⇒ 龙 / 人 高度比 = %.2f ×（人 %.3f m）" % [dragon_h / maxf(hh, 0.0001), hh])

	# ---- 合影：人站龙前方（+Z 一侧），同相机同尺度 ----
	human.visible = true
	_place(human, 1.0, Vector3(0, 0, 3.0))
	human.rotation_degrees = Vector3(0, 180, 0)   # 让人面向 -Z（与工程逻辑前方一致，便于看朝向）
	_place(dragon, scale_s, Vector3(0, 0, -0.6))
	_play(dragon, anim)
	if with_markers:
		_add_marker(Vector3(0, 0.25, 2.6), Color(0.9, 0.15, 0.15))   # 红 = +Z
		_add_marker(Vector3(0, 0.25, -3.4), Color(0.15, 0.35, 0.95))  # 蓝 = -Z
	await _shoot(out)
	get_tree().quit(0)


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(900, _px)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = _cam_size
	_cam.position = Vector3(12.0, _cam_size * 0.42, 0.0)
	_cam.rotation_degrees = Vector3(0, 90, 0)
	_vp.add_child(_cam)
	_cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.06)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.0
	env.environment = e
	_vp.add_child(env)
	var light_rig := Node3D.new()
	_vp.add_child(light_rig)
	for rot in [Vector3(-55, 25, 0), Vector3(-25, 200, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = rot
		l.light_energy = 1.2
		light_rig.add_child(l)


func _add_marker(pos: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.position = pos
	add_child(m)


## 放到「脚踩 y=0、水平居中于 at」；返回模型自身空间的静态尺寸。
func _place(model: Node3D, s: float, at: Vector3) -> Vector3:
	model.scale = Vector3.ONE * s
	var box := _local_aabb(model)
	model.position = Vector3(at.x - (box.position.x + box.size.x * 0.5) * s,
		at.y - box.position.y * s,
		at.z - (box.position.z + box.size.z * 0.5) * s)
	if model.get_parent() == null:
		add_child(model)
	return box.size


func _play(model: Node3D, anim: String) -> void:
	var ap := _find_anim(model)
	if ap == null:
		return
	if anim.is_empty():
		# 显式回到绑定（静止）位姿：glTF 场景可能带 autoplay，光 stop() 不够，
		# 逐骨骼把 pose 写回 rest —— 这样量到的才是「静态 AABB 对应的那一帧」。
		ap.stop()
		var sk := _find_skel(model)
		if sk != null:
			for i in sk.get_bone_count():
				var r := sk.get_bone_rest(i)
				sk.set_bone_pose_position(i, r.origin)
				sk.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
				sk.set_bone_pose_scale(i, r.basis.get_scale())
		print("[动画] 已复位到绑定位姿（rest）")
		return
	if not ap.has_animation(anim):
		print("[动画] 找不到 ", anim, "，可用 ", ap.get_animation_list())
		return
	ap.play(anim)
	ap.seek(ap.get_animation(anim).length * 0.5, true)
	print("[动画] %s 定格在 50%%（时长 %.3fs）" % [anim, ap.get_animation(anim).length])


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _local_aabb(n: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in _meshes(n):
		var w := _rel(mi, n) * mi.get_aabb()
		out = w if first else out.merge(w)
		first = false
	return out


func _load_model(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("解析失败 " + path)
		get_tree().quit(1)
		return null
	return doc.generate_scene(st)


func _measure() -> int:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var bg := img.get_pixel(2, 2)
	var top := -1
	var bot := -1
	for y in img.get_height():
		for x in range(0, img.get_width(), 2):
			if _far(img.get_pixel(x, y), bg):
				if top < 0:
					top = y
				bot = y
				break
	return maxi(bot - top + 1, 0)


func _far(c: Color, bg: Color) -> bool:
	var a := c.srgb_to_linear()
	var b := bg.srgb_to_linear()
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.05


func _shoot(out_path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var p := out_path if out_path.begins_with("user://") else ProjectSettings.globalize_path(out_path)
	print("[保存] ", p, " err=", img.save_png(p), " 尺寸=", img.get_size())
	var bg := img.get_pixel(2, 2)
	var nonbg := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			if _far(img.get_pixel(x, y), bg):
				nonbg += 1
	print("[像素] 非背景采样 %d" % nonbg)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var r: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r


func _rel(n: Node3D, stop: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _parse_args() -> Dictionary:
	var d := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			d[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return d
