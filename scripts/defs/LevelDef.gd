class_name LevelDef
extends Resource
## ============================================================================
## 关卡定义（v38 关卡系统）。
##
## 一个「关卡」= 一条可进入的玩法线：进入哪个场景、在关卡选择地图上落在哪座岛、
## 有没有星级判定、玩法目标是什么。全部数据在代码里定义（见 LevelCatalog），
## 与 GameDefs 同范式：加关卡 = 加一条 Def，不改 UI / 不改运行时代码。
##
## 三种 kind：
##   · PROLOGUE    —— 有剧本的线性关卡（v38 首个：序章），由 PrologueDirector 驱动；
##   · SANDBOX     —— 开放式自由沙盒（当前的 Main 世界，作为「测试关卡」保留入口）；
##   · COMING_SOON —— 暂未开放：地图上可见、可查看简介，但不能进入。
##
## 地图坐标 map_pos 是归一化坐标（0~1，x 向右、y 向下），由 LevelSelect3D 换算成 3D
## 世界坐标——关卡旗子与它所在的岛屿共用同一套坐标，改一个数值即可整体挪动。
## ============================================================================

enum Kind { PROLOGUE, SANDBOX, COMING_SOON }

## 岛屿配色 id（LevelSelect3D 里登记了对应色板：green / forest / desert / snow / rock）。
const REGION_GREEN := &"green"
const REGION_FOREST := &"forest"
const REGION_DESERT := &"desert"
const REGION_SNOW := &"snow"
const REGION_ROCK := &"rock"

@export var id: StringName = &""
@export var chapter: String = ""                 # 章节标："序章" / "第一章" / "测试"
@export var title: String = ""                   # 关卡名："故土残火"
@export var subtitle: String = ""                # 一句话副标（信息面板标题下）
@export var desc: String = ""                    # 关卡简介（信息面板正文）
@export var kind: int = Kind.COMING_SOON
@export var scene_path: String = ""              # 空 = 不可进入（COMING_SOON 一律为空）
@export var map_pos: Vector2 = Vector2(0.5, 0.5) # 关卡选择地图上的归一化坐标
@export var region: StringName = REGION_GREEN    # 所属岛屿
@export var star_total: int = 3                  # 星级上限（0 = 不做星级判定，地图上显示「测试」芯片）
@export var objectives: PackedStringArray = PackedStringArray()   # 玩法目标（信息面板列表）
@export var star_hints: PackedStringArray = PackedStringArray()   # 星级条件（每条一星）


## 能否进入对局：必须既可玩、又配了场景路径。
func is_playable() -> bool:
	return kind != Kind.COMING_SOON and scene_path != ""


func is_coming_soon() -> bool:
	return kind == Kind.COMING_SOON


## 地图芯片文案：有星级 = "n/上限"，无星级 = "测试"。
func chip_text(stars: int) -> String:
	if star_total <= 0:
		return "测试"
	return "%d/%d" % [clampi(stars, 0, star_total), star_total]


## 面板上的类型标签。
func kind_label() -> String:
	match kind:
		Kind.PROLOGUE:
			return "剧情关卡"
		Kind.SANDBOX:
			return "自由沙盒"
		_:
			return "暂未开放"
