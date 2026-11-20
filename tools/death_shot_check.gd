extends SceneTree
## 死亡溶解样张像素分析：godot --headless --path . --script tools/death_shot_check.gd
## artifacts/v16-death-dissolve.png 三列野怪（左：倒地中 / 中：烧蚀过半 / 右：溶解殆尽），断言：
##   1) 左列有完整「身体像素」（非草地 / 非灰影）；
##   2) 中列存在足量「烧灼橙」像素（溶解边缘发光真实画出来了）；
##   3) 右列身体像素明显少于左列（真的溶掉了，不是原样站着）。

func _init() -> void:
	var img := Image.load_from_file("res://artifacts/v16-death-dissolve.png")
	if img == null:
		print("FAIL: sample image missing")
		quit(1)
		return
	var w := img.get_width()
	var h := img.get_height()
	print("image %dx%d" % [w, h])

	# 只看身体所在带（跳过天空区），按三列统计
	var y0 := int(h * 0.35)
	var y1 := int(h * 0.95)
	var col_w := w / 3
	var body := [0, 0, 0]
	var burn := [0, 0, 0]
	for y in range(y0, y1):
		for x in w:
			var c := img.get_pixel(x, y)
			var col := clampi(x / col_w, 0, 2)
			if _is_burn(c):
				burn[col] += 1
				body[col] += 1
			elif not _is_background(c):
				body[col] += 1

	print("body px  L=%d M=%d R=%d" % body)
	print("burn px  L=%d M=%d R=%d" % burn)

	var ok := true
	if body[0] < 3000:
		print("FAIL: left column lacks a full body (%d px)" % body[0])
		ok = false
	if burn[1] < 120:
		print("FAIL: middle column lacks burn-edge pixels (%d px)" % burn[1])
		ok = false
	if body[2] > body[0] * 0.75:
		print("FAIL: right column not visibly dissolved (R=%d vs L=%d)" % [body[2], body[0]])
		ok = false
	if burn[0] + burn[1] + burn[2] < 200:
		print("FAIL: dissolve burn effect too weak overall (%d px)" % (burn[0] + burn[1] + burn[2]))
		ok = false
	if ok:
		print("PASS: death anim + dissolve sample verified")
	quit(0 if ok else 1)


## 烧灼橙：溶解边缘的发光色（burn_color 1.0/0.42/0.12 × EMISSION 提亮）
func _is_burn(c: Color) -> bool:
	return c.r > 0.45 and c.g > 0.10 and c.g < 0.80 and c.b < 0.40 and c.r > c.b * 1.6


## 背景：草地（绿主导）或灰阶（阴影 / 远景）
func _is_background(c: Color) -> bool:
	if c.g >= c.r * 1.04 and c.g >= c.b * 1.04:
		return true
	return absf(c.r - c.g) < 0.07 and absf(c.g - c.b) < 0.07
