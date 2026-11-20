class_name SelectionController
extends Node
## 鼠标选择与命令：
## - 左键单击选中（点中单位由 SelectableComponent 处理）；点击空白处取消
## - 左键拖动框选玩家单位
## - 右键下达命令：命中敌人→攻击 / 命中资源→采集 / 否则→移动

const DRAG_THRESHOLD: float = 6.0

var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _box_rect: ColorRect


func _ready() -> void:
	_box_rect = ColorRect.new()
	_box_rect.color = Color(0.5, 0.8, 1.0, 0.25)
	_box_rect.visible = false
	_box_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var canvas := CanvasLayer.new()
	canvas.name = "BoxSelectCanvas"
	canvas.layer = 50
	canvas.add_child(_box_rect)
	get_tree().root.add_child.call_deferred(canvas)


func _unhandled_input(event: InputEvent) -> void:
	if SelectionManager.build_mode_active or SelectionManager.hero_mode_active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Godot 4 的 3D 拾取（SelectableComponent._input_event）延迟到物理帧执行，
			# set_input_as_handled 拦不住本函数：若此处仍记 _is_dragging，松开时 clear()
			# 会把刚完成的单击选中抹掉（单击选中闪一下就消失）。故按下时先自查命中：
			# 命中可选中单位 → 本次点击完全交给 SelectableComponent，不进入拖框/清除流程。
			if _selectable_under(event.position) != null:
				_is_dragging = false
				return
			_drag_start = event.position
			_is_dragging = true
		else:
			if _is_dragging:
				_is_dragging = false
				if _box_rect.visible:
					_box_rect.visible = false
					_perform_box_select(_drag_start, event.position)
				elif not event.shift_pressed:
					# 单击空白（SelectableComponent 未命中）→ 取消选择
					SelectionManager.clear()
	elif event is InputEventMouseMotion and _is_dragging:
		if event.position.distance_to(_drag_start) > DRAG_THRESHOLD:
			_update_box(_drag_start, event.position)
	elif event.is_action_pressed("command"):
		_issue_command_at(event.position)


func _update_box(start: Vector2, end: Vector2) -> void:
	_box_rect.position = Vector2(min(start.x, end.x), min(start.y, end.y))
	_box_rect.size = Vector2(abs(end.x - start.x), abs(end.y - start.y))
	_box_rect.visible = true


func _perform_box_select(start: Vector2, end: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := Rect2(
		Vector2(min(start.x, end.x), min(start.y, end.y)),
		Vector2(abs(end.x - start.x), abs(end.y - start.y))
	)
	var picked: Array = []
	for p in get_tree().get_nodes_in_group("selectable"):
		if not is_instance_valid(p):
			continue
		var screen := cam.unproject_position((p as Node3D).global_position)
		if rect.has_point(screen):
			picked.append(p)
	SelectionManager.box_select(picked)


## 屏幕点附近是否有可选中单位（身体中心投影距离 < 32px，与框选同源的投影判定）。
func _selectable_under(screen_pos: Vector2) -> Node:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var nearest: Node = null
	var best := 32.0
	for p in get_tree().get_nodes_in_group("selectable"):
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		var center: Vector3 = (p as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		if cam.is_position_behind(center):
			continue
		var d: float = cam.unproject_position(center).distance_to(screen_pos)
		if d < best:
			best = d
			nearest = p
	return nearest


func _issue_command_at(screen_pos: Vector2) -> void:
	if SelectionManager.selected.is_empty():
		return
	var cam := get_viewport().get_camera_3d() as IsometricCamera
	if cam == null:
		return
	var space := get_viewport().get_world_3d().direct_space_state
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit and hit.collider:
		var c = hit.collider
		if c.is_in_group("enemy"):
			SelectionManager.issue_attack(c)
			return
		if c.is_in_group("resource_node"):
			SelectionManager.issue_work(c)
			return
	SelectionManager.issue_move(cam.screen_to_ground(screen_pos))
