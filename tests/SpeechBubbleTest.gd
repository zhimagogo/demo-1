extends Node
## v14 小兵人设气泡回归：godot --headless --path . tests/SpeechBubbleTest.tscn
## 覆盖：人设台词池覆盖全部友方小兵（主角/野怪无台词）、心情映射、
##       气泡生命周期（显示→宽度自适应→自动隐藏）、并发上限与名额归还、
##       「不要太频繁」的数值约束、死亡抑制、头顶定位、自动冒泡端到端。

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var spawner := world.get_node("PawnSpawner")

	# ---- 1) 人设台词池：八类友方小兵齐全，每池 ≥2 条且简短 ----
	var full_mood_ids: Array = [
		&"settler_warrior", &"settler_mage", &"settler_assassin",
		&"settler_archer", &"colonist",
	]
	for id in full_mood_ids:
		for mood in [&"idle", &"work", &"combat"]:
			var lines: Array = GameDefs.bubble_lines_for(id, mood)
			_check(lines.size() >= 2, "bubble pool %s/%s has >=2 lines (%d)" % [id, mood, lines.size()])
			for line in lines:
				_check(line is String and line.length() >= 2 and line.length() <= 14,
					"bubble line is short non-empty string (%s/%s: %s)" % [id, mood, line])
	# 流民只有 idle 池：work/combat 心情自动回落 idle 口白
	var ref_idle: Array = GameDefs.bubble_lines_for(&"refugee", &"idle")
	_check(ref_idle.size() >= 2, "refugee idle pool has >=2 lines (%d)" % ref_idle.size())
	_check(GameDefs.bubble_lines_for(&"refugee", &"work") == ref_idle,
		"refugee work mood falls back to the idle pool")
	_check(GameDefs.bubble_lines_for(&"refugee", &"combat") == ref_idle,
		"refugee combat mood falls back to the idle pool")
	# 主角 / 野怪没有台词：永不冒泡
	for silent in [&"hero_warrior", &"raider", &"raider_elite", &"raider_boss"]:
		_check(GameDefs.bubble_lines_for(silent, &"idle").is_empty(),
			"%s has no bubble lines (hero/raiders stay silent)" % silent)
	# 人设区分度：不同职业的日常池内容确实不同
	_check(GameDefs.bubble_lines_for(&"settler_warrior", &"idle") != GameDefs.bubble_lines_for(&"settler_assassin", &"idle"),
		"warrior and assassin settlers have different persona pools")
	_check(GameDefs.bubble_lines_for(&"settler_mage", &"idle") != GameDefs.bubble_lines_for(&"settler_archer", &"idle"),
		"mage and archer settlers have different persona pools")

	# ---- 2) 心情映射：状态名 → 台词池 ----
	_check(SpeechBubble3D.mood_for_state("fight") == &"combat", "fight state maps to combat mood")
	_check(SpeechBubble3D.mood_for_state("villager_flee") == &"combat", "villager_flee maps to combat mood")
	for working in ["harvest", "villager_work", "villager_deliver", "patrol", "move"]:
		_check(SpeechBubble3D.mood_for_state(working) == &"work", "%s maps to work mood" % working)
	for chilling in ["idle", "rest", "wander", "follow", "hero_idle"]:
		_check(SpeechBubble3D.mood_for_state(chilling) == &"idle", "%s maps to idle mood" % chilling)

	# ---- 3) 频率约束（「不要太频繁」的硬保证）----
	_check(SpeechBubble3D.INTERVAL_MIN >= 30.0, "min gap between bubbles >= 30s (%.0f)" % SpeechBubble3D.INTERVAL_MIN)
	_check(SpeechBubble3D.INTERVAL_MAX > SpeechBubble3D.INTERVAL_MIN, "max gap > min gap")
	_check(SpeechBubble3D.FIRST_DELAY_MIN >= 10.0, "first bubble waits >= 10s after spawn")
	_check(SpeechBubble3D.DISPLAY_SEC <= 6.0, "bubble display stays short (<= 6s)")
	_check(SpeechBubble3D.MAX_CONCURRENT <= 4, "global concurrent bubble cap is tight (%d)" % SpeechBubble3D.MAX_CONCURRENT)
	var in_range := true
	for _i in 50:
		var iv := SpeechBubble3D.next_interval()
		if iv < SpeechBubble3D.INTERVAL_MIN or iv > SpeechBubble3D.INTERVAL_MAX:
			in_range = false
	_check(in_range, "next_interval() always samples inside [min, max]")

	# ---- 4) 组件挂载与初态 ----
	var soldier: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(8.0, 0.0, -20.0))
	_freeze(soldier)
	await get_tree().physics_frame
	var bubble := soldier.get_node_or_null("SpeechBubble3D") as SpeechBubble3D
	_check(bubble != null and soldier.speech_bubble == bubble, "pawn spawns with a SpeechBubble3D child")
	if bubble == null:
		_finish()
		return
	_check(bubble.is_in_group("speech_bubbles"), "bubble registers in the speech_bubbles group")
	_check(not bubble.is_showing() and not bubble.visible, "bubble starts hidden")

	# ---- 5) 手动生命周期：显示 / 文字 / 宽度自适应 / 自动隐藏 ----
	bubble.show_bubble("测试台词！", 0.7)
	_check(bubble.is_showing() and bubble.visible and bubble.current_text() == "测试台词！",
		"show_bubble displays the given text immediately")
	var f := UIStyle.make_font()
	var measured: Vector2 = f.get_string_size("测试台词！", HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
	var expect_px: float = measured.x + 26.0 * 2.0
	var got_px: float = bubble._bg.scale.x * 192.0
	_check(absf(got_px - expect_px) < 2.0,
		"bubble background width adapts to the text (%.0fpx vs %.0fpx expected)" % [got_px, expect_px])
	_check(SpeechBubble3D.active_count() == 1, "active bubble count tracked (1)")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(bubble.global_position.y > soldier.global_position.y + 2.0,
		"bubble floats well above the pawn's head (+%.2fm)" % (bubble.global_position.y - soldier.global_position.y))
	for _i in 120:
		await get_tree().physics_frame
	_check(not bubble.is_showing() and not bubble.visible, "bubble auto-hides after its duration")
	_check(SpeechBubble3D.active_count() == 0, "active count returns to 0 after hiding")

	# ---- 5.5) 俯视角可读性（v16 恒定屏幕像素）----
	# 近景相机（第三人称观距）：视野跨度 ≈ REF_SPAN → 不放大（保持 v14 近景观感）；
	# 俯瞰相机（等距 44m 级别观距）：跨度数倍 → 根节点等比放大，屏幕像素与近景一致。
	bubble.show_bubble("俯瞰可见", 3.0)
	await get_tree().physics_frame
	var near_cam := Camera3D.new()
	near_cam.fov = 78.0
	add_child(near_cam)
	near_cam.global_position = soldier.global_position + Vector3(0.0, 2.0, -5.0)
	near_cam.look_at(soldier.global_position + Vector3.UP * 2.4, Vector3.UP)
	near_cam.current = true
	bubble._follow()
	_check(bubble._view_scale <= 1.01,
		"near camera keeps bubble at original size (%.2fx)" % bubble._view_scale)
	var far_cam := Camera3D.new()
	far_cam.fov = 75.0
	add_child(far_cam)
	far_cam.global_position = soldier.global_position + Vector3(0.0, 44.0, 30.0)
	far_cam.look_at(soldier.global_position + Vector3.UP * 2.0, Vector3.UP)
	far_cam.current = true
	bubble._follow()
	_check(bubble._view_scale > 3.0 and bubble._view_scale <= SpeechBubble3D.VIEW_SCALE_MAX,
		"top-down camera scales bubble up for readability (%.1fx)" % bubble._view_scale)
	_check(bubble.scale.x > 2.0, "shown bubble root scale applies view scale (%.1fx)" % bubble.scale.x)
	_check(bubble.global_position.y > soldier.global_position.y + 2.4,
		"scaled bubble anchor rises so the tail stays above the head")
	near_cam.queue_free()
	far_cam.queue_free()
	(world.get_node("IsometricCamera") as Camera3D).current = true
	bubble.hide_now()
	await get_tree().physics_frame

	# ---- 6) 死亡抑制 ----
	soldier.set_dead(true)
	bubble.debug_set_timer(0.01)
	for _i in 12:
		await get_tree().physics_frame
	_check(not bubble.is_showing(), "dead pawns never bubble")
	soldier.set_dead(false)

	# ---- 7) 并发上限：满员时顺延，腾出名额后放行 ----
	var crowd: Array = []
	for i in 3:
		var p: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(),
			Vector3(12.0 + float(i) * 2.0, 0.0, -24.0))
		_freeze(p)
		crowd.append(p)
	var fourth: Pawn = spawner.call("spawn_colonist", Vector3(18.0, 0.0, -24.0))
	_freeze(fourth)
	await get_tree().physics_frame
	for p in crowd:
		(p.get_node("SpeechBubble3D") as SpeechBubble3D).show_bubble("占位", 30.0)
	_check(SpeechBubble3D.active_count() == 3, "three bubbles fill the cap")
	var fb := fourth.get_node("SpeechBubble3D") as SpeechBubble3D
	fb.debug_set_timer(0.01)
	for _i in 8:
		await get_tree().physics_frame
	_check(not fb.is_showing() and fb._timer > 0.0, "4th bubble defers while the cap is full (retry in %.1fs)" % fb._timer)
	(crowd[0].get_node("SpeechBubble3D") as SpeechBubble3D).hide_now()
	fb.debug_set_timer(0.01)
	for _i in 8:
		await get_tree().physics_frame
	_check(fb.is_showing(), "deferred bubble shows once a slot frees up")
	for p in crowd:
		(p.get_node("SpeechBubble3D") as SpeechBubble3D).hide_now()
	fb.hide_now()

	# ---- 8) 自动冒泡端到端：台词来自本单位的人设池 ----
	var all_lines := {}
	for mood in [&"idle", &"work", &"combat"]:
		for line in GameDefs.bubble_lines_for(&"settler_warrior", mood):
			all_lines[line] = true
	var fresh: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(6.0, 0.0, -16.0))
	_freeze(fresh)
	await get_tree().physics_frame
	var nfb := fresh.get_node("SpeechBubble3D") as SpeechBubble3D
	nfb.debug_set_timer(0.01)
	var shown := false
	for _i in 90:
		await get_tree().physics_frame
		if nfb.is_showing():
			shown = true
			break
	_check(shown, "auto timer fires and shows a bubble")
	_check(shown and all_lines.has(nfb.current_text()),
		"auto bubble text comes from this unit's persona pools (%s)" % nfb.current_text())
	nfb.hide_now()

	# ---- 9) 主角 / 野民实例：组件在但挑不出台词 ----
	var controller := world.get_node("HeroController") as HeroController
	var hero := controller.hero as Hero
	var hb := hero.get_node_or_null("SpeechBubble3D") as SpeechBubble3D
	_check(hb != null and hb.pick_line() == "", "hero has the component but never picks a line")
	var raider: Raider = spawner.call("spawn_raider", Vector3(24.0, 0.0, -30.0), GameDefs.raider_def())
	_freeze(raider)
	await get_tree().physics_frame
	_check((raider.get_node("SpeechBubble3D") as SpeechBubble3D).pick_line() == "",
		"raider has the component but never picks a line")

	_finish()


func _finish() -> void:
	print("SPEECH BUBBLE TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


## 冻结单位：Pawn 自身与状态机节点都要停（状态机是独立 Node，自己跑 _physics_process）。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)
