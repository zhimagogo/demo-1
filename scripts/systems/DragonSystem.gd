class_name DragonSystem
extends Node
## ============================================================================
## 驯龙系统中枢（v26，WorldRoot 子节点、分组 "dragon_system"）：
## - 解锁：龙园（分组 "dragon_garden"）存在时花金币解锁 DragonDef（会话级存档）；
## - 出战：同一时刻最多一只巨龙随队（Hero.party 之外的「编外第 5 位」）；
##   出战 = 在主角身后生成 DragonPet 并绑定 follow_leader；
## - 复苏：出战巨龙阵亡后 RESPAWN_SEC 秒在主角身边自动复苏（宠物不死机制，
##   DragonMenu / 市民出战区期间显示「复苏中」）；
## - UI 入口：HeroController 对龙园按 E → EventBus.dragon_menu_requested → DragonMenu；
##   市民管理（CitizenPanel）的「出战巨龙」区也读写本系统。
## ============================================================================

const RESPAWN_SEC: float = 25.0         # 巨龙阵亡后的复苏时长

var unlocked: Dictionary = {}           # dragon_id(StringName) -> true
var deployed_id: StringName = &""       # 当前出战的龙 id（空 = 未出战）
var pet: DragonPet = null               # 出战的 DragonPet 实例（阵亡后短暂保留至释放）
var respawn_left: float = 0.0           # 复苏倒计时（>0 = 阵亡等待复苏；测试可直接改写）


func _ready() -> void:
	add_to_group("dragon_system")
	EventBus.pawn_died.connect(_on_pawn_died)


func _process(delta: float) -> void:
	# 复苏倒计时：出战中的龙阵亡 → 在主角身边重生成（主角也倒下时顺延等待）
	if deployed_id == &"" or respawn_left <= 0.0:
		return
	respawn_left = maxf(0.0, respawn_left - delta)
	if respawn_left > 0.0:
		return
	var hero := _hero()
	if hero == null or hero.is_dead_flag:
		return   # 主角倒下期间顺延（下一帧再试）
	_spawn_pet(hero)


# ---- 查询 ----

## 场上是否建有龙园（解锁巨龙的前提；已解锁的龙随时可出战/召回）。
func has_garden() -> bool:
	return not get_tree().get_nodes_in_group("dragon_garden").is_empty()


func is_unlocked(dragon_id: StringName) -> bool:
	return unlocked.has(dragon_id)


## 当前出战的 DragonPet（阵亡等待复苏 / 未出战 → null）。
func current_pet() -> DragonPet:
	if pet != null and is_instance_valid(pet) and not pet.is_dead_flag:
		return pet
	return null


# ---- 解锁（龙园内花金币）----

## 花金币解锁一条龙；成功后自动出战（第一次驯龙即刻体验）。返回是否成功。
func try_unlock(dragon_id: StringName) -> bool:
	var d := GameDefs.dragon_def(dragon_id)
	if d == null or is_unlocked(dragon_id):
		return false
	if not has_garden():
		EventBus.game_message.emit("需要先建造龙园才能驯龙", Color.ORANGE_RED)
		return false
	if not ResourceManager.spend(GameDefs.GOLD, d.unlock_cost):
		EventBus.game_message.emit("金币不足：驯服「%s」需要 %d 金币" % [d.display_name, d.unlock_cost], Color.ORANGE_RED)
		return false
	unlocked[dragon_id] = true
	EventBus.dragon_unlocked.emit(dragon_id)
	EventBus.game_message.emit("驯服成功！「%s」加入你的队伍（编外巨龙，跟随出战）" % d.display_name,
		Color(0.85, 0.55, 1.0))
	AudioManager.play_sfx(&"boss_spawn")
	# 首次驯龙立即出战（召回 / 再出战走龙园菜单或市民管理）
	deploy(dragon_id)
	return true


# ---- 出战 / 召回 ----

## 让指定龙出战（同一时刻只有一只；换龙 = 先召回旧的）。返回是否成功。
func deploy(dragon_id: StringName) -> bool:
	if not is_unlocked(dragon_id):
		return false
	var d := GameDefs.dragon_def(dragon_id)
	if d == null:
		return false
	if deployed_id == dragon_id and current_pet() != null:
		return true           # 已经在出战中
	_undeploy_internal()
	deployed_id = dragon_id
	respawn_left = 0.0
	var hero := _hero()
	if hero == null:
		return false
	_spawn_pet(hero)
	EventBus.game_message.emit("「%s」出战：跟着你，打你打的目标，也会清掉你身边的敌人" % d.display_name, Color(0.8, 0.85, 1.0))
	return true


## 召回出战的龙（不出战 = 不生成实体；解锁保留）。
func undeploy() -> void:
	if deployed_id == &"":
		return
	var d := GameDefs.dragon_def(deployed_id)
	_undeploy_internal()
	if d != null:
		EventBus.game_message.emit("「%s」已回龙园休憩" % d.display_name, Color(0.7, 0.75, 0.8))


func _undeploy_internal() -> void:
	if pet != null and is_instance_valid(pet):
		pet.queue_free()
	pet = null
	deployed_id = &""
	respawn_left = 0.0
	EventBus.dragon_deploy_changed.emit(&"", null)


## 在主角身侧生成出战巨龙并绑定跟随。
## v29：出生点从「主角正后方 3.2m」改到「右侧 3.2m」——第三人称相机在主角正后方
## 5.2m，出生在正后方 = 直接怼在镜头前（与跟随槽位同一处修正，见 DragonFollowState）。
func _spawn_pet(hero: Hero) -> void:
	var d := GameDefs.dragon_def(deployed_id)
	if d == null:
		return
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null:
		return
	var fwd: Vector3 = hero.facing_dir()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var at: Vector3 = hero.global_position + right * 3.2 - fwd * 1.0
	var p: DragonPet = spawner.call("spawn_dragon", d, at)
	if p == null:
		return
	p.follow_leader = hero
	pet = p
	respawn_left = 0.0
	EventBus.dragon_deploy_changed.emit(deployed_id, p)


# ---- 事件 ----

func _on_pawn_died(node: Node) -> void:
	if node == pet and deployed_id != &"":
		respawn_left = RESPAWN_SEC
		var d := GameDefs.dragon_def(deployed_id)
		var name := d.display_name if d != null else "巨龙"
		EventBus.game_message.emit("「%s」倒下了！%.0f 秒后在主角身边复苏" % [name, RESPAWN_SEC], Color.ORANGE_RED)
		EventBus.dragon_deploy_changed.emit(deployed_id, null)


func _hero() -> Hero:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero and is_instance_valid(n):
			return n
	return null
