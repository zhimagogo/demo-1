shader_type canvas_item;
// ============================================================================
// v47 后处理分级（Post Grade）
// 作用：在 3D + AgX 之后、HUD 之前做一层极轻的「摄影感」收口——
//   · 冷暗部 / 暖高光的分割调色（split tone）
//   · 极轻的对比与饱和度微调（环境 adjustment 之外的二次收口）
//   · 暗角 + 细颗粒（强度随画质档位，低档可整层关闭）
// 所有强度都由 PostFx.gd 按 RenderQuality 预设写入，默认值保持克制。
// ============================================================================
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float vignette : hint_range(0.0, 1.5) = 0.2;
uniform float grain : hint_range(0.0, 0.08) = 0.01;
uniform float grade : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.03;
uniform float saturation : hint_range(0.0, 2.0) = 1.03;
uniform vec3 lift_color : source_color = vec3(0.0, 0.008, 0.02);
uniform vec3 gain_color : source_color = vec3(1.02, 1.0, 0.975);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));

	// 分割调色：暗部偏冷、高光偏暖，避免整张画面「一层灰绿」。
	col += lift_color * (1.0 - smoothstep(0.0, 0.62, luma)) * grade;
	col *= mix(vec3(1.0), gain_color, smoothstep(0.42, 1.0, luma) * grade);

	// 二次对比 / 饱和度（AgX 已做色调映射，这里只做很小的收口）。
	col = (col - 0.5) * mix(1.0, contrast, grade) + 0.5;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(grey), col, mix(1.0, saturation, grade));

	// 暗角：以屏幕中心为圆心，长宽各自归一化，边缘最多压暗 25%。
	vec2 centered = SCREEN_UV - 0.5;
	float radius = length(centered * vec2(1.12, 1.0));
	float vig = smoothstep(0.92, 0.22, radius);
	col *= mix(1.0, vig, vignette);

	// 细颗粒：高帧率下可读作胶片颗粒，低帧率也不会明显闪烁（幅度极低）。
	float n = hash12(FRAGCOORD.xy + vec2(TIME * 61.7, TIME * 37.3));
	col += (n - 0.5) * grain;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
