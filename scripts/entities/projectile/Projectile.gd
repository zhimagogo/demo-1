class_name Projectile
extends Area3D
## ============================================================================
## 飞行箭矢投射物：追踪预定目标，飞达 HIT_RADIUS 即对其 HealthComponent.apply_damage。
## 命中或超时(lifetime)自动销毁。目标中途死亡/失效 → 沿最后方向直线飞至超时销毁。
## 不参与物理重叠（monitoring/monitorable=false），靠每帧距离判定命中，
## 避免高速离散物理穿模、打不中横移目标。
## ============================================================================

@export var speed: float = 16.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0        # 最大飞行秒数（防丢目标后永久存留）

var target: Node                          # 预定目标（敌方 Pawn/建筑）
var source: Node                          # 攻击者（Pawn/Building），作 apply_damage 的 source
var is_crit: bool = false                 # v20 暴击标记（AttackerComponent 发射时掷骰；命中补飘字）
# ---- v26 火球溅射（巨龙普攻）：> 0 时命中点爆炸，对 splash_group 内其他单位造成溅射伤害 ----
# 直击目标只吃 damage；溅射范围内**其余**敌人吃 splash_damage（不叠加双份）。
var splash_radius: float = 0.0            # 爆炸半径（米），0 = 无溅射（普通箭矢/法术弹）
var splash_damage: float = 0.0            # 溅射伤害
var splash_group: String = "enemy"        # 溅射结算的敌方分组（按施放者阵营填）
var splash_effect: StringName = &""       # 爆炸特效 id（空 = 火星+冲击环默认款）
# ---- 视觉档案（由 AttackerComponent 按职业注入；缺省 = 箭矢 + 暖色火花）----
var visual_kind: int = 0                  # 0 = 箭矢（细长盒），1 = 法术弹（发光球），2 = 卡通火球（龙）
var body_scale: float = 1.0               # 弹体外观倍率（巨龙火球 1.75；不改判定半径）
var body_color: Color = Color(0.85, 0.8, 0.55)
var trail_effect: StringName = &"arrow_trail"   # 飞行拖尾（attach_trail 挂载）
var impact_effect: StringName = &"hit_spark"    # 命中爆散
var impact_color: Color = Color(1.0, 0.78, 0.4)
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _flame_sprite: Sprite3D = null        # v30：卡通火球的火舌贴图层（随飞行脉动）
var _fire_light: OmniLight3D = null       # v30：飞行照明灯（橙光随时抖动）

const HIT_RADIUS: float = 0.75            # 抵近此距离判定命中（容错横移）
const SOURCE_HEIGHT: float = 1.0          # 起手高度（胸口/弓位）
# 共享 mesh / 材质按「外观键」缓存，运行期不 new 新材质
static var _shared_meshes: Dictionary = {}
static var _shared_materials: Dictionary = {}


func _ready() -> void:
	# 不参与任何物理重叠/拾取：仅靠每帧距离判定命中
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	add_child(_make_body())
	# 飞行拖尾（世界坐标粒子留在原地 → 拖出尾迹；投射物销毁即随之消失）
	if trail_effect != &"":
		VFXManager.attach_trail(self, trail_effect)
	# v30：卡通火球（巨龙）——火舌贴图层（cel 火焰包住弹体）+ 飞行照明灯
	if visual_kind == 2:
		_flame_sprite = Sprite3D.new()
		_flame_sprite.name = "ToonFlame"
		_flame_sprite.texture = VFXManager.texture_for_role(&"flame_toon")
		_flame_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_flame_sprite.shaded = false
		_flame_sprite.transparent = true
		_flame_sprite.modulate = Color(1.0, 0.66, 0.28, 1.0)
		_flame_sprite.pixel_size = 0.0036 * body_scale   # 256px 贴图 ≈ 1.6m 火衣（包住 0.6m 弹芯）
		_flame_sprite.render_priority = 4
		add_child(_flame_sprite)
		_fire_light = OmniLight3D.new()
		_fire_light.name = "FireLight"
		_fire_light.light_color = Color(1.0, 0.6, 0.25)
		_fire_light.light_energy = 1.6
		_fire_light.omni_range = 6.0
		_fire_light.shadow_enabled = false
		add_child(_fire_light)


## 弹体外观：箭矢 = 细长盒，法术弹 = 发光球（将来可换 res://assets/vfx/arrow.tscn）
func _make_body() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var key := "%d|%s|%.2f" % [visual_kind, body_color.to_html(false), body_scale]
	if not _shared_meshes.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mat.emission_enabled = true
		mat.emission = body_color
		mat.emission_energy_multiplier = 2.6 if visual_kind == 1 else 1.2
		if visual_kind == 1:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if visual_kind == 2:
			# v30：卡通火球弹芯——亮度压在 1.5（辉光环境里 >3 会炸成白球盖住火衣），
			# 「火」的轮廓交给火衣贴图，芯只做透出来的亮核
			mat.albedo_color = Color(1.0, 0.75, 0.35)
			mat.emission = Color(1.0, 0.62, 0.22)
			mat.emission_energy_multiplier = 1.5
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared_materials[key] = mat
		var mesh: Mesh
		if visual_kind >= 1:
			var sp := SphereMesh.new()
			sp.radius = 0.17 * body_scale
			sp.height = 0.34 * body_scale
			mesh = sp
		else:
			var bx := BoxMesh.new()
			bx.size = Vector3(0.06, 0.06, 0.62) * body_scale
			mesh = bx
		mesh.material = mat
		_shared_meshes[key] = mesh
	mi.mesh = _shared_meshes[key]
	return mi


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	# v30：卡通火球飞行脉动——火衣呼吸缩放 + 灯光随机抖（火焰的本质就是不稳定的）
	if _flame_sprite != null:
		_flame_sprite.scale = Vector3.ONE * randf_range(0.9, 1.16)
	if _fire_light != null:
		_fire_light.light_energy = randf_range(1.2, 2.2)
	# 追踪：目标有效则速度始终指向目标；失效则保持上一帧方向直线飞
	if is_instance_valid(target):
		var desired: Vector3 = target.global_position - global_position
		desired.y = 0.0
		if desired.length_squared() > 0.0001:
			_velocity = desired.normalized() * speed
		# 命中判定（XZ 平面距离）
		if desired.length() <= HIT_RADIUS:
			_impact(target)
			return
	global_position += _velocity * delta
	# 箭体朝向飞行方向（look_at 让 -Z 指向前方点，与箭体 z 轴长方向一致）
	if _velocity.length_squared() > 0.01:
		look_at(global_position + _velocity, Vector3.UP)


## 命中结算：去中心化，直接调目标 HealthComponent（仿 AttackerComponent.try_attack）。
func _impact(node: Node) -> void:
	if is_instance_valid(node):
		var h: HealthComponent = node.get_node_or_null("HealthComponent")
		if h != null and not h.is_dead():
			h.apply_damage(damage, source)
			# v20 暴击反馈：目标头顶橙红「暴击！」（大伤害数字由 damage_dealt 通道照常出）
			if is_crit:
				EventBus.floating_text.emit("暴击！", Color(1.0, 0.45, 0.2),
					global_position + Vector3(0.0, 0.65, 0.0))
				# v27：远程暴击同享金色星芒（与近战 _emit_crit_feedback 同一款）
				VFXManager.spawn_effect(&"crit_burst", global_position, 0.0,
					{"throttle_key": get_instance_id()})
			# 命中爆散按弹种配色（箭矢暖橙火星 / 法术弹紫色爆散 + 冲击环）；
			# v28：沿弹道方向的定向喷溅 + 白闪（速度即方向）
			var flight_dir := _velocity.normalized()
			var flight_yaw := atan2(-flight_dir.x, -flight_dir.z) if _velocity.length_squared() > 0.01 else 0.0
			if impact_effect != &"":
				VFXManager.spawn_hit_impact(global_position, impact_color, impact_effect,
					null, flight_yaw)
			AudioManager.play_sfx(&"arrow_hit", global_position)
	# v26 火球爆炸：命中点对周围敌人造成小片溅射 + 更大一圈的爆炸特效
	if splash_radius > 0.0 and splash_damage > 0.0:
		# v30：巨龙火球 → 卡通分层爆炸（火舌团 + 白闪 + 烟团 + 橙环 + 闪烁灯光），
		# 替代旧「几粒火星」的 fire_burst；其他来源维持原样
		if source is DragonPet:
			VFXManager.spawn_toon_fireball_explosion(global_position)
		_explode_splash(node)
	queue_free()


## 爆炸溅射：以命中点为圆心，splash_group 内（直击目标除外）的活敌各吃 splash_damage。
func _explode_splash(direct_target: Node) -> void:
	var fx_color := impact_color if impact_color != Color(0.85, 0.8, 0.55) else Color(1.0, 0.55, 0.2)
	if splash_effect != &"":
		VFXManager.spawn_effect(splash_effect, global_position + Vector3(0.0, 0.5, 0.0), 0.0,
			{"amount": 16, "lifetime": 0.45, "throttle_key": get_instance_id()})
	VFXManager.spawn_hit_impact(global_position + Vector3(0.0, 0.6, 0.0), fx_color, &"hit_spark",
		get_instance_id())
	VFXManager.spawn_effect(&"hit_ring", global_position + Vector3(0.0, 0.4, 0.0), 0.0,
		{"color": fx_color, "throttle_key": get_instance_id()})
	var radius_sq := splash_radius * splash_radius
	for v in get_tree().get_nodes_in_group(splash_group):
		if not is_instance_valid(v) or v == direct_target or not (v is Node3D):
			continue
		var victim := v as Node3D
		var vh: HealthComponent = victim.get_node_or_null("HealthComponent")
		if vh == null or vh.is_dead():
			continue
		if global_position.distance_squared_to(victim.global_position) > radius_sq:
			continue
		vh.apply_damage(splash_damage, source)
