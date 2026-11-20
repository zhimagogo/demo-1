shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform int connections = 0;
uniform vec4 road_tint : source_color = vec4(1.0);
varying vec3 world_pos;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - ab * clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0));
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p);
	if ((connections & 1) != 0) { d = min(d, segment_distance(p, vec2(0.0), vec2(0, -0.55))); }
	if ((connections & 2) != 0) { d = min(d, segment_distance(p, vec2(0.0), vec2(0.55, 0))); }
	if ((connections & 4) != 0) { d = min(d, segment_distance(p, vec2(0.0), vec2(0, 0.55))); }
	if ((connections & 8) != 0) { d = min(d, segment_distance(p, vec2(0.0), vec2(-0.55, 0))); }
	// 世界坐标噪声使相邻格接缝连续，草土交界略有起伏。
	float grain = noise(world_pos.xz * 16.0);
	float edge = 0.405 + (noise(world_pos.xz * 7.0) - 0.5) * 0.045;
	if (d > edge) { discard; }
	float rim = smoothstep(edge - 0.045, edge, d);
	vec3 soil = mix(vec3(0.48, 0.33, 0.19), vec3(0.68, 0.51, 0.31), grain);
	soil = mix(soil, vec3(0.35, 0.31, 0.16), rim * 0.5);
	float pebbles = step(0.97, hash21(floor(world_pos.xz * 25.0)));
	// 土色常量按 sRGB 配色，转换到线性空间，避免日光下泛成亮白砂石。
	ALBEDO = pow(mix(soil, vec3(0.67, 0.61, 0.47), pebbles * 0.55), vec3(2.2)) * road_tint.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	ALPHA = road_tint.a;
}
