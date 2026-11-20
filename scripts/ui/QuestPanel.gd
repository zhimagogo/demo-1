class_name QuestPanel
extends PanelContainer
## 任务卡（v6 图标化重制）：左上角当前目标（quest 图标徽章 + 步骤序号 n/9）+ 进度条 +
## 奖励芯片 + 完成勾选态；完成时金色高亮闪一下再切下一张。
## 监听 QuestSystem 广播的 quest_updated / quest_completed。

var _icon: IconBadge
var _title: Label
var _desc: Label
var _bar: ProgressBar
var _progress: Label
var _reward: Label
var _reward_icon: IconRect
var _check: Label


func _ready() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 12
	offset_top = 60
	offset_right = 320
	offset_bottom = 182
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---- 标题行：任务卷轴图标徽章 + 「当前目标 n/9」 + 完成勾选 ----
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	_icon = IconBadge.new(&"quest", 22, Color(0.95, 0.80, 0.38), "任")
	head.add_child(_icon)
	_title = Label.new()
	_title.text = "当前目标"
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)
	_check = Label.new()
	_check.text = "✓ 已达成"
	_check.add_theme_font_size_override("font_size", 13)
	_check.add_theme_color_override("font_color", UIStyle.HP_GREEN)
	_check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_check.visible = false
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_check)
	root.add_child(head)

	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_desc)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar)

	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 5)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 13)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_progress)
	# 奖励：王冠小图标 + 文本（无奖励时整组隐藏）
	_reward_icon = IconRect.new(&"crown", 14, Color(0.95, 0.80, 0.38), "奖")
	_reward_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_reward_icon.visible = false
	foot.add_child(_reward_icon)
	_reward = Label.new()
	_reward.add_theme_font_size_override("font_size", 12)
	_reward.add_theme_color_override("font_color", Color(0.8, 0.9, 0.55))
	_reward.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_reward)
	root.add_child(foot)

	EventBus.quest_updated.connect(_on_quest_updated)
	EventBus.quest_completed.connect(_on_quest_completed)


func _on_quest_updated(index: int, desc: String, have: int, need: int) -> void:
	_title.text = "当前目标 %d/%d" % [index + 1, _total_steps()]
	_desc.text = desc
	_bar.max_value = maxi(1, need)          # 需量为 0 的防御性兜底：进度条不应出现除零
	_bar.value = have
	_progress.text = "%d / %d" % [mini(have, need), need]
	_check.visible = false
	_set_reward(_quest_reward_text(index))


func _on_quest_completed(_index: int, _desc: String) -> void:
	# 完成态：勾选亮起 + 进度改写 + 金色脉冲
	_check.visible = true
	_bar.value = _bar.max_value
	_progress.text = "达成！"
	_set_reward(_quest_reward_text(_index))
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.4, 1.25, 0.8), 0.12)
	tw.tween_property(self, "modulate", Color(1, 1, 1), 0.35)


## 奖励文本 + 王冠图标一起显示 / 隐藏。
func _set_reward(text: String) -> void:
	_reward.text = text
	_reward_icon.visible = text != ""


## 任务链总步数：优先读 QuestSystem（避免面板与任务链硬编码不同步），失败回退 9。
func _total_steps() -> int:
	if not is_inside_tree():
		return 9
	var sys := get_tree().get_first_node_in_group("quest_system")
	if sys == null:
		return 9
	var quests = sys.get("quests")
	if quests is Array and not (quests as Array).is_empty():
		return (quests as Array).size()
	return 9


## 单条任务的奖励文案（只读 QuestSystem 数据，面板不做任何玩法判定）。
func _quest_reward_text(index: int) -> String:
	if not is_inside_tree() or index < 0:
		return ""
	var sys := get_tree().get_first_node_in_group("quest_system")
	if sys == null:
		return ""
	var quests = sys.get("quests")
	if not (quests is Array) or index >= (quests as Array).size():
		return ""
	var q = (quests as Array)[index]
	if q == null:
		return ""
	var text = q.get("reward_text")
	return String(text) if text != null else ""
