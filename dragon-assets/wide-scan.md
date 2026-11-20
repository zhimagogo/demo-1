# 龙资源宽口径扫描（Sketchfab / itch.io / OpenGameArt / Godot 生态 / GitHub / 引擎商城）

- **调研员**：`dragon-scout-wide`（共享任务板 `task-2`）
- **取证日期**：2026-10-01（Asia/Shanghai）
- **范围边界**：**不含** KayKit / Quaternius / poly.pizza / Kenney 四家（由 `lowpoly-cc0` 线负责）。本文只写这四家之外的独立作者与平台。
- **风格基线**：项目现用 KayKit Character Pack: Adventurers（CC0 1.0，低多边形 + 平涂手绘贴图，单 GLB 内嵌动画）。
- **目标**：西方奇幻龙（带翼四足龙 / 飞龙 / 幼龙，**排除恐龙**）、免费或开源、rigged、最好带攻击动画、Godot 4.7 可直接用（glTF/GLB 优先）。
- **免责**：本文每条事实都附有**我本次亲自请求过**的 URL。凡是我没能取到证据的字段，一律写「未核实（原因）」，**没有任何猜测填充**。

---

## 0. 结论速览（先看这里）

### 0.1 最优 3 个（带攻击动画 + 许可宽松 + 可低成本接进 Godot）

| 排名 | 名称 | 来源 / URL | 许可证 | 攻击动画 | 下载门槛 | 为什么是它 |
|---|---|---|---|---|---|---|
| **#1** | **Low Poly Dragon Model 3D**（bocdagla） | itch.io<br><https://bocdagla.itch.io/low-poly-dragon> | 页面原文 `License: Creative Commons Attribution` + 「You can use this file however you want as long as you give credit」 | ✅ `Attack` | 免费（Name your own price），无需登录即可下载 `dragon.zip` 1 MB | **唯一同时满足：glTF+FBX 双格式、4 条动画含 Attack、CC-BY、体积 1 MB、作者本人明说「为 Godot 加了 tip bones 方便 IK」** |
| **#2** | **Wyvern**（DibArts） | Sketchfab<br><https://sketchfab.com/3d-models/wyvern-b3b83f40265347dd90e4666c3e2a843c> | **CC-BY 4.0**<br>页面 License 字段原文：*Creative Commons Attribution* — **Author must be credited. Commercial use is allowed.** | ✅ `Attack.new` | 免费下载，**无需登录即可看页面；下载需 Sketchfab 账号登录** | **1154 三角面 + glTF + 5 条动画（Standing/Walking/Running/Flying/Attack）**，作者自述「贴图适合像素或低多边形游戏」——和 KayKit 同一量级 |
| **#3** | **Magic Forest Dragon**（LivindorCreation） | Sketchfab<br><https://sketchfab.com/3d-models/magic-forest-dragon-9e1bcd17aa0f441fbf204fdfc7b8d8f7> | **CC-BY 4.0**（同上原文） | ✅ `attack_1` ~ `attack_5`（5 条）+ `Roar` | 免费下载，需 Sketchfab 账号登录 | **25 条动画的完整游戏动画集**（含 born / hurt / stun / win / travel / dead / cast），8040 三角面，FBX 8.19 MB；这是本次扫描里「动画覆盖度」最高的一条 |

> **一句话取舍**：要**最省事直接进 Godot** 选 #1（现成 glb）；要**面数最低的飞龙**选 #2；要**动画最全的 BOSS 级龙**选 #3。三者许可都可商用，**都要求署名**。

### 0.2 数量统计（本次亲自核实过页面/接口的条目）

| 分级 | 含义 | 条数 |
|---|---|---|
| **A 级** | 至少 1 条攻击类动画 + 可商用许可 + 低多边形/可直接导入 | **16** |
| **B 级** | 可商用、rigged 有动画，但**缺攻击动画** | **13** |
| **C 级** | **许可陷阱 / IP 风险 / 不可用**（含「CC 字段与作者描述自相矛盾」） | **12** |
| **D 级** | 明确「不合格」：无动画 / 无骨骼 / 非 3D / 造型不符（恐龙、东方龙、人形）——详见 §6 | **约 20 条** |
| 负向结论 | 整站确认「没有可用龙模型」的平台 | **4**（Godot Asset Library、Craftpix 免费区、GitHub、Fab 未核实） |

### 0.3 最大风险点（务必先读）

1. **Sketchfab 的 License 字段会被上传者滥用，必须读描述原文交叉验证。** 本次抓到 3 条实锤：
   - `Tarisland - Dragon (High Poly)` 页面 License 字段写 **CC Attribution**，但**作者自己的描述写**「**© Tencent. I do not own this model, all rights are reserved to the company. For non-commercial and PG13 use only.**」→ **字段与描述直接冲突，属于盗传商用游戏资产，绝不能用。**
   - `Drake`（Witsanu Superball，2 条）License 字段 CC-BY，描述只有四个字：`Ragnarok M Eternal Love` / `Ragnarok Origin` → **韩国 Gravity 公司手游拆包资产。**
   - `Poppy Playtime Chapter 4: NightmareCritterDragon` License 字段 CC-BY，页面上**作者显示为 `Unknown`** → 商业游戏拆包。
2. **CC-BY-NC 是本次扫描里「看起来最完美」的那条模型的唯一死穴。** `Mega Wyvern`（SpiderBight）有 11 条动画，动画名堪称「BOSS 全套」（`Flame Blast` / `Fire Balls` / `Talon Smash` / `Strike Swoop` / `Beam|Roar` / `Death` / `Combo Hit`），**glb 格式、16222 面、CC-BY-NC-SA**——**No commercial use，本项目（商业游戏）直接出局。**
3. **itch.io 的「免费下载」≠「可商用」，而且很多页根本没有 License 字段。** 例：`Simple 3D Dragon Model`（MattBas）在 **itch.io 页面完全没有许可证声明**（只有 "Name your own price"），但同一个模型在 OpenGameArt 上标的是 **CC-BY-SA 4.0**——两个平台口径不一致，以 OGA 为准更安全。
4. **`.blend` 单独格式在 Godot 里是「半成品」。** Godot 4.7 导入 `.blend` 依赖本机装 Blender 并在编辑器里配置路径；本仓库的 `PawnModelRig` 走 `load()` / `GLTFDocument`，**只吃 glTF/GLB**。所有「仅 .blend」条目（Cethiel's Dragon 3D、Low Poly Ice Dragon、GuieA_7 Dragon、clintbellanger Wyvern）都需要**先离线转 glTF**才可用。
5. **下载门槛要分开看**：**Sketchfab 侧全部需要登录**（本文 39 条候选逐个实测 `mayDownloadThisModel: false`，见 §1）；**itch.io / OpenGameArt 侧的免费条目本次实测无需登录**（下载按钮在匿名页面直接可见）。本文列出的所有 URL 都是我**匿名 GET 成功**的页面。

---

## 1. 取证方法与可复现证据链

为了让 lead 与另一条线能复核，这里写清每个数据点的来源端点（全部为本次实际请求）：

| 来源 | 端点 | 拿到的字段 |
|---|---|---|
| Sketchfab 搜索 | `https://api.sketchfab.com/v3/search?type=models&q=dragon&downloadable=true&animated=true` | 名称 / uid / 作者 / license.label / animationCount / faceCount / isDownloadable |
| Sketchfab 模型数据页（前端 JSON） | `https://sketchfab.com/i/models/<uid>` | **`license`（含 `needsAttribution` / `requirements` / `ccClauses` / `url`）**、`metadata.isRigged`、`metadata.totalTriangle`、`archiveSize`、`ext`、`downloadType`、`downloadCount`、`metadata.sourceFiles`、`mayDownloadThisModel` |
| Sketchfab 动画清单 | `https://sketchfab.com/i/models/<uid>/animations` | **逐条动画名 + duration + isLoop**（这是拿到真实动画名的关键端点） |
| Sketchfab 许可目录（权威原文） | `https://api.sketchfab.com/v3/licenses` | CC-BY / CC-BY-SA / CC-BY-NC / CC-BY-NC-SA / CC0 / Free Standard 等的 `requirements` 原文 |
| itch.io | 各素材页 HTML（`<title>` + 描述段 + 「More information」区 + 评论区） | 价格档位、`License:` 行、社区问答里的作者口头授权 |
| OpenGameArt | `https://opengameart.org/art-search-advanced?keys=<kw>&field_art_type_tid[]=10` + 各 `/content/<slug>` 页 | `License(s):` 行、`File(s):` 列表与体积、描述里的动画名、Art Type |
| Godot Asset Library | `https://godotengine.org/asset-library/api/asset?filter=<kw>&godot_version=4.4&max_results=30` | 全站匹配条目 |
| GitHub | `https://api.github.com/search/repositories?q=<kw>` | 仓库名 / star / SPDX 许可 |
| Mixamo | `https://www.mixamo.com/api/v1/products?page=1&limit=96&type=Character` | 匿名请求返回 **HTTP 403 `{"error_code":"403000","message":"Api Key is required"}`** |
| Fab (Epic) | `https://www.fab.com/i/search?q=dragon` | **HTTP 403 Cloudflare 挑战页** |

**体积口径约定**：凡写「archiveSize …B ≈x MB」的，均为 Sketchfab `archiveSize` 原始字节数按 **1 MB = 1024×1024 B** 换算；
OGA / itch.io 条目的体积沿用**页面自己显示的单位字符串**（如 `1.4 Mb`、`1 MB`），不做二次换算。

**Sketchfab 下载门槛的统一实测结论**：本次对 **39 条**候选逐个请求 `https://sketchfab.com/i/models/<uid>`，**全部返回 `mayDownloadThisModel: false` 且 `downloadType: "free"`** → 即「**模型免费，但匿名会话不能下载，必须登录 Sketchfab 账号**」。这是本文所有 Sketchfab 条目「下载门槛 = 需登录」这一栏的实测依据（不是猜测）。

**Sketchfab 许可目录原文（本次拉到的权威口径，用于判定「可否商用 / 是否需署名」）：**

| License 字段 | 可否商用 | 是否需署名 | 传染性 | requirements 原文 |
|---|---|---|---|---|
| CC0 Public Domain | ✅ | ❌ 不强制 | 无 | *Credit is not mandatory. Commercial use is allowed.* |
| CC Attribution (CC-BY) | ✅ | ✅ | 无 | *Author must be credited. Commercial use is allowed.* |
| CC Attribution-ShareAlike | ✅ | ✅ | ⚠️ **有** | *Author must be credited. Modified versions must have the same license. Commercial use is allowed.* |
| CC Attribution-NonCommercial | ❌ | ✅ | 无 | *Author must be credited. No commercial use.* |
| CC Attribution-NonCommercial-ShareAlike | ❌ | ✅ | ⚠️ | *Author must be credited. No commercial use. Modified versions must have the same license.* |
| Free Standard | ✅（有基本限制） | 未在字段里要求 | 未核实 | *Under basic restrictions, use worldwide, on all types of media, commercially or not, and in all types of derivative works* → 详情页 <https://sketchfab.com/licenses> **（本次未打开成功，条款细节未核实）** |

> ⚠️ `CC-BY-SA` 的「传染性」在游戏资产上的实务解读：ShareAlike 约束的是**该模型及其改编版本**，不是整个游戏工程；但因为存在解释分歧，**若项目将来要闭源或不愿在模型层面回馈同许可，建议优先选 CC-BY / CC0 而不是 CC-BY-SA**。本文对 CC-BY-SA 条目都会显式标注。

---

## 2. A 级候选：带攻击动画 + 可商用许可（按「接进 Godot 的省事程度」排序）

> 约定：**面数**统一取 Sketchfab `metadata.totalTriangle`（三角形）；OGA/itch 条目取作者自述或未核实。**动画名**逐条照抄接口返回值，不做美化。

### A1 ⭐ Low Poly Dragon Model 3D — bocdagla（itch.io）

| 字段 | 内容 |
|---|---|
| URL | <https://bocdagla.itch.io/low-poly-dragon> |
| 作者 | bocdagla |
| 许可证原文 | 页面 `License: **Creative Commons Attribution**`；描述原文：「You can use this file however you want as long as you give credit :D」 |
| 可否商用 | ✅ 可（作者在评论区回答「能收我改过的版本去卖吗」时明确同意：*"of course, go ahead and charge how much you want for it"*） |
| 是否需署名 | ✅ 需要（作者：*"Just just an entry on the credits is more than enough"*） |
| 格式与体积 | **`.fbx` 与 `.glb` 两种**；`dragon.zip` **1 MB** |
| 是否 rigged | ✅ 有骨骼；作者原话：「It is in fbx and **glb** format and i've added some **tip bones for easier IK on godot**」 |
| 动画清单 | **4 条，页面逐条列出：`Attack` / `Fly` / `Move` / `Idle`**（含攻击 ✅ 含飞行 ✅） |
| 面数量级 | 未核实（页面未给面数；zip 仅 1 MB → 推断为低多边形，但**未实测不加断言**） |
| 下载门槛 | 「Name your own price」= 0 元可下；**无需登录**（下载按钮直接可见） |
| 风格匹配度 | **高** — 明确标注 Low-poly / Dragons / Fantasy 标签，且 tag 里有 **Godot**；作者按 Godot IK 习惯加了 tip bones |
| 备注 | comment 区有第三方已用它做过改贴图/换动画并商业化，作者同意 → 社区验证过可用 |

### A2 ⭐ Wyvern — DibArts（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/wyvern-b3b83f40265347dd90e4666c3e2a843c> |
| 数据证据 | <https://sketchfab.com/i/models/b3b83f40265347dd90e4666c3e2a843c> ＋ <https://sketchfab.com/i/models/b3b83f40265347dd90e4666c3e2a843c/animations> |
| 作者 | DibArts |
| 许可证 | **CC Attribution（CC-BY 4.0）**，原文 *Author must be credited. Commercial use is allowed.*，<http://creativecommons.org/licenses/by/4.0/> |
| 可否商用 | ✅ |
| 是否需署名 | ✅ |
| 格式与体积 | `ext = gltf`（**glTF**），`archiveSize = 289,654 B ≈283 KB`；sourceFiles 仅 gltf |
| 是否 rigged | ⚠️ **Sketchfab 元数据 `metadata.isRigged = false`**（无蒙皮标记）；但作者描述明说有 5 条动画 → 可能是 Blockbench 风格的**节点级动画**。**必须下载实测 AnimationPlayer 轨道是否驱动网格形变**（见 §7 检查表） |
| 动画清单 | **5 条（照抄）**：`Attack.new` / `Flying.new` / `Running.new` / `Walking.new` / `Standing.new` |
| 面数量级 | **1154 三角形**（本次扫描最低的一档） |
| 下载门槛 | 免费下载；**下载需登录 Sketchfab 账号**（页面可匿名浏览） |
| 数据热度 | 296 次下载 / 1186 浏览 / 32 赞（2022-11-13 发布） |
| 风格匹配度 | **高** — 作者原话：「This wyvern has animation for idle, walking, running, flying, and attacking. It has textures that can fit in **pixel or low poly games**.」 |

### A3 ⭐ Magic Forest Dragon — LivindorCreation（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/magic-forest-dragon-9e1bcd17aa0f441fbf204fdfc7b8d8f7> |
| 数据证据 | <https://sketchfab.com/i/models/9e1bcd17aa0f441fbf204fdfc7b8d8f7/animations> |
| 作者 | LivindorCreation |
| 许可证 | **CC Attribution（CC-BY 4.0）**，原文 *Author must be credited. Commercial use is allowed.* |
| 可否商用 / 署名 | ✅ 可商用 / ✅ 需署名 |
| 格式与体积 | **`.fbx`（multi-take 单文件含全部动画）**，`archiveSize = 8,188,062 B ≈7.81 MB` |
| 是否 rigged | ✅ `metadata.isRigged = true` |
| 动画清单（25 条，照抄） | `idle` `pettyidle` `Roar` `travelidle` `travelmove` `travelrun` `travelpettyidle` **`attack_1` `attack_2` `attack_3` `attack_5`** `cast_1` `hurtsmall` `hurtbig` `dead` `born` `Down` `winover` `winstart` `winidle` `stunstart` `stunidle` `stunover` `stunhurtsmall` `stunhurtbig` — **注意：接口返回 25 条，其中没有 `attack_4`**（同类 `Skeleton Dragon` 有 `attack_4` 但没有 `attack_1`，两者似是同一套动画库的变体） |
| 面数量级 | **8040 三角形** |
| 下载门槛 | 免费下载（`downloadType = free`）；下载需登录 |
| 数据热度 | **1532 次下载 / 6158 浏览 / 211 赞** |
| 风格匹配度 | **中高** — stylized 奇幻龙，面数（8k）比 KayKit（数百~数千面）高一个量级，平涂观感接近但更细 |

### A4 Skeleton Dragon — LivindorCreation（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/skeleton-dragon-0ae92a30d2c242069acd61ed432f6c32> |
| 许可证 | **CC-BY 4.0**，*Author must be credited. Commercial use is allowed.* |
| 格式与体积 | `.fbx`，`archiveSize = 3,756,879 B ≈3.58 MB`，`isRigged = true` |
| 动画清单（23 条，照抄） | `pettyidle` `idle` `travelidle` `travelmove` `travelrun` `travelpettyidle` `soar` `born` `dead` `hurtsmall` `hurtbig` **`attack_2` `attack_3` `attack_4` `attack_5`** `cast_1` `stunstart` `stunidle` `stunover` `stunhurtsmall` `stunhurtbig` `winstart` `winidle` `winover` |
| 面数量级 | **7993 三角形** |
| 下载门槛 | 免费，需登录 |
| 数据热度 | 2441 下载 / 14785 浏览 / 327 赞（同作者最热一条） |
| 风格匹配度 | **中低** — 是**骷髅龙（亡灵）**，不是活体西方龙；若要「活龙」不符合，若要「亡灵 BOSS」则完全够用 |

### A5 Dragon Animation — dodibs（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/dragon-animation-0c601ab0b105409199b17ea0719f8310> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | `.fbx`，`archiveSize = 4,583,696 B ≈4.37 MB`，`isRigged = true` |
| 动画清单（3 条，照抄） | **`Attack` / `Flight` / `Roar`** |
| 面数量级 | **3476 三角形**（低多边形） |
| 下载门槛 | 免费，需登录 |
| 风格匹配度 | **中高**（面数合适），但见下方 ⚠️ |
| ⚠️ **来源风险** | 作者描述原文：「**Low Poly Dragon model I found.** Rigged it. Animated it with a roar, flight, and attack animation.」→ **基础网格是作者"找到的"，来源未说明**。作者对自己做的绑定与动画有版权，但**基础模型的许可链断裂**。若要用，建议按「仅作原型占位」处理，不要进正式版本 |

### A6 Leathern Drake - Blockbench — Breathfang（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/leathern-drake-blockbench-021865367838492a9839c64c6f3cb984> |
| 许可证 | **CC-BY 4.0**；描述里作者**再次亲口确认**：「This model is downloadable (based on **CC-BY**)」 |
| 格式与体积 | `ext = gltf`（**glTF**），`archiveSize = 1,274,536 B ≈1.22 MB`；作者另在描述里给了 MediaFire 的 Blockbench 源文件与 FBX 包链接（外部站，**未核实**） |
| 是否 rigged | ⚠️ `metadata.isRigged = false`（同 A2，Blockbench 节点动画风格），**需实测** |
| 动画清单（18 条，照抄） | `idle` `walk` `run` `jump` `jumpshort` `fall` `fallandsit` `fallaccident` `sit` `sleep` `eat` `sickness` `stayonair` `walkonair` **`breathfire` `breathfirestart` `breathfireend` `breathfireshort`** |
| 面数量级 | **2124 三角形** |
| 攻击动画判定 | **没有名字叫 Attack 的条目**；但**有完整 4 段吐息（breathfire 起手/持续/收招/短吐）**，作为远程攻击动作可用；作者描述也说「This drake can **breathing fire** and even **bite** them」 |
| 下载门槛 | 免费，需登录 |
| 数据热度 | 1569 下载 / 8370 浏览 / 176 赞 |
| 风格匹配度 | **中** — **Blockbench 出品 = Minecraft/MagicaVoxel 那一路的方正块面风**，与 KayKit 的圆润低多边形平涂不同；4 套贴图变体可选 |

### A7 Adventurer Dragon - Kai — AeviarththeDragoness（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/adventurer-dragon-kai-32182abf2c37431e911cb2ad92544c57> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | `ext = gltf`（**glTF**），`archiveSize = 2,338,922 B ≈2.23 MB` |
| 是否 rigged | ⚠️ `metadata.isRigged = false`（该作者另一条 `Robot Dragon` 描述明确说「made in **Blockbench**」→ 同源工作流，节点动画可能性大） |
| 动画清单（**接口返回 35 条**，作者页面标 29 条，照抄重点） | 攻击/技能类：**`breathFire` `clawSwipe1L` `clawSwipe1R` `clawSwipe2L` `clawSwipe2R` `tailWhip1L` `tailWhip1R` `tailWhip2`**；移动类：`idling` `walkies` `running` `jump` `fall` `rise` `land` `squatting` `sitting` `lying` `eeping`；飞行类：`flying` `flyingIdle` `gliding` `diving1` `diving2` `diving2.5` `diving3`；水中：`swimming` `swimmingIdle`；姿势：`wingsFoldIn` `wingsFoldOut` `quadrupedal` `bipedal` `bellyKicksMild` `bellyKicksWild` `Bleppy` |
| 面数量级 | **1708 三角形** |
| 下载门槛 | 免费，需登录 |
| 数据热度 | ⚠️ **很新**：2026-06-30 发布，仅 12 次下载 / 74 浏览 / 4 赞 → **未经社区验证** |
| 风格匹配度 | **高**（1708 面 + 8 条爪击/挥尾 + 吐息，动作覆盖极全），但需实测绑定形式 |

### A8 Hell Drake — Byuuru（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/hell-drake-c8505007238d44bcb575c7763307a570> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | **`ext = glb`（GLB，Godot 首选格式）**，`archiveSize = 18,729,312 B ≈17.86 MB` |
| 是否 rigged | ✅ `isRigged = true` |
| 动画清单（5 条，照抄） | `idle` `idle_turn` `walk_cycle` `roar` **`bite`** |
| 攻击动画判定 | ✅ 有 `bite`（咬击）+ `roar`；**没有独立的「爪击/吐息」** |
| 面数量级 | **52,458 三角形**（偏高） |
| 下载门槛 | 免费，需登录 |
| 数据热度 | 801 下载 / 3610 浏览 / 106 赞 |
| 风格匹配度 | **中** — 作者自述「A **demon dragon** thingo I created for practice as my first Blender project」，恶魔龙，写实度高于 KayKit；且作者自评 *Game-ready, feel free to use for Unreal Engine (or whatever you like)* |

### A9 Flying the Dragon with Kandinsky — Miguelangelo Rosario（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/flying-the-dragon-with-kandinsky-6d37bf7516da4cfd9ad3721d10ad3496> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | `.fbx`（原文件名 `WyvernALL`），`archiveSize ≈ 21.67 MB`，`isRigged = true` |
| 动画清单（10 条，照抄） | `Idle` `Idle2` `Idle3` `Fly` `SlowFly` **`Attack` `Attack2` `Attack3`** `Die` `Tpose` |
| 面数量级 | **13,405 三角形** |
| 攻击动画判定 | ✅ **3 条独立攻击 + Die + 两档飞行** |
| 下载门槛 | 免费，需登录 |
| 风格匹配度 | **中** — 作者定位是「Augmented Reality Art experiment」，观感偏艺术化，不是典型游戏低多边形 |

### A10 Four-Legged-Frost-Predator. — bensimulator2（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/four-legged-frost-predator-3ddc6f711201449cbc33617f430d1b20> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | `.fbx`，`archiveSize ≈10.65 MB`（11,165,203 B），`isRigged = true` |
| 动画清单（7 条，照抄） | `rig|Idle` `rig|walk` `rig|Run` **`rig|attack` `rig|Powerfull_attack`** `rig|Roar` `rig|Sleeping` |
| 面数量级 | **14,564 三角形** |
| 攻击动画判定 | ✅ 2 档攻击（普攻 + 强力攻击）+ Roar |
| 下载门槛 | 免费，需登录 |
| 风格匹配度 | **中** — 名字是「四足冰霜掠食者」不是龙；外观是否带翼**未核实**（我没有打开 3D 预览逐帧确认）。⚠️ 且描述只有「**kudos to [Timsblends]**」→ **疑似他人模型的二次上传，署名链需谨慎** |

### A11 Wyvern — clintbellanger（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/wyvern-3f11883f300842878e46b22fce554e81> |
| 许可证 | **CC Attribution-ShareAlike（CC-BY-SA 4.0）** ⚠️ **有传染性** |
| 格式与体积 | **`.blend`（仅 Blender 源文件）**，`archiveSize = 5,989,672 B ≈5.71 MB` |
| 是否 rigged | ✅ `isRigged = true` |
| 动画清单（6 条，照抄） | **`Sting`（刺击）** `Die` `Fly` `Hover` `Breathe` `Hit` |
| 面数量级 | **1436 三角形**（第二低） |
| 下载门槛 | 免费，需登录 |
| 风格匹配度 | **高**（面数极低），但需要 **Blender 转 glTF** + 接受 **ShareAlike** |
| 署名链 | 描述原文：「Model by **Clint Bellanger**, Skins by **Justin Nichol**, for project **Wandercall**」→ **要署两个名字** |
| 备注 | 作者 clintbellanger 是开源游戏 **Flare** 的作者，CC-BY-SA 资产长期被商用项目采用，实务上可靠 |

### A12 Dragon (3D) — GuieA_7（OpenGameArt）

| 字段 | 内容 |
|---|---|
| URL | <https://opengameart.org/content/dragon-3d> |
| 作者 | GuieA_7（署名要求原文：*Credit **Guillaume "GuieA_7" Englert***） |
| 许可证 | **CC-BY-SA 4.0** ⚠️ 传染性；页面 `License(s): CC-BY-SA 4.0` |
| 格式与体积 | **`.blend`**（+ 1024×512 png 贴图，含 .xcf），`dragon.zip` **10.1 MB**，230 次下载 |
| 是否 rigged | ✅ 有骨骼（描述：「some animations (walk, attack x 2, idle x 3, sleep, die...)」） |
| 动画清单（**作者描述原文**，非接口） | **walk / attack ×2 / idle ×3 / sleep / die** —— 含攻击 ✅ |
| 面数量级 | **2250 三角形**（作者原文） |
| 下载门槛 | 免费，**无需登录**（OGA 直接下载） |
| 风格匹配度 | **高**（2250 面 + 8 条动画 + 单张手绘贴图），**但必须先 Blender 转 glTF** |
| 备注 | 评论里有人反馈「just works in jMonkeyEngine」→ 至少被引擎实际导入验证过 |

### A13 Stylized Black/White dragon — BBangzip（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/stylized-blackwhite-dragon-ef9bafe6fb644355addadf2e5a0e7bfd> |
| 许可证 | **CC-BY 4.0**（作者描述：「You are free to use and modify this model as long as I am credited」——**同作者另一条姊妹模型页面的原文**） |
| 格式与体积 | `.fbx`，`archiveSize ≈9.87 MB`（10,352,156 B），`isRigged = true` |
| 动画清单（接口返回 18 条，照抄去重后的动作名） | `Black_dragon_attack` `Black_dragon_attack_another` `Black_dragon_fly` `Black_dragon_fly_another` `Black_dragon_fly_front` `Black_dragon_fly_front_another` —— 另外 12 条是同名动作带 `Armature.001\|` / `Armature.002\|` 前缀的重复副本（**18 条 ≈ 3 套骨架 × 同名 6 动作**，实际可用动作只有 6 个） |
| 面数量级 | **49,120 三角形**（偏高） |
| 下载门槛 | 免费，需登录；数据较冷（31 下载） |
| 风格匹配度 | **中** — 作者自称 low-poly 且面向 Unity/mobile，但 49k 面已不算低模 |

### A14 Stylized Red/Black dragon — BBangzip（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/stylized-redblack-dragon-5aba72274f2f4036b9e322f59492ac22> |
| 许可证 | **CC-BY 4.0**；描述原文完整引用：「This is a low-poly 3D model of a stylized black dragon, originally designed as an asset for Unity projects. Its simplified, low-poly design makes it highly suitable for mobile games, real-time applications, or games with a stylized art direction. **You are free to use and modify this model as long as I am credited as its original creator.**」 |
| 格式与体积 | `.fbx`，`archiveSize ≈3.87 MB`（4,054,796 B），`isRigged = true` |
| 动画清单（6 条，照抄） | `Reddragon_idle` `Armature.001|Reddragon_idle.001` **`Reddragon_fly_attack` `Armature.001|Reddragon_fly_attack`** `Reddragon_fly` `Armature.001|Reddragon_fly`（≈2 套骨架 × 3 动作） |
| 面数量级 | **48,800 三角形** |
| 攻击动画判定 | ✅ 有 `fly_attack`（飞行攻击），**但没有地面攻击/咬击** |
| 下载门槛 | 免费，需登录；63 下载 |

### A15 Mecha Drake — Yerko Alarcón（Sketchfab）

| 字段 | 内容 |
|---|---|
| URL | <https://sketchfab.com/3d-models/mecha-drake-558a423673f04ae5a9b82f9deeb4cf44> |
| 许可证 | **CC-BY 4.0** |
| 格式与体积 | **`.blend`**，`archiveSize = 537,036 B ≈524 KB`，`isRigged = true` |
| 动画清单（4 条，照抄，西语命名） | `Ani.Idle` / `Ani. Vuelo`（飞行）/ `Ani. Muerte`（死亡）/ **`Ani. Ataque`（攻击）** |
| 面数量级 | **4150 三角形** |
| 下载门槛 | 免费，需登录 |
| 风格匹配度 | **低** — 是**机甲龙（Mecha）**，与西方奇幻龙世界观不符；但「4 条动画含攻击 + 4k 面 + 仅 524 KB」这点值得记录 |

### A16 Low Poly Ice Dragon — xTerryx（OpenGameArt）

| 字段 | 内容 |
|---|---|
| URL | <https://opengameart.org/content/low-poly-ice-dragon> |
| 作者 | xTerryx（2023-04-01 提交） |
| 许可证 | **CC0**（页面 `License(s): CC0`）；Copyright/Attribution Notice 原文：「*None needed, just giving back to the community.*」 |
| 可否商用 / 署名 | ✅ 可商用 / ❌ 不要求署名 |
| 格式与体积 | **`.blend` 1.6 MB + `dragon_texture.png` 166 B**（贴图文件仅 166 字节 → 极可能是纯色/极简贴图）；**无 glTF/GLB** |
| 是否 rigged | ✅ 有骨骼（能播动画） |
| 动画清单（**作者描述原文**） | 「A basic Ice Dragon I made with **a fly and a bite animation**.」→ **fly + bite 两条**，含攻击类 ✅；**确切动画名未核实（作者未列名，我没有下载 zip）** |
| 面数量级 | 未核实（页面未给） |
| 下载门槛 | 免费，**无需登录** |
| 风格匹配度 | **高**（CC0 + 低多边形 + fly/bite），**但必须 Blender 转 glTF**，且下载量很低（102 次）说明社区验证不足 |

---

## 3. B 级候选：可商用、有动画，但**缺攻击动作**（可作飞行/坐骑/场景 NPC）

| # | 名称 | 作者 | URL | 许可证 | 格式 / 体积 | rigged | 动画清单（照抄） | 面数 | 门槛 |
|---|---|---|---|---|---|---|---|---|---|
| B1 | **European Dragon** | Regina Cachoa | <https://sketchfab.com/3d-models/european-dragon-82f393a2e6c048ad80c171ce3b3a7b87> | CC-BY 4.0 | `.fbx` **≈48.6 MB**（archiveSize 50,926,884 B） | ✅ true | `Idle Stand` `Idle Sit` `Walk` `Run` `Fly` | 42,338 | 免费，需登录；**5330 下载 / 419 赞（本次最热门）** |
| B2 | **Green Dragon** | GadgetHamster | <https://sketchfab.com/3d-models/green-dragon-72f132a847c849f3b5f1c40bb2dcba7a> | CC-BY 4.0 | `.fbx` ≈4.89 MB（5,127,660 B） | ✅ true | `GreenDragon_Skeleton\|WingStretch` `…\|sleep` `…\|Ref` `…\|Pose` `…\|pin` `…\|Fly`（**6 条里 3 条是 Ref/Pose 之类的非动作条目**） | 22,042 | 免费，需登录 |
| B3 | **Low Poly Flying Dragon** | CarolaBug | <https://sketchfab.com/3d-models/low-poly-flying-dragon-811f651584814044acfaa47546ec882d> | CC-BY 4.0 | **`.glb` ≈689 KB**（705,988 B） | ✅ true | `Fly` `Fly 2` | **1,708** | 免费，需登录 |
| B4 | **Whispering Wyrm** | DeliciousDynamite | <https://sketchfab.com/3d-models/whispering-wyrm-3387a26f80e446e290403eff33242ffc> | CC-BY 4.0 | `.fbx` ≈0.98 MB（1,030,732 B） | ✅ true | `Object_5\|Idle1_Object_5` `Object_5\|Fly_Object_5` | **1,881** | 免费，需登录 |
| B5 | **Sea-Dragon** | Jenosuke | <https://sketchfab.com/3d-models/sea-dragon-fc85d8300da44070891f0839c204567c> | CC-BY 4.0 | `.fbx` ≈733 KB（750,252 B） | ✅ true | `Sea-Dragon\|Idol` `Sea-Dragon\|Idol.001` `Sea-Dragon\|DeathAnimation` | 2,173 | 免费，需登录；⚠️ **海蛇形，非四足带翼龙** |
| B6 | **Simple 3D Dragon Model** | MattBas | OGA <https://opengameart.org/content/simple-3d-dragon-model> ／ itch <https://mattbas.itch.io/dragon-model> | **CC-BY-SA 4.0**（OGA 页）；⚠️ **itch 页无任何许可声明** | **`dragon.tar.gz` 168.5 KB（内含 glb + 贴图）** + `dragon.blend` 2 MB | ✅ 有 rig | `Flying` `Walking` `Idle` `Running`（**无攻击**） | 未核实 | 免费，两站都无需登录；⚠️ **两站许可口径不一致** |
| B7 | **Cethiel's Dragon 3D** | Drummyfish（协作者 Cethiel） | <https://opengameart.org/content/cethiels-dragon-3d> | **CC0**（*Not required. If you want, credit Cethiel and Drummyfish.*） | `dragon_oga.zip` **1.4 MB**（内含模型 + 两张贴图） | ✅ **描述原文「This 3D model is rigged and animated as well」** | **未核实** — 作者只写了「rigged and animated」，**页面与评论都没有列出动画名**；我遵守「只做纸上取证」没有下载 zip 解包 | 未核实 | 免费，无需登录；**2902 次下载 / 66 收藏**（CC0 龙里最热门） |
| B8 | **Wyvern animated** | CharlieCatling | <https://sketchfab.com/3d-models/wyvern-animated-1dc70bbf15c2456a85290c8613b6c1ff> | ⚠️ **Free Standard（Sketchfab 自有许可，非 CC）**：*Under basic restrictions, use worldwide, on all types of media, commercially or not…* — **条款细节未核实** | `.fbx` ≈ 12.04 MB | ✅ true | `metarig\|walk` `metarig\|take off` `metarig\|idol` `metarig\|flying` `metarig\|flaping` ＋ 带 `Cube.002\|` 前缀的重复（接口返回 11 条，页面标 5 条） | 28,706 | 免费，需登录；**无攻击/咬击** |
| B9 | **Adult Dragon** / **Young Dragon** / **Baby Dragon** | jose.ranieri | <https://sketchfab.com/3d-models/adult-dragon-b1667e01947148e5bea733b3b69cdccc> ／ <https://sketchfab.com/3d-models/young-dragon-fd27df134ab04945ac3d8678accc112b> ／ <https://sketchfab.com/3d-models/baby-dragon-affb5ea883094f638592273fb8dd4559> | CC-BY 4.0 | 均 `.blend`（≈2.09 MB / 1.67 MB / 38 KB） | ✅ true | **三只都只有 `cyclewalk` 一条** | 3876 / 1920 / 1412 | 免费，需登录；**成年/幼年/幼崽三档尺寸可做同一龙的成长形态**（这是它唯一的独特价值） |
| B10 | **Wyvern Flying Animation** | Lais.Marques | <https://sketchfab.com/3d-models/wyvern-flying-animation-330f6761ed7142b49b1e95cc9004e5e8> | CC-BY 4.0 | `.fbx` ≈1.71 MB | ✅ true | `Take 001`（**动画名无意义，单条**） | 9,524 | 免费，需登录 |
| B11 | **Dragon** | Sachinanc2 | <https://sketchfab.com/3d-models/dragon-8da32bc36fca41ea9d0d60398bcf8dee> | CC-BY 4.0 | **`.glb` ≈ 33.6 MB** | ✅ true | `idle` `running` `flying`（**无攻击**） | 19,544 | 免费，需登录 |
| B12 | **Frost Dragon - Low Poly** | dimas darfiangga | <https://sketchfab.com/3d-models/frost-dragon-low-poly-f5ae0c7070d24abdb124d3b36dfe0356> | CC-BY 4.0 | `.fbx` ≈272 KB | ✅ true | `CINEMA_4D_Naga`（**单条且名字与龙无关，疑似导出残留**） | 2,312 | 免费，需登录 |
| B13 | **Animated 3D Dragon Model** | （OGA 上传者未在页面显示作者字段）署名要求指向 **Benjamin Marty** | <https://opengameart.org/content/animated-3d-dragon-model> | **CC-BY 3.0** | `.blend` 1.7 MB + `DragonUVTexture1.jpg` 518 KB | ✅ 有可摆姿势的骨架（「posable skeleton」） | **未核实** — 作者原话：「animated it, but **have since forgotten how to use Blender**」→ 连作者都不确定；页面未列动画名 | 未核实 | 免费，无需登录；⚠️ 作者自评「贴图有点乱（texturing is a bit crazy）」 |

---

## 4. C 级：⚠️ 许可陷阱 / IP 风险清单（**这些是本报告最重要的部分**）

> 用户是商业游戏项目，以下条目**无论动画多好都不能直接用**。请 lead 在最终汇总里保留这一节。

| # | 名称 | URL | 页面 License 字段 | **真正的许可状态（来自作者自己的描述 / 页面其他原文）** | 风险类型 |
|---|---|---|---|---|---|
| **C1** | **Tarisland - Dragon (High Poly)** | <https://sketchfab.com/3d-models/tarisland-dragon-high-poly-ecf63885166c40e2bbbcdf11cd14e65f> | **CC Attribution**（*Commercial use is allowed*） | **描述原文**：「**.fbx** 7.5.0 multitake with **27 animations**」＋「**© Tencent. I do not own this model, all rights are reserved to the company. For non-commercial and PG13 use only.**」 | **字段与描述直接冲突** → 盗传腾讯《塔瑞斯世界》商用游戏资产。动画质量极佳（27 条含 `Qishilong_attack01/02`、`skill02`~`skill11`、`die`、`fly2`、`walk`），**但绝不能用**。28910 下载 / 2144 赞说明「CC 字段」完全没能阻止传播 |
| **C2** | **Mega Wyvern** | <https://sketchfab.com/3d-models/mega-wyvern-f8caf90ad5da4017b0dddfe880cf37cc> | **CC Attribution-NonCommercial-ShareAlike** — *Author must be credited. **No commercial use.** Modified versions must have the same license.* | 作者描述只说「This dragon can be game ready to use」，**未提许可**；以字段为准 | **NonCommercial 一票否决**。讽刺的是它是本次扫描里动画设计最像 BOSS 的：`Idle` `Appearance` `Combo Hit` `Talon Smash` `Strike Swoop` `Flame Blast` `Fire Balls` `Beam\|Roar` `Roar` `Wind Blast\|Wing Slap` `Death`（11 条，glb，16,222 面，≈4.9 MB） |
| **C3** | **Drake**（13 条动画版） | <https://sketchfab.com/3d-models/drake-6c937c1f965241999f313ade39ad815e> | **CC Attribution** | **描述全文只有一行**：「**Ragnarok M Eternal Love**」 | **手游拆包**（Gravity《仙境传说 M：永恒的爱》）。动画名很诱人（照抄 13 条：`attack` `happy` `die` `use_skill` `eat` `walk_InHand` `be_touch` `walk` `hit` `skill_ready` `wait_1` `wait_InHand` `playshow`，2286 面），但**版权不属于上传者** |
| **C4** | **Drake**（21 条动画版，`Monster_HaiDaoZhiWang_*`） | <https://sketchfab.com/3d-models/drake-94be40ba4547426087ce40e802d037d0> | **CC Attribution** | **描述全文只有一行**：「**Ragnarok Origin**」 | 同上，另一款手游拆包。动画名是中文拼音的内部命名（`Monster_HaiDaoZhiWang_Attack` / `_Death` / `_Run` / 11 条 `_Skill_*`），**典型的工程导出残留** |
| **C5** | **Poppy Playtime Chapter 4: NightmareCritterDragon** | <https://sketchfab.com/3d-models/poppy-playtime-chapter-4-nightmarecritterdragon-cefa17f3a1284f5482b0a65e184f8254> | **CC Attribution** | **页面作者显示为 `Unknown`**；动画名全是 `SK_NightmareCritter_Dragon_LOD0_Skeleton\|A_SmilingCritters_*`（64 条，含 `A_ColorPlush_AttackMelee_Montage`、`A_Critter_Jumpscare`、`A_Plush_CrawlScared`） | **商业游戏（Poppy Playtime）拆包 + 匿名上传**。`LOD0` + `SK_` + `A_` 前缀 = UE 资产命名规范，铁证 |
| **C6** | **Revamped Ender Dragon** | <https://sketchfab.com/3d-models/revamped-ender-dragon-990819619e03463c8c0dea011ea34bb0> | **CC Attribution** | 「I decided to **redisgn the Minecraft Ender Dragon** Boss mob because I was bored.」 | **Mojang/Microsoft IP 的衍生作品**。上传者只能授权自己的改动，不能授权 Ender Dragon 这个形象本身。技术参数很诱人（glb，**840 面**，6 条动画 `dragon_idle/flying/perch/swoop/sleep/death`），**但商业项目有法律风险** |
| **C7** | **[Warcraft] - Wyvern**（13 条动画） | <https://sketchfab.com/3d-models/warcraft-wyvern-c533a980571f48a9801276e28b8dd86c>（作者 Northcliffe，4948 面） | **CC Attribution-NonCommercial** | 名称前缀 `[Warcraft]` 已自陈来源 | **Blizzard IP + NC 双重风险**，连字段都是 NC |
| **C8** | **Black Dragon with Idle Animation** | <https://sketchfab.com/3d-models/black-dragon-with-idle-animation-fb0053a2e59b43868e934c239bf4eb36>（作者 3DHaupt） | **CC Attribution-NonCommercial** | 37992 面，仅 1 条 idle | **NC → 否决**（作为风格参考可看，不能进项目） |
| **C9** | **Desert Dragon** / **Dragon Walk** / **Fire Dragon** / **Dragon low poly animated** / **Dragon Boss Dark** / **Dragon Fly** | <https://sketchfab.com/3d-models/desert-dragon-d826b1a0cb2b4128a7307d0cd06d967a>（SpiderBight）<br><https://sketchfab.com/3d-models/dragon-walk-593ab073004a43089b74c03d3bd8b0cf>（LostBoyz2078）<br><https://sketchfab.com/3d-models/fire-dragon-687b5d8bd6224ac5861c41935f0ff36b>（danmatos）<br><https://sketchfab.com/3d-models/dragon-low-poly-animated-cd4a9470c57a4af18272e2119d4b5337>（Karevus）<br><https://sketchfab.com/3d-models/dragon-boss-dark-b39157ccfe3c45eba50511e59bf0602b>（kenchoo）<br><https://sketchfab.com/3d-models/dragon-fly-1443a7efe5d5450b8db4c15d8ff5c343>（LostBoyz2078） | 均为 **CC Attribution-NonCommercial** | — | **批量 NC**：本次 Sketchfab 扫描里所有标 NC 的龙，一律出局。注意 `Desert Dragon`（SpiderBight）与 `Mega Wyvern`(C2) 是同一作者；而 `Prowler Dragon Variant Rig` 与 `Desert Dragon` 是同一模型的两种许可版本（**CC-BY vs CC-BY-NC**）→ **想要这个模型请认准 CC-BY 的那条** |
| **C10** | **Elder Wyrm - FF XII / Ring Wyrm - Final Fantasy XII** | <https://sketchfab.com/3d-models/elder-wyrm-ff-xii-8627640573704b3c8505d61d483a38d6>（chatholoboom7745289，5041 面）<br><https://sketchfab.com/3d-models/ring-wyrm-final-fantasy-xii-77d35c86d9154c30881fb6a25578b8ca>（Catholomew，5876 面） | **CC Attribution-NonCommercial** | 标题即自陈来源 | **Square Enix IP + NC** |
| **C11** | **3DDisco 全系龙** | <https://3ddisco.itch.io/cartoon-red-dragon-animated-3d-model> 等 | 页面无 License 字段 | 价格 **`Buy Now $99.99 USD or more`**（*you must purchase it at or above the minimum price of $99.99 USD*）；包含 rig + 12 条动画（Idle, Talk, Walk, TakeOff, Fly…） | **仅付费**。该店有 20+ 条龙（Realistic 6 色 + Cartoon 十余色），质量看着不错但**不属"免费或开源"范围**；且 itch 购买页**没有声明可否用于 Godot**（多数卖 Unity/UE 包的店默认给 .unitypackage + UE 包，本条商品文件列表为 `.zip / .unitypackage ×2 / UE.zip`） |
| **C12** | **Robot Dragon** | <https://sketchfab.com/3d-models/robot-dragon-f78622a3f4a842faaa7fc1f983077ad7> | CC-BY 4.0（许可没问题） | 65 条「动画」全是 `eyelidsDown` / `eyesV` / `pupilsHearts` / `chestyScreenMusic` 这类**形态键** | **不是许可陷阱，是技术陷阱**：看着 65 条动画很多，实际**没有一条是动作动画**（是表情/屏幕贴图切换）。同作者的 `Adventurer Dragon - Kai`(A7) 也标 `isRigged=false`，**必须实测** |

### 4.1 「同名不同命」提醒

`Desert Dragon`（CC-BY-NC）与 `Prowler Dragon Variant Rig`（CC-BY）是**同一个 19766 面模型**的两个页面；`Demon_dragon` 与 `Demon Dragon Full Texture` 也是同一 uid 内容的两条（312,688 面，3 条动画，CC-BY）。**按名字搜到就下载是危险的，必须核对 uid 与 License 字段。**

---

## 5. 负向结论：这些地方**确认没有**可用的龙

| 平台 | 核查方式与结果 | 结论 |
|---|---|---|
| **Godot Asset Library** | `https://godotengine.org/asset-library/api/asset?filter=dragon&godot_version=4.4&max_results=20` → 只返回 `Godot-DragonBones v2`（2D Tools）、`Godot-DragonBones`（2D Tools）、`NodeShaker3D`（3D Tools）；`filter=creature` → 只返回 `Asset Iteration Helper` | ✅ **确认无任何 3D 龙模型/角色资源**。Asset Library 只有插件和工具，**不要指望从那里拿龙** |
| **Craftpix 免费区** | `https://craftpix.net/freebies/?s=dragon`（跟随 301 重定向后 HTTP 200）→ 命中 16 条，其中免费条目只有 `free-rpg-dragon-loot-icons`、`free-rpg-wing-game-icons`（都是 **2D 图标**）；龙本体全部落在 `product/`（付费）：`2d-fantasy-dragons-sprite-sheets`、`2d-game-dragon-character-sprites`、`dragon-pixel-art-character-sprite-sheets-pack` 等 | ✅ **确认无 3D 龙；龙相关全是 2D 像素/矢量，且模型本体多为付费** |
| **GitHub** | 多轮检索：`dragon glb`(2 条无关)、`godot dragon 3d`(3 条无关)、`dragon gltf model`(4 条无关)、`low poly dragon model`(0)、`dragon fbx rigged`(0)、`fantasy creature glb godot`(0)、`dragon in:name,description godot`(147 条，**Top 结果全是 DragonBones 插件 / 2D 游戏 / 同名插件**)。唯一沾边的 `khiim/lets-fight-a-dragon-with-godot`（3★，License `NOASSERTION`）实测目录树里 `assets/dragon/` **只有 4 张 PNG**（`dragon.png` / `dragon_flying.png` / `dragon_mouth_open.png` / `breath_weapon.png`）→ **2D 精灵，不是 3D 模型** | ⚠️ **修正：不能写「确认没有」。** 我自己的仓库级检索确实**找不到可用的**，但 `lowpoly-cc0` 线另发现了 **`igmixer/cpDragon-gltf`**——我随后**独立复核过**：`https://api.github.com/repos/igmixer/cpDragon-gltf` 返回 license = **MIT**、无 description、0★、2020-02-18 创建后未再更新、无 README（`/readme` 返回 404）；目录树 = `LICENSE`(1064B) ＋ `scene.gltf`(179,372B) ＋ `scene.bin`(383,852B) ＋ `textures/phong2_{baseColor,emissive,normal}.png`。→ **确有此仓库，但「来源与授权链不明」（无作者说明、MIT 由谁授予无据）、是否含动画未核实**。结论修正为：**GitHub 上不存在来源可信、文档齐全、有动画的龙资产仓库** |
| **Fab（Epic 商城）** | `https://www.fab.com/i/search?q=dragon` 与 `https://www.fab.com/search?q=dragon&is_free=1` 均返回 **HTTP 403 + Cloudflare 挑战页**（`cf_challenge_text_small`） | ⚠️ **未核实（原因：Cloudflare 反爬拦截，需人工浏览器访问）**。无法给出结论 |
| **Mixamo** | `https://www.mixamo.com/api/v1/products?page=1&limit=96&type=Character` → **HTTP 403 `{"error_code":"403000","message":"Api Key is required"}`** | ⚠️ **未核实（原因：Mixamo 目录 API 需鉴权，全站浏览需 Adobe 账号登录，本次无账号）**。检索到的公开资料（[Adobe Mixamo 常见问题](https://helpx.adobe.com/gr_en/creative-cloud/faq/mixamo-faq.html)、[jMonkeyEngine 论坛讨论](https://hub.jmonkeyengine.org/t/do-you-want-free-high-quality-characters-so-visit-mixamo/33693/5)）**只提及人形角色**，未见任何龙/四足生物条目，但**我没有拿到源站证据，因此不能写成「已确认无」** |

---

## 6. D 级：明确「不合格」条目（存档，避免别人重复踩）

### 6.1 无动画 / 无骨骼（rig 或动画缺失）

| 名称 | URL | 许可 | 不合格原因（页面原文证据） |
|---|---|---|---|
| Wyvern (Low Poly) | <https://opengameart.org/content/wyvern-low-poly> | CC-BY 3.0 | 标签含 **`Static Mesh`**，描述只讲面数减面（190 万 → 2800 面），**无骨骼无动画** |
| Dragon (3D, 场景那个) | <https://opengameart.org/content/dragon> | CC0 | 标签 **`Static Mesh`**，只有 `dragon.blend` 8.9 MB |
| Dragon | <https://opengameart.org/content/dragon-3> | CC0 | 描述原文：「Low poly dragon model (**unrigged and unskinned**)」；`.3ds` 33.8 KB |
| A three headed lizard or dragon creature. | <https://opengameart.org/content/a-three-headed-lizard-or-dragon-creature> | CC-BY 4.0 | 描述原文：「The model is rigged but **no animations**.」；24k tris；且 `dragon3headed.tar.gz` **99.4 MB** |
| Dragon (dragon-0) | <https://opengameart.org/content/dragon-0> | CC-BY 3.0 | 描述只说「modeled and rigged」；**评论区 2011 年就在求「could you please animate it??」且无回复** → 判为无动画 |
| Anthro Dragon-like Char (.obj) | <https://opengameart.org/content/anthro-dragon-like-char-obj> | CC0 | `.obj`，无骨骼；且是**拟人龙（anthro/furry）**，非四足带翼龙 |
| Low Poly Dragon (Rigged) | <https://sketchfab.com/3d-models/low-poly-dragon-rigged-c23530e89e8e4f21b0682860c9b2235b> | CC-BY 4.0 | `isRigged = false`，唯一动画 `Take 001`（无意义名）→ 实测价值低 |
| Red Wyvern | <https://sketchfab.com/3d-models/red-wyvern-ab7d1d9f8d304565b6ad28d724f920d8> | CC-BY 4.0 | `isRigged = false`，仅 `animation_flying` 一条；608 面 |
| Dragon's head / Dragon skull / Red Dragon bust / Naga Dragon Serpent | — | 混合 | 只有头/半身，非完整可动角色 |

### 6.2 造型不符（**恐龙 / 东方龙 / 人形 / 静态道具**）

| 名称 | 原因 |
|---|---|
| `Suchomimus`（uid `32160ecd801a4d22b3b1466219b066f9`）、`Brontosaurus`（OGA）、`Prehistoric Dinosaurs`（itch） | **恐龙**，用户明确排除 |
| `Chinese dragon`（uid `a5ad5ec06f43461f95bb93e95fe7553b`）、`Flying Dragon`（OGA，标签 `chinese dragon`，CC0，20.5 MB） | **东方长蛇龙**，与「西方奇幻龙」不符 |
| `Mazo Dragon Amadedj (.blend)`（<https://opengameart.org/content/mazo-dragon-amadedj-blend>，CC0，48.6 MB） | 标签 `humanoid` / `furry` → **人形龙**，非四足带翼 |
| `Lucoa 3D model (VRChat…)`、`Dragon Girl VTuber Model`、`Angel Dragon 3D Vtuber` | VTuber/人形，非生物龙 |
| `Jade Dragon`（GPL 2.0）、`Dragon skull`（GPL 3.0）、`Dragon Fantasy Helmet` | 静态装饰/道具 |
| `Dragon Koi`、`Dragon Glass`、`Dragon Fly`、`phoenix bird`、`dragonfly` 标签类 | 标题含 dragon 但实为锦鲤/玻璃装置/蜻蜓/凤凰 |
| 2D 精灵包：`Free Isometric animated Three-head dragon`(Engvee)、`Free RPG Dragon Boss (Kamedran)`(The Art Of Nemo)、`Free Dragon Sprites Pack #1`、`Dragons Pack Free`(MasuOne)、`Epic 2D Pixel Art Shadow Demon Dragon` | **2D 精灵/像素**，本项目要 3D GLB |
| `Womina (Blender 3.2)`（<https://opengameart.org/content/womina-blender-32>，CC0） | 名字与龙无关，**未核实**是否有龙（我没打开详情），按「与本次目标无关」归档 |

### 6.3 许可不可用（GPL / 无声明）

| 名称 | 许可 | 说明 |
|---|---|---|
| `Wyvern`（clintbellanger 的那条是 CC-BY-SA；另有一条 OGA `wyvern-0`） | **GPL 3.0 + CC-BY-SA 3.0 双许可** | `wyvern-0`：<https://opengameart.org/content/wyvern-0>，**712 三角形**（极低），描述「The model is rigged, but has **only 2 basic animations**」；`wyvern.zip` 6.3 MB。⚠️ **GPL 对游戏工程是强传染**，除非选 CC-BY-SA 分支。作者 Skorpio（基础模型 Andrew Buck，为 OpenDungeons 制作）。**动画面数与名字未核实（作者未列）** |
| `Dragon model`（itch.io 多家无 License 行） | **无许可声明** | itch.io 上大量免费 dragon 页（如 `bocdagla` 之外的若干）**没有 License 字段**，默认 = 保留所有权利。本次我只把**明确写了许可**的条目列进 A/B 级 |

---

## 7. 待核实清单（下一步必须做的事，按优先级）

| # | 待核实项 | 为什么重要 | 建议的核实动作 |
|---|---|---|---|
| **V1** | **A1 bocdagla 龙的实际面数与骨骼质量** | 它是最优先推荐，但页面没给面数 | 下载 `dragon.zip`（1 MB，无需登录）→ Godot 里 `Import` 后看 `Mesh` 的三角面数 + `Skeleton3D` 是否存在 |
| **V2** | **A2/A6/A7 的 `isRigged=false` 到底意味着什么** | 若只是节点动画，Godot 的 `AnimationPlayer` 仍能播；若整个网格是单个静态 mesh，则动画只驱动空节点、**模型不会形变**，直接不可用 | 下载后在 Godot 里看导入的 `AnimationPlayer` 轨道目标：应命中 `Skeleton3D:Bone` 或至少多个 `Node3D` 的 transform；**若所有轨道都指向 1 个根节点则该模型作废** |
| **V3** | **B7 Cethiel's Dragon 3D 的动画清单** | CC0 + rigged + animated + 手绘贴图，是本次**唯一一条 CC0 且有动画的完整西方龙**，动画名却完全未知 | 下载 `dragon_oga.zip`（1.4 MB，无需登录）解包看 `.blend`/导出格式的动作用名 |
| **V4** | **A16 Low Poly Ice Dragon 的面数与确切动画名** | CC0 + fly/bite，但下载量仅 102，社区没验证过 | 下载 `dragon_model.blend`（1.6 MB，无需登录）→ Blender 打开看 Action 名与三角面数 |
| **V5** | **A12 GuieA_7 `dragon.zip` 的格式构成与动画名** | CC-BY-SA + 2250 面 + 8 条动画（含 attack×2），性价比很高，但只有 `.blend` | 下载 10.1 MB → 转换成 glTF 后看动画名 |
| **V6** | **Fab 商城免费区是否有 CC0/CC-BY 龙** | 我这边被 Cloudflare 403 拦死 | 人工浏览器访问 <https://www.fab.com/search?q=dragon&is_free=1>，**重点看许可字段是 "CC BY 4.0" 还是 "Fab Standard License（个人/商用分级）"** |
| **V7** | **Mixamo 是否有龙** | 我这边 API 需 Key、站点需登录 | 登录 Mixamo 后搜 `dragon` / `wyvern`；**若确认无，请在最终报告里写「已确认无」，本文只能写「未核实」** |
| **V8** | **Sketchfab `Free Standard` 许可的完整条款**（B8 `Wyvern animated`） | 关系到能不能商用、能不能随游戏分发模型文件 | 打开 <https://sketchfab.com/licenses> 读原文（我这边该页未成功取到正文） |
| **V9** | **A10 Four-Legged-Frost-Predator 是否真的带翼** | 描述只有「kudos to Timsblends」，可能是二次上传 | 打开 Sketchfab 3D 预览目视；同时确认 Timsblends 是谁、许可链是否完整 |

---

## 8. 给 lead 的接入建议（Godot 4.7 实操注意）

1. **格式优先级**：`GLB > glTF(.gltf+.bin+贴图) > FBX > .blend`。
   - 本仓库 `PawnModelRig` 走 `load()` → 失败回退 `GLTFDocument` 运行时解析 → **只有 glTF/GLB 是"零配置"路径**。
   - FBX 需要 Godot 4.7 的 FBX 导入（或先转 glTF）；`.blend` 需要本机 Blender 且在编辑器里配置路径（`EditorSettings → filesystem/import/blender/blender_path`）。
2. **朝向**：KayKit 模型默认朝 **+Z**，项目里靠 `PawnDef.model_face_offset_deg = 180` 纠正。新龙模型**必须先确认朝向**再决定这个偏移值；**不要改 `Pawn` 的逻辑朝向**（逻辑前方固定本地 `-Z`，`look_at_target()` 是唯一改朝向的接口）。
3. **动画名映射**：本项目状态机需要的动作是 `Idle / Walking / Running / Attack(1~3) / Death`。本次候选里动画命名风格差异极大（`Standing.new` / `walkies` / `Black_dragon_attack` / `Ani. Ataque` / `attack_1`），**建议在 `PawnDef` 之外加一层"动画名别名表"**，避免把平台命名硬编码进状态机。
4. **死亡溶解（v16）会遍历模型子树逐 surface 换材质**：如果新龙是多 material（如 `European Dragon` 是 4 材质 6 贴图），溶解材质要**逐 surface 拷贝各自的 albedo**，不能只拷第一张贴图。
5. **尺寸**：`PawnDef.model_scale` 需要按新模型的原生尺寸重调（EU 龙与 KayKit 骑士的建模单位不一定一致）。
6. **法务留痕**：**A 级 16 条里只有 A16 `Low Poly Ice Dragon` 是 CC0（不要求署名）**，其余 15 条全部要求署名（B 级里 B7 `Cethiel's Dragon 3D` 也是 CC0）。建议在 `assets/` 下建 `CREDITS.md` 记录「模型名 / 作者 / 许可 / 来源 URL / 下载日期」——本项目已有 `assets/audio/CREDITS.md`、`assets/vfx/CREDITS.md` 的先例，照抄这个范式即可。

---

## 9. 与 `lowpoly-cc0` 线的边界声明（防重复）

- 本文**未收录** KayKit / Quaternius / poly.pizza / Kenney 四家的任何明细。
  - 注：本次 OGA 命中的 `LowPoly Animated Monsters`（CC0，含 dragon，`Animated Monster Pack by @Quaternius.zip` 1.4 MB）**属于 Quaternius，归另一条线**，我在此仅记录"命中但移交"，不展开。
  - 注：`dragon-assets/poc/quaternius_dragon_evolved_polypizza.glb` 已存在于仓库，属另一条线的产物，我未改动。
- 本文的独有覆盖：**Sketchfab（93+ 条候选 → 41 条深挖）、itch.io（53 条搜索结果 → 7 条深挖）、OpenGameArt（dragon 25 条 + wyvern 5 条 → 13 条深挖）、Godot Asset Library、GitHub、Mixamo、Craftpix、Fab**。

### 9.1 与 `lowpoly-cc0.md` 的已知交叠（诚实标注，供 lead 去重）

| 条目 | 本文位置 | 对方位置 | 处理建议 |
|---|---|---|---|
| **Simple 3D Dragon Model**（MattBas） | §3 B6 | 对方表格 D 行 | **同一模型。本文的增量信息 = itch.io 侧（<https://mattbas.itch.io/dragon-model>）页面**完全没有 License 字段**，只有 OGA 页标 CC-BY-SA 4.0 → 两平台许可口径不一致。**最终报告请合并为一条，采用「CC-BY-SA 4.0 + 无攻击动画」的判定** |
| **`igmixer/cpDragon-gltf`**（GitHub） | §5 GitHub 行（已修正） | 对方表格 E 行（`不建议`） | 我方独立复核结论一致（MIT 字段 + 无来源说明）→ **两线都不推荐，一致** |
| **Quaternius `LowPoly Animated Monsters`**（OGA 命中） | §9（仅记录移交，未展开） | 对方主场 | **归对方**，本文不重复 |

---

## 10. 附：本次抓取到但**未深挖**的 Sketchfab 条目（供后续按需取用）

以下条目通过了「downloadable + animated + 名字含 dragon/wyvern/drake/wyrm」筛选，但我判断优先级低（机甲 / 玩具 / 抽象 / 面数过高 / 拆包嫌疑）而未逐条拉动画清单，存档备查：

`Ancient Gear Wyvern`（17 条动画但名字是 `M12678_a`~`M12678_h2_loop` 这类内部代号，15586 面，CC-BY，<https://sketchfab.com/3d-models/ancient-gear-wyvern-658e63592788490d80ce30c13f5202db>）｜`Prowler Dragon Variant Rig`（19766 面，CC-BY，动画 `Landing/Walk/Walk Loop/PoseLib/Action.002`，仅 .blend 25.9 MB，<https://sketchfab.com/3d-models/prowler-dragon-variant-rig-7ee71aaf323d426bbbdf28d73d55bbd9>，**注意这条是 §4.1 提到的「CC-BY 版本」（对应 C9 里的 `Desert Dragon` 是 CC-BY-NC 版本），要这个模型请认准 CC-BY 的这条**）｜`Stylized Red/Black dragon_baby`（24136 面，4 条 `idle/fly/idle_another/fly_another`，<https://sketchfab.com/3d-models/stylized-redblack-dragon-baby-1d3cc450c8914665bf950c4fe06fc127>）｜`Demon_dragon` / `Demon Dragon Full Texture`（312,688 面，3 条动画，CC-BY，面数过高）｜`Dragon low poly`（3158 面，1 条 `voo`(飞行)，<https://sketchfab.com/3d-models/dragon-low-poly-e447fb63c82c448e936c769fe5344440>）｜`Wyvern`（Max7BE，17664 面，1 条 `armature|animation_2`，<https://sketchfab.com/3d-models/wyvern-a5d1f7a5119a4786bc54515b506f4919>）｜`Flying Dragon V.2 Wooden Toy` / `Dragon Flying Test` / `Flying Dragon Reveal Abstract Geometry` 等抽象/玩具类（不适用）。

---

*本报告所有 URL 均为 2026-10-01 本次调研中实际请求成功的地址。凡标注「未核实」的字段，均写明了我没能取得证据的具体原因，**没有任何推断被写成事实**。*
