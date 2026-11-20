extends Node
## 动画 ↔ 特效同步回归（v26）：godot --headless --path . tests/AnimVfxSyncTest.tscn
## 覆盖六组契约：
##  1) 职业动作匹配（per-def anim_map：双手斧 2H / 双匕 Dualwield / 法杖施法 / 手弩射击）
##  2) 特效档案类型匹配（野兽不吃剑光弧 / 法杖不吃枪口星 / 手弩保留枪口星）
##  3) 单次动画重播（同名 play 必须从帧 0 重来——Godot 4 默认不重播）
##  4) 循环动画让位 + 播完回落（攻击/受击期间 idle 不抢帧；播完自动回循环动画）
##  5) 攻速匹配（挥击动画按 def.attack_anim_speed 倍速播放）
##  6) 实机链路（游侠出手即上射击动作 / 小兵受击插播 Hit_A 后回落 idle）

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


func _rig(path: String, anim_map: Dictionary = {}) -> PawnModelRig:
	var rig := PawnModelRig.new()
	add_child(rig)
	rig.setup(path, 1.0, 0.0, &"", &"", anim_map, false)
	return rig


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var spawner := world.get_node("PawnSpawner")

	# ================= 1) 职业动作匹配（真实 GLB + per-def anim_map） =================
	var warrior_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb",
		GameDefs.settler_warrior_def().anim_map)
	_check(warrior_rig.resolved_anim(&"fight") == "2H_Melee_Attack_Slice",
		"warrior swings the 2H axe anim (got %s)" % warrior_rig.resolved_anim(&"fight"))
	_check(warrior_rig.resolved_anim(&"cast") == "Cheer",
		"warrior rage cast roars with Cheer (got %s)" % warrior_rig.resolved_anim(&"cast"))

	var mage_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_colonist_mage.glb",
		GameDefs.settler_mage_def().anim_map)
	_check(mage_rig.resolved_anim(&"shoot") == "Spellcast_Shoot",
		"mage bolt uses Spellcast_Shoot (got %s)" % mage_rig.resolved_anim(&"shoot"))
	_check(mage_rig.resolved_anim(&"cast") == "Spellcast_Raise",
		"mage blizzard raises the staff (got %s)" % mage_rig.resolved_anim(&"cast"))

	var assassin_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb",
		GameDefs.settler_assassin_def().anim_map)
	_check(assassin_rig.resolved_anim(&"fight") == "Dualwield_Melee_Attack_Slice",
		"assassin uses the dualwield slice (got %s)" % assassin_rig.resolved_anim(&"fight"))

	var archer_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb",
		GameDefs.settler_archer_def().anim_map)
	_check(archer_rig.resolved_anim(&"shoot") == "1H_Ranged_Shoot",
		"archer crossbow uses 1H_Ranged_Shoot (got %s)" % archer_rig.resolved_anim(&"shoot"))

	# 全局候选兜底：无覆盖的殖民者 shoot 走 1H_Ranged_Shoot；
	# GreenBlob（Quaternius 组）fight 兜底 Bite_Front、受击兜底资源拼写 HitRecieve
	var plain_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb")
	_check(plain_rig.resolved_anim(&"shoot") == "1H_Ranged_Shoot",
		"global shoot candidates resolve for plain colonist")
	var blob_rig := _rig("res://assets/_PLACEHOLDER/monsters/GreenBlob.gltf")
	_check(blob_rig.resolved_anim(&"fight") == "Bite_Front",
		"GreenBlob fight falls back to Bite_Front (got %s)" % blob_rig.resolved_anim(&"fight"))
	_check(blob_rig.resolved_anim(&"hit") == "HitRecieve",
		"GreenBlob hit react resolves asset's HitRecieve spelling (got %s)" % blob_rig.resolved_anim(&"hit"))

	# ================= 2) 特效档案类型匹配 =================
	var raider_profile: Dictionary = VFXManager.attack_profile(GameDefs.raider_def())
	_check(raider_profile["arc"] == &"", "raider punches carry no human sword arc")
	_check(VFXManager.attack_profile(GameDefs.raider_boss_def())["arc"] == &"",
		"boss (Ghost headbutt) carries no sword arc either")
	var mage_profile: Dictionary = VFXManager.attack_profile(GameDefs.settler_mage_def())
	_check(mage_profile["muzzle"] == &"", "mage staff bolt drops the firearm muzzle star")
	_check(mage_profile["cast"] == &"cast_glow", "mage keeps the arcane cast glow")
	var archer_profile: Dictionary = VFXManager.attack_profile(GameDefs.settler_archer_def())
	_check(archer_profile["muzzle"] == &"muzzle_flash", "crossbow keeps its muzzle flash")
	var warrior_profile: Dictionary = VFXManager.attack_profile(GameDefs.settler_warrior_def())
	_check(warrior_profile["arc"] == &"axe_arc", "warrior keeps the axe arc")
	_check(VFXManager.attack_profile(null).has("cast_dist"), "profile exposes cast_dist/cast_height keys")

	# ================= 3) 单次动画重播 =================
	var hero_rig := _rig("res://assets/_PLACEHOLDER/characters/placeholder_hero.glb")
	hero_rig.play(&"fight", 0.0)
	for _i in 8:
		await get_tree().physics_frame
	var ap: AnimationPlayer = hero_rig.anim_player
	var pos_before := ap.current_animation_position
	_check(pos_before > 0.05, "attack anim is progressing (%.2fs)" % pos_before)
	hero_rig.play(&"fight", 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(ap.current_animation_position < pos_before * 0.5,
		"re-requesting the same attack anim restarts it (%.2f -> %.2f)" % [pos_before, ap.current_animation_position])

	# ================= 4) 循环让位 + 播完回落 =================
	hero_rig.play(&"fight", 0.0)
	await get_tree().physics_frame
	hero_rig.play(&"idle")
	await get_tree().physics_frame
	_check(ap.current_animation.contains("Slice_Horizontal"),
		"loop anim request defers while the attack is playing (current=%s)" % ap.current_animation)
	await get_tree().create_timer(1.4).timeout
	_check(ap.current_animation.contains("Idle") or hero_rig.is_playing_loop(),
		"after the attack finishes the rig falls back to a loop anim (current=%s)" % ap.current_animation)

	# ================= 5) 攻速匹配 =================
	assassin_rig.attack_anim_speed = 1.9
	assassin_rig.play(&"fight", 0.0)
	_check(absf(assassin_rig.anim_player.speed_scale - 1.9) < 0.001,
		"swing anim plays at the def attack speed (%.2f)" % assassin_rig.anim_player.speed_scale)
	assassin_rig.play(&"hit", 0.0)
	_check(absf(assassin_rig.anim_player.speed_scale - 1.0) < 0.001,
		"non-swing anims play at normal speed")
	# 清理探针 rig
	for child in get_children():
		if child is PawnModelRig:
			child.queue_free()
	await get_tree().physics_frame

	# ================= 6) 实机链路：游侠出手上射击动作 =================
	var archer: Pawn = spawner.call("spawn_soldier", GameDefs.settler_archer_def(), Vector3(-46.0, 0.0, 42.0))
	archer.is_auto_fighter = true
	archer.town_life_active = false   # v41 城内生活：城外出生的兵默认回家，不会接战练靶
	var target: Raider = spawner.call("spawn_raider", Vector3(-40.0, 0.0, 42.0), GameDefs.raider_def())
	_freeze(target)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var shoot_anim := archer.model_rig.resolved_anim(&"shoot")
	var saw_shoot := false
	for _i in 30:   # 最多等 3s：索敌 → fight → 档1 站定第一箭
		await get_tree().physics_frame
		if archer.model_rig.anim_player != null \
				and archer.model_rig.anim_player.current_animation.contains(shoot_anim):
			saw_shoot = true
			break
	_check(saw_shoot, "archer plays the shoot anim on its real first shot (%s)" % shoot_anim)
	_check(int(VFXManager.stat_spawned_by_id.get(&"muzzle_flash", 0)) >= 1,
		"the same shot spawns the muzzle flash (anim and vfx on the same frame)")

	# ---- 小兵受击插播 Hit_A，播完回落 idle ----
	var warrior: Pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(-56.0, 0.0, 42.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit_anim := warrior.model_rig.resolved_anim(&"hit")
	warrior.health.apply_damage(5.0, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(warrior.model_rig.anim_player.current_animation.contains(hit_anim),
		"taking a hit plays the hit react anim (current=%s)" % warrior.model_rig.anim_player.current_animation)
	await get_tree().create_timer(1.0).timeout
	_check(warrior.model_rig.is_playing_loop(),
		"hit react falls back to a loop anim afterwards (current=%s)" % warrior.model_rig.anim_player.current_animation)

	# ================= 7) v27 特效丰富度：暴击 / 升级 / 死亡 / 新特效注册 =================
	VFXManager.reset_stats()
	# 近战暴击 → 金色星芒（与「暴击！」飘字同帧）
	warrior.crit_stat = 1.0
	var crit_target: Pawn = spawner.call("spawn_raider", warrior.global_position + Vector3(0.0, 0.0, 2.4), GameDefs.raider_def())
	_freeze(crit_target)
	crit_target.global_position = warrior.global_position + Vector3(0.0, 0.0, 2.4)
	warrior.attacker._cooldown_left = 0.0
	await get_tree().physics_frame
	warrior.attacker.try_attack(crit_target)
	await get_tree().physics_frame
	_check(int(VFXManager.stat_spawned_by_id.get(&"crit_burst", 0)) >= 1,
		"forced melee crit spawns the golden crit burst")
	warrior.crit_stat = 0.0
	# 升级 → 金环 + 金屑
	warrior.gain_xp(warrior.xp_to_next())
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(int(VFXManager.stat_spawned_by_id.get(&"levelup_ring", 0)) >= 1
		and int(VFXManager.stat_spawned_by_id.get(&"levelup_spark", 0)) >= 1,
		"leveling up spawns the golden ring and rising sparks")
	# 敌方死亡 → 魂魄离体（冻住的单位状态机不走，用一只未冻结的木桩）
	var dying: Pawn = spawner.call("spawn_raider", Vector3(-66.0, 0.0, 42.0), GameDefs.raider_def())
	await get_tree().physics_frame
	dying.health.apply_damage(9999.0, null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(int(VFXManager.stat_spawned_by_id.get(&"death_wisp", 0)) >= 1,
		"enemy death releases rising soul wisps")
	# 新特效 id 全部注册可生成（heal_mote / build_dust / coin_sparkle / sprint_dust）
	var probe := warrior.global_position + Vector3(0.0, 1.0, 0.0)
	var richness_ok := true
	for eid: StringName in [&"heal_mote", &"build_dust", &"coin_sparkle", &"sprint_dust"]:
		if VFXManager.spawn_effect(eid, probe, 0.0) == null:
			richness_ok = false
			push_error("FAIL: v27 effect %s is not registered" % eid)
	_check(richness_ok, "all v27 richness effect ids are registered and spawnable")

	# ================= 8) v28 战斗打击感：定向喷溅 / 白闪 / 重击震波 =================
	VFXManager.reset_stats()
	# 带攻击朝向的命中反馈 → 定向火星锥 + 白闪
	VFXManager.spawn_hit_impact(warrior.global_position + Vector3(0.0, 1.0, 0.0),
		Color(1.0, 0.8, 0.4), &"hit_spark", "v28_probe", 0.0)
	await get_tree().physics_frame
	_check(int(VFXManager.stat_spawned_by_id.get(&"hit_spark_cone", 0)) >= 1,
		"attacker yaw spawns the directional hit spray cone")
	_check(int(VFXManager.stat_spawned_by_id.get(&"impact_flash", 0)) >= 1,
		"hit impact spawns the white impact flash")
	# 主角第 3 段重击 → 脚下落地震波（重击带 0.12s 前摇，轮询等到 active 帧再断言）
	var hero: Hero = (world.get_node("HeroController") as HeroController).hero
	if hero != null:
		VFXManager.reset_stats()
		hero._start_combo(3)
		var shock_seen := false
		for _i in 45:
			await get_tree().physics_frame
			if int(VFXManager.stat_spawned_by_id.get(&"heavy_shock", 0)) >= 1:
				shock_seen = true
				break
		_check(shock_seen, "hero heavy combo step slams a ground shockwave")
	else:
		_check(false, "hero exists for the heavy shockwave check")

	archer.queue_free()
	warrior.queue_free()
	target.queue_free()
	crit_target.queue_free()
	dying.queue_free()
	_finish()


func _freeze(p: Node) -> void:
	p.set_physics_process(false)
	p.set_process(false)


func _finish() -> void:
	print("ANIM VFX SYNC TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
