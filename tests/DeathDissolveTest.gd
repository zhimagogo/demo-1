extends Node
## 死亡表现专项回归（v16）：godot --headless --path . tests/DeathDissolveTest.tscn --fixed-fps 60
## 覆盖：敌方死亡不缩小 / 播 Death 动画 / 动画定格后模型换溶解材质且进度推进 /
## 完全消散后按时释放；非敌方单位仍走旧缩小淡出路径。


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


## 按物理帧等待约 sec 秒（默认 60Hz 物理 tick；等待期间世界照常推进）。
func _wait_phys(sec: float) -> void:
	var frames := int(round(sec * 60.0))
	for _i in frames:
		await get_tree().physics_frame


## 在模型子树里统计「溶解材质」并返回 { 材质列表, 最大进度 }。
func _scan_dissolve(node: Node) -> Dictionary:
	var mats: Array = []
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.get_active_material(i)
				if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
						and String((m as ShaderMaterial).shader.resource_path).contains("death_dissolve"):
					mats.append(m)
	for c in node.get_children():
		var sub := _scan_dissolve(c)
		mats.append_array(sub["mats"])
	var max_prog: float = 0.0
	for m in mats:
		var pv: Variant = (m as ShaderMaterial).get_shader_parameter(&"dissolve_progress")
		if pv != null:
			max_prog = maxf(max_prog, float(pv))
	return { "mats": mats, "max_progress": max_prog }


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var hero: Hero = null
	for u in get_tree().get_nodes_in_group("player_unit"):
		if u is Hero:
			hero = u
			break

	# ---- 敌方（野怪）：死亡动画 + 贴图溶解，全程不缩小 ----
	var raider: Pawn = (spawner as Node).call("spawn_raider",
		hero.global_position + Vector3(8, 0, 0), GameDefs.raider_def())
	await get_tree().physics_frame
	await get_tree().physics_frame
	raider.health.apply_damage(99999.0)
	await get_tree().physics_frame
	_check(raider.state_machine.current_state.name == "dead", "raider enters dead state")
	# 死亡动画在播（KayKit Death_A；无模型动画时此项会失败，防映射回归）
	_check(raider.model_rig.has_anim(&"dead"), "raider model has death animation mapped")
	var anim_name: String = raider.model_rig.anim_player.current_animation
	_check(anim_name.contains("Death"), "death animation is playing (%s)" % anim_name)
	await _wait_phys(0.4)
	# 旧表现此处应已缩到 ~0.33；新表现必须保持原尺寸
	_check(raider.scale.is_equal_approx(Vector3.ONE),
		"enemy corpse keeps full scale (no shrink, %.3f)" % raider.scale.x)
	# 动画定格期还没有溶解材质
	var scan_early := _scan_dissolve(raider.model_rig)
	_check(scan_early["mats"].is_empty() or float(scan_early["max_progress"]) < 0.02,
		"dissolve not started during death animation hold")
	await _wait_phys(0.8)   # 越过 ANIM_HOLD_SEC=0.95，进入溶解
	var scan_mid := _scan_dissolve(raider.model_rig)
	_check(not (scan_mid["mats"] as Array).is_empty(),
		"dissolve shader materials applied to model (%d surfaces)" % int((scan_mid["mats"] as Array).size()))
	_check(float(scan_mid["max_progress"]) > 0.02,
		"dissolve progress advancing (%.2f)" % float(scan_mid["max_progress"]))
	_check(raider.scale.is_equal_approx(Vector3.ONE), "scale still untouched while dissolving")
	await _wait_phys(1.0)   # 越过 ANIM_HOLD + DISSOLVE = 1.85s，应已完全消散释放
	_check(not is_instance_valid(raider), "dissolved raider freed after anim + dissolve")

	# ---- 非敌方（士兵）：维持旧缩小淡出 ----
	var soldier: Pawn = (spawner as Node).call("spawn_soldier", GameDefs.settler_warrior_def(),
		hero.global_position + Vector3(4, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	soldier.health.apply_damage(99999.0)
	await _wait_phys(0.3)
	_check(soldier.state_machine.current_state.name == "dead", "soldier enters dead state")
	_check(soldier.scale.x < 0.99 and soldier.scale.x > 0.3,
		"non-enemy keeps legacy shrink fade (%.3f)" % soldier.scale.x)
	var scan_soldier := _scan_dissolve(soldier.model_rig)
	_check((scan_soldier["mats"] as Array).is_empty(), "non-enemy does not dissolve")
	await _wait_phys(0.6)
	_check(not is_instance_valid(soldier), "non-enemy freed by legacy shrink timer")

	print("DEATH DISSOLVE TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
