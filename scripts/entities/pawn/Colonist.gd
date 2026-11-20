class_name Colonist
extends Pawn
## ============================================================================
## 村民（殖民者）：城镇经济的发动机。
## 自主循环：选资源点 → 采集装满背包 → 回主城入库 → 再出发。
## 遇敌逃跑（VillagerFleeState）、城内缓慢回血；定居时获得随机姓名。
## 由 SettlementSystem 在流民抵达房屋时创建（PawnSpawner.spawn_colonist）。
## ============================================================================

const WORK_TICK: float = 1.2          # 单次采集耗时（秒）
const HARVEST_PER_TICK: int = 2       # 单次采集获得份数
const FLEE_SCAN_RADIUS: float = 14.0  # 敌人进入该半径 → 丢下活逃跑
const CARRY_DROP_RATIO: float = 0.5   # 逃跑不丢货：保留一半（跑得慢的代价）

var carried_id: StringName = &""      # 背包里装的是什么
var carried_amount: int = 0           # 背包份数（>= def.carry_capacity 时去入库）
var work_target = null                # 当前分配的资源点（ResourceNode）
var _carry_visual: MeshInstance3D = null   # 背上的货包（颜色随资源）


func _ready() -> void:
	if def == null:
		def = GameDefs.colonist_def()
	super._ready()
	_setup_carry_visual()
	EventBus.villager_spawned.emit(self)


func _setup_nodes() -> void:
	super._setup_nodes()
	# 村民决策路由 + 工作 / 入库 / 逃跑 三个专属状态（super 之后新增必须 register_state）
	state_machine.register_state("idle", VillagerIdleState.new())
	state_machine.register_state("villager_work", VillagerWorkState.new())
	state_machine.register_state("villager_deliver", VillagerDeliverState.new())
	state_machine.register_state("villager_flee", VillagerFleeState.new())


## 背上的货包：小盒子，装了东西才显示，颜色随资源种类。
func _setup_carry_visual() -> void:
	_carry_visual = MeshInstance3D.new()
	_carry_visual.name = "CarryVisual"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.35, 0.35)
	_carry_visual.mesh = box
	_carry_visual.position = Vector3(0.0, 1.35, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.SADDLE_BROWN
	mat.roughness = 0.9
	_carry_visual.material_override = mat
	_carry_visual.visible = false
	add_child(_carry_visual)
	_refresh_carry_visual()


func add_carry(resource_id: StringName, amount: int) -> void:
	if resource_id == &"" or amount <= 0:
		return
	if carried_id != &"" and carried_id != resource_id:
		# 换了货种（上个点采空）：先记着，入库时一并结算（村民一次只背一种，简化视觉）
		carried_id = resource_id
		carried_amount = 0
	carried_id = resource_id
	carried_amount += amount
	_refresh_carry_visual()


func carry_full() -> bool:
	return def != null and carried_amount >= def.carry_capacity


func carry_empty() -> bool:
	return carried_amount <= 0


## 入库：清空背包返回总份数（调用方负责 ResourceManager.add）。
func dump_carry() -> Dictionary:
	var out := { "id": carried_id, "amount": carried_amount }
	carried_id = &""
	carried_amount = 0
	_refresh_carry_visual()
	return out


func _refresh_carry_visual() -> void:
	if _carry_visual == null:
		return
	_carry_visual.visible = carried_amount > 0
	var mat := _carry_visual.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color.SADDLE_BROWN if carried_id != &"stone" else Color.DIM_GRAY
	# 背得越多，货包越大（0.6 ~ 1.2 倍）
	var load := 1.0
	if def != null and def.carry_capacity > 0:
		load = 0.6 + 0.6 * float(carried_amount) / float(def.carry_capacity)
	_carry_visual.scale = Vector3.ONE * load


## 逃跑掉货：丢一半（拾取不到，直接蒸发——惩罚足够轻，不至于白干）。
func drop_half_carry() -> void:
	carried_amount = carried_amount / 2
	_refresh_carry_visual()


func _on_died() -> void:
	# 村民死亡：床位空出（Building.has_vacancy 检查 resident 有效性自动放空）
	EventBus.game_message.emit("村民 %s 遇害了…" % get_display_name(), Color.ORANGE_RED)
	super._on_died()
