extends Node
## ============================================================================
## UI 图标/面板回归（v6「真实开源图标替换字徽」独立验收，结构层证据）。
##
## godot --headless --path . tests/UiIconTest.tscn --log-file /private/tmp/demo-1-uiicon.log
##
## 五组断言：
##   1) 45 个冻结 id → IconDB.has_icon、PNG 文件存在且字节数 > 0、导入后宽度 ≥ 64，
##      并用 Image.load_from_file 直读磁盘 PNG 证明「不是空白/全透明/纯黑块」；
##   2) assets/ui/icons/icons.json 逐条含 author/url/license、条目数 == 45、
##      CREDITS.md 含 "CC BY 3.0"，且 tools/fetch_icons.py 的 ICONS 表与本测试的
##      冻结 id 表、与 icons.json 三方一致（防止「改了管线没改运行时」）；
##   3) IconRect / IconBadge 在缺图 id 下不报错、回退 IconChar 字徽（uses_texture()==false）；
##   4) 真实实例化 scenes/ui/HUD.tscn，统计 UI 树里 texture != null 的 TextureRect 数量 > 0
##      （「真的接了真图标」的硬证据），并打印统计值；
##   5) 逐面板构造（TopBar/BuildMenu/HeroPanel/QuestPanel/SelectionInfoPanel/
##      EventLog/BossBanner/TutorialOverlay/Minimap）+ 在真实 Main 场景里触发各自内容路径，
##      断言每个面板子树至少 1 个非空图标贴图。
##
## 确定性：不联网、不依赖随机数与时间漂移；断言全部基于资源元数据、节点树结构与像素统计。
## 像素级证据（「代码接了但渲染成空白/黑块」）在 tests/UiCapture.gd + tests/PixelCheck.gd。
## ============================================================================

const ICON_DIR := "res://assets/ui/icons/"
const ICONS_JSON_PATH := ICON_DIR + "icons.json"
const CREDITS_PATH := ICON_DIR + "CREDITS.md"
const PIPELINE_PATH := "res://tools/fetch_icons.py"

## 冻结 id 数量（与 tools/fetch_icons.py 的 ICONS 表、icons.json 条目数三方一致）。
const FROZEN_COUNT := 42

## 冻结 id 表（42 个）。**刻意在测试里硬编码**：这是独立于 tools/fetch_icons.py 与
## icons.json 的第三份声明——任何一方被改动而另外两方没跟上，这里就会报错。
const FROZEN_IDS := [
	"res_wood", "res_stone", "res_food", "res_gold",
	"building_wall", "building_house", "building_tavern",
	"stat_pop", "stat_soldier", "stat_hero", "stat_enemy",
	"time_day", "time_night",
	"weather_clear", "weather_cloud", "weather_rain", "weather_storm",
	"unit_melee", "unit_ranged", "skill_slash", "skill_flame",
	"quest", "event_log", "tutorial", "boss", "hp", "xp", "map", "compass",
	"warning", "close", "help", "pause", "play", "fast_forward", "home",
	"tool_hammer", "target", "attack", "carry", "shield", "crown",
]

## 面板名（HUD 属性名 → 断言用标签），顺序即报告顺序。
const PANEL_PROPS := [
	"top_bar", "build_menu", "hero_panel", "quest_panel",
	"selection_panel", "event_log", "boss_banner", "tutorial_overlay", "minimap",
]
const PANEL_LABELS := [
	"TopBar", "BuildMenu", "HeroPanel", "QuestPanel",
	"SelectionInfoPanel", "EventLog", "BossBanner", "TutorialOverlay", "Minimap",
]

## 面板脚本路径（自绘面板做源码契约断言用）。
const PANEL_SCRIPTS := {
	"top_bar": "res://scripts/ui/TopBar.gd",
	"build_menu": "res://scripts/ui/BuildMenu.gd",
	"hero_panel": "res://scripts/ui/HeroPanel.gd",
	"quest_panel": "res://scripts/ui/QuestPanel.gd",
	"selection_panel": "res://scripts/ui/SelectionInfoPanel.gd",
	"event_log": "res://scripts/ui/EventLog.gd",
	"boss_banner": "res://scripts/ui/BossBanner.gd",
	"tutorial_overlay": "res://scripts/ui/TutorialOverlay.gd",
	"minimap": "res://scripts/ui/Minimap.gd",
}

## 纯自绘面板：把 IconDB 贴图直接 draw_texture_rect 到画布上，子树里没有 TextureRect 控件。
## 这类面板不能用「TextureRect 计数」判定，改用「源码经 IconDB 取真贴图」+ 真机截图复核。
const CANVAS_DRAWN_PANELS := ["minimap"]

## 真实 Main 场景里「触发各自内容后应当可见」的面板。
## 注意：这里断言的是**玩家真的能看到**——控件里有贴图不等于面板显示出来了。
## （v21 起招募菜单已随兵营删除。）
const VISIBLE_PANELS := [
	"top_bar", "build_menu", "quest_panel", "selection_panel", "event_log",
	"minimap", "boss_banner", "hero_panel", "tutorial_overlay",
]

## 图标内容阈值（直读磁盘 PNG，128×128 RGBA）。
## 语义：一个「真的画了东西的白色前景图标」必须同时满足
##   · 不透明像素占比 ∈ [1%, 95%] —— 全透明 = 空白洞；接近 100% = 一整块实心方块（黑底没清掉）；
##   · 不透明像素里 ≥ 85% 是白色（管线约定：去底 + 强制 #ffffff，运行时用 modulate 调色）。
## 阈值实测标定见 artifacts/UI验收报告.md（45 个图标实测占比区间）。
const ICON_MIN_COVERAGE := 0.01
const ICON_MAX_COVERAGE := 0.95
const ICON_MIN_WHITE_FRAC := 0.85
const ICON_ALPHA_CUTOFF := 0.25        # alpha > 该值算「不透明前景像素」
const ICON_WHITE_CUTOFF := 0.78        # rgb 三分量均 > 该值算「白色前景」

var _failures: int = 0
var _warnings: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: ", msg)


# ============================================================================
# 1) 冻结 id 全部可解析 + 磁盘 PNG 真有内容
# ============================================================================
func _check_frozen_ids() -> void:
	print("--- 1) 冻结 id 表（%d）与 PNG 实体 ---" % FROZEN_IDS.size())
	_check(FROZEN_IDS.size() == FROZEN_COUNT, "冻结 id 表条目数 == %d（实测 %d）" % [FROZEN_COUNT, FROZEN_IDS.size()])

	var bad_path: Array[String] = []
	var missing_icon: Array[String] = []
	var missing_file: Array[String] = []
	var empty_file: Array[String] = []
	var narrow: Array[String] = []
	var bad_type: Array[String] = []
	var blank: Array[String] = []
	var dark: Array[String] = []
	var sampled: int = 0
	var cover_min := 1.0
	var cover_max := 0.0
	var cover_min_id := ""
	var white_min := 1.0
	var white_min_id := ""

	for id in FROZEN_IDS:
		var sid := StringName(id)
		var path := IconDB.path_for(sid)
		if path != "%s%s.png" % [ICON_DIR, id]:
			bad_path.append(id)

		var tex := IconDB.get_texture(sid)
		if tex == null:
			missing_icon.append(id)
		else:
			if tex.get_width() < 64 or tex.get_height() < 64:
				narrow.append("%s(%dx%d)" % [id, tex.get_width(), tex.get_height()])
			if not (tex is CompressedTexture2D or tex is ImageTexture):
				bad_type.append("%s(%s)" % [id, tex.get_class()])

		# 磁盘实体：字节数 > 0 + 直读像素统计（绕开导入，证明文件本身有内容）
		if not FileAccess.file_exists(path):
			missing_file.append(id)
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() <= 0:
			empty_file.append(id)
			continue
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null or img.is_empty():
			blank.append("%s(读不出像素)" % id)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var total := img.get_width() * img.get_height()
		var opaque := 0
		var white := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a <= ICON_ALPHA_CUTOFF:
					continue
				opaque += 1
				if c.r > ICON_WHITE_CUTOFF and c.g > ICON_WHITE_CUTOFF and c.b > ICON_WHITE_CUTOFF:
					white += 1
		sampled += 1
		var cov := float(opaque) / float(maxi(total, 1))
		if cov < ICON_MIN_COVERAGE or cov > ICON_MAX_COVERAGE:
			blank.append("%s(前景 %.1f%%)" % [id, cov * 100.0])
		if opaque > 0:
			var wf := float(white) / float(opaque)
			if wf < ICON_MIN_WHITE_FRAC:
				dark.append("%s(白 %.0f%%)" % [id, wf * 100.0])
			if wf < white_min:
				white_min = wf
				white_min_id = id
		if cov < cover_min:
			cover_min = cov
			cover_min_id = id
		if cov > cover_max:
			cover_max = cov

	_check(bad_path.is_empty(), "IconDB.path_for() 全部符合 res://assets/ui/icons/<id>.png 约定（异常：%s）" % _join(bad_path))
	_check(missing_icon.is_empty(), "全部 %d 个 id 的 IconDB.has_icon() == true（缺：%s）"
		% [FROZEN_IDS.size(), _join(missing_icon)])
	_check(missing_file.is_empty(), "每个 id 的 PNG 文件都存在（缺：%s）" % _join(missing_file))
	_check(empty_file.is_empty(), "每个 PNG 字节数 > 0（空文件：%s）" % _join(empty_file))
	_check(narrow.is_empty(), "导入后贴图宽度/高度 ≥ 64（不达标：%s）" % _join(narrow))
	_check(bad_type.is_empty(), "每个 id 解析为纹理资源（异常：%s）" % _join(bad_type))
	# 「代码接了图标但 PNG 是空白/实心块」的结构级拦截——像素级拦截见 PixelCheck
	_check(blank.is_empty(), "PNG 前景占比 ∈ [%.0f%%, %.0f%%]（异常：%s）"
		% [ICON_MIN_COVERAGE * 100.0, ICON_MAX_COVERAGE * 100.0, _join(blank)])
	_check(dark.is_empty(), "PNG 前景 ≥ %.0f%% 为纯白（残留黑底/来源不符：%s）"
		% [ICON_MIN_WHITE_FRAC * 100.0, _join(dark)])
	if sampled > 0:
		print("STAT 图标前景占比 min=%.1f%%(%s) max=%.1f%% | 白占比 min=%.0f%%(%s) 样本=%d"
			% [cover_min * 100.0, cover_min_id, cover_max * 100.0, white_min * 100.0, white_min_id, sampled])
	else:
		_warnings += 1
		print("WARN 无任何 PNG 可直读采样（资产尚未落地？）")


# ============================================================================
# 2) 元数据 / 署名 / 三方 id 表一致
# ============================================================================
func _check_metadata() -> void:
	print("--- 2) icons.json / CREDITS.md / 管线 id 表 ---")
	_check(FileAccess.file_exists(ICONS_JSON_PATH), "icons.json 存在")
	if not FileAccess.file_exists(ICONS_JSON_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ICONS_JSON_PATH))
	_check(parsed is Dictionary, "icons.json 是合法 JSON 对象")
	if not (parsed is Dictionary):
		return
	var doc: Dictionary = parsed
	var top_license := String(doc.get("license", ""))
	_check(top_license.contains("CC BY 3.0"), "icons.json 顶层 license 含 CC BY 3.0（%s）" % top_license)
	_check(String(doc.get("source", "")).contains("game-icons.net"),
		"icons.json 顶层 source 指向 game-icons.net（%s）" % doc.get("source", ""))
	if not (doc.get("icons", null) is Dictionary):
		_check(false, "icons.json 含 icons 字典")
		return
	var entries: Dictionary = doc["icons"]
	_check(entries.size() == FROZEN_COUNT, "icons.json 条目数 == %d（实测 %d）" % [FROZEN_COUNT, entries.size()])
	if doc.has("count"):
		_check(int(doc.get("count", -1)) == FROZEN_COUNT,
			"icons.json 顶层 count == %d（实测 %s）" % [FROZEN_COUNT, doc.get("count")])

	var bad_author: Array[String] = []
	var bad_url: Array[String] = []
	var bad_license: Array[String] = []
	var bad_png: Array[String] = []
	var unknown: Array[String] = []
	for key in entries.keys():
		var id := String(key)
		var meta = entries[key]
		if not (meta is Dictionary):
			unknown.append(id)
			continue
		var m: Dictionary = meta
		if String(m.get("author", "")).strip_edges().is_empty():
			bad_author.append(id)
		if not String(m.get("url", "")).begins_with("http"):
			bad_url.append(id)
		if String(m.get("license", "")) != "CC BY 3.0":
			bad_license.append("%s:%s" % [id, m.get("license", "")])
		if String(m.get("png", "")) != "%s%s.png" % [ICON_DIR, id]:
			bad_png.append(id)
		if not FROZEN_IDS.has(id):
			unknown.append(id)

	_check(bad_author.is_empty(), "每条目含非空 author（缺：%s）" % _join(bad_author))
	_check(bad_url.is_empty(), "每条目含 http(s) url（缺：%s）" % _join(bad_url))
	_check(bad_license.is_empty(), "每条目 license == 'CC BY 3.0'（异常：%s）" % _join(bad_license))
	_check(bad_png.is_empty(), "每条目 png 路径符合 IconDB 约定（异常：%s）" % _join(bad_png))
	_check(unknown.is_empty(), "icons.json 不含冻结表之外/非字典条目（异常：%s）" % _join(unknown))

	var absent: Array[String] = []
	for id in FROZEN_IDS:
		if not entries.has(id):
			absent.append(id)
	_check(absent.is_empty(), "icons.json 覆盖全部 %d 个冻结 id（缺：%s）" % [FROZEN_COUNT, _join(absent)])

	_check(FileAccess.file_exists(CREDITS_PATH), "CREDITS.md 存在")
	if FileAccess.file_exists(CREDITS_PATH):
		var credits := FileAccess.get_file_as_string(CREDITS_PATH)
		_check(credits.contains("CC BY 3.0"), "CREDITS.md 含 'CC BY 3.0'")
		_check(credits.contains("game-icons.net"), "CREDITS.md 含来源域名 game-icons.net")
		var credited: Array[String] = []
		for id in FROZEN_IDS:
			if not credits.contains(id):
				credited.append(id)
		_check(credited.is_empty(), "CREDITS.md 署名逐条覆盖 %d 个 id（漏：%s）" % [FROZEN_COUNT, _join(credited)])

	# 管线 id 表（第三方独立来源）：与测试冻结表、icons.json 三方一致
	var pipeline_ids := _parse_pipeline_ids()
	_check(pipeline_ids.size() > 0, "能解析 tools/fetch_icons.py 的 ICONS 表（%d 条）" % pipeline_ids.size())
	if pipeline_ids.size() > 0:
		var diff_pipeline: Array[String] = []
		for id in FROZEN_IDS:
			if not pipeline_ids.has(id):
				diff_pipeline.append("缺:" + id)
		for id in pipeline_ids:
			if not FROZEN_IDS.has(id):
				diff_pipeline.append("多:" + id)
		_check(diff_pipeline.is_empty(), "管线 ICONS 表 == 测试冻结 id 表（差异：%s）" % _join(diff_pipeline))


## 解析 tools/fetch_icons.py 里 ICONS 字典的 key（形如 `    "res_wood": "delapouite/log",`）。
func _parse_pipeline_ids() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(PIPELINE_PATH):
		return out
	var text := FileAccess.get_file_as_string(PIPELINE_PATH)
	var in_block := false
	var re := RegEx.new()
	re.compile("^\\s*\"([a-z0-9_]+)\"\\s*:\\s*\"[^\"]+\"\\s*,?\\s*$")
	for raw_line in text.split("\n"):
		var line := String(raw_line)
		if line.contains("ICONS: dict"):
			in_block = true
			continue
		if not in_block:
			continue
		if line.begins_with("}"):
			break
		var m := re.search(line)
		if m != null:
			out.append(m.get_string(1))
	return out


func _join(items: Array) -> String:
	return "无" if items.is_empty() else ", ".join(items)


# ============================================================================
# 3) 缺图回退（IconRect / IconBadge）
# ============================================================================
func _check_fallback() -> void:
	print("--- 3) 缺图回退字徽 ---")
	var bogus := &"__no_such_icon__"
	_check(not IconDB.has_icon(bogus), "IconDB.has_icon(缺图 id) == false")

	var ir := IconRect.new(bogus, 24, UIStyle.GOLD, "木")
	add_child(ir)
	_check(not ir.uses_texture(), "IconRect 缺图时 uses_texture() == false（不报错）")
	_check(ir.texture == null, "IconRect 缺图时 texture == null（由字徽兜底，不是空白洞）")
	_check(_find_first(ir, "IconChar") != null, "IconRect 缺图时子节点含 IconChar 字徽")
	_check(ir.custom_minimum_size == Vector2(24, 24), "IconRect 缺图仍保留 24px 占位尺寸")

	# 无 fallback_char 时不建字徽，但也不得报错
	var ir_bare := IconRect.new(bogus, 16, UIStyle.GOLD, "")
	add_child(ir_bare)
	_check(not ir_bare.uses_texture() and _find_first(ir_bare, "IconChar") == null,
		"IconRect 无 fallback_char 时静默空置、不报错")

	var badge := IconBadge.new(bogus, 28, UIStyle.GOLD, "木")
	add_child(badge)
	var inner := _find_first(badge, "IconRect") as IconRect
	_check(inner != null, "IconBadge 含内部 IconRect")
	if inner != null:
		_check(not inner.uses_texture(), "IconBadge 缺图时内部 IconRect.uses_texture() == false")
	_check(_find_first(badge, "IconChar") != null, "IconBadge 缺图时回退到 IconChar 字徽")

	# 真实 id 必须走贴图路径（证明回退不是「永远回退」）
	var ok_rect := IconRect.new(&"res_wood", 24, UIStyle.GOLD, "木")
	add_child(ok_rect)
	_check(ok_rect.uses_texture(), "IconRect 真图标 id 时 uses_texture() == true")
	_check(_find_first(ok_rect, "IconChar") == null, "IconRect 真图标时不建字徽（无叠字）")
	var ok_badge := IconBadge.new(&"building_house", 28, UIStyle.GOLD, "房")
	add_child(ok_badge)
	var ok_inner := _find_first(ok_badge, "IconRect") as IconRect
	_check(ok_inner != null and ok_inner.uses_texture(),
		"IconBadge 真图标 id 时内部 IconRect.uses_texture() == true")

	# 缺图 → 真图（换 id）后应撤掉字徽，避免「图 + 字」双显
	var swap := IconRect.new(bogus, 24, UIStyle.GOLD, "木")
	add_child(swap)
	swap.set_icon(&"res_stone", 24, "木")
	_check(swap.uses_texture(), "IconRect 由缺图切到真图后 uses_texture() == true")

	for n in [ir, ir_bare, badge, ok_rect, ok_badge, swap]:
		n.queue_free()


func _find_first(node: Node, what: String) -> Node:
	for child in node.get_children():
		if what == "IconChar" and child is IconChar:
			return child
		if what == "IconRect" and child is IconRect:
			return child
		var deep := _find_first(child, what)
		if deep != null:
			return deep
	return null


# ============================================================================
# 4) 真实构造 HUD：统计非空贴图
# ============================================================================
func _check_hud_textures() -> void:
	print("--- 4) 真实实例化 scenes/ui/HUD.tscn ---")
	var packed := load("res://scenes/ui/HUD.tscn") as PackedScene
	_check(packed != null, "HUD.tscn 可加载")
	if packed == null:
		return
	var hud := packed.instantiate()
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	var rects := _count_tex_rects(hud)
	var icon_rects := _count_real_icon_rects(hud)
	var icon_chars := _count_icon_chars(hud)
	print("STAT HUD 非空 TextureRect = %d | IconRect 走真图 = %d | IconChar 字徽 = %d"
		% [rects, icon_rects, icon_chars])
	_check(rects > 0, "HUD UI 树里 texture != null 的 TextureRect 数量 > 0（实测 %d）" % rects)
	_check(icon_rects > 0, "HUD 里 IconRect 走真实贴图（实测 %d）" % icon_rects)
	hud.queue_free()
	await get_tree().process_frame


# ============================================================================
# 5a) 逐面板独立构造（不报错）
# ============================================================================
func _check_panels_standalone() -> void:
	print("--- 5a) 逐面板独立构造（不报错） ---")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(1600, 1000)
	add_child(host)
	await get_tree().process_frame
	for label in PANEL_LABELS:
		var p := _make_panel(label)
		if p == null:
			_check(false, "%s 可构造" % label)
			continue
		host.add_child(p)
		await get_tree().process_frame
		var alive: bool = is_instance_valid(p) and p.is_inside_tree()
		print("STAT 独立构造 %-20s 非空贴图=%d" % [label, _count_tex_rects(p)])
		_check(alive, "%s 独立构造后仍在树内、无致命错误" % label)
		p.queue_free()
		await get_tree().process_frame
	host.queue_free()
	await get_tree().process_frame


func _make_panel(label: String) -> Control:
	match label:
		"TopBar": return TopBar.new()
		"BuildMenu": return BuildMenu.new()
		"HeroPanel": return HeroPanel.new()
		"QuestPanel": return QuestPanel.new()
		"SelectionInfoPanel": return SelectionInfoPanel.new()
		"EventLog": return EventLog.new()
		"BossBanner": return BossBanner.new()
		"TutorialOverlay": return TutorialOverlay.new()
		"Minimap": return Minimap.new()
	return null


# ============================================================================
# 5b) 真实 Main 场景：逐面板内容触发 + 至少 1 个非空图标
# ============================================================================
func _check_panels_live() -> void:
	print("--- 5b) 真实 Main 场景：逐面板内容触发 + 至少 1 个非空图标 ---")
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	_check(packed != null, "Main.tscn 可加载")
	if packed == null:
		return
	var main := packed.instantiate()
	add_child(main)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := main.get_node_or_null("HUD")
	_check(hud != null, "Main 场景含 HUD 节点")
	if hud == null:
		return

	# —— 内容触发：全部走真实信号 / 真实系统，不直接改私有字段 ——
	EventBus.game_message.emit("UI 图标验收：占位消息 A", Color(1, 1, 1))
	EventBus.game_message.emit("UI 图标验收：占位消息 B", UIStyle.GOLD)

	var world := main.get_node_or_null("WorldRoot")
	var spawner: Node = null if world == null else world.get_node_or_null("PawnSpawner")
	var boss: Node = null
	if spawner != null and spawner.has_method("spawn_raider"):
		boss = spawner.spawn_raider(Vector3(34.0, 0.0, 34.0), GameDefs.raider_boss_def())
	_check(boss != null, "可经 PawnSpawner 刷出头目（用于横幅内容触发）")
	EventBus.boss_spawned.emit(boss)

	var tut = get_tree().get_first_node_in_group("tutorial_system")
	if tut != null:
		tut.restart()
	# v17 去冗余：单选主角不再弹 SelectionInfoPanel（主角卡唯一来源 = HeroPanel），
	# 选中面板的内容路径改由**选一名士兵**驱动（与 UiCapture 的 ui-select-soldier 一致）
	var sel_pawn: Node = null
	if spawner != null and spawner.has_method("spawn_soldier"):
		sel_pawn = spawner.call("spawn_soldier", GameDefs.settler_warrior_def(), Vector3(6.0, 0.0, 6.0))
	_check(sel_pawn != null, "可经 PawnSpawner 刷出士兵（用于选中面板内容触发）")
	if sel_pawn != null:
		SelectionManager.select_only(sel_pawn)
	await get_tree().process_frame
	await get_tree().process_frame

	var total_rects := _count_tex_rects(hud)
	print("STAT 真实 HUD 非空 TextureRect 合计 = %d | 真图 IconRect = %d | 字徽 IconChar = %d"
		% [total_rects, _count_real_icon_rects(hud), _count_icon_chars(hud)])
	_check(total_rects > 0, "真实 HUD 存在非空图标贴图（合计 %d）" % total_rects)

	# —— 面板可见性：控件里有贴图 ≠ 面板真的显示出来了（visible 是场景树状态，无头也能判）——
	# 已按各自内容路径触发：全部系统消息 / 头目广播 / 选中士兵 / 引导重启。
	for prop in VISIBLE_PANELS:
		var vp_node = hud.get(prop)
		var vis: bool = vp_node != null and (vp_node as CanvasItem).is_visible_in_tree()
		print("STAT 可见性 %-18s %s" % [prop, vis])
		_check(vis, "%s 在真实 HUD 中真的可见（实测 is_visible_in_tree=%s）" % [prop, vis])

	for i in PANEL_PROPS.size():
		var prop: String = PANEL_PROPS[i]
		var label: String = PANEL_LABELS[i]
		var panel = hud.get(prop)
		if panel == null:
			_check(false, "HUD.%s（%s）存在" % [prop, label])
			continue
		var n := _count_tex_rects(panel)
		print("STAT 面板 %-20s 非空贴图=%-3d 真图IconRect=%-3d 字徽=%d"
			% [label, n, _count_real_icon_rects(panel), _count_icon_chars(panel)])
		if CANVAS_DRAWN_PANELS.has(prop):
			# 自绘面板：图标用 draw_texture_rect 直接画在画布上，子树里**本来就没有** TextureRect 控件。
			# 因此这里改判「源码必须经 IconDB.get_texture() 取真贴图」这一契约，
			# 像素级证据（真的画出来了）由真机截图复核承担——见 artifacts/UI验收报告.md。
			var src := FileAccess.get_file_as_string(PANEL_SCRIPTS[prop])
			_check(src.contains("IconDB.get_texture("),
				"%s 自绘面板经 IconDB.get_texture() 取真贴图（TextureRect=%d 属预期）" % [label, n])
		else:
			_check(n >= 1, "%s 至少 1 个非空图标贴图（实测 %d）" % [label, n])

	# 自绘面板用到的两个 id 必须真实可解析（否则画布上是空白洞）
	_check(IconDB.has_icon(&"compass") and IconDB.has_icon(&"map"),
		"自绘面板依赖的 compass / map 图标可解析（Minimap 罗盘与地图语义）")

	if tut != null:
		tut.skip()
	main.queue_free()
	await get_tree().process_frame


# ============================================================================
# 6) 主题层真资源：9-slice 贴图 + 仓库内开源中文字体
#    「资产在仓库里」≠「运行时真的用上了」——这里直接问 UIStyle 要样式与字体，验真身。
# ============================================================================
func _check_theme_resources() -> void:
	print("--- 6) 主题层真资源（Kenney 9-slice + OFL 中文字体）---")
	var font := UIStyle.make_font()
	_check(font != null, "UIStyle.make_font() 返回字体")
	var fsrc := UIStyle.font_source()
	_check(fsrc.contains("ui_cjk.ttf"),
		"正文字体来源是仓库内字体而非系统字体链（font_source=%s）" % fsrc)
	if font is FontFile:
		var ff := font as FontFile
		_check(ff.resource_path.contains("assets/ui/fonts/ui_cjk.ttf"),
			"字体资源路径指向 assets/ui/fonts/ui_cjk.ttf（%s）" % ff.resource_path)
		var fname := ff.get_font_name()
		_check(fname.to_lower().contains("lxgw") or fname.contains("霞鹜"),
			"字体真名可核对为 LXGW WenKai（get_font_name=%s）" % fname)
	else:
		_check(false, "正文用的是 FontFile（实测 %s）" % ("null" if font == null else font.get_class()))

	var styles := {
		"panel_dark": UIStyle.panel_style(&"dark"),
		"panel_light": UIStyle.panel_style(&"light"),
		"panel_inset": UIStyle.panel_style(&"inset"),
		"panel_ornate": UIStyle.panel_style(&"ornate"),
		"button_normal": UIStyle.button_style(&"normal"),
		"button_hover": UIStyle.button_style(&"hover"),
		"button_pressed": UIStyle.button_style(&"pressed"),
		"chip": UIStyle.chip_style(),
		"bar": UIStyle.bar_style(&"gold"),
	}
	var tex_styles: Array[String] = []
	var flat_styles: Array[String] = []
	var foreign: Array[String] = []
	for name in styles.keys():
		var sb = styles[name]
		if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
			tex_styles.append(String(name))
			var p := String((sb as StyleBoxTexture).texture.resource_path)
			if not p.contains("res://assets/ui/kenney/"):
				foreign.append("%s→%s" % [name, p])
		else:
			flat_styles.append(String(name))
	print("STAT 主题样式：真 9-slice 贴图 %d 个 %s | 回退 StyleBoxFlat %d 个 %s"
		% [tex_styles.size(), tex_styles, flat_styles.size(), flat_styles])
	_check(tex_styles.size() >= 5,
		"主题样式至少 5 个用上 Kenney 真 9-slice 贴图（实测 %d：%s）" % [tex_styles.size(), tex_styles])
	_check(foreign.is_empty(), "9-slice 贴图全部来自 res://assets/ui/kenney/（越界：%s）" % _join(foreign))

	var theme := UIStyle.build_theme()
	_check(theme != null, "UIStyle.build_theme() 成功")
	if theme != null:
		var with_tex := 0
		var total := 0
		for t in theme.get_stylebox_type_list():
			for sb_name in theme.get_stylebox_list(t):
				total += 1
				var sb := theme.get_stylebox(sb_name, t)
				if sb is StyleBoxTexture and (sb as StyleBoxTexture).texture != null:
					with_tex += 1
		print("STAT Theme 内样式 %d 个，其中 9-slice 真贴图 %d 个" % [total, with_tex])
		_check(with_tex >= 1, "Theme 内至少 1 个类型用 9-slice 真贴图（实测 %d/%d）" % [with_tex, total])
		_check(theme.default_font != null and UIStyle.font_source().contains("ui_cjk.ttf"),
			"Theme 默认字体为仓库内开源中文字体")


# ============================================================================
# 统计工具
# ============================================================================
func _find_hero() -> Node:
	for n in get_tree().get_nodes_in_group("player_unit"):
		if n is Hero:
			return n
	return null


func _count_tex_rects(node: Node) -> int:
	var n := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		n += 1
	for child in node.get_children():
		n += _count_tex_rects(child)
	return n


func _count_real_icon_rects(node: Node) -> int:
	var n := 0
	if node is IconRect and (node as IconRect).uses_texture():
		n += 1
	for child in node.get_children():
		n += _count_real_icon_rects(child)
	return n


func _count_icon_chars(node: Node) -> int:
	var n := 0
	if node is IconChar:
		n += 1
	for child in node.get_children():
		n += _count_icon_chars(child)
	return n


# ============================================================================
# 主流程
# ============================================================================
func _run() -> void:
	_check_frozen_ids()
	_check_metadata()
	_check_fallback()
	_check_theme_resources()
	await _check_hud_textures()
	await _check_panels_standalone()
	await _check_panels_live()

	print("UI ICON CHECK: %d failure(s), %d warning(s)" % [_failures, _warnings])
	get_tree().quit(0 if _failures == 0 else 1)
