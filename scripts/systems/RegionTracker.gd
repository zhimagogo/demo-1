class_name RegionTracker
extends Node
## ============================================================================
## v40 区域追踪器：主角在「王城 + 六个主题区域」之间的进出判定与叙事播报。
## ============================================================================
## 区域数据唯一真相在 scripts/defs/WorldRegions.gd（本脚本只读，不改写 Region 字典）。
## WorldScenery._build_region_tracker() 在运行时用 load() + ResourceLoader.exists 把本脚本
## 实例化挂到 WorldScenery 下（节点名 RegionTracker）；脚本缺失时静默跳过，因此本脚本
## 不得依赖任何「必须先于自己就绪」的节点。
##
## 判定循环（0.35s 轮询一次，不逐帧）：
##   · 每轮取主角世界坐标 XZ，WorldRegions.region_at() → 区域字典（含王城 CITY）或 {}；
##   · 首次轮询只记录基线（出生点站在王城里不算「踏入」，避免一进游戏就弹横幅/播音效）；
##   · 进入新区域 → region_entered(id, name, subtitle, lore, first_time)；
##     会话内第一次踏入再补发 region_discovered(...) + 消息日志（lore，金色）+ 发现音效；
##   · 离开到无区域 / 跨到另一区域 → region_exited(旧 id)。
##
## 序章静音（_ready() 里按 LevelRuntime.current_level() 判定一次）：
##   剧情关（LevelDef.Kind.PROLOGUE，如序章）里本追踪器**完全不播报**——不广播任何
##   region_* 信号（HUD 因此不会弹横幅）、不写消息日志、不播音效，避免与序章剧本的
##   消息流 / 镜头演出打架。只读状态仍照常更新，Minimap 等取用方不受影响。
##   沙盒关 / 未选择关卡 / current_level() 为 null 时都按正常播报。
##
## 只读接口（Minimap / HUD / 测试可懒查找分组 "region_tracker" 后取用）：
##   current_region() / current_region_id() / discovered_ids() / is_discovered() / is_silent()
## 本脚本不落盘：发现状态只在本次会话内有效（测试可复现）。
## ============================================================================

## 位置轮询间隔（秒）。区域半径 ≥26m，走路 0.35s 位移远小于判定边界，足够灵敏。
const POLL_INTERVAL := 0.35

## 首次发现区域时的播报音效（assets/audio/quest_done.ogg）。
const DISCOVER_SFX := &"quest_done"

## 当前所在区域字典（WorldRegions 返回的 const 字典，只读；无区域时为空字典）。
var _current: Dictionary = {}
## 当前所在区域 id（无区域时 &""）。
var _current_id: StringName = &""
## 会话内已发现区域集合：id -> true。
var _discovered: Dictionary = {}
## 是否已经记过开局基线（首轮只记录、不播报）。
var _baseline_done: bool = false
## 轮询计时器。
var _poll_accum: float = 0.0
## 序章等剧情关静音：只更新只读状态，不广播任何 region_* 信号 / 日志 / 音效。
var _silent: bool = false


func _ready() -> void:
	add_to_group("region_tracker")
	# 关卡分流一次判定：剧情关（序章）静音，沙盒 / 未选择关卡正常播报。
	# 关卡选择在进场景前写 LevelRuntime，场景重载才会换关，因此 _ready() 判一次即可。
	_silent = _is_story_level()
	# 首轮立刻判定一次（此时主角已在 Main._ready 里生成，HUD 也已就绪），
	# 之后按 POLL_INTERVAL 节流轮询——不逐帧读位置。
	_poll_accum = POLL_INTERVAL
	set_process(true)


## 当前这一局是否为「剧情关」（序章）：是则完全不播报。
func _is_story_level() -> bool:
	var level := LevelRuntime.current_level()
	if level == null:
		return false          # 未选择关卡 = 沙盒关，正常播报
	return level.kind == LevelDef.Kind.PROLOGUE


func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < POLL_INTERVAL:
		return
	_poll_accum = 0.0
	_poll()


## 立即执行一次判定（测试 / 外部强制刷新用；正常游玩不需要调用）。
func poll_now() -> void:
	_poll()


# ============================================================================
# 只读接口
# ============================================================================

## 当前区域字典（含 name / subtitle / lore / accent / center / radius / kind …
## 字段见 WorldRegions；无区域返回 {}）。调用方只读，不要改写。
func current_region() -> Dictionary:
	return _current


## 当前区域 id（王城 = &"city"；无区域 = &""）。
func current_region_id() -> StringName:
	return _current_id


## 会话内已发现的区域 id 列表（顺序 = 发现顺序）。
func discovered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key in _discovered.keys():
		ids.append(StringName(key))
	return ids


## 某区域是否已在本次会话内发现过。
func is_discovered(region_id: StringName) -> bool:
	return _discovered.has(region_id)


## 本局是否处于「剧情关静音」状态（序章为 true；沙盒 / 未选择关卡为 false）。
func is_silent() -> bool:
	return _silent


# ============================================================================
# 判定
# ============================================================================

func _poll() -> void:
	if not is_inside_tree():
		return
	var hero := _find_hero()
	if hero == null:
		return   # 主角未出生 / 已释放的瞬间：保持上一次状态，等下一轮再判
	var pos: Vector3 = hero.global_position
	var region := WorldRegions.region_at(Vector2(pos.x, pos.z))
	var id: StringName = &""
	if not region.is_empty():
		id = StringName(region["id"])

	if not _baseline_done:
		_baseline_done = true
		_current = region
		_current_id = id
		return

	if id == _current_id:
		return   # 区域没变：不做任何广播

	# 序章剧本关：只同步只读状态，不广播（不弹横幅 / 不发信号 / 不写日志 / 不播音效）
	if _silent:
		_current = region
		_current_id = id
		return

	# 先离开旧区域（含跨区域直接切换的情况），再进入新区域
	if _current_id != &"":
		EventBus.region_exited.emit(_current_id)
	_current = region
	_current_id = id
	if id == &"":
		return   # 走到荒野：只发离开，没有进入

	_announce(region)


## 进入某区域：先发 region_entered；会话内首次再补 region_discovered + 故事日志 + 音效。
func _announce(region: Dictionary) -> void:
	var id := StringName(region.get("id", &""))
	var region_name := String(region.get("name", ""))
	var subtitle := String(region.get("subtitle", ""))
	var lore := String(region.get("lore", ""))
	var first_time := not _discovered.has(id)
	if first_time:
		_discovered[id] = true

	EventBus.region_entered.emit(id, region_name, subtitle, lore, first_time)
	if not first_time:
		return

	EventBus.region_discovered.emit(id, region_name, subtitle, lore)
	if lore != "":
		# HUD 的消息日志（EventLog）订阅 game_message；故事文本只在首次发现时进日志。
		EventBus.game_message.emit(lore, UIStyle.GOLD)
	AudioManager.play_sfx(DISCOVER_SFX)


## 找主角：优先 HeroController.hero（正常游戏路径），
## 兜底扫 player_unit 组并**按 Hero 类型筛**（组里还有 BaseCore，不能直接取第一个）。
## 全程 is_instance_valid 守卫——主角死亡复活 / 场景重载期间引用可能已释放。
func _find_hero() -> Hero:
	if not is_inside_tree():
		return null
	var controller := get_tree().get_first_node_in_group("hero_controller")
	if controller != null and is_instance_valid(controller):
		var maybe: Variant = controller.get("hero")
		if maybe != null and is_instance_valid(maybe) and maybe is Hero:
			return maybe as Hero
	for node in get_tree().get_nodes_in_group("player_unit"):
		if node != null and is_instance_valid(node) and node is Hero:
			return node as Hero
	return null
