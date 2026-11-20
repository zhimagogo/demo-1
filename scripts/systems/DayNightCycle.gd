class_name DayNightCycle
extends Node
## ============================================================================
## 昼夜循环（v3 画面核心）：把 TimeManager 的游戏时钟翻译成「真实的天色」。
## - 太阳沿天穹扫过：黎明暖橙 → 正午白亮 → 黄昏赤金 → 夜晚沉蓝
## - 天空 / 环境 ambient / 雾色 / 辉光随 daylight 因子连续过渡（ProceduralSkyMaterial 直改）
## - 风暴覆盖（v5）：采样 WeatherSystem 的雨强——雨天阳光衰减、天空转灰蓝、雾加浓；
##   闪电（lightning_flash）在此渲染成整片天光瞬亮（fill 光 + 环境 + 天空 + 太阳全通道）
## - 夜晚：月亮补光（蓝）、城堡与四向城门火炬点亮（暖光 + 火苗颤动）、萤火虫起飞
##   （雨天萤火虫收翅躲雨）
## - 20:00 / 06:00 切换时广播 night_changed（野怪集结 / 蟋蟀鸟鸣环境声都挂在上面）
## ============================================================================
## 挂在 WorldRoot 下，按名取兄弟节点：WorldEnvironment / Sun / FillLight。

# —— 调色板（day ↔ dusk ↔ night）——
# 夜景原则：暗而可读——月光要能照出地形与单位轮廓，火炬负责点缀而不是唯一光源
const SKY_TOP_DAY := Color(0.40, 0.54, 0.66)
const SKY_TOP_NIGHT := Color(0.035, 0.055, 0.13)
const SKY_HORIZON_DAY := Color(0.70, 0.76, 0.83)
const SKY_HORIZON_DUSK := Color(0.98, 0.52, 0.24)
const SKY_HORIZON_NIGHT := Color(0.09, 0.12, 0.22)
const GROUND_HORIZON_DAY := Color(0.42, 0.40, 0.36)
const GROUND_HORIZON_NIGHT := Color(0.05, 0.06, 0.10)
const SUN_COLOR_DAY := Color(1.0, 0.96, 0.88)
const SUN_COLOR_DUSK := Color(1.0, 0.60, 0.30)
const MOON_COLOR := Color(0.58, 0.70, 1.0)
const AMBIENT_DAY := Color(0.50, 0.56, 0.66)
const AMBIENT_NIGHT := Color(0.20, 0.27, 0.46)
const FOG_DAY := Color(0.66, 0.73, 0.83)
const FOG_NIGHT := Color(0.06, 0.09, 0.17)

# —— 风雨调色板（WeatherSystem 雨强叠加在昼夜基调上：灰蓝阴沉、雾更浓）——
const STORM_SKY_TOP := Color(0.32, 0.36, 0.44)
const STORM_SKY_HORIZON := Color(0.52, 0.56, 0.62)
const STORM_GROUND_HORIZON := Color(0.30, 0.33, 0.38)
const STORM_AMBIENT := Color(0.36, 0.40, 0.48)
const STORM_FOG := Color(0.56, 0.61, 0.68)
const FLASH_SKY := Color(0.93, 0.96, 1.0)   # 闪电时的天色（瞬亮偏冷白）

const NIGHT_START_HOUR: int = 20
const NIGHT_END_HOUR: int = 6

var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _torch_lights: Array[OmniLight3D] = []
var _fireflies: Array[GPUParticles3D] = []
var _is_night: bool = false
var _time_accum: float = 0.0
var _weather: WeatherSystem = null
var _last_daylight: float = 1.0
var _ambience_vol: float = 0.35


## 当前日照因子 0~1（WeatherSystem 用它给雨丝做昼夜配色）。
func daylight_factor() -> float:
	return _last_daylight


func _weather_storm() -> float:
	if _weather == null:
		_weather = get_parent().get_node_or_null("WeatherSystem") as WeatherSystem
	return _weather.rain_strength() if _weather != null else 0.0


func _weather_flash() -> float:
	if _weather == null:
		_weather = get_parent().get_node_or_null("WeatherSystem") as WeatherSystem
	return _weather.lightning_flash if _weather != null else 0.0


func _ready() -> void:
	var root := get_parent()
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment
		if _env != null and _env.sky != null:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
	# 关键（v3.1）：场景里 ambient_source=SKY 时，ambient_light_color/energy 全被忽略——
	# 夜空是暗的 → 环境光永远黑。切到 COLOR 源，昼夜环境光曲线才会真正生效。
	if _env != null:
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_sun = root.get_node_or_null("Sun") as DirectionalLight3D
	_fill = root.get_node_or_null("FillLight") as DirectionalLight3D
	_setup_torches()
	_setup_fireflies()
	_apply(TimeManager.hour + _day_fraction())
	# 初始昼夜态（跳过首帧广播——游戏从 6:00 白天开始）
	_is_night = _compute_is_night(TimeManager.hour)


func _process(delta: float) -> void:
	_time_accum += delta
	# 每 0.1s 更新一次天色（人眼不可分辨跳变，省 CPU）
	if _time_accum < 0.1:
		return
	_time_accum = 0.0
	var hour_f: float = TimeManager.hour + _day_fraction()
	_apply(hour_f)
	var now_night := _compute_is_night(TimeManager.hour)
	if now_night != _is_night:
		_is_night = now_night
		EventBus.night_changed.emit(now_night)


func _day_fraction() -> float:
	# 当前小时内已过去的比例（0~1），让太阳连续移动而非整点跳变
	var sec_per_hour: float = TimeManager.seconds_per_day / 24.0
	var in_hour: float = fmod(TimeManager.game_seconds, sec_per_hour)
	return in_hour / sec_per_hour


func _compute_is_night(hour: int) -> bool:
	return hour >= NIGHT_START_HOUR or hour < NIGHT_END_HOUR


# ---- 天色核心 ----

## daylight：0（深夜）~ 1（正午）；dusk_weight：晨昏赤金权重。
func _daylight(hour_f: float) -> float:
	# v47：日出 5:00 → 日落 20:00 的长日照穹顶。
	# 为什么从 5:00 起算：开局固定 6:00，若太阳 6:00 才升到地平线，开局会是一片黑；
	# 5:00 起算让 6:00 已有约 0.27 的日照（清晨侧光），同时保留 18:30~19:30 的黄金时刻。
	var t: float = (hour_f - 5.0) / 15.0
	var dome: float = sin(clampf(t, 0.0, 1.0) * PI)  # 日出日落为 0，正午为 1
	if hour_f >= 5.0 and hour_f <= 20.0:
		return clampf(dome * 1.32, 0.0, 1.0)
	# 夜间：黎明前 / 黄昏后的残余天光（保留极弱底光，避免天空与地形硬切）。
	if hour_f < 5.0:
		return clampf(0.5 - (5.0 - hour_f) * 0.35, 0.0, 0.3) * 0.18
	return clampf(0.5 - (hour_f - 20.0) * 0.4, 0.0, 0.3) * 0.22


func _dusk_weight(hour_f: float) -> float:
	# 晨昏各一个钟形（6 点 / 18 点附近最红）
	var morning: float = exp(-pow((hour_f - 6.5) / 1.4, 2.0))
	var evening: float = exp(-pow((hour_f - 18.6) / 1.45, 2.0))
	return clampf(maxf(morning, evening), 0.0, 1.0)


func _apply(hour_f: float) -> void:
	var daylight := _daylight(hour_f)
	var dusk := _dusk_weight(hour_f)
	_last_daylight = daylight
	var storm := _weather_storm()
	var flash := _weather_flash()
	# 夜间权重：月光 / 雾密度 / 辉光 / 体积雾共用的连续因子（0 白天 → 1 深夜）。
	var nightness := 1.0 - clampf(daylight * 2.0, 0.0, 1.0)

	# —— 太阳：方位角随时刻扫过天穹，仰角走穹顶曲线 ——
	if _sun != null:
		var t: float = clampf((hour_f - 5.0) / 15.0, -0.35, 1.35)
		var elevation: float = sin(clampf(t, 0.0, 1.0) * PI) * 62.0
		var azimuth: float = 60.0 + t * 180.0     # 东 → 南 → 西
		_sun.rotation_degrees = Vector3(-elevation, -azimuth, 0.0)
		# 颜色：白天偏白 → 晨昏暖橙；能量随高度（夜间 0，让位给月亮）
		# v47：主光 / 环境光比从约 1.5:1 拉到约 3.7:1，让体积与投影真正塑形。
		_sun.light_color = SUN_COLOR_DAY.lerp(SUN_COLOR_DUSK, dusk)
		_sun.light_energy = lerpf(0.0, 2.15, clampf(daylight * 1.35, 0.0, 1.0)) * (1.0 - 0.20 * dusk)
		# 风暴：阳光被云层吃掉一半；闪电瞬间补一击
		_sun.light_energy *= 1.0 - 0.50 * storm
		_sun.light_energy += 0.30 * flash

	# —— 月亮（复用 FillLight）：夜间升起冷蓝月光（够亮，能照出地形与敌人轮廓），白天退为柔补光 ——
	if _fill != null:
		_fill.light_color = Color(0.66, 0.74, 0.82).lerp(MOON_COLOR, nightness)
		_fill.light_energy = lerpf(0.10, 1.0, nightness)
		_fill.light_energy *= 1.0 - 0.20 * storm
		_fill.light_energy += 1.70 * flash

	# —— 天空 / 环境 / 雾 ——
	if _sky_mat != null:
		var top := SKY_TOP_DAY.lerp(SKY_TOP_NIGHT, 1.0 - clampf(daylight * 1.3, 0.0, 1.0))
		var horizon_day := SKY_HORIZON_DAY.lerp(SKY_HORIZON_DUSK, dusk)
		var horizon := horizon_day.lerp(SKY_HORIZON_NIGHT, 1.0 - clampf(daylight * 1.3, 0.0, 1.0))
		var ghorizon := GROUND_HORIZON_DAY.lerp(GROUND_HORIZON_NIGHT, 1.0 - clampf(daylight * 1.3, 0.0, 1.0))
		# 风暴：天色整体沉入灰蓝（夜里只混一部分——乌云夜不该比晴夜星空亮）；
		# 闪电：整片天瞬亮偏冷白
		var dl13 := clampf(daylight * 1.3, 0.0, 1.0)
		var storm_sky := storm * (0.30 + 0.70 * dl13)
		top = top.lerp(STORM_SKY_TOP, storm_sky).lerp(FLASH_SKY, 0.5 * flash)
		horizon = horizon.lerp(STORM_SKY_HORIZON, storm_sky).lerp(FLASH_SKY, 0.55 * flash)
		ghorizon = ghorizon.lerp(STORM_GROUND_HORIZON, storm_sky)
		_sky_mat.sky_top_color = top
		_sky_mat.sky_horizon_color = horizon
		_sky_mat.ground_horizon_color = ghorizon
	if _env != null:
		var dl := clampf(daylight * 1.3, 0.0, 1.0)
		var ambient := AMBIENT_DAY.lerp(AMBIENT_NIGHT, nightness).lerp(STORM_AMBIENT, storm * (0.4 + 0.6 * dl))
		# v47：夜间环境光压到 0.28（v46 为 0.72）——月亮是主光，环境光只负责暗部可读性；
		# 配合火炬 / 自发光把视觉重心留在城池，而不是一片均匀的夜蓝色。
		var ambient_e := lerpf(0.48, 0.64, dl) * (1.0 - 0.18 * storm) + 0.85 * flash
		_env.ambient_light_color = ambient
		_env.ambient_light_energy = ambient_e
		_env.fog_light_color = FOG_DAY.lerp(FOG_NIGHT, 1.0 - dl).lerp(STORM_FOG, storm * (0.4 + 0.6 * dl))
		_env.fog_light_energy = lerpf(0.16, 0.32, dl) + dusk * 0.12 + (0.10 + 0.22 * dl) * storm
		# 夜间空气更「厚」：远处地形淡入夜色，同时给火炬一点可见的体积。
		_env.fog_density = lerpf(0.0026, 0.0011, dl) + 0.0016 * storm
		_env.glow_intensity = lerpf(0.50, 0.22, dl)   # 夜里辉光更强：火炬 / 窗光 / 萤火虫更透
		# v47 眼睛自适应：夜里把曝光抬一档，白天略收，避免「白天过曝、夜里死黑」。
		_env.tonemap_exposure = lerpf(1.16, 0.97, dl)
		if _env.volumetric_fog_enabled:
			# 体积雾由画质档位决定是否开启；昼夜只改密度与颜色，不碰开关。
			_env.volumetric_fog_density = lerpf(0.0070, 0.0006, dl) * (1.0 + 0.8 * storm)
			_env.volumetric_fog_albedo = Color(0.62, 0.68, 0.82).lerp(Color(0.72, 0.78, 0.92), dl)
			_env.volumetric_fog_emission = FOG_NIGHT.lerp(Color(0.02, 0.02, 0.03), dl)
			_env.volumetric_fog_emission_energy = lerpf(0.22, 0.0, dl)

	# —— 水面夜色（water shader 的 night_dim uniform）——
	var water := get_parent().get_node_or_null("Water") as MeshInstance3D
	if water != null and water.material_override is ShaderMaterial:
		(water.material_override as ShaderMaterial).set_shader_parameter("night_dim", 1.0 - clampf(daylight * 1.4, 0.0, 1.0))

	# —— 火炬 / 萤火虫：入夜亮起（萤火虫雨天收翅躲雨，雨大就不再起飞）——
	var torch_on: float = clampf((0.42 - daylight) * 3.4, 0.0, 1.0)
	for torch in _torch_lights:
		# 火苗颤动：能量在基线上小幅抖动
		var flicker: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.013 + torch.position.x * 7.3)
		torch.light_energy = torch_on * 3.3 * flicker
	for ff in _fireflies:
		ff.emitting = torch_on > 0.25 and storm < 0.5
		ff.visible = torch_on > 0.05 and storm < 0.6

	# —— 环境声：晴昼鸟鸣 / 暮夜蟋蟀（雨天压低鸟虫声，让位给雨声）——
	_update_ambience(daylight, storm)


var _ambience: StringName = &""


func _update_ambience(daylight: float, storm: float = 0.0) -> void:
	var wanted: StringName = &"night_crickets" if daylight < 0.4 else &"day_birds"
	if wanted != _ambience:
		if _ambience != &"":
			AudioManager.stop_loop(_ambience)
		_ambience = wanted
	# 雨越大鸟虫越轻（雨声由 WeatherSystem 按强度驱动）
	var vol := 0.35 * (1.0 - 0.7 * clampf(storm, 0.0, 1.0))
	if absf(vol - _ambience_vol) > 0.04:
		_ambience_vol = vol
		AudioManager.play_loop(_ambience, vol)


# ---- 火炬与萤火虫 ----

## 火炬：主城中心 + 四向城门（道路出城处）。暖光 OmniLight，夜亮昼熄。
## v43：城门火把位置从 WorldLayout.CITY_HALF 派生（城沿外 1.5m），不再硬编码 21.5
## ——城池扩到 52×52m（半宽 26）后，火把必须跟着城门走。
func _setup_torches() -> void:
	var gate: float = WorldLayout.CITY_HALF + 1.5
	var spots := [
		Vector3(3.2, 3.6, 3.2),          # 城堡角（贴主城模型）
		Vector3(0.0, 1.9, -gate),        # 北门（-Z 侧城门，city_half + 1.5）
		Vector3(0.0, 1.9, gate),         # 南门（+Z 侧城门）
		Vector3(gate, 1.9, 0.0),         # 东门
		Vector3(-gate, 1.9, 0.0),        # 西门
		# v47：城内四角补灯——夜间城池有一圈暖光轮廓，而不是只有四个孤立的门灯。
		Vector3(gate * 0.66, 1.9, gate * 0.66),
		Vector3(-gate * 0.66, 1.9, gate * 0.66),
		Vector3(gate * 0.66, 1.9, -gate * 0.66),
		Vector3(-gate * 0.66, 1.9, -gate * 0.66),
	]
	for spot in spots:
		var torch := OmniLight3D.new()
		torch.name = "TorchLight"
		torch.light_color = Color(1.0, 0.66, 0.30)
		torch.omni_range = 16.0
		torch.omni_attenuation = 1.25
		torch.light_volumetric_fog_energy = 4.0
		torch.light_energy = 0.0
		torch.shadow_enabled = false
		torch.position = spot
		get_parent().call_deferred("add_child", torch)
		_torch_lights.append(torch)
		# 火苗柱（小小的发光柱体，白天也隐约可见是「灯柱」）
		var pole := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.08
		cyl.height = spot.y
		pole.mesh = cyl
		pole.position = Vector3(spot.x, spot.y * 0.5, spot.z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.24, 0.18, 0.12)
		pole.material_override = mat
		get_parent().call_deferred("add_child", pole)
		# 灯头（发光小方块，夜间被辉光放大成火苗）
		var head := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 0.3, 0.22)
		head.mesh = box
		head.position = Vector3(spot.x, spot.y + 0.1, spot.z)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(1.0, 0.72, 0.35)
		hmat.emission_enabled = true
		hmat.emission = Color(1.0, 0.55, 0.2)
		hmat.emission_energy_multiplier = 1.6
		head.material_override = hmat
		get_parent().call_deferred("add_child", head)


## 萤火虫：湖岸 + 西侧林间两团，夜间起飞（加法混合小光点，缓速漂浮）。
func _setup_fireflies() -> void:
	var spots := [Vector3(24.0, 1.2, -14.0), Vector3(-38.0, 1.2, 22.0)]
	for spot in spots:
		var p := GPUParticles3D.new()
		p.amount = 26
		p.lifetime = 7.0
		p.explosiveness = 0.0
		p.randomness = 1.0
		p.visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 6, 28))
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3.UP
		mat.spread = 180.0
		mat.initial_velocity_min = 0.25
		mat.initial_velocity_max = 0.7
		mat.gravity = Vector3(0, 0.05, 0)
		mat.scale_min = 0.5
		mat.scale_max = 1.1
		mat.color = Color(0.85, 1.0, 0.45)
		p.process_material = mat
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.09, 0.09)
		var mmat := StandardMaterial3D.new()
		mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mmat.albedo_color = Color(0.9, 1.0, 0.5, 0.9)
		mmat.emission_enabled = true
		mmat.emission = Color(0.75, 1.0, 0.4)
		mmat.emission_energy_multiplier = 2.2
		mmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.material = mmat
		p.draw_pass_1 = mesh
		p.position = spot
		p.emitting = false
		get_parent().call_deferred("add_child", p)
		_fireflies.append(p)
