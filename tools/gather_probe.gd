extends Node
## Lead 独立验收探针：集结加速 / 到位停住 / 跟随原速（需求 1 + 3 的客观量测）。
##
## 运行：
##   godot --path . tools/gather_probe.tscn
##   godot --headless --path . tools/gather_probe.tscn --fixed-fps 60
##
## 量测方式：把 4 名小兵摆在主角 26m 外 → 按 G 集结 → 每物理帧采样
##   · 追赶段（未到位）瞬时速度与均值   → 验证「加速 100%」
##   · 到位后位移                       → 验证「停住不搓」
##   · 主角移动后的跟随速度             → 验证「跟随时原速」
##   · 相机 FOV / 肩部偏移 / 主角在画面中的横向位置 → 验证需求 3

const SOLDIER_COUNT: int = 4
const SPAWN_RING: float = 26.0

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)


func _run() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	# v42：玩家默认俯视角主控；本探针量的是第三人称相机几何 → 显式进亲征模式取景
	controller.enter_hero_mode()
	await get_tree().physics_frame
	var spawner := world.get_node("PawnSpawner")
	var hero := controller.hero as Hero
	hero.global_position = Vector3(0.0, 0.0, 26.0)
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera

	# ---- 需求 3：正后背 + 抬高 + 广角 ----
	print("camera: fov=%.1f pivot=%.2f shoulder=%.2f pitch=%.2f dist=%.1f" % [
		tp.fov, ThirdPersonCamera.PIVOT_HEIGHT, ThirdPersonCamera.SHOULDER_OFFSET, tp.pitch, tp.target_distance])
	_check(tp.fov >= 76.0, "wide fov (>= 76)")
	_check(ThirdPersonCamera.PIVOT_HEIGHT >= 1.85, "pivot raised (>= 1.85)")
	_check(ThirdPersonCamera.SHOULDER_OFFSET <= 0.02, "no shoulder offset (back view)")
	_check(tp.pitch <= -0.35, "default pitch looks down (<= -0.35 rad)")

	# ---- 需求 1：集结加速与停住 ----
	hero.release_squad()
	hero.set_party([])
	var defs := [GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(),
		GameDefs.settler_assassin_def(), GameDefs.settler_archer_def()]
	var members: Array = []
	for i in SOLDIER_COUNT:
		var a: float = TAU * float(i) / float(SOLDIER_COUNT)
		var at: Vector3 = hero.global_position + Vector3(cos(a), 0.0, sin(a)) * SPAWN_RING
		var s: Pawn = spawner.call("spawn_soldier", defs[i], at)
		members.append(s)
	await get_tree().physics_frame
	var base_speed: float = (members[0] as Pawn).move_speed
	print("soldier move_speed = %.2f m/s; spawn ring %.0fm" % [base_speed, SPAWN_RING])

	# 集结前记录距离
	for m in members:
		(m as Pawn).set("follow_leader", null)
	controller._toggle_squad_rally()
	var squad_ids: Array = []
	for m in hero.squad:
		squad_ids.append((m as Node).get_instance_id())
	_check(hero.squad.size() == SOLDIER_COUNT, "squad recruited all %d members (got %d)" % [SOLDIER_COUNT, hero.squad.size()])

	# 采样：每帧记录每名成员的速度与到主角距离，直到全部进入 6m
	var rush_speeds: Array = []
	var rush_frames: int = 0
	var gathered_frame: int = -1
	for f in 600:
		await get_tree().physics_frame
		rush_frames += 1
		var all_close := true
		for m in members:
			var p := m as Pawn
			var d: float = p.global_position.distance_to(hero.global_position)
			if d > 6.0:
				all_close = false
				rush_speeds.append(p.velocity.length())
		if all_close:
			gathered_frame = f
			break
	var rush_avg: float = 0.0
	if rush_speeds.size() > 0:
		for v in rush_speeds:
			rush_avg += v
		rush_avg /= float(rush_speeds.size())
	print("gather: %d frames (%.2fs), avg rush speed %.2f m/s = %.2fx base" % [
		gathered_frame, float(gathered_frame) / 60.0, rush_avg, rush_avg / maxf(base_speed, 0.001)])
	_check(gathered_frame > 0 and gathered_frame < 300, "squad reaches the hero within 5s (frame %d)" % gathered_frame)
	_check(rush_avg > base_speed * 1.4, "gather phase is boosted (avg %.2f > 1.4x base %.2f)" % [rush_avg, base_speed])

	# 等「真正就位」：全部成员离主角 ≤ 2.2m（槽位在主角身后 1.7~3m 扇形，6m 只是接近）
	var settled_frame: int = -1
	for f in 600:
		await get_tree().physics_frame
		var all_set := true
		for m in members:
			if (m as Pawn).global_position.distance_to(hero.global_position) > 3.6:
				all_set = false
				break
		if all_set and f > gathered_frame + 30:
			settled_frame = f
			break
	print("settled at frame %d (%.2fs)" % [settled_frame, float(settled_frame) / 60.0])

	# 停住检测：全部就位后再跑 2s，统计每人位移
	var pos_before: Array = []
	for m in members:
		pos_before.append((m as Pawn).global_position)
	for _f in 120:
		await get_tree().physics_frame
	var settle_max: float = 0.0
	for i in members.size():
		var moved: float = (members[i] as Pawn).global_position.distance_to(pos_before[i] as Vector3)
		settle_max = maxf(settle_max, moved)
	print("settle: max drift in 2s = %.3f m" % settle_max)
	_check(settle_max < 0.6, "members hold position after gathering (drift %.3fm < 0.6)" % settle_max)

	# 跟随原速：让主角往前走 22m。分两段——前 1s 是起步追赶（允许略高），
	# 后 2s 是稳态跟随，必须回落到原速。v19：游侠有基础被动移速（比其他小怪快 25%），
	# 逐成员按「各自 move_speed」归一——契约是「各自回到原速」，不是「全队同速」。
	var follow_peak: float = 0.0
	var follow_sum: float = 0.0
	var follow_n: int = 0
	Input.action_press("move_up")
	for _f in 60:
		await get_tree().physics_frame
	for _f in 120:
		await get_tree().physics_frame
		for m in members:
			var p := m as Pawn
			if p.global_position.distance_to(hero.global_position) > 3.0:
				var ratio: float = p.velocity.length() / maxf(p.move_speed, 0.001)
				follow_peak = maxf(follow_peak, ratio)
				follow_sum += ratio
				follow_n += 1
	Input.action_release("move_up")
	await get_tree().physics_frame
	var follow_avg: float = follow_sum / maxf(float(follow_n), 1.0)
	print("follow: steady avg %.2fx peak %.2fx (per-member base speeds)" % [follow_avg, follow_peak])
	# 上限依据：FollowState 的 max_spd = move_speed * 1.25（seek + 分离叠加后的钳制值），
	# 故稳态均值必须接近 1×，瞬时不高于 1.25× + 一点抖动余量。
	_check(follow_avg < 1.12, "steady follow runs at each member's base speed (avg %.2fx)" % follow_avg)
	_check(follow_peak < 1.3, "no 2x boost left while following (peak %.2fx)" % follow_peak)

	# ---- 相机与主角画面位置：正后背（主角应落在画面中线上）----
	tp.yaw = 0.0
	tp.pitch = -0.4
	for _f in 5:
		await get_tree().physics_frame
	var vp_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var hero_screen: Vector2 = tp.unproject_position(hero.global_position + Vector3(0.0, 1.0, 0.0))
	print("screen: hero.x=%.1f centre.x=%.1f dx=%.1f px" % [hero_screen.x, vp_center.x, absf(hero_screen.x - vp_center.x)])
	_check(absf(hero_screen.x - vp_center.x) < 14.0, "hero sits on the vertical centre line (dx %.1fpx)" % absf(hero_screen.x - vp_center.x))

	# ---- 截图：正后背视角 + 小队列队（供人工看图验收）----
	if DisplayServer.get_name() != "headless":
		TimeManager.begin(11)
		TimeManager.set_speed(0.0)
		# 让小队重新列队到主角身后，站定后取景
		hero.global_position = Vector3(6.0, 0.0, 18.0)
		tp.yaw = PI                                   # 面向城内（-Z 方向看主城）
		tp.pitch = -0.42
		for m in members:
			var p := m as Pawn
			p.global_position = hero.global_position + Vector3(
				cos(float(members.find(m) + 1) * 1.9) * 2.4, 0.0, sin(float(members.find(m) + 1) * 1.9) * 2.4 + 2.2)
		controller.enter_hero_mode()
		controller._sync_focus_marker(null)
		for _f in 24:
			await get_tree().physics_frame
		# 冻结时间会弹出 P 键暂停遮罩——验收截图不需要它（HUD 面板保留）
		var hud := main.get_node_or_null("HUD") as CanvasLayer
		var pause_overlay := hud.get("pause_overlay") as CanvasItem if hud != null else null
		if pause_overlay != null:
			pause_overlay.visible = false
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://artifacts/v12-back-view-squad.png")
		print("saved artifacts/v12-back-view-squad.png")
		TimeManager.set_speed(1.0)

	print("gather_probe: %d failure(s)" % _failures)
	get_tree().quit(_failures)
