shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
// 落水点白沫（v45 重做）：
//   · 主瀑落点 = 浓白翻涌的核心（不是整片均匀白噪），外围按流量衰减；
//   · 沿水流方向拉长的白丝 / 气泡（径向向外的各向异性噪声），一圈圈往外扩散的涟漪环；
//   · 两侧细流按流量系数变弱；白沫只留在潭面上，平面边缘按 UV 淡出（没有矩形硬边）；
//   · 夜里冷蓝白但不发白过曝。
#include "res://assets/shaders/water_surface.gdshaderinc"

uniform float foam_gain = 1.0;      // 整体强度（主瓣 / 3D 沫丘可各调）
uniform float foam_thread = 0.55;   // 拉长白丝强度
varying vec3 wp;
varying vec2 v_uv;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	float t = TIME;
	// 湍流：低频团块 + 高频碎泡
	float froth = ws_fbm(wp.xz * 2.3 + vec2(t * 0.18, -t * 0.42));
	float fine = ws_noise(wp.xz * 7.2 + vec2(-t * 0.55, t * 0.30));
	vec2 slope = vec2((froth - 0.5) * 0.30, (fine - 0.5) * 0.30);

	float core = 0.0;
	float threads = 0.0;
	float rings = 0.0;
	float halo = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i >= ws_strand_count) { break; }
		vec2 c = ws_strand_point(i);
		float w = ws_strand_flow[i];
		vec2 d = wp.xz - c;
		float r = length(d) + 0.0001;
		vec2 dir = d / r;
		// 白沫核：主瀑最宽最浓（rcore ~2.1m），两侧细流按流量收紧
		float rcore = 0.45 + w * 0.55;
		float c0 = exp(-(r * r) / (rcore * rcore));
		core += c0 * (0.24 + froth * 0.42) * (0.40 + w * 0.70);
		// 沿径向外拉的成束白丝 / 气泡：角度方向高频、半径方向低频 → 被拉长
		float ang = atan(d.y, d.x);
		float streak = ws_noise(vec2(ang * 26.0 + float(i) * 4.1, r * 2.6 - t * 1.7 + froth * 2.4));
		streak = smoothstep(0.50, 0.86, streak);
		threads += streak * exp(-r * 1.15) * smoothstep(0.25, 0.85, r) * (0.30 + w * 0.60);
		// 向外扩散的涟漪环（越远越淡，不会在潭面边缘突然截断）
		float wave = pow(max(0.0, sin(r * 10.5 - t * 2.9 + froth * 2.6 + float(i) * 1.7)), 9.0);
		rings += wave * exp(-r * 1.20) * smoothstep(0.30, 0.95, r) * (0.30 + w * 0.60);
		// 很淡的水汽光晕，把白沫和潭水连起来
		halo += exp(-(r * r) / (rcore * rcore * 5.0)) * 0.012 * (0.35 + w * 0.65);
	}

	// 平面边缘淡出（UV 边界），避免白沫平面在潭面上留一圈矩形硬边
	// 平面边缘淡出（宽一点：白沫在到达平面边界前就完全消失，不出现方形淡边）
	float border = smoothstep(0.0, 0.20, v_uv.x) * smoothstep(1.0, 0.80, v_uv.x)
		* smoothstep(0.0, 0.17, v_uv.y) * smoothstep(1.0, 0.83, v_uv.y);

	// 孔洞：白沫是「翻涌的碎沫」而不是一块白布——低频团块 + 高频碎泡决定哪里透出潭水
	float gap = smoothstep(0.18, 0.62, froth * 0.60 + fine * 0.55);
	float alpha = (core * 0.55 + threads * 0.62 * foam_thread + rings * 0.22 + halo)
		* border * foam_gain;
	alpha *= (0.28 + 0.72 * gap) * (1.0 + rain_amount * 0.20);
	ALPHA = clamp(alpha, 0.0, 0.72);

	vec3 col = mix(vec3(0.52, 0.72, 0.80), vec3(0.86, 0.95, 0.96),
		clamp(core * 0.90 + threads * 0.45, 0.0, 1.0));
	// 夜间：冷蓝白的沫花，保留落点可读性（不抬太高，避免像发光白饼）
	col = mix(col, vec3(0.22, 0.36, 0.50), night_dim * 0.72);
	ALBEDO = col;
	EMISSION = col * (0.025 + core * 0.035) * (1.0 - night_dim * 0.7);
	ROUGHNESS = mix(0.85, 0.60, clamp(core + threads, 0.0, 1.0));
	SPECULAR = 0.20;
	NORMAL = normalize((VIEW_MATRIX * vec4(vec3(-slope.x, 1.0, -slope.y), 0.0)).xyz);
}
