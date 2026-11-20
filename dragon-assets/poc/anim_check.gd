extends SceneTree
## 动画映射端到端校验：用真实 PawnModelRig 加载模型，打印每个项目 key 解析到哪个动画。
## 用法：godot --headless --path . --script dragon-assets/poc/anim_check.gd
## 判据：KayKit 人形七 key 沿用旧名（Idle/Walking_A/Running_A/PickUp/1H_Melee_Attack_Slice_Horizontal/Death_A）
##       Quaternius 怪物应命中 Idle/Walk/Run/Punch/Death（Flying 组为 Flying_Idle/Fast_Flying/Headbutt/Death）

const CASES := [
	{ "name": "KayKit 主角 Knight", "path": "res://assets/_PLACEHOLDER/characters/placeholder_hero.glb" },
	{ "name": "KayKit 殖民者 Rogue", "path": "res://assets/_PLACEHOLDER/characters/placeholder_colonist.glb" },
	{ "name": "KayKit 野蛮人（旧野怪皮）", "path": "res://assets/_PLACEHOLDER/characters/placeholder_colonist_barbarian.glb" },
	{ "name": "怪物 Orc（Big）", "path": "res://assets/_PLACEHOLDER/monsters/Orc.gltf" },
	{ "name": "怪物 GreenBlob（Blob）", "path": "res://assets/_PLACEHOLDER/monsters/GreenBlob.gltf" },
	{ "name": "怪物 Ghost（Flying）", "path": "res://assets/_PLACEHOLDER/monsters/Ghost.gltf", "flyer": true },
]
const KEYS := [&"idle", &"move", &"run", &"harvest", &"fight", &"follow", &"dead"]

var _fail := 0


func _init() -> void:
	print("=== 动画映射端到端校验 ===")
	var root := Node3D.new()
	get_root().add_child(root)
	for c in CASES:
		var rig := PawnModelRig.new()
		root.add_child(rig)
		var ok := rig.setup(c["path"], 1.0, 180.0, &"", &"", {}, bool(c.get("flyer", false)))
		var line := "[%s] setup=%s" % [c["name"], "OK" if ok else "失败"]
		if not ok:
			_fail += 1
			print(line, "  ← 模型未挂载（路径不存在或解析失败）")
			continue
		print(line)
		var parts: Array[String] = []
		for k in KEYS:
			var got := rig.resolved_anim(k)
			parts.append("%s→%s" % [k, got if got != "" else "（缺失）"])
		print("    ", "  ".join(parts))
		root.remove_child(rig)
		rig.free()
	print("=== 缺失统计：以上出现「（缺失）」的 key 即该模型缺少对应动作 ===")
	quit(1 if _fail > 0 else 0)
