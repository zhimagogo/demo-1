class_name CampaignStyle
extends RefCounted
## 远征界面的轻量主题：冷色底、奶油字与单一金色重点，避免装饰抢走地图的注意力。

const INK := Color("182c36")
const PANEL := Color("203944")
const CREAM := Color("f5eedb")
const MUTED := Color("a6b9b8")
const GOLD := Color("efc76a")
const GREEN := Color("9fc594")

static var _regular_font: Font
static var _heavy_font: Font

static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func font(heavy: bool = false) -> Font:
	if heavy and _heavy_font != null:
		return _heavy_font
	if not heavy and _regular_font != null:
		return _regular_font
	var body := UIStyle.make_system_font(heavy)
	# 系统字体有个别缺字时，回落到工程内随包发布的完整中文字库。
	body.fallbacks = [UIStyle.make_font()]
	if heavy:
		_heavy_font = body
	else:
		_regular_font = body
	return body

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = font()
	result.default_font_size = 14
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", GOLD)
	result.set_color("font_disabled_color", "Button", MUTED.darkened(0.28))
	result.set_stylebox("normal", "Button", box(PANEL.lightened(0.06), Color(MUTED, 0.25)))
	result.set_stylebox("hover", "Button", box(PANEL.lightened(0.16), GOLD))
	result.set_stylebox("pressed", "Button", box(INK, GOLD))
	result.set_stylebox("disabled", "Button", box(INK.lightened(0.04), Color(MUTED, 0.12)))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, GOLD))
	return result

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box(GOLD))
	button.add_theme_stylebox_override("hover", box(GOLD.lightened(0.17)))
	button.add_theme_stylebox_override("pressed", box(GOLD.darkened(0.12)))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
