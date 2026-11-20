extends SceneTree
## demo-1 UI 图标资产管线（第 2 步：光栅化）。
##
## 用 Godot 内建 SVG 支持（ThorVG）把 assets/ui/icons/src/*.svg 渲染成
## assets/ui/icons/<id>.png，无需 cairosvg / rsvg 等外部依赖。
##
## 用法：
##   godot --headless --path . --script tools/rasterize_icons.gd
##   godot --headless --path . --script tools/rasterize_icons.gd -- --size 128

const SRC_DIR := "res://assets/ui/icons/src"
const OUT_DIR := "res://assets/ui/icons"
const DEFAULT_SIZE := 128


func _initialize() -> void:
	var target := DEFAULT_SIZE
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i] == "--size" and i + 1 < argv.size():
			target = int(argv[i + 1])

	var dir := DirAccess.open(SRC_DIR)
	if dir == null:
		push_error("找不到图标源目录：%s（先运行 tools/fetch_icons.py）" % SRC_DIR)
		quit(1)
		return

	var names := dir.get_files()
	names.sort()
	var ok := 0
	var failed: Array[String] = []
	for file_name in names:
		if not file_name.ends_with(".svg"):
			continue
		var id := file_name.get_basename()
		var svg := FileAccess.get_file_as_string("%s/%s" % [SRC_DIR, file_name])
		if svg.is_empty():
			failed.append("%s（读取为空）" % id)
			continue
		var scale := float(target) / 512.0
		var img := Image.new()
		var svg_err := img.load_svg_from_string(svg, scale)
		if svg_err != OK or img.is_empty():
			failed.append("%s（SVG 解析失败 %d）" % [id, svg_err])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var out_path := "%s/%s.png" % [OUT_DIR, id]
		var err := img.save_png(out_path)
		if err != OK:
			failed.append("%s（写盘失败 %d）" % [id, err])
			continue
		ok += 1
		print("[raster] %s → %s (%dx%d)" % [id, out_path, img.get_width(), img.get_height()])

	print("[raster] 完成 %d 个图标，%.0fpx" % [ok, target])
	for item in failed:
		print("[raster] 失败 " + item)
	quit(0 if failed.is_empty() else 1)
