class_name SkillTreeDef
extends Resource
## ============================================================================
## 技能树定义（v25）：一棵树的节点布局（由 GameDefs 在代码里定义，与其它 Def 同范式）。
## 每个人物（主角 + 定居市民）各持有一份运行时状态（PawnSkillTree），共用同一布局。
## ============================================================================

@export var id: StringName                    # 树 id（def.skill_tree_id 引用）
@export var display_name: String = ""         # 树名（UI 标题）
@export var nodes: Array[SkillNodeDef] = []   # 全部节点（顺序即展示顺序）
# v25.1 职业技门禁：非空 = 该节点 rank ≥ 1 才能施放职业主动技能
# （Pawn.try_cast_combat_skill 统一读取；主角走 Q/C 管线不受影响）
@export var gate_node_id: StringName = &""


## 按 id 取节点（查无返回 null）。
func node(node_id: StringName) -> SkillNodeDef:
	for n in nodes:
		if n != null and n.id == node_id:
			return n
	return null


## 分支编号列表（升序去重；UI 按分支分列）。
func branches() -> Array:
	var out: Array = []
	for n in nodes:
		if n != null and not out.has(n.branch):
			out.append(n.branch)
	out.sort()
	return out


## 某分支下的节点列表。
func branch_nodes(branch: int) -> Array:
	var out: Array = []
	for n in nodes:
		if n != null and n.branch == branch:
			out.append(n)
	return out


## 前置节点显示名（UI 提示用；无前置返回空串）。
func requirement_text(n: SkillNodeDef) -> String:
	if n == null or n.requires_node == &"":
		return ""
	var req := node(n.requires_node)
	var req_name: String = req.display_name if req != null else String(n.requires_node)
	return "需先点亮「%s」%d 级" % [req_name, maxi(n.requires_rank, 1)]


## 节点在树中的深度（根 = 0；按 requires_node 链向上数，UI 按深度分列画连线）。
## 带环防护（配置错误时按 16 层截断，不挂死）。
func node_depth(n: SkillNodeDef) -> int:
	var depth := 0
	var cur := n
	while cur != null and cur.requires_node != &"":
		cur = node(cur.requires_node)
		depth += 1
		if depth > 16:
			break
	return depth


## 树的最大深度（列数）。
func max_depth() -> int:
	var out := 0
	for n in nodes:
		out = maxi(out, node_depth(n))
	return out
