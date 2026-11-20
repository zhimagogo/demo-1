extends Node
## ============================================================================
## 真机 UI 截图采集（v6 图标验收用；**必须开窗口运行，不能 --headless**）。
##
##   godot --path . tests/UiCapture.tscn --log-file /private/tmp/demo-1-uicapture.log
##
## 产出（都落在 artifacts/，该目录有 .gdignore 不参与资源导入）：
##   ui-hud.png / ui-tutorial.png / ui-hero.png   整帧截图（1600×1000；v21 起兵营与招募菜单已删除）
##   ui-crop-<panel>.png                                           逐面板裁切 + 2× 最近邻放大（供肉眼/视觉复核）
##   ui-icon-rects.json                                            每个「非空图标控件」的屏幕矩形 + tint + 所属面板
##                                                                 （供 PixelCheck 做「图标真的画出来了」的像素断言）
##
## 为什么要采集矩形：PixelCheck 是 headless 的，拿不到节点树。把「图标控件的屏幕矩形 +
## 它被 modulate 成的颜色」落盘，headless 端就能在同一张截图上验证「这个矩形里真的有该颜色的
## 图标前景像素」——这正是「代码接了图标但渲染成空白/黑块」的唯一客观拦截方式。
##
## 确定性：窗口尺寸/相机/时间/天气全部固定；不打随机数。
## ============================================================================

const OUT_DIR := "res://artifacts/"
const FRAME := Vector2i(1600, 1000)
const PANEL_PROPS := [
	"top_bar", "build_menu", "hero_panel", "quest_panel",
	"selection_panel", "event_log", "boss_banner", "tutorial_overlay", "minimap",
]

var _main: Node
var _hud: Node
var _world: Node
var _captures: Dictionary = {}
var _failures: int = 0
var _last_img: Image = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("FAIL: UiCapture 需要真实窗口（请去掉 --headless）")
		get_tree().quit(1)
		return
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)
		push_error("FAIL: " + msg)


func _run() -> void:
	get_window().size = FRAME
	await _frames(12)
	# 注意：窗口尺寸可能被系统钳制（macOS 可用区），且 stretch=canvas_items 会把画布缩放后
	# 铺满窗口 —— 所以「控件 global_rect（画布空间）」≠「截图像素（窗口空间）」。
	# 台账里记录的必须是**窗口像素**：统一经 viewport.get_final_transform() 映射（见 _win_rect）。
	var vp := get_viewport().get_visible_rect().size
	print("STAT 窗口=%s 画布视口=%s scale_factor=%.3f final_transform=%s"
		% [get_window().size, vp, get_window().content_scale_factor, get_viewport().get_final_transform()])
	_check(vp.x >= 1024.0 and vp.y >= 600.0, "画布视口尺寸合理（%s）" % vp)

	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await _frames(12)
	_hud = _main.get_node_or_null("HUD")
	_world = _main.get_node_or_null("WorldRoot")
	_check(_hud != null, "HUD 节点存在")
	if _hud == null:
		_finish()
		return

	# —— 冻结环境：上午 10 点 + 晴天（确定性；面板底色/图标对比度不受天气影响，但少一个变量）——
	var weather := _world.get_node_or_null("WeatherSystem")
	if weather != null:
		weather._apply_state(WeatherSystem.State.CLEAR)
		weather._strength_target = 0.0
		weather._strength_walk_timer = 99.0
		weather._thunder_timer = 99.0
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	await _frames(24)

	# —— 内容触发：全部走真实信号 / 真实系统 ——
	EventBus.game_message.emit("UI 图标验收：日志占位 A", Color(1, 1, 1))
	EventBus.game_message.emit("UI 图标验收：日志占位 B", UIStyle.GOLD)
	# v17 去冗余：单选主角不再弹 SelectionInfoPanel（主角卡唯一来源 = HeroPanel），
	# 这里改选一名士兵驱动选中面板（帧 3 的 HeroPanel 截图仍以主角为主角）。
	var hero := _find_hero()
	var spawner := _world.get_node_or_null("PawnSpawner")
	var sel_soldier: Node = null
	if spawner != null and spawner.has_method("spawn_soldier"):
		sel_soldier = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(6.0, 0.0, 6.0))
	if sel_soldier != null:
		SelectionManager.select_only(sel_soldier)
	elif hero != null:
		SelectionManager.select_only(hero)
	var boss: Node = null
	if spawner != null and spawner.has_method("spawn_raider"):
		boss = spawner.spawn_raider(Vector3(34.0, 0.0, 34.0), GameDefs.raider_boss_def())
	_check(boss != null, "头目已刷出（驱动 BossBanner）")
	EventBus.boss_spawned.emit(boss)
	await _frames(30)

	# —— 帧 1：基线 HUD（顶栏 / 建造菜单 / 任务卡 / 小地图 / 日志 / 选中面板 / 头目横幅）——
	var tb := _hud.get("top_bar") as Control
	if tb != null:
		print("STAT 坐标映射自检：top_bar 画布矩形=%s → 窗口像素=%s（图像 %s）"
			% [tb.get_global_rect(), _win_rect(tb.get_global_rect()),
				get_window().size])
	# 面板可见性台账（有些面板「树里有贴图」但根本没显示——只有真机能抓到）
	for prop in PANEL_PROPS:
		var p = _hud.get(prop)
		if p is CanvasItem:
			print("STAT 可见性 %-18s visible_in_tree=%s" % [prop, (p as CanvasItem).is_visible_in_tree()])
	await _capture("ui-hud", ["top_bar", "build_menu", "quest_panel", "minimap",
		"event_log", "selection_panel", "boss_banner"], true)

	# —— 帧 1b：选中面板实拍（士兵；v17 起单选主角不再弹本面板）——
	_log_selection_icon("士兵")
	await _capture("ui-select-soldier", ["selection_panel"], false)

	# v21：兵营与招募菜单（RecruitMenu）已删除，原「帧 2：ui-recruit」段落移除。

	# —— 帧 2b：选中面板实拍（建筑 / 资源点 / 野怪三条分支）——
	# 注意：游戏内**只有 Pawn 在 "selectable" 组**，SelectionManager.select_only() 只接受有
	# set_selected() 的节点 —— 建筑/资源点无法用 select_only 选中（会报 Nonexistent function）。
	# 这里按面板的**信号契约**直发 selection_changed，验证面板三条分支的图标渲染。
	var any_building: Node = _first_in_group("building")
	if any_building != null:
		EventBus.selection_changed.emit([any_building])
		await _frames(16)
		_log_selection_icon("建筑")
		await _capture("ui-select-building", ["selection_panel"], false)
	var rn := _first_in_group("resource_node")
	if rn != null:
		EventBus.selection_changed.emit([rn])
		await _frames(16)
		_log_selection_icon("资源点")
		await _capture("ui-select-resource", ["selection_panel"], false)
	var sp := _spawner()
	var mob: Node = null
	if sp != null and sp.has_method("spawn_raider"):
		mob = sp.spawn_raider(Vector3(26.0, 0.0, -26.0), GameDefs.raider_def())
	if mob != null:
		SelectionManager.select_only(mob)
		await _frames(16)
		_log_selection_icon("野怪")
		await _capture("ui-select-enemy", ["selection_panel"], false)
	if hero != null:
		SelectionManager.select_only(hero)
		await _frames(8)

	# —— 帧 3：主角模式（HeroPanel 显形）——
	var controller := _world.get_node_or_null("HeroController")
	if controller != null and controller.has_method("enter_hero_mode"):
		controller.enter_hero_mode()
		await _frames(20)
		var hp = _hud.get("hero_panel")
		if hp is CanvasItem:
			# 专项探针：进主角模式后主角面板到底显示了没有（实测值，不做推断）
			print("STAT 主角模式后：hero_mode_active=%s HeroPanel.visible_in_tree=%s"
				% [SelectionManager.hero_mode_active, (hp as CanvasItem).is_visible_in_tree()])
			_check((hp as CanvasItem).is_visible_in_tree(),
				"进入主角模式后 HeroPanel 真的显示出来（实测 visible_in_tree=%s）"
				% (hp as CanvasItem).is_visible_in_tree())
		await _capture("ui-hero", ["hero_panel"], false)
		# 版面：HeroPanel 是否压到 BuildMenu / 选中面板（回答 Lead 的问题 3）
		var hp_rect := _panel_win_rect("hero_panel")
		print("STAT HeroPanel 窗口像素矩形：%s" % hp_rect)
		_check(hp_rect.size.x >= 120.0 and hp_rect.size.y >= 120.0,
			"HeroPanel 有实际版面尺寸（%.0fx%.0f）" % [hp_rect.size.x, hp_rect.size.y])
		# v17 布局契约（客观断言）：合并卡不得压建造菜单，也不得压左上任务卡
		var o_bm := _print_overlap("hero_panel", "build_menu")
		_check(o_bm.size.x < 1.0 or o_bm.size.y < 1.0,
			"HeroPanel 与建造菜单零相交（实测交叠 %.0fx%.0f）" % [o_bm.size.x, o_bm.size.y])
		var o_qp := _print_overlap("hero_panel", "quest_panel")
		_check(o_qp.size.x < 1.0 or o_qp.size.y < 1.0,
			"HeroPanel（含小队区）与任务卡零相交（实测交叠 %.0fx%.0f）" % [o_qp.size.x, o_qp.size.y])
		_print_overlap("hero_panel", "selection_panel")
		_print_overlap("hero_panel", "minimap")
		controller.exit_hero_mode()
	else:
		_check(false, "HeroController 可进入主角模式（用于 HeroPanel 截图）")

	# —— 帧 4：新手引导浮层 ——
	var tut = get_tree().get_first_node_in_group("tutorial_system")
	if tut != null:
		tut.restart()
		await _frames(24)
		await _capture("ui-tutorial", ["tutorial_overlay"], false)
		tut.skip()
		await _frames(4)
	else:
		_check(false, "tutorial_system 存在（用于 TutorialOverlay 截图）")

	_finish()


## 截一帧 → 落盘 PNG + 逐面板裁切 + （可选）收集图标矩形。
func _capture(name: String, crops: Array, collect_icons: bool) -> void:
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_check(img != null and not img.is_empty(), "%s 截帧成功" % name)
	if img == null or img.is_empty():
		return
	_last_img = img
	var err := img.save_png(OUT_DIR + name + ".png")
	_check(err == OK, "%s 已落盘（%s.png）" % [name, name])

	var icons: Array = []
	if collect_icons:
		icons = _collect_icons(img)
		print("STAT %s 采集到非空图标控件 %d 个" % [name, icons.size()])
		_tint_diag(img, icons)
	_captures[name] = {
		"image": name + ".png",
		"viewport": [img.get_width(), img.get_height()],
		"window": [get_window().size.x, get_window().size.y],
		"canvas": [int(get_viewport().get_visible_rect().size.x), int(get_viewport().get_visible_rect().size.y)],
		"final_transform": str(get_viewport().get_final_transform()),
		"icons": icons,
	}

	for prop in crops:
		var panel = _hud.get(prop)
		if panel == null or not (panel is Control):
			print("WARN 面板 %s 不可裁切（不存在）" % prop)
			continue
		if not (panel as CanvasItem).is_visible_in_tree():
			print("WARN 面板 %s 当前不可见（is_visible_in_tree=false），裁切内容会是背景" % prop)
		_write_crop(img, panel as Control, "%s-crop-%s" % [name, prop])


## 自诊断：用刚采的这一帧验证「台账矩形里真的有该 tint 的图标像素」。
## 坐标映射错了（画布 vs 窗口像素）会立刻在这里暴露，不必等 PixelCheck。
func _tint_diag(img: Image, icons: Array) -> void:
	var hits: Array[float] = []
	for rec in icons:
		var r: Array = rec["rect"]
		var t: Array = rec["tint"]
		if r.size() != 4 or t.size() != 4:
			continue
		var rect := Rect2i(r[0], r[1], r[2], r[3])
		var tint := Color(t[0], t[1], t[2], t[3])
		var lo := (tint.r + tint.g + tint.b) / 3.0 * clampf(tint.a, 0.25, 1.0) * 0.5
		var n := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := img.get_pixel(x, y)
				if (c.r + c.g + c.b) / 3.0 >= lo:
					n += 1
		hits.append(float(n) / float(maxi(rect.size.x * rect.size.y, 1)))
	if hits.is_empty():
		print("WARN 自诊断：没有可检图标")
		return
	hits.sort()
	var painted := 0
	for h in hits:
		if h >= 0.05:
			painted += 1
	print("STAT 自诊断 tint 命中：图标 %d 个，命中率 ≥0.05 的 %d 个，中位 %.3f，最低 %.3f，最高 %.3f"
		% [hits.size(), painted, hits[hits.size() / 2], hits[0], hits[hits.size() - 1]])


## 画布空间矩形 → 窗口像素矩形（截图坐标系）。窗口被系统钳制 / 画布缩放时这一步是必需的。
func _win_rect(r: Rect2) -> Rect2:
	var xf := get_viewport().get_final_transform()
	var a := xf * r.position
	var b := xf * r.end
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(b.x - a.x), absf(b.y - a.y)))


func _write_crop(img: Image, panel: Control, crop_name: String) -> void:
	var isize := img.get_size()
	var r := _win_rect(panel.get_global_rect())
	var pos := Vector2i(clampi(int(floor(r.position.x)) - 8, 0, isize.x - 1),
		clampi(int(floor(r.position.y)) - 8, 0, isize.y - 1))
	var end := Vector2i(clampi(int(ceil(r.end.x)) + 8, pos.x + 1, isize.x),
		clampi(int(ceil(r.end.y)) + 8, pos.y + 1, isize.y))
	var rect := Rect2i(pos, end - pos)
	if rect.size.x < 4 or rect.size.y < 4:
		print("WARN 面板裁切区域过小，跳过：%s %s" % [crop_name, rect])
		return
	var region := img.get_region(rect)
	region.resize(rect.size.x * 2, rect.size.y * 2, Image.INTERPOLATE_NEAREST)
	region.save_png(OUT_DIR + crop_name + ".png")
	print("STAT 裁切 %s %s（2× 放大）" % [crop_name, rect])


## 遍历 HUD 树，记录每个「有贴图且在树内可见」的 TextureRect（含 IconRect / IconBadge 内部图标）。
func _collect_icons(img: Image) -> Array:
	var out: Array = []
	var owner_map := _panel_owner_map()
	_walk(_hud, owner_map, out)
	# 画布空间 → 窗口像素（截图空间）；越界的直接丢掉（不参与像素断言）
	var kept: Array = []
	for rec in out:
		var c: Array = rec["rect_canvas"]
		var wr := _win_rect(Rect2(c[0], c[1], c[2], c[3]))
		rec["rect"] = [int(round(wr.position.x)), int(round(wr.position.y)),
			int(round(wr.size.x)), int(round(wr.size.y))]
		if rec["rect"][0] >= 0 and rec["rect"][1] >= 0 \
				and rec["rect"][0] + rec["rect"][2] <= img.get_width() \
				and rec["rect"][1] + rec["rect"][3] <= img.get_height():
			kept.append(rec)
	out = kept
	out.sort_custom(func(a, b): return a["panel"] < b["panel"] or (a["panel"] == b["panel"] and a["rect"][1] < b["rect"][1]))
	return out


func _panel_owner_map() -> Dictionary:
	var map := {}
	for prop in PANEL_PROPS:
		var p = _hud.get(prop)
		if p is Node:
			map[(p as Node).get_instance_id()] = prop
	return map


func _walk(node: Node, owner_map: Dictionary, out: Array) -> void:
	if node is TextureRect:
		var tr := node as TextureRect
		if tr.texture != null and tr.is_visible_in_tree():
			var r := tr.get_global_rect()
			if r.size.x >= 4.0 and r.size.y >= 4.0:
				var rec := {
					"cls": node.get_class() if not (node is IconRect) else "IconRect",
					"id": String(tr.get("icon_id")) if tr.get("icon_id") != null else "",
					"panel": _owner_of(node, owner_map),
					"rect_canvas": [r.position.x, r.position.y, r.size.x, r.size.y],
					"tint": [tr.self_modulate.r, tr.self_modulate.g, tr.self_modulate.b, tr.self_modulate.a],
					"modulate": [tr.modulate.r, tr.modulate.g, tr.modulate.b, tr.modulate.a],
					"px": tr.texture.get_width(),
				}
				out.append(rec)
	for child in node.get_children():
		_walk(child, owner_map, out)


func _owner_of(node: Node, owner_map: Dictionary) -> String:
	var cur := node
	while cur != null:
		if owner_map.has(cur.get_instance_id()):
			return String(owner_map[cur.get_instance_id()])
		cur = cur.get_parent()
	return "other"




func _panel_win_rect(prop: String) -> Rect2:
	var p = _hud.get(prop)
	if p is Control:
		return _win_rect((p as Control).get_global_rect())
	return Rect2()


## 两个面板是否互相遮挡：打印交叠矩形与面积（客观度量，不靠肉眼），并返回交叠矩形。
func _print_overlap(a: String, b: String) -> Rect2:
	var ra := _panel_win_rect(a)
	var rb := _panel_win_rect(b)
	var inter := ra.intersection(rb)
	var desc := "%s=%.0fx%.0f@(%.0f,%.0f) %s=%.0fx%.0f@(%.0f,%.0f)" % [
		a, ra.size.x, ra.size.y, ra.position.x, ra.position.y,
		b, rb.size.x, rb.size.y, rb.position.x, rb.position.y]
	if inter.size.x > 1.0 and inter.size.y > 1.0:
		print("STAT 重叠 %s ∩ %s = %.0fx%.0f（%.0f px²）| %s"
			% [a, b, inter.size.x, inter.size.y, inter.size.x * inter.size.y, desc])
	else:
		print("STAT 重叠 %s ∩ %s = 不相交 | %s" % [a, b, desc])
	return inter


## 绘制层级：谁在上面（同一父节点下的子节点索引，越大越晚绘制=越靠前）。
func _draw_order(a: String, b: String) -> String:
	var ia := _draw_index(a)
	var ib := _draw_index(b)
	if ia < 0 or ib < 0:
		return "无法判定（%s=%d %s=%d）" % [a, ia, b, ib]
	if ia == ib:
		return "同层（%s=%d）" % [a, ia]
	return "%s 在上（index %d > %d）" % [a if ia > ib else b, maxi(ia, ib), mini(ia, ib)]


func _draw_index(prop: String) -> int:
	var p = _hud.get(prop)
	if not (p is Node):
		return -1
	var cur: Node = p
	var guard := 0
	while cur.get_parent() != null and cur.get_parent().get_parent() != _hud and guard < 16:
		cur = cur.get_parent()
		guard += 1
	return cur.get_index()


## 底色不透视度量：取面板内「底部只有底色」的一条带，统计亮度与亮像素占比。
## 半透明底会把 3D 世界/下层卡片透出来 → 亮像素占比与亮度方差显著上升。
func _panel_bg_stats(prop: String) -> void:
	if _last_img == null:
		return
	var r := _panel_win_rect(prop)
	if r.size.y < 40.0:
		return
	# 注意：带的上下边界必须严格落在面板矩形内（否则会把面板外的世界/其他面板算进来）
	var band_h := mini(60.0, r.size.y * 0.25)
	var y1 := int(r.end.y) - 6
	var y0 := int(y1 - band_h)
	var n := 0
	var bright := 0
	var sum := 0.0
	var mx := 0.0
	for y in range(maxi(y0, 0), maxi(y1, 1)):
		for x in range(int(r.position.x) + 6, int(r.end.x) - 6, 2):
			if x < 0 or y < 0 or x >= _last_img.get_width() or y >= _last_img.get_height():
				continue
			var c := _last_img.get_pixel(x, y)
			var l := (c.r + c.g + c.b) / 3.0
			n += 1
			sum += l
			mx = maxf(mx, l)
			if l > 0.30:
				bright += 1
	if n == 0:
		return
	print("STAT %s 底部底色带：均亮 %.3f 最大 %.3f 亮像素(>0.30)占比 %.1f%%（不透视时应接近纯底色）"
		% [prop, sum / n, mx, 100.0 * bright / n])


## 选中面板当前展示的图标 id（验证「按选中对象取真图标」这条契约）。
func _log_selection_icon(tag: String) -> void:
	var panel = _hud.get("selection_panel")
	if panel == null:
		return
	var ic = panel.get("_icon")
	var iid := "?"
	if ic != null and ic.get("icon_id") != null:
		iid = String(ic.icon_id)
	print("STAT 选中面板[%s] 图标 id=%s visible=%s 非空贴图=%d"
		% [tag, iid, (panel as CanvasItem).is_visible_in_tree(), _count_tex(panel)])


func _count_tex(node: Node) -> int:
	var n := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		n += 1
	for c in node.get_children():
		n += _count_tex(c)
	return n


func _first_in_group(g: String) -> Node:
	for n in get_tree().get_nodes_in_group(g):
		if n != null and is_instance_valid(n):
			return n
	return null


func _spawner() -> Node:
	return null if _world == null else _world.get_node_or_null("PawnSpawner")


func _find_hero() -> Node:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var f := FileAccess.open(OUT_DIR + "ui-icon-rects.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_captures, "  "))
		f.close()
		print("STAT 图标矩形台账已写：artifacts/ui-icon-rects.json（%d 帧）" % _captures.size())
	else:
		_check(false, "图标矩形台账可写入")
	print("UI CAPTURE: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
