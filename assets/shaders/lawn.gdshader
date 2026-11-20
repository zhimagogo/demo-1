shader_type spatial;
// 实体弯叶 + 不透明深度写入，避免密草 alpha overdraw；16m MultiMesh 分块剔除。
render_mode cull_disabled, depth_draw_opaque, world_vertex_coords;
#include "res://assets/shaders/decor_dissolve.gdshaderinc"

uniform vec4 color_bottom : source_color = vec4(0.085, 0.22, 0.055, 1.0);
uniform vec4 color_top : source_color = vec4(0.34, 0.49, 0.125, 1.0);
uniform vec4 ground_color_a : source_color = vec4(0.22, 0.34, 0.105, 1.0);
uniform vec4 ground_color_b : source_color = vec4(0.33, 0.45, 0.16, 1.0);
uniform sampler2D lawn_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(-128.0);
uniform vec2 mask_size = vec2(256.0);
uniform bool mask_enabled = false;
uniform float city_half = 26.0;
uniform sampler2D bend_field : filter_linear, repeat_disable;
uniform vec2 bend_origin = vec2(0.0);
uniform float bend_field_size = 32.0;
uniform float bend_radius = 1.4;
uniform vec3 bend_body_position = vec3(0.0);
uniform vec2 bend_body_direction = vec2(0.0, -1.0);
uniform bool bend_body_active = false;
uniform bool bend_enabled = false;
varying float blade_pressure;
varying vec3 root_color;
varying vec3 tip_color;
varying vec3 root_world;
varying float blade_height;

float turf_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float turf_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(turf_hash(i), turf_hash(i + vec2(1, 0)), u.x),
		mix(turf_hash(i + vec2(0, 1)), turf_hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	root_world = MODEL_MATRIX[3].xyz;
	blade_height = UV.y;
	// v47：逐叶世界根（UV2 保存叶片根部），用于弯曲与「逐叶塌缩」消散。
	vec3 leaf_root_world = (MODEL_MATRIX * vec4(UV2.x, 0.0, UV2.y, 1.0)).xyz;
	float dist = distance(root_world, CAMERA_POSITION_WORLD);
	// 远处逐叶缩回根部，并略加宽余下叶片补覆盖；不走透明渐隐。
	float lod = smoothstep(36.0, 78.0, dist);
	float keep = 1.0 - smoothstep(1.0 - lod * 0.58 - 0.07, 1.0 - lod * 0.58, COLOR.r);
	float coverage = 1.0;
	if (mask_enabled) {
		coverage = 1.0 - textureLod(lawn_mask, (root_world.xz - mask_origin) / mask_size, 0.0).r;
	}
	vec3 delta = VERTEX - root_world;
	delta.xz *= 1.0 + lod * 0.28;
	float mesh_visibility = keep * coverage * (1.0 - smoothstep(96.0, 110.0, dist));
	VERTEX = root_world + delta * mesh_visibility;
	float town = 1.0 - smoothstep(city_half - 1.0, city_half + 1.0, max(abs(root_world.x), abs(root_world.z)));
	VERTEX.y = root_world.y + (VERTEX.y - root_world.y) * mix(1.0, 0.86, town);
	// 两层世界空间行波：根部固定，只弯叶尖；没有逐顶点 Worley 九邻域或矩阵求逆。
	float wave = sin(dot(root_world.xz, vec2(0.18, 0.12)) - TIME * 1.45);
	float ripple = sin(dot(root_world.xz, vec2(-0.43, 0.30)) - TIME * 2.1);
	VERTEX.xz += vec2(0.8, 0.6) * (0.036 + wave * 0.028 + ripple * 0.012) * UV.y * UV.y * keep * coverage;
	NORMAL = vec3(0.0, 1.0, 0.0);
	float broad = turf_noise(root_world.xz * 0.10) * 0.65 + turf_noise(root_world.xz * 0.27) * 0.35;
	// 大块冷暖色带 + 低对比实例变化；黄绿叶冠覆盖住深绿根部，不靠黑根制造厚度。
	float patch = smoothstep(0.2, 0.8, broad);
	vec3 undergrass = mix(ground_color_a.rgb, ground_color_b.rgb, patch);
	float variation = mix(0.94, 1.06, COLOR.g) * mix(0.92, 1.04, patch);
	root_color = mix(undergrass, color_bottom.rgb, 0.78) * variation;
	tip_color = mix(color_top.rgb, undergrass, 0.22) * variation;
	// 先按草簇做 32m 粗筛；远离交互场的绝大多数顶点不读贴图，也不计算弯曲。
	blade_pressure = 0.0;
	vec2 field_center = bend_origin + vec2(bend_field_size * 0.5);
	if (bend_enabled && all(lessThan(abs(root_world.xz - field_center), vec2(bend_field_size * 0.5 + 0.6)))) {
		// UV2 保存每片叶的根部：只弯叶身，根部固定。
		vec3 field = vec3(0.0);
		vec2 field_uv = (leaf_root_world.xz - bend_origin) / bend_field_size;
		if (all(greaterThanEqual(field_uv, vec2(0.0))) && all(lessThanEqual(field_uv, vec2(1.0)))) {
			vec3 encoded = textureLod(bend_field, field_uv, 0.0).rgb;
			field = vec3((encoded.rg * 2.0 - 1.0) * step(0.012, encoded.b), encoded.b);
		}
		if (bend_body_active && all(lessThan(abs(leaf_root_world.xz - bend_body_position.xz), vec2(bend_radius)))) {
			vec2 away = leaf_root_world.xz - bend_body_position.xz;
			float foot_distance = length(away);
			float pressure = 1.0 - smoothstep(bend_radius * 0.16, bend_radius, foot_distance);
			if (pressure > field.b) {
				vec2 side = vec2(-bend_body_direction.y, bend_body_direction.x);
				float split = dot(away, side);
				vec2 direction = normalize(away / max(foot_distance, 0.01) * 0.55 + side * (split / sqrt(split * split + 0.035)) * 0.85 + bend_body_direction * 0.16);
				field = vec3(direction * pressure, pressure);
			}
		}
		blade_pressure = field.b;
		if (blade_pressure > 0.001) {
			vec3 blade_root = root_world + (leaf_root_world - root_world) * mesh_visibility;
			VERTEX.y = blade_root.y + (VERTEX.y - blade_root.y) * mix(1.0, 0.18, blade_pressure);
			VERTEX.xz += field.rg * 0.68 * UV.y * UV.y * mesh_visibility;
		}
	}
	// 镜头进入草层时仍使用共享消隐参数；树木、岩石与高草的半球消散保持原逻辑。
	// v47 性能：本材质不再逐片元 discard（discard 会关闭 early-Z，实测草坪 7.3ms → 4.0ms）。
	// 改为逐叶顶点塌缩：用叶片世界根的 hash 与消散量比较，被消散的叶片收进根部，
	// 三角形退化为零面积而不再光栅化；边缘叶再按接近阈值缩小，得到「拨开草丛」的柔边。
	float dissolve = (1.0 - smoothstep(0.1, max(camera_dissolve_radius, 0.11), distance(root_world, camera_dissolve_pos))) * hero_dissolve_strength;
	if (dissolve > 0.002) {
		float leaf_noise = fract(sin(dot(leaf_root_world.xz, vec2(127.1, 311.7))) * 43758.5453);
		float edge = 1.0 - dissolve;
		if (leaf_noise > edge) {
			VERTEX = leaf_root_world;
		} else {
			float shrink = smoothstep(0.0, 0.25, edge - leaf_noise);
			VERTEX = mix(leaf_root_world, VERTEX, 0.55 + 0.45 * shrink);
		}
	}
}

void fragment() {
	// 平滑向上法线使整片草坪连续受光，避免背面翻转导致黑白碎片。
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = mix(root_color, tip_color, smoothstep(0.08, 0.94, blade_height)) * mix(1.0, 0.88, blade_pressure);
	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
}
