extends Node
## 主角遮挡剪影专项回归（v12 需求 5）：godot --headless --path . tests/HeroOcclusionTest.tscn
## 覆盖：默认不遮挡 -> 人为挡板触发 -> 剪影淡入 / 淡出 -> 渲染层与相机 cull_mask 隔离 ->
## 独立 World3D + CanvasLayer 层级 / 骨骼副本绑定 / 剪影与主角屏幕位置对齐。

var _failures: int = 0
var _main: Node
var _occluder: Node3D


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
	(world.get_node("WildlifeSpawner") as Node).set_process(false)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var controller := world.get_node("HeroController") as HeroController
	var tp := world.get_node("ThirdPersonCamera") as ThirdPersonCamera
	var iso := world.get_node("IsometricCamera") as IsometricCamera
	var hero: Hero = controller.hero
	var silhouette := world.get_node_or_null("HeroOcclusionSilhouette") as HeroOcclusionSilhouette
	_check(silhouette != null, "occlusion silhouette node is attached under WorldRoot")
	if silhouette == null:
		_finish()
		return

	# ---- 结构：独立 World3D / 剪影层隔离 / CanvasLayer 低于 HUD ----
	var sv := silhouette.silhouette_viewport()
	var sv_cam := silhouette.silhouette_camera()
	_check(sv != null and sv.own_world_3d, "silhouette SubViewport has its own World3D")
	_check(sv != null and sv.transparent_bg, "silhouette SubViewport uses a transparent background")
	_check(sv_cam != null and sv_cam.current and sv_cam.get_parent() == sv,
		"silhouette camera is the current camera of its own viewport")
	_check(sv_cam != null and sv_cam.cull_mask == HeroOcclusionSilhouette.SILHOUETTE_LAYER,
		"silhouette camera renders only the silhouette layer")
	_check((tp.cull_mask & HeroOcclusionSilhouette.SILHOUETTE_LAYER) == 0
		and (iso.cull_mask & HeroOcclusionSilhouette.SILHOUETTE_LAYER) == 0,
		"main cameras exclude the silhouette layer (no ghost double)")
	var blit := silhouette.get_node_or_null("SilhouetteCanvas/SilhouetteBlit") as TextureRect
	var canvas := silhouette.get_node_or_null("SilhouetteCanvas") as CanvasLayer
	_check(canvas != null and blit != null, "silhouette blit CanvasLayer + full-screen TextureRect exist")
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	_check(canvas != null and hud != null and canvas.layer < hud.layer,
		"silhouette CanvasLayer sits below HUD (layer %d < %d)" % [canvas.layer if canvas else -1, hud.layer if hud else -1])
	_check(canvas != null and not canvas.follow_viewport_enabled, "silhouette CanvasLayer does not follow the viewport")
	_check(blit != null and blit.modulate.a < 0.01 and not blit.visible,
		"silhouette blit starts hidden")

	# ---- 开阔城内空地：相机到胸口无遮挡 ----
	controller.enter_hero_mode()
	hero.global_position = Vector3(8.0, 0.0, 8.0)
	hero.velocity = Vector3.ZERO
	tp.yaw = 0.785          # 相机拉到主角 +x+z 侧（背对城堡）
	tp.pitch = -0.30
	tp.target_distance = 4.6
	for i in 12:
		await get_tree().physics_frame
	_check(silhouette.silhouette_copy() != null, "silhouette model copy is built from the hero model")
	_check(not silhouette.is_occluded(), "no occlusion with a clear line of sight")
	_check(silhouette.silhouette_alpha() < 0.01, "silhouette alpha stays 0 when not occluded (%.3f)"
		% silhouette.silhouette_alpha())
	_check(hero.visible, "hero itself stays visible (silhouette never hides the real model)")

	# ---- 副本绑定：网格落在剪影层、骨骼指向副本自己的 Skeleton3D、动画播放器停用 ----
	var copy := silhouette.silhouette_copy()
	var mesh_count := 0
	var layer_ok := true
	var skeleton_ok := true
	for node in _all_nodes(copy):
		if node is MeshInstance3D:
			mesh_count += 1
			var mi := node as MeshInstance3D
			if mi.layers != HeroOcclusionSilhouette.SILHOUETTE_LAYER:
				layer_ok = false
			if mi.skeleton != NodePath():
				var sk := mi.get_node_or_null(mi.skeleton)
				if not (sk is Skeleton3D) or not copy.is_ancestor_of(sk):
					skeleton_ok = false
	_check(mesh_count > 0 and layer_ok, "every copy mesh lives only on the silhouette layer (%d meshes)" % mesh_count)
	_check(skeleton_ok, "copy meshes deform by the copy's own Skeleton3D")
	var copy_anim := _find_anim_player(copy)
	_check(copy_anim != null and not copy_anim.active, "copy AnimationPlayer is disabled (poses synced per frame)")

	# ---- 人为挡板：相机与主角胸口之间放一块 layer 1 的静态盒 ----
	var chest := hero.global_position + Vector3.UP * HeroOcclusionSilhouette.CHEST_HEIGHT
	var cam_pos := tp.global_position
	# 挡板只挡胸口、不挡枢轴：放在靠主角一侧的矮墙（顶 1.45m < 枢轴 1.55m），
	# 否则相机收缩（贴墙判据）会先把相机拉到挡板前面，测不到「胸口射线被挡」
	var at := chest + (cam_pos - chest).normalized() * 1.1
	at.y = chest.y
	_occluder = _make_occluder(at, Vector3(1.6, 0.9, 1.6))
	world.add_child(_occluder)
	for i in 12:
		await get_tree().physics_frame
	_check(silhouette.is_occluded(), "a blocker between camera and chest is detected as occlusion")
	_check(silhouette.occluded_by_ray() and not silhouette.camera_squeezed(),
		"occlusion comes from the chest ray, not from camera squeeze")
	_check(silhouette.silhouette_alpha() > 0.9, "silhouette fades in while occluded (%.2f)"
		% silhouette.silhouette_alpha())
	_check(blit != null and blit.visible, "silhouette blit becomes visible")
	_check(sv.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "viewport renders while occluded")
	_check(hero.visible, "hero stays visible while occluded")

	# ---- 对齐：剪影像素质心 x 必须落在主角胸口投影位置（无渲染器时退化为投影一致性）----
	await _check_alignment(silhouette, tp, hero)

	# ---- 移除挡板：0.5s 内淡出 ----
	_occluder.queue_free()
	_occluder = null
	for i in 36:
		await get_tree().physics_frame
	_check(not silhouette.is_occluded(), "occlusion clears after the blocker is removed")
	_check(silhouette.silhouette_alpha() < 0.02, "silhouette fades out within 0.5s (%.3f)"
		% silhouette.silhouette_alpha())
	_check(blit != null and not blit.visible, "silhouette blit hides again")
	_check(sv.render_target_update_mode == SubViewport.UPDATE_DISABLED, "viewport stops rendering when idle")
	_check(hero.visible, "hero remains visible at the end")
	_finish()


# ---- 剪影 / 主角屏幕位置对齐 ----

func _check_alignment(silhouette: HeroOcclusionSilhouette, tp: ThirdPersonCamera, hero: Hero) -> void:
	var sv := silhouette.silhouette_viewport()
	var sv_cam := silhouette.silhouette_camera()
	# ① 相机位姿 / 投影参数逐项一致（位姿不同 = 剪影会偏移成重影）
	_check(sv_cam.global_transform.is_equal_approx(tp.global_transform)
		and is_equal_approx(sv_cam.fov, tp.fov) and is_equal_approx(sv_cam.near, tp.near)
		and is_equal_approx(sv_cam.far, tp.far),
		"silhouette camera mirrors the main camera (transform / fov / near / far)")
	var chest := hero.global_position + Vector3.UP * HeroOcclusionSilhouette.CHEST_HEIGHT
	var expected := tp.unproject_position(chest)
	var mirrored := sv_cam.unproject_position(chest)
	_check(absf(expected.x - mirrored.x) < 1.0 and absf(expected.y - mirrored.y) < 1.0,
		"both cameras project the chest to the same pixel (%.1f vs %.1f)" % [expected.x, mirrored.x])
	# ② 有渲染器时做真实像素质心断言（无头没有绘制帧，frame_post_draw 永不触发 -> 直接 SKIP）
	if DisplayServer.get_name() == "headless":
		print("SKIP: silhouette pixel centroid needs a real renderer (headless readback unavailable)")
		return
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sv.get_texture().get_image() if sv != null else null
	if img == null or img.is_empty() or img.get_width() < 4:
		print("SKIP: silhouette pixel centroid needs a real renderer (empty readback)")
		return
	var sum := 0.0
	var count := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).a > 0.08:
				sum += float(x)
				count += 1
	if count < 30:
		_check(false, "silhouette pixels found in its viewport (%d)" % count)
		return
	var centroid_x := sum / float(count)
	var scale := float(tp.get_viewport().get_visible_rect().size.x) / float(img.get_width())
	_check(absf(centroid_x * scale - expected.x) < 40.0,
		"silhouette pixel centroid matches hero chest projection (%.1f vs %.1f px, %d px)"
			% [centroid_x * scale, expected.x, count])


# ---- 工具 ----

func _make_occluder(at: Vector3, size: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "OcclusionTestBlocker"
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	body.add_child(mesh)
	var shape := BoxShape3D.new()
	shape.size = box.size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = at       # 调用于入树之前：global_position 会丢失（WorldRoot 本身在原点）
	return body


func _all_nodes(root: Node) -> Array:
	var out: Array = [root]
	for child in root.get_children():
		out.append_array(_all_nodes(child))
	return out


func _find_anim_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


func _finish() -> void:
	print("HERO OCCLUSION TEST: %d failure(s)" % _failures)
	_main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
