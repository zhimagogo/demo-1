class_name GameSettings
extends RefCounted
## ============================================================================
## GameSettings —— 全局游戏设置（静态类，无状态节点）。
## 主菜单与游戏内 ESC 菜单共用同一套键值；「改即应用、应用即保存」到
## user://settings.cfg，跨局跨场景持久。
##
## 设计约定：
##   · 全部走静态方法（项目里 UI 均为代码构建，无需 Autoload 也能随手调用）；
##   · apply_all(include_display) 里的 display 部分可选——Main 被测试当子场景
##     实例化时不改窗口（否则截图回归的窗口尺寸会被用户存档改掉）；
##   · 缺省值集中在 DEFAULTS；恢复默认 = 写回缺省并应用。
## ============================================================================

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "settings"

# ---- 键 ----
const KEY_WINDOW_MODE := "window_mode"            # 0=窗口化 1=全屏 2=无边框全屏
const KEY_VSYNC := "vsync"                        # 垂直同步
const KEY_MASTER_VOLUME := "master_volume"        # 主音量（0~1 线性）
const KEY_LOOK_SENSITIVITY := "look_sensitivity"  # 第三人称鼠标灵敏度（0.2~2.0 倍率）
const KEY_QUALITY := "quality"                    # 画质档位（0低 1中 2高 3极致；v47）

const WINDOW_MODE_NAMES := ["窗口化", "全屏", "无边框全屏"]
## v47 画质档位名称（实际参数在 RenderQuality.PRESETS；这里只给 UI/存档用）。
const QUALITY_NAMES := ["低", "中", "高", "极致"]
const QUALITY_DEFAULT := 2

const DEFAULTS := {
	KEY_WINDOW_MODE: 0,
	KEY_VSYNC: true,
	KEY_MASTER_VOLUME: 0.8,
	KEY_LOOK_SENSITIVITY: 1.0,
	KEY_QUALITY: QUALITY_DEFAULT,
}

static var _values: Dictionary = {}
static var _loaded: bool = false


# ============================================================================
# 一、读写与持久化
# ============================================================================

## 读取一个设置值（未保存过时返回缺省）。
static func get_value(key: String, default: Variant = null) -> Variant:
	_ensure_loaded()
	if _values.has(key):
		return _values[key]
	return DEFAULTS.get(key, default)


## 写入一个设置值：改即应用、应用即保存。
static func set_value(key: String, value: Variant) -> void:
	_ensure_loaded()
	_values[key] = value
	save_settings()
	_apply_single(key)


## 从磁盘加载（首次访问自动执行；path 参数供回归测试用独立临时文件）。
static func load_settings(path: String = SETTINGS_PATH) -> bool:
	_values = {}
	_loaded = true
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return false   # 无存档 = 全部用缺省，不算错误
	for key in DEFAULTS.keys():
		_values[key] = config.get_value(SECTION, key, DEFAULTS[key])
	return true


## 保存到磁盘（path 参数供回归测试用）。
static func save_settings(path: String = SETTINGS_PATH) -> void:
	var config := ConfigFile.new()
	for key in _values.keys():
		config.set_value(SECTION, key, _values[key])
	config.save(path)


## 恢复全部缺省值（改即应用即保存）。
static func reset_defaults() -> void:
	_values = DEFAULTS.duplicate()
	save_settings()
	apply_all()


# ============================================================================
# 二、语义访问器（面板与系统按名字取值，不碰裸键）
# ============================================================================

static func window_mode() -> int:
	return int(get_value(KEY_WINDOW_MODE))


static func vsync_enabled() -> bool:
	return bool(get_value(KEY_VSYNC))


static func master_volume() -> float:
	return clampf(float(get_value(KEY_MASTER_VOLUME)), 0.0, 1.0)


## 第三人称视角灵敏度倍率（ThirdPersonCamera.add_look_delta 每次调用时读取）。
static func look_sensitivity() -> float:
	return clampf(float(get_value(KEY_LOOK_SENSITIVITY)), 0.2, 2.0)


## 画质档位索引（0 低 / 1 中 / 2 高 / 3 极致）。实际应用见 RenderQuality。
static func quality() -> int:
	return clampi(int(get_value(KEY_QUALITY)), 0, QUALITY_NAMES.size() - 1)


static func set_quality(index: int) -> void:
	set_value(KEY_QUALITY, clampi(index, 0, QUALITY_NAMES.size() - 1))


static func set_window_mode(mode: int) -> void:
	set_value(KEY_WINDOW_MODE, clampi(mode, 0, WINDOW_MODE_NAMES.size() - 1))


static func set_vsync(enabled: bool) -> void:
	set_value(KEY_VSYNC, enabled)


static func set_master_volume(volume: float) -> void:
	set_value(KEY_MASTER_VOLUME, clampf(volume, 0.0, 1.0))


static func set_look_sensitivity(mult: float) -> void:
	set_value(KEY_LOOK_SENSITIVITY, clampf(mult, 0.2, 2.0))


# ============================================================================
# 三、应用到引擎
# ============================================================================

## 应用全部设置。include_display=false 时只应用音频/操控，不动窗口
## （Main 被测试当子场景实例化时用，避免覆盖截图回归的窗口尺寸）。
static func apply_all(include_display: bool = true) -> void:
	_ensure_loaded()
	apply_audio()
	if include_display:
		apply_display()


static func apply_display() -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var window: Window = (loop as SceneTree).root
	var mode := window_mode()
	match mode:
		1:
			# 专用全屏（独占/桌面分辨率切换，由系统管理）
			window.borderless = false
			window.mode = Window.MODE_FULLSCREEN
		2:
			# 无边框全屏：窗口化 + 去边框 + 铺满整屏（切换快、无分辨率切换黑闪）
			window.mode = Window.MODE_WINDOWED
			window.borderless = true
			var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
			window.position = screen.position
			window.size = screen.size
		_:
			# 窗口化
			window.borderless = false
			window.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled() else DisplayServer.VSYNC_DISABLED,
		DisplayServer.MAIN_WINDOW_ID)


static func apply_audio() -> void:
	# 全部播放器（AudioManager 池 + 环境声循环）都走 Master 总线，改一处即全局生效。
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	var volume := master_volume()
	AudioServer.set_bus_mute(bus, volume <= 0.005)
	if volume > 0.005:
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))


# ============================================================================
# 四、内部
# ============================================================================

static func _ensure_loaded() -> void:
	if not _loaded:
		load_settings()


static func _apply_single(key: String) -> void:
	match key:
		KEY_WINDOW_MODE, KEY_VSYNC:
			apply_display()
		KEY_MASTER_VOLUME:
			apply_audio()
		KEY_LOOK_SENSITIVITY:
			pass   # 灵敏度由 ThirdPersonCamera 每次读取，无需推送
		KEY_QUALITY:
			# 存档写入后由调用方（RenderQuality / 设置面板）负责应用；这里不主动推送，
			# 避免 GameSettings 与 RenderQuality 相互依赖。
			pass
