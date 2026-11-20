class_name CombatSystem
extends Node
## ============================================================================
## 战斗协调：城外野怪存活计数 + 狩猎掉落 + 头目战报。
## 伤害结算去中心化（各实体 AttackerComponent→HealthComponent 自行处理），
## 本系统只监听 spawn/died 维护计数（供 HUD 显示）并生成可见、可拾取的狩猎掉落。
## v3：掉落金额读 def.loot_gold；头目阵亡有专属战报与音效。
## v22：掉落概率本就是 100%（每杀必掉）——「提升掉落」落实为赏金全面上调
## （普通 10 / 精英 45 / 头目 200，见 GameDefs），金币是当前唯一建造货币。
## ============================================================================

const MONSTER_BOUNTY: int = 10         # 默认狩猎掉落（def.loot_gold 为 0 时用；v22 原 5）
const LootDropScript = preload("res://scripts/entities/LootDrop.gd")

const COIN_MIN := 1                    # 普通怪爆出份数范围（总金额不变，随机拆分）
const COIN_MAX := 3
const BOSS_COIN_MIN := 5               # 头目爆出份数范围（多爆一些，制造爽感）
const BOSS_COIN_MAX := 8

var enemies_alive: int = 0


func _ready() -> void:
	add_to_group("combat_system")
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_enemy_spawned(_enemy: Node) -> void:
	enemies_alive += 1


func _on_enemy_died(enemy: Node, _killer: Node) -> void:
	enemies_alive = max(0, enemies_alive - 1)
	if enemy == null or not is_instance_valid(enemy) or not (enemy is Node3D):
		return
	var bounty: int = MONSTER_BOUNTY
	var is_boss: bool = false
	if enemy.get("def") != null and enemy.def != null:
		if enemy.def.loot_gold > 0:
			bounty = enemy.def.loot_gold
		is_boss = enemy.def.is_boss
	# 爆币：普通随机 1~3 份 / 头目 5~8 份；每份金额从总赏金拆分，玩家拿到的不变
	var count: int = randi_range(BOSS_COIN_MIN, BOSS_COIN_MAX) if is_boss else randi_range(COIN_MIN, COIN_MAX)
	count = mini(count, maxi(bounty, 1))   # 份数不超过金额数（防拆出 0 金币）
	var shares: Array = _split_bounty(bounty, count)
	var origin: Vector3 = (enemy as Node3D).global_position
	var container := get_tree().get_first_node_in_group("loot_drops")
	for i in count:
		var drop: Node3D = LootDropScript.new()
		drop.resource_id = GameDefs.GOLD
		drop.amount = shares[i]
		drop.ground_y = origin.y
		drop.spawn_delay = i * randf_range(0.04, 0.07)   # 错峰喷出（喷泉感）
		if container != null:
			container.add_child(drop)
		else:
			get_parent().add_child(drop)
		var ang := randf() * TAU
		drop.global_position = origin + Vector3(cos(ang) * randf_range(0.0, 0.3), 0.45, sin(ang) * randf_range(0.0, 0.3))
	AudioManager.play_sfx(&"die_enemy", origin)
	# 头目战报：全服播报 + 战利品漂浮文字
	if is_boss:
		var boss_name: String = enemy.def.unit_name if enemy.def.unit_name != "" else enemy.def.display_name
		EventBus.game_message.emit("夜袭头目【%s】已被讨伐！+%d 金币" % [boss_name, bounty], Color(1.0, 0.85, 0.3))
		EventBus.floating_text.emit("头目讨伐！", Color(1.0, 0.5, 0.3), origin + Vector3(0.0, 2.6, 0.0))
		EventBus.boss_died.emit(enemy)
		AudioManager.play_sfx(&"victory")


## 总金额不变地拆成 count 份：先向下均分，余数逐份 +1（5 拆 3 份 = 2/2/1）。
func _split_bounty(total: int, count: int) -> Array:
	var shares: Array = []
	var base := floori(float(total) / float(count))
	for i in count:
		shares.append(base)
	var rem: int = total - base * count
	var idx := 0
	while rem > 0:
		shares[idx % count] = int(shares[idx % count]) + 1
		rem -= 1
		idx += 1
	return shares
