class_name PawnModelRig
extends Node3D
## ============================================================================
## Pawn 骨骼模型 + 动画挂载组件（占位美术通道）。
## 运行时加载 .glb、取出 AnimationPlayer，把「项目状态/动作名」映射到 glTF 动画名播放。
## 这是 Pawn 的纯美术子树：位置 / 朝向 / 碰撞与战斗判定始终由 Pawn 本体负责。
##
## 这是「占位美术」的唯一加载点：将来换正式美术只需替换 res://assets/_PLACEHOLDER/
## 下的 .glb（或改 GameDefs.model_path），并按新资源的动画名更新 ANIM_CANDIDATES，调用方不变。
##
## 加载策略：优先 load()（编辑器自动导入的 PackedScene，glTF 动画导入最可靠）；
##   失败回退 GLTFDocument 运行时解析（不依赖编辑器导入缓存，便于换文件即生效）。
## ============================================================================

# 项目状态名 / 动作名 → **候选 glTF 动画名数组**（按序取第一个在该模型里存在的）。
# 为什么是数组：本仓库同时挂着两套美术来源，动画命名完全不同——
#   ① KayKit 人形（主角 / 士兵 / 村民 / 流民）：Idle / Walking_A / Running_A / 1H_Melee_Attack_* / Death_A
#   ② Quaternius 怪物（野怪，CC0）：Idle / Walk / Run / Punch / Death（Big·Blob 组）、
#      Flying_Idle / Fast_Flying / Headbutt / Death（Flying 组）
# 用一个全局字典只能保一套，故「按序回退」——两套互不误命中（KayKit 76 条动画里没有裸名
# Punch / Walk / Death / Flying_Idle，Quaternius 也没有 Walking_A / Death_A）。
# 注意 `Death` 候选排在 `Death_A` 之后：KayKit 无裸名 Death，怪物无 Death_A，不会互相抢。
# 想让某个 def 单独覆盖，用 PawnDef.anim_map（优先级更高，见 setup()）。
const ANIM_CANDIDATES := {
	# 基础状态（所有 Pawn 共享）
	&"idle": ["Idle"],
	&"move": ["Walking_A", "Walk", "Flying_Idle", "Fast_Flying"],
	&"run": ["Running_A", "Run", "Walk", "Fast_Flying", "Flying_Idle"],
	&"harvest": ["PickUp", "Idle"],
	&"fight": ["1H_Melee_Attack_Slice_Horizontal", "Punch", "Bite_Front", "Headbutt", "Weapon"],
	&"follow": ["Walking_A", "Walk", "Flying_Idle", "Fast_Flying"],
	&"dead": ["Death_A", "Death"],
	# 远程射击（RangedFightState 每次出手 / 快速射击技能）：枪弩优先，法杖走施法投掷
	&"shoot": ["1H_Ranged_Shoot", "2H_Ranged_Shoot", "Spellcast_Shoot", "Throw"],
	# 站桩施法（暴风雪举杖引导 / 血怒仰天咆哮——由 per-def anim_map 按职业覆盖）
	&"cast": ["Spellcast_Raise", "Spellcasting", "Cheer"],
	# 突刺（刺客背刺：双匕首直刺，怪物种族回退 Punch）
	&"stab": ["Dualwield_Melee_Attack_Stab", "1H_Melee_Attack_Stab", "Punch"],
	# 受击反馈（KayKit=Hit_A；Quaternius=HitReact；GreenBlob/Yeti 资源拼写为 HitRecieve）
	&"hit": ["Hit_A", "HitReact", "HitRecieve"],
	# 主角连招 / 技能（HeroAnimator 委托）
	&"combo_light": ["1H_Melee_Attack_Slice_Diagonal"],
	&"combo_heavy": ["1H_Melee_Attack_Chop"],
	# 旋风斩用「可持续旋转」片段循环（Spin 完整版 2.4s 远超 1.0s 技能时长，播不完）
	&"skill_aoe": ["2H_Melee_Attack_Spinning", "2H_Melee_Attack_Spin"],
	&"skill_dash": ["Dodge_Forward"],
}

# 循环类（持续状态）——自动设 loop；攻击 / 死亡 / 连招为单次播放。
# skill_aoe（旋风斩）入列：技能持续期间身体连续旋转，与 whirlwind_aura 特效同步。
const LOOP_KEYS = [&"idle", &"move", &"run", &"follow", &"harvest", &"skill_aoe"]

# 单次动画里的「挥击类」：播放速度吃 def.attack_anim_speed（攻速匹配——
# 动画时长 > 攻击间隔的兵种按倍速播，让动作在下次出招前收完）。
const ATTACK_SWING_KEYS = [&"fight", &"shoot", &"stab"]

# 飞行单位（PawnDef.is_flying_unit）专用回退：飞行模型没有地面待机/行走，
# 只有 Flying_Idle（悬停待机）与 Fast_Flying（高速扑翼）。若沿用地面候选，
# `idle` 会落空、`move/run` 会拿到 Fast_Flying（高速扑翼当走路）——故飞行单位
# 把 idle 显式指向 Flying_Idle，move 用 Flying_Idle（悬停位移）、run 用 Fast_Flying（冲刺）。
const FALLBACK_FLYER := {
	&"idle": ["Flying_Idle", "Idle"],
	&"move": ["Flying_Idle", "Fast_Flying", "Walk"],
	&"run": ["Fast_Flying", "Flying_Idle"],
	&"follow": ["Flying_Idle", "Fast_Flying", "Walk"],
}

# 手部挂点（KayKit 占位角色：每只手一个挂点，挂点下把「该手的所有武器变体」都挂了一遍）。
# 注意 Godot 的 glTF 导入会把节点名里的 "." 换成 "_"，故实际节点名是 handslot_l / handslot_r。
const HAND_SLOT_MAIN := &"handslot_r"      # 主手（右手）
const HAND_SLOT_OFFHAND := &"handslot_l"   # 副手（左手）
const SLOT_ALIASES := {
	&"handslot_r": [&"handslot_r", &"handslot.r"],
	&"handslot_l": [&"handslot_l", &"handslot.l"],
}
const KEEP_ALL := &"*"                      # apply_weapon_loadout 的「不筛选」哨兵值

var anim_player: AnimationPlayer = null
var _model_root: Node3D = null
var _resolved: Dictionary = {}      # 项目 key(StringName) → { lib:String, anim:String }
var _current: StringName = &""
var _last_loop_key: StringName = &"idle"   # 最近一次播放的循环动画（单次动画播完后回落到它）
var _flyer: bool = false            # 是否飞行单位（决定 idle 回退到 Flying_Idle 还是 Idle）
# 攻击类单次动画的播放速度倍率（由 Pawn 按 def.attack_anim_speed 注入；1.0 = 原速）。
var attack_anim_speed: float = 1.0
# ---- v10：瞄准 / 集火红色描边（反转外壳法：复制模型网格 + FRONT 剔除外扩材质）----
var _outline_meshes: Array[MeshInstance3D] = []
var _outline_on: bool = false


## 是否已挂载骨骼模型（无模型时描边回退由 Pawn 用占位胶囊处理）。
func has_model() -> bool:
	return _model_root != null


## 当前是否正在播循环类动画（受击反馈只在这类动画上插播，不打断攻击 / 施法）。
func is_playing_loop() -> bool:
	return _current != &"" and LOOP_KEYS.has(_current) \
		and anim_player != null and anim_player.is_playing()


## 开关红色描边（准星瞄准 / 集火目标标记）。
## 实现：为模型子树里每个 MeshInstance3D 复制一份「反转外壳」网格——
## 材质剔除正面（只渲染背面）+ 顶点沿法线外扩 → 在轮廓处露出色带。
## 复制体与原网格同父节点：静态武器随挂点骨骼走；蒙皮网格的 skeleton NodePath
## 相对路径在同层兄弟位置解析结果一致，动画驱动完全同步。
func set_outline(on: bool, color: Color = Color(1.0, 0.22, 0.18)) -> void:
	if _outline_on == on:
		return
	_outline_on = on
	if on and _outline_meshes.is_empty():
		_build_outlines(color)
	for m in _outline_meshes:
		if is_instance_valid(m):
			m.visible = on


func _build_outlines(color: Color) -> void:
	if _model_root == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_FRONT   # 只画背面 → 轮廓描边
	mat.grow = true
	mat.grow_amount = 0.045             # 顶点沿法线外扩的描边宽度（米；0.03 在近景偏细难辨）
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.95
	_collect_outlines(_model_root, mat)


func _collect_outlines(n: Node, mat: StandardMaterial3D) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and not mi.name.begins_with("Outline"):
			var dup := MeshInstance3D.new()
			dup.name = "Outline_%s" % mi.name
			dup.mesh = mi.mesh
			dup.skeleton = mi.skeleton             # 蒙皮绑定：同父兄弟位置解析一致
			# 【v29 关键】必须连同 Skin 资源一起拷：glTF 蒙皮的 inverseBindMatrices 存在
			# MeshInstance3D.skin 里，只给 skeleton 路径的话描边副本按「绑定姿 + 骨骼空间」
			# 渲染——对骨骼带缩放补偿的模型（巨龙 Dragon2）会放出比本体大 2~3 倍的绿色/红色
			# 幽灵（真有此事：v26 龙队伍绿标 = 一只巨型绿龙盖在龙身上）。
			dup.skin = mi.skin
			dup.material_override = mat
			dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dup.visible = false
			var parent := mi.get_parent()
			parent.add_child(dup)
			dup.transform = mi.transform
			_outline_meshes.append(dup)
	for c in n.get_children():
		_collect_outlines(c, mat)


## 加载并挂载骨骼模型。path 为空 / 加载失败返回 false（调用方保持胶囊占位）。
## weapon_main / weapon_offhand 见 apply_weapon_loadout()。
## anim_map：per-def 动画覆盖（PawnDef.anim_map），优先级高于全局 ANIM_CANDIDATES；
##   键 = 项目 key（idle/move/run/fight/dead…），值 = 该模型的真实动画名。
## flyer：飞行单位（PawnDef.is_flying_unit）。飞行模型没有地面待机/行走（只有 Flying_Idle /
##   Fast_Flying），而 `move` 候选里排前面的 Walk/Run 对它们不存在，会回退到第一个飞行名——
##   那会是 Fast_Flying（高速扑翼）当待机，观感错。故飞行单位把 idle 回退名换成 Flying_Idle。
func setup(path: String, model_scale: float = 1.0, face_offset_deg: float = 0.0,
		weapon_main: StringName = &"", weapon_offhand: StringName = &"",
		anim_map: Dictionary = {}, flyer: bool = false) -> bool:
	clear_model()
	if path.is_empty():
		return false
	var scene := _load_glb_scene(path)
	if scene == null:
		push_warning("PawnModelRig: 加载返回 null: %s" % path)
		return false
	_model_root = scene
	_flyer = flyer
	# 偏移放在 Rig 容器，而非导入模型根节点：动画轨道不会覆盖它，且逻辑朝向保持单一来源（Pawn 的 -Z）。
	scale = Vector3.ONE * model_scale
	rotation = Vector3(0.0, deg_to_rad(face_offset_deg), 0.0)
	add_child(scene)
	apply_weapon_loadout(weapon_main, weapon_offhand)
	anim_player = _find_anim_player(scene)
	_resolve_anim_names(anim_map)
	# 防御性处理：外部场景若错误标记 top_level，会脱离 Pawn 而停在世界原点。
	_clear_top_level(scene)
	if anim_player == null:
		push_warning("PawnModelRig: 模型未含 AnimationPlayer %s" % path)
		return false
	# 单次动画（攻击 / 施法 / 受击）播完后自动回落到最近的循环动画——
	# 不再定格在收招姿势（旧版站定的单位会一直保持最后一帧）。
	if not anim_player.animation_finished.is_connected(_on_anim_finished):
		anim_player.animation_finished.connect(_on_anim_finished)
	if has_anim(&"idle"):
		play(&"idle", 0.0)
	return true


## 清理当前模型，支持运行时换装或定义重载。Rig 自身的本地变换同步复位。
func clear_model() -> void:
	if is_instance_valid(_model_root):
		remove_child(_model_root)
		_model_root.queue_free()
	_model_root = null
	anim_player = null
	_resolved.clear()
	_current = &""
	_last_loop_key = &"idle"
	attack_anim_speed = 1.0
	_outline_meshes.clear()   # 描边体是模型子树节点，随根一起释放；引用同步清空
	_outline_on = false
	_stealth_on = false       # 隐身材质挂在旧模型 surface 上，随模型一起作废
	_stealth_saved.clear()
	_flyer = false
	scale = Vector3.ONE
	rotation = Vector3.ZERO


# ---- 武器挂点 ----

## 只保留每只手的一件武器，隐藏该挂点下其余武器变体网格。
##
## 为什么需要：占位 KayKit 角色把「同一只手可用的所有武器」都挂在同一个手部挂点下
## （主角双手挂点里躺着 1H/2H 剑 + 4 面盾），导入后这些网格默认全部可见，
## 于是剑与盾会同时出现在左手上、两把剑叠在右手上（真机可见的穿模重叠）。
## 动画轨道只驱动骨骼（handslot_l / handslot_r 本身），武器网格是静态子节点，
## 故这里用 visible 显隐挑选武器，不影响任何动画与战斗判定。
##
## main_name / offhand_name：要保留的模型节点名（如 &"1H_Sword" / &"Rectangle_Shield"）。
##   空 StringName（默认）→ 保留该挂点第一个子节点（KayKit 的排序里第一个即该模型的主武器）；
##   指定名在该模型里不存在 → 该手空手（可用 &"none" 显式表达空手）；
##   KEEP_ALL(&"*") → 不筛选，保持模型原样（换装调试 / 「修复前」对照样张用）。
func apply_weapon_loadout(main_name: StringName = &"", offhand_name: StringName = &"") -> void:
	_keep_single_weapon(HAND_SLOT_MAIN, main_name)
	_keep_single_weapon(HAND_SLOT_OFFHAND, offhand_name)


## 在 slot 挂点下只保留名为 keep 的子节点（空 = 第一个）；找不到同名子节点则全部隐藏。
func _keep_single_weapon(slot: StringName, keep: StringName) -> void:
	var node := _find_hand_slot(slot)
	if node == null:
		return   # 模型没有该挂点（正式美术可能不再用 KayKit 约定）→ 保持原样
	if keep == KEEP_ALL:
		for child in node.get_children():
			if child is VisualInstance3D:
				(child as VisualInstance3D).visible = true
		return
	var children := node.get_children()
	var keep_index := 0
	if not keep.is_empty():
		keep_index = -1
		for i in children.size():
			if _same_node_name(String(children[i].name), String(keep)):
				keep_index = i
				break
	for i in children.size():
		var child := children[i]
		if child is VisualInstance3D:
			(child as VisualInstance3D).visible = (i == keep_index)


## 按挂点名（含 glTF 导入把 "." 换成 "_" 的两种写法）在模型子树里找手部挂点。
func _find_hand_slot(slot: StringName) -> Node3D:
	if _model_root == null:
		return null
	var aliases: Array = SLOT_ALIASES.get(slot, [slot])
	for alias in aliases:
		var found := _find_node_by_name(_model_root, String(alias))
		if found is Node3D:
			return found as Node3D
	return null


func _find_node_by_name(n: Node, wanted: String) -> Node:
	if _same_node_name(String(n.name), wanted):
		return n
	for c in n.get_children():
		var r := _find_node_by_name(c, wanted)
		if r != null:
			return r
	return null


# glTF 导入会清理节点名（"." → "_"），这里做一次宽松比较以防导入策略变化。
func _same_node_name(actual: String, wanted: String) -> bool:
	return actual == wanted or actual.replace(".", "_") == wanted.replace(".", "_")


# ---- 导入场景兼容 ----

## 递归关掉 n 子树里所有 Node3D 的 top_level（top_level=true 会忽略父变换、脱离实体停在原点）。
func _clear_top_level(n: Node) -> int:
	var cnt := 0
	if n is Node3D and (n as Node3D).is_set_as_top_level():
		(n as Node3D).set_as_top_level(false)
		cnt += 1
	for c in n.get_children():
		cnt += _clear_top_level(c)
	return cnt


## 加载 GLB 为场景。优先编辑器导入的 PackedScene，回退运行时 GLTFDocument 解析。
static func _load_glb_scene(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is PackedScene:
			return res.instantiate() as Node3D
	# 回退：运行时解析原始 GLB（不依赖编辑器导入缓存）
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_warning("PawnModelRig: 解析 GLB 失败 %s (err=%d)" % [path, err])
		return null
	return doc.generate_scene(state)


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


## 扫描 AnimationPlayer 的所有库 / 动画，建立「项目 key → 实际动画」映射。
## 扫描全部库（而非假定默认库），以兼容不同 glTF 导入产生的库名差异。
##
## 解析优先级：per-def 覆盖（override，值为单个名字或名字数组/池）＞ 全局 ANIM_CANDIDATES 按序回退。
## 全局用「候选数组 + 取第一个存在」而非单名，是为了让 KayKit 人形与 Quaternius 怪物
## 共用一份表：各自只会命中自己那套名字（已核对两套名字集合互不重叠）。
func _resolve_anim_names(override: Dictionary = {}) -> void:
	_resolved.clear()
	if anim_player == null:
		return
	var available := {}
	for lib_name in anim_player.get_animation_library_list():
		var lib: AnimationLibrary = anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			available[String(anim_name)] = String(lib_name)
	for key in ANIM_CANDIDATES:
		var cands: Array = []
		if override.has(key):
			var o: Variant = override[key]
			if o is Array:
				cands = o as Array
			elif o is String or o is StringName:
				cands = [o]
		if cands.is_empty():
			cands = FALLBACK_FLYER[key] if (_flyer and FALLBACK_FLYER.has(key)) else ANIM_CANDIDATES[key]
		for cand in cands:
			var cname := String(cand)
			if available.has(cname):
				_resolved[key] = { "lib": available[cname], "anim": cname }
				break


func has_anim(key: StringName) -> bool:
	return _resolved.has(key)


## 查询某个项目 key 最终解析到的真实动画名（无则空串）。供调试 / 回归校验用。
func resolved_anim(key: StringName) -> String:
	if not _resolved.has(key):
		return ""
	return String((_resolved[key] as Dictionary).get("anim", ""))


## 按项目 key 播放动画。blend 为淡入秒数；循环类自动 loop。
## 无此动画（模型不含 / 映射缺失）则静默跳过，调用方可另有 fallback。
##
## 播放规则（动画 ↔ 出招同步的三条核心约定）：
## ① 单次动画每次请求都从帧 0 重播——Godot 4 对播放中的同名动画再调 play() 并不会
##    重播（实测 position 继续前进），必须显式 seek(0)。旧实现注释声称「每次都重播」
##    但实际做不到，导致攻击动画相位与出招事件脱节（快攻速兵种几乎永远停在收招帧）。
## ② 单次动画（攻击 / 施法 / 受击 / 死亡）播放期间，循环动画的播放请求让位——
##    否则每帧 play(idle/run) 的状态会在一帧内盖掉受击 / 出招动作。
##    播完后由 animation_finished 自动回落到最近的循环动画。
## ③ 挥击类动画（fight/shoot/stab）按 attack_anim_speed 倍速播放——
##    动画时长超过攻击间隔的兵种（如刺客 1.17s 动画 / 0.55s 攻击间隔）
##    加速到与出招节奏匹配，动作不再越积越慢。
func play(key: StringName, blend: float = 0.12, speed: float = 1.0) -> void:
	if anim_player == null or not _resolved.has(key):
		return
	var is_loop: bool = LOOP_KEYS.has(key)
	# 规则②：单次动画播放中，循环动画让位（死亡也是单次动画，天然获得最高优先）
	if is_loop and _current != &"" and not LOOP_KEYS.has(_current) and anim_player.is_playing():
		return
	# 循环类：正在播同名动画则不重置（避免 idle 抖动）；但播放倍率变化时要跟上
	if is_loop and key == _current and anim_player.is_playing():
		if is_equal_approx(anim_player.speed_scale, clampf(speed, 0.1, 3.0)):
			return
		anim_player.speed_scale = clampf(speed, 0.1, 3.0)
		return
	var info: Dictionary = _resolved[key]
	var lib := String(info["lib"])
	var full := String(info["anim"]) if lib == "" else (lib + "/" + String(info["anim"]))
	if not anim_player.has_animation(full):
		return
	if is_loop:
		var a: Animation = anim_player.get_animation(full)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		_last_loop_key = key
		# 循环倍率：追赶 / 加速时的步伐速度匹配（默认 1.0 = 旧行为不变）
		anim_player.speed_scale = clampf(speed, 0.1, 3.0)
	else:
		# 规则③：挥击类按攻速倍速播放，其余单次动画（技能 / 受击 / 死亡）原速
		anim_player.speed_scale = attack_anim_speed if ATTACK_SWING_KEYS.has(key) else 1.0
	anim_player.play(full, blend)
	if not is_loop:
		# 规则①：单次动画显式回到帧 0（play() 同名不重播；seek 立即采样起始姿势，
		# 旧姿势到起始姿势之间仍走 blend 淡入，不会闪帧）
		anim_player.seek(0.0, true)
	_current = key


## 单次动画自然播完：回落到最近的循环动画（死亡除外——尸体保持倒地姿势）。
func _on_anim_finished(_anim: StringName) -> void:
	if _current == &"" or LOOP_KEYS.has(_current):
		return
	var finished_key: StringName = _current
	_current = &""
	if finished_key == &"dead":
		return
	play(_last_loop_key if _last_loop_key != &"" else &"idle", 0.15)


func stop() -> void:
	if anim_player != null:
		anim_player.stop()
	_current = &""


## 整体染色（精英怪 / 头目 / 兵种区分）。逐 surface 复制材质后乘 albedo：
## 直接改共享材质会污染所有用同一模型的单位，必须 per-instance override。
func apply_tint(tint: Color) -> void:
	if _model_root == null or tint.is_equal_approx(Color.WHITE):
		return
	_apply_tint_recursive(_model_root, tint)


func _apply_tint_recursive(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is BaseMaterial3D:
					var dm := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					dm.albedo_color = (mat as BaseMaterial3D).albedo_color * tint
					mi.set_surface_override_material(i, dm)
	for c in n.get_children():
		_apply_tint_recursive(c, tint)


# ---- v33：隐身半透明（暗杀者）----

const STEALTH_SHADER_PATH := "res://assets/shaders/stealth_cloak.gdshader"

var _stealth_on: bool = false
# 进入隐身前的 per-surface override 快照：[{mesh, surface, mat}]（null = 原本无 override）。
# 与 apply_tint / begin_dissolve 同理走 per-instance override，不碰共享材质。
var _stealth_saved: Array = []


## 当前是否处于隐身外观（由 Pawn.apply_stealth / break_stealth 驱动）。
func stealth_active() -> bool:
	return _stealth_on


## 开关隐身外观：per-surface override 换成隐身材质（跳过 Outline_* 描边副本，
## 否则隐身时描边照旧把人形勾出来）。结束恢复进入前的 override 状态。
## shader 缺失（未导入 / headless）时回落 StandardMaterial3D 半透明兜底——
## 视觉打折但 stealth_active() 仍为 true，逻辑与无头测试不依赖 shader 加载成功。
func set_stealth(on: bool) -> void:
	if on == _stealth_on:
		return
	_stealth_on = on
	if on:
		_apply_stealth_materials()
	else:
		_restore_stealth_materials()


func _apply_stealth_materials() -> void:
	_restore_stealth_materials()   # 防御：清掉可能残留的上一轮记录
	if _model_root == null:
		return
	var shader: Shader = load(STEALTH_SHADER_PATH) as Shader
	_collect_stealth(_model_root, shader)
	if _stealth_saved.is_empty():
		push_warning("PawnModelRig: 模型无可隐身网格，隐身仅剩逻辑效果")


func _collect_stealth(n: Node, shader: Shader) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and not String(mi.name).begins_with("Outline"):
			for i in mi.mesh.get_surface_count():
				# 先取「当前生效材质」再写 override：get_active_material 在写之前拿到的是
				# 进入前的 override（染色等），颜色 / 贴图据此拷贝，不丢原外观。
				var src := mi.get_active_material(i)
				_stealth_saved.append({
					"mesh": mi,
					"surface": i,
					"mat": mi.get_surface_override_material(i),
				})
				mi.set_surface_override_material(i, _make_stealth_material(src, shader))
	for c in n.get_children():
		_collect_stealth(c, shader)


func _restore_stealth_materials() -> void:
	for entry in _stealth_saved:
		var d: Dictionary = entry
		if not is_instance_valid(d.get("mesh")):
			continue
		(d["mesh"] as MeshInstance3D).set_surface_override_material(int(d["surface"]), d.get("mat"))
	_stealth_saved.clear()


## 生成单个 surface 的隐身材质：优先 vfx-dev 的 stealth_cloak shader；
## shader 为 null 时用 StandardMaterial3D（TRANSPARENCY_ALPHA + alpha 0.18）兜底。
func _make_stealth_material(src: Material, shader: Shader) -> Material:
	var base_color := Color.WHITE
	var base_tex: Texture2D = null
	var shading := BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		base_color = b.albedo_color
		base_tex = b.albedo_texture
		shading = b.shading_mode
	if shader != null:
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter(&"albedo_color", base_color)
		sm.set_shader_parameter(&"albedo_texture", base_tex)
		sm.set_shader_parameter(&"use_texture", base_tex != null)
		sm.set_shader_parameter(&"cloak", 1.0)                       # 1 = 隐身强度拉满
		sm.set_shader_parameter(&"rim_color", Vector3(0.55, 0.85, 1.0))
		# alpha_scale 是 shader 里叠在 ghost_alpha(0.24) 之上的系数，给 1.0 =
		# 直接用作者调好的幽灵透明度；填 0.18 会变成 0.24×0.18 ≈ 4% 几乎看不见。
		sm.set_shader_parameter(&"alpha_scale", 1.0)
		return sm
	var fb := StandardMaterial3D.new()
	fb.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.18)
	fb.albedo_texture = base_tex
	fb.shading_mode = shading
	fb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return fb


# ---- v16：死亡贴图溶解 ----

const DISSOLVE_SHADER_PATH := "res://assets/shaders/death_dissolve.gdshader"

## 死亡溶解入口：把模型子树全部网格 surface 的材质换成溶解材质（从原材质拷贝 albedo
## 颜色 / 贴图，武器等静态网格一并消散），返回创建的材质列表——调用方（DeadState）
## 每帧写 dissolve_progress(0→1) 驱动消散，到 1 后整体 queue_free。
## 与 apply_tint 同理走 per-instance override：不碰共享材质，不污染其它单位。
## 描边副本（Outline_*）与已隐藏网格跳过；返回空列表 = 模型无可溶网格（调用方直接释放）。
func begin_dissolve() -> Array[ShaderMaterial]:
	var mats: Array[ShaderMaterial] = []
	if _model_root == null:
		return mats
	var shader: Shader = load(DISSOLVE_SHADER_PATH) as Shader
	if shader == null:
		push_warning("PawnModelRig: 死亡溶解 shader 加载失败 " + DISSOLVE_SHADER_PATH)
		return mats
	_collect_dissolve(_model_root, shader, mats)
	return mats


func _collect_dissolve(n: Node, shader: Shader, mats: Array[ShaderMaterial]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and not String(mi.name).begins_with("Outline"):
			for i in mi.mesh.get_surface_count():
				var dm := ShaderMaterial.new()
				dm.shader = shader
				var base_color := Color.WHITE
				var src := mi.get_active_material(i)
				if src is BaseMaterial3D:
					var b := src as BaseMaterial3D
					base_color = b.albedo_color
					if b.albedo_texture != null:
						dm.set_shader_parameter(&"albedo_texture", b.albedo_texture)
						dm.set_shader_parameter(&"use_texture", true)
				dm.set_shader_parameter(&"albedo_color", base_color)
				dm.set_shader_parameter(&"dissolve_progress", 0.0)
				mi.set_surface_override_material(i, dm)
				mats.append(dm)
	for c in n.get_children():
		_collect_dissolve(c, shader, mats)
