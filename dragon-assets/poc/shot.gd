extends Node3D
## 龙模型预览渲染（dragon-poc；Lead 的 preview.gd 的加强版）
## 用法：godot --path . dragon-assets/poc/shot.tscn -- --scale 0.8 --anim Attack --out res://dragon-assets/poc/preview_boc_attack.png [--ref 1]
##
## 与 preview.gd 的差别：
##  ① 相机按**实测渲染尺寸**取景（本资产静态 AABB 比实际渲染大 1.84×，见 REPORT.md §2.3），
##     不再用 AABB 高度当取景依据；② 相机构图在模型水平中心（AABB 中心偏移已修）；
##  ③ 可选在 +Z 前方放一个 KayKit 人类做尺寸参照；④ 加地面网格便于看脚是否落地。
## 相机方位：azim=0 时相机在 +Z 正前方 → 正对模型脸（本模型朝 +Z）；默认 azim=38° 为 3/4 视角。

const DRAGON := "res://dragon-assets/poc/bocdagla/upload/Dragon2.glb"
const HUMAN := "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"

# 实测：本资产在「任一 authored 动画」位姿下渲染约为 mesh 顶点空间尺寸，
# 站立高度 ≈ 5.68 模型单位（静态 AABB 的 10.45 单位是 ×1.668 Armature 重复计数）。
const RENDERED_STAND_H := 5.68

var _vp: SubViewport


func _ready() -> void:
	var args := _parse_args()
	var scale_s: float = float(args.get("scale", "0.8"))
	var anim: String = args.get("anim", "Idle_loop")
	var out: String = args.get("out", "res://dragon-assets/poc/preview_dragon.png")
	var azim: float = float(args.get("azim", "38"))
	var elev: float = float(args.get("elev", "16"))
	var with_ref: bool = args.get("ref", "0") == "1"
	var model: String = args.get("model", DRAGON)

	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 720)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var dragon := _load(model)
	dragon.scale = Vector3.ONE * scale_s
	var box := _local_aabb(dragon)
	# 水平居中到原点、脚落到 y=0；竖直方向按「实测渲染高度」而不是 AABB 高度取景
	dragon.position = Vector3(-(box.position.x + box.size.x * 0.5) * scale_s,
		-box.position.y * scale_s,
		-(box.position.z + box.size.z * 0.5) * scale_s)
	_vp.add_child(dragon)
	print("[预览] %s scale=%.3f 静态AABB=%s（模型单位）" % [model, scale_s, box.size])

	var ap := _find_anim(dragon)
	if ap != null and ap.has_animation(anim):
		ap.play(anim)
		ap.seek(ap.get_animation(anim).length * 0.5, true)
		print("[预览] 播放 %s 定格 50%%（时长 %.3fs）" % [anim, ap.get_animation(anim).length])
	elif ap != null:
		print("[预览] 无动画 ", anim, "，可用 ", ap.get_animation_list())

	# 地面（看脚是否落地 + 提供空间参照）
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 24)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.20, 0.21, 0.24)
	ground.material_override = gm
	ground.position = Vector3(0, 0, 0)
	_vp.add_child(ground)

	if with_ref:
		var human := _load(HUMAN)
		human.scale = Vector3.ONE * 1.0
		var hb := _local_aabb(human)
		human.position = Vector3(0.0, -hb.position.y, box.size.z * 0.5 * scale_s + 0.9)
		human.rotation_degrees = Vector3(0, 180, 0)
		_vp.add_child(human)
		print("[预览] 参照人类（model_scale=1.0，静态高度 %.3f 单位 ≈ %.2f m）" % [hb.size.y, hb.size.y])

	# ---- 相机：围绕模型中心的球面机位 ----
	# 默认取景高度来自实测渲染高度；--dist / --targeth 可显式覆盖，
	# 让多张不同动画的图共用同一机位（姿势之间可直接对比）。
	var frame_h: float = float(args.get("targeth", str(RENDERED_STAND_H * scale_s * 0.5))) * 2.0
	var dist: float = float(args.get("dist", str(frame_h * 0.75 / tan(deg_to_rad(22.5)))))
	var yaw := deg_to_rad(azim)
	var pitch := deg_to_rad(elev)
	var target := Vector3(0, frame_h * 0.5, 0)
	var cam := Camera3D.new()
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.fov = 45.0
	_vp.add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	var vis := 2.0 * dist * tan(deg_to_rad(22.5))
	print("[预览] 机位 azim=%.0f° elev=%.0f° dist=%.2f 目标高=%.2f m 竖直视野=%.2f m 水平视野=%.2f m" % [
		azim, elev, dist, target.y, vis, vis * 4.0 / 3.0])

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.78, 0.9)
	e.ambient_light_energy = 0.7
	env.environment = e
	_vp.add_child(env)
	var rig := Node3D.new()
	_vp.add_child(rig)
	for rot in [Vector3(-48, -38, 0), Vector3(-22, 150, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = rot
		l.light_energy = 1.3
		rig.add_child(l)

	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var p := out if out.begins_with("user://") else ProjectSettings.globalize_path(out)
	print("[预览] 保存 ", p, " err=", img.save_png(p), " 尺寸=", img.get_size())
	var bg := img.get_pixel(2, 2)
	var nonbg := 0
	var total := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			total += 1
			if _far(img.get_pixel(x, y), bg):
				nonbg += 1
	print("[预览] 非背景采样点 ", nonbg, " / ", total)
	get_tree().quit(0 if nonbg > 400 else 2)


func _far(c: Color, bg: Color) -> bool:
	var a := c.srgb_to_linear()
	var b := bg.srgb_to_linear()
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() > 0.05


func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("解析失败 " + path)
		get_tree().quit(1)
	return doc.generate_scene(st)


func _local_aabb(n: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in _meshes(n):
		var w := _rel(mi, n) * mi.get_aabb()
		out = w if first else out.merge(w)
		first = false
	return out


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
