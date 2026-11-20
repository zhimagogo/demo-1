shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// 地面静水面：湖泊 / 河流 / 水潭由 ws_region_cut 拆成独立网格（避免透明面互相遮挡），
// 水面数学全部来自 water_surface.gdshaderinc，与 WorldLayout 的几何定义一一对应。
// v43：菲涅尔天空反射 + 日光 / 月光碎闪（靠 WaterFeature 每帧同步的 sun_dir / sun_color）。
// v45：取消「低粗糙 PBR 天空镜面 + 固定比例 Fresnel 提亮」造成的整片白纱——
//   · ROUGHNESS 抬到 0.55+ / METALLIC 归零 / SPECULAR 压低，引擎侧只剩一层很散的微光；
//   · 天空反射只按施里克菲涅尔叠加进 EMISSION（掠射强、俯视弱，夜间自动变暗）；
//   · 贴岸加一条「岸树暗绿倒影」窄带（随视角增强、用噪声打散成树影团块）；
//   · 水面 alpha 在湿沙上留 ~0.35m 交叠软边，水线不再是硬切。
#include "res://assets/shaders/water_surface.gdshaderinc"

varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_pos.xz;
	vec2 slope;
	vec3 col = ground_water(p, slope);
	// 世界空间法线 / 视线方向：菲涅尔与镜面高光都按世界空间算
	vec3 wn = normalize(vec3(-slope.x, 1.0, -slope.y));
	vec3 vw = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float ndv = clamp(dot(wn, vw), 0.0, 1.0);
	// 施里克近似菲涅尔（水的 F0 ≈ 0.02）：俯视几乎不反天，掠射才明显亮起来。
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 sky = ws_sky_color(night_dim);
	float sky_gain = mix(0.55, 0.34, night_dim);
	vec3 col_emit = sky * fres * sky_gain;
	// 岸树暗绿倒影：只在湖面、贴岸 ~2m 的窄带；掠射视角更强，低频噪声打散成树影团块，
	// 让湖岸不至于是一条干净的亮色边（也压住岸线附近的泛白）。
	float region_lake = 1.0 - step(1.5, ws_region_cut);
	float shore_band = smoothstep(0.845, 0.985, lake_sdf(p)) * region_lake;
	float tree_n = ws_fbm(p * 0.19 + vec2(3.1, 7.7));
	float tree_ref = shore_band * smoothstep(0.34, 0.78, tree_n) * smoothstep(0.10, 0.62, 1.0 - ndv);
	col_emit += water_reflect.rgb * tree_ref * (1.0 - night_dim * 0.45) * 1.1;
	// 日光 / 月光镜面高光 + 碎闪（与波纹法线联动）。潭面（region 3）只留 30%：
	// 小水面 + 三股落水点会让镜面带糊成一整片死白，潭面白沫交给 falls-fx 的白沫网格。
	float region_pool = step(2.5, ws_region_cut);
	vec3 glint = ws_sun_glint(p, wn, vw, night_dim) * (1.0 - region_pool * 0.70);
	col_emit += glint;
	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	// 水面是很大的一片微光面：粗糙度高 + 无金属 + **零介电镜面**——引擎的 PBR 镜面在掠射角
	// 会把整片湖刷成一层白纱（v43「冰面」根因），这里彻底交给手写的 glint + 天空菲涅尔。
	ROUGHNESS = clamp(0.55 + rain_amount * 0.16 + night_dim * 0.10, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// 夜间保底冷青光：夜色里水面不能是一块纯黑（也不洗成灰蓝）——给一点很弱的自发光青绿，
	// 白天不生效（night_dim = 0），量与月光碎闪一起构成「深青色的夜湖」。
	col_emit += vec3(0.008, 0.035, 0.031) * night_dim * (0.55 + 0.45 * ndv);
	EMISSION = col_emit;
	// 静水面：按「离岸距离」淡出，湖岸 / 河岸都能拿到软边
	// （湖岸的软边要比河 / 潭更窄——湖很大，过宽的半透明带会糊成一片沙色）
	float edge = 1.0;
	if (ws_region_cut < 1.5) {
		// 水线软边约 0.45m：水面轻微压到湿沙上（与 ground.gdshader 的湿带交叠）
		edge = 1.0 - smoothstep(0.992, 1.032, lake_sdf(p));
		edge *= smoothstep(0.985, 1.0, island_sdf(p));
	} else if (ws_region_cut < 2.5) {
		vec2 rv = river_sdf(p);
		edge = 1.0 - smoothstep(rv.y - 0.16, rv.y + 0.10, rv.x);
		// 河口：最后 3m 完全淡出到湖面（两张半透明水片叠在一起会泛白成一顶「灰纱」）
		edge *= smoothstep(0.15, 3.2, distance(p, river_pts[river_seg]));
	} else {
		edge = 1.0 - smoothstep(0.955, 1.045, pool_sdf(p));
	}
	ALPHA = clamp(edge, 0.0, 1.0);
}
