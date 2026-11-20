class_name SoldierRanged
extends Soldier
## 远程小兵载体：定居流民觉醒的远程职业（法师 / 游侠）挂本类，风筝 AI
## （同名替换 fight 状态为 RangedFightState），攻击为飞行箭矢投射物
## （AttackerComponent 按 attack_kind=RANGED 分叉）。
## v21 前兵营还招募「远程兵」，兵营删除后本类不再有专属默认兵种——
## 定居职业 def 由 SettlementSystem 经 PawnSpawner.spawn_soldier 显式注入。

func _ready() -> void:
	if def == null:
		def = GameDefs.settler_archer_def()   # 兜底：未注入 def 时按游侠处理
	super._ready()


func _setup_nodes() -> void:
	# super（Soldier）已安装生活状态；远程职业再把 fight 换成风筝版
	super._setup_nodes()
	state_machine.register_state("fight", RangedFightState.new())
