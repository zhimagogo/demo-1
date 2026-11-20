class_name RegionAmbience
extends Node3D
## ============================================================================
## v40.2 区域氛围粒子层（纯表现，不参与碰撞 / 寻路 / 玩法）
## ============================================================================
## 每个主题区域一盏「氛围发射器」：
##   北境霜语瀑布 —— 飘雪（全天）
##   东北星落矿坑 —— 紫色浮尘（全天，夜里更明显）
##   东境风吟麦海 —— 金色光尘 / 花粉（白天）
##   南境烬誓战场 —— 余烬上升（全天，夜里更亮）
##   西境雾隐密林 —— 萤火（夜晚）
##   西南盐风沼地 —— 低空雾气（全天）
##   王城         —— 城堡烟囱薄烟（全天）
##
## 设计原则：
## 1) 全部用 GPUParticles3D + 现有 VFX 贴图（assets/vfx/textures/），不新增素材；
## 2) 总预算 ≤ 8 个发射器 / ≤ 1200 粒子（本文件 7 个发射器，名义粒子约 900）；
## 3) 昼夜门控只在 _process 里切换 emitting / amount_ratio，不重建粒子；
## 4) 只做视觉：不挂碰撞体、不写 GridSystem.terrain_cells、不参与任何 Check。
## WorldScenery._build_region_ambience() 用 load() + ResourceLoader.exists 挂载本脚本。
## ============================================================================

const TEX_DIR := "res://assets/vfx/textures/"
const WIND := Vector3(0.55, 0.0, 0.32)     # 与草地风摆大致同向的微风
const PSE_BOX := 0
const PSE_SPHERE := 1

## 每项：{node, base_ratio, day_only, night_only}
var _emitters: Array[Dictionary] = []
var _accum: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 77123
	for region in WorldRegions.all():
		if region["kind"] == WorldRegions.KIND_CITY:
			continue
		_build_region(region)
	_build_city_smoke()
	_refresh_day_night(true)
	set_process(not _emitters.is_empty())
	print("[RegionAmbience] 氛围粒子就绪：%d 个发射器 / 名义粒子 %d。" % [_emitters.size(), _nominal_particles()])


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	_refresh_day_night(false)


func _nominal_particles() -> int:
	var total := 0
	for entry in _emitters:
		var p := entry["node"] as GPUParticles3D
		total += p.amount
	return total


func _refresh_day_night(force: bool) -> void:
	var night := TimeManager.is_night()
	for entry in _emitters:
		var p := entry["node"] as GPUParticles3D
		if not is_instance_valid(p):
			continue
		var day_only: bool = entry["day_only"]
		var night_only: bool = entry["night_only"]
		var should_emit := true
		if day_only and night:
			should_emit = false
		if night_only and not night:
			should_emit = false
		if p.emitting != should_emit or force:
			p.emitting = should_emit
		# 夜里余烬/浮尘更密；白天雪/雾保持原密度
		var target_ratio: float = float(entry["base_ratio"])
		if not day_only and not night_only:
			target_ratio = target_ratio * (1.18 if night else 1.0)
		p.amount_ratio = clampf(target_ratio, 0.0, 1.0)


func _build_region(region: Dictionary) -> void:
	var kind: StringName = region["kind"]
	var landmark: Vector2 = region["landmark"]
	var accent: Color = region["accent"]
	match kind:
		WorldRegions.KIND_FROST:
			# 飘雪：白色小圆点缓缓落下，覆盖整个区域（相机附近也能看到）
			_add_emitter("Snow", landmark, 24.0, "", Color(0.92, 0.96, 1.0, 0.72),
				260, 9.5, 0.035, 0.085, Vector3(0.14, -0.58, 0.08), 0.24, false, PSE_BOX,
				Vector3(24, 5, 24), Vector3(0, 6.0, 0), false, false, 0.95)
		WorldRegions.KIND_MINE:
			# 紫色浮尘：自坑底缓缓上浮，夜里更明显
			_add_emitter("MineDust", landmark, 18.0, "magic_03", Color(0.72, 0.55, 1.0, 0.7),
				60, 6.0, 0.08, 0.20, Vector3(0, 0.12, 0), 0.25, true, PSE_BOX,
				Vector3(16, 2.2, 16), Vector3(0, 3.0, 0), false, false, 0.75)
		WorldRegions.KIND_WHEAT:
			# 金色光尘 / 花粉：白天随风缓慢飘移
			_add_emitter("Pollen", landmark, 22.0, "star_04", Color(1.0, 0.86, 0.45, 0.7),
				140, 7.0, 0.06, 0.16, WIND * 0.35, 0.25, true, PSE_BOX,
				Vector3(22, 2.4, 22), Vector3(0, 1.6, 0), false, true, 1.0)
		WorldRegions.KIND_BATTLE:
			# 余烬上升：橙红火星，夜里更密
			_add_emitter("Embers", landmark, 18.0, "star_06", Color(1.0, 0.52, 0.25, 0.95),
				70, 2.2, 0.03, 0.08, Vector3(0, 0.42, 0), 0.30, true, PSE_BOX,
				Vector3(6.5, 0.6, 6.5), Vector3(0, 1.6, 0), false, false, 0.9)
		WorldRegions.KIND_FOREST:
			# 萤火：夜里在树冠间缓慢游荡的绿色光点
			_add_emitter("Fireflies", landmark, 14.0, "light_01", Color(0.62, 1.0, 0.55, 0.95),
				130, 7.0, 0.14, 0.26, Vector3(0, 0.05, 0), 0.28, true, PSE_BOX,
				Vector3(12, 2.2, 12), Vector3(0, 2.2, 0), false, true, 1.0)
		WorldRegions.KIND_SWAMP:
			# 低空雾气：灰绿烟团贴着地面缓慢流动
			_add_emitter("Mist", landmark, 22.0, "smoke_04", Color(0.62, 0.72, 0.62, 0.16),
				42, 13.0, 2.2, 5.0, Vector3(0, 0.10, 0), 0.20, false, PSE_BOX,
				Vector3(22, 0.8, 22), Vector3(0, 0.9, 0), false, false, 0.9)


## 程序化柔光点（32×32 径向渐变）：雪粒用它，避免 VFX 包里的环形贴图被看成「白色圆环」。
static var _soft_dot_cache: ImageTexture = null

static func _soft_dot_texture() -> ImageTexture:
	if _soft_dot_cache != null:
		return _soft_dot_cache
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := float(x) - float(size) * 0.5 + 0.5
			var dy := float(y) - float(size) * 0.5 + 0.5
			var d := Vector2(dx, dy).length() / (float(size) * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_soft_dot_cache = ImageTexture.create_from_image(img)
	return _soft_dot_cache


## 王城烟囱薄烟：给主城一点「有人在住」的活气。
func _build_city_smoke() -> void:
	_add_emitter("CitySmoke", Vector2(0.0, 0.0), 9.0, "smoke_04", Color(0.72, 0.74, 0.72, 0.15),
		22, 9.0, 1.2, 2.6, Vector3(0, 0.22, 0), 0.25, false, PSE_SPHERE,
		Vector3(4.0, 1.0, 4.0), Vector3(0, 7.0, 0), false, false, 1.0)


## 通用发射器。additive=true 用加法混合（光尘/火星/萤火），false 用普通 alpha（雪/雾）。
func _add_emitter(node_name: String, center: Vector2, radius: float, tex_name: String, tint: Color,
		amount: int, lifetime: float, size_min: float, size_max: float, gravity: Vector3,
		velocity: float, additive: bool, shape: int, extents: Vector3, origin: Vector3,
		day_only: bool, night_only: bool, base_ratio: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = 3.0
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.interpolate = false
	particles.emitting = true
	particles.position = Vector3(center.x, origin.y, center.y)
	particles.visibility_aabb = AABB(
		Vector3(-radius - 4.0, -6.0, -radius - 4.0),
		Vector3(radius * 2.0 + 8.0, 22.0, radius * 2.0 + 8.0))
	# ---- 粒子网格：billboard 面片 ----
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	if tex_name.is_empty():
		material.albedo_texture = _soft_dot_texture()
	else:
		material.albedo_texture = load(TEX_DIR + tex_name + ".png") as Texture2D
	material.albedo_color = Color(1, 1, 1, 1)
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.disable_receive_shadows = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	particles.draw_pass_1 = quad
	# ---- 粒子行为 ----
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX if shape == PSE_BOX \
		else ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	if shape == PSE_BOX:
		process.emission_box_extents = extents
	else:
		process.emission_sphere_radius = extents.x
	process.direction = gravity.normalized() if gravity.length_squared() > 0.0001 else Vector3.UP
	process.spread = 28.0 if not additive else 40.0
	process.initial_velocity_min = velocity * 0.5
	process.initial_velocity_max = velocity * 1.5
	process.gravity = gravity
	process.damping_min = 0.05
	process.damping_max = 0.15
	process.scale_min = size_min
	process.scale_max = size_max
	process.color = tint
	# 首尾透明、中段可见：粒子出现/消失不生硬
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.add_point(0.12, Color(1, 1, 1, 1))
	gradient.add_point(0.82, Color(1, 1, 1, 1))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	add_child(particles)
	_emitters.append({
		"node": particles,
		"base_ratio": base_ratio,
		"day_only": day_only,
		"night_only": night_only,
	})
	return particles
