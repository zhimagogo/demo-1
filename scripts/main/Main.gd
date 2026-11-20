extends Node
## ============================================================================
## 游戏根节点：引导启动。
## 世界树已搬入 Main.tscn（环境/灯光/地面/网格/主城/资源点/容器/系统/相机/主角操控
## 均在场景里可见、可编辑）。本脚本只负责：初始资源、主城逻辑层（占格/模型/信号）、
## 动态单位（主角）与 HUD 实例化，以及全局快捷键。
## ============================================================================

# 世界节点引用——@onready 在 _ready() 体执行前求值，此时整棵子树已就绪
@onready var world_root: Node3D = $WorldRoot
@onready var grid: GridSystem = $WorldRoot/GridSystem
@onready var city: CitySystem = $WorldRoot/CitySystem
@onready var build_system: BuildSystem = $WorldRoot/BuildSystem
@onready var camera: IsometricCamera = $WorldRoot/IsometricCamera
@onready var tp_camera: ThirdPersonCamera = $WorldRoot/ThirdPersonCamera
@onready var base_core: StaticBody3D = $WorldRoot/BaseCore
@onready var buildings: Node3D = $WorldRoot/Buildings
@onready var pawns: Node3D = $WorldRoot/Pawns
@onready var enemies: Node3D = $WorldRoot/Enemies
@onready var resource_nodes: Node3D = $WorldRoot/ResourceNodes
@onready var pawn_spawner = $WorldRoot/PawnSpawner
@onready var hero_controller: HeroController = $WorldRoot/HeroController
@onready var weather: WeatherSystem = $WorldRoot/WeatherSystem

var hero: Hero
var occlusion_silhouette: HeroOcclusionSilhouette


func _ready() -> void:
	# 应用全局设置（窗口/同步/音量/灵敏度）。Main 作为子场景被测试实例化时
	# 不动窗口显示（避免覆盖截图回归的窗口尺寸），音频与灵敏度始终应用。
	GameSettings.apply_all(get_tree().current_scene == self)

	# 初始资源
	var starting := GameDefs.starting_resources()
	for id in starting:
		ResourceManager.register(id, starting[id])

	# 时间系统启动（开放式沙盒：仅昼夜时钟，无入侵倒计时）
	TimeManager.begin(6)

	# 单位出生器：容器已在场景里，运行时只传引用
	pawn_spawner.configure(pawns, enemies)

	# 主城逻辑层：占格 + 模型挂载 + 生命信号（皮在场景里，这里只挂逻辑）
	_setup_base_core()

	# 动态单位 / HUD
	_spawn_hero()
	_setup_hud()
	# 主角被建筑遮挡时的轮廓透视（v12 需求 5）：纯代码自建，不动场景树
	_setup_occlusion_silhouette()
	# v42 镜头收敛：默认且唯一的玩家视角 = 俯视角主控（等距相机跟随主角）。
	# enter_hero_mode 只留给脚本 / 旧测试取景；玩家侧入口已屏蔽（见 SelectionManager）。
	hero_controller.enter_default_view_mode()
	# v38 关卡分流（最后一步：世界、主角、HUD 都已就绪，剧情关才好接管）
	_setup_level()
	# v47 画质分级：等世界节点全部就绪后，把 Environment / 阴影 / 草装饰视距 / PostFX
	# 一次性落到具体节点上。延迟调用，保证 DecorationScatter 的 MultiMesh 已建成。
	var quality := get_node_or_null("/root/RenderQuality")
	if quality != null:
		quality.call_deferred("apply_to_world", world_root)
	# v17 去冗余：旧版在这里连发 4 条「操作教学」日志刷屏消息日志（且首条与
	# HeroController 进模式的提示一字不差地重复）。键位教学现在只留在
	# 「视角切换即时提示 + HeroPanel 小队行 + 建造菜单标题 + 新手引导」各一处，
	# 消息日志还给真正发生的事件（夜袭 / 定居 / 达成目标）。


# ---- 主城逻辑层（视觉在场景里，这里只挂逻辑）----
func _setup_base_core() -> void:
	# 主城占 4×4 格（16 格）：以主城中心（世界原点）为正中心预留，禁止在其上建造。
	# 原点落在 4 格交界处，故取主城所在格再向左上偏移 2 格，使 4×4 正好以原点为中心。
	var base_cell := grid.world_to_grid(base_core.global_position) - Vector2i(2, 2)
	grid.place(base_cell, Vector2i(4, 4), base_core)

	# 主城视觉：Medieval-Hexagon 城堡（castle）。加载成功则隐藏上面的圆柱占位皮；
	# 加载失败保留圆柱（逻辑不受影响）。v43：王城扩到 52×52m，城堡模型 scale 3.5→4.0
	# 做视觉提档（碰撞 / 4×4 占格不变）。
	var castle_rig := base_core.get_node_or_null("ModelRig") as BuildingModelRig
	if castle_rig != null and castle_rig.setup("res://assets/_PLACEHOLDER/medieval_hexagon_buildings/building_castle_blue.gltf", 4.0, 0.0, 0.0):
		var ph := base_core.get_node_or_null("PlaceholderMesh")
		if ph != null:
			ph.visible = false

	# 主城生命与 GameManager 同步（HUD 读 GameManager.player_base_health）
	var health := base_core.get_node_or_null("HealthComponent") as HealthComponent
	if health != null:
		GameManager.player_base_health = int(health.current_hp)
		health.health_changed.connect(_on_base_health_changed)
		health.died.connect(_on_base_died)


func _on_base_health_changed(current: float, _max_hp: float) -> void:
	GameManager.player_base_health = int(current)


func _on_base_died() -> void:
	GameManager.request_game_over(false)


# ---- 动态单位 ----
func _spawn_hero() -> void:
	# 主城占地 4×4（碰撞体 r=4），英雄须生在主城之外：原点+对角 5m（距原点 ~7m > r=4）。
	hero = pawn_spawner.spawn_hero(Vector3(5.0, 0.0, 5.0))
	if hero_controller != null:
		hero_controller.hero = hero


# ---- HUD ----
func _setup_hud() -> void:
	var hud: Node = load("res://scenes/ui/HUD.tscn").instantiate()
	add_child(hud)


# ---- v38 关卡分流 ----
## 这一局按哪一关跑由 LevelRuntime 决定（关卡地图/主菜单入口写入；空选择 = 沙盒关，
## 因此所有直接实例化 Main.tscn 的旧测试与工具脚本行为完全不变）。
## 目前只有序章需要接管：挂 PrologueDirector，由它把世界切成剧情关舞台
## （停刷怪/流民/建造 + 冻结昼夜 + 刷匪徒 + 目标链 + 结算）。
## 沙盒关（测试关卡）不做任何事——就是现在这套开放玩法。
func _setup_level() -> void:
	var level := LevelRuntime.current_level()
	if level == null or level.kind != LevelDef.Kind.PROLOGUE:
		return
	var director := PrologueDirector.new()
	director.name = "PrologueDirector"
	world_root.add_child(director)
	director.setup(world_root, self)


# ---- 主角遮挡剪影（v12 需求 5）：代码自建，挂在 WorldRoot 下 ----
func _setup_occlusion_silhouette() -> void:
	occlusion_silhouette = HeroOcclusionSilhouette.new()
	occlusion_silhouette.setup(world_root, tp_camera, hero)
	world_root.add_child(occlusion_silhouette)


# ---- 全局快捷键 ----
func _pause_menu() -> PauseMenu:
	return get_tree().get_first_node_in_group("pause_menu") as PauseMenu


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.phase == GameManager.Phase.GAME_OVER:
		return
	var menu := _pause_menu()
	var party_panel := get_tree().get_first_node_in_group("party_panel") as CitizenPanel
	# V 市民管理界面（v25，由编队界面升级）：开着时 V / Esc 由界面自己收；暂停菜单开着时
	# V 不抢；新手引导进行中不响应（引导的 Esc 归快捷跳过，避免界面互抢）
	if event.is_action_pressed("party_menu"):
		if menu != null and menu.is_open:
			return
		var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
		if tutorial != null and tutorial.state == TutorialSystem.State.RUNNING:
			return
		# 技能树面板叠在市民管理之上：V 归它（先收到输入、自行关闭并标记已处理）
		var tree_panel := get_tree().get_first_node_in_group("skill_tree_panel")
		if tree_panel != null and tree_panel.get("is_open"):
			return
		if party_panel != null:
			if party_panel.is_open:
				party_panel.close()
			elif not SelectionManager.build_mode_active:
				party_panel.open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_toggle"):
		# 编队界面开着时 P 不重复暂停（界面已占用模态与倍速）
		if party_panel != null and party_panel.is_open:
			return
		# Esc 暂停菜单开着时按 P = 关闭菜单继续（两种出口行为一致）
		if menu != null and menu.is_open:
			menu.close()
		else:
			var is_paused := TimeManager.time_scale <= 0.0
			GameManager.set_paused(not is_paused)
	# 倍速键在 Esc 菜单打开时不抢速度（菜单关闭时统一恢复原倍速）
	# v8：数字键 1~6 让位给「直接选建筑」（BuildSystem），调速改为 - / = 循环 1→2→3 倍
	elif menu != null and menu.is_open:
		pass
	elif event.is_action_pressed("speed_up"):
		_cycle_game_speed(1)
	elif event.is_action_pressed("speed_down"):
		_cycle_game_speed(-1)
	elif event.is_action_pressed("toggle_grid"):
		grid.toggle_debug()
	elif event.is_action_pressed("focus_base"):
		# 操控模式：转身看向城堡；战术俯瞰：镜头平移回主城
		if SelectionManager.hero_mode_active:
			hero_controller.face_base()
		else:
			camera.focus_on(Vector3.ZERO)
	elif event.is_action_pressed("debug_weather") and OS.is_debug_build():
		# 调试热键（F6）：晴 → 多云 → 雨 循环，供真机快速验证天气链路
		weather.debug_cycle()


## 倍速循环：- / = 在 1×→2×→3× 间步进（钳制两端）；暂停态（×0）按加速直接回 1×。
func _cycle_game_speed(direction: int) -> void:
	var speeds := [1.0, 2.0, 3.0]
	var current := TimeManager.time_scale
	if current <= 0.0:
		if direction > 0:
			TimeManager.set_speed(1.0)
			EventBus.game_message.emit("游戏速度 ×1", Color(0.7, 0.85, 1.0))
		return
	var idx := 0
	for i in speeds.size():
		if absf(current - speeds[i]) < 0.01:
			idx = i
			break
	var next := clampi(idx + direction, 0, speeds.size() - 1)
	if next != idx:
		TimeManager.set_speed(speeds[next])
		EventBus.game_message.emit("游戏速度 ×%d" % int(speeds[next]), Color(0.7, 0.85, 1.0))


# Tab 同时绑定到 Godot 默认的 UI 焦点切换键 ui_focus_next：HUD 上任意按钮（如建造菜单）一旦
# 获得焦点，Tab 就会在 GUI 阶段被焦点系统消费，永远到不了 _unhandled_input。故必须在 GUI 之前的
# _input 阶段捕获，并 set_input_as_handled 阻止焦点跳转 —— 这样 Tab 才能稳定切视角模式。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hero_mode"):
		# Esc 暂停菜单打开时锁定视角模式切换（菜单底下不动相机/编组）
		var menu := _pause_menu()
		if menu != null and menu.is_open:
			get_viewport().set_input_as_handled()
			return
		if GameManager.phase != GameManager.Phase.GAME_OVER and hero_controller != null:
			# v42：玩家只开放俯视角主控 → 单模式时 cycle_view_mode 不换镜头，只提示（不视为失灵）
			hero_controller.cycle_view_mode()
		get_viewport().set_input_as_handled()
