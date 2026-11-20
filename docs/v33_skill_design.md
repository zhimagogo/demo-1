# v33 进阶职业技能（跳劈 / 陨石术 / 贯穿射击 / 隐身）实现契约

> 本文件是 v33 的**冻结接口契约**：四个人（Lead / skills-dev / pawn-dev / vfx-dev / test-dev）按此并行开发，
> 谁都不许单方面改这里的名字与语义；需要变更先在团队消息里提出，由 Lead 更新本文件。
> 约定沿用仓库规范：代码注释与用户可见字符串写中文，标识符/信号/节点名用英文。

## 0. 目标（用户需求原文口径）

| 进阶职业 | 新技能 | 玩法口径 |
| --- | --- | --- |
| 狂战士（`settler_berserker`） | 跳劈 `leap_slam` | 前摇较长 → 跃向目标落点砸地 → 地面单次圆形 AOE 伤害 + **怪物击飞并被控制**（眩晕） |
| 元素法师（`settler_elementalist`） | 陨石术 `meteor` | 长前摇、原地吟唱 → 目标点预警圈 → 陨石落地**高额伤害**，**容易被躲避**（离开圈即无伤） |
| 狙击手（`settler_sniper`） | 贯穿射击 `piercing_shot` | 向前射出一枚更大的子弹，**贯穿一串目标**，射程很远 |
| 暗杀者（`settler_slayer`） | 隐身 `stealth` | 隐身后**模型 shader 进入隐身态**，敌人一段时间内看不到目标；接近目标或逃生时释放 |

另外两条硬需求：
1. **新技能要进技能树**：转职后的进阶职业拥有自己的技能树（含「点亮后解锁该技能」的节点）。
2. **转职时技能点清空并全额返还**：已投入的点数全部退回 `skill_points`，玩家可重新分配。
3. **四个技能全部要有对应特效**（VFXManager 内置 EffectDef，按 id 注册）。

## 1. 文件归属（写范围，冲突即停手并找 Lead）

| 归属 | 文件 |
| --- | --- |
| **Lead** | `scripts/defs/PawnSkillDef.gd`、`scripts/defs/PawnDef.gd`、`scripts/defs/SkillNodeDef.gd`、`scripts/defs/SkillTreeDef.gd`、`scripts/defs/GameDefs.gd`、`scripts/entities/pawn/PawnSkillTree.gd`、`scripts/ui/*`、`CLAUDE.md`、`AGENTS.md`、`docs/CHANGELOG.md`、本文件、`tools/godot_locked.sh` |
| **skills-dev** | `scripts/components/PawnSkillComponent.gd`、`scripts/entities/SkillMeteorStrike.gd`（新）、`scripts/entities/SkillPiercingShot.gd`（新）、`scripts/entities/pawn/states/SkillCastState.gd`（新） |
| **pawn-dev** | `scripts/entities/pawn/Pawn.gd`、`scripts/entities/pawn/Soldier.gd`、`scripts/components/PawnModelRig.gd`、`scripts/entities/pawn/states/StunnedState.gd`（新）、`scripts/entities/pawn/states/FightState.gd`、`scripts/entities/pawn/states/RangedFightState.gd` |
| **vfx-dev** | `scripts/autoload/VFXManager.gd`、`assets/shaders/stealth_cloak.gdshader`（新）、`tools/v33_skill_shot.gd/.tscn`（新） |
| **test-dev** | `tests/AdvancedSkillTest.gd/.tscn`（新）、`tools/run_all_tests.sh`、`tests/SceneValidation.gd`（仅追加契约检查） |

工具链约束：
- **同一时刻只允许一个 godot 进程**（`.godot` 缓存会打架）。任何 godot 调用一律走 `bash tools/godot_locked.sh <godot 参数...>`（mkdir 锁 + 陈旧锁回收，最多等 20 分钟）。
- 本仓库**没有 git**：不要依赖回滚，改前先读、改后立刻跑测试。
- 新增 `class_name` 后需要 Lead 统一执行 `godot --headless --editor --quit --path .` 重建类缓存；需要时在群里喊 Lead。

## 2. 数据层契约（Lead 实现，其他人直接引用）

### 2.1 `PawnSkillDef`（新增 kind 与字段）

```gdscript
enum Kind { BLIZZARD, BLOOD_RAGE, RAPID_SHOT, BACKSTAB, LEAP_SLAM, METEOR, PIERCING_SHOT, STEALTH }

# ---- v33 前摇 / 位移类 ----
@export var windup: float = 0.0            # 前摇（吟唱）秒数；0 = 瞬发
@export var recover: float = 0.25          # 收招硬直秒数
@export var radius: float = 0.0            # 复用既有字段：AoE 半径（跳劈 / 陨石）
@export var leap_speed: float = 16.0       # 跳劈滞空水平速度（m/s；时长 = 距离/速度 钳到 [0.25, 0.9]）
@export var leap_height: float = 3.0       # 跳劈抛物线顶点高度（米）
@export var knockback_distance: float = 3.2  # 击飞水平位移
@export var knockback_height: float = 2.6    # 击飞高度
@export var airborne_time: float = 0.55      # 击飞滞空秒数
@export var stun_duration: float = 1.1       # 落地后眩晕（控制）秒数
@export var telegraph: float = 1.1           # 陨石：预警圈出现到落地的秒数
@export var pierce_length: float = 26.0      # 贯穿距离（米）
@export var pierce_radius: float = 1.0       # 贯穿判定半径（米）
@export var pierce_speed: float = 26.0       # 贯穿弹体飞行速度（m/s）
@export var stealth_duration: float = 5.0    # 隐身持续秒数
@export var escape_hp_ratio: float = 0.35    # 隐身：逃生触发血线（血量比例低于此值即释放）
@export var approach_range: float = 7.0      # 隐身：接近目标触发距离（米）
```

### 2.2 `PawnDef`

```gdscript
@export var extra_skills: Array[PawnSkillDef] = []   # 进阶职业技能（v33）；基础四职业为空
func all_skills() -> Array[PawnSkillDef]             # = [skill] + extra_skills（过滤 null）
func has_skill_id(skill_id: StringName) -> bool
```
`skill`（主技能）语义不变：基础四职业只有它；进阶职业 = 主技能（血怒/暴风雪/快速射击/背刺的进阶数值）+ `extra_skills`（本版本新增技能）。

### 2.3 `SkillNodeDef`

```gdscript
@export var unlocks_skill_id: StringName = &""   # rank ≥ 1 时解锁该 id 的技能（v33，多技能门禁）
```
旧字段 `unlocks_skill` / `pre_unlocked` 保留（主角树与基础四职业树继续用旧语义）。

### 2.4 `PawnSkillTree`（运行时）

```gdscript
func is_skill_unlocked(skill_id: StringName) -> bool
# 规则：树里有任何节点声明了 unlocks_skill_id → 精确匹配（该节点 rank ≥ 1 才算解锁）；
#       否则回落旧语义 skill_unlocked()（gate_node_id 根节点；无门禁 = true）。
func reset_and_refund() -> int      # 清空全部已投入级数（含预点亮重挂），返回**返还的点数**
func set_tree_def(new_def: SkillTreeDef) -> void   # 转职换树：换布局 + apply_pre_unlocks()
func points_spent() -> int          # 只算玩家真花的点（预点亮不计）
```

### 2.5 `GameDefs`（数值，Lead 定稿）

四个新技能 def（`skill_leap_slam_def()` / `skill_meteor_def()` / `skill_piercing_shot_def()` / `skill_stealth_def()`）：

| 技能 | id | CD | cast_range | damage | 关键参数 |
| --- | --- | --- | --- | --- | --- |
| 跳劈 | `leap_slam` | 14s | 8.0m | 34 | windup 0.55 / recover 0.30 / radius 3.4 / knockback 3.2·2.6m / airborne 0.55 / stun 1.1 |
| 陨石术 | `meteor` | 16s | 11.0m | 55 | windup 1.0（原地吟唱）/ recover 0.35 / telegraph 1.1 / radius 4.2 |
| 贯穿射击 | `piercing_shot` | 12s | 18.0m | 26（每个目标） | pierce_length 26 / pierce_radius 1.0 / pierce_speed 26 |
| 隐身 | `stealth` | 18s | 0（自身） | 0 | stealth_duration 5.0 / escape_hp_ratio 0.35 / approach_range 7.0 |

进阶职业 def 追加：

| 进阶职业 | `extra_skills` | `skill_tree_id` |
| --- | --- | --- |
| 狂战士 | `[skill_leap_slam_def()]` | `settler_berserker_tree` |
| 元素法师 | `[skill_meteor_def()]` | `settler_elementalist_tree` |
| 狙击手 | `[skill_piercing_shot_def()]` | `settler_sniper_tree` |
| 暗杀者 | `[skill_stealth_def()]` | `settler_slayer_tree` |

四棵进阶树（`GameDefs.skill_tree_def()` 按 id 分派）节点布局相同、名字随职业：

| 节点 id | 显示名 | 分支 | max_rank | 前置 | unlocks_skill_id |
| --- | --- | --- | --- | --- | --- |
| `class_skill` | 职业技 | 0 | 1 | — | 主技能 id（如 `blood_rage`） |
| `advanced_skill` | 新技能名（跳劈/陨石术/贯穿射击/隐身） | 1 | 1 | `class_skill` 1 级 | 新技能 id（如 `leap_slam`） |
| `damage` | 伤害强化 | 2 | 5 | `class_skill` 1 级 | — |
| `vitality` | 生命强化 | 3 | 5 | `damage` 1 级 | — |

`gate_node_id = &"class_skill"`；基础四职业继续用 `generic` 树（行为零变化）。

**转职返还口径（冻结，2026-10-02 Lead 裁决）**：**任何转职都清空已投入级数并全额返还**
（含沿用 `generic` 树的骑士 / 雷电法师 / 漫游射手 / 忍者）——转职 = 一次免费洗点，规则统一、
玩家不用记「哪些职业会洗点」。`Soldier._rebind_skill_tree()` 因此不再有「树 id 相同就不换树」
的短路：一律 `reset_and_refund()` → `set_tree_def(def.skill_tree_id 对应的树)` → `skill_points += 返还`。
`tests/CitizenManageTest.gd` 中「转职保留已加点」的旧断言随之更新（v25 → v33 语义变更，
test-dev 负责同步）。

## 3. 运行时契约（skills-dev / pawn-dev 之间的界面）

### 3.1 `Pawn`（pawn-dev 实现，skills-dev 调用）

```gdscript
# ---- 技能门禁 ----
func is_skill_unlocked(skill_id: StringName) -> bool     # 无树 = true；有树走 skill_tree.is_skill_unlocked
func combat_skill_unlocked() -> bool                     # 兼容旧调用（主技能门禁）

# ---- 施法态 ----
var skill_locked: bool = false
func is_skill_locked() -> bool
func begin_skill_cast(skill: PawnSkillDef, target: Node) -> bool
	# **返回是否真的进入了施法态**（施法状态未注册 / 已死亡 → false，组件不得消耗 CD）
	# 成功：set_skill_locked(true) + state_machine.transition_to("skill_cast", {"skill": skill, "target": target})
func end_skill_cast() -> void
	# 解除锁定；目标仍有效 → transition_to("fight", {"target": target})，否则 transition_to("idle")

# ---- 击飞 / 控制 ----
func apply_knockup(dir: Vector3, distance: float, height: float, airborne: float, stun: float) -> void
	# 进入 "stunned" 状态；滞空期走抛物线（水平 lerp + sin 弧），落地后眩晕 stun 秒
func is_stunned() -> bool
func is_controlled() -> bool          # 滞空或眩晕中
func tick_control(delta: float) -> bool   # 由 StunnedState 每物理帧调用；返回 false = 控制结束

# ---- 隐身 ----
func apply_stealth(duration: float) -> bool   # 已隐身 / 已死亡 → false；成功：置 can_be_targeted_by_enemies=false
                                              # + model_rig.set_stealth(true) + attach_trail(&"stealth_shimmer")
func break_stealth() -> void                  # 立即解除：恢复可被索敌 + model_rig.set_stealth(false)
                                              # + spawn_effect(&"stealth_break", ...) + 释放 shimmer
func is_stealthed() -> bool
func can_be_seen_by_enemies() -> bool         # = can_be_targeted_by_enemies and not is_stealthed()
```
隐身规则：**造成伤害即破隐**（监听 `EventBus.damage_dealt`，`source == self` 时 break）；**受到伤害不破隐**（逃生用）；到期自动 break。
索敌侧：`Pawn._valid_hostile_candidate()` 改用 `can_be_seen_by_enemies()`；`FightState`/`RangedFightState` 发现当前目标不可见 → 脱战回 `idle`。

### 3.2 `PawnSkillComponent`（skills-dev 实现，状态与 Pawn 调用）

```gdscript
var skills: Array[PawnSkillDef] = []     # 施放优先级 = def.extra_skills（进阶技能优先）+ [def.skill]
var skill: PawnSkillDef = null           # 主技能（= def.skill；既有调用点兼容，保持存在）
func sync_skills_from_def() -> void      # 转职 / def 更换后重建技能列表与冷却表（Soldier.promote_to 调用）
func try_cast(target: Node) -> bool      # 逐个试；第一个 ready + 条件满足即施放（返回 true = 本帧不再普攻）
func is_casting() -> bool                # 前摇 / 收招 / 跳劈滞空中
func cooldown_left(skill_id: StringName = &"") -> float
func tick_cast(delta: float) -> void     # SkillCastState 每物理帧调用（推进前摇 → 执行 → 收招 → 回调 end_skill_cast）
func abort_cast() -> void                # 中途被打断（击飞 / 死亡等）：不结算效果、解除锁定
func notify_stats_rebased() -> void      # 已有：升级 / 加点后重挂血怒基线
func is_raging() -> bool                 # 已有：血怒生效中
```
**转职联动（冻结）**：`Soldier.promote_to()` 换 def 后必须调用 `skill_comp.sync_skills_from_def()`（否则进阶技能不会进入施放列表），随后 `notify_stats_rebased()`；前摇技能起手必须用 `if not pawn.begin_skill_cast(...): return false`，**只有真正进入施法态才吃 CD**。
既有四个技能（暴风雪 / 血怒 / 快速射击 / 背刺）行为与门禁语义保持不变（仍受主技能节点门禁）。

各 kind 的执行口径：
- `LEAP_SLAM`：`windup` 原地蓄力（面向目标、`play_anim(&"cast")`、`leap_charge` 特效）→ 跃向**施法瞬间锁定的目标落点**（超出 `cast_range` 则钳到 8m；距离 < 1.2m 时原地起跳）→ 落地 `slam_impact` + `slam_shockwave` → 半径内敌方：`take_damage(damage)` + `apply_knockup(远离落点方向, …)` → `recover`。
- `METEOR`：`windup` 原地吟唱（`meteor_channel` 特效循环挂在自身）→ 生成 `SkillMeteorStrike`（落点 = **吟唱开始时锁定的目标位置**，`telegraph` 秒后落地）→ `recover`。**离开圈的敌人不受伤**（躲避成立）。
- `PIERCING_SHOT`：瞬发。生成 `SkillPiercingShot`（起点 = 施法者胸口高度，方向 = 指向目标水平方向）→ 沿途每个敌人只吃一次 `damage` → 飞满 `pierce_length` 或超时销毁。
- `STEALTH`：瞬发，条件 = 未隐身 且（血量比例 < `escape_hp_ratio` **或** 目标距离 ∈ (2.5, `approach_range`]）→ `pawn.apply_stealth(stealth_duration)`。

### 3.3 新状态

- `SkillCastState`（skills-dev，节点名 `skill_cast`，由 Pawn 注册）：`enter(msg)` 读 `msg.skill` / `msg.target`；`physics_update` → `pawn.skill_comp.tick_cast(delta)`；控制结束由组件调 `pawn.end_skill_cast()`。`exit()` 时若仍在施法 → `abort_cast()`。
- `StunnedState`（pawn-dev，节点名 `stunned`）：`enter` → `velocity = ZERO` + `play_anim(&"hit")`；`physics_update` → `pawn.tick_control(delta)`；返回 false → `transition_to("idle")`。

### 3.4 `PawnModelRig`（pawn-dev）

```gdscript
func set_stealth(on: bool) -> void    # 复制 per-surface override 材质应用隐身 shader（跳过 Outline_*）；
                                      # 结束恢复原 override（进入前的状态）
func stealth_active() -> bool
```
实现走 `res://assets/shaders/stealth_cloak.gdshader`（vfx-dev 提供）：
- uniforms：`albedo_color: vec4`、`albedo_texture: sampler2D`、`use_texture: bool`、`cloak: float`（0→1 渐变强度）、`rim_color: vec3`、`alpha_scale: float`。
- 期望表现：alpha 降到可辨认的「半透明幽灵」；边缘 fresnel 微光；轻微扰动。
- **`alpha_scale` 语义（实测提醒）**：它是叠在 shader 内置 `ghost_alpha(0.24)` **之上**的系数（`base.a * mix(1.0, ghost_alpha, cloak) * alpha_scale`）。调用侧走 shader 路径请固定传 `alpha_scale = 1.0`（用作者调好的幽灵透明度）；契约里 `0.18` 那个值只属于 **StandardMaterial3D 兜底路径**的 `albedo_color.a`，误填会得到 0.24×0.18 ≈ 4% 的「全透明」观感。
- **shader 缺失时的兜底**（务必实现）：用 StandardMaterial3D（`TRANSPARENCY_ALPHA`、`albedo_color.a = 0.18`、`shading_mode` 保持）顶替，`stealth_active()` 仍返回 true——headless 测试不依赖 shader 加载成功。

## 4. 特效契约（vfx-dev）

全部按 id 注册进 `VFXManager._register_defaults()`，调用侧一律 `VFXManager.spawn_effect(&"<id>", pos, rot_y, opts)`：

| id | 用途 | 建议形态 | priority |
| --- | --- | --- | --- |
| `leap_charge` | 跳劈蓄力（前摇） | 脚下尘土上扬 + 红色微光（BURST + GLOW） | 1 |
| `leap_trail` | 跳劈滞空拖尾 | TRAIL（挂在施法者身上） | 1 |
| `slam_impact` | 落地砸击 | 尘土 / 碎石爆散（BURST，`smoke`+`spark`） | 1 |
| `slam_shockwave` | 圆形冲击波 | RING（`scale_to` 放大到 AOE 直径、`no_depth_test`） | 1 |
| `meteor_channel` | 陨石吟唱 | AURA（自身法阵 + 上升火星） | 1 |
| `meteor_telegraph` | 落点预警圈 | RING（可按 opts `scale` 撑到半径，脉动） | 1 |
| `meteor_fall` | 陨石下落体 | 火球（`flame_toon`/`fire` 贴图 + 拖尾） | 1 |
| `meteor_impact` | 陨石爆炸 | 分层爆散 + 冲击环 + 余烬；可复用 `spawn_toon_fireball_explosion` 思路 | 1 |
| `pierce_muzzle` | 贯穿射击枪口 | FLASH（大号十字星，可复用 `muzzle_flash` 参数放大） | 1 |
| `pierce_trail` | 贯穿弹体尾迹 | TRAIL（青白 / 金色长尾） | 1 |
| `pierce_hit` | 贯穿命中单点 | 小爆散 + 冲击环 | 0 |
| `stealth_enter` | 隐身启动 | RING + 淡出粒子（紫 / 青） | 1 |
| `stealth_shimmer` | 隐身期微光 | **TRAIL 型**（`VFXManager.attach_trail(pawn, &"stealth_shimmer")` 用；稀疏冷色微粒） | 1 |
| `stealth_break` | 破隐 | BURST（冷色碎光散开） | 1 |

两个补充语义（vfx-dev 实现确认，2026-10-02）：
- **`meteor_telegraph` 的 opts**：`{"radius": R}` = 目标半径（米，推荐——按 AOE 实际半径撑圈）；`{"scale": k}` = 尺寸倍率（乘在 def 缩放曲线上）。不传 opts 时 def 已按陨石 AOE 校准（面片直径 8.4m = 半径 4.2m），**默认即正确大小**。
- **复合特效**：一个 id 可含多层表现（主层 = `_defs[id]` 的普通 EffectDef，附加层在 VFXManager 的 `_composites` 里声明）；`spawn_effect(id, ...)` 返回复合根节点（Node3D，位于 pos，随最慢一层释放），调用接口零变化。`_defs.has(id)` / kind / priority 断言依然成立（测试口径不变）。`meteor_fall` 的根节点**可移动**（火球 + 拖尾随根走）——陨石下落由 skills-dev tween 这个返回节点。


调用点（冻结，skills-dev / pawn-dev 按此写）：- 跳劈：`leap_charge`（自身）→ `attach_trail(pawn, &"leap_trail")` 或按需 spawn → `slam_impact` + `slam_shockwave`（落点）。
- 陨石：`meteor_channel`（自身）→ `SkillMeteorStrike` 内 `meteor_telegraph`（落点）→ `meteor_fall`（落点上空）→ `meteor_impact`（落点）。
- 贯穿：`pierce_muzzle`（起点）→ `attach_trail(shot, &"pierce_trail")` → 命中时 `pierce_hit`（每个受害者）。
- 隐身：Pawn 里 `stealth_enter`（起手）/ `stealth_shimmer`（持续，TRAIL）/ `stealth_break`（结束或破隐）。

`MAX_ACTIVE_EFFECTS = 30`：命中类用 priority 0，出招类 priority 1，别把技能表现丢成「技能没打出去」。

## 5. 测试与验收（test-dev）

新增 `tests/AdvancedSkillTest.tscn/.gd`（无头、`--fixed-fps 60`、任何路径都必须 `quit`，退出码 = 失败数），并加入 `tools/run_all_tests.sh` CORE 清单。必测项：

1. **数据契约**：4 个新技能 def 存在且 id/kind/CD/关键参数正确；4 个进阶职业 `all_skills()` 长度 2 且含新技能；四个进阶树 id 正确、每棵树有 `advanced_skill` 节点解锁对应技能 id；基础四职业仍用 `generic` 树。
2. **门禁**：进阶小兵未点 `class_skill` / `advanced_skill` 时 `is_skill_unlocked(&"leap_slam")` 等为 false，`try_cast` 不会施放；点亮后为 true。
3. **转职返还**：Lv.5 小兵花掉 N 点后 `promote_to()` → `skill_points` 恢复全额、全部节点 rank 归零、树换成进阶树、`skill_tree_changed` 已广播。
4. **跳劈**：接战后经过前摇落地；落点半径内 ≥2 个木桩同时掉血；半径外木桩无伤；受害木桩 `is_controlled()` 为真且位置被抬离地面 / 被击退（水平位移 ≥ 1m）；控制时长与 `stun_duration` 匹配。
5. **陨石**：吟唱期不产生伤害；预警圈节点存在（分组 `skill_meteor_strike`）；落地瞬间圈内木桩掉高额伤害、**吟唱期间走出圈的木桩无伤**（躲避成立）。
6. **贯穿**：一条直线上的 3 个木桩全部掉血（每个只吃一次）、线外木桩无伤、命中距离 > 20m。
7. **隐身**：施放后 `is_stealthed()` 为真、`can_be_seen_by_enemies()` 为假、`model_rig.stealth_active()` 为真；敌方 `find_nearest_hostile()` 扫不到它；持续到期自动解除；**造成伤害立即破隐**。
8. **特效**：14 个特效 id 全部在 `VFXManager` 注册表里（`spawned_by_id` 统计计数 > 0 或能 spawn 出节点）。
9. 跑批：`bash tools/godot_locked.sh --headless --path . tests/AdvancedSkillTest.tscn --log-file ... --fixed-fps 60` 全 PASS。

验收门槛：`bash tools/run_all_tests.sh` CORE 25+1 套全绿（含既有 SettlerSkillTest / CitizenManageTest / PawnStatsTest 不回归），并由 Lead 跑一次最终全量。
