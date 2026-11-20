// One expanding impact per staggered cell cycle. Returned xy is a world XZ slope,
// z is the soft crest. Adjacent cells are sampled so rings never get cut at tile edges.
vec3 rain_surface(vec2 p, float time, float strength) {
	float pixel_width = max(length(dFdx(p)), length(dFdy(p)));
	vec2 cell = floor(p);
	vec3 result = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = cell + vec2(float(x), float(y));
			float seed = fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
			float clock = time * 1.3 + seed * 6.0;
			float cycle = floor(clock);
			float age = fract(clock);
			float choice = fract(sin(seed * 91.7 + cycle * 17.3) * 18371.3);
			vec2 center = id + vec2(0.2 + 0.6 * seed, 0.2 + 0.6 * choice);
			vec2 delta = p - center;
			float dist = length(delta);
			float radius = 0.035 + age * 0.38;
			float width = max(0.022, pixel_width * 0.65);
			float ring = exp(-pow((dist - radius) / width, 2.0));
			float life = smoothstep(0.0, 0.08, age) * pow(1.0 - age, 2.0);
			float active = smoothstep(choice, choice + 0.08, strength);
			float crest = ring * life * active;
			result.xy += delta / max(dist, 0.001) * crest * (dist - radius) / width;
			result.z += crest;
		}
	}
	return result;
}
