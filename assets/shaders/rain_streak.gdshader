shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled;

// Same world-space direction as the emitter; orthographic cameras share one view basis.
uniform vec4 tint : source_color = vec4(0.72, 0.78, 0.84, 0.40);
uniform vec3 fall_direction = vec3(-0.22, -1.0, -0.12);
uniform float taper = 0.22;
varying vec4 particle_color;
varying float distance_fade;
varying float world_height;

void vertex() {
	vec3 anchor = MODEL_MATRIX[3].xyz;
	vec3 up = -normalize(fall_direction);
	vec3 right = normalize(cross(up, INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(right, up));
	float size = length(MODEL_MATRIX[1].xyz);
	mat4 world = mat4(vec4(right * size, 0.0), vec4(up * size, 0.0),
		vec4(forward * size, 0.0), vec4(anchor, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	world_height = (world * vec4(VERTEX, 1.0)).y;
	particle_color = COLOR;
	float depth = -(VIEW_MATRIX * vec4(anchor, 1.0)).z;
	distance_fade = 1.0 - smoothstep(45.0, 100.0, depth) * 0.65;
}
void fragment() {
	float ends = smoothstep(0.0, taper, UV.y) * (1.0 - smoothstep(0.70, 1.0, UV.y));
	float edge = 1.0 - smoothstep(0.12, 0.5, abs(UV.x - 0.5));
	// Clip the streak at the actual ground instead of letting its tail pass through.
	float contact = smoothstep(0.015, 0.18, world_height);
	ALBEDO = tint.rgb * particle_color.rgb;
	ALPHA = tint.a * ends * edge * particle_color.a * distance_fade * contact;
}
