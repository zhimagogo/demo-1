class_name IconBadge
extends Control
## ============================================================================
## 图标徽章（v6）：深色圆底 + accent 描边 + 真实语义图标，取代 v5 的纯字徽。
## 与旧 IconChar 尺寸 / 位置语义保持一致，面板可以直接一比一换用：
##     IconChar.new("木", color, 24, 13)  →  IconBadge.new(&"res_wood", 24, color, "木")
## 图标缺失时内部 IconRect 自动回退字徽，故 UI 永不出现空白洞。
##
## 几何约定：图标源 PNG 的内容几乎铺满 128×128（alpha bbox ≈ 91%），因此字模必须
## 内缩到圆盘内切正方形以内，否则四角会戳出圆底（45 个 id 实测：不内缩时最大像素
## 半径达圆盘半径的 1.33 倍，26.7% 的像素落在圆外）。GLYPH_RATIO 取 0.64 可把全部
## 45 个 id 收进圆盘内；圆盘半径 = 0.5·side·plate_ratio。
## ============================================================================

const GLYPH_RATIO := 0.64
const FALLBACK_FONT_RATIO := 0.52

var icon_id: StringName = &""
var accent: Color = UIStyle.GOLD
var badge_px: int = 24
var fallback_char: String = ""
var plate_ratio: float = 0.92          # 圆占控件的直径比（与 IconChar 一致）
var glyph_tint: Color = Color(0.0, 0.0, 0.0, 0.0)   # 全透明 = 自动按 accent 提亮

var _icon: IconRect = null


func _init(id: StringName = &"", px: int = 24, color: Color = UIStyle.GOLD,
		fb: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(px, px)
	icon_id = id
	badge_px = px
	accent = color
	fallback_char = fb
	_build_glyph()


func _ready() -> void:
	if not resized.is_connected(_layout):
		resized.connect(_layout)
	_layout()


func set_badge(id: StringName, px: int = -1, color: Color = Color(0, 0, 0, 0),
		fb: String = "") -> void:
	icon_id = id
	if px > 0:
		badge_px = px
		custom_minimum_size = Vector2(px, px)
	if color.a > 0.0:
		accent = color
	if fb != "":
		fallback_char = fb
	_build_glyph()


func set_accent(color: Color) -> void:
	accent = color
	if _icon != null:
		_icon.set_tint(_glyph_color())
	queue_redraw()


func _glyph_color() -> Color:
	if glyph_tint.a > 0.0:
		return glyph_tint
	return accent.lightened(0.35)


func _side() -> float:
	# 未进树 / 尚未布局时退回构造尺寸，避免算出 0 尺寸字模
	var s := minf(size.x, size.y)
	return s if s >= 4.0 else float(badge_px)


func _build_glyph() -> void:
	if _icon == null:
		_icon = IconRect.new(icon_id, int(round(maxf(10.0, _side() * GLYPH_RATIO))),
			_glyph_color(), fallback_char)
		add_child(_icon)
	else:
		_icon.set_icon(icon_id, int(round(maxf(10.0, _side() * GLYPH_RATIO))), fallback_char)
		_icon.set_tint(_glyph_color())
	_layout()


## 字模始终居中、内缩到圆盘内切正方形以内（容器拉伸徽章时也跟着重排）。
func _layout() -> void:
	if _icon == null:
		return
	var side := _side()
	var want := int(round(maxf(10.0, side * GLYPH_RATIO)))
	if want != _icon.icon_px:
		_icon.set_icon(icon_id, want, fallback_char)
		_icon.set_tint(_glyph_color())
	if _icon.size.x > 0.0 and side >= 4.0:
		_icon.position = (size - _icon.size) * 0.5
	queue_redraw()


## 当前是否用的是真实美术资源（调试 / 回归断言用）。
func uses_texture() -> bool:
	return _icon != null and _icon.uses_texture()


## 内层字模控件（回归测试可据此检查贴图 id / 回退字徽）。
func glyph() -> IconRect:
	return _icon


func _draw() -> void:
	# 圆底：accent 深色版 + 描边亮色（与 IconChar 同一视觉语言）
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * plate_ratio
	if r <= 0.5:
		return
	draw_circle(c, r, Color(accent.darkened(0.68), 0.92))
	draw_circle(c, r * 0.86, Color(0.0, 0.0, 0.0, 0.16))
	draw_arc(c, r - 1.0, 0.0, TAU, 36, accent, 1.6, true)
