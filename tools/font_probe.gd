extends Node
## 字体链诊断：确认自带字体是否可加载，以及 SystemFont 兜底是否报错。

func _ready() -> void:
	print("FONT source=", UIStyle.font_source())
	var f: Font = UIStyle.make_font()
	print("FONT class=", f.get_class(), " ascent=", f.get_ascent(16), " descent=", f.get_descent(16))
	print("FONT string_size=", f.get_string_size("第1天 12:00", HORIZONTAL_ALIGNMENT_LEFT, -1, 16))
	print("FONT theme_fallback=", ThemeDB.fallback_font, " ascent=", ThemeDB.fallback_font.get_ascent(16) if ThemeDB.fallback_font != null else -1)
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["PingFang SC", "Hiragino Sans GB", "sans-serif"])
	print("FONT system ascent=", sf.get_ascent(16), " class=", sf.get_class())
	var ff := ResourceLoader.load("res://assets/ui/fonts/ui_cjk.ttf", "Font") as FontFile
	if ff != null:
		print("FONT file ok ascent=", ff.get_ascent(16), " faces=", ff.get_face_count(), " data=", ff.data.size())
		ff.fallbacks = []
		print("FONT file no-fallback ascent=", ff.get_ascent(16))
	get_tree().quit()
