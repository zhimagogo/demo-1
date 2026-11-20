shader_type spatial;
// specular_disabled：瀑顶是水平大平面，太阳/月光镜面会在整块面上拉出白亮条纹（读成苍白平片），
// 这里直接关掉镜面，靠反照率 + 流动法线 + 唇口白沫出效果。
render_mode cull_back, depth_draw_opaque, specular_disabled;
// 瀑顶溢流（v45 重做）：岩槽里的山溪 → 唇口翻卷。
//   · 深青水色 + 沿流向（+Z）拉长的流动噪波水丝，不再是「天蓝色泳池板」；
//   · 细密流动波纹法线（specular 只留一点，避免整块平面被太阳打白）；
//   · 唇口前缘白色翻沫（feed_lip_foam）+ 两侧岩岸 / 卵石压边白沫（feed_edge_foam），
//     唇口越近水越白、越碎，和落水帘顶部的卷边接上；
//   · 夜里冷青偏暗，不发灰。
#include "res://assets/shaders/water_surface.gdshaderinc"

uniform vec4 feed_deep : source_color = vec4(0.016, 0.086, 0.120, 1.0);
uniform vec4 feed_mid : source_color = vec4(0.050, 0.205, 0.250, 1.0);
uniform vec4 feed_foam_color : source_color = vec4(0.84, 0.94, 0.95, 1.0);
uniform float feed_flow = 1.55;        // 流速（世界 z 向下游）
uniform float feed_lip_foam = 0.55;    // 唇口前缘白沫强度（0..1）
uniform float feed_edge_foam = 0.22;   // 两侧压边白沫强度（0..1）
uniform float feed_lip_z = -72.0;      // 唇口世界 z（白沫从这条线往上游衰减）
uniform float feed_half_width = 3.3;   // 水道半宽（米，压边白沫按它算）
uniform float feed_center_x = 58.0;    // 水道中心世界 x
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float t = TIME * feed_flow;
	// 各向异性噪声：x 高频 / z 低频 + 沿 -z 平移 = 被拉长、向下游走的水丝
	vec2 fp = vec2(wp.x * 3.8 + sin(wp.z * 0.85) * 0.32, wp.z * 0.80 - t);
	float streak = ws_fbm(fp);
	float fine = ws_noise(vec2(wp.x * 9.0 + 1.7, wp.z * 2.5 - t * 1.55));
	float ripple = ws_noise(vec2(wp.x * 6.0 - 2.3, wp.z * 4.4 - t * 2.3));

	// 水色：深青打底，水丝处提到青绿（很轻，主体压深）
	vec3 col = mix(feed_deep.rgb, feed_mid.rgb, 0.22 + streak * 0.62);
	col = mix(col, vec3(0.24, 0.44, 0.48), smoothstep(0.62, 0.94, fine) * 0.26);

	// 流动波纹法线（沿流向拉伸的细波 + 斜向交叉纹；幅度偏大 → 高光被打碎，不糊成白板）
	vec2 slope = vec2((fine - 0.5) * 0.40 + sin(wp.x * 2.6 + t * 0.7) * 0.07,
		(streak - 0.5) * 0.30 + sin(wp.z * 3.9 - t * 1.5) * 0.09);

	// 唇口前缘白沫：越靠近唇口越白、越碎（翻卷加速）
	// 白沫只留唇口最后 ~0.95m（原先铺满整块薄片 → 读成苍白平片）
	float lip = smoothstep(feed_lip_z - 0.50, feed_lip_z + 0.02, wp.z);
	float lip_foam = lip * (0.25 + 0.75 * smoothstep(0.44, 0.82,
		ws_noise(vec2(wp.x * 4.6 + t * 0.25, wp.z * 2.1 + t * 1.5)))) * feed_lip_foam;
	// 两侧压边白沫：贴岩岸 / 卵石边的一条不规则白线
	float edge_d = smoothstep(feed_half_width * 0.58, feed_half_width * 1.04,
		abs(wp.x - feed_center_x));
	float edge_foam = edge_d * (0.20 + 0.80 * streak) * feed_edge_foam;
	float foam = clamp(lip_foam + edge_foam, 0.0, 1.0);
	// 白沫也要吃夜色：夜里是暗冷蓝的沫花，不是发光白板
	vec3 foam_col = feed_foam_color.rgb * mix(1.0, 0.42, night_dim);
	col = mix(col, foam_col, foam);

	// 夜间：冷青压暗（保持青色饱和度，不发灰）
	vec3 night_col = col * vec3(0.28, 0.46, 0.66) + vec3(0.008, 0.020, 0.034);
	col = mix(col, night_col, night_dim * 0.86);
	col *= 1.0 - rain_amount * 0.10;

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(vec3(-slope.x, 1.0, -slope.y), 0.0)).xyz);
	ROUGHNESS = mix(0.50, 0.72, foam) + rain_amount * 0.06 + night_dim * 0.10;
	METALLIC = 0.0;
	// 夜里把镜面高光几乎收掉（瀑布顶是水平面，月光下很容易糊成一块亮平片）
	SPECULAR = 0.05 * (1.0 - night_dim * 0.90);
	EMISSION = col * 0.012 * (1.0 - night_dim * 0.8) + foam_col * foam * 0.010;
}
