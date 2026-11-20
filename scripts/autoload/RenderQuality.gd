extends Node
## ============================================================================
## RenderQuality —— v47 统一画质分级（autoload）。
##
## 设计目标：把「看得见的质感」与「付得起的成本」拆开——
##   · 艺术基线（AgX、光照比、雾、SSAO 参数、调色）固定在场景 / DayNightCycle 里，
##     所有档位共享同一套色彩与光影语言；
##   · 档位只决定昂贵的可选特性（SSIL / 体积雾 / 软阴影质量 / 阴影距离与图集 /
##     草与装饰的可视距离 / 3D 缩放 / MSAA / 后处理强度）。
##
## 落地方式：
##   · 全局项（阴影图集、软阴影滤波、Viewport AA/缩放）在 set_preset 时立即应用；
##   · 世界项（Environment 开关、DirectionalLight 阴影、DecorationScatter 视距）
##     由 Main._ready 末尾调用 apply_to_world(world_root)，以及运行中切档时自动重扫。
##   · 玩家选择持久化在 GameSettings（user://settings.cfg 的 quality 键）。
##
## 约定：本节点不持有玩法状态；切档只改渲染资源与参数，可随时回切。
## ============================================================================

enum Tier { LOW, MEDIUM, HIGH, ULTRA }

const TIER_NAMES: Array[String] = ["低", "中", "高", "极致"]
const DEFAULT_TIER: int = Tier.HIGH

## 每档的参数。字段说明：
##   scale / scaling_mode  3D 渲染分辨率与放大方式（<1 用 FSR1 质量更好）
##   msaa / screen_aa      多重采样 / 屏幕空间 AA（0 关 1 FXAA 2 SMAA）
##   ssao / ssil           环境光遮蔽 / 屏幕空间间接光
##   volumetric            夜间体积雾（DayNightCycle 只写密度，不碰开关）
##   post_fx               调色 / 暗角 / 颗粒后处理层
##   shadow_mode / distance / angular / soft / atlas  阴影分级
##   grass_range / decor_range  草与装饰 MultiMesh 的可视距离上限
const PRESETS: Array[Dictionary] = [
	{
		"name": "低",
		"scale": 0.87, "scaling_mode": 1,   # FSR1
		"msaa": 0, "screen_aa": 2,          # SMAA（比 FXAA 更干净，成本很低）
		"ssao": false, "ssil": false, "glow": true, "volumetric": false, "post_fx": false,
		"shadow_mode": 1, "shadow_distance": 84.0, "shadow_angular": 0.45,
		"shadow_soft": 1, "shadow_atlas": 2048, "split_1": 0.15, "split_2": 0.45, "split_3": 0.2,
		"fade_start": 0.6,
		"grass_range": 84.0, "decor_range": 96.0,
		"vignette": 0.0, "grain": 0.0, "grade": 1.0,
	},
	{
		"name": "中",
		"scale": 1.0, "scaling_mode": 0,
		"msaa": 0, "screen_aa": 2,
		"ssao": true, "ssil": false, "glow": true, "volumetric": false, "post_fx": true,
		"shadow_mode": 1, "shadow_distance": 104.0, "shadow_angular": 0.55,
		"shadow_soft": 2, "shadow_atlas": 4096, "split_1": 0.15, "split_2": 0.45, "split_3": 0.2,
		"fade_start": 0.65,
		"grass_range": 96.0, "decor_range": 120.0,
		"vignette": 0.16, "grain": 0.008, "grade": 0.8,
	},
	{
		"name": "高",
		"scale": 1.0, "scaling_mode": 0,
		"msaa": 0, "screen_aa": 2,
		"ssao": true, "ssil": true, "glow": true, "volumetric": true, "post_fx": true,
		# 2 split：俯视角只需覆盖近中景；同尺寸图集下每 split 分辨率翻倍，反而更锐。
		"shadow_mode": 1, "shadow_distance": 118.0, "shadow_angular": 0.65,
		"shadow_soft": 2, "shadow_atlas": 4096, "split_1": 0.16, "split_2": 0.46, "split_3": 0.2,
		"fade_start": 0.8,
		"grass_range": 112.0, "decor_range": 140.0,
		"vignette": 0.2, "grain": 0.01, "grade": 1.0,
	},
	{
		"name": "极致",
		"scale": 1.0, "scaling_mode": 0,
		"msaa": 1, "screen_aa": 0,          # 2× MSAA；边缘更稳，配 4 split 软阴影
		"ssao": true, "ssil": true, "glow": true, "volumetric": true, "post_fx": true,
		"shadow_mode": 2, "shadow_distance": 140.0, "shadow_angular": 0.9,
		"shadow_soft": 3, "shadow_atlas": 8192, "split_1": 0.12, "split_2": 0.22, "split_3": 0.3,
		"fade_start": 0.85,
		"grass_range": 140.0, "decor_range": 180.0,
		"vignette": 0.22, "grain": 0.012, "grade": 1.1,
	},
]

var _tier: int = DEFAULT_TIER
var _last_world: Node = null


func _ready() -> void:
	# 全局视图 / 阴影设置必须在第一帧之前到位；世界级设置在 Main 就绪后补。
	_tier = clampi(int(GameSettings.quality()), 0, PRESETS.size() - 1)
	_apply_globals()


func tier() -> int:
	return _tier


func tier_name() -> String:
	return PRESETS[_tier]["name"]


func preset() -> Dictionary:
	return PRESETS[_tier]


## 切换画质档位。persist=false 供测试 / 样张工具使用，不写玩家存档。
func set_preset(value: int, persist: bool = true) -> void:
	_tier = clampi(value, 0, PRESETS.size() - 1)
	if persist:
		GameSettings.set_quality(_tier)
	_apply_globals()
	_apply_current_world()
	EventBus.render_quality_changed.emit(_tier)


## Main 就绪后调用：把世界级开关落到具体节点上。可重复调用（幂等）。
func apply_to_world(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_last_world = root
	var p := PRESETS[_tier]
	for env_node in root.find_children("*", "WorldEnvironment", true, false):
		var we := env_node as WorldEnvironment
		if we != null and we.environment != null:
			_apply_environment(we.environment)
	for light_node in root.find_children("*", "DirectionalLight3D", true, false):
		var light := light_node as DirectionalLight3D
		if light != null:
			_apply_directional(light)
	for scatter in root.find_children("*", "DecorationScatter", true, false):
		if scatter.has_method("apply_render_quality"):
			scatter.call("apply_render_quality", float(p["grass_range"]), float(p["decor_range"]))
	var post := root.find_child("PostFx", true, false)
	if post != null and post.has_method("apply_render_quality"):
		post.call("apply_render_quality", p)


func _apply_globals() -> void:
	var p := PRESETS[_tier]
	var win := get_tree().root as Window
	if win != null:
		win.use_taa = false
		win.msaa_3d = int(p["msaa"])
		win.screen_space_aa = int(p["screen_aa"])
		win.scaling_3d_mode = int(p["scaling_mode"])
		win.scaling_3d_scale = float(p["scale"])
	# 阴影图集与软阴影滤波是全局设置；低档缩图集，省显存也省光栅化带宽。
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_atlas"]), false)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["shadow_soft"]))


func _apply_current_world() -> void:
	# 运行中切档：优先重扫最近一次注册的世界；没有则用当前场景。
	var root: Node = null
	if _last_world != null and is_instance_valid(_last_world):
		root = _last_world
	else:
		root = get_tree().current_scene
	if root != null:
		apply_to_world(root)


func _apply_environment(env: Environment) -> void:
	var p := PRESETS[_tier]
	env.ssao_enabled = bool(p["ssao"])
	env.ssil_enabled = bool(p["ssil"])
	env.glow_enabled = bool(p["glow"])
	env.volumetric_fog_enabled = bool(p["volumetric"])
	# 环境光遮蔽的半径 / 强度保持场景基线（美术口径统一），档位只开关。
	# 体积雾关闭时恢复一个低密度的「关」状态，避免切档瞬间残留上一档密度。
	if not env.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.0


func _apply_directional(light: DirectionalLight3D) -> void:
	var p := PRESETS[_tier]
	if not light.has_meta("v47_shadow_base"):
		light.set_meta("v47_shadow_base", light.shadow_enabled)
	var wants_shadow: bool = bool(light.get_meta("v47_shadow_base"))
	light.shadow_enabled = wants_shadow
	if not wants_shadow:
		return
	light.directional_shadow_mode = int(p["shadow_mode"])
	light.directional_shadow_max_distance = float(p["shadow_distance"])
	light.directional_shadow_split_1 = float(p["split_1"])
	light.directional_shadow_split_2 = float(p["split_2"])
	light.directional_shadow_split_3 = float(p["split_3"])
	light.directional_shadow_blend_splits = true
	light.directional_shadow_fade_start = float(p["fade_start"])
	# 角直径驱动 PCSS 半影；0 即硬阴影。低档保留一点软化，避免锯齿感。
	light.light_angular_distance = float(p["shadow_angular"])

