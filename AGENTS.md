# demo-1：AI 协作指南（AGENTS.md · 唯一维护文档）

> **文档策略（2026-10-18 起）**：**本文件是唯一维护的工程文档**——架构讲解 / 版本速览 / 工程契约 / 单位与模型约定 / 导航 / 检查清单 / 高频坑 / AI 工具链全部在这里。`CLAUDE.md` 已停止维护，只留一个指向本文件的指针。workspace instruction 预算 64KB：版本日志只在下方「版本速览」加**一行**，超过 ~10 条时把最旧的移入 `docs/CHANGELOG.md`（v3~v30 完整历史已归档于此，含动机 / 数值推导 / 踩坑过程 / 回归清单）。**不要在别处再维护第二份文档。**

## 项目概要（v47 当前形态）

Godot 4.7 / GDScript，3D，Forward+ 渲染器，Jolt 物理。**俯视角主控 + 模拟经营 + 战斗**沙盒：v42 起默认（且玩家唯一可用）的镜头是等距俯视角跟随主角——WASD 按屏幕方向移动、鼠标指向即瞄准 / 左键三段连招 / Q/C 技能 / E 交互 / 亲自建造；第三人称亲征与战术俯瞰 RTS 的实现与脚本接口保留、玩家入口屏蔽（恢复见 `SelectionManager.VIEW_MODE_*_ENABLED`）。在主城（`BaseCore`，HP 归 0 即游戏结束）周围经营。**没有波次 / 阶段切换**——开放沙盒仅推进昼夜时钟。

- **视角模式（v15 三态 → v42 玩家只保留 TOPDOWN）**：HERO 越肩亲征（玩家入口屏蔽）→ TACTICAL 战术俯瞰 RTS（等距相机框选 / 右键下令 / 点击建造菜单；玩家入口屏蔽）→ **TOPDOWN 俯视角主控（默认且唯一）**：等距相机跟随、WASD 按屏幕方向基底、朝向 = 鼠标落点、滚轮阻尼平滑推拉（`zoom_smoothing`，`snap_distance()` 供截图/定场）。
- **金币经济（v22）**：采集屏蔽（`GameDefs.HARVEST_INCOME_ENABLED=false`，树/石 = 场景障碍），初始 150 金；怪物必掉金币（普通 10 / 精英 45 / 头目 200），v23 爆散抛物线 + 落地弹跳 + 1.5s 停驻硬保护 + 磁吸拾取（主角优先、村民不抢）。
- **建筑 5 种（纯金币）**：木墙 10 / 房屋 30 / 酒馆 50（`is_tavern`：8m 光环给小兵 20/s 回血，城外血量 <20% 自动回馆、≥95% 出院）/ 龙园 120（`is_dragon_garden`，v43 起 footprint 4×4 全场最大）。**v43 建筑比例**：王城 52×52m（`CITY_HALF=26`）、房屋 3×3（6×6m，模型约 5.8m 高）、酒馆 3×3、龙园 4×4；土路 1 金/格（四邻 16 态自动拼接、长按左键连续铺设）。数字键 1~5 任意时刻直建（≤20m），B 开建造菜单。**v37 数量上限**：`BuildingDef.max_count`（0 = 不限量）——酒馆与龙园**全场各只能建 1 座**；判定 = 场上存活实例数（`GameDefs.building_at_limit`，分组实时统计），拆除即释放、可原地重建；`BuildSystem.build_limit_reached()` 是唯一拦截点（预览变红 / 放置拒绝且不扣费 / BuildMenu 卡片置灰显「满」）。新建受限建筑只需填 `max_count`。
- **人口循环**：房屋吸引流民 → 入住弹四职业卡（`SettleClassPicker`，真暂停；无 HUD 回落随机）→ 定居小兵（战士 / 法师 / 刺客 / 游侠，v19 各带职业技能与 CD）。小兵六维属性 + 等级成长（v20：封顶 Lv.10）、Lv.5 转职二选一（v25 `promotes_to`）、技能树（v25.x：根节点 = 职业技，点亮才能施放 → 伤害 5 级 → 生命 5 级）。**v33**：四个进阶职业各带一个专属主动技能（狂战士跳劈 / 元素法师陨石术 / 狙击手贯穿射击 / 暗杀者隐身），经**进阶职业专属技能树**的 `advanced_skill` 节点解锁（`SkillNodeDef.unlocks_skill_id` 精确门禁）；**转职一律清空已加点数并全额返还**（= 一次免费洗点）。
- **小队（v10/v18/v26）**：4 队员编制 + **编外巨龙**。G 集结（2× 追赶、到位停住）、T 集火（主人命令最高优先、立即转火、杀完归队）、V 市民管理（`CitizenPanel`，变量名/节点名仍 `party_panel`）；巨龙经龙园 E 交互花金币解锁（`DragonMenu`），始终跟随主角、主角打谁龙打谁、普攻溅射火球 + 40°×14m 烈焰吐息、阵亡 25s 复苏。**v34 经验共享**：小队里任何人击杀（主角 / 队友 / 巨龙），击杀者拿全额、其余在队成员各分 50%（`GameDefs.SQUAD_XP_SHARE_RATIO`；`Soldier` 按 `follow_leader` 同队判定）。
- **夜晚（v20 夜潮 + v31 守城准备 + v43 城内待命 + v44 按威胁方向布防）**：傍晚 18:00~20:00 停刷；入夜先冻结昼夜时钟（`TimeManager.clock_frozen`，游戏照常运行）进入守城准备期——清完场上残敌后小兵自动回城，玩家配置小队 / 布防，按 HUD「准备守城」按钮（回车同义）后时间恢复，四条路尽头随机一门刷大批量夜潮（批量随夜数涨、15% 精英带头）直取主城；推进途中被小兵打立即转火、杀完恢复攻城；天亮撤军。**v43 夜间待命**：非编队 / 非驻守小兵入夜不再满城 `wander`——受伤（<95%）且场上有酒馆先回馆疗伤到 95%，其余在城内稳定待命点站定（家 / 酒馆 / 路边 / 城心，按 `instance_id` 分布，每夜只选一次）；已站定的健康小兵可 2~3 人一组 `night_chat` 围站轮流冒泡（夜间台词含「第 N 夜」），结束后回各自待命点并冷却 25~45s；`follow` / 集火 / 驻守 / 警报 / 战斗优先级不变，天亮恢复白天巡逻与城内生活。**v44 按威胁方向布防**：WildlifeSpawner 选门后广播 `EventBus.night_threat_direction_changed(active, gate_index, gate_inside)`；所有非编队 / 非驻守小兵到对应「城门内侧」列阵——近战行在前（靠城门）、远程行在后，每行≤8、行距 2.4m、横向 2m，站定朝城外；部署期群聊原地不离位，威胁清除 / 天亮回原待命点。
- **主角**：击杀经验升级（不封顶）、技能树（升级 +1 点）、死亡按 `respawn_at_base` 复活。**v34 回城疗伤**：主角与巨龙白天回到城镇范围缓慢回血（主角 2/s、龙 4/s，`Pawn._try_town_regen`），晚上守城期间（20:00~06:00，`TimeManager.is_night()` 统一口径）不回；士兵的城内休整回血不受此门控。
- **表现层**：`VFXManager` 四条管线（SLASH / BILLBOARD / PARTICLES / TRAIL）+ Kenney CC0 + 程序化贴图（v27~v30 品质线：定向打击反馈、卡通 cel 火焰、特效灯）；v13 装饰半球消散、v16 怪物死亡动画 + 溶解、主角遮挡透视；**v43 湖泊东迁 + v45 水系二轮视觉**：湖泊 `(52,-38)` / 半径 `(17,12)`、三阶谐波自然岸线 + 湖心小岛、瀑布 `(58,-72)→(56,-64)` 多股落水（主瀑 + 两侧细流），河潭与湖统一读 `WorldLayout`；**v45 湖泊**：低粗糙 PBR 天空镜面换成「ROUGHNESS 0.55+ / SPECULAR 0 + 手写施里克菲涅尔 + 窄日光碎闪」，5 层世界空间波 + 深浅三段 + 噪声打散等深线，沙环 3.4m→2.0m + 湿暗水线，夜景压暗保青绿，调色统一收口 `WaterPalette`（湖 / 河 / 潭三套色）；**v45 瀑布**：主帘 + 前后薄水膜 + 唇口翻卷（`render_priority` 分层、顶点色四通道），sqrt 加速水丝 + 噪声羽化 + 底缘水舌，白沫重做 + 3D 沫丘 + 潭心 40~50% 覆盖，水雾改 0.55~1.35m alpha 混合（近距淡出）替换加法硬白圆饼，霜区浮冰 / 雪斑 / 冰晶改有机网格，湖心岛夜色同步。**v43 入住视觉**：已入住房屋暖色染色（蓝屋顶转暖棕 / 白墙金橙）+ 门口自发光小灯笼 + 夜间门口暖光，住户死亡 / 释放即恢复空房外观（`Building.is_occupied()` / `BuildingModelRig.set_occupancy_tint`）。 **v47 渲染**：AgX + 软阴影 + SSAO/SSIL + 夜间体积雾 + 9 火炬 + 后处理调色；`RenderQuality` 四档（设置可切）；草坪去 discard 改逐叶塌缩（7.34→3.86ms）；详见 `docs/render_v47.md`。
- **关卡系统（v38）**：数据层 `LevelDef` + `LevelCatalog`（5 关）、会话/进度 autoload `LevelRuntime`（`user://level_progress.cfg`，星级只增不减；**空选择 = 按沙盒关跑**）；主菜单「开始游戏」→ **3D 关卡选择地图** `scenes/main/LevelSelect3D.tscn`（五座程序化浮岛 + 奶油道路 + 旗子关卡点；`CharacterBody3D` 小人 WASD / 点地走位，可行走域 = 岛多边形 ∪ 道路的 0.5m 烘焙网格，走到旗旁按 E 选关；暂未开放的关卡可查看但拒绝进入）、「测试关卡」直入沙盒；`Main.gd._setup_level()` 按 `LevelRuntime.current_level()` 分流——序章挂 `PrologueDirector`（停刷怪 / 停流民 / 禁建造 / `clock_frozen` 钉白天 / 4 名匪徒 / 走到城堡 8m 内 1.5s 通关，1~3 星结算 + 进度落盘），`TutorialSystem.suppress_autostart()` 让剧情关不叠沙盒新手引导。
- **世界主题区域（v40 + v43 水系东迁）**：可玩边界 64→128m（**256×256 米 / 128×128 格**），旧地图 ±64m 内容原样保留；王城 v43 扩到 52×52m（`CITY_HALF=26`），湖 / 瀑 / 潭 / 河整体东迁到城东（`(52,-38)` / `(58,-72)` / `(56,-64)`，湖西岸 35m > 城东 26m，留 9m 净空）。六个主题区域（北境霜语瀑布 / 东北星落矿坑 / 东境风吟麦海 / 南境烬誓战场 / 西境雾隐密林 / 西南盐风沼地）由 `scripts/defs/WorldRegions.gd` 统一定义（名称/故事/圆心半径/地面色/地标点），`ThemedRegions.gd` 建地标道具与城外路标，`DecorationScatter` 做分区植被，ground shader 用 `region_*` 染色，小地图画区域层；`RegionTracker` 首次踏入弹 HUD 区域横幅 + 故事日志（序章静音）。夜潮（含头目）在 `night_wave_origin`（62m）集结，避免大图上「走到天亮」；详见 `docs/world_regions.md`。 **v40.1 场景表现专项**：道具统一 `_ground_fit` 贴地并按 AABB 推离互穿/压路（`ScenePolishTest` 把关）；雪/盐/焦土斑与余烬/芦苇减量换形；五区专属草色层 + 128~158m 外围林带；小径终点后撤 8.5m 停在区域石碑前；瀑布崖体改用同材质岩脊（去 KayKit 山体黄色顶面）、远山冷色乘算 + 远环山影、地面网格 1024→560 + 地平雾毯 + 地标夯土地皮。 **v40.2 氛围与动态**：`RegionAmbience.gd` 六区+王城粒子氛围（雪/紫尘/金尘/余烬/萤火/雾/烟，昼夜门控，7 发射器 724 粒子）；湖东岸栈桥 `Lake_Pier` + 小船 `Lake_Boat`；风车扇叶自转；`foliage.gdshader` 树干去红；battle/swamp 程序化枯树与外围环带多模型；分时段截图工具 `tools/ambience_shot`。
- **运行入口** `scenes/main/MainMenu.tscn`（开始游戏 → 关卡地图 / 测试关卡 / 设置 / 退出，MenuFlow 流式布局）→ `scenes/main/LevelSelect3D.tscn`（3D 世界地图选关）→ `Main.tscn`。HUD 场景是桩，UI 由 `HUD.gd` 代码构建（`UIStyle` 暗金主题 + `IconChar` 字徽 + `Crosshair` 准星；`HeroPanel` 合并卡 / `CitizenPanel` / `SkillTreePanel` / `SettleClassPicker` / `DragonMenu`）。
- **Esc 全局优先级链（勿破坏）**：游戏结束不响应 → 建造模式让位 BuildSystem → 引导让位 TutorialSystem → **技能树 > 市民管理 > PauseMenu**（各自 `_unhandled_input` 消费 + PauseMenu 防御性放行 + Main 的 V 键对技能树让位）。
- **调速** `-` / `=`（1×→2×→3× 循环钳制）；暂停 P。

## 版本速览（最近 10 条；更早版本与完整细节见 docs/CHANGELOG.md）

| 版本 | 主题 | 一句话 |
| --- | --- | --- |
| v40.2 | 氛围与动态表现 | 新增 `RegionAmbience.gd`：霜区飘雪 / 矿坑紫尘 / 麦海金尘 / 战场余烬 / 密林夜间萤火 / 沼地雾气 / 王城烟囱（7 发射器 724 粒子，昼夜门控）；湖上栈桥 `Lake_Pier` + 小船 `Lake_Boat`（湖东岸，纯视觉）；风车扇叶绕本地 Z 轴 0.45 rad/s 旋转；水井缩小调向；植被质感：`foliage.gdshader` 树干去红（`trunk_deep/light`）、battle/swamp 改程序化枯树（56 tri × 58 棵）、外围环带 3 变体（260 树 + 120 岩）；新增 `tools/ambience_shot` 分时段截图（12:00/18:30/21:00，25 张） |
| v41 | 玩家土路与小兵城内生活 | 土路（1 金/格、数字 5、长按拖动补格、16 态自动拼接）；城内取消预制道路与石板广场；流民 / 友方小兵按通行时间优选道路、路上 +20% 移速，独立加权 A* 与不削路口的平滑；小兵短时巡逻与城内生活交替，近邻停步相向聊天并轮流冒泡，命令 / 警报 / 受伤即时打断；新增 `tests/RoadTownLifeTest.tscn` 与 `tools/road_town_preview.tscn` |
| v42 | 镜头收敛 + 平滑推拉 | 玩家只保留俯视角主控：`SelectionManager.VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED = false`——开局即 TOPDOWN，Tab 不再换镜头（仅回一条提示），HERO / TACTICAL 实现与脚本接口保留（旧测试 / 截图工具取景），改回 true 即恢复三态；等距相机滚轮改**阻尼平滑推拉**（`zoom_smoothing` + `_distance` 逐帧收敛，`snap_distance()` 供截图 / 定场立即对齐，`factor` 支持触控板）；新手引导「战术俯瞰」等待步改信息步、`move` 步改讲鼠标瞄准，序章 / 主菜单 / HeroPanel / 设置文案同步 |
| v43 | 入住房屋颜色 + 夜晚待命 + 城池/水系迭代 | 已入住房屋暖色染色（蓝屋顶转暖棕 / 白墙金橙）+ 门口自发光灯笼 + 夜间暖光，住户死亡/释放即恢复空房（`Building.is_occupied()` / `BuildingModelRig.set_occupancy_tint`）；夜晚非编队小兵不再满城游荡：受伤先去酒馆回血到 95%，其余在城内稳定待命点站定，健康者 2~3 人一组 `night_chat` 闲聊（夜间台词/第 N 夜），天亮恢复；王城 40×40→52×52m（`CITY_HALF=26`）、房屋 3×3 / 酒馆 3×3 / 龙园 4×4、城门火把/刷怪环/相机同步；湖瀑潭河东迁（`(52,-38)` / `(58,-72)` / `(56,-64)`）并全面迭代水景（自然岸线/湖心岛/深浅色带/菲涅尔/多股落水/水雾），码头小船随迁 |
| v44 | 夜防阵型 + 进攻怪死战 | `EventBus.night_threat_direction_changed` + `WorldLayout.gate_inside_point/gate_outward_dir`：WildlifeSpawner 选门后，所有非编队 / 非驻守小兵到城门内侧列阵，近战前排 / 远程后排（每行≤8、行距 2.4m、横向 2m、朝城外），部署期群聊原地不离位；`Raider.should_flee_now` 对 `assaulting` 也强制死战（与 `_sieging` 同口径），夜潮低血不再逃跑跑远 |
| v45 | 瀑布 / 湖泊二轮视觉迭代 | 湖面：低粗糙 PBR 天空镜面 → ROUGHNESS 0.55+ / SPECULAR 0 + 手写菲涅尔 + 窄日光碎闪；5 层波纹 + 深浅三段 + 噪声等深线；沙环 3.4→2.0m + 湿暗水线；夜景压暗保青绿；调色收口 `WaterPalette`。瀑布：主帘 + 前后薄水膜 + 唇口翻卷（`render_priority` 分层 / 顶点色四通道 / sqrt 加速水丝 / 噪声羽化 / 底缘水舌）+ 白沫重做 + 3D 沫丘 + 水雾 0.55~1.35m alpha 混合；瀑顶不规则山溪；霜区浮冰 / 雪斑 / 冰晶改有机网格；湖心岛夜色修复 |
| v46 | 密实短草坪 | 主草层改为 12 片分根弯叶（每叶 3 三角）、分层抖动采样，城内恢复短草覆盖；草地/草叶同色、根尖柔和层次与世界空间风，不透明材质 + 16m 分块 + 远距减叶/宽度补偿；建筑/土路事件更新遮罩，拆除恢复；白花减量；`tests/LawnTest`（覆盖密度须 GPU）与 `tools/grass_shot` 同机位对照 |
| v46.1 | 按参考图补足草叶体积与树荫 | 草叶改宽腹圆冠（12 叶 × 5 三角，0.36~0.56m，城内 ×0.86）、深绿根→黄绿冠；主角脚边 0.95m 压弯代替大圈消散，草不秃圈；静态岩石按实际 AABB 登记椭圆净空；树冠 `depth_prepass_alpha` 恢复草坪接树荫；建拆遮罩与区域高草保持原逻辑 |
| v46.2 | 主角拨草与回弹 | `LawnInteraction` 以 64² 滚动场记录世界格弯曲，主角周围 1.4m 按行进方向向两侧拨草、离开后 0.8s 平滑恢复；叶根由 UV2 固定，16KB 贴图单次采样，不逐株更新；暂停/跳跃/死亡/传送均有生命周期处理；新增 `LawnInteractionTest` 与 12s 实机演示工具 |
| v47 | 渲染与光影迭代 + 画质分级 | AgX + 软阴影 + SSAO/SSIL + 夜间体积雾 + 9 火炬 + PostFx 调色；`RenderQuality` 四档（设置可切）；草坪去 discard 改逐叶塌缩（草坪 7.34→3.86ms，整帧 17.15→13.83ms）；4→2 split 阴影；字体 fallback 修复消除逐帧错误；详见 `docs/render_v47.md` |

## 运行与验证

`godot` CLI 已在 shell `PATH` 上（symlink 到 `/Applications/Godot.app`，4.7.1）；也可直接用 Godot 4.7 编辑器。从项目根目录：

```bash
godot --editor                    # 在编辑器中打开
godot --path .                    # 运行主场景（MainMenu.tscn 开始界面 → 开始游戏进 Main.tscn）
godot --headless --path . --quit  # 冒烟：无头加载项目后退出
godot --headless --path . --log-file /tmp/demo-1.log --quit-after 10
```

**一键跑批**：`bash tools/run_all_tests.sh` —— **CORE 42 套**（清单以脚本 `CORE` 数组为准：怪物行为稳定性 / 导航稳定性 / 集结跟随 / 小队指令 / 定居四职业技能 / 进阶职业技能（v33）/ 六维属性 / 小队经验共享 + 回城疗伤（v34）/ 酒馆疗伤 / **入住房屋视觉（v43）** / 建筑数量上限（v37）/ 关卡系统全链路（v38）/ 世界扩张（v40）/ **城池比例与湖迁（v43）** / 场景穿模（v40.1、v41 道路与小兵城内生活）/ 市民管理 / 驯龙 / 相机 / 水系 / 湖泊卡位（v36）/ 遮挡透视 / 消散 / 战斗特效 / 动画同步 / 气泡 / 死亡溶解 / 金币爆散 / 血条 / 第三人称三态 / 夜潮攻城 / **进攻怪不撤退（v44）** / **夜晚待命（v43）** / **夜防阵型（v44）** / **画质分级（v47）** / SceneValidation 等）；`--full` 追加 6 套（天气 / 小地图 / 头目夜 / 像素统计 / UI 图标 / 浸泡）。日志落 `${TMPDIR}/demo1-tests/<场景>.log`，判定「退出码 0 且日志无 `FAIL` / `SCRIPT ERROR` / `SHADER ERROR` / `Parse Error`」；**单场景默认 600s 超时（`SCENE_TIMEOUT` 可覆盖）**——测试脚本一旦 Parse Error，场景就没有脚本、永不 `quit`，没有护栏会让一个 godot 进程 100% CPU 挂死整批。**同一时刻只允许一个 godot 进程**（`.godot` 缓存会打架）——AI 协作 / 多会话并行时一律走 `bash tools/godot_locked.sh <godot 参数...>`（mkdir 锁 + 陈旧锁回收，见 v33 CHANGELOG），并给测试加 `--quit-after 20000` 兜底（半成品脚本会让场景永不 quit，连锁带整队一起挂死）。

场景回归主干 `tests/SceneValidation.tscn`（`--fixed-fps 60` 跑；覆盖定居 / 昼夜 / 天气 / 主角经验 / 武器挂点 / 引导全流程 / Esc 链 / 建筑已删等数据与 UI 契约）。改动运行时逻辑后至少执行一次无头加载；涉及交互、镜头或美术时还应在编辑器内实际运行验证。Lead 独立探针 `godot --path . tools/gather_probe.tscn`（跟随测速等客观量测）；定义层探针 `tools/v33_defs_probe.tscn`（25 项）、`tools/v38_defs_probe.tscn`（关卡目录 + 进度落盘 + 菜单接线 44 项）；v43 交付截图 `tools/v43_showcase_shot.tscn`（窗口模式出 4~5 张新城 / 入住房屋 / 夜间待命 / 水系总览；无头只做结构自检），水系样张 `tools/water_shot.tscn`（`-- --label=v45`，9 张；新增 lake-shallow / plunge 近景机位；基线用 `--label=v45-base`），v44 夜防阵型样张 `tools/v44_defense_shot.tscn`（东门内侧近战前排 / 远程后排；无头只做阵型自检）。 v47 渲染：`tools/render_showcase.tscn`（样张 + 帧时）、`tools/render_probe.tscn`（消融）。

**没有测试套件框架、没有 lint 配置、也没有 CI**（回归 = 上述场景跑批）。`.uid` 文件是 Godot 自动生成的稳定资源 ID——绝不手改；`.godot/` 是生成产物且已 gitignore。

## 目录与职责

| 目录 | 职责 |
| --- | --- |
| `scripts/autoload/` | 全局单例（EventBus / GameManager / ResourceManager / TimeManager / SelectionManager / AudioManager / VFXManager / DecorationDissolve / **LevelRuntime**（v38 关卡会话 + 星级进度）/ **RenderQuality**（v47 画质分级））。跨模块通知优先走 `EventBus`。 |
| `scripts/defs/` | 玩法数据资源类型与 `GameDefs.gd` 内置配置（单位 / 职业 / 建筑 / 技能 / 技能树 / 连招 / 特效 / 龙）；**v38 增关卡目录** `LevelDef.gd` + `LevelCatalog.gd`（关卡列表 / 地图坐标 / 星级 / 玩法目标）。 |
| `scripts/entities/` | 建筑、资源点、投射物、金币掉落和 Pawn 实体（`pawn/states/` 状态机状态）。 |
| `scripts/components/` | 可复用实体组件：血量、攻击、选择、血条 / 气泡 / 增益标记、技能组件、模型表现（`PawnModelRig` 等）。 |
| `scripts/systems/` | 世界级系统：网格、建造、选择、城市、寻路、刷怪、生成、定居、驯龙、引导、装饰消散等。 |
| `scripts/ui/` | HUD 与各面板。 |
| `assets/_PLACEHOLDER/` | 占位模型和贴图（KayKit CC0 / 怪物 / 巨龙 GLB，授权见 CREDITS.md）；正式资产可替换此处或改 Def 路径。 |
| `assets/shaders/`、`assets/vfx/`、`assets/audio/` | 着色器（含水系 / 消散 / 特效库）、特效贴图、音频。 |
| `tools/`、`tests/`、`artifacts/` | 探针与样张工具、回归场景、交付预览（`artifacts/` 已 `.gdignore`）。 |

## 运行时世界树

`Main.tscn` 已静态声明如下结构（`Main.gd._ready()` 只做运行时接线：初始资源、`pawn_spawner.configure()`、`_setup_base_core()`、`_spawn_hero()`、`_setup_hud()`、`_setup_level()`（v38 关卡分流）、全局快捷键）：

```text
Main (Node, Main.gd)
└─ WorldRoot (Node3D)
   ├─ WorldEnvironment / Sun / FillLight              # 天色由 DayNightCycle 实时驱动
   ├─ GroundPlane (StaticBody3D, layer 1)             # 256×256 可玩地面 + ground shader（v40）
   ├─ GridSystem / CitySystem / BuildSystem
   ├─ BaseCore (StaticBody3D) + ModelRig / Collision / HealthComponent   # HP=0 游戏结束
   ├─ ResourceNodes (42 个)                           # 树/石；v22 起采集屏蔽=纯障碍，采空仍补长
   ├─ Buildings / Pawns / Enemies / LootDrops / Projectiles   # 实体容器（后两者入同名分组）
   ├─ Decorations / DecorationScatter / Water         # 分块 MultiMesh 散布 + 水面（v12 三区拆网格）
   ├─ WorldScenery                                   # 地标、远山、边界碰撞；挂 WaterFeature（瀑布/河/潭）、ThemedRegions（v40 六区域地标）、RegionTracker 与 HeroOcclusionSilhouette
   ├─ DayNightCycle / WeatherSystem                  # 昼夜天色/火炬/萤火虫；天气(晴/云/雨/雷)
   ├─ PawnSpawner / SelectionController / WildlifeSpawner
   ├─ CombatSystem / SettlementSystem / ResourceGrowthSystem / QuestSystem / NavSystem
   ├─ TutorialSystem / DragonSystem（v26 驯龙，分组 dragon_system）
   └─ IsometricCamera / ThirdPersonCamera / HeroController   # 战术俯瞰 / 第三人称越肩（默认 current）/ 操控中枢
```

HUD 由 `Main.gd._setup_hud()` 实例化 `scenes/ui/HUD.tscn`（桩）挂到 `Main` 下，`HUD.gd._ready()` 在代码里构建整套 UI。系统按名称查找同级节点时，节点名是契约的一部分；批量查询使用 group，例如 `player_unit`、`enemy`、`pawn_spawner`、`nav_system`、`grid_system`、`quest_system`、`tutorial_system`、`dragon_system`。


**系统互查只有两种机制**，搞清当前用的是哪一种：
- **按名取兄弟节点**（`get_parent().get_node_or_null("GridSystem")` 等）——所以运行时新建的系统节点都要显式设置 `.name =`；节点名是契约的一部分。
- **分组（Groups）**用于集合与系统单例查找：实体 `selectable` / `player_unit` / `enemy` / `building` / `house` / `base_core` / `hero_squad` / `speech_bubbles` / `projectiles`；系统单例 `nav_system` / `city_system` / `build_system` / `pawn_spawner` / `combat_system` / `settlement_system` / `hero_controller` / `dragon_system` / `tutorial_system`。系统在 `_ready()` 里 `add_to_group` 自登记，其余节点用 `get_first_node_in_group(...)` 懒加载。

`Main.gd._ready()` 只做运行时接线（初始资源、`TimeManager.begin`、`pawn_spawner.configure()`、`_setup_base_core()`、`_spawn_hero()`、`_setup_hud()`、`_setup_level()`、全局快捷键），**没有 `_build_world()`**——改世界内容请改 `Main.tscn` 静态声明的树。

## 单位体系

- `Pawn` 是所有可移动单位的基础类，负责碰撞、组件、导航、选择、基础状态和逻辑朝向；带 `stance`（士兵姿态）/ `_sieging`（攻城标记）/ `alert_pos`（威胁支援）、六维属性与等级经验（v20）、技能点与技能树（v25）。
- 子类：`Colonist`（村民，采集屏蔽后基本闲置，类保留兼容旧测试/工具）、`Raider`（野怪：普通/精英/头目三档 def，v20 夜潮攻城）、`Soldier(Melee/Ranged)`（**定居四职业的行为载体**，非兵营招募——兵营 v21 已删；`SoldierRanged` 把 fight 换 `RangedFightState`）、`Refugee`（流民，入住时经 `settle_class_choice_required` 弹窗选职业后转小兵）、`DragonPet`（v26 宠物龙：跟随 / 同步转火 / 吐息三专属状态，绝不自主索敌）、`Hero`（主角，经验升级不封顶）。
- `PawnStateMachine` 按节点名注册状态。子类在 `super._setup_nodes()` 之后添加状态时，必须使用 `register_state()`，否则状态机不会识别它。
- `PawnSpawner` 是唯一的单位创建入口：主角、流民、村民、小兵、野怪（含精英/头目）、龙都从这里创建。新增单位来源时不要直接向 `Pawns` 或 `Enemies` 添加实例，应扩展 `PawnSpawner`。

## 组件与状态机

- **组件**（`scripts/components/`）：`HealthComponent`（`defense_factor` 减伤 / `incoming_damage_mult` 易伤 / `damaged` 信号）、`AttackerComponent`（`_roll_crit` 暴击 / `launch_projectile` 公开入口 / `attack_profile` 特效档案）、`TeamComponent`、`SelectableComponent`（拾取区独占 layer 7）、`HealthBar3D`、`BuffMarks3D`、`PawnSkillComponent`、`PawnModelRig` / `BuildingModelRig`。
- **战斗是去中心化的**：`AttackerComponent.try_attack()` 直接调目标 `HealthComponent.apply_damage()`；远程分叉为追踪 `Projectile`；主角连招 / 技能同样走 `Hero.apply_damage_to()`。
- **Pawn FSM**：`PawnStateMachine` 持有 `PawnState` 子节点，**节点名即状态名**，`transition_to(name, msg)` 切换。基础 6 态 `idle/move/harvest/fight/follow/dead`；子类把 `idle` 换成决策路由态并新增专属状态（如 `SoldierIdleState`、`DragonFollowState`）。
- **`register_state(name, node)` 是 super 之后新增 / 替换状态的唯一入口**：`_ready` 自动登记只覆盖挂树时已存在的状态；子类 `super._setup_nodes()` 之后新增的状态必须调它，否则 `transition_to` 静默找不到（替换正在运行的状态会平滑切到新态并重入 `enter`）。
- **Defs**：所有玩法数据（资源 / 建筑 / Pawn / 职业 / 技能 / 技能树 / 连招 / 特效 / 龙 / 关卡）都在 `scripts/defs/` 里通过 `GameDefs` 静态方法在代码中定义，返回 `Resource` 子类；新增单位 / 建筑 / 技能 = 加 Def 再让实体读取，不改实体硬编码。

## 坐标、朝向与模型约定

- Pawn 的逻辑前方固定为 Godot 的本地 `-Z`；移动、攻击扇形、小队跟随槽位都以此计算。
- `Pawn.look_at_target()` 是唯一应直接修改 Pawn 朝向的基础接口。不要为了纠正模型外观而反转它，否则会破坏攻击与小队逻辑。
- `PawnModelRig` 必须是 `Node3D`，以承接 Pawn 的 3D 变换；普通 `Node` 会导致 GLB 子树停在世界原点。
- 模型尺寸和朝向差异只通过 `PawnDef.model_scale` 与 `PawnDef.model_face_offset_deg` 处理。KayKit 占位模型默认朝 `+Z`，因此主角等配置 `180` 度偏转；偏转应用在 `PawnModelRig` 容器，不写入导入模型根节点（避免被动画轨道覆盖）。
- **武器挂点必须挑选**：KayKit 占位角色把「同一只手可用的所有武器变体」都挂在同一个手部挂点下（`handslot_l` / `handslot_r`）且默认全部可见。用 `PawnDef.model_weapon_main` / `model_weapon_offhand` 指定每只手保留的模型节点名（空 = 保留第一个，名字不存在 = 该手空手，`&"*"` = KEEP_ALL），由 `PawnModelRig.apply_weapon_loadout()` 用 `visible` 完成筛选；武器网格是静态子节点、动画轨道只驱动骨骼，显隐不影响动画与战斗判定。⚠️ 不存在的槽位/挂点静默跳过。
- **`anim_map` 必须写候选数组**：Godot glTF 导入器会剥 `_loop` 后缀（GLB 原名 `Idle_loop` → 导入后 `Idle`），单名字会静默落空；候选还须覆盖拼写变体（如 `HitRecieve`）。
- **反转外壳描边（`PawnModelRig.set_outline`：队伍绿标 / 瞄准红标 / 集火标记）必须连同 `MeshInstance3D.skin` 一起复制**：glTF 蒙皮的 `inverseBindMatrices` 存在 `skin` 资源里，只给 `skeleton` 路径的话副本会按「绑定姿 + 骨骼空间」渲染——骨骼带缩放补偿的模型（巨龙 `Armature_001` scale 1.668）会放出比本体大 2~3 倍的巨型幽灵。血液/溶解管线（`begin_dissolve`）是原地换材质，不受影响。
- **模型放大必须同步放大「半径盒」**：`PawnDef.body_scale`（v32）由 `Pawn._apply_body_scale()` 统一施加到碰撞胶囊 / 拾取圆柱 / `NavigationAgent3D.radius` / 选中·集火环；只改 `model_scale` 会得到「视觉 6m、碰撞到脚踝」的单位（穿建筑、点不中、分离力压不住）。**出口锚点同样按比例派生**，不要写死米数（`DragonPet.mouth_height()` = 0.55 基准 × `model_scale/0.55`）。
- **宠物「归位 seek」与「个人空间让位」是两套互斥行为**：不能同时生效（v32 实测：龙从主角身边飞过时被让位抢舵 → 永不 settle）；且让位半径必须显著小于「槽位距离 − 到位半径」（b=2 时 4.5m），否则两者在阈值附近来回触发。
- **给宠物加自主索敌要明确圆心**：v32 的 `DragonDef.auto_attack_range = 11m` 是**以主角为圆心**（不是以龙为圆心）；用 `combat_target`（FightState 进战即写）识别「正在打玩家的敌人」，并给已锁定目标 1.25× 滞回圈防边界抖动。测试里验三级优先级必须**冻结怪本体 + 怪状态机**并显式钉死 `combat_target`，否则干扰项也会 aggro 主角。
- **「出口位置」（嘴 / 枪口 / 施法等特效锚点）不要凭体型想当然**：龙是四足，头在 1.4m 而不是人形胸口 2.1m。定这类高度用骨骼客观量测（`Skeleton3D.find_bone(...)` 的 `get_bone_global_pose()` 乘 `skeleton.global_transform`，`tools/v29_dragon_probe.tscn` 有现成打印），别用模型 AABB。
- **大体重单位（龙）朝向要限速**：`DragonPet` 覆写了 `look_at_target`（3 rad/s），并修掉「同一帧先 `look_at_target` 再读 `facing_dir()` 拿到旧朝向 → 弹体从身侧横喷」——出膛方向改用显式传入的 `aim_dir`，且对准（<18°）才出膛。
- **贴图角色（`VFXManager.TEX_KEYWORDS`）是按文件名关键词 + 排序取第一张**：`flame` 命中的是**暗色**的 `flame_03`，加法混合下几乎不可见。要亮火用 `fire`（= `flame_05`）或 `flame_toon`；加新特效前先 `print(VFXManager.get("_textures"))` 确认角色解析到哪张图。

## 关键数据与通信规则

- 玩法数值集中在 `GameDefs.gd`；新增单位、建筑、技能时优先增加对应 Def，再让实体读取 Def。
- **Autoload（10 个）**：`EventBus`、`GameManager`、`ResourceManager`、`TimeManager`、`SelectionManager`、`AudioManager`、`VFXManager`、`DecorationDissolve`（v13：global uniform 必须抢在任何引用材质加载之前注册）、`LevelRuntime`（v38 关卡会话 + 星级进度落盘 `user://level_progress.cfg`；**空选择 = 按沙盒关跑**）、`RenderQuality`（v47 画质分级；`PRESETS` 是唯一档位数据源，`apply_to_world()` 由 Main 延迟调用）。
- 跨模块「发生了什么」使用 `EventBus` 信号（`scripts/autoload/EventBus.gd` 集中声明：资源变化 / 选择与命令 / 单位出生死亡 / 流民抵达与定居选职业 / 建造与土路 / 时间与天气 / 夜潮准备 / 区域发现 / 主角连招·技能·小队 / 金币经验 / 转职 / 龙 / 受击 `HealthComponent.damaged` / 消息 / game_over）。**EventBus 不持有任何状态**，只做广播。
- 跨模块「执行动作」调用对应单例方法：`ResourceManager.pay()` / `add()` / `refund()`、`SelectionManager.issue_move()` / `issue_attack()`、`GameManager.request_game_over()`、`AudioManager.play_sfx()` 等。
- `GameManager` 持阶段枚举（沙盒常驻 `BUILD`；`PAUSED` / `GAME_OVER` 仍用），`TimeManager` 推进游戏内昼夜时钟（`day` / `hour`，`Engine.time_scale` 控速）并每帧 emit `time_tick`；不要在局部脚本自行维护另一份暂停或阶段状态。`CombatSystem` 只统计存活敌人、在敌人死亡时生成金币 `LootDrop`（`_split_bounty` 拆份），不处理任何伤害结算。
- **`AudioManager` / `VFXManager` 的 id→路径约定自动激活**：`res://assets/audio/<sfx_id>.{ogg,wav,mp3}`、`res://assets/vfx/<effect_id>.tscn`（不存在则按内置 `EffectDef` 程序化生成）。新增音效 / 特效优先走这套约定，而不是改调用点。VFX 预算 `MAX_ACTIVE_EFFECTS=30`（v27），满额按 `EffectDef.priority` 分级回收（命中类可丢、出招类回收最旧低优先级）。
- 代码注释与用户可见字符串一律用**中文**；标识符、信号、节点名用英文。

## 导航与生成注意事项

- 寻路是**格子 A\***（`AStarGrid2D`），不是 NavMesh：`NavSystem` 监听 `building_placed`/`building_removed`，初始化时读取 `GridSystem.terrain_cells` 的湖泊阻挡并预留城堡地基；建筑变更只翻转受影响格的 `set_point_solid` 并即时作废同帧路径缓存，`get_world_path()` 同步返回世界 XZ 路径（`navmesh_updated` 信号名是历史遗留、实为「A* 占用变了」）。
- 玩家土路由 `GridSystem.road_cells` 持有，`EventBus.road_changed(grid, cell, present)` 同步连接样式与路径成本。`NavSystem.road_grid` 镜像障碍、道路成本 1 / 草地 1.2，只有流民与友方小兵使用；道路路径平滑必须保留拐点，不能直切草地。上路 +20% 走 `Pawn.road_speed_multiplier()`，不改基础移速，不给主角 / 敌人 / 巨龙加速。
- 小兵自主生活：`town_life_active` 与巡逻预算交替；编队 / 驻守 / 疗伤优先，城内生活不追城外游荡怪。`chat` 必须通过 `register_state()` 安装；双方预约、轮流气泡、退出双向释放与冷却，命令 / 威胁 / 受伤可中断。专项回归 `tests/RoadTownLifeTest.tscn`。**v43 夜间**：`night_vigil` / `night_chat` 也必须 `register_state()` 安装；夜间轻伤（<95%）且有酒馆时先回馆，站定后 `night_vigil_active=true` 才允许群聊招募，群组用共享 `night_chat_group` 数组（任一人退出其余人下一帧收尾），专项回归 `tests/NightVigilTest.tscn`。
- 寻路性能三层优化（同帧路径缓存 / 路径平滑含 0.45m 净空与对角穿角检查 / BFS 格吸附——不要改回逐环扫描）。
- 群体 AI 性能要点：`Pawn.compute_separation` 走静态空间桶（4m 桶、每物理帧惰性重建、按组名过滤）；`find_nearest_hostile` 带 0.2s 实例缓存、`get_combat_approach_position` 带 0.2s 缓存——索敌/站位在状态里每帧调用已是廉价操作。
- 敌人 AI：`Raider._pick_siege_target` 按「直线筛 top-6 → 真实路程选优」挑攻城目标；`FightState`/`RangedFightState` 每 2.5s 做 stuck 检测；夜潮攻城单位豁免追击中心距上限（44m leash 会把「向主城进军」判成跨图追杀，v20 实测原地折返）。
- 建筑/地面/主城在 layer 1，单位在 layer 5（值 16）且 mask 不含 16 → 单位间互不物理碰撞，靠软件分离力避让；`SelectableComponent` 拾取区独占 **layer 7（pickable，值 64）**——第三人称准星射线（mask=world|structure）得以穿透所有单位身体；`NavigationAgent3D` 节点仅作将来接入 avoidance 的扩展点。
- 士兵和野怪通过 `PawnSpawner._snap_to_navigation` → `NavSystem.snap_to_walkable` 吸附到最近可走格，避免出生在建筑占用的格洞里。

## 寻路维护补充（2026-10-01）

- `Pawn.move_along_path(delta)` 按剩余距离限制本帧速度，防止 3× 调速、集结和移速成长跨过航点后反复掉头；行军分离力受限且不得抵消前进。到达后清零分离力并标记航点已完成。
- `Pawn.navigation_status` 区分 `MOVING / ARRIVED / UNREACHABLE / BLOCKED`；`move_along_path()` 仅真实到达返回 true。不可达时停止直线兜底、最多每游戏秒重试一次；移动目标普通重算间隔 ≥0.25 游戏秒，建筑/资源占用更新立即作废旧路径。卡位恢复先重算，持续受阻交给战斗状态换目标/破墙，不能跳过绕障航点或伪装成到达。自动接战暂避同一失败目标 3 秒；显式集火保留命令、站定等待。新玩家移动指令使用 `force_repath=true`。
- 卡位采样同时看实际位移与到当前航点的进展，并随减速降低阈值；小幅目标更新不清卡位基准，`BLOCKED` 必须清掉残留的同目标更新请求。
- `NavSystem` 的动态格占用由每个障碍独立持有并引用计数；采空、拆除、直接释放不得清掉重叠资源、主城地基或永久地形。资源按实际方形拾取盒 + 单位/转向余量登记（`set_resource_solid` 阈值 1.55m ≥ √2 格角距离），不能退回圆形距离近似。
- 平滑连线包含 0.45m 单位净空，并核对实际离格心起点与精确终点；近距小队 steering 只有连线安全时启用，队形槽位落在障碍边缘时使用安全落点。
- 路径与攻城路程共用同帧 A* 结果；平滑只在申请移动路径时生成。近战站位采用弱引用持久槽位，增减成员不旋转已有站位；新增外圈仍须处于攻击射程内。
- `tests/NavigationStabilityTest.tscn`（CORE）覆盖 25 项加速、敌兵、分离、障碍生命周期、实际碰撞绕行、不可达/卡位、八人交战及查询节流契约；`tests/PathBenchmark.tscn` 固定随机种子、逐物理帧测量回调耗时。

## 野怪行为稳定性维护（2026-10-02）

- 普通野怪超出出生点 16m 后，`RoamState` 持续回撤到 12m 内圈；离开主城须越过 1m 缓冲后再索敌。游荡终点限制在出生点附近，候选路线逐段排除穿城，最多检查 6 个候选；无安全点停住并每秒重试，不能逐帧随机换点。
- 索敌缓存保留 0.2s 扫描节流，但缓存命中每次须复核存活、可被攻击、距离与城镇边界。近战站位不得落进主城；普通野怪追击路线穿城时暂时放弃该目标。夜袭仍可进城（v20 夜潮：进攻意图下被玩家方 Pawn 打立即转火，白天游荡怪与测试木桩保持被动不还手）。
- 夜袭受击首次立即转火，已有存活且可追击的单位目标时保持交战；避免多人连续伤害反复重入战斗。逃跑安全半径 17m 独立于 11m 战斗索敌范围，喘息后威胁到 15m 内才继续跑，扫描仍按 0.2s 节流。
- **v35 逃跑概率化**：低血到线（`flee_hp_ratio`）不再必跑——`Raider.should_flee_now` 按 `PawnDef.flee_chance`（普通 0.2 / 精英 0.15）**一次性掷签**定性格，终身不重掷（回血再战沿用首签）；攻城中与头目照旧死战。**v44 进攻意图死战**：`should_flee_now` 对 `assaulting`（夜潮总攻，含赶路中）与 `_sieging` 一并返回 false——低血也不撤退，避免跑远后玩家打不到；天亮清除 `assaulting` 后恢复普通逃跑语义。**v35 攻城还手优先**：`FightState._handle_stuck` 对已转火玩家单位的攻城怪不切回建筑——stuck 时改为重新索敌换最近玩家单位，索敌圈空才恢复攻城；被围死 / 追不上风筝兵恰恰是最常 stuck 的场景，旧逻辑一 stuck 就弃战冲城。
- `FightState`、`RangedFightState`、`MoveState` 与 `RoamState` 的延迟设点须核对当前状态，避免旧回调覆盖新指令。行走/逃跑动画按实际移动或停住同步。
- `tests/MonsterBehaviorStabilityTest.tscn`（**v44：35 项**，CORE）及 `tools/monster_roam_probe.tscn`（12s 城边与回撤探针）；有界面运行探针会生成 `artifacts/monster-stability/world-*.png`。夜潮不撤退专项：`tests/NightAssaultNoFleeTest.tscn`（15 项）。

## 经济、人口与战斗组织

- 金币 / 建筑 / 人口的当前数值见「项目概要」，这里记非显然的契约：
- `CitySystem` 是以原点为中心的**矩形**安全区（`city_half`）：`is_in_city()`（仅城内可建）、`random_point_outside()`（野怪出生）。**主城是矩形不是圆**：圆环采样 `min_r` 必须 ≥ `half*√2`，否则会采到城内。
- `SettlementSystem`：每屋一床位；定期在城边刷 `Refugee` → `travel_to(house)` → 抵达发 `settle_class_choice_required`（v25 起 HUD 弹 `SettleClassPicker` 四职业卡，真暂停；无 HUD 环境回落随机）→ 玩家点选后经 `settle_class_chosen` 完成转化（`_settle_refugee`）；多人同时抵达按队列逐个处理。
- **士兵 AI 优先级（v18/v22 契约）**：玩家直接命令（集火令）最高 > 低血回酒馆疗伤（`TAVERN_HEAL_THRESHOLD=0.2` 触发，行程中不接战）> 主角小队跟随 > 索敌接战；无酒馆时回落回城休整。城内按 `regen_per_sec` 回血。
- **攻击站位与投射物**：`get_combat_approach_position` 分配环形槽位（每圈 6 人、按 instance_id 稳定相位）；索敌给「已被多名友军交战的目标」+7m 等效路程分摊（自然分兵）。远程 `Projectile` 入 `"projectiles"` 容器、受 `MAX_ACTIVE_PROJECTILES` 上限约束；**`"projectiles"` 分组挂的是 Main 容器节点，弹体是它的子节点**。
- **城防现状**：箭塔 / 兵营已删（v21/v22）——城防 = 木墙 + 定居小兵（酒馆疗伤）+ 巨龙 + 主角。

## 新手引导 / 时间 / 输入

- **新手引导（`TutorialSystem`）**：9 步交互链，完全由 `EventBus` 既有信号 + `Input` 轮询驱动，不侵入玩法系统；HUD `TutorialOverlay` 渲染。首次以主场景运行 `Main.tscn` 时自动开始（判据 `scene_file_path`；测试实例化的子场景不会）；完成 / 跳过写 `user://tutorial.cfg`。**信息步占用 `ui_modal_count` 释放鼠标 + `blocks_control()` 锁操控；等待输入步自动归还**。等待步中「跳过引导」点不到 → **Esc 快捷跳过**（建造模式中的 Esc 让位 BuildSystem）。引导期 `WildlifeSpawner` 停刷、主角自动索敌临时关闭。改动引导步骤时同步维护 `SceneValidation._check_tutorial_flow`。
- **时间 / 暂停**：速度与暂停走 `Engine.time_scale`（0 = 暂停）；`TimeManager.clock_frozen` 只冻结昼夜时钟、不冻游戏（v31 守城准备期）。全局快捷键在 `Main.gd._unhandled_input()`：暂停 P、调速 `-` / `=`（1×→2×→3× 循环）、切网格 F3、聚焦基地 H；夜战准备期回车 = 点「准备守城」（无 UI 模态时）。
- **输入映射（`project.godot [input]`）**：`toggle_hero_mode`=Tab、`hero_attack`=左键、`command`=右键、`hero_skill_1/2`=Q/C、`interact`=E、`jump`=Space、`sprint`=Shift、`build_menu`=B、`squad_rally`=G、`squad_focus_fire`=T、`party_menu`=V、`rotate_building`=R、`zoom_in` / `zoom_out`=滚轮下 / 上。**`trigger_invasion`=T 是无人处理的死绑定**，勿据此推断有入侵。

## 操控与视角要点（v7 / v15）

- **视角模式**：`SelectionManager.ViewMode`（HERO / TACTICAL / TOPDOWN）；v42 起玩家只保留 TOPDOWN（`VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED = false`：开局默认与 Tab 循环都走 `enabled_view_modes()`，单模式时 Tab 只提示不换镜头）。HERO / TACTICAL 的交接收口仍是 `set_view_mode()` → `_enter_control()/_enter_tactical()`，脚本接口 `enter_hero_mode()` / `exit_hero_mode()` 保留（旧测试与截图工具取景）；`set_view_mode(mode, force=true)` 用于同模式重启交接（开局 `enter_default_view_mode()`）。旧布尔 `hero_mode_active` 保留为派生属性（读 = `!= TACTICAL`，写走旧语义）。双相机靠 `current` 互换；`HeroController` 是切换入口，同时管理鼠标捕获（`MOUSE_MODE_CAPTURED`）与小队编组。**等距相机推拉是阻尼平滑的**（`target_distance` 目标 + `_distance` 逐帧收敛），截图/定场用 `IsometricCamera.snap_distance()` 立即对齐。
- **鼠标模式校准**在 `HeroController._sync_mouse_mode()` 每帧执行：操控中 && 未暂停 && 无 UI 模态（`SelectionManager.ui_modal_count`）→ 捕获；模态面板（市民管理 / 驯龙 / 入住选职业 / 暂停 / 结算 / 引导信息卡）自动释放。UI 面板打开/关闭时必须维护 `ui_modal_count`。
- **准星射线**统一走 `HeroController.crosshair_hit()`（mask=1|8 穿透单位）；交互提示经 `EventBus.crosshair_target_changed(target, prompt, kind)` 由 `Crosshair` 渲染。E 交互要求命中点距主角 ≤6m（龙园驯龙；提示接口保留可扩展酒馆等）。
- **建造与操控共存**：`BuildSystem.enter_build_mode()` 不退出操控模式（战术俯瞰下进入建造会自动切回第三人称）；`_aim_ground()` 按当前相机取准星/鼠标投影；放置点距主角 ≤20m（`BUILD_RANGE`）才合法。数字键直建在 `_unhandled_input` 处理，带模态守卫（`ui_modal_count > 0` 或 GAME_OVER 时不响应）。
- **HERO 朝向**：`HeroIdleState` 让角色始终面向相机前方（aim_dir，不随移动方向转身，支持倒退跑），自带重力/跳跃；空中出招保留竖直速度分量。
- **TOPDOWN**：WASD 走 `IsometricCamera.input_to_world_dir()` 屏幕方向基底（随 Q/E 旋转自适应），朝向 = 鼠标落点（`TOPDOWN_AIM_DEADZONE=1.2` 死区防抖）；`Crosshair` 仅 HERO 显示。
- **时序坑**：写 `ThirdPersonCamera.yaw` 后相机 transform 在下一渲染帧才应用，而 `HeroController` 在物理帧读 `forward_flat()` 写 `aim_dir`——脚本化测试/引导必须跨 ≥2 帧等待链路收敛，否则挥砍扇形朝旧方向挥空。
- **`Tab` 必须在 `_input`（而非 `_unhandled_input`）里捕获并 `set_input_as_handled`**——Tab 绑了默认 `ui_focus_next`，HUD 按钮拿焦点后会在 GUI 阶段被消费。v42 玩家只剩俯视角主控时，Tab 仍在 `_input` 阶段被吃掉、只回一条提示（不换镜头，也不让焦点跳走）。
- **进入主控模式自动集结当前编队**（`recruit_squad`：`follow_leader` + `"hero_squad"` 组 + `transition_to("follow")`）；`Hero` 覆盖 `_on_died()`：不 `queue_free`，按 `respawn_at_base` 延迟复活，关闭复活才 `request_game_over(false)`。
- **主角成长**：击杀经验升级（不封顶）、升级 +1 技能点；`level` / `xp` 上移到 `Pawn` 基类，Hero 覆写自己的曲线。
- **TACTICAL 主角待命**：`Hero.autofight_enabled()` 在 TACTICAL 下返回 false——主角不自动索敌，只按玩家右键指派 / `SelectionManager.issue_attack()` 行动（v42 玩家入口已屏蔽，脚本 / 旧测试仍可用这套语义）。

## 修改检查清单

1. 新增全局状态或广播：优先更新 `EventBus.gd` / 对应 Autoload，而不是让实体互相硬引用。
2. 新增 Pawn 状态：确认状态在进入树后已注册（`register_state`），且状态名与跳转名一致。
3. 新增/改名 `class_name`：先 `godot --headless --editor --quit --path .` 重建类缓存再跑无头测试。
4. 更换 GLB：确认模型前方；只调 `model_face_offset_deg`，不要改 Pawn 逻辑朝向；`anim_map` 写候选数组。
5. 新增单位生成点：调用或扩展 `PawnSpawner`，不要复制 `snap_to_walkable` 吸附代码。
6. 修改世界树节点名或 group：先搜索所有 `get_node_or_null()` 和 `get_first_node_in_group()` 调用，避免破坏隐式契约。
7. 提交前运行无头加载 / 跑批；若改动可视内容，再在编辑器中验证俯视角移动/瞄准/挥砍、E 龙园交互、B 建造放置、滚轮平滑推拉与流民入住选职业（HERO / TACTICAL 已屏蔽，需要时用脚本接口取景）。
8. 改镜头 / 视角：玩家默认且唯一 = TOPDOWN（`SelectionManager.VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED`）；HERO / TACTICAL 只在脚本接口与旧测试 / 截图工具里用，恢复三态把开关改回 `true`。改默认视角后同步检查测试里「启动即第三人称」的假设与 headless 鼠标依赖。
9. 文档只改本文件（`CLAUDE.md` 已停止维护，只留指针）：新版本在「版本速览」加一行，超过 ~10 条把最旧的移入 `docs/CHANGELOG.md`。
10. 改渲染 / 画质 / 光照：先跑 `tools/render_probe` 拿到基线，再改 `RenderQuality` 或场景；`RenderQualityTest` + `tools/render_showcase` 至少各跑一次，窗口模式才能拿真实 GPU 数据。

## 场景扩展维护

- `WorldLayout.gd` 定义地图半径 128（v40：256×256 米 / 128×128 格）、王城半径 26（v43：52×52m）、湖岸谐波 / 湖心岛 / 河道折线 / 瀑布多股坐标、道路公式、四路尽头（`road_end`）与夜潮集结点（`night_wave_origin`，62m）；地面与水面着色都读这里经 `apply_shader_parameters()` 写入的 `lake_*` / `river_*` / `ws_*` / `trail_*` / `region_*` uniforms——**改小径 / 湖岸 / 河道只改 WorldLayout，shader 侧不再保留几何副本**。调整湖岸 / 道路公式时同步 water shader 与 `WaterFeatureTest`。
- `WorldRegions.gd` 是主题区域唯一真相（名称/故事/圆心半径/地面色与强度/地标点）；地面染色、分区植被（DecorationScatter）、区域地标（ThemedRegions）、小地图区域层（Minimap）与区域播报（RegionTracker）都读它。新增区域 = 加一条数据 + 对应 `kind` 的散布与地标分支。
- 水体表现（v45）：静水面颜色 / 通透感只改 `scripts/decor/WaterPalette.gd`（湖 / 河 / 潭三套 deep / shallow / shelf / foam / reflect），着色公式在 `water_surface.gdshaderinc` 的 `ground_water()`；瀑布立面着色单独在 `waterfall_surface.gdshaderinc`（共享库只提供 uniform / 噪声 / 天空色，不要在共享库里改瀑布）。水面网格 / 白沫 / 水雾 / 湖心岛在 `WaterFeature.gd`，霜区手工小件在 `ThemedRegions._build_frost` ⑦/⑦b；`tests/WaterFeatureTest` 有 v45 契约（调色来源 / 水雾尺度与混合模式 / 分层绘制序 / 浮冰雪斑有机网格）。
- `Main.tscn` 中地面碰撞 256×256、网格 128×128、相机边界 ±122、刷怪环 116 与散布数量需要一起维护；`WildlifeSpawner._night_gate_pos`（road_end，播报/测试锚点）与 `_night_wave_origin`（62m 集结点）是两个概念，不要混用。
- 序章 `PrologueStage._style_world` 会遍历 DecorationScatter 的 MultiMesh 做裁量：**不要对 MultiMesh 用 `duplicate()`**（逐实例写入的 MultiMesh buffer 未维护，duplicate 会刷 buffer 尺寸 ERROR），应按格式新建后逐实例拷贝（v40 已修）。
- `WorldScenery` 必须先于 `NavSystem` 就绪，将湖泊永久阻挡写入 `terrain_cells`；拆除建筑不得清空永久地形。**湖面物理碰撞盒（v36 `_build_lake_collision_boxes`）必须在 `WaterFeature._register_terrain()` 清出浅滩 / 涉水缺口之后再按 `terrain_cells` 最终状态创建**——先建盒后清格会出现「寻路可走但物理是隐形墙」的矛盾格，单位被路径 / 出生吸附引进去就永久卡在湖里。
- **草坪（v46.2）**：`DecorationScatter._scatter_grass` 的 `grass_count` 是分层采样候选预算（320000 → 约 24 万有效草簇，每簇 12 叶 × 5 三角；普通草地约 60 叶/m²）；`lawn.gdshader` 为不透明短草材质，`grass.gdshader` 继续负责麦田/芦苇等区域高草。草坪底色读取地面 `albedo_grass_a/b`，根/冠渐变在 `lawn.gdshader` 的 `color_bottom/top`；叶高 0.36~0.56m、城内 ×0.86，**v47 起 `lawn.gdshader` 不得使用片元 `discard`**（会关闭 early-Z；消散改逐叶顶点塌缩）；草坪下挂 `LawnInteraction`：64² RGBA8 滚动场（0.5m/像素、32m 视窗、16KB、30Hz 更新；脚边即时接触每渲染帧同步），按实际主角位移在半径 1.4m 内向两侧拨草；世界格短时记忆在 0.8s 内指数回弹至 1% 并清理，UV2 固定单叶根部。暂停不更新、跳跃离地/死亡停止施压、单帧 >6m 位移清历史避免传送连出长草痕；不逐株扫描。镜头穿草仍消隐（树/岩/区域高草保持原半球消散）；散布岩石 AABB 进入 8m 桶作椭圆净空，避免高叶穿岩；`foliage.gdshader` 的 `depth_prepass_alpha` 让完整树冠恢复投影且保留消散区透明。铺路/建筑事件更新 0.5m/像素单通道遮罩、拆除恢复，不修改碰撞或导航。`tests/LawnTest` 覆盖建拆与遮罩，`tests/LawnInteractionTest` 覆盖拨草方向/回弹/暂停/离地/传送/滚动场边界；`tools/grass_interaction_preview.tscn` 用真实主角状态机行走 12s，可加 `--fixed-fps 30 --write-movie artifacts/grass-interaction/walk.avi` 录制；headless 的 Dummy renderer 不保留 MultiMesh 变换，密度检查必须用窗口模式跑；`tools/grass_shot.tscn -- --label=after --view=city/meadow/close/shore/night/build/reference/gameplay`（view 每次选一项）出对照与帧时。参考 [AMD 草地渲染](https://gpuopen.com/learn/mesh_shaders/mesh_shaders-procedural_grass_rendering/) 、[Godot MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) 与 [空间着色器深度预处理](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)。
- 装饰模型与草花使用分块 MultiMesh（装饰 shader `#include decor_dissolve.gdshaderinc` 即自动纳入主角消散判定）；实际可采集目标为 `ResourceNodes`（v22 起屏蔽产出）。
- `artifacts/` 存放交付预览与验收记录（`.gdignore` 排除导入）。截图由运行 `tests/SceneValidation.tscn -- --capture` 或各 `tools/*_shot.tscn` 重新生成。

## 渲染与画质（v47）

- **档位唯一数据源**：`RenderQuality.PRESETS`（低/中/高/极致）；`Main` 末尾 `apply_to_world.call_deferred(world_root)` 落 Environment / DirectionalLight / DecorationScatter / PostFx。切档重扫当前世界；`DayNightCycle` 只写时刻量，**不碰特性开关**。
- **后处理**：`PostFx` 是 `CanvasLayer.layer=0`（3D 后、HUD 前），只调色 / 暗角 / 颗粒；低档整层隐藏。
- **性能契约**：`lawn.gdshader` 不得有 `discard;`（`RenderQualityTest` 卡）、草 LOD 36~78m、档位只收紧 `visibility_range_end`；阴影高档 2 split / 118m，只对原本有阴影的灯生效。
- **验证**：`RenderQualityTest` + `render_showcase` + `render_probe`，窗口模式才有 GPU 数据。

## 高频坑合集（长期有效；出处与完整过程见 docs/CHANGELOG.md 对应版本）

**GDScript 语言**
- 无 `??` 运算符；`for x in [-1.0, 1.0]` 的 `x` 是 Variant，`Vector2 * x` 推断失败是硬 Parse Error——先 `var x_f: float = x`。
- 已释放实例赋给类型化变量 / 做 `is` 判断都会先抛错，**只有 `is_instance_valid` 安全**（先无类型接引用 → 校验 → 再 `as` 转型）。
- 下划线前缀参数（`func f(_delta)`）体内误写 `delta` = 未声明标识符；**Pawn 基类 Parse Error 会让全部子类报「Nonexistent function '_ready'」级联**——排查要看最先的 Parse Error 行。

**Godot 引擎行为**
- **新增/改名 `class_name` 后必须先 `godot --headless --editor --quit --path .` 重建类缓存**，否则 headless 全线 `Identifier "X" not declared` 并级联成无关报错。
- Godot 4 对播放中的同名动画再 `play()` **不会重播**——要 `play()` 后 `seek(0, true)`（`PawnModelRig.play` 已封装三条规则：单次重播/循环让位/攻速匹配，别绕过它直接操作 AnimationPlayer）。
- `AnimationPlayer.pause()` 会清空 `current_animation`——定格姿态用 `speed_scale = 0.0`。
- `set_anchors_preset(PRESET_FULL_RECT/CENTER)` 在父级已布局时会按当前 0×0 rect **回推成负 offsets**（控件塌缩 0×0、`visible=true` 却什么都不画）——preset 后显式清零/设置四个 offset。
- 信号回调里 `remove_child + free` **正在发信号的节点**会 "freed while a signal is being emitted" 硬崩——重建 UI 一律 `call_deferred("_refresh")`。
- `SceneTree.create_timer` 第 4 参才是 `ignore_time_scale`（第 2 参是 `process_always`）；time_scale=0 的冻结等待务必传全 4 参。
- `global uniform` 必须在**任何引用它的材质加载之前**注册，否则报 "removed at some point" 且渲染不正确——只能做 Autoload（`DecorationDissolve` 的存在原因）。
- 反转外壳描边副本必须连同 `MeshInstance3D.skin` 一起复制（`dup.skin = mi.skin`）——缺 skin 副本按「绑定姿 + 骨骼空间」渲染，骨骼带缩放补偿的模型（龙）会放出巨型幽灵。
- 合成键盘事件只带 `physical_keycode` 匹配不上仅按 `keycode` 绑定的动作——`cancel` 动作同时绑两种 ESC。
- `Camera3D.unproject` 返回 canvas 坐标（stretch=canvas_items 基准 1152），PNG 抓帧是窗口像素（1600）——像素比对前先换算（横向 1.389×）。
- `MOUSE_FILTER_STOP` 遮罩**挡得住点击、挡不住滚轮**——滚轮事件对没有 `_gui_input` 处理的控件（ColorRect 遮罩等）不会被消费，直接穿透 GUI 落到 `_unhandled_input`（v35.1 市民管理滚轮缩放冲突的根因）。相机缩放 / 视角旋转这类无 GUI 消费方的输入，在消费端按 `ui_modal_count > 0` 守卫（`ThirdPersonCamera` / `IsometricCamera` 同款；建造模式不是 ui_modal 不受影响）。

**测试与跑批**
- `godot --headless --path . xxx.gd` 把脚本当场景跑会**静默挂死**——脚本必须经 `.tscn` 场景承载。
- Parse Error → 场景无脚本永不 `quit` → 挂死整批——这正是 `run_all_tests.sh` 的 `SCENE_TIMEOUT` 护栏存在的原因；新测试务必保证任何路径下都会 `quit`。
- 同一时刻只允许一个 godot 进程（`.godot` 缓存打架）。
- 物理射线 `hit_from_inside` 默认 false——**从碰撞体内部出发的射线永远打不中该碰撞体**；验「这格有没有碰撞盒」要从体外入射（v36 LakeStuckTest 用 y=6→0.5 竖直下射穿盒顶面；水平贴格射线因从盒内出发全数落空）。
- 写 `ThirdPersonCamera.yaw` 后 transform 下一渲染帧才应用——脚本化测试/引导跨 ≥2 帧等待链路收敛。
- 测试摆位：士兵与攻击木桩**不能叠格出生**（环形站位相位漂移 5s 杀不掉，隔 4m 分格）；金币磁吸类测试分节之间清场（前节遗留币会污染金额断言）；同进程连抓两帧会拿到逐字节相同的旧纹理——对照帧必须独立进程生成。
- 「队形静止 / 漂移」类断言必须先等队形**真正收敛**（连续 N 帧位移 < 亚毫米）再抓基线——固定帧数等待会把「向槽位收敛的残差运动」误判成被测行为，且该残差对初始条件双稳态（无关脚本改动即可让 drift 在 0 与 ~0.06m 间翻转，v34 SquadCommandTest C5 实锤）。
- `one_shot` 粒子的 `lifetime` 同时是**发射时长**——截图/展示给大 lifetime 会把火星摊成几秒慢吐；粒子类不给寿命覆盖，网格类（billboard/刀光）可安全覆盖定格。
- **v42 起玩家默认镜头是俯视角主控**：headless 下鼠标固定在 `(0,0)`，凡是依赖「准星 / 鼠标落点」的测试与工具（建造预览、E 准星交互、第三人称相机量测、巨龙站位）要么显式 `enter_hero_mode()` 用脚本接口取景，要么注入鼠标事件；旧测试的「启动即第三人称」假设要同步改。
- **等距相机推拉是阻尼平滑的**：脚本里改 `target_distance` 后立刻截图会停在过渡途中——截图 / 定场前先 `IsometricCamera.snap_distance()`，或等 ≥0.5s 收敛。

**本项目特有**
- **草坪 shader 不要用片元 `discard`**：会关闭 early-Z，实测草坪 7.34→3.86ms；消散走逐叶顶点塌缩。区域高草 / 树木 / 石头仍可保留 include 里的 `dissolve_clip`（数量少）。
- **不要用 `SystemFont` 作为默认 fallback**：macOS / 无桌面环境可能解析为 `ascent=0`，之后每次文本度量都刷 FreeType 错误并拖慢主线程；默认 fallback 用 `ThemeDB.fallback_font`（`UIStyle._fallback_font()`）。
- `player_unit` 组里除主角还有 `BaseCore`——找主角必须按 `Hero` 类型筛。
- HUD 晚于主角出生实例化（`Main._ready` 顺序）——UI 面板别只靠 `hero_spawned` 信号，要懒查找兜底。
- 冻结 `time_scale` 后只写 `game_seconds` 不够——`TimeManager.begin(hour)` 才同时校准 `hour` 与 `game_seconds`，否则 `DayNightCycle` 按旧 `hour` 画天色（截图全黑）。
- `"projectiles"` 分组挂的是 Main 容器节点，弹体是它的子节点——查飞行弹体读 `container.get_children()`。
- **直写 `global_position` 的位移会穿透静态碰撞**（击飞抛物线 / 复活 / 测试摆位）——落点必须按寻路格裁剪（v36 `Pawn._clamp_knockup_distance`），否则单位被嵌进湖面 / 建筑碰撞盒永久卡死；兜底是 `Pawn._check_terrain_rescue`（滞留阻挡格 2s 自动搬回岸上，主角 `allows_terrain_rescue()=false` 除外）。

## AI 工具链环境（2026-10-02 周博峥搭建）

本机为 AI 协作配了两套 Godot 工具链，互补使用：

### 1. godot-mcp（headless 验证闭环，不需要编辑器）

- DSH 已注册（`~/.dsh/profiles/desktop/cordis.patch.yml` 的 `mcp-godot` 条目），工具名 `mcp__godot__*`（run_scene / screenshot / run_with_capture / search_docs / profiler 等）。DSH 自动拉起与重连，无需人工启动；`GODOT_EXECUTABLE` 已固定为 `/opt/homebrew/bin/godot`（标准版 4.7.1）。
- 源码在 `~/.dsh/mcp-servers/godot-mcp`（纯 Python，MIT），可自行扩展工具。
- 用途：跑探针场景 / 截图 / 结构化抓 stdout+报错 / 性能剖析 / 按 4.7 API 转储查文档。

### 2. Hastur 活编辑器桥（迭代闭环，需要编辑器开着）

- 插件已装入本工程 `addons/hasturoperationgd/` 并在 `project.godot [editor_plugins]` 启用；用 Godot 编辑器打开本工程时插件自动连 broker。
- Broker（本地 Node）：源码 `~/.dsh/mcp-servers/hastur/broker-server`；HTTP 5302 / TCP 5301；token 在 `~/.dsh/mcp-servers/hastur/broker.json`（600 权限，勿入仓库）。
- **常驻方式**：launchd 服务 `com.douyu.hastur-broker`（`~/Library/LaunchAgents/com.douyu.hastur-broker.plist`，KeepAlive 崩溃/重启自动拉活；日志 `~/.dsh/mcp-servers/hastur/broker.log`）。验活 `curl localhost:5302/api/health`。**手动兜底**（服务被卸载时）：`bash ~/.dsh/mcp-servers/hastur/start-broker.sh`；重装服务：`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.douyu.hastur-broker.plist`。
- **用法**：先 `GET /api/executors` 确认编辑器已连；再 `POST /api/execute`（Bearer token）发 GDScript 片段——无 `extends` 的片段自动包 `@tool extends RefCounted`，用 `executeContext.output("key", value)` 返回结果；拿 `Engine.get_main_loop().edited_scene_root` / `EditorInterface` 操作活编辑器（查改场景树、抓编辑器视口、scan_sources 重建类缓存等）。
- **前提**：Godot 编辑器须开着本工程；broker 仅绑 localhost。编辑器未开时回落用 godot-mcp / bash CLI。

### 3. 自检与恢复（cordis.patch.yml 条目被第三方工具改写时）

`~/.dsh/profiles/desktop/cordis.patch.yml` 有被安装器/市场工具整体重写的前科（目录里多个 .bak）。若新会话发现 `mcp__godot__` 工具缺失，先查：

```bash
grep mcp-godot ~/.dsh/profiles/desktop/cordis.patch.yml
```

缺失则把下面模板追加进该文件（headless profile 同理，路径换 `profiles/headless`）：

```yaml
- insert:
    - id: mcp-godot
      name: "@deepseek-ai/dsh-mcp-client"
      config:
        serverName: godot
        transport: stdio
        command: /Users/zhima/.local/bin/godot-mcp
        env:
          GODOT_EXECUTABLE: /opt/homebrew/bin/godot
```
