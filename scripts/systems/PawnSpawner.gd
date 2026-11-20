extends Node
## 统一单位出生入口。
## 主场景、兵营与野怪刷新器均通过此节点创建单位，避免重复处理子类选择、容器挂载与格子寻路吸附。

var player_container: Node3D
var enemy_container: Node3D
const RefugeeScript = preload("res://scripts/entities/pawn/Refugee.gd")


func _ready() -> void:
	add_to_group("pawn_spawner")


func configure(player_pawns: Node3D, enemy_pawns: Node3D) -> void:
	player_container = player_pawns
	enemy_container = enemy_pawns


func spawn_colonist(at: Vector3) -> Colonist:
	var pawn := Colonist.new()
	pawn.position = at
	_add_player_pawn(pawn)
	return pawn


func spawn_refugee(at: Vector3) -> Pawn:
	var pawn: Pawn = RefugeeScript.new()
	pawn.position = _snap_to_navigation(at)
	_add_player_pawn(pawn)
	return pawn


func spawn_hero(at: Vector3) -> Hero:
	var pawn := Hero.new()
	pawn.name = "Hero"
	pawn.position = at
	_add_player_pawn(pawn)
	return pawn


func spawn_soldier(pawn_def: PawnDef, at: Vector3) -> Pawn:
	var pawn: Pawn = SoldierRanged.new() if pawn_def.attack_kind == PawnDef.AttackKind.RANGED else SoldierMelee.new()
	pawn.def = pawn_def
	pawn.position = _snap_to_navigation(at)
	_add_player_pawn(pawn)
	return pawn


## 生成野怪。可注入 def 变体（普通 / 精英 / 头目）；默认掠夺者。
func spawn_raider(at: Vector3, pawn_def: PawnDef = null) -> Raider:
	var pawn := Raider.new()
	if pawn_def != null:
		pawn.def = pawn_def
	pawn.position = _snap_to_navigation(at)
	if enemy_container != null:
		enemy_container.add_child(pawn)
	else:
		push_warning("PawnSpawner: 未配置敌人容器，无法生成野怪")
		pawn.queue_free()
	return pawn


## 生成出战巨龙（v26 驯龙系统；DragonSystem.deploy 调用）。
func spawn_dragon(dragon_def: DragonDef, at: Vector3) -> DragonPet:
	var pet := DragonPet.new()
	pet.name = "DragonPet"
	pet.def = dragon_def
	pet.position = _snap_to_navigation(at)
	_add_player_pawn(pet)
	return pet


func _add_player_pawn(pawn: Pawn) -> void:
	if player_container != null:
		player_container.add_child(pawn)
	else:
		push_warning("PawnSpawner: 未配置玩家单位容器，无法生成单位")
		pawn.queue_free()


func _snap_to_navigation(raw: Vector3) -> Vector3:
	var nav := get_tree().get_first_node_in_group("nav_system") as NavSystem
	return nav.snap_to_walkable(raw) if nav != null else raw
