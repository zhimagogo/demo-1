class_name DragonBreathState
extends PawnState
## ============================================================================
## 巨龙吐息态（技能）：原地朝目标方向喷吐烈焰，持续 duration 秒的锥形持续伤害。
##
## v29 重做（旧版：白色大方块）。旧实现用「无贴图的 0.34m QuadMesh + 加法混合」，
## 近看就是几片边缘生硬的白方块（v26 样张实锤，用户反馈「龙的效果很奇怪」）。
## 现在分四层，全部吃 Kenney CC0 贴图（缺图自动回退程序化软光斑）：
##   ① 主火舌 BreathFlame  —— flame 贴图、加法、白热→橙→暗红渐变、锥角 = 伤害锥
##   ② 白热芯 BreathCore   —— 更窄更快更亮（口部最亮的喷射芯）
##   ③ 余烟 BreathSmoke    —— smoke 贴图、alpha 混合、远端飘散（空气感，不只发光）
##   ④ 飞火星 BreathEmbers —— spark 贴图、带重力下坠（火星被甩出去落地的读感）
## 起手转身（WINDUP_SEC）：大体重单位不瞬移——先用限速转身对准目标，再锁向喷吐；
## 喷吐方向在起手结束时锁定（目标起手方位），喷吐期间不转向（经典吐息手感）。
##
## 伤害口径不变：每 tick_interval 一跳，锥形（顶点 = 龙嘴、half_arc 半角、range 长）
## 内全部敌人吃 breath_damage；几何口径与 DragonPet.enemies_in_breath_cone 完全一致。
## ============================================================================

const FIRE_COLOR := Color(1.0, 0.45, 0.12)
const WINDUP_SEC: float = 0.28          # 起手转身（对准目标后才开始喷）
const WINDUP_ALIGN_DEG: float = 12.0    # 转到这个夹角内即认为对上（可提前开喷）

var _dir: Vector3 = Vector3.FORWARD
var _t: float = 0.0
var _tick_left: float = 0.0
var _firing: bool = false               # 是否已进入喷吐段（起手转身结束后置 true）
var _layers: Array[GPUParticles3D] = []
var _light: OmniLight3D = null          # v30：嘴部火焰灯（照亮周围，随帧抖动）


func enter(msg: Dictionary) -> void:
	var pet := pawn as DragonPet
	if pet == null or pet.dragon_def == null:
		state_machine.transition_to("dragon_follow", {})
		return
	var t: Node = msg.get("target", null)
	pawn.combat_target = t          # 喷吐期间仍算「交战中」（FightState.exit 会先清空，这里接管）
	_dir = _dir_to(t)
	pawn.velocity = Vector3.ZERO
	pawn.look_at_target(_dir)      # 限速转身（DragonPet 覆写）——起手段
	pawn.play_anim(&"fight")
	_t = 0.0
	_firing = false
	_tick_left = WINDUP_SEC
	AudioManager.play_sfx(&"whirlwind", pawn.global_position)


func physics_update(delta: float) -> void:
	var pet := pawn as DragonPet
	if pet == null or pet.dragon_def == null:
		return
	# 全程站定（保留重力落地由 move_and_slide 的既有速度处理；龙贴地站立）
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()

	if not _firing:
		# ---- 起手：对准目标（限速转），对上或超时即锁向开喷 ----
		_t += delta
		var t: Node = pet.hero_target()
		var want := _dir_to(t)
		if want.length_squared() > 0.001:
			_dir = want
			pawn.look_at_target(want)
		if _t >= WINDUP_SEC or pet.facing_error_deg(_dir) <= WINDUP_ALIGN_DEG:
			# 锁向：优先用「此刻目标方位」，目标失效则用最后已知方向，再退自身朝向
			if want.length_squared() > 0.001:
				_dir = want
			if _dir.length_squared() <= 0.001:
				_dir = pawn.facing_dir()
			_firing = true
			_t = 0.0
			_tick_left = 0.35            # 首跳稍等火舌铺开
			_build_flame(pet)
			_ensure_light(pet)
			VFXManager.spawn_effect(&"muzzle_flash", pawn.mouth_position(), 0.0,
				{"color": FIRE_COLOR, "throttle_key": pawn.get_instance_id(), "throttle_time": 0.2})
			VFXManager.spawn_effect(&"cast_glow", pawn.mouth_position(), 0.0,
				{"color": FIRE_COLOR, "throttle_key": pawn.get_instance_id(), "throttle_time": 0.2})
		return

	# ---- 喷吐段：站定锁向，逐跳结算 ----
	_t += delta
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = pet.dragon_def.breath_tick_interval
		_tick(pet)
	# v30：嘴部火焰灯随时抖（火焰的本质就是不稳定的；照亮周围 = 酷炫一档的关键）
	if _light != null:
		_light.light_energy = randf_range(2.4, 4.0)

	if _t >= pet.dragon_def.breath_duration:
		pet._breath_cd_left = pet.dragon_def.breath_cooldown
		var still = pet.hero_target()
		if still != null:
			state_machine.transition_to("dragon_fight", {"target": still})
		else:
			state_machine.transition_to("dragon_follow", {})
		return


func exit() -> void:
	for n in _layers:
		if is_instance_valid(n):
			n.queue_free()
	_layers.clear()
	if _light != null and is_instance_valid(_light):
		_light.queue_free()
	_light = null
	_firing = false


## 是否已进入喷吐段（测试 / UI 查询；起手段返回 false）。
func is_firing() -> bool:
	return _firing


## 目标 → 自身的水平方向（无效 / 重叠时返回零向量）。
func _dir_to(t: Node) -> Vector3:
	if t == null or not is_instance_valid(t) or not (t is Node3D):
		return Vector3.ZERO
	var to: Vector3 = (t as Node3D).global_position - pawn.global_position
	to.y = 0.0
	return to.normalized() if to.length_squared() > 0.001 else Vector3.ZERO


## 单跳结算：锥形内敌人吃伤害 + 命中火星（逐跳反馈，节流）。
func _tick(pet: DragonPet) -> void:
	for e in pet.enemies_in_breath_cone(_dir):
		if not is_instance_valid(e):
			continue
		var victim := e as Node3D
		var h: HealthComponent = victim.get_node_or_null("HealthComponent")
		if h != null and not h.is_dead():
			h.apply_damage(pet.dragon_def.breath_damage, pawn)
			VFXManager.spawn_hit_impact(victim.global_position + Vector3(0.0, 0.9, 0.0),
				FIRE_COLOR, &"hit_spark", victim.get_instance_id())


# ---- 视觉：四层火舌 ----

## 嘴部锥形火舌：四层粒子全部从嘴部沿本地 -Z（= 龙的面朝方向）喷出，锥角与伤害判定一致。
func _build_flame(pet: DragonPet) -> void:
	var d := pet.dragon_def
	var mouth := pet.mouth_local()
	var half := d.breath_half_arc_deg
	# ① 火舌主体：**alpha 混合**（不是加法）——additive 在明亮草地上会被「加白」成一片惨白
	#    （v29 实测：整条火舌读成白色小纸片）；不透明橙红火体在任何背景下都是「火」。
	#    v30：贴图换成卡通 cel 火舌（toon_flame，tools/make_toon_fire_textures.gd 生成），
	#    并加 ±55° 翻滚角——每片火舌各自乱滚，卡通火焰「活」的关键。
	_layers.append(_make_layer("BreathFlame", 300, mouth, {
		"lifetime": d.breath_range / 8.0 + 0.12,
		"spread": half * 1.1, "flatness": 0.72,
		"vel_min": 7.5, "vel_max": 11.5,
		"gravity": Vector3(0.0, 0.35, 0.0),
		"damping": 0.85,
		"size": 0.80, "scale_min": 0.75, "scale_max": 1.75,
		"texture": &"flame_toon", "additive": false, "angle": 55.0,
		"ramp": [[0.0, Color(1.0, 0.96, 0.72, 0.0)], [0.06, Color(1.0, 0.90, 0.48, 1.0)],
			[0.34, Color(1.0, 0.56, 0.13, 0.96)], [0.70, Color(0.86, 0.21, 0.04, 0.62)],
			[1.0, Color(0.38, 0.07, 0.02, 0.0)]],
	}))
	# ② 白热芯：窄、快、亮——口部最亮的喷射芯（「火是从嘴里喷出来的」读感），加法混合
	_layers.append(_make_layer("BreathCore", 110, mouth, {
		"lifetime": d.breath_range / 14.0 + 0.08,
		"spread": half * 0.5, "flatness": 0.72,
		"vel_min": 12.0, "vel_max": 16.0,
		"gravity": Vector3(0.0, 0.6, 0.0),
		"damping": 0.6,
		"size": 0.50, "scale_min": 0.7, "scale_max": 1.45,
		"texture": &"fire", "additive": true,
		"ramp": [[0.0, Color(1.0, 1.0, 0.96, 0.0)], [0.10, Color(1.0, 0.99, 0.88, 0.92)],
			[0.50, Color(1.0, 0.78, 0.36, 0.5)], [1.0, Color(1.0, 0.42, 0.12, 0.0)]],
	}))
	# ③ 余烟：alpha 混合——远端飘散，火舌之外有空气感（v30 换卡通烟团贴图 + 翻滚）
	_layers.append(_make_layer("BreathSmoke", 50, mouth, {
		"lifetime": d.breath_range / 5.0 + 0.3,
		"spread": half * 1.2, "flatness": 0.6,
		"vel_min": 3.5, "vel_max": 6.5,
		"gravity": Vector3(0.0, 1.5, 0.0),
		"damping": 0.5,
		"size": 1.3, "scale_min": 1.0, "scale_max": 2.2,
		"texture": &"puff_toon", "additive": false, "angle": 45.0,
		"ramp": [[0.0, Color(0.42, 0.34, 0.30, 0.0)], [0.22, Color(0.34, 0.28, 0.25, 0.28)],
			[1.0, Color(0.20, 0.18, 0.17, 0.0)]],
	}))
	# ④ 飞火星：带重力下坠（被甩出去落地的小火星）
	_layers.append(_make_layer("BreathEmbers", 50, mouth, {
		"lifetime": d.breath_range / 11.0 + 0.5,
		"spread": half * 0.9, "flatness": 0.7,
		"vel_min": 8.0, "vel_max": 13.0,
		"gravity": Vector3(0.0, -7.0, 0.0),
		"damping": 0.5,
		"size": 0.20, "scale_min": 0.5, "scale_max": 1.1,
		"texture": &"spark", "additive": true,
		"ramp": [[0.0, Color(1.0, 0.90, 0.52, 0.0)], [0.15, Color(1.0, 0.72, 0.26, 1.0)],
			[1.0, Color(0.78, 0.20, 0.05, 0.0)]],
	}))


## 单层发射器：贴图 + 渐变 + 锥形喷射（本地 -Z 为龙的面朝方向）。
func _make_layer(layer_name: String, amount: int, mouth: Vector3, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = layer_name
	p.amount = amount
	p.lifetime = float(cfg["lifetime"])
	p.one_shot = false
	p.local_coords = true                   # 跟随龙头（站定喷吐，方向锁定）
	p.fixed_fps = 30
	p.position = mouth
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.26
	mat.direction = Vector3(0.0, 0.0, -1.0)  # 本地 -Z = 龙的面朝方向
	mat.spread = float(cfg["spread"])
	# 压扁喷射锥：伤害判定是**水平扇形**（XZ 口径），视觉也必须是扁的——
	# 圆椎会把近半粒子甩到上方，看起来像「一串火苗飘在半空」而不是「一道火舌」。
	mat.flatness = float(cfg.get("flatness", 0.7))
	mat.initial_velocity_min = float(cfg["vel_min"])
	mat.initial_velocity_max = float(cfg["vel_max"])
	mat.gravity = cfg["gravity"]
	mat.damping_min = float(cfg["damping"]) * 0.8
	mat.damping_max = float(cfg["damping"]) * 1.25
	mat.scale_min = float(cfg["scale_min"])
	mat.scale_max = float(cfg["scale_max"])
	# v30：贴图翻滚角（cartoon 火舌各自乱滚；余烬等发光小粒默认 0 不翻）
	var jitter := float(cfg.get("angle", 0.0))
	mat.angle_min = -deg_to_rad(jitter)
	mat.angle_max = deg_to_rad(jitter)
	mat.color_ramp = _ramp(cfg["ramp"])
	p.process_material = mat
	var mesh := QuadMesh.new()
	mesh.size = Vector2(float(cfg["size"]), float(cfg["size"]))
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if bool(cfg["additive"]) else BaseMaterial3D.BLEND_MODE_MIX
	# v30：BILLBOARD_PARTICLES 让 angle 参数生效（BILLBOARD_ENABLED 是死板正对不翻滚）
	mmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mmat.billboard_keep_scale = true
	mmat.vertex_color_use_as_albedo = true
	mmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mmat.albedo_texture = VFXManager.texture_for_role(cfg["texture"])
	mmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mesh.material = mmat
	p.draw_pass_1 = mesh
	var reach := float(cfg["lifetime"]) * float(cfg["vel_max"]) + 2.0
	p.custom_aabb = AABB(Vector3(-reach, -2.0, -reach), Vector3(reach * 2.0, reach, reach * 2.0))
	p.emitting = true
	pawn.add_child(p)
	return p


## 嘴部火焰灯（v30）：挂在龙身上随嘴走，暖橙光把周围地面 / 单位都照亮——
## 火焰「酷炫一个档次」的最大单项：火不再只是贴在空气里的贴图，而是场景里的光源。
func _ensure_light(pet: DragonPet) -> void:
	if _light != null and is_instance_valid(_light):
		return
	_light = OmniLight3D.new()
	_light.name = "BreathLight"
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 3.0
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = pet.mouth_local()
	pet.add_child(_light)


func _ramp(points: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	# Gradient 默认自带 2 个点：先把它们设成首尾，再加中间点（避免出现 0 与 1 之外的重复）
	grad.set_color(0, points[0][1])
	grad.set_color(1, points[points.size() - 1][1])
	for i in range(1, points.size() - 1):
		grad.add_point(float(points[i][0]), points[i][1])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	return ramp
