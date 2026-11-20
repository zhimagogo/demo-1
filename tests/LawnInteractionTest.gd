extends Node
var failures := 0
var field: LawnInteraction

func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if ok: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func _run() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/lawn.gdshader") as Shader
	field = LawnInteraction.new()
	add_child(field)
	field.setup(material)
	field.set_process(false)
	field.advance(0.1, Vector3.INF, false)
	check(field._cells.is_empty() and not material.get_shader_parameter("bend_enabled"), "no hero means no phantom footprint at world origin")
	field.advance(0.1, Vector3(-2, 0, 0))
	for i in 60: field.advance(1.0 / 60.0, Vector3(-2.0 + float(i + 1) / 30.0, 0, 0))
	var north := field.state_at(Vector3(0, 0, -0.625))
	var south := field.state_at(Vector3(0, 0, 0.625))
	check(north.y < -0.25 and south.y > 0.25, "eastbound hero parts grass to opposite sides of travel")
	check(north.z > 0.45 and south.z > 0.45, "both sides bend visibly")
	check(field.state_at(Vector3.ZERO).z > 0.9, "grass under feet is fully pressed")
	check(field.state_at(Vector3(0, 0, 3)).z == 0.0, "grass outside contact radius stays untouched")
	var pixel := Vector2i(floori(0.0 / field.CELL_SIZE), floori(-0.625 / field.CELL_SIZE)) - field._origin_cell
	var encoded := field._image.get_pixelv(pixel)
	check(encoded.g < 0.4 and absf(encoded.b - north.z) < 0.01, "GPU field carries signed bend direction and pressure")
	var frozen := field.state_at(Vector3.ZERO)
	field.advance(0.0, Vector3(3, 0, 0))
	check(field.state_at(Vector3.ZERO) == frozen, "pause freezes recovery and stamping")
	for i in 24: field.advance(1.0 / 60.0, Vector3(3, 0, 0), false)
	var trail := field.state_at(Vector3.ZERO).z
	check(trail > 0.04 and trail < 0.20, "grass is partly recovered after 0.4 seconds")
	for i in 24: field.advance(1.0 / 60.0, Vector3(3, 0, 0), false)
	check(field.state_at(Vector3.ZERO).z == 0.0, "grass fully recovers and clears history within 0.8 seconds")
	field.advance(1.0 / 60.0, Vector3(3, 0, 0))
	check(field.state_at(Vector3(3, 0, 0)).z > 0.9, "standing hero keeps current grass parted")
	field.advance(0.1, Vector3(40, 0, 40))
	check(field.state_at(Vector3(3, 0, 0)).z == 0.0 and field.state_at(Vector3(20, 0, 20)).z == 0.0, "respawn or teleport clears stale contact without stamping a bridge")
	check(field.state_at(Vector3(40, 0, 40)).z > 0.9, "new location starts a fresh footprint")
	for i in 90: field.advance(1.0 / 60.0, Vector3(40, 2, 40), false)
	check(field.state_at(Vector3(40, 0, 40)).z < 0.1, "airborne or missing hero lets previous contact recover")
	for i in 500: field.advance(1.0 / 60.0, Vector3(40.0 + float(i) * 0.08, 0, 40))
	check(field._cells.size() < 1200, "long travel keeps active world cells bounded")
	var current := Vector3(79.9, 0, 40)
	check(field.state_at(current).z > 0.85, "contact survives rolling texture origin changes")
	for i in 240: field.advance(1.0 / 60.0, current, false)
	check(field._cells.is_empty(), "unused trail state is eventually reclaimed")
	print("LAWN INTERACTION: %d failure(s)" % failures)
	field.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
