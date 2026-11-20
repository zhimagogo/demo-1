class_name IconDB
extends RefCounted
## ============================================================================
## 语义图标库（v6）：把「图标 id」映射到真实美术资源，供全 HUD 复用。
##
## 约定：**图标 id 即文件名**（不含扩展名）——
##     id "res_wood"  →  res://assets/ui/icons/res_wood.png
## 这批 PNG 由资产管线（tools/ 下脚本）从 game-icons.net 的 CC BY 3.0 SVG
## 光栅化而来：去底、统一白色填充（可在运行时用 modulate 任意调色）、128×128。
## 授权与作者逐条记录在 res://assets/ui/icons/icons.json 与 CREDITS.md。
##
## 缺图不报错：get_texture() 返回 null，由 IconRect / IconBadge 回退到
## IconChar 字徽，保证「素材没到位时 UI 依然完整可用」。
## ============================================================================

const ICON_DIR := "res://assets/ui/icons/"

static var _cache: Dictionary = {}
static var _missing: Dictionary = {}


## 图标 id 对应的资源路径（无扩展名约定）。
static func path_for(id: StringName) -> String:
	return ICON_DIR + String(id) + ".png"


## 是否已注册该图标资源。
static func has_icon(id: StringName) -> bool:
	return get_texture(id) != null


## 取图标贴图；缺失返回 null（带缓存，重复调用不重复 IO）。
static func get_texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if _missing.has(id):
		return null
	var p := path_for(id)
	if not ResourceLoader.exists(p):
		_missing[id] = true
		return null
	var res: Resource = ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REUSE)
	if res is Texture2D:
		_cache[id] = res
		return res
	_missing[id] = true
	return null


## 全部已加载成功的 id（仅供调试覆盖层 / 回归测试使用）。
static func loaded_ids() -> Array:
	return _cache.keys()


## 资源图标 id：wood/stone/food/gold → res_*（GameDefs.resource_defs() 的 id 同名映射）。
static func resource_icon(res_id: StringName) -> StringName:
	return StringName("res_" + String(res_id))


## 建筑图标 id：GameDefs.building_defs() 的 id → building_*。
static func building_icon(building_id: StringName) -> StringName:
	return StringName("building_" + String(building_id))


## 清空缓存（回归测试在热重载资源后调用）。
static func clear_cache() -> void:
	_cache.clear()
	_missing.clear()
