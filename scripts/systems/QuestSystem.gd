class_name QuestSystem
extends Node
## ============================================================================
## 任务引导（v3）：一条线性的「新手 → 中期」目标链，教玩家把系统全部转起来。
## 逐条推进：当前目标完成 → 发奖励 + 音效 + 亮下一张卡（HUD QuestPanel 显示）。
## 全部完成后进入自由发展模式（面板显示天数与战绩）。
## ============================================================================

class Quest:
	var id: StringName
	var desc: String                 # 目标描述
	var need: int                    # 达成数量
	var have: int = 0                # 当前进度
	var reward: Dictionary = {}      # StringName -> int 资源奖励
	var reward_text: String = ""
	func _init(q_id: StringName, q_desc: String, q_need: int, q_reward: Dictionary, q_reward_text: String) -> void:
		id = q_id
		desc = q_desc
		need = q_need
		reward = q_reward
		reward_text = q_reward_text

var quests: Array = []
var current_index: int = 0
var completed_all: bool = false

# 累计统计（供多个任务判定复用）
var _kills: int = 0
var _houses_built: int = 0
var _taverns_built: int = 0
var _villagers_settled: int = 0


func _ready() -> void:
	add_to_group("quest_system")
	_build_quest_chain()
	_connect_signals()
	# 首帧后广播初始任务（HUD 可能晚于本系统就绪）
	call_deferred("_broadcast_current")


func _build_quest_chain() -> void:
	# v22：采集经济屏蔽、建筑统一金币造价 → 任务链改为「讨伐赚金币 → 建房引人流 →
	# 酒馆疗伤 → 扩军清剿」的金币主线；奖励全部发金币（木/石已无用途）。
	quests = [
		Quest.new(&"first_hunt", "讨伐 3 只城外野怪（金币是唯一的建造货币，走近掉落自动拾取）", 3, { GameDefs.GOLD: 30 }, "奖励 30 金币"),
		Quest.new(&"build_house", "建造 2 栋房屋（B 建造 · 数字键 2），等待流民敲门", 2, { GameDefs.GOLD: 30 }, "奖励 30 金币"),
		Quest.new(&"settle_villagers", "迎来 2 名居民入住（空房会自己吸引流民，觉醒为随机职业小兵）", 2, { GameDefs.GOLD: 30 }, "奖励 30 金币"),
		Quest.new(&"build_tavern", "建 1 座酒馆（B 建造 · 数字键 3）——低血小兵会自动回馆疗伤", 1, { GameDefs.GOLD: 40 }, "奖励 40 金币"),
		Quest.new(&"population_4", "城镇人口成长到 4 名（定居小兵计入，多造房屋招揽流民）", 4, { GameDefs.GOLD: 40 }, "奖励 40 金币"),
		Quest.new(&"kill_raiders", "清剿 10 只城外野怪（左键连招 · Q/C 技能 · G 集结小队 · T 集火）", 10, { GameDefs.GOLD: 60 }, "奖励 60 金币"),
		Quest.new(&"hero_level3", "把主角练到 3 级（击杀得经验）", 3, { GameDefs.GOLD: 50 }, "奖励 50 金币"),
		Quest.new(&"village_of_6", "城镇人口达到 6 名居民（含定居小兵）", 6, { GameDefs.GOLD: 100 }, "奖励 100 金币"),
	]


func _connect_signals() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.resident_settled.connect(_on_settled)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.hero_leveled.connect(_on_hero_leveled)
	EventBus.villager_spawned.connect(_on_villager_spawned)


func _process(_delta: float) -> void:
	if completed_all:
		return
	# 房屋 / 酒馆类目标在拆掉后要能回退（重算式而非累加式更稳）
	match _current().id:
		&"build_house":
			_update_progress(_houses_built)
		&"build_tavern":
			_update_progress(_taverns_built)
		&"kill_raiders", &"first_hunt":
			_update_progress(_kills)
		&"settle_villagers":
			_update_progress(_villagers_settled)
		&"population_4", &"village_of_6":
			# 存活人口口径：减员会掉进度（真实城镇）
			_update_progress(_alive_villagers())


func _current() -> Quest:
	return quests[clampi(current_index, 0, quests.size() - 1)]


func _update_progress(value: int) -> void:
	var q := _current()
	var clamped: int = clampi(value, 0, q.need)
	if clamped == q.have:
		return
	q.have = clamped
	EventBus.quest_updated.emit(current_index, q.desc, q.have, q.need)
	if q.have >= q.need:
		_complete_current()


func _complete_current() -> void:
	var q := _current()
	for id in q.reward:
		ResourceManager.add(id, q.reward[id])
	EventBus.quest_completed.emit(current_index, q.desc)
	EventBus.game_message.emit("目标达成：%s（%s）" % [q.desc, q.reward_text], Color(0.5, 1.0, 0.6))
	AudioManager.play_sfx(&"quest_done")
	current_index += 1
	if current_index >= quests.size():
		completed_all = true
		EventBus.game_message.emit("全部目标达成！城镇步入自由发展时代。", Color(1.0, 0.9, 0.4))
	else:
		_broadcast_current()


func _broadcast_current() -> void:
	if completed_all:
		return
	var q := _current()
	EventBus.quest_updated.emit(current_index, q.desc, q.have, q.need)


# ---- 信号累计 ----

func _on_building_placed(building: Node, _cell: Vector2i) -> void:
	if building == null or not is_instance_valid(building):
		return
	match building.def.id:
		&"house":
			_houses_built += 1
		&"tavern":
			_taverns_built += 1


func _on_settled(_name: String, _house: Node) -> void:
	_villagers_settled += 1


func _on_villager_spawned(_villager: Node) -> void:
	# 村民计数以实际存活数为准（死亡会减员；人口类任务应看当前而非历史）
	_villagers_settled = maxi(_villagers_settled, _alive_villagers())


## 城镇存活人口（v10 起定居小兵计入；v21 起小兵全部来自流民定居觉醒）。
func _alive_villagers() -> int:
	var count: int = 0
	for n in get_tree().get_nodes_in_group("player_unit"):
		if not is_instance_valid(n) or not (n is Pawn) or (n as Pawn).is_dead_flag:
			continue
		if n is Colonist or n is Soldier:
			count += 1
	return count


func _on_enemy_died(_enemy: Node, _killer: Node) -> void:
	_kills += 1


func _on_hero_leveled(hero: Node, level: int) -> void:
	if not completed_all and _current().id == &"hero_level3":
		_update_progress(level)
