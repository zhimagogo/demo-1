extends SceneTree
## v18 小队绿标渲染校验：godot --headless --path . --script tools/v18_marks_check.gd
## 前置：先跑两次渲染探针（纯灰地面 + 单个小兵，排除草地环境绿干扰）——
##   godot --path . tools/v18_marks_probe.tscn               # artifacts/v18-probe-marks.png
##   godot --path . tools/v18_marks_probe.tscn -- --no-marks # artifacts/v18-probe-plain.png
## 断言：
##   1) 带绿标帧存在大量「绿主导」像素（反转外壳描边真实画出）；
##   2) 下带（脚部高度）也有足量绿（脚下小绿圈真实画出）；
##   3) 无绿标帧几乎为零绿像素（灰底对照组，证明绿全部来自绿标）。

func _init() -> void:
	var on := Image.load_from_file("res://artifacts/v18-probe-marks.png")
	var off := Image.load_from_file("res://artifacts/v18-probe-plain.png")
	if on == null or off == null:
		print("FAIL: probe images missing (run tools/v18_marks_probe.tscn twice first)")
		quit(1)
		return
	var w := on.get_width()
	var h := on.get_height()
	print("probe image %dx%d" % [w, h])

	var vivid_on := 0
	var vivid_on_low := 0   # 下 2/5 带（脚下小绿圈所在高度）
	var vivid_off := 0
	for y in h:
		for x in w:
			if _is_mark_green(on.get_pixel(x, y)):
				vivid_on += 1
				if y > h * 3 / 5:
					vivid_on_low += 1
			if _is_mark_green(off.get_pixel(x, y)):
				vivid_off += 1
	print("green px  marks=%d (foot band %d)  plain=%d" % [vivid_on, vivid_on_low, vivid_off])

	var ok := true
	if vivid_on < 3000:
		print("FAIL: green outline not rendered (%d px)" % vivid_on)
		ok = false
	if vivid_on_low < 300:
		print("FAIL: green foot ring not rendered (%d px)" % vivid_on_low)
		ok = false
	if vivid_off > 200:
		print("FAIL: control frame should have no green (%d px)" % vivid_off)
		ok = false
	if ok:
		print("PASS: squad green outline + foot ring render verified")
	quit(0 if ok else 1)


## 「队伍绿」标记色（0.35 / 1.0 / 0.45，无光照直出；经 tonemap 后仍绿主导）。
## 灰底对照组中任何绿主导像素都只能来自绿标。
func _is_mark_green(c: Color) -> bool:
	return c.g > 0.35 and c.g - maxf(c.r, c.b) > 0.10
