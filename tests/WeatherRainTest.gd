extends Node
## 雨效果回归（v5）：godot --headless --path . tests/WeatherRainTest.tscn
## 专注 WeatherSystem / DayNightCycle 的雨天运行时行为（渲染效果由 PixelCheck 对截图统计）：
## 强度演进与分档广播 / 雷电与闪电数值 / 风向摆动 / 湿度非对称干湿 / 粒子系统开关。

var _failures: int = 0
var _main: Node


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	world.get_node("WildlifeSpawner").set_process(false)
	var weather := world.get_node("WeatherSystem") as WeatherSystem
	var dnc := world.get_node("DayNightCycle") as DayNightCycle
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day

	# ---- 1) 强度演进：开场即中雨 → 满强度；雨停 → 快速消退 ----
	weather._apply_state(WeatherSystem.State.RAIN)
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	weather._thunder_timer = 99.0
	await get_tree().create_timer(1.0).timeout
	var s1: float = weather.rain_strength()
	_check(s1 > 0.3, "rain strength ramps up (%.2f after 1s)" % s1)
	await get_tree().create_timer(2.2).timeout
	_check(weather.rain_strength() > 0.95, "rain strength reaches target (%.2f)" % weather.rain_strength())
	# 粒子全部在发射，且量比随强度>0.9
	var all_emitting := true
	var any_ratio := 0.0
	for p in world.get_children():
		if p is GPUParticles3D and p.name.begins_with("Rain"):
			all_emitting = all_emitting and (p as GPUParticles3D).emitting
			if (p as GPUParticles3D).name == "RainMid":
				any_ratio = (p as GPUParticles3D).amount_ratio
	_check(all_emitting, "all rain particle systems emit in rain")
	_check(any_ratio > 0.9, "RainMid amount_ratio follows strength (%.2f)" % any_ratio)
	# 雨停：强度 0.30/s 消退 → 3.5s 内归零
	weather._apply_state(WeatherSystem.State.CLEAR)
	await get_tree().create_timer(3.6).timeout
	_check(weather.rain_strength() <= 0.02, "rain strength decays after rain stops (%.2f)" % weather.rain_strength())
	var none_emitting := true
	for p in world.get_children():
		if p is GPUParticles3D and p.name.begins_with("Rain"):
			none_emitting = none_emitting and not (p as GPUParticles3D).emitting
	_check(none_emitting, "rain particle systems stop emitting in clear weather")

	# ---- 2) 湿度非对称：淋湿快（0.5/s），晒干慢（0.018/s）----
	weather._apply_state(WeatherSystem.State.RAIN)
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	await get_tree().create_timer(1.5).timeout
	var wet_mid: float = weather._wetness
	_check(wet_mid > 0.5, "ground wets quickly in rain (%.2f after 1.5s)" % wet_mid)
	await get_tree().create_timer(1.5).timeout
	var wet_full: float = weather._wetness
	weather._apply_state(WeatherSystem.State.CLEAR)
	await get_tree().create_timer(1.5).timeout
	var wet_drying: float = weather._wetness
	_check(wet_full - wet_drying < wet_drying,
		"ground dries slower than it wets (%.2f→%.2f in 1.5s)" % [wet_full, wet_drying])

	_check(wet_drying > wet_full * 0.9, "wet ground persists after the shower")
	weather._strength = 0.0
	weather._tick_apply()
	_check(float(weather._ground_mat.get_shader_parameter("rain_amount")) == 0.0,
		"ground impacts stop independently of retained wetness")
	_check(float(weather._ground_mat.get_shader_parameter("wetness")) > 0.5,
		"puddles remain after impacts stop")
	for _i in 600:
		weather._update_strength(0.1)
	_check(weather._wetness < 0.001, "ground eventually dries completely")

	# ---- 3) 雷电：闪电数值双击闪烁 → 归零；强度门槛拦截毛毛雨 ----
	weather._apply_state(WeatherSystem.State.RAIN)
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	await get_tree().create_timer(3.2).timeout
	weather._thunder_strike()
	var flash_peak := 0.0
	for _i in 20:                       # 逐帧采样 0.3s，抓双击闪烁的峰值
		await get_tree().process_frame
		flash_peak = maxf(flash_peak, weather.lightning_flash)
	_check(flash_peak > 0.5, "lightning flash value rises on strike (%.2f)" % flash_peak)
	await get_tree().create_timer(1.0).timeout
	_check(weather.lightning_flash <= 0.01, "lightning flash decays back to zero (%.2f)" % weather.lightning_flash)
	# 毛毛雨不打雷：强度低于门槛时雷计时器不推进
	weather._strength = 0.3
	weather._thunder_timer = 0.05
	await get_tree().create_timer(0.4).timeout
	_check(absf(weather._thunder_timer - 0.05) < 0.001, "drizzle below thunder gate holds timer")

	# ---- 4) 风向摆动：随时间缓慢变化 ----
	var wind_a: Vector3 = weather._wind_vec()
	await get_tree().create_timer(0.5).timeout
	var wind_b: Vector3 = weather._wind_vec()
	_check((wind_a - wind_b).length() > 0.001, "wind vector drifts over time (%.4f)" % (wind_a - wind_b).length())

	# ---- 5) 分档广播：强度爬升应发出递增的 weather_changed ----
	var events: Array[float] = []
	var collector := func(_id: StringName, intensity: float): events.append(intensity)
	EventBus.weather_changed.connect(collector)
	weather._apply_state(WeatherSystem.State.RAIN)
	weather._strength_target = 1.0
	weather._strength_walk_timer = 99.0
	weather._bucket_last = -1
	events.clear()                       # 丢弃 _apply_state 的初始广播，只看强度分档
	await get_tree().create_timer(3.2).timeout
	EventBus.weather_changed.disconnect(collector)
	var rising := events.size() >= 2
	for i in range(1, events.size()):
		rising = rising and events[i] >= events[i - 1]
	_check(rising and events.size() >= 2, "weather_changed broadcasts rising intensity buckets (%d events)" % events.size())

	# ---- 6) DayNightCycle 风暴联动：强雨压暗太阳，放晴恢复 ----
	TimeManager.game_seconds = 12.0 / 24.0 * TimeManager.seconds_per_day
	await get_tree().create_timer(0.4).timeout
	var sun := world.get_node("Sun") as DirectionalLight3D
	var dim_energy: float = sun.light_energy
	weather._apply_state(WeatherSystem.State.CLEAR)
	await get_tree().create_timer(3.6).timeout
	_check(sun.light_energy > dim_energy * 1.3,
		"storm dims sun energy at noon (%.2f rain vs %.2f clear)" % [dim_energy, sun.light_energy])
	_check(dnc.daylight_factor() > 0.5, "daylight_factor exposed for rain tinting (%.2f)" % dnc.daylight_factor())

	# ---- 7) 调试循环：晴→云→雨→晴 ----
	weather.debug_cycle()   # 当前 CLEAR（上面已切）
	var seen := [weather.state]
	weather.debug_cycle()
	seen.append(weather.state)
	weather.debug_cycle()
	seen.append(weather.state)
	_check(seen == [WeatherSystem.State.CLOUDY, WeatherSystem.State.RAIN, WeatherSystem.State.CLEAR],
		"debug_cycle walks cloudy→rain→clear")

	print("WEATHER RAIN TEST: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
