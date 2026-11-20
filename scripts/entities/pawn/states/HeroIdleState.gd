class_name HeroIdleState
extends PawnState
## 主角待机（第三人称操控下）：
## - WASD 直接操控：velocity = pawn.desired_velocity（不走 NavMesh，物理碰撞挡障碍）
## - 重力 / 跳跃：落地贴地，空中按 24m/s² 下坠（HeroController 写入跳跃请求）
## - 朝向始终对齐相机前方（aim_dir）：支持倒退跑 / 侧移跑而不转身
## - 普攻 / 技能由 HeroController 触发 request_*，进而切到 hero_combo / hero_skill

const GRAVITY: float = 24.0   # 下坠重力（比真实 9.8 快，游戏感更利落）
const JUMP_SPEED: float = 7.2 # 起跳速度（与 HeroController.JUMP_SPEED 保持一致）


func enter(_msg: Dictionary) -> void:
	pawn.velocity = Vector3.ZERO


func physics_update(delta: float) -> void:
	var h := pawn as Hero
	if h == null:
		return
	var v := h.desired_velocity
	# 重力：落地清零竖直速度并消费跳跃请求；空中持续下坠
	if h.is_on_floor():
		if v.y < 0.0:
			v.y = 0.0
		if h.consume_jump():
			v.y = JUMP_SPEED
			AudioManager.play_sfx(&"jump", h.global_position)
	else:
		v.y = h.velocity.y - GRAVITY * delta
	h.velocity = v
	h.play_anim(&"run" if Vector2(h.velocity.x, h.velocity.z).length_squared() > 0.04 else &"idle")
	# v27：冲刺扬尘——超速移动（Shift 冲刺 ×1.5）且在地面时脚下扬起小股尘土（0.22s 节流）
	var planar_speed := Vector2(h.velocity.x, h.velocity.z).length()
	if h.is_on_floor() and planar_speed > h.move_speed * 1.15:
		VFXManager.spawn_effect(&"sprint_dust", h.global_position + Vector3(0.0, 0.15, 0.0), 0.0,
			{"throttle_key": h.get_instance_id(), "throttle_time": 0.22})
	# 第三人称：角色面向相机前方（不随移动方向转身，可倒退跑）
	if h.aim_dir.length_squared() > 0.001:
		h.look_at_target(h.aim_dir)
	h.move_and_slide()
