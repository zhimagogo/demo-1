# v47 · 渲染与光影质感迭代（含性能优化）

> 日期：2026-11-19　执行：周博峥（Lead）　Godot 4.7.1 / Forward+ / Metal 4 / Apple M4
>
> 目标：在不牺牲帧率的前提下，把画面的「光影质感」提一档——更自然的高光与暗部、更柔和的阴影、
> 更明确的主光/环境光比、夜间的月光与火炬氛围；同时把画质做成玩家可选的档位，并把最贵的渲染项
> 找出真实成本后逐项优化。本文记录技术路线、改动、性能数据与验收命令。

---

## 1. 结论先行

- **画质**：AgX 高动态范围管线 + 软阴影（PCSS）+ SSAO/SSIL + 夜晚体积雾 + 暖色火炬/月光 + 后处理调色；
  画面从「高饱和荧光绿、硬阴影、无空气感」变为「自然层次 + 方向光塑形 + 远景空气透视 + 夜间暖冷对比」。
- **性能**：在 1600×900、同一批固定机位下，中位帧时 **10.0 ~ 15.4 ms（全部机位 < 16.7 ms）**。
  默认 1152×648 窗口实测中位 **14.3 ms / 约 70 fps**；比 v46.2 多开了 SSIL / 体积雾 / 软阴影 / 后处理，
  但通过草坪 early-Z 修复、2-split 阴影与字体链修复把成本压了回来。
- **关键性能发现**：草坪 shader 的逐片元 `discard` 会关闭 early-Z，实测草坪 **7.34 ms → 3.86 ms**，
  1440×900 同机位整帧 **17.15 ms → 13.83 ms**。改为逐叶顶点塌缩后消散观感不变、性能大幅改善。
- **画质分级**：新增 `RenderQuality` autoload 与设置面板「画质档位」（低/中/高/极致），默认「高」。

---

## 2. 技术路线（为什么是这四件事）

### 2.1 先把「光照比」拉开，而不是堆特效

v46.2 的画面问题不是缺特效，而是**均匀**：环境光 0.78、太阳 1.15，主光/环境光比只有约 1.5:1，
再加上高饱和草地 albedo，几乎所有表面都被同一种绿填满。v47 先做：

| 项 | v46.2 | v47 |
| --- | --- | --- |
| 色调映射 | ACES（白点 1.0） | **AgX**（white 6.0 / contrast 1.3） |
| 正午太阳能量 | 1.15 | **2.15**（暖白） |
| 白天环境光能量 | 0.78 | **0.64**（冷色天光） |
| 夜间环境光能量 | 0.72 | **0.48**（月光为主光） |
| 月光补光能量 | 0.75 | **1.0**（夜间），白天 0.10 |
| 曝光 | 固定 | **昼夜自适应**：白天 0.97 / 夜间 1.16 |

AgX 负责把高光滚降得更自然（避免 ACES 下的荧光绿过饱和），主光/环境光比拉到约 3.4:1 后，
体积、投影和材质起伏才真正读得出来。草地/地面 albedo 同时去饱和、压暗（见 §4.2），
把「荧光绿地毯」变成偏橄榄的自然草色。

### 2.2 阴影：从「有阴影」到「有接触感的软阴影」

- 方向光从 4 split / 150m 改为 **2 split / 118m**：俯视角下近中景就够用；同尺寸图集下
  每 split 分辨率翻倍，阴影反而更锐；同时阴影 draw call 大幅下降（城市机位 1917 → 1570）。
- `light_angular_distance = 0.65°` + `RenderingServer.directional_soft_shadow_filter_set_quality(SOFT_LOW)`
  开启 PCSS 半影，树冠/屋檐/单位脚边不再是硬黑边。
- `directional_shadow_fade_start` 低/中/高/极致 = 0.6 / 0.65 / 0.8 / 0.85，远距阴影渐隐而不是硬切。
- `directional_shadow_pancake_size = 20`，避免俯视相机近平面裁掉大物体阴影。
- SSAO 从 radius 1.0 / intensity 0.9 / power 1.2 调到 **1.5 / 1.15 / 1.9**，
  并加 `detail 0.6 / horizon 0.06 / sharpness 0.98 / light_affect 0.35`，让建筑与单位接地。
- 高档起加 **SSIL**（radius 3.0 / intensity 0.9），提供草地与暗部之间的间接反弹。

### 2.3 氛围：空气透视 + 夜间体积光

- 指数雾密度改为白天 0.0011 / 夜间 0.0026，`fog_aerial_perspective = 0.45`、`fog_sky_affect = 0.22`，
  再加高度雾 3.5m / 密度 0.004：远景有空气透视，但不会糊成白幕。
- **体积雾**（高档起）：`volumetric_fog_length = 56`、夜间密度 0.007、白天 0.0006、
  `anisotropy 0.18`、`detail_spread 1.4`、`gi_inject 0.25`；火炬带 `light_volumetric_fog_energy = 4.0`。
- 夜间火炬从 5 盏（城堡角 + 四门）扩到 **9 盏**（+ 城内四角），range 16m / 能量 3.3 / attenuation 1.25；
  配合辉光与体积雾形成暖光池，和月光冷调形成暖冷对比。
- 辉光改为 screen blend、HDR threshold 1.0、bloom 0.12；夜间 intensity 0.50 / 白天 0.22，
  让火炬、窗光、萤火虫有真正的 HDR 溢光。

### 2.4 后处理：一层很轻的「摄影感」收口

`PostFx`（CanvasLayer 0，位于 3D 之后、HUD(CanvasLayer 1) 之前）做四件小事：

- 冷暗部 / 暖高光分割调色（lift/gain）；
- 对比 1.03、饱和 1.03 的二次收口（AgX 之外的微调）；
- 暗角（高档 0.20）与细颗粒（0.01，低档完全关闭）；
- 不拦截输入、不影响 HUD 颜色与清晰度；低档省掉整层（一个全屏 pass 约 0.6ms）。

### 2.5 性能：先测量，再优化

新增两个工具（见 §7）：

- `tools/render_showcase.tscn`：11 个固定机位 / 固定时刻的样张 + 帧时 / draw call / primitives；
- `tools/render_probe.tscn`：同一机位下逐项关闭/替换特性，**每测一项立刻回测基线**以抵消 M4 集显的温热漂移。

实测（1440×900，高档基线 13.83ms）的单项成本：

| 关闭项 | Δms | 说明 |
| --- | ---: | --- |
| 草（MM_grass_*） | **-3.86** | 最大头；early-Z 修复后已从 7.34 降下来 |
| 装饰整体 | -3.89 | 与草重叠 |
| 阴影 | -2.46 | 2 split 后 |
| SSIL | -1.45 | 高档起才有 |
| 软阴影（PCSS） | -1.40 | 硬阴影对比 |
| 3D 缩放 0.87 | -1.31 | 低档用 |
| 体积雾 | -0.66 | 夜间 |
| 后处理 | -0.60 | 低档关闭 |
| SSAO | -0.42 | 保留 |
| MSAA 2× | **+2.91** | 只有极高档开启 |
| 草 LOD 提前（36~78m） | ~-0.1~-0.3 | 与 visibility 84m 低档配套 |

**最关键的修复**：`lawn.gdshader` 原来在片元里调用 `dissolve_clip()` → `discard`，
而 `discard` 会禁用 early-Z，导致 2M+ 草叶的 overdraw 全部着色。v47 改为**逐叶顶点塌缩**：
按叶片世界根的 hash 与消散量比较，被消散的叶片收进根部，三角形退化为零面积而不再光栅化；
边缘叶按接近阈值缩小，保留「拨开草丛」的柔边。实测草坪 7.34→3.86ms，1440×900 整帧 17.15→13.83ms。
`tests/RenderQualityTest` 增加了「草坪 shader 不得出现 `discard;`」的性能契约。

**字体链修复**：原 `UIStyle` 把 `SystemFont` 挂成 fallback；在本机 macOS 环境里 SystemFont 解析为
`ascent=0`，之后每次文本度量都触发 FreeType 错误刷屏（主线程 `process_time` 中位近 30ms，
偶发 17 秒级尖峰）。改为优先使用 `ThemeDB.fallback_font`，只有它也不可用才退回 SystemFont。
实测主界面帧中位 18.06→16.67ms，错误日志归零，HUD 中文正常显示。

---

## 3. 画质分级

`RenderQuality`（autoload，`scripts/autoload/RenderQuality.gd`）提供四档；玩家可在
主菜单 / 游戏内 Esc → 设置 → **画面 → 画质档位** 切换，选择持久化在 `user://settings.cfg` 的 `quality` 键。

| 档位 | 3D 缩放 | AA | SSAO | SSIL | 体积雾 | 后处理 | 阴影 | 草/装饰视距 | 1600×900 城景中位 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| 低 | 0.87 FSR1 | SMAA | 关 | 关 | 关 | 关 | 2 split / 84m / soft very-low / 2048 | 84 / 96m | ≈10.0ms |
| 中 | 1.0 | SMAA | 开 | 关 | 关 | 开 | 2 split / 104m / soft low / 4096 | 96 / 120m | ≈13.2ms |
| 高（默认） | 1.0 | SMAA | 开 | 开 | 开 | 开 | 2 split / 118m / soft low / 4096 | 112 / 140m | ≈15.5ms |
| 极致 | 1.0 | MSAA 2× | 开 | 开 | 开 | 开 | 4 split / 140m / soft medium / 8192 | 140 / 180m | ≈20.8ms |

> 表内数字为同一固定机位 / 时刻（city_day, 1600×900, VSync off）的中位帧时，随机器/温度有 ±0.5ms 波动。
> 低/中档不是「砍画质」：AgX、环境光遮蔽、软阴影、雾与调色都保留；差的只是最贵的可选层。

![quality tiers](../artifacts/render-v47/quality-tiers.png)

`RenderQuality.apply_to_world(world_root)` 负责把开关落到具体节点（Environment / DirectionalLight /
DecorationScatter / PostFx）；`Main._ready()` 末尾延迟调用一次，切档时自动重扫最近一次的世界。
`DayNightCycle` 只写随时刻变化的量（环境光、雾色、曝光、体积雾密度），**不碰特性开关**，
避免两套系统互相覆盖。

---

## 4. 具体改动

### 4.1 环境与光照

- `scenes/main/Main.tscn`
  - `Environment`：AgX、`tonemap_agx_white 6.0`、`tonemap_agx_contrast 1.3`、`exposure 0.97`；
    `adjustment_contrast 1.05`、`adjustment_saturation 1.06`；
    SSAO / SSIL / 雾 / 体积雾 / 辉光参数见 §2；雾高度 3.5m / 密度 0.004。
  - `Sun`：能量 1.9 静态（DayNightCycle 运行时覆盖到 2.15）、`light_angular_distance 0.65`、
    2 split / 118m / split 0.16/0.46、`blend_splits`、`fade_start 0.8`、`pancake 20`。
  - `FillLight`：冷蓝月光补光，夜间能量 1.0。
  - 草地/地面 albedo：`albedo_grass_a (0.22,0.34,0.105)`、`b (0.33,0.45,0.16)`。
- `scripts/systems/DayNightCycle.gd`
  - 日照穹顶改为 **5:00 日出 → 20:00 日落**（开局 6:00 已有约 0.27 日照，不再是黑屏）；
  - 太阳/环境光/月光/天空/雾/辉光/曝光全部重调；新增夜间曝光自适应；
  - 体积雾密度按昼夜写；火炬 9 盏、range 16、能量 3.3、体积能量 4.0。
- `scripts/autoload/RenderQuality.gd`（新）与 `project.godot` autoload 注册。

### 4.2 草与地表

- `assets/shaders/lawn.gdshader`
  - 去掉片元 `discard`，改为逐叶顶点塌缩（性能核心）；
  - 草色去荧光：`color_bottom (0.085,0.22,0.055)`、`color_top (0.34,0.49,0.125)`；
    `variation` 范围放宽到 0.88~1.08，`tip_color` 多混 22% 底层地面色；
  - 远距 LOD 从 48~92m 提前到 **36~78m**，远处叶片更早收拢。
- `assets/shaders/ground.gdshader`：默认草地 albedo 同步压暗去饱和。
- `scripts/decor/DecorationScatter.gd`：新增 `apply_render_quality()` /
  静态 `apply_visibility_ranges()`，按档位收紧草与装饰 MultiMesh 的视距（只收不放）。

### 4.3 后处理

- `scripts/systems/PostFx.gd`（新）+ `assets/shaders/post_grade.gdshader`（新）
  - CanvasLayer 0 + 全屏 ColorRect + screen texture；vignette / grain / split-tone / 二次对比饱和；
  - 由 `RenderQuality` 写入 `vignette / grain / grade`；低档整层隐藏。

### 4.4 UI / 设置 / 字体

- `scripts/ui/GameSettings.gd`：新增 `quality` 键（默认 2=高）、`quality()/set_quality()`、`QUALITY_NAMES`。
- `scripts/ui/SettingsPanel.gd`：新增「画面 → 画质档位」下拉与说明；切换即时应用并持久化；
  「恢复默认」同时把档位恢复到默认高。
- `scripts/ui/UIStyle.gd`：字体 fallback 改 `ThemeDB.fallback_font`，修复 SystemFont 失败导致的
  逐帧 FreeType 错误刷屏；`make_system_font()` 返回类型改为 `Font`（不再限定 SystemFont）。
- `scripts/main/Main.gd`：`_ready()` 末尾调用 `RenderQuality.apply_to_world(world_root)`。
- `scripts/autoload/EventBus.gd`：新增 `render_quality_changed(tier)` 信号。

### 4.5 测试与工具

- `tests/RenderQualityTest.tscn/.gd`（新，CORE）：四档字段完整性、成本单调性、世界应用、
  Viewport AA/缩放、PostFX 层序、GameSettings 持久化、SettingsPanel 联动、草坪无 `discard;` 契约、
  装饰视距。
- `tests/CityScaleTest.gd`：火炬数量 5→9（新增城内四角），验证四门仍在 26m 城沿。
- `tools/render_showcase.tscn/.gd`（新）：11 机位样张 + 帧时；
- `tools/render_probe.tscn/.gd`（新）：消融探针（基线回测抵消漂移）；
- `tools/font_probe.tscn/.gd`（新）：字体链诊断；
- `tools/run_all_tests.sh`：CORE 41→42 套。

---

## 5. 性能数据

### 5.1 样张机位前后对比（1600×900，VSync off）

| 机位 | v46.2 中位 | v47 中位 | Δ | v46.2 p95 | v47 p95 | 阴影 draw calls 前→后 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| city_day | 14.65 | 15.36 | +0.71 | 15.89 | 16.31 | 1917 → 1570 |
| street_day | 9.99 | 11.34 | +1.35 | 10.95 | 13.01 | 997 → 672 |
| gameplay_day | 12.26 | 13.79 | +1.53 | 13.39 | 14.64 | 1374 → 1014 |
| forest_day | 11.62 | 13.67 | +2.05 | 12.78 | 14.88 | 960 → 691 |
| lake_day | 12.14 | 14.21 | +2.07 | 13.42 | 15.20 | 1367 → 1129 |
| waterfall_day | 10.95 | 13.17 | +2.22 | 12.36 | 13.97 | 805 → 693 |
| city_dusk | 14.42 | 14.95 | +0.53 | 15.89 | 16.00 | 1872 → 1429 |
| city_night | 13.22 | 15.26 | +2.04 | 14.34 | 16.30 | 1110 → 1082 |
| gameplay_night | 11.11 | 13.97 | +2.86 | 12.47 | 15.32 | 494 → 436 |

所有机位 < 16.7ms（60fps 预算）；多出的 0.5~2.9ms 换来了 SSIL、体积雾、软阴影、9 盏火炬、
后处理与更高的可视距离。若只看「同特性」对比：草坪 early-Z 修复让 1440×900 同机位
**17.15 → 13.83ms**（-3.3ms），这部分的节省被新特性吃掉了，但整体仍在预算内。

### 5.2 实际窗口（1152×648，Main.tscn）

| 阶段 | 中位帧时 | p95 | 说明 |
| --- | ---: | ---: | --- |
| v46.2 + 原字体链 | 18.06 ms | 20.83 ms | process_time 中位 29.7ms，max 17s |
| 字体 fallback 修复后 | 16.67 ms | 18.52 ms | process_time 中位 25.4ms，max 79ms |
| v47 最终（默认高） | **14.29 ms** | **14.82 ms** | 中位 fps ≈ 70 |

> 最终数据为 `godot_run_with_profiler` 8 秒采样（窗口 1152×648，游戏默认窗口）。
> 1600×900 固定机位数据来自 `tools/render_showcase.tscn`。

### 5.3 画质档位（1600×900 city_day）

| 低 | 中 | 高 | 极致 |
| ---: | ---: | ---: | ---: |
| ≈10.0 ms | ≈13.2 ms | ≈15.5 ms | ≈20.8 ms |

低档在 1600×900 仍有 10ms 余量，适合集显 / 高分辨率；极致档主要成本是 MSAA 2×（约 +2.9ms）
与 4 split 阴影，建议搭配中高档显示器/独显使用。

---

## 6. 视觉对照

完整样张在 `artifacts/render-v47/`（`before/` = v46.2，`after/` = v47；`tier-*/` = 各档位）。

**日景（城堡 / 城市）**

| v46.2 | v47 |
| --- | --- |
| ![before city](../artifacts/render-v47/before/city_day.png) | ![after city](../artifacts/render-v47/after/city_day.png) |

**黄昏**

| v46.2 | v47 |
| --- | --- |
| ![before dusk](../artifacts/render-v47/before/city_dusk.png) | ![after dusk](../artifacts/render-v47/after/city_dusk.png) |

**夜晚**

| v46.2 | v47 |
| --- | --- |
| ![before night](../artifacts/render-v47/before/city_night.png) | ![after night](../artifacts/render-v47/after/city_night.png) |

**湖景**

| v46.2 | v47 |
| --- | --- |
| ![before lake](../artifacts/render-v47/before/lake_day.png) | ![after lake](../artifacts/render-v47/after/lake_day.png) |

**主角脚边（草叶体积 / 拨草 / 软阴影）**

![hero close](../artifacts/render-v47/after/hero_close.png)

---

## 7. 复现与验收

```bash
# 一键样张（11 机位，1600×900，输出 artifacts/render-v47/<label>/）
bash tools/godot_locked.sh --path . tools/render_showcase.tscn -- --label=after

# 指定机位 / 画质档位（low|medium|high|ultra）
bash tools/godot_locked.sh --path . tools/render_showcase.tscn -- --label=low --quality=low --view=city_day

# 消融探针（逐项关特性 + 基线回测）
bash tools/godot_locked.sh --path . tools/render_probe.tscn -- --view=gameplay --samples=50

# 画质分级回归（CORE）
bash tools/godot_locked.sh --headless --path . tests/RenderQualityTest.tscn

# 全量 CORE（42 套）
bash tools/run_all_tests.sh
```

本次已跑通：`RenderQualityTest`（0 failure）、`LawnTest`、`LawnInteractionTest`、`DissolveZoneTest`、
`CityScaleTest`、`SceneValidation`、`WeatherRainTest`、`MenuFlowTest`、`UiIconTest`，以及 **全量 CORE 42 套 /
0 failed**（日志 `${TMPDIR}/demo1-tests/`；样张见 `artifacts/render-v47/`）。

---

## 8. 已知限制与后续

- **默认档位**为「高」。M4 + 1152×648 有约 70fps；若玩家在 1080p/4K 全屏遇到掉帧，可在设置里切「中」。
  后续可加「自动」档（按 GPU/实时帧时自适应），本版未做以避免截图/测试被动态降档干扰。
- **TAA 未启用**：M4 上实测 +5.7ms，性价比低；高档用 SMAA，极高档用 MSAA 2×。
- **体积雾**只在昼夜间用密度变化，不做动态开关（避免切换时的管线重编译卡顿）。
- **草坪消散**由逐片元抖动改为逐叶塌缩：极近景（镜头贴近草叶）时边缘是「叶片级」而非「像素级」，
  但正常俯视角（20~40m 高）不可见；换来了 3.3ms 的整帧收益。
- **夜间暖光**目前来自 9 盏火炬 + 月光；后续可给酒馆/龙园/入住房屋补窗光（注意每盏灯的成本）。
- **draw calls** 仍有 1570（城景），主要来自 16m 分块的阴影投影；后续可在「低档」进一步合并装饰块
  （32m 分块）或关闭小道具投影，需要单独做视觉/性能权衡。
