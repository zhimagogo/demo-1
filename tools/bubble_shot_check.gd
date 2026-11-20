extends SceneTree
## 气泡样张像素分析（严格版）：godot --headless --path . --script tools/bubble_shot_check.gd
## 在画面中找「暖纸白长条区」（气泡底），要求：
##   1) 找到 >=4 个纵向相连的白色长条盒（每个 ≈ 一个气泡）；
##   2) 每个盒内都有足量深色像素（文字真的画在气泡里）；
##   3) 盒的下缘有暗金描边色（圆角描边存在）。

func _init() -> void:
	var img := Image.load_from_file("res://artifacts/v14-bubbles.png")
	if img == null:
		print("FAIL: sample image missing")
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	print("image %dx%d" % [w, h])

	# 每行找白色长条 run（气泡底：连续 >=60px 的暖白）
	var runs_by_row: Array = []   # [y, x0, x1]
	for y in h:
		var x := 0
		while x < w:
			if _is_fill(img.get_pixel(x, y)):
				var x0 := x
				while x < w and _is_fill(img.get_pixel(x, y)):
					x += 1
				if x - x0 >= 60:
					runs_by_row.append([y, x0, x - 1])
			else:
				x += 1

	# 合并成盒：行内 run 相邻行且 x 区间重叠 → 同盒；再按 x 区间重叠二次合并成「竖带」
	# （文字行会把白底横向断开，单气泡常碎成上下两半，二次合并后一条竖带 = 一个气泡）
	var boxes: Array = []
	for r in runs_by_row:
		var y: int = r[0]
		var x0: int = r[1]
		var x1: int = r[2]
		var merged := false
		for b in boxes:
			if absi(y - b[3]) <= 2 and x0 <= b[2] + 8 and x1 >= b[1] - 8:
				b[1] = mini(b[1], x0)
				b[2] = maxi(b[2], x1)
				b[3] = maxi(b[3], y)
				b[4] += 1   # 覆盖行数
				merged = true
				break
		if not merged:
			boxes.append([y, x0, x1, y, 1])
	var bands: Array = []
	for b in boxes:
		if (b[2] - b[1]) < 120 or b[4] < 12:
			continue   # 只留真气泡尺寸
		var merged2 := false
		for band in bands:
			if b[1] <= band[2] + 20 and b[2] >= band[1] - 20:
				band[0] = mini(band[0], b[0])
				band[1] = mini(band[1], b[1])
				band[2] = maxi(band[2], b[2])
				band[3] = maxi(band[3], b[3])
				merged2 = true
				break
		if not merged2:
			bands.append([b[0], b[1], b[2], b[3]])
	var bubbles: Array = bands
	print("bubble bands: %d" % bubbles.size())

	var ok := true
	if bubbles.size() < 4:
		print("FAIL: expected >=4 bubble boxes, got %d" % bubbles.size())
		ok = false
	for b in bubbles:
		var text_px := _count_text_in_box(img, b)
		var border_found := _has_border_below(img, b, h)
		print("  band x[%d..%d] y[%d..%d] text_px=%d border=%s"
			% [b[1], b[2], b[0], b[3], text_px, border_found])
		if text_px < 40:
			print("FAIL: bubble at x[%d..%d] has too little text inside (%d px)" % [b[1], b[2], text_px])
			ok = false
		if not border_found:
			print("FAIL: bubble at x[%d..%d] missing gold border under it" % [b[1], b[2]])
			ok = false
	print("BUBBLE SHOT CHECK: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _is_fill(c: Color) -> bool:
	return c.r > 0.93 and c.g > 0.90 and c.b > 0.78 and c.b < 0.985 and c.a > 0.5


func _is_text(c: Color) -> bool:
	return c.r < 0.45 and c.g < 0.35 and c.b < 0.28


func _count_text_in_box(img: Image, b: Array) -> int:
	var n := 0
	for y in range(maxi(b[0] - 2, 0), mini(b[3] + 3, img.get_height())):
		for x in range(b[1], b[2] + 1):
			if _is_text(img.get_pixel(x, y)):
				n += 1
	return n


func _has_border_below(img: Image, b: Array, h: int) -> bool:
	# 盒底向下 0..12 行内找暗金描边像素（0.55,0.44,0.26 附近；抗锯齿/压亮场景放宽半档）
	for y in range(mini(b[3] + 12, h - 1), maxi(b[3] - 2, 0), -1):
		for x in range(b[1] + 10, b[2] - 10):
			var c := img.get_pixel(x, y)
			if absf(c.r - 0.55) < 0.12 and absf(c.g - 0.44) < 0.10 and absf(c.b - 0.26) < 0.09:
				return true
	return false
