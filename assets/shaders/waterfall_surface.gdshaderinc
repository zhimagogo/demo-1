// ============================================================================
// 瀑布立面着色库（v45 从 water_surface.gdshaderinc 拆出 / 重写）：
// 落水帘的纵向水丝 / 白沫 / 入水翻涌全部在这里，共享 uniform（ws_*、sun_*、night_dim、
// rain_amount）与噪声工具来自 water_surface.gdshaderinc。改立面着色只动本文件，
// 不要改共享库；湖泊 / 河流 / 水潭的静水面着色在共享库的 ground_water()。
//
// v45 观感目标（对照 v45-base）：
//   · 不再是「一块均匀发亮的平板」：深青阴影里透出亮白水芯，长水丝 / 细水丝 / 断续白沫
//     三种频率叠在一起，下游（v 大）流得比瀑顶快（sqrt 加速采样）；
//   · 左右边缘按噪声羽化（并强制在最外侧 taper 到 0），上下边缘都不留直切线；
//   · 底部入水处翻涌成白、被噪声蚀碎，交给潭面白沫网格（waterfall_foam）接着；
//   · 多层水膜共用本函数：顶点色 COLOR 四通道携带该层参数，见 waterfall.gdshader。
// ============================================================================
#ifndef WATERFALL_SURFACE_INC
#define WATERFALL_SURFACE_INC

#include "res://assets/shaders/water_surface.gdshaderinc"

// ============================================================================
// 瀑布立面着色：p = 世界 xz（立面倾斜时近似），v = 纵向 0..1，lat = 横向 -0.5..0.5，
// bright = 该股明亮度（顶点色 r 通道，主瀑 1.0，两侧细流 0.7~0.86），
// flow = 该层流速倍率（顶点色 g 通道，前层更快 → 视差），
// opacity = 该层整体不透明度（顶点色 b 通道，薄水膜 0.3~0.55），
// shade = 该层明暗（顶点色 a 通道，后层压暗 → 叠出前后层次）。
// ============================================================================
vec3 waterfall_surface(vec2 p, float v, float lat, float bright, float flow, float opacity,
		float shade, out vec2 slope, out float alpha) {
	// ---- 纵向水丝：sqrt(v) 采样 = 下游更快（重力加速），各层 flow 不同 → 视差 ----
	float t = TIME * (1.15 + flow * 0.62);
	float adv = sqrt(max(v, 0.0) + 0.012) * 4.6 * (0.80 + flow * 0.20) - t;
	float wob = sin(v * 6.4 + 1.3) * 0.34 + sin(v * 15.0 - 0.6) * 0.13;
	float wob2 = sin(v * 3.1 - 0.4) * 0.20;

	// 三层频率：大块水幕明暗（慢）/ 主水丝 / 细水丝
	float veil = ws_fbm(vec2(lat * 3.4 + wob2, adv * 0.55 + 1.7));
	float ribbons = ws_noise(vec2(lat * 15.0 + wob, adv * 1.30));
	float mid_rib = ws_noise(vec2(lat * 31.0 + wob * 0.6, adv * 1.85 + 4.3));
	float fine = ws_noise(vec2(lat * 74.0, adv * 2.60 + 7.3));
	float strands = smoothstep(0.44, 0.78, ribbons) * 0.55
		+ smoothstep(0.52, 0.82, mid_rib) * 0.26
		+ smoothstep(0.64, 0.88, fine) * 0.15;

	// 断续白沫团：沿 v 反复出现、横向成块（不是一条连续的亮带）
	float clumps = smoothstep(0.52, 0.86,
		ws_noise(vec2(lat * 9.0 + 3.7, v * 8.0 - TIME * (0.85 + flow * 0.30) + veil * 1.6)));
	float clumps2 = smoothstep(0.58, 0.90,
		ws_noise(vec2(lat * 21.0 + 7.1, v * 15.0 - TIME * (1.35 + flow * 0.45))));

	// ---- 边缘羽化：噪声 + 强制在最外侧（|lat|→0.5）收敛到 0，杜绝刀切直边 ----
	float edge_n = ws_noise(vec2(lat * 5.5 + 2.3, v * 3.2 - TIME * 0.30)) - 0.5;
	float edge = 1.0 - smoothstep(0.30, 0.475, abs(lat) + edge_n * 0.11);
	edge *= 1.0 - smoothstep(0.435, 0.498, abs(lat));
	// 顶部（贴着唇口/岩檐）与底部（入水）也淡入淡出，避免上下直切线
	float top_fade = smoothstep(0.008, 0.055, v);
	float plunge = smoothstep(0.58, 0.97, v);
	float bottom_tear = mix(1.0, 0.20 + 0.80 * clumps * (0.55 + 0.45 * clumps2),
		smoothstep(0.90, 1.0, v));

	// ---- alpha：水膜本体（偏透明，让后面的岩壁 / 后层透出来）+ 落水翻涌 ----
	float body = (0.33 + strands * 0.42 + veil * 0.12) * edge * top_fade * bottom_tear;
	float froth = plunge * (0.06 + clumps * 0.22 + clumps2 * 0.10) * edge * top_fade;
	alpha = clamp((body + froth) * opacity, 0.0, 0.97);
	// 薄水膜 / 侧流整体更淡一些（细流读作「挂在岩壁上的水膜」）
	alpha *= 0.72 + bright * 0.28;

	// ---- 颜色：深青阴影 → 青蓝水膜 → 亮白水芯（夜里偏冷月青，不惨白）----
	vec3 deep = vec3(0.022, 0.098, 0.135);
	vec3 mid = vec3(0.060, 0.255, 0.305);
	vec3 lit = vec3(0.300, 0.520, 0.580);
	vec3 white = vec3(0.890, 0.955, 0.970);
	vec3 col = mix(deep, mid, clamp(veil * 0.85 + strands * 0.28, 0.0, 1.0));
	col = mix(col, lit, smoothstep(0.52, 0.94, ribbons) * 0.38);
	// 水芯：只给最亮的细丝（收窄），越靠近底部翻涌越白
	float core = clamp(strands * 0.18 + fine * 0.10, 0.0, 1.0) * (0.40 + 0.60 * smoothstep(0.05, 0.95, v));
	col = mix(col, white, core * 0.85);
	col = mix(col, white, plunge * (0.12 + clumps * 0.30 + clumps2 * 0.10) * smoothstep(0.25, 0.80, strands + fine));
	col *= 0.58 + bright * 0.48;
	col *= shade;

	// 夜间：冷月色（压暗但保住青蓝层次，不发灰 / 不惨白）
	vec3 night_col = col * vec3(0.30, 0.48, 0.68) + vec3(0.008, 0.022, 0.038) * (0.35 + strands);
	col = mix(col, night_col, night_dim * 0.86);
	col *= 1.0 - rain_amount * 0.08;

	slope = vec2((veil - 0.5) * 0.10 + (ribbons - 0.5) * 0.05,
		(mid_rib - 0.5) * 0.08 + (fine - 0.5) * 0.04);
	return col;
}

#endif
