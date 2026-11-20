shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque, depth_prepass_alpha;
// 完全可见的树冠先写深度并投影，草坪能接到树荫；消散区仍保留 alpha 淡出。

// 树木 / 水草：主角周围半球消散（v13，见 decor_dissolve.gdshaderinc）
#include "res://assets/shaders/decor_dissolve.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 forest_deep : source_color = vec4(0.23, 0.39, 0.29, 1.0);
uniform vec4 forest_light : source_color = vec4(0.45, 0.57, 0.33, 1.0);
// v40.2 树干去红：KayKit 树干的红棕贴图在草地上像「红棍」，非叶像素按灰色木调重混。
// 默认灰褐 #4a3f34 → #6b5a48；区域树只调 forest_* 与 stone_*，树干自动跟随这套默认值。
uniform vec4 trunk_deep : source_color = vec4(0.29, 0.25, 0.20, 1.0);
uniform vec4 trunk_light : source_color = vec4(0.42, 0.35, 0.28, 1.0);
uniform float dissolve_scale = 0.11;   // 世界空间噪声频率（与草共用一套，靠 instance scale 归一）
uniform vec4 dissolve_tint : source_color = vec4(0.70, 0.84, 0.66, 1.0);

varying float variation;
varying vec3 v_world;
varying float v_dissolve;
varying float v_zone;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xz;
	variation = fract(sin(dot(origin, vec2(12.9898, 78.233))) * 43758.5453);
	float tip = smoothstep(0.3, 1.1, VERTEX.y);
	VERTEX.x += sin(TIME * 1.1 + origin.x * 0.18 + origin.y * 0.12) * 0.012 * tip;

	// 半球消散：用【顶点世界坐标】判定（树冠比树干高，冠部先散、树干根部留着），
	// 噪声频率按实例缩放归一 —— 树是 3~4 倍缩放、水草 1.5 倍，归一后消隐块尺寸一致。
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float inst_scale = max(length(MODEL_MATRIX[0].xyz), 0.01);
	v_dissolve = dissolve_cut(v_world, dissolve_scale / inst_scale);
	v_zone = dissolve_zone(v_world);
}

void fragment() {
	if (dissolve_clip(v_world, FRAGCOORD.xy, dissolve_scale, v_dissolve)) {
		discard;
	}
	vec3 original = texture(albedo_texture, UV).rgb;
	float leaves = smoothstep(0.01, 0.08, original.g - original.r) * smoothstep(-0.01, 0.06, original.g - original.b);
	vec3 canopy = mix(forest_deep.rgb, forest_light.rgb, variation) * (0.8 + original.g * 0.55);
	// 非叶像素（树干 / 水草茎 / 蘑菇柄）：保留贴图明暗，但色相压成灰褐木色
	vec3 wood = mix(trunk_deep.rgb, trunk_light.rgb, variation) * (0.72 + original.r * 0.55);
	vec3 col = mix(wood, canopy, leaves);
	// 消散边缘泛亮，让「正在消散的枝叶」有存在感
	ALBEDO = mix(col, dissolve_tint.rgb, smoothstep(0.35, 1.0, v_dissolve) * 0.5);
	ALPHA = dissolve_alpha(v_dissolve, v_zone);
	ROUGHNESS = 0.92;
}
