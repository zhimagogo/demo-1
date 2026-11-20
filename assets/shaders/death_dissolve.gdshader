// v16 死亡贴图溶解：怪物死亡动画播完后，模型按噪声阈值逐片「烧蚀消散」。
// 用法：PawnModelRig.begin_dissolve() 逐 surface 生成 ShaderMaterial（拷贝原 albedo 颜色/贴图），
// 之后每帧写 dissolve_progress 0→1 驱动；到 1 时全部片元 discard（配合外层 queue_free）。
// 采用 discard（alpha_scissor 思路）而非透明混合：不产生排序问题，阴影也同步消散。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
// 溶解进度：0 = 完整，1 = 全部消散。由 DeadState 每帧写入。
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.3) = 0.08;       // 烧灼边缘带宽（噪声值域内）
uniform vec4 burn_color : source_color = vec4(1.0, 0.42, 0.12, 1.0); // 边缘灼烧色
uniform float burn_emission : hint_range(0.0, 8.0) = 2.2;     // 边缘自发光强度
uniform float noise_scale : hint_range(1.0, 32.0) = 7.0;      // 噪声频率（碎块大小）

// ---- 简易 fbm 值噪声（无需外部贴图；逐 UV 取阈值场）----
float dh_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float dvalue_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);   // 平滑插值，避免网格感
	float a = dh_hash(i);
	float b = dh_hash(i + vec2(1.0, 0.0));
	float c = dh_hash(i + vec2(0.0, 1.0));
	float d = dh_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float dfbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * dvalue_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec4 base = albedo_color;
	if (use_texture) {
		base *= texture(albedo_texture, UV);
	}
	// 阈值场：progress=1 时 cutoff 超过 fbm 上界（~0.94），保证彻底消散无残片
	float n = dfbm(UV * noise_scale);
	float cutoff = dissolve_progress * (1.0 + edge_width);
	if (n < cutoff - edge_width) {
		discard;
	}
	// 接近阈值的带状区域做烧灼：越接近边缘越亮越偏燃烧色
	float edge = 1.0 - smoothstep(cutoff - edge_width, cutoff, n);
	ALBEDO = mix(base.rgb, burn_color.rgb, edge);
	ROUGHNESS = mix(0.9, 0.4, edge);
	EMISSION = burn_color.rgb * edge * edge * burn_emission;
}
