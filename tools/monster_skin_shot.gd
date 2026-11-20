extends Node
## v21 交付留档 + 比例校准：怪物皮肤「同框对照 + 实测渲染高度」探针（不参与游戏运行）。
##
## 运行：godot --path . tools/monster_skin_shot.tscn
## 输出：artifacts/v21-monster-skins.png
##
## 为什么需要它：`PawnDef.model_scale` **不能拿静态 AABB 反推**——静态 AABB 是绑定姿态下的
## 包围盒（常含 T-pose 张臂），与游戏里实际渲染的站立高度能差一倍以上（本项目龙的实例：
## AABB 报 10.45，实渲只有 5.68）。故这里直接加载真实世界、用真实 def 刷怪，量**渲染后**的
## 合并 AABB 高度，并以真人小兵（KayKit 人类，已知静态高 2.187）做标尺自检。

const ROW_Z := -16.0
const SPACING := 1.9
const SETTLE_FRAMES := 24      # 等动画姿态稳定几帧再量（首帧常停在绑定姿）

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	TimeManager.begin(11)                      # 正午，光线充足
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	var hero := controller.hero as Hero
	if hero != null:
		hero.visible = false                   # 样张只看怪物
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	(world.get_node("IsometricCamera") as IsometricCamera).set_process(false)

	# 固定机位，平视略俯，能看出与人类的相对高度
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	var n := 8
	var center_x := float(n - 1) * 0.5 * SPACING
	cam.global_position = Vector3(center_x, 2.2, ROW_Z + 13.0)
	cam.look_at(Vector3(center_x, 1.1, ROW_Z))
	cam.current = true

	# 从左到右：真人标尺 · 普通野怪池 4 款 · 精英 · 头目
	var spawner := world.get_node("PawnSpawner")
	var raider_def := GameDefs.raider_def()
	var entries := [
		{ "label": "人类标尺(战士)", "def": GameDefs.settler_warrior_def(), "kind": "soldier" },
		{ "label": "普通·Orc", "def": _with_model(raider_def, "Orc"), "kind": "raider" },
		{ "label": "普通·Ninja", "def": _with_model(raider_def, "Ninja"), "kind": "raider" },
		{ "label": "普通·Cactoro", "def": _with_model(raider_def, "Cactoro"), "kind": "raider" },
		{ "label": "普通·Yeti", "def": _with_model(raider_def, "Yeti"), "kind": "raider" },
		{ "label": "普通·GreenBlob", "def": _with_model(raider_def, "GreenBlob"), "kind": "raider" },
		{ "label": "精英·MushroomKing", "def": GameDefs.raider_elite_def(), "kind": "raider" },
		{ "label": "头目·Ghost", "def": GameDefs.raider_boss_def(), "kind": "raider" },
	]
	var units: Array[Pawn] = []
	for i in entries.size():
		var e: Dictionary = entries[i]
		var at := Vector3(float(i) * SPACING, 0.0, ROW_Z)
		var p: Pawn = null
		if String(e["kind"]) == "soldier":
			p = spawner.call("spawn_soldier", e["def"], at)
		else:
			p = spawner.call("spawn_raider", at, e["def"])
		if p == null:
			print("[跳过] ", e["label"], " 生成失败")
			continue
		p.look_at_target(cam.global_position - at)   # 面向镜头（可见正面 + 前进方向校验）
		units.append(p)
		await get_tree().physics_frame

	for i in SETTLE_FRAMES:
		await get_tree().physics_frame

	# ---- 量测：真实 Pawn 的渲染 AABB（含 model_rig 的缩放与朝向）----
	print("=== 实测渲染高度（静态 AABB 不可信，以本表为准）===")
	print("%-22s %8s %8s %8s   %s" % ["单位", "高(m)", "宽(m)", "scale", "模型"])
	for i in entries.size():
		if i >= units.size():
			continue
		var e: Dictionary = entries[i]
		var d: PawnDef = e["def"]
		var box := _render_aabb(units[i])
		print("%-22s %8.3f %8.3f %8.3f   %s" % [
			e["label"], box.size.y, box.size.x, d.model_scale, d.model_path.get_file()
		])

	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://artifacts/v21-monster-skins.png")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	print("保存 ", out, " err=", img.save_png(out))
	get_tree().quit(0)


## 取 def 里指定怪物的模型路径（用于同框展示池内各款）。
func _with_model(base: PawnDef, model_name: String) -> PawnDef:
	var d: PawnDef = base.duplicate(true)
	d.model_path = "res://assets/_PLACEHOLDER/monsters/%s.gltf" % model_name
	d.model_path_pool = []          # 固定展示这一款，避免随机抽到别的
	return d


## 合并该单位模型子树里所有 MeshInstance3D 的世界包围盒（即玩家真正看到的体积）。
func _render_aabb(root: Node) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	var first := true
	var out := AABB()
	for mi in meshes:
		if not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
