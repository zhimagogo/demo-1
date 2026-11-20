class_name SoldierMelee
extends Soldier
## 近战小兵载体：定居流民觉醒的近战职业（战士 / 刺客）挂本类，贴身站定砍（基础 FightState）。
## v21 前兵营还招募「近战兵」，兵营删除后本类不再有专属默认兵种——
## 定居职业 def 由 SettlementSystem 经 PawnSpawner.spawn_soldier 显式注入。

func _ready() -> void:
	if def == null:
		def = GameDefs.settler_warrior_def()   # 兜底：未注入 def 时按战士处理
	super._ready()
