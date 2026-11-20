class_name IconChar
extends Control
## 圆形字徽：彩色圆底 + 单个汉字/字符（资源图标 / 建筑图标 / 姿态按钮用）。
## 代码绘制，无贴图依赖；颜色 / 直径 / 字号可定制。
##
## v6 定位：**它是缺图时的兜底**——有真实图标的场合请用 IconBadge / IconRect，
## 只有在美术资源缺失或确实需要纯文字徽标时才落到这里。
## 视觉在本版做了小幅打磨：三层圆底（暗底 / 内压暗 / 高光）+ 双圈描边 + 居中字形带投影，
## 小尺寸（20~26px）下比 v5 的单圈 + 手工偏移更清晰、字也不再偏上。
##
## 构造签名与属性（char_text / accent / circle_ratio / font_size）保持不变，
## IconRect 的回退路径依赖它们。

var char_text: String = "?"
var accent: Color = UIStyle.GOLD
var circle_ratio: float = 0.92          # 圆占控件的直径比
var font_size: int = 15
var _font: Font = null


func _init(text: String = "?", color: Color = UIStyle.GOLD, size_px: int = 26, f_size: int = 15) -> void:
	custom_minimum_size = Vector2(size_px, size_px)
	char_text = text
	accent = color
	font_size = f_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if _font == null:
		# 字徽字号很小（12~20px），用标题字体（若落地了粗体则更清晰），缺失自动回退系统字体链
		_font = UIStyle.make_display_font()
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * circle_ratio
	if r <= 0.5:
		return

	# —— 底盘：深色圆 + 内圈压暗 + 顶部一抹高光 ——
	draw_circle(c, r, Color(accent.darkened(0.70), 0.95))
	draw_circle(c, r * 0.86, Color(0.0, 0.0, 0.0, 0.20))
	if r > 8.0:
		draw_arc(c + Vector2(0.0, -r * 0.30), r * 0.62, PI * 1.12, PI * 1.88, 20,
			Color(1.0, 1.0, 1.0, 0.07), maxf(1.0, r * 0.30), true)

	# —— 描边：外圈 accent 亮线 + 内圈半透明衬线（双圈更立体）——
	draw_arc(c, r - 1.0, 0.0, TAU, 40, accent, 1.6, true)
	if r > 7.0:
		draw_arc(c, r - 2.8, 0.0, TAU, 40, Color(accent.lightened(0.25), 0.30), 1.0, true)

	# —— 居中字形：按 ascent/descent 精确垂直居中，带 1px 深色投影 ——
	var ascent := _font.get_ascent(font_size)
	var descent := _font.get_descent(font_size)
	var ts := _font.get_string_size(char_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := Vector2(c.x - ts.x * 0.5, c.y + (ascent - descent) * 0.5)
	draw_string(_font, origin + Vector2(1.0, 1.0), char_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(0.0, 0.0, 0.0, 0.5))
	draw_string(_font, origin, char_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.TEXT_MAIN)
