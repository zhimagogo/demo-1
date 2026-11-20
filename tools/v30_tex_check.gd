extends Node
func _ready() -> void:
	var srcs: Dictionary = VFXManager.texture_sources()
	for role: StringName in [&"fire", &"flame", &"flame_toon", &"puff_toon", &"smoke"]:
		print(role, " -> ", srcs.get(role, "（未注册）"))
	var t: Texture2D = VFXManager.texture_for_role(&"flame_toon")
	print("flame_toon tex=", t, " size=", t.get_size() if t != null else Vector2.ZERO)
	get_tree().quit()
