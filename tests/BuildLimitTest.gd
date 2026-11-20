extends Node
## ============================================================================
## v37 建筑数量上限专项回归（酒馆 / 龙园全场唯一）：
##   godot --headless --path . tests/BuildLimitTest.tscn --log-file /private/tmp/a-limit.log --fixed-fps 60
##
## 需求覆盖（「龙园和酒馆只能建造一个」）：
##   0. 数据契约：酒馆 / 龙园 max_count = 1；木墙 / 房屋 = 0（不限量）；旧字段完好（造价/占地/光环）。
##   A. 酒馆唯一：首座落地成功；第二座（不同空位）被拒 —— 场上仍 1 座、金币分文未扣、模型未生成。
##   B. 建造菜单联动：达上限后卡片置灰 + 造价芯片显「满」+ tooltip 追加上限说明。
##   C. 拆除后释放：酒馆被摧毁 → 计数归零、卡片重新可点、原地重建成功并正常扣费。
##   D. 龙园唯一：3×3 龙园同款拦截（另一栋建筑用同一套机制）；同时校验「达上限」不影响其他建筑卡片的可负担性联动。
##   E. 上限不阻断预览外的合法路径：木墙 / 房屋等不限量建筑照常可建（正向对照）。
##
## 输出：PASS/FAIL 消息为英文；中文仅出现在「满」这类被测 UI 文案与 push_error 详情里
## （headless 日志实测可正常显示中文）。
## ============================================================================

const TAVERN_SPOT := Vector3(8.0, 0.0, -4.0)      # 城内 3×3 空缺（v43 酒馆放大后）
const TAVERN_SPOT_2 := Vector3(8.0, 0.0, -14.0)   # 另一处空位：第二座酒馆应在此被拒（距主角出生点 <=20m）
const HOUSE_SPOT := Vector3(16.4, 0.0, 16.4)      # 房屋（不限量）对照位（3×3）

var _failures: int = 0
var _main: Node
var _build: BuildSystem
var _menu: BuildMenu
var _tavern_def: BuildingDef
var _garden_def: BuildingDef
var _house_def: BuildingDef


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		_failures += 1
		push_error("FAIL: " + message)


func _run() -> void:
	_main = load("res://scenes/main/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().physics_frame
	var world := _main.get_node("WorldRoot") as Node3D
	# v42：玩家默认俯视角主控，建造预览跟随**OS 鼠标**——headless 下鼠标固定在屏幕角，
	# 准星落点会跑到城外（预览恒红）。本文件只验证「数量上限」，用脚本接口进第三人称，
	# 让预览锚在屏幕中心准星上（与 v42 之前一致），几何判定不走鼠标。
	var hc := world.get_node("HeroController") as HeroController
	hc.enter_hero_mode()
	await get_tree().physics_frame
	_build = world.get_node("BuildSystem") as BuildSystem
	# 冻结随机源（野怪 / 资源再生 / 流民），并关掉新手引导（引导信息步会占用 ui_modal_count）
	for sys_name in ["WildlifeSpawner", "ResourceGrowthSystem", "SettlementSystem"]:
		var sys := world.get_node_or_null(sys_name)
		if sys != null:
			sys.set_process(false)
			sys.set_physics_process(false)
	var tutorial := get_tree().get_first_node_in_group("tutorial_system") as TutorialSystem
	if tutorial != null:
		tutorial.skip()
	_menu = _hud().build_menu
	# 依赖缺失就直接判失败退出：绝不能让运行期错误打断协程（那样永远到不了 quit，整批挂到超时）
	if _build == null or _menu == null:
		push_error("FAIL: BuildSystem / BuildMenu missing - cannot run build limit regression")
		get_tree().quit(1)
		return
	TimeManager.game_seconds = 10.0 / 24.0 * TimeManager.seconds_per_day   # 固定白天
	ResourceManager.add(GameDefs.GOLD, 1000)
	await get_tree().physics_frame

	# ================= 0. 数据契约 =================
	for d in GameDefs.building_defs():
		match d.id:
			&"tavern":
				_tavern_def = d
			&"dragon_garden":
				_garden_def = d
			&"house":
				_house_def = d
	_check(_tavern_def != null and _tavern_def.max_count == 1, "tavern def: max_count = 1 (%s)" % _limit_text(_tavern_def))
	_check(_garden_def != null and _garden_def.max_count == 1, "dragon garden def: max_count = 1 (%s)" % _limit_text(_garden_def))
	var unlimited := true
	for d in GameDefs.building_defs():
		if d.id != &"tavern" and d.id != &"dragon_garden" and d.max_count != 0:
			unlimited = false
	_check(unlimited, "wall/house stay unlimited (max_count = 0)")
	_check(_tavern_def != null and _tavern_def.is_tavern and _tavern_def.footprint == Vector2i(3, 3)
			and _tavern_def.cost[GameDefs.GOLD] == 50, "tavern def intact (3x3 / 50 gold / is_tavern)")
	_check(_garden_def != null and _garden_def.is_dragon_garden and _garden_def.footprint == Vector2i(4, 4)
			and _garden_def.cost[GameDefs.GOLD] == 120, "dragon garden def intact (4x4 / 120 gold / is_dragon_garden)")
	_check(_menu != null, "build menu found in HUD (for card assertions)")

	# ================= A. 酒馆唯一（第二座被拒且不扣费） =================
	_check(not _build.build_limit_reached(_tavern_def), "tavern: unlimited before first build")
	# 摆放点自检（与 try_place_at 同口径）：否则「第二座被拒」可能只是「这里本来就放不下」的假通过
	_check(_spot_legal(TAVERN_SPOT, _tavern_def.footprint), "TAVERN_SPOT itself is a legal 3x3 spot")
	_check(_spot_legal(TAVERN_SPOT_2, _tavern_def.footprint), "TAVERN_SPOT_2 itself is a legal 3x3 spot")
	var gold_0: int = ResourceManager.get_amount(GameDefs.GOLD)
	_build.enter_build_mode(_tavern_def)
	# 预览基线：上限未满 + 有空位 + 钱够 → ghost 应为绿（与后面的红对照，避免断言恒真）
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_build.preview != null and _build.preview.is_valid, "preview ghost is valid before the cap is reached")
	_build.try_place_at(TAVERN_SPOT)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var n_after_first: int = _count(&"tavern")
	_check(n_after_first == 1, "first tavern placed (%d)" % n_after_first)
	_check(ResourceManager.get_amount(GameDefs.GOLD) == gold_0 - 50, "first tavern charged 50 gold (%d -> %d)" % [
		gold_0, ResourceManager.get_amount(GameDefs.GOLD)])
	_check(_build.build_limit_reached(_tavern_def), "tavern: at limit right after first build")
	_check(GameDefs.building_at_limit(get_tree(), _tavern_def), "static GameDefs.building_at_limit() agrees")
	# 预览门（v37：达上限时 ghost 必须变红）——等待 _process 跑一轮后再读
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_build.preview != null and not _build.preview.is_valid,
		"preview ghost turns invalid at limit")

	var gold_before_reject: int = ResourceManager.get_amount(GameDefs.GOLD)
	var total_before_reject: int = _count()
	_build.try_place_at(TAVERN_SPOT_2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count(&"tavern") == 1, "second tavern rejected: still 1 tavern (%d)" % _count(&"tavern"))
	_check(_count() == total_before_reject, "second tavern rejected: no building object created (%d)" % _count())
	_check(ResourceManager.get_amount(GameDefs.GOLD) == gold_before_reject,
		"second tavern rejected: no gold charged (%d)" % ResourceManager.get_amount(GameDefs.GOLD))

	# ================= B. 建造菜单联动（置灰 / 「满」芯片 / tooltip） =================
	var btn := _card(&"tavern")
	_check(btn != null and btn.disabled, "build menu: tavern card greyed out at limit")
	_check(_cost_text(&"tavern") == "满", "build menu: tavern cost chip reads 满 (%s)" % _cost_text(&"tavern"))
	_check(btn != null and btn.tooltip_text.contains("已达上限"),
		"build menu: tavern tooltip warns about the limit")
	var house_btn := _card(&"house")
	_check(house_btn != null and not house_btn.disabled, "build menu: unlimited house card stays clickable")

	# ================= C. 拆除后释放上限（可原地重建） =================
	var destroyed := _destroy_all(&"tavern")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(destroyed == 1, "tavern destroyed for the rebuild check (%d)" % destroyed)
	_check(_count(&"tavern") == 0 and not _build.build_limit_reached(_tavern_def),
		"limit released after tavern destroyed (count=%d)" % _count(&"tavern"))
	_check(_card(&"tavern") != null and not _card(&"tavern").disabled, "build menu: tavern card re-enabled after destroy")
	_check(_cost_text(&"tavern") == "50", "build menu: cost chip restored to 50 after destroy (%s)" % _cost_text(&"tavern"))
	var gold_before_rebuild: int = ResourceManager.get_amount(GameDefs.GOLD)
	_build.enter_build_mode(_tavern_def)
	_build.try_place_at(TAVERN_SPOT)          # 原地重建：占格已在 building_removed 时释放
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count(&"tavern") == 1, "tavern rebuilt on the same spot (%d)" % _count(&"tavern"))
	_check(ResourceManager.get_amount(GameDefs.GOLD) == gold_before_rebuild - 50,
		"rebuild charged 50 gold (%d -> %d)" % [gold_before_rebuild, ResourceManager.get_amount(GameDefs.GOLD)])

	# ================= D. 龙园唯一（4×4，同一套机制） =================
	_build.enter_build_mode(_garden_def)
	var garden_spot := _find_garden_spot()
	_check(garden_spot != Vector3.INF, "found a legal 4x4 spot inside the city for the garden")
	if garden_spot != Vector3.INF:
		_build.try_place_at(garden_spot)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(_count(&"dragon_garden") == 1, "first dragon garden placed (%d)" % _count(&"dragon_garden"))
		var total_before: int = _count()
		var gold_before: int = ResourceManager.get_amount(GameDefs.GOLD)
		var spot_b: Vector3 = _find_garden_spot()
		# 第二座必须「本来合法、却因上限被拒」——空位不存在时直接判失败，避免断言静默退化
		_check(spot_b != Vector3.INF, "found a second legal 4x4 spot for the rejection probe")
		if spot_b != Vector3.INF:
			_build.try_place_at(spot_b)
			await get_tree().physics_frame
			await get_tree().physics_frame
		_check(_count(&"dragon_garden") == 1, "second dragon garden rejected (%d)" % _count(&"dragon_garden"))
		_check(_count() == total_before, "second dragon garden created no object (%d)" % _count())
		_check(ResourceManager.get_amount(GameDefs.GOLD) == gold_before,
			"second dragon garden charged nothing (%d)" % ResourceManager.get_amount(GameDefs.GOLD))
		_check(_build.build_limit_reached(_garden_def), "dragon garden: at limit")
		_check(_card(&"dragon_garden") != null and _card(&"dragon_garden").disabled,
			"build menu: dragon garden card greyed out at limit")
		_check(_cost_text(&"dragon_garden") == "满",
			"build menu: dragon garden cost chip reads 满 (%s)" % _cost_text(&"dragon_garden"))
		# 拆除 → 释放（与酒馆同源判定，这里只验计数与卡片）
		_destroy_all(&"dragon_garden")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(_count(&"dragon_garden") == 0 and not _build.build_limit_reached(_garden_def),
			"limit released after dragon garden destroyed (count=%d)" % _count(&"dragon_garden"))

	# ---- 可负担性联动未被上限逻辑破坏：金币清零 → 房屋卡置灰；补钱 → 恢复 ----
	ResourceManager.spend(GameDefs.GOLD, ResourceManager.get_amount(GameDefs.GOLD))
	_menu.call("_refresh_affordability")
	_check(_card(&"house") != null and _card(&"house").disabled, "affordability: house card greyed out with 0 gold")
	ResourceManager.add(GameDefs.GOLD, 500)
	_menu.call("_refresh_affordability")
	_check(_card(&"house") != null and not _card(&"house").disabled, "affordability: house card restored once gold is back")
	# 此时场上仍立着 C 段重建的那座酒馆 → 酒馆卡应保持「已达上限」置灰（与金币多少无关）
	_check(_card(&"tavern") != null and _card(&"tavern").disabled and _cost_text(&"tavern") == "满",
		"tavern card stays at-limit even with plenty of gold (%s)" % _cost_text(&"tavern"))
	_check(_card(&"dragon_garden") != null and not _card(&"dragon_garden").disabled,
		"dragon garden card clickable after its destruction")

	# ================= E. 正向对照：不限量建筑照常可建（上限没有误伤） =================
	_check(_spot_legal(HOUSE_SPOT, _house_def.footprint), "HOUSE_SPOT itself is a legal 3x3 spot")
	var houses_before: int = _count(&"house")
	_build.enter_build_mode(_house_def)
	_build.try_place_at(HOUSE_SPOT)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_count(&"house") == houses_before + 1,
		"unlimited house still builds fine (%d -> %d)" % [houses_before, _count(&"house")])
	_check(not _build.build_limit_reached(_house_def), "house (max_count 0) never reports at-limit")
	_check(_card(&"house") != null and not _card(&"house").disabled, "house card stays clickable after building one")

	print("BUILD LIMIT: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


# ---- 测试辅助 ----

func _hud() -> Node:
	for c in _main.get_children():
		if c.get("build_menu") != null:
			return c
	return null


func _count(id: StringName = &"") -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b):
			continue
		if id == &"" or (b as Building).def.id == id:
			n += 1
	return n


func _card(id: StringName) -> Button:
	if _menu == null:
		return null
	return _menu.get_card_button(id)


## 卡片的造价芯片文本（达上限时应为「满」，否则为价格数字）。
func _cost_text(id: StringName) -> String:
	if _menu == null:
		return ""      # HUD 缺失时不要在这里炸：留给 _check 断言失败，并保证仍能走到 quit()
	for entry in _menu.get("_cards"):
		if (entry["def"] as BuildingDef).id != id:
			continue
		for rid in (entry["cost_labels"] as Dictionary):
			return ((entry["cost_labels"] as Dictionary)[rid] as Label).text
	return ""


## 某世界点是否满足 placed 前的全部几何条件（与 BuildSystem.try_place_at 同口径，
## 只差「金币够不够」与「数量上限」两条非几何判定）。
func _spot_legal(ground: Vector3, footprint: Vector2i) -> bool:
	var grid := _build.grid
	var cell := grid.world_to_grid(ground)
	if not grid.is_inside(cell) or not grid.can_place(cell, footprint):
		return false
	if not (_build.call("_footprint_in_city", cell, footprint) as bool):
		return false
	return _build.call("_within_build_range", ground) as bool


## 摧毁场上某类建筑的全部实例（直接打血；建筑 died → queue_free 是既有链路）。
func _destroy_all(id: StringName) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("building"):
		if not is_instance_valid(b):
			continue
		var bd := b as Building
		if bd == null or bd.def == null or bd.def.id != id:
			continue
		bd.health.apply_damage(99999.0)
		n += 1
	return n


## 找一个能落 4×4 龙园的空位（与 tools/v29_dragon_shot.gd 同款做法：试到成功为止）。
## 走 _spot_legal（与 BuildSystem.try_place_at 同口径），确保「第二座被拒」是真的被上限拒。
## v43：龙园 3×3 → 4×4，城市半宽 26m，扫描范围放宽到 ±28m。
func _find_garden_spot() -> Vector3:
	_build.enter_build_mode(_garden_def)
	var fp := Vector2i(4, 4)
	for x in range(-7, 8):
		for z in range(-7, 8):
			var cand := Vector3(float(x) * 4.0 + 1.0, 0.0, float(z) * 4.0 + 1.0)
			if _spot_legal(cand, fp):
				return cand
	return Vector3.INF


func _limit_text(def: BuildingDef) -> String:
	return "none" if def == null else str(def.max_count)
