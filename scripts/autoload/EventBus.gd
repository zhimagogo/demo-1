extends Node
## ============================================================================
## EventBus —— 全局事件总线
## 集中声明所有跨模块信号，只做广播转发，不持有状态。
## 通信约定：跨模块「通知」走 EventBus；「动作」走 autoload 单例方法。
## ============================================================================

# ---- 资源 ----
signal resource_changed(resource_id: StringName, new_amount: int, delta: int)
signal resource_insufficient(resource_id: StringName, needed: int)

# ---- 选择 / 命令 ----
signal selection_changed(selected: Array)        # Array[Pawn]
signal move_command_issued(position: Vector3, pawns: Array)
signal work_command_issued(target: Node, pawns: Array)
signal attack_command_issued(target: Node, pawns: Array)

# ---- Pawn / 敌人 ----
signal pawn_spawned(pawn: Node)
signal pawn_died(pawn: Node)
signal enemy_spawned(enemy: Node)
signal enemy_died(enemy: Node, killer: Node)
signal refugee_arrived(refugee: Node, house: Node)
signal resident_settled(resident_name: String, house: Node)
signal villager_spawned(villager: Node)          # 定居成功的村民（供人口统计 / 任务系统）
# v25 流民入住职业选择：流民抵房后先弹窗让玩家选职业（SettleClassPicker），
# 选择完成再走 resident_settled；无拾取器（如无头测试）时由 SettlementSystem 回落随机职业。
signal settle_class_choice_required(refugee: Node, house: Node)
signal settle_class_chosen(refugee: Node, house: Node, class_id: StringName)

# ---- 战斗播报 ----
signal damage_dealt(target: Node, amount: float, source: Node)   # 伤害数字 / 统计
signal threat_alert(position: Vector3, victim: Node)             # 玩家方遇袭（士兵支援响应）
signal boss_spawned(boss: Node)                                  # 夜袭头目登场
signal boss_died(boss: Node)                                     # 夜袭头目被击杀

# ---- 建造 ----
signal build_mode_entered(def: Resource)
signal build_mode_exited()
signal building_placed(building: Node, cell: Vector2i)
signal building_removed(building: Node, cell: Vector2i)
signal road_changed(grid: Node, cell: Vector2i, present: bool)

# v21 起兵营相关信号（barracks_selected / barracks_train_changed / soldier_trained）已删除：
# 兵营建筑与「近战兵/远程兵」一并移除，小兵统一由流民定居觉醒（见 SettlementSystem）。

# ---- 时间 / 阶段 / 昼夜 / 天气 ----
signal time_tick(game_seconds: float, day: int, hour: int)
signal day_changed(day: int)
signal time_scale_changed(scale: float)
signal phase_changed(old_phase: int, new_phase: int)
signal night_changed(is_night: bool)             # 昼↔夜切换（20:00 / 06:00）
signal weather_changed(weather_id: StringName, intensity: float)   # 天气切换（强度 0~1）
# v31 夜间守城准备（入夜时间静止 → 玩家确认开战）：
signal night_prep_started()     # 准备期开始：昼夜时钟冻结、夜潮延迟，等待清残敌 / 布防
signal night_prep_cleared()     # 准备期残敌清空：小兵回城待命，可随时开战
signal night_defense_started()  # 玩家按下「准备守城」：时间恢复流动、夜潮攻城开始
# v44 今夜威胁方向（守城准备期由 WildlifeSpawner 选门后广播）：
# active=true 时 gate_index 0南/1东/2北/3西，gate_inside = 城门内侧世界点（已吸附可走格），
# 小兵据此到对应城门内侧列阵（近战前排 / 远程后排）；active=false 表示威胁解除 / 天亮，
# gate_index=-1、gate_inside=Vector3.ZERO，小兵恢复常规夜间待命点。EventBus 不持状态。
signal night_threat_direction_changed(active: bool, gate_index: int, gate_inside: Vector3)

# ---- v40 主题区域发现 / 叙事播报 ----
# 数据唯一真相在 scripts/defs/WorldRegions.gd；判定与广播在 RegionTracker。
# region_entered 每次「跨进」某个区域都发（含王城），first_time = 本会话内第一次踏入；
# region_discovered 只在会话内首次发现时补发一次（HUD 用它显示「✦ 新区域」与故事文本）；
# 离开到无区域（或跨到另一区域）时补发 region_exited(旧区域 id)。
# EventBus 不持状态：发现集合归 RegionTracker 所有。
signal region_entered(region_id: StringName, region_name: String, subtitle: String, lore: String, first_time: bool)
signal region_discovered(region_id: StringName, region_name: String, subtitle: String, lore: String)
signal region_exited(region_id: StringName)

# ---- 主角 ----
signal hero_spawned(hero: Node)
signal hero_died(hero: Node)
signal hero_mode_changed(active: bool)
signal hero_harvested(node: Node, resource_id: StringName, amount: int)   # 主角亲自挥砍采集（第一人称）
signal crosshair_target_changed(target: Node, prompt: String, kind: StringName)   # 准星指向变化（HUD 交互提示）
signal hero_hp_changed(hero: Node, current: float, max_hp: float)
signal hero_leveled(hero: Node, new_level: int)  # 主角升级（RPG 成长线）
signal pawn_leveled(pawn: Node, new_level: int)  # 小兵升级（v20 属性系统：六维成长；UI 刷新用）
signal combo_step_changed(hero: Node, step: int)
signal skill_cast(hero: Node, index: int, skill_def: Resource)
signal skill_cooldown_changed(hero: Node, index: int, ratio: float)
signal squad_changed(hero: Node, members: Array)
signal party_changed(hero: Node, members: Array)            # 编队（最多 4 名小兵）成员变化
signal squad_focus_changed(hero: Node, target: Node)        # 小队集火目标下令 / 取消（target=null 即取消）
# ---- v25 转职 / 技能树 ----
signal soldier_promoted(pawn: Node, new_def: Resource)      # 市民转职进阶（数值/名字/模型染色已换）
signal skill_tree_changed(pawn: Node)                       # 技能树加点（面板刷新用）
# ---- v26 驯龙系统 ----
signal dragon_menu_requested(garden: Node)                  # 对龙园按 E：请求打开驯龙界面
signal dragon_unlocked(dragon_id: StringName)               # 巨龙解锁成功（金币已扣）
signal dragon_deploy_changed(dragon_id: StringName, pet: Node)  # 出战巨龙变化（pet=null 即未出战/阵亡等待复苏）

# ---- 消息 / 任务 / 漂浮文字 ----
signal game_message(text: String, color: Color)
signal game_over(victory: bool)
signal floating_text(text: String, color: Color, world_pos: Vector3)   # 世界坐标漂浮文字（入库 / 升级 / 结算提示）
signal quest_updated(quest_index: int, desc: String, have: int, need: int)  # 任务进度刷新
signal quest_completed(quest_index: int, desc: String)                      # 任务完成（奖励已发）

# ---- 新手引导 ----
signal tutorial_step_changed(step_index: int, total: int)   # 引导步骤切换（TutorialOverlay 渲染步骤卡）
signal tutorial_finished()                                  # 引导正常走完
signal tutorial_skipped()                                   # 引导被玩家跳过

# ---- v47 渲染 ----
signal render_quality_changed(tier: int)                     # 画质档位切换（0低/1中/2高/3极致）
