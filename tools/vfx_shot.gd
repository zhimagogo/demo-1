extends Node
## v12 交付留档工具：主角 / 小兵攻击特效对照样张（不参与游戏运行）。
##
## 运行：godot --path . tools/vfx_shot.tscn
## 输出：
##   artifacts/v12-vfx-hero.png      第三人称实机：主角第 3 段重击刀光 + 命中火星 / 冲击环
##   artifacts/v12-vfx-soldiers.png  四职业小兵同帧出招：斧光 / 双匕弧 / 枪口闪光 / 施法微光
##
## 定格手法：VFXManager.debug_anim_progress 把刀光 / 冲击环 / 闪光定格在最亮的进度上
## （否则 0.1~0.3s 的瞬时特效在抓帧时早已淡出）；粒子与投射物仍按真实时间飞行。
## 取景：先在城外找一块「没有树 / 石 / 资源点」的开阔地，否则刀光会被树冠挡住。

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var spawner := world.get_node("PawnSpawner")
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午光照，特效看得清
	var spot := _find_open_ground(world, 30.0)
	print("open ground = ", spot)

	# ==== 样张 1：主角第 3 段重击（刀光 + 命中火星 + 冲击环），第三人称实机视角 ====
	hero.global_position = spot
	for _i in 6:
		await get_tree().physics_frame
	var fwd := hero.facing_dir()
	var raider: Raider = spawner.call("spawn_raider", hero.global_position + fwd * 2.4, GameDefs.raider_def())
	_freeze(raider)
	raider.global_position = hero.global_position + fwd * 2.4
	var to_r := raider.global_position - hero.global_position
	to_r.y = 0.0
	# 越肩视角：侧偏 30° 让主角与怪在画面里错开，俯角 33° 才看得清水平月牙的全貌
	tp.yaw = atan2(-to_r.x, -to_r.z) + deg_to_rad(22.0)
	tp.pitch = -0.95
	tp.target_distance = 5.0
	for _i in 12:
		await get_tree().physics_frame
	controller._refresh_crosshair_prompt()
	_hide_event_log(hud)                  # 开局提示条会盖住画面中心
	await get_tree().process_frame
	VFXManager.debug_anim_progress = 0.30  # 刀光定格在最亮的一帧
	hero._start_combo(3)
	var arc: Node3D = await _wait_group(&"vfx_slash_heavy", 120)
	var ring: Node3D = await _wait_group(&"vfx_ring", 60)
	for _i in 4:
		await get_tree().process_frame
	print("hero shot: arc=", arc != null, " ring=", ring != null,
		" effects=", VFXManager.active_effect_count())
	await _snap("v12-vfx-hero")
	VFXManager.debug_anim_progress = -1.0

	# ==== 样张 2：四职业小兵同帧出招（专属镜头，另找一块空地避开主角）====
	if hero.squad.size() > 0:
		hero.release_squad()
	if hud != null:
		hud.visible = false
	# 先等样张 1 的定格特效自然释放，再换场地（否则主角的刀光会糊进小兵样张）
	for _i in 90:
		await get_tree().process_frame
	var spot2 := _find_open_ground(world, 34.0, spot, 22.0)
	print("open ground 2 = ", spot2)
	hero.global_position = spot2 + Vector3(0.0, 0.0, 26.0)     # 主角挪出画面
	var row := spot2
	var facing := Vector3(0.0, 0.0, 1.0)          # 全员朝 +Z（面向相机）：特效落在身体与相机之间，不被自身挡住
	var defs := [GameDefs.settler_warrior_def(), GameDefs.settler_assassin_def(),
		GameDefs.settler_archer_def(), GameDefs.settler_mage_def()]
	var units: Array = []
	for i in defs.size():
		var at: Vector3 = row + Vector3(float(i) * 2.4 - 3.6, 0.0, 0.0)
		var s: Pawn = spawner.call("spawn_soldier", defs[i], at)
		_freeze(s)
		s.global_position = at
		s.look_at_target(facing)
		# 近战靶子贴身、远程靶子拉开（法师留远一点，让法术弹带尾迹飞在半路）
		var pd: PawnDef = defs[i]
		var reach: float = 1.3 if pd.attack_kind == PawnDef.AttackKind.MELEE else 3.4
		var side := 2.0
		if pd.id == &"settler_mage":
			reach = 5.0
		elif pd.id == &"settler_archer":
			side = 3.8            # 远程靶子拉得更开：否则挡住射手的枪口闪光
		var tpos: Vector3 = at + facing * reach + Vector3(side, 0.0, 0.0)   # 横向错开：靶子不挡小兵本体与特效
		var t: Raider = spawner.call("spawn_raider", tpos, GameDefs.raider_def())
		_freeze(t)
		t.global_position = tpos
		units.append([s, t])
	var shot := Camera3D.new()
	shot.fov = 45.0
	world.add_child(shot)
	var mid := row + Vector3(0.0, 0.9, 0.6)
	# 正面高机位（约 28° 俯角）：弧光 / 枪口闪光 / 法术弹都在小兵与相机之间，正对镜头
	shot.global_position = mid + Vector3(2.6, 7.2, 8.4)
	shot.look_at(mid)
	shot.current = true
	for _i in 10:
		await get_tree().physics_frame
	VFXManager.debug_anim_progress = 0.28          # 弧光 / 闪光定格
	for pair in units:
		(pair[0] as Pawn).attacker.try_attack(pair[1])
	for _i in 14:
		await get_tree().process_frame
	print("soldier shot: effects alive = ", VFXManager.active_effect_count())
	await _snap("v12-vfx-soldiers")
	VFXManager.debug_anim_progress = -1.0
	print("vfx shot done, spawned ids: ", VFXManager.stat_spawned_by_id)
	get_tree().quit()


## 冻结单位：Pawn 自身与状态机节点都要停（状态机是独立 Node，自己跑 _physics_process）
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)


## 开局提示条（EventLog）会压在画面中心，样张里隐藏
func _hide_event_log(hud: CanvasLayer) -> void:
	if hud == null:
		return
	var log_node: Variant = hud.get("event_log")
	if log_node is CanvasItem:
		(log_node as CanvasItem).visible = false
	var pause: Variant = hud.get("pause_overlay")
	if pause is CanvasItem:
		(pause as CanvasItem).visible = false


## 在城外找一块离树 / 石 / 资源点最远的开阔地（特效不能被树冠挡住）
## exclude / min_dist：避开已经用过的取景地（两块样张不能互相串场）
func _find_open_ground(world: Node3D, radius: float, exclude: Vector3 = Vector3.INF, min_dist: float = 0.0) -> Vector3:
	var blockers: Array = []
	_collect_blockers(world.get_node("Decorations"), blockers)
	_collect_blockers(world.get_node("WorldScenery"), blockers)
	for n in get_tree().get_nodes_in_group("resource_node"):
		if is_instance_valid(n):
			blockers.append((n as Node3D).global_position)
	var best := Vector3(26.0, 0.0, 26.0)
	var best_score := -1.0
	var step := 3.0
	var steps := int(radius / step)
	for gx in range(-steps, steps + 1):
		for gz in range(-steps, steps + 1):
			var p := Vector3(float(gx) * step, 0.0, float(gz) * step)
			if maxf(absf(p.x), absf(p.z)) < 22.0:      # 城内不取景（避免网格线与建筑）
				continue
			if WorldLayout.lake_distance(Vector2(p.x, p.z)) < 1.25:
				continue
			if min_dist > 0.0 and is_finite(exclude.x) and p.distance_to(exclude) < min_dist:
				continue
			var score := 999.0
			for b in blockers:
				score = minf(score, p.distance_to(b))
			if score > best_score:
				best_score = score
				best = p
	print("open ground clearance = ", snappedf(best_score, 0.1))
	return best


func _collect_blockers(node: Node, out: Array) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is MultiMeshInstance3D:
			var mm := (c as MultiMeshInstance3D).multimesh
			# 草 / 花是超大 MultiMesh（数万实例），不遮挡视线，跳过
			if mm != null and mm.instance_count > 0 and mm.instance_count <= 600:
				for i in mm.instance_count:
					out.append((c as Node3D).global_transform * mm.get_instance_transform(i).origin)
		_collect_blockers(c, out)


func _wait_group(group: StringName, max_frames: int) -> Node3D:
	for _i in max_frames:
		var n := get_tree().get_first_node_in_group(group)
		if n != null and is_instance_valid(n):
			return n as Node3D
		await get_tree().physics_frame
	return null


func _snap(filename: String) -> void:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % filename)
	print("saved artifacts/%s.png" % filename)
