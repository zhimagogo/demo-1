class_name StunnedState
extends PawnState
## ============================================================================
## 受控状态（v33）：被跳劈等技能击飞 / 眩晕期间的状态。
##
## 进入方式唯一：`Pawn.apply_knockup()`（其它模块不要直接 transition_to("stunned")，
## 否则抛物线参数未初始化，tick_control 会立即返回 false）。
## 推进逻辑在 Pawn.tick_control：滞空段直接写 global_position 走抛物线，
## 落地后原地眩晕倒计时；返回 false = 控制结束 → 回 idle 交还自主 AI。
## ============================================================================


func enter(_msg: Dictionary) -> void:
	# 击飞瞬间清零速度：水平位移完全由 tick_control 的抛物线接管，
	# 不清零会与上一帧的行走 / 追击速度叠加，飞出去的距离不可控。
	pawn.velocity = Vector3.ZERO
	pawn.play_anim(&"hit")


func physics_update(delta: float) -> void:
	# 返回 false = 滞空 + 落地眩晕都结束 → 回待命（各子类的 idle 决策路由接管）
	if not pawn.tick_control(delta):
		state_machine.transition_to("idle")
