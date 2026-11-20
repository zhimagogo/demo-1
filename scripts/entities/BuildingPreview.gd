class_name BuildingPreview
extends Node3D
## 建造预览：半透明 ghost，跟随鼠标吸附网格，可旋转。
## 两部分：
## - _box：占地合法性框（绿=可放 / 红=不可放），尺寸=碰撞盒 mesh_size，随旋转转动。
## - _rig：真实建筑模型预览（看外观 + 旋转方向）；无 model_path 时只剩占地框。
## 旋转作用于本节点自身，框与模型一起转动，与最终放置的建筑朝向一致。

var _box: MeshInstance3D
var _rig: BuildingModelRig
var _mat_valid: StandardMaterial3D
var _mat_invalid: StandardMaterial3D
var is_valid: bool = true     # 最近一次 set_valid 的结果（绿/红态）；测试与调用方可直接读，不必碰材质
var _road_material: ShaderMaterial
var _is_road: bool = false


func _ready() -> void:
	_mat_valid = _make_mat(Color(0.2, 1.0, 0.3, 0.35))
	_mat_invalid = _make_mat(Color(1.0, 0.25, 0.25, 0.35))

	_box = MeshInstance3D.new()
	_box.name = "GhostBox"
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.material_override = _mat_valid
	add_child(_box)

	_rig = BuildingModelRig.new()
	_rig.name = "ModelRig"
	add_child(_rig)

	visible = false


func setup(def: BuildingDef) -> void:
	_is_road = def.is_road
	# 占地框 = 碰撞盒体积（绿/红），显示占地范围与合法性
	var box := BoxMesh.new()
	box.size = def.mesh_size
	_box.mesh = box
	_box.position.y = def.mesh_size.y * 0.5
	_box.material_override = _mat_valid
	if _is_road:
		var plane := PlaneMesh.new()
		plane.size = Vector2(def.mesh_size.x, def.mesh_size.z)
		_box.mesh = plane
		_box.position.y = 0.055
		_road_material = ShaderMaterial.new()
		_road_material.shader = preload("res://assets/shaders/dirt_road.gdshader")
		_box.material_override = _road_material
		set_valid(true)
	# 真实模型预览：有 model_path 才挂载，否则只剩占地框（回退）
	if def.model_path != "" and _rig.setup(def.model_path, def.model_scale, def.model_face_offset_deg, def.model_height_offset):
		pass   # 模型挂载成功
	else:
		_rig.clear_model()
	visible = true


## 应用建造旋转（0/1/2/3 → 0/90/180/270°）。整体转动占地框 + 模型，与放置朝向一致。
func set_rotation_steps(steps: int) -> void:
	rotation = Vector3.ZERO if _is_road else Vector3(0.0, deg_to_rad(steps * 90.0), 0.0)


func set_valid(ok: bool) -> void:
	is_valid = ok
	if _is_road:
		_road_material.set_shader_parameter("road_tint", Color(0.6, 1.0, 0.5, 0.7) if ok else Color(1.0, 0.25, 0.2, 0.7))
	else:
		_box.material_override = _mat_valid if ok else _mat_invalid


func set_road_connections(mask: int) -> void:
	if _is_road and _road_material != null:
		_road_material.set_shader_parameter("connections", mask)


func hide_preview() -> void:
	visible = false


func _make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
