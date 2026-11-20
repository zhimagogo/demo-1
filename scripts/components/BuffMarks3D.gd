class_name BuffMarks3D
extends Node3D
## ============================================================================
## 头顶状态标记（v19 小怪技能）：冰蓝「减速」/ 橙红「易伤」/ 绯红「血怒」。
## 与 HealthBar3D / FocusMarker 同款「Sprite3D 公告牌 + 程序化贴图 + no_depth_test」
## 管线：人堆里不被遮挡、按宿主模型高度自动抬升、到期自动隐藏。
## 挂在 Pawn 下由 Pawn 懒创建（_ensure_buff_marks），竖排叠在血条上方——
## 竖向偏移不随宿主转向旋转，避免横排标记跟着单位转身甩动。
## ============================================================================

const MARGIN: float = 0.30         # 血条顶之上的首枚标记间距
const SLOT_GAP: float = 0.24       # 标记之间的竖向间距（米）
const ICON_SIZE: float = 0.26      # 单枚标记世界边长（米）
const BOB_AMP: float = 0.035       # 轻微上下浮动幅度
const BOB_SPEED: float = 4.0
const PIXEL_SIZE: float = 0.0085   # 32px 贴图 → 约 0.27m

# 标记档案：id → { 颜色, 形状（0=环 / 1=菱形 / 2=芒星）}
const MARK_DEFS := {
	&"slow": {"color": Color(0.45, 0.80, 1.00), "shape": 0},
	&"vuln": {"color": Color(1.00, 0.42, 0.28), "shape": 1},
	&"rage": {"color": Color(0.98, 0.22, 0.26), "shape": 2},
}

var pawn: Pawn = null                 # 宿主（get_parent()）
var _slots: Dictionary = {}           # StringName -> { "sprite": Sprite3D, "left": float }
var _t: float = 0.0
static var _texes: Dictionary = {}    # int(shape) -> Texture2D（全实例共享）


func _ready() -> void:
	pawn = get_parent() as Pawn


## 显示 / 刷新一枚标记（同名标记取更长的剩余时间）。
func show_mark(id: StringName, duration: float) -> void:
	if not MARK_DEFS.has(id) or duration <= 0.0:
		return
	if not _slots.has(id):
		var sprite := Sprite3D.new()
		sprite.name = "Mark_%s" % String(id)
		sprite.texture = _texture_for_shape(int(MARK_DEFS[id]["shape"]))
		sprite.pixel_size = PIXEL_SIZE
		sprite.modulate = MARK_DEFS[id]["color"]
		sprite.no_depth_test = true       # 穿过人群可见（与血条 / 集火箭头同款约定）
		sprite.shaded = false
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.render_priority = 29
		add_child(sprite)
		_slots[id] = {"sprite": sprite, "left": 0.0}
	_slots[id]["left"] = maxf(float(_slots[id]["left"]), duration)


## 某枚标记当前是否可见（测试 / 断言用）。
func is_mark_visible(id: StringName) -> bool:
	if not _slots.has(id):
		return false
	var sprite: Sprite3D = _slots[id]["sprite"]
	return is_instance_valid(sprite) and sprite.visible


func _process(delta: float) -> void:
	if pawn == null or not is_instance_valid(pawn):
		return
	_t += delta
	# 倒计时 + 竖向排布：按固定顺序排列可见标记（slow → vuln → rage）
	var order: Array[StringName] = [&"slow", &"vuln", &"rage"]
	var head: float = 0.0
	if pawn.health_bar != null:
		head = pawn.health_bar.head_height()
	var slot_idx: int = 0
	for id in order:
		if not _slots.has(id):
			continue
		var entry: Dictionary = _slots[id]
		entry["left"] = maxf(0.0, float(entry["left"]) - delta)
		var sprite: Sprite3D = entry["sprite"]
		if not is_instance_valid(sprite):
			continue
		sprite.visible = float(entry["left"]) > 0.0
		if sprite.visible:
			var y: float = head + MARGIN + float(slot_idx) * SLOT_GAP + sin(_t * BOB_SPEED) * BOB_AMP
			position = Vector3(0.0, y, 0.0)   # 本地偏移（父节点原点在脚底）
			slot_idx += 1


# ---- 程序化贴图（白色形状 + modulate 着色，全实例共享）----

func _texture_for_shape(shape: int) -> Texture2D:
	if _texes.has(shape):
		return _texes[shape]
	const S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(S - 1) * 0.5
	for y in S:
		for x in S:
			var p := Vector2(float(x) - c, float(y) - c) / c   # -1..1
			var a := 0.0
			match shape:
				0:   # 减速 = 空心圆环（冰霜护壳感）
					a = clampf(1.0 - absf(p.length() - 0.72) / 0.20, 0.0, 1.0)
				1:   # 易伤 = 实心菱形（尖刺破甲感）
					var d := absf(p.x) + absf(p.y)
					a = clampf(1.0 - (d - 0.42) / 0.16, 0.0, 1.0)
				_:   # 血怒 = 四芒星（怒气迸发感）
					var r := p.length()
					var star := maxf(1.0 - absf(p.x) * 2.6, 1.0 - absf(p.y) * 2.6)
					a = maxf(clampf(1.0 - r / 0.92, 0.0, 1.0) * 0.35, clampf(star, 0.0, 1.0))
			if a > 0.0:
				var edge := 0.72 + 0.28 * a   # 中心亮、边缘淡
				img.set_pixel(x, y, Color(edge, edge, edge, clampf(a, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_texes[shape] = tex
	return tex
