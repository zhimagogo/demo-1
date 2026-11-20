extends Node3D
## 怪物比例标定探针（monster-assets / task-5）
##
## 用法（**必须带窗口跑，不要加 --headless**——headless 下 RenderingServer.frame_post_draw
## 不触发，场景会挂死到超时）：
##   ① 量测：godot --path . dragon-assets/monsters/measure.tscn -- --mode eval
##   ② 对照图：godot --path . dragon-assets/monsters/measure.tscn -- --mode sheet \
##              --targets "Orc=2.60,Ninja=2.15,MushroomKing=3.40,Cactoro=2.75,GreenBlob=1.15,Yeti=3.10,Ghost=2.30,Glub=1.35"
##
## 为什么用渲染量测而不是读静态 AABB：glTF 对蒙皮网格的 accessor min/max 只保证「包住
## 整个蒙皮可能范围」，经常严重高估（本项目龙的 AABB 报 10.45、实渲只有 5.68）。
## 所以尺寸口径取**正交相机渲染 + 像素量测**：
##   正交相机竖直视野 = cam.size 米，视口高 H 像素 → 1px = cam.size / H 米；
##   量出模型**不透明像素**的竖直跨度 → 直接得到「它在世界里有多高（米）」。
## 透明判定优先用 alpha 通道（SubViewport.transparent_bg = true），退化时按背景色差判定。
##
## 标尺自检：KayKit 占位人类 placeholder_colonist.glb 在同一相机下应量到 ≈2.19。

const HUMAN := "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb"
const BARBARIAN := "res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb"
const HERO := "res://assets/_PLACEHOLDER/characters/placeholder_hero.glb"
const MON_DIR := "res://assets/_PLACEHOLDER/monsters/"
const OUT_DIR := "res://dragon-assets/monsters/"

const MONSTERS: Array[String] = [
	"Orc", "Ninja", "MushroomKing", "Cactoro",
	"GreenBlob", "Yeti", "Ghost", "Glub",
]

## 静息动画优先级：Quaternius 的 Blob/Flying 目录没有裸 `Idle`，用语义等价键回退。
const IDLE_PRIORITY: Array[String] = ["Idle", "Flying_Idle", "idle", "Idle_loop"]

## 游戏内人类基准：KayKit 人类实渲高 × PawnDef.model_scale(1.05)
const HUMAN_GAME_SCALE := 1.05

## 参考目标高度（米）→ 供 REPORT 直接查表换算 model_scale
const REF_TARGETS: Array[float] = [1.5, 2.0, 2.5, 3.0, 3.5]

const MEAS_W := 1200
const MEAS_H := 900
const SHEET_W := 1800
const SHEET_H := 760
const PAIR_W := 1000
const PAIR_H := 820
## 对照图「逐个对齐脚底」那一趟用的宽松竖直视野（米），要装得下最高的怪物
const ALIGN_CAM := 9.0
## 参考线放在模型后方多远处（正交投影下 x 不影响屏幕位置，只影响遮挡）
const GUIDE_X := -6.0

var _vp: SubViewport
var _cam: Camera3D
var _cam_dist := 14.0


func _ready() -> void:
	var args := _parse_args()
	var mode: String = args.get("mode", "eval")
	_build_stage()
	match mode:
		"eval":
			await _mode_eval()
		"sheet":
			await _mode_sheet(args)
		_:
			push_error("未知 --mode：%s（可选 eval / sheet）" % mode)
			get_tree().quit(2)
			return
	get_tree().quit(0)


# --------------------------------------------------------------------------
# 舞台
# --------------------------------------------------------------------------

func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(MEAS_W, MEAS_H)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT   # cam.size = 竖直视野（米）
	_cam.size = 6.0
	_cam.position = Vector3(_cam_dist, 3.0, 0.0)
	_cam.rotation_degrees = Vector3(0, 90, 0)  # 屏幕左 = 世界 +Z
	_cam.near = 0.05
	_cam.far = 200.0
	_vp.add_child(_cam)
	_cam.current = true

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.085, 0.095, 0.125)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.0
	env.environment = e
	_vp.add_child(env)

	var rig := Node3D.new()
	_vp.add_child(rig)
	for rot in [Vector3(-52, 28, 0), Vector3(-22, 205, 0), Vector3(-8, 118, 0)]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = rot
		l.light_energy = 0.95
		rig.add_child(l)


# --------------------------------------------------------------------------
# 模式 A：量测
# --------------------------------------------------------------------------

func _mode_eval() -> void:
	_vp.size = Vector2i(MEAS_W, MEAS_H)
	print("=== 怪物比例标定（渲染量测口径）===")
	print("视口 %dx%d；正交相机 KEEP_HEIGHT；屏幕左=世界+Z" % [MEAS_W, MEAS_H])

	# ---- 标尺自检 ----
	var rulers := {
		"Colonist(KayKit)": HUMAN,
		"Barbarian(KayKit)": BARBARIAN,
		"Hero(KayKit)": HERO,
	}
	var ruler_h := {}
	for k in rulers.keys():
		var n := _spawn(rulers[k])
		if n == null:
			print("[标尺] 加载失败 ", rulers[k])
			continue
		var r := await _measure_actor(n, 1.0, "")
		if r.get("ok", false):
			ruler_h[k] = r["fine"]["h_m"]
			print("[标尺] %-18s 静态 AABB 高=%.3f  实渲高@scale1=%.3f m  alpha=%s" % [
				k, r["aabb"].size.y, r["fine"]["h_m"], r["fine"]["alpha_mode"]])
		_free(n)
	var human_h: float = ruler_h.get("Colonist(KayKit)", 0.0)
	if human_h > 0.0:
		print("[自检] 人类标尺实渲 %.3f m（真值 2.187）→ 偏差 %+.2f%%；游戏内 1.05× = %.3f m" % [
			human_h, (human_h / 2.187 - 1.0) * 100.0, human_h * HUMAN_GAME_SCALE])
	else:
		print("[自检] 人类标尺量测失败——下列数值不可采信")

	# ---- 8 个怪物 ----
	print("")
	print("## 逐模型：静态 AABB 高 / 实渲高（rest 绑定位姿）/ 实渲高（静息动画 50% 帧）")
	print("##TABLE|名称|AABB高|AABB宽|AABB长|实渲rest高|实渲idle高|idle动画名|实渲/AABB|alpha")
	var results := {}
	for name in MONSTERS:
		var path := MON_DIR + name + ".gltf"
		var n := _spawn(path)
		if n == null:
			print("##TABLE|%s|LOAD_FAIL|||||||" % name)
			continue
		var r_rest := await _measure_actor(n, 1.0, "")
		var r_idle := await _measure_actor(n, 1.0, _pick_idle(n))
		var aabb: AABB = r_rest["aabb"]
		var h_rest: float = r_rest["fine"]["h_m"] if r_rest.get("ok", false) else -1.0
		var h_idle: float = r_idle["fine"]["h_m"] if r_idle.get("ok", false) else -1.0
		var ratio := (h_idle / aabb.size.y) if aabb.size.y > 0.0 and h_idle > 0.0 else -1.0
		print("##TABLE|%s|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%.3f|%s" % [
			name, aabb.size.y, aabb.size.x, aabb.size.z, h_rest, h_idle,
			_idle_used, ratio, str(r_idle.get("fine", {}).get("alpha_mode", "?"))])
		results[name] = {"aabb": aabb, "h_rest": h_rest, "h_idle": h_idle}
		_free(n)

	# ---- 换算表 ----
	print("")
	print("## 换算：model_scale = 目标高度(m) ÷ 实渲高@scale1(m)。下表按 **idle 实渲高** 算。")
	var head := "##SCALE|名称|实渲高@1|"
	for t in REF_TARGETS:
		head += "→%.1fm|" % t
	print(head)
	for name in MONSTERS:
		if not results.has(name):
			continue
		var h: float = results[name]["h_idle"]
		if h <= 0.0:
			print("##SCALE|%s|量测失败||||||" % name)
			continue
		var line := "##SCALE|%s|%.3f|" % [name, h]
		for t in REF_TARGETS:
			line += "%.3f|" % (t / h)
		print(line)
	# 人类基准行（同口径参照）
	if human_h > 0.0:
		var line2 := "##SCALE|(人类标尺)|%.3f|" % human_h
		for t in REF_TARGETS:
			line2 += "%.3f|" % (t / human_h)
		print(line2)


# --------------------------------------------------------------------------
# 模式 B：同框对照图
# --------------------------------------------------------------------------

func _mode_sheet(args: Dictionary) -> void:
	var targets := _parse_targets(args.get("targets", ""))
	print("=== 同框对照渲染 ===")
	if targets.is_empty():
		print("[提示] 未给 --targets，怪物一律 model_scale=1.0（原始比例图）")

	# 1) 收集演员：人类标尺（游戏 scale）+ 8 怪物（按目标高度换算出的 scale）
	var actors: Array[Dictionary] = []
	var human := _spawn(HUMAN)
	if human == null:
		print("[致命] 人类标尺加载失败")
		return
	actors.append({"name": "Colonist", "node": human, "scale": HUMAN_GAME_SCALE,
		"human": true, "model": HUMAN})

	var meas := {}
	for name in MONSTERS:
		var n := _spawn(MON_DIR + name + ".gltf")
		if n == null:
			print("[跳过] 加载失败 ", name)
			continue
		var r := await _measure_actor(n, 1.0, _pick_idle(n))
		var h: float = r["fine"]["h_m"] if r.get("ok", false) else -1.0
		if h <= 0.0:
			print("[跳过] 量测失败 ", name)
			_free(n)
			continue
		var s: float = (targets[name] / h) if targets.has(name) else 1.0
		meas[name] = {"h_native": h, "scale": s, "target": targets.get(name, 0.0)}
		print("[换算] %-14s 实渲高@1=%.3f m  目标=%s m  → model_scale=%.3f" % [
			name, h, ("%.2f" % targets[name]) if targets.has(name) else "原始", s])
		actors.append({"name": name, "node": n, "scale": s, "human": false,
			"model": MON_DIR + name + ".gltf"})

	# 2) 逐个对齐「渲染出来的脚底」到 y=0，并量出宽度（用于自适应间距）
	print("")
	print("## 逐个对齐脚底到 y=0（按渲染像素，不按 AABB）")
	var spacing: Array[float] = []
	var max_h := 0.0
	var human_top := 0.0
	for a in actors:
		var n2: Node3D = a["node"]
		n2.scale = Vector3.ONE * float(a["scale"])
		_pose_by_aabb(n2, _local_aabb(n2))
		_play(n2, "" if a["human"] else _pick_idle(n2))
		var sv := ALIGN_CAM
		# 关键：这一趟是「逐个量」，必须把其余演员藏起来，否则量到的是全部模型的并集。
		for other in actors:
			(other["node"] as Node3D).visible = (other["node"] == n2)
		var scan := await _render_scan(sv, sv * 0.45, SHEET_W, SHEET_H)
		if scan.get("empty", false):
			print("  %-14s 空帧" % a["name"])
			continue
		# 把渲染出来的底边平移到 y=0
		n2.position.y -= float(scan["y_bot"])
		var scan2 := await _render_scan(sv, sv * 0.45, SHEET_W, SHEET_H)
		a["w"] = float(scan2.get("w_m", 1.2))
		a["h"] = float(scan2.get("h_m", 1.0))
		max_h = maxf(max_h, float(a["h"]))
		if a["human"]:
			human_top = float(a["h"])
		print("  %-14s scale=%.3f  实渲高=%.3f m  实渲宽=%.3f m" % [
			a["name"], a["scale"], a["h"], a["w"]])
	for a in actors:
		(a["node"] as Node3D).visible = true

	# 3) 自适应间距 + 沿排布轴落位
	for i in actors.size():
		var w_i: float = float(actors[i].get("w", 1.2))
		var w_j: float = float(actors[i + 1].get("w", 1.2)) if i + 1 < actors.size() else 0.0
		spacing.append(maxf(1.30, (w_i + w_j) * 0.5 + 0.45))
	var total := 0.0
	for s in spacing:
		total += s

	var axis := Vector3(0, 0, 1)      # 侧视：屏幕左 = 世界 +Z
	var flip := true                  # index 0 放屏幕最左
	var view: String = args.get("view", "side")
	if view == "front":
		axis = Vector3(1, 0, 0)       # 前视：相机在 +Z 看 -Z，屏幕右 = 世界 +X
		flip = false
		_cam.rotation_degrees = Vector3(0, 0, 0)
		_cam.position = Vector3(0, 0, _cam_dist)
	else:
		_cam.rotation_degrees = Vector3(0, 90, 0)
		_cam.position = Vector3(_cam_dist, 0, 0)

	var cum := 0.0
	for i in actors.size():
		var along := (total * 0.5 - cum) if flip else (-total * 0.5 + cum)
		var a: Dictionary = actors[i]
		var n3: Node3D = a["node"]
		var p := axis * along
		n3.position.x = p.x
		n3.position.z = p.z
		cum += float(spacing[i]) if i < spacing.size() else 1.3

	# 4) 参考线（1m 网格 + 人类游戏身高绿线）
	_add_guides(axis, total, human_top, view)

	# 5) 定相机 + 出图
	var sv2 := maxf(total / (float(SHEET_W) / float(SHEET_H)) * 1.04, max_h * 1.28)
	var cam_y := sv2 * 0.45
	var out_main: String = args.get("out", OUT_DIR + ("contact_sheet_front.png" if view == "front" else "contact_sheet_calibrated.png"))
	await _render_save(out_main, sv2, cam_y, SHEET_W, SHEET_H)
	print("[对照图] ", out_main, "  相机竖直视野=%.2f m  横向=%.2f m" % [
		sv2, sv2 * float(SHEET_W) / float(SHEET_H)])

	# 6) 逐个「人类 + 该怪物」特写（特写一律侧视，便于比高矮）
	if args.get("pairs", "1") == "1":
		_cam.rotation_degrees = Vector3(0, 90, 0)
		_cam.position = Vector3(_cam_dist, _cam.position.y, 0.0)
		var pairs_cam := maxf(max_h * 1.30, 2.2)
		for i in actors.size():
			var a2: Dictionary = actors[i]
			if a2["human"]:
				continue
			var n4: Node3D = a2["node"]
			var sp := n4.position
			n4.position = Vector3(0, n4.position.y, 0.0)
			human.position = Vector3(0, human.position.y, 0.0)
			# 人类摆在该怪物左侧（+Z）
			human.position.z = 1.55
			n4.position.z = -0.45
			# 特写只留这两个，否则邻座会串进画面
			for a3 in actors:
				var n5: Node3D = a3["node"]
				n5.visible = (n5 == n4 or n5 == human)
			var pth := OUT_DIR + "contact_sheet_pair_%s.png" % a2["name"]
			await _render_save(pth, pairs_cam, pairs_cam * 0.46, PAIR_W, PAIR_H)
			print("[特写] ", pth, "  怪物 scale=%.3f（目标 %.2f m）" % [
				a2["scale"], float(meas[a2["name"]]["target"])])
			n4.position = sp
			human.position = Vector3(0, human.position.y, 0.0)
		for a3 in actors:
			(a3["node"] as Node3D).visible = true


## 参考线：每 1m 一条暗线（画在模型后方 x=-1.6），人类游戏身高一条绿线。
func _add_guides(axis: Vector3, span: float, human_top: float, view: String) -> void:
	var length := span + 3.0
	for m in range(1, 9):
		var c := Color(0.32, 0.34, 0.40) if m % 2 == 0 else Color(0.22, 0.24, 0.29)
		_make_bar(Vector3.ZERO, float(m), c, length, axis, 0.55, view)
	# 地面
	_make_bar(Vector3.ZERO, 0.0, Color(0.30, 0.32, 0.38), length, axis, 1.18, view)
	if human_top > 0.0:
		_make_bar(Vector3.ZERO, human_top, Color(0.35, 1.0, 0.45), length, axis, 1.5, view)
		print("[参考线] 绿色横线 = 人类在游戏里的头顶高度 %.3f m（实渲 %.3f × scale %.2f）" % [
			human_top, human_top / HUMAN_GAME_SCALE, HUMAN_GAME_SCALE])


func _make_bar(_origin: Vector3, y: float, col: Color, length: float, axis: Vector3, e: float, view: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var along := axis.abs()
	if along.z > 0.5:
		bm.size = Vector3(0.035, 0.014 * e, length)
	else:
		bm.size = Vector3(length, 0.014 * e, 0.035)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	var off := Vector3(GUIDE_X, y, 0) if view == "side" else Vector3(0, y, GUIDE_X)
	mi.position = off
	add_child(mi)


# --------------------------------------------------------------------------
# 量测核心
# --------------------------------------------------------------------------

## 在宽松视野粗测 → 用粗测结果居中收窄 → 精测。
## 返回 {"ok":bool, "aabb":AABB, "rough":scan, "fine":scan}
## 量测期间**强制隔离**：场景里其他模型/参考线一律隐藏，否则量到的是并集而不是单体。
func _measure_actor(node: Node3D, s: float, anim: String) -> Dictionary:
	_isolate(node)
	node.scale = Vector3.ONE * s
	var aabb := _local_aabb(node)
	_pose_by_aabb(node, aabb)
	_play(node, anim)
	var rough := await _render_scan(14.0, 7.0, MEAS_W, MEAS_H)
	var res := {"ok": false, "aabb": aabb, "rough": rough, "fine": {}}
	if not rough.get("empty", false):
		var cy: float = (float(rough["y_top"]) + float(rough["y_bot"])) * 0.5
		var cs: float = maxf((float(rough["y_top"]) - float(rough["y_bot"])) * 1.22, 0.25)
		var fine := await _render_scan(cs, cy, MEAS_W, MEAS_H)
		res["fine"] = fine
		res["ok"] = not fine.get("empty", false)
	_unisolate()
	return res


var _hidden: Array[Node3D] = []


func _isolate(target: Node3D) -> void:
	_hidden.clear()
	for c in get_children():
		if c is Node3D and c != target and (c as Node3D).visible:
			(c as Node3D).visible = false
			_hidden.append(c as Node3D)


func _unisolate() -> void:
	for c in _hidden:
		c.visible = true
	_hidden.clear()


func _render_scan(size_v: float, y: float, w: int, h: int) -> Dictionary:
	if _vp.size != Vector2i(w, h):
		_vp.size = Vector2i(w, h)
	_vp.transparent_bg = true
	_cam.size = size_v
	_cam.position.y = y
	var img := await _shot()
	return _scan(img)


func _render_save(path: String, size_v: float, y: float, w: int, h: int) -> void:
	if _vp.size != Vector2i(w, h):
		_vp.size = Vector2i(w, h)
	_vp.transparent_bg = false      # 对照图要实底，避免透明合成出偏色
	_cam.size = size_v
	_cam.position.y = y
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var p := ProjectSettings.globalize_path(path)
	var err := img.save_png(p)
	print("[保存] %s err=%d 尺寸=%s" % [p, err, str(img.get_size())])


func _shot() -> Image:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	return _vp.get_texture().get_image()


## 扫描不透明像素的四至。透明判定优先 alpha 通道，退化时按左上角背景色差。
func _scan(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	var alpha_mode: bool = d[3] < 128
	var br := int(d[0])
	var bg := int(d[1])
	var bb := int(d[2])
	var top := -1
	for y in h:
		var base := y * w * 4
		for x in w:
			if _hit(d, base + x * 4, alpha_mode, br, bg, bb):
				top = y
				break
		if top >= 0:
			break
	if top < 0:
		return {"empty": true, "alpha_mode": alpha_mode}
	var bot := -1
	for y in range(h - 1, -1, -1):
		var base2 := y * w * 4
		for x in w:
			if _hit(d, base2 + x * 4, alpha_mode, br, bg, bb):
				bot = y
				break
		if bot >= 0:
			break
	var left := -1
	for x in w:
		for y in range(top, bot + 1):
			if _hit(d, (y * w + x) * 4, alpha_mode, br, bg, bb):
				left = x
				break
		if left >= 0:
			break
	var right := -1
	for x in range(w - 1, -1, -1):
		for y in range(top, bot + 1):
			if _hit(d, (y * w + x) * 4, alpha_mode, br, bg, bb):
				right = x
				break
		if right >= 0:
			break
	var mpp := _cam.size / float(h)
	var cy := _cam.position.y
	return {
		"empty": false,
		"alpha_mode": alpha_mode,
		"top": top, "bot": bot, "left": left, "right": right,
		"h_px": bot - top + 1, "w_px": right - left + 1,
		"mpp": mpp,
		"y_top": cy + (h * 0.5 - float(top) - 0.5) * mpp,
		"y_bot": cy + (h * 0.5 - float(bot) - 0.5) * mpp,
		"h_m": float(bot - top + 1) * mpp,
		"w_m": float(right - left + 1) * mpp,
	}


func _hit(d: PackedByteArray, i: int, alpha_mode: bool, br: int, bg: int, bb: int) -> bool:
	if alpha_mode:
		return d[i + 3] > 128
	var dr := int(d[i]) - br
	var dg := int(d[i + 1]) - bg
	var db := int(d[i + 2]) - bb
	return dr * dr + dg * dg + db * db > 1100


# --------------------------------------------------------------------------
# 模型工具
# --------------------------------------------------------------------------

func _spawn(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("解析失败 " + path)
		return null
	var scene := doc.generate_scene(st)
	if scene == null:
		push_error("生成场景失败 " + path)
		return null
	add_child(scene)
	return scene


func _free(n: Node3D) -> void:
	remove_child(n)
	n.queue_free()


## 放到「AABB 底边踩 y=0、水平居中于原点」。
func _pose_by_aabb(model: Node3D, box: AABB) -> void:
	var s := model.scale.x
	model.position = Vector3(
		-(box.position.x + box.size.x * 0.5) * s,
		-box.position.y * s,
		-(box.position.z + box.size.z * 0.5) * s)


var _idle_used := ""

func _pick_idle(model: Node3D) -> String:
	var ap := _find_anim(model)
	_idle_used = ""
	if ap == null:
		return ""
	var names := ap.get_animation_list()
	for want in IDLE_PRIORITY:
		if names.has(want):
			_idle_used = want
			return want
	if names.size() > 0:
		_idle_used = names[0]
		return names[0]
	return ""


func _play(model: Node3D, anim: String) -> void:
	var ap := _find_anim(model)
	if ap == null:
		return
	if anim.is_empty():
		# 回到绑定位姿：glTF 场景可能带 autoplay，光 stop() 不够，
		# 逐骨骼把 pose 写回 rest —— 量到的才是「静态 AABB 对应的那一帧」。
		ap.stop()
		var sk := _find_skel(model)
		if sk != null:
			for i in sk.get_bone_count():
				var r := sk.get_bone_rest(i)
				sk.set_bone_pose_position(i, r.origin)
				sk.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
				sk.set_bone_pose_scale(i, r.basis.get_scale())
		return
	if not ap.has_animation(anim):
		print("[动画] %s 找不到 %s，可用 %s" % [model.name, anim, str(ap.get_animation_list())])
		return
	ap.play(anim)
	ap.seek(ap.get_animation(anim).length * 0.5, true)
	# 必须冻结：渲染要跨若干帧，AnimationPlayer 会继续推进，
	# 否则「量测时那一帧」与「出图时那一帧」不是同一帧，数字对不上（飞行怪尤其明显）。
	ap.pause()


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var r: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		r.append(n)
	for c in n.get_children():
		r.append_array(_meshes(c))
	return r


func _local_aabb(n: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in _meshes(n):
		var w := _rel(mi, n) * mi.get_aabb()
		out = w if first else out.merge(w)
		first = false
	return out


func _rel(n: Node3D, stop: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != stop:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# --------------------------------------------------------------------------
# 参数
# --------------------------------------------------------------------------

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


func _parse_targets(s: String) -> Dictionary:
	var d := {}
	for part in s.split(",", false):
		var kv := part.split("=", false)
		if kv.size() == 2:
			d[kv[0].strip_edges()] = float(kv[1])
	return d
