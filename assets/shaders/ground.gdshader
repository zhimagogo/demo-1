shader_type spatial;
render_mode depth_draw_opaque, cull_back;

#include "res://assets/shaders/rain_surface.gdshaderinc"
varying vec3 world_pos;
uniform float rain_amount = 0.0;
uniform vec2 lake_center = vec2(37.0, -28.0);
uniform vec2 lake_radii = vec2(15.0, 11.0);
uniform float map_half = 128.0;   // v40：可玩边界 256×256 米
uniform float city_half = 20.0;   // 城内道路由玩家铺设，城外保留探索道路
uniform vec4 albedo_grass_a : source_color = vec4(0.22, 0.34, 0.105, 1.0);
uniform vec4 albedo_grass_b : source_color = vec4(0.33, 0.45, 0.16, 1.0);
uniform vec4 albedo_dirt : source_color = vec4(0.67, 0.57, 0.39, 1.0);
uniform float wetness = 0.0;      // 雨天湿地：整体压暗 + 反光（roughness 下降）
uniform float cloud_amount = 1.0; // 云影强度（多云 / 雨天加浓）
// ---- v12 水系：河床 / 潭底压暗（uniform 名与 WorldLayout.apply_shader_parameters 对齐）----
// 河道 / 水潭不真的挖地形（世界是 y=0 平地），靠这里把水下与河岸着成湿泥 / 卵石滩，
// 与水面网格（WorldScenery → WaterFeature）读同一份折线，改河道只需改 WorldLayout。
uniform vec2 river_pts[7];
uniform float river_w[7];
uniform int river_seg = 0;
uniform vec2 ws_pool_center = vec2(44.0, -45.0);
uniform vec2 ws_pool_radii = vec2(5.2, 4.4);
uniform float water_bed_strength = 1.0;
// ---- v40 主题区域染色（WorldLayout.apply_shader_parameters 写入；未用槽位 strength = 0）----
// 六个区域的草地目标色 / 影响半径 / 染色强度全部来自 WorldRegions（地面 shader 只做混色）。
uniform vec2 region_center[8];
uniform float region_radius[8];
uniform vec4 region_color[8] : source_color;
uniform float region_strength[8];
// v40.1：区域地标的「夯土地皮」中心点（道具群脚下压成泥地，避免建筑直接坐草上的穿帮）。
uniform vec2 region_landmark[8];
uniform int region_count = 0;
// ---- v40 小径网（WorldLayout.TRAIL_SEGMENTS 的唯一着色副本；trail_seg 截断未用槽位）----
uniform vec2 trail_a[16];
uniform vec2 trail_b[16];
uniform int trail_seg = 0;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float lake_distance(vec2 p) {
	// v43：与 WorldLayout.LAKE_HARMONICS / LAKE_PHASES、water_surface.gdshaderinc 同式的
	// 三阶谐波岸线（双湾 + 半岛）。改振幅 / 相位时三处一起改。
	vec2 q = (p - lake_center) / lake_radii;
	float a = atan(q.y, q.x);
	return length(q) + dot(vec3(0.075, 0.050, 0.022), sin(vec3(a * 3.0, a * 7.0, a * 11.0) + vec3(0.0, 0.0, 0.0)));
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
	float t = clamp(dot(p - a, b - a) / dot(b - a, b - a), 0.0, 1.0);
	return length(p - mix(a, b, t));
}
// 小径网距离：与 WorldLayout.trail_distance 同式（折线 → 最近点距离）。
// v40 起不再硬编码折线，改读 trail_a / trail_b / trail_seg（旧地标小径 + 探索小径共 14 段）。
float trails(vec2 p) {
	float d = 1e6;
	for (int i = 0; i < 16; i++) {
		if (i >= trail_seg) { break; }
		d = min(d, segment_distance(p, trail_a[i], trail_b[i]));
	}
	return d;
}
float roads(vec2 p) {
	float bend_x = sin(p.y * 0.065) * smoothstep(18.0, 36.0, abs(p.y)) * 5.0;
	float bend_z = sin(p.x * 0.07) * smoothstep(18.0, 36.0, abs(p.x)) * 4.0;
	return min(min(abs(p.x - bend_x), abs(p.y - bend_z)), trails(p) + 0.8);
}
// 点到河道折线的距离与该处半宽（与 WorldLayout.river_distance 同式）
vec2 river_sdf(vec2 p) {
	float best_d = 1e6;
	float best_w = 1.2;
	for (int i = 0; i < 6; i++) {
		if (i >= river_seg) { break; }
		vec2 a = river_pts[i];
		vec2 b = river_pts[i + 1];
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		float d = distance(p, a + ab * t);
		float w = mix(river_w[i], river_w[i + 1], t);
		if (d - w < best_d - best_w) { best_d = d; best_w = w; }
	}
	return vec2(best_d, best_w);
}
// 水潭边缘（与 WorldLayout.pool_distance 同式）
float pool_sdf(vec2 p) {
	vec2 q = (p - ws_pool_center) / max(ws_pool_radii, vec2(0.01));
	float a = atan(q.y, q.x);
	return length(q) + 0.05 * sin(a * 4.0);
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz;
	float broad = noise(p * 0.10) * 0.65 + noise(p * 0.27) * 0.35;
	float fine = noise(p * 2.8);
	vec3 grass = mix(albedo_grass_a.rgb, albedo_grass_b.rgb, smoothstep(0.2, 0.8, broad));
	// 东南干燥草甸、北面林地，使不同探索方向有可读的色彩区别。
	float meadow = smoothstep(5.0, 36.0, p.y) * smoothstep(-20.0, 25.0, p.x);
	grass = mix(grass, vec3(0.40, 0.43, 0.18), meadow * 0.08);
	// 短草绒面底层：细纹仅近处出现，远处由像素导数过滤，避免闪烁与砂粒感。
	float detail = 1.0 - smoothstep(0.025, 0.12, max(length(dFdx(p)), length(dFdy(p))));
	float fiber = noise(p * vec2(27.0, 11.0)) * 0.6 + noise(p * vec2(13.0, 39.0)) * 0.4;
	grass *= 1.0 + (fiber - 0.5) * 0.16 * detail;
	// v40 主题区域染色：只叠在草地基色上。后续道路 / 广场 / 岸边 / 河床都基于 col 混色，
	// 因此这些「硬表面」的区域优先级天然高于染色（染色不会盖住路面与水床）。
	// 边缘用低频噪声扰动归一化距离，避免出现生硬的圆环接缝；strength = 0 的槽位不参与。
	for (int i = 0; i < 8; i++) {
		if (i >= region_count) { break; }
		float rr = max(region_radius[i], 0.01);
		float rd = length(p - region_center[i]) / rr;
		rd += (broad - 0.5) * 0.14 + (fine - 0.5) * 0.05;
		float influence = (1.0 - smoothstep(0.45, 1.0, rd)) * region_strength[i];
		grass = mix(grass, region_color[i].rgb, clamp(influence, 0.0, 1.0));
	}
	float road_d = roads(p);
	float path = 1.0 - smoothstep(1.25, 2.55, road_d + (broad - 0.5) * 0.6);
	path *= 1.0 - smoothstep(map_half - 3.0, map_half + 9.0, max(abs(p.x), abs(p.y)));
	path *= smoothstep(city_half, city_half + 1.0, max(abs(p.x), abs(p.y)));
	float plaza = 0.0;
	float clearings = max(1.0 - smoothstep(3.0, 6.5, length(p - vec2(-31, 12))),
		max(1.0 - smoothstep(4.0, 7.0, length(p - vec2(-40, -35))),
		1.0 - smoothstep(4.0, 8.0, length(p - vec2(39, 28)))));
	vec3 dirt = albedo_dirt.rgb * (0.91 + 0.16 * fine);
	vec3 col = mix(grass, dirt, max(max(path, plaza), clearings * 0.86));
	// v40.1 地标夯土地皮：道具群脚下压出泥土空地（噪声扰动边缘，避免标准圆盘穿帮）。
	// 范围 4~9.5m、强度 0.55；道路 / 岸边 / 水床逻辑在其后继续覆盖，不会被压掉。
	for (int i = 0; i < 8; i++) {
		if (i >= region_count) { break; }
		float sd = length(p - region_landmark[i]) + (broad - 0.5) * 2.0 + (fine - 0.5) * 0.6;
		float settle = (1.0 - smoothstep(3.0, 8.0, sd)) * 0.42;
		col = mix(col, albedo_dirt.rgb * 0.72, settle);
	}
	// ---- 湖边岸线（v45）：湿暗沙/湿土窄带 → 不规则窄沙带 → 草 ----
	// 阈值单位是「归一化离岸距离」：湖半径 12~17m，0.01 ≈ 0.12~0.17m。
	// 宽带用低频噪声（broad）扰动、细带用高频噪声（fine）打碎，避免出现用圆规画的沙环。
	// v45 二轮：沙环整体收窄 ~35%（1.00~1.17 ≈ 2m），湿带从水线开始向外压暗，
	// 湿沙颜色再压深一档（原先偏亮偏黄，像沙漠）。
	float ld = lake_distance(p) + (broad - 0.5) * 0.024 + (fine - 0.5) * 0.009;
	float wet_band = 1.0 - smoothstep(1.002, 1.055, ld);     // 水线外 ~0.7m 的湿暗沙/湿土
	float damp_band = 1.0 - smoothstep(1.026, 1.098, ld);    // 湿沙窄带（约 1.1m）
	float dry_band = 1.0 - smoothstep(1.062, 1.150, ld);     // 干沙 → 草（约 1.1m 过渡）
	vec3 wet_shore = mix(vec3(0.092, 0.104, 0.082), vec3(0.150, 0.142, 0.108),
		smoothstep(0.30, 0.80, fine));
	vec3 damp_shore = mix(vec3(0.205, 0.198, 0.148), vec3(0.270, 0.252, 0.188),
		smoothstep(0.20, 0.80, broad));
	vec3 dry_shore = vec3(0.352, 0.322, 0.228);
	col = mix(col, dry_shore, dry_band * 0.38);
	col = mix(col, damp_shore, damp_band * 0.80);
	col = mix(col, wet_shore, wet_band * 0.94);
	// 水线以下（湖床）再压暗一档：水边 alpha 是半透明的，透过水面看不到亮沙。
	float lake_bed = 1.0 - smoothstep(0.900, 0.995, ld);
	col = mix(col, col * vec3(0.34, 0.35, 0.30), lake_bed * 0.85);
	col *= 0.96 + fine * 0.08;
	// 极淡的移动云影，主场景上方不用实体云遮挡角色与建筑。
	float cloud = smoothstep(0.43, 0.74, noise(p * 0.035 + vec2(TIME * 0.007, TIME * 0.003)));
	ALBEDO = col * (1.0 - cloud * 0.13 * cloud_amount);
	// Porous grass stays rough; compacted paths collect connected, irregular pools.
	float soil = max(max(path, plaza), clearings * 0.86);
	float basin = noise(p * 0.48 + vec2(noise(p * 1.1), noise(p * 0.9 + 7.0)) * 0.65);
	float fill = smoothstep(0.28, 0.86, wetness);
	float pud = (1.0 - smoothstep(0.26 + fill * 0.22, 0.32 + fill * 0.22, basin));
	pud *= fill * mix(0.16, 1.0, soil);
	float damp = wetness * (0.75 + fine * 0.25);
	ALBEDO *= 1.0 - damp * mix(0.18, 0.32, soil);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.64, 0.72, 0.78), pud * 0.55);
	ROUGHNESS = mix(mix(0.96, 0.79, damp), 0.24, pud);
	SPECULAR = mix(0.25, 0.38, damp);
	METALLIC = 0.0;
	// ---- v12 河床 / 潭底 / 河岸卵石带（水面网格之外的地面补偿）----
	vec2 _rv = river_sdf(p);
	float bed = smoothstep(_rv.y + 0.9, _rv.y - 0.2, _rv.x);
	bed = max(bed, smoothstep(1.18, 0.90, pool_sdf(p)));
	float bank = smoothstep(_rv.y + 2.3, _rv.y + 0.15, _rv.x) * (1.0 - bed);
	bank = max(bank, smoothstep(1.45, 1.05, pool_sdf(p)) * (1.0 - bed));
	vec3 gravel = vec3(0.50, 0.47, 0.38) * (0.88 + 0.24 * fine);
	ALBEDO = mix(ALBEDO, gravel, bank * 0.26 * water_bed_strength);
	ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.40, 0.38, 0.30), bed * 0.90 * water_bed_strength);
	ROUGHNESS = mix(ROUGHNESS, 0.40, bed * water_bed_strength);
	vec3 impact = vec3(0.0);
	if (rain_amount > 0.003) {
		impact = rain_surface(p * 1.25, TIME, rain_amount);
	}
	// NORMAL is view-space in fragment(); transform the world-space water normal.
	vec2 slope = impact.xy * pud * 0.16;
	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	ALBEDO += vec3(0.12, 0.14, 0.15) * impact.z * pud * rain_amount;
}
