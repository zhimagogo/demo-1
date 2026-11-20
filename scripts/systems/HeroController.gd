class_name HeroController
extends Node
## ============================================================================
## 主角操控中枢（group "hero_controller"，由 Main 挂到 WorldRoot）。
## 三种视角 / 操控模式（实现保留；v42 起玩家只开放俯视角主控，见 SelectionManager
## 的 VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED）：
## ① HERO     第三人称亲征：鼠标捕获视角 + WASD 相对相机 + 左键连招 +
##            Q/C 技能 + E 准星交互；Shift 冲刺、Space 跳跃、滚轮拉相机距离
## ② TACTICAL 战术俯瞰 RTS：等距相机自由平移，框选 / 右键下令 / 点击建造菜单；
##            主角退为基础 AI 单位且【不自动索敌】，完全等玩家下令（右键指派 / 切回主控）
## ③ TOPDOWN  俯视角主控（v42 默认且玩家唯一可用的模式）：等距相机跟随主角、鼠标释放；
##            WASD 按屏幕方向移动、鼠标落点瞄准（双摇杆）、左键连招、E 鼠标处交互、
##            G 集结、T 集火
## 模式交接（编队 / 选择 / 相机 / 主角状态机）全部收口在 set_view_mode()。
## ============================================================================

const INTERACT_RANGE: float = 6.0     # E 交互距离（命中点距主角）
const PROMPT_RANGE: float = 9.0       # 准星提示距离
const RAY_LENGTH: float = 48.0        # 瞄准射线长度
const SPRINT_MULT: float = 1.5        # 冲刺速度倍率
const JUMP_SPEED: float = 7.2         # 起跳速度（重力 24 → 跳高约 1.1m）
const PROMPT_INTERVAL: float = 0.12   # 瞄准提示刷新节流
const AIM_SNAP_PX: float = 64.0       # 瞄准吸附的屏幕像素半径（亲征=屏幕中心 / 俯视主控=鼠标）
const AIM_MAX_DEPTH: float = 60.0     # 瞄准怪物的最大距离（米，从第三人称相机起算）
const TOPDOWN_AIM_DEADZONE: float = 1.2  # 俯视主控朝向死区：鼠标落点距主角小于此值时随移动方向

var hero: Hero
var camera: ThirdPersonCamera
var iso_camera: IsometricCamera
var _tutorial: TutorialSystem            # 引导系统缓存（信息步锁定操控用；可空）

var _prompt_timer: float = 0.0
var _aim_enemy: Node = null              # 准星当前瞄准的怪物（红描边）
var _focus_marker: FocusMarker = null    # 集火箭头（目标头顶倒锥，v11）


func _ready() -> void:
	add_to_group("hero_controller")
	call_deferred("_resolve_refs")


func _resolve_refs() -> void:
	if hero == null:
		for h in get_tree().get_nodes_in_group("player_unit"):
			if h is Hero:
				hero = h
				break
	if camera == null:
		var root := get_parent()
		camera = root.get_node_or_null("ThirdPersonCamera") as ThirdPersonCamera
	if iso_camera == null:
		var root := get_parent()
		iso_camera = root.get_node_or_null("IsometricCamera") as IsometricCamera
	if _tutorial == null:
		_tutorial = get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem


## 引导信息步（欢迎/说明卡）期间锁定操控：鼠标已释放给卡片按钮，主角也不应乱动。
func _control_locked() -> bool:
	if _tutorial == null:
		_tutorial = get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	return _tutorial != null and _tutorial.blocks_control()


# ---- 视角：鼠标捕获期间转向（_input 阶段，先于 UI / 其他处理；仅第三人称亲征）----

func _input(event: InputEvent) -> void:
	if SelectionManager.view_mode != SelectionManager.ViewMode.HERO or camera == null:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera.add_look_delta(event.relative)


# ---- 动作输入 ----

func _unhandled_input(event: InputEvent) -> void:
	if not SelectionManager.hero_mode_active or hero == null or hero.is_dead_flag:
		return
	if _control_locked():
		return   # 引导信息步：鼠标在卡片上，动作输入全部让位
	if event.is_action_pressed("hero_attack"):
		# 建造模式下左键归 BuildSystem（放置建筑），不触发普攻
		if SelectionManager.build_mode_active:
			return
		hero.request_basic_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hero_skill_1"):
		hero.request_skill(0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hero_skill_2"):
		hero.request_skill(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("squad_focus_fire"):
		_toggle_focus_fire()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("squad_rally"):
		_toggle_squad_rally()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if camera == null or iso_camera == null:
		_resolve_refs()
		if camera == null or iso_camera == null:
			return
	if not SelectionManager.hero_mode_active or hero == null:
		return

	# 鼠标模式校准：操控中且无 UI 模态且未暂停 → 捕获；否则释放（招募菜单 / 入驻提示 / 暂停 / 结算 / 引导信息卡）
	_sync_mouse_mode()

	if hero.is_dead_flag:
		return

	# 引导信息步：清空输入、主角站定（等待步恢复操控，玩家实操推进引导）
	if _control_locked():
		hero.desired_velocity = Vector3.ZERO
		return

	# 移动基底随模式分流：
	# - HERO：相机视线基底（W = 远离镜头，A/D = 屏幕左右），朝向 = 相机前方（可倒退跑）
	# - TOPDOWN：等距相机屏幕方向基底（复用 IsometricCamera.input_to_world_dir，
	#   随 Q/E 旋转过的视角自适应），朝向 = 鼠标落点（双摇杆：跑一处、打另一处）
	var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := Vector3.ZERO
	if SelectionManager.view_mode == SelectionManager.ViewMode.HERO:
		var fwd := camera.forward_flat()
		var right := fwd.cross(Vector3.UP)
		dir = fwd * -input_vec.y + right * input_vec.x
		hero.aim_dir = fwd
	else:
		dir = iso_camera.input_to_world_dir(input_vec)
		hero.aim_dir = _topdown_aim_dir(dir)
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	var speed: float = hero.move_speed
	if Input.is_action_pressed("sprint"):
		speed *= SPRINT_MULT
	hero.desired_velocity = dir * speed
	# 跳跃（HeroIdleState 的重力逻辑消费）
	if Input.is_action_just_pressed("jump"):
		hero.request_jump()

	# 瞄准提示（节流）：亲征喂准星 UI；俯视主控喂鼠标处目标（准星隐藏，红描边/集火仍生效）
	_prompt_timer -= delta
	if _prompt_timer <= 0.0:
		_prompt_timer = PROMPT_INTERVAL
		_refresh_crosshair_prompt()


## 俯视角主控的朝向：优先指向鼠标落点（等距相机屏幕→地面投射），鼠标贴身（< 死区）
## 时随移动方向——否则鼠标停在主角脚边会让朝向抖动。
func _topdown_aim_dir(move_dir: Vector3) -> Vector3:
	if iso_camera == null or hero == null:
		return move_dir
	var point := iso_camera.screen_to_ground(get_viewport().get_mouse_position())
	var to_mouse := point - hero.global_position
	to_mouse.y = 0.0
	if to_mouse.length() > TOPDOWN_AIM_DEADZONE:
		return to_mouse.normalized()
	if move_dir.length_squared() > 0.0001:
		return move_dir.normalized()
	return hero.aim_dir


func _sync_mouse_mode() -> void:
	# 指针捕获仅第三人称亲征；俯视角主控必须保持释放（鼠标落点瞄准 / UI 点击都靠自由指针）
	var want_captured: bool = SelectionManager.view_mode == SelectionManager.ViewMode.HERO \
		and TimeManager.time_scale > 0.0 \
		and GameManager.phase != GameManager.Phase.GAME_OVER \
		and SelectionManager.ui_modal_count <= 0
	if want_captured and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not want_captured and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---- 瞄准射线 ----

## 当前瞄准用相机：亲征 = 第三人称（屏幕中心准星）；俯视角主控 = 等距相机（鼠标位置）。
func _aim_camera() -> Camera3D:
	if SelectionManager.view_mode == SelectionManager.ViewMode.HERO:
		return camera
	return iso_camera


## 瞄准射线查询（世界几何 layer 1 + 拾取区）。返回 { collider, position, normal }，未命中返回空字典。
func crosshair_hit() -> Dictionary:
	var cam := _aim_camera()
	if cam == null:
		return {}
	var origin: Vector3
	var dir_vec: Vector3
	if cam is ThirdPersonCamera:
		var ray: Dictionary = (cam as ThirdPersonCamera).aim_ray()
		origin = ray["from"]
		dir_vec = ray["dir"]
	else:
		# 俯视角主控：从等距相机过鼠标位置做地面/拾取区投射
		var sp := get_viewport().get_mouse_position()
		origin = cam.project_ray_origin(sp)
		dir_vec = cam.project_ray_normal(sp)
	var space := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir_vec * RAY_LENGTH)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 1 | 8   # world + structure：不撞单位（layer 5），瞄准穿透人群
	var hit := space.intersect_ray(query)
	return hit if not hit.is_empty() else {}


## 瞄准的怪物：HERO = 敌人胸口投影到屏幕后取离屏幕中心最近的一个（阈值 AIM_SNAP_PX）；
## TOPDOWN = 取离鼠标位置最近的一个。且深度不能超过世界几何命中点（被墙 / 树挡住的怪不算瞄准到）。
func _find_aim_enemy(world_hit: Dictionary) -> Node:
	var cam := _aim_camera()
	if cam == null:
		return null
	var cam_pos: Vector3 = cam.global_position
	# 等距相机悬在高空（默认 44m），从相机起算的深度天然偏大，按其目标距离放宽上限
	var max_depth: float = AIM_MAX_DEPTH
	if cam is IsometricCamera:
		max_depth = maxf(AIM_MAX_DEPTH, (cam as IsometricCamera).target_distance * 1.6)
	# 世界几何挡板深度（无命中 = 射线全长）
	var occlude_dist: float = RAY_LENGTH
	if not world_hit.is_empty():
		occlude_dist = cam_pos.distance_to(world_hit["position"])
	var center: Vector2 = get_viewport().get_mouse_position() \
			if SelectionManager.view_mode != SelectionManager.ViewMode.HERO \
			else get_viewport().get_visible_rect().size * 0.5
	var best: Node = null
	var best_score: float = AIM_SNAP_PX * 3.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Pawn) or not is_instance_valid(e) or (e as Pawn).is_dead_flag:
			continue
		var chest: Vector3 = (e as Node3D).global_position + Vector3.UP * 1.0
		if cam.is_position_behind(chest):
			continue
		var depth: float = cam_pos.distance_to(chest)
		if depth > max_depth or depth > occlude_dist + 0.6:
			continue   # 太远 / 被世界几何遮挡
		var screen: Vector2 = cam.unproject_position(chest)
		var px: float = screen.distance_to(center)
		if px > AIM_SNAP_PX:
			continue
		var score: float = px + depth * 0.15   # 屏幕距离优先，同分取近者
		if score < best_score:
			best_score = score
			best = e
	return best


## 瞄准 / 集火红描边：aim 与 focus 任一命中即高亮；变化时切换。
## 集火目标额外获得头顶箭头（FocusMarker 自跟踪 + 自隐藏）。
func _update_enemy_highlights() -> void:
	var want: Array = []
	if _aim_enemy != null and is_instance_valid(_aim_enemy):
		want.append(_aim_enemy)
	var focus_t: Node3D = null
	if hero != null and hero.is_focus_alive():
		want.append(hero.focus_target)
		focus_t = hero.focus_target as Node3D
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Pawn):
			continue
		(e as Pawn).set_aim_highlight(want.has(e))
	_sync_focus_marker(focus_t)


## 集火箭头：懒创建一个 FocusMarker 挂 WorldRoot，指派/撤下目标由它自跟踪。
func _sync_focus_marker(target: Node3D) -> void:
	if target == null:
		if _focus_marker != null:
			_focus_marker.target = null
		return
	if _focus_marker == null:
		var world := get_parent() as Node3D
		if world == null:
			return
		_focus_marker = FocusMarker.new()
		_focus_marker.name = "FocusMarker"
		world.add_child(_focus_marker)
	_focus_marker.target = target


## 命中体 → 关联实体（兵营拾取区 → Building；其余原样返回）。
func _hit_owner(hit: Dictionary) -> Node:
	var c: Object = hit.get("collider")
	if c == null:
		return null
	var node := c as Node
	if node is Area3D:
		var parent := node.get_parent()
		if parent != null and parent.is_in_group("building"):
			return parent
	return node


func _refresh_crosshair_prompt() -> void:
	var target: Node = null
	var prompt := ""
	var kind: StringName = &""
	var hit := crosshair_hit()
	if not hit.is_empty() and hero != null:
		var pos: Vector3 = hit["position"]
		var dist_to_hero: float = pos.distance_to(hero.global_position)
		var owner_node := _hit_owner(hit)
		if owner_node != null:
			# v22：采集经济暂时屏蔽——树/石不再给「挥砍采集」提示（保留为场景障碍/景观）
			if owner_node.is_in_group("resource_node") and GameDefs.HARVEST_INCOME_ENABLED \
					and dist_to_hero <= PROMPT_RANGE:
				var rn := owner_node as ResourceNode
				var res_name := "木材" if rn.yield_resource == GameDefs.WOOD else "石料"
				target = owner_node
				kind = &"resource"
				prompt = "左键 挥砍采集 · %s" % res_name
			elif owner_node.is_in_group("building"):
				var b := owner_node as Building
				target = owner_node
				kind = &"building"
				prompt = b.def.display_name
				# v26 驯龙：龙园给专用交互提示（E 打开驯龙界面）
				if b.def.is_dragon_garden and dist_to_hero <= PROMPT_RANGE:
					prompt = "龙园 · [E] 驯龙"
	# 怪物瞄准优先于背景：准星附近的怪 → 红准星 + 集火提示（v10）
	var enemy := _find_aim_enemy(hit)
	if enemy != null:
		target = enemy
		kind = &"enemy"
		var e_name: String = (enemy as Pawn).get_display_name()
		if hero != null and hero.focus_target == enemy:
			prompt = "集火中 · %s · [T] 取消" % e_name
		else:
			prompt = "%s · [T] 集火" % e_name
	_aim_enemy = enemy
	_update_enemy_highlights()
	EventBus.crosshair_target_changed.emit(target, prompt, kind)


# ---- E 交互 ----

func _try_interact() -> void:
	var hit := crosshair_hit()
	if hit.is_empty() or hero == null:
		return
	var pos: Vector3 = hit["position"]
	if pos.distance_to(hero.global_position) > INTERACT_RANGE:
		EventBus.game_message.emit("走近一点再交互", Color(0.9, 0.85, 0.7))
		return
	# v26 驯龙：对龙园按 E → 打开驯龙界面（DragonMenu 监听信号开合，含金币解锁 / 出战召回）
	var owner_node := _hit_owner(hit)
	if owner_node != null and owner_node.is_in_group("building"):
		var b := owner_node as Building
		if b.def != null and b.def.is_dragon_garden:
			EventBus.dragon_menu_requested.emit(b)
			return
	EventBus.game_message.emit("这里没有什么可交互的", Color(0.7, 0.7, 0.7))


# ---- G 集结 / 解散（v10：只集结「编队」成员，上限 4；先按 V 编队或自动补位）----

func _toggle_squad_rally() -> void:
	if hero == null:
		return
	if hero.squad.size() > 0:
		var n := hero.squad.size()
		hero.release_squad()
		EventBus.game_message.emit("小队解散：%d 名小兵恢复自主作战" % n, Color(0.8, 0.85, 1.0))
		return
	var members: Array = hero.alive_party()
	if members.is_empty():
		EventBus.game_message.emit("编队里没有小兵——建房屋吸引流民、兵营 [E] 募兵，或按 V 调整编队", Color(0.9, 0.85, 0.7))
		return
	hero.recruit_squad(members)
	EventBus.game_message.emit("集结！%d 名小兵跟随你作战（G 解散）" % hero.squad.size(), Color(1.0, 0.9, 0.5))


# ---- T 集火（v10：小队围攻准星目标，直到它死亡才恢复各自行为 AI）----

func _toggle_focus_fire() -> void:
	if hero == null:
		return
	# 已在集火：准星没指向别的怪 → 取消集火
	if hero.is_focus_alive():
		if _aim_enemy == null or _aim_enemy == hero.focus_target:
			var old_name: String = (hero.focus_target as Pawn).get_display_name()
			hero.order_focus_fire(null)
			EventBus.game_message.emit("取消集火 %s，小队恢复自主作战" % old_name, Color(0.8, 0.85, 1.0))
			_update_enemy_highlights()
			return
	# 准星指着怪 → 下令集火
	if _aim_enemy != null and is_instance_valid(_aim_enemy):
		var hero_squad_size: int = hero.squad.size()
		if hero_squad_size == 0:
			EventBus.game_message.emit("小队未集结——先按 G 集结编队成员", Color(0.9, 0.85, 0.7))
			return
		hero.order_focus_fire(_aim_enemy)
		EventBus.game_message.emit("集火 %s！%d 名小兵围攻至其倒下" % [( _aim_enemy as Pawn).get_display_name(), hero_squad_size], Color(1.0, 0.6, 0.4))
		_update_enemy_highlights()
		return
	EventBus.game_message.emit("准星指向怪物后按 T 下令集火", Color(0.7, 0.75, 0.8))


# ---- 面向主城（focus_base：HERO = 转身看向城堡；TOPDOWN = 主角转身、相机自动跟随）----

func face_base() -> void:
	if hero == null:
		return
	var to_base := Vector3.ZERO - hero.global_position
	to_base.y = 0.0
	if to_base.length_squared() < 0.01:
		return
	if SelectionManager.view_mode != SelectionManager.ViewMode.HERO:
		hero.look_at_target(to_base.normalized())   # 等距相机跟随主角，转身即可
		return
	if camera == null:
		return
	camera.yaw = atan2(-to_base.x, -to_base.z)
	camera.pitch = -0.18


# ---- 模式切换（v42：玩家入口只剩俯视角主控，Tab 不再换镜头；脚本接口保留全三态）----

## Tab：在「玩家开放」的视角模式间循环（SelectionManager.enabled_view_modes）。
## v42 只开放俯视角主控 → 单模式时 Tab 不切镜头，只回一条提示，避免玩家以为按键失灵。
func cycle_view_mode() -> void:
	var modes := SelectionManager.enabled_view_modes()
	if modes.size() <= 1:
		EventBus.game_message.emit("当前版本只保留俯视角主控：WASD 移动 · 鼠标瞄准 · 左键挥砍", Color(0.85, 0.95, 1.0))
		return
	var idx: int = modes.find(SelectionManager.view_mode)
	set_view_mode(modes[(idx + 1) % modes.size()])


## 兼容旧入口：等价一轮 Tab 循环（Main / 旧测试仍在用）。
func toggle_hero_mode() -> void:
	cycle_view_mode()


## 脚本 / 旧测试入口：进第三人称亲征（v42 起玩家入口已屏蔽，但实现与工具取景保留）。
func enter_hero_mode() -> void:
	set_view_mode(SelectionManager.ViewMode.HERO)


## 脚本 / 旧测试入口：进战术俯瞰 RTS（v42 起玩家入口已屏蔽）。
func exit_hero_mode() -> void:
	set_view_mode(SelectionManager.ViewMode.TACTICAL)


## 开局默认视角（v42 = 俯视角主控）。force 让「同模式」也重新交接一次相机与编队，
## 因为 Autoload 里的 view_mode 默认就是 TOPDOWN，开局需要强制走一遍 _enter_control。
func enter_default_view_mode() -> void:
	set_view_mode(SelectionManager.default_view_mode(), true)


## 三态切换核心：SelectionManager 的模式位 + 相机 / 小队 / 主角状态机统一交接。
## force=true 时即使模式位相同也重新执行交接（开局 / 剧情定场用）。
func set_view_mode(mode: int, force: bool = false) -> void:
	if mode == SelectionManager.view_mode and not force:
		return
	if hero == null or camera == null or iso_camera == null:
		_resolve_refs()
	if hero == null:
		return
	SelectionManager.set_view_mode(mode)
	if mode == SelectionManager.ViewMode.TACTICAL:
		_enter_tactical()
	else:
		_enter_control(mode)
	_sync_mouse_mode()


## 进入主控（HERO 越肩 / TOPDOWN 俯视跟随）：编队跟随、清 RTS 选择、主角接管输入。
func _enter_control(mode: int) -> void:
	# 编队成员（v10 起 G 语义）自动跟随；编队为空则无人跟随（G 再集结）
	hero.recruit_squad(hero.alive_party())
	SelectionManager.clear()
	if mode == SelectionManager.ViewMode.HERO:
		# 相机交接：第三人称接管，等距退出跟随
		if camera != null:
			camera.hero = hero
			camera.current = true
			# yaw 对齐主角当前朝向：战术俯瞰期间主角可能被右键下令移动/索敌转过身，
			# 不对齐的话切回瞬间相机仍朝旧方向——按 WASD 移动时主角朝移动方向跑、
			# 相机却朝旧方向，画面视角就是歪的（v7 真机反馈 bug）。
			# aim_dir 一并同步：HeroIdleState 的物理回调先于本控制器，若留旧值它会先把
			# 主角转回旧朝向、再被本帧覆盖，造成一帧抖动与测试竞态。
			var f := hero.facing_dir()
			if f.length_squared() > 0.001:
				camera.yaw = atan2(-f.x, -f.z)   # 与 Pawn.look_at_target 同一公式
				hero.aim_dir = f
		if iso_camera != null:
			iso_camera.current = false
			iso_camera.follow_target = null
		EventBus.game_message.emit("第三人称亲征：鼠标视角 · WASD 移动 · 左键挥砍", Color.WHITE)
	else:
		# 俯视角主控：等距相机跟随主角（自动禁 WASD/边缘平移），指针保持释放
		if iso_camera != null:
			iso_camera.current = true
			iso_camera.focus_on(hero.global_position)
			iso_camera.follow_target = hero
		if camera != null:
			camera.current = false
		EventBus.game_message.emit("俯视角主控：WASD 移动 · 鼠标瞄准 · 左键挥砍 · G 集结 / T 集火", Color(0.85, 0.95, 1.0))
	# 建造模式与主控共存（HERO 准星放置 / TOPDOWN 鼠标落点放置）
	if hero.state_machine != null:
		hero.state_machine.transition_to("hero_idle")
	EventBus.hero_mode_changed.emit(true)


## 进入战术俯瞰 RTS：鼠标释放、恢复框选/右键下令；主角切基础 AI 且不自动索敌（等玩家下令）。
func _enter_tactical() -> void:
	# 战术俯瞰下建造走「点击菜单 → 网格放置」原流程，先退出准星/落点建造
	var bs := get_tree().get_first_node_in_group("build_system") as BuildSystem
	if bs != null and bs.is_building:
		bs.exit_build_mode()
	_aim_enemy = null
	_update_enemy_highlights()   # 清掉瞄准红描边（集火目标保留至死亡）
	hero.desired_velocity = Vector3.ZERO
	hero.release_squad()
	hero.aim_dir = hero.facing_dir()
	if iso_camera != null:
		iso_camera.current = true
		iso_camera.follow_target = null
		iso_camera.focus_on(hero.global_position)
	if camera != null:
		camera.current = false
	if hero.state_machine != null:
		hero.state_machine.transition_to("idle")
	EventBus.game_message.emit("战术俯瞰：框选 · 右键下令 · 点击建造（主角待命不主动接敌）", Color(0.8, 0.9, 0.8))
	EventBus.hero_mode_changed.emit(false)
