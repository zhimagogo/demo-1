class_name VillagerIdleState
extends PawnState
## 村民待机（决策路由，不滞留）：
## 1) 附近有敌 → 逃跑
## 2) 背包满了 / 采空了 → 回城入库
## 3) 有活干 → 去资源点采集
## 4) 没活干（资源耗尽 / 全被占满）→ 城内闲逛歇息

const WORK_SCAN_INTERVAL: float = 0.8   # 找活频率（避免每帧全图扫节点）


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"idle")


func physics_update(delta: float) -> void:
	var v := pawn as Colonist
	if v == null:
		return
	# 城内回血（def.regen_per_sec）
	pawn._try_city_regen(delta)

	# 1) 威胁：敌人逼近 → 逃跑（掉一半货，跑得快）
	var threat = pawn.find_nearest_hostile(Colonist.FLEE_SCAN_RADIUS)
	if threat != null:
		state_machine.transition_to("villager_flee", {"threat": threat})
		return

	# 2) 背包满 / 上个点采空还有存货 → 入库
	if v.carry_full() or (v.work_target == null and not v.carry_empty()):
		state_machine.transition_to("villager_deliver")
		return

	# 3) 找活干（限频扫描；目标失效 / 采空时重新挑点）
	if v.work_target == null or not is_instance_valid(v.work_target) or v.work_target.is_depleted():
		_scan_timer(delta)
		if _scan_ready:
			_scan_ready = false
			var node = _pick_resource_node()
			if node != null:
				v.work_target = node
	if v.work_target != null and is_instance_valid(v.work_target) and not v.work_target.is_depleted():
		state_machine.transition_to("villager_work", {"target": v.work_target})
		return

	# 4) 没活：背包有零头先入库，否则回城歇着
	if not v.carry_empty():
		state_machine.transition_to("villager_deliver")
		return
	var city: CitySystem = pawn._get_city()
	if city != null and not city.is_in_city(pawn.global_position):
		pawn.move_target = city.random_point_in_city()
		state_machine.transition_to("move")
	else:
		pawn.play_anim(&"idle")


var _scan_accum: float = 0.0
var _scan_ready: bool = true


func _scan_timer(delta: float) -> void:
	_scan_accum += delta
	if _scan_accum >= WORK_SCAN_INTERVAL:
		_scan_accum = 0.0
		_scan_ready = true


## 挑资源点：距离近优先，已采空的跳过，被 2+ 村民盯上的降权（自然分流）。
## 扫描前先一次遍历全组构建「资源点 instance_id → 盯着它的村民数」映射，
## 之后每个候选点 O(1) 查询，替代原先的 O(资源点 × 村民) 嵌套遍历。
func _pick_resource_node():
	var best = null
	var best_score: float = INF
	var occupancy := {}   # 资源点 instance_id → 该点已被多少村民盯上
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if not (unit is Colonist) or not is_instance_valid(unit):
			continue
		var wt = (unit as Colonist).work_target
		if wt != null and is_instance_valid(wt):
			var key: int = wt.get_instance_id()
			occupancy[key] = occupancy.get(key, 0) + 1
	for node in get_tree().get_nodes_in_group("resource_node"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		if node.is_depleted():
			continue
		var dist: float = pawn.global_position.distance_to((node as Node3D).global_position)
		if dist > 70.0:
			continue
		var crowding: int = occupancy.get(node.get_instance_id(), 0)
		if crowding >= 3:
			continue   # 太挤的点不抢
		var score: float = dist + crowding * 18.0
		if score < best_score:
			best_score = score
			best = node
	return best
