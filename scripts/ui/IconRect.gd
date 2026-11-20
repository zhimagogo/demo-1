class_name IconRect
extends TextureRect
## ============================================================================
## 语义图标控件（v6）：id → IconDB 贴图 + 调色 + 尺寸。
## 缺图时可选回退为 IconChar 圆形字徽（fallback_char 非空即启用），
## 因此面板可以在美术资源尚未到位时照常工作。
##
## 用法：
##     var ic := IconRect.new(&"res_wood", 24, UIStyle.GOLD, "木")
##     hbox.add_child(ic)
##     ic.set_icon(&"res_stone", 20, "石")      # 换图标（保留当前颜色）
##     ic.set_tint(UIStyle.TEXT_MAIN)           # 只换颜色
## ============================================================================

var icon_id: StringName = &""
var fallback_char: String = ""
var icon_px: int = 24
var tint: Color = Color.WHITE

var _fallback: IconChar = null


func _init(id: StringName = &"", px: int = 24, color: Color = Color.WHITE,
		fb: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_icon(id, px, fb)
	set_tint(color)


## 设置图标（px <= 0 表示沿用当前尺寸；fb 为空表示沿用当前回退字）。
func set_icon(id: StringName, px: int = -1, fb: String = "") -> void:
	icon_id = id
	if px > 0:
		icon_px = px
	if fb != "":
		fallback_char = fb
	_rebuild()


## 只改颜色。
func set_tint(color: Color) -> void:
	tint = color
	self_modulate = color
	if _fallback != null:
		_fallback.accent = color
		_fallback.queue_redraw()


func _rebuild() -> void:
	custom_minimum_size = Vector2(icon_px, icon_px)
	size = custom_minimum_size
	tooltip_text = "" if fallback_char == "" else fallback_char
	texture = IconDB.get_texture(icon_id)
	if _fallback != null:
		_fallback.queue_free()
		_fallback = null
	if texture == null and fallback_char != "":
		# 回退：美术资源缺失时仍然显示一个可读的字徽，而不是空白
		_fallback = IconChar.new(fallback_char, tint, icon_px, int(maxf(9.0, icon_px * 0.6)))
		_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_fallback)


## 当前是否用的真实美术资源（调试 / 回归断言用）。
func uses_texture() -> bool:
	return texture != null
