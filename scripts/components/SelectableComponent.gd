class_name SelectableComponent
extends Area3D
## 可选中组件：响应鼠标左键点击，通知 SelectionManager。
## 仅挂载于玩家可控单位。

signal clicked(owner_node: Node)


func _ready() -> void:
	# 确保 Area3D 可被射线拾取
	input_ray_pickable = true
	monitoring = false   # 仅作拾取用，不参与物理重叠检测
	# 拾取区独占 layer 7（pickable）：第三人称准星射线（mask=world|structure）可穿透
	# 所有单位身体——否则相机拉在主角身后时，主角自己的选中圆柱永远第一个挡住准星。
	# Camera3D 的物体拾取（input_event）不做 layer 过滤，点击选择行为不变。
	collision_layer = 64


func _input_event(_camera: Camera3D, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# 主角模式下左键用于普攻：不选中、不拦截（事件继续冒泡到 HeroController）
	if SelectionManager.hero_mode_active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var owner_node: Node = get_parent()
		clicked.emit(owner_node)
		if event.shift_pressed:
			SelectionManager.add_to_selection(owner_node)
		else:
			SelectionManager.select_only(owner_node)
		get_viewport().set_input_as_handled()   # 阻止 SelectionController 再次处理（避免 clear 覆盖选中）
