class_name EventLog
extends VBoxContainer
## 左下消息日志（v6 图标化）：每条 = event_log 图标徽章 + 描边文字。
## 图标配色沿用消息自带的分类色（EventBus.game_message(text, color) 就是现有分类渠道），
## 缺图时的回退字也按色系区分（红=警 / 橙=报 / 绿=成 / 蓝=讯）。
## 新消息淡入、旧消息渐隐；最多 8 行。定位在主角面板右侧上方（不与建造菜单 / 日志打架）。

const MAX_LINES := 8
const FADE_START := 6.0      # 秒后开始渐隐
const FADE_TIME := 2.0
const ICON_PX := 16


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 1.0
	anchor_right = 0.0
	anchor_bottom = 1.0
	offset_left = 366
	offset_top = -300
	offset_right = 730
	offset_bottom = -100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 3)
	EventBus.game_message.connect(_on_message)


func _on_message(text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.modulate = Color(1, 1, 1, 0)

	var icon := IconBadge.new(&"event_log", ICON_PX, color, _fallback_for(color))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	add_child(row)

	# 整行一起淡入（原来是逐 Label；现在行内含图标，必须整行同步）
	var tw := row.create_tween()
	tw.tween_property(row, "modulate", Color(1, 1, 1, 1), 0.18)
	# 存活 6 秒后渐隐自毁
	var die := row.create_tween()
	die.tween_interval(FADE_START)
	die.tween_property(row, "modulate", Color(1, 1, 1, 0), FADE_TIME)
	die.tween_callback(row.queue_free)
	# 行数上限（先摘除再释放，避免 queue_free 不摘子导致的死循环——见旧版教训）
	while get_child_count() > MAX_LINES:
		var c := get_child(0)
		if c:
			remove_child(c)
			c.queue_free()


## 缺图回退字：按消息色系区分日志类别（纯表现层，不改变任何分类逻辑）。
func _fallback_for(color: Color) -> String:
	if color.s < 0.15:
		return "讯"                      # 近中性（白/灰）：普通情报
	var h := color.h
	if h < 0.06 or h >= 0.94:
		return "警"                      # 红：危险 / 损失
	if h < 0.16:
		return "报"                      # 橙金：收益 / 里程碑
	if h < 0.45:
		return "成"                      # 黄绿：达成 / 好消息
	return "讯"                          # 青蓝紫：系统与天气信息
