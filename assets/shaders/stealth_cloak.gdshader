// v33 隐身披风：小兵「隐身」状态的模型表现（PawnModelRig.set_stealth 逐 surface 换成本材质）。
// 用法：从原材质拷贝 albedo_color / albedo_texture，之后写 cloak 0→1 渐变驱动幽灵化；
// 结束（破隐 / 到期）反向写回 0 并恢复进入前的 override。
// 表现三层：① alpha 压到半透明幽灵态；② 边缘 fresnel 冷色微光（半透明轮廓仍可辨认）；
// ③ 轻微扰动（贴图 UV 流动 + 顶点低频摇曳，读作「形体不实在」）。
// 参数风格与 death_dissolve.gdshader 保持一致（albedo_color / albedo_texture / use_texture）。
//
// ⚠️ alpha_scale 是**倍率**（默认 1.0 = 用调好的 ghost_alpha），不是绝对透明度：
//    最终 ALPHA = base.a × mix(1.0, ghost_alpha, cloak) × alpha_scale。
//    走本 shader 的调用方固定传 1.0；填 0.18 会变成几乎全透明（那是 StandardMaterial3D 兜底路径的写法）。
// 缺 shader 时的兜底由 PawnModelRig 负责（StandardMaterial3D 半透明），本文件不处理。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // 原材质底色（拷贝）
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;                                       // 原材质是否带 albedo 贴图
// 隐身强度：0 = 与常态无异（原材质观感），1 = 完全幽灵态。进入 / 解除时渐变写入。
uniform float cloak : hint_range(0.0, 1.0) = 1.0;
// 边缘微光色（冷色青光：潜行 / 幽灵的读感）
uniform vec3 rim_color : source_color = vec3(0.58, 0.88, 1.0);
// 整体透明度倍率：**倍率**，默认 1.0（= 用下面的 ghost_alpha）；不要填绝对透明度。
uniform float alpha_scale : hint_range(0.0, 1.0) = 1.0;

// ---- 调参项（缺省即推荐值，调用方一般不用动）----
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.24;    // 幽灵态基础不透明度
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;       // 边缘光锐度（越大边缘越细）
uniform float rim_strength : hint_range(0.0, 8.0) = 1.6;    // 边缘光强度（过强会把幽灵糊成一团白）
uniform float wobble_strength : hint_range(0.0, 1.0) = 0.5; // 扰动强度（0 = 完全静止）
uniform float wobble_speed : hint_range(0.0, 8.0) = 2.2;    // 扰动频率

void vertex() {
	// 轻微扰动：沿法线的低频摇曳（幅度 ~6mm 级，只做「不实在」的读感，不动骨架）
	if (wobble_strength > 0.001) {
		float amp = wobble_strength * cloak * 0.012;
		float w = sin(TIME * wobble_speed + VERTEX.y * 26.0 + VERTEX.x * 17.0);
		VERTEX += NORMAL * (w * amp);
	}
}

void fragment() {
	// 扰动后的采样 UV：贴图轻微流动（幽灵边缘的丝丝游动感）
	vec2 uv = UV;
	if (wobble_strength > 0.001) {
		float t = TIME * wobble_speed;
		uv += vec2(sin(t + UV.y * 22.0), cos(t * 0.83 + UV.x * 19.0)) * (0.010 * wobble_strength * cloak);
	}
	// 底色：原材质颜色 × 顶点色（无顶点色的模型 COLOR 恒为白，乘以它安全）
	vec4 base = albedo_color * COLOR;
	if (use_texture) {
		base *= texture(albedo_texture, uv);
	}
	// 幽灵化着色：越隐身越偏冷、越「褪色」，避免半透明后仍像实心塑料
	vec3 ghost_tint = mix(base.rgb, base.rgb * vec3(0.80, 0.92, 1.08), cloak);
	ALBEDO = ghost_tint;
	ROUGHNESS = mix(ROUGHNESS, 0.65, cloak);
	METALLIC = mix(METALLIC, 0.0, cloak);
	// 边缘 fresnel 微光：视线越接近掠射越亮（模型轮廓在隐身态依然可辨认）
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color * fres * rim_strength * cloak;
	// 透明：常态不透明（cloak = 0 时与原材质观感一致），幽灵态压到 ghost_alpha
	ALPHA = clamp(base.a * mix(1.0, ghost_alpha, cloak) * alpha_scale, 0.0, 1.0);
}
