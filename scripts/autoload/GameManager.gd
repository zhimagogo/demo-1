extends Node
## ============================================================================
## GameManager —— 全局游戏状态 + 阶段标记。
## 开放式经营沙盒：无定时入侵波次（野怪由 WildlifeSpawner 在城外持续刷新）。
## phase 保持在 BUILD；PAUSED / GAME_OVER 仍可用。Phase.COMBAT 暂为枚举占位（未使用）。
## ============================================================================

enum Phase { BUILD, COMBAT, PAUSED, GAME_OVER }

@export var player_base_max_health: int = 1000

var phase: int = Phase.BUILD
var player_base_health: int = 1000


func _ready() -> void:
	player_base_health = player_base_max_health
	EventBus.game_over.connect(_on_game_over)


# ---- 阶段切换 ----
func change_phase(p: int) -> void:
	if phase == p:
		return
	var old := phase
	phase = p
	EventBus.phase_changed.emit(int(old), int(p))
	print("[GameManager] 阶段切换: %s -> %s" % [Phase.keys()[old], Phase.keys()[p]])


func set_paused(paused: bool) -> void:
	# 通过 Engine.time_scale 暂停一切；不切换 phase
	TimeManager.set_speed(0.0 if paused else 1.0)


# ---- 基地受损 / 结束 ----
func damage_base(amount: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	player_base_health = max(0, player_base_health - amount)
	if player_base_health <= 0:
		request_game_over(false)


func request_game_over(victory: bool) -> void:
	change_phase(Phase.GAME_OVER)
	TimeManager.set_speed(0.0)
	EventBus.game_over.emit(victory)


## v31 夜间守城：玩家在守城准备期确认开战（HUD「准备守城」按钮 / 回车）。
## 只在昼夜时钟冻结（准备期）时有效；广播 night_defense_started，由 WildlifeSpawner
## 解冻时钟并发起夜潮攻城。动作入口集中在 GameManager，与 request_game_over 同型。
func request_night_defense() -> void:
	if phase == Phase.GAME_OVER:
		return
	if not TimeManager.clock_frozen:
		return   # 非准备期（已开战 / 白天）：幂等忽略
	EventBus.night_defense_started.emit()


func _on_game_over(victory: bool) -> void:
	print("[GameManager] 游戏结束 victory=%s" % victory)
