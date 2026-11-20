extends Node
## ============================================================================
## ResourceManager —— 库存资源唯一可信源
## 所有可堆叠资源（木材/石头/食物/金币）的增删改查集中于此。
## 每次变更通过 EventBus.resource_changed 广播，UI 监听刷新。
## ============================================================================

# StringName -> int
var _amounts: Dictionary = {}


func register(id: StringName, amount: int) -> void:
	_amounts[id] = amount
	# delta=0：初始登记不是「采集进账」，任务系统的累计口径不应把开局资源算作采集量
	EventBus.resource_changed.emit(id, amount, 0)


func get_amount(id: StringName) -> int:
	return _amounts.get(id, 0)


func has(id: StringName, amount: int) -> bool:
	return get_amount(id) >= amount


func add(id: StringName, amount: int) -> void:
	var prev: int = get_amount(id)
	_amounts[id] = prev + amount
	EventBus.resource_changed.emit(id, _amounts[id], amount)


func spend(id: StringName, amount: int) -> bool:
	if not has(id, amount):
		EventBus.resource_insufficient.emit(id, amount)
		EventBus.game_message.emit("资源不足：%s" % String(id), Color.ORANGE_RED)
		return false
	_amounts[id] = get_amount(id) - amount
	EventBus.resource_changed.emit(id, _amounts[id], -amount)
	return true


func can_afford(costs: Dictionary) -> bool:
	for id in costs:
		if not has(id, costs[id]):
			return false
	return true


func pay(costs: Dictionary) -> bool:
	if not can_afford(costs):
		EventBus.game_message.emit("资源不足，无法建造", Color.ORANGE_RED)
		return false
	for id in costs:
		spend(id, costs[id])
	return true


func refund(costs: Dictionary) -> void:
	for id in costs:
		add(id, costs[id])
