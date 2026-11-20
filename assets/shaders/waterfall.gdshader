shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
// 落水帘（v45）：多股落水 + 主瀑前后叠的薄水膜共用一份 shader，逐层参数走顶点色四通道：
//   COLOR.r = 该股明亮度（主瀑 1.0 / 两侧细流 0.7~0.86，v43 契约沿用）
//   COLOR.g = 该层流速倍率（前层 > 1 → 水丝跑得更快，和主帘形成视差）
//   COLOR.b = 该层整体不透明度（薄水膜 0.30~0.55）
//   COLOR.a = 该层明暗（后层 < 1 → 压暗，透出前后层次）
// depth_draw_never：多层半透明水膜要能互相叠着看见（写深度会把后层整片裁掉）。
// specular_disabled：大角度斜面上太阳镜面会把整片帘子洗白，亮度改由反照率/自发光控制。
// 底部翻涌白沫的自发光压低、夜里只留冷月青，避免夜里整块帘子发白（v45-base 实锤）。
#include "res://assets/shaders/waterfall_surface.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_nrm;
varying float v_bright;
varying float v_flow;
varying float v_opacity;
varying float v_shade;

void vertex() {
	// 小幅纵向摆动（水膜随流轻颤），不改变落水点和溢流口位置。
	VERTEX.y += sin(UV.y * 22.0 - TIME * 4.8 + UV.x * 15.0) * 0.018 * sin(UV.y * 3.14159);
	v_bright = clamp(COLOR.r, 0.30, 1.0);
	v_flow = clamp(COLOR.g, 0.30, 2.0);
	v_opacity = clamp(COLOR.b, 0.0, 1.0);
	v_shade = clamp(COLOR.a, 0.20, 1.50);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 slope;
	float alpha;
	vec3 col = waterfall_surface(world_pos.xz, UV.y, UV.x - 0.5,
		v_bright, v_flow, v_opacity, v_shade, slope, alpha);
	// 立面上的「水膜高光」：朝向太阳的一面亮一点（夜里交给月光色，且层越靠后越弱）
	vec3 wn = normalize(world_nrm + vec3(slope.x, 0.0, slope.y));
	float facing = clamp(dot(wn, normalize(sun_dir)), 0.0, 1.0);
	col += sun_color.rgb * facing * 0.035 * (1.0 - night_dim * 0.65) * v_shade;
	ALBEDO = col;
	ALPHA = alpha;
	// 底部白沫自发光：只留很轻的一点，夜里读得出落水点但不泛白
	float plunge = smoothstep(0.80, 1.0, UV.y);
	EMISSION = col * (0.020 + plunge * 0.060) * (1.0 - night_dim * 0.82)
		+ vec3(0.008, 0.022, 0.036) * plunge * night_dim;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 0.40;
	METALLIC = 0.0;
	SPECULAR = 0.28;
}
