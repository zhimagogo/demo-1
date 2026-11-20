class_name PawnSkillTree
extends RefCounted
## ============================================================================
## 技能树运行时状态（v25）：持有 SkillTreeDef 布局 + 各节点已投入级数。
## 纯数据与判定（不挂场景树）；由 Pawn 持有——def.skill_tree_id 非空的单位
## 在 _apply_def 时创建（主角 + 定居四职业小兵）。
## 点数与面板生效由宿主 Pawn 负责（try_invest_skill_point 统一入口）。
## ============================================================================

var tree_def: SkillTreeDef = null
var ranks: Dictionary = {}   # StringName(节点 id) -> int(已投入级数)


## 应用树定义里的预点亮节点（pre_unlocked，主角职业技根——不耗点）。
## 创建树后调用一次；转职换树（set_tree_def）会重新调用。
func apply_pre_unlocks() -> void:
	if tree_def == null:
		return
	for n in tree_def.nodes:
		if n != null and n.pre_unlocked and rank(n.id) == 0:
			ranks[n.id] = 1


## 职业技是否已解锁（树配了 gate 节点且 rank ≥ 1；无门禁 = 恒 true）。
func skill_unlocked() -> bool:
	if tree_def == null or tree_def.gate_node_id == &"":
		return true
	return rank(tree_def.gate_node_id) > 0


## v33 多技能门禁：某 id 的技能是否已解锁。
## 规则：树里只要有一个节点声明了 unlocks_skill_id → 按**精确 id** 判定（该节点 rank ≥ 1）；
##       全树都没声明 → 回落旧语义 skill_unlocked()（gate 根节点解锁 def.skill）。
func is_skill_unlocked(skill_id: StringName) -> bool:
	if tree_def == null or skill_id == &"":
		return true
	var precise := false
	for n in tree_def.nodes:
		if n == null or n.unlocks_skill_id == &"":
			continue
		precise = true
		if n.unlocks_skill_id == skill_id:
			return rank(n.id) > 0
	return not precise and skill_unlocked()


## 换树（转职）：整体替换布局，清空旧加点并重挂预点亮节点。
func set_tree_def(new_def: SkillTreeDef) -> void:
	tree_def = new_def
	ranks.clear()
	apply_pre_unlocks()


## v33 转职返还：清空全部已投入级数（预点亮重新挂上），返回**返还给玩家的点数**。
func reset_and_refund() -> int:
	var refund := points_spent()
	ranks.clear()
	apply_pre_unlocks()
	return refund


func node(node_id: StringName) -> SkillNodeDef:
	return tree_def.node(node_id) if tree_def != null else null


## 某节点当前已投入级数。
func rank(node_id: StringName) -> int:
	return int(ranks.get(node_id, 0))


## 已投入总级数（**只算玩家真花的点**；v33：预点亮节点不计入——转职返还不能把免费的点退成钱）。
func points_spent() -> int:
	var total := 0
	for k in ranks.keys():
		total += int(ranks[k])
	return maxi(0, total - _pre_unlocked_count())


func _pre_unlocked_count() -> int:
	if tree_def == null:
		return 0
	var n := 0
	for node in tree_def.nodes:
		if node != null and node.pre_unlocked:
			n += 1
	return n


## 不能加点的原因（返回空串 = 可以加点；UI 按钮提示用）。
func invest_block_reason(node_id: StringName, available_points: int) -> String:
	var n := node(node_id)
	if n == null:
		return "未知节点"
	if rank(node_id) >= n.max_rank:
		return "已满级"
	if available_points <= 0:
		return "没有技能点"
	if n.requires_node != &"" and rank(n.requires_node) < n.requires_rank:
		return tree_def.requirement_text(n)
	return ""


## 投入一点（校验通过才加级）。返回是否成功；扣技能点由调用方（Pawn）负责。
func invest(node_id: StringName, available_points: int) -> bool:
	if invest_block_reason(node_id, available_points) != "":
		return false
	ranks[node_id] = rank(node_id) + 1
	return true


## 累计攻击伤害加成（0.15 = +15%；无树 / 未加点 = 0）。
func damage_bonus() -> float:
	var total := 0.0
	for n in (tree_def.nodes if tree_def != null else []):
		total += n.damage_bonus_at(rank(n.id))
	return total


## 累计生命上限加成。
func hp_bonus() -> float:
	var total := 0.0
	for n in (tree_def.nodes if tree_def != null else []):
		total += n.hp_bonus_at(rank(n.id))
	return total
