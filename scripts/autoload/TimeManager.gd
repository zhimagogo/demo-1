extends Node
## ============================================================================
## TimeManager —— 游戏内时钟 + 倍速（驱动士兵昼夜日循环 / HUD 时刻显示）。
## time_scale 控制推进速度（0=暂停）。开放式沙盒：已移除入侵倒计时。
## v31 夜间守城准备：clock_frozen 只冻结昼夜时钟（Engine.time_scale 不动）——
## 战斗 / 移动 / 建造照常进行，玩家清残敌、配置小队后由开战令解冻。
## ============================================================================

@export var seconds_per_day: float = 120.0   # 真实秒 == 1 游戏日

var game_seconds: float = 0.0
var time_scale: float = 1.0
var day: int = 1
var hour: int = 6
var clock_frozen: bool = false   # v31 守城准备期：昼夜时钟停走（游戏本身照常运行）


## 是否处于夜间（20:00 ~ 06:00）。v34 起作为全局统一口径：
## Raider.is_night_now / 主角与巨龙的「回城疗伤」门控等都读这里，避免各处复制时间窗。
func is_night() -> bool:
	return hour >= 20 or hour < 6


func begin(start_hour: int = 6) -> void:
	# 让游戏从指定小时开始
	game_seconds = float(start_hour) * (seconds_per_day / 24.0)
	_recalc_clock()


func freeze_clock() -> void:
	clock_frozen = true


func unfreeze_clock() -> void:
	clock_frozen = false


func set_speed(mult: float) -> void:
	time_scale = mult
	Engine.time_scale = mult   # 全局缩放 _process/_physics_process 的 delta，真暂停/倍速
	EventBus.time_scale_changed.emit(mult)


func _process(delta: float) -> void:
	# delta 已被 Engine.time_scale 缩放，直接累加即可得到「游戏时间」；
	# 守城准备期（clock_frozen）只停昼夜时钟——天色钉在入夜时刻，其余系统照常。
	# _recalc_clock 不受冻结门控：直接改写 game_seconds（TimeManager.begin /
	# 测试跳钟）时 hour 仍须跟随刷新，否则昼夜系统读到陈旧小时。
	if not clock_frozen:
		game_seconds += delta
	_recalc_clock()
	EventBus.time_tick.emit(game_seconds, day, hour)


func _recalc_clock() -> void:
	var hours_total := int(game_seconds / (seconds_per_day / 24.0))
	var new_day: int = hours_total / 24 + 1
	var new_hour: int = hours_total % 24
	if new_day != day:
		day = new_day
		EventBus.day_changed.emit(day)
	hour = new_hour
