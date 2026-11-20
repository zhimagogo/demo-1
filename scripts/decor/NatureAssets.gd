class_name NatureAssets
extends RefCounted
## 保留模型原有树干纹理，统一林冠的自然色调与轻微风动。
## v13：林冠 / 石头材质换成带「主角半球消散」的 shader（见 decor_dissolve.gdshaderinc），
## 判定半径由 DecorationDissolveSystem 通过全局 shader 参数驱动。

const FOLIAGE_SHADER := preload("res://assets/shaders/foliage.gdshader")
const STONE_SHADER := preload("res://assets/shaders/stone.gdshader")
const GENERIC_SHADER := preload("res://assets/shaders/decor_generic.gdshader")


## 通用装饰材质：把纯色 StandardMaterial3D 换成语义等价的消散材质
## （花朵、金叶林树干/树冠这类没有贴图的小装饰）。
static func dissolve_material(color: Color, roughness: float = 0.95, scale: float = 1.1) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GENERIC_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("base_roughness", roughness)
	material.set_shader_parameter("dissolve_scale", scale)
	return material


static func forest_mesh(source: Mesh) -> Mesh:
	var mesh := source.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var original := mesh.surface_get_material(surface) as StandardMaterial3D
		if original == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = FOLIAGE_SHADER
		material.set_shader_parameter("albedo_texture", original.albedo_texture)
		mesh.surface_set_material(surface, material)
	return mesh


## 石头 / 卵石：同样接入半球消散（主角贴脸时不该被石块糊住视线）。
static func stone_mesh(source: Mesh) -> Mesh:
	var mesh := source.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var original := mesh.surface_get_material(surface) as StandardMaterial3D
		if original == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = STONE_SHADER
		material.set_shader_parameter("albedo_texture", original.albedo_texture)
		mesh.surface_set_material(surface, material)
	return mesh


static func style_tree(root: Node) -> void:
	if root is MeshInstance3D:
		var visual := root as MeshInstance3D
		visual.mesh = forest_mesh(visual.mesh)
	for child in root.get_children():
		style_tree(child)
