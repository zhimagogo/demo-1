extends Node
## 小地图朝向一致性测试（v3.1 回归线）：
## 对 4 档相机朝向 × 8 个罗盘方向，验证「单位在屏幕上的方位角 == 在小地图上的方位角」。
## v3.0 的朝向 bug：相机默认旋转 90°（屏幕上方=西），小地图却固定北在上——两者差 90°。
## godot --headless --path . tests/MinimapOrientation.tscn --fixed-fps 60

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().process_frame
	# 默认第三人称亲征：本测试验证等距相机的小地图视野框 → 先切战术俯瞰（iso 为 current 相机）
	var hc := _main.get_node("WorldRoot/HeroController") as HeroController
	hc.exit_hero_mode()
	await get_tree().process_frame
	var hud := _main.get_node_or_null("HUD")
	var mm = hud.get("minimap") if hud != null else null
	_check(mm != null, "minimap node exists")
	if mm == null:
		_finish()
		return
	var cam := _main.get_node("WorldRoot/IsometricCamera") as IsometricCamera
	var vp_size := get_viewport().get_visible_rect().size
	var screen_center := vp_size * 0.5
	var map_center := Vector2(mm.MAP_PX * 0.5, mm.MAP_PX * 0.5)

	# 8 个罗盘方向（世界坐标，距焦点 30m）
	var dirs := {
		"北": Vector2(0, -30), "东北": Vector2(21, -21), "东": Vector2(30, 0), "东南": Vector2(21, 21),
		"南": Vector2(0, 30), "西南": Vector2(-21, 21), "西": Vector2(-30, 0), "西北": Vector2(-21, -21),
	}
	# 相机 4 档朝向（_yaw_step 0..3 → yaw 0/90/180/270）
	for step in 4:
		cam._yaw_step = step
		await get_tree().process_frame
		await get_tree().process_frame
		mm._refresh_rotation()
		var worst: float = 0.0
		var worst_dir := ""
		for dir_name in dirs:
			var w: Vector2 = dirs[dir_name]
			# 屏幕方位：投影 (w.x, 0, w.y) 相对屏幕中心
			var sp: Vector2 = cam.unproject_position(Vector3(w.x, 0.0, w.y))
			var s_vec: Vector2 = (sp - screen_center).normalized()
			# 小地图方位：_w2m 相对地图中心
			var mp: Vector2 = mm._w2m(w)
			var m_vec: Vector2 = (mp - map_center).normalized()
			# 方位角差（度）；两个归一化向量点积 < 0 即反向，> 0.866 即夹角 < 30°
			var dot: float = s_vec.dot(m_vec)
			var angle_deg: float = rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
			if angle_deg > worst:
				worst = angle_deg
				worst_dir = dir_name
		_check(worst < 30.0, "yaw_step=%d（%.0f°）：8 方向屏幕/小地图方位差均 < 30°（最大 %.1f°，%s）" % [
			step, float(step) * 90.0, worst, worst_dir])

	# 视野框几何（v3.1 白线修复回归线）：闭合、全在画布内、非退化（有面积），
	# 且相机在地图中心 / 四角都要成立（旧版径向钳制会在角落把框拉变形）
	for focus in [Vector2(0, 0), Vector2(48, 48), Vector2(-48, 48), Vector2(48, -48), Vector2(-48, -48)]:
		for step in [0, 1]:
			cam._yaw_step = step
			cam.focus_on(Vector3(focus.x, 0.0, focus.y))
			await get_tree().process_frame
			await get_tree().process_frame
			mm._refresh_rotation()
			var vc: PackedVector2Array = mm.get_view_corners_map()
			var closed: bool = vc.size() == 5 and vc[0].is_equal_approx(vc[4])
			var inside: bool = true
			for pt in vc:
				if pt.x < -0.5 or pt.y < -0.5 or pt.x > mm.MAP_PX + 0.5 or pt.y > mm.MAP_PX + 0.5:
					inside = false
			# 鞋带公式面积（取 abs）
			var area: float = 0.0
			for i in 4:
				area += vc[i].x * vc[i + 1].y - vc[i + 1].x * vc[i].y
			area = absf(area) * 0.5
			_check(closed and inside and area > 200.0,
				"view frustum closed/in-bounds/non-degenerate @focus(%.0f,%.0f) yaw%d（闭合=%s 界内=%s 面积=%.0f）" % [
					focus.x, focus.y, step * 90, closed, inside, area])

	# 点击映射闭环：随机 12 个画布点 → 世界 → 再画回，应回到原点（旋转可逆）
	mm._refresh_rotation()
	var roundtrip_worst: float = 0.0
	for i in 12:
		var canvas_pt := Vector2(randf() * mm.MAP_PX, randf() * mm.MAP_PX)
		var world: Vector2 = mm._px_to_world(canvas_pt)
		var back: Vector2 = mm._w2m(world)
		roundtrip_worst = maxf(roundtrip_worst, canvas_pt.distance_to(back))
	_check(roundtrip_worst < 0.6, "click mapping roundtrip error < 0.6px（%.2fpx）" % roundtrip_worst)
	_finish()


func _finish() -> void:
	print("MINIMAP ORIENTATION: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
