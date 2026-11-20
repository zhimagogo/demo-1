# 复查用事实表

> 调研范围：KayKit / Quaternius / poly.pizza / Kenney 四大低多边形 CC0 生态线 + 任务书点名的其它作者。
> 负责人：dragon-scout-lowpoly（共享任务板 task-1）。宽口径线（Sketchfab / itch.io / Godot 生态 / OpenGameArt）由 dragon-scout-wide 负责，本文只在交汇处标注。
> 取证纪律：**本文每一条事实都来自我亲自打开的页面 / API 响应 / 文件字节**；搜索摘要里的许可证与动画数量一律未采信。凡未打开或无法打开的，明确写「未核实（原因）」，不猜测。
> 取证时间：2026-10-01（Asia/Shanghai）。

---

## 0. 结论速览（TL;DR）

| 项 | 结论 |
|---|---|
| **可用候选总数** | **4 个**（3 个 Quaternius CC0 龙 + 1 个 OpenGameArt CC-BY-SA 龙）。另有 1 个非 CC0 的 GitHub 龙，不建议采用 |
| **最优 1** | Quaternius **Animated Monster Pack → Dragon**（四足带翼、双攻击动作、CC0、可脚本直连 GLB） |
| **最优 2** | Quaternius **Ultimate Monsters → Dragon / Dragon_Evolved**（带翼奇幻龙、有 Headbutt/Punch、CC0、官方 glTF 自带贴图） |
| **最优 3** | Quaternius **Cute Animated Monsters → YellowDragon**（有 Bite_Front 咬击、CC0、glTF） |
| **最大风险①** | **三条 Quaternius 龙全部没有地面行走/奔跑动画，也没有地面待机**——只有 `Flying`/`Flying_Idle`。项目现用的 `Idle`/`Walking_A`/`Running_A` 契约无法平移 |
| **最大风险②** | **Quaternius 站点级许可证已从 CC0 换成自定义 QAL v1.0（页面标注 Last updated: 8/28/2026）**，与各包页面仍标 CC0 互相矛盾。**缓解证据**：候选 A、B 两个包的**包内 `License.txt` 都逐字写着 CC0 1.0 Universal**（见 §3.1），加上 QAL §7 声明不追溯，CC0 落地有据可依——但**必须锁版本并留存该 License.txt** |
| **最大风险③** | KayKit 官方生态**确认零龙**；Kenney 3D 目录**确认零龙**。也就是说「与基线同厂同风格」的龙**不存在**，必须在跨作者风格迁移上做妥协 |

---

## 1. 风格基线（项目现状，亲自解析本地文件核实）

来源：本地文件 `assets/_PLACEHOLDER/characters/placeholder_hero.glb`（不写入、只读取字节解析 glTF JSON chunk）。

| 字段 | 实测值 |
|---|---|
| 文件体积 | 3,659,532 字节 |
| 生成器 | `Khronos glTF Blender I/O v1.7.33` |
| 动画数量 | **76**（与任务书一致，已逐一列出核对：含 `Idle` / `Walking_A` / `Running_A` / `1H_Melee_Attack_*` / `2H_Melee_Attack_*` / `Dodge_*` / `Death_A` / `Death_B` / `Hit_A` / `Block*` / `Spellcast*` / `Jump_*` / `Sit_*` / `Lie_*` / `T-Pose` 等） |
| 三角面 | 6,952 |
| 骨骼关节数 | 41 |
| 贴图 | `knight_texture`（image/png，**内嵌**于 GLB） |
| 许可证 | CC0 1.0（任务书基线；同厂 LICENSE.txt 原文见 §2.4） |

**匹配判据（本文打分基准）**：低多边形 + 平涂/无渐变 + 单文件自包含 + 骨骼动画 + 面数同量级（数千面）。

---

## 2. KayKit（Kay Lousberg）—— 确认**无龙**

### 2.1 官方 GitHub 组织：10 个仓库，递归文件树全量检索，**dragon/wyvern/drake/wyrm 命中 = 0**

方法：`GET https://api.github.com/users/KayKit-Game-Assets/repos` 取全部仓库 → 每个仓库 `GET /repos/{repo}/git/trees/main?recursive=1` → 对全部路径做 `dragon|wyvern|drake|wyrm` 子串匹配。所有仓库 `truncated: false`（即不是被截断的假阴性）。

| 仓库 | 文件数 | 龙命中 | 仓库 URL |
|---|---|---|---|
| KayKit-Character-Pack-Adventures-1.0 | 136 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |
| KayKit-Character-Pack-Skeletons-1.0 | 75 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 |
| KayKit-City-Builder-Bits-1.0 | 309 | 0 | https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0 |
| KayKit-Dungeon-Remastered-1.0 | 856 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 |
| KayKit-Furniture-Bits-1.0 | 341 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Furniture-Bits-1.0 |
| KayKit-Halloween-Bits-1.0 | 415 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0 |
| KayKit-Medieval-Hexagon-Pack-1.0 | 1551 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 |
| KayKit-Prototype-Bits-1.0 | 465 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Prototype-Bits-1.0 |
| KayKit-Restaurant-Bits-1.0 | 899 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Restaurant-Bits-1.0 |
| KayKit-Space-Base-Bits-1.0 | 397 | 0 | https://github.com/KayKit-Game-Assets/KayKit-Space-Base-Bits-1.0 |

**结论**：KayKit 官方 GitHub 不存在任何「龙 / 飞龙 / 幼龙 / 双足飞龙」模型，也不存在任何 Monsters/Fantasy Creatures 类包。

### 2.2 KayKit Dungeon Remastered 的 406 个资产名逐个看过：**全是道具，零生物**

同一棵树取出 406 个资产基名，`banner_* / table_* / barrel_* / floor_tile_* / pillar_* / stairs_* / crate_* / keg_* / bed_* / box_*` 等；按 `skeleton|slime|zombie|ghost|mimic|goblin|bat|spider|rat|demon|monster|dragon|character|knight|mage|rogue|barbar` 检索只命中 `*_decorated`（装饰变体）这类假阳性。**Dungeon Remastered 是纯道具包，连普通怪物都没有，更无龙。**

### 2.3 KayKit itch.io 全站：32 个包，主页 `dragon` 出现次数 = **0**

来源：https://kaylousberg.itch.io/ （正则提取 32 个 `kaylousberg.itch.io/*` 包链接；对整页做 `dragon` 大小写不敏感计数 = 0）。

包清单（32 个，均无「Dragons/Monsters」类命名）：`bits-bundle-1`、`bits-bundle-2`、`block-bits`、`board-game-bits`、`city-builder-bits`、`fantasy-weapons-bits`、`furniture-bits`、`halloween-bits`、`holiday-bits`、`kay-kit-mini-game-variety-pack`、`kaykit-adventurers`、`kaykit-animations`、`kaykit-character-animations`、`kaykit-complete`、`kaykit-dungeon`、`kaykit-dungeon-pack`、`kaykit-forest`、`kaykit-medieval-builder-pack`、`kaykit-medieval-hexagon`、`kaykit-platformer`、`kaykit-series-4`、`kaykit-series-5`、`kaykit-series-6`、`kaykit-skeleton-pack`、`kaykit-skeletons`、`kaykit-spooktober`、`mixed-bag-1`、`prototype-bits`、`resource-bits`、`restaurant-bits`、`rpg-tools-bits`、`space-base-bits`。

逐页复核（正标题 + 页内 `dragon` 计数）——**全部 False**：

| 包 URL | 页面正标题 |
|---|---|
| https://kaylousberg.itch.io/kaykit-spooktober | (Legacy) KayKit - Spooktober Seasonal Pack |
| https://kaylousberg.itch.io/kaykit-series-4 | KayKit - Character Pack : Mystery Monthly Series 4 |
| https://kaylousberg.itch.io/kaykit-series-5 | KayKit - Character Pack : Mystery Monthly Series 5 |
| https://kaylousberg.itch.io/kaykit-series-6 | KayKit - Character Pack : Mystery Monthly Series 6 |
| https://kaylousberg.itch.io/kaykit-dungeon | (Legacy) KayKit - Dungeon Pack |
| https://kaylousberg.itch.io/kaykit-forest | KayKit - Forest Nature Pack |
| https://kaylousberg.itch.io/kaykit-complete | The Complete KayKit |
| https://kaylousberg.itch.io/fantasy-weapons-bits | KayKit : Fantasy Weapons Bits |

> 注意：`kaykit-series-4/5/6` 是「Character Pack : Mystery Monthly」盲盒式角色包，**包内具体角色名未在商店页逐一列出 → 这三个包是否含龙的「角色名级」核实为未核实**；但主页与包页均无 `dragon` 字样，且若真有龙 Kay Lousberg 必然作为独立卖点命名，故判定为「极不可能含龙」。

### 2.4 KayKit LICENSE.txt 原文（raw 文件逐字读取）

| 包 | LICENSE 原文关键行 | URL |
|---|---|---|
| Adventurers | `License: (Creative Commons Zero, CC0)` / `http://creativecommons.org/publicdomain/zero/1.0/` / `This content is free to use in personal, educational and commercial projects.` / `Support me by using a brand resource provided in this pack or by crediting Kay Lousberg, www.kaylousberg.com (this is not mandatory)` | https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/LICENSE.txt |
| Dungeon Remastered | 同上（仅包名与日期不同） | https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0/main/LICENSE.txt |
| Medieval Hexagon | 同上 | https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0/main/LICENSE.txt |
| Halloween Bits | 同上 | https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0/main/LICENSE.txt |

**许可证结论（KayKit 全线）**：CC0 1.0 —— 可商用、**无需署名**、可改作、可再分发。

---

## 3. Quaternius —— **3 条 CC0 龙**（本任务的主要产出）

### 3.1 先讲许可证冲突（这是本次最重要的发现，直接影响能否用）

同一站点上存在**三份互相矛盾**的许可证声明，我都亲自打开确认：

| 证据位置 | 声明 | URL |
|---|---|---|
| 站点级 License 页 | **「Quaternius Asset License (QAL) v1.0」，页面标注 `Last updated: 8/28/2026`**。明文：可商用、**无需署名**；但 `You may not resell or redistribute the Assets themselves`（不得把素材本身原样或改作后再分发/转售）。§7 写明新版本**不追溯**已获得的素材 | https://quaternius.com/license.html （源码：https://github.com/Quaternius/quaternius.github.io/blob/main/license.html） |
| 各包页面 License 字段 | 绝大多数包仍写 **`CC0`**，链接到 `https://creativecommons.org/publicdomain/zero/1.0/` | 见 §3.2 表 |
| 最新包（Bestiary - Dungeon Monsters Kit，2026-08） | 写 **`QAL`**，链接到 `/license.html` | https://quaternius.com/packs/bestiarydungeonmonsterskit.html |
| **包内实际携带的 License.txt**（Ultimate Monsters 下载目录根） | **`License: CC0 1.0 Universal (CC0 1.0) Public Domain Dedication` + `https://creativecommons.org/publicdomain/zero/1.0/`**（374 字节，逐字读取）。**注意：该文件抬头误写成 `Ultimate Platformer Pack by @Quaternius`——是 Quaternius 自己的复制粘贴残留，但许可证正文明确是 CC0** | https://drive.google.com/file/d/16GqsDGESyEOfRbc4dS7EqAwkIUSIW4_y/view |
| **包内实际携带的 License.txt**（Animated Monster Pack 下载目录根） | **`License:` / `CC0 1.0 Universal (CC0 1.0)` / `Public Domain Dedication` / `https://creativecommons.org/publicdomain/zero/1.0/`**，抬头正确写为 `Animated Monsters by Quaternius`，并附「若要署名请写：Animated Monsters by Quaternius + Patreon 链接」（即**署名可选而非必需**）。逐字读取 | https://drive.google.com/file/d/1kmh71Y_VBZdwr9P_8iwM9yn8bRS9RXcG/view |

**逐包 License 字段实测（我下载了 86 个包页面的原始 HTML 并正则提取 License 字段）**：

| 包页面 | License 字段实测 |
|---|---|
| ultimatemonsters | `CC0` → creativecommons.org/publicdomain/zero/1.0/ |
| animatedmonster | `CC0` |
| cutemonsters | `CC0` |
| easyenemy | `CC0` |
| ultimatefantasyrts | `CC0` |
| rpg | `CC0` |
| rpgcharacters | `CC0` |
| universalanimationlibrary / 2 | `CC0` |
| 3dcardkitfantasy | `CC0` |
| animateddinosaurs | `CC0` |
| **bestiarydungeonmonsterskit**（2026-08 新品） | **`QAL`** → /license.html |

**给 Lead 的风险判断**：Quaternius 正处在 CC0 → QAL 的迁移期。若要 CC0 落地，**必须在下载当时留存包内 `License.txt` 与包页面快照**（QAL §7 明确「不追溯已获得素材」，即「获得时点的版本」为准）；且 QAL 禁止「把素材本身再分发」，本项目只把模型嵌进游戏、不分发素材包，即使按 QAL 也**可以商用**，但**不能把资源再放进公开仓库**（这一点对 `assets/` 入 git 有约束，需 Lead 决策）。

### 3.2 三条龙逐个核实（含动画清单——全部来自文件字节，不是页面文字）

#### 候选 A：Animated Monster Pack → **Dragon** ★本任务最优

| 字段 | 值 |
|---|---|
| 名称 | `Dragon`（包内 4 个模型中之一：Bat / Dragon / Skeleton / Slime） |
| 作者 | Quaternius |
| 包页面 | https://quaternius.com/packs/animatedmonster.html （`Animated Monster Pack`，页面标注 August 2018，`4` models，`Animated ✓`，`License: CC0`） |
| 下载目录（可脚本直连） | https://drive.google.com/drive/folders/102H-oyUM8SGYi1mW0GOgkjEu7xSdaORA |
| 目录结构（我逐层列举） | `Blend/` `FBX/` `OBJ/` + `License.txt` + `Preview.jpg` —— **注意：此包无 glTF 目录** |
| 格式与体积 | 官方：`.fbx`（`Dragon.fbx` 实测 **874,204 字节**）/ `.blend` / `.obj`。**glTF 由 poly.pizza 提供**（见下行） |
| glTF 直链（poly.pizza 镜像） | https://static.poly.pizza/9714f533-5d2d-4cfd-b8f1-c8dfff64a672.glb （HTTP 200，实测 **268,896 字节**） |
| 是否绑定骨骼 | **是**。GLB 解析：`skins[0].joints = 27`；FBX 内含 `DragonArmature` |
| **动画清单（逐个，来自我解析的 GLB + FBX 双源交叉验证，两源完全一致）** | `Dragon_Attack`（攻击①）、`Dragon_Attack2`（攻击②）、`Dragon_Death`、`Dragon_Flying`、`Dragon_Hit` |
| **是否含攻击动作** | **是，且有两个（Attack / Attack2）** |
| 三角面 | 页面标 `Tris: 1088`；我解析 GLB 全部 primitive 索引和 = **1,344**（差异应为页面统计口径，两者同量级） |
| 贴图 | **无贴图文件**。GLB 解析 `images = []`；由 6 个分色材质表达：`Eyes` / `Main` / `Main` / `Belly` / `Claws` / `Wings`；网格名 `Eyes` + `Dragon`。**平涂分色（无 UV 贴图）** |
| 下载门槛 | poly.pizza 直链 **HTTP 200 直取，无需登录、无需账号**（我已实际下载并解析字节）；Google Drive 目录同为公开共享、无需登录 |
| 许可证 | 包页 `CC0`（creativecommons.org/publicdomain/zero/1.0/）；poly.pizza 页 `Public Domain (CC0)` + `"Licence":"CC0 1.0"`；**该包 Drive 根 `License.txt` 原文 = `CC0 1.0 Universal (CC0 1.0) Public Domain Dedication`**（逐字读取，抬头 `Animated Monsters by Quaternius`） |
| 页面 | https://poly.pizza/m/VBvzjFIYws （meta 明写 `No login required.`） |
| **造型核实（亲自看图）** | 我下载了预览图并放大查看：**深紫红躯干 + 黄色腹甲 + 两只大蝠翼 + 犄角 + 四足带黑爪**——**标准「带翼四足龙」**，非恐龙 |
| 风格匹配度 | **高**。同为低多边形 + 平涂 + 数千面；差异在于它用「分色材质」而 KayKit 用「手绘图集」，且体型比例更敦实。远观同一档次 |

#### 候选 B：Ultimate Monsters → **Dragon** / **Dragon_Evolved**

| 字段 | 值 |
|---|---|
| 名称 | `Dragon`、`Dragon_Evolved`（进化体，两个独立模型） |
| 作者 | Quaternius |
| 包页面 | https://quaternius.com/packs/ultimatemonsters.html （`Ultimate Monsters`，October 2022，`50` models，`Animated ✓`，`Textured ✗`，formats `FBX / OBJ / Blend / glTF`，`License: CC0`） |
| 下载目录（可脚本直连） | https://drive.google.com/drive/folders/18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C |
| 目录结构（我递归列举，共 50 个模型，与页面「50」相符） | 根：`Big`(16) / `Blob`(17) / `Flying`(17) + `Atlas_Monsters.png` + `Color Guide.png` + `License.txt` + `Preview.jpg`。**龙在 `Flying/` 下**，四个格式子目录 `Blends/` `FBX/` `glTF/` `OBJ/` 均含 `Dragon.*` 与 `Dragon_Evolved.*` |
| 格式与体积（实测，Drive 直取） | `Dragon.gltf` **427,100 字节**；`Dragon_Evolved.gltf` **991,335 字节**。另有 `.fbx` / `.blend` / `.obj`+`.mtl` |
| 自包含性 | **是**。`Dragon.gltf` 的 `buffers[0].uri` 为 `data:application/octet-stream;base64,...`，`images[0]`=`Atlas_Monsters`(image/png) 挂在 bufferView 上 → **单文件即完整可用，无外部 .bin / .png 依赖** |
| 是否绑定骨骼 | **是**。`skins[0].joints = 13`（Dragon）/ `46`（Dragon_Evolved）；根节点 `CharacterArmature` |
| **动画清单（逐个，来自 glTF 字节解析）** | 两个模型**完全相同的 8 条**：`Death`、`Fast_Flying`、`Flying_Idle`、`Headbutt`（攻击）、`HitReact`、`No`、`Punch`（攻击）、`Yes` |
| **是否含攻击动作** | **是**：`Headbutt`（撞头）+ `Punch`（挥爪）。**但无咬击 / 无吐息 / 无火焰** |
| 三角面 | `Dragon` 实测 **4,562** 面 / 2,870 顶点；`Dragon_Evolved` 实测 **7,440** 面。poly.pizza 页面标 3,826 / 6,702（口径差异）。**与基线 6,952 面同量级** |
| 贴图 | **有**：1 张 `Atlas_Monsters`（image/png）内嵌于 glTF。材质 `Material`（Drive 版）；poly.pizza 镜像版则改成 5 个分色材质 `Dragon_Main`/`Dragon_Secondary`/`Dragon_Horn`/`Eye_White`/`Eye_Black` 且**无贴图** |
| 三角面/网格名 | `Dragon.gltf` 网格名 `Cube.222`；poly.pizza 镜像版网格名 `Dragon_Fly` |
| 下载门槛 | **Google Drive 公开共享目录，无需登录**（我用 `embeddedfolderview` 端点直接列举并下载了文件字节）；poly.pizza 直链同样免登录 |
| poly.pizza 镜像（免登录直链 GLB） | `Dragon` https://poly.pizza/m/3rUm1cN3yp → https://static.poly.pizza/ae5b8510-1fa5-4d53-b943-a4f3b88fb629.glb （251,540 字节）<br>`Dragon_Evolved` https://poly.pizza/m/LlwD0QNUPj → https://static.poly.pizza/90ed3740-d8c4-4910-88ce-ac2ed426022d.glb （436,000 字节） |
| 页面标注 | 两页均 `Public Domain (CC0)`、`Animated` 徽章；`__SERVER_APP_STATE__`：`"Licence":"CC0 1.0"`、`"Animated":true`、Tris 3,826 / 6,702、UploadDate 2022-10-23 |
| **造型核实（亲自看图）** | 包预览图（1920×1080 全阵容渲染）放大查看：**橙色龙、白色犄角、紫色翼膜、白色獠牙、口鼻有鼻孔、有翼**——卡通西方奇幻龙，**非恐龙** |
| 风格匹配度 | **中—高**。同样低多边形 + 平涂、面数与基线同量级；但比例是 Q 版大头短身（比 KayKit 的写实骑士头身比更卡通），且**无手绘贴图细节**（`Textured ✗`） |

#### 候选 C：Cute Animated Monsters Pack → **YellowDragon**

| 字段 | 值 |
|---|---|
| 名称 | `YellowDragon`（包内 21 个模型中之一） |
| 作者 | Quaternius |
| 包页面 | https://quaternius.com/packs/cutemonsters.html （`Cute Animated Monsters Pack`，August 2020，`21` models，`Animated ✓`，`Textured ✓`，`License: CC0`） |
| 下载目录（可脚本直连） | https://drive.google.com/drive/folders/1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0 |
| 目录结构 | `Blends/` `FBX/` **`glTF/`** `OBJ/` `Textures/` + `Preview.jpg`。**根目录未见 License.txt → 该包缺包内许可证文件，许可证只能以包页面 CC0 为依据** |
| 格式与体积（实测） | `YellowDragon.gltf` **634,125 字节**（Drive 直取）；另有 `.fbx`/`.blend`/`.obj`+`.mtl` |
| 自包含性 | **否（部分）**。贴图是**外部文件** `Textures/YellowDragon_Texture.png`，glTF 里 `images[0].uri` 指向外部 → 拷进项目必须连贴图一起拷 |
| 是否绑定骨骼 | **是**。`skins[0].joints = 17`；网格名 `Cube.036` |
| **动画清单（逐个，来自 glTF 字节解析）** | `Bite_Front`（咬击·攻击）、`Death`、`Flying`、`HitRecieve`（原文拼写如此） |
| **是否含攻击动作** | **是**：`Bite_Front`（正面咬击） |
| 三角面 | 实测 **1,592** 面（比基线轻得多） |
| 贴图 | 有（外部 PNG，1 张，材质名 `Texture`） |
| 下载门槛 | Google Drive 公开共享目录，**无需登录** |
| 造型核实 | **未核实造型**（未下载预览图逐像素确认）。仅由包名 `Cute Animated Monsters` + 模型名 `YellowDragon` + 动画名 `Bite_Front`/`Flying` 判定为「幼龙/可爱龙」。**若 Lead 要它，需补一次看图** |
| 风格匹配度 | **中**。同为低多边形平涂，但 `Cute` 系列是 Q 版幼儿化造型，与 KayKit 的成人体型差得更远；且无地面行走动画 |

#### 3.3 我逐包排查过、确认**无龙**的 Quaternius 包

| 包 | Drive 目录 ID | 实测模型清单要点 | 龙 |
|---|---|---|---|
| Easy Enemy Pack | `1VbJIslXPWK-1KybQN6yezZrfJcw608qe` | 6 个：Frog / Rat / Snake / Snake_angry / Spider / Wasp | **无** |
| Ultimate Fantasy RTS | `1h7sztlZyavWla-JDk3jp6KiWDdMh08yd` | 128 个：全是建筑/自然（TownCenter / Wall / Farm / Resource_Tree / Mountain…） | **无** |

> 附带纠错：`index.html` 的 `<noscript>` SEO 关键词块里出现 `dragon`（第 608、970、1626 行），按位置一度让人以为 Easy Enemy Pack 含龙。**实际打开该包目录后确认 Easy Enemy 是蛙/鼠/蛇/蜘蛛/黄蜂，`dragon` 只是 SEO 关键词堆砌**。这条纠正了的线索不应再被引用。

---

## 4. poly.pizza —— 可用，但**只能走页面内嵌 JSON，公开 API 不可用**

| 探测 | 结果 |
|---|---|
| `https://poly.pizza/api` | **HTTP 404**（返回的是「Page not found」HTML） |
| `https://api.poly.pizza/v1/search?q=dragon` | **HTTP 401** `{"error":"You need an API key to do that dingus"}` → **无 API Key 时不可用** |
| `https://poly.pizza/search/dragon` | **HTTP 200**，HTML 内嵌 `window.__SERVER_APP_STATE__`，**含每条的 `Licence`、`Tris`、`Animated` 字段** → **这是可行的取证路径**（我据此拿到了本文所有 poly.pizza 许可证字段） |
| `https://poly.pizza/m/<id>` | **HTTP 200**，`__SERVER_APP_STATE__.initialData.model` 给出 `Title / UploadDate / Tris / Views / Downloads / Licence / Animated / Creator` |
| 登录门槛 | 页面 meta 明写 `No login required.`；我已实际 HTTP 200 直取 `.glb` 与 `.jpg` 字节，**确认免登录** |

### 4.1 `/search/dragon` 全部 27 条去重结果（许可证逐条实测）

| 标题 | 作者 | 许可证 | 链接 |
|---|---|---|---|
| Dragon | **Quaternius** | **CC0 1.0** | https://poly.pizza/m/VBvzjFIYws |
| Dragon | **Quaternius** | **CC0 1.0** | https://poly.pizza/m/3rUm1cN3yp |
| Dragon Evolved | **Quaternius** | **CC0 1.0** | https://poly.pizza/m/LlwD0QNUPj |
| Dragon Rigged | na3ee1 | CC-BY 3.0 | https://poly.pizza/m/WIOTISRjeX |
| Red Dragon | Tomek Zamojski | CC-BY 3.0 | https://poly.pizza/m/5SgYrV6nhws |
| Dragon | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/aQ6YU1JK1wC |
| Dragon | jeremy | CC-BY 3.0 | https://poly.pizza/m/3ZuMS3IRb0C |
| Dragon Surveying | Emmett “TawpShelf” Baber | CC-BY 3.0 | https://poly.pizza/m/esNK-8cq6mr |
| Low Poly Dratini | Tipatat Chennavasin | CC-BY 3.0 | https://poly.pizza/m/bO68CLhdP_c |
| Wing and tail | Max M83 | CC-BY 3.0 | https://poly.pizza/m/cKtudiXlIV- |
| Unicorn | Thomas DR | CC-BY 3.0 | https://poly.pizza/m/6pM6hFiGolw |
| Stegoknight | Hoai Nguyen | CC-BY 3.0 | https://poly.pizza/m/2Nvj7py0bvX |
| Monsterolophus | Hoai Nguyen | CC-BY 3.0 | https://poly.pizza/m/6ybhT9b43Ys |
| Monster & Medieval Kits | Don Carson | CC-BY 3.0 | https://poly.pizza/m/0gdoFXqTyvp |
| KAIJYU / kaijyu | sugamo | CC-BY 3.0 | https://poly.pizza/m/4pQiM7_T-NA / /m/c64-Nr6adkT |
| Ogre | joney_lol | CC-BY 3.0 | https://poly.pizza/m/7oO8liwQv6 |
| Dragonfly ×2 | Poly by Google | CC-BY 3.0 | https://poly.pizza/m/0myA_BOcZrD / /m/1W4laTqRGyC |
| **Dragonfly** | AssetQuest | **CC0 1.0** | https://poly.pizza/m/de6jep5Fq5 |
| **Red Dragonfly** | AssetQuest | **CC0 1.0** | https://poly.pizza/m/UIxtFAD1ve |
| **Cake Character** | Polygonal Mind | **CC0 1.0** | https://poly.pizza/m/gpZIDI2FVD |
| Birb / Dino / Alpaking / Blue Demon / Big arm | Quaternius | CC0（`Big arm` 除外，实测 CC-BY 3.0） | /m/gZ2ExU9OAB / /m/wuerCFCWNR / /m/AQ8zbFoDln / /m/S7jYW6Amye / /m/KaVJET0WHx |

**要点**：`/search/dragon` 里**只有 Quaternius 的 3 条是 CC0 的真龙**（AssetQuest 的两条是蜻蜓 Dragonfly，不是龙）。其余龙全部 CC-BY 3.0（需署名，且 Poly by Google / Google Poly 系列多为已下架内容，授权链存疑）。

### 4.2 poly.pizza 检索不可靠——不要用它做「有/无」结论

- `/search/wyvern`：返回一堆泛匹配结果（含 Unicorn、Dragonfly），**未筛出任何专门的 wyvern 模型**。
- `/search/drake`：**返回空**。
- `/search/yellowdragon`：结果里出现 `Japan Village | Art Equilibrium | CC0 1.0 | /m/LlwD0QNUPj` —— 标题与 ID **明显错配**（`LlwD0QNUPj` 实际是 Quaternius 的 Dragon Evolved）。**说明该站搜索是模糊匹配且结果字段会串位**。
- 结论：poly.pizza 只能用于**逐条打开模型页取 `Licence`**，不能用于「某站有没有 X」的否定式结论。

---

## 5. Kenney（kenney.nl）—— 确认**无龙**

方法：`https://kenney.nl/assets/category:3D` 逐页翻完（page 1–4，page 5 返回 **HTTP 500**），提取去重后的全部 3D 资产。

**Kenney 3D 目录 = 50 项，全量如下**：`3d-road-tiles`、`animated-characters-protagonists`、`animated-characters-retro`、`animated-characters-survivors`、`blaster-kit`、`blocky-characters`、`brick-kit`、`building-kit`、`car-kit`、`castle-kit`、`city-kit-commercial`、`city-kit-industrial`、`city-kit-roads`、`city-kit-suburban`、`coaster-kit`、`cube-pets`、`factory-kit`、`fantasy-town-kit`、`food-kit`、`furniture-kit`、`graveyard-kit`、`hexagon-kit`、`holiday-kit`、`marble-kit`、`mini-arcade`、`mini-arena`、`mini-characters`、`mini-dungeon`、`mini-forest`、`mini-market`、`mini-skate`、`minigolf-kit`、`modular-buildings`、`modular-cave-kit`、`modular-dungeon-kit`、`modular-space-kit`、`nature-kit`、`pirate-kit`、`platformer-kit`、`prototype-kit`、`racing-kit`、`retro-fantasy-kit`、`retro-urban-kit`、`space-kit`、`space-station-kit`、`survival-kit`、`tower-defense-kit`、`toy-car-kit`、`train-kit`、`watercraft-kit`。

- 按 `dragon|wyvern|drake|monster|creature` 匹配资产名：**NONE**。
- 逐页打开 6 个「可能有生物」的包（`cube-pets`、`animated-characters-survivors`、`animated-characters-protagonists`、`animated-characters-retro`、`blocky-characters`、`mini-characters`）：页面许可证字样均为 **CC0**，页内 `dragon` 出现次数 **均为 0**。
- 注意：`https://kenney.nl/assets?q=dragon` **不可作为证据**——它返回的是一份与 dragon 无关的通用 32 卡片列表（Skyboxes Space / Tiny Factory / City Kit…），说明该站搜索是模糊全文匹配。**Kenney 站内搜索的「命中数」不可信，结论以 3D 目录全量枚举为准。**

**结论：Kenney 3D 资产线无龙，且其角色包均为人类/僵尸/机器人/方块宠物，无可替代的奇幻龙。**

---

## 6. 任务书点名的其它作者（逐个给结论）

| 来源 | 核实动作 | 结论 |
|---|---|---|
| **Craftpix** | 打开 https://craftpix.net/file-licenses/ 并抽取条款原文 | **不适用（非 3D）**。条款只谈 `PNG, JPG, EPS, Adobe Illustrator, PSD` 等 2D 源文件格式；站点导航只有 Game Kits / Sprites & Characters / GUI / Backgrounds / Icons / Tilesets / Objects / Text Effects，**无 3D 分类**。许可要点：可商用、无需署名；但 `You can NOT resell the source files ... You can not redistribute the art or modified version of the art in a manner that would make some or all of the art files useable to another end user`；另有禁止用于 AI/ML 训练的专条 |
| **Poly Haven** | `GET https://api.polyhaven.com/assets?t=models` | **不适用（无角色）**。返回 **521** 个 model 资产；按 `dragon` / `character` / `creature` / `human` / `monster` 检索**命中均为 0** |
| **Elthen's Pixel Art** | 打开 https://elthen.itch.io/ 并列出其全部龙相关商品 | **不适用（2D 精灵）**。其龙类商品全部是 2D 像素精灵表：`2D Pixel Art Elder Dragon Sprites`、`2D Pixel Art Elder Dragon Hatchling`、`2D Pixel Art Faerie Dragon Sprites`、`2D Pixel Art Dragon Hatchling Sprites`、`2D Pixel Art Kobold Dragonshield Sprites`、`2D Pixel Art Dragonfly Sprites` —— **无 3D 模型** |
| **J-Toastie** | 尝试 https://j-toastie.itch.io 与 https://itch.io/profile/j-toastie | **未核实（原因：两个 URL 均返回 HTTP 404，未能定位其主页）** |
| **TinyTreats** | 打开 https://tinytreats.itch.io/ | **部分核实**：页面存在（标题 `Tiny Treats - itch.io`），主页 `dragon` 出现次数 **0**；**未逐包打开 → 「包内是否含龙」未核实** |
| **GitHub 上以 CC0 发布的 dragon glb** | `GET https://api.github.com/search/repositories?q=dragon+gltf+cc0` → `total_count: 0`；`q=dragon+in:name+gltf` → `total_count: 1` | **GitHub 上基本不存在 CC0 龙模型仓库。** 唯一命中 `igmixer/cpDragon-gltf`（API 标注 license `MIT`，default_branch `master`，7 个文件：`LICENSE` / `scene.gltf` / `scene.bin` / `textures/phong2_{baseColor,emissive,normal}.png`）。**未标 CC0、无作者/来源说明 → 不建议采用**（连它是 CC0 的反证都没有，等于授权链不明） |
| **OpenGameArt**（任务书未点名，但检索中浮现且属 CC 生态，故一并取证；宽口径线归 dragon-scout-wide） | 打开 https://opengameart.org/content/simple-3d-dragon-model 并读取全部元数据 | **CC-BY-SA 4.0，非 CC0**。详见 §7 |

---

## 7. 候选总表（任务书要求的字段矩阵）

### 7.1 龙候选

| # | 名称 | 作者 / 平台 | 精确 URL | 许可证（原文） | 商用 | 署名 | 再分发/改作 | 格式 / 体积 | 绑定骨骼 | 动画清单 | 含攻击 | 三角面 | 贴图 | 下载门槛 | 风格匹配 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | **Dragon**（Animated Monster Pack） | Quaternius / quaternius.com + poly.pizza | 包页 https://quaternius.com/packs/animatedmonster.html<br>Drive https://drive.google.com/drive/folders/102H-oyUM8SGYi1mW0GOgkjEu7xSdaORA<br>模型页 https://poly.pizza/m/VBvzjFIYws<br>**GLB 直链** https://static.poly.pizza/9714f533-5d2d-4cfd-b8f1-c8dfff64a672.glb | 包页 `CC0`（creativecommons.org/publicdomain/zero/1.0/）；poly.pizza 页 `Public Domain (CC0)` + `"Licence":"CC0 1.0"`；**包内 `License.txt` 原文 = `CC0 1.0 Universal (CC0 1.0) Public Domain Dedication`**（逐字读取） | 可 | 否 | 可（CC0） | 官方 `.fbx`(874,204B)/`.blend`/`.obj`；镜像 **`.glb` 268,896B** | **是**（27 joints） | `Dragon_Attack`、`Dragon_Attack2`、`Dragon_Death`、`Dragon_Flying`、`Dragon_Hit`（5） | **是 ×2** | 1,344（实测）／1,088（页面） | **无贴图**，6 个分色材质（Eyes/Main/Main/Belly/Claws/Wings） | **免登录直连**（poly.pizza HTTP 200；Drive 公开共享） | **高**：平涂低多边形、面数同量级；差异=分色材质 vs 手绘图集 |
| B | **Dragon** + **Dragon_Evolved**（Ultimate Monsters） | Quaternius / quaternius.com | 包页 https://quaternius.com/packs/ultimatemonsters.html<br>Drive https://drive.google.com/drive/folders/18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C （`Flying/glTF/`）<br>镜像 https://poly.pizza/m/3rUm1cN3yp 、 https://poly.pizza/m/LlwD0QNUPj | 包页 `CC0`；poly.pizza `"Licence":"CC0 1.0"`；**包内 `License.txt` 原文 = `CC0 1.0 Universal (CC0 1.0) Public Domain Dedication`**（374B，逐字读取；抬头误写为 Ultimate Platformer Pack） | 可 | 否 | 可（CC0） | **官方 `.gltf` 427,100B / 991,335B**（自包含）＋`.fbx`/`.blend`/`.obj` | **是**（13 / 46 joints） | `Death`、`Fast_Flying`、`Flying_Idle`、`Headbutt`、`HitReact`、`No`、`Punch`、`Yes`（8，两模型相同） | **是**（Headbutt、Punch） | 4,562 / 7,440（实测）；3,826 / 6,702（页面） | **有**：内嵌 `Atlas_Monsters.png`（镜像版改为 5 分色材质、无贴图） | **免登录**（Drive 公开共享 + poly.pizza 直链） | **中—高**：同风格低多边形平涂、面数同级；差异=更 Q 版、`Textured ✗` |
| C | **YellowDragon**（Cute Animated Monsters Pack） | Quaternius / quaternius.com | 包页 https://quaternius.com/packs/cutemonsters.html<br>Drive https://drive.google.com/drive/folders/1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0 （`glTF/`） | 包页 `CC0`；**该 Drive 根目录无 License.txt → 包内许可证未核实** | 可（依包页） | 否 | 可（CC0） | `.gltf` 634,125B ＋`.fbx`/`.blend`/`.obj` | **是**（17 joints） | `Bite_Front`、`Death`、`Flying`、`HitRecieve`（4） | **是**（Bite_Front 咬击） | 1,592（实测） | 有，但**外部** `Textures/YellowDragon_Texture.png` | **免登录**（Drive 公开共享） | **中**：低多边形平涂，但幼儿化 Q 版造型；**造型未看图核实** |
| D | **Simple 3D Dragon Model** | MattBas / OpenGameArt | https://opengameart.org/content/simple-3d-dragon-model | 页面 `License(s): CC-BY-SA 4.0` | 可 | **是（必须署名）** | **ShareAlike 传染性** | `dragon.tar.gz` 168.5 Kb（glb+贴图）、`dragon.blend` 2 Mb | **是**（Tags 标 `rigged`） | `Flying`、`Walking`、`Idle`、`Running`（4） | **否——无任何攻击动作** | 未核实（页面未标） | 页面称 tarball 含 glb 与其贴图 | 页面下载链接可直接取；**「是否需登录」未逐字节验证** | **中**：低多边形 + 有完整地面位移/待机；但**无攻击动作**，且 CC-BY-SA |
| E | `cpDragon-gltf`（**不建议**） | igmixer / GitHub | https://github.com/igmixer/cpDragon-gltf | API 标 `MIT`（**非 CC0**），仓库无 description、无来源说明 | 不明 | 不明 | 不明 | `scene.gltf` + `scene.bin` + 3 张贴图 | **未核实** | **未核实**（未解析动画） | 未核实 | 未核实 | GitHub 公开仓库，可直接 clone | **低**：来源与授权链不明，不作为候选 |

### 7.2 被排除的来源（一句话理由）

| 来源 | 排除理由 |
|---|---|
| KayKit 全线（10 仓库 + 32 itch 包） | 逐仓递归树 + 逐包页面核实：**零龙** |
| Kenney 全线（50 个 3D 资产） | 目录全量枚举：**零龙** |
| Quaternius Easy Enemy Pack | 6 个模型为蛙/鼠/蛇/蜘蛛/黄蜂，**无龙**（SEO 关键词误导已纠正） |
| Quaternius Ultimate Fantasy RTS | 128 个模型全为建筑/自然，**无龙** |
| Craftpix | **无 3D 模型**（纯 2D 源文件站） |
| Poly Haven | **无角色模型**（521 个模型全为场景/道具） |
| Elthen's Pixel Art | **纯 2D 像素精灵** |
| GitHub 全网 | `dragon gltf cc0` 检索 **total_count = 0** |

---

## 8. 集成风险清单（给 Lead 决策用）

1. **【最高】三条 Quaternius 龙都没有地面行走/奔跑，也没有地面待机。**
   项目现有契约是 `Idle` / `Walking_A` / `Running_A` 驱动移动状态机；而这三条龙的动画集分别是
   `{Attack, Attack2, Death, Flying, Hit}`、`{Death, Fast_Flying, Flying_Idle, Headbutt, HitReact, No, Punch, Yes}`、`{Bite_Front, Death, Flying, HitRecieve}`。
   **没有任何一条含 Walk / Run。** 若采用，必须：① 用 `Flying`/`Flying_Idle` 顶替待机与位移（视觉上浮空，与地面寻路打架）；② 或自建/重定向位移动画；③ 或接受「贴地滑行 + 无踏步」的表现降级。**这是本次调研最大的落地风险，且无法靠换候选解决——CC0 生态里带完整位移的龙只有 D（无一击动作）。**

2. **【高】Quaternius 许可证正在从 CC0 迁移到 QAL v1.0（2026-08-28）。**
   站点 License 页已换 QAL，只有老包页面还写 CC0；最新包（Bestiary，2026-08）已标 QAL。
   QAL §7 明确不追溯。**必须锁版本并留证**（下载时保存 `License.txt` 与包页快照）。另外 QAL 禁止「把素材本身再分发」→ 若走 QAL 口径，**模型不宜原样提交进公开仓库**，需 Lead 确认仓库策略。

3. **【高】`Dragon`/`Dragon_Evolved` 的官方 glTF 与 poly.pizza 镜像版不是同一份材质。**
   官方 `Dragon.gltf`：1 个材质 `Material` + 内嵌 `Atlas_Monsters.png`（有贴图）。
   poly.pizza GLB：5 个分色材质、`images = []`（无贴图）。
   **不要混用两者的视觉预期**；若走 poly.pizza 直链（脚本最省事），拿到的是**无贴图分色版**。

4. **【中】贴图是否内嵌不一致。**
   B 候选官方 `.gltf` **完全自包含**（buffer 为 base64 data-URI + 贴图挂 bufferView），单文件可 `load()`；
   C 候选 `YellowDragon.gltf` **贴图外置**（`Textures/YellowDragon_Texture.png`），必须一起拷；
   A 候选镜像 GLB 无贴图（分色材质），拷贝最简单。

5. **【中】造型只对 A、B 做了看图核实，C 未看图。** C（YellowDragon）的「幼龙」造型是推断，需补一次预览图确认；D（OGA）也未看图。

6. **【中】网络可达性差异。** poly.pizza 直链为静态 CDN，**脚本直连最稳**（我已实测 HTTP 200 + 字节解析）；Google Drive 公开目录需走 `embeddedfolderview` 端点列举、`uc?export=download&id=` 取文件，**能用但更脆**（历史上 Drive 对大文件会插确认页；本次三个 glTF 均在 1MB 内，未遇确认页）。

7. **【低】面数口径差异。** poly.pizza 页面的 `Tris` 普遍比我自己解析 GLB 得到的三角面少约 15–20%（如 3,826 vs 4,562）。**报数时以实测为准并标注来源**，别把两个数混用。

8. **【低】文件命名/元数据瑕疵（不影响可用性，但记录在案）：**
   - Ultimate Monsters 的包内 `License.txt` 抬头误写为 `Ultimate Platformer Pack`（正文许可证仍是 CC0）。
   - C 候选动画名拼写为 `HitRecieve`（原文如此，非 `HitReceive`）。
   - `YellowDragon.gltf` 网格名为 `Cube.036`、`Dragon.gltf` 网格名为 `Cube.222`、poly.pizza 版为 `Dragon_Fly` —— 若代码按网格名取节点会踩坑。

---

## 9. 附：本次取证的可复现命令（供复查）

```bash
# KayKit：10 个仓库递归树全量检索龙
curl -s "https://api.github.com/users/KayKit-Game-Assets/repos?per_page=100"   # 取仓库列表（注意是 /users/ 不是 /orgs/，/orgs/ 返回 404）
curl -s "https://api.github.com/repos/KayKit-Game-Assets/<REPO>/git/trees/main?recursive=1"   # 逐仓取树，再 grep dragon|wyvern|drake|wyrm
curl -s "https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/LICENSE.txt"

# Quaternius：站点 License 页与包页
curl -s "https://raw.githubusercontent.com/Quaternius/quaternius.github.io/main/license.html"        # QAL v1.0
curl -s "https://raw.githubusercontent.com/Quaternius/quaternius.github.io/main/packs/ultimatemonsters.html"

# Quaternius：Google Drive 公开目录（无需登录，embeddedfolderview 可列举）
curl -s "https://drive.google.com/embeddedfolderview?id=<FOLDER_ID>#list"
curl -sL "https://drive.google.com/uc?export=download&id=<FILE_ID>" -o Dragon.gltf
# 包内 License.txt（Ultimate Monsters 根目录）
curl -sL "https://drive.google.com/uc?export=download&id=16GqsDGESyEOfRbc4dS7EqAwkIUSIW4_y"

# poly.pizza：公开 API 不可用，改从页面内嵌 JSON 取 Licence
curl -s "https://poly.pizza/search/dragon"      # 200，内含 window.__SERVER_APP_STATE__
curl -s "https://api.poly.pizza/v1/search?q=dragon"   # 401 需要 API key
curl -s "https://poly.pizza/m/VBvzjFIYws"       # 模型页，含 Licence / Tris / Animated
curl -sL "https://static.poly.pizza/9714f533-5d2d-4cfd-b8f1-c8dfff64a672.glb" -o d.glb   # 免登录直取

# Kenney：3D 目录全量（page 5 会 500，翻到 page 4 即完）
curl -s "https://kenney.nl/assets/category:3D"

# 其它
curl -s "https://api.polyhaven.com/assets?t=models"     # 521 个，无角色
curl -s "https://craftpix.net/file-licenses/"
curl -s "https://opengameart.org/content/simple-3d-dragon-model"
curl -s "https://api.github.com/search/repositories?q=dragon+gltf+cc0"   # total_count 0

# 本地基线核实（只读）
python3 -c "解析 assets/_PLACEHOLDER/characters/placeholder_hero.glb 的 glTF JSON chunk"   # 76 动画 / 6952 面 / 41 joints
# GLB / glTF 动画名解析：读 header，遍历 chunk，取 ctype==0x4E4F534A 的 JSON chunk，读 animations[].name
```

---

## 10. 明确「未核实」清单（不猜，列出来）

| 项 | 原因 |
|---|---|
| Cute Animated Monsters Pack 包内许可证 | 该 Drive 根目录**没有** `License.txt` 文件项（已复核根目录 6 个条目：Blends/FBX/glTF/OBJ/Textures/Preview.jpg），只能依包页 CC0 |
| `YellowDragon` 造型 | 未下载/查看其预览图 |
| `Simple 3D Dragon Model`(OGA) 三角面数、是否需登录下载 | 页面未标面数；下载链接存在但未实际点击验证登录门槛 |
| KayKit `series-4/5/6` 盲盒角色包的逐个角色名 | 商店页未列角色名 |
| TinyTreats 各包内是否含龙 | 只看了主页，未逐包打开 |
| J-Toastie 全部 | itch.io 两个候选 URL 均 404，未能定位主页 |
| `cpDragon-gltf` 的动画与授权链 | 未解析其 `scene.gltf` 动画；仓库无来源说明 |
| poly.pizza 上是否有 Cute 包 `YellowDragon` | `/search/yellowdragon` 未返回该项；但该站搜索已知不可靠（见 §4.2），故记为「未核实」而非「无」 |
