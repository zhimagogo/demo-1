extends "res://tools/v38_prologue_probe.gd"
## 序章表现验收：沿用全链路断言，追加真实输入攻击与三种视角、占领过程留档。
var _claim_saved := false

func _process(_delta: float) -> void:
	if _claim_saved or not is_instance_valid(_director):
		return
	if float(_director.get("_hold_time")) > 0.25 and not bool(_director.get("finished")):
		_claim_saved = true
		_save("campaign-claim")


func _snap(png_name: String) -> void:
	if png_name == "v38-prologue-start":
		await _wait_process_frames(230)
		await _save("campaign-prologue")
		await _check_combat_input()
		return
	if png_name == "v38-prologue-result":
		await get_tree().create_timer(0.7, true, false, true).timeout
		await _save("campaign-result")

func _check_combat_input() -> void:
	var hero := _find_hero() as Hero
	var guards: Array = _director.call("raiders")
	if hero == null or guards.is_empty():
		_check(false, "真实战斗探针缺少角色")
		return
	var guard := guards[0] as Raider
	var nav := _world.get_node("NavSystem") as NavSystem
	var controller := _world.get_node("HeroController") as HeroController
	var original := hero.global_position
	hero.global_position = nav.snap_to_walkable(guard.global_position + Vector3(0, 0, 2.1))
	await _wait_process_frames(20)
	# 先观察驻守敌人反击；不会用测试伤害代替真实的攻击组件。
	var hp_before := hero.health.current_hp
	await _wait_process_frames(85)
	_check(hero.health.current_hp < hp_before, "驻守匪徒靠近后会真实攻击主角")
	var enemy_hp := guard.health.current_hp
	# 只暂时固定准心朝向，动作本身通过真实输入管线触发。
	controller.set_physics_process(false)
	hero.aim_dir = (guard.global_position - hero.global_position).normalized()
	hero.look_at_target(hero.aim_dir)
	var press := InputEventAction.new()
	press.action = &"hero_attack"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"hero_attack"
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_process_frames(24)
	_check(guard.health.current_hp < enemy_hp, "攻击输入触发实际挥剑并命中匪徒")
	controller.set_physics_process(true)
	await _save("campaign-combat")
	# 视角切换使用游戏的唯一交接入口，检查相机与鼠标模态同步。
	for mode in [SelectionManager.ViewMode.HERO, SelectionManager.ViewMode.TACTICAL, SelectionManager.ViewMode.TOPDOWN]:
		controller.set_view_mode(mode)
		await _wait_process_frames(4)
		_check(SelectionManager.view_mode == mode and get_viewport().get_camera_3d() != null, "序章视角切换正常：%d" % mode)
	hero.global_position = original
	hero.health.current_hp = hero.health.max_hp
	await _wait_process_frames(4)

func _save(label: String) -> void:
	await _wait_process_frames(8)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://artifacts/%s.png" % label)
	print("saved artifacts/%s.png" % label)
