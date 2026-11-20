class_name TutorialSystem
extends Node
## ============================================================================
## 新手引导系统（v7 第三人称重写）：与任务链（QuestSystem）互补的入门引导。
## 一条 9 步交互链（v42 起默认且唯一玩家视角 = 俯视角主控）：
## 欢迎 → 移动/瞄准 → 首杀野怪 → 建房屋 → 定居说明 → 俯视角打法（信息步）→ 集结小队 →
## 战斗技巧 → 完成。
##
## 设计约定：
## · 完全由 EventBus 既有信号 + Input 轮询驱动，不侵入任何玩法系统；
## · 每步的视觉呈现（聚光灯遮罩 + 步骤卡）由 HUD 的 TutorialOverlay 监听
##   tutorial_step_changed 渲染，本系统只管状态与推进；
## · 首次启动（Main 作为主场景运行）自动开始；完成 / 跳过写入 user:// 记忆，
##   顶栏「？」按钮可随时重播；测试场景中 Main 是被实例化的子场景，
##   current_scene 不是本树 → 不自动开始（避免污染回归 / 截图体检）。
## ============================================================================

enum State { IDLE, RUNNING, DONE }

const SAVE_PATH := "user://tutorial.cfg"
# 移动步可触发完成的输入（任一按下即算「学会了移动」；Q/E 已是技能/交互，不在列）
const MOVE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"jump", &"sprint",
]


class Step:
	var id: StringName
	var title: String
	var desc: String
	var wait_input: bool = false   # true=等待玩家实际操作（达成自动推进）；false=信息卡（带按钮）
	var focus: Dictionary = {}     # 聚光灯焦点：{ "kind": "none"/"ui_build_card"/"world", "arg": ... }
	var button := ""               # 信息卡按钮文案（空=「下一步」）


	func _init(step_id: StringName, step_title: String, step_desc: String,
			step_wait: bool = false, step_focus: Dictionary = {}, step_button: String = "") -> void:
		id = step_id
		title = step_title
		desc = step_desc
		wait_input = step_wait
		focus = step_focus
		button = step_button


var steps: Array[Step] = []
var state: int = State.IDLE
var current_index: int = 0
var saved_done: bool = false            # 完成 / 跳过记忆（真实玩家只看一次）
var advance_delay: float = 0.55         # 等待步达成后的停顿（给完成音效留空间）；测试可调 0 加速
var _advance_token: int = 0             # 令牌：跳过 / 重播时作废在途的延迟推进
var _completing: bool = false           # 完成中防重入：按住按键时 _process 每帧都会触发完成判定
var _cam_origin := Vector3.INF          # 移动步：步骤开始时的相机位姿基线（米级容差比较）
var _cam_yaw_basis := Vector3.INF       # 基线欧拉角（鼠标转动超过 5° 也算「学会了视角」）
var _hero_suppressed: bool = false      # 引导期间临时关闭主角自动索敌（战术俯瞰下防追野怪跑丢）
var _hero_autofight_saved: bool = true
var _modal_registered: bool = false     # 信息步占用的 UI 模态登记（释放鼠标供玩家点「下一步/开始」按钮）
## v38 关卡系统：剧情关（序章）自带目标流程，不需要沙盒新手引导。
## 由 PrologueDirector 在进入场景的同一帧调用 suppress_autostart() 关掉自动开始。
var autostart_enabled: bool = true


func _ready() -> void:
	add_to_group("tutorial_system")
	_build_steps()
	saved_done = _load_done()
	_connect_signals()
	# 自动开始判定放在稍后帧：子节点 _ready 时 current_scene 可能尚未赋值，
	# 且测试场景（Main 被实例化为子树）要靠首帧后的 current_scene 区分。
	_try_autostart.call_deferred()


func _build_steps() -> void:
	# v22：采集经济屏蔽 → 原「亲手砍树」步换成「讨伐第一只野怪」（金币经济入门）。
	steps = [
		Step.new(&"welcome", "欢迎来到领地",
			"你将以俯视角亲率这座昼夜交替的沙盒城镇：白天讨伐野怪赚金币、建房安民，夜晚野怪集结攻城。\n接下来约 2 分钟，学会最核心的操作——之后左上角的任务卡会继续引路。",
			false, {}, "开始引导"),
		Step.new(&"move", "先迈开腿、学会瞄准",
			"· WASD 移动（按屏幕方向），鼠标指向哪主角就朝哪——鼠标就是瞄准方向\n· Shift 冲刺 · Space 跳跃 · 滚轮平滑推拉镜头\n· P 暂停，B 建造",
			true),
		Step.new(&"first_blood", "讨伐第一只野怪",
			"金币是眼下唯一的建造货币，全靠击杀野怪掉落（走近自动拾取）。\n去城外找一只落单野怪：左键三段连招将它放倒，第三段是重击。",
			true),
		Step.new(&"build_house", "建起第一栋房屋",
			"按 B 进入建造（数字键 1~3 直接换建筑），选「房屋」后准星对准城内空地：\n绿格可放置、红格不可，R 旋转朝向，左键放下。\n房屋会吸引流民入住，觉醒为战士 / 法师 / 刺客 / 游侠小兵。",
			true, { "kind": "ui_build_card", "arg": "house" }),
		Step.new(&"settle", "小兵从哪来？",
			"这座城镇没有兵营——所有小兵都由流民定居觉醒：\n空着的房屋会自动吸引流民，入住即随机成为战士 / 法师 / 刺客 / 游侠。\n多造房屋、留住居民，队伍自然壮大。",
			false, {}, "下一步"),
		# v42 镜头收敛：Player 只剩俯视角主控 → 原「切战术俯瞰」等待步改成信息步，
		# 讲清俯视角下的战斗/指挥键位（等待步会永远等不到模式切换，把玩家卡死）。
		Step.new(&"tactics", "俯视角怎么打",
			"镜头固定在俯视角跟随你：鼠标移到怪身上，左键三段连招，Q 旋风斩 / C 冲锋斩，E 交互。\nG 集结小队、T 集火；B 建造时鼠标落点就是放置点，R 旋转朝向。",
			false, {}, "下一步"),
		Step.new(&"rally", "集结你的部队",
			"按 G：编队小兵跟随你作战（最多 4 名，V 调整编队），再按 G 解散。\n鼠标指向怪物按 T 可令小队集火；白天小兵也会自动出城讨伐野怪。",
			false, {}, "下一步"),
		Step.new(&"combat", "战斗与疗伤",
			"左键三段连招（第三段重击）· Q 旋风斩 · C 冲锋斩。\n击杀获得经验升级；小兵在外面打到血量低于 20% 会自己回酒馆疗伤——记得造一座（数字键 3）。\n夜晚野怪集结攻城，每逢双数夜有头目袭城：建墙护卫、多造房屋壮大民兵！",
			false, {}, "下一步"),
		Step.new(&"finish", "引导完成！",
			"白天赚金币扩军，夜晚守住主城。接下来跟随左上角任务卡经营你的领地！",
			false, {}, "开始经营"),
	]


func _connect_signals() -> void:
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.hero_mode_changed.connect(_on_hero_mode_changed)
	EventBus.game_over.connect(_on_game_over)


# ---- 对外 API ----

func current() -> Step:
	return steps[clampi(current_index, 0, steps.size() - 1)]


## 首杀教学需要一只普通野怪；击杀后的延迟推进期不再补刷。
func needs_combat_target() -> bool:
	return _waiting(&"first_blood") and not _completing


## 信息步是否应锁定主角操控（第三人称下鼠标释放、WASD 暂停——让玩家专心点卡片按钮）。
## HeroController 每帧查询；等待输入步不锁（玩家必须实操才能推进）。
func blocks_control() -> bool:
	return state == State.RUNNING and current() != null and not current().wait_input


## 信息步 ↔ 等待步切换时同步 UI 模态登记：信息步占用鼠标（ui_modal_count+1 → 第三人称
## 释放指针，玩家才能点「开始引导 / 下一步」按钮）；等待步 / 结束后归还（恢复鼠标捕获）。
## 期望值比较式写法：任何切换路径（推进 / 跳过 / 重播 / 游戏结束中止）都不会泄漏计数。
func _sync_input_modal() -> void:
	var want: bool = blocks_control()
	if want and not _modal_registered:
		SelectionManager.ui_modal_count += 1
		_modal_registered = true
	elif not want and _modal_registered:
		SelectionManager.ui_modal_count = maxi(0, SelectionManager.ui_modal_count - 1)
		_modal_registered = false


## 首次进入 / 顶栏重播入口。
func start() -> void:
	current_index = 0
	state = State.RUNNING
	_advance_token += 1
	_completing = false
	_suppress_hero_autofight()
	_sync_input_modal()
	EventBus.tutorial_step_changed.emit(current_index, steps.size())


func restart() -> void:
	start()
	EventBus.game_message.emit("重播新手引导——跟随右下角引导卡操作。", Color(0.7, 0.85, 1.0))


## 信息卡的「下一步」按钮。
func advance() -> void:
	if state != State.RUNNING or current().wait_input:
		return
	_goto(current_index + 1)


func skip() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	_advance_token += 1
	_completing = false
	_restore_hero_autofight()
	_sync_input_modal()
	_mark_done()
	EventBus.tutorial_skipped.emit()
	EventBus.game_message.emit("已跳过引导——顶栏「？」按钮可随时重播。", Color(0.9, 0.85, 0.7))


func finish() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	_advance_token += 1
	_completing = false
	_restore_hero_autofight()
	_sync_input_modal()
	_mark_done()
	EventBus.tutorial_finished.emit()
	EventBus.game_message.emit("新手引导完成！跟随左上角任务卡继续发展城镇。", Color(0.5, 1.0, 0.6))
	AudioManager.play_sfx(&"level_up")


## 游戏结束（基地陷落）时静默中止引导：不写完成记忆（重来一局的新玩家应再次看到引导），
## 只收起浮层，避免引导卡/遮罩压在结算画面上。
func _on_game_over(_victory: bool) -> void:
	abort_silently()


## 静默中止引导（v38 抽出）：不写完成记忆 —— 游戏结束与剧情关接管共用。
func abort_silently() -> void:
	if state != State.RUNNING:
		return
	state = State.DONE
	_advance_token += 1
	_completing = false
	_restore_hero_autofight()
	_sync_input_modal()
	EventBus.tutorial_skipped.emit()


## 剧情关接管（v38）：关掉自动开始，已在跑的直接静默中止。
## 与 skip() 的区别：不写 user://tutorial.cfg —— 玩家之后进沙盒关仍会正常看到引导。
func suppress_autostart() -> void:
	autostart_enabled = false
	abort_silently()


# ---- 主角自动索敌抑制 ----

func _suppress_hero_autofight() -> void:
	var hero := _find_hero()
	if hero == null:
		return
	_hero_autofight_saved = hero.is_auto_fighter
	hero.is_auto_fighter = false   # 引导期间主角安静待在基地（战术俯瞰下不追野怪跑丢）
	_hero_suppressed = true


func _restore_hero_autofight() -> void:
	if not _hero_suppressed:
		return
	_hero_suppressed = false
	var hero := _find_hero()
	if hero != null and is_instance_valid(hero):
		hero.is_auto_fighter = _hero_autofight_saved


func _find_hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero and is_instance_valid(n):
			return n
	return null


func clear_save() -> void:
	saved_done = false
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section("tutorial"):
		cfg.erase_section("tutorial")
		cfg.save(SAVE_PATH)


# ---- 内部推进 ----

func _goto(index: int) -> void:
	if index >= steps.size():
		finish()
		return
	current_index = index
	_completing = false
	_sync_input_modal()
	EventBus.tutorial_step_changed.emit(current_index, steps.size())


## 等待步达成：播音效 → 短暂停顿 → 推进下一步。
## _completing 防重入：按住 W 时 _process 每帧都会命中完成判定，不加锁会连播几十次音效。
## 令牌防竞态：停顿期间若被跳过 / 重播则作废。
func _complete_current() -> void:
	if state != State.RUNNING or _completing:
		return
	_completing = true
	AudioManager.play_sfx(&"quest_done")
	var target := current_index + 1
	_advance_token += 1
	var token := _advance_token
	# ignore_time_scale：入驻提示 / 暂停会把 time_scale 归零，普通定时器会永不触发、卡死推进
	await get_tree().create_timer(advance_delay, true, false, true).timeout
	if state != State.RUNNING or token != _advance_token:
		return
	_goto(target)


func _waiting(step_id: StringName) -> bool:
	return state == State.RUNNING and current().id == step_id


func _try_autostart() -> void:
	if not autostart_enabled:
		return   # v38 剧情关接管：序章有自己的目标流程，不叠沙盒引导
	for _i in 10:
		if get_tree().current_scene != null:
			break
		await get_tree().process_frame
	var cs := get_tree().current_scene
	# 只有当前运行的根场景就是游戏主场景时才自动开始：测试把 Main 实例化为子节点时，
	# current_scene 是测试场景（scene_file_path 不同）→ 保持 IDLE 由测试手动驱动。
	if cs == null or cs.scene_file_path != "res://scenes/main/Main.tscn":
		return
	if saved_done:
		return
	start()


func _process(_delta: float) -> void:
	if state != State.RUNNING or _completing:
		return
	if current().id == &"move":
		_process_move_step()


## Esc 快捷跳过：等待输入步期间鼠标处于捕获态、点不了卡片上的「跳过引导」按钮，
## 键盘是唯一出口。建造模式中的 Esc 归 BuildSystem（退出建造），此时不拦截。
func _unhandled_input(event: InputEvent) -> void:
	if state != State.RUNNING:
		return
	if event.is_action_pressed("cancel") and not SelectionManager.build_mode_active:
		skip()
		get_viewport().set_input_as_handled()


func _process_move_step() -> void:
	# 1) 输入动作（WASD / 跳跃 / 冲刺）——按键即触发，最即时；
	# 2) 相机相对步骤基线的位移 / 转动超过容差——覆盖「只转鼠标视角」的路径
	#    （准星转动也是「学会移动」的一半）。容差与原相机步一致（0.75m / 5°）。
	for action in MOVE_ACTIONS:
		if Input.is_action_pressed(action):
			_complete_current()
			return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var origin := cam.global_position
	var euler := cam.global_transform.basis.get_euler()
	if _cam_origin == Vector3.INF:
		_cam_origin = origin
		_cam_yaw_basis = euler
		return
	if origin.distance_to(_cam_origin) > 0.75 or euler.distance_to(_cam_yaw_basis) > deg_to_rad(5.0):
		_complete_current()


## 砍伐步开局：把第三人称视角转向最近的资源节点（否则新手可能背对树林找不到目标）。
func _focus_camera_on_nearest_resource() -> void:
	var hero := _find_hero()
	var cam := get_viewport().get_camera_3d()
	if hero == null or cam == null or not (cam is ThirdPersonCamera):
		return
	var nearest: Node3D = null
	var best := INF
	for n in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(n):
			continue
		var d: float = (n as Node3D).global_position.distance_to(hero.global_position)
		if d < best:
			best = d
			nearest = n
	if nearest == null:
		return
	var to := nearest.global_position - hero.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	var tp := cam as ThirdPersonCamera
	tp.yaw = atan2(-to.x, -to.z)
	tp.pitch = -0.2


# ---- 信号累计 ----

## 首杀步（v22，替代原「亲手砍树」步）：主角（或其小兵）亲手击杀任一野怪即达成。
func _on_enemy_died(_enemy: Node, killer: Node) -> void:
	if _waiting(&"first_blood") and (killer is Hero or killer is Soldier):
		_complete_current()


func _on_building_placed(building: Node, _cell: Vector2i) -> void:
	if _waiting(&"build_house") and building != null and is_instance_valid(building) \
			and (building as Building).def.id == &"house":
		_complete_current()


func _on_hero_mode_changed(active: bool) -> void:
	# 原「战术俯瞰」步的达成条件（切出主控视角）。v42 该步已改成信息步，
	# 这里补 wait_input 判定：脚本 / 截图工具切模式时不能把信息步直接顶掉。
	if _waiting(&"tactics") and current().wait_input and not active:
		_complete_current()


# ---- 完成记忆 ----

func _load_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	return bool(cfg.get_value("tutorial", "done", false))


func _mark_done() -> void:
	saved_done = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("tutorial", "done", true)
	cfg.save(SAVE_PATH)
