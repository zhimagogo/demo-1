# 怪物占位素材来源记录 — Quaternius *Ultimate Monsters*

> 本目录 8 个 `.gltf` 是 **CC0 1.0 Universal（公有领域奉献）** 素材，**零署名义务**。
> 按项目惯例仍留此来源记录（与 `assets/audio/CREDITS.md`、`assets/vfx/CREDITS.md` 同范式）。

## 来源

| 项 | 内容 |
|---|---|
| 素材包 | **Ultimate Monsters**（50 个全动画怪物） |
| 作者 | Quaternius |
| 官方包页 | <https://quaternius.com/packs/ultimatemonsters.html> |
| 发布 | 2022 年 10 月 |
| 许可 | [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) |
| 下载日期 | **2026-10-01**（Asia/Shanghai） |
| 获取方式 | 作者公开的 Google Drive 目录（`Big` / `Blob` / `Flying` 三个子目录），逐文件直连下载 |

包内 `License.txt` 原文（逐字，含行尾；`\n` 为换行）：

```
------------------------------------------------------
Ultimate Platformer Pack by @Quaternius
Consider supporting me on Patreon, even $1 helps me a lot!

https://www.patreon.com/quaternius
-------------------------------------------------------

License:
CC0 1.0 Universal (CC0 1.0) 
Public Domain Dedication
https://creativecommons.org/publicdomain/zero/1.0/
```

> 抬头误写 `Ultimate Platformer Pack` 是作者复制粘贴残留，与许可条款无关。
> 已核对副本：`dragon-assets/monsters/License.txt`（374 B，与上文字节一致）。

## 下载命令（可复现）

```bash
curl -sL "https://drive.google.com/uc?export=download&id=<FILE_ID>" -o <名字>.gltf
```

| 文件 | FILE_ID | 原目录 |
|---|---|---|
| `Orc.gltf` | `17675H4Owu5FeHUk_7Goyc9TKI5YK3cEM` | Big |
| `Ninja.gltf` | `1T45Ab6f3oX6m-r-kRqEOsmv0Yp9ySmDb` | Big |
| `MushroomKing.gltf` | `1sCGed1ce1CrdCdFz5bxVQMqphu5e3a1m` | Big |
| `Cactoro.gltf` | `19Po2Ae16TbImr6dCu7PRZdpPQhEA13OQ` | Big |
| `GreenBlob.gltf` | `1Qj3EPCAzN7P3KNrfjV_sFMw98nsBUyob` | Blob |
| `Yeti.gltf` | `1VpqldMiSmrmoDtTqA5PqOZ0FrPIKKjiP` | Blob |
| `Ghost.gltf` | `1rUs1QRA9v1Y2wRYEXsfteBisTsz4JlLi` | Flying |
| `Glub.gltf` | `1X-6f4qyrbloGVq3wf-IdxUgmuA0u1JGu` | Flying |

## 落盘校验（2026-10-01 实测）

每个文件均通过三项校验：① 首字节为 `{`（真 glTF JSON，不是 Drive 确认页）；② 体积非 0；
③ `python3 -c "import json;json.load(open('f.gltf'))"` 可解析。

| 文件 | 字节 | sha256 | 三角面 | 骨骼 | 动画 | 内嵌图集 |
|---|---:|---|---:|---:|---:|---|
| `Orc.gltf` | 1,280,189 | `e61a37f8d9b2eee2…` | 7,344 | 43 | 14 | `Atlas_Monsters` 1024², 9,007 B |
| `Ninja.gltf` | 1,226,528 | `f1042e533bd24b98…` | 5,964 | 43 | 14 | `Atlas_Monsters` 1024², 9,007 B |
| `MushroomKing.gltf` | 1,219,690 | `ccf27e126b881d80…` | 6,044 | 43 | 14 | `Atlas_Monsters` 1024², 9,007 B |
| `Cactoro.gltf` | 1,261,358 | `29051fc39751fa5b…` | 6,398 | 43 | 14 | `Atlas_Monsters` 1024², 9,007 B |
| `GreenBlob.gltf` | 148,007 | `e2d2049ebe8d243b…` | 1,520 | 4 | 9 | `Atlas_Monsters` 32², 912 B |
| `Yeti.gltf` | 191,774 | `44b0627cc6511275…` | 2,136 | 4 | 9 | `Atlas_Monsters` 32², 912 B |
| `Ghost.gltf` | 643,180 | `40bea9d887874cc8…` | 3,192 | 38 | 8 | `Atlas_Monsters` 32², 927 B |
| `Glub.gltf` | 308,583 | `54f638cef5aae04f…` | 2,528 | 13 | 8 | `Atlas_Monsters` 32², 927 B |

完整 sha256 见本节末「附：完整哈希」。

## ⚠️ 关于 `Atlas_Monsters.png`（重要，且与任务书初稿的「已确认事实」有出入）

**每个 `.gltf` 都是自包含的**：唯一 buffer 是 `data:` URI（内嵌 base64），
唯一 image 走 `bufferView` 内嵌，**外部 URI 计数 = 0**。
因此这 8 个文件**没有任何外挂依赖**，可直接被 `GLTFDocument` / 引擎导入器读取。

任务书初稿写「共用一张 `Atlas_Monsters.png`（9,007 B）」——**逐字节核对后需修正**：
8 个文件里内嵌图的**节点名都叫 `Atlas_Monsters`**，但实际是 **3 份内容不同的 PNG**：

| 分组 | 成员 | 内嵌图集 | 字节 | sha256[:12] |
|---|---|---|---:|---|
| Big | Orc / Ninja / MushroomKing / Cactoro | 1024×1024 | 9,007 | `b970ed1359ce` |
| Flying | Ghost / Glub | 32×32 | 927 | `ce8ee9c55f5e` |
| Blob | GreenBlob / Yeti | 32×32 | 912 | `df160c995a71` |

即：只有 **Big 组**那张是任务书说的 9,007 B 图集；Blob / Flying 组各自带一张**同名但更小**的 32² 图集
（这也解释了实渲观感差异——Big 组有人脸/装备细节，Blob / Flying 组基本是平涂色块）。

**运行不依赖上面任何一张**（已内嵌）。为留底与取证，三张图集已抽出到 `atlas_archive/`：

- `atlas_archive/Atlas_Monsters_Big.png`（1024², 9,007 B, `b970ed1359ce749f…`）← 抽自 `Orc.gltf`
- `atlas_archive/Atlas_Monsters_Flying.png`（32², 927 B, `ce8ee9c55f5eb724…`）← 抽自 `Ghost.gltf`
- `atlas_archive/Atlas_Monsters_Blob.png`（32², 912 B, `df160c995a714004…`）← 抽自 `GreenBlob.gltf`

> **`atlas_archive/` 仅存档，不是运行依赖。** 目录根下**刻意不放**同名 `Atlas_Monsters.png`，
> 以免被误当成「8 个模型共用的外挂贴图」。

### 交叉校验（独立复现）

`dragon-assets/monsters/` 下在本次任务前已有 Lead / dragon-poc 放的参考副本，
逐字节对比确认**下载链路无损**：

| 文件 | 结果 |
|---|---|
| `Orc.gltf` | **IDENTICAL** `e61a37f8d9b2eee28928bdfad2c55e0798cc0a212e925cc5dcc66b243526c1a3` |
| `GreenBlob.gltf` | **IDENTICAL** `e2d2049ebe8d243bd0f60a3f48a7e174444f641ebc40cbea2f6c23cb97a82519` |
| `Ghost.gltf` | **IDENTICAL** `40bea9d887874cc86b391b83e72cc5ac2cac340892e23f3d8068a568b6e61457` |
| `atlas_archive/Atlas_Monsters_Big.png`（抽自 `Orc.gltf`） | **IDENTICAL** 于 `dragon-assets/monsters/Atlas_Monsters.png`，`b970ed1359ce749f…` |

⇒ ① 下载无损坏；② 独立证明 **Big 组内嵌的图集就是那张 9,007 B 的 `Atlas_Monsters.png`**。

### Godot 导入器自动生成的旁挂文件（非手工，勿手改）

项目跑过一次编辑器导入（`godot --editor --quit` 重建类缓存）后，本目录多出：

- `*.gltf.import`、`*.png.import` —— Godot 标准导入产物（**不要手改**，同 `.uid` 约定）
- `<名字>_Atlas_Monsters.png` —— **导入器把内嵌图集抽出来的旁挂副本**（Orc/Ninja/MushroomKing/Cactoro/Ghost/Glub/GreenBlob/Yeti 各一份）

第三重交叉校验：这些旁挂副本与 `atlas_archive/` 中的存档**逐字节一致**：

```
b970ed1359ce749f…  Orc_Atlas_Monsters.png        == atlas_archive/Atlas_Monsters_Big.png
ce8ee9c55f5eb724…  Ghost_Atlas_Monsters.png      == atlas_archive/Atlas_Monsters_Flying.png
df160c995a714004…  GreenBlob_Atlas_Monsters.png  == atlas_archive/Atlas_Monsters_Blob.png
```

⇒ 三份图集的划分再次被独立证实。
导入之后 `load("res://assets/_PLACEHOLDER/monsters/Orc.gltf")` 可直接作为 `PackedScene` 使用
（导入前需走 `GLTFDocument` 运行时解析回退）。

## 附：完整哈希

```
29051fc39751fa5b3af69f7bce77297c620651b1b2235bbd644962bd6a895461  Cactoro.gltf
40bea9d887874cc86b391b83e72cc5ac2cac340892e23f3d8068a568b6e61457  Ghost.gltf
54f638cef5aae04f4d00874d8cbbfadd863697157fedad7c5e6e5cb9724abbb0  Glub.gltf
e2d2049ebe8d243bd0f60a3f48a7e174444f641ebc40cbea2f6c23cb97a82519  GreenBlob.gltf
ccf27e126b881d80a2046c3ab96ddd94eb996837480e783142009ecd6629a3a4  MushroomKing.gltf
f1042e533bd24b98ceee179eaf4119517051fd745feb8d71af1b78a4ac3c88a3  Ninja.gltf
e61a37f8d9b2eee28928bdfad2c55e0798cc0a212e925cc5dcc66b243526c1a3  Orc.gltf
44b0627cc65112756642f2d0de529a1fba9d74c4fbc9829b572d90625bbb842f  Yeti.gltf
b970ed1359ce749fd81a8395d58ff5f3044d843213e17fb94b97892d417c0af9  atlas_archive/Atlas_Monsters_Big.png
df160c995a7140049b259c8b9974130f498a577f1e50312b1e7bed17b2f44927  atlas_archive/Atlas_Monsters_Blob.png
ce8ee9c55f5eb7249372c033d1fd2a35381d4eeed2eea971997067694455eb04  atlas_archive/Atlas_Monsters_Flying.png
```

（`shasum -a 256 atlas_archive/*.png` 实测输出。）

## 使用提示（比例）

这 8 个模型**原始尺寸普遍偏大**（人形怪实渲高 2.9~3.8 m），
直接 `model_scale = 1.0` 会明显高于当前占位人类（游戏内 2.29 m）。
逐模型的 AABB / 实渲高 / 换算公式 / 建议 `model_scale` 见：

- `dragon-assets/monsters/REPORT.md`
- `dragon-assets/monsters/contact_sheet_calibrated.png`（同框对照，含 1 m 网格与人类身高绿线）

朝向：8 个模型**原生朝 +Z**（与 KayKit 一致）→ 项目里 `model_face_offset_deg` 取 **180°**，
与现有 `raider_def` 等 KayKit 单位的配置一致（证据：`contact_sheet_front.png`）。
