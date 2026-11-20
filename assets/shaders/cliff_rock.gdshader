shader_type spatial;
render_mode cull_disabled;
// 崖体岩石（v43）：岩层条带 + 裂缝 + 苔藓（朝上的面）+ 湿岩（落在水帘下方 / 潭边 / 出水口附近）。
// 湿岩判定不再只看「离潭心多远」——崖壁距潭心 8m 也会被水帘打湿，因此同时算到落水线的距离。
#include "res://assets/shaders/water_surface.gdshaderinc"
uniform vec4 rock_color : source_color = vec4(0.58, 0.56, 0.51, 1.0);
uniform vec4 rock_moss : source_color = vec4(0.36, 0.44, 0.25, 1.0);
uniform float rock_wet = 0.2;
varying vec3 world_pos;
varying vec3 world_nrm;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// 把 y 揉进 xz 采样 → 岩面纹理不会沿水平方向被拉成竖条
	vec2 p = vec2(world_pos.x + world_pos.y * 0.7, world_pos.z + world_pos.y * 1.9);
	float grain = ws_noise(p * 1.4);
	float fine = ws_noise(p * 5.3 + vec2(3.7, 1.9));
	// 岩层：明显但不断裂的层理（两层不同厚度）
	float strata = smoothstep(0.78, 0.97, sin(world_pos.y * 4.4 + ws_noise(p * 0.4) * 2.4) * 0.5 + 0.5);
	float strata2 = smoothstep(0.86, 0.99, sin(world_pos.y * 11.0 + ws_noise(p * 0.9) * 1.7) * 0.5 + 0.5);
	// 裂缝：噪声脊线，压暗成细缝
	float crack = smoothstep(0.47, 0.50, abs(ws_noise(p * 2.6) - 0.5) * 2.0);
	crack *= smoothstep(0.35, 0.62, ws_noise(p * 0.8 + vec2(5.1, 2.3)));
	vec3 col = rock_color.rgb * (0.86 + grain * 0.18 - strata * 0.09 - strata2 * 0.05 - crack * 0.22);
	col += vec3(fine - 0.5) * 0.045;
	// 苔藓：朝上的面长苔，侧面只留薄薄一圈（外加低频斑块）
	float up = smoothstep(0.28, 0.78, world_nrm.y);
	float moss = up * (0.55 + 0.45 * ws_noise(world_pos.xz * 0.7));
	moss += smoothstep(0.55, 0.92, ws_noise(p * 1.1 + vec2(9.3, 4.1))) * 0.32 * smoothstep(0.1, 0.5, world_nrm.y);
	col = mix(col, rock_moss.rgb, clamp(moss, 0.0, 1.0) * 0.88);
	// 湿岩：潭边 + 落水线附近（把 xz 投影到「唇口→落水点」线段上量距离）
	vec2 seg = ws_waterfall_b - ws_waterfall_a;
	float along = clamp(dot(world_pos.xz - ws_waterfall_a, seg) / max(dot(seg, seg), 1e-3), 0.0, 1.0);
	float line_d = distance(world_pos.xz, ws_waterfall_a + seg * along);
	float wet_pool = 1.0 - smoothstep(2.4, 6.0, distance(world_pos.xz, ws_waterfall_b));
	float wet_fall = 1.0 - smoothstep(1.1, 3.6, line_d);
	float wet = max(wet_pool * 0.9, wet_fall) * rock_wet;
	col *= 1.0 - wet * 0.30;
	// 湿面偏深青，且更光滑（雨后整体再压暗一点）
	col = mix(col, col * vec3(0.72, 0.86, 0.92), wet * 0.45);
	col *= 1.0 - rain_amount * 0.16;
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.42, wet) - rain_amount * 0.10;
	SPECULAR = mix(0.25, 0.55, wet);
	// 夜间：只压暗不洗灰（冷色调乘算，保留苔藓的绿）
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.30, 0.44, 0.58), night_dim * 0.72);
	EMISSION = rock_moss.rgb * 0.02 * night_dim;
}
