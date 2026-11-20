shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// ============================================================================
// 挥砍刀光（月牙弧面）：由 VFXManager 用 SurfaceTool 生成的弧形条带网格驱动。
// - 网格局部空间：逻辑前方 = -Z，UV.x 沿弧长、UV.y 由内缘 0 到外缘 1
// - progress 为「逐实例」uniform（instance uniform），生命周期淡入淡出；
//   缺省 0.3 → 即使实例参数未生效也保持可见（回退安全）
// - 结构 = 贴着外缘的窄刀身 + 更细的刃口高光；两端软化（月牙头尾不硬切）
// - 亮度刻意压低：WorldEnvironment 开了辉光，加法混合过亮会糊成一片白
// ============================================================================

uniform vec4 arc_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float edge_soft = 0.32;      // 弧两端的软化比例（0~0.5）
uniform float core_power = 1.6;      // 刃口高光的锐度（越大越细）
uniform float rim_boost = 1.15;      // 刃口高光亮度
uniform float body_boost = 0.70;     // 刀身亮度
uniform float alpha_boost = 0.95;    // 整体不透明度增益
uniform float fade_in_end = 0.16;    // 进度到此值前完全淡入
uniform float fade_out_start = 0.46; // 进度在此值后开始淡出
uniform float core_white : hint_range(0.0, 1.0) = 0.5;  // 刃口白热：高光中心向白偏移的比例
uniform float streaks : hint_range(0.0, 1.0) = 0.30;    // 弧长方向的流动亮纹强度（速度感）

instance uniform float progress : hint_range(0.0, 1.0) = 0.3;

varying float v_u;
varying float v_v;

void vertex() {
	v_u = UV.x;
	v_v = UV.y;
}

void fragment() {
	// 两端软化：月牙头尾自然消失，不出现硬切边
	float ends = smoothstep(0.0, edge_soft, v_u) * (1.0 - smoothstep(1.0 - edge_soft, 1.0, v_u));
	float v = clamp(v_v, 0.0, 1.0);
	// 刀身：贴着外缘的一条窄带（内缘柔和收进去）
	float body = smoothstep(0.36, 0.72, v) * (1.0 - smoothstep(0.86, 1.0, v));
	// 刃口高光：更细更亮的一条线
	float rim = pow(smoothstep(0.58, 0.90, v), core_power) * (1.0 - smoothstep(0.92, 1.0, v));
	// 流动亮纹：沿弧长的细密条纹随 progress 向刃尖流动（金属刀光的速度感；
	// 只作用在刀身与刃口上，不放大两端软化区）
	float streak_band = sin(v_u * 46.0 - progress * 14.0) * 0.5 + 0.5;
	float shimmer = streak_band * streaks * (body * 0.5 + rim);
	// 生命周期：快速淡入 → 保持 → 淡出
	float fade = clamp(progress / max(fade_in_end, 0.001), 0.0, 1.0)
		* (1.0 - smoothstep(fade_out_start, 1.0, progress));
	// 白热刃口：高光中心向白偏移（层次 = 白热刃口 → 主题色刀身 → 透明），避免整条弧一个颜色
	vec3 col = mix(arc_color.rgb, vec3(1.0), rim * core_white);
	ALBEDO = col * (0.18 + body * body_boost + rim * rim_boost + shimmer);
	ALPHA = clamp(ends * (body * 0.75 + rim) * fade * alpha_boost, 0.0, 1.0);
}
