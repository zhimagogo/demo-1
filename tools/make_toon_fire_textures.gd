extends SceneTree
## v30 贴图工具：程序化绘制「卡通火焰」贴图（火舌 + 烟团）。
## 卡通画法 = 分层色块 + 硬边界（cel shading）：外层暗红橙轮廓 → 橙 → 黄 → 白热芯，
## 每层都是扁平色块；边缘抖动用正弦噪声模拟手绘感；512 绘制 → 256 缩放做柔边。
##
## 运行：godot --headless --path . --script tools/make_toon_fire_textures.gd
## 产物：assets/vfx/textures/toon_flame_01.png / toon_puff_01.png（提交入库）

const OUT_DIR := "res://assets/vfx/textures/"
const DRAW := 512          # 绘制分辨率（缩放前）
const OUT := 256           # 输出分辨率


func _init() -> void:
	_make_flame()
	_make_puff()
	print("toon fire textures written to ", OUT_DIR)
	quit(0)


## 卡通火舌：自下而上的火苗，随高度收窄 + 正弦抖边，四层色块叠出卡通层次。
func _make_flame() -> void:
	var img := Image.create(DRAW, DRAW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := DRAW * 0.5
	var base_y := DRAW * 0.92
	# 各层：[颜色, 高度比例, 半径比例, 抖动幅度, 抖动频率, x 偏移比例]
	# 语义：外层暗红橙是「火的轮廓」，往内逐层更亮更短——卡通火焰的经典读法。
	var passes := [
		[Color(0.85, 0.22, 0.04, 1.0), 1.00, 1.00, 26.0, 5.1, 0.0],
		[Color(0.99, 0.55, 0.10, 1.0), 0.86, 0.70, 22.0, 6.3, 0.02],
		[Color(1.00, 0.82, 0.24, 1.0), 0.66, 0.44, 16.0, 7.7, -0.02],
		[Color(1.00, 0.97, 0.80, 1.0), 0.44, 0.22, 12.0, 9.0, 0.0],
	]
	for p in passes:
		var col: Color = p[0]
		var h_scale: float = p[1]
		var r_scale: float = p[2]
		var wobble: float = p[3]
		var wfreq: float = p[4]
		var x_off: float = p[5]
		var height := DRAW * 0.78 * h_scale
		var r0 := DRAW * 0.20 * r_scale
		var steps := int(height / 3.0)
		for i in steps + 1:
			var t := float(i) / float(steps)          # 0 底部 → 1 尖端
			var y := base_y - height * t
			# 火苗越往尖端越向一侧偏甩（经典火舌形态），加正弦抖边
			var sway := sin(t * wfreq) * wobble * (0.35 + 0.65 * t)
			var px := cx + x_off * DRAW * t + sway + sin(t * 13.0) * wobble * 0.12
			var r := r0 * pow(1.0 - t, 0.62) * (1.0 + 0.14 * sin(t * 17.0))
			r = maxf(r, 2.0)
			_stamp_circle(img, Vector2(px, y), r, col)
	_save(img, "toon_flame_01.png")


## 卡通烟团：几个扁平圆叠成的云朵状灰团，底部略暗（体积感的最小表达）。
func _make_puff() -> void:
	var img := Image.create(DRAW, DRAW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.90, 0.89, 0.88, 0.92)
	var shade := Color(0.72, 0.70, 0.70, 0.92)
	var cx := DRAW * 0.5
	var cy := DRAW * 0.58
	# 底层阴影（略暗、略低）
	_stamp_circle(img, Vector2(cx, cy + DRAW * 0.10), DRAW * 0.16, shade)
	_stamp_circle(img, Vector2(cx - DRAW * 0.16, cy + DRAW * 0.06), DRAW * 0.13, shade)
	# 主体云朵：中大 + 环绕小圆
	_stamp_circle(img, Vector2(cx, cy), DRAW * 0.19, col)
	_stamp_circle(img, Vector2(cx - DRAW * 0.17, cy + DRAW * 0.02), DRAW * 0.13, col)
	_stamp_circle(img, Vector2(cx + DRAW * 0.17, cy + DRAW * 0.03), DRAW * 0.14, col)
	_stamp_circle(img, Vector2(cx - DRAW * 0.06, cy - DRAW * 0.12), DRAW * 0.12, col)
	_stamp_circle(img, Vector2(cx + DRAW * 0.08, cy - DRAW * 0.10), DRAW * 0.11, col)
	_save(img, "toon_puff_01.png")


## 实心圆印章（同色覆盖即可并集成轮廓）。
func _stamp_circle(img: Image, center: Vector2, radius: float, col: Color) -> void:
	var x0 := maxi(int(center.x - radius), 0)
	var x1 := mini(int(center.x + radius), img.get_width() - 1)
	var y0 := maxi(int(center.y - radius), 0)
	var y1 := mini(int(center.y + radius), img.get_height() - 1)
	var r2 := radius * radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, col)


## 512 → 256 缩放（自带柔边抗锯齿）后落盘 PNG。
func _save(img: Image, file_name: String) -> void:
	img.resize(OUT, OUT, Image.INTERPOLATE_LANCZOS)
	var path := OUT_DIR + file_name
	var err := img.save_png(path)
	print("  ", path, " err=", err)
