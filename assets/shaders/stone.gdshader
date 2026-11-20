shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

// 石头 / 卵石：主角周围半球消散（v13，见 decor_dissolve.gdshaderinc）。
// 石头本是实体块，这里同样给它消散能力 —— 主角贴脸时不该被一块半人高的石头糊住视线。
#include "res://assets/shaders/decor_dissolve.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 stone_deep : source_color = vec4(0.40, 0.40, 0.38, 1.0);
uniform vec4 stone_light : source_color = vec4(0.68, 0.67, 0.63, 1.0);
uniform float dissolve_scale = 0.28;
uniform vec4 dissolve_tint : source_color = vec4(0.74, 0.76, 0.72, 1.0);

varying float variation;
varying vec3 v_world;
varying float v_dissolve;
varying float v_zone;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xz;
	variation = fract(sin(dot(origin, vec2(21.9898, 58.233))) * 21378.5453);
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
	// 石头统一压成冷灰调，和林地/草原分开（贴图偏暖时也不突兀）
	vec3 stone = mix(stone_deep.rgb, stone_light.rgb, variation) * (0.72 + original.r * 0.5);
	ALBEDO = mix(stone, dissolve_tint.rgb, smoothstep(0.35, 1.0, v_dissolve) * 0.5);
	ALPHA = dissolve_alpha(v_dissolve, v_zone);
	METALLIC = 0.0;
	ROUGHNESS = 0.96;
}
