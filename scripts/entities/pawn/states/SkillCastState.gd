class_name SkillCastState
extends PawnState
## ============================================================================
## v33 施法状态（skills-dev）：前摇 / 吟唱 / 跳劈滞空 / 收招的载体。
##
## 进入方式：Pawn.begin_skill_cast(skill, target) →
##   state_machine.transition_to("skill_cast", {"skill": def, "target": node})
## 本状态只做两件事：
##   ① 每物理帧把 delta 交给 PawnSkillComponent.tick_cast()，由组件推进
##      「前摇 → 执行 → 收招」，结算完成后组件回调 pawn.end_skill_cast()
##      （由 Pawn 决定回 fight 还是 idle）；
##   ② 被强制切出（死亡 / 眩控 / 其它系统抢占）时若仍在施法 → abort_cast()：
##      不结算效果、解除技能锁定（跳劈滞空被打断还会放回地面）。
## 节点名固定 "skill_cast"（Pawn._setup_nodes 注册；状态名即跳转名）。
## ============================================================================

var skill: PawnSkillDef = null   # 本次施放的技能（enter 时锁定）
var target: Node = null          # 本次施放的目标（enter 时锁定，中途可能失效）


func enter(msg: Dictionary) -> void:
	skill = msg.get("skill", null) as PawnSkillDef
	target = msg.get("target", null)


func physics_update(delta: float) -> void:
	var comp := _component()
	if comp == null:
		# 异常路径（宿主没有技能组件）：别把单位永久卡在施法态
		if state_machine != null:
			state_machine.transition_to("idle")
		return
	comp.tick_cast(delta)


func exit() -> void:
	var comp := _component()
	if comp != null and comp.is_casting():
		comp.abort_cast()


## 宿主技能组件（Pawn.skill_comp；字段在 Pawn 基类声明，类型安全）。
func _component() -> PawnSkillComponent:
	if pawn == null or not is_instance_valid(pawn):
		return null
	return (pawn as Pawn).skill_comp
