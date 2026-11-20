extends Node
## ============================================================================
## v47 画质分级回归：档位数据 / 世界应用 / 后处理层 / 设置面板 / 草坪性能契约。
##
##   bash tools/godot_locked.sh --headless --path . tests/RenderQualityTest.tscn
##
## 覆盖：
##   1. RenderQuality autoload 存在、四档预设字段完整且成本单调；
##   2. set_preset 把 SSAO / SSIL / 体积雾 / 阴影 / 后处理 / Viewport 落到节点；
##   3. GameSettings 的 quality 键可读写并持久化；
##   4. SettingsPanel 有「画质档位」下拉且与当前档位同步；
##   5. 草坪 shader 不再含逐片元 discard（early-Z 性能契约），且保留逐叶塌缩。
## ============================================================================

var failures := 0
var _world: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _post: CanvasLayer


func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _run() -> void:
	var rq := get_node_or_null("/root/RenderQuality")
	check(rq != null, "RenderQuality autoload exists")
	if rq == null:
		_finish()
		return
	var original_tier: int = rq.tier()
	var original_quality := GameSettings.quality()

	# ---- 1) 预设数据 ----
	check(rq.PRESETS.size() == 4, "four quality presets")
	check(rq.TIER_NAMES == ["低", "中", "高", "极致"], "tier names are player-facing Chinese")
	var required := ["scale", "msaa", "screen_aa", "ssao", "ssil", "volumetric", "post_fx",
		"shadow_mode", "shadow_distance", "shadow_angular", "shadow_soft", "shadow_atlas",
		"grass_range", "decor_range", "split_1", "split_2", "split_3", "fade_start"]
	for i in rq.PRESETS.size():
		var preset: Dictionary = rq.PRESETS[i]
		for key in required:
			if not preset.has(key):
				check(false, "preset %d has %s" % [i, key])
		check(String(preset["name"]) == rq.TIER_NAMES[i], "preset %d name matches" % i)
	var low: Dictionary = rq.PRESETS[0]
	var medium: Dictionary = rq.PRESETS[1]
	var high: Dictionary = rq.PRESETS[2]
	var ultra: Dictionary = rq.PRESETS[3]
	check(float(low["shadow_distance"]) < float(medium["shadow_distance"])
		and float(medium["shadow_distance"]) < float(high["shadow_distance"])
		and float(high["shadow_distance"]) <= float(ultra["shadow_distance"]),
		"shadow distance grows with tier")
	check(bool(low["ssao"]) == false and bool(high["ssao"]) and bool(high["ssil"]),
		"SSAO only above low, SSIL from high")
	check(bool(high["volumetric"]) and not bool(medium["volumetric"]),
		"volumetric fog is a high+ feature")
	check(int(high["msaa"]) == 0 and int(ultra["msaa"]) > 0,
		"high keeps SMAA headroom; ultra enables MSAA")

	# ---- 2) 世界应用 ----
	_world = Node3D.new()
	_world.name = "QualityTestWorld"
	add_child(_world)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	we.environment = _env
	_world.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_world.add_child(_sun)
	_fill = DirectionalLight3D.new()
	_fill.name = "FillLight"
	_fill.shadow_enabled = false
	_world.add_child(_fill)
	_post = load("res://scripts/systems/PostFx.gd").new() as CanvasLayer
	_post.name = "PostFx"
	_world.add_child(_post)
	await settle()

	for i in rq.PRESETS.size():
		rq.set_preset(i, false)
		await settle()
		var preset: Dictionary = rq.preset()
		check(_env.ssao_enabled == bool(preset["ssao"]), "tier %d applies SSAO" % i)
		check(_env.ssil_enabled == bool(preset["ssil"]), "tier %d applies SSIL" % i)
		check(_env.volumetric_fog_enabled == bool(preset["volumetric"]), "tier %d applies volumetric fog" % i)
		check(_sun.directional_shadow_mode == int(preset["shadow_mode"]), "tier %d applies shadow mode" % i)
		check(is_equal_approx(_sun.directional_shadow_max_distance, float(preset["shadow_distance"])),
			"tier %d applies shadow distance" % i)
		check(is_equal_approx(_sun.light_angular_distance, float(preset["shadow_angular"])),
			"tier %d applies PCSS angular diameter" % i)
		check(_post.visible == bool(preset["post_fx"]), "tier %d toggles post FX" % i)
		check(get_window().msaa_3d == int(preset["msaa"]), "tier %d applies MSAA" % i)
		check(is_equal_approx(get_window().scaling_3d_scale, float(preset["scale"])),
			"tier %d applies 3D scale" % i)
	check(not _fill.shadow_enabled, "tier application never enables shadow on fill light")
	check(_post.layer == 0, "post FX layer stays below HUD CanvasLayer(1)")

	# ---- 3) 设置持久化（写后读回；结束时恢复原值）----
	GameSettings.set_quality(1)
	var cfg := ConfigFile.new()
	var loaded := cfg.load(GameSettings.SETTINGS_PATH) == OK
	check(loaded, "settings file readable")
	if loaded:
		check(int(cfg.get_value(GameSettings.SECTION, GameSettings.KEY_QUALITY, -1)) == 1,
			"quality key persisted to settings.cfg")
	GameSettings.set_quality(original_quality)
	check(GameSettings.quality() == original_quality, "quality restored after persistence check")

	# ---- 4) 设置面板 ----
	var panel := load("res://scripts/ui/SettingsPanel.gd").new() as PanelContainer
	panel.name = "QualitySettingsPanel"
	add_child(panel)
	await settle()
	print("SETTINGS PANEL min=%s size=%s" % [panel.get_combined_minimum_size(), panel.size])
	check(panel.quality_option != null, "settings panel builds quality option")
	if panel.quality_option != null:
		check(panel.quality_option.item_count == 4, "settings panel exposes four quality choices")
		check(panel.quality_option.selected == GameSettings.quality(), "quality option syncs with settings")
		panel.quality_option.select(0)
		panel.quality_option.item_selected.emit(0)
		await settle()
		check(rq.tier() == 0, "selecting quality applies immediately")
	panel.queue_free()
	rq.set_preset(original_tier, true)
	GameSettings.set_quality(original_quality)

	# ---- 5) 草坪 shader 性能契约 ----
	var code := FileAccess.get_file_as_string("res://assets/shaders/lawn.gdshader")
	check(code.find("discard;") == -1, "lawn shader avoids per-fragment discard (early-Z)")
	check(code.find("leaf_root_world") != -1, "lawn shader keeps per-leaf collapse path")
	check(code.find("dissolve_clip") == -1, "lawn shader no longer calls the dither dissolve")

	# ---- 6) 装饰视距按档位收紧 ----
	var mm := MultiMeshInstance3D.new()
	mm.name = "MM_grass_test"
	mm.multimesh = MultiMesh.new()
	var tree_chunk := MultiMeshInstance3D.new()
	tree_chunk.name = "MM_forest_test"
	tree_chunk.multimesh = MultiMesh.new()
	_world.add_child(mm)
	_world.add_child(tree_chunk)
	DecorationScatter.apply_visibility_ranges(_world, 84.0, 96.0)
	check(is_equal_approx(mm.visibility_range_end, 84.0), "grass visibility range follows low tier")
	check(is_equal_approx(tree_chunk.visibility_range_end, 96.0), "decor visibility range follows low tier")

	_finish()


func _finish() -> void:
	print("RENDER QUALITY TEST: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
