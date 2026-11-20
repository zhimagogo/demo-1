class_name DeadState
extends PawnState
## 死亡状态（v16 起两种表现，按阵营分流）：
## - 敌方（野怪）：不再缩小——播死亡动画（KayKit Death_A 0.8s，播完定格倒地姿势），
##   随后模型做贴图溶解（death_dissolve.gdshader 噪声烧蚀）消散，最后 queue_free。
## - 其余单位（村民 / 士兵 / 流民）：维持旧的缩小淡出表现。

const LEGACY_SHRINK_SEC: float = 0.6   # 旧表现：缩小淡出时长
const ANIM_HOLD_SEC: float = 0.95      # 死亡动画播放 + 定格时长（Death_A 0.8s 略留余量）
const DISSOLVE_SEC: float = 0.9        # 贴图溶解时长

var _timer: float = 0.0
var _enemy_death: bool = false         # 敌方走「动画 + 溶解」新表现
var _dissolving: bool = false          # 已进入溶解阶段
var _dissolve_mats: Array[ShaderMaterial] = []


func enter(_msg: Dictionary) -> void:
	_timer = 0.0
	_enemy_death = false
	_dissolving = false
	_dissolve_mats = []
	pawn.velocity = Vector3.ZERO
	pawn.set_dead(true)
	pawn.play_anim(&"dead")
	_enemy_death = pawn.team_comp != null and pawn.team_comp.team == TeamComponent.Team.ENEMY
	# 停掉导航，避免死亡淡出期间还在寻路抽搐
	if pawn.nav_agent != null:
		pawn.nav_agent.target_position = pawn.global_position
	# 关闭物理碰撞：死亡单位不再阻挡其他单位；也避免缩放 0 导致 Jolt 报 singular basis
	var col := pawn.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		col.disabled = true
	# 取消选中
	if pawn.is_selected:
		SelectionManager.remove_from_selection(pawn)
	# 敌方尸体保持原尺寸倒地：顺手关掉描边 / 瞄准高亮等附加表现，只留待溶解的模型
	if _enemy_death:
		pawn.set_aim_highlight(false)
		if pawn.model_rig != null:
			pawn.model_rig.set_outline(false)
		# v27：魂魄离体——青白光点从尸身缓缓升起（与 v16 贴图溶解衔接：先出魂、再消散）
		VFXManager.spawn_effect(&"death_wisp", pawn.global_position + Vector3(0.0, 1.0, 0.0), 0.0,
			{"throttle_key": pawn.get_instance_id()})


func physics_update(delta: float) -> void:
	_timer += delta
	if _enemy_death:
		_update_enemy_death()
	else:
		_update_legacy_shrink()


## 敌方死亡：动画定格 → 换溶解材质 → 逐帧推进 dissolve_progress → 完全消散后释放。
func _update_enemy_death() -> void:
	if not _dissolving:
		if _timer < ANIM_HOLD_SEC:
			return
		_dissolving = true
		if pawn.model_rig != null:
			_dissolve_mats = pawn.model_rig.begin_dissolve()
		if _dissolve_mats.is_empty():
			pawn.queue_free()   # 无模型 / 无可溶网格（如胶囊占位）：直接释放
			return
	var t: float = clampf((_timer - ANIM_HOLD_SEC) / DISSOLVE_SEC, 0.0, 1.0)
	for m in _dissolve_mats:
		if m != null:
			m.set_shader_parameter(&"dissolve_progress", t)
	if t >= 1.0:
		pawn.queue_free()


## 旧表现：缩小淡出。缩到极小但非零：scale=0 会让 CharacterBody3D 的 transform basis 奇异，Jolt 报错。
func _update_legacy_shrink() -> void:
	var s: float = max(0.01, 1.0 - _timer / LEGACY_SHRINK_SEC)
	pawn.scale = Vector3(s, s, s)
	if _timer >= LEGACY_SHRINK_SEC:
		pawn.queue_free()
