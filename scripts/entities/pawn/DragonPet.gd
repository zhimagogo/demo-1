class_name DragonPet
extends Pawn
## ============================================================================
## 巨龙宠物（v26 驯龙系统，v32 起带自主攻击）：小队「编外第 5 位」。
## - 不占 4 人编队槽（Hero.party/squad 不收录），由 DragonSystem 生成 / 召回 / 阵亡复苏；
## - **目标三级优先级**（见 pick_target）：① 玩家的目标（集火令 T / 主角当前攻击目标，
##   Hero.live_pet_target）＞② 正在打玩家的敌人 ＞③ 自主索敌（**以主角为圆心**
##   DragonDef.auto_attack_range 内最近的敌人）。主角一有目标龙立即转火；
## - 跟随是**带缓冲半径的懒跟随**：主角在缓冲圈里走动龙原地不动，超出才追到侧翼槽位
##   （跟随半径）再停——见 DragonFollowState；
## - 普攻 = 朝目标吐火球（Projectile + 溅射爆炸，见 spawn_fireball）；
## - 技能 = 原地向目标方向吐火 2 秒的 40° 锥形持续伤害（DragonBreathState，CD 自动施放）；
## - 数值 / 模型 / 描述全部来自 DragonDef（GameDefs.dragon_defs()，数据驱动可扩新龙）。
## ============================================================================

var dragon_def: DragonDef = null        # def 的龙视图（_apply_def 时转换）

# ---- 冷却（跨状态持续，_process 统一倒计时）----
var _fire_cd_left: float = 0.0          # 火球普攻 CD 剩余
var _breath_cd_left: float = 0.0        # 吐息 CD 剩余

# 出口位置 = 真实嘴部（v29 按骨骼实测标定：四足龙的头并不高）。
# 实测基准（黑曜龙 model_scale 0.55 站定帧）：Head 骨骼 y=1.43 / Head.Tip（吻尖）y=1.26、
# 水平前伸 1.40m。旧值 (2.1 高, 1.1 前) 是「人形胸口高度」的想当然——火球 / 火舌 / 枪口
# 火光全部从龙头上方 0.7m 的空中凭空出现，这是「龙的效果很奇怪」的直接来源之一。
# v32：改成**按 model_scale 比例**算（不再写死米数）——体型翻倍时嘴部出口自动跟着走，
# 否则翻倍后火球又会从脚边喷出来。见 mouth_height() / mouth_forward()。
const MOUTH_SCALE_REF: float = 0.55     # v29 骨骼实测时的 model_scale
const MOUTH_HEIGHT_REF: float = 1.35    # 该尺寸下的嘴部高度（米，相对脚底）
const MOUTH_FORWARD_REF: float = 1.35   # 该尺寸下的嘴部前伸（米，沿朝向）
# 大体重单位的转向速率（rad/s）：不瞬移，限速转（约 172°/s，转身肉眼可见但不拖沓）
const TURN_RATE: float = 3.0
const FIREBALL_AOE_COLOR := Color(1.0, 0.55, 0.2)

# ---- 自主索敌（v32）----
const AUTO_TARGET_CACHE_FRAMES: int = 12   # 自主索敌结果缓存（0.2s @60fps，与 find_nearest_hostile 同口径）
const AUTO_LEASH_MULT: float = 1.25        # 自主目标飘出「主角圈」×此值才脱战（滞回防抖）

var _mouth_height: float = MOUTH_HEIGHT_REF
var _mouth_forward: float = MOUTH_FORWARD_REF
var _want_dir: Vector3 = Vector3.ZERO   # 本帧登记的目标朝向（look_at_target 写入，限速执行）
var _auto_cache: Node = null            # 自主索敌缓存（0.2s）
var _auto_cache_frame: int = -100


func _ready() -> void:
	super._ready()
	# 与 4 名编队小兵共用 hero_squad 分组（软件分离力互推不重叠）；
	# 但不在 Hero.squad 数组里——编队 / 集结 / 解散都不会动它。
	add_to_group("hero_squad")
	set_squad_mark(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_apply_turn(delta)


func _setup_nodes() -> void:
	super._setup_nodes()
	# 三个专属状态 + 把 idle 换成跟随态（出生即贴身跟随主角，无需 DragonSystem 手动切状态；
	# 跟随态 leader 失效时会自己站定等待）。
	state_machine.register_state("idle", DragonFollowState.new())
	state_machine.register_state("dragon_follow", DragonFollowState.new())
	state_machine.register_state("dragon_fight", DragonFightState.new())
	state_machine.register_state("dragon_breath", DragonBreathState.new())


func _apply_def() -> void:
	super._apply_def()
	dragon_def = def as DragonDef
	# 嘴部出口按体型比例标定（v32：model_scale 变了出口跟着走）
	var ratio: float = 1.0
	if def != null and def.model_scale > 0.0:
		ratio = def.model_scale / MOUTH_SCALE_REF
	_mouth_height = MOUTH_HEIGHT_REF * ratio
	_mouth_forward = MOUTH_FORWARD_REF * ratio


func _process(delta: float) -> void:
	# v34 回城疗伤：白天在城镇范围内缓慢回血（晚上守城期间不回）
	_try_town_regen(delta)
	if _fire_cd_left > 0.0:
		_fire_cd_left = maxf(0.0, _fire_cd_left - delta)
	if _breath_cd_left > 0.0:
		_breath_cd_left = maxf(0.0, _breath_cd_left - delta)


## 宠物定位（v32 起**有自主攻击**）：主角没指定/没在打目标时，龙自己守住主角身边
## auto_attack_range 那一圈（圆心 = 主角）；主角一旦有目标，立即转火主角的目标。
## 跟随是「带缓冲半径的懒跟随」（见 DragonFollowState），不是贴身黏着。


## 水平朝向（与 Hero.facing_dir 同公式：本地 -Z 投影到 XZ 平面）。
func facing_dir() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


# ---- 转向（v29：大体重单位不瞬移）----

## 覆写：登记「想朝向」而不是直接写 rotation.y —— 由 _physics_process 每帧限速转过去。
## 为什么：龙的模型 3m 级、转身量最大 180°，瞬时吸附看着像贴图在跳；且旧实现在同一帧里
## 先 look_at_target 再 spawn_fireball，rotation 尚未落到 global_transform 上时
## facing_dir() 仍是旧方向 → 火球从身侧 1.1m 处横着喷出来（实机可见）。
func look_at_target(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 0.001:
		_want_dir = flat.normalized()


## 当前朝向与 dir 的水平夹角（度；dir 零向量返回 0）。出招对齐门槛 / 测试查询用。
func facing_error_deg(dir: Vector3) -> float:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() <= 0.001:
		return 0.0
	return rad_to_deg(facing_dir().angle_to(flat.normalized()))


func _apply_turn(delta: float) -> void:
	if _want_dir.length_squared() <= 0.001:
		return
	rotation.y = _rotate_angle_toward(rotation.y, atan2(-_want_dir.x, -_want_dir.z), TURN_RATE * delta)
	_want_dir = Vector3.ZERO


## 角度限速逼近（最短弧；到目标即吸附，防抖）。
static func _rotate_angle_toward(cur: float, want: float, max_rad: float) -> float:
	var diff := wrapf(want - cur, -PI, PI)
	if absf(diff) <= max_rad:
		return want
	return cur + signf(diff) * max_rad


# ---- 目标同步：玩家打谁我打谁 ----

## 本帧应当攻击的目标（主角的集火令 / 保鲜期内的最近攻击目标）。
## 主角阵亡 / 失效 / 没在打谁 → null（回跟随态）。
func hero_target() -> Node:
	var leader = follow_leader
	if leader == null or not is_instance_valid(leader):
		return null
	# leader 可能是非 Pawn 的替身（探针 / 将来换成坐骑锚点）——用 get() 而不是硬取属性，
	# 否则每帧刷 "Invalid access to property 'is_dead_flag' on Node3D"（v29 实测）。
	if leader is Pawn and (leader as Pawn).is_dead_flag:
		return null
	if not leader.has_method("live_pet_target"):
		return null
	var t = leader.call("live_pet_target")
	if t == null or not is_instance_valid(t):
		return null
	var p := t as Pawn
	if p != null and p.is_dead_flag:
		return null
	return t


## 吐息是否就绪（UI / 测试查询）。
func breath_ready() -> bool:
	return _breath_cd_left <= 0.0


## 吐息 CD 剩余秒（UI / 测试查询）。
func breath_cd_left() -> float:
	return _breath_cd_left


# ---- 目标选择：三级优先级（v32）----

## 主角本体（跟随 leader 是活着的 Pawn 时）；替身节点 / 失效 / 阵亡 → null。
func hero_pawn() -> Pawn:
	var l = follow_leader
	if l is Pawn and is_instance_valid(l) and not (l as Pawn).is_dead_flag:
		return l as Pawn
	return null


## 本帧该打的目标，三级优先级：
##   ① 玩家的目标（集火令 T / 主角当前攻击目标，Hero.live_pet_target）
##   ② 正在打玩家的敌人（对方 combat_target == 主角，且主角圈内）
##   ③ 自主索敌：**以主角为圆心** auto_attack_range 内最近的敌人
## 全都没有 → null（回跟随态，原地待命）。
func pick_target() -> Node:
	var t := hero_target()
	if t != null:
		return t
	var h := hero_pawn()
	if h == null or dragon_def == null:
		return null
	return _auto_target(h)


## 自主索敌半径（米；圆心 = 主角）。UI / 测试查询用。
func auto_attack_range() -> float:
	return dragon_def.auto_attack_range if dragon_def != null else 0.0


## 该目标是否属于「主角指定」（优先级 1）：不受自主圈 leash 限制（主角追出去的龙也跟）。
func is_hero_target(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	return t == hero_target()


## ②③ 合一的扫描（0.2s 缓存，同 find_nearest_hostile 口径）：
## 优先「正在打主角的敌人」，其次圈内任意最近敌人。
## **滞回**：已经锁定的自主目标按 ×AUTO_LEASH_MULT 的宽容圈留人（11m 锁、13.75m 才丢），
## 新目标一律按严格 auto_attack_range 收——边界上来回抖的怪不会被反复抢/丢。
func _auto_target(h: Pawn) -> Node:
	var frame := Engine.get_physics_frames()
	var keep: Node = _auto_cache if (_auto_cache != null and is_instance_valid(_auto_cache)) else null
	if keep != null and frame - _auto_cache_frame <= AUTO_TARGET_CACHE_FRAMES \
			and _within_auto_leash(h, keep):
		return keep
	var radius := dragon_def.auto_attack_range
	var leash := radius * AUTO_LEASH_MULT
	var best_threat: Node = null
	var best_threat_d := INF
	var best_any: Node = null
	var best_any_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Pawn):
			continue
		var p := e as Pawn
		if p.is_dead_flag:
			continue
		var d: float = h.global_position.distance_to(p.global_position)
		if d > (leash if e == keep else radius):
			continue                      # 圈外不管（宠物只守主角身边这一圈）
		if p.combat_target == h and d < best_threat_d:
			best_threat = p              # ② 正在打主角的，最优先
			best_threat_d = d
		if d < best_any_d:               # ③ 圈内最近
			best_any = p
			best_any_d = d
	_auto_cache = best_threat if best_threat != null else best_any
	_auto_cache_frame = frame
	return _auto_cache


## 自主目标是否还在「主角圈」内（带滞回：出圈 ×AUTO_LEASH_MULT 才算丢，防边界抖动）。
func _within_auto_leash(h: Pawn, t: Node) -> bool:
	if t == null or not is_instance_valid(t) or not (t is Node3D):
		return false
	var p := t as Pawn
	if p != null and p.is_dead_flag:
		return false
	return h.global_position.distance_to((t as Node3D).global_position) \
		<= dragon_def.auto_attack_range * AUTO_LEASH_MULT


# ---- 火球普攻：朝目标吐球，命中爆炸小片溅射 ----

## 朝目标吐一发火球（溅射参数来自 DragonDef）。战斗态在 CD 就绪 + 已对准时调用。
## aim_dir：本发火球的出膛方向（战斗态传「龙 → 目标」的方向；零向量回落自身朝向）。
## 为什么要传：rotation.y 当帧写、global_transform 下一帧才被读到（v7 相机坑同源），
## 只读 facing_dir() 会得到上一帧的旧朝向 → 火球从身侧横喷。
func spawn_fireball(target: Node, aim_dir: Vector3 = Vector3.ZERO) -> void:
	if dragon_def == null or target == null or not is_instance_valid(target):
		return
	var fwd := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if fwd.length_squared() <= 0.001:
		fwd = facing_dir()
	fwd = fwd.normalized()
	var fb := Projectile.new()
	fb.speed = dragon_def.fireball_speed
	fb.damage = dragon_def.fireball_damage
	fb.target = target
	fb.source = self
	# 外观（v30 卡通火球）：白热弹芯 + cel 火舌火衣 + 火舌尾焰 + 飞行灯光；
	# 命中走 v30 卡通分层爆炸（火舌团 / 烟团 / 橙环 / 闪烁灯光，见 _explode_splash 分支）
	fb.visual_kind = 2
	fb.body_scale = 1.75
	fb.body_color = FIREBALL_AOE_COLOR
	fb.trail_effect = &"fire_tongue_trail"
	fb.impact_effect = &"hit_spark"
	fb.impact_color = FIREBALL_AOE_COLOR
	fb.splash_radius = dragon_def.splash_radius
	fb.splash_damage = dragon_def.splash_damage
	fb.splash_group = "enemy"
	fb.splash_effect = &""
	var container := get_tree().get_first_node_in_group("projectiles")
	if container != null:
		container.add_child(fb)
	else:
		get_parent().add_child(fb)
	fb.global_position = global_position + fwd * _mouth_forward + Vector3(0.0, _mouth_height, 0.0)
	var dir: Vector3 = (target as Node3D).global_position + Vector3(0.0, 0.8, 0.0) - fb.global_position
	if dir.length_squared() > 0.0001:
		fb._velocity = dir.normalized() * dragon_def.fireball_speed
	else:
		fb._velocity = fwd * dragon_def.fireball_speed
	# 出手反馈（v30）：龙口火苗迸发（cel 火舌朝出膛方向吐出的一小口）+ 出膛灯闪
	var fire_yaw := atan2(-fwd.x, -fwd.z)
	VFXManager.spawn_effect(&"fire_snap", fb.global_position, fire_yaw,
		{"throttle_key": get_instance_id(), "throttle_time": 0.1})
	VFXManager.spawn_light(fb.global_position, Color(1.0, 0.55, 0.22), 1.0, 0.26, 4.0)
	AudioManager.play_sfx(&"arrow_shoot", global_position)
	_fire_cd_left = dragon_def.fireball_cooldown


## 火球 CD 是否就绪（战斗态 / 测试查询）。
func fireball_ready() -> bool:
	return _fire_cd_left <= 0.0


# ---- 烈焰吐息：锥形范围查询（战斗态与测试共用同一几何口径）----

## 以自身（嘴部）为顶点、朝 dir 的锥形（breath_range 长 / half_arc 半角）内的敌人列表。
func enemies_in_breath_cone(dir: Vector3) -> Array:
	var out: Array = []
	if dragon_def == null:
		return out
	# 锥顶取嘴部（XZ 口径与旧版一致：只比水平方向与距离；y 仅影响不到判定）
	var origin := global_position + Vector3(0.0, _mouth_height, 0.0)
	var f := Vector3(dir.x, 0.0, dir.z)
	if f.length_squared() < 0.0001:
		return out
	f = f.normalized()
	var half_arc := deg_to_rad(dragon_def.breath_half_arc_deg)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var p := e as Pawn
		if p != null and p.is_dead_flag:
			continue
		var to := (e as Node3D).global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist > dragon_def.breath_range:
			continue
		if dist > 0.001 and f.angle_to(to.normalized()) > half_arc:
			continue
		out.append(e)
	return out


## 嘴部世界坐标（吐息粒子 / 火球出口共用）。
func mouth_position() -> Vector3:
	return global_position + facing_dir() * _mouth_forward + Vector3(0.0, _mouth_height, 0.0)


## 嘴部在本体坐标系里的位置（挂载在龙身上的粒子发射器用；模型前向 = 本地 -Z）。
func mouth_local() -> Vector3:
	return Vector3(0.0, _mouth_height, -_mouth_forward)


## 嘴部高度 / 前伸（米，按 model_scale 比例标定；UI 与测试查询用）。
func mouth_height() -> float:
	return _mouth_height


func mouth_forward() -> float:
	return _mouth_forward
