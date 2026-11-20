extends Node
## ============================================================================
## v33.1 UI 样张工具：验证「技能树紧凑卡 + 悬停浮窗」与「市民管理技能点实时刷新」。
##
##   bash tools/godot_locked.sh --path . tools/v331_ui_shot.tscn
##
## 产出（artifacts/，像素抓帧为窗口像素；逻辑坐标 = 画布基准 1152）：
##   v331-skilltree-compact.png   转职后 4 列进阶树（紧凑卡，不超框）
##   v331-skilltree-hover.png     鼠标悬停「跳劈」节点卡 → 浮动弹窗（完整说明 / 收益 / 前置 / 状态）
##   v331-citizen-before.png      市民管理：加点前（技能点 5）
##   v331-citizen-after.png       市民管理：在同一面板内加点后（技能点 4 + 攻击提升，无需重开）
##
## 只做展示与截图，不改任何玩法状态；退出码恒为 0（截图失败仅打印）。
## ============================================================================

const SHOT_DIR := "res://artifacts/"
const WATCHDOG_SEC := 90.0     # 兜底自退：任何脚本错误都不许把 godot 挂在这里

var _elapsed: float = 0.0


func _ready() -> void:
	call_deferred("_run")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > WATCHDOG_SEC:
		print("[v331] watchdog timeout, quit")
		get_tree().quit(1)


## 主面板（SkillTreePanel 是 FULL_RECT Control）：真正的面板是 CenterContainer 里的
## PanelContainer；NodeTip 浮窗也是 PanelContainer 直接子节点，必须排除（v33.1 首跑踩过）。
func _find_panel_container(root: Node) -> Control:
	for c in root.get_children():
		if c is CenterContainer:
			for cc in c.get_children():
				if cc is PanelContainer:
					return cc as Control
	for c in root.get_children():
		if c is PanelContainer and String(c.name) != "NodeTip":
			return c as Control
	return null


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR + name
	var err := img.save_png(path)
	print("[v331] shot ", path, " -> ", "OK" if err == OK else "ERR %d" % err)


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _run() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await _wait(3)
	var world := main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem"]:
		var s := world.get_node_or_null(n)
		if s != null:
			s.set_process(false)
			s.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	await _wait(3)

	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null:
		print("[v331] no pawn_spawner, abort")
		get_tree().quit(0)
		return
	# 转职后的狂战士：4 列进阶树（职业技 → 跳劈 → 伤害强化 → 生命强化）
	var adv: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-4.0, 0.0, -4.0))
	adv.level = 5
	adv.skill_points = 5
	var promoted: bool = adv.promote_to(&"settler_berserker")
	print("[v331] promoted=", promoted, " tree=", adv.skill_tree.tree_def.id,
		" cols=", adv.skill_tree.tree_def.max_depth() + 1)
	adv.try_invest_skill_point(&"class_skill")
	adv.try_invest_skill_point(&"advanced_skill")
	await _wait(3)

	var tree_panel := get_tree().get_first_node_in_group("skill_tree_panel")
	if tree_panel == null:
		print("[v331] no skill_tree_panel, abort")
		get_tree().quit(0)
		return
	tree_panel.open_for(adv)
	await _wait(20)
	Input.warp_mouse(Vector2(20.0, 620.0))   # 先把鼠标停到角落，保证「无悬停」样张干净
	await _wait(4)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var panel_ctrl := _find_panel_container(tree_panel)
	var panel_rect: Rect2 = panel_ctrl.get_global_rect() if panel_ctrl != null else Rect2()
	print("[v331] viewport(logic)=", vp, " panel rect=", panel_rect,
		" fits=", panel_rect.size.x <= vp.x and panel_rect.size.y <= vp.y)
	var lowest := 0.0
	for id in tree_panel._cards.keys():
		var c: Control = tree_panel._cards[id]
		if c != null and is_instance_valid(c):
			var r: Rect2 = c.get_global_rect()
			lowest = maxf(lowest, r.end.y)
			print("[v331] card ", id, " rect=", r)
	var tree_rect: Rect2 = tree_panel._tree_area.get_global_rect()
	print("[v331] tree area rect=", tree_rect, " lowest card bottom=", lowest,
		" cards inside tree=", lowest <= tree_rect.end.y + 2.0)
	await _shot("v331-skilltree-compact.png")

	# 悬停「跳劈」节点卡：先真移鼠标，再兜底直接填浮窗（保证截图一定含浮窗样式）
	var card: Control = tree_panel._cards.get(&"advanced_skill")
	if card != null and is_instance_valid(card):
		Input.warp_mouse(card.get_global_rect().get_center())
		await _wait(6)
		var tip_visible: bool = tree_panel._tip.visible
		print("[v331] hover tip visible after warp =", tip_visible)
		if not tip_visible:
			tree_panel._fill_tip(adv.skill_tree.node(&"advanced_skill"))
			tree_panel._position_tip(card)
			tree_panel._tip.visible = true
			await _wait(2)
		await _shot("v331-skilltree-hover.png")
	tree_panel.close()
	await _wait(6)

	# 市民管理：同面板内加点 → 技能点 / 攻击实时刷新（不必关掉重开）
	var citizen := get_tree().get_first_node_in_group("party_panel")
	if citizen == null:
		print("[v331] no citizen panel, abort")
		get_tree().quit(0)
		return
	citizen.open()
	await _wait(12)
	await _shot("v331-citizen-before.png")
	var invested: bool = adv.try_invest_skill_point(&"damage")
	await _wait(4)
	print("[v331] invested damage =", invested, " skill_points=", adv.skill_points,
		" attacker.damage=", adv.attacker.damage)
	await _shot("v331-citizen-after.png")

	print("[v331] done")
	get_tree().quit(0)
