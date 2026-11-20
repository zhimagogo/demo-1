extends Node
## ============================================================================
## SelectionManager —— 当前选中 Pawn 集合 + 命令下发
## 单选 / Shift 多选 / 框选统一收口；命令下发带简单方阵队形偏移。
## ============================================================================

## 视角 / 操控模式（v15 起三态；v42 起玩家只保留俯视角主控）：
## - HERO     第三人称亲征：越肩相机 + 鼠标捕获，WASD 相对相机、准星瞄准
## - TACTICAL 战术俯瞰 RTS：等距相机自由平移，框选 / 右键下令（主角待命不自动索敌）
## - TOPDOWN  俯视角主控：等距相机跟随主角、鼠标释放，WASD 按屏幕方向、鼠标落点瞄准
enum ViewMode { HERO, TACTICAL, TOPDOWN }

## v42 镜头收敛：当前版本玩家只保留「俯视角主控」。
## HERO / TACTICAL 的相机、操控、RTS 选择实现全部保留（脚本接口 enter_hero_mode /
## set_view_mode 仍可用，旧测试与截图工具靠它取景），屏蔽只作用于**玩家入口**：
## 开局默认视角 + Tab 循环（见 enabled_view_modes）。恢复三态：两个开关改回 true。
const VIEW_MODE_HERO_ENABLED: bool = false
const VIEW_MODE_TACTICAL_ENABLED: bool = false

var selected: Array = []   # Array[Pawn]
var build_mode_active: bool = false   # 建造模式下禁用选择/框选
var view_mode: int = ViewMode.TOPDOWN
## 主控模式（HERO / TOPDOWN）为 true：禁用选择/框选（左键用于普攻）。
## **派生属性**：读 = view_mode != TACTICAL；写走旧语义兼容（true→HERO / false→TACTICAL，
## 供旧测试直接赋值不踩坑）。要进 TOPDOWN 必须经 set_view_mode() / HeroController。
var hero_mode_active: bool:
	set(v):
		view_mode = ViewMode.HERO if v else ViewMode.TACTICAL
	get:
		return view_mode != ViewMode.TACTICAL
var ui_modal_count: int = 0           # UI 模态计数（>0 = 入驻提示/引导信息卡等占住鼠标，第三人称暂时释放指针）


## 切换视角 / 操控模式的唯一入口（HeroController 在此基础上做相机与主角状态交接）。
func set_view_mode(mode: int) -> void:
	if mode == view_mode:
		return
	view_mode = mode


## 玩家可切换到的视角模式（顺序即 Tab 循环顺序）：v42 只剩俯视角主控。
## 恢复三态只需把 VIEW_MODE_HERO_ENABLED / VIEW_MODE_TACTICAL_ENABLED 改回 true。
func enabled_view_modes() -> Array:
	var modes: Array = []
	if VIEW_MODE_HERO_ENABLED:
		modes.append(ViewMode.HERO)
	if VIEW_MODE_TACTICAL_ENABLED:
		modes.append(ViewMode.TACTICAL)
	modes.append(ViewMode.TOPDOWN)   # 当前常开：俯视角主控
	return modes


## 开局默认视角：取开放列表首位（收敛期即俯视角主控，恢复三态后回到亲征）。
func default_view_mode() -> int:
	var modes := enabled_view_modes()
	return int(modes[0]) if not modes.is_empty() else ViewMode.TOPDOWN


func select_only(pawn: Node) -> void:
	_deselect_all()
	if pawn != null:
		pawn.set_selected(true)
		selected = [pawn]
	EventBus.selection_changed.emit(selected)


func add_to_selection(pawn: Node) -> void:
	if pawn == null or pawn in selected:
		return
	pawn.set_selected(true)
	selected.append(pawn)
	EventBus.selection_changed.emit(selected)


func box_select(pawns: Array) -> void:
	_deselect_all()
	selected.clear()
	for p in pawns:
		if p == null:
			continue
		p.set_selected(true)
		selected.append(p)
	EventBus.selection_changed.emit(selected)


func clear() -> void:
	_deselect_all()
	selected.clear()
	EventBus.selection_changed.emit(selected)


func remove_from_selection(pawn: Node) -> void:
	# 单位死亡 / 入队时从选中集合移除（DeadState 已在调用）
	if pawn == null:
		return
	var i := selected.find(pawn)
	if i < 0:
		return
	if is_instance_valid(pawn):
		pawn.set_selected(false)
	selected.remove_at(i)
	EventBus.selection_changed.emit(selected)


# ---- 命令 ----
func issue_move(pos: Vector3) -> void:
	if selected.is_empty():
		return
	var offsets := _formation_offsets(selected.size())
	for i in selected.size():
		selected[i].set_destination(pos + offsets[i])
	EventBus.move_command_issued.emit(pos, selected)


func issue_work(target: Node) -> void:
	for p in selected:
		p.assign_work(target)
	EventBus.work_command_issued.emit(target, selected)


func issue_attack(target: Node) -> void:
	for p in selected:
		p.assign_attack(target)
	EventBus.attack_command_issued.emit(target, selected)


# ---- 内部 ----
func _deselect_all() -> void:
	for p in selected:
		if is_instance_valid(p):
			p.set_selected(false)


func _formation_offsets(count: int) -> Array:
	# 简单方阵：边长 ceil(sqrt(n))，间距 1.5m
	var offsets: Array = []
	if count <= 0:
		return offsets
	var side := maxi(1, ceili(sqrt(float(count))))
	var spacing := 1.5
	var start := -(float(side) - 1.0) * spacing * 0.5
	var placed := 0
	for r in side:
		for c in side:
			if placed >= count:
				break
			offsets.append(Vector3(start + float(c) * spacing, 0.0, start + float(r) * spacing))
			placed += 1
		if placed >= count:
			break
	return offsets
