class_name DecorationDissolveSystem
extends Node
## ============================================================================
## 主角周围「半球消散」判定区（v13，参考《逃离鸭科夫》）。
##
## 做什么：每帧把主角（以及相机）的世界位置与判定半径写进 **全局 shader 参数**，
## 装饰类 shader（草 / 树 / 石头 / 水草，见 assets/shaders/decor_dissolve.gdshaderinc）
## 据此在半球内按噪声消散，把视线让出来；球外装饰完全不受影响。
##
## 为什么走全局 shader 参数而不是逐个材质赋值：
##   装饰是 ~300 个 MultiMesh 分块（光草就 65000 株），逐块写 uniform 既慢又容易漏；
##   全局参数只需一次 `RenderingServer.global_shader_parameter_set`，所有材质自动同步，
##   新增装饰 shader 只要 #include 那份 gdshaderinc 就自动纳入同一判定。
##
## 【必须注册为 Autoload（project.godot [autoload] DecorationDissolve）】
##   global uniform 在**任何引用它的材质被加载之前**就必须注册，否则引擎会打印
##   「Shader uses global parameter 'x', but it was removed at some point」并且材质渲染不正确。
##   场景内建节点永远晚于 Main.tscn 里的材质解析，因此只能靠 autoload 抢在场景之前。
##
## 判定球心取主角**胸口高度**（不是脚底）：半球才真正罩住挡视线的植被。
## ============================================================================

const PARAM_HERO_POS := &"hero_dissolve_pos"
const PARAM_CAM_POS := &"camera_dissolve_pos"
const PARAM_RADIUS := &"hero_dissolve_radius"
const PARAM_INNER := &"hero_dissolve_inner"
const PARAM_STRENGTH := &"hero_dissolve_strength"
const PARAM_CAM_RADIUS := &"camera_dissolve_radius"
const PARAM_ALPHA_MIX := &"decor_dissolve_alpha_mix"
const PARAM_DITHER := &"decor_dissolve_dither"

const DEFAULT_RADIUS: float = 5.6      # 外半径：到这为止完全恢复
const DEFAULT_INNER: float = 2.2       # 内半径：到这为止完全消散
const DEFAULT_CAM_RADIUS: float = 2.6  # 相机副球（相机贴进植被时让开）
const DEFAULT_ALPHA_MIX: float = 1.0   # 1 = 纯按判定值淡出（定稿观感，最干净）
const DEFAULT_DITHER: float = 0.0      # 阈值抖动强度（0 = 不抖；调高会偏「点半调」）

var hero: Node3D = null                # 主角（懒查找 player_unit 组）
var camera: Camera3D = null            # 当前视角相机（懒查找）
var radius: float = DEFAULT_RADIUS
var inner_radius: float = DEFAULT_INNER
var cam_radius: float = DEFAULT_CAM_RADIUS
var alpha_mix: float = DEFAULT_ALPHA_MIX  # 消散区块内的半透明比例（0=纯抖动 / 1=纯淡出）
var dither: float = DEFAULT_DITHER        # 阈值抖动强度
var strength: float = 1.0              # 0 = 关闭消散；>0 生效（可做整体开关/淡入）
var enabled: bool = true

var _registered: bool = false
var _last_hero_pos: Vector3 = Vector3.INF
var _last_cam_pos: Vector3 = Vector3.INF


func _ready() -> void:
	_register_globals()
	add_to_group("decoration_dissolve")
	call_deferred("_resolve_refs")


## 注册全局 shader 参数（一次性，autoload 启动即执行 = 早于任何场景材质加载）。
## 缺任一类型都会让 include 了 decor_dissolve 的 shader 编译失败，
## 所以这里的参数名必须与 assets/shaders/decor_dissolve.gdshaderinc 里声明的完全一致。
func _register_globals() -> void:
	if _registered:
		return
	if not RenderingServer.has_method("global_shader_parameter_add"):
		push_warning("DecorationDissolveSystem: 当前引擎不支持全局 shader 参数，消散关闭")
		enabled = false
		return
	var existing: Array = RenderingServer.global_shader_parameter_get_list()
	# 已存在（例如编辑器里手工加过 / 热重载）就不再重复注册
	if not existing.has(PARAM_HERO_POS):
		RenderingServer.global_shader_parameter_add(PARAM_HERO_POS, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	if not existing.has(PARAM_CAM_POS):
		RenderingServer.global_shader_parameter_add(PARAM_CAM_POS, RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	if not existing.has(PARAM_RADIUS):
		RenderingServer.global_shader_parameter_add(PARAM_RADIUS, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, DEFAULT_RADIUS)
	if not existing.has(PARAM_INNER):
		RenderingServer.global_shader_parameter_add(PARAM_INNER, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, DEFAULT_INNER)
	if not existing.has(PARAM_STRENGTH):
		RenderingServer.global_shader_parameter_add(PARAM_STRENGTH, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	if not existing.has(PARAM_CAM_RADIUS):
		RenderingServer.global_shader_parameter_add(PARAM_CAM_RADIUS, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, DEFAULT_CAM_RADIUS)
	if not existing.has(PARAM_ALPHA_MIX):
		RenderingServer.global_shader_parameter_add(PARAM_ALPHA_MIX, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, DEFAULT_ALPHA_MIX)
	if not existing.has(PARAM_DITHER):
		RenderingServer.global_shader_parameter_add(PARAM_DITHER, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, DEFAULT_DITHER)
	_registered = true
	_push_all(true)


func _resolve_refs() -> void:
	# 注意：`player_unit` 组里除了主角还有 BaseCore（主城也是玩家侧单位）——
	# 必须按 Hero 类型筛，否则消散判定区会挂在主城上而不是主角身上。
	if hero == null or not is_instance_valid(hero) or not (hero is Hero):
		hero = null
		for n in get_tree().get_nodes_in_group("player_unit"):
			if n is Hero:
				hero = n as Hero
				break
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d() if is_inside_tree() else null


func _process(_delta: float) -> void:
	if not enabled or not _registered:
		return
	if hero == null or not is_instance_valid(hero):
		_resolve_refs()
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d() if is_inside_tree() else null

	# 球心取胸口高度：判定区才真正罩住挡视线的草丛/树冠
	var hero_pos: Vector3 = hero.global_position + Vector3.UP * 1.0 if hero != null else Vector3.ZERO
	var cam_pos: Vector3 = camera.global_position if camera != null else hero_pos
	if hero_pos.distance_squared_to(_last_hero_pos) < 0.0001 and cam_pos.distance_squared_to(_last_cam_pos) < 0.0001:
		return   # 主角与相机都没动，省掉一次全局参数写入
	_last_hero_pos = hero_pos
	_last_cam_pos = cam_pos
	_push_all(false)


func _push_all(_force: bool) -> void:
	RenderingServer.global_shader_parameter_set(PARAM_RADIUS, radius)
	RenderingServer.global_shader_parameter_set(PARAM_INNER, minf(inner_radius, radius - 0.1))
	RenderingServer.global_shader_parameter_set(PARAM_CAM_RADIUS, cam_radius)
	RenderingServer.global_shader_parameter_set(PARAM_ALPHA_MIX, alpha_mix)
	RenderingServer.global_shader_parameter_set(PARAM_DITHER, dither)
	RenderingServer.global_shader_parameter_set(PARAM_STRENGTH, strength if enabled else 0.0)
	RenderingServer.global_shader_parameter_set(PARAM_HERO_POS, _last_hero_pos if _last_hero_pos.is_finite() else Vector3.ZERO)
	RenderingServer.global_shader_parameter_set(PARAM_CAM_POS, _last_cam_pos if _last_cam_pos.is_finite() else Vector3.ZERO)


## 运行时调参（调试/设置面板可用）。
func configure(p_radius: float, p_inner: float, p_cam_radius: float) -> void:
	radius = maxf(p_radius, 0.5)
	inner_radius = clampf(p_inner, 0.0, radius - 0.1)
	cam_radius = maxf(p_cam_radius, 0.0)
	_push_all(true)


func set_enabled(on: bool) -> void:
	enabled = on
	_push_all(true)


# ---- 供测试/调试查询判定值（与 shader 内 dissolve_zone 同一套数学，GDScript 侧复刻）----

## 某个世界坐标的「消散进度」：0 = 完全可见，1 = 完全消散。
func dissolve_amount_at(world_pos: Vector3) -> float:
	if not enabled:
		return 0.0
	var d := world_pos - (hero.global_position + Vector3.UP * 1.0 if hero != null else Vector3.ZERO)
	var sphere_d := Vector3(d.x, d.y * 0.75, d.z).length()
	var t_hero := 1.0 - smoothstep(inner_radius, radius, sphere_d)
	var t_cam := 0.0
	if camera != null and is_instance_valid(camera):
		t_cam = (1.0 - smoothstep(0.0, cam_radius, world_pos.distance_to(camera.global_position))) * 0.85
	return maxf(t_hero, t_cam) * strength


## 判定区是否覆盖某点（外半径内即算覆盖）。
func covers(world_pos: Vector3) -> bool:
	return dissolve_amount_at(world_pos) > 0.001
