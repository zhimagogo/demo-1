class_name SettlementSystem
extends Node
## 房屋驱动的人口循环：空房会定期、有概率吸引一名流民；流民抵达后入住并
## **觉醒为四职业小兵之一**（战士 / 法师 / 刺客 / 游侠，见 GameDefs.settler_*_def）。
## v25 起职业由玩家在入住弹窗中点选（SettleClassPicker）；无弹窗环境回落随机。
## 小兵白天自动出城讨伐野怪、夜晚回城游荡驻防（SoldierIdleState 昼夜路由）；
## 定居时给小兵随机姓名（unit_name），HUD / 事件日志显示活人姓名。
## v10 变更：定居产物由「村民（采集工人）」改为「随机职业小兵」——经营线只靠
## 建筑（房屋/农田/市集）产出，人口线全部产出战斗单位。

const RefugeeScript = preload("res://scripts/entities/pawn/Refugee.gd")

const ARRIVAL_CHECK_INTERVAL: float = 8.0
const ARRIVAL_CHANCE: float = 0.65
# 房屋吸引力随空房数量提升：多建几栋，来人明显更勤
const CHANCE_PER_VACANCY: float = 0.12

var _timer: float = 0.0
var _pending_house_ids: Dictionary = {}


func _ready() -> void:
	add_to_group("settlement_system")
	EventBus.refugee_arrived.connect(_on_refugee_arrived)
	EventBus.settle_class_chosen.connect(_on_settle_class_chosen)
	EventBus.building_removed.connect(_on_building_removed)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < ARRIVAL_CHECK_INTERVAL:
		return
	_timer = 0.0
	var vacancies := _vacant_houses()
	if vacancies.is_empty():
		return
	var chance: float = ARRIVAL_CHANCE + CHANCE_PER_VACANCY * float(vacancies.size() - 1)
	if randf() > chance:
		return
	_spawn_refugee_for(vacancies.pick_random())


func _vacant_houses() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("house"):
		if node is Building and is_instance_valid(node) and (node as Building).has_vacancy() \
				and not _pending_house_ids.has(node.get_instance_id()):
			out.append(node)
	return out


func _find_open_house() -> Building:
	var houses := _vacant_houses()
	return houses[0] if not houses.is_empty() else null


func _spawn_refugee_for(house: Building) -> void:
	var city := get_tree().get_first_node_in_group("city_system") as CitySystem
	var at := city.random_point_outside(city.city_half + 5.0, city.city_half + 9.0) if city != null else house.global_position + Vector3(8.0, 0.0, 0.0)
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_refugee"):
		return
	_pending_house_ids[house.get_instance_id()] = true
	var refugee: Node = spawner.call("spawn_refugee", at)
	refugee.call("travel_to", house)
	EventBus.game_message.emit("一名流民被房屋吸引，正前往城镇…", Color(0.75, 0.9, 1.0))


func _on_refugee_arrived(refugee: Node, house: Node) -> void:
	if house != null:
		_pending_house_ids.erase(house.get_instance_id())
	if refugee == null or refugee.get_script() != RefugeeScript or not is_instance_valid(refugee) or not (house is Building) or not is_instance_valid(house):
		return
	var home := house as Building
	if not home.has_vacancy():
		refugee.queue_free()
		return
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_soldier"):
		return
	# v25 流民入住职业选择：界面上有职业选择弹窗（SettleClassPicker）时先交给玩家点选，
	# 选择完成经 settle_class_chosen 回到这里完成转化；无弹窗（如无头测试）回落随机职业。
	if not get_tree().get_nodes_in_group("settle_class_picker").is_empty():
		EventBus.settle_class_choice_required.emit(refugee, home)
		return
	_settle_refugee(refugee, home, GameDefs.random_settler_def().id)


## 玩家在职业选择弹窗里点选后回调（refugee / house 在等待期间可能已失效，需重校验）。
func _on_settle_class_chosen(refugee: Node, house: Node, class_id: StringName) -> void:
	if house != null and house is Building and is_instance_valid(house):
		_pending_house_ids.erase(house.get_instance_id())
	if refugee == null or not is_instance_valid(refugee) or refugee.get_script() != RefugeeScript \
			or not (house is Building) or not is_instance_valid(house):
		if refugee != null and is_instance_valid(refugee):
			refugee.queue_free()
		return
	_settle_refugee(refugee, house as Building, class_id)


## 流民 → 指定职业小兵：随机姓名 + 挂家（白天出城讨伐 / 夜晚回城驻防）。
func _settle_refugee(refugee: Node, home: Building, class_id: StringName) -> void:
	if not is_instance_valid(refugee) or not is_instance_valid(home) or not home.has_vacancy():
		if is_instance_valid(refugee):
			refugee.queue_free()
		return
	var spawner := get_tree().get_first_node_in_group("pawn_spawner")
	if spawner == null or not spawner.has_method("spawn_soldier"):
		return
	var settler_def := GameDefs.settler_def(class_id)
	var soldier: Pawn = spawner.call("spawn_soldier", settler_def, refugee.global_position)
	soldier.def.unit_name = GameDefs.random_villager_name()
	home.assign_resident(soldier)
	if soldier is Soldier:
		(soldier as Soldier).assign_home(home)
	refugee.queue_free()
	EventBus.resident_settled.emit("%s（%s）" % [soldier.get_display_name(), settler_def.display_name], home)


func _on_building_removed(building: Node, _cell: Vector2i) -> void:
	if building != null:
		_pending_house_ids.erase(building.get_instance_id())
		# 房屋在流民赶到前被拆毁时，取消这次迁入，避免无目标单位滞留在地图上。
		for refugee in get_tree().get_nodes_in_group("refugee"):
			if is_instance_valid(refugee) and refugee.get("destination_house") == building:
				refugee.queue_free()
