# 对抗式复核报告（task-3）

- **复核员**：`dragon-verifier`（共享任务板 `task-3`，依赖 task-1/task-2）
- **复核对象**：仅 6 个候选 —— `lowpoly-cc0.md` 的 A/B/C，`wide-scan.md` 的 A1/A2/B6
- **复核时间**：2026-10-01（Asia/Shanghai）
- **方法**：对每个候选**亲自请求页面**（`web_fetch` + 原始 HTML 抓取）→ 抓许可原文 → **下载真实文件并解析字节**（glTF/GLB 的 `animations[]` / `skins[]` / `accessors[]` 三角面 / 逐关节运动幅度）→ 下载入口用匿名 HTTP 全程实测
- **红线纪律**：本报告每一条都是我自己请求或解析到的；凡未拿到证据的一律写「无法核实（原因）」。**没有任何猜测被写成结论**（个别推断已显式标注「推断」）。

---

## 0. 六条裁决速览

| # | 候选 | 裁决 | 一句话理由 |
|---|---|---|---|
| 1 | Quaternius **Animated Monster Pack → Dragon**（CC0） | ✅ **可信** | CC0 双源证实（包页字段 + 包内 `License.txt` 528B 原文）；5 条攻击/飞行动画经 **官方 FBX + poly.pizza GLB 双源字节交叉**，动作数据互不相同；唯一硬伤 = **无地面行走/待机** |
| 2 | Quaternius **Ultimate Monsters → Dragon / Dragon_Evolved**（CC0） | ✅ **可信（但必须换下载源）** | CC0 双源证实；官方 glTF 8 条动画字节级证实且逐条驱动 12/13、45/46 关节；**但 poly.pizza 镜像版是降级版**（翼尖/脖子不动），**`dragon-assets/poc/` 里那个文件就是降级版** |
| 3 | Quaternius **Cute Animated Monsters → YellowDragon**（CC0） | ⚠️ **存疑** | 动画字节可信（`Bite_Front/Death/Flying/HitRecieve`）；但①包内**无** License.txt，许可只有包页单一来源；②**我推翻调研员「贴图外置」的结论——贴图是内嵌的**；③造型是「大头浮空 Q 版」，与基线差距**大于**调研员评估 |
| 4 | bocdagla **Low Poly Dragon Model 3D**（itch，CC-BY） | ✅ **可信（六条里技术最强）** | 全流程匿名脚本直连下载成功；**实测 6 条动画（宣传只写 4 条）**，含真迈步 `Walk_menacing_loop`(腿 111°) 与 `GroundToFly`；76 关节全驱动；2,004 三角面；tip bones 证实。**许可陷阱：CC-BY 无版本号 + zip 内无 LICENSE 文件** |
| 5 | DibArts **Wyvern**（Sketchfab，CC-BY 4.0） | ⚠️ **存疑** | 许可 CC-BY 4.0、5 条动画名（含 0.5s `Attack.new`）、1154 面全部证实；下载确需登录（`isDownloadable:true` 但匿名 `mayDownloadThisModel:false`）。**但「动画能否驱动网格」无法核实**（原始 glTF 需登录、viewer 载荷加密），且 `isRigged=false` + Blockbench + `minecraft` 标签 |
| 6 | MattBas **Simple 3D Dragon Model**（OGA + itch，CC-BY-SA 4.0） | ✅ **可信（但无攻击，且 ShareAlike）** | **包内 `license.txt` 两平台各有一份、都写 CC BY-SA 4.0**；4 条动画字节证实、65 关节全驱动、2,698 三角面。**「两站许可口径不一致」是假冲突，我下载 itch 包后推翻**。**实际动画名带 `-loop` 后缀**，与页面 prose 不同 |

---

## 0.1 我推翻或修正了调研员的哪些结论（本报告的核心产出）

| # | 调研员原结论 | 我的复核结果 | 证据 |
|---|---|---|---|
| **F1** | `lowpoly-cc0.md` §8.4 / §7.1 表 C：`YellowDragon.gltf` **「贴图外置，必须一起拷」** | 🔴 **错**。`images[0]` 无 `uri`、挂在 **bufferView** 上，`buffers[0].uri` 是 `data:application/octet-stream;base64,…`(371,860 B) → **该 .gltf 单文件自包含，贴图内嵌** | 我下载 `YellowDragon.gltf`(634,125 B) 解析 glTF JSON |
| **F2** | `lowpoly-cc0.md` §7.1 表 B / §8.3：官方 glTF 与 poly.pizza 镜像「**只是材质不同**」，未提动画差异 | 🔴 **严重遗漏**。镜像版动画是**降级**的：`Dragon` 各动画只驱动 9–10 骨骼（官方 12），**`Neck` 与 `Wing4.L/R` 完全不动**；`Dragon_Evolved` 只驱动 16–32 骨骼（官方 45），**缺 `Wing4.L/R` + 全部手指/肩** | 官方 `Dragon.gltf` vs 镜像 `*.glb` 逐动画比较「被驱动骨骼名集合」 |
| **F3** | （无人指出）`dragon-assets/poc/quaternius_dragon_evolved_polypizza.glb` 的来源与质量 | 🔴 **该文件 sha256 `f660d8f4…` 与 poly.pizza 镜像 `Dragon_Evolved` 逐字节相同 → 就是 F2 说的降级版**，不是官方 glTF。**不要用它做动画质量评估** | `shasum -a 256` 双向比对 |
| **F4** | `wide-scan.md` §0.3-3 / §3 B6：MattBas「**两平台许可口径不一致**，以 OGA 为准更安全」 | 🔴 **假冲突**。我按匿名流程下载了 itch 自己的 `dragon.zip`，内含 **`license.txt` 162 B，原文写 CC BY-SA 4.0**；且两包 `dragon.glb` **sha256 完全相同**。**itch 只是没把许可写进页面，包里有** | 两包 sha256 + 两份 license.txt 原文 |
| **F5** | 两线共同：MattBas 动画清单 = `Flying / Walking / Idle / Running` | 🟠 **不精确**。页面 prose 确实是这 4 个词，但 **GLB 里真实动画名是 `Flying-loop` / `Idle-loop` / `Run-loop` / `Walk-loop`**（带 `-loop` 后缀）。按页面名硬编码查找会全部 miss | 解析 `dragon.glb` 的 `animations[].name` |
| **F6** | `lowpoly-cc0.md` §7.1 表 A/表 B：动画名写作 `Dragon_Attack` / `Death` / `Fast_Flying` … | 🟠 **少了命名空间前缀**。真实名是 `DragonArmature\|Dragon_Attack`（官方 FBX 与镜像 GLB 都带）与 `CharacterArmature\|Death`（镜像 GLB）。**Godot 导入后 `AnimationPlayer` 里的名字会带前缀** | FBX 字节里的 `DragonArmature\|…` 串 + GLB `animations[].name` |
| **F7** | `wide-scan.md` §7 V1：bocdagla 龙「**面数与骨骼质量未核实**」、动画「4 条」 | 🟢 **已核实并修正为更好**：**2,004 三角面**、**76 关节**、**实际 6 条动画**（多出 `AttackPose`、`GroundToFly`） | 下载 `dragon.zip` 解析 `Dragon2.glb` |
| **F8** | 两线共同：`igmixer/cpDragon-gltf`「授权链不明 / MIT 字段但来源不明」 | 🔴 **理由需更正**：授权链**是明确的** —— 仓库 `LICENSE`=MIT(igmixer)，但 `scene.gltf` 的 `asset.extras` **自陈**上游是 `lolilith` 的 Sketchfab 模型 **CC-BY-4.0**。即「**已知的授权冲突**」，不是「不明」。且它**只有 1 条动画 `Take 001`**、贴图外置、赛博朋克风 | `raw.githubusercontent…/LICENSE` + `scene.gltf` 的 `asset.extras` |
| **F9** | `lowpoly-cc0.md` §10：YellowDragon「**造型未核实**」 | 🟢 **已补**：整包 21 只都是「**大头 + 极小身体 + 浮空**」的 Q 版生物（见 §3.5 图）。风格匹配度应从「中」下调 | 下载包预览图 1920×1080 并实际看图 |
| **F10** | `wide-scan.md` §1：Sketchfab「39 条全部 `mayDownloadThisModel: false`」 | 🟢 **成立，但字段语义要分清**：`api.sketchfab.com/v3/models/<uid>` 的 **`isDownloadable: true`** 说的是「作者允许下载」，`/i/models/<uid>` 的 `mayDownloadThisModel: false` 说的是「当前匿名会话不能下」。**两者不矛盾，别当成两组数据打架** | 两个端点分别实测 |

---

## 1. 候选 1：Quaternius Animated Monster Pack → **Dragon**（CC0）

### 1.1 URL 可达性 ✅

| 检查 | 结果 |
|---|---|
| 包页 | <https://quaternius.com/packs/animatedmonster.html> → **HTTP 200**，`<title>` 区正标题 `Quaternius • Animated Monster Pack`，**名称对得上** |
| 页面字段 | `Models 4`、`Animated ✓`、`Textured ✗`、`Formats: FBX / OBJ / Blend`、`August 2018` |
| ⚠️ 关键 | **`Formats` 里没有 glTF** —— 官方包**不含 glTF 目录**（我列举 Drive 根目录确认：`Blend/ FBX/ OBJ/ License.txt Preview.jpg`） |

### 1.2 许可证原文 ✅（CC0 双源证实，QAL 不适用）

| 来源 | 原文 | URL |
|---|---|---|
| 包页信息栏 | `License` → [`CC0`](https://creativecommons.org/publicdomain/zero/1.0/)（原始 HTML：`<div class="infoitem">…License<div class="text-right"><a href="https://creativecommons.org/publicdomain/zero/1.0/" target="_blank">CC0</a></div></div>`） | 包页 |
| **包内 `License.txt`**（528 B，sha256 `2b04fed13cc05aa0ae58f42cc8fd194121204e3151ee8abb8d35049a9b1c1d93`） | 逐字：`Animated Monsters by Quaternius` / `License:` / `CC0 1.0 Universal (CC0 1.0)` / `Public Domain Dedication` / `https://creativecommons.org/publicdomain/zero/1.0/` / `If you want to credit me just say: Animated Monsters by Quaternius` | <https://drive.google.com/file/d/1kmh71Y_VBZdwr9P_8iwM9yn8bRS9RXcG/view> |
| poly.pizza 模型页 | `"Licence" = "CC0 1.0"`，`"Animated" = true`，`"UploadDate" = "2022-07-11"`，meta 明写 `No login required.` | <https://poly.pizza/m/VBvzjFIYws> |

**裁决**：**CC0 1.0**。可商用 ✅ / **无需署名** ✅ / 可改作 ✅ / 可再分发 ✅ / **无 NFT、无 AI 训练附加条款**（我逐字读完 QAL 全文，其 §3 只有「不得再分发素材本身」与「不得冒称作者」两条限制，见 §7）。**站点级 QAL v1.0 不适用本包**（见 §7 裁决）。

### 1.3 动画证据 ✅（字节级，双源交叉）

**动画清单出处 = 文件字节**，不是页面文字（页面根本没列动画名）：

| 源 | 文件 | 动画（照抄 `animations[].name`） |
|---|---|---|
| **poly.pizza 镜像 GLB** | `9714f533-…glb`，**268,896 B**，generator `FBX2glTF v0.9.7` | `DragonArmature\|Dragon_Attack`、`…\|Dragon_Attack2`、`…\|Dragon_Death`、`…\|Dragon_Flying`、`…\|Dragon_Hit` |
| **官方 FBX**（我自己下载） | `Dragon.fbx`，**874,204 B**（Drive id `1dM_UUyuQSi73q1ez3NmVBfZZC7Q1kTek`），`Kaydara FBX Binary` | 字节内命中的动画栈名**完全一致**：`Dragon_Attack` / `Dragon_Attack2` / `Dragon_Death` / `Dragon_Flying` / `Dragon_Hit`（均在 `DragonArmature\|` 下） |

**「5 条是不是真的 5 个不同动作」——我逐条算了时长与关键帧数据哈希，全部互不相同**：

| 动画 | 时长 | 通道数 | 驱动的关节数 | 关键帧数据哈希 |
|---|---|---|---|---|
| `Dragon_Attack` | 0.875 s | 25 | 21 / 27 | `0e395e923eb6` |
| `Dragon_Attack2` | 1.667 s | 22 | 19 / 27 | `74187c74f249` |
| `Dragon_Death` | 1.208 s | 24 | 22 / 27 | `0e3818f5129e` |
| `Dragon_Flying` | 1.667 s | 16 | 16 / 27 | `f3bf810785c3` |
| `Dragon_Hit` | 1.667 s | 22 | 19 / 27 | `285246de9456` |

- **蒙皮确实形变** ✅：`skins[0].joints = 27`，动画通道的目标就是这些关节（`BodyRoot`/`Body`/`Neck`/`Head`/`Face`/`Wing1.L`…），不是「只驱动一个根节点」。
- **`Dragon_Flying` 不驱动腿部**（`UpperLeg.L/R`、`LowerLeg.L/R`、`Neck` 都不在其通道里）→ **腿保持绑定站姿，只有翅膀/身体/头/尾在动**。
- 三角面：**1,344**（我按 `accessors[].count` 求和）／页面标 `1,088`（口径差，非矛盾）。
- 贴图：**无**（`images = []`）；**6 个纯色材质**：`Eyes`/`Main`/`Main`/`Belly`/`Claws`/`Wings`，我另取出 `baseColorFactor` 确认是分色：`Main`≈linear(0.0398, 0.0093, 0.0116) 暗酒红、`Belly`≈(0.2611, 0.1809, 0.0188) 橄榄黄、`Wings`/`Eyes`≈0.0107 近黑、`metallicFactor=0.4`。
- **造型** ✅：我下载官方包预览图（`Preview.jpg`，1920×1080，EXIF 记 `Blender:File:…Render.blend`、`Date:2018/08/09`）并看图 —— **暗酒红四足带翼龙 + 黄色腹甲 + 黑色蝠翼膜 + 头部双角**，是标准西幻龙，不是恐龙。

### 1.4 下载入口 ✅（除 glTF 外全部免登录）

| 通道 | 实测 |
|---|---|
| Drive 目录列举 | `https://drive.google.com/embeddedfolderview?id=102H-oyUM8SGYi1mW0GOgkjEu7xSdaORA#list` → **HTTP 200**，无需登录 |
| Drive 文件直取 | `https://drive.google.com/uc?export=download&id=<FILE_ID>` → **HTTP 200**，`Dragon.fbx` 874,204 B 实取成功 |
| poly.pizza GLB 直链 | `https://static.poly.pizza/9714f533-5d2d-4cfd-b8f1-c8dfff64a672.glb` → **HTTP 200，268,896 B**，**免登录** |
| ⚠️ 限制 | **官方包没有 glTF**，所以「脚本直连拿到 glTF」这条路**只有 poly.pizza 第三条路**。我已验证它与官方 FBX 的动画名完全一致（转换是忠实的），但**它仍是第三方转换产物**，若要严格留证请同时保存官方 FBX |

### 1.5 落地到 Godot 还缺什么

1. **没有地面待机/行走/奔跑**——这是最硬的缺口。`Flying` 会扇翅膀而腿被冻在站姿，贴地使用等于「站着扇翅膀滑行」。
2. 要一份 **动画名别名表**：Godot 里名字带 `DragonArmature|` 前缀。
3. 6 个 surface 的溶解材质要**逐 surface 拷 `albedo_color`**（本项目 v16 `death_dissolve` 管线），此模型**无贴图**、颜色全在 `baseColorFactor`。
4. `metallicFactor=0.4` 在 Godot 默认环境下可能偏亮，需按需调 0。
5. 朝向需实测（本模型来自 FBX，与 KayKit 的 +Z 约定不一定一致）。

---

## 2. 候选 2：Quaternius Ultimate Monsters → **Dragon / Dragon_Evolved**（CC0）

### 2.1 URL 可达性 ✅

<https://quaternius.com/packs/ultimatemonsters.html> → **HTTP 200**，正标题 `Quaternius • Ultimate Monsters`；`Models 50`、`Animated ✓`、**`Textured ✗`**、`Formats: FBX / OBJ / Blend / glTF`、`October 2022`。

### 2.2 许可证原文 ✅

| 来源 | 原文 |
|---|---|
| 包页信息栏 | `License` → [`CC0`](https://creativecommons.org/publicdomain/zero/1.0/) |
| **包内 `License.txt`**（374 B，sha256 `de990ef6fc68cffd7fd1ae342c4d0c823b541b8848d8f76bca5d3339f4de6f6e`） | 逐字：`Ultimate Platformer Pack by @Quaternius` ← **抬头误写（调研员已发现，我复核确认）** / `License:` / `CC0 1.0 Universal (CC0 1.0)` / `Public Domain Dedication` / `https://creativecommons.org/publicdomain/zero/1.0/` |
| poly.pizza（两个模型页） | `"Licence" = "CC0 1.0"`，`"Animated" = true`；`Dragon` Tris 3,826 UploadDate 2022-10-23；`Dragon Evolved` Tris 6,702 |

URL：<https://drive.google.com/file/d/16GqsDGESyEOfRbc4dS7EqAwkIUSIW4_y/view>、<https://poly.pizza/m/3rUm1cN3yp>、<https://poly.pizza/m/LlwD0QNUPj>

**裁决：CC0 1.0**（可商用/无需署名/可改作/可再分发）。抬头误写是 **Quaternius 自己的复制粘贴残留**，许可证正文明确，不影响效力。

### 2.3 动画证据 ✅（官方 glTF 字节级）

我匿名下载了官方 Drive 上的两个 glTF：

| 文件 | 大小 | generator | 动画（8 条，照抄） | joints | 三角面 | 网格名 | 材质 |
|---|---|---|---|---|---|---|---|
| `Dragon.gltf`（id `1-mQSm6_oGt7-EEQfNj1dFWYgPQy4AdPC`） | **427,100 B** | `Khronos glTF Blender I/O v1.7.33` | `Death` `Fast_Flying` `Flying_Idle` `Headbutt` `HitReact` `No` `Punch` `Yes` | 13 | **4,562** | `Cube.222` | `Material` + 内嵌 `Atlas_Monsters` |
| `Dragon_Evolved.gltf`（id `1Mcfuavq7F4itG9xhqc-20_IL257ZY2_3`） | **991,335 B** | 同上 | 同上 8 条 | 46 | **7,440** | `Cube.221` | **`Atlas`**（不叫 `Material`）+ 内嵌 `Atlas_Monsters` |

- **自包含** ✅：`buffers[0].uri` = `data:application/octet-stream;base64,…`（219,500 B / 382,140 B），`images[0]` 挂在 **bufferView** 上 → **单文件可直接 `load()`，无外部依赖**。
- **8 条是真不同动作** ✅：逐条时长 + 关键帧数据哈希全部互不相同（`Dragon` 侧：Death 0.667s / Fast_Flying 0.833s / Flying_Idle 1.167s / Headbutt 1.167s / HitReact 0.467s / No 1.167s / Punch 1.167s / Yes 1.167s）。
- **蒙皮确实被驱动** ✅：每条动画驱动 **12/13**（Dragon）与 **45/46**（Evolved）关节。
- 三角面：`Dragon` **4,562** ／ `Dragon_Evolved` **7,440**（页面 poly.pizza 标 3,826 / 6,702，口径差）。

### 2.4 🔴 重大发现：poly.pizza 镜像版 ≠ 官方版（动画被降级）

| | 官方 `Dragon.gltf` | poly.pizza 镜像 `Dragon` GLB（251,540 B，`FBX2glTF v0.9.7`） |
|---|---|---|
| 动画名 | `Fast_Flying` | **`CharacterArmature\|Fast_Flying`**（多前缀） |
| 材质 | 1 个 `Material` + 内嵌 Atlas 贴图 | **5 个分色材质**（`Dragon_Main`/`Dragon_Secondary`/`Dragon_Horn`/`Eye_White`/`Eye_Black`），**`images=[]` 无贴图** |
| 网格名 | `Cube.222` | `Dragon_Fly` |
| 三角面 | 4,562 | 4,562（一致 ✅） |
| **每动画驱动骨骼** | **12 / 13** | **9–10 / 13**；**`Neck`、`Wing4.L`、`Wing4.R` 在 `Fast_Flying`/`Flying_Idle`/`Headbutt`/`Punch` 上完全不动** |

`Dragon_Evolved` 镜像（436,000 B）更严重：**每动画只驱动 16–32 / 45 骨骼**，缺 **`Wing4.L/R`（翼尖）+ 全部手指（Index/Middle/Pinky/Thumb ×3 节）+ `Shoulder.L/R`**。

> 🔴 **`dragon-assets/poc/quaternius_dragon_evolved_polypizza.glb` 的 sha256 = `f660d8f48be4ea3f39639f6206a0181127e7fe7503cb4bad8d07d27d80528f3a`，与我下载的 poly.pizza 镜像 `Dragon_Evolved`（436,000 B）逐字节相同。**
> **⇒ poc 里那个文件就是降级版；用它的渲染效果去评估「Quaternius 龙好不好看/动画全不全」会低估官方版本。**

**裁决**：要用这个候选，**必须走 Drive 官方 `.gltf`**；poly.pizza 直链虽然免登录最省事，但拿到的是**翼尖与脖子僵住的降级版**。

### 2.5 下载入口 ✅

- Drive 目录枚举：`18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C` → 根 `Big(16)/ Blob(17)/ Flying(17)/ Atlas_Monsters.png / Color Guide.png / License.txt / Preview.jpg`，**16+17+17=50** 与页面 `Models 50` 相符 ✅
- 龙在 `Flying/glTF/`（17 个 `.gltf` + 共享 `Atlas_Monsters.png`）
- 全部 `uc?export=download&id=` **匿名 HTTP 200 直取**，**无需登录** ✅（我实测 3 个文件）

### 2.6 落地还缺什么

1. **同样没有地面 walk / run / 地面 idle**（只有 `Flying_Idle`/`Fast_Flying`）。作为**飞行怪 / BOSS** 可用；作为地面怪要接受浮空滑行。
2. **无咬击 / 无吐息 / 无火焰**：攻击只有 `Headbutt`（撞头）与 `Punch`（挥爪）。
3. 用官方 `.gltf`，**不要用 poly.pizza 直链**（§2.4）。
4. 贴图内嵌于 Base64 buffer：`file://` 直接 `load()` 即可，但首帧解析 1 MB 级 glTF 有开销。
5. `Dragon_Evolved` 材质名是 `Atlas`（不是 `Material`），代码别按名字硬取。

---

## 3. 候选 3：Quaternius Cute Animated Monsters → **YellowDragon**（CC0）

### 3.1 URL 可达性 ✅

<https://quaternius.com/packs/cutemonsters.html> → **HTTP 200**，正标题 `Quaternius • Cute Animated Monsters Pack`；`Models 21`、`Animated ✓`、`Textured ✓`、`Formats: FBX / OBJ / Blend / glTF`、`August 2020`。

### 3.2 许可证原文 ⚠️（只有单一来源）

| 来源 | 结果 |
|---|---|
| 包页信息栏 | `License` → [`CC0`](https://creativecommons.org/publicdomain/zero/1.0/) ✅ |
| **包内 `License.txt`** | 🔴 **不存在**。我列举 Drive 根目录 `1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0`，**6 个条目**：`Blends/ FBX/ glTF/ OBJ/ Textures/ Preview.jpg` —— **没有 `License.txt`**（调研员结论正确，我复核确认） |

**裁决：CC0（依包页）**，但**「包内许可证未核实」这条是实打实的缺口** —— 与候选 1/2 不同，本候选**没有随包凭证**。若采用，务必自行抓包页 HTML 快照 + 记录抓取日期。

### 3.3 动画证据 ✅（字节级）

`YellowDragon.gltf`（Drive id `1JuOhGmG0BXCdNA39M8qUQL6YuiQ_5zgH`），**634,125 B**，generator `Khronos glTF Blender I/O v1.6.16`：

| 动画（照抄 4 条） | 说明 |
|---|---|
| `Bite_Front` | ✅ 攻击（正面咬击），51 channels / 17 关节 |
| `Death` | |
| `Flying` | |
| `HitRecieve` | **原文拼写如此**（非 `HitReceive`），调研员已记录，我确认 |

- `skins[0].joints = **17**`；**每条动画驱动全部 17 个关节** ✅（真蒙皮形变）
- 三角面 **1,592**；网格名 `Cube.036`；材质 `Texture`；贴图名 `YellowDragon_Texture`
- 4 条动画时长/数据哈希互不相同 ✅（`Bite_Front`/`Death`/`Flying`/`HitRecieve` 各 51 samplers）

### 3.4 🔴 推翻：贴图是**内嵌**的，不是外置

调研员在 §8.4 与 §7.1 表 C 写「**贴图是外部文件 `Textures/YellowDragon_Texture.png`，glTF 里 `images[0].uri` 指向外部 → 拷进项目必须连贴图一起拷**」。

**我解析字节的实际结果**：

```
images(1): [('YellowDragon_Texture', 'bufferView')]     ← 挂在 bufferView，不是外部 uri
buffers:  [('data:application/octet-stream;base64,1L9Jvx+wbz/VJ', 371860)]
```

⇒ **`YellowDragon.gltf` 是单文件自包含的**（贴图内嵌在 Base64 buffer 里）。包内那个 `Textures/` 目录是给 **FBX/OBJ** 用的，**glTF 不需要它**。这一条把候选 3 的落地成本从「要拷两个文件」降为「拷一个文件」。

### 3.5 造型 ✅（补上调研员留的「未核实」）

我下载了包预览图并**实际看图**（`Preview.jpg`，Drive id `1S-j0FDZMdDbjmEmlUzukx--R108czpgD`，1920×1080，505,865 B，取自 `1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0`；下载后以 `read_image` 逐像素查看，**该图只在本地临时目录、未存入工作区**）：

> 复现看图：`curl -sS -L "https://drive.google.com/uc?export=download&id=1S-j0FDZMdDbjmEmlUzukx--R108czpgD" -o cute_preview.jpg`

- **整包 21 只全部是「大头 + 极小身体 + 浮空」的 Q 版生物**：骷髅、蘑菇、熊猫、企鹅、蜜蜂、南瓜、史莱姆… 没有一只是完整的四足动物。
- 图中确有一只**黄色 + 双角 + 蝠翼**的个体（底排左起第 4 只），与 `YellowDragon` 名字最相符。
- ⚠️ **诚实边界**：预览图**没有标注个体名字**，所以「图中那只黄色的就是 `YellowDragon`」是**推断**，不是证实。可证实的是**整包造型风格** = Q 版浮空大头。

**裁决**：造型匹配度应从调研员的「**中**」**下调**——它不是「幼龙」，是**会飞的胖头龙**；且因为没有地面位移动画，与「四足带翼龙」的目标形象差距很大。

### 3.6 下载入口 ✅

Drive 目录 `1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0` → `glTF/` 下 21 个条目，`uc?export=download&id=` **匿名 HTTP 200 直取**，**无需登录**。

### 3.7 落地还缺什么

1. **无地面行走/待机**（只有 `Flying`）——同候选 1/2 的通病。
2. **无随包许可证文件**：必须自留包页快照。
3. 造型差异大，且**只有一只**龙（不可做多档变体）。
4. 网格名 `Cube.036` —— 代码别按网格名取节点。

---

## 4. 候选 4：bocdagla **Low Poly Dragon Model 3D**（itch.io，CC-BY） ★技术最强

### 4.1 URL 可达性 ✅

<https://bocdagla.itch.io/low-poly-dragon> → **HTTP 200**，正标题 `Low Poly Dragon Model 3D`（`<title>` = `Low Poly Dragon Model 3D by bocdagla`），作者 `bocdagla`，**名称对得上**。`data.json` 亦返回 `"title":"Low Poly Dragon Model 3D"`、`"id":2677031`、`"price":"$0.00"`、`"suggested_price":"$2.00"`、tags 含 **`godot`** 与 `no-ai`。

### 4.2 许可证原文 ⚠️（是描述正文，不是结构化字段；且无版本号）

页面「More information」区上方的描述正文原文：

> A low poly dragon animated with diferent colour schemes and 4 diferent animations:
> - Attack / Fly / Move / Idle
>
> It is in fbx and glb format ad i've added some tip bones for easier IK on godot
>
> You can use this file however you want as long as you give credit :D
>
> **License:**
> **Creative Commons Attribution**

🔴 **两个必须记录的细节**（调研员未指出）：

1. **这不是 itch.io 的结构化 License 字段**。原始 HTML 显示它位于 `<div class="formatted_description user_formatted">` **内部**（和动画清单同一段富文本），而「More information」表格里**没有 License 行** —— 对比：`Status/Category/Rating/Author/Tags/Content` 都有行，**License 没有**。⇒ 这是**作者自述文本**，不是平台登记的许可。
2. **未标版本号**。「Creative Commons Attribution」到底是 CC BY 4.0 还是 3.0 不明 ⇒ 若法务要精确 SPDX 标识，**这一条不够**。

**作者对「商用 / 署名 / 再分发」的原话**（评论区，我逐条读到）：

| 议题 | 作者原话 |
|---|---|
| 商用（改过之后拿去卖） | `of course, go ahead and charge how much you want for it 😁` —— 同意第三方改贴图/换动画后的版本**标价出售** |
| 署名方式 | `Just just an entry on the credits is more than enough :D` |
| **再分发/随包许可** | MattBas 建议「include a text file with your username and license in the zip file」→ 作者回复 **`I will surely add the file and the license in the project.`**（**但见 §4.5：实际没加**） |

### 4.3 动画证据 🔴（页面说 4 条，实际 6 条）

**动画清单出处 = 文件字节**（我下载 zip 后解析 `Dragon2.glb`）：

| 动画（照抄 `animations[].name`） | 时长 | 通道 | 驱动关节 | 部位运动幅度实测 |
|---|---|---|---|---|
| `Attack` | 0.917 s | 78 | **76 / 76** | 前肢 110.9°、翼根 55.2°、尾 42.1° |
| `AttackPose` | 0.417 s | 78 | 76 / 76 | 头 54.6°、后肢 45.0° |
| `Flying_loop` | 1.667 s | 78 | 76 / 76 | 翼根 **65.2°**、躯干 34.6°、头 24.4° |
| `GroundToFly` | 0.833 s | 78 | 76 / 76 | 腿 **121.0°**、翼 **92.2°**（起飞过渡） |
| `Idle_loop` | 5.000 s | 152 | 76 / 76 | 腿/头仅 **0.03°**（基本静止），**只有尾 24.4° 摆** |
| `Walk_menacing_loop` | 1.667 s | 90 | 76 / 76 | 腿 **111.1°**（真在迈步）、头 41.8°、尾 41.9° |

🔴 **页面宣传 4 条（Attack/Fly/Move/Idle），实际有 6 条** —— 多出 `AttackPose`（起手姿）与 `GroundToFly`（地面→起飞过渡）。**这是正向的证伪：资产比宣传的更好。**

- 页面名 ↔ 实际名的映射：`Fly`→`Flying_loop`、`Move`→`Walk_menacing_loop`、`Idle`→`Idle_loop`、`Attack`→`Attack`
- **`Move` 真的在迈步，不是滑行** ✅ —— 这一点**直接解决了 `lowpoly-cc0.md` §8.1 认定的「本次调研最大落地风险（CC0 生态里没有带地面位移的龙）」**：bocdagla 这条有 **地面待机 + 地面行走 + 地面起飞 + 飞行 + 攻击 + 受击姿**，是六条候选里**唯一动画覆盖完整**的。
- **tip bones 证实** ✅：关节名里确实存在 `Head.Tip`、`Head.downTip`、`LegFront_L.Tip`、`LegBack_L.Tip`、`Tail.Tip` ⇒ 作者「i've added some tip bones for easier IK on godot」属实。
- 三角面 **2,004**（解开 `wide-scan.md` §7 V1 的未知项）；`skins[0].joints = **76**`；网格名 `Cube.003`；材质 `basic.001`。
- 贴图：GLB 内嵌 `palette_alt_3`（bufferView）⇒ **单文件自包含** ✅；zip 另附 `palette.png` + `palette_alt_1/2/3.png` 供换色（对应页面「diferent colour schemes」）。

### 4.4 下载入口 ✅（全流程匿名脚本直连，实测通过）

调研员只写到「下载按钮直接可见」。我**把整条链走通了**：

```
① GET  https://bocdagla.itch.io/low-poly-dragon/purchase            → 200，取出 <meta name="csrf_token">
② POST https://bocdagla.itch.io/low-poly-dragon/download_url        → 200 JSON {"url":"…/download/eyJleHBpcmVz…"}
   （带 csrf_token，header X-Requested-With: XMLHttpRequest）
③ GET  该 signed download 页                                         → 200，取 data-upload_id="10302750"
④ POST https://bocdagla.itch.io/low-poly-dragon/file/10302750?source=game_download
                                                                    → 200 JSON，给 60 秒有效的
                                                                      Cloudflare R2 签名直链
⑤ GET  该直链                                                        → 200，dragon.zip 1,067,149 B ✅
```

**结论：itch.io 免费条目「可脚本直连下载」，全程无需登录、无需账号、无需浏览器。** 唯一注意：第 ④ 步签名的 URL **有效期 60 秒**，必须立刻取。

zip 内容（`unzip -l`）：

| 文件 | 大小 |
|---|---|
| `upload/Dragon2.glb` | 498,564 B |
| `upload/Dragon2.fbx` | 4,982,716 B |
| `upload/palette.png` | 502 B |
| `upload/palette_alt_1.png` / `_alt_2.png` / `_alt_3.png` | 506 / 501 / 503 B |

### 4.5 🔴 许可证陷阱：zip 内**没有** LICENSE 文件

作者 2 年前公开承诺会加，但**实际交付的包里没有**：

```
$ unzip -l dragon.zip
  upload/Dragon2.glb  upload/Dragon2.fbx  upload/palette.png
  upload/palette_alt_1.png  upload/palette_alt_2.png  upload/palette_alt_3.png
  ← 无 LICENSE / license.txt / CREDITS
```

⇒ **该资产的许可凭证只存在于网页描述里**，转发/离线传播时会丢失。对标 `assets/audio/CREDITS.md`、`assets/vfx/CREDITS.md` 的项目惯例：**必须在项目内自建 CREDITS 条目，写入「作者 bocdagla / 来源 URL / 抓取日期 2026-10-01 / 许可表述原文 / 该页面无版本号」**。

### 4.6 裁决与落地

**裁决：✅ 可信（技术维度六条里最强，且唯一动画覆盖完整）**；许可维度是「**可用但需自己补留痕**」。

落地还缺什么：

1. **许可版本号缺失** —— 建议按「CC-BY（作者意图：可商用、需署名、改作可卖）」处理，并在 CREDITS.md 里原文照录，不擅自写成 "CC BY 4.0"。
2. FBX 与 GLB 并存，GLB 自包含（贴图内嵌），**优先用 GLB**；FBX 4.98 MB 只在需要重新导入 DCC 时用。
3. 动画名要和项目状态机做别名映射：`Idle_loop`→idle、`Walk_menacing_loop`→walk、`Flying_loop`→fly、`Attack`/`AttackPose`→attack、`GroundToFly`→起飞。
4. 本项目 v16 死亡溶解：材质是 `basic.001` + **调色板贴图**，溶解时要拷的是**贴图 + base color**（与候选 1 的纯色不同）。
5. 朝向需实测。

---

## 5. 候选 5：DibArts **Wyvern**（Sketchfab，CC-BY 4.0）

### 5.1 URL 可达性 ✅

<https://sketchfab.com/3d-models/wyvern-b3b83f40265347dd90e4666c3e2a843c> → **HTTP 200**，`<title>` = `Wyvern - Download Free 3D model by DibArts (@youssefe22) [b3b83f4]`；页面显示 `Triangles: 1.2k`、`Vertices: 772`、`296 Downloads`/`1186 Views`/`32 Like`、`Published Nov 13th 2022`、**`Uploaded with Blockbench`**。

### 5.2 许可证原文 ✅（CC-BY 4.0 确认）

| 来源 | 原文 |
|---|---|
| 页面 License 区块 | `License: CC Attribution` / `Creative Commons Attribution` → `http://creativecommons.org/licenses/by/4.0/`，`Learn more` |
| `api.sketchfab.com/v3/models/<uid>` | `license.label = "CC Attribution"`、`license.fullName = "Creative Commons Attribution"`、`license.requirements = "Author must be credited. Commercial use is allowed."`、`license.url = "http://creativecommons.org/licenses/by/4.0/"`、`license.slug = "by"` |

**裁决：CC-BY 4.0** —— 可商用 ✅ / **必须署名 DibArts** ✅ / 可改作 ✅；无 NC、无 SA、无 NFT/AI 附加条款。调研员结论成立。

### 5.3 动画证据 ✅（清单出处 = Sketchfab 接口；⚠️ 补一条调研员漏报的）

`https://sketchfab.com/i/models/b3b83f40265347dd90e4666c3e2a843c/animations` → **HTTP 200**，逐条返回（这是「动画名」的权威出处，不是作者口述）：

| 动画名 | 时长 | isLoop | 载荷字节 |
|---|---|---|---|
| `Attack.new` | **0.5 s** | ⚠️ **false** | 924 |
| `Flying.new` | 1.5 s | ⚠️ **false** | 2,460 |
| `Running.new` | 1.5 s | ⚠️ **false** | 2,044 |
| `Walking.new` | 2.0 s | ⚠️ **false** | 4,076 |
| `Standing.new` | 1.5 s | ⚠️ **false** | 1,212 |

- 5 条 ✅、名字含攻击 ✅ —— 与调研员一致。
- 🔴 **补充**：5 条**全部 `isLoop: false`**（作者没标循环）。在 Godot 里自己设 loop 即可，不是阻塞项，但要知道页面上写的「idle/walking/running/flying」**在数据里并没有被标成循环动作**。
- `faceCount = 1154`（页面 `Triangles: 1.2k` 与之相符）、`vertexCount = 772`、`animationCount = 5`。

### 5.4 下载入口 ✅（结论成立，但两个字段别搞混）

任务要求用 `api.sketchfab.com/v3/models/<uid>` 看 `mayDownloadThisModel` / `isDownloadable`。我实测两个端点：

| 端点 | 关键字段 | 值 |
|---|---|---|
| `api.sketchfab.com/v3/models/<uid>` | **`isDownloadable`** | **`true`** |
| | `mayDownloadThisModel` / `downloadType` | **字段不存在（=null）** —— 公开 v3 接口**不返回**这两个字段 |
| `sketchfab.com/i/models/<uid>`（匿名会话） | **`mayDownloadThisModel`** | **`false`** |
| | `downloadType` | `"free"` |
| | `metadata.isRigged` | **`false`** |
| | `metadata.totalTriangle` | 1154 |
| | `archiveSize` / `ext` | 289,654 / `"gltf"` |
| | `downloadCount` | 296 |
| | `metadata.sourceFiles` | 单个 `source/model.gltf`，289,654 B（`misc`/`image` 均为空） |
| | `exporter.name` | **`"Blockbench"`** |

**裁决**：**两个字段不矛盾、语义不同** —— `isDownloadable: true` = 「作者允许下载」；`mayDownloadThisModel: false` = 「当前匿名会话不能下」。**结论：页面可匿名浏览，但下载确实需要登录 Sketchfab 账号** ⇒ **不可脚本直连**。调研员结论成立。

### 5.5 🔴 `isRigged=false` 的技术裁决：**无法核实**（调研员标为「必须实测」，我给出了实测尝试与失败原因）

这是本候选唯一的技术生死问题：**「Standing/Walking/Running/Flying/Attack」这 5 个名字到底能不能驱动网格形变？** `isRigged = false` + `Uploaded with Blockbench` + 标签含 **`minecraft`** + `*.new` 后缀（Blockbench 的动画命名习惯）**都指向「节点变换动画」**——如果整只龙是一个单一网格、没有子部件，那 5 条动画只能让模型**整体刚性位移**，翅膀根本不会扇。

我尝试了 3 条取证路径，**前两条失败，第三条只能给出旁证**：

1. ❌ 直接下载原始 glTF → 需登录，`mayDownloadThisModel: false`。
2. ❌ 从 embed 页暴露的 viewer 载荷 `media.sketchfab.com/models/<uid>/…/files/2179d…/file.binz`（**98,850 B**，匿名可取）反推节点结构 → **文件是加密的**：gzip / zlib / raw-deflate **三种解压全部失败**，文件内**搜不到** `osgjs` / `MatrixTransform` / `Geometry` / `Skeleton` / `vertex` 任何一个明文标记（可打印字符占比 37%）。⇒ **无法解析**。
3. ⚠️ 旁证（**推断，非结论**）：5 条动画的 viewer 载荷极小（Attack **924 B**、Standing 1,212 B、Running 2,044 B、Flying 2,460 B、Walking 4,076 B，未压缩）。按 24 fps 粗估，0.5 s 的 `Attack` 只够编码**约 2–3 个节点**的旋转+位移。**这与「少量部件做节点动画」相符，与「几十根骨骼的蒙皮」不符。**（该推断基于未公开的私有格式，仅供参考，不作为结论。）

**裁决：⚠️ 无法核实（原因：原始 glTF 需登录下载；viewer 载荷加密且格式未公开）。**

**给 Lead 的精确证伪判据**（一旦有人能登录下载）：
> 在 Godot 里导入后打开 `AnimationPlayer`，看 `Attack.new` 的轨道目标：
> - 若轨道命中 **多个 `Node3D`/`Bone`**（≥3 个不同节点）→ 节点动画，**可用**（翅膀/头像部件是分开的网格）；
> - 若**所有轨道只指向 1 个根节点** → **该模型作废**（动画只让整只龙平移，翅膀不扇）。

**风险评级**：比调研员的表述**更高**。1,154 三角面 / 772 顶点的 Blockbench 模型，若为单网格，则 5 条动画名全部是「驱动不了网格」的空壳——正是本次复核要抓的那一类。

### 5.6 落地还缺什么

1. **动画驱动性必须先验证**（§5.5），否则整个候选择不选都无从谈起。
2. **下载需登录**，不能进自动化流水线。
3. 风格：Blockbench + `minecraft` 标签 = **方块/Minecraft 风**，与 KayKit 的手绘贴图低多边形**不是一路**；且 `Attack.new` 只有 **0.5 s**，作为攻击动作偏短。
4. 页面上写「textures that can fit in pixel or low poly games」——贴图风格偏像素。

---

## 6. 候选 6：MattBas **Simple 3D Dragon Model**（OpenGameArt + itch.io，CC-BY-SA 4.0）

### 6.1 URL 可达性 ✅

| 页面 | 结果 |
|---|---|
| OGA | <https://opengameart.org/content/simple-3d-dragon-model> → **HTTP 200**，正标题 `Simple 3D Dragon Model`，`Author: MattBas`，`Wednesday, May 22, 2024`，`Art Type: 3D Art`，Tags `dragon / blender / rigged / flying / walk cycle` |
| itch | <https://mattbas.itch.io/dragon-model> → **HTTP 200**，正标题 `Simple 3D Dragon Model`，作者 `MattBas` |
| 作者自有站（许可凭证） | <https://dragon.best/3d/> → **HTTP 200**，页脚 `Copyright © 2017-2026 Mattia Basaglia` + `CC BY-SA` 链接 |

### 6.2 许可证原文 ✅（**包内 license.txt 两平台各一份，都写 CC BY-SA 4.0**）

| 来源 | 原文 |
|---|---|
| OGA 页面 | `License(s): CC-BY-SA 4.0` → `http://creativecommons.org/licenses/by-sa/4.0/` |
| **OGA 包内 `license.txt`**（94 B） | 逐字：<br>`3D dragon model by MattBas`<br>`License CC BY-SA: https://creativecommons.org/licenses/by-sa/4.0/` |
| **itch 包内 `license.txt`**（162 B，比 OGA 版多两行） | 逐字：<br>`3D dragon model by MattBas`<br>`License CC BY-SA: https://creativecommons.org/licenses/by-sa/4.0/`<br>`For the latest version of this model check https://dragon.best/3d/` |
| itch 页面 | 🔴 **grep `licen` = 0 命中** —— 页面正文/信息栏**确实完全没有许可声明**（调研员正确） |
| 作者自有站 | 页脚 `CC BY-SA` → `https://creativecommons.org/licenses/by-sa/4.0/`，`License info` |

### 6.3 🔴 冲突裁决：「两站许可口径不一致」是**假冲突**

`wide-scan.md` §0.3-3 与 §3 B6 判定：「itch 页无任何许可声明 … 两平台许可口径不一致 → 以 OGA 为准更安全」，并在 §9.1 建议「最终报告合并为一条，采用 CC-BY-SA 4.0」。

**我的裁决：结论（用 CC-BY-SA 4.0）正确，但「口径不一致」这个事实判断错误，理由链也要换。**

证据链：

1. 我按与 §4.4 相同的匿名流程，从 itch **实际下载了它自己的 `dragon.zip`**（**168,677 B**，`upload_id=10528775`）。
2. 该 zip 内含 **`license.txt`（162 B）→ CC BY-SA 4.0**（原文见 §6.2）。
3. 两包资产**逐字节相同**：

```
ea354a6fbea4422d5183bcbbe3d6049215e7a09c4740c20f61b8d476bf79c4c2  OGA_tarball/dragon.glb
ea354a6fbea4422d5183bcbbe3d6049215e7a09c4740c20f61b8d476bf79c4c2  itch_zip/dragon.glb
c7cd27b0d4ef3a1b77add8a6006d79fcf6b6c3a753d979c2eedf6dac16a15712  OGA_tarball/glax.png
c7cd27b0d4ef3a1b77add8a6006d79fcf6b6c3a753d979c2eedf6dac16a15712  itch_zip/glax.png
```

4. ⇒ **两个平台的下载包都携带同一份 CC-BY-SA 4.0 许可文件；itch 只是没把它写进网页。不存在许可冲突。**

**裁决**：以 **CC-BY-SA 4.0** 为准；**依据从「OGA 页面」升级为「包内 license.txt 原文（两平台各一份）」**。第三方印证：作者自有站 `dragon.best/3d/` 页脚亦标 CC BY-SA。

⚠️ **遗留风险（必须写进最终报告）**：**CC-BY-SA 4.0 的 ShareAlike 对「该模型及其改作」有传染性** —— 可商用 ✅、必须署名 MattBas ✅，但**若分发修改后的模型文件，修改版也须以兼容许可发布**。对商业闭源游戏而言，这条要在「模型文件层面」评估（游戏整体属聚合，通常不被传染，但存在解释分歧）。**若项目不愿承担这个不确定性，本候选与候选 1/2/3/4（CC0/CC-BY）相比是唯一带 SA 的。**

### 6.4 动画证据 ✅（字节级；🔴 真实名与页面 prose 不同）

**清单出处**：页面 prose 写 `Flying / Walking / Idle / Running`；**文件字节里的真实名不同**。

`dragon.glb`（**435,176 B**，generator `Khronos glTF Blender I/O v4.1.63`）：

| GLB 里真实动画名 | 时长 | 通道 | 驱动关节 |
|---|---|---|---|
| `Flying-loop` | 1.042 s | 195 | **65 / 65** |
| `Idle-loop` | 1.458 s | 195 | **65 / 65** |
| `Run-loop` | 0.833 s | 195 | **65 / 65** |
| `Walk-loop` | 1.667 s | 195 | **65 / 65** |

- `skins[0].joints = **65**`；**每条动画 195 通道、驱动全部 65 关节** ✅ ⇒ **真蒙皮，动画确实形变网格**（这一点比候选 5 明确）。
- 4 条时长 + 关键帧数据哈希互不相同 ✅（真 4 个动作）。
- 🔴 **`-loop` 后缀 + `Run-loop`/`Walk-loop` vs 页面的 `Running`/`Walking`** —— 按页面名硬编码查找会**全部 miss**。
- 三角面 **2,698**（解开两线共同的「面数未核实」）；网格名 `Dragon`；材质 `Toon`；贴图 `glax` **内嵌 bufferView** ⇒ 单文件自包含 ✅。
- **无攻击动画** ✅ 确认（4 条里没有 attack）。
- 页面注释（作者自己）：`I added a running animation and tweaked a bit the walk cycle`。

### 6.5 下载入口 ✅（两站都匿名直连，实测）

| 通道 | 实测 |
|---|---|
| **OGA 直链** | `https://opengameart.org/sites/default/files/dragon.tar_1.gz` → **HTTP 200，168,491 B** ✅（`wide-scan.md` 标「是否需登录未逐字节验证」→ **我验证了：无需登录**）。页面标 `168.5 Kb` 与实测 168,491 B 相符 |
| OGA 内容 | tar.gz 内 `dragon.glb` 435,176 B / `glax.png` 4,281 B / `license.txt` 94 B |
| **itch 匿名链** | 与 §4.4 同一套 5 步流程（purchase → csrf → `download_url` → file 端点 → 60s 签名直链）→ **HTTP 200，168,677 B**，全程无需登录 ✅ |
| itch 页面标称 | `dragon.zip 164 kB`、`dragon.blend 1.9 MB`（与实测 168,677 B ≈ 164.7 KiB 相符） |
| OGA 另一文件 | `dragon.blend` 2 Mb（我未下载，`.blend` 对本项目无用——`PawnModelRig` 只吃 glTF/GLB） |

### 6.6 落地还缺什么

1. **无攻击动画** —— 作为「要打的龙」不够用；只能做飞行怪/坐骑/场景生物。
2. **CC-BY-SA 4.0 的 ShareAlike**（§6.3 遗留风险）。
3. 动画名带 `-loop` 后缀，需别名表。
4. 只有 4 条，无受击/死亡动作 —— 死亡要靠项目自己合成或缩放淡出（本项目的 `LEGACY_SHRINK_SEC` 分支恰好可兜底）。
5. 65 关节 / 2,698 面对项目量级合适（基线 KayKit 6,952 面）。

---

## 7. Quaternius 站点级 QAL v1.0 vs 包页 CC0 —— 裁决

我逐字读了 <https://quaternius.com/license.html>（**HTTP 200**）：

- 标题：`Quaternius Asset License (QAL) v1.0`，**`Last updated: 8/28/2026`**
- 摘要原文：`You can use these assets, free of charge, in personal, educational, and commercial games and other projects, with no credit required. You just can't resell or redistribute the assets themselves as assets.`
- §2 `No attribution is required.`
- §3 限制**只有两条**：`(a)` 不得把素材本身（含改作后）作为独立素材/素材包/模板再分发或转售（**不限制**「把素材嵌进成品游戏后发行」）；`(b)` 不得冒称作者/不得谎称 Quaternius 背书。
- §7 原文：`We may publish updated versions of this License for future Asset releases. Changes will not apply retroactively to Assets you've already obtained under an earlier version; the version in effect at the time you obtained the Assets governs your use of them.`
- 🔴 **全文没有 NFT 条款，也没有 AI/ML 训练条款。**

**矛盾的两侧我都亲自确认了**：

| 侧 | 证据 |
|---|---|
| 站点级 = QAL | `/license.html` 正文如上；且**包页导航栏**有一个按钮 `licensebtn` 的 `onClick="window.location='/license.html'"`（原始 HTML 确认），所以包页上**同时存在**一个通往 QAL 的入口 |
| 包页字段 = CC0 | 三个包页的**信息栏字段**都是 `<div class="infoitem">…License<div class="text-right"><a href="https://creativecommons.org/publicdomain/zero/1.0/" target="_blank">CC0</a></div></div>` —— **显示 CC0、链接指向 CC0 1.0 deed** |
| 包内文件 = CC0 | 候选 1（528 B）与候选 2（374 B）的 `License.txt` **逐字写 CC0 1.0 Universal**；候选 3 **无此文件** |

**裁决：**

1. **候选 1 与候选 2 按 CC0 落地，证据充分** —— 包页字段 + 包内 `License.txt` **双重**独立证据，且 QAL §7 明文不追溯（「获得时点的版本」为准）。
2. **候选 3 只有包页单一证据**（无包内文件）⇒ 风险略高，但仍应按 CC0 处理，**必须自留包页快照**。
3. **即使按 QAL 口径也仍可商用**，但两点约束要落进流程：
   - QAL §3(a) 只约束「素材本身」。本项目把模型嵌进游戏成品 → **不受限**；但**不要把模型原样提交进公开仓库**（这一点对 `assets/` 入 git 的策略有影响，需 Lead 决策）。
   - QAL §7 不追溯 ⇒ **锁版本 + 留证**：下载当时就保存 `License.txt` 原件（候选 1 sha256 `2b04fed1…`、候选 2 sha256 `de990ef6…`）+ 包页 HTML 快照 + 抓取日期。
4. **不存在「CC0 被撤销」的风险**：CC0 一旦适用即不可撤回；QAL 是给「未来新发布的素材」用的。

---

## 8. `igmixer/cpDragon-gltf` 是否算数 —— 裁决（**不可用**）

两线都说「不建议/不推荐」，方向一致。但我把「为什么」查到了**根上，并需要更正两线的理由**：

| 我实测的 | 内容 |
|---|---|
| 仓库 `LICENSE`（1064 B） | `MIT License` / `Copyright (c) 2020 igmixer` —— **与两线所述一致** |
| 🔴 **`scene.gltf` 的 `asset.extras`（两线都没打开这个文件看）** | `{"author": "lolilith (https://sketchfab.com/lolilith)",`<br>` "license": "CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)",`<br>` "source": "https://sketchfab.com/models/f36b9f16c41d4ad2983215d89d89da3f",`<br>` "title": "Cyberpunk Dragon LD34"}`<br>generator = `Sketchfab-3.18.2` |
| 动画 | **只有 1 条：`Take 001`**（Sketchfab/FBX 自动生成的**无意义名**） |
| 网格 | 三角面 **5,180**、`skins[0].joints = 63`、网格名 `draak_phong2_0` |
| 贴图 | **外置**：`textures/phong2_{normal,emissive,baseColor}.png` ⇒ **非自包含** |
| 风格 | `Cyberpunk Dragon` —— **赛博朋克**，非西幻 |

**裁决：❌ 不可用（明确否决）。三条理由，且第一条与两线给出的不同：**

1. 🔴 **不是「授权链不明」，而是「已知的授权冲突」**：`igmixer` 在仓库根贴 MIT，但 glTF 的 `asset.extras` 自陈上游是 **lolilith 的 Sketchfab 模型「Cyberpunk Dragon LD34」，许可是 CC-BY-4.0**。⇒ 上游的**署名要求（须署 lolilith）不能被下游的 MIT 声明覆盖**；两线「授权链不明」的措辞应更正为「授权链已查明，且与仓库 LICENSE 冲突」。
2. **动画不可用**：只有 1 条 `Take 001`，驱动不了 `Idle/Walk/Attack/Death` 状态机。（两线均标「是否含动画未核实」→ **我核实了：有且仅有 1 条，且名字无意义**。）
3. **风格不符 + 非自包含**：赛博朋克机甲龙 + 3 张外置贴图。

---

## 9. 仍未核实清单（不猜，列出来）

| 项 | 原因 |
|---|---|
| **候选 5 的动画是否驱动网格形变** | 原始 glTF **需登录 Sketchfab**；viewer 载荷 `file.binz` **加密**（gzip/zlib/raw-deflate 全失败、无明文格式标记）。**已给精确证伪判据，见 §5.5** |
| **候选 3 的包内许可证** | 该 Drive 目录**确实没有** `License.txt`（我复核 6 个条目）；许可只有包页 CC0 一个来源 |
| 候选 3 预览图里「哪一只叫 `YellowDragon`」 | 预览图**未标注个体名字**；我能证实的是**整包风格 = Q 版浮空大头**，与「图中那只黄色带翼个体是 YellowDragon」属**推断** |
| 候选 5 页面宣称的「textures that can fit in pixel or low poly games」具体贴图尺寸/风格 | 需登录下载才能看；我只从页面文字读到该描述 |
| 本地基线 `placeholder_hero.glb` 的 76 动画 / 6,952 面 / 41 关节 | **引用 `lowpoly-cc0.md`，我未复核** —— 超出本次「只复核 6 个候选」的范围 |
| bocdagla 龙的**朝向**、Godot 内实际观感、`palette` 换色流程 | 需导入 Godot 实测，本次为「只写可 fetch/解析证据」的纸上取证（且我的写入范围仅限本文件） |

---

## 10. 复现命令（全部为本次实际执行）

```bash
# ---------- 站点级许可（QAL v1.0）----------
curl -sS -L "https://quaternius.com/license.html"

# ---------- 三个 Quaternius 包页：License 字段 + Formats ----------
for p in animatedmonster ultimatemonsters cutemonsters; do
  curl -sS -L "https://quaternius.com/packs/$p.html" -o $p.html
  grep -o 'infoitem.*License.*creativecommons[^"]*' $p.html      # 显示 CC0 → CC0 deed
  grep -o 'formats.svg.*Blend\|formats.svg.*glTF' $p.html        # animatedmonster 无 glTF
done

# ---------- Drive 公开目录（无需登录）----------
curl -sS -L "https://drive.google.com/embeddedfolderview?id=<FOLDER_ID>#list"
#   AMP 102H-oyUM8SGYi1mW0GOgkjEu7xSdaORA / UM 18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C
#   Cute 1zLLO_7ZoWgUsS4uooYnVSErQYRu1VdS0 / UM-Flying-glTF 1RDoNgoRYBNacHO-uRPfSxEgtc4U-EmaB
curl -sS -L "https://drive.google.com/uc?export=download&id=<FILE_ID>" -o out
#   包内 License.txt: AMP 1kmh71Y_VBZdwr9P_8iwM9yn8bRS9RXcG (528B, sha256 2b04fed1…)
#                     UM  16GqsDGESyEOfRbc4dS7EqAwkIUSIW4_y (374B, sha256 de990ef6…)
#   官方模型: UM/Flying/glTF/Dragon.gltf 1-mQSm6_oGt7-EEQfNj1dFWYgPQy4AdPC (427,100B)
#             UM/Flying/glTF/Dragon_Evolved.gltf 1Mcfuavq7F4itG9xhqc-20_IL257ZY2_3 (991,335B)
#             Cute/glTF/YellowDragon.gltf 1JuOhGmG0BXCdNA39M8qUQL6YuiQ_5zgH (634,125B)
#             AMP/FBX/Dragon.fbx 1dM_UUyuQSi73q1ez3NmVBfZZC7Q1kTek (874,204B)

# ---------- poly.pizza 免登录直链 + 许可字段 ----------
curl -sS -L "https://poly.pizza/m/VBvzjFIYws"        # "Licence":"CC0 1.0" / "No login required"
curl -sS -L "https://poly.pizza/m/3rUm1cN3yp" ; curl -sS -L "https://poly.pizza/m/LlwD0QNUPj"
curl -sS -L "https://static.poly.pizza/9714f533-5d2d-4cfd-b8f1-c8dfff64a672.glb" -o amp.glb      # 268,896B
curl -sS -L "https://static.poly.pizza/ae5b8510-1fa5-4d53-b943-a4f3b88fb629.glb" -o um.glb       # 251,540B
curl -sS -L "https://static.poly.pizza/90ed3740-d8c4-4910-88ce-ac2ed426022d.glb" -o umev.glb     # 436,000B
shasum -a 256 dragon-assets/poc/quaternius_dragon_evolved_polypizza.glb umev.glb   # 必须相同

# ---------- itch.io 匿名脚本直连（bocdagla / MattBas 通用）----------
# ① purchase 页取 <meta name="csrf_token">；② POST <game>/download_url 拿 signed 下载页；
# ③ signed 页取 data-upload_id；④ POST <game>/file/<id>?source=game_download 拿 60s 签名直链；⑤ GET 直链
UA='Mozilla/5.0'; J=cj.txt
curl -sS -L -A "$UA" -c $J -b $J "https://bocdagla.itch.io/low-poly-dragon/purchase" -o p.html
T1=$(grep -o '<meta name="csrf_token" value="[^"]*' p.html | cut -d'"' -f4)
curl -sS -L -A "$UA" -c $J -b $J -H 'X-Requested-With: XMLHttpRequest' \
  --data-urlencode "csrf_token=$T1" "https://bocdagla.itch.io/low-poly-dragon/download_url"   # → {"url": …}
# …下载页 → csrf + data-upload_id → POST …/file/<id>?source=game_download → {"url": 60s 签名}

# ---------- Sketchfab（匿名可取的部分）----------
MUID=b3b83f40265347dd90e4666c3e2a843c
curl -sS -L "https://api.sketchfab.com/v3/models/$MUID"            # isDownloadable:true; license CC-BY 4.0
curl -sS -L -H 'Accept: application/json' "https://sketchfab.com/i/models/$MUID"
#   mayDownloadThisModel:false / downloadType:"free" / metadata.isRigged:false
#   exporter.name:"Blockbench" / archiveSize:289654 / ext:"gltf"
curl -sS -L -H 'Accept: application/json' "https://sketchfab.com/i/models/$MUID/animations"
#   5 条 *.new + duration + isLoop(全 false)
curl -sS -L "https://sketchfab.com/models/$MUID/embed" | grep -o 'https://media.sketchfab.com/models/[^"&]*file.binz'
#   → 98,850B，加密，解不开（见 §5.5）

# ---------- OpenGameArt + MattBas ----------
curl -sS -L "https://opengameart.org/content/simple-3d-dragon-model"          # License(s): CC-BY-SA 4.0
curl -sS -L "https://opengameart.org/sites/default/files/dragon.tar_1.gz" -o d.tar.gz   # 168,491B 免登录
tar xzf d.tar.gz && cat license.txt        # → CC BY-SA 4.0
curl -sS -L "https://mattbas.itch.io/dragon-model"                            # grep -i licen → 0 命中
curl -sS -L "https://dragon.best/3d/"                                         # 页脚 CC BY-SA

# ---------- cpDragon ----------
curl -sS -L "https://raw.githubusercontent.com/igmixer/cpDragon-gltf/master/LICENSE"      # MIT (igmixer)
curl -sS -L "https://raw.githubusercontent.com/igmixer/cpDragon-gltf/master/scene.gltf"   # asset.extras → lolilith / CC-BY-4.0

# ---------- 本地字节解析（glTF/GLB）----------
# GLB: 读 header → 遍历 chunk → ctype==0x4E4F534A 的 JSON chunk → animations[].name / skins[].joints
#      / meshes[].primitives[].indices → accessors[].count//3 = 三角面
#      动画是否「真不同」：比较各 sampler 输出 accessor 的字节 sha1
#      动画是否「驱动网格」：统计 channels[].target.node 落在 skin.joints 里的数量
```

---

## 11. 给 Lead 的一句话汇总结论

**六条里真正「动画覆盖完整、可以直接进 Godot 状态机」的只有候选 4（bocdagla）** —— 它有地面待机 + 真迈步行走 + 地面起飞 + 飞行 + 攻击 + 受击姿共 6 条，76 关节全驱动，2,004 面，自包含 GLB，且**匿名脚本直连可下**；代价是 **CC-BY 无版本号 + zip 内无 LICENSE 文件**，需自己写 CREDITS 留痕。

**候选 1/2（Quaternius CC0）许可最干净、动画也真实，但三条 Quaternius 龙全部没有地面行走/待机** —— 只能做飞行怪/BOSS，贴地使用会「站着扇翅膀滑行」。**且候选 2 必须用官方 Drive `.gltf`，poly.pizza 直链拿到的是翼尖与脖子僵住的降级版（`dragon-assets/poc/` 里那个文件就是它）。**

**候选 6（MattBas）两站许可其实一致（都 CC BY-SA 4.0，包内各有 license.txt），但无攻击动作 + ShareAlike 传染性。**

**候选 3（YellowDragon）是 Q 版浮空大头龙，风格差距最大，且无随包许可**；**候选 5（DibArts Wyvern）动画能否驱动网格无法核实**，采用前必须先登录下载做 §5.5 的证伪测试。
