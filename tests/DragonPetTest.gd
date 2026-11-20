extends Node
## ============================================================================
## v26 驯龙系统专项回归：
##   godot --headless --path . tests/DragonPetTest.tscn --log-file /private/tmp/a-dragon.log --fixed-fps 60
##
## 覆盖：
##   0. 数据契约：龙园 3×3 占地全场最大 / 纯金币造价；黑曜龙 def 参数（40° 吐息 / 解锁价 / 模型路径）。
##   A. 龙园建造 + E 交互：准星提示「[E] 驯龙」→ _try_interact 打开 DragonMenu。
##   B. 解锁：无龙园拒绝 / 金币不足拒绝 / 足额扣款解锁并**自动出战**（龙在主角身边生成）。
##   C. 出战实体：DragonPet 入 player_unit + hero_squad 组、不占编队 4 槽、不自动索敌、
##      anim_map 覆盖生效（run → Walk_menacing_loop）、血条高度用 def.hud_head_height。
##   D. 跟随：主角瞬移后龙追上来贴身。
##   E. 玩家打谁龙打谁：note_attack_target → dragon_fight；锥形吐息 + 火球溅射命中判定
##      （扇形内两只受伤、扇形外不受伤）；主角换目标龙同步转火；目标过期回跟随。
##   F. 吐息几何直测：enemies_in_breath_cone 的 40° / 14m 口径。
##   G. 阵亡复苏：宠物死亡 → 复苏倒计时 → 主角身边重生。
##   H. UI：DragonMenu 信号开合；CitizenPanel 巨龙出战区；HeroPanel 龙行；BuildMenu 4 张卡。
##
## 输出保持 ASCII（headless 日志中文会乱码）；命令直接调 API，不依赖真实输入。
## ============================================================================

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
	var world := _main.get_node("WorldRoot") as Node3D
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	# v42：玩家默认俯视角主控（朝向 = 鼠标落点，headless 下鼠标在屏幕角 → 主角朝向乱转）。
	# 本套件的 E 准星交互与巨龙懒跟随站位都假设「屏幕中心准星 + 朝向稳定」，
	# 用脚本接口进第三人称（交互 / 跟随玩法代码与俯视角同一套）。
	var hc_default := world.get_node("HeroController") as HeroController
	hc_default.enter_hero_mode()
	await get_tree().physics_frame
	var hero: Hero = null
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			hero = n
			break
	# 测试期停刷野怪 / 流民并清场：行为必须确定性
	var wildlife := world.get_node_or_null("WildlifeSpawner")
	if wildlife != null:
		wildlife.set_process(false)
	var settlement := world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	await get_tree().physics_frame

	# ================= 0. 数据契约 =================
	var ids: Array = []
	var garden_def: BuildingDef
	var max_other_cells: int = 0
	var gold_only := true
	for d in GameDefs.building_defs():
		ids.append(d.id)
		if d.id == &"dragon_garden":
			garden_def = d
		elif d.footprint.x * d.footprint.y > max_other_cells:
			max_other_cells = d.footprint.x * d.footprint.y
		for rid in d.cost:
			if rid != GameDefs.GOLD:
				gold_only = false
	_check(garden_def != null and garden_def.is_dragon_garden, "dragon garden registered in building defs")
	_check(garden_def != null and garden_def.footprint.x * garden_def.footprint.y > max_other_cells,
		"dragon garden footprint (%s) larger than every other building (max %d cells)" % [
			str(garden_def.footprint) if garden_def != null else "?", max_other_cells])
	_check(gold_only, "all building costs stay gold-only")
	var dragons := GameDefs.dragon_defs()
	var dr: DragonDef = dragons[0] if not dragons.is_empty() else null
	_check(dr != null, "dragon defs table non-empty")
	if dr != null:
		_check(dr.unlock_cost > 0, "dragon has positive unlock cost")
		_check(is_equal_approx(dr.breath_half_arc_deg, 20.0) and is_equal_approx(dr.breath_duration, 2.0),
			"breath = 40 deg cone for 2s (half=%.1f, dur=%.1f)" % [dr.breath_half_arc_deg, dr.breath_duration])
		_check(dr.splash_radius > 0.0 and dr.fireball_damage > dr.splash_damage,
			"fireball direct damage > splash damage (aoe burst profile)")
		_check(ResourceLoader.exists(dr.model_path), "dragon model imported at %s" % dr.model_path)
		_check(not dr.can_level and dr.is_auto_fighter and dr.auto_attack_range > 0.0,
			"pet dragon: no leveling, auto-engages only inside its guard radius (%.0fm)" % dr.auto_attack_range)
	_check(ds != null, "dragon system node present in world tree")

	# ================= A. 龙园建造 + E 交互 =================
	ResourceManager.add(GameDefs.GOLD, 1000)
	var build := world.get_node("BuildSystem") as BuildSystem
	build.enter_build_mode(garden_def)
	build.try_place_at(Vector3(12.0, 0.0, -12.0))
	build.exit_build_mode()
	await get_tree().physics_frame
	var gardens := get_tree().get_nodes_in_group("dragon_garden")
	_check(gardens.size() == 1, "garden placed through actual build system")
	var garden: Building = gardens[0] if not gardens.is_empty() else null
	if garden != null and hero != null:
		_check(garden.footprint == Vector2i(4, 4), "placed garden occupies 4x4 cells (v43: 8x8m)")
		var hc := get_tree().get_first_node_in_group("hero_controller") as HeroController
		var cam := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
		hero.global_position = garden.global_position + Vector3(0.0, 0.0, 5.2)
		await get_tree().physics_frame
		var to_garden := garden.global_position - hero.global_position
		to_garden.y = 0.0
		cam.yaw = atan2(-to_garden.x, -to_garden.z)
		cam.pitch = -0.22
		await get_tree().physics_frame
		var prompt_info := {}
		var sig := func(_t, prompt, _k): prompt_info["prompt"] = prompt
		EventBus.crosshair_target_changed.connect(sig)
		hc._refresh_crosshair_prompt()
		await get_tree().process_frame
		EventBus.crosshair_target_changed.disconnect(sig)
		_check(String(prompt_info.get("prompt", "")).find("[E]") >= 0,
			"crosshair prompts dragon-garden interact (%s)" % String(prompt_info.get("prompt", "")))
		hc._try_interact()
		await get_tree().process_frame
		var hud := _main.get_node_or_null("HUD")
		var menu = hud.get("dragon_menu") if hud != null else null
		_check(menu != null and menu.get("is_open") == true, "E on garden opens DragonMenu")
		if menu != null:
			menu.call("close")

	# ================= B. 解锁（金币门禁 + 自动出战） =================
	if ds != null and dr != null and garden != null:
		ResourceManager.spend(GameDefs.GOLD, ResourceManager.get_amount(GameDefs.GOLD))  # 清零金币
		_check(not ds.try_unlock(dr.id), "unlock refused without gold")
		ResourceManager.add(GameDefs.GOLD, dr.unlock_cost - 1)
		_check(not ds.try_unlock(dr.id), "unlock refused with insufficient gold")
		ResourceManager.add(GameDefs.GOLD, 1)
		_check(ds.try_unlock(dr.id), "unlock succeeds with exact gold")
		_check(ResourceManager.get_amount(GameDefs.GOLD) == 0, "unlock cost deducted (gold now 0)")
		_check(not ds.try_unlock(dr.id), "second unlock refused (already tamed)")
		await get_tree().physics_frame
		# ================= C. 出战实体 =================
		var pet := ds.current_pet()
		_check(pet != null, "unlock auto-deploys the dragon near hero")
		if pet != null:
			_check(pet is DragonPet and pet.dragon_def != null and pet.dragon_def.id == dr.id,
				"deployed pet is DragonPet carrying its def")
			_check(pet.is_in_group("player_unit") and pet.is_in_group("hero_squad"),
				"pet joins player_unit + hero_squad groups")
			_check(hero != null and not hero.party.has(pet) and not hero.squad.has(pet),
				"pet does NOT occupy any of the 4 squad slots")
			# v32：龙有自主攻击，但**只在主角身边的圈内**出手（圈外仍不主动找架打）
			_check(pet.autofight_enabled(), "pet auto-engages inside the hero-centred guard circle")
			_check(pet.follow_leader == hero, "pet bound to hero as follow leader")
			_check(pet.model_rig != null and pet.model_rig.has_model(), "pet loads dragon glb model")
			_check(pet.model_rig != null and pet.model_rig.resolved_anim(&"run") in ["Walk_menacing_loop", "Walk_menacing"],
				"per-def anim_map resolves run -> walk anim (%s)" % (
					pet.model_rig.resolved_anim(&"run") if pet.model_rig != null else "?"))
			_check(pet.health_bar != null and is_equal_approx(pet.health_bar.head_height(), dr.hud_head_height),
				"health bar honors def hud_head_height")

		# ================= D. 跟随 =================
		if hero != null:
			hero.global_position = Vector3(26.0, 0.0, 26.0)
			await get_tree().physics_frame
			var pet2 := ds.current_pet()
			if pet2 != null:
				var followed := false
				for i in 300:
					await get_tree().physics_frame
					if pet2.global_position.distance_to(hero.global_position) < 6.0:
						followed = true
						break
				_check(followed, "pet catches up after hero teleports away")

		# ================= E. 玩家打谁龙打谁（吐息 + 火球溅射 + 转火） =================
		var pet3 := ds.current_pet()
		if hero != null and pet3 != null:
			var d1: Pawn = spawner.call("spawn_raider", Vector3(26.0, 0.0, 16.0), GameDefs.raider_def())
			var d2: Pawn = spawner.call("spawn_raider", Vector3(27.5, 0.0, 16.0), GameDefs.raider_def())
			var d3: Pawn = spawner.call("spawn_raider", Vector3(32.0, 0.0, 16.0), GameDefs.raider_def())
			await get_tree().physics_frame
			hero.note_attack_target(d1)
			var engaged := false
			for i in 90:
				await get_tree().physics_frame
				if pet3.state_machine.current_state.name in ["dragon_fight", "dragon_breath"] \
						and pet3.combat_target == d1:
					engaged = true
					break
			_check(engaged, "pet engages the target hero is attacking (state=%s)" % (
				"ok" if engaged else pet3.state_machine.current_state.name))
			# 吐息 2s + 火球：扇形内 d1/d2 受伤；扇形外 d3（远侧向）不应被波及
			var damaged := false
			for i in 300:
				await get_tree().physics_frame
				if d1.health.current_hp < d1.health.max_hp and d2.health.current_hp < d2.health.max_hp:
					damaged = true
					break
			_check(damaged, "cone + splash damage reaches primary and nearby secondary")
			_check(d3.health.current_hp >= d3.health.max_hp - 0.5,
				"far-offside enemy outside cone/splash stays untouched (%.0f/%.0f)" % [
					d3.health.current_hp, d3.health.max_hp])
			# 转火：主角换目标，龙同步切换
			var d4: Pawn = spawner.call("spawn_raider", Vector3(26.0, 0.0, 8.0), GameDefs.raider_def())
			await get_tree().physics_frame
			hero.note_attack_target(d4)
			var switched := false
			# 吐息锁向最长 2s：转火判定要等它喷完这一轮
			for i in 360:
				await get_tree().physics_frame
				if pet3.combat_target == d4:
					switched = true
					break
			_check(switched, "pet switches target when hero switches")
			# 目标保鲜过期（主角停手）→ 回跟随态
			# v32：龙现在会自主守备，先把圈内残敌清掉才能验「停手即回跟随」
			for v in [d1, d2, d3, d4]:
				if is_instance_valid(v):
					v.health.apply_damage(99999.0)
			await get_tree().physics_frame
			hero.note_attack_target(d4)
			hero._attack_target_left = 0.05
			var back := false
			for i in 90:
				await get_tree().physics_frame
				if pet3.state_machine.current_state.name == "dragon_follow":
					back = true
					break
			_check(back, "pet returns to follow when hero stops attacking (state=%s)" % (
				"ok" if back else pet3.state_machine.current_state.name))
			for v in [d1, d2, d3, d4]:
				if is_instance_valid(v):
					v.queue_free()
			await get_tree().physics_frame

		# ================= F. 吐息几何直测（40° / 14m） =================
		# 木桩出生会被 NavSystem 吸附挪位 → 出生后直接钉到精确坐标，几何判定才确定。
		var pet4 := ds.current_pet()
		if pet4 != null:
			hero.global_position = Vector3(-24.0, 0.0, -27.0)
			pet4.global_position = Vector3(-24.0, 0.0, -24.0)
			await get_tree().physics_frame
			var near_a: Pawn = spawner.call("spawn_raider", Vector3(-24.0, 0.0, -14.0), GameDefs.raider_def())
			var near_b: Pawn = spawner.call("spawn_raider", Vector3(-26.4, 0.0, -16.0), GameDefs.raider_def())
			var wide: Pawn = spawner.call("spawn_raider", Vector3(-30.0, 0.0, -20.0), GameDefs.raider_def())
			var behind: Pawn = spawner.call("spawn_raider", Vector3(-24.0, 0.0, -30.0), GameDefs.raider_def())
			near_a.global_position = Vector3(-24.0, 0.0, -14.0)   # 正前 10m
			near_b.global_position = Vector3(-26.4, 0.0, -16.0)  # 前方 8m 偏 2.4m（≈16.7° < 20°）
			wide.global_position = Vector3(-30.0, 0.0, -20.0)    # 前方 4m 偏 6m（≈56° 出锥）
			behind.global_position = Vector3(-24.0, 0.0, -30.0)  # 身后（180°）
			await get_tree().physics_frame
			var cone: Array = pet4.enemies_in_breath_cone(Vector3(0.0, 0.0, 1.0))
			_check(cone.has(near_a) and cone.has(near_b), "cone contains straight-ahead and 17deg-off enemies")
			_check(not cone.has(wide) and not cone.has(behind),
				"cone excludes off-angle and behind enemies (40deg / 14m profile)")
			# 吐息状态机：站定 2s → CD 写入（CD 自写入起即倒计时，断言区间而非精确值）
			pet4._breath_cd_left = 0.0
			pet4.state_machine.transition_to("dragon_breath", {"target": near_a})
			await get_tree().physics_frame
			var stood_still := pet4.velocity.length() < 0.01
			var breath_looped := false
			for i in 180:
				await get_tree().physics_frame
				if pet4.state_machine.current_state.name != "dragon_breath":
					breath_looped = true
					break
			_check(breath_looped, "breath state ends after its duration")
			_check(pet4._breath_cd_left > dr.breath_cooldown - 1.5 and pet4._breath_cd_left <= dr.breath_cooldown,
				"breath cooldown written after cast (%.1f)" % pet4._breath_cd_left)
			_check(stood_still, "dragon stands still while breathing")
			for v in [near_a, near_b, wide, behind]:
				if is_instance_valid(v):
					v.queue_free()
			await get_tree().physics_frame

		# ================= G. 阵亡复苏 =================
		var pet5 := ds.current_pet()
		if pet5 != null:
			pet5.health.apply_damage(99999.0)
			await get_tree().physics_frame
			await get_tree().physics_frame
			_check(ds.deployed_id == dr.id and ds.respawn_left > 0.0,
				"pet death schedules respawn countdown (%.0fs)" % ds.respawn_left)
			ds.respawn_left = 0.4
			var revived := false
			for i in 180:
				await get_tree().physics_frame
				if ds.current_pet() != null and ds.current_pet() != pet5:
					revived = true
					break
			_check(revived, "pet revives beside hero after countdown")
			_check(ds.current_pet() != null and ds.current_pet().health.current_hp == ds.current_pet().health.max_hp,
				"revived pet returns at full hp")

		# ================= H. UI =================
		var hud2 := _main.get_node_or_null("HUD")
		if hud2 != null:
			EventBus.dragon_menu_requested.emit(garden)
			await get_tree().process_frame
			var menu2 = hud2.get("dragon_menu")
			_check(menu2 != null and menu2.get("is_open") == true, "dragon_menu opens via signal")
			menu2.call("close")
			# 市民管理：巨龙出战区存在且含龙行
			var cp = hud2.get("party_panel")
			if cp != null:
				cp.call("open")
				await get_tree().process_frame
				var dbox: VBoxContainer = cp.get("_dragon_box")
				_check(dbox != null and dbox.get_child_count() >= 2, "citizen panel dragon section lists dragons")
				cp.call("close")
			# 主角面板：出战龙行
			var hp_panel = hud2.get("hero_panel")
			var pet6 := ds.current_pet()
			_check(pet6 != null and hp_panel != null and hp_panel.get("_rows").has(pet6.get_instance_id()),
				"hero panel squad rows include deployed dragon")
			# 建造菜单：4 张卡（木墙/房屋/酒馆/龙园）
			var bm = hud2.get("build_menu")
			_check(bm != null and bm.get("_cards").size() == GameDefs.building_defs().size(),
				"build menu card count matches building defs (%d)" % GameDefs.building_defs().size())

	# ================= I. v29 龙系统优化 =================
	# 四个真机问题各留一条硬断言（都是「改回去必红」的客观量）：
	# ① 描边副本缺 Skin → 巨大绿色幽灵；② 跟随站位压镜头走廊；
	# ③ 火球出膛不在嘴部（旧版头顶 2.1m 空中）；④ 大体重单位朝向瞬移。
	await _check_v29(world, spawner, hero)
	await _check_v32(world, spawner, hero)
	await _finish()


func _check_v29(world: Node, spawner: Node, hero: Hero) -> void:
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	var dr := GameDefs.dragon_def(&"dragon_obsidian")
	if ds == null or dr == null:
		_check(false, "v29: dragon system / def available")
		return
	# 重新出战（H 节前面的阵亡复苏后宠物仍在场）
	var pet: DragonPet = ds.current_pet()
	if pet == null:
		ds.deploy(dr.id)
		await get_tree().physics_frame
		pet = ds.current_pet()
	if pet == null:
		_check(false, "v29: pet deployed for follow/aim checks")
		return

	# ---- ① 描边（队伍绿标 / 瞄准红标同一管线）必须带蒙皮 Skin ----
	var rig := pet.get_node_or_null("ModelRig") as PawnModelRig
	pet.set_squad_mark(true)
	await get_tree().physics_frame
	var outlines: Array = rig.get("_outline_meshes")
	_check(outlines.size() >= 1, "v29: squad mark builds outline hull copies (%d)" % outlines.size())
	var body := _first_body_mesh(rig)
	var dup: MeshInstance3D = outlines[0] as MeshInstance3D if not outlines.is_empty() else null
	_check(body != null and dup != null and body.skin != null and dup.skin == body.skin,
		"v29: outline copy carries the glTF Skin (inverseBindMatrices) — else giant ghost")
	# 描边副本与本体同骨架（蒙皮绑定一致性）
	_check(dup != null and body != null and dup.skeleton == body.skeleton,
		"v29: outline copy keeps the same skeleton binding")

	# ---- ② 跟随站位：主角站定后，龙必须在**侧向**（不在相机视线走廊正后方） ----
	if hero != null:
		hero.global_position = Vector3(-30.0, 0.0, 30.0)
		await get_tree().physics_frame
		# 等龙「真正就位」：距离进 6m 且连续 12 帧速度接近零（槽位冻结后站住）
		var calm := 0
		for i in 600:
			await get_tree().physics_frame
			if pet.global_position.distance_to(hero.global_position) < 6.0 \
					and Vector2(pet.velocity.x, pet.velocity.z).length() < 0.25:
				calm += 1
				if calm >= 12:
					break
			else:
				calm = 0
		var off: Vector3 = pet.global_position - hero.global_position
		off.y = 0.0
		var f := hero.facing_dir()
		var right := Vector3(-f.z, 0.0, f.x)
		var side := off.dot(right)
		var back := -off.dot(f)
		_check(absf(side) > 2.0, "v29: dragon parks on the hero's flank (side=%.2fm)" % side)
		_check(absf(side) > absf(back),
			"v29: flank offset dominates the camera corridor (side=%.2f back=%.2f)" % [side, back])
		# 站定 2s 不许漂移（大体重单位贴住休整位）
		var p0 := pet.global_position
		for i in 120:
			await get_tree().physics_frame
		_check(p0.distance_to(pet.global_position) < 0.35,
			"v29: parked dragon does not drift (2s drift=%.3fm)" % p0.distance_to(pet.global_position))

	# ---- ③ 火球：出膛点 = 嘴部（不是头顶空中），且在朝向对准前不出膛 ----
	var mouth_dy: float = pet.mouth_position().y - pet.global_position.y
	var mouth_expect: float = DragonPet.MOUTH_HEIGHT_REF * (dr.model_scale / DragonPet.MOUTH_SCALE_REF)
	_check(absf(mouth_dy - mouth_expect) < 0.05,
		"v29: mouth height tracks model scale (%.2fm vs expected %.2fm)" % [mouth_dy, mouth_expect])
	pet.rotation.y = 0.0                      # 面朝 -Z
	var mob: Pawn = spawner.call("spawn_raider", pet.global_position + Vector3(0.0, 0.0, -9.0),
		GameDefs.raider_def())
	mob.global_position = pet.global_position + Vector3(0.0, 0.0, -9.0)
	await get_tree().physics_frame
	pet._fire_cd_left = 0.0
	var projs_before := _projectiles().size()
	pet.spawn_fireball(mob, Vector3(0.0, 0.0, -1.0))
	await get_tree().physics_frame
	var shots := _projectiles()
	_check(shots.size() == projs_before + 1, "v29: fireball spawns a projectile (%d -> %d)" % [
		projs_before, shots.size()])
	var fb: Node3D = null
	for p in shots:
		if is_instance_valid(p) and (p as Node3D).global_position.distance_to(pet.global_position) < 6.0:
			fb = p as Node3D
	var expected: Vector3 = pet.global_position + Vector3(0.0, 0.0, -1.0) * pet.mouth_forward() \
		+ Vector3(0.0, pet.mouth_height(), 0.0)
	_check(fb != null and fb.global_position.distance_to(expected) < 0.6,
		"v29: fireball leaves from the mouth (%s vs %s)" % [
			str(fb.global_position.round()) if fb != null else "?", str(expected.round())])
	_check(fb != null and absf(fb.global_position.y - (pet.global_position.y + pet.mouth_height())) < 0.3,
		"v29: fireball flies at mouth height, not over the target's head")
	# 朝向限速：180° 反向命令一帧只转一小步（不瞬移）
	pet.rotation.y = 0.0
	pet.look_at_target(Vector3(0.0, 0.0, 1.0))     # 要求掉头 180°
	await get_tree().physics_frame
	var turned := absf(rad_to_deg(pet.rotation.y))
	_check(turned > 1.0 and turned < 60.0,
		"v29: dragon turns at a limited rate (one frame = %.1f deg, not 180)" % turned)
	# 出招对准门槛：朝向与目标夹角大时不出膛
	pet.rotation.y = PI                          # 背对目标
	pet._fire_cd_left = 0.0
	var dist := pet.global_position.distance_to(mob.global_position)
	_check(pet.facing_error_deg(mob.global_position - pet.global_position) > 90.0,
		"v29: facing-error metric reports the misalignment (%.0f deg, dist=%.1fm)" % [
			pet.facing_error_deg(mob.global_position - pet.global_position), dist])

	# ---- ④ 队伍脚圈按体型放大（0.42 的小圈会被龙身整个盖住） ----
	var ring := pet.get_node_or_null("SquadRing") as MeshInstance3D
	_check(ring != null and (ring.mesh as TorusMesh).outer_radius >= 1.0,
		"v29: squad ring scales with body size (outer=%.2fm)" % (
			(ring.mesh as TorusMesh).outer_radius if ring != null else -1.0))
	# 非 Pawn 替身 leader 不得刷错误（hero_target 的防御分支）
	var dummy := Node3D.new()
	add_child(dummy)
	pet.follow_leader = dummy
	var safe: bool = pet.hero_target() == null
	pet.follow_leader = hero
	_check(safe, "v29: hero_target tolerates a non-Pawn leader (no invalid property spam)")
	dummy.queue_free()
	if is_instance_valid(mob):
		mob.queue_free()
	await get_tree().physics_frame


## 场上飞行中的弹体（"projectiles" 分组挂的是 Main 的容器节点，弹体是它的子节点）。
func _projectiles() -> Array:
	var container := get_tree().get_first_node_in_group("projectiles")
	return container.get_children() if container != null else []


func _first_body_mesh(rig: Node) -> MeshInstance3D:
	var stack: Array = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and not String(n.name).begins_with("Outline"):
			return n as MeshInstance3D
		for c in n.get_children():
			stack.append(c)
	return null


## ================= J. v32 体型翻倍 + 懒跟随 + 自主攻击 =================
func _check_v32(world: Node, spawner: Node, hero: Hero) -> void:
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	var dr := GameDefs.dragon_def(&"dragon_obsidian")
	var pet: DragonPet = ds.current_pet() if ds != null else null
	if dr == null or pet == null or hero == null:
		_check(false, "v32: dragon def + deployed pet available")
		return

	# ---- ① 体型翻倍 + 半径盒同步 ----
	_check(is_equal_approx(dr.model_scale, 1.10), "v32: dragon model scale doubled (%.2f)" % dr.model_scale)
	_check(is_equal_approx(dr.body_scale, 2.0) and is_equal_approx(pet.body_scale(), 2.0),
		"v32: body box scale doubled (%.1fx)" % pet.body_scale())
	var cap := pet.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(cap != null and cap.shape is CapsuleShape3D and is_equal_approx((cap.shape as CapsuleShape3D).radius, 0.8),
		"v32: collision capsule scales with body (r=%.2f, was 0.4)" % (
			(cap.shape as CapsuleShape3D).radius if cap != null and cap.shape is CapsuleShape3D else -1.0))
	_check(cap != null and is_equal_approx(cap.position.y, 1.6),
		"v32: collision capsule centre lifts with height (y=%.2f)" % (cap.position.y if cap != null else -1.0))
	var pick_radius := -1.0
	if pet.selectable != null:
		for c in pet.selectable.get_children():
			var sc := c as CollisionShape3D
			if sc != null and sc.shape is CylinderShape3D:
				pick_radius = (sc.shape as CylinderShape3D).radius
	_check(is_equal_approx(pick_radius, 1.2),
		"v32: pick cylinder scales with body (r=%.2f, was 0.6)" % pick_radius)
	_check(is_equal_approx(pet.nav_agent.radius, 0.8), "v32: nav radius scales (%.2f)" % pet.nav_agent.radius)
	_check(is_equal_approx(pet.mouth_height(), 2.7) and is_equal_approx(pet.mouth_forward(), 2.7),
		"v32: mouth anchor scales with the model (%.2fm)" % pet.mouth_height())
	var ring := pet.get_node_or_null("SquadRing") as MeshInstance3D
	_check(ring != null and is_equal_approx((ring.mesh as TorusMesh).outer_radius, 2.5),
		"v32: squad ring scales (%.2fm)" % ((ring.mesh as TorusMesh).outer_radius if ring != null else -1.0))

	# ---- ② 懒跟随：缓冲圈内不动 / 出圈追到跟随半径再停 ----
	# 先清场（前面几节会留下残敌，自主攻击会打断跟随测量）
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	hero.note_attack_target(null)
	hero._attack_target_left = 0.0
	hero.global_position = Vector3(30.0, 0.0, 30.0)
	await get_tree().physics_frame
	pet.global_position = hero.global_position + Vector3(5.0, 0.0, 0.0)
	await get_tree().physics_frame
	await _wait_calm(pet, 90)
	var parked := pet.global_position
	# 主角在缓冲半径内挪 8m：龙必须原地不动
	hero.global_position = parked + Vector3(8.0, 0.0, 0.0)
	await _frames(90)
	var drift := parked.distance_to(pet.global_position)
	_check(drift < 0.6, "v32: hero moving inside the buffer leaves the dragon parked (drift=%.2fm)" % drift)
	# 主角拉出缓冲半径（15m 以外）：龙追到「跟随半径」（侧翼槽位）附近再停
	hero.global_position = pet.global_position + Vector3(26.0, 0.0, 0.0)
	await get_tree().physics_frame
	var arrived := false
	var closest := INF
	for i in 600:
		await get_tree().physics_frame
		var d: float = pet.global_position.distance_to(hero.global_position)
		closest = minf(closest, d)
		if d < 6.5 and Vector2(pet.velocity.x, pet.velocity.z).length() < 0.25:
			arrived = true
			break
	_check(arrived, "v32: hero leaving the buffer makes the dragon catch up to the follow radius (closest=%.2fm)" % closest)
	# 到位后主角再挪 8m（仍在缓冲内）：又不动了
	await _wait_calm(pet, 90)
	var parked2 := pet.global_position
	hero.global_position = hero.global_position + Vector3(0.0, 0.0, 8.0)
	await _frames(90)
	_check(parked2.distance_to(pet.global_position) < 0.6,
		"v32: dragon re-enters the buffer state after arriving (drift=%.2fm)" % parked2.distance_to(pet.global_position))

	# ---- ③ 自主攻击：主角身边圈内的怪自己打，圈外不管 ----
	hero.global_position = Vector3(-20.0, 0.0, 34.0)
	await get_tree().physics_frame
	pet.global_position = hero.global_position + Vector3(4.0, 0.0, 0.0)
	await _frames(30)
	var near_mob: Pawn = spawner.call("spawn_raider", hero.global_position + Vector3(0.0, 0.0, -8.0),
		GameDefs.raider_def())
	near_mob.global_position = hero.global_position + Vector3(0.0, 0.0, -8.0)
	await get_tree().physics_frame
	hero.note_attack_target(null)
	hero._attack_target_left = 0.0
	var engaged := false
	for i in 120:
		await get_tree().physics_frame
		if pet.combat_target == near_mob:
			engaged = true
			break
	_check(engaged, "v32: pet auto-engages an enemy inside the hero circle (state=%s)" % pet.state_machine.current_state.name)
	# 圈外（主角 20m 外）的怪：不主动去打
	var far_mob: Pawn = spawner.call("spawn_raider", hero.global_position + Vector3(20.0, 0.0, 0.0),
		GameDefs.raider_def())
	far_mob.global_position = hero.global_position + Vector3(20.0, 0.0, 0.0)
	if is_instance_valid(near_mob):
		near_mob.health.apply_damage(99999.0)
	await _frames(60)
	var left_combat := false
	for i in 240:
		await get_tree().physics_frame
		if pet.state_machine.current_state.name == "dragon_follow" and pet.combat_target == null:
			left_combat = true
			break
	_check(left_combat and pet.pick_target() != far_mob,
		"v32: enemy outside the hero circle is ignored (target=%s state=%s)" % [
			str(pet.combat_target), pet.state_machine.current_state.name])
	_check(far_mob.health.current_hp >= far_mob.health.max_hp - 0.5, "v32: out-of-circle enemy stays untouched")

	# ---- ④ 三级优先级：玩家的目标 > 打玩家的 > 自己最近的 ----
	var mob_a: Pawn = spawner.call("spawn_raider", hero.global_position + Vector3(0.0, 0.0, -6.0),
		GameDefs.raider_def())
	var mob_b: Pawn = spawner.call("spawn_raider", hero.global_position + Vector3(6.0, 0.0, 0.0),
		GameDefs.raider_def())
	var mob_c: Pawn = spawner.call("spawn_raider", hero.global_position + Vector3(0.0, 0.0, 3.0),
		GameDefs.raider_def())
	for m in [mob_a, mob_b, mob_c]:
		await get_tree().physics_frame
	# 三只全部**冻结**（本体 + 状态机）→ 站位与 combat_target 不会被各自的怪 AI 改写，
	# 优先级判定才是确定性的（不冻的话 3m 的 C 也会去打主角，等于两只「威胁」）。
	for m in [mob_a, mob_b, mob_c]:
		m.set_physics_process(false)
		m.state_machine.set_physics_process(false)
	mob_a.global_position = hero.global_position + Vector3(0.0, 0.0, -6.0)   # 主角指定
	mob_b.global_position = hero.global_position + Vector3(6.0, 0.0, 0.0)    # 正在打主角
	mob_c.global_position = hero.global_position + Vector3(0.0, 0.0, 3.0)    # 离龙最近（干扰项）
	# 三只的「是否在打主角」显式钉死（冻结前它们各自的 AI 可能已经 aggro 过主角）：
	#   A = 主角指定目标（不算威胁）｜B = 正在打主角（威胁）｜C = 圈内最近（不算威胁）
	mob_a.combat_target = null
	mob_c.combat_target = null
	mob_b.state_machine.transition_to("fight", {"target": hero})
	mob_b.state_machine.set_physics_process(false)
	await get_tree().physics_frame
	_check(mob_b.combat_target == hero and mob_a.combat_target == null and mob_c.combat_target == null,
		"v32: test setup — only mob_b is attacking the hero (b=%s a=%s c=%s)" % [
			str(mob_b.combat_target != null), str(mob_a.combat_target != null), str(mob_c.combat_target != null)])
	hero.note_attack_target(mob_a)
	_check(pet.pick_target() == mob_a, "v32 priority 1: hero's own target wins")
	# 主角停手 → 打主角的 B 胜过离龙更近的 C
	hero.note_attack_target(null)
	hero._attack_target_left = 0.0
	pet._auto_cache = null                     # 清缓存，避免上一轮的自主目标占位
	_check(pet.pick_target() == mob_b, "v32 priority 2: enemy attacking the hero beats the nearest one")
	# B 不再打主角 → 落到最近的 C
	mob_b.combat_target = null
	pet._auto_cache = null
	_check(pet.pick_target() == mob_c, "v32 priority 3: falls back to the nearest enemy in the circle")
	for m in [mob_a, mob_b, mob_c, far_mob]:
		if is_instance_valid(m):
			m.queue_free()
	await get_tree().physics_frame


## 等龙站定（速度收敛若干帧），最多 max_frames 帧。
func _wait_calm(pet: DragonPet, max_frames: int) -> void:
	var calm := 0
	for i in max_frames:
		await get_tree().physics_frame
		if Vector2(pet.velocity.x, pet.velocity.z).length() < 0.2:
			calm += 1
			if calm >= 10:
				return
		else:
			calm = 0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _finish() -> void:
	var ds := get_tree().get_first_node_in_group("dragon_system") as DragonSystem
	if ds != null:
		ds.undeploy()
	print("DRAGON PET: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
