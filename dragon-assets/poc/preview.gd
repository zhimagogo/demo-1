extends Node3D
## 龙模型预览渲染（Lead 用于「肉眼确认是西方龙 + 攻击姿态」）
## 用法：godot --path . dragon-assets/poc/preview.tscn -- --anim "CharacterArmature|Headbutt" --out res://dragon-assets/poc/preview.png
## 结构：模型与相机**从一开始就都挂在 SubViewport 下**（避免主视口与 SubViewport 两个 current 相机打架），
## 抓帧取 SubViewport 的贴图。

const MODEL := "res://dragon-assets/poc/bocdagla/upload/Dragon2.glb"
const TARGET_HEIGHT := 1.6   # 目标视觉高度（米）：与 KayKit 单位身高同量级

var _vp: SubViewport


func _ready() -> void:
	var args := _parse_args()
	var anim_name: String = args.get("anim", "CharacterArmature|Headbutt")
	var out_path: String = args.get("out", "res://dragon-assets/poc/preview.png")

	_vp = SubViewport.new()
	_vp.size = Vector2i(900, 700)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	# 运行时解析 GLB（不依赖编辑器导入缓存，换文件即生效——与 PawnModelRig 的回退路径一致）
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(MODEL), state)
	if err != OK:
		push_error("GLB 解析失败 err=%d" % err)
		get_tree().quit(1)
		return
	var model := doc.generate_scene(state)
	_vp.add_child(model)

	# ---- 量测：原始高度 → 推导 model_scale ----
	var aabb := _model_aabb(model)
	var raw_h: float = aabb.size.y
	var target_h: float = float(args.get("h", str(TARGET_HEIGHT)))
	var target_scale: float = target_h / maxf(raw_h, 0.0001)
	model.scale = Vector3.ONE * target_scale
	model.position = Vector3(0, -aabb.position.y * target_scale, 0)
	print("[预览] 原始尺寸 ", aabb.size, " 原始高度 ", "%.4f" % raw_h, " → model_scale=", "%.3f" % target_scale, " 目标高度=", target_h)

	# ---- 播放指定动画并停在中间帧（攻击动作的发力点）----
	var ap := _find_anim_player(model)
	if ap != null and ap.has_animation(anim_name):
		ap.play(anim_name)
		ap.seek(ap.get_animation(anim_name).length * 0.5, true)
		print("[预览] 播放 ", anim_name, " 并定格在 50% 处")
	elif ap != null:
		print("[预览] 找不到动画 ", anim_name, "，可用：", ap.get_animation_list())

	# ---- 相机 / 灯光 / 环境 ----
	var cam := Camera3D.new()
	_vp.add_child(cam)
	var cam_dist := maxf(target_h, 1.0) * 1.9
	cam.position = Vector3(cam_dist * 0.55, target_h * 0.75, cam_dist)
	cam.look_at(Vector3(0, target_h * 0.45, 0), Vector3.UP)
	cam.fov = 50.0
	cam.current = true

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.85)
	e.ambient_light_energy = 0.6
	env.environment = e
	_vp.add_child(env)

	# DirectionalLight3D 的朝向在父级 Node3D 下才正确计算，故加一层容器。
	var light_rig := Node3D.new()
	_vp.add_child(light_rig)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_energy = 1.4
	light_rig.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.5
	light_rig.add_child(fill)

	# ---- 抓帧 ----
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var save_path := out_path if out_path.begins_with("user://") else ProjectSettings.globalize_path(out_path)
	var err2 := img.save_png(save_path)
	print("[预览] 保存 ", save_path, " err=", err2, " 尺寸=", img.get_size())
	var bg := img.get_pixel(2, 2)
	var nonbg := 0
	var total := 0
	# Godot 4.7 的 Color 没有 distance_to，按 RGB 分量自算距离。
	var bg_lin := bg.srgb_to_linear()
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			total += 1
			var c := img.get_pixel(x, y).srgb_to_linear()
			var d := Vector3(c.r - bg_lin.r, c.g - bg_lin.g, c.b - bg_lin.b).length()
			if d > 0.06:
				nonbg += 1
	print("[预览] 非背景采样点 ", nonbg, " / ", total, " 背景色 ", bg.to_html(false))
	get_tree().quit(0 if nonbg > 200 else 2)


func _parse_args() -> Dictionary:
	var d := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			d[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1
	return d


## 用局部 AABB + 相对本节点的变换合并，避开 _ready 期 global_transform 尚未生效的坑。
func _model_aabb(n: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in _meshes(n):
		var b := mi.get_aabb()
		var xf := _relative_transform(mi, n)
		var world := xf * b
		out = world if first else out.merge(world)
		first = false
	return out


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var r: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r


func _relative_transform(n: Node3D, stop: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
