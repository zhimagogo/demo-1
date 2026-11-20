extends Node3D
## ============================================================================
## v29 龙系统实机样张（第三人称主角视角，带 HUD）：
##   godot --path . tools/v29_dragon_shot.tscn
## 产出 artifacts/：
##   ① v29-dragon-follow.png    行军中的跟随站位（龙在侧翼，不挡镜头）
##   ② v29-dragon-breath.png    烈焰吐息（四层火舌实拍）
##   ③ v29-dragon-fireball.png  火球出膛（嘴部高度 + 拖尾）
##   ④ v29-dragon-marks.png     队伍绿标近景（描边贴合 + 体型适配脚圈）
## 同时打印客观量测：龙相对主角的「侧向 / 后方」偏移、龙在屏幕上的
## 偏心距（准星 = 屏幕中心，龙越偏心越不挡路）、嘴部高度。
## ============================================================================

var _main: Node
var _pet: DragonPet
var _hero: Hero
var _cam: ThirdPersonCamera


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	var world := _main.get_node("WorldRoot") as Node3D
	for n in ["WildlifeSpawner", "SettlementSystem"]:
		var node := world.get_node_or_null(n)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	await _frames(2)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	_hero = _find_hero()
	_cam = world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	if _cam != null:
		_cam.target_distance = 6.4

	# ---- 驯龙（真实链路：建龙园 → 花金币解锁 → 自动出战）----
	ResourceManager.add(GameDefs.GOLD, 2000)
	var build := world.get_node("BuildSystem") as BuildSystem
	var garden_def: BuildingDef
	for d in GameDefs.building_defs():
		if d.id == &"dragon_garden":
			garden_def = d
	build.enter_build_mode(garden_def)
	# 3×3 龙园要落在主城内且不压已有建筑：挨个候选点试到成功为止
	for cand in [Vector3(12.0, 0.0, -12.0), Vector3(14.0, 0.0, -14.0), Vector3(-12.0, 0.0, -12.0),
			Vector3(12.0, 0.0, 12.0), Vector3(-12.0, 0.0, 12.0), Vector3(0.0, 0.0, -16.0)]:
		build.try_place_at(cand)
		if not get_tree().get_nodes_in_group("dragon_garden").is_empty():
			break
	build.exit_build_mode()
	await _frames(3)
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	var unlocked: bool = ds.try_unlock(&"dragon_obsidian")
	await _frames(4)
	_pet = ds.current_pet()
	print("gardens=", get_tree().get_nodes_in_group("dragon_garden").size(), " unlocked=", unlocked, " gardens=", get_tree().get_nodes_in_group("dragon_garden").size(),
		" pet=", _pet, " gold=", ResourceManager.get_amount(GameDefs.GOLD))
	if _pet == null:
		print("V29 DRAGON SHOT: 布景失败（龙未出战），中止")
		get_tree().quit(1)
		return
	_hero.global_position = Vector3(20.0, 0.0, -2.0)
	await _frames(10)
	print("hero=", str(_hero.global_position.round()), " pet=", str(_pet.global_position.round()))

	# ---- ① 行军中跟随：按住 W 前冲，相机跟拍（龙必须让开正后背视线走廊）----
	Input.action_press("move_up")
	await _frames(150)                 # 先让龙追到侧翼站位，再抓「行军跟随」
	await _shot("v29-dragon-follow.png")
	for i in 3:
		await _frames(30)
		_report_follow("行军中%d" % (i + 1))
	Input.action_release("move_up")
	await _frames(150)
	_report_follow("站定后")

	# ---- ② 烈焰吐息：正前方三只野怪，强制技能就绪 ----
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	var fwd := _hero.facing_dir()
	var mobs: Array = []
	for i in 3:
		var at: Vector3 = _hero.global_position + fwd * 9.0 + Vector3(1.6 * float(i - 1), 0.0, 0.0)
		mobs.append(spawner.call("spawn_raider", at, GameDefs.raider_def()))
	await _frames(3)
	_hero.note_attack_target(mobs[0])
	_pet._breath_cd_left = 0.0
	# 等进入喷吐段（起手转身 0.28s + 火舌铺开）
	var fired := false
	for i in 120:
		await get_tree().physics_frame
		var st = _pet.state_machine.current_state
		if st.name == "dragon_breath" and st.has_method("is_firing") and st.call("is_firing") and i > 26:
			fired = true
			break
	print("breath fired=", fired, " state=", _pet.state_machine.current_state.name)
	await _shot("v29-dragon-breath.png")

	# ---- ③ 火球出膛（吐息结束后普攻）----
	_pet._breath_cd_left = 30.0      # 压住技能，逼出火球
	_pet._fire_cd_left = 0.0
	_hero.note_attack_target(mobs[0])
	var shot := false
	for i in 240:
		await get_tree().physics_frame
		if get_tree().get_nodes_in_group("projectiles").size() > 0:
			shot = true
			await _frames(4)          # 飞出一小段，看拖尾
			break
	print("fireball launched=", shot)
	await _shot("v29-dragon-fireball.png")

	# ---- ④ 队伍绿标近景（主角转身面向龙，平视）----
	for m in mobs:
		if is_instance_valid(m):
			m.queue_free()
	_hero.note_attack_target(null)
	await _frames(20)
	if _cam != null:
		_cam.target_distance = 5.6
	await _frames(40)
	# 抓拍前重算视线（这一步之前龙还在挪位，早算的 yaw 会拍空）
	for i in 6:
		var to_pet: Vector3 = _pet.global_position - _hero.global_position
		to_pet.y = 0.0
		# 偏 38° 的 3/4 机位：正对会让主角身体把龙整个挡住（实测拍空）
		_cam.yaw = atan2(-to_pet.x, -to_pet.z) + deg_to_rad(38.0)
		_cam.pitch = -0.14
		await _frames(6)
	_dump_particles()
	_report_follow("绿标近景")
	await _shot("v29-dragon-marks.png")
	print("ring_outer=", (_pet.get_node("SquadRing").mesh as TorusMesh).outer_radius,
		" mouth_y=%.2f" % (_pet.mouth_position().y - _pet.global_position.y))

	print("V29 DRAGON SHOT: done")
	get_tree().quit()


## 跟随站位量测：龙相对主角的「侧向 / 后方」分量 + 屏幕偏心距（准星在屏幕中心）。
func _report_follow(tag: String = "行军中") -> void:
	if _pet == null or not is_instance_valid(_pet):
		return
	var off: Vector3 = _pet.global_position - _hero.global_position
	off.y = 0.0
	var f := _hero.facing_dir()
	var right := Vector3(-f.z, 0.0, f.x)
	var side := off.dot(right)
	var back := -off.dot(f)
	var cam := get_viewport().get_camera_3d()
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var head: Vector3 = _pet.global_position + Vector3(0.0, 1.6, 0.0)
	var sp := cam.unproject_position(head)
	var d := sp - center
	print("[%s] 距离=%.2fm 侧向=%+.2fm 后方=%+.2fm | 龙屏幕偏心=(%+.0f, %+.0f)px 距准星=%.0fpx" % [
		tag, off.length(), side, back, d.x, d.y, d.length()])
	print("       相机距离=%.1f 相机高度=%.1f 主角屏幕偏移=%.0fpx" % [
		_cam._distance, cam.global_position.y,
		(cam.unproject_position(_hero.global_position + Vector3(0.0, 1.0, 0.0)) - center).length()])


## 打印场上所有粒子发射器（排查「样张里飘着一堆火苗」是哪来的）。
func _dump_particles() -> void:
	print("---- 场上 GPUParticles3D ----")
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GPUParticles3D:
			var p := n as GPUParticles3D
			print("  ", p.get_path(), " emitting=", p.emitting, " amount=", p.amount,
				" pos=", str(p.global_position.round()), " vis=", p.visible)
		for c in n.get_children():
			stack.append(c)


func _find_hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _shot(fname: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/%s" % fname)
	print("saved ", fname)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
