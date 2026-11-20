# demo-1 版本日志（v3 → v47）

> 本文件是 **AGENTS.md 历史版本日志的完整归档**（`CLAUDE.md` 自 2026-10-18 起停止维护，只留指向 AGENTS.md 的指针），不占用 AI 会话的 workspace instruction 预算。
> 主文件只保留「当前形态 + 稳定工程契约 + 高频坑」；需要某个版本的动机、数值推导、踩坑过程与回归清单时再按需查阅本文件。
> 条目原文迁移自当时的两个主文件（2026-10-02 归档；2026-10-18 起文档统一到 `AGENTS.md`，CLAUDE.md 只留指针），含并行记录，零删减。


## 目录

- v4 · 全局交互 bug 修复六连
- v5 · 雨效果全面强化
- 新手引导契约（v4 建立，v7 重写为第三人称链）
- v7 · 第三人称大改
- v8 · 开始界面 / 设置 / Esc 菜单
- v9 · 武器挂点筛选
- v11 · 寻路行走面修复 + 集火箭头
- v12 · 集结加速 / 攻击特效 / 正后背相机 / 水系 / 遮挡透视
- v13 · 主角周围「半球消散」装饰判定区
- v14 · 小兵人设气泡
- v15 · 三态视角模式 + RTS 主角待命
- v16 · 怪物死亡「动画 + 贴图溶解」
- v16.1 · 气泡俯视角可读性
- v17 · HUD 去冗余改版
- v18 · 小队指令优先 + 常驻绿标 + 拟真跟随
- v19 · 定居小兵四职业技能
- v20 · 夜潮攻城
- v20 · 小兵属性系统（六维 + 等级成长）
- v21 · 删除兵营与募兵兵种
- v20.2 · 小兵属性复审（v21+ 新形态适配）
- v20.3 · 怪物属性对应优化
- v22 · 金币经济 + 酒馆疗伤 + 采集屏蔽
- v23 · 金币「爆出」掉落
- v25 · 入住选职业 + 市民管理 + 转职 + 技能树
- v25.1 · 技能树树状化 + 职业技根节点 + 加点崩溃修复
- v25.2 · 技能树 UI 全面美化
- v26 · 动画 ↔ 特效同步
- v26 · 驯龙系统
- v27 · 特效品质与丰富度
- v28 · 战斗打击感
- v29 · 巨龙系统优化
- v30 · 巨龙卡通火焰
- v31 · 夜间守城准备（入夜时间静止 + 「准备守城」按钮）
- v32 · 巨龙翻倍 + 懒跟随 + 自主守备
- v33 · 进阶职业技能（跳劈 / 陨石术 / 贯穿射击 / 隐身）+ 转职洗点返还
- v34 · 小队经验共享 + 回城疗伤（主角 / 巨龙）
- v35 · 怪物 AI 优化（逃跑概率化 + 攻城还手优先）
- v35.1 · UI 模态期滚轮屏蔽（市民管理开着不再缩放相机）
- v36 · 湖泊卡位修复（碰撞盒与寻路一致 + 击飞落点裁剪 + 滞留自救）
- v37 · 建筑数量上限（酒馆 / 龙园各 1 座：预览变红 + 不扣费 + 卡片置灰）
- v38 · 关卡系统 + 3D 关卡选择地图 + 序章关
- v40 · 世界扩张 256×256 + 六大主题区域
- 历史基线快照（v3 内容状态，v21 修订——已被 v22+ 取代）
- v10 · 小队 / 编队 / 集火系统（AGENTS.md 侧完整记录）
- v42 · 镜头收敛（只保留俯视角主控）+ 相机平滑推拉
- v43 · 入住房屋颜色 + 夜晚城内待命 + 城池/房屋比例 + 湖泊迁移与水景迭代
- v44 · 夜防阵型（按威胁方向部署到城门内侧）+ 进攻中的怪物低血不撤退
- v45 · 瀑布 / 湖泊二轮视觉迭代（白纱湖面 / 平板瀑布 / 硬白圆饼 / 纸片浮冰）
- v47 · 渲染与光影迭代 + 画质分级（AgX / 软阴影 / SSIL / 体积雾 / 草坪 early-Z）


## v47 · 渲染与光影迭代 + 画质分级（2026-11-19）

**需求**：迭代一版渲染与光影质感，同时考虑性能优化；技术路线由执行者决定。

**路线 / 结果**：不堆特效，先把光照比拉开（AgX + 太阳 2.15 / 环境光 0.64 / 夜间月光 1.0），再加软阴影（PCSS）、SSAO/SSIL、夜间体积雾与 9 盏火炬，最后一层轻后处理（PostFx：冷暗部/暖高光、暗角、细颗粒）。画质做成 `RenderQuality` 四档（低/中/高/极致）并接入设置面板，默认高。性能侧的新发现：`lawn.gdshader` 的逐片元 `discard` 关闭 early-Z，草坪 7.34→3.86ms、1440×900 整帧 17.15→13.83ms；改逐叶顶点塌缩后观感不变。方向光从 4 split/150m 改 2 split/118m，城市机位阴影 draw call 1917→1570；字体 fallback 从 SystemFont 改 `ThemeDB.fallback_font`，消除逐帧 FreeType 错误刷屏。最终 1600×900 全部样张机位中位 ≤15.5ms（p95 ≤16.3ms），默认 1152×648 窗口约 70fps；全量 CORE 42 套 0 failed。

**详细交付**（改动清单 / 参数 / 消融数据 / 样张 / 复现命令）：[`docs/render_v47.md`](render_v47.md)。

## v45 · 瀑布 / 湖泊二轮视觉迭代（2026-10-18）

**需求**：本轮重点优化瀑布与湖泊的效果。v43 水系首版实机截图问题：湖面大片乳白像冰面、岸线沙环宽而亮像沙漠、瀑布像一块平板、落水点 / 水雾是硬白圆饼、潭边浮冰与雪斑是纯白多边形纸片。

**湖泊 / 静水面（`water_surface.gdshaderinc` / `water_ground.gdshader` / `ground.gdshader` / 新增 `WaterPalette.gd`）**
- **白纱根因**：湖面材质的低粗糙 PBR 天空镜面（ROUGHNESS 0.22~0.34 / METALLIC 0.12）+ 固定比例 Fresnel + glint EMISSION 在低视角把整片湖刷白。改为 ROUGHNESS 0.55+ / METALLIC 0 / SPECULAR 0，只保留手写「施里克菲涅尔天空反射（F0 = 0.02，俯视≈0、掠射才亮）+ 窄日光带（pow 260）+ 双噪声碎闪（与波纹法线联动）」。
- 深浅三段（沙绿浅滩 → 饱和青绿 → 暗蓝绿深水）+ 低频噪声打散等深线与 basin 暗化（湖心只再暗 10~16%，不再出现黑斑）；岛周浅水晕；河道修正为「中心深、贴岸浅」（上一版方向反）。
- 5 层世界空间波（波长 ≈20 / 8.8 / 2.9 / 1.4 / 1.1m；低频层在浅水 ×0.32）+ 相位噪声 4.6 rad + 法线限幅 0.22 + 波峰明暗 ±8%（夜间减半）。
- 岸线：`ground.gdshader` 沙环 ~3.4m → ~2.0m（湿暗带 0.7m / 湿沙 1.1m / 干沙过渡 1.1m，双噪声扰动）；湖床压暗 66%；水面 alpha 自 1.032 起淡出，与湿沙交叠约 0.45m；白沫收细断续。
- 夜景：乘算保色相 + 墨蓝混合（湖面 V 0.222 → 0.169、rgb 4,41,42）；雨天压暗保饱和。
- **调色收口**：新增 `scripts/decor/WaterPalette.gd`（湖 / 河 / 潭三套 deep / shallow / shelf / foam / reflect），`WaterFeature` 只调用，不再把颜色散落在实体脚本里。
- 量化（overview 机位）：湖面白纱 6.4% → 2.4%、平均饱和度 0.433 → 0.578、青绿占比 55.7% → 71.9%、南岸沙色 24.2% → 8.9%；非湖区域像素不变。

**瀑布（`waterfall.gdshader` 族 / `WaterFeature.gd` / `ThemedRegions.gd` 霜区）**
- 每股落水 = 主帘 40×32 + 主瀑后层水膜（render_priority -2）/ 前层水膜（+2）/ 唇口翻卷（+3），两侧细流各一层后膜（帘类网格 8 个，`curtain_meshes` 仍为 3）；顶点色四通道 = 亮度（r，旧契约保留）/ 流速（g）/ 不透明度（b）/ 明暗（a）；`depth_draw_never` + `render_priority` 强制「后层 → 主帘 → 前层 → 卷边」的绘制顺序。
- 帘面：sqrt(v) 加速水丝、三层频率（大块水幕 / 主水丝 / 细水丝）、边缘噪声羽化（最外缘强制归零）、顶部淡入、底缘逐列「水舌」下探入水；新增唇口翻卷网格（岩檐水面 → 主帘顶）。
- 落水白沫：`waterfall_foam.gdshader` 重做（翻涌白芯 + 径向拉长白丝 + 外扩涟漪 + 孔洞 mask + UV 宽边淡出）；平面缩到 7.2×4.8 + 3 座低矮 3D 白沫丘（半径 1.10 / 0.55 / 0.50m，高 0.075 / 0.040 / 0.035m）→ 白沫只占潭心约 40~50%，外圈回深青水面。
- 水雾 / 飞溅：352 颗（< 400）——Mist 128 @0.55~1.35m alpha 混合 + 近距 2.6~7m 淡出、MistHigh 42、Droplets 64 抛物线、PlungeSpray 34；彻底替换原 96 颗 1.6~3.4m 加法硬白圆饼。
- 瀑顶：`CliffTopStream` 改 10×14 不规则山溪、`CliffLipSheet` 改 7×18 收口唇片；新增 8 块岩岸 + 10 颗卵石压边；唇口最后 0.5m 叠白沫。
- 霜区 ⑦ / ⑦b：3 块 16 段碎边半透冰蓝浮冰（0.86m、吃水 -0.03、水下暗缘、anchor 防互穿推离）、7 片 18 段噪声薄雪堆（近白 `eef3f6`，与浮冰分色）、⑦b 纯白圆锥改 3 根低矮棱面冰晶丛（根部埋地）。
- 湖心岛夜间：岛顶草 / 岛体岩 / 水下沙洲材质登记进夜色同步并压到冷暗色，修掉「夜里亮盘」（强月光下岛顶仍比湖面略亮一档，属月照草面）。

**回归 / 验证**
- `tools/water_check.tscn`（headless）0 failure；`tests/WaterFeatureTest.tscn` **79 PASS / 0 failure**（新增 14 项 v45 契约：WaterPalette 调色来源、湖面 v45 uniform、瀑布后 / 主 / 前层绘制顺序、水雾尺度与混合模式（防硬白圆饼回归）、3D 白沫丘、霜区浮冰 / 雪斑有机网格）。
- `tests/ScenePolishTest` / `tests/CityScaleTest` / `tests/LakeStuckTest` 全绿；全量 CORE 跑批 **39 套全部 PASS / 0 failed**（`bash tools/run_all_tests.sh`）。
- 样张：`tools/water_shot.tscn -- --label=v45`（9 张，新增 lake-shallow / plunge 两个近景机位）；基线 `--label=v45-base`；量化脚本 `tools/water_metrics.py`。
- 坑：① 低粗糙 PBR 镜面是湖面白纱主因，只降 glint / Fresnel 是治标；② 浅滩沙环写成单个反向 smoothstep 会让整湖被沙色 + 焦散覆盖（中间轮实锤）；③ 半透明水帘写 depth 会把后层整片裁掉；④ 浮冰不加 anchor 会被互穿求解推到岸上；⑤ SnowPatch 翻绕序会被整片背面剔除。

## v44 · 夜防阵型 + 进攻怪死战（2026-10-18）

**需求**：① 夜晚按今夜威胁方向把所有非编队 / 非驻守小兵部署到城门内侧，近战前排、远程后排；② 进攻中的怪物低血不撤退（此前逃跑后玩家打不到）。

**夜防阵型（数据/信号）**
- `EventBus.night_threat_direction_changed(active, gate_index, gate_inside)`：active=false 约定 gate=-1、inside=ZERO。EventBus 仍无状态。
- `WorldLayout.gate_inside_point(index, inset=2.5) -> Vector2` / `gate_outward_dir(index)` / `gate_lateral_dir(index)`：0南 1东 2北 3西，按 CITY_HALF + 道路中线；纯函数，测试直接调用。
- `WildlifeSpawner`：`_begin_night_prep` 选门后广播（内侧点 `_snap` 到可走格）；`_dawn_cleanup` 广播清除；监听 `pawn_spawned`，夜里新兵补发当前威胁方向（晚到单位也能进阵列）。

**Soldier / 状态层**
- `Soldier` 新增 `defense_active/gate_index/inside/outward/slot/slot_valid`；订阅威胁信号（在 `super._ready()` 之前，保证夜里新兵补发能收到）；`is_defense_deployable()`（非死亡 / 非 follow / 非 HOLD）、`is_ranged_combatant()`（`def.attack_kind == RANGED`）。
- `ensure_defense_slot()` + 静态布局缓存：名单按 instance_id 稳定排序；近战行从城门内侧点起、远程行接在后面；每行≤8、行距 2.4m、横向 2m 居中；槽位 `nav.snap_to_walkable` + `city.is_in_city` 校验，贴边沿城内方向回退；布局 key = 门号 + 内侧点 + 名单，战斗减员不重排、换门/新兵补发时重建一次。
- `SoldierNightVigilState`：有威胁时站定点从 `night_post` 换成 defense slot，到位朝 `defense_outward`；清除/天亮回原待命点；疗伤/索敌/警报/驻守/集结优先级不变。
- `SoldierNightChatState`：部署状态下不离位——原地相向冒泡，聊天中威胁到达/解除立即交回 night_vigil 重新列阵。

**进攻怪死战**
- `Raider.should_flee_now()`：门控改为 `_sieging or assaulting or ...`；夜潮总攻（含赶路中）与攻城态低血都强制 false；天亮清除 `assaulting` 后恢复普通逃跑语义。`begin_night_assault()` 若当前在 `RaiderFleeState`，先回 idle 中止撤退再恢复攻城。
- `FightState` 低血分支保持唯一调用 `should_flee_now()`，不复制条件。

**回归**
- 新增 `tests/NightDefenseFormationTest.tscn`：21 PASS / 0 failure（东门 7/7 到位、近战纵深 1.06m vs 远程 3.01m、7/7 朝外、部署中 3 人原地群聊不离位、天亮清空）。
- 新增 `tests/NightAssaultNoFleeTest.tscn`：15 PASS / 0 failure（正控制逃跑签仍工作、assaulting/_sieging 强制不逃、低血 assaulting 怪 120 物理帧不进 flee、已在逃跑的怪被总攻令拉回）。
- `MonsterBehaviorStabilityTest` 34→35 checks（补 assaulting 断言）；`NightVigilTest` / `NightAssaultTest` / `RoadTownLifeTest` / `SceneValidation` / `TavernHealTest` 全部 PASS。
- 截图：`artifacts/v44-night-defense-east.png` / `v44-night-defense-top.png` / `v44-night-defense-rows.png`；工具 `tools/v44_defense_shot.tscn`。
- 总回归：CORE 39 套 / 0 failure（`/tmp/v44-core-final.log`）。


## v43 · 入住房屋颜色 + 夜晚城内待命 + 城池/房屋比例 + 湖泊迁移与水景迭代（2026-10-18）

**需求**：① 已入住房屋要有颜色变化；② 夜晚未开战时小兵不要满城乱跑——先去酒馆回血，然后在城内待命，2~3 人闲聊或独自站着，营造等开战氛围；③ 城池与房屋比例要扩大（湖需挪位），湖 + 瀑布全面迭代。

**需求① 入住房屋视觉（`Building.gd` / `BuildingModelRig.gd`）**
- `Building.is_occupied()`：住户有效且未 `is_dead_flag`；`assign_resident()` 连 `resident.tree_exiting`，死亡当帧即回空房外观（不等尸体 0.6s 淡出释放）。
- `BuildingModelRig.set_occupancy_tint(tint, emission)` / `clear_occupancy_tint()`：首次逐 surface 记录原始材质并只 duplicate 一次，之后只改乘色 / emission；clear 把原 override 写回（原本无 override 则写 null），共享 atlas 材质永不改写；`clear_model()` 清记录防悬空。
- 强对比参数：`OCCUPIED_TINT=(1.8,0.62,0.25)`、`OCCUPIED_EMISSION=(0.21,0.11,0.035)`——蓝屋顶变暖棕、白墙金橙；加门口自发光小灯笼（只建一次、白天也亮、空房隐藏）+ 夜间 `OmniLight3D` 暖光（range 4.5、shadow off、按模型 AABB 推导挂点，避免放大后陷进墙体）。
- 回归 `tests/HouseOccupancyTest.tscn`：58 PASS（空房→入住→释放/死亡/拆房，共享材质无污染，占位 BoxMesh 路径）。

**需求② 夜晚城内待命（`Soldier.gd` + 新 `SoldierNightVigilState` / `SoldierNightChatState`）**
- 20:00~06:00（含 v31 `clock_frozen` 守城准备期）非编队 / 非驻守小兵 idle → `night_vigil`，不再进入 `patrol` / `wander`；天亮回 idle 恢复白天巡逻与城内生活。
- 夜间轻伤（`health.ratio() < 0.95`）且场上有酒馆：`healing_trip=最近酒馆`，馆旁站到 ≥95% 再回待命点；行程中 `autofight_enabled=false`；无酒馆则待命点城内回血。
- 待命点：`CitySystem` 城内 + `nav.snap_to_walkable` + 可走格校验，按 `instance_id` 稳定分布在「家附近 / 酒馆附近 / 玩家路边 / 城心（地基外）」；每夜只选一次，抵达后站定（仅极慢换朝向），被新建筑占用才重选。
- 2~3 人群聊：站定且 ≥95% 的小兵每 1.2~2.2s 扫描 5m 内同样站定者，招募 1~2 名进入 `night_chat`；围站相向、每 ~3s 轮流冒泡（8 条夜间台词 + 「已经守到第 N 夜了」，由 `soldier_night_chat_lines(day)` 生成），10.5~13.5s 后各回待命点并进入 25~45s 夜间冷却。白天 `try_chat_with` / `SoldierChatState` 双人契约原样保留。
- 回归 `tests/NightVigilTest.tscn`：22 PASS（守城准备期、无 patrol/wander、3s 位移 0.000m、AI 3 人群聊、显式 3 人组聊、酒馆回血、天亮恢复）。

**需求③a 城池/房屋比例 + 湖泊迁移（`WorldLayout.gd` / `CitySystem.gd` / `GameDefs.gd` / `Main.tscn` 等）**
- 王城 40×40 → **52×52m**（`CITY_HALF=26`）；`CitySystem` 默认 / `Main.tscn` / `DecorationScatter` 同步 26，`WorldRegions.CITY.radius` 24→28。
- 房屋 `footprint 2×2→3×3`、mesh `(5.2,4.2,5.2)`、`model_scale 4.5→6.2`（约 4.9m 宽 × 5.77m 高）；酒馆 3×3 / scale 4.4 / `heal_radius 6→8`；龙园 4×4 / scale 4.2；木墙 1×1 / mesh `(2.0,2.8,0.45)` / scale 1.15；BaseCore 城堡 model scale 3.5→4.0（仅视觉，4×4 占格与碰撞不变）。造价 / HP / 上限 / 产出未改。
- 水系整体东迁：`LAKE_CENTER=(52,-38)`、`LAKE_RADII=(17,12)`（湖西岸 35m > 城东 26m，9m 净空）；`WATERFALL_LIP=(58,-72)`、`POOL_CENTER=(56,-64)`、`POOL_RADII=(6,5)`、`WATERFALL_WIDTH=9.0`、`WATERFALL_TOP_Y=8.2`；`RIVER_PTS` 末点 `lake_distance=0.68<1`。Main.tscn `Water` 节点 (52,0.06,-38)、PlaneMesh 52×52。
- 城门火把 `CITY_HALF+1.5=±27.5` 派生；`WildlifeSpawner.spawn_min_r 32→40`（≥26√2）；`IsometricCamera.max_distance 55→68`；42 个资源点中 11 个迁到 29~34m 城外环带（0 城内 / 0 水中）。
- 回归 `tests/CityScaleTest.tscn` 68 PASS；`WorldExpansionTest` 135 PASS；`SceneValidation` 158 PASS；`BuildLimitTest` / `RoadTownLifeTest` / `MonsterBehaviorStabilityTest` / `DragonPetTest` 同步通过。

**需求③b 水景全面迭代（`WaterFeature.gd` / `WorldScenery.gd` / `ThemedRegions.gd` / water shaders）**
- 湖泊：三阶谐波自然岸线（双湾 + 半岛）、湖心小岛（纯视觉，不参与寻路 / 碰撞，水面 shader 挖洞）、深浅色带 + 浅滩沙底 + 焦散、菲涅尔天空反射 + 日光 / 月光碎闪、角向扇贝白沫；夜间压暗但保青绿饱和度，雨天叠雨点涟漪。
- 瀑布：`WATERFALL_STRANDS` 三股（主瀑 + 西 / 东细流）+ 出挑岩檐承托唇口、分层湿岩苔藓、白沫环 / 同心涟漪 / 水雾 / 飞溅；顶部水道与河潭接缝重做。
- 配套：`Lake_Pier` / `Lake_Boat` / 灯 / 箱 / 袋迁到新湖东岸（约 69.1,-40.6），霜区浮冰迁到新潭西岸，城郊路标与城门统一 ±27.5；`WorldScenery` 湖岸卵石 / 芦苇按 `WorldLayout` 新岸线采样。
- 回归：`WaterFeatureTest` 65 PASS（含多股落水 / 湖心岛 / 岸线谐波 / shader uniform）、`LakeStuckTest` 12 PASS、`ScenePolishTest` 0 failure、`tools/water_check` 16 PASS；截图 `artifacts/v43-water-*.png`（正面 / 侧面 / 湖全景 / 小岛 / 码头 / 夜景 / 雨天）。

**交付截图**：`artifacts/v43-city-day-overview.png`、`v43-house-occupied.png`、`v43-night-vigil-wide.png`、`v43-night-vigil-chat.png`、`v43-water-*.png`；工具 `tools/v43_showcase_shot.tscn`（Lead 专用，无头只做结构自检）。

**总回归**：`bash tools/run_all_tests.sh` 通过 **CORE 37 套 / 0 failure**；另有 FULL 6 套（天气 / 小地图 / 头目夜 / 像素统计 / UI 图标 / 浸泡）全部 PASS（`/tmp/v43-core-final.log`、`/tmp/v43-full6.log`）。


## v42 · 镜头收敛（只保留俯视角主控）+ 相机平滑推拉（2026-10-18）

**需求**：① 镜头只保留俯视角主控，第三人称亲征 / 战术俯瞰先屏蔽；② 滚轮推拉从「一格一格跳」改成平滑过渡。

**视角收敛**：
- `SelectionManager` 新增 `VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED`（均 false）与 `enabled_view_modes()` / `default_view_mode()`；`view_mode` 默认改 `TOPDOWN`。
- 玩家入口只有「开局默认 + Tab 循环」：`Main._ready()` 改调 `hero_controller.enter_default_view_mode()`（`set_view_mode(mode, force=true)` 支持同模式强制交接相机 / 编队）；`cycle_view_mode()` 按开放列表循环，单模式时只回一条提示、不换镜头（避免误以为按键失灵）。
- HERO / TACTICAL 的实现、脚本接口（`enter_hero_mode()` / `exit_hero_mode()`）与旧测试 / 截图工具全部保留；恢复三态 = 两个开关改回 `true`。
- 新手引导：原「切到战术俯瞰」等待步（依赖 `hero_mode_changed(false)`）收敛后永远等不到 → 改为信息步「俯视角怎么打」；`_on_hero_mode_changed` 增加 `wait_input` 判定，防脚本切模式顶掉信息步；`move` 步文案改为「鼠标指向即瞄准」。序章控制器文案、主菜单副标题 / 页脚、`HeroPanel` tooltip 同步。

**平滑推拉（`IsometricCamera`）**：
- 之前 `_apply_transform()` 直接用 `target_distance`，滚轮一次改 5m 立刻生效 → 观感一格一格。
- 现在滚轮只改目标值 `target_distance`（`zoom_step` 5→4，按 `InputEventMouseButton.factor` 缩放以支持触控板），真实视距 `_distance` 在 `_process` 按 `1-exp(-delta*zoom_smoothing)` 收敛（`zoom_smoothing=9`）；平移速度随实际视距缩放；新增 `snap_distance()` 供截图 / 剧情定场立即对齐（`SceneValidation._save_frame` 与 `tools/{ambience,world_regions,visual_qa}_shot` 已接入）。
- 验收：`ThirdPersonTest` 新增 4 条（滚轮只改目标值、当帧不瞬移、0.8s 内收敛、`snap_distance` 瞬移）。

**坑**：
- 改默认视角后，所有断言「启动即第三人称」的测试与工具都要改成显式脚本接口取景（`tests/CameraBackViewTest`、`tests/ThirdPersonTest`）；`ThirdPersonTest` 的 Tab 三态循环断言改成「Tab 不再离开俯视角 + 脚本接口仍可进 HERO / TACTICAL」。
- 引导 `move` 步在 headless 下「按下 1 个物理帧」可能与本帧 press / release 落在同一毫秒，`_process` 采不到 → 测试改为按住 6 个物理帧（真机无影响）。
- 等距相机平滑后，一帧内把 `target_distance` 从 44 拉到 100 再截图会停在过渡途中——截图前必须 `snap_distance()`。

**验收**：`bash tools/run_all_tests.sh` CORE 34 套全绿（SceneValidation 157 PASS / ThirdPersonTest 含新增 4 条 / CameraBackViewTest 0 failed）。

## v40.2 · 氛围与动态表现

**动机**：v40.1 把穿模清零后，场景仍然「太静」：树木一圈红树干、战场/沼地的枯树像棕色大圆锥、区域里没有天气感、湖面是空的、风车是死的。用户要求再迭代一轮。

**区域氛围（`RegionAmbience.gd`，Lead）**：七个 GPUParticles3D 发射器（霜区飘雪 200 / 矿坑紫尘 90 / 麦海金色光尘 140 / 战场余烬 70 / 密林萤火 130 / 沼地雾气 42 / 王城烟囱 22），总计 724 粒子；全部用现有 VFX 贴图 + 程序化柔光点（雪最初用 `circle_02` 被看成白色圆环，改 Image 径向渐变纹理后成细雪）；`ParticleProcessMaterial` 的 emission box/gravity/color ramp 按区域定制；`_process` 每 0.5s 按 `TimeManager.is_night()` 切换 `emitting/amount_ratio`（萤火夜间、花粉白天、余烬夜里更密）。

**湖上码头 + 小船（`ThemedRegions`）**：湖东岸 (53.6,-28) 建 `Lake_Pier`（7 块桥板 + 两根纵梁 + 入水木桩 + 系船桩/系绳 + 岸灯 + 渔具箱/麻袋），旁边 `Lake_Boat` 浮在水面 y≈0.12（船底/船帮/首尾封板/座板/双桨）；纯视觉、不加碰撞、不写 terrain_cells。

**风车自转**：KayKit `building_windmill_blue` 的扇叶节点 `building_windmill_top_fan_blue`（gltf 中扇面在 XY 平面、无内置动画）绕本地 Z 轴 0.45 rad/s，由 ThemedRegions 唯一的 `_process` 驱动（实测 2.1s rotation delta≈0.95 rad）；水井 scale 3.0→2.7 并转 0.6rad，侧看不再歪塌。

**植被质感（terrain-scatter）**：`foliage.gdshader` 新增 `trunk_deep/trunk_light`，非叶像素乘出灰褐木色（叶色/消散逻辑不变），基础林/区域树/外围环带/水草统一生效；battle 34 / swamp 24 改为 SurfaceTool 程序化枯树（主干两段 + 3~4 斜枝，56 tri，dissolve 材质，3 变体），替换「棕色大圆锥」；外围环带 `MM_outer_trees/_v2/_v3`（86+87+87）与 `MM_outer_rocks/_v2/_v3`（40+40+40）。

**坑**：
- 用两帧截图判断风车是否在转不可靠——`TimeManager.seconds_per_day=120`，2.5 秒真实时间 = 30 游戏分钟，太阳/阴影变化会被误看成扇叶转动；必须读节点 rotation 或固定时钟对比几何。
- 粒子贴图要按用途选：`circle_02` 是环形描边，做雪会变成一圈白圆环；`light_01` 是柔光球，适合萤火/光点；雪最终用程序化径向渐变点。
- 栈桥木桩必须插进湖床（min_y 为负），`ScenePolishTest` 的贴地阈值要对 `Lake_Pier/Lake_Boat` 单独白名单，否则会误报。
- 夜间 additive 粒子容易「过亮成星空」：余烬要收小发射盒、缩短寿命、降低数量；萤火要收拢到林间空地，否则大量粒子被树冠遮挡、看起来只有几颗。

**验收**：`tools/ambience_shot` 12:00/18:30/21:00 三时段共 25 张 → `artifacts/world40c/`；ScenePolishTest 16 PASS（含 RegionAmbience 存在/≤8 发射器/≤1200 粒子两条新断言，Lake_Pier 白名单）；WorldExpansionTest / v38_prologue_probe / 全量 39 套 0 failed。

## v40.1 · 场景表现专项（穿模修复 + 环境打磨）

**动机**：v40 的实机截图里能直接看到一批「穿模/悬空/埋地」：断旗插进残墙、风车底座嵌在农田板里、沉船只剩灰板、枯树桩半埋、雪原/盐沼满地白色圆饼与棕色小盒；另外瀑布崖顶压着 KayKit 山体资产，黄色草顶悬空穿插；高空视角还能看到 1024 地面网格的直边。用户要求「全力优化场景表现」。

**几何体检先行**：新增临时 QA 探针（世界 AABB 求 min_y、两两 XZ 重叠面积、road_distance、植被实例 vs 道具 AABB），把问题量化成清单：沉地 30 项（最惨 BrokenFlag -0.87、Boat -0.38、Stump -0.50）、互穿 top 44m²（古树之间）、压路 7 项、植被压道具/悬空若干。清单直接分派给 regions-builder / terrain-scatter，Lead 负责世界层。

**ThemedRegions（穿模修复）**：新增通用工具 `_ground_fit`（世界 AABB 的 min_y 贴地，旋转后的旗/梯/倒木/船同样有效，`fit_min_y` 可覆盖）、`_separate_trees`（≥4.6m）、`_resolve_overlaps`（锚点不动、树×道具只推树、分离轴选「离路更远」）、`_push_props_off_road`、5 轮收敛；具体重做：麦田 scale 2.2→1.5/间距 5m、栅栏两段连续贴地、矿轨 11m→4.5m + 程序化矿车、矿洞杂物成组间距 ≥2.2m、断旗/焦木/余烬重排避墙避路、战场黑饼拆 3 块 r≤1.5、沉船抬到 min_y=-0.10（船帮加高、桨收进船、泥潭 r1.6 作子部件）、盐壳 6→3 块颜色压向地面、矿晶倾斜后按 AABB 贴地、森林古树改等角环（主干最小 7.28m）、`waterplant_C`/`trees_A_cut` 红棕模型全撤换程序化芦苇/倒木。

**地表散布**：余烬 130→45（0.06~0.12m、聚焦土边缘、橙红自发光）；芦苇 1400→450（细长薄片、灰绿）；雪/盐/焦土斑分别 170/250/210 → 80/80/60，尺寸 0.5~1.8m，最小间距拒绝采样、离路 ≥3m；五区专属草色层（frost/battle/swamp/mine/forest = 2200/2200/2200/1100/1300）压掉「区域染色被绿草冲淡」；新增 128~158m 外围环带 `MM_outer_trees` 260 棵 + `MM_outer_rocks` 120 个，补上地图边界与远山之间的秃边；分区散布改为 `call_deferred` 一帧执行，以便读取 ThemedRegions 道具 AABB 做 0.6~1.6m 精确避让。

**世界层/环境**：六条探索小径终点后撤 8.5m（停在区域石碑前，不再从地标道具群中间穿过）；霜语瀑布区域 46,-62/r26 → 44,-60/r24（消除与星落矿坑的圆重叠）；瀑布崖顶的 `mountain_A_grass` / `hills_A_trees` 全部移除，改用同 `cliff_rock` 材质的岩脊块，黄色顶面消失；远山改两环（164~182m 近环 56 座 + 232~268m 远环 40 座）并用乘算色调压成冷绿灰；`Main.tscn` 地面网格 1024→560、地平加 2400m² 雾毯（受光受雾的深绿灰）；ground shader 新增 `region_landmark[8]` 地标夯土地皮（半径 8m、强度 0.42，噪声扰动边缘）；环境雾 0.0012→0.0010 / aerial 0.2→0.16。

**新增回归**：`tests/ScenePolishTest.tscn`（CORE，13 PASS）：道具 min_y ∈ [-0.18,+0.22]（Boat/Ice 白名单）、非树道具互穿 <1.2m²、树×树 <30m²、道具中心 road_distance ≥2.0、道具在图内、植被不压道具、古树主干间距 ≥4.0m、六条小径终点距 landmark ∈ [7.5,9.5]m、无头日志 0 错误。新增 `tools/visual_qa_shot.tscn`（窗口模式，24 张：6 区域 × 30m/16m/低角度 + 城门路标/湖岸/瀑布低角度/地图边缘/200m+320m 全景）。

**坑**：
- `ScenePolishTest` 的日志扫描在拿不到 `--log-file` 时回退读 `${TMPDIR}/demo1-tests/ScenePolishTest.log`，旧日志里的「PASS: 加载日志 0 条 SCRIPT ERROR」文本本身含关键词 → 误判 1 条 bad line；跑批前清旧日志或用新 `--log-file`。
- `Tree×Tree` 树冠允许交叠（自然形态，阈值 30m²），但树×非树必须 <1.2m²——分离算法不能把石碑/残墙推开给树让路（v40.1 首版曾把残墙推回路面）。
- 分区植被 `call_deferred` 后，若有人在实例化后同帧立即读 MultiMesh 会看到 0 实例（测试需跨帧）。
- 低角度截图是发现埋地/悬空的最有效手段，等距高机位会掩盖问题。

## v40 · 世界扩张 256×256 + 六大主题区域

**动机**：v39 的沙盒只有 128×128 米，四个方向都在 60 米左右撞到地图边界；玩家希望世界更大、野外有可探索的主题区域与故事背景，而不是一整片同样的草地。

**尺度（Lead 决策，先与用户确认「256×256 米」）**：`WorldLayout.MAP_HALF` 64→128 → 地图 256×256 米、`GridSystem` 64×64→128×128 格（cell 2m）、A* 覆盖 16,384 格；`Main.tscn` 地面碰撞盒 128→256、Camera `bounds` ±58→±122、`DirectionalLight3D` 不变；`WildlifeSpawner` 白天刷怪环 57→116m、白天上限 10→14、夜晚上限 22→28；`DecorationScatter` 数量 tree 240→520 / rock 130→300 / grass 65k→120k / flower 3.6k→7k / waterplant 100→160；远山环带 83~91→166~184m、36→48 座。**旧地图 ±64m 内所有地标位置保持不变**（主城 / 湖 / 瀑布 / 营地 / 废墟 / 采石场），新内容全部落在扩张环带，因此旧存档语义、旧测试坐标与夜潮/引导/序章行为不受影响。

**主题区域**：新增 `scripts/defs/WorldRegions.gd`（唯一真相：id/名称/副标题/故事/圆心/半径/kind/地面色/染色强度/accent/地标点）定义六个区域：北境·霜语瀑布（46,-62 / 26m）、东北·星落矿坑（94,-84 / 30m）、东境·风吟麦海（94,4 / 30m）、南境·烬誓战场（4,96 / 30m）、西境·雾隐密林（-94,-4 / 30m）、西南·盐风沼地（-86,86 / 30m）；王城作为 `CITY` 只参与播报/小地图，不参与染色与植被改造。设计文档见 `docs/world_regions.md`。

**表现链**：
- `ThemedRegions.gd`（新）：按 kind 建六组地标（冰晶祭坛/矿洞矿轨矿车/风车麦田稻草人/断旗墓碑余烬/树灵祭坛立石/沉船盐壳鬼火）+ 四座城外路标 + 六个区域入口石碑（Label3D 中文指路）；纯视觉、无碰撞、不进 terrain_cells；187 个子节点。
- `DecorationScatter`：新增分区散布（密林古树/寒地冷色树与冰晶/金色麦浪/枯树焦土余烬/裸岩矿晶/枯树芦苇盐壳），独立 MultiMesh + 每区独立 foliage 材质参数，固定 seed；`_valid` 继续避水面/道路/城内/资源点/地标。
- `ground.gdshader`：删除硬编码小径折线，改读 `WorldLayout.TRAIL_SEGMENTS` 写入的 `trail_a[16]/trail_b[16]/trail_seg`；新增 `region_center[8]/region_radius[8]/region_color[8]/region_strength[8]/region_count` 区域染色（噪声扰动边缘，只叠在草地基色上，道路/广场/岸边/水床优先级更高）；首次截图发现染色偏淡 → 区域 tint 提高到 0.68~0.78 并加饱和。
- `Minimap.gd`：底图与湖泊之间画六个区域半透明色块 + accent 描边 + 中心点；左上角显示当前所在区域名（若 RegionTracker 存在则按已发现过滤）。
- `RegionTracker.gd`（新）+ `EventBus` 三个信号（`region_entered/discovered/exited`）+ `HUD` 区域横幅：0.35s 轮询主角位置，首次踏入弹横幅（名称 + 副标题 + 「✦ 新区域」）+ 金色故事日志 + `quest_done` 音效，再次进入只弹横幅不重复故事；开启首轮基线（出生在城内不播报）；**序章（PROLOGUE）完全静音**。

**夜潮平衡（大图回归）**：地图扩到 256m 后 `road_end` 在 ±121m，掠夺者 3.5m/s 要走 35~45 秒，而一夜只有 50 游戏秒——首波还没摸到城墙天就亮。新增 `WorldLayout.night_wave_origin(index)`（同一条路、62m 处，即旧地图边缘距离）：`WildlifeSpawner._night_gate_pos` 仍是 road_end（播报/测试锚点），夜潮与头目改从 `_night_wave_origin` 出生，夜战节奏与 v39 一致；播报「道路尽头」改为「大道」。

**顺手修掉的坑**：
- `PrologueStage._style_world` 对草/花 MultiMesh 用 `duplicate()` → 序章加载时每块草刷一条 `Cannot set a buffer on a Multimesh that is a different size...`（v40 前就存在，只是 ERROR 不在跑批判定里）；改为按源格式新建 MultiMesh、逐实例拷贝前 1/8（保留旧语义）。
- `road_end_name` 与小地图罗盘不一致（旧版把 +Z 叫「北」，小地图测试以北 = -Z）；v40 统一为 **-Z=北、+X=东、+Z=南、-X=西**。
- `NavSystem` 平滑注释里的「64×64 图」更新为 128×128。

**回归**：新增 `tests/WorldExpansionTest.tscn`（133 PASS：网格/地图物理边界/六区域数据自洽/主城→六地标 A* 可达/14 段小径可吸附/四路尽头在路面/小地图投影/加载耗时与节点统计），加入 CORE；`tests/SceneValidation.gd` 旧尺寸断言改 128×128 与 (200,200) 越界点；`NightAssaultTest` 改为校验 62m 集结点；`v38_prologue_probe` 复核序章 MultiMesh ERROR 归零；`tests/MinimapOrientation` / `WaterFeatureTest` / `LakeStuckTest` / `PixelCheck` 保持 PASS。截图 `artifacts/world40/`（六区域 + 高空全景 + 小地图）。

## v4 · 全局交互 bug 修复六连

**v4 顺手修的全局交互 bug（均为真机验证）：** ① `Pawn` 可选中碰撞圆柱原点半埋地下（y∈[-1,1]）→ 上移至 y=1 覆盖全身；② Godot 4 的 3D 拾取延迟到物理帧，`SelectableComponent.set_input_as_handled` 拦不住 `SelectionController`，单击选中在松开时被 `clear()` 抹掉 → `SelectionController` 按下时用 `_selectable_under()`（投影 32px 邻近）自查命中并跳过拖框/清除流程；③ `ResourceNode` 点击命中盒过小（0.8m 树干盒 ≈ 11px）→ 拾取盒脚印 ≥1.8m、高 +0.6m（视觉/寻路不变）；④ `SelectionInfoPanel` 把 `get_display_name()` 调在 def 资源上报错 → 改调 Pawn 方法；⑤ 场景重载拆卸期 TopBar 收到 time_tick 时 `get_tree()` 为 null 崩溃 → `is_inside_tree()` 守卫；⑥ 游戏结束「重新开始」后 `time_scale` 仍为 0（重开即暂停）→ 重载前恢复 1.0。


## v5 · 雨效果全面强化

**雨效果全面强化（v5 新增）：** `WeatherSystem` 的雨从「单层雨幕 + 湿地 uniform」升级为一整条视觉链：**雨强 0~1 随机漫步**（毛毛雨↔暴雨，`rain_strength()` 公开；开场即中雨）、**三层视差雨幕**（RainFar/RainMid/RainNear，全局坐标 `local_coords=false` + 发射盒跟随**视线与地面交点**（不是半空中点，屏幕边缘才有雨）+ `amount_ratio` 随强度缩放；雨丝用**柱状公告牌 `BILLBOARD_FIXED_Y`**——在世界里保持竖直、只绕 Y 朝向相机，配合 55° 俯角产生真实透视（长度已按 ×0.57 预补偿）；**不要用 `BILLBOARD_ENABLED` 球形公告牌**：面片完全正对相机会变成「贴在屏幕玻璃上的一排竖线」，失去世界感（v5.1 真机修）。v5.2 起雨丝改用 `assets/shaders/rain_streak.gdshader`（手工柱状公告牌矩阵）：屏幕平面内随风倾斜 + 两端软锥形 + 逐粒子长度/明暗随机 + 生命周期淡入淡出 + 视距衰减；**v5.3 连贯雨帘（多模态像素诊断 + 成熟引擎通则修正）**：三层倾斜系数必须统一（1.0/1.0/1.0，分层角度差 = 交叉乱雨）、湍流只留轻微摆动（0.12，强湍流=乱飘）、风向只留 15~20s 慢漂移不带快摆分量、屏幕倾角增益 1.15 钳 ±17°——成熟做法是「全场一个风向 + 轻微湍流」（Unity VFX Graph / Niagara 通则），雨丝宽度 ≥2px 防亚像素珠链化、湿地镜面 roughness 0.15/metallic 0.12 防过曝白块、湖面涟漪三频旋转坐标防摩尔纹且指数 8 稀疏化）、**地面溅落环 + 溅起水珠**（程序化环贴图 + `scale_curve`/`color_ramp`，`PlaneMesh.FACE_Y` 平铺加法混合）、**阵风**（双正弦叠加缓慢摆风向，写入各层 `direction`）、**湿度非对称**（淋湿 0.5/s、晒干 0.18/s → 雨停水洼余韵）、**雷电强化**（`lightning_flash` 数值由 `DayNightCycle._apply` 采样渲染成整片天光双击闪烁；雷声延迟 0.25~1.3s 距离感；强度 <0.55 毛毛雨不打雷）。**`DayNightCycle` 风暴覆盖**：采样 `rain_strength()` 把阳光 ×(1-0.5·storm)、天空/雾/环境光 lerp 向灰蓝风暴调色板（夜里只混 30%——乌云夜不该比晴夜亮）、雾加浓、萤火虫雨天收翅；`daylight_factor()` 公开给雨丝做昼夜配色（夜里雨丝偏暗偏蓝）。**shader**：ground 加 `puddle_mask`（低频噪声洼地积水：更深压暗 + roughness 0.06 近镜面 + 法线涟漪）；water 加 `rain_amount`（量化时间值噪声雨点亮斑 + 法线抖动）。**联动**：雨声音量随强度渐变（`play_loop` 目标音量）、`weather_changed(&"rain", 强度)` 分档广播 → TopBar 显示 小雨/中雨/大雨/暴雨、鸟虫环境声雨中压低。**调试**：F6（`debug_weather`，debug 构建生效）循环 晴→云→雨。回归：`tests/WeatherRainTest.tscn`（强度/雷电/风向/干湿/分档 16 项）+ `PixelCheck` 新增雨丝可见性（细竖亮线检测）、风暴天变暗、夜雨可读三组客观统计断言；截图对照新增 `scene-rain-night`。


## 新手引导契约（v4 建立，v7 重写为第三人称链）

**新手引导（v4 新增，v7 重写为第三人称链）：** `TutorialSystem`（`WorldRoot` 子节点、分组 `tutorial_system`）提供一条 9 步交互引导链（欢迎→移动视角→亲自砍树→建房屋→定居说明（v21 替代原「兵营募兵」步）→战术俯瞰→集结小队→战斗技巧→完成），**完全由 EventBus 既有信号 + Input 轮询驱动**，不侵入玩法系统；视觉由 HUD 的 `TutorialOverlay`（聚光灯遮罩 + 步骤卡，遮罩 `mouse_filter=IGNORE`、卡片背景 `PASS` 可点击穿透，不挡操作）监听 `tutorial_step_changed` 渲染。首次以主场景运行 `Main.tscn` 时自动开始（判据：`current_scene.scene_file_path == Main.tscn`，测试实例化的子场景不会自动开始）；完成 / 跳过写 `user://tutorial.cfg` 记忆，顶栏「？」按钮随时重播（`restart()`）。**信息步 vs 等待步的鼠标/操控策略（v7 真机教训：启动即第三人称捕获鼠标，欢迎卡的「开始引导」按钮根本点不到）**：信息步（wait_input=false）经 `_sync_input_modal()` 占用 `SelectionManager.ui_modal_count`（指针释放给卡片按钮）且 `blocks_control()` 让 `HeroController` 清空输入主角站定；等待输入步自动归还计数恢复捕获（玩家必须实操推进）。等待步中卡片「跳过引导」按钮因捕获点不到 → **Esc 快捷跳过**（建造模式时 Esc 让位给 BuildSystem）。引导期间的配套保护（真机调试得出）：**WildlifeSpawner 完全停刷**（`_tutorial_running()` 门禁）、**主角自动索敌临时关闭**、**砍伐步开局自动把第三人称视角转向最近资源点**、游戏结束时引导静默中止（不写记忆、浮层收起）。移动步的完成判定 = 输入动作（WASD/跳跃/冲刺）**或** 相机位姿变化超容差（`_completing` 防按住重触发、完成定时器 `ignore_time_scale` 防暂停死锁）。改动引导步骤时同步维护 `SceneValidation` 的 `_check_tutorial_flow`（真实入口驱动全流程，含信息步/等待步的模态与锁操控断言）。


## v7 · 第三人称大改

**v7 第三人称大改（当前形态）：** 新增 `ThirdPersonCamera`（越肩跟随 / 滚轮缩放 2.2~9m / 射线碰撞收缩 / `shake()` 与等距相机同签名）+ `HeroController` 重写为第三人称操控中枢：**启动即亲征**（`Main._ready()` 调 `enter_hero_mode()`），鼠标捕获视角、WASD 相对相机移动（角色始终面向相机前方，可倒退跑）、Shift 冲刺 ×1.5、Space 跳跃（`HeroIdleState` 带重力 24m/s²）、左键三段连招**顺带砍伐扇形内资源节点**（`hero_harvested` 信号 + chop_wood/mine_stone 音效）、Q/C 技能（技能 2 从 E 改 C）、**E 准星交互**（命中点距主角 ≤6m 才有效：兵营弹招募菜单）、**G 全军集结/解散**、**B 建造**（建造与操控共存；战术俯瞰下进建造自动切回亲征；放置点距主角 ≤20m `BUILD_RANGE`；建造中数字键 1~6 换建筑）、**Tab 切战术俯瞰**（等距相机恢复原 RTS 全套交互）。`SelectableComponent` 拾取区移到 **layer 7（pickable=64）**：准星射线（mask=1|8）穿透所有单位身体，否则主角自己的选中圆柱永远挡准星。鼠标捕获由 `HeroController._sync_mouse_mode()` 每帧校准（`SelectionManager.ui_modal_count` 计数 UI 模态：招募菜单 / 入驻提示打开时自动释放指针，关闭后重新捕获）。HUD 新增 `Crosshair`（准星 + 可交互扩张 + `[E]` 提示，监听 `crosshair_target_changed`）。**踩坑记录（真机验证）**：① 相机上仰时屏幕上缘射线与地面无交点 → `ThirdPersonCamera.screen_to_ground` 返回水平外推 240m 远点，否则小地图视野框塌缩成负坐标、每帧刷 "Invalid polygon data, triangulation failed"；② 写 `tp.yaw` 后相机 transform 下一渲染帧才应用、HeroController 物理帧才读到 → 测试/引导必须跨 ≥2 帧等待，否则挥砍扇形朝旧方向挥空；③ `enter_hero_mode` 在 `Main._ready` 期被调用时 `_resolve_refs`（call_deferred）未跑，相机引用为 null → 进入时若引用缺失须现场解析；④ `Building` 无公开 `is_barracks` 字段只有 `_is_barracks()`，v7 补了带 getter 的公开属性；⑤ **Tab 往返后视角歪**：战术俯瞰期间主角会被下令移动/索敌转身，切回第三人称若相机 yaw 仍停在旧值 → 按 WASD 时主角朝移动方向跑、相机朝旧方向。`enter_hero_mode` 末尾把 `camera.yaw` 对齐 `hero.facing_dir()`（同 look_at_target 公式），且 `hero.aim_dir` 一并同步——HeroIdleState 的物理回调先于 HeroController，留旧 aim 会让主角先转回旧朝向一帧抖动（ThirdPersonTest 有回归断言）。资源节点树/石按近地比例缩小（3.7→2.6 / 7.0→4.5）、金币拾取半径 1.45→2.2。新增回归 `tests/ThirdPersonTest.tscn`（29 项：视角/切换/准星/交互/建造距离/砍伐/跳跃/集结/震屏）。


## v8 · 开始界面 / 设置 / Esc 菜单

**v8 开始界面 / 设置 / Esc 菜单：** 主场景切换为 `scenes/main/MainMenu.tscn`（标题页：开始游戏 / 设置 / 退出游戏，暗金主题 + 渐层背景，代码构建 UI 与 HUD 同范式）。**主菜单布局必须是单一 VBox 流式布局**（`MenuFlow`：上弹性 spacer(2) → `TitleBox` → 36px 固定间距 → `ButtonBox` → 下弹性 spacer(3)）——历史 bug：曾用「标题固定 offset_top + 按钮锚 50% 居中」双锚点方案，两套锚点在不同字体行高 / 窗口纵横比下余量被吃掉，标题与三按钮重合；流式布局在任何画布尺寸（stretch=canvas_items+expand 下画布恒 ≥1152×648）下结构上不可能重叠，MenuFlowTest 有 ≥30px 间距断言。多分辨率验证存档见 `artifacts/res-*.png`。「开始游戏」`change_scene_to_file` 进 `Main.tscn`（TutorialSystem 的自动开始判据 `current_scene.scene_file_path == Main.tscn` 经由主菜单进入依然成立）。游戏内按 **Esc** 弹 `PauseMenu`（HUD 最顶层模态：继续 / 设置 / 返回主菜单 / 退出游戏），打开 = 记住当前倍速并 `set_speed(0)` + `ui_modal_count+=1`（`HeroController._sync_mouse_mode` 据此自动释放鼠标），关闭 = 原倍速恢复。**Esc 优先级链**（HUD 晚于 WorldRoot 挂树、先收到 `_unhandled_input`，必须在 PauseMenu 里自查让位）：GAME_OVER 不响应 → `build_mode_active` 让位 BuildSystem → 引导 RUNNING 让位 TutorialSystem → 设置子页只收子页 → 开关菜单。**P 键互操作**：菜单开着时 P = 关闭菜单（两种出口一致）；倍速键/Tab 在菜单开着时被 `Main.gd` 忽略。**返回主菜单**前必须清理 Autoload 残留（退出建造/退出操控/清空选择/`ui_modal_count` 硬归零/`set_speed(1.0)`——主菜单动画按真实时间走）。设置面板 `SettingsPanel.gd` 主菜单与 Esc 菜单共用一份实现（窗口模式/垂直同步/主音量/鼠标灵敏度），`GameSettings.gd`（静态类，非 Autoload）读写 `user://settings.cfg`、改即应用即保存；音量走 Master 总线，灵敏度由 `ThirdPersonCamera.add_look_delta` 每次读取倍率。**测试坑（真机 computer-use 验证结论）**：合成键盘事件若只带 `physical_keycode`，匹配不上仅按 `keycode` 绑定的动作——`cancel` 动作 v8 起同时绑定 keycode 与 physical 两种 ESC 事件；自动化驱动 Godot 画布 UI 时 AX hit-test 路径按不到按钮，需走 CGEvent 像素路径（`double_click`/keystrokes）。回归：`tests/MenuFlowTest.tscn`（主菜单→对局→Esc 菜单→返回主菜单全链路 + 流式布局间距断言，观察者节点挂 /root 存活过场景切换）+ SceneValidation 新增 Esc 菜单开合/优先级链检查。


## v9 · 武器挂点筛选

**武器挂点（v9 修复「主角左手同时握剑和盾、重叠穿模」）：** 占位 KayKit 角色的每个手部挂点（导入后节点名 `handslot_l` / `handslot_r`）下**挂着该手可用的全部武器变体**且默认全部可见——主角挂点里是 1H/2H 剑 + 4 面盾，于是剑与盾同时出现在左手上、两把剑叠在右手上；村民/士兵/野怪同理（4~5 件叠一起）。修法：`PawnDef.model_weapon_main` / `model_weapon_offhand` 指定每只手保留的模型节点名（空 = 保留挂点第一个子节点，名字不存在 = 该手空手，`PawnModelRig.KEEP_ALL`(&"*") = 模型原样），由 `PawnModelRig.apply_weapon_loadout()`（`setup()` 新增两个可选参数，`Pawn._apply_def` 透传）用 `visible` 完成筛选——武器网格是挂点下的**静态子节点**、动画轨道只驱动骨骼（`handslot_*` 本身），故显隐不影响任何动画与战斗判定。当前配置：主角 = `1H_Sword` + `Rectangle_Shield`（单手剑 + 骑士盾），近战兵 = `Knife`（默认第一个是弩，与近战定位不符），其余单位走默认「每手一件」。回归见 `SceneValidation._check_weapon_loadout`（真实主角实例 + 全部角色 def 逐个断言每手最多一件可见武器）；交付对照样张 `artifacts/hero-weapon-fix.png` 可由 `tools/hero_weapon_shot.tscn` 重新生成。


## v11 · 寻路行走面修复 + 集火箭头

**v11 寻路行走面修复 + 集火箭头（当前形态）：** 用户反馈「小兵总会卡在各种奇怪的地方」+「集火时怪头顶要箭头特效」。三个卡位根因逐一修掉：① **资源点占格**——树/石的物理拾取盒 ≥1.8m 却不占 A* 格，v6 的路径平滑把 A* 逐格路径拉直成**长直段**后径直穿过树干格、单位怼上物理盒即永久卡死。`NavSystem.set_resource_solid()` 把资源中心 **1.55m**（盒半宽 0.9 + 单位半径 0.4 + 转向余量 0.25）内的格心标障碍；**初始 42 点大多恰好落在格角**（到四个邻格心都是 √2≈1.41m），阈值必须 ≥1.41（1.3 旧值导致角位树 29/42 完全不占格）；`ResourceNode._ready`（补苗）/`_deplete`（采空）增量同步并 emit `navmesh_updated` 促 repath。② **跟随纯 steering**——`FollowState` 原先「不走 NavMesh」的直线 seek，成员隔着城堡/墙/树林直线怼死。改**混合导航**：距槽位 >5.5m 走格子 A*（槽位挪 >1.6m 才重规划，防主角每步触发全队寻路风暴），≤5.5m 贴身 steering；贴身期 1.2s 无进展自动切回寻路逃逸 ~1.25s。③ **移动无自愈**——`move_along_path` 全新卡位自愈：0.8s 采样实际位移、<0.25m 无进展连续 2 次 → 跳过顶不过去的航点 → 终点吸附最近可走格强制重寻路 → 仍卡则按「已抵达」返回交回状态机重新决策（直线 fallback 分支同样采样）。**集火箭头 `FocusMarker`**（新组件，挂 WorldRoot 由 `HeroController._sync_focus_marker` 指派）：目标头顶红色下指箭头，**走 HealthBar3D 同款「Sprite3D 公告牌 + 程序化贴图」管线**（首版 MeshInstance3D 倒锥在围攻人堆中始终不可见，弃用——头顶指示类特效一律抄血条的 Sprite3D 方案），上下浮动 + 脉动、`no_depth_test` 穿过人群可见、自跟踪移动目标、按 `def.model_scale` 抬升（头目更高）、目标死亡自动隐藏。**flash 多模态看图还揪出一个真 bug**：`SquadPanel` 只靠 `hero_spawned` 信号拿主角，但 HUD 晚于主角出生实例化（`Main._ready` 顺序）→ 信号永远错过 → 面板从不填充；修为 `_find_hero()` 懒查找（`player_unit` 组扫描）+ SceneValidation 增加「面板列出 4/4 成员」断言。GDScript 坑：已释放实例赋给类型化变量 / 做 `is` 判断都会先抛错，**只有 `is_instance_valid` 安全**（先无类型接引用 → is_instance_valid → 再 as 转型）。回归：SceneValidation 新增 `_check_walk_surface`（资源占格计数 + 孤树生命周期切换 + **成员隔主城直线相望必须绕城归队**（旧纯 steering 必卡的对照实验）+ **80m 穿林行军可达性**）+ 集火箭头 4 断言 + 小队面板填充断言，共 153 项全绿；其余 6 套回归 + Soak 2 游戏日全过。**坑**：`move_along_path(_delta: float)` 参数带下划线前缀，体内误写 `delta` = 未声明标识符——**Pawn 基类 Parse Error 会让全部子类报「Nonexistent function '_ready'」级联错误**，排查要看编辑器输出里最先的 Parse Error 行而不是 Raider/Hero 的报错行。


### 附：AGENTS.md（Codex 指南）侧记录

- **资源点占格**：树/石的物理拾取盒 ≥1.8m 却不占 A* 格——平滑后的长直段径直穿过树干、单位撞上即永久卡死（「小兵卡在奇怪地方」主因之一）。`NavSystem.set_resource_solid()` 把资源中心 **1.55m**（盒半宽 0.9 + 单位半径 0.4 + 转向余量 0.25）内的格心标为障碍：**初始 42 点大多恰落在格角（到四邻格心 √2≈1.41m），阈值必须 ≥1.41**（1.3 旧值角位树完全不占格）；补苗 / 采空由 `ResourceNode._ready/_deplete` 增量同步（emit `navmesh_updated` 促 repath）。
- **跟随混合导航**：`FollowState` 远距（>5.5m）走格子 A* 接近槽位（绕墙 / 建筑 / 树 / 湖；槽位挪 >1.6m 才重规划防寻路风暴），近距贴身 steering；贴身期 1.2s 无进展自动切回寻路逃逸 ~1.25s。v10 前的纯 steering 是隔着城堡 / 树林直线怼死的主因。
- **卡位自愈（`Pawn.move_along_path`）**：按实际位移采样（0.8s 周期、<0.25m 无进展），连续 2 次触发分级自救——① 跳过顶不过去的当前航点；② 终点吸附最近可走格强制重寻路；③ 仍卡则按「已抵达」语义返回，交回状态机重新决策。直线 fallback 分支同样采样。
- **集火箭头（`FocusMarker`）**：小队集火期间目标头顶红色下指箭头，**走 HealthBar3D 同款「Sprite3D 公告牌 + 程序化贴图」管线**（MeshInstance3D 倒锥方案在围攻人堆中不可见，弃用）；上下浮动 + 脉动、`no_depth_test` 穿过人群可见、按 `model_scale` 抬升（头目更高）、目标死亡自动隐藏；由 `HeroController._sync_focus_marker` 指派（挂 WorldRoot）。
- **回归**：SceneValidation 新增 `_check_walk_surface`（资源占格 42/42 + 生命周期切换 + **成员绕主城归队**（旧纯 steering 必卡）+ **80m 穿林行军可达**）与集火箭头 4 项断言，共 153 项全绿。
- **坑**：`move_along_path(_delta)` 参数带下划线前缀，函数体内误写 `delta` 是未声明标识符——Pawn 类挂掉会让全部子类报「Nonexistent function '_ready'」级联错误，排查要看最先的 Parse Error 而不是 Raider/Hero 的报错行。


## v12 · 集结加速 / 攻击特效 / 正后背相机 / 水系 / 遮挡透视

**v12 五条改动（当前形态）——「集结加速 / 攻击特效 / 正后背相机 / 水系 / 遮挡透视」：**

1. **集结加速 + 到位停住 + 跟随原速**（`FollowState` + `Pawn.speed_multiplier`）：G 集结进入追赶期 `GATHER_SPEED_MULT=2.0`（离主角 >`GATHER_START_DIST=10.0` 才算），就位（离槽位 ≤`GATHER_DONE_DIST=2.3`）后永久回落 1×；到位（≤`SETTLE_DIST=1.3`）后 `velocity` 硬置零、`SETTLE_HYSTERESIS=0.9` 滞回不再 seek，分离力有 `SEPARATION_DEADZONE=0.12` 死区 + `SEPARATION_MAX_RATIO=0.15` 上限 → 不再「在地上搓」。实测追赶均值 8.7 m/s（2.18×）、到位后 2s 位移 0.000 m、稳态跟随 1.06×。
2. **攻击特效链**（`VFXManager` 四条管线 + Kenney CC0 贴图）：SLASH（`SurfaceTool` 月牙弧面 + `vfx_arc.gdshader`）、BILLBOARD（`vfx_billboard.gdshader`：冲击环 / 枪口十字星 / 施法微光）、PARTICLES（火星带重力）、TRAIL（投射物尾迹）。职业分派在 `AttackerComponent.attack_profile(PawnDef)`；主角 1/2 段 `slash_arc`、3 段 `slash_arc_heavy`。贴图落 `assets/vfx/textures/`（26 张，`assets/vfx/CREDITS.md` 记来源），缺图程序化回退；`spawn_effect()` 签名未变，命中类按 (攻击者,目标) 0.1s 节流；`MAX_ACTIVE_EFFECTS=24` 满额时按 `EffectDef.priority` 分级——命中类（`PRIORITY_HIT=0`）可丢弃，出招类（`PRIORITY_ATTACK=1`：刀光/枪口闪/施法光）**回收最旧的低优先级节点后照常生成**（同级不互顶：宁可少个火星，也不能「打出去没刀光」）。
3. **正后背相机**（`ThirdPersonCamera`）：`BASE_FOV=78`、`PIVOT_HEIGHT=1.95`、`SHOULDER_OFFSET=0.0`（越肩偏移=用户说的「侧偏」）、初始 `pitch=-0.42`、距离 5.2（2.4~10.0）。主角屏幕横向偏移 0.0px。
4. **水系（瀑布→河流→湖）**：几何真相在 `WorldLayout`（`WATERFALL_LIP/BASE`、`POOL_*`、`RIVER_PTS`+`RIVER_HALF`、`FORD_CENTER=(43.75,-40.4)`），着色库 `assets/shaders/water_surface.gdshaderinc`，入口 shader `water_ground.gdshader`（`ws_region_cut` 1 湖 / 2 河 / 3 潭拆网格）/ `waterfall.gdshader`（`ws_phase` 0 湿岩 / 2 落水帘）；网格与地貌在 `scripts/decor/WaterFeature.gd`（group `water_feature`），河/潭/崖登记 `terrain_cells`（75 格）+ 浅滩可涉水走廊。
5. **主角遮挡透视**（`HeroOcclusionSilhouette`，参考《逃离鸭科夫》）：相机→主角胸口射线（mask `1|8`）判遮挡 → 主角副本渲染进**独立 World3D 的 SubViewport**（层 2，主相机 cull_mask 排除）+ 逐帧同步骨架姿态，经低于 HUD 的 CanvasLayer 半透明叠加，0.12s 迟滞防闪。

**一键跑批**：`bash tools/run_all_tests.sh`（核心 9 套；`--full` 追加既有 7 套；**单场景默认 600s 超时 `SCENE_TIMEOUT` 护栏**——测试脚本 Parse Error 会导致场景永不 `quit`、挂死整批）；Lead 独立探针 `godot --path . tools/gather_probe.tscn`。**新增 `class_name` 后必须先 `godot --headless --editor --quit --path .` 重建类缓存**，否则 headless 全线 `Identifier "X" not declared`（会级联成无关测试的 `Cannot infer the type` 报错）。


### 附：AGENTS.md（Codex 指南）侧记录

- **集结加速 + 到位停住 + 跟随原速**（`FollowState`）：G 集结瞬间成员进入**追赶期**（`GATHER_SPEED_MULT=2.0`、`GATHER_START_DIST=10.0`），就位（离槽位 ≤ `GATHER_DONE_DIST=2.3`）后**永久回落 1×**；到位（≤ `SETTLE_DIST=1.3`）后 `velocity` 硬置零、`SETTLE_HYSTERESIS=0.9` 滞回不再 seek，分离力加 `SEPARATION_DEADZONE=0.12` 死区 + `SEPARATION_MAX_RATIO=0.15` 上限 → 不再「在地上搓」。倍率走 `Pawn.speed_multiplier` + `effective_move_speed()`（默认 1.0，`FollowState.exit()` 还原，不泄漏到战斗/巡逻）。实测：追赶平均 8.7 m/s（2.18×）、到位后 2s 位移 **0.000 m**、稳态跟随均值 1.06×。
- **攻击特效链（`VFXManager` 四条管线）**：① **SLASH**——`SurfaceTool` 自绘月牙弧面 + `assets/shaders/vfx_arc.gdshader`（内缘淡 / 刃口高光 / 逐实例 `progress` 淡入淡出）；② **BILLBOARD**——`vfx_billboard.gdshader` 手写正交基面片（冲击环 / 枪口十字星 / 施法微光）；③ **PARTICLES**（命中火星带重力）；④ **TRAIL**（投射物世界坐标尾迹）。全部 mesh/material/贴图按 `effect_id` 共享缓存，`spawn_effect()` 签名未变。职业分派在 `AttackerComponent.attack_profile(PawnDef)`：战士 `axe_arc`、刺客 `dagger_arc`×2、射手 `muzzle_flash`+`arrow_trail`、法师 `cast_glow`+`magic_trail`+`magic_burst`；主角 1/2 段 `slash_arc`、3 段 `slash_arc_heavy`。**贴图来自 Kenney Particle Pack（CC0）**，落在 `assets/vfx/textures/`（26 张，来源见 `assets/vfx/CREDITS.md`），关键词匹配 + `ResourceLoader.exists()` 守卫，缺图走程序化回退。命中特效按 (攻击者,目标) 0.1s 节流；`MAX_ACTIVE_EFFECTS=24` 名额满时按 `EffectDef.priority` 分级处理——**命中类（`PRIORITY_HIT=0`：hit_spark/hit_ring/hit_burst/magic_burst）可丢弃，出招类（`PRIORITY_ATTACK=1`：slash_arc*/axe_arc/dagger_arc/muzzle_flash/cast_glow/whirlwind_aura/charge_trail）回收最旧的低优先级活动节点后照常生成**（同级不互顶，否则「打出去没刀光」比「少个火星」严重得多）。
- **正后背第三人称相机**（`ThirdPersonCamera`）：`BASE_FOV=78.0`（原 70）、`PIVOT_HEIGHT=1.95`（原 1.55）、`SHOULDER_OFFSET=0.0`（原 0.42 —— 越肩偏移就是用户说的「侧偏」）、初始 `pitch=-0.42`、`target_distance=5.2`、`MIN/MAX=2.4/10.0`。主角在相机空间 |x|=0.000m、屏幕横向偏移 0.0px。`aim_ray()`/`screen_to_ground()`/pitch 钳制逻辑未动。
- **水系（瀑布 → 河流 → 湖泊）**：几何真相集中在 `WorldLayout`（`WATERFALL_LIP=(45.5,-53)` / `WATERFALL_BASE=(44,-45)` / `POOL_*` / `RIVER_PTS`+`RIVER_HALF` / `FORD_CENTER=(43.75,-40.4)`），着色库 `assets/shaders/water_surface.gdshaderinc`（`ground_water` / `waterfall_surface` / `lake_sdf` / `river_sdf` / `pool_sdf` / `ground_water_mask`），两个入口 shader：`water_ground.gdshader`（静水面，`ws_region_cut` 1=湖 / 2=河 / 3=潭 拆网格避免透明面互遮）与 `waterfall.gdshader`（`ws_phase` 0=湿岩 / 2=落水帘）。网格与地貌在 `scripts/decor/WaterFeature.gd`（RiverWater / PoolWater / WaterfallCurtain / CliffTopStream / RiverBankGravel / RiverBanks / NorthCliffRock / NorthCliff 碰撞，group `water_feature`），河道+水潭+崖体登记 `GridSystem.terrain_cells`（永久阻挡 75 格），**浅滩涉水点**留出可走走廊让单位过河。`Main.tscn` 的 `Water` 节点换 `water_ground.gdshader` + `ws_region_cut=1`、PlaneMesh 48×48。**坑**：`bank` 白沫的 smoothstep 必须**递增**（`rv.x` 是到河心距离，写反会让整条河刷成雪坡）；`DecorationScatter._valid()` 与 `ResourceGrowthSystem._pick_spot()` 都要判 `WorldLayout.water_distance()` 否则树草长进河里。
- **主角遮挡透视（`HeroOcclusionSilhouette`）**：参考《逃离鸭科夫》的角色剪影——相机→主角胸口物理射线（mask `1|8`）判定遮挡，超过阈值时把主角模型的副本渲染进**独立 `World3D` 的 SubViewport**（层 2，主相机 `cull_mask` 排除），骨架姿态逐帧从原模型 `Skeleton3D` 同步（骨骼模型不共享 skeleton，必须手动搬 `bone_pose_*`），再经 `CanvasLayer(layer < HUD)` 半透明叠加。0.12s 迟滞 + 淡入淡出防闪。
- **回归**：新增 5 套测试（`RallyFollowTest` / `CameraBackViewTest` / `WaterFeatureTest` / `HeroOcclusionTest` / `CombatVfxTest`）+ Lead 独立探针 `tools/gather_probe.tscn`（客观量测加速倍率 / 到位位移 / 跟随速度 / 画面横向偏移）。**一键跑批 `bash tools/run_all_tests.sh`（核心 9 套；`--full` 追加既有 7 套）**。交付样张：`artifacts/v12-{back-view-squad,integration-water,integration-waterfall,integration-river,vfx-hero,vfx-soldiers,waterfall,water-overview,hero-occlusion}.png`。
- **坑（v12 血泪）**：① 新增 `class_name` 后**必须**先 `godot --headless --editor --quit --path .` 重建类缓存，否则 headless 全线报 `Identifier "X" not declared`，且会级联成「Cannot infer the type」把无关测试一起打挂；② `for side in [-1.0, 1.0]:` 里的 `side` 是 **Variant**，`Vector2 * (side * off)` 推断不出类型 → 硬 Parse Error，必须先 `var side_f: float = side`；③ `TimeManager.begin(hour)` 才会同时校准 `hour` 与 `game_seconds`——冻结 `time_scale` 后只写 `game_seconds`，`DayNightCycle` 仍按旧 `hour` 画天色（截图全黑就是这么来的）。


## v13 · 主角周围「半球消散」装饰判定区

**v13 主角周围「半球消散」装饰判定区（参考《逃离鸭科夫》）：** 以主角（及相机）为球心、`hero_dissolve_radius=5.6` / `inner=2.2` 的半球内，装饰物（草 / 树 / 石头 / 水草 / 花朵 / 金叶林）按距离渐隐到全透明，球外不受影响；球心取主角**胸口高度**，判定区随主角移动。驱动是 `DecorationDissolveSystem`（**Autoload**，`project.godot [autoload] DecorationDissolve`）每帧写**全局 shader 参数**——装饰是 ~484 个 MultiMesh 分块，全局参数一次写入全部材质同步，新装饰 shader 只要 `#include "res://assets/shaders/decor_dissolve.gdshaderinc"` 就自动纳入。使用方 `grass/foliage/stone/decor_generic` 四个 shader 都是 `blend_mix + depth_draw_opaque`，alpha **由 zone 直接驱动**（球心必为 0，不留半透鬼影）；材质接入点在 `NatureAssets.forest_mesh/stone_mesh/dissolve_material`。**关键坑**：`global uniform` 必须在任何引用它的材质加载**之前**注册（否则报 "removed at some point" 且渲染不正确）→ 只能做 Autoload；`player_unit` 组里还有 `BaseCore`，找主角要按 `Hero` 筛。回归 `tests/DissolveZoneTest.tscn`（30 项），样张 `artifacts/v13-dissolve-{forest,grove}-{on,off}.png`（`godot --path . tools/dissolve_shot.tscn`）。


### 附：AGENTS.md（Codex 指南）侧记录

- **是什么**：以主角（以及相机）为球心、`hero_dissolve_radius=5.6` / `hero_dissolve_inner=2.2` 的**半球判定区**内的装饰物（草 / 树 / 石头 / 水草 / 花朵 / 金叶林）按离球心距离渐隐到全透明，球外完全不受影响——主角走进草丛、树冠、石堆时挡视线的装饰自己让开（对齐《逃离鸭科夫》观感）。判定球心取**主角胸口高度**（不是脚底），所以半球才真正罩住挡视线的植被；判定区随主角移动，离开即恢复。
- **驱动方式（关键设计）**：`DecorationDissolveSystem`（**Autoload**，`project.godot [autoload] DecorationDissolve`）每帧把球心/半径写进 **全局 shader 参数**（`RenderingServer.global_shader_parameter_set`）。装饰是 ~484 个 MultiMesh 分块（光草就 65000 株），逐块写 uniform 既慢又易漏；全局参数一次写入全部材质同步，**新增装饰 shader 只要 `#include "res://assets/shaders/decor_dissolve.gdshaderinc"` 就自动纳入同一判定**。
- **shader 侧**：`decor_dissolve.gdshaderinc` 提供 `dissolve_zone()`（半球判定，y 压缩 0.75 + `smoothstep` 中段更陡）、`dissolve_cut()`（判定值 + 程序化 3D 值噪声 → 消散进度）、`dissolve_alpha()`（**由 zone 直接驱动**的剩余不透明度）、`dissolve_clip()`（4x4 Bayer 抖动 discard，默认强度 0）+ 噪声。使用方：`grass.gdshader`（草簇按**实例原点**判定，整簇一起散，逐顶点会把单株草撕两半）、`foliage.gdshader`（树/水草按**顶点世界坐标**判定，树冠比树干先散；噪声频率按实例缩放归一，树 3~4 倍缩放与水草 1.5 倍消隐块尺寸一致）、`stone.gdshader`（石头）、`decor_generic.gdshader`（花朵 / 金叶林这类纯色装饰）。四者都是 `blend_mix + depth_draw_opaque`。
- **材质接入点**：`NatureAssets.forest_mesh()`（树）/ `stone_mesh()`（石头）/ `dissolve_material()`（纯色装饰），由 `DecorationScatter._load_mesh()` 与花朵/金叶林散布处调用。**资源点（`ResourceNode`）与建筑不是装饰，不受影响**。
- **观感定稿过程（踩坑）**：① 只做 `discard` 阈值抖动 → 大屏上呈明显「点半调」，像撒了一层网格；② 抖动 + `cut` 驱动 alpha → 球心长期停在 ~35% 半透，像一层幽灵；③ 最终：**alpha 由 `zone` 直接驱动（球心必为 0）+ `alpha_mix=1.0` / `dither=0.0`**，观感是干净的「淡出散尽」。两个表现参数留成全局 uniform（`decor_dissolve_alpha_mix` / `decor_dissolve_dither`），`tools/dissolve_shot.tscn` 可出开/关对照样张。
- **坑（重要）**：`global uniform` 必须在**任何引用它的材质被加载之前**注册，否则引擎打印 `Shader uses global parameter 'x', but it was removed at some point` 且材质渲染不正确——**场景内建节点永远晚于 `Main.tscn` 的材质解析**，所以只能做成 Autoload 抢在场景之前（`DecorationDissolveSystem._ready()` → `_register_globals()`）。另外 `player_unit` 组里除主角还有 `BaseCore`，查找主角必须按 `Hero` 类型筛。
- **回归**：`tests/DissolveZoneTest.tscn`（30 项：全局参数注册/类型、判定半径五段采样、跟随主角移动、开关、484 个分块的 shader 接入统计、资源点不受影响）。交付样张：`artifacts/v13-dissolve-{forest,grove}-{on,off}.png`（`godot --path . tools/dissolve_shot.tscn` 重新生成）。


## v14 · 小兵人设气泡

**v14 小兵人设气泡：** `SpeechBubble3D`（`Pawn._setup_nodes` 统一挂载，命名 `"SpeechBubble3D"`，分组 `speech_bubbles`）让友方小兵**随机低频**冒出符合人设的台词气泡。台词数据在 `GameDefs.BUBBLE_LINES`（按 `def.id` 分人设池 × `idle/work/combat` 三种心情；缺心情池回落 idle 池），心情由 `SpeechBubble3D.mood_for_state()` 按状态机当前状态名映射（fight/villager_flee→combat，harvest/patrol/move 等→work，其余→idle）。**「不要太频繁」三层硬约束**：单位两泡间隔 `INTERVAL_MIN=45s`~`INTERVAL_MAX=95s`、全场并发 `MAX_CONCURRENT=3`（满员短延时重试）、出生首泡延迟 ≥14s；气泡停留 `DISPLAY_SEC=4s`。实现走血条同款「程序化 Sprite3D 公告牌 + no_depth_test」管线（文字是 `Label3D`，字体走 `UIStyle.make_font()` 与 HUD 同一份 CJK 字体），底图宽度按 `font.get_string_size` 量测自适应；top_level 每帧钉在血条上方（`2.1×model_scale+0.46`）。**无台词池的单位（主角 / 野怪）组件在但永不冒泡**（`pick_line()` 返回空 → 计时器拉长）；死亡期间抑制；`_exit_tree` 归还并发名额防泄漏。回归 `tests/SpeechBubbleTest.tscn`（130 项，已入 `run_all_tests.sh` CORE），样张 `artifacts/v14-bubbles.png`（`godot --path . tools/bubble_shot.tscn`，像素校验 `--script tools/bubble_shot_check.gd`：5 气泡带 × 带内文字 × 暗金描边）。


## v15 · 三态视角模式 + RTS 主角待命

**v15 三态视角模式 + RTS 主角待命（当前形态）：** 「相机 × 操控」从单一布尔 `hero_mode_active` 拆为 `SelectionManager.ViewMode` 三态枚举（`HERO` 第三人称亲征 / `TACTICAL` 战术俯瞰 RTS / `TOPDOWN` 俯视角主控），**Tab 三态循环** HERO→TACTICAL→TOPDOWN→HERO（`HeroController.cycle_view_mode()`，交接全收口在 `set_view_mode()`→`_enter_control()/_enter_tactical()`）。`hero_mode_active` 保留为**派生属性**（读 = `view_mode != TACTICAL`，写走旧语义兼容 `true→HERO / false→TACTICAL`——旧测试直接赋值不踩坑；要进 TOPDOWN 必须经 `set_view_mode()` / HeroController）——绝大多数旧引用（选择禁用 / 兵营拾取让位 / 建造距离 / Q·E 让技能）按「主控」语义继续成立。**俯视角主控（TOPDOWN）**：等距相机 `follow_target=hero` 跟随（禁 WASD/边缘平移，滚轮缩放仍可用），鼠标**保持释放**；WASD 走 `IsometricCamera.input_to_world_dir()` 屏幕方向基底（随 Q/E 旋转过的视角自适应），朝向 = 鼠标落点（`screen_to_ground` 双摇杆瞄准，`TOPDOWN_AIM_DEADZONE=1.2` 死区防抖），瞄准射线 / 怪物吸附（`_find_aim_enemy` 圆心=鼠标位置）/ E 交互全部复用同一条 mode-aware 链路；`Crosshair` 仅 HERO 显示。**RTS 主角待命**：`Pawn.autofight_enabled()` 钩子（基类看 `is_auto_fighter`）+ `Hero` 覆写——TACTICAL 下返回 false，`IdleState/MoveState` 不再自动接战（引导期手动抑制的语义常态化）；玩家右键指派（`issue_attack`）仍可下令接战。外围按实际相机分流：`HealthBar3D` 战术距离档 = `view_mode != HERO`；`Minimap` 点击拉镜头仅 TACTICAL（主控模式镜头属于主角）；`BuildSystem` 在 TOPDOWN 建造 = 鼠标落点放置 + 20m 距离限制（`_aim_ground` 天然按 current 相机分流，无需改）。回归 `tests/ThirdPersonTest.tscn` 37 项（三态循环 / RTS 待命+下令可打 / TOPDOWN 移动基底 / yaw 回 align）全绿。


## v16 · 怪物死亡「动画 + 贴图溶解」

**v16 怪物死亡「动画 + 贴图溶解」（当前形态）：** 用户要求「死亡不要缩小，播死亡动画，然后贴图溶解」。`DeadState` 按**阵营分流**：敌方（野怪）`Death_A` 动画 0.8s 播完定格倒地（`ANIM_HOLD_SEC=0.95`）→ `PawnModelRig.begin_dissolve()` 把模型子树**逐 surface** 换成 `assets/shaders/death_dissolve.gdshader` 的 per-instance ShaderMaterial（拷贝原 albedo 颜色/贴图，武器静态网格一并溶；描边副本 Outline_* 跳过）→ DeadState 每帧写 `dissolve_progress` 0→1（`DISSOLVE_SEC=0.9`）→ queue_free；其余单位（村民/士兵/流民）**维持旧缩小淡出**（`LEGACY_SHRINK_SEC`）。shader 要点：**discard 式消散**（alpha_scissor 思路，无透明排序问题、阴影同步消散），fbm 值噪声阈值场 + `edge_width=0.08` 烧灼带（`burn_color` 橙 × `EMISSION` 发光），`cutoff=progress*(1+edge)` 保证 progress=1 时全片元 discard 无残片。**坑**：GDScript 无 `??` 运算符（测试 Parse Error → 场景永不 quit 挂死跑批，正是 `run_all_tests.sh` SCENE_TIMEOUT 护栏防的场景）；死亡时顺手 `set_aim_highlight(false)` + `set_outline(false)` 防尸体残留红描边。回归 `tests/DeathDissolveTest.tscn`（13 项，已入 CORE：不缩放/动画在播/溶解材质与进度/按时释放/非敌仍缩小），样张 `artifacts/v16-death-dissolve.png`（`godot --path . tools/death_shot.tscn`，同屏三阶段：倒地中/烧蚀过半/溶解殆尽，像素校验 `--script tools/death_shot_check.gd`）。


## v16.1 · 气泡俯视角可读性

**v16.1 气泡俯视角可读性（恒定屏幕像素）：** 用户反馈「气泡在俯视角下太小看不见」——气泡是世界尺寸（宽 ~1.06m），等距相机悬在 ~44m 高空时屏幕上只剩十来个像素。修法抄 `HealthBar3D._follow` 的同一套数学：`SpeechBubble3D._update_view_scale()` 每帧按「当前相机在气泡深度处的竖直视野跨度」（透视 `2·depth·tan(fov/2)`、正交 `cam.size`、KEEP_WIDTH 回竖直）换算根节点缩放 `view_span / REF_SPAN`（`REF_SPAN=9.73` = 第三人称 6m 观距，钳 1.0~9.0）——近景保持 1× 不动 v14 观感，远眺按跨度等比放大到屏幕像素一致；锚点同步抬高 `(_view_scale-1)·TEX_H/2·PIXEL_SIZE` 防大气泡尾巴吞头。回归：SpeechBubbleTest 新增 5.5 节（近景相机 ≤1.01× / 俯瞰相机 >3× 且封顶 / 根缩放生效 / 锚点抬升）。**注意 `bubble_shot_check` 既有抖动**：`Label3D` 文字在同屏多实例下随机丢字形（带轮换失败、bg/描边正常、场景树状态全对、禁用本改动依旧复现、双快照前后帧均有字）——与 v16 系列改动无关，权威回归是无头 SpeechBubbleTest 134 项。**探针教训：`Camera3D.unproject` 返回 canvas 坐标（stretch=canvas_items 基准 1152），PNG 抓帧是窗口像素（1600），横向差 1.389×——比对像素前先换算。**


## v17 · HUD 去冗余改版

**v17 HUD 去冗余改版（当前形态）：** 针对「界面太冗余、很多重复」真机实锤的四类问题一次收敛：① **小队卡并入主角卡**——`SquadPanel` 类删除，`HeroPanel` 变单张合并卡（上半：头像/称号/HP/经验/技能卡，连招段位挪到头像行尾；下半：「小队 n/4 · G 集结 · T 集火 · V 编队」标题行 + 成员紧凑单行（徽章+姓名+44px 迷你血条+数值+跟随/自主）+ 集火行 + 空态行），小队计数从此只有一处；**布局契约：底边锚死建造菜单上方 8px（`offset_bottom=-130`）、顶边随内容收放（`_fit_height()`，量 `get_combined_minimum_size()`）且不越过任务卡下缘（`TOP_LIMIT=-458`）**——重建行用 `remove_child+free` 立即摘除（`queue_free` 的垂死节点会虚增最小高度）。② **单选主角不再弹选中卡**——`SelectionInfoPanel._on_selection_changed` 对单选 Hero 直接 `visible=false`（主角信息唯一来源 = 常驻 HeroPanel；称号 tooltip 补伤害/移速防信息丢失），多选聚合视图不受影响。③ **日志去噪**——删 Main.gd 启动 4 条教学刷屏（首条与 HeroController 模式提示逐字重复）、BuildSystem「建造模式：…」（BuildMenu 标题栏同文常驻）、RecruitMenu「走近兵营按 E 打开」；TopBar 暂停 tooltip「空格」→「P」。④ **布局重叠归零**：旧版 SquadPanel∩任务卡、HeroPanel∩建造菜单（467×36px）两处实叠全部消灭，UiCapture 新增 HeroPanel∩建造菜单 / ∩任务卡 两条零相交断言。**测试契约变化**：SceneValidation 小队断言改走 `hud.get("hero_panel")._rows`；UiIconTest / UiCapture 的选中面板内容触发改「spawn_soldier + 选中士兵」（选主角不再出卡）。对照样张 `artifacts/ui-{hud,hero}.png`。


### 附：AGENTS.md（Codex 指南）侧记录

- **背景**：真机截图暴露的冗余与重叠——① 左下两张卡各自报小队数（HeroPanel「小队 0」+ SquadPanel「小队 0/4」）；② 单选主角时右侧选中卡把生命/经验/等级/击杀**原样再印一遍**；③ 启动时 Main.gd 连发 4 条操作教学日志刷屏消息日志（首条与 HeroController 进模式提示一字不差重复）；④ SquadPanel 压任务卡、HeroPanel 压建造菜单（实交叠 467×36 px）。
- **合并**：`SquadPanel` 类删除，小队区（标题行自带键位提示 / 成员紧凑单行 / 集火行 / 空态行）并入 `HeroPanel`；`HUD` 不再有 `squad_panel` 属性，SceneValidation 断言改走 `hero_panel._rows`。成员行改单行紧凑制（徽章 + 姓名 + 44px 迷你血条 + 数值 + 跟随/自主），职业名进 tooltip。
- **选中去重**：`SelectionInfoPanel._on_selection_changed` 对「单选主角」直接不显示（主角信息卡唯一来源 = HeroPanel；`_title_label.tooltip_text` 补了伤害/移速，旧选中卡独有的两条属性不丢）。UiIconTest / UiCapture 的选中面板内容触发改用 `spawn_soldier` + 选中士兵。
- **日志去噪**：删 Main.gd 启动 4 连发、BuildSystem「建造模式：…」（BuildMenu 标题栏同文常驻）、RecruitMenu「走近兵营按 E 打开」（开着才可见且准星已有 [E] 提示）；TopBar 暂停按钮 tooltip「空格」改「P」（v7 起空格是跳跃）。入驻提示收敛为一行键位提示。
- **回归**：UiCapture 新增 HeroPanel∩建造菜单 / ∩任务卡 零相交断言（真机跑批 0 失败）；UiIconTest / SceneValidation / ThirdPersonTest / MenuFlowTest / 核心批 13 套全绿。对照样张 `artifacts/ui-{hud,hero}.png`（`godot --path . tests/UiCapture.tscn` 重新生成）。


## v18 · 小队指令优先 + 常驻绿标 + 拟真跟随

**v18 小队指令优先 + 常驻绿标 + 拟真跟随（当前形态）：** 三个用户反馈一次收敛：
① **主人命令最高优先**——`FightState`/`RangedFightState` 每帧先查 `_live_focus_order()`（队长活着的集火令）：正在打别的目标（自动索敌接上的）也**立即转火**（旧版要等当前目标死掉才理睬新命令）；目标**死亡即失效**（`_target_dead` 看 `is_dead_flag`，不等野怪尸体 1.7s 动画+溶解才 `queue_free`——旧版会对着尸体空挥到释放）；小队成员目标失效后**回队长身边列队**（不再 40m `find_nearest_hostile` 顺手追打无关敌人脱离指挥）；`find_nearest_hostile` 跳过垂死尸体（索敌不会再选中消散中的尸体）；G 集结令附带 **2.5s 停火期**（`FollowState.RALLY_BREAKOFF_SEC`，`gather=true` 进入时置位）：正在接战的成员先归队列阵、不被沿途近敌拉走（集火令仍最高，不受停火限制）。② **小队常驻绿标**——`Pawn.set_squad_mark(on)`：绿色反转外壳描边（复用 v10 红描边管线，`SQUAD_MARK_GREEN=0.35/1.0/0.45` 与主角血条同款绿）+ 脚下 **TorusMesh 小绿圈**（`SquadRing`，内/外半径 0.34/0.42，unshaded）；`Hero.recruit_squad` 开、`_release_member`/死亡/失效清理口关。③ **拟真跟随（根治「踱步」）**——三个根因逐一修掉：(a) **槽位持久化**：slot 缺省读 `Pawn.squad_slot`（Hero 编队/重排维护），战斗→idle→follow 回环不再全员回落 0 号槽挤同一点（旧版 IdleState/SoldierIdleState 回 follow 不带 slot，四人挤同点 = seek/分离互推振荡）；(b) **队形朝向改跟随队长移动方向**（`_rotate_toward` 限速 2.6rad/s 平滑），不再用队长瞬时朝向——主角第三人称永远面向相机，转视角会让旧算法的槽位绕主角旋转、成员不停重走；**队长停下后槽位冻结为世界坐标休整位**（`_rest_pos`，队长偏离锚点 `REST_RELEASE_DIST=3m` 才重排）→ 站定即静止；(c) **动画按实际速度**（`_sync_move_anim`：站定 idle / 常速步行 / 2× 追赶 run，抄 HeroIdleState 同款速度判定）——旧版 enter 播一次 `follow`（Walking_A 循环）永不切换，站定时就是「原地踏步」。回归 `tests/SquadCommandTest.tscn`（18 项，已入 CORE）：转火打断 / 击杀归队 / 集结打断战斗 / 绿标开合 / 槽位持久 / 主角转身零踱步（2s 漂移 0.000m）/ 站定 idle 动画；渲染级校验 `tools/v18_marks_probe.tscn`（灰底对照，20293 绿像素 / 脚圈带 3313 / 对照组 0）+ `--script tools/v18_marks_check.gd`；实机样张 `artifacts/v18-squad-green-marks.png`（`tools/v18_squad_marks_shot.tscn`，**同进程连抓两帧会拿到逐字节相同的旧纹理——对照帧必须独立进程 `-- --disband` 生成**）。v12 契约不回归：RallyFollowTest 13 项 / gather_probe 全绿（2.09× 追赶、到位 2s 漂移 0.000、稳态 1.06×）。


## v19 · 定居小兵四职业技能

**v19 定居小兵四职业技能（当前形态）：** 四职业定居小兵（战士/法师/刺客/游侠）各配一个主动技能，**全部带 CD、全部带特效或显示**。框架：`PawnDef.skill: PawnSkillDef`（新 Def，`kind` 枚举派发）+ `PawnSkillComponent`（`Pawn._setup_nodes` 见 `def.skill` 非空才挂载）；`FightState`/`RangedFightState` 在姿态 leash 判定后每帧调 `pawn.try_cast_combat_skill(target)`——CD 就绪且满足施法距离即**瞬发**（不设独立技能状态，返回 true 该帧不再普攻）。四技能：① **法师 · 暴风雪**（CD 9s）——目标地点生成 `SkillBlizzardZone`：地面冰蓝指示圈 + 上空落雪粒子，半径 4.5m（比普攻判定大一圈）、3s 每 0.5s 一跳伤害 + 减速到 55%（`Pawn.apply_slow` 逐跳刷新），到期自毁；② **战士 · 血怒**（CD 15s）——自身增益 6s：`attacker.damage` 临时 ×1.5（到期精确还原），吸血监听 `EventBus.damage_dealt`（自己造成的每笔伤害回 60%）；表现 = `rage_burst` 爆发环 + 常驻 `RageAura` 怒气粒子 + 头顶血怒芒星标记；③ **游侠（原「射手」改名）· 快速射击**（CD 8s）——0.14s 三连金箭（`AttackerComponent.launch_projectile(target, dmg, tint)` 公开入口）+ 给目标挂 3s 易伤（受伤 ×1.3）；**基础被动 = `move_speed 5.25`（原 4.2 × 1.25，全职业最快）**；④ **刺客 · 背刺**（CD 10s）——`cast_range 7m` 远超普攻 1.7m，CD 就绪**优先先手**（靠近到 7m 即闪不必走到贴脸）：瞬移目标身后 1.1m + 转身 + 单次 32 点重伤；表现 = 起落双向 `blink_ring` 紫环 + 双匕首弧光 + 命中爆散。**状态效果基础设施**：`Pawn` 的 `apply_slow/apply_vulnerable/incoming_damage_mult/show_status_mark`（`_physics_process` 统一倒计时；`effective_move_speed()` 乘减速因子——寻路/风筝/逃跑全分支生效）；`HealthComponent.apply_damage` 开头按宿主 `incoming_damage_mult()` 放大（易伤对一切来源生效）。头顶标记 `BuffMarks3D`（Sprite3D 公告牌 + 程序化形状：环=减速冰蓝/菱形=易伤橙红/芒星=血怒绯红，竖排血条上方到期自隐）。`SelectionInfoPanel` 单选小兵新增「技能 名 · CD Xs（就绪/冷却）」行。回归 `tests/SettlerSkillTest.tscn`（43 项，已入 CORE）；**gather_probe 跟随测速契约改为逐成员按各自 move_speed 归一**（游侠被动移速后拿战士 4.0 当全队基准会误判超速）；样张 `artifacts/v19-settler-skills.png`（`tools/v19_skill_shot.tscn`）。


### 附：AGENTS.md（Codex 指南）侧记录

- **技能框架**：`PawnDef.skill: PawnSkillDef`（新增 Def，`kind` 派发）+ `PawnSkillComponent`（`Pawn._setup_nodes` 检测到 `def.skill` 才挂载）。战斗状态（`FightState` / `RangedFightState`）在姿态 leash 判定后每帧调 `pawn.try_cast_combat_skill(target)`，CD 就绪且满足距离即**瞬发**（不设独立技能状态，不打断既有站位逻辑），返回 true 该帧不再普攻。四职业技能都在 `GameDefs.skill_*_def()`，全部 `cooldown > 0`、全部带特效（VFXManager 新注册 `blizzard_ring` / `rage_burst` / `blink_ring`）+ 施法飘字（`EventBus.floating_text`）。
- **法师 · 暴风雪（CD 9s）**：目标地点生成 `SkillBlizzardZone`（半径 4.5m 比普攻判定大一圈）：地面冰蓝指示圈 + 上空落雪粒子，3s 内每 0.5s 一跳伤害 + 减速到 55%（`Pawn.apply_slow`，逐跳刷新），到期自毁；施法者死亡不影响已落成的场。
- **战士 · 血怒（CD 15s）**：自身增益 6s——`AttackerComponent.damage` 临时 ×1.5（到期精确还原），吸血走 `EventBus.damage_dealt` 监听（自己造成的每笔伤害回 60%，去中心化、免侵入 `try_attack`）；表现 = 绯红爆发环 + 常驻 `RageAura` 上升怒气粒子 + 头顶血怒标记。
- **游侠（原「射手」改名）· 快速射击（CD 8s）+ 基础被动**：被动 = `move_speed 5.25`（原 4.2 × 1.25，全职业最快）；技能 = 0.14s 间隔三连金箭（`AttackerComponent.launch_projectile(target, dmg, tint)` 公开入口，复用职业档案尾迹/枪口），并给目标挂 3s 易伤（`Pawn.apply_vulnerable`）。
- **刺客 · 背刺（CD 10s）**：`cast_range 7m` 远超普攻 1.7m——CD 就绪时由战斗状态**优先先手**（靠近到 7m 即闪，不必先走到贴脸）；瞬移到目标身后 1.1m、转身、单次 32 点重伤（易伤乘区由 `HealthComponent.apply_damage` 统一处理）；表现 = 起落双向紫环 + 双匕首弧光 + 命中爆散。
- **状态效果基础设施**：`Pawn` 新增 `apply_slow / apply_vulnerable / incoming_damage_mult / show_status_mark`（`_physics_process` 统一倒计时，`effective_move_speed()` 乘上减速因子——寻路/风筝/逃跑全部分支自动生效）；`HealthComponent.apply_damage` 开头按宿主 `incoming_damage_mult()` 放大（易伤对一切来源伤害生效）。头顶标记 `BuffMarks3D`：Sprite3D 公告牌 + 程序化形状贴图（环=减速冰蓝 / 菱形=易伤橙红 / 芒星=血怒绯红），竖排血条上方、到期自隐。
- **UI**：`SelectionInfoPanel` 单选小兵新增「技能 名 · CD Xs（就绪/冷却）」行，实时刷新。
- **回归**：`tests/SettlerSkillTest.tscn`（43 项：数据契约/暴风雪区域与减速吸血/血怒面板与吸血起止/易伤数值与到期/背刺先手瞬移落位/CD 门禁）已入 `run_all_tests.sh` CORE。**`tools/gather_probe.tscn` 跟随测速契约更新**：游侠被动移速后，「稳态跟随回原速」改为**逐成员按各自 move_speed 归一**（原实现拿战士 4.0 当全队基准，游侠 5.25 会被误判超速）。交付样张 `artifacts/v19-settler-skills.png`（`godot --path . tools/v19_skill_shot.tscn`，像素校验：冰蓝/绯红/金色/紫色四族特效同屏可见）。


## v20 · 夜潮攻城

**v20 夜潮攻城（当前形态）：** 用户需求「傍晚不刷怪；夜晚真正来临时四个路的尽头（其中一个）刷大批量的怪持续攻主城；中途被小兵打就优先打小兵」四件套一次落地：① **傍晚停刷**——`Raider.is_dusk_now()`（18:00~20:00）门禁 `WildlifeSpawner._process` 直接返回，白天零散补刷照旧；② **夜潮出自四路尽头**——`WorldLayout.road_end(0..3)`（`ROAD_END_INSET=57`，`road_center_x/z` 与 `road_distance` 同一套弯曲公式；方位与四向城门火炬同约定 **+Z=北、+X=东**）入夜随机四选一并整夜固定，`_spawn_night_wave` 从该路口按 4 列纵深队列刷大批量（夜 N 批量 = `clampi(5+N, 6, 11)`，15% 精英带头；`night_max_monsters` 16→22、`night_wave_interval=9s`）；③ **直取主城持续推进**——夜潮怪出生即 `Raider.begin_night_assault()`（`assaulting` 标记），`try_start_siege` 的 assaulting 分支**无概率/冷却/并发门控**锁定 `base_core`（无主城场景回退 `_pick_siege_target`）；被小兵打断杀完后经 idle→try_start_siege 同一分支**立刻恢复推进**；天亮 `_dawn_cleanup` 清标记（FightState 天亮检查负责撤军）。**关键修复：`FightState` 追击中心距上限（44m）对攻城单位豁免**——夜潮出生在 ~57m 外，旧 leash 会把「向主城进军」判成跨图追杀，fight↔idle 每帧折返原地杵立（实测 12 游戏秒位移 0.0m）；④ **被小兵打立即转火**——`HealthComponent` 新增 `signal damaged(amount, source)`（受击仍存活时发射），`Raider._on_damaged` **仅在进攻意图下**（`assaulting or _sieging`，即「中间」= 向主城推进途中）对**玩家方 Pawn**（士兵/主角）立即 `transition_to("fight", {target, siege: true})`：追小兵允许跟进城、杀完经 idle→try_start_siege 恢复推进；**白天游荡怪与测试木桩保持被动不还手**（首版无差别反击会把依赖「野怪挨打不动」契约的测试打红，PawnStatsTest 实锤）；建筑（箭塔）伤害不打断推进（卡墙换目标归 FightState stuck 检测）；低血逃跑中不反击；已在打同一目标不重复切状态防抖。**坑**：`TimeManager`（autoload）先于场景节点看到 `hour=20` → `_process` 兜底选门与 `night_changed` 信号选门同帧各跑一次（第二选择覆盖第一次，播报方位与实际出怪方位相反）——`_on_night_changed` 选门必须**幂等**（`_night_gate < 0` 才选）。回归 `tests/NightAssaultTest.tscn`（18 项，已入 CORE：白天出怪正控制 / 傍晚停刷 / 门几何与道路贴合 / 批量≥5 且全体锁主城带 siege 旗 / 平均距离 59.5→17.6 的推进 / 被小兵打转火 / 杀完恢复攻城 / 天亮清标记）。


## v20 · 小兵属性系统（六维 + 等级成长）

**v20 小兵属性系统（六维 + 等级成长）：** 用户需求「给小兵增加属性系统：等级（经验）/ 血量 / 攻击力 / 防御力 / 移动速度 / 暴击率，并按每个小兵种风格分配基础值」。六种小兵（兵营近战/远程 + 定居战士/法师/刺客/游侠）全部落地：① **Def 层**——`PawnDef` 新增 `defense / crit_rate / crit_multiplier / can_level`（血量/攻击/移速复用既有 `max_hp / attack_damage / move_speed`），基础值按风格分配：近战兵防最高（32 肉盾）、法师单发攻最高（20 玻璃大炮）、刺客暴击最高（32% 暴击流）、游侠腿最快（5.25 + 20% 暴击灵巧射手）、战士 24 防重装、远程兵后排脆皮；`can_level` 只对小兵开（主角有自己的成长线，村民/流民/野怪不升级）。② **等级/经验**——`level / xp / gain_xp / xp_to_next` 上移到 `Pawn` 基类（Hero 原字段删除、只覆写曲线 60/100/… 与 `_level_up` 固定成长 +30 血回满 / damage_mult，`_level_cap()` 覆写为不封顶）；小兵曲线 40/65/90…（每级 +25）封顶 Lv.10，击杀经验由 `Soldier._ready` 监听 `enemy_died`（最后一击归属 = `HealthComponent.last_attacker`，取被杀者 `def.xp_value`）。③ **升级成长**——`_apply_stats_for_level()` 统一从「基础值 × (1 + 成长率 × (level-1))」重算六维（血 +10%/攻 +8%/防 +10%/移速 +1.5%/暴击 +0.5% 绝对值、封顶 75%），出生 level=1 即基础值本身；成长血量差补进当前血；`EventBus.pawn_leveled` 广播 + 金色「升级！」飘字 + level_up 音效；血怒中的战士经 `PawnSkillComponent.notify_stats_rebased()` 重挂伤害基线（防怒气结束还原到旧面板）。④ **防御结算**——`HealthComponent.apply_damage` 在易伤放大后按宿主 `defense_factor()`（`DEFENSE_K=80`，受伤 × 80/(80+防御)）乘法减免，保底 1 点伤害防无敌；防御 0 的单位（主角/野怪/建筑/主城）与无该方法的宿主完全不受影响。⑤ **暴击结算**——`AttackerComponent._roll_crit()`（owner 是 Pawn 且 `crit_chance() > 0` 时按 `randf() < 暴击率` 掷骰 × `crit_multiplier`）：近战在 `try_attack` 即时放大，远程在 `_spawn_projectile_ex` 发射瞬间定伤并给 `Projectile.is_crit` 打标（命中时补橙红「暴击！」飘字；技能投射物如游侠快速射击同样吃暴击）；主角 `crit_stat` 恒 0 不受影响。⑥ **UI**——`SelectionInfoPanel` 单选小兵新增「等级 Lv.X · 经验 a/b（MAX 封顶）」+「攻击/防御/移速」+「暴击 P%（暴伤 ×N）」实时面板与 Lv 芯片；`HeroPanel` 小队成员行名字旁带 `·Lv.X`（0.25s 节流刷新）。回归 `tests/PawnStatsTest.tscn`（59 项，已入 CORE：数据契约风格分化 / 出生基础值 / 真实击杀链经验入账 / 升级六维曲线 + 连升封顶 / 防御减伤与 1 点保底 / 近战·远程暴击倍率 / 主角旧契约回归）。**坑**：测试里士兵与木桩**不能吸附进同一格**——叠点出生时双方 FightState 的环形站位相位（按 instance_id 取相位角）会让追击点互相漂移、5s 杀不掉；隔 4m 分格出生即稳定。**并行工作提示**：同版本号的「v20 夜潮攻城」（见上一条）与本属性系统同期落地，`HealthComponent` 同时携带两者的改动（`damaged` 信号 + `defense_factor` 减伤）。


## v21 · 删除兵营与募兵兵种

**v21 删除兵营与募兵兵种（当前形态）：** 用户定调「以后没有近战兵/远程兵了，兵营也删掉，所有小兵都通过流民转化而来」。① **建筑层**——`building_defs()` 移除兵营，`BuildingDef.is_barracks/train_list`、`TrainItemDef`、`Building` 的 `is_barracks/enqueue_train/train_progress/BarracksPickArea` 与死亡退款逻辑全删；建造菜单自动缩为 5 项（数字键 6 静默失效，`BuildSystem` 的 `idx < defs.size()` 守卫已兜住）。② **兵种层**——`GameDefs.soldier_melee_def/soldier_ranged_def` 与 `_train_item_*` 删除，`BUBBLE_LINES` 同步去掉两池；`SoldierMelee/SoldierRanged` 保留为「定居近战/远程职业的行为载体」（兜底 def 改战士/游侠），`VFXManager` 删两档攻击档案（走通用回退）。③ **信号层**——EventBus 删 `barracks_selected/barracks_train_changed/soldier_trained`；`HeroController` E 交互不再特判兵营（保留提示接口），HUD 删 `RecruitMenu` 装配，`SelectionInfoPanel` 删「可招募」芯片，`UIStyle.building_accent` 删兵营色。④ **内容层**——新手引导第 5 步「兵营募兵」改信息步「小兵从哪来？」（房屋吸引流民觉醒，无世界聚光，`TutorialOverlay` 的 barracks 选择器删除）；任务链 `build_barracks/train_soldiers` 换成 `build_farm`（开垦农田）与 `population_4`（人口到 4，`_alive_villagers()` 口径），收尾 `village_of_6` 文案去「募兵」；`TopBar` 人口胶囊 / `HeroPanel`、`PartyPanel` 空态文案同步。⑤ **测试层**——SceneValidation 的兵营端到端检查换成 `_check_barracks_removed`（数据/UI/等级参与三契约）+ 武器挂点对「无 handslot 的怪物模型」放行（并行线换了野怪模型）+ 击杀数断言改增量式；ThirdPersonTest 删 E 募兵段改「HUD 不残留 recruit_menu」；各测试的 `soldier_melee_def` 样本统一换定居职业 def；**PawnStatsTest 击杀链改用远程游侠**（近战击杀受环形站位相位漂移影响，脚本编译布局都会拨动它——v20 已实锤一次）；UiCapture 删 ui-recruit 帧、UiIconTest 面板清单去 RecruitMenu。**并行工作提示**：本改动与「v20 夜潮攻城 / 怪物模型替换」同窗口进行，共享文件（GameDefs/PawnModelRig/SceneValidation）以时间戳最新者为准互相让行。


## v20.2 · 小兵属性复审（v21+ 新形态适配）

**v20.2 小兵属性复审（v21+ 新形态适配，当前形态）：** 兵营删除、小兵=定居四职业、酒馆疗伤与夜潮重做落地后，对 v20 六维做一次数值评审与调优（`GameDefs.settler_*_def` + `Pawn` 成长常数）。**修掉的倒挂**：Lv.1 期望 DPS 原为 刺客 21.6 ≫ 战士 16.2 > 法师 12.4 > 游侠 11.1——肉盾比两个远程 carry 输出都高、玻璃大炮输出垫底；调整后 刺客 20.9 > 法师 16.8（+暴风雪 AoE）> 战士 13.7（血怒期 ~20.5）≈ 游侠 13.1，输出排序与角色身份一致。**基础值调整**：战士 HP 150→165 / 攻 15→14 / CD 1.0→1.1 / 防 24→28（EHP≈223 坦克位坐实）；法师攻 20→24 / CD 1.8→1.6（远程爆发 carry 兑现玻璃体质）；游侠攻 12→14；刺客 HP 95→90 / 暴击 32%→28%（仍单挑第一，不再全面碾压）。**防御拉开四档** 6/10/12/28（旧 5/8/10/24 中玻璃职业间差异 <4 个百分点、形同虚设）。**成长率上调**：HP +10%→+12%/级、攻 +8%→+10%/级、暴击 +0.5%→+1%/级（Lv.10 刺客 37% 暴击，成长有感）；移速/防御/XP 曲线（40/65/90…）/封顶 Lv.10/DEFENSE_K=80 维持——击杀经验仍按最后一击归属（「老练幸存者」叙事）。怪物档位（60/170/650 HP、8/14/24 攻）未动，酒馆 20/s 回血与防御减伤互补。**测试契约加固**：PawnStatsTest 成长断言从硬编码倍率改为读 `Pawn.GROWTH_*` 常量（后续调参不再需要同步改测试）；风格四断言（战士防最高/法师攻最高/刺客暴击最高/游侠腿最快）继续成立。**顺手修**：SoakTest 无游戏结束出口——主城被攻破后游戏暂停且不恢复，浸泡挂死到跑批 600s 超时（两次批处理 TIMEOUT 的真因，非 CPU 争用）；补 GAME_OVER 检测：记录终局后干净退出（浸泡目的是稳定性不是平衡断言）。**平衡观察（供 v22 线参考）**：无箭塔后夜防全靠 3~4 名定居小兵 + 被动主角，浸泡中主城 480 HP 在夜 1~2 后剩 240~360、偶发被攻破（随机夜门/职业/精英所致）——建议 v22 线考虑加强主城 HP 或酒馆/城墙防御联动。


## v20.3 · 怪物属性对应优化

**v20.3 怪物属性对应优化（当前形态）：** 与 v20.2 小兵六维复审配套，三档怪物接入六维并调档（`GameDefs.raider_*_def`）。**档位**：普通 HP 60→**70** / 攻 8→**9** / 防 **2** / XP 8→**10**；精英 HP 170→**190** / 防 **10**（−11%）/ 暴击 **10%** / XP 22→**25**；头目 HP 650→**750** / 攻 24→**26** / 防 **20**（−20%）/ 暴击 **15%** / XP 80→**90**（赏金属 v22 线未动）。**设计意图**：杂兵「量取胜」（单只扛 3~5 拍，原 2~4 拍即死）、精英中坚（需 2~3 人围殴，暴击重击制造酒馆治疗压力）、头目攻城兵器（战士单挑 ~8 击必倒、全队集火 ~13s、主角重击 ×0.8 仍是最优解）；**战士 28 防仍是全场防御标杆**（> 头目 20），小兵身份不倒。**夜潮节奏核算（关键平衡点）**：普通 70 HP ≈ 全队 6~8s 清一波 < 9s 波间隔——**浸泡实测 80 HP 会滚雪球必破主城（3/3），70 HP 为 2 存活 1 破城（被动防守刀口边缘、主动玩家稳赢）**；漏怪由 1000 HP 主城 + 城墙吸收。**UI**：`SelectionInfoPanel` 野怪分支与小兵面板同构（攻击/防御/移速/暴击，无经验行；头目加「死战不退」提示）。**测试契约**：木桩 helper 归零防御/暴击（怪物有六维后伤害断言须精确）；PawnStatsTest 新增怪物六维契约（防御/暴击/XP 三档递增 + 战士防 > 头目防）。


## v22 · 金币经济 + 酒馆疗伤 + 采集屏蔽

**v22 金币经济 + 酒馆疗伤 + 采集屏蔽（当前形态）：** 用户定调「删农田/市集/箭塔，新增酒馆（小兵回血，城外血量 <20% 优先回馆），建筑先用金币造价并暂时屏蔽采集，怪物掉金币要提升」。① **建筑表**——`building_defs()` 只剩 **木墙（10 金）/ 房屋（30 金）/ 酒馆（50 金）** 三种，造价纯金币（`SceneValidation._check_barracks_removed` 有 gold-only 断言）；`BuildingDef.is_turret/attack_*` 全删、新增 `is_tavern/heal_radius(6m)/heal_per_sec(20)`；酒馆模型 = KayKit `building_tavern_blue`（CC0，scale 3.4，见 medieval_hexagon_catalog 已导入表）。② **酒馆行为**——`Building._tavern_heal` 每帧给 `heal_radius` 内的 **Soldier** 回血（主角/流民不参与）；`Soldier.healing_trip`（`TAVERN_HEAL_THRESHOLD=0.2` 触发 / `TAVERN_EXIT_RATIO=0.95` 出院，滞回防抖）+ `SoldierIdleState._route_healing`（优先级在「主角小队跟随」之后、「索敌接战」之前）+ `FightState/RangedFightState` 开头低血脱战检查（**排在集火令之后**——v18「玩家直接命令最高优先」契约不破）；行程中 `Soldier.autofight_enabled()` 返回 false（赶路不被沿途野怪拉走）；`SoldierRestState.enter` 接受 `msg.at` 指定馆旁休整点（外推 2.6m 出 footprint）。无酒馆时低血回落旧「回城休整」行为。③ **采集屏蔽**——`GameDefs.HARVEST_INCOME_ENABLED=false` 总开关：`ResourceNode.harvest_by/harvest_carry` 返回 0（不入账/不耗储量/不发 `hero_harvested`），树/石退化为场景障碍；准星不再给资源「挥砍采集」提示；`starting_resources()` 只发 **150 金币**。④ **赏金提升**——掉落本就 100% 必掉（`CombatSystem` 每杀必生成 LootDrop），「提升概率」落实为赏金上调：普通 5→**10** / 精英 25→**45** / 头目 120→**200**（`MONSTER_BOUNTY` 同步 10）。⑤ **内容层**——任务链改金币主线（first_hunt 3 杀 → build_house×2 → settle×2 → **build_tavern** → population_4 → kill_raiders×10 → hero_level3 → village_of_6，奖励全金币）；新手引导第 3 步「亲手砍树」换「**讨伐第一只野怪**」（`enemy_died` killer 是 Hero/Soldier 即达成，`hero_harvested/resource_changed` 处理器与砍树镜头聚焦已删）；`UIStyle.building_accent` 去三色加 tavern 琥珀色；`SelectionInfoPanel` 酒馆显示「小兵疗伤 +20/s」芯片；图标库三方冻结表（fetch_icons.py/icons.json/UiIconTest）更新为 42 个（farm/market/barracks/turret 图标删、**building_tavern**=lorc/glass-shot 新增）。⑥ **测试**——新增 `tests/TavernHealTest.tscn`（23 项，已入 CORE：数据契约/光环速率对照/低血回馆全程/战斗脱战/无馆回落/爆币拆分总额）；ThirdPersonTest 砍伐段反转为「屏蔽采集契约」；SoakTest/PathBenchmark 布局换酒馆+墙。**顺手修**：LootDrop v21 爆币版缺 `_settle()`（FLY→REST 转换）导致全库 Parse Error 连坐 CombatSystem——已补。**遗留**：木/石/食物资源栏仍显示（恒 0 / 房屋菜园缓慢产出食物但无消耗方），采集经济玩法待重新设计。


## v23 · 金币「爆出」掉落

**v23 金币「爆出」掉落（当前形态）：** 用户需求「怪物死亡金币爆出来：抛物线 + 落地弹跳、距离不要太远；在地上停留一小会儿后自动吸附到玩家或附近最近的小兵；普通怪随机爆 1~3 份 / BOSS 多爆 5~8 份（总数值不变）；拾取时的缩小效果去掉」。`LootDrop` 重写为四阶段状态机：**DELAY（`spawn_delay` 错峰出场，喷泉感）→ FLY（重力抛物线 g=15，随机初速水平 1.1~2.3 / 竖直 3.0~4.4 m/s）→ REST（触地按 0.45/0.7 保留比反弹并随机偏转，弹不动了 `_settle()` **按姿态贴地 + 慢速自转**：飞行/弹跳触地面 `FLY_FLOOR_Y=0.28`（斜立最坏下沿 ≈0.26 不插地），停驻按圆柱几何 `h·|A_y|+r·√(1−A_y²)` 求当前姿态落差落到位（平躺贴得低、斜立站得高，0.1s 补落），并恢复落地慢转 1.6rad/s——`rotation.y += ` 是绕世界 Y 进动，轴倾角不变→下沿高度恒定不穿模（v23.1 用户反馈「躺平不行，要保留落地旋转与磁吸翻滚」）；停驻 `REST_DELAY=1.5s` 后才起吸）→ HOMING（12m 内找 Hero/Soldier，主角距离 ×0.75 优先；逐币随机吸附加速 30~46、极速 16 m/s「越吸越快」，距胸口 0.7m 结算；目标半路死亡回 REST 重扫）**；落地后 **1.5s 硬保护窗口**：FLY 不结算、REST 未停满前贴身直捡也不结算（v23.2 用户要求「必须看到 1.5s 动画，不能刚掉下来就被吃」），停满后 2.2m 贴身直捡 + 磁吸恢复，25s 无认领超时释放。份数拆分在 `CombatSystem._split_bounty`（向下均分 + 余数逐份 +1，总额精确不变；份数钳 ≤ 金额数），普通 `randi_range(1,3)` / 头目 `randi_range(5,8)`。**拾取结算 = 入账 + coin 音效 + 「+N 金币」飘字 + 立即 `queue_free`——旧「缩小淡出」动画删除**（根节点 scale 全程恒 1，仅视觉子件出场时弹入；缩放随机 0.85~1.15 更有机）。金币无物理体（纯数学积分，不存在卡墙/物理抖动）。回归 `tests/LootBurstTest.tscn`（32 项，已入 CORE：拆分总额 / 普通 1~3 份 / 头目 5~8 份 / 抛物线峰值 0.55~1.35m + 停驻贴地下沿 0~0.06（`bottom_height()` 防穿模契约，带姿态斜立）+ 散布 ≤3.0m / 主角站立 6m 磁吸入账精确 + 结算时刻 ≥2.17s（证明停满 1.5s 才起吸）/ **硬保护窗口：主角站金币堆上 1s 不被吃、停满后才结算且不早于 1.8s** / 根 scale 恒 1 / 村民不抢金币·小兵到场即吸）；BossNightTest 掉落断言改「头目附近 5~8 份且总额 ≥100」（单份 ≥100 契约随拆分作废）。样张 `artifacts/v23-loot-{burst,magnet}.png`（`godot --path . tools/loot_shot.tscn`：爆发期金币腾空 + 磁吸期金币列队飞向主角）。**测试坑**：12m 磁吸半径会让「前序小节遗留币」被后序主角/小兵顺手吸走、污染金额断言——分节之间必须 `_clear_loot()` 清场；击杀位离主角 ≤2.2m 会被贴身直捡路径提前收走，磁吸场景要放 6m。


## v25 · 入住选职业 + 市民管理 + 转职 + 技能树

**v25 入住选职业 + 市民管理 + 转职 + 技能树（当前形态）：** 用户三条需求一次落地：① **流民入住选职业**——流民抵房后不再随机觉醒：`SettlementSystem._on_refugee_arrived` 发 `settle_class_choice_required`，HUD 的 `SettleClassPicker`（分组 `settle_class_picker`）真暂停弹四职业卡（字徽/三维/技能名），玩家点选后经 `settle_class_chosen` 回系统完成转化（`_settle_refugee(refugee, home, class_id)`）；**多人同时抵达按队列逐个处理；`_choose` 先收起恢复倍速再 emit**（否则紧随的入驻提示会把「弹窗期 0 倍速」记成原始倍速）；无弹窗环境（无头测试无 HUD）回落随机职业。② **市民管理**——`PartyPanel` 类删除，升级为 `CitizenPanel`（**HUD 变量名/节点名/分组仍叫 `party_panel`**，`open/close/is_open/_count_label` API 兼容，SceneValidation/v10_squad_shot 零改动）：出战编队 4 槽（点击移出）+ 主角行（等级/血量/技能点/技能树入口）+ 城镇市民全表（含在队标 `［在队］`、等级/职业/血量/攻防/技能点、加入/移出编队按钮）；右上新增**独立入口按钮**（右侧 y352~390 空档：选中面板底 344 与小地图顶 440 之间，UiCapture 式零重叠断言在 CitizenManageTest）。③ **转职**——`PawnDef.promotes_to` 声明进阶路线（基础四职业各 2 条，进阶 def `promotes_to` 空 = 不可再转）：战士→**狂战士/骑士**、法师→**元素法师/雷电法师**、游侠→**狙击手/漫游射手**、刺客→**暗杀者/忍者**（`GameDefs.settler_advanced_def`，数值为基础职业风格化微调，模型沿用、字徽/配色/染色区分）；`Soldier.promote_to(adv_id)`（`GameDefs.PROMOTE_LEVEL=5` 门槛）：**保留姓名/等级/经验/技能树/血量比例**，六维与攻击参数按新 def 重算，`skill_comp.skill` 同步换新数值并重挂血怒基线，`soldier_promoted` 广播。④ **技能树**——`SkillNodeDef/SkillTreeDef`（分支/级数/前置/每级收益全数据驱动）+ `PawnSkillTree`（RefCounted 运行时：ranks/invest/前置与满级拦截/累计加成）+ `Pawn.skill_points`（**每次升级 +1**，主角与小兵两条升级线都发）+ `Pawn.try_invest_skill_point`（扣点→加级→`_rebase_stats_for_tree` 面板重算+血量差补入+血怒基线重挂）；`PawnDef.skill_tree_id` 非空才建树（主角+定居四职业含进阶；村民/流民/野怪无）。**通用树 `&"generic"`**：分支一「伤害强化」5 级每级 +5% 攻击、分支二「生命强化」5 级每级 +6% 生命（**需伤害 ≥1 级**——前置框架示范，后续设计就绪在 `generic_skill_tree_def` 扩节点即可，UI 数据驱动无需改）。**生效乘区**：小兵 `_apply_stats_for_level` 攻/血再乘 `(1+树加成)`（未加点=1× 不动旧数值契约）；主角 `damage_mult() = 1+0.12×(lv-1)+树攻击加成`（**加算不是乘算**），生命上限抽出 `_max_hp_formula() = (320+30×(lv-1))×(1+树生命加成)` 供升级与加点两路共用。`SkillTreePanel`（分组 `skill_tree_panel`，挂 HUD 最顶层）从市民管理行内「技能树」按钮进入，Esc/V 关闭回到仍开着的市民管理；Esc 优先级链扩为 **技能树 > 市民管理 > PauseMenu**（各自 `_unhandled_input` 消费 + PauseMenu 防御性放行 + Main 的 V 键对技能树让位）。回归 `tests/CitizenManageTest.tscn`（112 项，已入 CORE：数据契约/入住选择全链路/转职门槛与保留项/两分支加点与拦截/主角公式/界面开合与入口按钮零重叠）；**SoakTest 必须自动点选职业**（`_on_soak_settle_choice` 轮换四职业——否则第一个流民就把浸泡冻在弹窗上）；SceneValidation 定居段改「等弹窗→模拟点战士→断言所选职业生效」。**坑**：① GDScript 里给 Button 当行容器时嵌套子按钮会误触——市民行改用 `PanelContainer` 浅色卡 + 独立小按钮（编队/技能树/转职互不干扰）。② **模态面板根节点 `set_anchors_preset(PRESET_FULL_RECT)` 在父级（HUD root）已布局时会按当前 0×0 rect 回推 offsets（得到 -width 的 offset_right）→ 面板永远 0×0、`visible=true` 却什么都不画**（旧 PartyPanel 同病，只是旧测试只断言逻辑不截图没暴露）；修法 = preset 后**显式清零四个 offset**（`_dim`/内嵌行同理，准星同款坑的完整版）。像素验证走 `tools/v25_citizen_shot.tscn` 三张样张（四职业卡配色 / 市民行 / 树面板 pip 点亮都要在图上可见——逻辑断言查不出 0×0）。


## v25.1 · 技能树树状化 + 职业技根节点 + 加点崩溃修复

**v25.1 技能树树状化 + 职业技根节点 + 加点崩溃修复（当前形态）：** 用户两条反馈：① **点「加点」崩游戏**——根因：加点按钮 `pressed` 回调里 `try_invest_skill_point` → `skill_tree_changed` → `_refresh` 同步 `remove_child+free` **正在发信号的按钮本体**（Godot 报 "freed while a signal is being emitted" 并可能硬崩）；修法 = SkillTreePanel 的信号驱动刷新一律 **`call_deferred("_refresh")`**（推迟到信号发射完毕后再重建）。② **技能树要长成树 + 第一个节点是各职业现有技能**——树布局改为「根 → 分支」链：根节点「职业技」= 该职业现在的主动技能（战士 血怒 / 法师 暴风雪 / 游侠 快速射击 / 刺客 背刺；**进阶职业改名如雷电法师「雷暴」自动跟随 `def.skill` 显示**），**点亮（1 点）后才可在战斗中施放**（`Pawn.try_cast_combat_skill` 门禁读 `PawnSkillTree.skill_unlocked()`；`Pawn.combat_skill_unlocked()` 供 UI/测试查询；主角走 Q/C 管线不经此门禁，其树根 `pre_unlocked` 预点亮只作树根）→「伤害强化」5 级（前置：职业技）→「生命强化」5 级（前置：伤害 1 级）。数据层：`SkillNodeDef.unlocks_skill/pre_unlocked` + `SkillTreeDef.gate_node_id/node_depth()/max_depth()`；`PawnSkillTree.apply_pre_unlocks()` 在建树时点亮预解锁节点。UI 层：SkillTreePanel 按**节点深度分列**（根 0 / 伤害 1 / 生命 2），父子之间由 `TreeConnectors`（内部类，垫底 Control）画**连线 + 箭头**（前置满足=金色 / 未满足=灰色，draw 时实时取卡片位置，布局变化自动跟随）；根卡按钮文案「点亮」、预解锁显示「已随职业解锁」。**契约变化**：新兵出生技能锁定（首点通常 Lv.2 到手）——SettlerSkillTest 四个出生点后统一 `_unlock_class_skill()`（发 1 点点亮，不升级、六维不动）；CitizenManageTest 加「未解锁不可施放 / damage 分支被根锁 / 点亮后解锁」断言；SelectionInfoPanel 技能行显示「未解锁（技能树点亮）」。


## v25.2 · 技能树 UI 全面美化

**v25.2 技能树 UI 全面美化（当前形态）：** 针对「技能树 UI 很奇怪、不好看」的全面改版（只动 `scripts/ui/SkillTreePanel.gd` 与样张工具，数据 / 运行时 / 测试契约零变化——`is_open`/`pawn`/`open_for`/`close`/Esc 链 /「加点」按钮文本契约原样，CitizenManageTest 112 项不改编译即全绿）。① **节点卡竖版化 + 四态视觉**：圆纹章徽座（`Medallion` 内部类：IconBadge 外套发光环，已点亮常亮 / 可加点呼吸闪烁——真实时间驱动，暂停中界面依然有生命感 / 未解锁灰化 + 右下角纯 draw 小锁印）、节点名+级数、效果说明、**当前累计收益行**（属性节点显示「攻击 +10%」等实时数值，职业技节点显示「主动技已就绪 / 战斗中无法施放」）、pip 条（下一级落点亮金框提示）；卡片 StyleBoxFlat 按 **已满级（金框+金色投影）/ 可加点（节点色 2px 框+彩色投影）/ 已投入（常态）/ 未解锁（暗化）** 分态；满级 / 预解锁节点不再渲染按钮，改「★ 已满级 / ✦ 已点亮 / 已随职业解锁」金字徽标（测试按 Button 文本收集「加点」，标签替代按钮不影响）。② **连线修复 + 升级**：v25.1 的 `TreeConnectors` 只在 `queue_redraw()` 时画一次，此时容器排版未定稿 → **连线悬空错位**（v25 样张实锤）；修法 = 面板 `_process`（仅 `is_open and visible`）每帧 `queue_redraw()`，draw 时实时取卡片全局矩形——布局变化永远跟随。视觉升级为**水平切线三次贝塞尔**（控制点在两点水平中线上）+ 双层描（宽辉光 + 亮芯）+ 子端箭头 + **已点亮路径上两颗沿曲线流动的光点**，颜色取子节点主题色（伤害橙 / 生命绿）。③ **树区背景纹章**：`TreeBackdrop` 内部类画中心柔光（三层递减圆叠出径向渐变感）+ 两圈同心圆环 + 外环 8 颗菱形星点（低透明暗金，衬托而非抢戏）。④ **头部信息条**：职业纹章（def.class_icon/class_color，主角金色「英」）+ 姓名（display 字体）+「职业 · Lv」副行 + **技能点胶囊**（chip_style + xp 图标，有点数蓝色 / 无点数灰化）+ **已生效加成汇总行**（RichTextLabel bbcode 上色「攻击伤害 +10% · 生命上限 +6%」，实时读运行时树；未加点显示引导文案）。⑤ **底栏**：操作提示（左）+ 关闭按钮（右），`_note_label` 固定 18px 占位防整版跳动。**坑**：`Medallion` 的 IconBadge 子件默认停在 (0,0)，圆盘与外环错位成月牙——`_ready` 挂 `resized` 把徽章钉在 `((size - badge_min) * 0.5)`；`PRESET_CENTER` 在未布局时按 0×0 rect 回推 offsets 会把徽章缩成 0（同模态面板 0×0 坑）。样张 `tools/v25_citizen_shot.tscn` 新增第 4 张 `artifacts/v25-skill-tree-locked.png`（Lv.2 刺客带余点：根节点可点亮呼吸态 + 后续两节点前置锁定 + 锁印对照），`artifacts/v25-skill-tree.png` 为已投入形态。


## v26 · 动画 ↔ 特效同步

**v26 动画 ↔ 特效同步（当前形态）：** 针对「一些特效跟动作不匹配」的专项审计与修复（审计事实：把 5 个人形 GLB + 8 个怪物 GLB 的全部动画名/时长倒出来逐一对照调用点，见 `tools/v26_anim_sync_shot.tscn` 样张 `artifacts/v26-anim-vfx-sync.png`）。① **职业动作匹配（per-def `anim_map`）**：战士双手斧走 `2H_Melee_Attack_Slice`（旧版播 1H 单手剑动作）、刺客走 `Dualwield_Melee_Attack_Slice`、法师法弹走 `Spellcast_Shoot` / 暴风雪走 `Spellcast_Raise`、游侠手弩走 `1H_Ranged_Shoot`；`ANIM_CANDIDATES` 新增项目 key：`shoot`（射击）/ `cast`（站桩施法，战士血怒经 anim_map 覆盖为 `Cheer` 举臂咆哮）/ `stab`（刺客背刺直刺）/ `hit`（受击，**GreenBlob/Yeti 的受击动画资源拼写是 `HitRecieve`**，候选必须带上；`Bite_Front` 只有 GreenBlob/Yeti 有——它们没有 Punch/Run，不能当死候选删）。② **`PawnModelRig.play` 三条播放规则**（动画↔出招同步的核心）：(a) **单次动画显式重播**——Godot 4 对播放中的同名动画再调 `play()` 并不会重播（实测 position 继续前进），必须 `play()` 后 `seek(0, true)`，旧注释「单次类每次都重播」与实际行为不符，导致攻击动画相位与出招事件脱节；(b) **循环动画让位**——单次动画（攻击/施法/受击/死亡）播放中，每帧 `play(idle/run)` 的循环请求被忽略，否则受击/出招动作一帧就被状态机盖掉；`animation_finished` 播完自动回落 `_last_loop_key`（死亡除外），站定单位不再定格在收招姿势、风筝射击后不再吞掉跑步循环；(c) **攻速匹配**——挥击类（fight/shoot/stab）按 `PawnDef.attack_anim_speed` 倍速播放（刺客 1.17s 动画 ÷ 0.55s 攻击间隔 ≈ ×1.9），动作节奏跟上出招节奏。③ **状态机接线**：`RangedFightState` 出手即 `play(&"shoot")`（旧版只在 enter 播一次近战挥砍——接敌前空挥一刀、真正射击反而无动作），档1 冷却期播 idle、档2 风筝播 run；`FightState` 站定冷却期播 idle；`PawnSkillComponent` 暴风雪→cast、血怒→cast、快速射击→shoot（起手一次，0.14s 连发不逐箭重启）、背刺→stab。④ **受击反馈**：`HealthComponent.damaged` → `Pawn._on_damaged_hit_react`（0.5s 节流、死亡外、仅循环动画时插播 `hit`，不打断攻击/施法）。⑤ **特效档案纠偏（`VFXManager.attack_profile`）**：野怪三档 `arc=&""`（兽爪 Punch/Bite_Front/Headbutt 不再扫出人形剑光弧，命中火花保留）；法师 `muzzle=&""`（法杖弹不吃火枪口十字星）；`muzzle_height` 1.25→1.05 与弹体出手高度 `Projectile.SOURCE_HEIGHT=1.0` 对齐；新增 `cast_dist/cast_height`（法师微光落在举起的杖头 1.5m）。⑥ **主角旋风斩同步**：`skill_aoe` 动画改 `2H_Melee_Attack_Spinning` 并入 `LOOP_KEYS`（旧版 `Spin` 完整版 2.4s 远超 1.0s 技能时长播不完），旋风刀光距离改 `radius*0.58` 贴合 3.6m 伤害圈。**回归** `tests/AnimVfxSyncTest.tscn`（26 项已入 CORE：per-def 动画解析 / 档案类型 / 同名重播 / 循环让位+播完回落 / 攻速倍率 / 游侠实机出手即上射击动作+枪口闪光同帧 / 受击插播 Hit_A 后回落）。**注意**：`try_attack` 伤害保持同步结算（PawnStatsTest 直接断言调用后 HP 差），动画接触帧对齐留待正式美术通道。并行线提示：本改动与龙宠物线同窗口共抢 `VFXManager/AttackerComponent/HeroSkillState/GameDefs`，以时间戳新者为准互相让行。


## v26 · 驯龙系统

**v26 驯龙系统（当前形态，与 v26 动画同步线同窗口并行）：** 用户需求「龙园新建筑（比其他建筑占地大、E 交互弹界面花金币解锁龙）、龙的模型用像黑龙的那条单独模型、小队 4 队员之外额外带一只龙上场、龙一直跟着玩家、玩家打谁他打谁（小队宠物定位、后续可扩新龙）、普攻朝目标吐火球爆炸小片 AOE、技能原地朝目标方向吐火 2 秒 40° 锥形长距伤害」。① **数据层**——新 Def 类 `DragonDef extends PawnDef`（unlock_cost / fireball_* / splash_* / breath_* / description / skill_desc）；`GameDefs.dragon_defs()` 数据驱动（新龙加表即全链路自动接入），首龙「黑曜龙」= bocdagla `Dragon2.glb` 四足带翼龙（落位 `assets/_PLACEHOLDER/dragons/` + CREDITS 授权记录）；建筑表新增 **龙园（`dragon_garden`，120 金，footprint 3×3 全场最大 > 2×2，`BuildingDef.is_dragon_garden`，模型复用闲置的原兵营大厅 scale 3.2）**。② **实体层**——`DragonPet extends Pawn` 三专属状态（`DragonFollowState` 贴身跟随主角身后偏右、远距 1.5× 追赶 / `DragonFightState` 每帧轮询主角目标**同步转火**、主角停手或跑远即收手回队 / `DragonBreathState` 起手锁向原地喷火 2s）；**宠物定位绝不自主索敌**（is_auto_fighter=false + autofight 覆写），目标来源 `Hero.live_pet_target()`（集火令 T 优先 > `Hero.attack_target` 保鲜 2.5s，由 `apply_damage_to` 最近目标 + `AttackerComponent.try_attack` 通用 hook 写入——「玩家打谁龙打谁」）；**普攻火球** = `DragonPet.spawn_fireball()` 配置 `Projectile`（visual_kind=1 橙色发光球 + 新 `fire_trail` 尾焰 / `fire_burst` 爆炎，`splash_radius/splash_damage/splash_group/splash_effect` 溅射字段——直击目标只吃直击伤、圈内其余敌人吃溅射）；**烈焰吐息** = 40° 全角（half_arc 20°）/ 14m / 2.0s / 0.4s×9 跳 / CD 12s，锥形几何收口 `DragonPet.enemies_in_breath_cone()`（与 Hero.acquire_enemies_in_arc 同款 XZ 口径），视觉 = 嘴部锥形火舌粒子（局部 -Z 喷射、随龙转向）+ 逐跳火星环。③ **系统层**——`DragonSystem`（WorldRoot 子节点、分组 `dragon_system`）：金币解锁（需龙园、足额扣款、**解锁即自动出战**）→ `PawnSpawner.spawn_dragon` 主角身后生成；同一时刻仅一条出战；**阵亡 25s 自动在主角身边复苏**（宠物不死机制）；EventBus 新增 `dragon_menu_requested / dragon_unlocked / dragon_deploy_changed`。④ **交互 / UI**——`HeroController` 准星提示「龙园 · [E] 驯龙」+ `_try_interact` 发信号打开 **`DragonMenu`**（真暂停模态：每龙一张卡——解锁价 / 出战 / 召回 / 复苏倒计时；Esc 链入 PauseMenu 让位序列）；**小队配置界面（CitizenPanel）新增「出战巨龙」区**（编外第 5 位：未建龙园引导 / 未驯服提示 / 出战·召回按钮 + 状态）；HeroPanel 小队行末追加龙行（紫字「出战」态 + 血条）。⑤ **顺手**——`PawnDef.hud_head_height`（血条高度显式覆盖，供 AABB 严重失准的模型；龙 AABB 高 10.45 vs 实渲 5.68，自动量测会把血条顶到半空，龙定 3.4）；龙 `anim_map` **必须写候选数组**（Godot glTF 导入器会剥 `_loop` 后缀：GLB 原名 `Idle_loop/Walk_menacing_loop` → 导入后 `Idle/Walk_menacing`，单名字会静默落空）。**回归** `tests/DragonPetTest.tscn`（46 项已入 CORE：数据契约 / E 交互链路 / 金币门禁 / 出战实体契约（不占 4 槽·anim_map·血条高度）/ 跟随 / 目标同步+转火+过期回队 / 吐息几何直测+状态机+CD / 阵亡复苏 / 三处 UI）；TavernHealTest 建筑表契约 3→4。样张 `artifacts/v26-dragon-{follow,garden,breath}.png`（`tools/dragon_shot.tscn`；火焰可见性用「隐藏火舌前后帧差分」客观校验：差分 4.1% 屏幕像素、近半为暖色）。**并行线提示**：与 v26 动画同步线共抢 `VFXManager/AttackerComponent/GameDefs`，已互相让行、全量 CORE 25 套全绿。


## v27 · 特效品质与丰富度

**v27 特效品质与丰富度（当前形态）：** 针对「提升特效品质/质量 + 效果丰富度」的一轮全面升级（只动表现层，战斗数值与既有测试契约零变化）。① **shader 品质升级**：`vfx_arc.gdshader` 新增 `core_white`（刃口白热——高光中心向白偏移，层次 = 白热刃口 → 主题色刀身 → 透明）与 `streaks`（沿弧长随 progress 流动的细密亮纹，速度感）；`vfx_billboard.gdshader` 新增 `spin`（贴图随生命周期旋转——星芒/闪光会转，环带因对称无感）与 `ring_fill`（空心环内侧柔光填充，冲击环不再是孤线）。**穿透变体**：`vfx_billboard_overlay.gdshader`（同款 + `depth_test_disabled`）——`EffectDef.no_depth_test` 此前**从未接到 shader 材质上**（只写了字段没消费，「人堆里也要看得见」是假的），`_billboard_material` 现按该字段选用变体，StandardMaterial3D 兜底路径同步 `fb.no_depth_test`；缓存键含 effect_id，同一特效的 shader 选择天然确定。② **程序化纹理重绘**：star=主十字 + 45° 短芒 + 白热核心三层合成；glow=小半径高亮核心 + 大半径柔晕双曲线；ring=外亮细环（冲击波前）+ 内柔宽环（气浪余韵）双带。③ **粒子色阶**：全局 Gradient 加 0.04 白热起点（爆开瞬间先白一下再回主题色），hit_spark/magic_burst/fire_burst 等全部受益。④ **丰富度——七个缺失时刻全部补上特效**（新 id 均注册于 `_register_defaults`）：`crit_burst`（近战 `AttackerComponent._emit_crit_feedback` / 远程 `Projectile._impact` is_crit 分支——金色星芒旋开，暴击从「一行字」变「一次闪光」）；`death_wisp`（`DeadState` 敌方 enter——青白魂魄上飘，与 v16 溶解衔接「先出魂再消散」）；`levelup_ring` + `levelup_spark`（`Pawn._level_up` / `Hero._level_up`——金环上浮 + 金屑升腾）；`heal_mote`（`Building._tavern_heal`——正在回血的士兵身上冒绿色荧光，throttle 1.2s/人、满血不冒，PRIORITY_HIT 环境类可丢）；`build_dust`（`BuildSystem` 落成 + `Building` 倒塌——尘土 + 暗金环，替换旧 hit_burst）；`coin_sparkle`（`LootDrop._collect`——入袋星屑）；`sprint_dust`（`HeroIdleState` 超速移动脚下扬尘，0.22s 节流）。⑤ **预算**：`MAX_ACTIVE_EFFECTS` 24→30（丰富度特效并发更多，命中类优先丢弃的保护不变）；`muzzle_flash` spin 150°（击发瞬间十字星旋开）。**回归**：AnimVfxSyncTest 扩到 30 项（强制近战暴击出星芒 / 升级出金环金屑 / 敌方死亡出魂魄 / 四个新 id 注册可生成——注意测试里冻结的单位状态机不走、死亡魂魄要用未冻结木桩验）；CombatVfxTest 溢出探针 30→40（预算扩容后 30 次不再溢出）。样张 `artifacts/v27-vfx-quality.png`（`tools/v27_vfx_quality_shot.tscn`：暴击星芒 / 升级金环 / 治疗荧光 / 死亡魂魄 / 建造尘环同框；**摆位铁律：billboard 会被前景身体遮挡，特效点必须让到单位身侧/上方，且先冻结摆位再触发特效**）；`tools/v27_probe.tscn` 为单特效渲染隔离探针（暗背景逐枚验证 shader）。**坑**：`AnimationPlayer.pause()` 会清空 `current_animation`（定格姿态用 `speed_scale = 0.0`）；`godot --headless --path . xxx.gd` 把脚本当场景跑会静默挂死（脚本必须经 .tscn 场景承载）。


## v28 · 战斗打击感

**v28 战斗打击感（当前形态，战斗特效专项）：** 在 v27 品质底座上专攻「打击感」——命中反馈从**对称爆开**升级为**有方向的打击**。① **定向火星喷溅**：新 def `hit_spark_cone`（38° 窄锥、local_coords=true、重力下坠）——`spawn_hit_impact` 新增可选参数 `dir_yaw`（「攻击者 → 目标」水平角，NAN 缺省保持旧行为），传入时额外喷一束从命中点向外喷的火星锥；`EffectDef` 新增 `local_coords` 字段（`_build_particles` 尊重之——局部坐标下旋转节点即旋转喷射方向，一次性爆点在固定位置不受影响）。接线：近战 `AttackerComponent._spawn_melee_vfx`（注意 `rot_y` 原声明在弧光分支块内、野怪无弧光时未定义——改为函数顶部按「攻击者→目标」算 `hit_yaw`）/ 弹体 `Projectile._impact`（沿弹道方向）/ 主角连招 `_apply_hit` / 冲锋扫掠 / **旋风斩逐跳**（旧版只有伤害数字没有任何命中表现）。② **命中白闪**：`impact_flash`（白色微光 0.12s）——每次定向命中在命中点同帧炸一记白闪。③ **重击落地震波**：`heavy_shock`（金白大环 2.8m）——主角第 3 段（收招段）落地时脚下炸一圈。④ **背刺交叉双匕弧**：`PawnSkillComponent` 背刺补第二道反向扫动的 `dagger_arc`（spin +1，偏 0.35rad），双匕首「剪」的读感。**回归**：AnimVfxSyncTest 扩到 33 项（带 yaw 的命中出锥+白闪 / 主角重击出震波——重击带 0.12s 前摇须轮询等 active 帧而非固定等 2 帧）。样张 `artifacts/v28-combat-feel.png`（`tools/v28_combat_shot.tscn`：暴击重劈的斧光+星芒+定向喷溅+白闪 / 背刺交叉弧+青白喷溅 / 落地震波同框）；`tools/v28_cone_probe.tscn` 为喷射方向验证探针（两束锥相向喷、截图延迟到 0.33s 读方向）。**大坑**：`one_shot` 粒子的 `lifetime` 同时是**发射时长**——截图/展示时给粒子传大 `lifetime`（如 3s）会把 12 颗火星摊成几秒慢慢吐、画面里只剩一两颗（v27 样张里治疗荧光/建造尘土偏淡的根因）；粒子类不给寿命覆盖，网格类（billboard/刀光）可安全覆盖定格。**顺手硬化（FollowState 站定滑移门槛）**：站定分支的「被动滑移」原门槛为 0（只要有分离力就滑），slot 间距落在分离力死区之上的残余微推力会让成员以 ~0.03-0.05 m/s 持续蹭开——「主角原地转身零踱步」契约间歇性踩爆（普通时序 0.030-0.100m 波动、`--fixed-fps 60` 批处理环境恒 0.100）；现设 0.35 m/s 最小推力门槛，低于直接吞掉、真实重叠（队友叠进来）的大推力照常滑开。普通时序改善至 0.000-0.030m 且三连跑稳定；**遗留**：`--fixed-fps 60` 下该测试仍恒 0.100m（来源是 fixed-fps 下成员在 slot 附近的 seek 微振荡，与门槛无关、与本线改动无关——该测试在本线改动前的批次就曾 0.050 失败），属 v18 跟随域的既有敏感项，留待跟随逻辑专项处理。


## v29 · 巨龙系统优化

**v29 巨龙系统优化（当前形态，四个真机问题一次收敛）：** 用户反馈「龙本身的效果、跟随、朝向都很奇怪」——逐条实测定位到四个**根因**（都不是「调参能救」的观感问题），并各留一条硬回归：

① **描边副本缺 Skin → 巨大绿色幽灵（最严重）**：`PawnModelRig._collect_outlines`（v10 反转外壳描边：队伍绿标 / 瞄准红标 / 集火标记共用）只拷了 `mesh` + `skeleton` 路径，**没拷 `MeshInstance3D.skin`**——glTF 蒙皮的 `inverseBindMatrices` 存在 Skin 资源里，缺了它描边副本会按「绑定姿 + 骨骼空间」渲染：对骨骼带缩放补偿的龙（`Armature_001` scale 1.668）就是**一只比本体大 2~3 倍、张翼悬浮的巨型绿龙盖在龙身上**（v26 样张里那团绿影就是它，人形模型恰好 inverseBind≈单位阵所以一直没暴露）。修法一行 `dup.skin = mi.skin`，A/B 样张 `artifacts/v29-outline-ab-{a_skin,b_noskin}.png` 肉眼可判。**同时**队伍脚圈改按体型（`PawnDef.squad_ring_radius`，龙 1.25m；旧值 0.42 的圈被龙身整个盖住 = 没有队伍标）。

② **跟随站位压在相机视线走廊正中央**：旧槽位「主角身后 2.6m + 右 1.8m」正好落在第三人称「枢轴 → 相机（正后方 5.2m）」的连线上，3m 级的龙把整个画面糊死（v26 follow 样张实锤）。改为**右侧 3.2m + 身后 1.0m**（侧翼可见、不挡镜头），并抄 v18 的两条成熟做法：**队形朝向取「主角朝向」而非移动方向**（第三人称下视线走廊 = 主角朝向；用移动方向时主角贴树拐个弯龙就漂到正后方）+ **站定冻结休整位**（`_rest_pos`，主角偏离锚点 `REST_RELEASE_DIST=1.0m` 才重排）+ 到位滞回（`SETTLE_DIST=1.1` / 滞回 0.8）。追赶改**比例式**（`speed_multiplier = 1 + 落后量×0.30`，上限 2.0）——旧的「超 6.5m 才 1.6×」开关式在阈值附近一冲一停。实机量测（`tools/v29_dragon_shot.tscn`）：行军/站定侧向恒 **+3.20m**、龙屏幕偏心距准星 **294~349px**（不再压准星）、站定 2s 漂移 **0.000m**。

③ **出膛点与朝向**：`MOUTH_HEIGHT` 旧值 2.1m 是「人形胸口高度」的想当然——骨骼实测（`bone Head/Head.Tip` 世界坐标）四足龙的头只有 **1.43m / 吻尖 1.26m、前伸 1.40m**，于是火球、火舌、枪口火光全部从**龙头上方 0.7m 的空中凭空出现**。改 `MOUTH_HEIGHT=1.35 / MOUTH_FORWARD=1.35` + `DragonPet.look_at_target` 覆写为**限速转身**（3 rad/s；大体重单位不瞬移，同时修掉「rotation 当帧写、`facing_dir()` 读到旧值 → 火球从身侧横喷」）+ `DragonFightState` 加 **18° 对准门槛**（没转到位不出膛，站着瞄准而不是边转边吐）。

④ **吐息「白色大方块」**：旧实现是**无贴图的 0.34m QuadMesh + 加法混合**，近看就是几片边缘生硬的白方块。重做为**四层**（`flame_05` 火舌主体 alpha 混合 + 白热芯加法 + 余烟 + 带重力火星，`mat.flatness=0.6~0.72` 把喷射锥压扁以贴合 XZ 扇形伤害口径——不压扁近半粒子会甩到半空像「一串火苗飘着」），并加 **0.28s 起手转身**（对准后锁向再喷，喷吐期间不转向）。**顺带挖出一个全局特效 bug**：贴图角色 `flame` 按文件名排序命中的是 `flame_03`（**暗色**烟状贴图），加法混合下几乎不可见——`fire_trail` / `fire_burst`（龙的火球拖尾与爆炎）一直被它拖成灰雾；新增 `fire` 角色（认领最亮的 `flame_05`）并接给两者，`flame` 保持旧语义不动其它调用方（`VFXManager.texture_for_role()` 同时公开给「手工搭粒子层」的调用方复用）。

**回归**：`tests/DragonPetTest.tscn` 新增 I 节 14 项（描边副本带 Skin/同骨架、侧翼站位 side>2m 且 dominant、站定 2s 漂移<0.35m、嘴部高度 0.9~1.8m、火球出膛 = 嘴部坐标（±0.6m）、一帧转角 <60°、朝向误差口径、脚圈 ≥1.0m、非 Pawn leader 不刷错）——**注意 `"projectiles"` 分组挂的是 Main 的容器节点，弹体是它的子节点**（测试里查飞行中的弹体要读 `container.get_children()`，直接 `get_nodes_in_group("projectiles")` 会拿到容器本身）。探针/样张：`tools/v29_dragon_shot.tscn`（实机第三人称四张：跟随/吐息/火球/绿标 + 打印侧向/后方偏移与屏幕偏心距）、`tools/v29_dragon_probe.tscn`（固定机位 + 骨骼朝向/嘴部高度/AABB 客观量测）、`tools/v29_breath_probe.tscn`（吐息四层隔离 + 火球飞行/命中）、`tools/v29_outline_ab.tscn`（描边 Skin A/B）。**观察（未在本线处理）**：`glow` 贴图角色按同样规则命中 `scorch_02`（暗色焦痕），`heal_mote`/`coin_sparkle`/`build_dust`/各类 trail 等加法特效实际都偏淡——若要统一提亮，改 `TEX_KEYWORDS[&"glow"]` 的候选即可（会影响面较广，需重跑像素类回归）。


## v30 · 巨龙卡通火焰

**v30 巨龙卡通火焰（当前形态，龙特效品质专项）：** 针对「吐火球和吐息都要酷炫一个档次，制作新贴图模拟卡通火焰」的全面升级（伤害数值与既有契约零变化）。① **自制卡通火焰贴图**：`tools/make_toon_fire_textures.gd`（Godot Image API 程序化绘制，512 绘制 → 256 缩放自带柔边）生成 **cel 分层火舌** `toon_flame_01.png`（暗红橙轮廓 → 橙 → 黄 → 白热芯四层色块 + 正弦抖边，经典卡通火苗读法）与 **卡通烟团** `toon_puff_01.png`（扁平圆叠云朵）；入库 `assets/vfx/textures/`（来源记录在 CREDITS.md）。`VFXManager` 新增贴图角色 `flame_toon` / `puff_toon`（关键词 `toon_*` 精确匹配，不会被 fire/flame 角色抢走；缺文件时回退 fire/smoke）。② **粒子翻滚**：`EffectDef` 新增 `angle_jitter`（粒子贴图随机翻滚角）与 `alpha_blend`（MIX 混合开关——卡通色块体必须 alpha 混合，加法在明亮草地上会被「加白」）；`_particle_mesh` 全面改用 `BILLBOARD_PARTICLES`（BILLBOARD_ENABLED 不吃 angle 参数，是死板正对）。③ **吐火球升级**：`Projectile` 新增 `visual_kind=2`（卡通火球）——白热弹芯（**自发光压到 1.5**：辉光环境里 >3 会炸成白球盖住火衣）+ `Sprite3D` cel 火衣（随飞行随机脉动）+ 双层尾焰（`fire_tongue_trail` 卡通火舌 MIX + 旧 FireTrail）+ **飞行照明灯**（橙光随时抖）；出膛 = `fire_snap`（龙口火苗迸发，定向）+ 出膛灯闪；命中爆炸 = `VFXManager.spawn_toon_fireball_explosion()` 分层一次出齐（`fireball_burst` 火舌团向上舔 + 白闪 + `toon_smoke_pop` 烟团 + 橙色冲击环 + 闪烁灯光），`_explode_splash` 按 `source is DragonPet` 分流。④ **吐息升级**：主火舌 / 余烟贴图换 toon 版并加 ±45-55° 翻滚（`_make_layer` 的 billboard 同步改 PARTICLES），**嘴部火焰灯**（`_ensure_light`，挂龙身随嘴走，2.4-4.0 随帧抖）——火从「贴在空气里的贴图」变成「场景里的光源」。⑤ `VFXManager.spawn_light()` 公共助手（OmniLight3D + 能量抖动衰减 tween 自毁；**特效灯一律 `shadow_enabled=false`**）。**回归**：DragonPetTest 58 项全绿（视觉节点名无契约）；`tools/v30_dragon_fire_shot.tscn` 三张样张 `artifacts/v30-dragon-{fireball,explosion,breath}.png`、`tools/v28_cone_probe.tscn` / `tools/v30_tex_check.tscn`（贴图角色解析检查）。**坑**：① 火球弹芯自发光 >3 在辉光环境炸成白球盖住火衣——压到 1.5 让 cel 火衣当主角；② 特效灯照亮淡色沙地 + 辉光 = 白斑，出膛灯 1.0/0.26s、爆炸灯 2.2/0.42s、吐息灯 2.4-4.0 随帧抖是调好的量。


## v31 · 夜间守城准备（入夜时间静止 + 「准备守城」按钮）

**需求：** 到晚上时时间停止；场上小怪清完后小兵回城待命；玩家配置小队，界面上开一个「准备守城」按钮；点下按钮后时间继续、怪物攻城开始。

**方案（夜潮从「入夜即刷」改为「玩家确认后刷」，夜与夜之间多出一个可自由操作的布防窗口）：**

- **TimeManager.clock_frozen（昼夜时钟冻结，≠ 暂停）**：新属性 + `freeze_clock()/unfreeze_clock()`。`_process` 里只冻结 `game_seconds` 累加——**`Engine.time_scale` 不动**，战斗/移动/建造/索敌照常跑，玩家能在「时间停止」里清残敌、造墙、编队；天色钉在 20:00（DayNightCycle 轮询 `hour`，自然定格）。**关键坑：`_recalc_clock()` 不能圈进冻结分支**——测试与 `TimeManager.begin()` 会直接改写 `game_seconds`，冻结时若不重算 `hour`，昼夜系统永远读到陈旧小时（SceneValidation 跳钟后太阳能量全 0 的根因）。
- **WildlifeSpawner 守城准备期**：`_begin_night_prep()`（night_changed(true) 触发；引导期入夜则在 `_process` 夜分支兜底补进，不跳过整段）：选门（提前播报今夜来向，供玩家定向布防）→ 冻结时钟 → 广播 `night_prep_started`。`_update_night_prep()`：场上 `enemy` 组清空 → `_prep_cleared` 一次性广播 `night_prep_cleared` + 「士兵们回城待命」播报（**小兵回城复用 `SoldierIdleState` 既有夜间路由**——时钟停在 20:00 仍属夜间，城外小兵自动收兵回城游荡驻防，零新增行为代码）。`_on_night_defense_started()`：解冻 → 播报 + `charge` 号角 → 头目夜同步进场 → `_wave_timer = night_wave_interval` 首波下一帧出（保持旧版「开打即见怪」节奏）。`_dawn_cleanup()` 兜底清准备态并解冻（测试直跳钟跨夜安全）。
- **EventBus 三信号**：`night_prep_started` / `night_prep_cleared` / `night_defense_started`（通知走总线）；**动作入口** `GameManager.request_night_defense()`（与 `request_game_over` 同型：GAME_OVER 拒绝、非冻结期幂等忽略）。
- **Raider.try_start_siege 冻结门控**：准备期残敌「按兵不动」——不吃夜袭概率 roll，防止玩家清残敌时被散怪自主攻城搅局；确认开战后时钟已解冻，夜潮 assaulting 通道不受影响。
- **HUD「准备守城」按钮**：底部居中（建造菜单左下 / 准星中心，无遮挡），`focus_mode=NONE`（不抢 Tab 焦点链）、**不占 `ui_modal_count`**（准备期玩家保持自由操作）；上方状态行每帧刷「时间静止 · 残敌 N 只」→「城防就绪 · 配置小队（V/G/T）后迎战夜潮」。第三人称鼠标被捕获点不到按钮 → **回车 = 同义入口**（`HUD._unhandled_input`，物理键码匹配 KEY_ENTER/KEY_KP_ENTER，模态打开时让位）。游戏结束/开战后隐藏。
- **引导期豁免保持**：tutorial RUNNING 时入夜既不进准备也不刷怪（旧语义），引导结束后当夜经 `_process` 兜底进准备期。

**测试适配：** NightAssaultTest ③ 改为「入夜 → 门选定 + 时钟冻结 + 准备期不出怪 → `request_night_defense()` → 解冻 + 离开准备态 + 重复请求幂等 → 夜潮批量/推进/转火/天亮清理」全链；BossNightTest 先等 `clock_frozen` 再确认，头目在确认后登场；SoakTest 模拟玩家布防 1.5s（真实秒，`create_timer` 第 4 参 ignore_time_scale）后自动按按钮——否则多日浸泡退化成无限长夜。其余 CORE 测试白天运行或 `set_process(false)`，不受影响。

**回归**：NightAssaultTest 24 项 / BossNightTest 10 项 / SceneValidation 153 项 / SoakTest（跨夜+GAME_OVER 出口）全绿；`tools/run_all_tests.sh` CORE 25 套通过。**坑**：① 冻结的是「时钟累加」不是 `_recalc_clock`（见上）；② 测试直发 `night_defense_started` 也能走通（GameManager 校验冻结态，幂等）；③ SoakTest 的自动确认必须用 ignore_time_scale 计时器——浸泡 5× 速下普通 SceneTreeTimer 会被倍速「快进」，布防窗口时长不可控。


## v33 · 进阶职业技能（跳劈 / 陨石术 / 贯穿射击 / 隐身）+ 转职洗点返还

**需求（用户口径，2026-10-02）：** ① 狂战士加「跳劈」——前摇较长、砸地形成单次圆形 AOE、把怪物击飞并控制；② 元素法师加「陨石术」——长前摇、原地吟唱、高额伤害、容易被躲避；③ 狙击手加「贯穿射击」——射出一枚更大的子弹、贯穿一串目标、射程很远；④ 暗杀者加「隐身」——隐身后 shader 进入隐身态、敌人一段时间看不到，接近目标或逃生时释放。四条附加要求：新技能要进技能树、**转职后技能点清空并全额返还**、四个技能全部要配特效。

**设计（`docs/v33_skill_design.md` 是本次的冻结接口契约，五人并行开发的单一事实源）：** 数据层（`PawnSkillDef` 新 kind + 15 个新字段 / `PawnDef.extra_skills` / `SkillNodeDef.unlocks_skill_id` / `GameDefs` 四棵进阶树）→ 运行时（`PawnSkillComponent` 多技能 + `SkillCastState` 前摇管线 + `SkillMeteorStrike` / `SkillPiercingShot` 两个技能实体）→ 宿主（`Pawn` 施法锁 / 击飞控制 / 隐身四件套 / `PawnModelRig.set_stealth`）→ 特效（14 个 id + `stealth_cloak.gdshader`）→ 测试（`AdvancedSkillTest`）。写范围按文件切分，互不重叠。

**数值（`GameDefs`）：**

| 技能 | id / kind | CD | 射程 | 关键参数 |
| --- | --- | --- | --- | --- |
| 跳劈（狂战士） | `leap_slam` / LEAP_SLAM | 14s | 8m（超距钳到 8m 落点） | 伤害 34 · AOE r3.4 · windup 0.55s · recover 0.30s · 击飞 3.2m/高 2.6m · 滞空 0.55s · 眩晕 1.1s |
| 陨石术（元素法师） | `meteor` / METEOR | 16s | 11m | 伤害 55 · r4.2 · 原地吟唱 1.0s + 预警 1.1s（落点吟唱瞬间锁定，走出圈无伤） |
| 贯穿射击（狙击手） | `piercing_shot` / PIERCING_SHOT | 12s | 开火 18m / 弹体飞 26m | 每目标 26（各只吃一次）· 判定半径 1.0m · 弹速 26 |
| 隐身（暗杀者） | `stealth` / STEALTH | 18s | 自身 | 持续 5s · 逃生血线 35% · 接近触发 2.5~7m · **造成伤害即破隐、受击不破隐** |

**技能树与转职洗点：** 四个进阶职业（狂战士 / 元素法师 / 狙击手 / 暗杀者）改用专属树 `settler_*_tree`，多一个 `advanced_skill` 节点（`unlocks_skill_id` = 新技能 id，需先点亮 `class_skill`）；`PawnSkillTree.is_skill_unlocked(id)` 在有 `unlocks_skill_id` 声明的树上走**精确 id 门禁**，无声明则回落 v25 的 gate 根节点语义（基础四职业与主角零变化）。`Soldier.promote_to()` 统一走 `reset_and_refund()` → `set_tree_def(def.skill_tree_id)` → `skill_points += 返还` → 广播 `skill_tree_changed` + 飘字「技能点返还 +N」——**任何转职都清空已加点数并全额返还**（含沿用 generic 树的骑士 / 雷电法师 / 漫游射手 / 忍者；规则统一 = 一次免费洗点）。`points_spent()` 扣除预点亮节点，避免把主角的免费根节点退成点数。

**实现要点：**
- `PawnSkillComponent` 施放优先级 = `extra_skills`（进阶技能优先）+ 主技能；每技能独立 CD（`_cd: id → 剩余秒`）；`try_cast` 逐个试「CD 就绪 + 门禁解锁 + 条件满足」。既有四技能分支逐行保持原表现（`SettlerSkillTest` 44 项零回归）。
- 前摇技能走 `SkillCastState`（节点名 `skill_cast`）：`windup → 执行 → recover` 由组件 `tick_cast` 推进，收招结束回调 `Pawn.end_skill_cast()` 决定回 fight 还是 idle；`abort_cast()` 不抢状态机（跳劈滞空被打断会把单位放回地面）。`begin_skill_cast()` **返回 bool**，未进入施法态时组件撤销起手、不吃 CD。
- 击飞/眩晕走新状态 `stunned`：`Pawn.apply_knockup()` 记录起点 + 水平速度 + `sin(πt)` 弧高，`tick_control()` 逐帧写 `global_position`；`is_controlled()`/`is_stunned()` 在「滞空 + 落地眩晕」整段为真。
- 隐身：`can_be_seen_by_enemies() = can_be_targeted_by_enemies and not is_stealthed()`；`_valid_hostile_candidate` 与 `FightState`/`RangedFightState` 全部改走它（0.2s 索敌缓存命中时同样立即失效），死亡/击飞/到期/造成伤害都会解除并释放 `stealth_shimmer` 拖尾。
- 特效：14 个 id（4 个技能各 3~4 层 + 隐身 3 件）+ 7 个复合特效（主层仍是 `_defs[id]` 的普通 EffectDef，附加层在 `_composites`）；`meteor_telegraph` 支持 `{"radius": R}` 按 AOE 半径撑圈；隐身 shader `stealth_cloak.gdshader`（半透明 + 边缘 fresnel + 轻微扰动），`PawnModelRig.set_stealth` 走 per-surface override 且**跳过 `Outline_*`**，shader 缺失时回落半透明 `StandardMaterial3D`（headless 测试不依赖 shader 加载成功）。
- UI：`SkillTreePanel` 四列进阶树自动收窄卡片宽度（198 → 176）、`advanced_skill` 节点保留自己的名字（只把「解锁主技能」的节点改写成「职业技 · 血怒」）、底栏提示补「转职会清空并全额返还技能点」；`CitizenPanel` 转职按钮 tooltip 与提示同步。

**测试：** 新增 `tests/AdvancedSkillTest.tscn/.gd`（CORE 第 26 套，`tools/run_all_tests.sh` 已收录）覆盖数据契约（74）/ 门禁（34）/ 转职返还（13）/ 跳劈（13：前摇后第 50 帧落地、同帧全体 -34、圈外零伤、抬升 2.60m、击退 3.30m、控制 1.65s）/ 陨石（10：吟唱零伤、落点锁定偏差 0.00m、圈内 -55、走出圈零伤）/ 贯穿（7：一线 3 目标各一次 -26、远靶 22.5m、线外零伤）/ 隐身（15：索敌对照组 → 隐身失效、受击不破隐、造成伤害即刻破隐、到期解除）/ 14 个特效 id（5），**173 PASS / 0 FAIL**，同命令两跑逐行一致。`CitizenManageTest` 的两条 v25 旧断言按新语义更新（四职业专属树分流、转职清空 + 全额返还、两条字面 `%` 未转义的 format 错误）。Lead 最终验收：`bash tools/run_all_tests.sh` **CORE 26 套全绿（suites: 26 / failed: 0）**；定义层另有 `tools/v33_defs_probe.tscn`（25 项）。有界面样张 `artifacts/v33-*.png`（6 张：跃击落地 / 陨石吟唱+预警圈 / 陨石爆炸 / 贯穿三点一线 / 隐身对照 / 破隐）。

**坑（v33 新增）：**
- **半成品脚本会把整队锁死**：改到一半的 `.gd` 会让场景无脚本 → 永不 `quit` → 占着 godot 锁不放。跑批一律 `--quit-after 20000` 兜底，godot 调用统一走 `bash tools/godot_locked.sh`（mkdir 锁 + 陈旧锁回收）。
- **`Pawn.gd` 用 `load()` 延迟拿 `SkillCastState` 只是过渡**：直引类名需要组件方法已落地，否则 Pawn 基类 Parse Error 会级联到全部子类（本版本真实踩过：`_clamped_leap_point` 签名不符 → 四个套件同时红）；类缓存重建（`godot --headless --editor --quit --path .`）必须由单一角色统一执行。
- **`stealth_cloak.gdshader` 的 `alpha_scale` 是倍率不是绝对值**（`base.a × mix(1.0, 0.24, cloak) × alpha_scale`）：填 0.18 会得到 ≈4% 的「全透明」，调用侧固定传 1.0，0.18 只属于 StandardMaterial3D 兜底路径。
- **`VFXManager._process` 的已释放实例**：复合特效根被技能中断 `queue_free` 时，登记过的子层节点会连带释放，`var node: Node = e["node"]` 直接抛 SCRIPT ERROR（首轮样张 341 条）——必须「无类型接引用 → `is_instance_valid` → `as`」三件套。
- **贯穿射击的测试摆位**：`PawnSpawner` 出生吸附会移动施法者，弹道相对木桩连线就斜了（20m 处横向偏差 >1.3m 判定半径 → 假 FAIL）；用例必须钉死施法者与木桩坐标。
- **并行会话/多智能体协作**：写范围按文件冻结 + `godot_locked.sh` 串行化；同工作区若有其它会话在改同一批 CORE 测试（本次遇到 v32 巨龙侧并发编辑），跑批结论要按文件 mtime 与变更面区分归属。

**v33.1 · UI 修复（2026-10-02，用户真机反馈两连）：**
- **技能树「超框」根因不是列数，而是同深度叠列 + 固定树高**：进阶树的「跳劈」与「伤害强化」都在深度 1（`requires_node` 都指 `class_skill`），同一列叠两张 132px 卡 → 列高 282 > 树区固定最小高 236 → 卡片压到底部提示行、面板顶出画面（横向 3 列其实放得下）。修法：`_refresh()` 里按**各列实际内容高**求最大值得出 `_tree_area` 最小高度（下限保留 236），列数变化自动跟随；面板实测 760×513 在 1152×648 逻辑视口内 `fits=true`。
- **卡片改「缩略图 + 简介」紧凑版**：旧竖版卡（徽座 60 + 两行说明 + 收益行 + pip 条 + 按钮）单卡近 200px 高；新卡只留 名称/级数 + 徽章 46 + 一行简介（省略号截断）+ 加点按钮，宽度 154（三列）/ 126（四列以上）、列间距 44 / 28。
- **悬停浮动弹窗**（用户要的交互）：说明文本从卡片移到浮窗，鼠标悬停由 `_process` 逐帧做命中检测（`get_global_rect().has_point()`，比 `mouse_entered/exited` 稳——卡内按钮 / pip 等子控件都算命中），浮窗显示 **类型 · 等级 / 完整说明 / 每级与当前收益 / 前置要求（未满足红字）/ 当前状态（可加点 · 已满级 · 未解锁 · 技能点不足）**；默认贴卡片右侧，越界自动翻到左侧并内收，`mouse_filter=IGNORE` 不抢鼠标。
- **市民管理技能点实时刷新**：旧 `_on_skill_tree_changed` 只刷主角行（注释写「市民行在树面板内自刷新」——错的），市民加点后要关掉面板重开才更新。现在每个市民行注册就地刷新器（`_row_refreshers`：技能点 / 攻防 / 生命条 / 技能树按钮 tooltip），加点即刷、无需重建整表；找不到行时兜底整表重建。样张实测同一面板内加点前后 `技能点 3 → 2`、`攻 24 → 25`（`artifacts/v331-citizen-{before,after}.png`）。
- **回归**：`SceneValidation` / `CitizenManageTest` / `AdvancedSkillTest` / `UiIconTest` 全绿，随后 CORE 26 套全量复跑通过。样张工具 `tools/v331_ui_shot.tscn`（4 张图）带 90s 看门狗——首版脚本 `get_node` 路径写错抛 SCRIPT ERROR 后永不 quit，把 godot 挂住，已按「测试必须任何路径都会 quit」的规矩补上。


## v32 · 巨龙翻倍 + 懒跟随 + 自主守备

**需求（两条）：** ① 龙放大一倍，注意跟随不要遮挡玩家，半径盒同步扩大；② AI 迭代——跟玩家要有**范围较大的缓冲半径**（圈内玩家移动时龙不跟，出圈才追到「跟随半径」附近，随后再次进入缓冲）；另外玩家没有攻击目标/没有指定目标时，龙要有**自己的攻击 AI**（主动攻击，攻击半径按主角的口径算），优先级 = **玩家的目标 ＞ 打玩家的目标 ＞ 自己攻击的目标**。

**① 体型翻倍 + 半径盒（`PawnDef.body_scale`，新增）**

- `dragon_obsidian_def()`：`model_scale 0.55 → 1.10`（实渲 ≈3.1m → **6.2m**）、`body_scale = 2.0`、`hud_head_height 3.4 → 6.8`、`squad_ring_radius 1.25 → 2.5`。
- **半径盒同步**：`Pawn._apply_body_scale()`（`_apply_def` 末尾调用）按 `def.body_scale` 复制并放大 **碰撞胶囊（r0.4/h1.6 → r0.8/h3.2，中心同步抬到 y=1.6）/ 占位胶囊 / 拾取圆柱（r0.6 → r1.2）/ NavigationAgent3D.radius / 选中黄盘 / 集火红盘**。`body_scale == 1.0`（全部老单位）时整段空转 → **零回归面**。
- **嘴部出口改为按体型比例**：`MOUTH_HEIGHT/MOUTH_FORWARD` 两个写死米数的常量 → `MOUTH_HEIGHT_REF/MOUTH_FORWARD_REF + MOUTH_SCALE_REF`（0.55 基准，v29 骨骼实测值 1.35m）派生 `mouth_height()/mouth_forward()`；否则翻倍后火球/火舌又会从脚边喷出来。
- **站位随体型线性外推**（`_grow(base, per_body, b)`，b=1 时即旧值）：侧翼 `3.2 + 2.3×(b-1)` → b=2 时 **右翼 5.5m / 身后 1.6m**（第一版按比例 ×2 = 4.5m，实机样张里 8m 翼展的翼尖会扫过画面中心，遂外推加大）；到位半径 `1.1 + 0.1×(b-1)`、分离半径 `2.2 + 1.4×(b-1)`、个人空间 `2.6 + 1.0×(b-1)`。

**② 懒跟随（缓冲半径 + 跟随半径）**

- 新增 `BUFFER_RADIUS = 15m` 闸门 + `_following` 闩：**主角在缓冲圈内怎么走，龙原地不动**；`dist > 15m` 才置位追赶，追到侧翼槽位（= 跟随半径，b=2 约 5.7m）就位后**立刻复位**、重新进入缓冲态。→ 龙不再像尾巴一样贴着玩家一顿一顿地挪。
- **个人空间让位**（新增）：主角贴到 `2.6 + 1.0×(b-1)` 以内（玩家自己走进龙怀里也算）时龙侧移让开，别挡视线。**只在「原地待命」分支生效**——第一版放在归位之前，结果「让位退开」和「飞向槽位」互相拉扯：龙从主角身边飞过时被让位逻辑抢舵，600 帧都没站住（v32 回归实测 closest 2.93m → 永不 settle）。
- 到达后的滞回、`_rest_pos` 世界休整位冻结、`look_at_target` 限速转身（v29）全部保留。

**③ 自主攻击 AI（三级优先级）**

- `DragonDef.auto_attack_range = 11.0`（**圆心 = 主角**，口径由用户拍板：玩家会被怪打到的那一圈 = 龙该清的那一圈）；`d.is_auto_fighter = true`，删掉 `autofight_enabled()` 的「绝不索敌」覆写。
- `DragonPet.pick_target()` 三级：**① 玩家的目标**（`Hero.live_pet_target`：集火令 T ＞ 主角保鲜期内的最近攻击目标）＞ **② 正在打玩家的敌人**（对方 `combat_target == 主角`，FightState/RangedFightState 进战即写该字段）＞ **③ 自主索敌**（主角圈内最近的敌人）。同级取「离主角最近」。
- 0.2s 缓存 + **滞回**：已锁定的自主目标按 `×AUTO_LEASH_MULT(1.25) = 13.75m` 宽容圈留人，新目标一律按严格 11m 收 → 边界上的怪不会被反复抢/丢。
- `DragonFightState` 改为每帧轮询 `pick_target()`：主角一有目标**立即转火**；自主目标出圈/死亡 → 自动换目标或回跟随。`DragonFollowState.enter` 清 `combat_target`、`DragonBreathState.enter` 接管（喷吐期间仍算交战）——修掉「吐息态把 combat_target 清空」的字段空窗。
- 出战播报文案同步：「跟着你，打你打的目标，也会清掉你身边的敌人」。

**回归**：`DragonPetTest` 新增 J 节 19 项（体型/半径盒 8 项：model_scale、body_scale、胶囊 r0.8+y1.6、拾取 r1.2、导航 r0.8、嘴部 2.7m、脚圈 2.5m；懒跟随 3 项：圈内挪 8m 位移 0.00m、出圈追到 6.5m 内且站住、再进缓冲又不动；自主攻击 3 项：圈内自主接战、圈外 20m 不接战且不掉血、三级优先级 3 断言），v26 的两条旧契约按新语义改写（「never auto-fight」→「只在主角圈内自主」；「主角停手即回跟随」→ **先清场**再验）。**全量 CORE 26 套通过**。样张 `artifacts/v32-dragon-{scale,buffer,chase,guard}.png`（`tools/v32_dragon_ai_shot.tscn`，同时打印客观量测：屏幕偏心距 413→498px（越大越不挡准星）、缓冲圈内位移 0.00m、出圈追到 4.63m 停住、圈外 20m 的怪 `pick_target()==null`）。

**坑**：① **个人空间半径必须小于「槽位距离 − 到位半径」**（b=2：5.7−1.2=4.5），否则龙在「站到槽位」与「让位退开」之间来回抖；② 让位逻辑不能与归位 seek 同时生效（见上）；③ 测试里摆「三只怪验优先级」必须**冻结怪本体 + 怪状态机**并显式钉死各自 `combat_target`——否则 3m 的干扰项也会 aggro 主角，等于两只「威胁」，优先级断言随机失败。


## v34 · 小队经验共享 + 回城疗伤（主角 / 巨龙）

**需求（用户两条，2026-10-02）：** ① 做一个小队共享经验的功能——只要加入到小队的小兵都能共享经验，但击杀者经验最多，其他人的经验先按击杀者的 50% 算；② 龙和主角只要回到城镇范围就缓慢回血，晚上守城时不会。

**① 小队经验共享（`GameDefs` + `Soldier` + `Hero`）**

- **单一数值源**：`GameDefs.SQUAD_XP_SHARE_RATIO = 0.5` + `GameDefs.squad_share_xp(base_xp)`（向下取整、保底 1 点：10→5 / 25→12 / 1→1）。主角侧旧的「小队击杀折半」（`maxi(1, xp_gain / 2)`）改走同一助手——数值等价（正整数下整除 == 截断），但调比例只动一处。
- **判定口径 = `follow_leader` 同队**（与 `Hero.recruit_squad/_release_member` 的入队/出队维护天然同步，不用额外登记表）：`Soldier._on_enemy_killed_for_xp` 重构为三分支——killer==self 拿全额（原行为）；killer 是自己的小队长（主角亲手）或与自己同队跟随的 Pawn（队友 / 编外巨龙，`killer.follow_leader == leader`）→ 分 50%；其余（队外小兵击杀、无队归属）不分进也不外溢。死亡（`is_dead_flag`）与 `can_level_up()` 门禁保持。
- **主角侧不变式**：`Hero._on_enemy_killed` 的归属链（自己击杀全额 / `follow_leader == self` 的队员与巨龙击杀 50%）原本就在，v34 后主角与队员终于**双向对称**——主角杀 → 队员各 +50%；队员杀 → 主角 +50%、其他队员 +50%；巨龙杀（编外第 5 位，`DragonSystem._spawn_pet` 同样设 `follow_leader`）→ 主角与队员各 +50%。龙自己 `can_level=false` 不吃经验。
- **边界**：解散小队（`release_squad` 清 `follow_leader`）即刻停止分账；队外士兵（城内驻防）击杀只有自己全额；等级封顶时 `gain_xp` 自行丢弃。

**② 回城疗伤（`Pawn._try_town_regen` + 主角 / 巨龙 `_process` 驱动）**

- 新增 `Pawn._try_town_regen(delta)`：白天 + `CitySystem.is_in_city(global_position)` 才回 `def.regen_per_sec × delta`；**夜晚（`TimeManager.is_night()`，20:00~06:00，含守城准备期与夜潮攻城整段）一律停**——守城战不能靠城内站位白嫖回复。满血 / 暂停（delta≤0）早退，不发无意义的 `health_changed` 信号。
- 数值：主角 `hero_warrior_def.regen_per_sec = 2.0`（320 血 ≈160s 回满）、黑曜龙 `dragon_obsidian_def.regen_per_sec = 4.0`（360 血 ≈90s）——都刻意「缓慢」（对照：酒馆 20/s、士兵城内 5~8/s）。挂点：`Hero._process` / `DragonPet._process` 每帧各一行。
- **与士兵城内回血分立两条管线**（`_try_city_regen` 不动）：士兵夜间城内休整回血是既有契约（v20 夜循环），不受夜晚门控；主角 / 巨龙的「回城疗伤」才吃夜晚门控。
- **夜晚口径统一**：新增 `TimeManager.is_night()`（hour ≥ 20 或 < 6），`Raider.is_night_now()` 改为委托——三处（夜袭决策 / 回城疗伤 / 今后的新消费方）读同一窗口，不再各写一份 `h >= 20 or h < 6`。

**测试：** 新增 `tests/SquadXpTownRegenTest.tscn`（CORE 第 27 套，`tools/run_all_tests.sh` 已收录，29 项）：数据契约 6（比例常量 / 换算截断保底 / 双方 regen / 龙 can_level=false）+ 经验共享 16（真实 `apply_damage(source)` 归属链：主角击杀、队员击杀、队外击杀不外溢、巨龙击杀、解散后停止，全部按累计值断言）+ 回城疗伤 7（白天城内 ≈2/s 精确区间、城外 0、夜 22:00 城内 0、跳回白天原地恢复、龙 ≈4/s 与夜晚 0）。**全量 CORE 27 套通过（suites: 27 / failed: 0）**。

**坑（v34 新增，重要）：**

- **「队形漂移」断言的双稳态假失败**：`SquadCommandTest` C5（主角原地转视角 → 队员 drift < 0.05m）在 v34 改动后稳定失败（drift 0.06~0.10），但二分定位发现被改的 `Soldier` 函数**在断言时刻从未执行过**（插桩证实首次触发在第 301 帧，旋转测试早已结束）——机制是：集结判定「全员 3.5m 内即 break」+ 固定 60 帧等待后成员仍在向槽位收敛，**残差收敛运动**才是 drift 的来源；该残差对初始条件双稳态（任何无关脚本改动都会让编队落位整体微移 ~0.1m，恰好跨过成员间距的分离力阈值，drift 就从 0.000 翻到 ~0.06）。基线 3× 绿 / 改动 3× 红、只加一行 print 也改变 drift 值，均为该机制的实证。**修法 = 测量前等队形真正静止**（`_wait_squad_settled`：连续 20 帧全员位移 < 0.5mm，600 帧兜底）——教训已进 AGENTS/CLAUDE 高频坑：此类断言必须以「收敛完成」为前提抓基线，不能用固定帧数。
- **经验共享的归属判定别用 `hero_squad` 分组**：`DragonPet._ready` 无条件入组，但龙的队属绑定是 `follow_leader`（`DragonSystem._spawn_pet` 生成后才设）——用分组判定会把「已入组但还没绑 leader 的龙」误算进队；`follow_leader` 与 `recruit_squad/release_squad` 的维护天然同步，才是正确的队籍事实源。


## v35.1 · UI 模态期滚轮屏蔽（市民管理开着不再缩放相机）

**需求（用户反馈，2026-10-02）：** 打开市民管理界面后划滚轮，会和外面的视野距离调整冲突——模态开着应该屏蔽外面。

**根因（探针实测，非猜测）：** Godot 的 `MOUSE_FILTER_STOP` 遮罩**挡得住点击、挡不住滚轮**——`Viewport` 的 GUI 只消费「被某控件 `accept_event()` 过」的事件，滚轮事件（`MOUSE_BUTTON_WHEEL_UP/DOWN`）对没有 `_gui_input` 处理的控件（如 `ColorRect` 遮罩）不会被消费，直接穿透 GUI 落到 `_unhandled_input`。临时探针（全屏 STOP ColorRect + `_unhandled_input` 观察者）：`unhandled_wheel=1`——市民管理的遮罩、面板卡对滚轮全都形同虚设，双相机的滚轮缩放照常触发。

**修法（消费端守卫，单点收口）：** `ThirdPersonCamera` / `IsometricCamera` 的 `_unhandled_input` 开头按 **`SelectionManager.ui_modal_count > 0` 直接返回**（BuildSystem 同款既有约定）——市民管理 / 技能树 / 入住选职业 / 驯龙菜单 / 暂停菜单 / 引导信息步等一切模态期间，滚轮缩放与等距相机的 Q/E 视角旋转全部屏蔽；建造模式**不是** ui_modal，建造中滚轮缩放照旧（v7「建造与操控共存」不破）。GUI 内部该滚的列表（市民全表 ScrollContainer）不受影响——滚轮落在 STOP 的 ScrollContainer 上仍由它消费。

**回归：** `tests/CitizenManageTest.gd` E 段新增两条——① 面板开着向 (80,80)（遮罩上）发 `WHEEL_UP/DOWN` 合成事件，双相机 `target_distance` 不变；② 面板关闭后正向对照：滚轮恢复缩放（发 `WHEEL_UP`＝`zoom_out`，视距 5.20→6.10 确实变化，随后还原），证明守卫只作用于模态期。修前 ① 必红（视距 ±0.9），修后全绿。**注意本项目滚轮方向是「下滚拉近」：`zoom_in` 绑 `MOUSE_BUTTON_WHEEL_DOWN(5)`、`zoom_out` 绑 `WHEEL_UP(4)`。**

**坑（进 CLAUDE.md 高频坑合集）：** 「遮罩挡点击不挡滚轮」；无 GUI 消费方的输入（滚轮 / 边缘平移类）要在 `_unhandled_input` 消费端按 `ui_modal_count` 守卫，而不是指望遮罩。


## v36 · 湖泊卡位修复（碰撞盒与寻路一致 + 击飞落点裁剪 + 滞留自救）

**需求（用户反馈，2026-10-02）：** 有单位现在会卡到湖里，修复一下。

**根因（两个叠加，均实测定位）：**
1. **湖面碰撞盒与寻路阻挡脱节（主因）**：`WorldScenery._build_terrain_collision()` 在 `_ready` 里先给湖面格建物理碰撞盒，而 `WaterFeature._register_terrain()`（`_build_water_feature()` 内同步执行）**之后**才把河口浅滩（`SHALLOW_CENTER` 半径 3m）从 `terrain_cells` 里清掉——清掉只影响 A\*，碰撞盒已经建好不会消失。结果湖东岸河口出现 **7 个「寻路认为可走、物理却是隐形墙」的矛盾格**（41..45, -33..-37 一带）：路径把单位引进去撞墙卡死、`random_point_outside` 的出生点吸附在这些格上原地保留（出生即嵌盒）、repath 也救不回来（寻路认为它站得好好的）。
2. **跳劈击飞抛物线穿墙（v33 引入，放大器）**：`Pawn.tick_control()` 的击飞是**直写 `global_position`** 的抛物线（水平匀速 + sin 弧），完全不与物理碰撞——湖岸边被狂战士跳劈命中的怪按 3.2m 掀飞，直接穿过湖面碰撞盒落在湖里，落地即嵌进静态盒永久卡死。「现在会卡到湖里」的时间点与 v33 上线吻合。

**修法（三层，防再发）：**
1. **建盒顺序**（`WorldScenery.gd`）：`_build_terrain_collision()` 只登记 `terrain_cells` + 地图边界墙；新增 `_build_lake_collision_boxes()` 在 `_build_water_feature()` **之后**按 `terrain_cells` 最终状态逐格建盒——浅滩清掉导航阻挡的同时不再有物理盒，nav 与 physics 逐格一致（河口浅滩按 Lead 原意成为可涉水的落脚点，与浅滩过河点同款）。
2. **击飞落点裁剪**（`Pawn._clamp_knockup_distance`）：`apply_knockup()` 起跳前沿击飞方向 0.4m 步进试探，把水平位移截到最后一个可站立格再减 0.4m（≈胶囊半径）边距；判定走新增的 `NavSystem.is_walkable_cell()`（与 A\* 同口径：湖 / 河 / 崖 / 建筑 / 资源 / 主城地基都站不得）。附带效果：击飞不再把单位拍进建筑 / 树林格，满程击飞距离 3.2→2.8m（玩家无感）。
3. **滞留自救兜底**（`Pawn._check_terrain_rescue`，每物理帧、O(1)）：单位所在格连续 2s 是阻挡格（或出图）且期间位移 <0.5m（=真卡死，涉水通过不误伤）→ `snap_to_walkable` 搬回最近可走格 + 立即作废旧路径。**主角覆写 `allows_terrain_rescue()=false`**——玩家亲自操控、河 / 浅滩本就无物理碰撞，涉水合法，绝不自动搬移玩家角色。

**回归：** 新增 `tests/LakeStuckTest.tscn`（进 CORE，第 28 套）：① 湖面 127 格逐格「物理盒 ⟺ 寻路阻挡」一致（0 不匹配；修前 7 格矛盾）+ 河口浅滩 7 格保持可涉水；② 湖西岸跳劈向湖心：落点在可走格、lake_sdf≥1.0、落地后能正常走离（无嵌入）；③ 模拟历史 bug 直写坐标把小兵放进湖心：~2s 内自动搬回岸上且计数 +1；④ 主角 `allows_terrain_rescue()==false`。既有回归全绿：WaterFeature / NavigationStability / AdvancedSkill（跳劈四技）/ SceneValidation（湖心射线仍命中实体碰撞）/ MonsterBehaviorStability / DragonPet。

**坑（进高频坑合集）：** ① 直写 `global_position` 的位移（击飞抛物线 / 复活 / 测试摆位）会**穿透静态碰撞**——落点必须按寻路格裁剪，否则单位嵌进碰撞体；② 物理一致性射线测试：`hit_from_inside` 默认 false，**从碰撞体内部出发的射线永远打不中**——验证「这格有没有碰撞盒」要用体外入射（本例：从 y=6 向下打到 y=0.5，穿盒顶面）。


## v37 · 建筑数量上限（酒馆 / 龙园各 1 座）

**动机**：酒馆与龙园是功能型建筑（酒馆光环疗伤 / 龙园驯龙），此前可以无限复制，玩家铺满后既破坏平衡也让城内布局失去取舍。

**做法**：`BuildingDef.max_count`（0 = 不限量）——酒馆与龙园各填 1；判定 = 场上存活实例数（`GameDefs.building_at_limit`，按 `def_id` 分组实时统计），拆除即释放、可原地重建。`BuildSystem.build_limit_reached()` 是唯一拦截点：预览变红、放置拒绝**且不扣费**，`BuildMenu` 卡片置灰 + 造价芯片显示「满」+ tooltip 追加上限说明。新增受限建筑只需在 Def 里填 `max_count`。

**回归**：新增 `tests/BuildLimitTest.tscn`（进 CORE）：首座可建 / 第二座预览变红且拒绝 / 不扣金币 / 卡片置灰与「满」芯片 / 拆除后可以原地重建。


## v38 · 关卡系统 + 3D 关卡选择地图 + 序章关

**动机**：此前工程只有「进游戏 = 直接进沙盒世界」这一条路，没有关卡概念——既没法把已有沙盒留作调试场，也开不了有剧本的剧情关。本版把「一局玩什么」抽成数据（关卡目录），入口从主菜单改为**世界地图选关**（3D 场景里操控小人走到旗子旁选关，参考用户给的选关地图截图），并落地第一个剧情关「序章」。

**关卡系统（数据层 + 会话层）**
- `scripts/defs/LevelDef.gd`：一关 = 章节/标题/简介/类型（`Kind.PROLOGUE / SANDBOX / COMING_SOON`）/场景路径/地图归一化坐标/岛屿配色/星级上限/玩法目标/星级条件。
- `scripts/defs/LevelCatalog.gd`：唯一数据源，当前 5 关——**序章·故土残火**（可玩，3 星）、**测试关卡·沙盒战场**（旧沙盒世界保留为测试场，不做星级判定、地图芯片显示「测试」）、**第一章·边境烽烟 / 第二章·盐碱商道 / 第三章·霜牙峡谷**（`COMING_SOON`：地图上可见、可看简介，`scene_path` 为空、拒绝进入）。新增关卡只改这一个文件。
- `scripts/autoload/LevelRuntime.gd`（**第 9 个 autoload**）：会话（`selected_id` / `select` / `current_level` / `enter_level`）+ 进度（`user://level_progress.cfg`，`record_result` 只增不减、按 `star_total` 钳制）。关键契约：**空选择 = 按沙盒关跑**——所有直接实例化 `Main.tscn` 的旧测试与工具脚本行为完全不变（这是本次改动零回归的根因）。
- 主菜单改造：`开 始 游 戏` → 关卡地图；新增 `测 试 关 卡` 按钮直入沙盒（`_goto_game()` 显式 `LevelRuntime.select(SANDBOX_ID)`，避免上一局的剧情关选择残留）。暂停菜单新增「返 回 关 卡 地 图」出口（与「返回主菜单」共用抽出的 `_teardown_session()` 状态清理）。

**3D 关卡选择地图（`scenes/main/LevelSelect3D.tscn` + `scripts/main/LevelSelect3D.gd` + `LevelFlag3D.gd`）**
- 程序化生成：五座**板状漂浮岛**（多边形棱柱，顶面 y=0 / 侧壁下沉 0.8m / 下面再垫 y=-1 的深色影子板制造浮空感）、奶油色蜿蜒道路（带暗色路肩）、岛面装饰（针叶树 155 件量级 / 灰岩 / 金币 / 冰棱 / 木屋）、每岛一面旗（旗杆 + 燕尾旗 + 深藏青星数芯片 + 金皇冠 `Sprite3D` + 暂未开放的锁标）。
- 角色：`CharacterBody3D` + `placeholder_hero.glb`（Idle/Walk 候选名回退），WASD（相机相对）+ **鼠标点地面走位**（点旗子 = 走到旗前）；可行走域 = 0.5m 烘焙网格（五座岛多边形 ∪ 道路带，`Geometry2D.is_point_in_polygon` 生成后腐蚀一圈；旗下降级强制可走），运行期 O(1) 查表，越界每帧夹回最近可走点——**绝不会掉进虚空**。
- 视角：固定斜俯视 `Camera3D`（俯角 57°、fov 32、默认 dist 52 整图同框；滚轮可推近到 24m 看真实跟随），无旋转。
- 交互：走到旗 3.5m 内 → 旗高亮 + 信息面板切到该关 + 底部提示条「按 E 进入关卡」；E / 面板主按钮进入（`LevelRuntime.enter_level`）；暂未开放 → 主按钮置灰「暂 未 开 放」+ Toast「该关卡暂未开放，敬请期待」且**绝不切场景**。
- 覆盖 UI（`CanvasLayer` + `UIRoot`，套 `UIStyle` 主题）：`TopBar/TitleLabel/TotalStarsLabel/InfoPanel/InfoChapterLabel/InfoTitleLabel/InfoSubtitleLabel/InfoDescLabel/ObjectivesBox/StarHintsBox/StarRow/StartButton/BackButton/ToastLabel/HintLabel`。测试钩子：`flag_world_position(id)` / `teleport_player(to)` / `player_position` / `walk_to` / `is_walkable_point` / `map_report`。

**序章关（`scripts/systems/PrologueDirector.gd` + `scripts/ui/PrologueOverlay.gd`）**
- 复用世界树：不新建 3D 世界场景，`Main.gd._setup_level()` 读 `LevelRuntime.current_level()`，`Kind.PROLOGUE` 时才 `add_child(PrologueDirector)` + `setup(world_root, self)`（放在 `_ready` 最后一步：世界/主角/HUD 都已就绪）。
- 接管方式：`WildlifeSpawner` / `SettlementSystem` 停 `_process`、`BuildSystem` 停 `_process` + 停 `_unhandled_input`（先退出建造态）、`TutorialSystem.suppress_autostart()`（v38 新增：静默中止且**不写** `user://tutorial.cfg`——玩家之后进沙盒仍会看到引导）；`TimeManager.begin(10)` + `clock_frozen` 把昼夜钉在上午十点（不入夜 → 夜潮/攻城判定全部失效，`Raider.try_start_siege` 在 `clock_frozen` 下直接返回 false）。
- 玩法：主角在城外西北 `(-34,0,26)` 登场（**直写坐标前先 `NavSystem.snap_to_walkable` 吸附**）→ 4 名削弱匪徒（`raider_def` 复制：HP 70→45 / 攻 9→7 / `display_name="匪徒"` / `flee_chance=0` 死战不退，出生彼此 ≥4m 防叠格）→ 目标①清剿 4 名 ②主角在城堡 8m 内连续停留 1.5s（离开清零）→ 两条都达成通关，顺序无关。
- 星级：完成 1 星 + 全程未阵亡 1 星 + 90s 内完成 1 星（`record_result` 落盘）；结算层金框「序 章 完 成」+ ★★★ + 用时/阵亡 + 两个出口（返回关卡地图 / 再打一次）；结算时 `TimeManager.set_speed(0)` + 占一个 `ui_modal_count`（期望值比较式归还，绝不泄漏计数）。
- 目标卡：左上「序章 · 故土残火」+ 两条目标（`已击杀 x/4`、`停留 1.5 秒`）+ 计时；顺手隐藏沙盒任务卡与建造条（只改运行时可见性，不动 `HUD.gd`）。

**踩坑（都进坑合集/注释）**
- **`signal finished(stars)` 与 `var finished: bool` 同名是 GDScript 硬 Parse Error**（`Variable "finished" has the same name as a previously declared signal`）→ 保留布尔钩子，完成广播改用 `_init()` 里 `add_user_signal(&"finished")`。
- **场景起来 ~0.1s 时 `DayNightCycle` 会广播 `night_changed(false)` → `WildlifeSpawner._dawn_cleanup()` → `TimeManager.unfreeze_clock()`**，把剧情关刚冻结的时钟解开（信号回调不受 `set_process(false)` 影响）→ 序章在 `_process` 里做每帧兜底重钉（正常帧只读一个布尔量）。
- `_ready` 里父节点正在装配子节点：`add_child()` / `change_scene_to_file()` 都会报 "Parent node is busy setting up children" 并静默失败 → 探针必须先 `call_deferred`。
- 手工 `SurfaceTool` 多边形在 Godot 里被判成背面、法线被翻转，顶面只吃环境光（实测仅色板 ~20% 亮度、发灰）→ 关卡地图的岛面/道路改用 `SHADING_MODE_UNSHADED` 平涂（侧壁用顶点色烘焙南亮北暗的体积感），装饰仍是引擎 `PrimitiveMesh` 正常光照。
- `PawnSpawner` 没有 `class_name`，类型化取用会 `Could not find type` → 按名取节点 + `call()`。

**回归**
- 新增 `tests/LevelSelectTest.tscn`（进 CORE，第 30 套）：目录契约（5 关 / id 唯一 / 可玩关场景存在 / 暂未开放无场景路径 / 芯片文案钳制）、主菜单入口、3D 关卡地图装配（16 个 UI 节点 + 相机 + CanvasLayer + 5 关旗子世界坐标 + 走到旗旁自动选中 + 提示条含 E）、暂未开放拒绝进入（按钮置灰 / `try_enter_selected` false / 不切场景 / 不写会话）、真实切场景进序章（导演接管 / 沙盒系统 `is_processing=false` / `clock_frozen` / 引导不跑 / 4 名匪徒 / 两个目标 / 1~3 星 / 结算层 / 进度落盘），收尾按字节还原 `user://level_progress.cfg`。**88 PASS / 0 FAIL**。
- 新增 Lead 探针：`tools/v38_defs_probe.tscn`（数据层 + 进度落盘 + 菜单接线，52 项）、`tools/v38_e2e_probe.tscn`（**真实入口全链路**：主菜单 →点开始游戏→ 3D 地图 →走到旗旁+E→ 序章 →通关→ 结算层「返回关卡地图」→ 回地图，17 项全绿，覆盖三次真实 `change_scene`）。
- 新增样张工具 `tools/level_select3d_shot.tscn`（结构/逻辑自检 60 项 + 两张 1600×1000 截图 `artifacts/v38-level-map.png` / `v38-level-map-locked.png`）。
- 既有回归：`MenuFlowTest`（主菜单流式布局 / 设置浮层 / 进 Main 引导自启 / 暂停菜单 / 返回主菜单清理）全绿；CORE 跑批见交付说明。

## 历史基线快照（v3 内容状态，v21 修订——已被 v22+ 取代）

**当前内容状态（v3，v21 修订）：** `GameDefs.building_defs()` 注册 **5 种建筑：木墙、房屋、农田（farm，食物）、市集（market，金币）、箭塔（turret）**——**兵营已删除（v21）**，小兵不再走「近战兵/远程兵」招募，统一由房屋吸引流民入住觉醒为四职业之一。箭塔自动索敌。流民定居产物改为**村民**（`Colonist`，自主「采集→搬运→入库」经济 AI，带随机姓名）。野怪分普通/精英/头目三档（`raider_def`/`raider_elite_def`/`raider_boss_def`，`spawn_raider(at, def)` 注入）；夜晚成群集结并**攻城**（`Raider.try_start_siege`，强度随夜数增长，每逢双数夜刷头目并震屏播报）。主角有击杀经验/等级/称号（`Hero.gain_xp`）。`DayNightCycle`（太阳/月亮/天空/雾/火炬/萤火虫/蟋蟀鸟鸣）与 `WeatherSystem`（晴/云/雨/雷，地面 wetness）驱动画面；`QuestSystem` 提供 9 步任务链；UI 统一 `UIStyle` 暗金主题 + 小地图 + 伤害数字。


## v10 · 小队 / 编队 / 集火系统（AGENTS.md 侧完整记录）

- **流民统一形象**：`refugee_def()` 固定 `placeholder_colonist_rogue_hooded.glb` 且双手空手（`model_weapon_* = &"none"`，名字不存在 = 空手）。
- **定居觉醒职业**：`SettlementSystem` 在流民抵达后经 `PawnSpawner.spawn_soldier` 生成随机职业小兵（`GameDefs.random_settler_def()`：`settler_warrior/mage/assassin/archer`），挂家 `soldier.assign_home(house)`、随机姓名；职业武器挂点与普攻距离都在 def（法师 10m > 射手 9.5m > 战士 2.2m > 刺客 1.7m）。Colonist 采集循环不再产出（类保留兼容旧测试/工具）。
- **昼夜行为**：`SoldierIdleState` 夜间「城外 → move 回城 / 城内 → wander 游荡驻防」，白天 patrol 出城讨伐；低血仍走 rest 回城治疗。
- **编队与小队**：`Hero.party`（≤ `SQUAD_MAX=4`，含主角共 5 人编制）；士兵出生自动补位（监听 `pawn_spawned`）；G 集结 = `recruit_squad(alive_party())`、再按解散；`enter_hero_mode` 也自动集结编队（v7 的「框选编入小队」已移除）。
- **瞄准与集火**：`HeroController._find_aim_enemy()` 屏幕中心 64px 吸附 + 世界射线遮挡判定；命中怪 → `Pawn.set_aim_highlight()`（`PawnModelRig.set_outline()` 反转外壳红描边 + 脚下红环）+ `Crosshair` 变红并显示怪物血量条；按 T → `hero.order_focus_fire(target)`，`FollowState` 优先路由集火目标、`FightState`/`RangedFightState` 对集火目标跳过姿态 leash 与追击距离限制，**目标死亡自动解除**（`enemy_died` 钩子）。
- **UI（v17 合并后）**：`HeroPanel`（HUD 左下**单张合并卡**）：上半是主角（头像 / 称号 / HP / 经验 / 连招段位 / 技能卡），下半是小队区（「小队 n/4 · G 集结 · T 集火 · V 编队」标题行 + 成员紧凑单行 = 职业字徽 + 姓名 + 迷你血条 + 数值 + 跟随/自主 + 集火目标行 + 空态行）；原独立 `SquadPanel` 类已删除。**布局契约**：底边锚死建造菜单上方 8px（`offset_bottom=-130`），顶边随内容收放（`_fit_height()`）且不得越过左上任务卡下缘（画布 y ≥ 190）。`PartyPanel`（V 键，真暂停模态）：上排 4 出战槽位（点击移出）+ 城镇全部小兵列表（点击加入/移出），Esc 链中优先于 PauseMenu。
- **键位**：`squad_focus_fire`=T、`party_menu`=V（`project.godot [input]`）。
- **坑**：① `Crosshair` 曾因 `set_anchors_preset(PRESET_FULL_RECT)` 在父级已布局时把 0×0 当前 rect 回推成 (0,0,-w,-h) offsets 而整体塌缩——全屏铺满控件必须显式清零四个 offset（`PartyPanel` 遮罩同款防御）；② `SceneTree.create_timer` 第 4 参才是 `ignore_time_scale`（第 2 参是 `process_always`），time_scale=0 冻结等待务必传全 4 参。交付样张：`artifacts/v10-{classes,hero-hud,party-panel}.png`（`godot --path . tools/v10_squad_shot.tscn` 重新生成）。


## 版本速览归档（2026-10-17，从 CLAUDE.md 迁出）

| 版本 | 主题 | 一句话 |
| --- | --- | --- |
| v32 | 巨龙翻倍 + 懒跟随 + 自主守备 | `body_scale` 半径盒同步 ×2、缓冲半径 15m 懒跟随（出圈才追到侧翼 5.5m）、三级目标优先级（玩家目标 > 打玩家的 > 主角圈 11m 内最近） |
| v33 | 进阶职业技能 | 狂战士跳劈（击飞+眩晕控制）/ 元素法师陨石术（长吟唱·可躲避）/ 狙击手贯穿射击 / 暗杀者隐身（shader 半透明 + 敌方索敌失效）；四职业专属技能树 + 转职**清空并全额返还**技能点；技能树 UI = 紧凑卡 + 悬停浮窗（v33.1，树高按列自适应、市民管理加点实时刷新） |
| v34 | 小队经验共享 + 回城疗伤 | 击杀者全额、其余在队成员 50%（`SQUAD_XP_SHARE_RATIO`，主角/队友/巨龙击杀同口径）；主角 2/s·龙 4/s 白天回城回血、晚上守城不回（`TimeManager.is_night()` 统一夜晚口径） |
| v35 | 怪物 AI 优化 | 低血逃跑概率化：`PawnDef.flee_chance` 一次性掷签（普通 20%/精英 15% 的怂怪才跑，`Raider.should_flee_now`）——近战小兵不再被迫满图追杀 1.5× 速逃跑怪；攻城怪 stuck 修复：已转火玩家单位时不切回建筑（`FightState._handle_stuck`），「被打还手」优先于冲城，索敌圈空才恢复攻城 |
| v35.1 | UI 模态期滚轮屏蔽 | 市民管理等模态开着滚轮不再穿透缩放相机：双相机 `_unhandled_input` 按 `ui_modal_count` 守卫（BuildSystem 同款；建造模式不受影响）；根因是遮罩「挡点击不挡滚轮」 |


## 版本速览归档（2026-10-18，从 AGENTS.md 迁入）

| 版本 | 主题 | 一句话 |
| --- | --- | --- |
| v38 | 关卡系统 + 序章 | `LevelDef`/`LevelCatalog`（5 关：序章·测试关卡 + 三章暂未开放）+ `LevelRuntime` autoload（会话 + `user://level_progress.cfg` 星级）；主菜单「开始游戏」→ **3D 关卡选择地图** `LevelSelect3D.tscn`（程序化浮岛/道路/旗子 + 可操控小人的可行走网格，暂未开放关拒绝进入）、「测试关卡」直入沙盒；`Main.gd._setup_level()` 按关卡分流，序章由 `PrologueDirector` 接管（停刷怪/流民/建造 + 冻结昼夜 + 4 名匪徒 + 收复主城，1~3 星结算）；`TutorialSystem.suppress_autostart()` 让剧情关不叠沙盒引导 |
| v39 | 远征界面与序章打磨 | 冷青暖金轻量 UI、可读关卡名与微缩城堡、跨岛 A* 与桥头整格净空；序章默认俯视主控（Tab 保留三态）、人形驻守匪徒、稀疏草花与进城路标、先清剿再升旗的连续占领反馈及勋章结算；`CampaignStyle` / `PrologueStage` 独立表现层，沙盒数值与场景保持原样 |
| v39.1 | Demo 直入 + 首次刷怪修复 | 开始游戏直入沙盒并覆盖旧序章选择，暂停菜单隐藏选关；首杀教学维持一只普通怪（含夜间补刷），完成或跳过后恢复正常刷怪，避免新玩家被引导停刷卡死 |
| v40 | 世界扩张 256×256 + 六大主题区域 | 可玩边界 64→128m（256×256m / 128×128 格）、地面碰撞 256、相机 ±122、刷怪环 116；旧地图 ±64m 内容原样保留。`WorldRegions.gd`（霜语瀑布 / 星落矿坑 / 风吟麦海 / 烬誓战场 / 雾隐密林 / 盐风沼地，含故事文本与配色）+ `ThemedRegions.gd`（六区域地标 + 城外路标与区域石碑）+ 分区植被与地面染色（ground shader `region_*` / `trail_*` uniforms）+ 小地图区域层 + `RegionTracker`（区域发现横幅与故事日志，序章静音）；夜潮集结点改在 62m 处保夜战节奏（`night_wave_origin`）。详见 `docs/world_regions.md` |
