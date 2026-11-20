# 龙模型落地验证报告（task-4）

- **执行人**：`dragon-poc`（共享任务板 `task-4`；依赖 task-3 复核报告）
- **工作目录**：`/Users/zhima/Desktop/demo-1`（Godot 4.7.1.stable.official.a13da4feb / Metal / Apple M4）
- **时间**：2026-10-01（Asia/Shanghai）
- **写入范围**：仅 `dragon-assets/poc/`（未改仓库任何源码、未动 `assets/_PLACEHOLDER/`）
- **纪律**：本报告每一条数字都是**我自己跑出来的命令输出**（命令原文见 §10）；凡没跑通的一律在 §9 写「未完成 / 未核实」。

---

## 0. 结论速览

| # | 问题 | 结论 |
|---|---|---|
| 1 | **官方版 Quaternius 对照能否跑通** | ✅ **跑通**。官方 Drive `Dragon.gltf` 匿名直连下载成功（427,100 B，sha256 `d219a29b…`），Godot 内 4,562 三角面 / 13 骨骼 / 8 条动画全部实测到。**但官方版是「大头 Q 版浮空龙」，没有四足站姿**（见 §1.4 侧视图） |
| 2 | **主候选 bocdagla 质量** | ✅ 2,004 三角面 / 76 骨骼 / 1 材质（内嵌 4×4 调色板贴图）/ 6 条动画，**是标准西方四足带翼龙**，地面待机 + 真迈步行走 + 攻击 + 起飞 + 飞行俱全（§2） |
| 3 | **`model_scale` 取多少** | **0.80**（作为 BOSS）。⚠️ 任务书里「包围盒 10.45 高 → 0.3~0.43」这个推算**是错的**：静态 AABB 比实际渲染大 **1.84×**，实测本资产直立渲染高度只有 **5.68 模型单位**（§3） |
| 4 | **`model_face_offset_deg` 取多少** | **180.0**。模型自身朝 **+Z**（头在 +Z、尾在 −Z，骨骼静止位姿 + Walk 迈步方向 + 标记球渲染三重证实），项目逻辑前方是 **−Z**（`Pawn.gd:887`）（§4） |
| 5 | **七 key 能否映射** | **bocdagla：6/7 有解**（`idle/move/fight` 直给，`run` 复用行走、`harvest/follow` 回落 move），**唯一缺口 = 没有死亡动画**；**官方 Quaternius：7/7 有解但没有地面移动/地面待机**（只有空中，腿冻在绑定站姿）。两个资产的缺口正好互补。逐 key 表见 §5，缺口处理见 §6 |
| 6 | **ANIM_MAP 怎么改** | `ANIM_MAP` 是 **`PawnModelRig` 里的全局 `const` 字典，全仓库无任何 per-def 覆盖点**（grep 实证）⇒ 龙与 KayKit 动画名不同**必须**改全局或新增 per-def 覆盖。推荐「候选名数组 + 现有名排第一」这种向后兼容改法，两种龙 + 全部 KayKit 单位可共存（§7.4） |

---

## 1. 官方版 Quaternius 对照（任务第 1 项，✅ 跑通）

### 1.1 下载（走复核员 `verification.md` §10 记录的直连方式，未用 poly.pizza 镜像）

```
curl -sS -L --max-time 120 "https://drive.google.com/uc?export=download&id=1-mQSm6_oGt7-EEQfNj1dFWYgPQy4AdPC" \
     -o quaternius_official_Dragon.gltf -w "HTTP %{http_code} size=%{size_download} type=%{content_type}\n"
```

实际输出：`HTTP 200 size=427100 type=application/octet-stream`（与复核员记录的大小**逐字节相符**）

| 文件 | 字节 | sha256 | 备注 |
|---|---|---|---|
| `quaternius_official_Dragon.gltf` | 427,100 | `d219a29b5e928da26c24218a64284bbf999b88484a508ac6c01e0edad9f1f56c` | **本次对照主角**（官方 Drive，非镜像） |
| `quaternius_official_Dragon_Evolved.gltf` | 991,335 | `39ba6ea24b5f27acf68bbf4c19fe80ba070dbec167ff14bbe933453303426f5c` | 一并下载留档（**本次未深入实测**，见 §9） |
| `quaternius_dragon_evolved_polypizza.glb`（复核员的降级镜像） | 436,000 | `f660d8f48be4ea3f…` | 与复核员记录一致 ⇒ **确认就是降级镜像版，本次只当对照组，未用于任何结论** |
| `bocdagla/upload/Dragon2.glb` | 498,564 | `eefbbb611e07ae64f46634dd4c260cafcae9afbc78e316c327a692aabe6149e1` | 主候选 |

**官方 Drive 下载无需登录、无需交互式确认**（HTTP 200 直接落盘），所以**没有**动用替代方案。

### 1.2 官方 `Dragon.gltf` 实测（`probe2.gd` 输出照抄）

```
模型根节点名: quaternius_official_Dragon  类型: Node3D
[Node3D] quaternius_official_Dragon scale=(1.0, 1.0, 1.0)
  [Node3D] CharacterArmature scale=(1.0, 1.0, 1.0)          ← 无缩放差异（与 bocdagla 的 1.668 不同）
    [Skeleton3D] Skeleton3D scale=(1.0, 1.0, 1.0)
      [MeshInstance3D] Dragon_Fly
MeshInstance3D 数: 1 表面数: 1
三角面数: 4562
Skeleton3D 数: 1 骨骼数: 13
前 12 根骨骼: ["Root", "Torso", "Neck", "Head", "Wing1.L", "Wing2.L", "Wing3.L", "Wing4.L", "Wing1.R", "Wing2.R", "Wing3.R", "Wing4.R"]
材质数: 1 带 albedo 贴图的材质数: 1
  surface 0 材质 Material albedo_color=(1,1,1,1) albedo_texture=<内嵌> tex_size=(32, 32) transparent=0 cull=2
包围盒位置: (-2.191019, 1.599733, -1.430203) 尺寸: (4.382037, 1.540679, 2.42991)
AnimationPlayer[AnimationPlayer] 动画 8 条（库：[&""]）：
   - Death       时长 0.667s 轨道 12 once
   - Fast_Flying 时长 0.833s 轨道 10 once
   - Flying_Idle 时长 1.167s 轨道 10 once
   - Headbutt    时长 1.167s 轨道 11 once
   - HitReact    时长 0.467s 轨道 12 once
   - No          时长 1.167s 轨道 11 once
   - Punch       时长 1.167s 轨道 11 once
   - Yes         时长 1.167s 轨道 11 once
```

三条对落地**直接有用**的观察：

1. **包围盒 y 从 1.5997 到 3.1404** —— 网格**不在原点、悬在半空**，而且高度只有 1.54（翼展 4.38 宽、体长 2.43）。这是一条「飞行姿态」的模型：**没有四足站姿**。
2. **8 条动画在 Godot 里循环位全是 `once`** —— glTF 里没带 loop 信息。项目侧 `PawnModelRig.play()` 对 `LOOP_KEYS` 会强制 `LOOP_LINEAR`（`PawnModelRig.gd:291-294`），所以**「Flying_Idle 不循环」不会成为问题**，但要知道这是项目侧替它兜的底。
3. **13 根骨骼、只有 4 根翼骨/侧** —— 相比 bocdagla 的 76 骨骼是**低得多的绑定精度**。

### 1.3 官方版渲染尺寸实测（正交渲染 + 像素量测）

| 项 | 值 |
|---|---|
| 参照人类 `placeholder_colonist.glb`（model_scale 1.0） | 静态 2.945×**2.187**×1.477 → 渲染 **2.190 m**（219 px） |
| 官方 `Dragon.gltf` @ model_scale **0.80**，`Flying_Idle` | 渲染 **1.580 m**（158 px）= **1.975 模型单位** |
| ⇒ 龙/人高度比 | **0.72 ×** |

官方版静态 AABB 高 1.541 与实测渲染 1.975 同量级（略小于渲染，因为飞行动画会把脖子/翅膀甩出绑定包围盒）⇒ **这个资产的 AABB 是可用的估算口径**（不像 bocdagla，见 §3.2）。

### 1.4 🔴 官方版造型：**大头 Q 版浮空龙，不是四足龙**

`preview_quaternius_side.png`（侧视，dist 6.0 / targeth 1.5 / azim 88° / elev 8°）与 `preview_quaternius_Flying_Idle.png`（3/4 视）看得很清楚：

- 头**极大**、身体极小，四肢几乎不可见，是一条「会飞的胖头龙」；
- **没有四足着地的站姿**，脖子/身体全程浮空；
- 与「西方四足带翼龙」的目标形象**差距很大**。

**裁决：官方 Quaternius 版「跑通了、但造型不达标」**。它的价值在于：① 是 CC0（许可最干净）② **唯一带 `Death` 死亡动画的候选** ③ 适合当**飞行怪 / 空中 BOSS**，不适合当地面四足龙。

---

## 2. 主候选 bocdagla `Dragon2.glb` 实测（客观数字）

### 2.1 网格 / 骨骼 / 材质（`probe2.gd` 输出照抄）

```
模型根节点名: Dragon2  类型: Node3D
[Node3D] Dragon2 scale=(1.0, 1.0, 1.0) origin=(0,0,0)
  [Node3D] Armature_001 scale=(1.668396, 1.668396, 1.668396)   ← 只有这一层带缩放
    [Skeleton3D] Skeleton3D scale=(1.0, 1.0, 1.0)
      [MeshInstance3D] DragonBody_002
MeshInstance3D 数: 1 表面数: 1
三角面数: 2004
顶点数: 4556
Skeleton3D 数: 1 骨骼数: 76
前 12 根骨骼: ["Body","Body.002","Body.003","Head","Head.001","Head.002","Head.Tip","Head.003","Head.downTip","LegFront_L.001",…]
材质数: 1 带 albedo 贴图的材质数: 1
  surface 0 材质 basic.001 albedo_color=(1,1,1,1) albedo_texture=<内嵌> tex_size=(4,4) transparent=0 cull=2
```

| 项 | 值 | 落地含义 |
|---|---|---|
| 三角面 | **2,004** | 比 KayKit 基线（野蛮人 6,543 / 主角 6,952）**更省**，可放心批量刷 |
| 骨骼 | **76** | 每根手指/翼骨/尾节都有；含作者宣称的 IK tip bones（`Head.Tip` / `Head.downTip` / `LegFront_L.Tip` / `LegBack_L.Tip` / `Tail.Tip`）|
| 材质 | 1 个 `basic.001` | |
| 贴图 | **内嵌** 4×4 调色板（`albedo_texture.resource_path` 为空 = 非外链）| 单文件自包含 ✅ |
| `albedo_color` | **(1,1,1,1) 纯白** | ⇒ 想换色（精英/头目）走 `PawnModelRig.apply_tint()` 是**乘白**，不会偏色 ✅ |
| `transparency` | `0`（DISABLED） | 不透明，无透明排序问题 |
| `cull_mode` | `2`（**CULL_DISABLED 双面**） | ① 反壳描边（`_build_outlines` 用 `CULL_FRONT` + grow）照样可用；② v16 溶解走 discard，不受双面影响 |

### 2.2 六条动画（`probe2.gd` 输出照抄，含循环位）

| 动画名（照抄） | 时长 | 轨道 | Godot 循环位 | 说明 |
|---|---|---|---|---|
| `Attack` | 0.917 s | 52 | once | 攻击 |
| `AttackPose` | 0.417 s | 52 | once | 起手/张翼姿 |
| `Flying_loop` | 1.667 s | 32 | **loop** | 飞行 |
| `GroundToFly` | 0.833 s | 36 | once | 地面→起飞过渡 |
| `Idle_loop` | 5.000 s | 37 | **loop** | 地面待机 |
| `Walk_menacing_loop` | 1.667 s | 50 | **loop** | 地面行走（真迈步） |

**与任务书给的 6 条清单逐条相符**（名字、时长、顺序都对得上）。补一条任务书没有的信息：**这个 GLB 自带正确的循环位**（3 条 loop / 3 条 once），而官方 Quaternius 那 8 条全是 `once`。

### 2.3 包围盒「厘米级」的真相

```
包围盒（模型局部，未含根变换）位置: (-3.656521, 0.001086, -7.086356)
                              尺寸: (7.313042, 10.45131, 11.4635)（x 宽 / y 高 / z 长）
```

与任务书给的 **7.31 × 10.45 × 11.46 完全一致**，且脚底在 y≈0.001（**脚踩地面，不需要高度补偿**）。

**但 §3 会证明：这个 10.45 不是它在屏幕上有多高。**

---

## 3. 🔴 `model_scale`：静态 AABB 比实际渲染大 1.84×，任务书的 0.3~0.43 是错的

### 3.1 方法（为什么不能只看 AABB）

`Armature_001` 节点带 **1.668396** 缩放，而 `probe.gd` / `probe2.gd` 的 AABB 会把这一层乘进去（`mesh.get_aabb()` × 父链变换）。但**蒙皮网格的顶点是在被骨骼矩阵变换后绘制的**——顶点空间与「AABB × 父链缩放」并不等价。所以尺寸标定改用**最不可争辩的口径**：

> 正交相机（竖直视野 `size` 米、视口高 H 像素 → **1 px = size / H 米**）渲染 → 数不透明像素的竖直跨度 → 直接得到「它渲染出来有几米高」。

参照物用项目自己的 KayKit 人类 `placeholder_colonist.glb`（`GameDefs` 里 `model_scale = 1.0`），**同一台相机**渲一张，两者的米数比就是「龙有几倍人高」。

### 3.2 量测结果（`size.gd`，1 px = 0.0100 m）

**人类参照（自检）**：静态 AABB 高 2.187 → 渲染 **2.190 m**（219 px）⇒ **口径自洽**（静态值 ≈ 渲染值）。

**龙（model_scale 0.40）**：

| 动画位姿 | 像素高 | 渲染世界高度 | 反推「模型单位」高度 |
|---|---|---|---|
| 绑定位姿（rest，逐骨骼复位） | 122 px | 1.220 m | 3.05 |
| `Walk_menacing_loop` | 125 px | 1.250 m | 3.13 |
| `GroundToFly` | 148 px | 1.480 m | 3.70 |
| `Flying_loop` | 205 px | 2.050 m | 5.13 |
| `Idle_loop` | 227 px | 2.270 m | **5.68** |
| `Attack`（前肢立起） | 247 px | 2.470 m | **6.18** |

**线性校验**（`model_scale` 0.80 重跑 `Idle_loop`）：

| model_scale | 渲染高度 | 折合模型单位 |
|---|---|---|
| 0.40 | 2.270 m | 5.675 |
| 0.80 | 4.550 m | 5.688 |

⇒ 两次独立渲染比值差 **0.2%**，线性成立。

### 3.3 结论

> **本资产 `model_scale = 1.0` 时，直立渲染高度 ≈ 5.68 模型单位；静态 AABB 说 10.451 ⇒ AABB 高估 `10.451 / 5.68 = 1.84×`。**
>
> ⇒ 任务书按 AABB 推的「`model_scale ≈ 0.3~0.43`」如果照抄，龙渲染出来只有 **1.7~2.4 m**——**比一个人还矮**，完全不是龙。
> ⇒ 正确的取法是按 **5.68 单位**算：`渲染高度(m) ≈ 5.68 × model_scale`。

### 3.4 `model_scale` 建议表（按 §3.2 实测算）

| model_scale | 直立渲染高度 | 相当于人类（2.19 m） | 适用定位 |
|---|---|---|---|
| 0.45 | 2.56 m | 1.17 × | 普通野怪（与 KayKit 人类同级，**偏小，不建议**）|
| 0.58 | 3.29 m | 1.50 × | 精英怪 |
| 0.70 | 3.98 m | 1.82 × | 头目（对位现有 `raider_boss_def` 的 1.75 × 2.187 = **3.83 m**）|
| **0.80** | **4.55 m** | **2.08 ×** | ✅ **推荐（BOSS 定位）**——已出图 `preview_scale_0.80.png` 与人类并排目视确认 |

**推荐 `model_scale = 0.80`**：比现有头目（野蛮人 1.75）**高一档**，但不至于遮天；若只想当精英怪用 `0.58`。

---

## 4. 朝向判定 ⇒ `model_face_offset_deg = 180.0`

三条**互相独立**的证据，全部指向「模型自身朝 **+Z**」：

### 4.1 骨骼静止位姿（`kin.gd`，模型空间坐标，已含 1.668 缩放）

```
[ 3] Head            x=+0.000 y=+2.460 z=+1.309
[ 6] Head.Tip        x=+0.049 y=+1.986 z=+2.990     ← 头/吻部整条链都在 +Z
[ 8] Head.downTip    x=+0.071 y=+1.860 z=+2.710
[60] Tail            x=-0.000 y=+1.647 z=-1.546
[65] Tail.Tip        x=-0.000 y=+1.827 z=-5.548     ← 尾巴整条链都在 -Z
[ 9] LegFront_L.001  x=-0.404 y=+1.748 z=+0.696     ← 「前腿」根在 +Z
[66] LegBack_L.001   x=-0.403 y=+1.481 z=-1.245     ← 「后腿」根在 -Z
```

头/前腿在 +Z、尾/后腿在 −Z，**头尾不可能同时装反**。

### 4.2 `Walk_menacing_loop` 迈步方向（任务书要求的判据）

`LegBack_L.Tip` 逐帧轨迹（(z, y) 对，8 采样）：

```
z: -2.18  -2.28  -1.76  -1.10  -1.71  -2.11  -2.30  -2.18
y: +0.33  +0.73  +0.36  -0.02  -0.03  +0.03  -0.00  +0.33
```

读法：后脚在 **z = −1.10、y ≈ 0（踩实）**落地，随后沿地面向 **z = −2.30** 方向后移（y 全程 ≈ 0 = 支撑相），再抬起（y +0.73）向前摆回。**支撑相里脚相对身体向后走 ⇒ 身体朝 +Z 前进。**

`LegFront_L.Tip` 同向印证：

```
z: +1.69  +1.49  +1.08  +0.81  +0.62  +0.55  +1.28  +1.69
y: +0.03  -0.03  -0.01  +0.20  +0.35  +0.43  +0.19  +0.03
```

前脚最靠前在 **z = +1.69**，整条轨迹都落在 +Z 半轴。

### 4.3 渲染实证（标记球）

`preview_facing_markers.png`：侧视（相机在 +X 朝 −X 看，该机位下**屏幕左 = 世界 +Z**），放了两个标记球——**红球在世界 +Z 侧、蓝球在 −Z 侧**，并放了一个 KayKit 人类站在 +Z 侧作交叉参照。

看图：**人（+Z）与红球在左，蓝球在右；龙的头部（带角、带绿膜翼前缘）在左（+Z），长尾拖向右（−Z）。** 与 §4.1/§4.2 完全一致。

### 4.4 结论

项目逻辑前方是**本地 −Z**（`Pawn.look_at_target()`：`rotation.y = atan2(-dir.x, -dir.z)`，注释明写「让 -Z 轴指向 dir」，`Pawn.gd:883-887`）。模型自身朝 +Z ⇒

> ### `model_face_offset_deg = 180.0`（与 KayKit 占位角色同一取值）

---

## 5. 七 key 映射表（任务第 2 项：这是落地真正要解决的问题）

### 5.1 先说清「哪些 key 真的会被播」——读源码得到的调用点

| key | 触发点（`pawn.play_anim(key)`） | 对野怪（Raider 系）是否走到 |
|---|---|---|
| `idle` | `MonsterIdleState.gd:10`（Raider 把 `idle` 换成 `MonsterIdleState`，`Raider.gd:216`）/ `IdleState.gd:8` / `SoldierIdleState` / `VillagerIdleState` | ✅ |
| `move` | `RoamState.gd:16`（野怪游荡）/ `SoldierPatrolState` / `SoldierWanderState` | ✅ |
| `run` | **`MoveState.gd:12`、`FightState.gd:36`（进场）、`FightState.gd:145`、`RaiderFleeState.gd:24`、`HarvestState`、`VillagerWorkState`…** | ✅ **用得最多** |
| `fight` | `FightState.gd:110` / `RangedFightState.gd:35` / `PawnSkillComponent.gd:119,243,299` | ✅ |
| `dead` | `DeadState.gd:25` | ✅ |
| `harvest` | `HarvestState.gd:47` / `VillagerWorkState.gd:53` | ❌ 玩家方村民专用 |
| `follow` | `FollowState.gd:305`（小队跟随）| ❌ 玩家方小队专用 |

**关键推论：`run` 比 `move` 重要得多**（寻路移动 `MoveState` 和战斗进场 `FightState` 都播 `run`）。如果只给龙映射 `move` 而漏了 `run`，龙**走路全程没有任何动画**（`play()` 静默跳过），会变成滑行。这一点必须在接入时盯住。

### 5.2 主候选 bocdagla `Dragon2.glb` —— 逐 key 映射建议

| key | 建议映射 | 依据（本人实测） | 风险 |
|---|---|---|---|
| `idle` | **`Idle_loop`** | 5.0s / loop；唯一的**地面**待机：腿/头位移仅 0.03°（基本静止）、只有尾摆 24.4°（复核员数据）。⚠️ 看图补充：**基准姿是「四足落地 + 双翼张开」**（不是收翼站姿），见 `preview_boc_Idle_loop.png` | 无 |
| `move` | **`Walk_menacing_loop`** | 1.667s / loop；**真迈步**：前脚 Tip 在 z=+1.69↔+0.55 间摆动（Δz 1.139）、抬脚 Δy 0.460（本人实测，见 §4.2）| 无 |
| `run` | **`Walk_menacing_loop`** | ⚠️ **本资产没有跑步动画**（6 条里唯一的地面位移动画就是它）。**必须有这一条映射**，否则龙滑行 | 跑起来「步频没变」；若要更像跑，需要给 `PawnModelRig.play()` 加播放速率参数（**本仓库目前没有**，`play()` 只有 `blend`）|
| `harvest` | 回落 `move`（= `Walk_menacing_loop`）| 龙无采集语义；`HarvestState` 只在村民身上走 | 无 |
| `follow` | 回落 `move`（= `Walk_menacing_loop`）| `FollowState` 只在小队成员身上走 | 无 |
| `fight` | **`Attack`** | 0.917s / once；前腿 Tip 从 (z +1.00, y 0.28) 前伸抬到 (z +2.35, y 2.36) —— **前肢立起前扑**，攻击姿态成立（§8 图 `preview_boc_Attack.png`）| 无 |
| `dead` | **缺 → 见 §6.1** | 6 条动画里没有死亡 | ⚠️ |

**额外可用（可挂到技能/飞行分支，非必需）**：`AttackPose`（0.417s，张翼起手姿）、`GroundToFly`（0.833s，地面→起飞）、`Flying_loop`（1.667s，飞行）。

### 5.3 官方 Quaternius `Dragon.gltf` —— 逐 key 映射建议（对照组）

| key | 建议映射 | 依据 | 风险 |
|---|---|---|---|
| `idle` | `Flying_Idle` | 唯一待机，但是**空中**待机（腿冻在绑定站姿）| ⚠️ 落地怪会「站着扇翅膀」|
| `move` | `Fast_Flying` | ⚠️ **本资产没有任何地面位移动画** | ⚠️ 地面移动 = 浮空滑行 |
| `run` | `Fast_Flying` | 同上 | ⚠️ 同上 |
| `harvest` | 无（静默跳过）| — | 若当村民用会没动作 |
| `follow` | `Fast_Flying` | — | 同 `move` |
| `fight` | `Punch`（备选 `Headbutt`）| 1.167s / once；`Punch` 挥爪、`Headbutt` 撞头 | 无咬击 / 无吐息 |
| `dead` | **`Death`** | 0.667s / once，**本资产唯一有真死亡动画的候选** | 无 |

---

## 6. 两个缺口的降级方案

### 6.1 缺口 A：bocdagla **没有死亡动画**

**现状链路（读代码，`DeadState.gd`）**：敌方单位 → `pawn.play_anim(&"dead")`（`DeadState.gd:25`）→ 等 `ANIM_HOLD_SEC = 0.95s` 定格 → `model_rig.begin_dissolve()` 逐 surface 换 v16 溶解材质 → 每帧写 `dissolve_progress`，`DISSOLVE_SEC = 0.9s` → `queue_free`。

**如果 `dead` 没映射会怎样（诚实说明）**：`PawnModelRig.play()` 在 `_resolved` 里找不到 key 就**静默 return**（`PawnModelRig.gd:281-282`），**不会停掉 AnimationPlayer** ⇒ 龙会**继续循环播它死前那条动画**（例如 `Walk_menacing_loop` 原地踏步 / `Attack` 反复挥爪）0.95s，然后才开始溶解。**不是崩溃，是「死得不像」。**

三个方案，按代价排序：

| 方案 | 做法 | 效果 | 代价 |
|---|---|---|---|
| **A（最省事）** | `dead` → **`AttackPose`** | 0.417s 定格张翼姿 | 一行映射。⚠️ **但要诚实说**：我渲了 `preview_boc_AttackPose.png`，它是**双翼张开、四足站立的起手姿**，**不像倒地**——读起来是「张翼威吓」不是「死」 |
| **B（推荐，若要好观感）** | `dead` → **`GroundToFly` 倒放** | 0.833s「飞行→落地」倒过来 = **收翼、伏地**，比 A 像死亡 | 需要给 `PawnModelRig.play()` 加一个反向标志（`anim_player.play(name, blend, -1.0)`），约 3~5 行；本仓库现在**没有**这个能力 |
| **C（零改动兜底）** | **不加 `dead` 映射**，纯靠 v16 贴图溶解 | 定格 → 溶解，仍然「不缩小、有消散」 | 0 行。缺点见上：溶解那 0.9s 里尸体还在原地踏步 |

**建议**：先用 **C**（零风险，v16 管线已存在且本资产适配良好——1 个 surface + 内嵌贴图，`begin_dissolve()` 会逐 surface 拷 `albedo_color`(白) 与 `albedo_texture`(4×4 调色板)，溶解覆盖整只龙）；如果实机看着难受，再上 **B**。

### 6.2 缺口 B：官方 Quaternius **没有地面移动 / 地面待机**

8 条动画 = `Death / Fast_Flying / Flying_Idle / Headbutt / HitReact / No / Punch / Yes`，**没有一条是走/跑/地面待机**；而且 §1.2 实测包围盒本来就悬空（y 1.60~3.14）、造型是大头 Q 版（§1.4）。

**降级方案**：
1. **当飞行怪 / 空中 BOSS 用**（推荐）：`idle→Flying_Idle`、`move/run/follow→Fast_Flying`、`fight→Punch`、`dead→Death`。这样 7 个 key **全部有解**，是三种里唯一「死亡动画不缺」的路线。落地时需要让它在世界坐标里**抬高**一段（模型自身悬空 1.6 个单位），或者接受贴地飞行。
2. **当坐骑/场景生物**：不接状态机，只播 `Flying_Idle`。
3. **不要**为了「地面化」去硬套 —— 腿被冻在绑定站姿，地面使用就是「站着扇翅膀滑行」，这是资产本身没有的能力，不是代码能补的（除非自己做腿部动画）。

**两个候选是互补的**：bocdagla 有地面全套但没死亡；Quaternius 官方有死亡但没地面。**建议 bocdagla 主用（地面四足龙/BOSS），Quaternius 官方备用（飞行怪）。**

---

## 7. 接入清单（任务第 4 项）

### 7.1 直接抄进 `GameDefs` 的三个数值（以 `raider_boss_def()` 或新增 `dragon_def()` 为例）

```gdscript
	d.model_path = "res://dragon-assets/poc/bocdagla/upload/Dragon2.glb"   # 见 §7.2 的路径建议
	d.model_scale = 0.80                  # 实测渲染 4.55 m 直立（= 2.08 × KayKit 人类）见 §3.4
	d.model_face_offset_deg = 180.0        # 模型自身朝 +Z，项目逻辑前方 -Z，见 §4
```

配套（可选但建议一起给）：

```gdscript
	# 颜色：本资产 albedo_color = (1,1,1,1) 纯白 + 内嵌 4×4 调色板 ⇒ apply_tint 是「乘白」，不会偏色
	d.model_tint = Color(1.0, 1.0, 1.0)    # 想区分精英/头目再给色，例如 Color(1.0, 0.55, 0.55)
	# 武器挂点：本模型没有 handslot_l / handslot_r 节点 ⇒ apply_weapon_loadout 直接 return，不填也安全
```

**两个必须一起改的数值（否则大模型会很怪）**：

| 项 | 现状（读代码） | 建议 |
|---|---|---|
| 碰撞半径 | `Pawn.gd:307/320` **硬编码 `capsule.radius = 0.4`**、`nav_agent.radius = 0.4`，**不随 `model_scale` 缩放** | 4.55 m 高的龙配 0.4 m 胶囊 ⇒ 小兵能走进龙身体里。若在意，需要给 `PawnDef` 加半径字段（本仓库现在**没有**）|
| 攻击距离 | `AttackerComponent.in_range()` 用**表面距离** `中心距 − 0.4 − 目标半径 ≤ attack_range`（`AttackerComponent.gd:184-192`），`SELF_RADIUS` **硬编码 0.4** | 龙的「表面」比 0.4 m 半径大得多，`attack_range` 会显得偏大/偏小错位。现头目用 2.6，龙建议**先按 2.6~3.0 试**，再实机调 |

### 7.2 `model_path` 的落位建议

- **本次验证就放在** `res://dragon-assets/poc/bocdagla/upload/Dragon2.glb`（本任务红线要求只写 `poc/`，所以**没有**搬动任何文件）。
- **正式接入时**建议移到 `res://assets/models/dragons/Dragon2.glb`（与 `assets/audio/`、`assets/vfx/` 的「约定路径自动生效」惯例一致），并**同目录补一份 `CREDITS.md`**：复核员已证 `dragon.zip` 内**没有 LICENSE 文件**、作者自述是「Creative Commons Attribution（未标版本号）」⇒ 必须自留「作者 bocdagla / 来源 URL / 抓取日期 2026-10-01 / 许可原文照录」。**不要擅自写成 "CC BY 4.0"。**
- 路径必须在 `res://` 内（`PawnModelRig._load_glb_scene()` 先 `load()` 再回退 `GLTFDocument.append_from_file(path)`，两者都吃 `res://` 路径）。`dragon-assets/` 在项目内 ✅。

### 7.3 ⚠️ 尺寸相关的「连带数值」提醒

`model_scale` 不只影响外观，还驱动这几处（读代码）：

| 位置 | 公式 | 用 0.80 的后果 |
|---|---|---|
| `HealthBar3D.gd:78-79` | `_head_height = RISE(2.1) * max(model_scale, 0.85)` | 血条挂在 **1.785 m**（`max(0.8, 0.85) = 0.85`）——而龙直立 **4.55 m** ⇒ **血条会插在龙肚子里** ⚠️ |
| `FocusMarker.gd:65-68` | `BASE_HEIGHT(2.1) * max(model_scale, 0.8)` | 集火箭头同样偏低 ⚠️ |
| `SpeechBubble3D.gd:289` | `RISE_BASE * max(model_scale, 0.85) + RISE_MARGIN` | 同上（野怪不冒泡，影响小）|

**这是个真实的、非显然的坑**：`HealthBar3D` 的抬升公式是**线性乘 `model_scale`**，而本资产「模型单位高度 : 实际渲染高度 = 5.68 : 10.45」的错位意味着 —— **血条想抬到龙头顶需要 `model_scale ≈ 2.17`（4.55/2.1），但那会让龙渲染成 12.3 m 高**。⇒ 建议接入时**单独给血条高度一个 def 字段**，或先把这条公式改成读「实测渲染高度」。**本次未改任何源码，仅记录。**

### 7.4 🔴 `ANIM_MAP` 结论（去读 `src` 后的确定答案，不是猜的）

**核实过程**（命令见 §10）：全仓库 grep `ANIM_MAP|anim_map`，`scripts/`、`tests/`、`tools/`、`scenes/` 下**只有 1 处命中且不是引用**——`Pawn.gd:502` 的一句注释。其余命中都在 `PawnModelRig.gd` 自身内部。

**事实**：
1. `PawnModelRig.ANIM_MAP` 是 **`const` 全局字典**（`PawnModelRig.gd:17-31`），**不是 per-def 的**。
2. `PawnModelRig.setup()` 的签名是 `(path, model_scale, face_offset_deg, weapon_main, weapon_offhand)`（`PawnModelRig.gd:111-112`）——**没有任何动画映射参数**。
3. `Pawn._apply_def()` 唯一的 `model_rig.setup(...)` 调用（`Pawn.gd:463-464`）**只透传这 5 个参数**。
4. `_resolve_anim_names()` 的解析逻辑是「**按精确名相等**匹配」（`PawnModelRig.gd:269-271`），一个 key 只能对应**一个名字**。

> ### 结论：**本仓库目前没有 per-def 覆盖能力，`ANIM_MAP` 是全局唯一映射。**
> 龙的动画名（`Idle_loop` / `Walk_menacing_loop` / `Attack` …）与 KayKit 的（`Idle` / `Walking_A` / `1H_Melee_Attack_Slice_Horizontal` / `Death_A` …）**完全不同**，所以**照现状必须动全局表**；直接改全局表的值会把**所有 KayKit 单位**（主角 / 村民 / 士兵 / 现有野怪）**全部打哑**（`play()` 静默跳过）——**包括主角的连招/技能 key**（`combo_light`/`skill_aoe`…也都在这张表里）。

**两种可落地改法（推荐同时上，或者只上第二种）**：

**改法一（推荐，干净）：新增 per-def 覆盖**
```gdscript
# PawnDef.gd
@export var anim_map: Dictionary = {}      # 项目 key(StringName) → 该模型的动画名（空 = 用全局 ANIM_MAP）

# PawnModelRig.gd：setup() 加一个 anim_map 参数并保存到 _anim_map(_override)，
# _resolve_anim_names() 里改成：
var map: Dictionary = _anim_map if not _anim_map.is_empty() else ANIM_MAP
```
`Pawn._apply_def()` 多透传一个 `def.anim_map`。约 8~10 行，**对现有 def 零影响**（空字典 = 走旧路径）。

**改法二（零风险过渡，不动任何 def）：把 `ANIM_MAP` 的值从「一个名字」升级为「候选名数组」，现有 KayKit 名排第一**
```gdscript
	&"idle":  ["Idle", "Idle_loop"],
	&"move":  ["Walking_A", "Walk_menacing_loop"],
	&"run":   ["Running_A", "Walk_menacing_loop"],
	&"fight": ["1H_Melee_Attack_Slice_Horizontal", "Attack"],
	&"dead":  ["Death_A", "Death", "AttackPose"],
```
`_resolve_anim_names()` 改成按候选顺序取**第一个在该模型里存在的**。因为**现有名排第一且仍然存在**，所有 KayKit 单位解析结果**逐字节不变**；龙则落到后面的候选上。**这一种改法能同时覆盖 bocdagla 与官方 Quaternius 两个候选。**

**安全性实证**（我实测了 KayKit 主角的 76 条动画名，确认不会误命中）：列表里存在裸名 `Idle`、`Walking_A`、`Running_A`、`Death_A`、`Hit_A`，**不存在**裸名 `Attack`、`Idle_loop`、`Walk_menacing_loop`、`Death`。所以「现有名排第一」的策略下，追加的龙名**不可能抢走** KayKit 单位的解析结果。

**另一个必须知道的点**：`LOOP_KEYS = [idle, move, run, follow, harvest]`（`PawnModelRig.gd:34`）在 `play()` 里会**强制** `a.loop_mode = LOOP_LINEAR`（`PawnModelRig.gd:291-294`）。所以官方 Quaternius 那 8 条「glTF 里没标 loop」的动画**只要挂在 `idle/move/run` 上就会被项目侧强制循环**，不需要改资产。

---

## 8. 渲染对照图（任务第 3 项）

全部用**同一个相机**（3/4 视 azim 38° / elev 16° / dist 10.5 / targeth 2.5m，960×720），模型 `model_scale = 0.8`，左下角是 KayKit 人类参照（`model_scale = 1.0`）⇒ **六张图姿势之间可直接对比、尺寸可直接对比**。

> task-4 原始描述里点名的 `dragon-assets/poc/preview.png` 也已产出：它是
> [preview_boc_Walk_menacing_loop.png](preview_boc_Walk_menacing_loop.png) 的副本（sha256 相同 `bfc3dbf8…`），
> 取「四足行走 + 人类尺寸参照」这一张当门面图；Lead 派单里点名的 `preview_*.png` 三张见下表前三行。

| 文件 | 内容 | 看图确认到的事实 |
|---|---|---|
| [preview.png](preview.png) | **门面图**（= `preview_boc_Walk_menacing_loop.png` 的副本）| 四足带翼龙行走 + 人类尺寸参照 |
| [preview_boc_Attack.png](preview_boc_Attack.png) | `Attack` 定格 50% | ✅ 双翼张开、**前肢抬起前扑**、头前伸 —— 攻击姿态合理 |
| [preview_boc_Walk_menacing_loop.png](preview_boc_Walk_menacing_loop.png) | `Walk_menacing_loop` 定格 50% | ✅ **四足着地、前腿抬起迈步**、翼收拢、头前压 —— 真在走路，不是滑行 |
| [preview_boc_Idle_loop.png](preview_boc_Idle_loop.png) | `Idle_loop` 定格 50% | ✅ **四足落地站立 + 双翼张开**待机（基准姿是张翼，不是收翼）|
| [preview_boc_AttackPose.png](preview_boc_AttackPose.png) | `AttackPose` 定格 50% | ⚠️ 张翼站立姿 —— **据此判定它当死亡动画「不像」**（§6.1 方案 A 的诚实边界）|
| [preview_boc_GroundToFly.png](preview_boc_GroundToFly.png) | `GroundToFly` 定格 50% | 前压低伏、双翼横展的起跳姿；**倒放可读作「落地伏地」**（§6.1 方案 B，建议实机确认）|
| [preview_boc_Flying_loop.png](preview_boc_Flying_loop.png) | `Flying_loop` 定格 50% | 飞行姿态 |
| [preview_facing_markers.png](preview_facing_markers.png) | 侧视 + **红球(+Z)/蓝球(−Z)** 标记 + 人类 | ✅ **头在红球(+Z)侧、尾在蓝球(−Z)侧** ⇒ 朝 +Z（§4.3）|
| [preview_scale_0.80.png](preview_scale_0.80.png) | 正交侧视，龙 0.80 + 人类 1.0 并排 | ✅ 龙 ≈ 2.1 × 人高，BOSS 感成立（§3.4 推荐值的目视依据）|
| [preview_scale_0.40.png](preview_scale_0.40.png) | 同上但 0.40 | 龙 ≈ 1.04 × 人高 ⇒ **证明任务书的 0.43 会渲成「人一样高」** |
| [preview_quaternius_Flying_Idle.png](preview_quaternius_Flying_Idle.png) / [preview_quaternius_side.png](preview_quaternius_side.png) / [preview_quaternius_top.png](preview_quaternius_top.png) | 官方 Quaternius 版 | ⚠️ **大头 Q 版浮空龙、无四足站姿**（§1.4）|
| [preview_h45_Idle_loop.png](preview_h45_Idle_loop.png) / [preview_h45_Walk_menacing_loop.png](preview_h45_Walk_menacing_loop.png) / [preview_h45_Attack.png](preview_h45_Attack.png) | 用 Lead 的 `preview.gd --h 4.5` 原样渲的 3 张 | ⚠️ 见下 |

### 8.1 ⚠️ 关于任务书指定的 `--h 4.5` 取景（必须记录）

用 Lead 的 `preview.gd --h 4.5` 渲的图**能用但取景偏小**，原因正是 §3 那个 1.84× 错位：`preview.gd` 用 **静态 AABB 高度 10.4513** 反推 `model_scale = 4.5/10.4513 = 0.431`，而 0.431 实际只渲出 **2.45 m** 高。它的非背景像素统计也印证了：

| 图 | 非背景采样点 / 总采样 | 占比 |
|---|---|---|
| `preview_h45_Attack.png`（--h 4.5, Attack）| 608 / 70,200 | 0.87% |
| `preview_h45_Idle_loop.png`（--h 4.5, Idle）| 819 / 70,200 | 1.17% |
| `preview_h45_Walk_menacing_loop.png`（--h 4.5, Walk）| **224 / 70,200** | **0.32%**（已接近 `preview.gd` 自己的 `nonbg > 200` 失败阈值）|
| 对比：`shot.gd` 同一批图 | 39,370~41,368 / 76,800 | **51~54%** |

> ⚠️ **macOS 文件系统大小写不敏感**（本轮实际踩到）：`shot.gd` 输出的 `preview_boc_Attack.png` 与 `--h 4.5` 版的 `preview_boc_attack.png` 在 macOS 上是**同一个文件**，会互相覆盖（我第一次就是这么把 `--h 4.5` 版覆盖掉的，已改用 `preview_h45_*.png` 命名并重渲）。跨平台协作时文件名大小写不要只靠字母区分。

⇒ **图上主体太小不是脚本 bug，是取景高度算错了**。我保留了 `--h 4.5` 的原始版本（满足任务书字面要求 + 留证），另出一套正确取景的图（上表前 6 张）作为**真正能用来判断造型**的证据。图片本身非空、非全黑，已逐张用 `read_image` 目视确认。

---

## 9. 未完成 / 未核实（不猜，列出来）

| 项 | 状态 | 原因 |
|---|---|---|
| `quaternius_official_Dragon_Evolved.gltf` 的实测细节 | ⚠️ **只下载未实测** | 任务书要求对照的是官方 `Dragon.gltf`；`Dragon_Evolved` 991,335 B 已落盘留档（sha256 `39ba6ea2…`），本次未跑探针/渲染 |
| `kin.gd` 里手工套 GPU 蒙皮公式 `pose * rest⁻¹` 算出的 AABB | ❌ **方法失败，结论未采用** | 算出来（静止位姿 20.25×10.65×18.06）与静态网格（7.31×10.45×11.46）**不自洽**，且与正交渲染量测（5.68 单位高）矛盾。**该路径的任何绝对数字都没有进本报告结论**；只有「逐帧尺寸会变」这一点与渲染可见的姿势差异一致。尺寸一律以 §3 的正交渲染量测为准 |
| `--h 4.5` 那三张图的观感 | ⚠️ 主体偏小 | 见 §8.1，已用正确取景的图补上 |
| 本资产「为什么渲染尺寸 ≈ mesh 顶点空间而不是 ×1.668 的 Armature 空间」的根因 | ⚠️ **未查到根因**（只证实了现象） | 现象本身**三重量测一致**（线性校验 0.2% 误差、六种姿势、人类参照自检），但「Godot 蒙皮渲染不乘父链缩放」这一步我没有读 Godot 源码验证。**接入建议按实测值走**（§3.4 / §7.1），不要按 AABB |
| 许可（CC-BY 版本号 / CREDITS） | ⚠️ **未复核** | 属 task-3 范围；我只落地使用了复核员已下载的文件。`dragon.zip` 内无 LICENSE 一事见复核报告 §4.5 |
| 实机接入后的观感（血条高度 / 碰撞半径 / 攻击距离） | ⚠️ **未实测** | 本任务红线是「只做离线验证、不改仓库源码、不动 `assets/_PLACEHOLDER/`」⇒ §7.3 只给风险与建议，**没有改任何代码、没有跑游戏** |
| 项目回归测试 | ⚠️ **未跑** | 超出本任务范围，且并行有其他成员在改 `scripts/`、`tests/`（我看到 `HealthComponent` / `PawnSkillComponent` / `NightAssaultTest` 等同期在动），此时跑批不能归因于本次改动 |

---

## 10. 复现命令（全部为本次实际执行）

```bash
cd /Users/zhima/Desktop/demo-1/dragon-assets/poc

# ---------- ① 官方 Quaternius Drive 直连下载（匿名，无需登录）----------
curl -sS -L --max-time 120 "https://drive.google.com/uc?export=download&id=1-mQSm6_oGt7-EEQfNj1dFWYgPQy4AdPC" \
     -o quaternius_official_Dragon.gltf -w "HTTP %{http_code} size=%{size_download} type=%{content_type}\n"
#   → HTTP 200 size=427100 type=application/octet-stream
curl -sS -L --max-time 180 "https://drive.google.com/uc?export=download&id=1Mcfuavq7F4itG9xhqc-20_IL257ZY2_3" \
     -o quaternius_official_Dragon_Evolved.gltf      # 991,335 B，留档未实测
shasum -a 256 bocdagla/upload/Dragon2.glb quaternius_official_Dragon.gltf \
              quaternius_official_Dragon_Evolved.gltf quaternius_dragon_evolved_polypizza.glb

# ---------- ② 结构探针（网格/三角面/骨骼/动画名/包围盒/材质贴图）----------
cd /Users/zhima/Desktop/demo-1
godot --headless --path . --script dragon-assets/poc/probe2.gd -- res://dragon-assets/poc/bocdagla/upload/Dragon2.glb
godot --headless --path . --script dragon-assets/poc/probe2.gd -- res://dragon-assets/poc/quaternius_official_Dragon.gltf
godot --headless --path . --script dragon-assets/poc/probe2.gd -- res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb
#   probe2.gd 相对 probe.gd 的修正：probe.gd 用 mi.global_transform 量包围盒，在 SceneTree._init 期
#   可能报 "Condition !is_inside_tree() is true" 而退化成 IDENTITY（我实测到了）→ 丢掉 Armature 的
#   1.668 缩放。probe2.gd 改手工沿父链累乘变换，并额外打印「顶点真值包围盒」与每层节点 scale。

# ---------- ③ 骨架运动学（朝向 + 迈步方向 + 逐动画骨骼位移）----------
godot --headless --path . dragon-assets/poc/kin.tscn -- --model res://dragon-assets/poc/bocdagla/upload/Dragon2.glb
#   输出存档：kin_bocdagla.txt

# ---------- ④ 实际渲染尺寸标定（正交相机 + 像素量测；人类作参照）----------
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim Idle_loop --camsize 7.0 --out res://dragon-assets/poc/preview_scale_0.40.png
godot --path . dragon-assets/poc/size.tscn -- --scale 0.80 --anim Idle_loop --camsize 7.0 --out res://dragon-assets/poc/preview_scale_0.80.png
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim ""        --camsize 7.0   # 绑定位姿
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim Walk_menacing_loop --camsize 7.0
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim Attack --camsize 7.0
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim Flying_loop --camsize 7.0
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim GroundToFly --camsize 7.0
godot --path . dragon-assets/poc/size.tscn -- --scale 0.40 --anim Idle_loop --markers 1 --camsize 7.0 \
      --out res://dragon-assets/poc/preview_facing_markers.png        # ← 朝向标记球图
godot --path . dragon-assets/poc/size.tscn -- --model res://dragon-assets/poc/quaternius_official_Dragon.gltf \
      --scale 0.8 --anim Flying_Idle --camsize 7.0

# ---------- ⑤ 六种姿势 + 官方对照的预览渲染（同一机位，可横向对比）----------
for a in Attack Walk_menacing_loop Idle_loop AttackPose GroundToFly Flying_loop; do
  godot --path . dragon-assets/poc/shot.tscn -- --scale 0.8 --anim "$a" \
        --out "res://dragon-assets/poc/preview_boc_${a}.png" --ref 1 --dist 10.5 --targeth 2.5
done
for a in Flying_Idle Punch Death; do
  godot --path . dragon-assets/poc/shot.tscn -- \
        --model res://dragon-assets/poc/quaternius_official_Dragon.gltf \
        --scale 1.0 --anim "$a" --out "res://dragon-assets/poc/preview_quaternius_${a}.png" --dist 6.5 --targeth 1.6 --azim 30
done
godot --path . dragon-assets/poc/shot.tscn -- --model res://dragon-assets/poc/quaternius_official_Dragon.gltf \
      --scale 1.0 --anim Flying_Idle --out res://dragon-assets/poc/preview_quaternius_side.png --dist 6.0 --targeth 1.5 --azim 88 --elev 8

# ---------- ⑥ 用 Lead 的 preview.gd 原样跑「--h 4.5」版（满足任务书字面要求）----------
#   ⚠️ macOS 大小写不敏感：输出名不要写成 preview_boc_attack.png，否则会覆盖 shot.gd 的 preview_boc_Attack.png
godot --path . dragon-assets/poc/preview.tscn -- --anim "Attack" --out res://dragon-assets/poc/preview_h45_Attack.png --h 4.5
godot --path . dragon-assets/poc/preview.tscn -- --anim "Walk_menacing_loop" --out res://dragon-assets/poc/preview_h45_Walk_menacing_loop.png --h 4.5
godot --path . dragon-assets/poc/preview.tscn -- --anim "Idle_loop" --out res://dragon-assets/poc/preview_h45_Idle_loop.png --h 4.5

# ---------- ⑦ ANIM_MAP 是否有 per-def 覆盖：全仓库证据 ----------
grep -rn "ANIM_MAP\|anim_map" --include=*.gd --include=*.tscn --include=*.tres scripts/ tests/ tools/ scenes/
#   → 唯一命中 scripts/entities/pawn/Pawn.gd:502，且是注释 ⇒ 无任何覆盖点
grep -n "const ANIM_MAP\|const LOOP_KEYS\|func setup\|_resolve_anim_names" scripts/components/PawnModelRig.gd
grep -n "model_rig.setup" scripts/entities/pawn/Pawn.gd            # → 463 行，只透传 5 个参数
grep -n "const RISE" scripts/components/HealthBar3D.gd             # → 2.1
grep -n "const SELF_RADIUS\|func in_range" scripts/components/AttackerComponent.gd
grep -n "capsule.radius\|nav_agent.radius" scripts/entities/pawn/Pawn.gd   # → 0.4 硬编码
```

### 本轮新增的工具脚本（都在 `dragon-assets/poc/`，可复用）

| 文件 | 作用 |
|---|---|
| `probe2.gd` | 结构探针修正版（手工父链变换 + 顶点真值包围盒 + 逐层节点 scale 打印 + 材质细节 + 循环位）|
| `kin.gd` / `kin.tscn` | 骨架运动学：全骨骼静止位姿、逐动画骨骼位移幅度与轨迹、朝向/迈步判据 |
| `size.gd` / `size.tscn` | **正交渲染 + 像素量测**标定实际渲染尺寸与朝向（带人类参照 + 红/蓝轴标记球）|
| `shot.gd` / `shot.tscn` | 姿势预览渲染（多机位、可带人类参照、可复用同一机位横向对比）|

### 踩坑记录（供后续复用）

1. **`probe.gd` 的包围盒在 headless 下会量错**：`extends SceneTree` 的 `_init` 期 `get_root().add_child(root)` 后 `get_global_transform()` 仍可能报 `Condition "!is_inside_tree()" is true`，退化成 IDENTITY，**静默丢掉父链缩放**（本项目这个资产正好差 1.668×）。凡量包围盒一律**手工沿父链累乘**或改用渲染量测。
2. **先看最先出现的 Parse Error**：我在 `kin.gd` 里误留一个全角冒号 `：`，Godot 只报 `Parse Error: Invalid character "：" (U+FF1A)`，但**进程不退出**（前台 `timeout` 命令 macOS 上没有，直接挂住）。排查顺序永远是「第一条 Parse Error」而不是后面的 `Failed to load script`。
3. **`--headless` 抓图会挂死**（Lead 已记录，本次遵守）：渲染一律不带 `--headless`。
4. `godot --headless --path . <scene.tscn>` 跑场景（非 `--script`）是可靠的：`await get_tree().process_frame` 正常推进，`Skeleton3D` 的骨骼位姿也是真实属性、不依赖渲染。
5. **macOS 文件系统大小写不敏感**：`preview_boc_attack.png` 与 `preview_boc_Attack.png` 是同一个文件。我第一次用 `shot.gd` 渲 `preview_boc_Attack.png` 时**静默覆盖**了 Lead 用 `--h 4.5` 渲的 `preview_boc_attack.png`（发现方式：两者 sha256/字节数完全相同）。已改名为 `preview_h45_*.png` 重渲。**跨平台协作别只靠大小写区分文件名。**
