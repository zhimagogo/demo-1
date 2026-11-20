extends Node
## v33 交付留档工具：四个进阶职业技能特效样张（跳劈 / 陨石术 / 贯穿射击 / 隐身）。
##
## 运行（**只在有界面运行时用**，无头场景不要跑它）：
##   bash tools/godot_locked.sh --path . tools/v33_skill_shot.tscn
##
## 产物（artifacts/）：
##   v33-leap-slam.png       跳劈：蓄力尘土红光 → 滞空拖尾 → 落地砸击 + 圆形冲击波 + 被击飞木桩
##   v33-meteor.png          陨石：吟唱法阵 + 落点预警圈 + 下落火球
##   v33-meteor-impact.png   陨石落地：分层爆炸（火舌团 + 白热芯 + 烟团 + 冲击环 + 余烬 + 特效灯）
##   v33-piercing-shot.png   贯穿射击：大号枪口十字星 + 青白长尾贯穿三个目标
##   v33-stealth.png         隐身：模型进入 stealth_cloak shader（右侧为未隐身对照）
##   v33-stealth-break.png   破隐：冷色碎光炸散 + 隐身解除
##
## 布景约定（同 v19/v28/v30 样张工具）：直接驱动 VFXManager 的 v33 特效时序，
## 不依赖技能 AI 走位的时机——施法者用进阶职业 def（造型与实机一致）+ 冻结的木桩。
## 粒子不做寿命覆盖（one_shot 的 lifetime 同时是发射时长），网格类特效走
## debug_anim_progress 定格；每张图截完立刻清场，避免上一场的余效串进下一张。

const CLOAK_SHADER_PATH := "res://assets/shaders/stealth_cloak.gdshader"
const V33_IDS: Array[StringName] = [
	&"leap_charge", &"leap_trail", &"slam_impact", &"slam_shockwave",
	&"meteor_channel", &"meteor_telegraph", &"meteor_fall", &"meteor_impact",
	&"pierce_muzzle", &"pierce_trail", &"pierce_hit",
	&"stealth_enter", &"stealth_shimmer", &"stealth_break",
]
const FPS := 60.0

var _main: Node
var _world: Node3D
var _spawner: Node
var _hero: Pawn
var _tp: ThirdPersonCamera
var _stage: Array[Node] = []            # 本场搭建的单位（截完即释放）
var _cloak_shader: Shader = null
var _cloak_mats: Dictionary = {}        # MeshInstance3D -> Array[ShaderMaterial]（避免重复 new）


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_world = _main.get_node("WorldRoot") as Node3D
	# 停掉刷怪 / 定居（样张要静态的舞台）
	_world.get_node("WildlifeSpawner").set_process(false)
	var settlement := _world.get_node_or_null("SettlementSystem")
	if settlement != null:
		settlement.set_process(false)
		settlement.set_physics_process(false)
	_spawner = _world.get_node("PawnSpawner")
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day   # 正午顺光
	# 样张只要特效本体：结束新手引导（它会锁操控 + 占 UI 模态）并整层隐藏 HUD
	var tutorial := _world.get_node_or_null("TutorialSystem")
	if tutorial != null:
		tutorial.set_process(false)
		tutorial.call("skip")
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	_cloak_shader = load(CLOAK_SHADER_PATH) as Shader
	if _cloak_shader == null:
		push_warning("v33 样张：隐身 shader 加载失败 " + CLOAK_SHADER_PATH)

	# 主角只当相机载体（隐藏本体，避免挡住构图）
	var controller := _world.get_node("HeroController") as HeroController
	_hero = controller.hero
	_hero.velocity = Vector3.ZERO
	_hero.release_squad()
	_hero.set_party([])
	controller.enter_hero_mode()
	var placeholder := _hero.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if placeholder != null:
		placeholder.visible = false
	if _hero.model_rig != null:
		_hero.model_rig.visible = false
	_tp = _world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	_tp.fov = 42.0          # 收窄视场当长焦：技能特效在画面里足够大

	await _shot_leap_slam()
	await _shot_meteor()
	await _shot_piercing()
	await _shot_stealth()
	_report()
	get_tree().quit()


# ============================================================================
# ① 跳劈：蓄力 → 跃击 → 落地砸击 + 冲击波 + 击飞
# ============================================================================

func _shot_leap_slam() -> void:
	var anchor := Vector3(0.0, 0.0, -26.0)          # 落点（AOE 圆心）
	# 施法者放画面左侧、木桩放右侧：落点圆环不被角色身体挡住
	var caster := _spawn_caster(anchor + Vector3(2.6, 0.0, -3.4), &"settler_berserker")
	var dummy := _spawn_dummy(anchor + Vector3(-1.4, 0.0, 0.9))
	await _settle()
	_face(caster, dummy)
	_freeze(caster); _freeze(dummy)
	await _place_camera(Vector3(0.0, 0.0, anchor.z - 7.0), PI, -0.30, 4.6)

	# 前摇：脚下尘土上扬 + 红色微光（契约：leap_charge 挂自身）
	VFXManager.spawn_effect(&"leap_charge", caster.global_position, 0.0)
	await _wait(0.34)

	# 滞空：attach_trail 挂在施法者身上，抛物线跃向锁定落点（3m 顶点，同契约 leap_height）
	var trail := VFXManager.attach_trail(caster, &"leap_trail")
	var from := caster.global_position
	var land := anchor + Vector3(1.1, 0.0, 0.0)
	var steps := 24
	for i in steps + 1:
		var t := float(i) / float(steps)
		caster.global_position = from.lerp(land, t) + Vector3.UP * (3.0 * sin(PI * t))
		await get_tree().physics_frame
	caster.global_position = land
	if trail != null:
		trail.emitting = false                     # 停发新粒子，已喷出的留在空中成弧

	# 落地：砸击尘土 + 圆形冲击波（面片直径 = AOE 直径 6.8m）
	VFXManager.spawn_effect(&"slam_impact", land + Vector3(0.0, 0.05, 0.0), 0.0)
	VFXManager.spawn_effect(&"slam_shockwave", land + Vector3(0.0, 0.08, 0.0), 0.0)
	# 击飞读感：木桩被抬离地面 + 顺着远离落点的方向推开 + 轻微翻倒
	var away := (dummy.global_position - land).normalized()
	dummy.global_position += away * 1.15 + Vector3.UP * 1.25
	if dummy.model_rig != null:
		dummy.model_rig.rotation.x = deg_to_rad(-22.0)
	await _wait(0.16)
	await _shot("artifacts/v33-leap-slam.png", 0.40)
	await _clear_stage()


# ============================================================================
# ② 陨石术：吟唱法阵 → 落点预警圈 → 下落火球 → 分层爆炸
# ============================================================================

func _shot_meteor() -> void:
	var center := Vector3(0.0, 0.0, -34.0)          # 落点（吟唱开始时锁定）
	# 施法者站画面左侧，落点 / 预警圈留在画面中央
	var caster := _spawn_caster(center + Vector3(4.6, 0.0, -5.2), &"settler_elementalist")
	var d1 := _spawn_dummy(center + Vector3(-2.2, 0.0, 0.8))
	var d2 := _spawn_dummy(center + Vector3(2.2, 0.0, -0.8))
	await _settle()
	_face(caster, d1)
	_freeze(caster); _freeze(d1); _freeze(d2)
	await _place_camera(Vector3(0.0, 0.0, center.z - 12.0), PI, -0.24, 5.5)

	# 吟唱：自身法阵 + 上升火星
	VFXManager.spawn_effect(&"meteor_channel", caster.global_position, 0.0)
	await _wait(0.18)
	# 落点预警圈：半径 4.2m（= 陨石 AOE；opts.radius 按米撑圈）
	VFXManager.spawn_effect(&"meteor_telegraph", center + Vector3(0.0, 0.07, 0.0), 0.0,
		{"radius": 4.2})
	# 下落火球：落点上空 7m 落向 0.9m；定格在将落未落（y≈2.6m）——此时预警圈与火球同框
	var fall := VFXManager.spawn_effect(&"meteor_fall", center + Vector3(0.0, 7.0, 0.0), 0.0) as Node3D
	var steps := 42
	for i in 30:
		var t := float(i + 1) / float(steps)
		if is_instance_valid(fall):
			fall.global_position = center + Vector3.UP * lerpf(7.0, 0.9, t)
		await get_tree().physics_frame
	await _shot("artifacts/v33-meteor.png", 0.50)

	# 落地：分层爆炸（火舌团 + 白热芯 + 烟团 + 橙色冲击环 + 余烬 + 特效灯）
	if is_instance_valid(fall):
		fall.queue_free()
	VFXManager.spawn_effect(&"meteor_impact", center + Vector3(0.0, 0.05, 0.0), 0.0)
	await _wait(0.26)          # 火舌铺开一半再定格（0.14s 太早，爆炸还没散开）
	await _shot("artifacts/v33-meteor-impact.png", 0.42)
	await _clear_stage()


# ============================================================================
# ③ 贯穿射击：枪口十字星 + 青白长尾贯穿三点
# ============================================================================

func _shot_piercing() -> void:
	var shooter := _spawn_caster(Vector3(0.0, 0.0, -40.0), &"settler_sniper")
	var targets: Array[Pawn] = []
	for i in 3:
		targets.append(_spawn_dummy(Vector3(0.0, 0.0, -33.0 + 6.0 * float(i))))   # 7 / 13 / 19m
	await _settle()
	_face(shooter, targets[0])
	for p: Pawn in targets:
		_freeze(p)
	_freeze(shooter)
	# 贯穿是一条直线：正后方看三点会前后遮挡 → 用专用侧视相机拍整条弹道横穿画面
	_hero.global_position = Vector3(0.0, 0.0, -52.0)
	var cam := _place_side_camera(Vector3(-18.0, 3.2, -30.5), Vector3(0.0, 1.1, -30.5))

	# 枪口：大号十字星（网格类 → 给足寿命好定格）
	var yaw := shooter.rotation.y
	var dir := -Vector3(sin(yaw), 0.0, cos(yaw))          # Pawn 逻辑前方 = 本地 -Z
	var muzzle := shooter.global_position + Vector3(0.0, 1.05, 0.0) + dir * 0.6
	VFXManager.spawn_effect(&"pierce_muzzle", muzzle, yaw, {"lifetime": 4.0})

	# 弹体：一个容器节点载着 pierce_trail（attach_trail 挂弹体），沿线飞满 24m
	var shot_node := Node3D.new()
	shot_node.name = "PierceShotProbe"
	VFXManager.add_child(shot_node)
	shot_node.global_position = muzzle
	VFXManager.attach_trail(shot_node, &"pierce_trail")

	# 弹速对齐契约 pierce_speed=26 m/s：飞 20.5m（约 0.79s）刚好越过最后一个目标，
	# 定格时青白长尾仍横在画面里（飞太远会让尾迹整段飘出取景框）
	var far := muzzle + dir * 20.5
	var steps := 47
	var hit_next := 0
	for i in steps + 1:
		var t := float(i) / float(steps)
		shot_node.global_position = muzzle.lerp(far, t)
		if hit_next < targets.size():
			var d_along: float = (targets[hit_next].global_position - muzzle).dot(dir)
			if t * 20.5 >= d_along:
				VFXManager.spawn_effect(&"pierce_hit",
					targets[hit_next].global_position + Vector3(0.0, 1.0, 0.0), 0.0)
				hit_next += 1
		await get_tree().physics_frame
	cam.current = true          # 再确认一次（专用机位只在没有别的相机抢 current 时有效）
	await _shot("artifacts/v33-piercing-shot.png", 0.32)
	shot_node.queue_free()
	await _clear_stage()


# ============================================================================
# ④ 隐身：stealth_cloak shader 幽灵态 + 启动环 + 持续微光 + 破隐
# ============================================================================

func _shot_stealth() -> void:
	# 复用第一场的空地（此时已清场）：右侧一只不隐身的同职业当对照
	var spot := Vector3(0.0, 0.0, -26.0)
	var hidden := _spawn_caster(spot + Vector3(-1.7, 0.0, -1.0), &"settler_slayer")
	var control := _spawn_caster(spot + Vector3(2.3, 0.0, -1.4), &"settler_slayer")
	await _settle()
	_face(hidden, control)
	_face(control, hidden)
	_freeze(hidden); _freeze(control)
	await _place_camera(Vector3(0.0, 0.0, spot.z - 5.0), PI, -0.16, 3.4)

	# 启动：冷色环 + 淡出微粒；模型 cloak 0 → 1 渐入隐身态
	VFXManager.spawn_effect(&"stealth_enter", hidden.global_position + Vector3(0.0, 0.05, 0.0), 0.0)
	_apply_cloak(hidden, 0.0)
	for i in 14:
		_apply_cloak(hidden, float(i + 1) / 14.0)
		await get_tree().physics_frame
	# 持续微光（TRAIL 型挂隐身者身上）
	VFXManager.attach_trail(hidden, &"stealth_shimmer")
	await _wait(0.40)
	await _shot("artifacts/v33-stealth.png", 0.55)

	# 破隐：冷色碎光炸散 + cloak 1 → 0 退出
	VFXManager.spawn_effect(&"stealth_break", hidden.global_position + Vector3(0.0, 1.0, 0.0), 0.0)
	for i in 10:
		_apply_cloak(hidden, 1.0 - float(i + 1) / 10.0)
		await get_tree().physics_frame
	await _wait(0.10)
	await _shot("artifacts/v33-stealth-break.png", 0.26)
	await _clear_stage()


# ============================================================================
# 隐身 shader：逐 surface 换 stealth_cloak（跳过 Outline_* 描边副本）
# 说明：正式实装由 PawnModelRig.set_stealth 负责（含 shader 缺失兜底）；
# 本工具自带一份等价实现，好在 Pawn 侧接入前就能验证 shader 本体。
# ============================================================================

func _apply_cloak(pawn: Node, amount: float) -> void:
	if pawn == null or not is_instance_valid(pawn) or _cloak_shader == null:
		return
	var rig: Variant = pawn.get("model_rig")
	var root: Node = (rig as Node) if rig is Node else pawn
	var meshes: Array = []
	_collect_meshes(root, meshes)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mats: Array = _cloak_mats.get(mi, [])
		if mats.is_empty():
			for i in mi.mesh.get_surface_count():
				var sm := ShaderMaterial.new()
				sm.shader = _cloak_shader
				var base_color := Color.WHITE
				var src := mi.get_active_material(i)
				if src is BaseMaterial3D:
					var b := src as BaseMaterial3D
					base_color = b.albedo_color
					if b.albedo_texture != null:
						sm.set_shader_parameter(&"albedo_texture", b.albedo_texture)
						sm.set_shader_parameter(&"use_texture", true)
				sm.set_shader_parameter(&"albedo_color", base_color)
				sm.set_shader_parameter(&"cloak", amount)
				sm.set_shader_parameter(&"rim_color", Vector3(0.58, 0.88, 1.0))
				sm.set_shader_parameter(&"alpha_scale", 1.0)
				mi.set_surface_override_material(i, sm)
				mats.append(sm)
			_cloak_mats[mi] = mats
		else:
			for sm_v in mats:
				(sm_v as ShaderMaterial).set_shader_parameter(&"cloak", amount)


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and not String(n.name).begins_with("Outline"):
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


# ============================================================================
# 布景 / 截图基础设施
# ============================================================================

func _caster_def(adv_id: StringName) -> PawnDef:
	var d: PawnDef = GameDefs.settler_advanced_def(adv_id)
	if d != null:
		return d
	push_warning("v33 样张：进阶职业 def 缺失（%s），回落到基础职业" % String(adv_id))
	match adv_id:
		&"settler_berserker": return GameDefs.settler_warrior_def()
		&"settler_elementalist": return GameDefs.settler_mage_def()
		&"settler_sniper": return GameDefs.settler_archer_def()
		&"settler_slayer": return GameDefs.settler_assassin_def()
	return GameDefs.settler_warrior_def()


func _spawn_caster(at: Vector3, adv_id: StringName) -> Pawn:
	var p: Pawn = _spawner.call("spawn_soldier", _caster_def(adv_id), at)
	_stage.append(p)
	return p


func _spawn_dummy(at: Vector3) -> Pawn:
	var d: PawnDef = GameDefs.raider_def()
	d.max_hp = 6000.0
	d.attack_damage = 0.0
	d.flee_hp_ratio = 0.0
	var p: Pawn = _spawner.call("spawn_raider", at, d)
	_stage.append(p)
	return p


## 相机就位：写 yaw 后 transform 下一渲染帧才应用（已知坑）——跨物理帧 + 渲染帧等链路收敛。
func _place_camera(at: Vector3, yaw: float, pitch: float, dist: float) -> void:
	_hero.global_position = at
	_hero.velocity = Vector3.ZERO
	_tp.yaw = yaw
	_tp.pitch = pitch
	_tp.target_distance = dist
	_tp.current = true          # 专用侧视机位用过之后要把第三人称机位抢回来
	await _settle(4)
	for _i in 4:
		await get_tree().process_frame


## 专用侧视机位（只有「要横向读一条线」的样张用；HeroController 仅在切换视角时改 camera.current，
## 拍完把第三人称机位 current 抢回来即可）。
func _place_side_camera(eye: Vector3, look_at_pos: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "V33ShotCamera"
	cam.fov = 42.0
	_world.add_child(cam)
	cam.global_position = eye
	cam.look_at(look_at_pos, Vector3.UP)
	cam.current = true
	return cam


func _settle(frames: int = 8) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	var frames := maxi(int(round(seconds * FPS)), 1)
	for _i in frames:
		await get_tree().physics_frame


## 定格截图：网格类特效用 debug_anim_progress 定格在 hold（< 0 = 不定格）。
## HUD 已在 _ready 整层隐藏，画面上只有世界本体（样张的看点是特效）。
func _shot(path: String, hold: float = -1.0) -> void:
	if hold >= 0.0:
		VFXManager.debug_anim_progress = hold
	TimeManager.set_speed(0.0)
	for _i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://" + path)
	print("saved ", path, " err=", err)
	TimeManager.set_speed(1.0)
	if hold >= 0.0:
		VFXManager.debug_anim_progress = -1.0


func _clear_stage() -> void:
	for n in _stage:
		if is_instance_valid(n):
			n.queue_free()
	_stage.clear()
	_cloak_mats.clear()
	await _settle(4)
	await _wait(1.2)          # 等上一场余效自然结束，避免串场


func _face(p: Node3D, target: Node3D) -> void:
	var dir: Vector3 = target.global_position - p.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		p.look_at_target(dir.normalized())


## 冻结单位：本体与状态机都停（与 CombatVfxTest 同款），只留特效继续播。
func _freeze(pawn: Node) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	pawn.set_physics_process(false)
	var sm: Variant = pawn.get("state_machine")
	if sm is Node:
		(sm as Node).set_physics_process(false)


func _report() -> void:
	var defs: Dictionary = VFXManager.get("_defs")
	var composites: Dictionary = VFXManager.get("_composites")
	var missing: Array[String] = []
	var stats: Array[String] = []
	for id in V33_IDS:
		if not defs.has(id):
			missing.append(String(id))
		stats.append("%s=%d" % [String(id), int(VFXManager.stat_spawned_by_id.get(id, 0))])
	print("v33 特效 id 缺失: ", missing)
	print("v33 复合特效数: ", composites.size())
	print("v33 生成计数: ", ", ".join(stats))
	print("v33 shot done")
