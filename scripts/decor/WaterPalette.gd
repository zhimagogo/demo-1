class_name WaterPalette
extends RefCounted
## 水体调色板（v45）：湖泊 / 河流 / 水潭三张静水面的颜色与质感参数只在这里写。
##
## 为什么单独一个文件：湖面材质定义在 Main.tscn（ws_region_cut=1），河 / 潭材质由
## WaterFeature 运行时创建，原先颜色散落在 WaterFeature._ready() 里；水体表现迭代时
## 只要改这里，不必动几何 / 网格代码。**着色公式在 assets/shaders/**，
## 这里只写 uniform（颜色 / 深浅 / 通透感），几何真相仍在 WorldLayout。
##
## region: 1 湖 / 2 河 / 3 潭（与 WorldLayout.set_water_region 同口径）。
##
## v45 配色原则（修「湖面大片乳白像冰面」）：
##   · 深水 = 暗蓝绿（压暗、偏蓝绿），浅水 = 饱和青绿；两者之间用 shader 的三段式混出层次，
##     这里不再出现任何接近灰白的高明度色；
##   · 浅滩 shelf = 沙绿（水下透底），只在贴岸 / 岛周 ~1m 的窄带里出现；
##   · 白沫 foam = 冷白但明度受限，只做断续细线（着色器里还有一次断续 + 衰减）；
##   · 岸树倒影 reflect = 很暗的青绿，只在贴岸狭窄带里按视角叠加。

## 湖泊：深水暗蓝绿 / 浅水饱和青绿。
const LAKE_DEEP := Color(0.010, 0.086, 0.120)
const LAKE_SHALLOW := Color(0.150, 0.440, 0.390)
const LAKE_SHELF := Color(0.265, 0.320, 0.235)
const LAKE_FOAM := Color(0.600, 0.735, 0.700)
const LAKE_REFLECT := Color(0.030, 0.092, 0.070)

## 河流：比湖略深一档（窄水面更暗），但仍保持青绿。
const RIVER_DEEP := Color(0.012, 0.082, 0.108)
const RIVER_SHALLOW := Color(0.125, 0.395, 0.355)
const RIVER_SHELF := Color(0.250, 0.300, 0.225)
const RIVER_FOAM := Color(0.585, 0.720, 0.690)
const RIVER_REFLECT := Color(0.026, 0.082, 0.064)

## 水潭：主瀑翻涌区略亮，外圈回深；整体比湖更冷更暗。
const POOL_DEEP := Color(0.010, 0.076, 0.102)
const POOL_SHALLOW := Color(0.135, 0.410, 0.380)
const POOL_SHELF := Color(0.245, 0.295, 0.230)
const POOL_FOAM := Color(0.610, 0.745, 0.710)
const POOL_REFLECT := Color(0.028, 0.086, 0.068)


static func apply(mat: ShaderMaterial, region: int) -> void:
	if mat == null:
		return
	match region:
		1:
			mat.set_shader_parameter("water_deep", LAKE_DEEP)
			mat.set_shader_parameter("water_shallow", LAKE_SHALLOW)
			mat.set_shader_parameter("water_shelf", LAKE_SHELF)
			mat.set_shader_parameter("water_foam", LAKE_FOAM)
			mat.set_shader_parameter("water_reflect", LAKE_REFLECT)
		2:
			mat.set_shader_parameter("water_deep", RIVER_DEEP)
			mat.set_shader_parameter("water_shallow", RIVER_SHALLOW)
			mat.set_shader_parameter("water_shelf", RIVER_SHELF)
			mat.set_shader_parameter("water_foam", RIVER_FOAM)
			mat.set_shader_parameter("water_reflect", RIVER_REFLECT)
		3:
			mat.set_shader_parameter("water_deep", POOL_DEEP)
			mat.set_shader_parameter("water_shallow", POOL_SHALLOW)
			mat.set_shader_parameter("water_shelf", POOL_SHELF)
			mat.set_shader_parameter("water_foam", POOL_FOAM)
			mat.set_shader_parameter("water_reflect", POOL_REFLECT)


## 三张水面一次性调色（WaterFeature._ready 与潜在的工具脚本共用）。
static func apply_all(lake: ShaderMaterial, river: ShaderMaterial, pool: ShaderMaterial) -> void:
	apply(lake, 1)
	apply(river, 2)
	apply(pool, 3)
