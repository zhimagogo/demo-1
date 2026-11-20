# Quaternius *Ultimate Monsters* — 比例校准报告（task-5 / monster-assets）

日期：**2026-10-01** ｜ 执行：`monster-assets`（素材与量测员）
Godot 4.7.1.stable.official.a13da4feb ｜ Metal 3.2 / Forward+ / Apple M4

---

## 0. 结论速览

| 项 | 结论 |
|---|---|
| 8 个模型是否全部到手 | ✅ **8/8 全部到手并通过三重校验**（首字节 `{` / 体积非 0 / `json.load` 可解析） |
| 渲染量测是否可信 | ✅ 人类标尺实渲 **2.185 m** vs 真值 **2.187** ⇒ 偏差 **−0.11%** |
| 可复现性 | ✅ 冻结动画姿势后，`eval` 与 `sheet` 两趟**独立运行**给出的实渲高**逐模型 0.000 m 差**（§8 踩坑 #1） |
| 尺寸口径 | **必须用渲染量测**；静态 AABB 对本批模型误差 **−4.0% ~ +3.0%**（双向都错，见 §3） |
| 原始尺寸 | 人形怪实渲高 **2.93 ~ 3.83 m**，**全部显著大于**当前占位人类（游戏内 2.29 m） |
| 建议 `model_scale` | 见 §5（**0.640 ~ 1.209**，无一可取 1.0） |
| 朝向 | 8/8 **原生朝 +Z**（与 KayKit 一致）⇒ `model_face_offset_deg = 180.0` |
| 五键覆盖 | 满键 4 个（Orc / Ninja / MushroomKing / Cactoro）；**缺键 4 个**，见下 |

**缺键清单（任务要求的「五键里缺哪些」）：**

| 模型 | 缺的键 |
|---|---|
| `GreenBlob` | **`Run`**（只有 `Walk` 0.43 s） |
| `Yeti` | **`Run`**（只有 `Walk` 0.43 s） |
| `Ghost` | **`Idle`**、**`Walk`**、**`Run`**（`Idle` 可用 `Flying_Idle` 代；`Walk`/`Run` 可用 `Flying_Idle`/`Fast_Flying` 两档代） |
| `Glub` | **`Idle`**、**`Walk`**、**`Run`**（同上） |

---

## 1. 做法：为什么用渲染量测而不是静态 AABB

glTF 规范对**蒙皮网格**的 `POSITION` accessor `min/max` 只要求「包住该网格被蒙皮后可能到达的范围」，
导出器常直接写成绑定姿势 + 余量，于是 AABB 与「站在地上时实际有多高」脱钩。
本项目刚踩过：龙的 AABB 报 **10.45**，实渲只有 **5.68** ⇒ **高估 1.84×（+84%）**，
按 AABB 推的缩放会让龙比人还矮。

所以本报告的主口径是**正交相机渲染 + 像素量测**——最不可争辩的一步：

```
正交相机竖直视野 = cam.size 米，视口高 H 像素  →  1 px = cam.size / H 米
扫描模型「不透明像素」的最高行 top 与最低行 bot  →  实渲高 = (bot - top + 1) × cam.size / H
```

- 不透明判定优先用 **alpha 通道**（`SubViewport.transparent_bg = true`；实测 8/8 + 3 个标尺全部命中 alpha 模式），
  退化时按左上角背景色差判定——**绝不依赖模型自身颜色**，避免深色模型漏检。
- 每个模型跑 **两趟**：先 14 m 宽松视野粗测 → 用粗测的 top/bot 把相机**正好居中收窄**（`cam.size = 实测高 × 1.22`）→ 精测。
  精测档下 1 px ≈ 0.003 ~ 0.005 m（随模型高度）。
- **必须隔离单体**：量测期间强制隐藏场景里其他所有模型与参考线（§8 踩坑 #2），否则量到的是并集。
- **必须冻结动画姿势**：静息动画 seek 到 50% 后 `pause()`（§8 踩坑 #1）。这一条是本次最关键的方法修正。

### 标尺自检（关键）

| 标尺模型 | 静态 AABB 高 | 实渲高 @scale1 | 备注 |
|---|---:|---:|---|
| `placeholder_colonist.glb` | 2.187 | **2.185** | **真值 2.187 → 偏差 −0.11%** ✅（脚本原始输出） |
| `placeholder_colonist_barbarian.glb` | 2.398 | 2.397 | 现 `raider_def` 用的模型 |
| `placeholder_hero.glb` | 2.467 | 2.465 | 主角 |

⇒ 量测管线**通过自检**，下面的数字可用。

**顺带得到项目内基准（供 Lead 换算）：**

| 单位 | 计算 | 游戏内实渲高 |
|---|---|---:|
| 人类 / 村民（colonist @1.05） | 2.185 × 1.05 | **2.294 m** |
| 现普通野怪 `raider_def`（barbarian @1.05） | 2.397 × 1.05 | **2.517 m** |
| 现夜袭头目 `raider_boss_def`（barbarian @1.75） | 2.397 × 1.75 | **4.195 m** |

> 注：colonist 在对照图那一趟（`_play` 复位到绑定位姿）量得 2.286/1.05 = 2.177，与 eval 的 2.185 差 0.008 m——
> 这是**绑定位姿复位**（逐骨骼写回 rest）与**静态 AABB** 之间的正常差异，不是漂移。

---

## 2. 逐模型实测数据

口径：AABB / 实渲均在 **`model_scale = 1.0`** 下取值，单位米。
`实渲rest` = 逐骨骼写回绑定位姿；`实渲idle` = 静息动画定格 50% 帧（已冻结）。

| 模型 | 静态 AABB 高 | AABB 宽 | AABB 长 | 实渲高 (rest) | **实渲高 (idle)** | idle 动画键 | idle/AABB |
|---|---:|---:|---:|---:|---:|---|---:|
| `Orc` | 3.209 | 4.685 | 1.871 | 3.048 | **3.082** | `Idle` | 0.960 |
| `Ninja` | 3.021 | 4.649 | 3.049 | 2.902 | **2.934** | `Idle` | 0.971 |
| `MushroomKing` | 3.609 | 4.648 | 2.056 | 3.417 | **3.494** | `Idle` | 0.968 |
| `Cactoro` | 3.957 | 4.649 | 2.136 | 3.766 | **3.833** | `Idle` | 0.969 |
| `GreenBlob` | 1.853 | 2.249 | 2.195 | 1.869 | **1.909** | `Idle` | 1.030 |
| `Yeti` | 2.437 | 2.547 | 2.592 | 2.415 | **2.482** | `Idle` | 1.018 |
| `Ghost` | 3.101 | 5.500 | 1.236 | 3.058 | **3.108** | `Flying_Idle` | 1.002 |
| `Glub` | 2.351 | 4.304 | 2.171 | 2.344 | **2.344** | `Flying_Idle` | 0.997 |

> `AABB 宽` 4.6 ~ 5.5 m 不是「怪物很胖」，而是**绑定姿势是 T-pose 横伸双臂**。
> 这恰好说明为什么不能拿 AABB 推尺寸：同一个 AABB 既含横伸手臂的余量，也含头顶余量。

---

## 3. 静态 AABB 到底错多少（正面回答任务的坑）

| 模型 | AABB 高 | 实渲 rest | 实渲 idle | rest 误差 | **idle 误差** | 方向 |
|---|---:|---:|---:|---:|---:|---|
| `Orc` | 3.209 | 3.048 | 3.082 | −5.02% | **−3.96%** | AABB 高估 |
| `Ninja` | 3.021 | 2.902 | 2.934 | −3.94% | **−2.88%** | AABB 高估 |
| `MushroomKing` | 3.609 | 3.417 | 3.494 | −5.32% | **−3.19%** | AABB 高估 |
| `Cactoro` | 3.957 | 3.766 | 3.833 | −4.83% | **−3.13%** | AABB 高估 |
| `GreenBlob` | 1.853 | 1.869 | 1.909 | +0.86% | **+3.02%** | AABB **低估** |
| `Yeti` | 2.437 | 2.415 | 2.482 | −0.90% | **+1.85%** | AABB **低估** |
| `Ghost` | 3.101 | 3.058 | 3.108 | −1.39% | **+0.23%** | 基本准 |
| `Glub` | 2.351 | 2.344 | 2.344 | −0.30% | **−0.30%** | 基本准 |

- **vs rest 绑定位姿**：误差 **−5.32% ~ +0.86%**，AABB 基本就是 rest 包围盒（符合预期，差值来自网格 AABB 自带的余量）。
- **vs idle 实际站姿**：误差 **−3.96% ~ +3.02%**，**方向双向**——Big 组（人形）AABB 偏高，
  Blob / Flying 组偏低或持平。也就是说「AABB 一律偏大」是错的，「AABB 一律可靠」更是错的。
- 与本项目龙的案例（AABB 高估 **1.84×**）相比，本批模型 AABB 的绝对误差不大（≤ 0.16 m），
  但**仍然不能反推**：误差方向不可预测，且这 8 个模型的 AABB/实渲关系彼此不同（0.960 ~ 1.030）。

---

## 4. 换算公式

```
model_scale = 目标高度 X（米） ÷ 该模型实渲高@scale=1（米）
```

反推校验（`X_达成 = 建议 model_scale × 实渲高@1`）已在对照图那一趟逐模型复量，
**8/8 与目标差 ≤ 0.008 m**（见 §5 末列）。

### 参考换算表（按 `实渲高 (idle)`，直接查）

| 模型 | 实渲高@1 | →1.5 m | →2.0 m | →2.5 m | →3.0 m | →3.5 m |
|---|---:|---:|---:|---:|---:|---:|
| `Orc` | 3.082 | 0.487 | 0.649 | 0.811 | 0.973 | 1.136 |
| `Ninja` | 2.934 | 0.511 | 0.682 | 0.852 | 1.023 | 1.193 |
| `MushroomKing` | 3.494 | 0.429 | 0.572 | 0.716 | 0.859 | 1.002 |
| `Cactoro` | 3.833 | 0.391 | 0.522 | 0.652 | 0.783 | 0.913 |
| `GreenBlob` | 1.909 | 0.786 | 1.048 | 1.310 | 1.572 | 1.834 |
| `Yeti` | 2.482 | 0.604 | 0.806 | 1.007 | 1.209 | 1.410 |
| `Ghost` | 3.108 | 0.483 | 0.644 | 0.804 | 0.965 | 1.126 |
| `Glub` | 2.344 | 0.640 | 0.853 | 1.067 | 1.280 | 1.493 |
| *（人类标尺）* | *2.185* | *0.687* | *0.916* | *1.144* | *1.373* | *1.602* |

---

## 5. 建议 `model_scale`（逐怪物）

**目标高度是设计选择，不是量测结果**——下表按「与项目现有野怪体型语言一致」定档：
现普通野怪 `raider_def` = **2.52 m**、现头目 = **4.20 m**，
故取「炮灰 ≈ 1.25 ~ 1.50 m / 标准 ≈ 2.30 ~ 2.50 m / 精英 ≈ 3.00 ~ 3.40 m」。
若 Lead 想换档位，用 §4 公式或查表即可。

| 模型 | 建议定位 | 目标高 X (m) | **建议 `model_scale`** | 实渲高@1 | 复量达成 | 该档实渲宽 |
|---|---|---:|---:|---:|---:|---:|
| `Orc` | 标准近战 | 2.50 | **0.811** | 3.082 | 2.499 | 1.457 |
| `Ninja` | 标准敏捷 | 2.30 | **0.784** | 2.934 | 2.297 | 2.167 |
| `Ghost` | 标准飞行 | 2.40 | **0.772** | 3.108 | 2.404 | 1.457 |
| `Glub` | 小型飞行（炮灰） | 1.50 | **0.640** | 2.344 | 1.492 | 1.279 |
| `GreenBlob` | 小型地面（炮灰） | 1.25 | **0.655** | 1.909 | 1.243 | 1.445 |
| `Yeti` | 精英肉盾 | 3.00 | **1.209** | 2.482 | 3.008 | 3.126 |
| `MushroomKing` | 精英法系 | 3.20 | **0.916** | 3.494 | 3.197 | 1.918 |
| `Cactoro` | 大型精英 | 3.40 | **0.887** | 3.833 | 3.399 | 1.883 |

> 末列「该档实渲宽」是**按该 `model_scale` 实渲出来的横向宽度**（含武器/翅膀/草帽），
> 可直接用作 `CollisionShape3D` 半径或 `footprint` 的参考——注意 `Ninja`（持刀 2.17 m）、
> `Yeti`（3.13 m）比同高的其它怪宽得多，碰撞体不要按身高一刀切。

**即插即用的 `GameDefs` 片段：**

```gdscript
# Quaternius Ultimate Monsters（CC0）— 比例由渲染量测标定，见 dragon-assets/monsters/REPORT.md
# 全部原生朝 +Z，与 KayKit 同约定 ⇒ model_face_offset_deg = 180.0
d.model_face_offset_deg = 180.0
d.model_path = "res://assets/_PLACEHOLDER/monsters/Orc.gltf";          d.model_scale = 0.811  # → 2.50 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/Ninja.gltf";        d.model_scale = 0.784  # → 2.30 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/Ghost.gltf";        d.model_scale = 0.772  # → 2.40 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/Glub.gltf";         d.model_scale = 0.640  # → 1.50 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/GreenBlob.gltf";    d.model_scale = 0.655  # → 1.25 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/Yeti.gltf";         d.model_scale = 1.209  # → 3.00 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/MushroomKing.gltf"; d.model_scale = 0.916  # → 3.20 m
d.model_path = "res://assets/_PLACEHOLDER/monsters/Cactoro.gltf";      d.model_scale = 0.887  # → 3.40 m
```

> ⚠️ **不要取 `model_scale = 1.0`**：原始尺寸下 6 个模型比现有头目（4.20 m）以外的所有单位都高，
> 其中 `Cactoro` 实渲 3.83 m ≈ 1.67 倍人类，直接放进去会显得场面失衡。

---

## 6. 动画清单与五键覆盖

命令（逐个跑，输出原文见 §7）：

```bash
godot --headless --path . --script dragon-assets/poc/probe.gd -- "res://assets/_PLACEHOLDER/monsters/<名字>.gltf"
```

### 覆盖表

五键 = `Idle` / `Walk` / `Run` / `Punch`（或语义等价的 `Bite_Front` / `Headbutt`）/ `Death`。
`✅` = 原生同名键；`🟡` = 只有语义等价键；`❌` = 缺。

| 模型 | 动画数 | `Idle` | `Walk` | `Run` | 攻击键 | `Death` | 覆盖 |
|---|---:|---|---|---|---|---|---|
| `Orc` | 14 | ✅ `Idle` | ✅ `Walk` | ✅ `Run` | ✅ `Punch` | ✅ `Death` | **5/5** |
| `Ninja` | 14 | ✅ `Idle` | ✅ `Walk` | ✅ `Run` | ✅ `Punch` | ✅ `Death` | **5/5** |
| `MushroomKing` | 14 | ✅ `Idle` | ✅ `Walk` | ✅ `Run` | ✅ `Punch` | ✅ `Death` | **5/5** |
| `Cactoro` | 14 | ✅ `Idle` | ✅ `Walk` | ✅ `Run` | ✅ `Punch` | ✅ `Death` | **5/5** |
| `GreenBlob` | 9 | ✅ `Idle` | ✅ `Walk` | ❌ | 🟡 `Bite_Front` | ✅ `Death` | 4/5 |
| `Yeti` | 9 | ✅ `Idle` | ✅ `Walk` | ❌ | 🟡 `Bite_Front` | ✅ `Death` | 4/5 |
| `Ghost` | 8 | 🟡 `Flying_Idle` | ❌ | ❌ | 🟡 `Headbutt` | ✅ `Death` | 2/5（+2 代） |
| `Glub` | 8 | 🟡 `Flying_Idle` | ❌ | ❌ | 🟡 `Headbutt` | ✅ `Death` | 2/5（+2 代） |

### 完整动画名清单

| 模型 | 动画键（含时长，单位 s） |
|---|---|
| `Orc` | `Death`0.77 `Duck`1.67 `HitReact`0.60 `Idle`1.00 `Jump`0.37 `Jump_Idle`0.50 `Jump_Land`0.37 `No`1.67 `Punch`0.87 `Run`0.57 `Walk`1.00 `Wave`1.67 `Weapon`0.87 `Yes`1.67 |
| `Ninja` | 同 `Orc`（14 条，**键名与时长逐条一致**） |
| `MushroomKing` | 同 `Orc` 14 条（`Weapon` 轨道数 30 vs Orc 25） |
| `Cactoro` | 同 `Orc` 14 条（`Idle` / `No` / `Wave` / `Yes` 轨道数各 +1） |
| `GreenBlob` | `Bite_Front`0.40 `Dance`0.67 `Death`0.37 `HitRecieve`0.30 `Idle`2.00 `Jump`0.43 `No`1.00 `Walk`0.43 `Yes`0.97 |
| `Yeti` | 同 `GreenBlob`（9 条，**键名与时长逐条一致**） |
| `Ghost` | `Death`0.67 `Fast_Flying`0.83 `Flying_Idle`1.17 `Headbutt`1.17 `HitReact`0.47 `No`1.17 `Punch`1.17 `Yes`1.17 |
| `Glub` | 同 `Ghost`（8 条，**键名与时长逐条一致**） |

### 缺键的可行替代

- **`GreenBlob` / `Yeti` 缺 `Run`**：只有 `Walk`（0.43 s）。若要「跑」的表现，只能**提高 `Walk` 的播放速率**
  （`AnimationPlayer.speed_scale ≈ 1.6`）或按实际移动速度线性调 `speed_scale`——**不要**去找不存在的 `Run` 键。
  注意这两个的 `Walk` 只有 0.43 s（很短），提速后容易「抖腿」，建议上限 ~1.8×。
- **`Ghost` / `Glub` 缺 `Idle` / `Walk` / `Run`**：飞行组用替代档——
  `Flying_Idle`（1.17 s，悬浮待机）→ 悬停/慢速；`Fast_Flying`（0.83 s）→ 快速移动；`Headbutt` → 攻击。
  这两个模型的「移动」语义与地面单位不同，**状态映射需特殊处理**（没有踏步位移的地面 `Walk`）。
- 补充：`Ghost` 与 `Glub` 还额外有 `Punch`（1.17 s），攻击键实际有两档可选。

---

## 7. 我跑过的命令原文

### 1) 下载（可复现）

```bash
mkdir -p assets/_PLACEHOLDER/monsters
curl -sL "https://drive.google.com/uc?export=download&id=17675H4Owu5FeHUk_7Goyc9TKI5YK3cEM" -o Orc.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1T45Ab6f3oX6m-r-kRqEOsmv0Yp9ySmDb" -o Ninja.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1sCGed1ce1CrdCdFz5bxVQMqphu5e3a1m" -o MushroomKing.gltf
curl -sL "https://drive.google.com/uc?export=download&id=19Po2Ae16TbImr6dCu7PRZdpPQhEA13OQ" -o Cactoro.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1Qj3EPCAzN7P3KNrfjV_sFMw98nsBUyob" -o GreenBlob.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1VpqldMiSmrmoDtTqA5PqOZ0FrPIKKjiP" -o Yeti.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1rUs1QRA9v1Y2wRYEXsfteBisTsz4JlLi" -o Ghost.gltf
curl -sL "https://drive.google.com/uc?export=download&id=1X-6f4qyrbloGVq3wf-IdxUgmuA0u1JGu" -o Glub.gltf
```

### 2) 校验

```bash
python3 -c "import json;json.load(open('Orc.gltf'))"     # 8/8 通过
shasum -a 256 *.gltf
```

### 3) 渲染量测（**带窗口**，不加 `--headless`）

```bash
godot --headless --path . --check-only --script dragon-assets/monsters/measure.gd   # 先查语法
godot --path . dragon-assets/monsters/measure.tscn -- --mode eval
```

### 4) 同框对照图

```bash
T="Orc=2.50,Ninja=2.30,MushroomKing=3.20,Cactoro=3.40,GreenBlob=1.25,Yeti=3.00,Ghost=2.40,Glub=1.50"

# 校准后（怪物按建议 scale、人类按游戏 scale 1.05）+ 8 张逐个特写
godot --path . dragon-assets/monsters/measure.tscn -- --mode sheet --view side \
  --out res://dragon-assets/monsters/contact_sheet_calibrated.png --targets "$T"

# 原始比例（全部 scale=1.0）
godot --path . dragon-assets/monsters/measure.tscn -- --mode sheet --view side --pairs 0 \
  --out res://dragon-assets/monsters/contact_sheet_raw.png

# 正视（判朝向 + 判体宽）
godot --path . dragon-assets/monsters/measure.tscn -- --mode sheet --view front --pairs 0 \
  --out res://dragon-assets/monsters/contact_sheet_front.png --targets "$T"
```

### 5) 动画探针

```bash
for m in Orc Ninja MushroomKing Cactoro GreenBlob Yeti Ghost Glub; do
  godot --headless --path . --script dragon-assets/poc/probe.gd -- "res://assets/_PLACEHOLDER/monsters/$m.gltf"
done
```

### 6) 独立复核（不信脚本自报，直接从交付 PNG 反量）

```bash
/Users/zhima/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3 - <<'EOF'
from PIL import Image; import numpy as np
im = Image.open("dragon-assets/monsters/contact_sheet_calibrated.png").convert("RGB")
a = np.asarray(im).astype(np.int16); H, W, _ = a.shape
mask = (np.abs(a - a[2,2]).sum(axis=2) > 40)
for y in np.where(mask.sum(axis=1) > W*0.75)[0]: mask[y,:] = False   # 剔掉参考线
# 再按列切分演员、量像素高 → × (cam.size/H) → 米
EOF
```

---

## 8. 踩坑记录（供后续复用）

1. **⚠️ 最关键的坑：动画必须在 seek 之后 `pause()`。**
   第一版只做 `ap.play(); ap.seek(len*0.5, true)`。但渲染要跨若干帧，`AnimationPlayer` 会**继续推进**：
   从「量测那一帧」到「出图那一帧」中间隔了 9 个演员各 ~7 帧 ≈ 1 秒，
   对一个 1.17 s 的 `Flying_Idle` 等于走完 ~85% 周期 ⇒ **量的和画的根本不是同一帧**。
   症状：同一模型 `eval` 与 `sheet` 两趟数字对不上（Glub 2.638 vs 2.647），
   且交付图里 `Glub` 反量出来只有 1.319 m（报告 1.587 m，差 0.268 m，**肉眼可见的 17% 误差**）。
   修法：seek 后 `ap.pause()` 把姿势钉死。修完后两趟独立运行**逐模型 0.000 m 差**，交付图反量最大偏差降到 **0.036 m**。
   > 这个坑对**悬浮/上下摆动幅度大**的模型（Ghost / Glub）影响最大，对站桩人形最小——所以它很容易被误当成「量化误差」放过去。
2. **量测必须隔离单体。** 第一版把人类 + 8 怪物同场摆好再逐个量，结果每个都量到 **3.79 m**——
   扫到的是**全部模型的并集**。修法：`_measure_actor()` 内置 `_isolate()`，量谁只显示谁。
   同一坑在「换算」那一趟也复现过（`GreenBlob` 量到 3.791 m，被前面的 `Cactoro` 污染）。
3. **特写图也要隔离**：第一版 `contact_sheet_pair_Orc.png` 里串进了仙人掌的草帽。
4. **参考线要画在模型后方足够远**（`x = −6`）。正交投影下 x 不影响屏幕位置，只影响遮挡；
   放在 `x = −1.6` 会被 T-pose 横伸的手臂盖住。
5. **`--headless` 会挂死**：`RenderingServer.frame_post_draw` 在无头模式下不触发。本报告所有渲染均**带窗口**执行。
6. **`DecorationDissolveSystem` 在非编辑器环境每帧报一条**
   `This function should never be used outside the editor`（`global_shader_parameter_get_list`）。
   与本次任务无关（项目既有行为），纯日志噪声，**不影响渲染结果**。
7. **`probe.gd` 的 `load()` 会失败**（`.gltf` 未走编辑器导入、无 `.import`），它会自动回退 `GLTFDocument`，
   此时打印 `No loader found` + `!is_inside_tree()` 两三条 ERROR——**这是预期路径，不是失败**，随后照常输出完整数据。
8. **`--check-only` 是必需的**：GDScript 在本项目里把「从 Variant 推断类型」当**错误**（不是警告），
   一处 `var x := dict.get(k)` 就会 Parse Error → 场景永不 `quit` → 挂到超时。

---

## 9. 交付物清单

### 素材（`assets/_PLACEHOLDER/monsters/`）

| 路径 | 说明 |
|---|---|
| `Orc.gltf` `Ninja.gltf` `MushroomKing.gltf` `Cactoro.gltf` | Big 组，内嵌 1024² `Atlas_Monsters`（9,007 B） |
| `GreenBlob.gltf` `Yeti.gltf` | Blob 组，内嵌 32² `Atlas_Monsters`（912 B） |
| `Ghost.gltf` `Glub.gltf` | Flying 组，内嵌 32² `Atlas_Monsters`（927 B） |
| `CREDITS.md` | 来源 / 许可原文 / FILE_ID / 哈希 / 图集内嵌说明 |
| `atlas_archive/Atlas_Monsters_{Big,Blob,Flying}.png` | **仅存档**，非运行依赖 |

### 报告与对照图（`dragon-assets/monsters/`）

| 路径 | 内容 |
|---|---|
| `REPORT.md` | 本文件 |
| `measure.gd` / `measure.tscn` | 可复现的量测 + 对照图工具（`--mode eval` / `--mode sheet`） |
| `contact_sheet_calibrated.png` | **主对照图**：人类(1.05×) + 8 怪物（建议 scale），侧视，含 1 m 网格 + 人类身高绿线 |
| `contact_sheet_raw.png` | 原始比例：9 个全部 `scale = 1.0`（直观看出「原包尺寸偏大」） |
| `contact_sheet_front.png` | 正视：判朝向（8/8 朝 +Z）+ 判体宽 |
| `contact_sheet_pair_<名字>.png` ×8 | 逐个「人类 vs 该怪物」特写（含绿线标尺） |

### 交付图独立复核结果（从 PNG 反量，非脚本自报）

主对照图 `contact_sheet_calibrated.png`（相机竖直视野 8.68 m / 760 px）：

| 演员 | 从图反量 | 报告值 | 差 |
|---|---:|---:|---:|
| Colonist | 2.261 | 2.286 | −0.025 |
| Orc | 2.478 | 2.499 | −0.021 |
| Ninja | 2.261 | 2.297 | −0.036 |
| MushroomKing | 3.186 | 3.197 | −0.011 |
| Cactoro | 3.381 | 3.399 | −0.018 |
| GreenBlob | 1.233 | 1.243 | −0.010 |
| Yeti | 2.981 | 3.008 | −0.027 |
| Ghost | 2.387 | 2.404 | −0.017 |
| Glub | 1.485 | 1.492 | −0.007 |

**最大偏差 0.036 m**（系统性负偏来自不透明底图下 alpha 阈值取边，属阈值定义差，非几何差）。
⇒ 交付图与报告数字自洽。

> `contact_sheet_raw.png` 的反量会失败（列切分把 Orc 的狼牙棒与相邻演员连成一段）——
> 这是**复核脚本的切分问题**，不是图的问题；该图定位是「肉眼总览」，量化结论一律以校准图为准。

---

## 10. 未完成项 / 已知不确定度

| 项 | 状态 |
|---|---|
| `Ghost` / `Glub` 的悬浮高度 | ⚠️ **未定**。二者 idle 姿势本身浮在空中（AABB `position.y` 分别为 `+0.280`、`+1.377`），本报告按「渲染像素底边对齐 y=0」摆位；游戏里若要「飘在离地 h 米」，需在此之上再加偏移，**本报告不提供该偏移的建议值** |
| 行走/跑步**位移速度**与动画的匹配 | ❌ **未测**。本报告只给尺寸，未测 `Walk` / `Run` / `Fast_Flying` 的根位移速率，故无法给出「`PawnDef.move_speed` 取多少才不滑步」 |
| 攻击动画的命中时机（`Punch` / `Bite_Front` / `Headbutt` 的有效帧） | ❌ **未测**，不属本次范围 |
| `GreenBlob` / `Yeti` 缺 `Run` 的具体 `speed_scale` 补偿值 | ❌ **未定**，需先知道游戏侧 `move_speed` |
| 挂点/武器筛选（`PawnModelRig.apply_weapon_loadout` 对 Quaternius 模型是否适用） | ⏭️ **不属本次范围**（Lead 正在改 `PawnModelRig`/`PawnDef`/`Pawn`/`GameDefs`，本任务刻意不碰 `scripts/`）。**提示**：Quaternius 的武器是**骨骼内网格**而非独立挂点子树，KayKit 那套 `handslot_l/r` 显隐筛选**大概率不适用**，需实测 |
| `MushroomKing` 探针报 `MeshInstance3D 数: 2` | 备注：Big 组的 `Orc`、`MushroomKing` 与 Blob 组的 `GreenBlob` 是 **2 个 MeshInstance3D**（2 个 surface），其余 5 个为 1 个；本报告的量测与对照图均已覆盖**全部** mesh，无遗漏 |

---

## 11. 对任务书「已确认事实」的一处修正

任务书写「共用一张 `Atlas_Monsters.png`（9,007 B）」。**逐字节核对后需修正**：
8 个文件里内嵌图的**节点名都叫 `Atlas_Monsters`**，但实际是 **3 份内容不同的 PNG**——

| 分组 | 成员 | 尺寸 | 字节 | sha256[:12] |
|---|---|---|---:|---|
| Big | Orc / Ninja / MushroomKing / Cactoro | 1024×1024 | 9,007 | `b970ed1359ce` |
| Flying | Ghost / Glub | 32×32 | 927 | `ce8ee9c55f5e` |
| Blob | GreenBlob / Yeti | 32×32 | 912 | `df160c995a71` |

只有 **Big 组**那张是任务书说的 9,007 B 图集（已独立证明：从 `Orc.gltf` 抽出的图集与
`dragon-assets/monsters/Atlas_Monsters.png` **字节完全一致**）。
Blob / Flying 组各自带一张**同名但更小**的 32² 图集——这也解释了实渲观感差异：
Big 组有人脸/装备细节，Blob / Flying 组基本是平涂色块（**若 Lead 想要细节，这两组只能靠 `model_tint` 或换贴图**）。

**运行不依赖上述任何一张**：每个 `.gltf` 的 buffer 是 `data:` URI、image 走 `bufferView`，
**外部 URI 计数 = 0**，`GLTFDocument` 可直接加载，无需外挂文件。
