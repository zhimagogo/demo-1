extends CanvasLayer
## ============================================================================
## PostFx —— v47 后处理调色层（挂在 Main 下，CanvasLayer.layer = 0）。
##
## 为什么用 CanvasLayer 而不是 Environment.adjustment：
##   环境自带 adjustment 只能线性调亮度/对比/饱和度，做不了暗角与颗粒；
##   而 CanvasLayer 0 位于 3D 之后、HUD（CanvasLayer 1）之前，
##   因此画面被调色而 UI 保持原始颜色与清晰度，也不会拦截点击。
##
## 强度由 RenderQuality 的档位预设通过 apply_render_quality() 写入；
## 默认隐藏，只有中档以上才显示（低档完全跳过这一层，省一个全屏 pass）。
## ============================================================================

const GRADE_SHADER := preload("res://assets/shaders/post_grade.gdshader")

var _rect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 0
	visible = false
	_material = ShaderMaterial.new()
	_material.shader = GRADE_SHADER
	_rect = ColorRect.new()
	_rect.name = "Grade"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_rect.material = _material
	add_child(_rect)
	# 先锚满父级再清零 offsets：preset 在已有布局里会按当前 rect 回推负 offsets。
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.offset_left = 0.0
	_rect.offset_top = 0.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0


## RenderQuality 调用：按档位开关本层并写入强度。
func apply_render_quality(preset: Dictionary) -> void:
	if _material == null:
		return
	var enabled := bool(preset.get("post_fx", true))
	visible = enabled
	if not enabled:
		return
	_material.set_shader_parameter("vignette", float(preset.get("vignette", 0.2)))
	_material.set_shader_parameter("grain", float(preset.get("grain", 0.01)))
	_material.set_shader_parameter("grade", float(preset.get("grade", 1.0)))
