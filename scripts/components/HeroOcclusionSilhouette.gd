class_name HeroOcclusionSilhouette
extends Node
## ============================================================================
## 主角被遮挡时的轮廓透视（v12 需求 5，参考 Escape from Tarkov）。
##
## 现状问题：ThirdPersonCamera 的碰撞收缩只保证相机不穿墙——主角被城墙 / 房屋 / 树
## 挡在镜头外时没有任何提示，玩家会「丢人」。
## 参考表现：遮挡物照常可见，但主角的**淡青色剪影**透出来（内层实心 + 边缘光晕），
## 随遮挡程度淡入淡出。不是把遮挡物变透明（那会破坏场景可读性）。
##
## 实现（完全代码自建，不改 Main.tscn）：
##   ① 遮挡判定：主相机 → 主角胸口（+1.0m）的物理射线（mask 1|8，与
##      HeroController.crosshair_hit 一致）；再加一条「相机被压到期望距离 60% 以下」
##      的贴墙辅助判据；0.12s 淡入 / 0.22s 淡出的迟滞防闪烁。
##   ② 剪影渲染：独立 World3D 的 SubViewport（透明背景）+ 主角模型的第二份副本
##      （骨骼逐帧同步主模型的 bone pose）+ unshaded 剪影材质；副本只落在渲染层 2，
##      主相机 cull_mask 不含该层 → 主画面里绝不出现「重影」。
##   ③ 合成：CanvasLayer（layer 低于 HUD 的 10）+ 全屏 TextureRect 用 modulate.a 淡入淡出，
##      未遮挡时 SubViewport 停止渲染（UPDATE_DISABLED）省性能。
## ============================================================================

const SILHOUETTE_LAYER: int = 1 << 1      # 渲染层 2：专供剪影副本（主相机 cull_mask 排除）
const OCCLUSION_MASK: int = 1 | 8         # world + structure，与准星射线同口径（不撞单位）
const CHEST_HEIGHT: float = 1.0           # 胸口高度（射线终点）
const FADE_IN: float = 0.12               # 遮挡后剪影淡入秒数
const FADE_OUT: float = 0.22              # 遮挡消失后淡出秒数（0.15~0.3s）
const COMPRESS_RATIO: float = 0.6         # 相机距离被压到期望值 60% 以下 → 视为贴墙遮挡
const CANVAS_LAYER: int = 9               # HUD 是 CanvasLayer layer=10，剪影必须压在它之下

## 剪影材质：unshaded（独立 World3D 里没有灯光，受光材质会全黑）。
## 观感对齐《逃离鸭科夫》：**身体半透明**（透过遮挡物看得见轮廓，而不是角色反过来挡住墙），
## 靠边缘 Fresnel 描边读出形体；外发光由下方 blit 着色器补一层。
const SILHOUETTE_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_never;
uniform vec4 silhouette_color : source_color = vec4(0.62, 0.90, 1.0, 1.0);
uniform float body_alpha : hint_range(0.0, 1.0) = 0.40;
uniform float rim_power = 1.5;
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = silhouette_color.rgb * (0.78 + 0.55 * fres);
	ALPHA = mix(body_alpha, 1.0, fres);   // 身体 ~0.4 半透 → 外缘 ~1.0 亮描边
}
"""

## 合成层着色器：给剪影补一层外扩柔光（8 向邻域取最大 alpha − 自身），
## 即 Tarkov 的「半透身体 + 亮描边 + 柔光」三段式；同时保留 modulate.a 的淡入淡出。
const BLIT_SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_mix;
uniform vec4 glow_color : source_color = vec4(0.55, 0.86, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 1.0) = 0.55;
uniform float glow_px : hint_range(0.0, 8.0) = 2.0;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 px = glow_px * TEXTURE_PIXEL_SIZE;
	float near_a = 0.0;
	near_a = max(near_a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	near_a = max(near_a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	near_a = max(near_a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	near_a = max(near_a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	near_a = max(near_a, texture(TEXTURE, UV + px).a);
	near_a = max(near_a, texture(TEXTURE, UV - px).a);
	near_a = max(near_a, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
	near_a = max(near_a, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);
	float glow = clamp(near_a - base.a, 0.0, 1.0) * glow_strength;
	COLOR = vec4(base.rgb + glow_color.rgb * glow, clamp(base.a + glow * 0.9, 0.0, 1.0));
}
"""

var world_root: Node3D = null
var camera: Camera3D = null               # 主相机（第三人称）
var hero: Node3D = null

var _canvas: CanvasLayer
var _blit: TextureRect
var _viewport: SubViewport
var _sv_camera: Camera3D
var _copy_root: Node3D = null             # 剪影副本容器：逐帧跟随主角 ModelRig 的世界变换
var _copy: Node3D = null                  # 剪影副本（主角模型的第二份，独立 World3D）
var _src_skeleton: Skeleton3D = null
var _dst_skeleton: Skeleton3D = null
var _silhouette_material: ShaderMaterial
var _alpha: float = 0.0                   # 当前剪影透明度（0 = 完全不显示）
var _occluded: bool = false
var _ray_blocked: bool = false            # 遮挡来自「相机->胸口」射线命中（真被挡住）
var _squeezed: bool = false               # 遮挡来自相机被压近（贴墙辅助判据）
var _forced: bool = false                 # 调试 / 截图：强制显示剪影
var _built: bool = false


func _ready() -> void:
	name = "HeroOcclusionSilhouette"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if world_root == null:
		world_root = get_parent() as Node3D
	_build_viewport()
	get_viewport().size_changed.connect(_resize)


## 由 Main.gd 在出场后调用（也可什么都不传，靠 _process 懒解析）。
func setup(world: Node3D, cam: Camera3D, tracked: Node3D) -> void:
	world_root = world
	camera = cam
	hero = tracked


## ---- 对外查询（测试 / 截图工具用）----

func is_occluded() -> bool:
	return _occluded or _forced


## 遮挡是否来自射线命中（区别于「相机被压近」的辅助判据）——截图选机位 / 调试用。
func occluded_by_ray() -> bool:
	return _ray_blocked or _forced


## 相机是否被挤到期望距离 60% 以内（贴墙）。
func camera_squeezed() -> bool:
	return _squeezed


func silhouette_alpha() -> float:
	return _alpha


func silhouette_copy() -> Node3D:
	return _copy


func silhouette_camera() -> Camera3D:
	return _sv_camera


func silhouette_viewport() -> SubViewport:
	return _viewport


func set_forced(value: bool) -> void:
	_forced = value


# ---- 构建：CanvasLayer + 全屏 TextureRect + 独立 World3D 的 SubViewport ----

func _build_viewport() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "SilhouetteCanvas"
	_canvas.layer = CANVAS_LAYER
	_canvas.follow_viewport_enabled = false
	add_child(_canvas)

	_blit = TextureRect.new()
	_blit.name = "SilhouetteBlit"
	_blit.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 全屏铺满控件必须显式清零四个 offset（父子布局时机不同会把 rect 推成负值）
	_blit.offset_left = 0.0
	_blit.offset_top = 0.0
	_blit.offset_right = 0.0
	_blit.offset_bottom = 0.0
	_blit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_blit.stretch_mode = TextureRect.STRETCH_SCALE
	_blit.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_blit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blit.visible = false
	var blit_shader := Shader.new()
	blit_shader.code = BLIT_SHADER_CODE
	var blit_mat := ShaderMaterial.new()
	blit_mat.shader = blit_shader
	_blit.material = blit_mat
	_canvas.add_child(_blit)

	_viewport = SubViewport.new()
	_viewport.name = "SilhouetteViewport"
	_viewport.own_world_3d = true             # 独立 World3D：主相机看不到剪影副本
	_viewport.transparent_bg = true
	_viewport.disable_3d = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.size = _viewport_size()
	add_child(_viewport)
	_blit.texture = _viewport.get_texture()

	_sv_camera = Camera3D.new()
	_sv_camera.name = "SilhouetteCamera"
	_sv_camera.cull_mask = SILHOUETTE_LAYER         # 只渲染剪影层
	_sv_camera.current = true                        # 本 viewport 的当前相机
	_sv_camera.environment = null
	_viewport.add_child(_sv_camera)
	# 主相机排除剪影层（双保险：副本本来就在另一个 World3D 里）
	for node in _main_cameras():
		node.cull_mask = node.cull_mask & ~SILHOUETTE_LAYER
	_built = true


func _main_cameras() -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if world_root == null:
		return out
	for child in world_root.get_children():
		var cam := child as Camera3D
		if cam != null and cam != _sv_camera:
			out.append(cam)
	return out


func _viewport_size() -> Vector2i:
	var size := get_viewport().get_visible_rect().size
	return Vector2i(maxi(int(size.x), 2), maxi(int(size.y), 2))


func _resize() -> void:
	if _viewport != null:
		_viewport.size = _viewport_size()


# ---- 每帧：解析引用 → 建副本 → 同步相机与骨骼 → 判定 → 淡入淡出 ----

func _process(delta: float) -> void:
	_resolve()
	if camera == null or hero == null or _viewport == null:
		return
	if not _ensure_copy():
		return
	_sync_camera()
	_sync_transform()
	_sync_pose()
	var active := camera.current and _visible_in_tree_safe(hero)
	var hit := active and _detect_occlusion()
	_occluded = hit
	var target := 1.0 if (hit or _forced) else 0.0
	var speed := (1.0 / FADE_IN) if target > _alpha else (1.0 / FADE_OUT)
	_alpha = move_toward(_alpha, target, delta * speed)
	_apply_display()


func _resolve() -> void:
	if world_root == null:
		world_root = get_parent() as Node3D
	if world_root == null:
		return
	if camera == null:
		camera = world_root.get_node_or_null("ThirdPersonCamera") as Camera3D
	if hero == null:
		var controller := get_tree().get_first_node_in_group("hero_controller")
		if controller != null:
			hero = controller.get("hero") as Node3D
		if hero == null:
			for n in get_tree().get_nodes_in_group("player_unit"):
				if n is Hero:
					hero = n as Node3D
					break


func _visible_in_tree_safe(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree()


## 建剪影副本：把主角模型子树深拷贝一份（不重新实例化 PackedScene，保留武器挂点筛选），
## 全部网格改到剪影层并套 unshaded 剪影材质；AnimationPlayer 停用，姿势由主模型逐帧同步。
func _ensure_copy() -> bool:
	if _copy != null and is_instance_valid(_copy):
		return true
	var rig := hero.get("model_rig") as PawnModelRig
	if rig == null or not rig.has_model():
		return false
	var src := rig.get("_model_root") as Node3D
	if src == null and rig.get_child_count() > 0:
		src = rig.get_child(0) as Node3D
	if src == null:
		return false
	_src_skeleton = _find_skeleton(src)
	var dup := src.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS) as Node3D
	if dup == null:
		return false
	dup.name = "SilhouetteCopy"
	if _silhouette_material == null:
		_silhouette_material = _make_silhouette_material()
	_apply_copy_materials(dup)
	# 副本必须坐在主角 ModelRig 的世界变换上（只复制模型子树会丢掉 Rig 的位置 / 缩放 / 朝向），
	# 否则剪影会飘在世界原点、与主角的屏幕位置对不上（真机实测：小人在城堡那边）
	_copy_root = Node3D.new()
	_copy_root.name = "SilhouetteRoot"
	_viewport.add_child(_copy_root)
	_copy_root.add_child(dup)
	_copy = dup
	_dst_skeleton = _find_skeleton(dup)
	return true


func _make_silhouette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = SILHOUETTE_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _apply_copy_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		mi.layers = SILHOUETTE_LAYER
		mi.material_override = _silhouette_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is AnimationPlayer:
		(root as AnimationPlayer).active = false    # 姿势由 Skeleton3D 逐帧同步，避免两套动画打架
	for child in root.get_children():
		_apply_copy_materials(child)


static func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## 相机位姿 / 投影参数与主相机完全一致，剪影才会落在主角的屏幕位置上（否则成重影）。
func _sync_camera() -> void:
	if _sv_camera == null or camera == null:
		return
	_sv_camera.global_transform = camera.global_transform
	_sv_camera.projection = camera.projection
	_sv_camera.fov = camera.fov
	_sv_camera.size = camera.size
	_sv_camera.near = camera.near
	_sv_camera.far = camera.far
	_sv_camera.keep_aspect = camera.keep_aspect
	_sv_camera.h_offset = camera.h_offset
	_sv_camera.v_offset = camera.v_offset


## 副本容器跟随主角 ModelRig（含 model_scale / face_offset 与 Pawn 的世界变换）。
func _sync_transform() -> void:
	if _copy_root == null or hero == null:
		return
	var rig := hero.get("model_rig") as Node3D
	if rig == null:
		return
	_copy_root.global_transform = rig.global_transform


func _sync_pose() -> void:
	if _src_skeleton == null or _dst_skeleton == null:
		return
	var count := mini(_src_skeleton.get_bone_count(), _dst_skeleton.get_bone_count())
	for i in count:
		_dst_skeleton.set_bone_pose_position(i, _src_skeleton.get_bone_pose_position(i))
		_dst_skeleton.set_bone_pose_rotation(i, _src_skeleton.get_bone_pose_rotation(i))
		_dst_skeleton.set_bone_pose_scale(i, _src_skeleton.get_bone_pose_scale(i))


## 遮挡判定：① 相机 → 胸口射线命中世界几何；② 相机被压到期望距离 60% 以下（贴墙）。
func _detect_occlusion() -> bool:
	var chest := hero.global_position + Vector3.UP * CHEST_HEIGHT
	var from := camera.global_position
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, chest, OCCLUSION_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	_ray_blocked = not hit.is_empty()
	_squeezed = false
	var tp := camera as ThirdPersonCamera
	if tp != null and tp.target_distance > 0.5:
		var pivot: Vector3 = hero.global_position + Vector3(0.0, ThirdPersonCamera.PIVOT_HEIGHT, 0.0)
		_squeezed = from.distance_to(pivot) < tp.target_distance * COMPRESS_RATIO
	return _ray_blocked or _squeezed


func _apply_display() -> void:
	if _blit == null or _viewport == null:
		return
	var on := _alpha > 0.002
	_blit.visible = on
	_blit.modulate.a = _alpha
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
