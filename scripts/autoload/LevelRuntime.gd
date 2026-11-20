extends Node
## ============================================================================
## LevelRuntime —— 关卡会话 + 关卡进度（v38，autoload 单例）。
##
## 两件事，都必须是「跨场景」的：
##   ① 会话：玩家在关卡选择地图上点了哪一关。Main.gd 进入 Main.tscn 后读它决定
##      这一局按哪套规则跑（序章剧本 / 开放沙盒）。**空选择 = 沙盒**，因此所有
##      直接实例化 Main.tscn 的旧测试与工具脚本行为完全不变。
##   ② 进度：每关已得星数与通关标记，落盘 user://level_progress.cfg（ConfigFile）。
##      只增不减：重打一次拿少星不会把记录改低。
##
## 契约：本单例只存状态 + 落盘，不碰场景树之外的任何玩法系统；
##      切场景的动作入口是 enter_level()，与 MainMenu._goto_game / PauseMenu 同型。
## ============================================================================

const PROGRESS_PATH := "user://level_progress.cfg"
const SECTION_STARS := "stars"
const SECTION_CLEARED := "cleared"

## 选中关卡变化（关卡地图刷新芯片/高亮用）。
signal level_selected(id: StringName)
## 某关成绩变化（通关/星级提升）。
signal progress_changed(id: StringName, stars: int)

## 当前选中的关卡 id；空 StringName = 没有选择（= 按开放沙盒跑）。
var selected_id: StringName = &""

var _stars: Dictionary = {}      # StringName -> int（已得星数）
var _cleared: Dictionary = {}    # StringName -> bool（是否通关过）


func _ready() -> void:
	_load_progress()


# ---- 会话 ----

## 选中一关；id 不在目录里返回 false 且不改状态。暂未开放的关卡不可选中。
func select(id: StringName) -> bool:
	var level := LevelCatalog.get_level(id)
	if level == null or level.is_coming_soon():
		return false
	selected_id = id
	level_selected.emit(id)
	return true


func selected_level() -> LevelDef:
	if selected_id == &"":
		return null
	return LevelCatalog.get_level(selected_id)


## 当前这一局该按哪一关跑：没选 → 沙盒（旧行为）；选坏了 → 同样回落沙盒。
func current_level() -> LevelDef:
	var level := selected_level()
	if level != null and level.is_playable():
		return level
	return LevelCatalog.sandbox()


func is_running(id: StringName) -> bool:
	var level := current_level()
	return level != null and level.id == id


func clear_selection() -> void:
	if selected_id == &"":
		return
	selected_id = &""
	level_selected.emit(&"")


## 进入一关：写会话 + 复位全局速度 + 切场景。返回 false = 没进（关卡不可玩）。
func enter_level(id: StringName) -> bool:
	var level := LevelCatalog.get_level(id)
	if level == null or not level.is_playable():
		return false
	select(id)
	TimeManager.set_speed(1.0)   # 从暂停菜单/关卡地图进来时可能残留 0 倍速
	get_tree().change_scene_to_file(level.scene_path)
	return true


## 回到关卡选择地图（关卡入口场景路径由 LevelSelect 自己声明）。
func enter_level_select(scene_path: String) -> void:
	TimeManager.set_speed(1.0)
	get_tree().change_scene_to_file(scene_path)


# ---- 进度 ----

func stars_of(id: StringName) -> int:
	return int(_stars.get(id, 0))


func is_cleared(id: StringName) -> bool:
	return bool(_cleared.get(id, false))


## 记录一次成绩：星级与通关标记只增不减。
func record_result(id: StringName, stars: int, cleared: bool = true) -> void:
	var level := LevelCatalog.get_level(id)
	var cap: int = level.star_total if level != null else 0
	var new_stars: int = clampi(stars, 0, maxi(cap, 0))
	var changed := false
	if new_stars > stars_of(id):
		_stars[id] = new_stars
		changed = true
	if cleared and not is_cleared(id):
		_cleared[id] = true
		changed = true
	if not changed:
		return
	_save_progress()
	progress_changed.emit(id, stars_of(id))


## 已得总星数 / 全部可玩关卡的星级上限（地图右上角汇总用）。
func total_stars() -> int:
	var total: int = 0
	for level in LevelCatalog.all():
		total += stars_of(level.id)
	return total


func total_capacity() -> int:
	var total: int = 0
	for level in LevelCatalog.all():
		if level.star_total > 0:
			total += level.star_total
	return total


## 清空全部进度（调试用；测试收尾也会调它）。
func reset_progress() -> void:
	_stars.clear()
	_cleared.clear()
	_save_progress()
	progress_changed.emit(&"", 0)


## 重新从磁盘读进度（测试收尾还原存档后，把内存态同步回去）。
func reload_progress() -> void:
	_load_progress()


# ---- 落盘 ----

func _load_progress() -> void:
	_stars.clear()
	_cleared.clear()
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		return   # 没有存档 = 全新进度
	for key in cfg.get_section_keys(SECTION_STARS):
		_stars[StringName(key)] = int(cfg.get_value(SECTION_STARS, key, 0))
	for key in cfg.get_section_keys(SECTION_CLEARED):
		_cleared[StringName(key)] = bool(cfg.get_value(SECTION_CLEARED, key, false))


func _save_progress() -> void:
	var cfg := ConfigFile.new()
	for id in _stars:
		cfg.set_value(SECTION_STARS, String(id), int(_stars[id]))
	for id in _cleared:
		cfg.set_value(SECTION_CLEARED, String(id), bool(_cleared[id]))
	cfg.save(PROGRESS_PATH)
