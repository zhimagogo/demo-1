class_name WeatherSystem
extends Node
## ============================================================================
## 天气系统（v3 氛围层；v5 雨效果全面强化）：
## - 晴 → 多云 → 雨 的随机马尔可夫链；雨中强度随机漫步（毛毛雨 ↔ 暴雨）
## - 雨幕：远雨雾 / 主雨层 / 近景大雨丝 三层视差 + 地面溅落环 + 溅起水珠（全部跟随相机）
## - 阵风：风向风力缓慢起伏，雨丝倾斜随之摆动
## - 湿地：淋湿快、放晴慢（水洼余韵）；低洼处噪声水洼（ground shader）
## - 湖面雨涟漪（water shader rain_amount）
## - 雷暴：多段闪电闪烁（lightning_flash 数值交 DayNightCycle 渲染整片天光）
##   + 延迟雷声（先见闪电后闻雷的距离感）+ 震屏；毛毛雨（强度低）不打雷
## - 雨声音量随强度渐变；weather_changed 携带强度分档（顶栏显示 小雨/中雨/大雨/暴雨）
## 天气纯视觉，不影响玩法数值——但夜里下雨 + 火炬 = 氛围直接拉满。
## ============================================================================

enum State { CLEAR, CLOUDY, RAIN }

const SWITCH_INTERVAL_MIN: float = 90.0    # 天气段最短时长（游戏秒）
const SWITCH_INTERVAL_MAX: float = 220.0
const RAIN_CHANCE: float = 0.38            # 切换时进入雨天的概率
const CLOUDY_CHANCE: float = 0.42
const THUNDER_MIN_GAP: float = 14.0        # 两声雷的最小间隔

# —— 雨强演进 ——
const STRENGTH_WET_RATE: float = 0.35      # 下雨时强度爬升速率（/秒）
const STRENGTH_DRY_RATE: float = 0.30      # 雨停后强度消退速率（/秒）
const STRENGTH_WALK_MIN: float = 0.35      # 雨中强度随机漫步区间
const STRENGTH_WALK_MAX: float = 1.0
const STRENGTH_WALK_EVERY_MIN: float = 9.0
const STRENGTH_WALK_EVERY_MAX: float = 22.0
const THUNDER_STRENGTH_GATE: float = 0.55  # 强度低于此值不打雷（毛毛雨无雷）

# —— 湿度演进（淋湿快、晒干慢 → 雨停后地面留一段时间水光）——
const WET_WET_RATE: float = 0.50
const WET_DRY_RATE: float = 0.018

# —— 雨声音量区间（随强度）——
const RAIN_VOLUME_MIN: float = 0.16
const RAIN_VOLUME_MAX: float = 0.68

var state: int = State.CLEAR
var lightning_flash: float = 0.0           # 闪电亮度 0~1（DayNightCycle 每帧采样渲染）
var _timer: float = 0.0
var _next_switch: float = 120.0
var _wetness: float = 0.0                  # 平滑过渡到目标湿度
var _wetness_target: float = 0.0
var _cloud_amount: float = 1.0             # 云影强度（ground shader）
var _cloud_target: float = 1.0
var _thunder_timer: float = 8.0
var _camera: Camera3D = null
var _dnc: DayNightCycle = null

var _strength: float = 0.0                 # 雨强 0~1（平滑演进 + 雨中随机漫步）
var _strength_target: float = 0.0
var _strength_walk_timer: float = 0.0
var _wind_time: float = 0.0
var _volume_last: float = -1.0             # 上次设置的雨声音量（避免每帧重设）
var _bucket_last: int = -1                 # 上次广播的强度分档（顶栏 小/中/大/暴雨）
var _tick_accum: float = 0.0               # 0.1s 节流：材质 / 风向 / 音量更新

# —— 雨幕层（远雨雾 / 主雨层 / 近景大雨丝）+ 溅落 ——
var _rain_layers: Array[GPUParticles3D] = []
var _rain_mats: Array[ParticleProcessMaterial] = []
var _layer_alpha: Array[float] = []
var _layer_rgb: Array[Color] = []
var _layer_y: Array[float] = []
var _layer_gain: Array[float] = []         # amount_ratio = strength × gain（近景层要大雨才满）
var _layer_draw_mats: Array[ShaderMaterial] = []
var _streak_shader: Shader = null
var _streak_alpha_gradient: GradientTexture1D = null
var _streak_life_curve: CurveTexture = null
var _splash_rings: GPUParticles3D = null
var _splash_bounce: GPUParticles3D = null
var _splash_ring_draw: StandardMaterial3D = null
var _splash_bounce_draw: StandardMaterial3D = null
var _ground_mat: ShaderMaterial = null
var _water_mat: ShaderMaterial = null


func _ready() -> void:
	EventBus.night_changed.connect(_on_night_changed)
	_setup_rain()
	_apply_state(State.CLEAR)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_switch:
		_timer = 0.0
		_next_switch = randf_range(SWITCH_INTERVAL_MIN, SWITCH_INTERVAL_MAX)
		_pick_next()
	_update_strength(delta)
	_wind_time += delta
	_update_rain_position()
	# 0.1s 节流块：湿度/云影写入、雨丝昼夜配色、风向、音量、分档广播
	_tick_accum += delta
	if _tick_accum >= 0.1:
		_tick_accum = 0.0
		_tick_apply()
	# 雷（仅强度足够的雨；毛毛雨静默）
	if state == State.RAIN and _strength > THUNDER_STRENGTH_GATE:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_strike()


## 雨强 0~1（DayNightCycle 采样做风暴压暗；HUD / 测试可读）。
func rain_strength() -> float:
	return _strength


# ---- 状态机 ----

func _pick_next() -> void:
	var r := randf()
	if r < RAIN_CHANCE:
		_apply_state(State.RAIN)
	elif r < RAIN_CHANCE + CLOUDY_CHANCE:
		_apply_state(State.CLOUDY)
	else:
		_apply_state(State.CLEAR)


func _apply_state(s: int) -> void:
	state = s
	match s:
		State.CLEAR:
			_wetness_target = 0.0
			_cloud_target = 1.0
			_set_rain(false)
			EventBus.weather_changed.emit(&"clear", 0.0)
			EventBus.game_message.emit("云开了，是个干活的好天气。", Color(0.85, 0.9, 1.0))
		State.CLOUDY:
			_wetness_target = 0.0
			_cloud_target = 2.6
			_set_rain(false)
			EventBus.weather_changed.emit(&"cloudy", 0.0)
			EventBus.game_message.emit("云层压低了，风里有潮气…", Color(0.7, 0.72, 0.78))
		State.RAIN:
			_cloud_target = 3.4
			_set_rain(true)
			_strength_target = randf_range(0.5, 0.85)   # 开场即中雨，随后随机漫步
			_strength_walk_timer = randf_range(STRENGTH_WALK_EVERY_MIN, STRENGTH_WALK_EVERY_MAX)
			_thunder_timer = randf_range(3.0, 8.0)
			_bucket_last = -1
			_volume_last = -1.0
			EventBus.weather_changed.emit(&"rain", _strength_target)
			EventBus.game_message.emit("下雨了，火把在雨里噼啪作响。", Color(0.55, 0.7, 0.95))
			AudioManager.play_loop(&"rain_loop", RAIN_VOLUME_MIN)


## 调试热键（F6）：晴 → 多云 → 雨 循环，供真机快速验证天气链路。
func debug_cycle() -> void:
	match state:
		State.CLEAR:
			_apply_state(State.CLOUDY)
		State.CLOUDY:
			_apply_state(State.RAIN)
		_:
			_apply_state(State.CLEAR)
	_timer = 0.0
	_next_switch = randf_range(SWITCH_INTERVAL_MIN, SWITCH_INTERVAL_MAX)


func _on_night_changed(_is_night: bool) -> void:
	# 雨停后环境声切换（雨声停；晴夜蟋蟀 / 晴昼鸟鸣由 DayNightCycle 处理）
	if state != State.RAIN:
		AudioManager.stop_loop(&"rain_loop")


# ---- 雨强 / 湿度 / 风演进 ----

func _update_strength(delta: float) -> void:
	if state == State.RAIN:
		_strength_walk_timer -= delta
		if _strength_walk_timer <= 0.0:
			_strength_walk_timer = randf_range(STRENGTH_WALK_EVERY_MIN, STRENGTH_WALK_EVERY_MAX)
			_strength_target = randf_range(STRENGTH_WALK_MIN, STRENGTH_WALK_MAX)
		_strength = move_toward(_strength, _strength_target, STRENGTH_WET_RATE * delta)
	else:
		_strength = move_toward(_strength, 0.0, STRENGTH_DRY_RATE * delta)
	# 湿度目标随强度：中雨即接近全湿；放晴后目标归零但晒干更慢
	_wetness_target = (0.55 + 0.35 * _strength) if state == State.RAIN else 0.0
	var wet_rate := WET_WET_RATE if _wetness_target > _wetness else WET_DRY_RATE
	_wetness = move_toward(_wetness, _wetness_target, wet_rate * delta)
	_cloud_amount = lerpf(_cloud_amount, _cloud_target, delta * 0.5)


## 阵风：两个不同频率正弦叠加 → 风向缓慢起伏，雨丝倾斜随之摆动。
func _wind_vec() -> Vector3:
	# 成熟做法（Unity VFX Graph / Niagara 通行）：全场一个风向、慢漂移（周期 15~20s），
	# 阵风只短暂改变风速不改方向；轨迹倾角稳定在 7~21°。
	var wx := -0.22 + 0.10 * sin(_wind_time * 0.43)
	var wz := -0.12 + 0.09 * sin(_wind_time * 0.31 + 1.7)
	return Vector3(wx, -1.0, wz).normalized()


## 0.1s 一次的材质 / 音量 / 广播同步（避免每帧写 uniform 与重设音量）。
func _tick_apply() -> void:
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("wetness", _wetness)
		_ground_mat.set_shader_parameter("rain_amount", _strength)
		_ground_mat.set_shader_parameter("cloud_amount", _cloud_amount)
	if _water_mat != null:
		_water_mat.set_shader_parameter("rain_amount", _strength)
	# 雨丝昼夜配色（夜里稍暗偏蓝但保持可读）+ 世界空间随风倾斜
	var daylight := _daylight_factor()
	var night := 1.0 - daylight
	var wind := _wind_vec()
	for i in _rain_layers.size():
		var dm: ShaderMaterial = _layer_draw_mats[i]
		dm.set_shader_parameter("tint", Color(
			_layer_rgb[i].lerp(Color(0.55, 0.66, 0.92), night * 0.45),
			_layer_alpha[i] * lerpf(1.0, 0.7, night)))
		dm.set_shader_parameter("fall_direction", wind)
	# 溅落昼夜压暗：夜里溅落环大幅减弱（诊断：夜里环像悬浮发光气泡、喧宾夺主）
	if _splash_ring_draw != null:
		_splash_ring_draw.albedo_color = Color(0.45, 0.55, 0.70, lerpf(0.12, 0.30, daylight))
	if _splash_bounce_draw != null:
		_splash_bounce_draw.albedo_color = Color(0.55, 0.65, 0.82, lerpf(0.18, 0.45, daylight))
	# 风向写入 + 粒子量随强度（远雨雾毛毛雨就有，近景大雨丝要暴雨才满）
	for i in _rain_mats.size():
		_rain_mats[i].direction = wind
	_set_particles_emitting(_strength > 0.005)
	for i in _rain_layers.size():
		_rain_layers[i].amount_ratio = clampf(_strength * _layer_gain[i], 0.0, 1.0)
	if _splash_rings != null:
		_splash_rings.amount_ratio = clampf(_strength * 1.2, 0.0, 1.0)
	if _splash_bounce != null:
		_splash_bounce.amount_ratio = clampf(_strength * 1.2, 0.0, 1.0)
	# 雨声音量随强度渐变
	if state == State.RAIN:
		var vol := lerpf(RAIN_VOLUME_MIN, RAIN_VOLUME_MAX, clampf(_strength, 0.0, 1.0))
		if absf(vol - _volume_last) > 0.03:
			_volume_last = vol
			AudioManager.play_loop(&"rain_loop", vol)
	# 强度分档广播（顶栏 小雨/中雨/大雨/暴雨；分档变化才发）
	if state == State.RAIN:
		var bucket := int(clampf(_strength, 0.0, 0.999) / 0.25)
		if bucket != _bucket_last:
			_bucket_last = bucket
			EventBus.weather_changed.emit(&"rain", _strength)


func _daylight_factor() -> float:
	if _dnc == null:
		_dnc = get_parent().get_node_or_null("DayNightCycle") as DayNightCycle
	if _dnc != null:
		return _dnc.daylight_factor()
	return 1.0


# ---- 雨幕 / 溅落构建 ----

func _setup_rain() -> void:
	# 找地面 / 水面材质（GroundPlane / Water 的 material_override）
	var root := get_parent()
	var gp := root.get_node_or_null("GroundPlane") as Node3D
	if gp != null:
		var mi := gp.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mi != null and mi.material_override is ShaderMaterial:
			_ground_mat = mi.material_override
	var water := root.get_node_or_null("Water") as MeshInstance3D
	if water != null and water.material_override is ShaderMaterial:
		_water_mat = water.material_override
	# 统一终端速度方向；短曝光雨丝，发射高度覆盖屋顶与镜头上沿。
	_make_rain_layer("RainFar", 1000, 1.25, 19.0, 22.0, Vector3(44, 1.2, 44),
		Vector2(0.035, 0.65), Color(0.68, 0.74, 0.80, 0.28), 18.0, 0.85)
	_make_rain_layer("RainMid", 2200, 1.1, 24.0, 28.0, Vector3(34, 1.5, 34),
		Vector2(0.045, 1.05), Color(0.72, 0.78, 0.84, 0.48), 20.0, 1.0)
	_make_rain_layer("RainNear", 380, 0.95, 29.0, 33.0, Vector3(24, 1.2, 24),
		Vector2(0.060, 1.45), Color(0.76, 0.81, 0.87, 0.44), 22.0, 0.7)
	_setup_splash()


## 一层雨幕：长条雨丝快速下落（全局坐标，发射盒跟随相机，摄像机平移不拖尾）。
## 世界空间风向拉伸、软边与逐粒子长短/透明度变化。
func _make_rain_layer(p_name: String, amount: int, lifetime: float, vel_min: float, vel_max: float,
		box: Vector3, streak: Vector2, base_color: Color, y_off: float, ratio_gain: float) -> void:
	var p := GPUParticles3D.new()
	p.name = p_name
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	# AABB 要罩住整段下落轨迹（原版只到 -6，雨丝半空消失；这里下缘放到 -42）
	p.visibility_aabb = AABB(
		Vector3(-box.x - 10.0, -box.y - 42.0, -box.z - 10.0),
		Vector3((box.x + 10.0) * 2.0, box.y * 2.0 + 88.0, (box.z + 10.0) * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(-0.25, -1.0, -0.12)
	mat.spread = 1.0
	mat.initial_velocity_min = vel_min
	mat.initial_velocity_max = vel_max
	mat.gravity = Vector3.ZERO
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = box
	# 逐粒子长度随机（短丝/长丝混布，打破等长的机械感）
	mat.scale_min = 0.65
	mat.scale_max = 1.45
	# 逐粒子明暗随机（半透→全亮的雨丝混布）
	mat.color_initial_ramp = _streak_initial_gradient()
	# 生命周期淡入淡出（避免雨丝闪现/闪灭）
	mat.color_ramp = _streak_life_ramp()
	# 雨滴按终端速度运动，避免横向湍流形成飘雪感。
	p.process_material = mat
	var mesh := QuadMesh.new()
	mesh.size = streak
	if _streak_shader == null:
		_streak_shader = load("res://assets/shaders/rain_streak.gdshader") as Shader
	var mmat := ShaderMaterial.new()
	mmat.shader = _streak_shader
	mmat.set_shader_parameter("tint", base_color)
	mmat.set_shader_parameter("taper", 0.22)
	mesh.material = mmat
	p.draw_pass_1 = mesh
	p.emitting = false
	get_parent().call_deferred("add_child", p)
	_rain_layers.append(p)
	_rain_mats.append(mat)
	_layer_alpha.append(base_color.a)
	_layer_rgb.append(Color(base_color.r, base_color.g, base_color.b))
	_layer_y.append(y_off)
	_layer_gain.append(ratio_gain)
	_layer_draw_mats.append(mmat)


## 逐粒子明暗变化梯度：出生时随机取样（0→1 映射 alpha 0.55→1.0、亮度 0.85→1.0）。
func _streak_initial_gradient() -> GradientTexture1D:
	if _streak_alpha_gradient != null:
		return _streak_alpha_gradient
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.87, 0.92, 0.55))
	grad.set_color(1, Color(1.0, 1.0, 1.0, 1.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	_streak_alpha_gradient = tex
	return tex


## 生命周期淡入淡出：出生 15% 内淡入、末段 25% 淡出（雨丝不再闪现闪灭）。
func _streak_life_ramp() -> CurveTexture:
	if _streak_life_curve != null:
		return _streak_life_curve
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.80, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var tex := CurveTexture.new()
	tex.curve = curve
	_streak_life_curve = tex
	return tex


## 地面溅落：贴地扩散的涟漪环（透明混合 + 生命周期内放大淡出）+ 溅起的小水珠。
func _setup_splash() -> void:
	var ring_tex := _make_ring_texture()
	var grow := CurveTexture.new()
	var grow_curve := Curve.new()
	grow_curve.add_point(Vector2(0.0, 0.30))
	grow_curve.add_point(Vector2(1.0, 1.25))
	grow.curve = grow_curve
	var fade := CurveTexture.new()
	var fade_curve := Curve.new()
	fade_curve.add_point(Vector2(0.0, 0.0))
	fade_curve.add_point(Vector2(0.10, 0.9))
	fade_curve.add_point(Vector2(0.55, 0.5))
	fade_curve.add_point(Vector2(1.0, 0.0))
	fade.curve = fade_curve

	# —— 溅落环：平铺地面的圆环（FACE_Y 不做公告板），出生即扩散、后段淡出 ——
	# v5.2：更小、更暗、环带更细（诊断：v5 的环又大又亮，夜里像悬浮的发光肥皂泡）
	_splash_rings = GPUParticles3D.new()
	_splash_rings.name = "RainSplashRings"
	_splash_rings.amount = 300
	_splash_rings.lifetime = 0.6
	_splash_rings.local_coords = false
	_splash_rings.visibility_aabb = AABB(Vector3(-28, -2, -28), Vector3(56, 4, 56))
	var rmat := ParticleProcessMaterial.new()
	rmat.direction = Vector3.UP
	rmat.spread = 1.0
	rmat.initial_velocity_min = 0.01
	rmat.initial_velocity_max = 0.02
	rmat.gravity = Vector3.ZERO
	rmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rmat.emission_box_extents = Vector3(28, 0.0, 28)
	rmat.scale_curve = grow
	rmat.color_ramp = fade
	_splash_rings.process_material = rmat
	var ring_mesh := QuadMesh.new()
	ring_mesh.size = Vector2(0.24, 0.24)
	ring_mesh.orientation = PlaneMesh.FACE_Y
	var rmmat := StandardMaterial3D.new()
	rmmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	rmmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmmat.albedo_color = Color(0.45, 0.55, 0.70, 0.8)
	rmmat.albedo_texture = ring_tex
	rmmat.vertex_color_use_as_albedo = true
	ring_mesh.material = rmmat
	_splash_rings.draw_pass_1 = ring_mesh
	_splash_rings.emitting = false
	get_parent().call_deferred("add_child", _splash_rings)
	_splash_ring_draw = rmmat

	# —— 溅起水珠：小颗粒向上弹起后受重力回落 ——
	_splash_bounce = GPUParticles3D.new()
	_splash_bounce.name = "RainSplashBounce"
	_splash_bounce.amount = 170
	_splash_bounce.lifetime = 0.38
	_splash_bounce.local_coords = false
	_splash_bounce.visibility_aabb = AABB(Vector3(-28, -1, -28), Vector3(56, 8, 56))
	var bmat := ParticleProcessMaterial.new()
	bmat.direction = Vector3.UP
	bmat.spread = 38.0
	bmat.initial_velocity_min = 1.4
	bmat.initial_velocity_max = 2.4
	bmat.gravity = Vector3(0, -9, 0)
	bmat.scale_min = 0.6
	bmat.scale_max = 1.3
	bmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	bmat.emission_box_extents = Vector3(28, 0.0, 28)
	bmat.color_ramp = fade
	_splash_bounce.process_material = bmat
	var drop_mesh := QuadMesh.new()
	drop_mesh.size = Vector2(0.035, 0.045)
	var dmmat := StandardMaterial3D.new()
	dmmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	dmmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmmat.albedo_color = Color(0.55, 0.65, 0.82)
	dmmat.vertex_color_use_as_albedo = true
	dmmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drop_mesh.material = dmmat
	_splash_bounce.draw_pass_1 = drop_mesh
	_splash_bounce.emitting = false
	get_parent().call_deferred("add_child", _splash_bounce)
	_splash_bounce_draw = dmmat


## 程序化溅落环贴图：外圈亮环 + 中心淡斑（雨滴击中点）。
## v5.2：环带收细（0.20→0.13）、中心斑减弱（0.7→0.45）——薄的涟漪而不是实心甜甜圈。
func _make_ring_texture() -> ImageTexture:
	var size := 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - c, y + 0.5 - c).length() / c
			var a := clampf(1.0 - absf(d - 0.62) / 0.13, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var dot_a := clampf(1.0 - d / 0.30, 0.0, 1.0) * 0.45
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a + dot_a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _set_particles_emitting(on: bool) -> void:
	for p in _rain_layers:
		p.emitting = on
	if _splash_rings != null:
		_splash_rings.emitting = on
	if _splash_bounce != null:
		_splash_bounce.emitting = on


func _set_rain(on: bool) -> void:
	if on:
		_set_particles_emitting(true)
	else:
		AudioManager.stop_loop(&"rain_loop")


func _update_rain_position() -> void:
	if state != State.RAIN and _strength <= 0.005:
		return
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	# 雨幕中心：视线与地面的交点（相机注视的地面点，而非半空的视线中点）——
	# 这样发射盒以画面中心为圆心铺开，屏幕边缘也有雨。
	var forward := -_camera.global_transform.basis.z
	var cam_pos := _camera.global_position
	var focus := cam_pos + forward * 24.0
	if forward.y < -0.15:
		var t := cam_pos.y / (-forward.y)
		if t > 0.0 and t < 200.0:
			focus = cam_pos + forward * t
	for i in _rain_layers.size():
		_rain_layers[i].global_position = Vector3(focus.x, focus.y + _layer_y[i], focus.z)
	if _splash_rings != null:
		_splash_rings.global_position = Vector3(focus.x, 0.025, focus.z)
	if _splash_bounce != null:
		_splash_bounce.global_position = Vector3(focus.x, 0.025, focus.z)


# ---- 雷 ----

func _thunder_strike() -> void:
	# 强度越高雷越密
	var gap_scale := 1.25 - 0.45 * clampf(_strength, 0.0, 1.0)
	_thunder_timer = randf_range(THUNDER_MIN_GAP, THUNDER_MIN_GAP + 18.0) * gap_scale
	# 闪电：双击闪烁（本节点只写数值，整片天光渲染在 DayNightCycle._apply 里采样）
	var tw := create_tween()
	tw.tween_property(self, "lightning_flash", 0.85, 0.05)
	tw.tween_property(self, "lightning_flash", 0.15, 0.10)
	tw.tween_property(self, "lightning_flash", 1.0, 0.06)
	tw.tween_property(self, "lightning_flash", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 雷声延迟：先见闪电后闻雷（距离感）
	var delay := randf_range(0.25, 1.3)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		AudioManager.play_sfx(&"thunder"))
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("shake"):
		cam.call("shake", 0.16, 0.4)
