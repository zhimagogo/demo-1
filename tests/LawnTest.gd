extends Node
## 草坪覆盖、道路/建筑生命周期遮罩与渲染预算回归。无头检查数据，有窗口工具验证画面。
var failures := 0
var scatter: DecorationScatter
var grid: GridSystem
var build: BuildSystem

func _ready() -> void:
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func mask_at(point: Vector3) -> float:
	var pixel := Vector2i(Vector2(point.x + grid.half_x(), point.z + grid.half_z()) * float(scatter.LAWN_MASK_PIXELS_PER_CELL) / grid.cell_size)
	return scatter._lawn_mask_image.get_pixelv(pixel).r

func settle() -> void:
	for i in 3: await get_tree().process_frame

func _run() -> void:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await settle()
	var world := main.get_node("WorldRoot")
	for name in ["WildlifeSpawner", "SettlementSystem", "ResourceGrowthSystem", "HeroController"]:
		world.get_node(name).set_process(false)
		world.get_node(name).set_physics_process(false)
	scatter = world.get_node("Decorations/DecorationScatter") as DecorationScatter
	grid = world.get_node("GridSystem") as GridSystem
	build = world.get_node("BuildSystem") as BuildSystem
	var terrain_before := grid.terrain_cells.size()
	var town_count := 0
	var meadow_count := 0
	var total := 0
	var chunks := 0
	for child in scatter.get_children():
		if not child is MultiMeshInstance3D or not String(child.name).begins_with("MM_grass_"): continue
		chunks += 1
		var mm := child.multimesh as MultiMesh
		total += mm.instance_count
		if chunks == 1: check(mm.instance_count < 1800, "chunk instance count bounded")
		for i in mm.instance_count:
			var point := mm.get_instance_transform(i).origin
			if point.x > 8 and point.x < 18 and point.z > 8 and point.z < 18: town_count += 1
			if point.x > 8 and point.x < 18 and point.z > 32 and point.z < 42: meadow_count += 1
	print("DENSITY total=%d chunks=%d town=%d meadow=%d" % [total, chunks, town_count, meadow_count])
	# Dummy renderer 不保留 MultiMesh 的变换数据；覆盖量必须在真实 GPU 运行中验。
	if DisplayServer.get_name() != "headless":
		check(town_count > 350, "town lawn covers empty buildable ground (>42 blades/m2)")
		check(meadow_count > 350, "meadow has continuous short grass coverage")
	else:
		print("SKIP: instance position coverage requires real renderer (run LawnTest without --headless)")
	check(total < scatter.grass_count * 1.01 and chunks > 100, "bounded grass budget with independent spatial chunks")
	check(scatter._lawn_material.shader.code.find("ALPHA =") == -1, "lawn uses opaque depth, no alpha blending")
	check(scatter._make_lawn_clump().get_aabb().size.y < 0.6, "broad grass crown stays below character knees")
	check(not scatter._lawn_allowed(WorldLayout.LAKE_CENTER), "lake is excluded")
	check(not scatter._lawn_allowed(WorldLayout.RIVER_PTS[2]), "river is excluded")
	check(not scatter._lawn_allowed(Vector2(0, 45)), "exploration road is excluded")
	check(not scatter._lawn_allowed(Vector2.ZERO), "castle base is excluded")
	var point := Vector3(11, 0, 11)
	check(mask_at(point) < 0.01, "empty land initially grows grass")
	ResourceManager.add(GameDefs.GOLD, 2000)
	SelectionManager.ui_modal_count = 0
	world.get_node("HeroController").enter_hero_mode()
	for def: BuildingDef in GameDefs.building_defs():
		if def.id == &"house":
			build.enter_build_mode(def)
			break
	build.try_place_at(point)
	await settle()
	var house = grid._occupants.get(grid.world_to_grid(point))
	check(is_instance_valid(house), "house placed through normal build flow")
	check(mask_at(point) > 0.99 and mask_at(point + Vector3(4, 0, 4)) > 0.99, "whole 3x3 house footprint clears grass")
	check(mask_at(point - Vector3(2, 0, 2)) < 0.01, "neighboring lawn remains visible")
	if is_instance_valid(house):
		EventBus.building_removed.emit(house, house.cell)
		house.queue_free()
	await settle()
	check(mask_at(point) < 0.01, "demolition restores lawn")
	for def: BuildingDef in GameDefs.building_defs():
		if def.is_road:
			build.enter_build_mode(def)
			break
	build.try_place_at(point)
	await settle()
	var road = grid.road_cells.get(grid.world_to_grid(point))
	check(is_instance_valid(road) and mask_at(point) > 0.99, "player road clears grass despite separate road group")
	if is_instance_valid(road): road.queue_free()
	await settle()
	check(mask_at(point) < 0.01, "direct road removal restores grass")
	check(grid.terrain_cells.size() == terrain_before, "lawn edits never modify terrain collision or navigation")
	build.exit_build_mode()
	print("LAWN: instances=%d chunks=%d town=%d/100m2 meadow=%d/100m2 failures=%d" % [total, chunks, town_count, meadow_count, failures])
	main.queue_free()
	await settle()
	get_tree().quit(0 if failures == 0 else 1)
