// ============================================================================
// 水体表面着色公共库（湖泊 / 河流 / 瀑布 / 水潭共用一份水域数学）。
// 唯一的几何真相来自 WorldLayout（lake_distance / island_distance / river_distance /
// waterfall_uv / pool_distance），WorldLayout.apply_shader_parameters() 会把全部 uniform
// 写入材质，因此改河道走向只需改 WorldLayout，着色、碰撞、寻路三处自动一致。
//
// v43 视觉迭代（需求③b）：
//   · 湖岸改成三阶谐波自然岸线（双湾 + 半岛），水面按「归一化离岸距离」分深浅色带，
//     浅滩叠沙色与焦散碎斑（透底感）；
//   · 加入菲涅尔天空反射（随昼夜从白昼天蓝渐变到夜空深蓝）与日光/月光镜面高光 + 碎闪；
//   · 湖心小岛：lake_sdf 之外再算 island_sdf，岛内挖掉水面、岛缘出一圈浅滩与白沫；
//   · 瀑布改成多股落水（ws_strand_dx / ws_strand_flow），白沫与扩散涟漪按股累加；
//   · 夜间保留青绿饱和度 + 冷月光泽（不再整体洗成灰蓝）；雨天叠雨点涟漪与压暗。
//
// phase 用法：
//   phase < 1.0  → 地面静水面（湖泊 + 河流 + 水潭，按 region 判定归属）
//   phase > 1.5  → 瀑布立面（倾斜落水帘 + 崖壁湿痕）
// ============================================================================
#ifndef WATER_SURFACE_INC
#define WATER_SURFACE_INC

#include "res://assets/shaders/rain_surface.gdshaderinc"

// ---- 湖泊 ----
uniform vec2 lake_center = vec2(52.0, -38.0);
uniform vec2 lake_radii = vec2(17.0, 12.0);
// 湖岸谐波（与 WorldLayout.LAKE_HARMONICS / LAKE_PHASES 完全同式）
const vec3 LAKE_HARMONIC_A = vec3(0.075, 0.050, 0.022);
const vec3 LAKE_HARMONIC_P = vec3(0.0, 0.0, 0.0);
// ---- 湖心小岛（纯视觉：岛内挖水面，不改寻路 / 碰撞）----
uniform vec2 lake_island_center = vec2(47.0, -36.0);
uniform vec2 lake_island_radii = vec2(3.6, 2.8);
// ---- 河流（折线 + 逐点半宽，xz 打包；最多 6 段 / 7 点）----
uniform vec2 river_pts[7];
uniform float river_w[7];
uniform int river_seg = 0;
// ---- 瀑布 / 水潭 ----
uniform vec2 ws_waterfall_a = vec2(58.0, -72.0);   // 瀑顶唇口中心
uniform vec2 ws_waterfall_b = vec2(56.0, -64.0);   // 水潭中心（主瀑落水点）
uniform float ws_waterfall_len = 8.0;              // 立面长度（米）
uniform float ws_waterfall_width = 9.0;            // 立面宽度（米）
uniform vec2 ws_pool_center = vec2(56.0, -64.0);
uniform vec2 ws_pool_radii = vec2(6.0, 5.0);
uniform float ws_pool_depth = 1.1;
// ---- 多股落水（v43）：各股横向偏移（米）与流量系数；主瀑恒在 dx=0 ----
uniform int ws_strand_count = 1;
uniform float ws_strand_dx[3];
uniform float ws_strand_flow[3];

uniform float map_half = 64.0;
uniform vec4 water_deep = vec4(0.10, 0.39, 0.43, 1.0);
uniform vec4 water_shallow = vec4(0.40, 0.66, 0.59, 1.0);
// v45 调色入口收口到 WaterPalette：贴岸沙绿浅滩 / 白沫 / 岸树倒影三种辅助色也走 uniform，
// 改湖泊 / 河流 / 水潭配色只动 scripts/decor/WaterPalette.gd（shader 只做混色）。
uniform vec4 water_shelf = vec4(0.29, 0.34, 0.24, 1.0);      // 浅滩沙绿（水下透底）
uniform vec4 water_foam = vec4(0.58, 0.72, 0.68, 1.0);       // 岸线白沫（冷白）
uniform vec4 water_reflect = vec4(0.030, 0.085, 0.062, 1.0); // 岸树暗绿倒影
uniform float flow_speed = 0.45;
uniform float night_dim = 0.0;
uniform float rain_amount = 0.0;
uniform float ws_phase = 0.0;
uniform float ws_lake_cut = 0.0;    // >0.5 时丢弃湖面（瀑布立面材质用）
uniform float ws_region_cut = 0.0;  // 0 全部 / 1 仅湖 / 2 仅河流 / 3 仅水潭
// ---- 光照（v43）：由 WaterFeature._process 每帧从 Sun 节点同步，供镜面高光 / 天空反射 ----
uniform vec3 sun_dir = vec3(0.35, 0.86, 0.38);
uniform vec4 sun_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform float sun_strength = 1.0;

float ws_hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ws_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ws_hash21(i), ws_hash21(i + vec2(1, 0)), u.x),
		mix(ws_hash21(i + vec2(0, 1)), ws_hash21(i + vec2(1, 1)), u.x), u.y);
}
// 三倍频噪声：岸线白沫 / 焦散的有机形状（比单层 hash 更不像方格）。
float ws_fbm(vec2 p) {
	return ws_noise(p) * 0.55 + ws_noise(p * 2.13 + vec2(1.7, 9.2)) * 0.30
		+ ws_noise(p * 4.31 - vec2(3.1, 5.7)) * 0.15;
}

// 多层正弦湖岸（与 WorldLayout.lake_distance 完全同式）
float lake_sdf(vec2 p) {
	vec2 q = (p - lake_center) / lake_radii;
	float a = atan(q.y, q.x);
	return length(q) + dot(LAKE_HARMONIC_A, sin(vec3(a * 3.0, a * 7.0, a * 11.0) + LAKE_HARMONIC_P));
}

// 湖心小岛边缘（与 WorldLayout.island_distance 同式；< 1 = 岛上）
float island_sdf(vec2 p) {
	vec2 q = (p - lake_island_center) / max(lake_island_radii, vec2(0.01));
	float a = atan(q.y, q.x);
	return length(q) + 0.10 * sin(a * 3.0 + 1.1) + 0.06 * sin(a * 5.0 - 0.4);
}

// 水潭边缘（与 WorldLayout.pool_distance 同式）
float pool_sdf(vec2 p) {
	vec2 q = (p - ws_pool_center) / max(ws_pool_radii, vec2(0.01));
	float a = atan(q.y, q.x);
	return length(q) + 0.05 * sin(a * 4.0);
}

// 点到折线段的距离 + 该处半宽（返回 vec2(距离, 半宽)）
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

// 瀑布立面参数化：u 横向 0..1（沿 A→B 的垂线），v 纵向 0..1（瀑顶 0 → 落水点 1），
// outside 返回 1.0 表示不在立面范围内。立面沿 A→B 方向倾斜（不是纯竖直板）。
vec3 waterfall_uv(vec2 p) {
	vec2 axis = normalize(ws_waterfall_b - ws_waterfall_a);
	vec2 side = vec2(-axis.y, axis.x);
	float along = dot(p - ws_waterfall_a, axis);
	float lat = dot(p - ws_waterfall_a, side);
	float outside = 0.0;
	if (along < -0.25 || along > ws_waterfall_len + 0.25) { outside = 1.0; }
	if (abs(lat) > ws_waterfall_width * 0.5) { outside = 1.0; }
	return vec3(lat / max(ws_waterfall_width, 0.01) + 0.5, along / max(ws_waterfall_len, 0.01), outside);
}

// 河流局部流向（供法线扰动用；与 river_sdf 同折线）
vec2 river_flow_dir(vec2 p) {
	vec2 dir = vec2(0.0, 1.0);
	vec2 rv = river_sdf(p);
	for (int i = 0; i < 6; i++) {
		if (i >= river_seg) { break; }
		vec2 a = river_pts[i];
		vec2 b = river_pts[i + 1];
		vec2 ab = b - a;
		float tt = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		if (distance(p, a + ab * tt) < rv.x + 0.02) { dir = normalize(ab); }
	}
	return vec2(-dir.y, dir.x);
}

// 天空反射色（白昼天蓝 → 黄昏暖灰 → 夜空墨蓝），夜间保持蓝绿饱和度不发灰。
// v45：昼夜差异拉大（白昼更饱和的青蓝天、黄昏带暖色、夜晚压到墨蓝），天空反射本身只按
// 菲涅尔叠加（见 water_ground.gdshader），不再用固定比例给整片湖提亮。
vec3 ws_sky_color(float night) {
	vec3 day = vec3(0.30, 0.47, 0.60);
	vec3 dusk = vec3(0.56, 0.44, 0.36);
	vec3 night_sky = vec3(0.032, 0.068, 0.130);
	vec3 col = mix(day, dusk, smoothstep(0.22, 0.72, night) * (1.0 - smoothstep(0.72, 1.0, night)));
	return mix(col, night_sky, smoothstep(0.50, 1.0, night));
}

// 日光 / 月光镜面高光 + 碎闪：wn / vw 是世界空间法线与「片元→相机」方向。
// v45：镜面高光收成一条窄带（pow 指数高）+ 细小碎闪（两档噪声门限），宽晕只留极弱一层；
// 碎闪由波纹法线驱动，所以日光路径会跟着波纹起伏、而不是糊成一层白纱。
vec3 ws_sun_glint(vec2 p, vec3 wn, vec3 vw, float night) {
	vec3 r = reflect(-vw, wn);
	vec3 light_dir = normalize(sun_dir);
	float facing = max(dot(r, light_dir), 0.0);
	float core = pow(facing, 260.0);              // 窄镜面带
	float halo = pow(facing, 30.0) * 0.018;       // 很弱的宽晕（避免完全平 = 塑料感）
	float sparkle = ws_fbm(vec2(p.x * 2.2 + TIME * 0.31, p.y * 2.9 - TIME * 0.23));
	float fine = ws_noise(vec2(p.x * 5.6 - TIME * 0.55, p.y * 4.2 + TIME * 0.44));
	float flash = smoothstep(0.54, 0.92, sparkle * 0.62 + fine * 0.48);
	float spec = core * (0.10 + 1.35 * flash) + halo * (0.35 + 0.65 * flash);
	vec3 tint = mix(sun_color.rgb, ws_sky_color(night) * 1.5, night * 0.60);
	float energy = sun_strength * (0.50 - night * 0.30);
	return tint * spec * energy;
}

// 焦散碎斑：浅水区（湖岸 / 岛缘 / 河岸）的水底光斑。
float ws_caustics(vec2 p, float time) {
	vec2 q = p * 1.35;
	float a = ws_noise(q + vec2(time * 0.11, time * 0.07));
	float b = ws_noise(q * 1.7 - vec2(time * 0.09, -time * 0.13) + a * 1.4);
	return smoothstep(0.62, 0.92, a * 0.6 + b * 0.65);
}

// 第 i 股落水在潭面的落水点（越界回落到主瀑）。
vec2 ws_strand_point(int i) {
	float dx = 0.0;
	if (i < ws_strand_count && i < 3) { dx = ws_strand_dx[i]; }
	return ws_waterfall_b + vec2(dx, 0.0);
}

// 分段函数：地面静水面（湖泊 ∪ 河流 ∪ 水潭）着色。返回 rgb 与用于法线的坡度。
vec3 ground_water(vec2 p, out vec2 slope) {
	float t = TIME * flow_speed;
	float shore = lake_sdf(p);
	float isl = island_sdf(p);
	vec2 rv = river_sdf(p);
	float pool = pool_sdf(p);

	// 区域剔除（湖面 / 河面 / 潭面拆成不同网格，避免透明面互相遮挡）
	// v43：湖面不再沿河道走廊挖洞——河道网格会盖在湖面上（两张水面都透明，挖洞只会在
	// 河口留一条硬边 / 亮缝）；湖面本来就用 shore > 1.015 剔除湖外区域。
	if (ws_region_cut > 0.5) {
		if (ws_region_cut > 1.5 && ws_region_cut < 2.5 && rv.x > rv.y) { discard; }
		if (ws_region_cut > 2.5 && pool > 1.0) { discard; }
	}
	if (ws_region_cut < 1.5) {
		// v45：剔除线放到 1.035，让水面在湿沙上留 ~0.35m 的交叠软边（河 / 潭同理见 water_ground 的 ALPHA）。
		if (shore > 1.035) { discard; }
		// 湖心小岛：岛内挖掉水面（岛体网格填上）。岛屿只影响观感，不改寻路 / 碰撞。
		if (isl < 1.0) { discard; }
	}

	// 区域标记（湖 / 河 / 潭三张网格用 ws_region_cut 区分；后面多处要用，先算出来）
	float region_lake = 1.0 - step(1.5, ws_region_cut);
	float region_river = step(1.5, ws_region_cut) * (1.0 - step(2.5, ws_region_cut));

	// ---- 河流：沿流向的涟漪 + 可见度（基色要用，先算）----
	float river_m = 0.0;
	float river_flow = 0.0;
	if (rv.x < rv.y + 0.6) {
		float e = smoothstep(rv.y, rv.y - 0.75, rv.x);   // 中心 1 → 岸边 0
		vec2 flow_dir = vec2(0.0, 1.0);
		for (int i = 0; i < 6; i++) {
			if (i >= river_seg) { break; }
			vec2 a = river_pts[i];
			vec2 b = river_pts[i + 1];
			vec2 ab = b - a;
			float tt = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
			if (distance(p, a + ab * tt) < rv.x + 0.02) { flow_dir = normalize(ab); }
		}
		// 沿流向拉伸的噪声 = 流动感（各向异性采样）
		vec2 fp = vec2(dot(p, vec2(-flow_dir.y, flow_dir.x)) * 3.4, dot(p, flow_dir) * 0.85 - t * 1.4);
		float streak = ws_noise(fp) * 0.55 + ws_noise(fp * 2.7 + vec2(1.7, 3.1)) * 0.45;
		river_flow = streak;
		river_m = e;   // 河面可见度：中心 1 → 岸边 0
	}
	// ---- 水潭：多股落水点的环形涟漪（主瀑最强，两侧细流按流量衰减）----
	float pool_m = smoothstep(1.0, 0.86, pool);
	float ring = 0.0;
	float strand_foam = 0.0;
	if (pool_m > 0.0) {
		for (int i = 0; i < 3; i++) {
			if (i >= ws_strand_count) { break; }
			vec2 c = ws_strand_point(i);
			float w = ws_strand_flow[i];
			float rd = distance(p, c);
			float phase = float(i) * 1.7;
			ring += pow(max(0.0, sin(rd * 3.3 - TIME * 2.5 + phase)), 12.0)
				* smoothstep(6.2, 0.5, rd) * (0.45 + w * 0.55);
			// 落水点白沫核：先给水面一层亮芯，白沫网格再叠一层翻涌
			strand_foam += exp(-rd * rd * 0.95) * (0.25 + w * 0.65);
		}
	}

	// ---- 按区域给「基色」：湖 / 河 / 潭 三种水面各算各的底色 ----
	// v43 修：河 / 潭网格在河口处也算 lake_sdf，若直接套湖色会被「浅滩沙色 + 焦散」刷成
	// 一条发白的带子（截图里像一块浮在湖上的灰纱）。因此湖色只给 region 0/1，
	// 河 / 潭用自己的深浅（river_m / pool_m 是到各自岸线的可见度）。
	//
	// v45 深浅三段式（shore 是归一化离岸距离：1.0 = 岸线，越小越深）：
	//   贴岸 ~1.5m 沙绿浅滩 → 青绿浅水 → 暗蓝绿深水；湖心再压一档读出「深」。
	//   色标全部来自 WaterPalette 写入的 water_deep / water_shallow / water_shelf。
	float depth = clamp((1.0 - shore) / 0.80, 0.0, 1.0);
	// 深度场低频扰动：等深线被噪声打散，不会出现圆规画的椭圆（幅度适中，太大反而糊成墨渍）。
	depth = clamp(depth + (ws_fbm(p * 0.06 + vec2(2.3, 1.7)) - 0.5) * 0.060, 0.0, 1.0);
	// 岛周读作浅水：贴近小岛的水面亮一档，岛脚不会直接掉进深水色（也不出现白环）。
	float island_shallow = smoothstep(1.85, 1.06, isl);
	depth *= 1.0 - island_shallow * 0.32;
	vec3 shelf_c = mix(water_shallow.rgb, water_shelf.rgb, 0.36);
	vec3 lake_col = mix(shelf_c, water_shallow.rgb, smoothstep(0.03, 0.28, depth));
	// 主渐变：贴岸沙绿 → 青绿浅水 → 深青蓝。**深水底色只用 water_deep 的 82%**，
	// 这样从浅到深是平滑的「变暗变蓝」，不会在湖心突然掉成一块黑（Lead v45-lake-final2 反馈）。
	vec3 deep_base = mix(water_shallow.rgb, water_deep.rgb, 0.82);
	lake_col = mix(lake_col, deep_base, smoothstep(0.08, 0.92, depth));
	// 湖心只比深水平台再暗 ~12%（低频噪声打散，不会出现可辨的「黑团」）。
	float basin = smoothstep(0.35, 1.05, depth + (ws_fbm(p * 0.075 + vec2(4.1, 2.9)) - 0.5) * 0.40);
	lake_col *= 1.0 - basin * 0.12;
	// 等深色带：深度频率降低 + 噪声扰动加强（只用来破「均匀渐变」，不放大深浅边界）
	float band = smoothstep(0.36, 0.78, sin(depth * 7.5 + ws_fbm(p * 0.11) * 6.0) * 0.5 + 0.5);
	lake_col *= 0.965 + band * 0.055;
	// 浅滩沙绿：**必须是窄环带**（shore ≈ 0.93~1.03，约 1.0~1.2m），内缘与外缘各一个 smoothstep。
	// 单一反向 smoothstep 会在 shore < 0.95 的整片湖心都返回 1（v45 首版踩过：整湖被沙绿 + 焦散刷白）。
	float shelf_inner = smoothstep(0.932, 0.982, shore);
	float shelf_outer = 1.0 - smoothstep(1.000, 1.058, shore);
	float shelf_ring = shelf_inner * shelf_outer;
	vec3 shelf_sand = mix(water_shelf.rgb, water_shallow.rgb, 0.54);
	lake_col = mix(lake_col, shelf_sand, shelf_ring * 0.26);
	float island_ring = smoothstep(1.26, 1.02, isl);
	lake_col = mix(lake_col, shelf_sand * 0.88, island_ring * 0.20);
	// 焦散：只在贴岸 / 贴岛的极浅水里（透底光斑）
	float caustic = ws_caustics(p, t) * (shelf_ring * 0.55 + island_ring * 0.62);
	lake_col += vec3(0.075, 0.105, 0.080) * caustic * (1.0 - night_dim * 0.82);
	// 河道底色：**中心深（水流下切）→ 贴岸浅**，叠一层沿流向的亮丝（不再引用湖的浅滩沙色）。
	// 方向别写反：river_m = 1 在河心、0 在岸边（v45 二轮截图里河心比岸边亮，整条河发淡）。
	vec3 river_col = mix(water_shallow.rgb * 0.94, water_deep.rgb * 1.12,
		clamp(0.06 + river_m * 0.50, 0.0, 1.0));
	// 水潭底色：主瀑落点附近更亮（翻涌），外圈回到深色
	// v45：潭面更容易被叠加项刷成一片死白（小水面 + 三段落差落水点），基色压深一档、
	// 只留落水点附近一点翻涌亮芯，白沫/水雾交给 falls-fx 的白沫网格。
	vec3 pool_col = mix(water_deep.rgb, water_shallow.rgb * 0.90,
		clamp(0.06 + pool_m * 0.42, 0.0, 1.0));
	vec3 col = lake_col;
	if (ws_region_cut > 1.5 && ws_region_cut < 2.5) {
		col = river_col;
	} else if (ws_region_cut > 2.5) {
		col = pool_col;
	}

	col = mix(col, water_shallow.rgb * 0.95, (1.0 - river_m) * 0.10 * region_river);
	col = mix(col, water_shallow.rgb * 0.92, pool_m * 0.08);
	// 夜间（v45）：乘算保色相（青绿的红/绿/蓝比例不变）→ 不会洗成灰蓝；
	// 再掺一点墨蓝夜色把整体压到「深色水面」，但仍读得出是水而不是黑坑。
	vec3 night_water = col * vec3(0.140, 0.408, 0.332);
	night_water = mix(night_water, vec3(0.013, 0.060, 0.058), 0.22);
	col = mix(col, night_water, night_dim * 0.92);
	// 雨天：压暗（保留涟漪与饱和度，不用灰色去洗）
	col *= 1.0 - rain_amount * 0.16;
	col += river_flow * river_m * 0.06 * (1.0 - night_dim * 0.6);
	// 落水点的环形涟漪保留少量（水面自身的涌动感），但亮芯压到原来的 1/3 以下，
	// 避免小潭面被叠加成一大片白（v45-lake-2 fall-front 截图实锤）。
	col += ring * 0.042 * (1.0 - night_dim * 0.45);
	col += strand_foam * vec3(0.045, 0.075, 0.075);

	// ---- 岸线白沫（湖 / 岛 / 河）：v45 收细 + 断续（不再是一圈均匀白纱）----
	// 每条白沫只给属于它的网格：河 / 潭网格在河口处 shore 也接近 1，若不加区域门控，
	// 湖岸白沫会把整段河口刷成一条发白的「灰纱」（v43 截图实锤）。
	float ang = atan((p - lake_center).y, (p - lake_center).x);
	float foam_n = ws_fbm(p * 0.78 + vec2(t * 0.05, -t * 0.03));
	float lake_foam = smoothstep(0.972, 0.992, shore) * (1.0 - smoothstep(0.996, 1.012, shore));
	lake_foam *= smoothstep(0.46, 0.82, foam_n);                    // 断断续续，不是整圈
	lake_foam *= 0.55 + 0.45 * sin(ang * 23.0 + t * 1.1);           // 角向扇贝（碎）
	lake_foam *= region_lake;
	col = mix(col, water_foam.rgb, clamp(lake_foam, 0.0, 1.0) * 0.34);
	float island_foam = smoothstep(1.075, 1.005, isl) * (1.0 - smoothstep(0.995, 0.965, isl));
	island_foam *= smoothstep(0.42, 0.80, ws_fbm(p * 1.15 - vec2(TIME * 0.07, 0.0)));
	island_foam *= region_lake;
	col = mix(col, water_foam.rgb * 1.04, island_foam * 0.36);
	// 河岸白沫：只在贴岸的窄带（rv.x 从 rv.y-0.55 涨到 rv.y-0.12）出现。
	// 注意方向——rv.x 是「到中心线距离」，河心小、岸线大，故 smoothstep 必须递增，
	// 写成递减会让河心反而最白（v12 修：整条河被刷成雪坡）。
	float bank = smoothstep(rv.y - 0.58, rv.y - 0.20, rv.x) * step(rv.x, rv.y);
	bank *= smoothstep(0.42, 0.80, ws_fbm(p * 1.4 + vec2(0.0, t * 0.9)));
	bank *= (0.55 + 0.45 * sin(p.y * 2.4 + p.x * 1.7 + t * 1.6)) * region_river;
	col = mix(col, water_foam.rgb * 1.03, bank * 0.26 * (1.0 - night_dim * 0.55));

	// ---- 波纹法线（v45）：5 层世界空间波 + 相位域噪声扭曲 ----
	// 大浪（~19m）撑起缓慢起伏，中浪（~8.6m）打散规则感，风纹（~2.9m）给质感，
	// 细纹（~1.4m）只做细碎闪；幅度依次递减，叠起来法线倾角约 3~4°，不会出现塑料镜面。
	// 相位噪声加强（4.6 rad）+ 5 层方向打散：俯视时不再出现成排的规则斜带（Lead 反馈）。
	float warp = ws_fbm(p * 0.038 + vec2(t * 0.015, -t * 0.012)) * 4.6;
	// 低频大浪只在水深处保留，浅滩 / 岸边交给细纹 → 湖心有大尺度起伏、岸边是细碎波纹。
	float big_w = mix(0.30, 1.0, clamp(depth * 2.2, 0.0, 1.0));
	vec2 s = vec2(0.0);
	// 同时累积一个「波峰高度」标量：法线之外再给一层 8~12% 的波峰受光明暗，
	// 否则静水面在漫反射下像一块塑料色块（v45 二轮实拍：湖面读不出波纹）。
	float crest = 0.0;
	// 1) 缓慢大浪 ~20m
	float ph1 = dot(p, vec2(0.80, 0.60)) * 0.31 + TIME * 0.42 + warp;
	s += vec2(0.80, 0.60) * (cos(ph1) * 0.31 * 0.030) * big_w;
	crest += sin(ph1) * 0.030 * big_w;
	// 2) 中浪 ~8.8m
	float ph2 = dot(p, vec2(-0.42, 0.91)) * 0.71 + TIME * 0.78 + warp * 1.7;
	s += vec2(-0.42, 0.91) * (cos(ph2) * 0.71 * 0.017) * big_w;
	crest += sin(ph2) * 0.017 * big_w;
	// 3) 风纹 ~2.9m
	float ph3 = dot(p, vec2(0.68, -0.73)) * 2.17 + TIME * 1.65 + warp * 2.3;
	s += vec2(0.68, -0.73) * (cos(ph3) * 2.17 * 0.0105);
	crest += sin(ph3) * 0.0105;
	// 4) 细纹 ~1.4m
	float ph4 = dot(p, vec2(-0.24, -0.97)) * 4.49 + TIME * 2.90 + warp * 3.1;
	s += vec2(-0.24, -0.97) * (cos(ph4) * 4.49 * 0.0036);
	crest += sin(ph4) * 0.0036;
	// 5) 碎风纹 ~1.06m（方向再打散一层）
	float ph5 = dot(p, vec2(0.94, 0.34)) * 5.90 + TIME * 3.80 + warp * 3.7;
	s += vec2(0.94, 0.34) * (cos(ph5) * 5.90 * 0.0018);
	crest += sin(ph5) * 0.0018;
	// 浅滩 / 岸边波纹收小（水浅扰动弱），避免岸线出现高频闪动与摩尔纹
	s *= (1.0 - shelf_ring * 0.55) * mix(0.78, 1.0, clamp(depth * 3.0, 0.0, 1.0));
	s += river_flow_dir(p) * 0.026 * river_m;
	// 雨天：雨点涟漪（保留 v12 的碰撞环）
	vec3 impact = vec3(0.0);
	if (rain_amount > 0.003) { impact = rain_surface(p * 1.25, TIME, rain_amount); }
	col += vec3(0.10, 0.14, 0.16) * impact.z * rain_amount * (1.0 - night_dim * 0.65);
	s += impact.xy * rain_amount * 0.14;
	// 落水点周围被推开的同心波纹
	for (int i = 0; i < 3; i++) {
		if (i >= ws_strand_count) { break; }
		vec2 d = p - ws_strand_point(i);
		float rr = length(d) + 0.001;
		float wave = sin(rr * 5.0 - TIME * 3.4) * exp(-rr * 0.55) * 0.10;
		s += d / rr * wave;
	}
	// 波峰明暗：细纹为主，整体 ±8~10%；夜间压到一半（夜里不该有强日光起伏）
	col *= 1.0 + crest * 1.6 * (1.0 - night_dim * 0.55);
	// 限幅：法线被推到接近水平时掠射会出现整片亮斑（v43 冰面教训），这里硬性限住。
	float sm = length(s);
	if (sm > 0.22) { s *= 0.22 / sm; }
	slope = s;
	return col;
}

// 水面反照率是否可见（供地面对着色排除水面区域：河道 / 水潭压暗成湿泥）
float ground_water_mask(vec2 p) {
	vec2 rv = river_sdf(p);
	float m = smoothstep(rv.y + 0.9, rv.y - 0.2, rv.x);
	m = max(m, smoothstep(1.18, 0.9, pool_sdf(p)));
	return m;
}

#endif
