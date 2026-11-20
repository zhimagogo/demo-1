shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

// 通用「半球消散」装饰材质（v13）：给原本只有 StandardMaterial3D 的装饰网格用
// （花朵、金叶林树干/树冠等），保留原 albedo 与粗糙度，仅叠加主角周围消散。
#include "res://assets/shaders/decor_dissolve.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float base_roughness = 0.95;
uniform float dissolve_scale = 1.1;
uniform vec4 dissolve_tint : source_color = vec4(0.78, 0.86, 0.70, 1.0);

varying vec3 v_world;
varying float v_dissolve;
varying float v_zone;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float inst_scale = max(length(MODEL_MATRIX[0].xyz), 0.01);
	v_dissolve = dissolve_cut(v_world, dissolve_scale / inst_scale);
	v_zone = dissolve_zone(v_world);
}

void fragment() {
	if (dissolve_clip(v_world, FRAGCOORD.xy, dissolve_scale, v_dissolve)) {
		discard;
	}
	ALBEDO = mix(base_color.rgb, dissolve_tint.rgb, smoothstep(0.35, 1.0, v_dissolve) * 0.45);
	ALPHA = dissolve_alpha(v_dissolve, v_zone);
	ROUGHNESS = base_roughness;
	METALLIC = 0.0;
}
