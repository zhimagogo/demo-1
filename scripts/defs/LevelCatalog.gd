class_name LevelCatalog
extends RefCounted
## ============================================================================
## 关卡目录（v38）：关卡系统的唯一数据源。
##
## 关卡选择地图（LevelSelect）、主菜单入口、Main.gd 的关卡分流、
## 进度读写（LevelRuntime）全部从这里取数据——新增关卡只改本文件。
##
## 当前目录（对应关卡选择地图上的五座岛）：
##   · prologue —— 序章·故土残火（绿岛，可玩，3 星）—— v38 新做的剧情关；
##   · sandbox  —— 测试关卡·沙盒战场（岩岛，可玩，无星级判定）—— 旧 Main 世界保留为测试场；
##   · ch1/ch2/ch3 —— 后续章节（林/沙/雪岛）—— 暂未开放，只有简介与星级上限。
## ============================================================================

const PROLOGUE_ID := &"prologue"
const SANDBOX_ID := &"sandbox"

const MAIN_SCENE := "res://scenes/main/Main.tscn"

## 关卡选择地图场景（v38：3D 世界地图，小人走上去选关；主菜单入口 / 关卡归来出口都指向它）。
const LEVEL_SELECT_SCENE := "res://scenes/main/LevelSelect3D.tscn"


## 全部关卡，顺序 = 关卡选择地图上的推荐顺序。
static func all() -> Array[LevelDef]:
	var levels: Array[LevelDef] = []

	# ---- 序章（v38 首个剧情关）：一张小规模、有剧本的线性关 ----
	var prologue := LevelDef.new()
	prologue.id = PROLOGUE_ID
	prologue.chapter = "序章"
	prologue.title = "故土残火"
	prologue.subtitle = "王国只剩你一人，夺回要塞，点燃复国的第一簇火。"
	prologue.desc = "十年流亡，一剑归乡。\n清剿城下的匪徒，在旧日要塞重立王旗。"
	prologue.kind = LevelDef.Kind.PROLOGUE
	prologue.scene_path = MAIN_SCENE
	prologue.map_pos = Vector2(0.335, 0.455)
	prologue.region = LevelDef.REGION_GREEN
	prologue.star_total = 3
	prologue.objectives = PackedStringArray([
		"清剿盘踞故土的 4 名匪徒",
		"收复主城：走到城堡 8 米内",
	])
	prologue.star_hints = PackedStringArray([
		"完成序章",
		"全程未阵亡",
		"90 秒内完成",
	])
	levels.append(prologue)

	# ---- 测试关卡：旧沙盒世界，作为随时可进的测试场保留 ----
	var sandbox := LevelDef.new()
	sandbox.id = SANDBOX_ID
	sandbox.chapter = "测试"
	sandbox.title = "沙盒战场"
	sandbox.subtitle = "无剧本、无终点的开放沙盒，全部系统都在这里。"
	sandbox.desc = "白昼筑城，长夜守疆。\n经营城邦、招募伙伴，与巨龙一同守住王国。"
	sandbox.kind = LevelDef.Kind.SANDBOX
	sandbox.scene_path = MAIN_SCENE
	sandbox.map_pos = Vector2(0.30, 0.165)
	sandbox.region = LevelDef.REGION_ROCK
	sandbox.star_total = 0   # 沙盒不做星级判定，地图芯片显示「测试」
	sandbox.objectives = PackedStringArray([
		"自由经营：建造房屋吸引流民定居",
		"守住夜潮：主城生命归零即失败",
	])
	sandbox.star_hints = PackedStringArray()
	levels.append(sandbox)

	# ---- 后续章节：暂未开放（地图上先摆出来，只有简介与星级上限）----
	levels.append(_coming_soon(&"ch1", "第一章", "边境烽烟",
		"边境村落燃起狼烟，第一批流民正在往要塞赶。",
		Vector2(0.565, 0.205), LevelDef.REGION_FOREST, 6))
	levels.append(_coming_soon(&"ch2", "第二章", "盐碱商道",
		"穿过盐碱商道，把金币与粮食运回王国。",
		Vector2(0.855, 0.275), LevelDef.REGION_DESERT, 6))
	levels.append(_coming_soon(&"ch3", "第三章", "霜牙峡谷",
		"峡谷深处的霜牙部族正在集结。",
		Vector2(0.745, 0.760), LevelDef.REGION_SNOW, 6))

	return levels


static func _coming_soon(lid: StringName, chapter: String, title: String, desc: String,
		pos: Vector2, region: StringName, stars: int) -> LevelDef:
	var level := LevelDef.new()
	level.id = lid
	level.chapter = chapter
	level.title = title
	level.subtitle = "剧情关卡 · 制作中"
	level.desc = desc + "\n（关卡内容尚未制作，敬请期待。）"
	level.kind = LevelDef.Kind.COMING_SOON
	level.scene_path = ""
	level.map_pos = pos
	level.region = region
	level.star_total = stars
	level.objectives = PackedStringArray(["剧情关卡 · 制作中"])
	level.star_hints = PackedStringArray()
	return level


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for level in all():
		out.append(level.id)
	return out


static func get_level(lid: StringName) -> LevelDef:
	for level in all():
		if level.id == lid:
			return level
	return null


static func has_level(lid: StringName) -> bool:
	return get_level(lid) != null


## 序章关卡（首个剧情关）；目录被改坏时返回 null。
static func prologue() -> LevelDef:
	return get_level(PROLOGUE_ID)


## 测试/沙盒关卡（默认回落的关卡）。
static func sandbox() -> LevelDef:
	return get_level(SANDBOX_ID)
