# Medieval-Hexagon-Pack 资源目录（选用索引）

> **用途**：本游戏要加新模型时，**先查本文档**找有没有合适的，再去仓库拉对应文件——
> 避免每次全量搜索 221 个文件。本表是按「对本游戏适配度」筛选 + 标注用途的**选用索引**，非全量清单。

## 概况
- **仓库**：https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 （CC0 1.0）
- **风格**：低多边形 Q 版 —— 与本游戏 KayKit 角色统一
- **格式**：分离的 `.gltf` + `.bin` + 共用 atlas `hexagons_medieval.png`（**不是**自包含 .glb）
- **规模**：221 个 `.gltf` = **144 种唯一模型**（39 建筑 + 40 六边形地块 + 65 装饰）；彩色建筑各有 blue/green/red/yellow 四色变体
- **本地完整副本**（含 obj/fbx 等所有格式）：`/tmp/kaykit_mh/` ⚠️ 可能被系统清理，需要时重新 clone
- **预览图**：仓库 `Samples/sample1.jpg`、`sample2.jpg`

## 拉新模型进游戏（3 步）
1. **复制文件**：从仓库 `Assets/gltf/<路径>/<模型>.gltf` + 同名 `.bin` → `res://assets/_PLACEHOLDER/medieval_hexagon_buildings/`。**保留原名**（.gltf 内部 URI 写死 .bin/.png 名，改名会加载失败）。atlas png 已在目录里共用，**不用重复拉**。
2. **接线**：
   - 建筑类 → `GameDefs.building_defs()` 给对应 def 设 `model_path` + `model_scale`
   - 主城等特殊 → `Main.gd` 或对应实体
   - 资源节点等 → 对应实体脚本（当前 ResourceNode 是 BoxMesh，可挂 `BuildingModelRig`）
3. **调视觉**：跑 `godot --editor --quit` 重建缓存 → 编辑器看 → 调 `model_scale` / `model_height_offset` / `model_face_offset_deg`

> 加载机制：建筑用 `BuildingModelRig`、角色用 `PawnModelRig`。视觉模型当「皮」，不影响寻路（AStarGrid2D 按 footprint）和碰撞（BoxShape3D 按 mesh_size）。

## 尺寸速读
- 单位米，来自 .gltf accessor min/max。`y起≠0` 表示**模型悬浮或原点偏中**，需 `model_height_offset` 修正。
- 网格 `cell_size = 2.0`（一格 2m）。建筑占地由 `BuildingDef.footprint`（格）决定，碰撞由 `mesh_size` 决定，**与视觉模型无关**。

---

## ✅ 已导入（7）
| 模型 | 尺寸 W×H×D (m) | y起 | 用途 | scale |
|---|---|---|---|---|
| building_castle_blue | 1.98×3.98×2.26 | 0 | 主城 BaseCore | 2.0 |
| building_barracks_blue | 1.44×1.64×1.57 | 0 | 兵营 | 2.2 |
| building_home_A_blue | 0.79×0.93×0.85 | 0 | 房屋 | 1.9 |
| building_tavern_blue | 1.17×1.40×1.33 | 0 | 酒馆（v22 小兵疗伤据点） | 3.4 |
| building_tower_base_blue | 0.93×1.50×1.11 | 0 | 箭塔 | 2.0 |
| wall_straight | 2.00×1.10×0.80 | 0 | 城墙 | 1.0 |
| fence_wood_straight | 0.10×0.55×1.15 | -0.05 | 备用（木围栏，暂未映射） | — |

> v22：农田/市集/箭塔建筑已从 `building_defs()` 移除（经济统一金币 + 新增酒馆疗伤），
> tower_base 条目保留作历史参照与复用索引。

---

## 🎯 推荐导入

### A. 资源节点（当前 ResourceNode 是 BoxMesh，收益最高）
木材/石头正是本游戏的两种资源，强烈建议接这两个。

| 模型 | 尺寸 | y起 | 源路径 | 建议用途 |
|---|---|---|---|---|
| resource_lumber | 0.69×0.21×0.33 | 0 | decoration/props/ | **木材**资源节点（矮堆，scale~4） |
| resource_stone | 0.42×0.28×0.36 | 0 | decoration/props/ | **石头**资源节点（scale~5） |
| tree_single_A | 0.57×1.20×0.55 | -0.10 | decoration/nature/ | 树（资源/地图装饰） |
| tree_single_A_cut | 0.17×0.33×0.16 | -0.10 | decoration/nature/ | 砍伐树桩（采集后状态） |
| rock_single_A | 0.30×0.07×0.28 | 0 | decoration/nature/ | 岩石（贴地扁石） |

### B. 建筑多样化（除注明外都贴地，y起≈0）
| 模型 | 尺寸 | 源路径 | 建议用途 |
|---|---|---|---|
| building_home_B_blue | 0.87×1.28×1.10 | buildings/blue/ | 第二种住宅（殖民者房屋多样） |
| building_archeryrange_blue | 1.67×1.79×1.55 | buildings/blue/ | 弓箭场（远程兵视觉） |
| building_blacksmith_blue | 1.29×0.99×1.25 | buildings/blue/ | 铁匠铺（升级/经济） |
| building_mine_blue | 1.61×1.14×1.92 | buildings/blue/ | 矿场（石头产出） |
| building_market_blue | 1.80×0.98×1.32 | buildings/blue/ | 集市（金币产出） |
| building_windmill_blue | 1.00×1.00×0.11 | buildings/blue/ | 风车（食物产出）⚠️ y起-0.5 需 offset +0.5 |
| building_watermill_blue | 1.05×1.05×0.42 | buildings/blue/ | 水车 ⚠️ y起-0.53 需 offset |
| building_tavern_blue | 1.17×1.40×1.33 | buildings/blue/ | 酒馆 |
| building_church_blue | 1.03×1.65×1.16 | buildings/blue/ | 教堂 |
| building_well_blue | 0.65×0.83×0.75 | buildings/blue/ | 水井（小装饰） |
| building_lumbermill_blue | 0.28×0.49×0.49 | buildings/blue/ | 伐木场 ⚠️ y起-0.24 需 offset |
| building_grain | 1.87×0.39×2.09 | buildings/neutral/ | 农田（平铺贴地，食物产出） |

### C. 城防完善
| 模型 | 尺寸 | 源路径 | 建议用途 |
|---|---|---|---|
| wall_corner_A_outside | 1.76×1.10×1.43 | buildings/neutral/ | 城墙拐角（外角） |
| wall_corner_A_inside | — | buildings/neutral/ | 城墙拐角（内角） |
| wall_corner_B_outside / inside | — | buildings/neutral/ | 另一组拐角变体 |
| wall_straight_gate | 0.45×0.79×0.18 | buildings/neutral/ | 城门（直线段） |
| wall_corner_A_gate | 0.43×0.79×0.31 | buildings/neutral/ | 城门（拐角） |
| projectile_catapult | 0.24×0.28×0.25 | buildings/neutral/ | 投石车弹药（可作投射物） |

### D. 阵营标识（本游戏 team 0=玩家蓝 / 1=敌人红）
| 模型 | 尺寸 | 源路径 | 建议用途 |
|---|---|---|---|
| flag_blue / green / red / yellow | 0.06×0.28×0.26 | decoration/props/ | 阵营旗（蓝=玩家、红=敌人） |

### E. 其他（地图氛围）
| 模型 | 尺寸 | 源路径 | 注意 |
|---|---|---|---|
| building_bridge_A | 1.33×1.25×1.92 | buildings/neutral/ | 桥 ⚠️ y起-1.0 需大幅 offset |
| building_destroyed | 1.54×0.99×1.31 | buildings/neutral/ | 废墟（建筑被毁视觉） |
| building_stage_A / B / C | ~1.05×0.29 | buildings/neutral/ | 舞台/平台（装饰） |

---

## ⚠️ 避坑
- **tower_A / tower_B 悬空**（y起 1.28，是城墙顶上的塔楼，非独立塔）——独立塔**只用 tower_base**（贴地）。若非要用 A/B，设 `model_height_offset = -1.28`。
- **风车/水车/伐木场/桥** 原点在模型中部（y起为负），需正 `model_height_offset` 抬起贴地（约 +0.5 / +0.24 / +1.0）。
- **资源堆很矮**（木材堆 H0.21、石头堆 H0.28）——作资源节点要放大（scale 4~5）才显眼，或接受贴地矮堆。
- **彩色建筑 4 色**：本游戏建筑都是玩家方，统一用 `_blue`；若将来敌人有建筑，用 `_red` / `_green` / `_yellow`。

## 🚫 暂不适用
- **tiles/（40 种六边形地块）**：本游戏是方格（cell 2.0），六边形地块用不上，除非改地形系统。含：草地/水/海岸/河流/道路（各带斜坡变体）。
- **cloud_big / small**：云，无游戏用途。
- 其余未列的纯装饰道具（bucket / wheelbarrow / sack / barrel / crate 等 23 种 props）按需自取，仓库 `Assets/gltf/decoration/props/` 下可浏览。

## 📚 其他备选资源源（CC0）

> 选资源时不止看 Medieval-Hexagon，也可考虑下面这些源。已按「对本游戏契合度」标注，**避免重复调研**。
> 风格统一性提醒：KayKit 系列同作者、风格一致可放心混用；Quaternius / Kenney 是不同作者，混用前先并排对比色感/比例。

### KayKit 同系列（同作者，风格统一）— https://github.com/KayKit-Game-Assets
| 仓库 | 主题 | 契合度 | 说明 |
|---|---|---|---|
| Character-Pack-Adventurers | 人形角色 5 个 | ✅ 已用 | 主角 + 殖民者 |
| Character-Pack-Skeletons | 骷髅角色（同骨架同动画） | 🎯 **推荐接入** | 做 Raider 敌人（当前仍是胶囊） |
| Medieval-Hexagon-Pack | 中世纪建筑 | ✅ 已用 | 见本文档主体 |
| City-Builder-Bits | 现代城市：汽车/红绿灯/消防栓/水塔 | ❌ 不搭 | 现代风，与中世纪冲突（已调研确认） |
| Dungeon-Remastered | 地牢环境：墙/地板/门 + 宝箱/陷阱/木桶（200+，**无角色**） | ⚠️ 低 | 室内地牢，本游戏室外；仅陷阱/宝箱/木桶可借作防御设施/资源装饰 |
| Furniture-Bits | 室内家具 | ❌ 低 | 本游戏室外 RTS |
| Prototype-Bits | 原型占位几何 | ❌ 过时 | 已用真实模型 |
| Restaurant-Bits | 餐厅/食物 | ❌ 不搭 | 现代风 |
| Space-Base-Bits | 科幻基地 | ❌ 不搭 | 科幻风 |
| Halloween-Bits | 万圣节（南瓜/鬼） | ❌ 低 | 节日限定 |

### 其他 CC0 源（不同作者，混用需评估风格统一）
| 源 | 方向 | 何时考虑 |
|---|---|---|
| **Quaternius** | 低多边形系列权威（Nature / Medieval / Fantasy 等） | 要更多怪物种类或植被地形时；换源需为新骨架单独配 `PawnModelRig.ANIM_MAP`（动画名不同） |
| **Kenney**（kenney.nl） | 海量 CC0，含 Castle / Medieval / Nature kit | 同上；Kenney 偏更几何抽象，与 KayKit Q 版可能有差 |

> **换源决策**：本游戏人形角色已达 KayKit 上限（5 个）。若要突破——更多怪物种类（不止骷髅）或更丰富植被——考虑 Quaternius Fantasy/Nature。建筑/资源目前 Medieval-Hexagon 够用。

---

## 附：全量浏览
需要本文档没列的模型时，看仓库 `Assets/gltf/` 目录树，或本地 `/tmp/kaykit_mh/`（若还在）。全套 144 种：建筑 39（见上）+ 地块 40（六边形）+ 装饰 65（props 23 + nature 42）。
