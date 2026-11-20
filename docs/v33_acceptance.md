# v33 进阶职业技能 · 验收记录（test-dev 独立复跑）

- 版本：v33（狂战士跳劈 / 元素法师陨石术 / 狙击手贯穿射击 / 暗杀者隐身）
- 验收人：test-dev（周博峥）；日期：2026-10-02
- 契约依据：`docs/v33_skill_design.md` 第 5 节「测试与验收」（冻结契约）
- 判定口径（与 `tools/run_all_tests.sh` 一致）：**退出码 0 且日志 0 行匹配 `FAIL|SCRIPT ERROR|SHADER ERROR|Parse Error`**

## 0. 环境与纪律

- Godot 4.7.1 stable（`godot --headless`），`--fixed-fps 60`。
- **同一时刻只允许一个 godot 进程**：本记录中所有调用一律经 `bash tools/godot_locked.sh <godot 参数...>`，并加 `--quit-after` 兜底（防半成品脚本永不 `quit` 挂死整批）。
- 复跑命令模板：

```sh
bash tools/godot_locked.sh --headless --path . tests/<Scene>.tscn \
    --log-file /private/tmp/a-<name>.log --fixed-fps 60 --quit-after 20000
```

## 1. 交付物

| 文件 | 变更 | 说明 |
| --- | --- | --- |
| `tests/AdvancedSkillTest.tscn` / `.gd` | 新增 | v33 专项回归：数据契约 / 门禁 / 转职返还 / 四技能行为 / 特效，共 8 节 |
| `tools/run_all_tests.sh` | 修改 | CORE 清单第 26 条：`tests/AdvancedSkillTest.tscn|v33 advanced class skills (leap/meteor/pierce/stealth)`（`bash -n` 通过） |
| `tests/CitizenManageTest.gd` | 修改 | 同步 v33 语义：进阶职业专属树分流断言、转职「清空 + 全额返还」、两条 `String formatting error` |

测试脚本自防护：`_process` 看门狗（300 游戏秒强制 `quit(1)`）、分节完成标记（任一节中途脚本报错会漏标记 → `all N sections completed` 直接 FAIL、不会假绿）、退出码 = 失败数（`min(_failures, 120)`）、日志全 ASCII。

## 2. 契约第 5 节逐项结论

主命令与结果：

```sh
bash tools/godot_locked.sh --headless --path . tests/AdvancedSkillTest.tscn \
    --log-file /private/tmp/a-adv.log --fixed-fps 60 --quit-after 20000
# -> exit 0；173 PASS / 0 FAIL；日志 0 行 bad pattern；RESULT: ALL PASS（日志第 176 行）
```

**确定性复核**：同命令连跑第二次（日志 `/private/tmp/a-adv2.log`）同样 `exit 0 / 173 PASS / 0 bad`，与首跑 `diff` PASS 行集合**逐行一致**；且实现文件最后修改时间（最新 `PawnSkillComponent.gd` 15:38:04）早于两次复跑，即为**冻结版**结论。

| # | 契约项 | 结论 | 关键 PASS 行（`/private/tmp/a-adv.log`） |
| --- | --- | --- | --- |
| 1 | 数据契约（74 项） | ✅ | `1: leap_slam cd 14 / range 8 / dmg 34`、`1: meteor windup 1.0 / recover 0.35 / telegraph 1.1`、`1: piercing_shot length 26 / radius 1.0 / speed 26`、`1: stealth duration 5 / escape 0.35 / approach 7`、`1: settler_*_tree advanced_skill unlocks <新技能> behind class_skill`、`1: base class settler_* unchanged (1 skill, generic tree)`、`1: reset_and_refund returns 2 and clears every rank`、`1: pre-unlocked root costs no points` |
| 2 | 技能门禁（34 项） | ✅ | `2[0..3]: gated cast entry refuses to fire while locked`、`2[x]: main skill <x> unlocked` / `new skill <x> still locked` / `new skill <x> unlocked`、`2: base warrior class skill locked (legacy gate semantics)` |
| 3 | 转职返还（13 项） | ✅ | `3: promote refunds every invested point (2 + 2 = 4, got 4)`、`3: level preserved + all ranks cleared on promote`、`3: skill tree swapped to the advanced tree`、`3: skill_tree_changed broadcast on promote (1)`、`3: promote refunds every invested point` 后可重新加点点亮 `leap_slam` |
| 4 | 跳劈（13 项） | ✅ | `4: first damage lands only after the windup (hit at frame 50, windup = 33 frames)`、`4: every victim inside takes exactly 34 damage [T/A/B drop=34.0 lift=2.60 disp=3.30 ctrl=1.65s]`、`4: the whole circle is hit in the same physics frame`、`4: dummy outside the radius takes no damage (1 outside)` |
| 5 | 陨石（10 项） | ✅ | `5: channeling deals no damage before the impact`、`5: landing point is locked where the target stood at channel start (0.00m off)`、`5: dummy inside the circle takes the 55-damage meteor hit`、`5: dummy that walked out of the circle takes no meteor damage`、`5: meteor lands and the strike entity frees itself` |
| 6 | 贯穿（7 项） | ✅ | `6: all 3 dummies on the line take exactly one 26-damage pierce hit (1/1/1)`、`6: farthest dummy on the line stands beyond 20m (22.5m)`、`6: off-line dummy takes no pierce damage` |
| 7 | 隐身（15 项） | ✅ | `7: control - the enemy spots the slayer before stealth`（对照组）→ `7: enemy scan no longer finds the stealthed slayer`、`7: model rig reports the stealth look`、`7: taking damage does NOT break stealth`、`7: dealing damage breaks stealth immediately`、`7: stealth expires automatically` |
| 8 | 特效 14 id（5 项） | ✅ | `8: all 14 v33 effect ids are registered in VFXManager._defs (missing=[])`、`8: 11 spawn-type effect ids build a node (failed=[])`、`8: 3 TRAIL-type effect ids attach a GPUParticles3D (failed=[])`、`8: stat_spawned_by_id counted every spawn-type effect (zero=[])` |
| 9 | 跑批回归（5 套） | ✅ | 见下表 |

### 2.1 第 9 项：回归套件独立复跑

| 套件 | 退出码 | bad 行 | PASS | 结论行 |
| --- | --- | --- | --- | --- |
| `tests/AdvancedSkillTest.tscn` | 0 | 0 | 173 | `RESULT: ALL PASS` |
| `tests/SettlerSkillTest.tscn` | 0 | 0 | 44 | `RESULT: ALL PASS` |
| `tests/CitizenManageTest.tscn` | 0 | 0 | 122 | `CITIZEN MANAGE TEST: 0 failure(s)` |
| `tests/PawnStatsTest.tscn` | 0 | 0 | 59 | `RESULT: ALL PASS` |
| `tests/MonsterBehaviorStabilityTest.tscn` | 0 | 0 | 24 | `MONSTER BEHAVIOR STABILITY: 24 checks, 0 failures` |

日志：`/private/tmp/a-reg-<Scene>.log`（`--quit-after 30000`）。既有四职业技能（暴风雪 / 血怒 / 快速射击 / 背刺）行为零回归。

> 全量 `bash tools/run_all_tests.sh`（CORE 26 套）由 Lead 作为最终验收门槛执行；本记录只覆盖 task-6 指定的 5 套 + v33 专项。

## 3. 过程中发现与处置

### 3.1 阻塞项：类缓存缺 4 个新 `class_name`（已由 Lead 处置）

- 现象：`Pawn.gd:719` 报 `Parse Error: Identifier "StunnedState" not declared`，级联到 `Soldier/Hero/Refugee/PawnSpawner/PawnSkillComponent` 全部 `Failed to compile`，任何 headless 测试的 `spawn_*` 都报 `Nonexistent function '_ready'`。
- 证据：`.godot/global_script_class_cache.cfg`（15:24）缺 `StunnedState / SkillCastState / SkillMeteorStrike / SkillPiercingShot`，而四个文件已存在并写了 `class_name`。
- 处置：Lead 执行 `godot --headless --editor --quit --path .` 重建类缓存（15:26:52），全线恢复。**结论：新增 `class_name` 后必须先重建类缓存，这是跑批的前置条件。**

### 3.2 首跑 3 个 FAIL —— 均为测试脚手架问题（非实现缺陷），已修

| FAIL 断言 | 根因 | 修法 |
| --- | --- | --- |
| `6: sniper fires the piercing shot (explicit cast order)` | `SoldierIdleState` 不看 `is_auto_fighter`，视野内有敌即进战斗；狙击手在测试显式开火**前一帧**自动放了贯穿并占用 CD | 新增 `_freeze_ai(pawn)`（`state_machine.set_physics_process(false)`），瞬发技能段启用 |
| `6: all 3 dummies ... (0/1/1)` | 同一发「抢跑」的弹体在测试清空伤害流水**之前**已命中开火目标 → 记账 0；更远的 mid/far 在清空之后被命中 → 1/1 | 同上 |
| `7: taking damage does NOT break stealth` | 暗杀者隐身起手后，AI 立刻自动放「背刺」→ 自己造成伤害 → 反手破隐（契约「造成伤害即破隐」是对的） | 同上（隐身段冻结 AI；隐身倒计时仍在 `Pawn._physics_process`，不受影响） |

跳劈 / 陨石两段**故意保留真实 AI 链路**（不冻结）：受害者分类按「落地帧实测 AOE 圆心」判定，天然抗 AI 抢放；实测落地帧 = 施法后第 50 帧（前摇 33 帧 + 滞空），符合契约。

### 3.3 `tests/CitizenManageTest.gd` 同步（Lead 裁决的 v33 语义变更）

- `advanced %s keeps skill tree + leveling`：改为按 `adv.extra_skills.is_empty()` 分流 —— 四个 v33 进阶职业各自专属树，骑士 / 雷电法师 / 漫游射手 / 忍者仍 `generic`。
- `level / skill tree / ranks preserved on promote` → `level preserved + all ranks cleared on promote` + `promote refunds every invested point (2 + 2 = 4, got 4)`（转职 = 清空 + 全额返还）。
- `damage rank 1 gives +5% attack` / `vitality rank 1 gives +6% max hp`：两条 `String formatting error` 的根因是**同一字符串里字面 `%` 未转义**（不是缺参），改 `%%` 并把 `→` 换成 ASCII `->`。

## 4. 残余风险与未覆盖面（交 Lead 决策）

1. **全量跑批**（CORE 26 套，含 `DragonPetTest` / `NightAssaultTest` / `SceneValidation` 等）未由本记录覆盖 —— 按契约由 Lead 跑最终全量。
2. `tests/DragonPetTest.gd` 及 `Dragon*` 文件由**另一个并行会话（v32）**改写，不在 v33 写范围；若最终跑批中它变红，应按「文件 mtime + FAIL 摘要」与 v33 变更区分（Lead 已记录此口径）。
3. 退出时 `WARNING: 30 ObjectDB instances were leaked at exit` / `ERROR: 9 resources still in use at exit`（stderr，不落 `--log-file`）：批处理判定口径（退出码 + 日志 4 类关键字）不受影响；本仓库无 git 基线，无法判定是否 v33 引入 — **记录在案，未阻断验收**。
4. 特效「形态与手感」只做了注册 / 可生成 / 统计计数的客观断言，观感验收依赖 vfx-dev 的 `artifacts/v33-*.png` 与有界面运行，不在无头范围内。
5. 跳劈击飞、陨石躲避的断言基于 `--fixed-fps 60`；有界面可变帧率下的手感需人工确认。

## 5. 复现命令清单

```sh
# v33 专项（8 节 / 173 断言）
bash tools/godot_locked.sh --headless --path . tests/AdvancedSkillTest.tscn \
    --log-file /private/tmp/a-adv.log --fixed-fps 60 --quit-after 20000

# 第 9 项 5 套回归
for s in AdvancedSkillTest SettlerSkillTest CitizenManageTest PawnStatsTest MonsterBehaviorStabilityTest; do
  bash tools/godot_locked.sh --headless --path . "tests/$s.tscn" \
      --log-file "/private/tmp/a-reg-$s.log" --fixed-fps 60 --quit-after 30000
done

# 最终全量（Lead）
bash tools/run_all_tests.sh
```
