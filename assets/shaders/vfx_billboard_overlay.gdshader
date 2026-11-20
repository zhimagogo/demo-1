shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, depth_test_disabled;

// ============================================================================
// 命中公告牌特效（穿透变体）：与 vfx_billboard.gdshader 完全同款，唯一区别是
// 关闭深度测试——EffectDef.no_depth_test = true 的特效（冲击环 / 枪口闪光 /
// 施法微光 / 暴击星芒 / 升级金环）用它，人群里也看得见（「人堆里不丢反馈」）。
// 普通特效仍用 vfx_billboard.gdshader（保留遮挡关系，避免全屏透视一片乱）。
// ============================================================================

uniform vec4 vfx_color : source_color = vec4(1.0, 0.8, 0.45, 1.0);
uniform sampler2D vfx_texture : hint_default_white, filter_linear, repeat_disable;
uniform float ring_amount = 0.0;      // 0 = 光斑，1 = 环带
uniform float softness = 0.55;        // 边缘柔化
uniform float thickness = 0.30;       // 环带宽度（ring_amount = 1 时生效）
uniform float strength = 1.0;         // 亮度增益
uniform float fade_in_end = 0.12;
uniform float fade_out_start = 0.45;
uniform float spin = 0.0;             // 贴图随 progress 旋转的弧度总数（十字星/闪光的转动感；环对称无感）
uniform float ring_fill : hint_range(0.0, 1.0) = 0.35; // 空心环内侧的柔光填充（环不再是一根孤线）

instance uniform float progress : hint_range(0.0, 1.0) = 0.3;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
	// 公告牌：面片永远正对相机；节点 scale 决定世界尺寸
	vec3 anchor = MODEL_MATRIX[3].xyz;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	float size = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	mat4 world = mat4(vec4(right * size, 0.0), vec4(up * size, 0.0),
		vec4(normalize(cross(right, up)) * size, 0.0), vec4(anchor, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
}

void fragment() {
	// 贴图旋转：绕中心随生命周期转过 spin 弧度（星芒 / 闪光会转，环带因对称无感）
	vec2 uv = v_uv;
	if (abs(spin) > 0.0001) {
		float ang = progress * spin;
		float ca = cos(ang);
		float sa = sin(ang);
		uv = mat2(vec2(ca, -sa), vec2(sa, ca)) * (v_uv - vec2(0.5)) + vec2(0.5);
	}
	float d = length(uv - vec2(0.5)) * 2.0;                       // 0 中心 → 1 边缘
	float disc = 1.0 - smoothstep(1.0 - softness, 1.0, d);        // 圆盘柔边
	float ring = smoothstep(1.0 - thickness - 0.18, 1.0 - thickness, d)
		* (1.0 - smoothstep(1.0 - 0.18, 1.0, d));                 // 空心环带
	// 内侧柔光填充：环心到环带的一段渐弱辉光，让冲击环更有「气浪」体积感
	ring += (1.0 - smoothstep(0.0, 1.0 - thickness, d)) * ring_fill;
	float mask = mix(disc, ring, clamp(ring_amount, 0.0, 1.0));
	float tex = texture(vfx_texture, uv).a;
	float fade = clamp(progress / max(fade_in_end, 0.001), 0.0, 1.0)
		* (1.0 - smoothstep(fade_out_start, 1.0, progress));
	ALBEDO = vfx_color.rgb * (0.75 + 0.9 * tex) * (1.0 + strength * 0.35);
	ALPHA = clamp(mask * tex * fade * strength, 0.0, 1.0);
}
