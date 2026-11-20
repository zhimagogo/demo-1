shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://assets/shaders/rain_surface.gdshaderinc"
varying vec3 world_pos;
uniform vec2 lake_center = vec2(37.0, -28.0);
uniform vec2 lake_radii = vec2(15.0, 11.0);
uniform float map_half = 64.0;
uniform vec4 water_deep : source_color = vec4(0.10, 0.39, 0.43, 1.0);
uniform vec4 water_shallow : source_color = vec4(0.40, 0.66, 0.59, 1.0);
uniform float flow_speed = 0.45;
uniform float night_dim = 0.0;   // 夜色浓度（DayNightCycle 写入）：夜里水面沉入深蓝
uniform float rain_amount = 0.0; // 雨强（WeatherSystem 写入）：雨滴打在水面的涟漪

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz;
	vec2 q = (p - lake_center) / lake_radii;
	float a = atan(q.y, q.x);
	float shore = length(q) + 0.06 * sin(a * 3.0) + 0.035 * sin(a * 7.0);
	if (shore > 1.015) { discard; }
	float t = TIME * flow_speed;
	float wave = sin(p.x * 1.6 + p.y * 0.65 + t * 2.0) * sin(p.y * 1.35 - t);
	float ripple = pow(max(0.0, sin(p.x * 2.6 + p.y * 3.0 + wave * 2.0 + t * 2.0)), 24.0);
	ripple *= smoothstep(0.35, 0.9, sin(p.x * 0.7 - p.y * 0.8 + t) * 0.5 + 0.5);
	vec3 col = mix(water_deep.rgb, water_shallow.rgb, smoothstep(0.3, 1.0, shore));
	// 夜色：水面整体沉入深蓝（保留泡沫亮度，让岸线夜里仍可读）——v3.1 提亮到月光可读
	col = mix(col, col * vec3(0.34, 0.42, 0.62) + vec3(0.008, 0.012, 0.030), night_dim);
	col += ripple * 0.022;
	float foam = smoothstep(0.955, 0.985, shore) * (1.0 - smoothstep(0.997, 1.015, shore));
	foam *= 0.6 + 0.4 * sin(a * 30.0 + t);
	col = mix(col, vec3(0.72, 0.85, 0.72), foam * 0.65);
	vec3 impact = vec3(0.0);
	if (rain_amount > 0.003) {
		impact = rain_surface(p * 1.25, TIME, rain_amount);
	}
	col += vec3(0.12, 0.16, 0.18) * impact.z * rain_amount * (1.0 - night_dim * 0.65);
	ALBEDO = col;
	vec2 slope = vec2(cos(p.x * 1.6 + t), sin(p.y * 1.3 - t)) * 0.04;
	slope += impact.xy * rain_amount * 0.12;
	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	ROUGHNESS = 0.28;
	METALLIC = 0.12;
	ALPHA = 1.0 - smoothstep(1.0, 1.015, shore);
}
