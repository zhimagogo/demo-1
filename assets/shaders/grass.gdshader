shader_type spatial;
// ============================================================================
// 塞尔达风格草原 + 清风波纹
// 核心：Worley 程序化噪声做【世界坐标风场】，沿风向滚动采样 → 整片草顺同一
// 方向如波浪流动（清风拂过的灵魂，而非每根草各自乱摆）。单株为五叉三角草簇，
// 摆动是绕底的 pitch/yaw 旋转（顺着风向倾倒）；每株相位由【实例世界位置 hash】
// 随机化——不依赖 MultiMesh 的 INSTANCE_CUSTOM（其 set_instance_custom_data 在
// 当前路径不写入缓冲，已知坑），改用 MODEL_MATRIX[3].xz 做 hash，每株唯一、稳定。
// 每株大小由 MultiMesh transform 缩放提供。颜色底深绿 → 尖黄绿，受风强处更平滑。
// 完全自包含，无需外部纹理。参考：lonegamedev/godot_botw_grass（Worley 风场）。
// ============================================================================
render_mode cull_disabled, blend_mix, depth_draw_opaque;

// 主角周围半球消散（v13）：判定区内的草丛按噪声消散，让出视线（见 decor_dissolve.gdshaderinc）
#include "res://assets/shaders/decor_dissolve.gdshaderinc"

uniform vec4 color_top    : source_color = vec4(0.58, 0.74, 0.30, 1.0);  // 尖端受光黄绿
uniform vec4 color_bottom : source_color = vec4(0.12, 0.28, 0.10, 1.0);  // 根部深绿

uniform vec3 wind_direction = vec3(0.7, 0.0, 0.7);   // 清风方向（归一化前任意值）
uniform float wind_scale = 0.30;     // 风场噪声空间频率（越小→风团越大、波纹越舒展）
uniform float wind_speed = 1.2;      // 风流动速度
uniform float deg_sway_pitch = 30.0; // 俯仰摆动幅度（度）
uniform float deg_sway_yaw = 16.0;   // 偏航扭动幅度（度）
uniform float dissolve_scale = 5.0;  // 消散噪声频率（草簇小 → 频率高）
uniform vec4 dissolve_tint : source_color = vec4(0.72, 0.85, 0.70, 1.0);  // 消散边缘的微光色

varying float v_wind;
varying vec3 v_color;
varying vec3 v_world;
varying float v_dissolve;
varying float v_zone;

const vec3 UP = vec3(0.0, 1.0, 0.0);
const float DEG2RAD = 0.01745329;

// 罗德里格斯旋转矩阵（绕任意轴）
mat3 mat3_axis_angle(float a, vec3 axis) {
	float s = sin(a);
	float c = cos(a);
	float t = 1.0 - c;
	float x = axis.x, y = axis.y, z = axis.z;
	return mat3(
		vec3(t*x*x + c,    t*x*y + s*z, t*x*z - s*y),
		vec3(t*x*y - s*z,  t*y*y + c,   t*y*z + s*x),
		vec3(t*x*z + s*y,  t*y*z - s*x, t*z*z + c)
	);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.32, 231.4)), dot(p, vec2(12.3, 146.3)))) * 231.23);
}

// Worley / 细胞噪声：程序化，无需外部纹理
float worley(vec2 p) {
	float d = 1.0;
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = vec2(float(x), float(y));
			vec2 diff = n + hash2(ip + n) - fp;
			d = min(d, length(diff));
		}
	}
	return d;
}

void vertex() {
	NORMAL = UP;
	vec3 v = VERTEX;

	vec3 wdir = normalize(wind_direction);
	float t = TIME * wind_speed;

	// 世界坐标风场：Worley 噪声沿风向滚动 → 草原上风如云流动（清风波纹）
	vec2 wuv = (MODEL_MATRIX * vec4(v, 1.0)).xz * wind_scale + wdir.xz * t;
	float w = worley(wuv);
	v_wind = w * UV.y;   // UV.y 底 0 → 顶 1，高处摆得多、根部不动

	// 每株随机相位：用实例世界位置 hash（不依赖 INSTANCE_CUSTOM，规避 custom data 写入坑）
	vec2 ipos = MODEL_MATRIX[3].xz;
	float r_phase = hash21(ipos);
	float r_yaw = hash21(ipos + vec2(13.7, 5.3));

	// 顺风向倾倒：摆动轴垂直于风向（草被风推着倒向风去的方向）
	mat3 to_model = inverse(mat3(MODEL_MATRIX));
	vec3 fwd = normalize(to_model * wdir);
	vec3 right = normalize(cross(fwd, UP));

	float pitch = deg_sway_pitch * DEG2RAD * v_wind + (r_phase - 0.5) * 0.5;
	float yaw = deg_sway_yaw * DEG2RAD * sin(t) * v_wind + r_yaw * TAU;

	v = mat3_axis_angle(pitch, right) * mat3_axis_angle(yaw, fwd) * v;
	VERTEX = v;

	v_color = mix(color_bottom.rgb, color_top.rgb, UV.y);

	// 半球消散：草簇很小，直接取草簇中心（MODEL_MATRIX 平移）判定，
	// 整簇一起消散 —— 逐顶点判定会把单株草撕成两半，观感很脏。
	v_world = MODEL_MATRIX[3].xyz;
	v_dissolve = dissolve_cut(v_world, dissolve_scale);
	v_zone = dissolve_zone(v_world);
}

void fragment() {
	if (dissolve_clip(v_world, FRAGCOORD.xy, dissolve_scale, v_dissolve)) {
		discard;
	}
	float side = FRONT_FACING ? 1.0 : -1.0;
	NORMAL = NORMAL * side;   // 双面法线翻转，正反面都受光
	// 消散边缘泛一点亮：让「正在消失的草」有存在感，而不是突然消失
	ALBEDO = mix(v_color, dissolve_tint.rgb, smoothstep(0.35, 1.0, v_dissolve) * 0.55);
	ALPHA = dissolve_alpha(v_dissolve, v_zone);
	METALLIC = 0.0;
	ROUGHNESS = clamp(1.0 - v_wind * 0.9, 0.4, 1.0);   // 受风强的草叶表面更平滑
}
