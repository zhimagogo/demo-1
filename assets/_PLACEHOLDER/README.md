# 占位美术资源（PLACEHOLDER）

> ⚠️ 本目录下所有资源都是**临时占位**，后续会被正式美术替代。一眼可辨：目录名 `_PLACEHOLDER` + 文件名 `placeholder_*`。

## 来源
- **KayKit - Character Pack: Adventurers**（Knight / Rogue / Rogue_Hooded / Barbarian / Mage 共 5 角色）
- 仓库：https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
- 许可证：**CC0 1.0**（公有领域：免费商用、无需署名）

## 当前文件
| 文件 | 来源角色 | 项目用途 |
|---|---|---|
| `characters/placeholder_hero.glb` | Knight | 主角（战士职业） |
| `characters/placeholder_colonist.glb` | Rogue | 殖民者候选之一 |
| `characters/placeholder_colonist_barbarian.glb` | Barbarian | 殖民者候选之一 |
| `characters/placeholder_colonist_mage.glb` | Mage | 殖民者候选之一 |
| `characters/placeholder_colonist_rogue_hooded.glb` | Rogue_Hooded | 殖民者候选之一 |

每个 GLB **自带 76 个动画、贴图全内嵌**，单文件自包含，无外部依赖。
5 个角色同骨架同动画，换皮即用、动画映射（见下）通用。

## 加载方式
代码用 `PawnModelRig`（[scripts/components/PawnModelRig.gd](scripts/components/PawnModelRig.gd)）运行时加载：
- 优先 `load()`（编辑器自动导入的 PackedScene，glTF 动画导入最可靠）
- 失败回退 `GLTFDocument` 运行时解析（不依赖编辑器导入缓存）

模型路径在 `GameDefs` 里以 `PawnDef.model_path` 指定。
**殖民者配了 `model_path_pool`**（见 `colonist_def()`）：每个实例从池里随机抽一个 → 外观多样化；
单一造型的角色（主角）仍用 `model_path`。

## 动画映射（项目状态/动作 → glTF 动画名）
见 `PawnModelRig.ANIM_MAP`：

| 项目 key | glTF 动画 | 说明 |
|---|---|---|
| `idle` | `Idle` | 待机（所有 Pawn） |
| `move` | `Walking_A` | 移动 |
| `run` | `Running_A` | 主角 WASD 奔跑 |
| `harvest` | `PickUp` | 殖民者采集 |
| `fight` | `1H_Melee_Attack_Slice_Horizontal` | 普通单位攻击 |
| `follow` | `Walking_A` | 小队跟随 |
| `dead` | `Death_A` | 死亡 |
| `combo_light` | `1H_Melee_Attack_Slice_Diagonal` | 主角轻击 |
| `combo_heavy` | `1H_Melee_Attack_Chop` | 主角重击 |
| `skill_aoe` | `2H_Melee_Attack_Spin` | 旋风斩 |
| `skill_dash` | `Dodge_Forward` | 冲锋斩 |

## 替换为正式美术（5 步）
1. 把正式模型的 `.glb` 放进本目录（或新建 `res://assets/characters/` 等正式目录）
2. 改 `GameDefs` 里对应 def 的 `model_path`（多外观角色如殖民者，则改 `model_path_pool` 数组）
3. 新资源动画名不同 → 更新 `PawnModelRig.ANIM_MAP`
4. 模型背对前方 → 调 def 的 `model_face_offset_deg`（通常 0 或 180）
5. 模型大小不对 → 调 `model_scale`

把本目录（或 def 的 `model_path` 置空）即可回退到胶囊占位。

---

## medieval_hexagon_buildings/（建筑模型）

> 📋 要从这套包选更多模型？见选用索引 [medieval_hexagon_catalog.md](medieval_hexagon_catalog.md)（按本游戏适配度分类 + 尺寸 + 用途 + 避坑）。

- **来源**：KayKit - Medieval Hexagon Pack（`KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0`，CC0 1.0）
- **格式**：分离的 `.gltf` + `.bin` + 共用贴图 `hexagons_medieval.png`（15K atlas）——**不是**自包含 .glb。
- **命名**：**保留 `building_*` / `wall_*` 原名，不加 `placeholder_` 前缀**。原因：.gltf 内部 `buffers[].uri` / `images[].uri` 写死了 .bin / .png 文件名，改名要同步改 JSON，风险大不抵收益。目录名已足够标识占位身份。
- **共享依赖**：`hexagons_medieval.png` 是所有建筑的共用 atlas，**勿删、勿改名**——删了全部建筑变粉。

### 当前文件
| 文件 | 用途 |
|---|---|
| `building_castle_blue.gltf/.bin` | 主城 BaseCore |
| `building_barracks_blue.gltf/.bin` | 兵营 |
| `building_home_A_blue.gltf/.bin` | 房屋 |
| `building_tower_base_blue.gltf/.bin` | 箭塔（贴地独立塔；tower_A 悬空故不用） |
| `wall_straight.gltf/.bin` | 城墙（neutral 中性色，所有玩家通用） |
| `fence_wood_straight.gltf/.bin` | 木围栏（备用） |
| `hexagons_medieval.png` | 共用 atlas 贴图 |

### 加载方式
代码用 `BuildingModelRig`（[scripts/components/BuildingModelRig.gd](../../scripts/components/BuildingModelRig.gd)）运行时加载，机制与角色 `PawnModelRig` 一致（`load()` 优先，`GLTFDocument` 回退）。建筑无动画，故组件去掉了动画逻辑。

> **架构支点**：寻路用 AStarGrid2D 2D 格子（`_set_building_solid` 只按 `BuildingDef.footprint` 标记占地），单位碰撞用 CollisionShape3D（size=`mesh_size`）——两者都不读视觉 mesh。所以建筑模型是「皮」，任意缩放/偏移都不影响寻路、碰撞、占地。

模型路径与缩放在 `GameDefs.building_defs()` 里以 `BuildingDef.model_path` / `model_scale` 指定；主城 castle 在 `Main.gd._create_base_core()` 硬编码。

### 替换为正式美术
1. 换 `.gltf` + `.bin`（同名覆盖，或改 GameDefs 的 `model_path`）；贴图换 `hexagons_medieval.png`。
2. 尺寸不对 → 调 `BuildingDef.model_scale`。
3. 悬浮 / 沉地 → 调 `model_height_offset`。
4. 门朝向不对 → 调 `model_face_offset_deg`。

清空对应 `model_path` 即回退到 BoxMesh 占位。

---

## v40 主题区域新增模型（medieval_hexagon_props/ + nature/ + buildings/）

> v40 世界扩张新增六个主题区域（区域数据见 `scripts/defs/WorldRegions.gd`，地标实现在
> `scripts/decor/ThemedRegions.gd`）。区域地标用到的建筑 / 道具 / 植被模型全部来自同一套
> **KayKit - Medieval Hexagon Pack**，与上面的建筑模型同源同授权。

- **来源**：KayKit - Medieval Hexagon Pack（`KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0`）
- **许可证**：**CC0 1.0**（公有领域：免费商用、无需署名；仓库根目录 `LICENSE.txt`）
- **拉取方式**：GitHub raw
  `https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0/main/addons/kaykit_medieval_hexagon_pack/Assets/gltf/<子目录>/<名字>.gltf`
  以及同名 `.bin`（同目录）
- **格式**：分离 `.gltf` + `.bin` + 共用 atlas `hexagons_medieval.png`（不是自包含 .glb；
  三者必须同目录，**保留原文件名**——.gltf 内部 `buffers[].uri` / `images[].uri` 写死相对路径）
- **加载**：`ThemedRegions._load_model_scene()`：`load()` 优先（编辑器导入的 PackedScene），
  失败回退 `GLTFDocument` 运行时解析。**纯视觉，不加任何 CollisionShape3D**。

### medieval_hexagon_props/（区域道具，13 个模型 + 复用 atlas）

| 文件 | 源路径（Assets/gltf/ 下） | 项目用途 |
|---|---|---|
| `flag_red.gltf/.bin` | `decoration/props/` | 烬誓战场：折断的红旗 |
| `weaponrack.gltf/.bin` | `decoration/props/` | 烬誓战场：武器架 |
| `target.gltf/.bin` | `decoration/props/` | 烬誓战场：箭靶 |
| `bucket_arrows.gltf/.bin` | `decoration/props/` | 烬誓战场：箭桶 |
| `barrel.gltf/.bin` | `decoration/props/` | 矿坑 / 沼地：木桶 |
| `crate_A_small.gltf/.bin` | `decoration/props/` | 矿坑：木箱 |
| `crate_A_big.gltf/.bin` | `decoration/props/` | 矿坑：大木箱 |
| `crate_long_A.gltf/.bin` | `decoration/props/` | 矿坑：长条箱 |
| `pallet.gltf/.bin` | `decoration/props/` | 矿坑：货板 |
| `wheelbarrow.gltf/.bin` | `decoration/props/` | 矿坑：独轮车 |
| `ladder.gltf/.bin` | `decoration/props/` | 矿坑 / 战场：梯子 |
| `sack.gltf/.bin` | `decoration/props/` | 麦场 / 矿坑：麻袋 |
| `resource_stone.gltf/.bin` | `decoration/props/` | 矿坑：废石料 |
| `hexagons_medieval.png` | （从 `medieval_hexagon_buildings/` 复制） | 本目录共用 atlas（**勿删**） |

### medieval_hexagon_buildings/ 新增（5 个模型）

| 文件 | 源路径（Assets/gltf/ 下） | 项目用途 |
|---|---|---|
| `building_mine_blue.gltf/.bin` | `buildings/blue/` | 星落矿坑：矿洞入口（scale 4.0，正面朝探索小径） |
| `building_windmill_blue.gltf/.bin` | `buildings/blue/` | 风吟麦海：风车（scale 4.2） |
| `building_well_blue.gltf/.bin` | `buildings/blue/` | 风吟麦海：水井 |
| `building_grain.gltf/.bin` | `buildings/neutral/` | 风吟麦海：农田（6 块，scale 2.2） |
| `building_destroyed.gltf/.bin` | `buildings/neutral/` | 烬誓战场：半塌城墙（3 段） |

> ⚠️ **风车 y 偏移的坑**：`medieval_hexagon_catalog.md` 里写 `building_windmill_blue`「y 起 -0.5，
> 需 offset +0.5」是**只量了风叶网格**（`building_windmill_top_fan`，单看它 y∈[-0.5, 0.5]）。
> 整场景实测 y 从 0 到 1.46——**不需要任何 y 偏移**，加 +0.5 反而整座风车浮空。

### nature/ 新增（16 个模型，v40 区域植被）

| 文件 | 源路径（Assets/gltf/ 下） | 项目用途 |
|---|---|---|
| `tree_single_B.gltf/.bin` | `decoration/nature/` | 区域古树（候选） |
| `tree_single_B_cut.gltf/.bin` | `decoration/nature/` | 盐风沼地：树桩 |
| `trees_A_small.gltf/.bin` | `decoration/nature/` | 区域树（候选） |
| `trees_A_medium.gltf/.bin` | `decoration/nature/` | 区域树（候选 / 旧模型回退） |
| `trees_A_large.gltf/.bin` | `decoration/nature/` | 雾隐密林：古树 |
| `trees_B_small.gltf/.bin` | `decoration/nature/` | 区域树（候选） |
| `trees_B_medium.gltf/.bin` | `decoration/nature/` | 区域树（候选） |
| `trees_B_large.gltf/.bin` | `decoration/nature/` | 雾隐密林：古树 |
| `trees_A_cut.gltf/.bin` | `decoration/nature/` | 盐风沼地：倒伏枯树 |
| `trees_B_cut.gltf/.bin` | `decoration/nature/` | 沼地 / 战场枯树（候选） |
| `rock_single_C.gltf/.bin` | `decoration/nature/` | 星落矿坑：裸岩（候选） |
| `rock_single_D.gltf/.bin` | `decoration/nature/` | 星落矿坑：裸岩（候选） |
| `rock_single_E.gltf/.bin` | `decoration/nature/` | 星落矿坑：裸岩（候选） |
| `waterplant_B.gltf/.bin` | `decoration/nature/` | 盐风沼地：芦苇（候选） |
| `waterplant_C.gltf/.bin` | `decoration/nature/` | 盐风沼地：芦苇 |
| `waterlily_A.gltf/.bin` | `decoration/nature/` | 水塘浮叶（备用） |

> 这批 nature 模型由 `ThemedRegions`（地标氛围）与 `DecorationScatter._scatter_regions()`（分区植被）
> 共用；两处都先 `ResourceLoader.exists()` 判断，缺失时静默回退旧模型，不阻塞主场景加载。
> `nature/hexagons_medieval.png` 是这套模型的共用 atlas，**勿删、勿改名**。
