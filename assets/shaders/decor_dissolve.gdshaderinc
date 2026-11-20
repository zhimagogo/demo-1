// ============================================================================
// 装饰物「半球消散」公共库（参考《逃离鸭科夫》主角周围装饰淡出）
//
// 语义：以主角（以及相机）为球心、`*_dissolve_radius` 为半径的**半球判定区**内，
// 装饰物按「离球心越近消散得越彻底」渐隐，到球心附近完全消失；球外完全不受影响。
// 判定区跟着主角移动，所以主角走进草丛 / 树冠 / 石堆时，挡视线的植被自动让开。
//
// 三套 shader（grass / foliage / stone）共用本文件的 uniform 与函数；位置与半径由
// `DecorationDissolveSystem`（scripts/systems/）用**全局 shader 参数**每帧写入，
// 因此新增装饰 shader 只要 `#include` 本文件即可自动获得同一份判定，无需逐个材质赋值。
//
// 【关键设计】消散用「有序抖动 + discard」而不是 blend 半透明：
//   ① 草丛是 65000 株的 MultiMesh，半透明会带来巨量 overdraw 与排序问题；
//   ② discard 不写深度 → 不会把身后的地形/建筑挡掉，视觉上就是「消散」而非「玻璃」；
//   ③ 抖动阈值叠加了逐实例 hash（用世界坐标 hash），消散面呈自然颗粒而非规则点阵。
// 消隐纹理是程序化 3D 值噪声（世界坐标采样）——同一片区域的装饰共享同一噪声场，
// 消散边缘在空间上连续，不会「每株草各散各的」。
// ============================================================================
#ifndef DECOR_DISSOLVE_INC
#define DECOR_DISSOLVE_INC

global uniform vec3 hero_dissolve_pos;        // 判定球心（主角胸口高度）
global uniform vec3 camera_dissolve_pos;      // 副球心（相机），相机贴进植被时同样让开
global uniform float hero_dissolve_radius;    // 外半径：到此为止完全恢复
global uniform float hero_dissolve_inner;     // 内半径：到此为止完全消失
global uniform float hero_dissolve_strength;  // 0 = 整体关闭（可做开关）
global uniform float camera_dissolve_radius;
// 消散表现参数（美术可调，见 tools/dissolve_shot.tscn 的对照组）
global uniform float decor_dissolve_alpha_mix;    // 0 = 纯阈值抖动；1 = 区块内全用半透明
global uniform float decor_dissolve_dither;       // 0 = 不抖动（只靠 alpha）；1 = 标准 4x4 抖动

// ---- 程序化 3D 值噪声（世界坐标采样，全场景共享同一噪声场）----
float decor_hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float decor_noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = decor_hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = decor_hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = decor_hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = decor_hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = decor_hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = decor_hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = decor_hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = decor_hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// ---- 半球判定：0 = 球外完全可见，1 = 球心完全消失 ----
float dissolve_zone(vec3 world_pos) {
	// 主角半球：y 方向按 0.75 压缩 → 判定区略扁（脚边草丛先让开，高处树冠仍会被清）
	vec3 d = world_pos - hero_dissolve_pos;
	float sphere_d = length(vec3(d.x, d.y * 0.75, d.z));
	// 用 smoothstep 的平方做「中段更陡」的落点：物体要么还在、要么已经散掉，
	// 线性淡出会让装饰长时间停在半透「鬼影」状态（v13 首版观感问题）。
	float k = 1.0 - smoothstep(hero_dissolve_inner, hero_dissolve_radius, sphere_d);
	float t_hero = k * k * (3.0 - 2.0 * k);
	// 相机球：相机是另一个遮挡源（相机身后/植被内部也要让开）
	float t_cam = 1.0 - smoothstep(0.0, camera_dissolve_radius, distance(world_pos, camera_dissolve_pos));
	return max(t_hero, t_cam * 0.85) * hero_dissolve_strength;
}

// ---- 消隐阈值：zone 与噪声叠加，得到 0..1 的「消散进度」----
// 噪声占主导（0.62 权重）→ 消散沿噪声块推进，而不是整体均匀变淡；
// scale 用于匹配物体尺度（草 ~5、树按实例缩放归一），保证不同大小物体的消隐块尺寸相近。
float dissolve_cut(vec3 world_pos, float scale) {
	float zone = dissolve_zone(world_pos);
	if (zone <= 0.002) { return 0.0; }
	float n = decor_noise3(world_pos * scale) * 0.66 + decor_noise3(world_pos * scale * 2.7) * 0.34;
	return clamp(zone * 1.62 - n * 0.62, 0.0, 1.0);
}

// ---- 4x4 Bayer 有序抖动（解析式，无需常量数组）----
float decor_bayer4(vec2 pixel) {
	ivec2 p = ivec2(mod(floor(pixel), 4.0));
	int x = p.x, y = p.y;
	int b = ((x & 1) * 8 + (y & 1) * 4 + ((x >> 1) & 1) * 2 + ((y >> 1) & 1)) ;
	return (float(b) + 0.5) / 16.0;
}

// ---- 是否丢弃该片元（返回 true = 已消散）----
// clip_noise 把阈值扰动一点，避免所有草叶用同一块规则点阵看起来像「网格筛子」。
bool dissolve_clip(vec3 world_pos, vec2 pixel_pos, float scale, float amount) {
	if (amount <= 0.003) { return false; }
	if (amount >= 0.997) { return true; }
	float clip_noise = decor_hash13(floor(world_pos * 3.0));
	float threshold = decor_bayer4(pixel_pos + clip_noise * 3.0) * 0.92 + clip_noise * 0.08;
	// decor_dissolve_dither 调低时把阈值拉向 0.5，抖动退化为「整块一起淡」
	float soft = mix(0.5, threshold, clamp(decor_dissolve_dither, 0.0, 1.0));
	return amount > soft;
}

// ---- 消散期的剩余不透明度 ----
// 关键：**直接由 zone 驱动**（不是由 cut）——这样球心一定归零（不会留下半透鬼影），
// 而 cut 只负责「什么时候开始散」。cut 版会让物体在球心附近长期停在 30% 半透，
// 看起来像一层幽灵，而鸭科夫的观感是「散尽」。
float dissolve_alpha(float cut_amount, float zone) {
	if (zone <= 0.002) { return 1.0; }
	float fade = clamp(1.0 - zone, 0.0, 1.0);
	fade = fade * fade;                                  // 近中心更快趋零
	fade = mix(fade, fade * fade, clamp(decor_dissolve_alpha_mix, 0.0, 1.0));
	return clamp(fade, 0.0, 1.0);
}

#endif
