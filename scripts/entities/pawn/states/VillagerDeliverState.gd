class_name VillagerDeliverState
extends PawnState
## 村民入库：背着货走回主城边缘 → 交割（ResourceManager.add + 漂浮文字 + 音效）→ 回路由。
## 交割点：主城外缘朝向自己一侧（不会钻进城堡碰撞体）。

const ARRIVE_DIST: float = 5.6      # 距主城中心这么近就算到了（城堡半径 4 + 货包身位）
const SEPARATION_RADIUS: float = 1.4


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"run")
	call_deferred("_update_nav_target")


func physics_update(delta: float) -> void:
	var v := pawn as Colonist
	if v == null or v.carry_empty():
		state_machine.transition_to("idle")
		return
	# 路上遇敌：掉一半货开溜
	if pawn.find_nearest_hostile(Colonist.FLEE_SCAN_RADIUS) != null:
		state_machine.transition_to("villager_flee", {})
		return
	# 抵达主城边缘 → 交割
	if pawn.global_position.length() <= ARRIVE_DIST:
		_deposit(v)
		state_machine.transition_to("idle")
		return
	pawn._steer_separation = pawn.compute_separation("player_unit", SEPARATION_RADIUS) * 3.0
	pawn.play_anim(&"run")
	pawn.move_along_path(delta)


func _deposit(v: Colonist) -> void:
	var payload := v.dump_carry()
	var amount: int = int(payload["amount"])
	if amount <= 0:
		return
	ResourceManager.add(payload["id"], amount)
	AudioManager.play_sfx(&"deposit", pawn.global_position)
	# 主城头顶漂浮 "+N 木材"（HUD FloatingLabels 监听 floating_text）
	var res_name := "资源"
	for rd in GameDefs.resource_defs():
		if rd.id == payload["id"]:
			res_name = rd.display_name
			break
	EventBus.floating_text.emit("+%d %s" % [amount, res_name], Color(0.65, 0.95, 0.55), Vector3(0.0, 3.2, 0.0))


func _update_nav_target() -> void:
	# 目标：主城中心方向、自己这一侧的外缘点（自然走向最近的城门）
	var dir = pawn.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(1.0, 0.0, 0.0)
	pawn.set_navigation_target(dir.normalized() * (ARRIVE_DIST - 0.8))
