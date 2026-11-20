class_name HeroAnimator
extends Node
## ============================================================================
## 主角动画器（动作系统的唯一接缝）。
## 当前无骨骼模型：用 tween 做程序化占位动作（蓄力缩放 / 命中发光闪烁 / 收招回弹）。
## 将来 HeroDef.anim_rig 提供 AnimationPlayer 时，改为委托播放，调用方（HeroComboState 等）不变。
## ============================================================================

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _base_scale: Vector3 = Vector3.ONE
var _anim_player: AnimationPlayer = null   # 将来挂骨骼模型时赋值，play() 会优先委托
var _rig: PawnModelRig = null              # 骨骼动画通道（来自 Pawn.model_rig）；非空时 play() 委托它
var _tween: Tween = null


func setup(mesh: MeshInstance3D, rig: PawnModelRig = null) -> void:
	_mesh = mesh
	_rig = rig
	if _mesh != null:
		_base_scale = _mesh.scale
		_mat = _mesh.material_override as StandardMaterial3D
		if _mat != null:
			# 开启发光（animator 用 emission_energy_multiplier 做命中闪烁；骨骼模型挂载后胶囊隐藏，此特效自动失效）
			_mat.emission_enabled = true
			_mat.emission = _mat.albedo_color
			_mat.emission_energy_multiplier = 0.0


## 优先委托骨骼动画（PawnModelRig 挂载主角模型后）；无骨骼时回退 tween 占位（保留命中发光特效）。
func play(anim_id: StringName, opts: Dictionary = {}) -> void:
	if anim_id == &"":
		return
	if _rig != null and _rig.has_anim(anim_id):
		_rig.play(anim_id, 0.08)
		return
	match String(anim_id):
		"combo_light": _squash(1.12, 0.5)
		"combo_heavy": _squash(1.30, 1.0)
		"skill_aoe": _pulse()
		"skill_dash": _stretch()
		"dead": _shrink()
		_: pass


func _kill_active() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


# 命中：纵向顶拉伸 → 回弹 + 发光闪
func _squash(intensity: float, flash: float) -> void:
	if _mesh == null:
		return
	_kill_active()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_mesh, "scale", _base_scale * intensity, 0.05).set_trans(Tween.TRANS_QUART)
	if _mat != null:
		_tween.tween_property(_mat, "emission_energy_multiplier", flash, 0.0)
	_tween.chain().tween_property(_mesh, "scale", _base_scale, 0.14).set_ease(Tween.EASE_OUT)
	if _mat != null:
		_tween.parallel().tween_property(_mat, "emission_energy_multiplier", 0.0, 0.18)


# 旋风：放大脉动 + 持续发光
func _pulse() -> void:
	if _mesh == null:
		return
	_kill_active()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_mesh, "scale", _base_scale * 1.15, 0.12).set_trans(Tween.TRANS_QUART)
	if _mat != null:
		_tween.tween_property(_mat, "emission_energy_multiplier", 0.9, 0.05)
	_tween.chain().tween_property(_mesh, "scale", _base_scale, 0.30)
	if _mat != null:
		_tween.parallel().tween_property(_mat, "emission_energy_multiplier", 0.0, 0.35)


# 冲锋：前后拉伸
func _stretch() -> void:
	if _mesh == null:
		return
	_kill_active()
	_tween = create_tween()
	_tween.tween_property(_mesh, "scale", _base_scale * Vector3(0.9, 1.2, 0.9), 0.08)
	_tween.tween_property(_mesh, "scale", _base_scale, 0.22)


# 死亡：缩小
func _shrink() -> void:
	if _mesh == null:
		return
	_kill_active()
	_tween = create_tween()
	_tween.tween_property(_mesh, "scale", _base_scale * 0.3, 0.30)
