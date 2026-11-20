class_name VillagerWorkState
extends PawnState
## 村民采集：走向资源点的环形站位 → 每隔 WORK_TICK 采一份 →
## 背包满 / 点采空 / 遇敌 → 返回路由（idle 会分流到入库或逃跑）。

const SLOT_SETTLE_DIST: float = 0.55
const SEPARATION_RADIUS: float = 1.4
const SLOT_CACHE_FRAMES: int = 18   # slot 计算缓存时长（约 0.3s @60fps 物理帧）

var target_node = null      # ResourceNode
var _timer: float = 0.0

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
	var v := pawn as Colonist
	if v == null:
		return
	# 遇敌即逃（router 也会兜底，这里提前止损）
	if pawn.find_nearest_hostile(Colonist.FLEE_SCAN_RADIUS) != null:
		state_machine.transition_to("villager_flee", {})
		return
	if target_node == null or not is_instance_valid(target_node) or target_node.is_depleted():
		state_machine.transition_to("idle")
		return

	var tn: Node3D = target_node
	var slot_pos: Vector3 = _work_slot_position(tn)
	var slot_dist: float = pawn.global_position.distance_to(slot_pos)
	if slot_dist > SLOT_SETTLE_DIST:
		pawn._steer_separation = pawn.compute_separation("player_unit", SEPARATION_RADIUS) * 3.0
		pawn.play_anim(&"run")
		pawn.move_along_path(delta)
		return

	# 到位：原地采集
	pawn.velocity = Vector3.ZERO
	pawn.move_and_slide()
	pawn.play_anim(&"harvest")
	var dir: Vector3 = tn.global_position - pawn.global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		pawn.look_at_target(dir.normalized())
	_timer += delta
	if _timer >= Colonist.WORK_TICK:
		_timer = 0.0
		var got: int = target_node.harvest_carry(pawn, Colonist.HARVEST_PER_TICK)
		if got > 0:
			v.add_carry(target_node.yield_resource, got)
			_play_chop_sfx(target_node)
		if v.carry_full() or target_node == null or not is_instance_valid(target_node) or target_node.is_depleted():
			state_machine.transition_to("idle")


func _play_chop_sfx(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id: StringName = &"chop_wood" if node.yield_resource == &"wood" else &"mine_stone"
	AudioManager.play_sfx(id, pawn.global_position)


func _update_nav_target() -> void:
	if target_node != null and is_instance_valid(target_node):
		pawn.set_navigation_target(_work_slot_position(target_node as Node3D))


func _on_navmesh_updated() -> void:
	_update_nav_target()


## 同一资源点的采集者环形站位（与 HarvestState 同思路：分圈不重叠）。
## 带 0.3s 实例缓存：站定判定（SLOT_SETTLE_DIST 比较）用缓存值精度完全够用。
func _work_slot_position(resource: Node3D) -> Vector3:
	var frame := Engine.get_physics_frames()
	var rid := resource.get_instance_id()
	if rid == _slot_cache_target_id and frame - _slot_cache_frame < SLOT_CACHE_FRAMES:
		return _slot_cache_pos
	var workers: Array = []
	for unit in get_tree().get_nodes_in_group("player_unit"):
		if not (unit is Colonist) or not is_instance_valid(unit):
			continue
		var cur = (unit as Colonist).work_target
		if cur == target_node:
			var st = (unit as Colonist).state_machine.current_state
			if st is VillagerWorkState or st is VillagerIdleState:
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
	var radius := 1.2 + float(ring) * 0.8
	_slot_cache_pos = resource.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	_slot_cache_target_id = rid
	_slot_cache_frame = frame
	return _slot_cache_pos
