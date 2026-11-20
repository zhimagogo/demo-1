class_name HarvestState
extends PawnState
## 采集状态：沿 NavMesh 走向资源节点 → 每秒采集一次 → 资源耗尽回待命。

var target_node   # ResourceNode
var _timer: float = 0.0

const SLOT_SETTLE_DIST: float = 0.5
const SEPARATION_RADIUS: float = 1.5
const SLOT_CACHE_FRAMES: int = 18   # slot 计算缓存时长（约 0.3s @60fps 物理帧）

# slot 位置实例缓存：slot 计算需遍历 "player_unit" 全组 + 排序，
# 40 个村民同采一处时为 O(N² log N)/帧——缓存后每单位每 0.3s 只算一次。
var _slot_cache_pos: Vector3 = Vector3.ZERO
var _slot_cache_target_id: int = 0
var _slot_cache_frame: int = -SLOT_CACHE_FRAMES


func enter(msg: Dictionary) -> void:
	target_node = msg.get("target", null)
	_timer = 0.0
	_slot_cache_target_id = 0   # 重新进入可能换了采集目标：缓存失效
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"run")
	call_deferred("_update_nav_target")


func physics_update(delta: float) -> void:
	if target_node == null or not is_instance_valid(target_node):
		state_machine.transition_to("idle")
		return

	var tn: Node3D = target_node
	var dist: float = pawn.global_position.distance_to(tn.global_position)
	var slot_pos: Vector3 = _harvest_slot_position(tn)
	var slot_dist: float = pawn.global_position.distance_to(slot_pos)
	if dist > 2.0 or slot_dist > SLOT_SETTLE_DIST:
		# 还没到，沿 NavMesh 前进
		pawn._steer_separation = pawn.compute_separation("player_unit", SEPARATION_RADIUS) * 3.5
		pawn.play_anim(&"run")
		pawn.move_along_path(delta)
		return

	# 到达采集距离，原地采集
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"harvest")
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		target_node.harvest_by(pawn)
		if target_node == null or not is_instance_valid(target_node) or target_node.is_depleted():
			state_machine.transition_to("idle")


func _update_nav_target() -> void:
	if target_node != null and is_instance_valid(target_node):
		pawn.set_navigation_target(_harvest_slot_position(target_node as Node3D))


func _on_navmesh_updated() -> void:
	_update_nav_target()


## 同一资源点的采集者按实例顺序分到环形站位，既都在采集距离内，也不会重叠。
## 带 0.3s 实例缓存：站定判定（SLOT_SETTLE_DIST 比较）用缓存值精度完全够用。
func _harvest_slot_position(resource: Node3D) -> Vector3:
	var frame := Engine.get_physics_frames()
	var rid := resource.get_instance_id()
	if rid == _slot_cache_target_id and frame - _slot_cache_frame < SLOT_CACHE_FRAMES:
		return _slot_cache_pos
	var workers: Array = []
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if not (unit is Pawn) or not is_instance_valid(unit):
			continue
		var current = (unit as Pawn).state_machine.current_state
		if current is HarvestState and current.target_node == target_node:
			workers.append(unit)
	if not workers.has(pawn):
		workers.append(pawn)
	workers.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var slot: int = workers.find(pawn)
	const SLOTS_PER_RING := 6
	var ring: int = slot / SLOTS_PER_RING
	var first_slot: int = ring * SLOTS_PER_RING
	var count_in_ring: int = mini(SLOTS_PER_RING, workers.size() - first_slot)
	var in_ring: int = slot - first_slot
	var phase := fmod(float(resource.get_instance_id()) * 0.4142135624, 1.0) * TAU
	var angle := phase + TAU * float(in_ring) / maxf(float(count_in_ring), 1.0)
	var radius := 1.1 + float(ring) * 0.75
	_slot_cache_pos = resource.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	_slot_cache_target_id = rid
	_slot_cache_frame = frame
	return _slot_cache_pos
