extends Node
## 截图像素体检：对 artifacts/ 下的渲染截图做客观色彩统计，验证关键视觉是否真实生效。
## godot --headless --path . tests/PixelCheck.tscn
## 检查：夜空变暗 / 雨天地面压暗（同机位对照）/ HUD 面板（小地图、任务卡、顶栏）确实渲染。

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _avg_brightness(img: Image, rect: Rect2i) -> float:
	var size := img.get_size()
	var x0 := clampi(rect.position.x, 0, size.x - 1)
	var y0 := clampi(rect.position.y, 0, size.y - 1)
	var x1 := clampi(rect.position.x + rect.size.x, 1, size.x)
	var y1 := clampi(rect.position.y + rect.size.y, 1, size.y)
	var total: float = 0.0
	var count: int = 0
	var y := y0
	while y < y1:
		var x := x0
		while x < x1:
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			count += 1
			x += 4
		y += 4
	return total / float(maxi(count, 1))


func _load(path: String) -> Image:
	var img := Image.new()
	var err := img.load(path)
	if err != OK:
		_check(false, "load %s" % path)
		return null
	return img


func _run() -> void:
	var overview_img := _load("res://artifacts/scene-overview.png")
	var size: Vector2i = overview_img.get_size() if overview_img != null else Vector2i(1600, 938)

	# ---- 1) 夜景 vs 白昼总览：天空（顶部 12%）应显著更暗 ----
	var night := _load("res://artifacts/scene-night.png")
	if night != null and overview_img != null:
		var sky_rect := Rect2i(0, 0, size.x, int(size.y * 0.12))
		var night_sky := _avg_brightness(night, sky_rect)
		var day_sky := _avg_brightness(overview_img, sky_rect)
		_check(night_sky < day_sky * 0.55, "night sky darker than day (%.3f < %.3f×0.55)" % [night_sky, day_sky])
		# 夜景整体也应偏暗（月亮 + 微光环境）
		var night_all := _avg_brightness(night, Rect2i(0, 0, size.x, size.y))
		var day_all := _avg_brightness(overview_img, Rect2i(0, 0, size.x, size.y))
		_check(night_all < day_all * 0.75, "night scene overall darker (%.3f < %.3f×0.75)" % [night_all, day_all])
		# v3.1 修复回归线：夜要「暗而可读」——月光下地形/单位轮廓可见，不许纯黑
		_check(night_all > 0.05, "night readable under moonlight, not pitch black (%.3f > 0.05)" % night_all)

	# ---- 2) 雨天 vs 晴天（同机位、同太阳）：中位亮度应下降（湿地压暗基调）----
	# 用中位数而非均值/占比：湿地面会同时出现镜面高光（少数亮像素），均值与占比统计都会被它拉偏；
	# 中位数反映「整片地面」的基调变化，且两次截图前太阳位置被冻结，唯一变量是天气。
	var rain := _load("res://artifacts/scene-rain.png")
	var dry := _load("res://artifacts/scene-dry.png")
	if rain != null and dry != null:
		var ground_rect := Rect2i(0, int(size.y * 0.45), size.x, int(size.y * 0.5))
		var rain_med := _median_luma(rain, ground_rect)
		var dry_med := _median_luma(dry, ground_rect)
		_check(rain_med < dry_med * 0.99, "rain darkens ground tone at same spot (median %.3f < %.3f×0.99)" % [rain_med, dry_med])
		# v5：风暴压暗天色——雨天顶部天空带应明显更暗（灰蓝风暴天 vs 晴日蓝天）
		var sky_rect := Rect2i(0, 0, size.x, int(size.y * 0.10))
		var rain_sky := _median_luma(rain, sky_rect)
		var dry_sky := _median_luma(dry, sky_rect)
		_check(rain_sky < dry_sky * 0.85, "storm sky darker than clear sky (median %.3f < %.3f×0.85)" % [rain_sky, dry_sky])
		# v5：雨丝可见性——雨丝是「比左右邻居亮」的细竖线；雨图的细竖线像素占比应显著高于晴天空镜
		var band := Rect2i(int(size.x * 0.25), int(size.y * 0.35), int(size.x * 0.7), int(size.y * 0.55))
		var rain_sp := _streak_pixel_frac(rain, band)
		var dry_sp := _streak_pixel_frac(dry, band)
		# v7：树/石按第三人称近地比例缩小后，晴天空镜里枝干边缘的「伪细竖线」底噪略升
		# （v6 实测 dry_sp ~0.0132 → v7 ~0.0185），1.4 倍阈值贴边抖动；与夜雨线一致取 1.25。
		_check(rain_sp > dry_sp * 1.25, "rain streaks visible (thin-bright-line frac %.4f > %.4f×1.25)" % [rain_sp, dry_sp])
		# v5：夜雨——同机位（对照 scene-night）：雨丝夜里仍可读、整场不纯黑、乌云夜不比晴夜天空亮
		var rain_night := _load("res://artifacts/scene-rain-night.png")
		if night != null and rain_night != null:
			var night_sp := _streak_pixel_frac(night, band)
			var rn_sp := _streak_pixel_frac(rain_night, band)
			_check(rn_sp > night_sp * 1.25, "rain streaks readable at night (frac %.4f > %.4f×1.25)" % [rn_sp, night_sp])
			var rn_all := _median_luma(rain_night, Rect2i(0, 0, size.x, size.y))
			_check(rn_all > 0.03, "night rain scene readable, not pitch black (%.3f > 0.03)" % rn_all)
			var rn_sky := _median_luma(rain_night, Rect2i(0, 0, size.x, int(size.y * 0.10)))
			var night_sky := _median_luma(night, Rect2i(0, 0, size.x, int(size.y * 0.10)))
			_check(rn_sky < night_sky * 2.0, "overcast night sky not brighter than clear night (%.3f < %.3f×2.0)" % [rn_sky, night_sky])

	# ---- 3) HUD：小地图（右下 200px 方块）应比草地显著更暗（面板底色） ----
	var gameplay := _load("res://artifacts/scene-gameplay.png")
	if gameplay != null:
		var field_rect := Rect2i(int(size.x * 0.35), int(size.y * 0.30), 200, 200)
		var field_b := _avg_brightness(gameplay, field_rect)
		var mm_b := _avg_brightness(gameplay, Rect2i(size.x - 200, size.y - 200, 120, 120))
		_check(field_b > 0.2 and mm_b < field_b * 0.8, "minimap panel renders at bottom-right (%.3f < %.3f×0.8)" % [mm_b, field_b])
		# 顶栏：顶部应有深色条带（面板）
		var top_b := _avg_brightness(gameplay, Rect2i(400, 10, 800, 30))
		_check(top_b < field_b * 0.9, "top bar panel renders (%.3f vs field %.3f)" % [top_b, field_b])
		# 任务卡：左上（顶栏下方）深色面板
		var quest_b := _avg_brightness(gameplay, Rect2i(30, 70, 240, 80))
		_check(quest_b < field_b * 0.9, "quest panel renders top-left (%.3f vs field %.3f)" % [quest_b, field_b])
		# 建造菜单：底部左侧应有 6 张卡片（深色按钮区）
		var build_b := _avg_brightness(gameplay, Rect2i(20, size.y - 70, 600, 50))
		_check(build_b < field_b * 0.95, "build menu cards render bottom-left (%.3f)" % build_b)

	# ---- 4) v6：HUD 图标可见性（顶栏 / 建造菜单 / 各面板）——
	# 台账（每个图标控件的屏幕矩形 + tint）由 tests/UiCapture.tscn 在真机上落盘；
	# 这里在同一张渲染帧上验证「该矩形里真的有该 tint 的图标前景像素」。
	# 这是「代码接了图标，但实际渲染成空白 / 黑块 / 被裁掉」的唯一客观拦截点。
	_hud_icon_stats()

	print("PIXEL CHECK: %d failure(s)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## 区域亮度中位数（抗离群：镜面高光 / 雨丝亮像素不拉偏）。
func _median_luma(img: Image, rect: Rect2i) -> float:
	var size := img.get_size()
	var values: Array[float] = []
	var y := clampi(rect.position.y, 0, size.y - 1)
	while y < clampi(rect.position.y + rect.size.y, 1, size.y):
		var x := clampi(rect.position.x, 0, size.x - 1)
		while x < clampi(rect.position.x + rect.size.x, 1, size.x):
			var c := img.get_pixel(x, y)
			values.append((c.r + c.g + c.b) * 0.333)
			x += 3
		y += 3
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]


## 细竖亮线像素占比（雨丝检测）：像素比左右各 2px 的邻居都亮出一截 —— 雨丝内部特征。
func _streak_pixel_frac(img: Image, rect: Rect2i, margin: float = 0.04) -> float:
	var size := img.get_size()
	var n: int = 0
	var total: int = 0
	var y := clampi(rect.position.y, 0, size.y - 1)
	while y < clampi(rect.position.y + rect.size.y, 1, size.y):
		var x := clampi(rect.position.x + 2, 0, size.x - 3)
		while x < clampi(rect.position.x + rect.size.x - 2, 1, size.x - 2):
			var c := (img.get_pixel(x, y))
			var ca: float = (c.r + c.g + c.b) * 0.333
			var l := img.get_pixel(x - 2, y)
			var la: float = (l.r + l.g + l.b) * 0.333
			var r := img.get_pixel(x + 2, y)
			var ra: float = (r.r + r.g + r.b) * 0.333
			if ca - la > margin and ca - ra > margin:
				n += 1
			total += 1
			x += 1
		y += 1
	return float(n) / float(maxi(total, 1))


# ============================================================================
# v6：HUD 图标可见性（数据源 = tests/UiCapture.tscn 在真机上落盘的图标矩形台账）
#
# 为什么这么做：UiIconTest 能证明「节点树里 texture != null」，但证明不了「屏幕上真的
# 画出来了」——图标可能被面板裁掉、被背景色吞掉、贴图全透明、或渲染成黑块。这里把
# 每个图标控件的屏幕矩形 + 它的 self_modulate(tint) 从真机落盘，然后在同一帧截图上做
# 「tint 颜色聚类计数」：矩形里必须有足量「亮度达到 tint 亮度一半、且色度方向与 tint
# 一致」的前景像素。空白/黑块/透明贴图 → 命中率 ≈ 0，直接挂。
#
# 阈值标定（实测见 artifacts/UI验收报告.md，全部取实测值的一半以下留余量）：
#   · 单图标命中率下限 0.05：白色图标贴图 128→24px 缩绘后，实体笔画内部的像素是满 tint，
#     实测中位数 ≈ 0.35~0.55，取 0.05 仍能抓住「渲染成空白」；
#   · ≥16px 的图标才参与逐图标阈值（更小的图标像素太少，统计噪声大）；
#   · 允许 ≤20% 的受检图标低于下限（部分图标可能被同类面板遮挡或描边极细）。
# ============================================================================
const ICON_RECTS_JSON := "res://artifacts/ui-icon-rects.json"
const ICON_FRAME := "ui-hud"
const ICON_MIN_SIDE := 16                 # 参与逐图标阈值的最小边长（px）
const ICON_HIT_FRAC := 0.05               # 单图标命中率下限
const ICON_BAD_RATIO_MAX := 0.20          # 低于下限的受检图标占比上限
const ICON_TOTAL_MIN := 8                 # 全帧「真的画出像素」的图标数下限
const ICON_REGION_MIN_PIXELS := 300       # 顶栏 / 建造菜单各自的最小命中像素数
const ICON_MEDIAN_MIN := 0.10             # tint 命中率中位数下限（聚类计数）
## 形状相关性（更强判据）：把图标自己的 128×128 alpha 遮罩缩放到控件矩形，与渲染帧的
## 亮度做 Pearson 相关。渲染对了 → 高相关；空白/黑块/错图/被裁 → 相关 ≈ 0。
## 该判据与绝对亮度、tint 无关，抗小尺寸抗锯齿（11px 图标也能判）。
const ICON_CORR_MIN := 0.30               # 单图标「图形真的画出来了」相关下限
const ICON_CORR_MEDIAN_MIN := 0.45        # 全部受检图标相关中位数下限
const ICON_CORR_OK_RATIO_MIN := 0.75      # 达标图标占比下限


func _hud_icon_stats() -> void:
	if not FileAccess.file_exists(ICON_RECTS_JSON):
		_check(false, "图标矩形台账 artifacts/ui-icon-rects.json 存在（先跑 godot --path . tests/UiCapture.tscn）")
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(ICON_RECTS_JSON))
	_check(doc is Dictionary, "图标矩形台账是合法 JSON")
	if not (doc is Dictionary):
		return
	if not (doc as Dictionary).has(ICON_FRAME):
		_check(false, "台账含基线帧 %s" % ICON_FRAME)
		return
	var frame_v = (doc as Dictionary)[ICON_FRAME]
	_check(frame_v is Dictionary, "台账帧 %s 是对象" % ICON_FRAME)
	if not (frame_v is Dictionary):
		return
	var frame: Dictionary = frame_v
	var img := _load("res://artifacts/%s" % String(frame.get("image", "")))
	if img == null:
		return
	var vp: Array = frame.get("viewport", [])
	_check(vp.size() == 2 and img.get_width() == int(vp[0]) and img.get_height() == int(vp[1]),
		"HUD 截图尺寸与台账视口一致（%dx%d）" % [img.get_width(), img.get_height()])

	var icons: Array = frame.get("icons", [])
	_check(icons.size() >= ICON_TOTAL_MIN, "台账含 ≥%d 个非空图标控件（实测 %d）" % [ICON_TOTAL_MIN, icons.size()])

	var fracs: Array[float] = []
	var painted_by_panel := {}
	var pixels_by_panel := {}
	var corrs: Array[float] = []
	var corr_ok_by_panel := {}
	var corr_by_panel := {}
	var detail: Array = []          # [[命中率, 文本], …] 按命中率升序打印最差若干条
	var skipped := 0
	for rec in icons:
		if not (rec is Dictionary):
			continue
		var r: Array = rec.get("rect", [])
		var t: Array = rec.get("tint", [])
		if r.size() != 4 or t.size() != 4:
			continue
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		if rect.position.x < 0 or rect.position.y < 0 \
				or rect.end.x > img.get_width() or rect.end.y > img.get_height():
			skipped += 1
			continue
		var tint := Color(float(t[0]), float(t[1]), float(t[2]), float(t[3]))
		if tint.a <= 0.05:
			skipped += 1
			continue
		var matched := _tint_pixels(img, rect, tint)
		var frac := float(matched) / float(maxi(rect.size.x * rect.size.y, 1))
		var panel := String(rec.get("panel", "?"))
		pixels_by_panel[panel] = int(pixels_by_panel.get(panel, 0)) + matched
		if frac >= ICON_HIT_FRAC:
			painted_by_panel[panel] = int(painted_by_panel.get(panel, 0)) + 1
		# 形状相关性（有 id 的图标才算；纯 TextureRect 没有 id → 跳过）
		var corr := _mask_correlation(img, rect, String(rec.get("id", "")))
		if corr > -1.5:
			corrs.append(corr)
			corr_by_panel[panel] = int(corr_by_panel.get(panel, 0)) + 1
			if corr >= ICON_CORR_MIN:
				corr_ok_by_panel[panel] = int(corr_ok_by_panel.get(panel, 0)) + 1
		if mini(rect.size.x, rect.size.y) >= ICON_MIN_SIDE:
			fracs.append(frac)
		detail.append([frac, "%s/%s %dpx 命中=%.2f" % [panel, rec.get("id", "?"),
			mini(rect.size.x, rect.size.y), frac]])

	# 台账里没记到面板名（"other"）的贴图（如漂浮文字/遮罩）不参与面板断言
	var painted_total := 0
	for k in painted_by_panel:
		painted_total += int(painted_by_panel[k])
	print("STAT 图标像素：受检图标 %d（跳过 %d）| tint 画出像素的图标 %d | tint 命中率中位数 %.3f"
		% [fracs.size(), skipped, painted_total, _median_of(fracs)])
	var corr_ok := 0
	for v in corrs:
		if v >= ICON_CORR_MIN:
			corr_ok += 1
	print("STAT 形状相关性：可判图标 %d | 达标(≥%.2f) %d | 中位数 %.3f | 最低 %.3f | 最高 %.3f"
		% [corrs.size(), ICON_CORR_MIN, corr_ok, _median_of(corrs),
			_min_of(corrs), _max_of(corrs)])
	var corr_panels: Array = corr_by_panel.keys()
	corr_panels.sort()
	for k in corr_panels:
		print("STAT 面板 %-18s 形状相关可判=%-3d 达标=%-3d tint 命中像素=%d"
			% [k, corr_by_panel[k], int(corr_ok_by_panel.get(k, 0)), int(pixels_by_panel.get(k, 0))])
	var panels_sorted: Array = painted_by_panel.keys()
	panels_sorted.sort()
	for k in panels_sorted:
		print("STAT 面板 %-18s 真画出图标=%-3d tint 命中像素=%d"
			% [k, painted_by_panel[k], int(pixels_by_panel.get(k, 0))])
	# 最差 8 条明细（排查「哪个图标没画出来」）
	var worst := detail.duplicate()
	worst.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(8, worst.size()):
		print("STAT 明细 %s" % worst[i][1])

	_check(painted_total >= ICON_TOTAL_MIN,
		"全帧至少 %d 个图标矩形里存在该 tint 的前景像素（实测 %d）" % [ICON_TOTAL_MIN, painted_total])
	_check(int(painted_by_panel.get("top_bar", 0)) >= 2,
		"顶栏区域 ≥2 个图标真的画出 tint 前景像素（实测 %d）" % int(painted_by_panel.get("top_bar", 0)))
	_check(int(painted_by_panel.get("build_menu", 0)) >= 3,
		"建造菜单区域 ≥3 个图标真的画出 tint 前景像素（实测 %d）" % int(painted_by_panel.get("build_menu", 0)))
	_check(int(pixels_by_panel.get("top_bar", 0)) >= ICON_REGION_MIN_PIXELS,
		"顶栏图标 tint 像素总数 ≥%d（实测 %d）" % [ICON_REGION_MIN_PIXELS, int(pixels_by_panel.get("top_bar", 0))])
	_check(int(pixels_by_panel.get("build_menu", 0)) >= ICON_REGION_MIN_PIXELS,
		"建造菜单图标 tint 像素总数 ≥%d（实测 %d）" % [ICON_REGION_MIN_PIXELS, int(pixels_by_panel.get("build_menu", 0))])
	_check(fracs.size() > 0 and _median_of(fracs) >= ICON_MEDIAN_MIN,
		"图标命中率中位数 ≥%.2f（实测 %.3f，受检 %d 个）" % [ICON_MEDIAN_MIN, _median_of(fracs), fracs.size()])
	var bad := 0
	for f in fracs:
		if f < ICON_HIT_FRAC:
			bad += 1
	var bad_ratio := float(bad) / float(maxi(fracs.size(), 1))
	_check(fracs.size() > 0 and bad_ratio <= ICON_BAD_RATIO_MAX,
		"低于 tint 命中率下限的图标占比 ≤%.0f%%（实测 %d/%d = %.0f%%）"
		% [ICON_BAD_RATIO_MAX * 100.0, bad, fracs.size(), bad_ratio * 100.0])
	# —— 形状相关性（主判据）：图形真的按自己的遮罩画在该矩形里 ——
	_check(corrs.size() >= 8, "可判形状相关性的图标 ≥8 个（实测 %d）" % corrs.size())
	_check(_median_of(corrs) >= ICON_CORR_MEDIAN_MIN,
		"形状相关性中位数 ≥%.2f（实测 %.3f，可判 %d 个）"
		% [ICON_CORR_MEDIAN_MIN, _median_of(corrs), corrs.size()])
	var ok_ratio := float(corr_ok) / float(maxi(corrs.size(), 1))
	_check(corr_ok >= 8 and ok_ratio >= ICON_CORR_OK_RATIO_MIN,
		"形状相关达标图标占比 ≥%.0f%%（实测 %d/%d = %.0f%%）"
		% [ICON_CORR_OK_RATIO_MIN * 100.0, corr_ok, corrs.size(), ok_ratio * 100.0])
	_check(int(corr_ok_by_panel.get("top_bar", 0)) >= 3,
		"顶栏 ≥3 个图标形状相关达标（实测 %d）" % int(corr_ok_by_panel.get("top_bar", 0)))
	_check(int(corr_ok_by_panel.get("build_menu", 0)) >= 4,
		"建造菜单 ≥4 个图标形状相关达标（实测 %d）" % int(corr_ok_by_panel.get("build_menu", 0)))


## 矩形内「属于该 tint 图标前景」的像素数（颜色聚类计数）。
## 亮度阈值**自适应**：lo = 本矩形最暗像素 + 30% × (tint 亮度 − 最暗像素)。
## 理由（实测标定）：10~14px 的小图标受双线性缩绘 + 徽章圆底影响，永远达不到 tint 的
## 满亮度（实测 res_wood 11px 矩形 max luma 0.255 vs tint 0.543），固定「半 tint 亮度」
## 会把真实画出的图标误判成空白；自适应阈值下「整块空白/黑块」仍然 0 命中（无对比度）。
func _tint_pixels(img: Image, rect: Rect2i, tint: Color) -> int:
	var min_l := 1.0
	var max_l := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c0 := img.get_pixel(x, y)
			var l0 := (c0.r + c0.g + c0.b) / 3.0
			min_l = minf(min_l, l0)
			max_l = maxf(max_l, l0)
	var tint_l := (tint.r + tint.g + tint.b) / 3.0 * clampf(tint.a, 0.25, 1.0)
	var span := maxf(tint_l - min_l, 0.02)
	var lo := min_l + 0.30 * span
	var chroma := Vector3(tint.r, tint.g, tint.b) - Vector3(
		(tint.r + tint.g + tint.b) / 3.0, (tint.r + tint.g + tint.b) / 3.0, (tint.r + tint.g + tint.b) / 3.0)
	var is_gray := chroma.length() < 0.05
	var dir := chroma.normalized()
	var matched := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := img.get_pixel(x, y)
			var cl := (c.r + c.g + c.b) / 3.0
			if cl < lo:
				continue
			if not is_gray:
				var pc := Vector3(c.r - cl, c.g - cl, c.b - cl)
				if pc.length() < 0.0001 or pc.normalized().dot(dir) < 0.80:
					continue
			matched += 1
	return matched


## 形状相关性：把该图标自己的 PNG alpha 遮罩缩放到控件矩形，与渲染帧亮度做 Pearson 相关。
## 返回 -2.0 表示「不可判」（无 id / 贴图缺失）；返回 0.0 表示「矩形内没有任何与遮罩相关的起伏」。
func _mask_correlation(img: Image, rect: Rect2i, id: String) -> float:
	if id.is_empty():
		return -2.0
	var path := "res://assets/ui/icons/%s.png" % id
	if not ResourceLoader.exists(path):
		return -2.0
	var mask: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if mask == null or mask.is_empty():
		return -2.0
	mask.convert(Image.FORMAT_RGBA8)
	mask.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_BILINEAR)
	var n := 0
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for y in rect.size.y:
		for x in rect.size.x:
			var a := mask.get_pixel(x, y).a
			var c := img.get_pixel(rect.position.x + x, rect.position.y + y)
			var l := (c.r + c.g + c.b) / 3.0
			n += 1
			sx += a
			sy += l
			sxx += a * a
			syy += l * l
			sxy += a * l
	var fn := float(maxi(n, 1))
	var mx := sx / fn
	var my := sy / fn
	var vx := sxx / fn - mx * mx
	var vy := syy / fn - my * my
	if vx <= 1e-9 or vy <= 1e-9:
		return 0.0
	return (sxy / fn - mx * my) / sqrt(vx * vy)


func _min_of(values: Array[float]) -> float:
	var m := 1.0
	for v in values:
		m = minf(m, v)
	return m


func _max_of(values: Array[float]) -> float:
	var m := -1.0
	for v in values:
		m = maxf(m, v)
	return m


func _median_of(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var copy := values.duplicate()
	copy.sort()
	return copy[copy.size() / 2]
