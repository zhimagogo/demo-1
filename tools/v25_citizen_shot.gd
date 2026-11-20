extends Node
## v25 交付留档工具：入住选职业 / 市民管理 / 转职 / 技能树 对照样张（不参与游戏运行）。
##
## 运行：godot --path . tools/v25_citizen_shot.tscn
## 输出：
##   artifacts/v25-settle-picker.png   流民入住职业选择弹窗（四职业卡 + 真暂停）
##   artifacts/v25-citizen-panel.png   市民管理（编队 4 槽 + 主角行 + 市民全表 + 转职按钮）
##   artifacts/v25-skill-tree.png      技能树界面（已点亮/已投入 + 发光连线 + 纹章背景）
##   artifacts/v25-skill-tree-locked.png 技能树状态卡（可点亮呼吸辉光 / 前置锁定 + 锁印）

var _main: Node


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
	var controller := world.get_node("HeroController") as HeroController
	controller.exit_hero_mode()
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午
	TimeManager.set_speed(1.0)
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	var spawner := world.get_node("PawnSpawner")
	(hud.get("pause_overlay") as CanvasItem).visible = false   # 冻结期 P 遮罩不入画

	# ==== 样张 1：入住职业选择弹窗 ====
	var build := world.get_node("BuildSystem") as BuildSystem
	var house_def: BuildingDef
	for definition in GameDefs.building_defs():
		if definition.id == &"house":
			house_def = definition
	build.enter_build_mode(house_def)
	build.try_place_at(Vector3(16.4, 0, 16.4))
	build.exit_build_mode()
	var house: Building = (get_tree().get_nodes_in_group("house")[0] as Building)
	var refugee: Pawn = spawner.call("spawn_refugee", house.global_position + Vector3(1.5, 0.0, 0.0))
	EventBus.refugee_arrived.emit(refugee, house)
	await get_tree().process_frame
	var picker = hud.get("settle_picker")
	await _snap("v25-settle-picker")
	picker.call("_choose", &"settler_warrior")   # 样张主角选战士；定居者留在城里当市民
	await get_tree().process_frame
	if hud.has_method("_dismiss_settlement_notice"):
		hud.call("_dismiss_settlement_notice")

	# ==== 样张 2：市民管理（编队 + 主角行 + 市民全表 + 转职按钮） ====
	var hero := controller.hero
	hero.set_party([])
	var names := ["林铁柱", "苏小满", "陈知秋"]
	var defs := [GameDefs.settler_warrior_def(), GameDefs.settler_mage_def(), GameDefs.settler_assassin_def()]
	var citizens: Array = []
	for i in defs.size():
		var c: Pawn = spawner.call("spawn_soldier", defs[i],
			hero.global_position + Vector3(3.0 + float(i) * 1.5, 0.0, 0.0))
		c.def.unit_name = names[i]
		citizens.append(c)
	await get_tree().physics_frame
	# 铁柱练到 Lv.5（出现转职按钮）并沿树点亮 职业技→伤害→生命；知秋直接转职成忍者做「已进阶」样例
	citizens[0].gain_xp(310)
	citizens[0].try_invest_skill_point(&"class_skill")
	citizens[0].try_invest_skill_point(&"damage")
	citizens[0].try_invest_skill_point(&"vitality")
	citizens[2].gain_xp(310)
	citizens[2].try_invest_skill_point(&"class_skill")
	(citizens[2] as Soldier).promote_to(&"settler_ninja")
	hero.gain_xp(200)   # 主角升几级，让技能点 > 0 入画
	await get_tree().process_frame
	var panel = hud.get("party_panel")
	panel.call("open")
	(hud.get("pause_overlay") as CanvasItem).visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("v25-citizen-panel")

	# ==== 样张 3：技能树（铁柱：职业技已点亮 → 伤害 2 级 → 生命 1 级） ====
	citizens[0].try_invest_skill_point(&"damage")
	var tree_panel = hud.get("skill_tree_panel")
	tree_panel.call("open_for", citizens[0])
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("v25-skill-tree")
	tree_panel.call("close")

	# ==== 样张 4：技能树状态卡（刺客 Lv.2 带余点：根节点可点亮呼吸辉光，
	#      后续两节点前置未满足 → 暗化 + 锁印；对照 v25.2 四态视觉） ====
	var rogue: Pawn = spawner.call("spawn_soldier", GameDefs.settler_assassin_def(),
		hero.global_position + Vector3(3.0, 0.0, 6.0))
	rogue.def.unit_name = "夜无声"
	rogue.gain_xp(40)   # Lv.2 → 1 技能点未投入
	await get_tree().physics_frame
	tree_panel.call("open_for", rogue)
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("v25-skill-tree-locked")
	tree_panel.call("close")
	panel.call("close")
	get_tree().quit()


func _snap(filename: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % filename)
	print("saved artifacts/%s.png" % filename)
