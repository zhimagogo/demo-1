class_name HealthComponent
extends Node
## 生命值组件：可挂到任何实体（Pawn / Enemy / Building / BaseCore）。
## 去中心化伤害结算：被 AttackerComponent 直接调用 apply_damage。
## v3：记录最后攻击者（击杀归属 / 主角经验）、广播 damage_dealt（伤害数字）、
##     玩家方受击时发 threat_alert（士兵支援响应）。

signal health_changed(current: float, max_hp: float)
signal damaged(amount: float, source: Node)   # 受击（仍然存活时；供单位做「被打反击」等响应）
signal died

@export var max_hp: float = 100.0
var current_hp: float = 100.0
var last_attacker: Node = null        # 最后一次伤害来源（击杀归属用）

# threat_alert 限流：同一受害者短时间内只播报一次，避免群殴时信号风暴
static var _last_threat_time: Dictionary = {}   # instance_id -> 秒（engine time）


func _ready() -> void:
	current_hp = max_hp


func apply_damage(amount: float, source: Node = null) -> void:
	if current_hp <= 0.0:
		return
	var owner_node := get_parent()
	# v19 易伤 debuff：宿主实现了 incoming_damage_mult（Pawn）则先放大伤害，
	# 后续伤害数字 / 吸血统计均按放大后的真实值走。
	if owner_node != null and owner_node.has_method("incoming_damage_mult"):
		amount *= float(owner_node.call("incoming_damage_mult"))
	# v20 属性系统 · 防御力：宿主实现了 defense_factor（Pawn）则按防御减免。
	# 乘法减伤（× K/(K+防御)）平滑无硬上限；保底 1 点伤害防止高防「打不动」。
	if owner_node != null and owner_node.has_method("defense_factor"):
		var factor := float(owner_node.call("defense_factor"))
		if factor < 1.0:
			amount = maxf(1.0, amount * factor)
	current_hp = max(0.0, current_hp - amount)
	if source != null:
		last_attacker = source
	health_changed.emit(current_hp, max_hp)
	# 广播伤害数字（HUD 漂浮文字）。BaseCore 等大体积目标也走同一通道。
	if amount >= 1.0 and owner_node is Node3D:
		EventBus.damage_dealt.emit(owner_node, amount, source)
	# 玩家方遇袭 → 威胁播报（士兵支援）。建筑 / 士兵 / 村民 / 主城都算玩家方。
	if owner_node != null and _is_player_side(owner_node) and amount >= 2.0:
		_try_emit_threat(owner_node)
	# 受击仍然存活 → 广播 damaged（v20：野怪被小兵打中即转火小兵的入口）
	if current_hp > 0.0 and amount > 0.0:
		damaged.emit(amount, source)
	if current_hp <= 0.0:
		died.emit()


## 玩家阵营判定：Pawn 看 TeamComponent；建筑 / 主城默认玩家方（本作无非玩家建筑）。
func _is_player_side(node: Node) -> bool:
	if node is Pawn:
		return (node as Pawn).team_comp != null and (node as Pawn).team_comp.team == TeamComponent.Team.PLAYER
	return node is Building or node.is_in_group("base_core")


## 同一目标 2 秒内只播报一次威胁，且全场每 0.5 秒最多一条（避免信号洪水）。
func _try_emit_threat(owner_node: Node) -> void:
	var now := Time.get_ticks_msec()
	var id := owner_node.get_instance_id()
	var last: int = _last_threat_time.get(id, 0)
	if now - last < 2000:
		return
	_last_threat_time[id] = now
	EventBus.threat_alert.emit((owner_node as Node3D).global_position, owner_node)


func heal(amount: float) -> void:
	current_hp = min(max_hp, current_hp + amount)
	health_changed.emit(current_hp, max_hp)


func is_dead() -> bool:
	return current_hp <= 0.0


func ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return current_hp / max_hp
