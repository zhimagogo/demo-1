class_name BuildingDef
extends Resource
## 建筑定义。

@export var id: StringName
@export var display_name: String = ""
@export var footprint: Vector2i = Vector2i.ONE   # 占用格数 (x=宽, y=深)
@export var cost: Dictionary = {}                 # StringName -> int
@export var max_hp: float = 200.0
@export var mesh_size: Vector3 = Vector3(1.8, 2.0, 1.8)
@export var mesh_color: Color = Color.GRAY
@export var bakes_into_navmesh: bool = true   # 是否烘焙进 NavMesh 当障碍（墙/房屋/酒馆=是）
# 全场数量上限（v37）：0 = 不限制（木墙/房屋可随意铺）；1 = 全场只能存在一座。
# 判定口径 = 场上存活实例数（分组实时统计，无需存档），建筑被拆后上限自动释放、可原地重建。
# 拦截点集中在 BuildSystem.build_limit_reached()：预览变红、放置拒绝并退款提示，
# BuildMenu 卡片同步置灰；新建筑物只需在这里填数即自动接入全部 UI。
@export var max_count: int = 0
@export var is_road: bool = false   # 道路占用建造格，但不阻挡行走，四邻自动拼接

# 静态模型（占位美术通道）。有 model_path 时视觉用模型、并隐藏上面的 BoxMesh 占位皮；
# mesh_size / mesh_color 仍是碰撞体、NavMesh footprint、建造预览 ghost 的依据，
# 不受模型影响。无 model_path 则回退 BoxMesh 占位。占位资源统一放 res://assets/_PLACEHOLDER/。
@export var model_path: String = ""
@export var model_scale: float = 1.0
@export var model_face_offset_deg: float = 0.0   # 绕 Y 旋转修正（度），让模型「门/正面」朝向相机
@export var model_height_offset: float = 0.0     # 垂直偏移（米），修正模型原点悬浮（如城墙顶塔楼）

# 酒馆（v22）：小兵疗伤据点。is_tavern 标记 + 回血光环参数；
# 小兵在城外血量低于 20% 时会自动中断当前行为、回馆疗伤（见 Soldier / SoldierIdleState）。
@export var is_tavern: bool = false
@export var heal_radius: float = 6.0    # 回血光环半径（米），0 = 无光环
@export var heal_per_sec: float = 20.0  # 光环内友方小兵每秒回血

# 龙园（v26 驯龙系统）：驯龙据点。走近按 E 弹出驯龙界面（DragonMenu），
# 花金币解锁巨龙；解锁 / 出战状态由 DragonSystem 管理，建筑本身只作交互入口。
@export var is_dragon_garden: bool = false

# 产出（每 interval 秒产出 amount 个 producer_resource）
@export var producer_resource: StringName = &""   # 空 = 不产出
@export var producer_amount: int = 0
@export var producer_interval: float = 5.0

# v21 起兵营字段（is_barracks / train_list）已删除：小兵统一由流民定居觉醒，不走建筑招募。
# v22 起箭塔字段（is_turret / attack_*）已删除：防御建筑随箭塔一并移除。

# ---- UI 展示（v3 新增）----
@export var description: String = ""              # 建造卡片悬停说明（空 = 不显示）
@export var hotkey_hint: String = ""              # 快捷键提示（仅展示用）
