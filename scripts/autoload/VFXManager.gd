extends Node
## ============================================================================
## VFXManager —— 特效播放单例（autoload）。
##
## 三条并行管线，全部按 effect_id 从内置 EffectDef 注册表代码生成：
## ① PARTICLES —— GPUParticles3D（命中火星 / 旋风光环 / 冲刺拖尾）；
## ② SLASH     —— SurfaceTool 自绘的月牙弧面 + vfx_arc.gdshader（挥砍刀光）；
## ③ RING/FLASH/GLOW —— 1×1 公告牌网格 + vfx_billboard.gdshader
##    （命中冲击环 / 枪口十字星 / 施法微光；尺寸走节点 scale、朝向自动正对相机）。
## TRAIL 是挂在投射物上的持续发射尾迹（用 attach_trail 挂载，不占活动配额）。
##
## 约定：
## - 所有 mesh / material / 贴图按 effect_id 共享缓存，运行期绝不 new 新材质；
## - 生命周期由本单例 _process 统一推进（缩放 / 扫动 / 淡入淡出 / 自动释放），
##   _active_effects 严格等于「已登记未释放」的特效数，超过 MAX_ACTIVE_EFFECTS 丢弃；
## - 美术资源放 res://assets/vfx/<effect_id>.tscn 即优先使用（调用方不变）；
##   粒子贴图放 res://assets/vfx/textures/ 按文件名关键词自动匹配（缺失走程序化回退）。
## ============================================================================

const MAX_ACTIVE_EFFECTS := 30           # 硬上限：战斗密集时宁可丢弃，也不无限创建 GPU 资源（v27 扩容：丰富度特效并发更多）
const VFX_TEX_DIR := "res://assets/vfx/textures/"
const ARC_SHADER_PATH := "res://assets/shaders/vfx_arc.gdshader"
const BILLBOARD_SHADER_PATH := "res://assets/shaders/vfx_billboard.gdshader"
const BILLBOARD_OVERLAY_SHADER_PATH := "res://assets/shaders/vfx_billboard_overlay.gdshader"   # no_depth_test 用（穿透变体）
const THROTTLE_DEFAULT := 0.1            # 同一单位同种特效的最小间隔（秒）
const PARTICLE_TAIL := 0.12              # 粒子发射结束后再保留一点时间，让残余粒子飞完
const TRAIL_AABB_MARGIN := 10.0          # 拖尾是世界坐标粒子，必须放大包围盒防视锥剔除
const PARTICLE_AABB_BOX := 8.0           # 一次性粒子特效的包围盒半径（世界坐标粒子防剔除）
const PRIORITY_FALLBACK := 1             # 未注册 / .tscn 覆盖件的默认优先级（按出招类保护）
const PRIORITY_HIT := 0                  # 命中反馈（火星 / 冲击环）：名额不够时优先丢
const PRIORITY_ATTACK := 1               # 出招表现（刀光弧 / 枪口闪光 / 施法微光 / 技能）：不可丢
## v33：需要「脉动」读感的网格类特效 id（预警圈不脉动就像静态贴图，读不出「正在倒计时」）。
const PULSE_IDS: Array[StringName] = [&"meteor_telegraph"]

# 诊断统计（测试 / 调试用）：本局累计生成次数（effect_id -> 次数）
var stat_spawned_by_id: Dictionary = {}
var stat_dropped_by_budget: int = 0
# 截图 / 录屏工具用：>= 0 时所有网格类特效定格在该进度（0~1）且不再释放；-1 = 正常播放
var debug_anim_progress: float = -1.0

var _defs: Dictionary = {}                        # StringName -> EffectDef
var _composites: Dictionary = {}                  # StringName -> 复合特效描述（主层 + 附加层 / 点光 / 拖尾）
var _active_effects: int = 0
var _anims: Array = []                            # 活动特效动画条目
var _shared_particle_meshes: Dictionary = {}      # 变体键 -> QuadMesh（公告牌粒子面片）
var _shared_particle_materials: Dictionary = {}   # 变体键 -> ParticleProcessMaterial
var _shared_arc_meshes: Dictionary = {}           # 尺寸键 -> ArrayMesh（月牙弧面）
var _shared_materials: Dictionary = {}            # 键 -> ShaderMaterial（弧 / 公告牌）
var _textures: Dictionary = {}                    # 角色(StringName) -> Texture2D
var _texture_from_file: Dictionary = {}           # 角色 -> 是否来自 assets/vfx/textures
var _throttle_until: Dictionary = {}              # 节流键 -> 到期毫秒
var _quad_mesh: QuadMesh = null                   # 公告牌共用的 1×1 面片


func _ready() -> void:
	_load_textures()
	_register_defaults()


# ============================================================================
# 注册表：所有 effect_id 在此声明（新增特效只动这里 + 调用点）
# ============================================================================

func _register_defaults() -> void:
	# ---- 挥砍刀光（Kind.SLASH）：主角三段连招 + 各职业挥击 ----
	_defs[&"slash_arc"] = _slash(&"SlashArc", Color(0.92, 0.97, 1.0), 152.0, 1.25, 0.24, 84.0)
	_defs[&"slash_arc_heavy"] = _slash(&"SlashArcHeavy", Color(1.0, 0.74, 0.32), 196.0, 1.52, 0.34, 130.0, true)
	_defs[&"slash_arc_small"] = _slash(&"SlashArcSmall", Color(0.90, 0.95, 1.0), 118.0, 0.95, 0.19, 76.0)
	_defs[&"axe_arc"] = _slash(&"AxeArc", Color(0.96, 0.78, 0.42), 122.0, 1.15, 0.22, 64.0)
	_defs[&"dagger_arc"] = _slash(&"DaggerArc", Color(0.78, 1.0, 0.92), 92.0, 0.85, 0.15, -118.0)

	# ---- 命中反馈：火星四溅 + 冲击环 ----
	var spark := _particles(&"HitSparks", Color(1.0, 0.74, 0.34), 20, 0.34, &"spark")
	spark.shape = EffectDef.Shape.BURST
	spark.speed_min = 3.0
	spark.speed_max = 7.5
	spark.gravity = Vector3(0.0, -16.0, 0.0)     # 火星受重力下坠
	spark.damping = 0.9                          # 阻力 → 拖尾感
	spark.size = 0.17
	spark.scale_min = 0.5
	spark.scale_max = 1.1
	spark.priority = PRIORITY_HIT
	_defs[&"hit_spark"] = spark

	var ring := _billboard(&"ImpactRing", Color(1.0, 0.84, 0.46), EffectDef.Kind.RING, 0.30, &"ring")
	ring.ring_amount = 1.0
	ring.thickness = 0.16
	ring.softness = 0.45
	ring.strength = 0.9
	ring.scale_from = 0.42
	ring.scale_to = 1.55
	ring.rise = 0.12
	ring.no_depth_test = true                    # 人堆里也要看得见
	ring.priority = PRIORITY_HIT
	_defs[&"hit_ring"] = ring

	var magic := _particles(&"MagicBurst", Color(0.74, 0.5, 1.0), 26, 0.45, &"magic")
	magic.shape = EffectDef.Shape.BURST
	magic.speed_min = 2.5
	magic.speed_max = 6.5
	magic.gravity = Vector3(0.0, -3.5, 0.0)
	magic.damping = 1.4
	magic.size = 0.34
	magic.scale_min = 0.7
	magic.scale_max = 1.6
	magic.priority = PRIORITY_HIT
	_defs[&"magic_burst"] = magic

	# ---- 职业专属：枪口闪光 / 施法微光 ----
	var muzzle := _billboard(&"MuzzleFlash", Color(1.0, 0.95, 0.72), EffectDef.Kind.FLASH, 0.09, &"star")
	muzzle.ring_amount = 0.0
	muzzle.scale_from = 0.46
	muzzle.scale_to = 0.78
	muzzle.fade_in_end = 0.05
	muzzle.fade_out_start = 0.30
	muzzle.strength = 1.35
	muzzle.spin_deg = 150.0              # 十字星击发瞬间旋开（v27 品质：闪光不再静止贴图）
	muzzle.no_depth_test = true
	muzzle.priority = PRIORITY_ATTACK
	_defs[&"muzzle_flash"] = muzzle

	var cast := _billboard(&"CastGlow", Color(0.72, 0.46, 1.0), EffectDef.Kind.GLOW, 0.30, &"glow")
	cast.scale_from = 0.42
	cast.scale_to = 0.86
	cast.fade_in_end = 0.22
	cast.fade_out_start = 0.62
	cast.strength = 1.0
	cast.no_depth_test = true
	cast.priority = PRIORITY_ATTACK
	_defs[&"cast_glow"] = cast

	# ---- 投射物拖尾（attach_trail 挂载；世界坐标粒子留在原地形成尾迹）----
	var arrow := _trail(&"ArrowTrail", Color(0.92, 0.94, 1.0), 26, 0.30, &"trace")
	arrow.speed_min = 0.15
	arrow.speed_max = 0.5
	arrow.size = 0.11
	arrow.scale_min = 0.4
	arrow.scale_max = 0.9
	_defs[&"arrow_trail"] = arrow

	var magic_trail := _trail(&"MagicTrail", Color(0.62, 0.34, 1.0), 40, 0.36, &"glow")
	magic_trail.speed_min = 0.1
	magic_trail.speed_max = 0.4
	magic_trail.size = 0.20
	magic_trail.scale_min = 0.5
	magic_trail.scale_max = 1.0
	_defs[&"magic_trail"] = magic_trail

	# ---- v26 驯龙：火球尾焰（橙红余烬，巨龙普攻）与爆炎（命中爆炸）----
	# 巨龙火球比箭矢大一圈：拖尾加量加粗（v29 与 body_scale 1.75 配套）
	var fire_trail := _trail(&"FireTrail", Color(1.0, 0.5, 0.18), 60, 0.42, &"fire")
	fire_trail.speed_min = 0.15
	fire_trail.speed_max = 0.6
	fire_trail.size = 0.38
	fire_trail.scale_min = 0.8
	fire_trail.scale_max = 1.7
	_defs[&"fire_trail"] = fire_trail

	var fire_burst := _particles(&"FireBurst", Color(1.0, 0.55, 0.2), 26, 0.42, &"fire")
	fire_burst.shape = EffectDef.Shape.BURST
	fire_burst.speed_min = 3.0
	fire_burst.speed_max = 7.0
	fire_burst.gravity = Vector3(0.0, 2.5, 0.0)   # 火焰上飘
	fire_burst.damping = 1.6
	fire_burst.size = 0.30
	fire_burst.scale_min = 0.7
	fire_burst.scale_max = 1.6
	fire_burst.priority = PRIORITY_HIT
	_defs[&"fire_burst"] = fire_burst

	# ---- 既有 id（保持原语义：其它系统在用）----
	var burst := EffectDef.new()
	burst.kind = EffectDef.Kind.PARTICLES
	burst.shape = EffectDef.Shape.BURST
	burst.node_name = "HitBurst"
	burst.color = Color(1.0, 0.7, 0.4)
	burst.amount = 10
	burst.lifetime = 0.28
	burst.speed_min = 2.0
	burst.speed_max = 5.0
	burst.size = 0.16
	burst.texture_role = &"spark"
	burst.priority = PRIORITY_HIT
	_defs[&"hit_burst"] = burst

	var aura := EffectDef.new()
	aura.kind = EffectDef.Kind.PARTICLES
	aura.shape = EffectDef.Shape.AURA
	aura.node_name = "WhirlwindAura"
	aura.color = Color(0.5, 0.8, 1.0)
	aura.amount = 40
	aura.lifetime = 0.55
	aura.radius = 3.4
	aura.speed_min = 3.0
	aura.speed_max = 6.0
	aura.size = 0.24
	aura.texture_role = &"glow"
	aura.priority = PRIORITY_ATTACK       # 技能光环代表「技能放出去了」，不可丢
	_defs[&"whirlwind_aura"] = aura

	var trail := EffectDef.new()
	trail.kind = EffectDef.Kind.PARTICLES
	trail.shape = EffectDef.Shape.TRAIL
	trail.node_name = "ChargeTrail"
	trail.color = Color(1.0, 1.0, 0.8)
	trail.amount = 24
	trail.lifetime = 0.32
	trail.speed_min = 0.4
	trail.speed_max = 1.2
	trail.size = 0.2
	trail.texture_role = &"glow"
	trail.priority = PRIORITY_ATTACK
	_defs[&"charge_trail"] = trail

	# ---- v19 职业技能特效：暴风雪宣告环 / 血怒爆发环 / 背刺闪现环 ----
	var blizzard_ring := _billboard(&"BlizzardRing", Color(0.55, 0.80, 1.0), EffectDef.Kind.RING, 0.7, &"ring")
	blizzard_ring.ring_amount = 1.0
	blizzard_ring.thickness = 0.12
	blizzard_ring.softness = 0.5
	blizzard_ring.strength = 0.95
	blizzard_ring.scale_from = 0.2
	blizzard_ring.scale_to = 4.8          # 张到与 4.5m AoE 同宽：落雪区域一眼可读
	blizzard_ring.rise = 0.1
	blizzard_ring.no_depth_test = true
	blizzard_ring.priority = PRIORITY_ATTACK
	_defs[&"blizzard_ring"] = blizzard_ring

	var rage_burst := _billboard(&"RageBurst", Color(1.0, 0.28, 0.22), EffectDef.Kind.RING, 0.5, &"ring")
	rage_burst.ring_amount = 1.0
	rage_burst.thickness = 0.18
	rage_burst.strength = 1.1
	rage_burst.scale_from = 0.3
	rage_burst.scale_to = 2.6
	rage_burst.fade_out_start = 0.35
	rage_burst.no_depth_test = true
	rage_burst.priority = PRIORITY_ATTACK
	_defs[&"rage_burst"] = rage_burst

	var blink_ring := _billboard(&"BlinkRing", Color(0.66, 0.44, 1.0), EffectDef.Kind.RING, 0.4, &"ring")
	blink_ring.ring_amount = 1.0
	blink_ring.thickness = 0.14
	blink_ring.strength = 1.0
	blink_ring.scale_from = 0.25
	blink_ring.scale_to = 1.6
	blink_ring.fade_out_start = 0.3
	blink_ring.no_depth_test = true
	blink_ring.priority = PRIORITY_ATTACK
	_defs[&"blink_ring"] = blink_ring

	# ---- v27 特效丰富度：暴击 / 升级 / 死亡 / 治疗 / 建造 / 拾取 / 冲刺 ----
	var crit_burst := _billboard(&"CritBurst", Color(1.0, 0.82, 0.30), EffectDef.Kind.FLASH, 0.45, &"star")
	crit_burst.scale_from = 0.5
	crit_burst.scale_to = 1.5
	crit_burst.strength = 1.3
	crit_burst.spin_deg = 220.0          # 金色星芒旋开——暴击的「会心一击」读感
	crit_burst.fade_out_start = 0.4
	crit_burst.no_depth_test = true
	crit_burst.priority = PRIORITY_ATTACK
	_defs[&"crit_burst"] = crit_burst

	var death_wisp := _particles(&"DeathWisp", Color(0.62, 0.90, 1.0), 20, 0.9, &"glow")
	death_wisp.shape = EffectDef.Shape.AURA
	death_wisp.radius = 0.5
	death_wisp.speed_min = 0.6
	death_wisp.speed_max = 1.4
	death_wisp.gravity = Vector3(0.0, 1.6, 0.0)   # 魂魄上飘
	death_wisp.damping = 0.6
	death_wisp.size = 0.2
	death_wisp.scale_min = 0.6
	death_wisp.scale_max = 1.4
	death_wisp.priority = PRIORITY_ATTACK  # 死亡只此一次，不可被命中特效挤掉
	_defs[&"death_wisp"] = death_wisp

	var levelup_ring := _billboard(&"LevelupRing", Color(1.0, 0.85, 0.30), EffectDef.Kind.RING, 0.6, &"ring")
	levelup_ring.ring_amount = 1.0
	levelup_ring.thickness = 0.10
	levelup_ring.strength = 1.05
	levelup_ring.scale_from = 0.3
	levelup_ring.scale_to = 2.3
	levelup_ring.rise = 0.4              # 金环上浮——「经验灌顶」的上升感
	levelup_ring.no_depth_test = true
	levelup_ring.priority = PRIORITY_ATTACK
	_defs[&"levelup_ring"] = levelup_ring

	var levelup_spark := _particles(&"LevelupSpark", Color(1.0, 0.88, 0.4), 16, 0.7, &"spark")
	levelup_spark.shape = EffectDef.Shape.AURA
	levelup_spark.radius = 0.4
	levelup_spark.speed_min = 1.0
	levelup_spark.speed_max = 2.2
	levelup_spark.gravity = Vector3(0.0, 2.4, 0.0)   # 金屑升腾
	levelup_spark.size = 0.15
	levelup_spark.scale_min = 0.5
	levelup_spark.scale_max = 1.1
	levelup_spark.priority = PRIORITY_ATTACK
	_defs[&"levelup_spark"] = levelup_spark

	var heal_mote := _particles(&"HealMote", Color(0.45, 1.0, 0.62), 6, 0.9, &"glow")
	heal_mote.shape = EffectDef.Shape.AURA
	heal_mote.radius = 0.35
	heal_mote.speed_min = 0.5
	heal_mote.speed_max = 1.0
	heal_mote.gravity = Vector3(0.0, 1.2, 0.0)   # 治疗荧光缓缓上升
	heal_mote.size = 0.13
	heal_mote.scale_min = 0.5
	heal_mote.scale_max = 1.0
	heal_mote.priority = PRIORITY_HIT      # 环境类表现：名额紧张时让位给战斗反馈
	_defs[&"heal_mote"] = heal_mote

	var build_dust := _particles(&"BuildDust", Color(0.78, 0.68, 0.50), 18, 0.6, &"smoke")
	build_dust.shape = EffectDef.Shape.BURST
	build_dust.speed_min = 1.5
	build_dust.speed_max = 3.5
	build_dust.gravity = Vector3(0.0, -3.0, 0.0)   # 尘土落地
	build_dust.damping = 2.0
	build_dust.size = 0.26
	build_dust.scale_min = 0.8
	build_dust.scale_max = 1.7
	build_dust.priority = PRIORITY_ATTACK
	_defs[&"build_dust"] = build_dust

	var coin_sparkle := _particles(&"CoinSparkle", Color(1.0, 0.88, 0.35), 8, 0.4, &"star")
	coin_sparkle.shape = EffectDef.Shape.BURST
	coin_sparkle.speed_min = 1.2
	coin_sparkle.speed_max = 2.6
	coin_sparkle.gravity = Vector3(0.0, -2.0, 0.0)
	coin_sparkle.size = 0.12
	coin_sparkle.scale_min = 0.5
	coin_sparkle.scale_max = 1.0
	coin_sparkle.priority = PRIORITY_HIT
	_defs[&"coin_sparkle"] = coin_sparkle

	var sprint_dust := _particles(&"SprintDust", Color(0.72, 0.66, 0.55), 5, 0.45, &"smoke")
	sprint_dust.shape = EffectDef.Shape.BURST
	sprint_dust.speed_min = 0.8
	sprint_dust.speed_max = 1.6
	sprint_dust.gravity = Vector3(0.0, -1.5, 0.0)
	sprint_dust.size = 0.18
	sprint_dust.scale_min = 0.7
	sprint_dust.scale_max = 1.3
	sprint_dust.priority = PRIORITY_HIT
	_defs[&"sprint_dust"] = sprint_dust

	# ---- v28 战斗打击感：定向喷溅 / 命中白闪 / 重击震波 ----
	var hit_spark_cone := _particles(&"HitSparkCone", Color(1.0, 0.78, 0.4), 12, 0.35, &"spark")
	hit_spark_cone.shape = EffectDef.Shape.BURST
	hit_spark_cone.spread = 38.0        # 窄锥：沿「攻击者 → 目标」方向喷溅
	hit_spark_cone.speed_min = 3.5
	hit_spark_cone.speed_max = 7.5
	hit_spark_cone.gravity = Vector3(0.0, -9.0, 0.0)
	hit_spark_cone.damping = 1.2
	hit_spark_cone.size = 0.14
	hit_spark_cone.scale_min = 0.5
	hit_spark_cone.scale_max = 1.1
	hit_spark_cone.local_coords = true  # 局部坐标：旋转节点即旋转喷射方向
	hit_spark_cone.priority = PRIORITY_HIT
	_defs[&"hit_spark_cone"] = hit_spark_cone

	var impact_flash := _billboard(&"ImpactFlash", Color(1.0, 0.97, 0.88), EffectDef.Kind.FLASH, 0.12, &"glow")
	impact_flash.scale_from = 0.3
	impact_flash.scale_to = 0.7
	impact_flash.strength = 1.25
	impact_flash.fade_in_end = 0.04
	impact_flash.fade_out_start = 0.5
	impact_flash.no_depth_test = true
	impact_flash.priority = PRIORITY_HIT   # 每次命中都伴随，名额紧张时可丢
	_defs[&"impact_flash"] = impact_flash

	var heavy_shock := _billboard(&"HeavyShock", Color(1.0, 0.9, 0.6), EffectDef.Kind.RING, 0.45, &"ring")
	heavy_shock.ring_amount = 1.0
	heavy_shock.thickness = 0.14
	heavy_shock.strength = 1.1
	heavy_shock.scale_from = 0.3
	heavy_shock.scale_to = 2.8
	heavy_shock.no_depth_test = true
	heavy_shock.priority = PRIORITY_ATTACK
	_defs[&"heavy_shock"] = heavy_shock

	# ---- v30 巨龙卡通火焰：火舌尾焰 / 出膛火苗 / 爆炸火舌团 / 爆炸烟团 ----
	# 全部走 toon_flame / toon_puff 贴图 + alpha 混合 + 大角翻滚（cel 色块的本色读法）。
	var fire_tongue_trail := _trail(&"FireTongueTrail", Color(1.0, 0.6, 0.16), 30, 0.42, &"flame_toon")
	fire_tongue_trail.size = 0.34
	fire_tongue_trail.scale_min = 0.6
	fire_tongue_trail.scale_max = 1.5
	fire_tongue_trail.angle_jitter = 90.0     # 火舌四散翻滚
	fire_tongue_trail.alpha_blend = true
	fire_tongue_trail.priority = PRIORITY_ATTACK
	_defs[&"fire_tongue_trail"] = fire_tongue_trail

	var fire_snap := _particles(&"FireSnap", Color(1.0, 0.6, 0.16), 10, 0.3, &"flame_toon")
	fire_snap.shape = EffectDef.Shape.BURST
	fire_snap.spread = 30.0
	fire_snap.speed_min = 3.0
	fire_snap.speed_max = 6.0
	fire_snap.gravity = Vector3(0.0, 1.2, 0.0)
	fire_snap.size = 0.3
	fire_snap.scale_min = 0.6
	fire_snap.scale_max = 1.3
	fire_snap.angle_jitter = 70.0
	fire_snap.local_coords = true             # 随出膛朝向定向（旋转节点即定向）
	fire_snap.alpha_blend = true
	fire_snap.priority = PRIORITY_ATTACK
	_defs[&"fire_snap"] = fire_snap

	var fireball_burst := _particles(&"FireballBurst", Color(1.0, 0.58, 0.14), 26, 0.55, &"flame_toon")
	fireball_burst.shape = EffectDef.Shape.BURST
	fireball_burst.spread = 180.0
	fireball_burst.speed_min = 3.0
	fireball_burst.speed_max = 7.5
	fireball_burst.gravity = Vector3(0.0, 3.5, 0.0)   # 火舌向上舔
	fireball_burst.damping = 1.4
	fireball_burst.size = 0.55
	fireball_burst.scale_min = 0.7
	fireball_burst.scale_max = 1.9
	fireball_burst.angle_jitter = 180.0
	fireball_burst.alpha_blend = true
	fireball_burst.priority = PRIORITY_ATTACK
	_defs[&"fireball_burst"] = fireball_burst

	var toon_smoke_pop := _particles(&"ToonSmokePop", Color(0.5, 0.44, 0.4), 10, 0.8, &"puff_toon")
	toon_smoke_pop.shape = EffectDef.Shape.BURST
	toon_smoke_pop.spread = 180.0
	toon_smoke_pop.speed_min = 1.0
	toon_smoke_pop.speed_max = 2.4
	toon_smoke_pop.gravity = Vector3(0.0, 1.8, 0.0)   # 烟团上飘
	toon_smoke_pop.damping = 0.9
	toon_smoke_pop.size = 0.7
	toon_smoke_pop.scale_min = 0.8
	toon_smoke_pop.scale_max = 1.8
	toon_smoke_pop.angle_jitter = 180.0
	toon_smoke_pop.alpha_blend = true
	toon_smoke_pop.priority = PRIORITY_HIT
	_defs[&"toon_smoke_pop"] = toon_smoke_pop

	# ---- v33 进阶职业技能特效（契约第 4 节，14 个 id）----
	_register_v33_effects()


## 刀光（月牙弧面）定义。
func _slash(name: String, color: Color, arc_deg: float, width: float,
		lifetime: float, spin: float, heavy: bool = false) -> EffectDef:
	var d := EffectDef.new()
	d.kind = EffectDef.Kind.SLASH
	d.node_name = name
	d.color = color
	d.arc_deg = arc_deg
	d.arc_width = width
	d.arc_inner_ratio = 0.48
	d.lifetime = lifetime
	d.spin_deg = spin
	d.heavy = heavy
	d.priority = PRIORITY_ATTACK
	d.scale_from = 0.80
	d.scale_to = 1.06
	d.fade_in_end = 0.16
	d.fade_out_start = 0.48
	return d


## 公告牌特效定义（冲击环 / 枪口闪光 / 施法微光）。
## spin_deg 在公告牌语义下 = 贴图随生命周期旋转的总角度（刀光语义的「节点绕 Y 扫动」
## 对永远正对相机的公告牌无效，故借字段表达 shader 内的贴图旋转；环带对称旋转无感）。
func _billboard(name: String, color: Color, kind: int, lifetime: float, role: StringName) -> EffectDef:
	var d := EffectDef.new()
	d.kind = kind
	d.node_name = name
	d.color = color
	d.lifetime = lifetime
	d.texture_role = role
	d.spin_deg = 0.0
	d.fade_in_end = 0.12
	d.fade_out_start = 0.45
	return d


## 粒子特效定义。
func _particles(name: String, color: Color, amount: int, lifetime: float, role: StringName) -> EffectDef:
	var d := EffectDef.new()
	d.kind = EffectDef.Kind.PARTICLES
	d.node_name = name
	d.color = color
	d.amount = amount
	d.lifetime = lifetime
	d.texture_role = role
	d.spread = 180.0
	return d


## 拖尾定义（持续发射，世界坐标粒子）。
func _trail(name: String, color: Color, amount: int, lifetime: float, role: StringName) -> EffectDef:
	var d := _particles(name, color, amount, lifetime, role)
	d.kind = EffectDef.Kind.TRAIL
	d.shape = EffectDef.Shape.TRAIL
	d.spread = 12.0
	d.priority = PRIORITY_ATTACK
	return d


## 复合特效声明：主层仍是 _defs[id] 的普通 EffectDef，这里登记「附加层」。
## 层字典键：
## - id      附加层特效 id（必填，light / trail 层除外）
## - offset  相对根节点的偏移（随 rot_y 旋转，米）；缺省 = 原点
## - opts    传给该层的 opts（throttle_key/throttle_time 会被剥掉，避免多层互相节流）
## - yaw     该层朝向；缺省 = 根节点朝向
## - light   true = 该层是瞬态点光（配 color / energy / duration / range）
## - trail   该层是挂在根节点上的拖尾 id（不占活动配额）
## priority 用于超预算时的取舍（命中类 0 / 出招类 1），缺省按出招类保护。
func _composite(id: StringName, name: String, layers: Array, priority: int = PRIORITY_ATTACK) -> void:
	_composites[id] = {"name": name, "layers": layers, "priority": priority}


# ============================================================================
# v33 进阶职业技能特效（契约 docs/v33_skill_design.md 第 4 节，14 个 id）
# 调用侧一律 VFXManager.spawn_effect(&"<id>", pos, rot_y, opts) / attach_trail(pawn, &"<id>")。
# ============================================================================

func _register_v33_effects() -> void:
	# ---- 通用底层：脚下尘土上扬（跳劈蓄力 / 落地砸击共用；与 build_dust 的下落方向相反）----
	var dust := _particles(&"DustRise", Color(0.82, 0.74, 0.60), 26, 0.55, &"smoke")
	dust.shape = EffectDef.Shape.AURA
	dust.radius = 0.55
	dust.speed_min = 0.9
	dust.speed_max = 2.4
	dust.gravity = Vector3(0.0, 1.8, 0.0)      # 上扬
	dust.damping = 1.7
	dust.size = 0.30
	dust.scale_min = 0.7
	dust.scale_max = 1.7
	dust.angle_jitter = 60.0
	dust.alpha_blend = true                    # 烟尘是色块体：加法混合在日光下会糊成白团
	dust.priority = PRIORITY_ATTACK
	_defs[&"dust_rise"] = dust

	# ---- ① 跳劈 leap_slam ----
	# 蓄力：脚下尘土上扬（主层）+ 红色微光（附加层）——前摇「在攒力」的读感
	var leap_charge := _particles(&"LeapCharge", Color(0.96, 0.60, 0.40), 30, 0.50, &"smoke")
	leap_charge.shape = EffectDef.Shape.AURA
	leap_charge.radius = 0.70
	leap_charge.speed_min = 1.2
	leap_charge.speed_max = 2.8
	leap_charge.gravity = Vector3(0.0, 1.6, 0.0)
	leap_charge.damping = 1.7
	leap_charge.size = 0.28
	leap_charge.scale_min = 0.7
	leap_charge.scale_max = 1.6
	leap_charge.angle_jitter = 60.0
	leap_charge.alpha_blend = true
	leap_charge.priority = PRIORITY_ATTACK
	_defs[&"leap_charge"] = leap_charge
	_composite(&"leap_charge", "LeapChargeRoot", [
		{"id": &"cast_glow", "offset": Vector3(0.0, 0.9, 0.0),
			"opts": {"color": Color(1.0, 0.30, 0.22), "lifetime": 0.50, "scale": 1.2}},
	])

	# 滞空拖尾（attach_trail 挂在施法者身上：世界坐标粒子留在空中拉出红色跃击弧）
	var leap_trail := _trail(&"LeapTrail", Color(1.0, 0.42, 0.20), 46, 0.40, &"fire")
	leap_trail.speed_min = 0.2
	leap_trail.speed_max = 0.7
	leap_trail.size = 0.34
	leap_trail.scale_min = 0.7
	leap_trail.scale_max = 1.5
	leap_trail.angle_jitter = 35.0
	leap_trail.priority = PRIORITY_ATTACK
	_defs[&"leap_trail"] = leap_trail

	# 落地砸击：尘土爆散（主层）+ 碎石火星（附加层）
	var slam_impact := _particles(&"SlamImpact", Color(0.86, 0.78, 0.62), 30, 0.60, &"smoke")
	slam_impact.shape = EffectDef.Shape.BURST
	slam_impact.speed_min = 2.0
	slam_impact.speed_max = 5.0
	slam_impact.gravity = Vector3(0.0, 1.1, 0.0)   # 砸地扬尘：先向外炸开再缓缓上浮
	slam_impact.damping = 1.8
	slam_impact.size = 0.34
	slam_impact.scale_min = 0.8
	slam_impact.scale_max = 2.0
	slam_impact.angle_jitter = 80.0
	slam_impact.alpha_blend = true
	slam_impact.priority = PRIORITY_ATTACK
	_defs[&"slam_impact"] = slam_impact
	_composite(&"slam_impact", "SlamImpactRoot", [
		{"id": &"hit_spark", "opts": {"color": Color(1.0, 0.86, 0.58), "amount": 26,
			"scale": 1.5, "lifetime": 0.45}},
	])

	# 圆形冲击波：面片直径 = AOE 直径（半径 3.4m → 6.8m），前缘正好落在判定边界
	var slam_shock := _billboard(&"SlamShockwave", Color(1.0, 0.66, 0.34), EffectDef.Kind.RING, 0.45, &"ring")
	slam_shock.ring_amount = 1.0
	slam_shock.thickness = 0.14
	slam_shock.softness = 0.50
	slam_shock.strength = 1.6
	slam_shock.scale_from = 0.50
	slam_shock.scale_to = 6.8
	slam_shock.fade_in_end = 0.06
	slam_shock.fade_out_start = 0.72
	slam_shock.no_depth_test = true
	slam_shock.priority = PRIORITY_ATTACK
	_defs[&"slam_shockwave"] = slam_shock

	# ---- ② 陨石术 meteor ----
	# 吟唱：身周上升火星（主层 AURA）+ 脚下法阵环（附加层）
	var channel := _particles(&"MeteorChannel", Color(1.0, 0.55, 0.22), 30, 0.70, &"fire")
	channel.shape = EffectDef.Shape.AURA
	channel.radius = 0.90
	channel.speed_min = 0.7
	channel.speed_max = 1.8
	channel.gravity = Vector3(0.0, 1.5, 0.0)   # 火星升腾
	channel.damping = 1.2
	channel.size = 0.22
	channel.scale_min = 0.6
	channel.scale_max = 1.4
	channel.angle_jitter = 90.0
	channel.priority = PRIORITY_ATTACK
	_defs[&"meteor_channel"] = channel
	_composite(&"meteor_channel", "MeteorChannelRoot", [
		{"id": &"blink_ring", "offset": Vector3(0.0, 0.06, 0.0),
			"opts": {"color": Color(1.0, 0.52, 0.24), "lifetime": 1.05, "scale": 1.4}},
	])

	# 落点预警圈：半径 4.2m（陨石 AOE）——面片直径 = 2×半径；需要别的半径传 opts {"radius": R}
	var telegraph := _billboard(&"MeteorTelegraph", Color(1.0, 0.44, 0.18), EffectDef.Kind.RING, 1.1, &"ring")
	telegraph.ring_amount = 1.0
	telegraph.thickness = 0.10
	telegraph.softness = 0.60
	telegraph.strength = 1.35
	telegraph.scale_from = 7.60
	telegraph.scale_to = 8.40
	telegraph.fade_in_end = 0.10
	telegraph.fade_out_start = 0.72
	telegraph.no_depth_test = true
	telegraph.priority = PRIORITY_ATTACK
	_defs[&"meteor_telegraph"] = telegraph

	# 下落火球：卡通火球本体（主层）+ 火舌拖尾（挂在根上，随根节点移动）+ 一路照亮的火光
	var fall := _billboard(&"MeteorFall", Color(1.0, 0.58, 0.18), EffectDef.Kind.GLOW, 0.90, &"flame_toon")
	fall.ring_amount = 0.0
	fall.softness = 0.85
	fall.strength = 1.4
	fall.scale_from = 2.0
	fall.scale_to = 2.5
	fall.spin_deg = 120.0
	fall.fade_in_end = 0.06
	fall.fade_out_start = 0.90
	fall.priority = PRIORITY_ATTACK
	_defs[&"meteor_fall"] = fall
	_composite(&"meteor_fall", "MeteorFallRoot", [
		{"trail": &"fire_tongue_trail"},
		{"light": true, "color": Color(1.0, 0.55, 0.20), "energy": 2.4, "duration": 0.5, "range": 9.0},
	])

	# 落地爆炸：卡通火舌团（主层）+ 白热芯 + 烟团 + 橙色冲击环 + 特效灯（分层一次出齐）
	var meteor_impact := _particles(&"MeteorImpact", Color(1.0, 0.58, 0.14), 30, 0.60, &"flame_toon")
	meteor_impact.shape = EffectDef.Shape.BURST
	meteor_impact.spread = 180.0
	meteor_impact.speed_min = 3.0
	meteor_impact.speed_max = 7.5
	meteor_impact.gravity = Vector3(0.0, 3.2, 0.0)   # 火舌向上舔
	meteor_impact.damping = 1.4
	meteor_impact.size = 0.60
	meteor_impact.scale_min = 0.7
	meteor_impact.scale_max = 1.9
	meteor_impact.angle_jitter = 180.0
	meteor_impact.alpha_blend = true
	meteor_impact.priority = PRIORITY_ATTACK
	_defs[&"meteor_impact"] = meteor_impact
	_composite(&"meteor_impact", "MeteorImpactRoot", [
		{"id": &"impact_flash", "offset": Vector3(0.0, 0.25, 0.0),
			"opts": {"lifetime": 0.30, "scale": 2.2}},
		{"id": &"toon_smoke_pop", "offset": Vector3(0.0, 0.70, 0.0),
			"opts": {"amount": 16, "scale": 2.4, "lifetime": 1.0}},
		{"id": &"hit_ring", "offset": Vector3(0.0, 0.35, 0.0),
			"opts": {"color": Color(1.0, 0.50, 0.16), "scale": 4.0, "lifetime": 0.60}},
		{"light": true, "offset": Vector3(0.0, 0.9, 0.0), "color": Color(1.0, 0.50, 0.18),
			"energy": 2.8, "duration": 0.55, "range": 10.0},
	])

	# ---- ③ 贯穿射击 piercing_shot ----
	# 枪口：比普攻十字星（0.46→0.78）大一圈的大号星芒
	var muzzle := _billboard(&"PierceMuzzle", Color(1.0, 0.92, 0.62), EffectDef.Kind.FLASH, 0.16, &"star")
	muzzle.ring_amount = 0.0
	muzzle.softness = 0.55
	muzzle.strength = 1.4
	muzzle.scale_from = 0.90
	muzzle.scale_to = 1.70
	muzzle.spin_deg = 190.0
	muzzle.fade_in_end = 0.04
	muzzle.fade_out_start = 0.42
	muzzle.no_depth_test = true
	muzzle.priority = PRIORITY_ATTACK
	_defs[&"pierce_muzzle"] = muzzle

	# 弹体尾迹（attach_trail 挂在贯穿弹体上：青白速度线长尾）
	var pierce_trail := _trail(&"PierceTrail", Color(0.72, 0.95, 1.0), 52, 0.40, &"trace")
	pierce_trail.speed_min = 0.15
	pierce_trail.speed_max = 0.55
	pierce_trail.size = 0.30
	pierce_trail.scale_min = 0.6
	pierce_trail.scale_max = 1.4
	pierce_trail.angle_jitter = 20.0
	pierce_trail.priority = PRIORITY_ATTACK
	_defs[&"pierce_trail"] = pierce_trail

	# 单点命中：小青白爆散（主层）+ 冲击环（附加层）——命中类，超预算时优先丢
	var pierce_hit := _particles(&"PierceHit", Color(0.74, 0.94, 1.0), 16, 0.34, &"spark")
	pierce_hit.shape = EffectDef.Shape.BURST
	pierce_hit.speed_min = 2.5
	pierce_hit.speed_max = 6.0
	pierce_hit.gravity = Vector3(0.0, -6.0, 0.0)
	pierce_hit.damping = 1.3
	pierce_hit.size = 0.16
	pierce_hit.scale_min = 0.5
	pierce_hit.scale_max = 1.2
	pierce_hit.priority = PRIORITY_HIT
	_defs[&"pierce_hit"] = pierce_hit
	_composite(&"pierce_hit", "PierceHitRoot", [
		{"id": &"hit_ring", "opts": {"color": Color(0.78, 0.96, 1.0),
			"scale": 1.25, "lifetime": 0.36}},
	], PRIORITY_HIT)

	# ---- ④ 隐身 stealth ----
	# 启动：冷色环（主层）+ 淡出的冷色微粒（附加层）
	var enter := _billboard(&"StealthEnter", Color(0.62, 0.92, 1.0), EffectDef.Kind.RING, 0.50, &"ring")
	enter.ring_amount = 1.0
	enter.thickness = 0.13
	enter.softness = 0.60
	enter.strength = 1.1
	enter.scale_from = 0.30
	enter.scale_to = 2.40
	enter.fade_in_end = 0.10
	enter.fade_out_start = 0.40
	enter.no_depth_test = true
	enter.priority = PRIORITY_ATTACK
	_defs[&"stealth_enter"] = enter
	_composite(&"stealth_enter", "StealthEnterRoot", [
		{"id": &"death_wisp", "opts": {"color": Color(0.58, 0.88, 1.0), "amount": 20,
			"scale": 1.15, "lifetime": 0.70}},
	])

	# 隐身期微光：TRAIL 型（attach_trail(pawn, &"stealth_shimmer") —— 稀疏冷色微粒缓缓飘散）
	var shimmer := _trail(&"StealthShimmer", Color(0.66, 0.90, 1.0), 22, 0.55, &"glow")
	shimmer.speed_min = 0.05
	shimmer.speed_max = 0.25
	shimmer.size = 0.16
	shimmer.scale_min = 0.4
	shimmer.scale_max = 0.9
	shimmer.spread = 26.0
	shimmer.angle_jitter = 25.0
	shimmer.priority = PRIORITY_ATTACK
	_defs[&"stealth_shimmer"] = shimmer

	# 破隐：冷色碎光炸散
	var break_burst := _particles(&"StealthBreak", Color(0.70, 0.92, 1.0), 28, 0.45, &"spark")
	break_burst.shape = EffectDef.Shape.BURST
	break_burst.speed_min = 3.2
	break_burst.speed_max = 7.0
	break_burst.gravity = Vector3(0.0, -3.0, 0.0)
	break_burst.damping = 1.5
	break_burst.size = 0.20
	break_burst.scale_min = 0.6
	break_burst.scale_max = 1.5
	break_burst.angle_jitter = 40.0
	break_burst.priority = PRIORITY_ATTACK
	_defs[&"stealth_break"] = break_burst


# ============================================================================
# 对外接口
# ============================================================================

## 生成特效。返回特效节点（一次性，到期自动 queue_free）；未注册 / 被节流 / 超预算返回 null。
## opts 兼容既有键：amount / lifetime；可选键：color / throttle_key / throttle_time / spin_scale /
## scale（尺寸倍率）/ radius（目标半径，米——「预警圈按 AoE 半径撑开」用）。
##
## 预算规则（EffectDef.priority）：名额已满时，**命中类（priority 0，火星 / 冲击环）直接丢弃**；
## **出招类（priority 1，刀光弧 / 枪口闪光 / 施法微光 / 技能特效）回收最旧的低优先级节点后照常生成**
## ——否则大规模夜战里「打中了没反馈」会退化成「出招了看不见」，后者更伤观感。
##
## v33 复合特效：注册在 _composites 里的 id（如 leap_charge = 尘土上扬 + 红色微光、
## meteor_impact = 分层爆散 + 冲击环 + 余烬 + 特效灯）会一次铺开多层表现，调用方接口不变；
## 返回值是复合根节点（Node3D，位于 pos，随最慢一层一起释放）。
func spawn_effect(effect_id: StringName, pos: Vector3, rot_y: float = 0.0, opts: Dictionary = {}) -> Node:
	if effect_id == &"":
		return null
	if _is_throttled(effect_id, opts):
		return null
	if _composites.has(effect_id):
		return _spawn_composite(effect_id, pos, rot_y, opts)
	return _spawn_single(effect_id, pos, rot_y, opts)


## 单层特效的生成路径（复合特效的主层与附加层也走这里；节流已在 spawn_effect 处理）。
func _spawn_single(effect_id: StringName, pos: Vector3, rot_y: float = 0.0, opts: Dictionary = {}) -> Node:
	# 优先用 .tscn 覆盖（将来美术资源；覆盖件按「出招类」保护，不被命中特效挤掉）
	var scene_path := "res://assets/vfx/%s.tscn" % String(effect_id)
	var has_scene := ResourceLoader.exists(scene_path)
	var d: EffectDef = _defs.get(effect_id, null)
	if d == null and not has_scene:
		return null
	var priority: int = PRIORITY_FALLBACK if d == null else d.priority
	if _active_effects >= MAX_ACTIVE_EFFECTS and not _recycle_for_priority(priority):
		stat_dropped_by_budget += 1
		return null
	if has_scene:
		var ps := load(scene_path) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			add_child(inst)
			if inst is Node3D:
				(inst as Node3D).global_position = pos
				(inst as Node3D).rotate_y(rot_y)
			stat_spawned_by_id[effect_id] = int(stat_spawned_by_id.get(effect_id, 0)) + 1
			_register_anim(inst as Node, d, opts, priority, effect_id)
			return inst
	if d == null:
		return null
	var node := _build_effect(effect_id, d, opts)
	if node == null:
		return null
	add_child(node)
	node.global_position = pos
	if not is_zero_approx(rot_y):
		node.rotate_y(rot_y)
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = true
	stat_spawned_by_id[effect_id] = int(stat_spawned_by_id.get(effect_id, 0)) + 1
	_register_anim(node, d, opts, priority, effect_id)
	return node


## 复合特效：主层（_defs[effect_id]）+ 附加层（其他已注册 id / 挂在根上的拖尾 / 瞬态点光）
## 一次铺开。主层照常走单层路径（含 .tscn 覆盖与预算判定），附加层各自独立计费；
## 根节点登记为「无 def 的动画条目」——只负责跟着最慢一层释放，不参与缩放 / 淡出。
func _spawn_composite(effect_id: StringName, pos: Vector3, rot_y: float, opts: Dictionary) -> Node3D:
	var c: Dictionary = _composites[effect_id]
	var root := Node3D.new()
	root.name = String(c.get("name", String(effect_id)))
	add_child(root)
	root.global_position = pos
	if not is_zero_approx(rot_y):
		root.rotate_y(rot_y)
	var max_life := 0.25
	# ① 主层：本 id 自身的 def（复合特效同样在 _defs 里注册，便于测试 / 工具的 introspection）
	var main := _spawn_single(effect_id, pos, rot_y, opts)
	if main is Node3D:
		main.reparent(root, true)
		var dm: EffectDef = _defs.get(effect_id, null)
		if dm != null:
			max_life = maxf(max_life, dm.lifetime + PARTICLE_TAIL)
	# ② 附加层
	for layer_v in (c.get("layers", []) as Array):
		var layer: Dictionary = layer_v
		var off: Vector3 = layer.get("offset", Vector3.ZERO)
		var lp := pos + off.rotated(Vector3.UP, rot_y)
		var lyaw: float = float(layer.get("yaw", rot_y))
		if bool(layer.get("light", false)):
			spawn_light(lp, layer.get("color", Color(1.0, 0.7, 0.4)),
				float(layer.get("energy", 2.0)), float(layer.get("duration", 0.4)),
				float(layer.get("range", 7.0)))
			continue
		var trail_id: StringName = layer.get("trail", &"")
		if trail_id != &"":
			attach_trail(root, trail_id)
			max_life = maxf(max_life, 1.0)
			continue
		var lid: StringName = layer.get("id", &"")
		if lid == &"":
			continue
		# 附加层不继承复合层的节流键（否则同一 key 会把多层互相节流掉）
		var lopts: Dictionary = (layer.get("opts", {}) as Dictionary).duplicate()
		lopts.erase("throttle_key")
		lopts.erase("throttle_time")
		var node := spawn_effect(lid, lp, lyaw, lopts)
		if node != null:
			var ld: EffectDef = _defs.get(lid, null)
			if ld != null:
				max_life = maxf(max_life, ld.lifetime + PARTICLE_TAIL)
	_register_anim(root, null, {"lifetime": max_life},
		int(c.get("priority", PRIORITY_ATTACK)), effect_id)
	return root


## 超预算时的回收：释放「优先级严格低于新特效」里最旧的一个活动特效（列表按生成顺序）。
## 返回 true 表示腾出了名额（调用方继续生成），false 表示只能丢弃新的。
func _recycle_for_priority(priority: int) -> bool:
	var idx := -1
	var lowest := priority            # 只回收比新特效级别更低的
	for i in _anims.size():
		var p: int = int((_anims[i] as Dictionary).get("priority", 0))
		if p < lowest:
			lowest = p
			idx = i                    # 顺序遍历 → 同级里天然取最早的那个
	if idx < 0:
		return false
	var victim_v: Variant = (_anims[idx] as Dictionary)["node"]
	if is_instance_valid(victim_v):
		var victim := victim_v as Node
		if victim != null:
			victim.queue_free()
	_active_effects = maxi(0, _active_effects - 1)
	_anims.remove_at(idx)
	return true


## 命中反馈：火星四溅（粒子）+ 冲击环（公告牌），都落在真实命中点。
## color 决定这一击的配色（金 / 土黄 / 青白 / 紫）。
## dir_yaw（v28）：可选的「攻击者 → 目标」水平朝向——传入时额外喷一束
## 定向火星锥（hit_spark_cone，从命中点向外喷）+ 一记白闪（impact_flash），
## 命中反馈从「对称爆开」升级为「有方向的打击感」。NAN = 不定向（保持旧行为）。
func spawn_hit_impact(pos: Vector3, color: Color = Color(1.0, 0.78, 0.4),
		spark_id: StringName = &"hit_spark", throttle_key: Variant = null,
		dir_yaw: float = NAN) -> void:
	var opts := {"color": color}
	if throttle_key != null:
		opts["throttle_key"] = throttle_key
		opts["throttle_time"] = 0.12
	spawn_effect(spark_id, pos, 0.0, opts)
	spawn_effect(&"hit_ring", pos, 0.0, {"color": color, "throttle_key": throttle_key, "throttle_time": 0.12})
	if not is_nan(dir_yaw):
		spawn_effect(&"hit_spark_cone", pos, dir_yaw,
			{"color": color, "throttle_key": throttle_key, "throttle_time": 0.12})
		spawn_effect(&"impact_flash", pos, 0.0,
			{"throttle_key": throttle_key, "throttle_time": 0.12})


## 瞬态点光（v30）：在 pos 处放一盏暖光，energy 从起始值抖动衰减到 0 后自毁。
## 火焰的灵魂是「照亮周围」——火球飞行 / 爆炸 / 吐息配一盏闪烁灯，效果直接上一档。
## range_m 为照射半径；flicker = 是否随机抖动（火焰的本质就是不稳定的）。
func spawn_light(pos: Vector3, color: Color, energy: float, duration: float,
		range_m: float = 7.0, flicker: bool = true) -> void:
	var light := OmniLight3D.new()
	light.name = "VfxLight"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.shadow_enabled = false          # 特效灯不开阴影（性能 + 加法特效不投影）
	add_child(light)
	light.global_position = pos
	var tw := create_tween()
	if flicker:
		var steps := maxi(int(duration / 0.06), 2)
		for i in steps:
			var k := float(i) / float(steps)
			var jitter := randf_range(0.72, 1.22)
			tw.tween_property(light, "light_energy", energy * (1.0 - k) * jitter, duration / float(steps))
	else:
		tw.tween_property(light, "light_energy", 0.0, duration)
	tw.tween_callback(light.queue_free)


## 卡通火球爆炸（v30）：分层一次出齐——卡通火舌团向上舔 + 白热芯爆点 + 烟团 +
## 橙色冲击环 + 闪烁橙光。巨龙火球落点专用（替代单层 fire_burst 的「几粒火星」读法）。
func spawn_toon_fireball_explosion(pos: Vector3) -> void:
	spawn_effect(&"fireball_burst", pos, 0.0)
	spawn_effect(&"impact_flash", pos + Vector3(0.0, 0.2, 0.0), 0.0, {"lifetime": 0.2})
	spawn_effect(&"toon_smoke_pop", pos + Vector3(0.0, 0.5, 0.0), 0.0)
	spawn_effect(&"hit_ring", pos + Vector3(0.0, 0.3, 0.0), 0.0,
		{"color": Color(1.0, 0.55, 0.18), "throttle_key": "toon_boom"})
	spawn_light(pos + Vector3(0.0, 0.8, 0.0), Color(1.0, 0.55, 0.22), 2.2, 0.42, 7.0)


## 把拖尾挂到投射物上（跟随移动节点持续发射；节点销毁即随之消失，不占活动特效配额）。
func attach_trail(parent: Node3D, effect_id: StringName) -> GPUParticles3D:
	if parent == null or not _defs.has(effect_id):
		return null
	var d: EffectDef = _defs[effect_id]
	var p := GPUParticles3D.new()
	p.name = d.node_name
	p.amount = d.amount
	p.lifetime = d.lifetime
	p.one_shot = false
	p.local_coords = false            # 世界坐标：粒子留在原地 → 拖出尾迹
	p.explosiveness = 0.0
	p.fixed_fps = 30
	p.process_material = _particle_material(effect_id, d, d.color)
	p.draw_pass_1 = _particle_mesh(effect_id, d)
	p.custom_aabb = AABB(Vector3.ONE * -TRAIL_AABB_MARGIN, Vector3.ONE * TRAIL_AABB_MARGIN * 2.0)
	p.emitting = true
	parent.add_child(p)
	return p


## 职业 → 攻击特效档案。AttackerComponent / Projectile 只读这张表，不硬编码特效 id。
## 键：arc（近战弧，空 = 无）/ arc_double / arc_dist / arc_height / cast / muzzle /
##     muzzle_dist / muzzle_height / cast_dist / cast_height / trail / impact /
##     impact_color / visual_kind / proj_tint
func attack_profile(pd: PawnDef) -> Dictionary:
	var p := {
		"arc": &"slash_arc_small", "arc_double": false, "arc_dist": 0.7, "arc_height": 1.0,
		"cast": &"", "muzzle": &"muzzle_flash", "muzzle_dist": 0.55,
		# muzzle_height 与弹体出手高度（Projectile.SOURCE_HEIGHT=1.0）对齐：闪光就出现在箭出发的位置
		"muzzle_height": 1.05,
		"cast_dist": 0.45, "cast_height": 1.25,
		"trail": &"arrow_trail", "impact": &"hit_spark", "impact_color": Color(1.0, 0.78, 0.4),
		"visual_kind": 0, "proj_tint": Color(0.88, 0.84, 0.62),
	}
	if pd == null:
		return p
	match pd.id:
		&"hero_warrior":
			p["arc"] = &"slash_arc"
			p["arc_dist"] = 0.9
			p["arc_height"] = 1.05
			p["impact_color"] = Color(1.0, 0.86, 0.45)
		&"settler_warrior":        # 双手斧：比主角小一号的土黄弧光
			p["arc"] = &"axe_arc"
			p["arc_dist"] = 0.72
			p["arc_height"] = 1.0
			p["impact_color"] = Color(0.95, 0.72, 0.34)
		&"settler_assassin":       # 双匕首：两道细弧 + 青白火花
			p["arc"] = &"dagger_arc"
			p["arc_dist"] = 0.55
			p["arc_height"] = 1.0
			p["arc_double"] = true
			p["impact_color"] = Color(0.72, 1.0, 0.9)
		&"settler_archer":         # 手弩：枪口十字星 + 白色速度线拖尾
			p["arc"] = &""
			p["impact_color"] = Color(1.0, 0.9, 0.6)
		&"settler_mage":           # 长杖：施法微光 + 紫色法术弹拖尾 + 紫色爆散
			p["arc"] = &""
			p["cast"] = &"cast_glow"
			p["muzzle"] = &""       # 法杖弹不吃「火枪口十字星」——那是枪械类特效，法术弹只留奥术微光
			p["cast_dist"] = 0.3
			p["cast_height"] = 1.5  # 微光落在举起的杖头（Spellcast_Shoot 抬臂过头）
			p["trail"] = &"magic_trail"
			p["impact"] = &"magic_burst"
			p["impact_color"] = Color(0.74, 0.5, 1.0)
			p["visual_kind"] = 1
			p["proj_tint"] = Color(0.74, 0.5, 1.0)
		&"raider", &"raider_elite", &"raider_boss":
			# 野兽拳脚（Punch / Bite_Front / Headbutt）不吃人形「剑光弧」——
			# 命中火花照常保留（打击反馈），但不再从兽爪上扫出一把光剑
			p["arc"] = &""
			p["impact_color"] = Color(1.0, 0.62, 0.42)
		_:   # v21：soldier_melee/soldier_ranged 档案已随兵营兵移除，走通用档案
			p["arc"] = &"" if pd.attack_kind == PawnDef.AttackKind.RANGED else &"slash_arc_small"
	return p


## 当前活动特效数（测试 / 性能面板用）。
func active_effect_count() -> int:
	return _active_effects


## 从文件成功加载的贴图角色数（0 = 全程序化回退）。
func file_texture_count() -> int:
	return _texture_from_file.size()


## 贴图角色清单（role -> "file"/"procedural"），调试用。
func texture_sources() -> Dictionary:
	var out: Dictionary = {}
	for role in _textures:
		out[role] = "file" if _texture_from_file.has(role) else "procedural"
	return out


## 清空诊断计数（测试用）。
func reset_stats() -> void:
	stat_spawned_by_id.clear()
	stat_dropped_by_budget = 0


# ============================================================================
# 构建（全部走共享缓存）
# ============================================================================

func _build_effect(effect_id: StringName, d: EffectDef, opts: Dictionary) -> Node3D:
	match d.kind:
		EffectDef.Kind.SLASH:
			return _build_slash(effect_id, d)
		EffectDef.Kind.RING, EffectDef.Kind.FLASH, EffectDef.Kind.GLOW:
			return _build_billboard(effect_id, d, opts)
		_:
			return _build_particles(effect_id, d, opts)


func _build_slash(effect_id: StringName, d: EffectDef) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = d.node_name
	mi.add_to_group("vfx_slash")
	if d.heavy:
		mi.add_to_group("vfx_slash_heavy")
	mi.mesh = _arc_mesh(d)
	mi.material_override = _arc_material(effect_id, d)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.scale = Vector3.ONE * d.scale_from
	return mi


func _build_billboard(effect_id: StringName, d: EffectDef, opts: Dictionary) -> MeshInstance3D:
	var color: Color = opts.get("color", d.color)
	var mi := MeshInstance3D.new()
	mi.name = d.node_name
	mi.add_to_group(_group_for_kind(d.kind))
	mi.mesh = _billboard_quad()
	mi.material_override = _billboard_material(effect_id, d, color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.scale = Vector3.ONE * d.scale_from
	return mi


func _build_particles(effect_id: StringName, d: EffectDef, opts: Dictionary) -> GPUParticles3D:
	var color: Color = opts.get("color", d.color)
	var p := GPUParticles3D.new()
	p.name = d.node_name
	p.add_to_group("vfx_particles")
	p.amount = int(opts.get("amount", d.amount))
	p.lifetime = float(opts.get("lifetime", d.lifetime))
	p.one_shot = true
	p.emitting = false
	p.local_coords = d.local_coords   # v28：定向喷射用局部坐标（旋转节点即旋转喷射方向）
	p.fixed_fps = 30
	# 命中特效高频出现时必须共享 Mesh / ProcessMaterial；每次 new 会触发新的 GPU 资源分配。
	p.process_material = _particle_material(effect_id, d, color)
	p.draw_pass_1 = _particle_mesh(effect_id, d)
	p.custom_aabb = AABB(Vector3.ONE * -PARTICLE_AABB_BOX, Vector3.ONE * PARTICLE_AABB_BOX * 2.0)
	return p


func _group_for_kind(kind: int) -> StringName:
	match kind:
		EffectDef.Kind.RING: return &"vfx_ring"
		EffectDef.Kind.FLASH: return &"vfx_flash"
		EffectDef.Kind.GLOW: return &"vfx_glow"
	return &"vfx_billboard"


# ---- 月牙弧面网格 ----

func _arc_mesh(d: EffectDef) -> ArrayMesh:
	var key := "%.0f|%.2f|%.2f" % [d.arc_deg, d.arc_width, d.arc_inner_ratio]
	if _shared_arc_meshes.has(key):
		return _shared_arc_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segs := maxi(10, int(d.arc_deg / 6.0))
	var arc := deg_to_rad(clampf(d.arc_deg, 20.0, 330.0))
	var r_out := maxf(d.arc_width, 0.1)
	var r_in := r_out * clampf(d.arc_inner_ratio, 0.05, 0.95)
	for i in segs + 1:
		var t := float(i) / float(segs)
		var a := -arc * 0.5 + arc * t
		# 逻辑前方为 -Z：0 弧度指向 -Z，正角度偏向 +X
		var dir := Vector3(sin(a), 0.0, -cos(a))
		var bow := sin(PI * t)          # 月牙弧度：中段略抬、两端收窄
		st.set_uv(Vector2(t, 0.0))
		st.add_vertex(dir * r_in * (0.94 + 0.06 * bow) + Vector3(0.0, bow * 0.05, 0.0))
		st.set_uv(Vector2(t, 1.0))
		st.add_vertex(dir * r_out + Vector3(0.0, bow * 0.16, 0.0))
	var mesh := st.commit()
	_shared_arc_meshes[key] = mesh
	return mesh


func _arc_material(effect_id: StringName, d: EffectDef) -> Material:
	var key := "arc|%s" % String(effect_id)
	if _shared_materials.has(key):
		return _shared_materials[key]
	var mat: Material = null
	if ResourceLoader.exists(ARC_SHADER_PATH):
		var sh := load(ARC_SHADER_PATH) as Shader
		if sh != null:
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("arc_color", d.color)
			sm.set_shader_parameter("alpha_boost", 1.10)
			sm.set_shader_parameter("fade_in_end", d.fade_in_end)
			sm.set_shader_parameter("fade_out_start", d.fade_out_start)
			sm.set_shader_parameter("rim_boost", 2.1 if d.heavy else 1.6)
			sm.set_shader_parameter("body_boost", 1.05 if d.heavy else 0.80)
			sm.set_shader_parameter("edge_soft", 0.30 if d.heavy else 0.36)
			sm.render_priority = 6
			mat = sm
	if mat == null:
		# 兜底（shader 缺失）：加法混合的纯色月牙
		var fb := StandardMaterial3D.new()
		fb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fb.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fb.albedo_color = d.color
		fb.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = fb
	_shared_materials[key] = mat
	return mat


# ---- 公告牌（1×1 面片 + 逐实例 progress）----

func _billboard_quad() -> QuadMesh:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2.ONE
	_quad_mesh.material = null
	return _quad_mesh


func _billboard_material(effect_id: StringName, d: EffectDef, color: Color) -> Material:
	var key := "bb|%s|%s" % [String(effect_id), color.to_html(false)]
	if _shared_materials.has(key):
		return _shared_materials[key]
	var mat: Material = null
	# v27：no_depth_test = true 的特效换用「穿透变体」shader（关闭深度测试）——
	# 人群里也看得见（此前该字段从未生效，冲击环会被前排身体整个遮住）
	var shader_path := BILLBOARD_SHADER_PATH
	if d.no_depth_test:
		shader_path = BILLBOARD_OVERLAY_SHADER_PATH
	if ResourceLoader.exists(shader_path):
		var sh := load(shader_path) as Shader
		if sh != null:
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("vfx_color", color)
			sm.set_shader_parameter("ring_amount", d.ring_amount)
			sm.set_shader_parameter("softness", d.softness)
			sm.set_shader_parameter("thickness", d.thickness)
			sm.set_shader_parameter("strength", d.strength)
			sm.set_shader_parameter("fade_in_end", d.fade_in_end)
			sm.set_shader_parameter("fade_out_start", d.fade_out_start)
			sm.set_shader_parameter("spin", deg_to_rad(d.spin_deg))   # 贴图随生命周期旋转（星芒转动感）
			sm.set_shader_parameter("vfx_texture", _texture_for_role(d.texture_role))
			sm.render_priority = 8
			mat = sm
	if mat == null:
		var fb := StandardMaterial3D.new()
		fb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fb.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fb.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fb.no_depth_test = d.no_depth_test
		fb.albedo_color = color
		fb.albedo_texture = _texture_for_role(d.texture_role)
		fb.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = fb
	_shared_materials[key] = mat
	return mat


# ---- 粒子 ----

func _particle_material(effect_id: StringName, d: EffectDef, color: Color) -> ParticleProcessMaterial:
	var key := "pm|%s|%s" % [String(effect_id), color.to_html(false)]
	if _shared_particle_materials.has(key):
		return _shared_particle_materials[key]
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.0, -1.0)
	mat.gravity = d.gravity
	mat.damping_min = d.damping
	mat.damping_max = d.damping
	mat.scale_min = d.scale_min
	mat.scale_max = d.scale_max
	mat.initial_velocity_min = d.speed_min
	mat.initial_velocity_max = d.speed_max
	match d.shape:
		EffectDef.Shape.BURST:
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			mat.emission_sphere_radius = 0.09
			mat.spread = d.spread
		EffectDef.Shape.ARC:
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			mat.direction = Vector3(0.0, 0.0, -1.0)
			mat.spread = 55.0
		EffectDef.Shape.RING, EffectDef.Shape.AURA:
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			mat.emission_sphere_radius = d.radius
			mat.spread = d.spread
		EffectDef.Shape.TRAIL:
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			mat.spread = d.spread
	# 颜色 / 透明度曲线：白热起点 → 亮起 → 保持 → 末段淡出（爆开的瞬间先白一下再回到主题色）
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 0.0))
	grad.set_color(1, Color(color.r * 0.6, color.g * 0.45, color.b * 0.35, 0.0))
	grad.add_point(0.04, Color(1.0, 1.0, 1.0).lerp(color, 0.3))   # 白热起点（v27 命中手感）
	grad.add_point(0.12, Color(color.r * 1.15, color.g * 1.1, color.b, 1.0))
	grad.add_point(0.55, color)
	# v30：粒子贴图随机翻滚角（cartoon 火舌 / 烟团的生命感来源；火星等只给轻微抖动）
	mat.angle_min = -deg_to_rad(d.angle_jitter)
	mat.angle_max = deg_to_rad(d.angle_jitter)
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	mat.color_ramp = ramp
	_shared_particle_materials[key] = mat
	return mat


func _particle_mesh(effect_id: StringName, d: EffectDef) -> Mesh:
	var key := "pm|%s|%.2f" % [String(effect_id), d.size]
	if _shared_particle_meshes.has(key):
		return _shared_particle_meshes[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# v30：alpha_blend 的卡通色块体（火舌 / 烟团）走 MIX 混合——加法在明亮草地上会被
	# 「加白」成惨白一片（v29 吐息实测）；发光体（火星 / 微光 / 余烬）保持加法。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if d.alpha_blend else BaseMaterial3D.BLEND_MODE_ADD
	# v30：BILLBOARD_PARTICLES 让每颗粒子吃 process material 的 angle 参数——
	# 卡通火舌 / 烟团按各自随机角翻滚（BILLBOARD_ENABLED 是死板正对）。
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true      # 粒子颜色由 ParticleProcessMaterial 提供
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	var tex := _texture_for_role(d.texture_role)
	if tex != null:
		mat.albedo_texture = tex
		if d.alpha_blend:
			mat.emission_enabled = false       # alpha 色块体不发光（保持卡通色块的本色）
		else:
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_energy_multiplier = 1.4
			mat.emission_texture = tex
	var mesh := QuadMesh.new()
	mesh.size = Vector2(maxf(d.size, 0.02), maxf(d.size, 0.02))
	mesh.material = mat
	_shared_particle_meshes[key] = mesh
	return mesh


# ============================================================================
# 贴图：assets/vfx/textures/ 按关键词匹配，缺失走程序化生成
# ============================================================================

const TEX_ROLES: Array[StringName] = [&"star", &"ring", &"magic", &"muzzle", &"smoke", &"fire", &"flame", &"flame_toon", &"puff_toon", &"spark", &"trace", &"glow"]
const TEX_KEYWORDS := {
	&"star": ["star", "cross", "flare", "sparkle"],
	&"ring": ["ring", "shock", "wave", "circle", "halo"],
	&"smoke": ["smoke", "cloud", "fog", "dust", "puff"],
	# v29：`flame` 角色按文件名排序会命中 flame_03（**暗色**烟状火焰贴图）——加法混合下
	# 几乎不可见（巨龙火球拖尾 / 爆炎、吐息火舌全都被它拖成灰雾）。新增 `fire` 角色先一步
	# 认领最亮的火焰贴图（flame_05），`flame` 保持旧语义（想要暗色烟焰的调用方不受影响）。
	&"fire": ["fire", "flame_05", "flame05"],
	&"flame": ["flame", "fire", "burn", "ember"],
	# v30：卡通火焰贴图（tools/make_toon_fire_textures.gd 生成，toon_* 文件名不会被
	# fire/flame 角色抢先认领）——巨龙火球尾焰 / 爆炸 / 吐息火舌的专属 cel 火舌。
	&"flame_toon": ["toon_flame"],
	&"puff_toon": ["toon_puff"],
	&"spark": ["spark", "light", "dot", "particle", "star"],
	&"glow": ["glow", "light", "circle", "dot", "particle", "scorch"],
	&"trace": ["trace", "streak", "line", "speed"],
	&"magic": ["magic", "rune", "arcane", "twirl"],
	&"muzzle": ["muzzle", "flash"],
}


func _load_textures() -> void:
	var files := _scan_texture_files()
	var used: Array[String] = []
	for role in TEX_ROLES:
		var tex := _find_texture(files, used, TEX_KEYWORDS[role])
		if tex != null:
			_textures[role] = tex
			_texture_from_file[role] = true
	# 程序化回退：软光斑 / 十字星 / 环带（纯代码生成，零外部资源）
	if not _textures.has(&"glow"):
		_textures[&"glow"] = _make_glow_texture(64, 2.6)
	if not _textures.has(&"spark"):
		_textures[&"spark"] = _make_glow_texture(48, 3.4)
	if not _textures.has(&"star"):
		_textures[&"star"] = _make_star_texture(96, 5.0)
	if not _textures.has(&"ring"):
		_textures[&"ring"] = _make_ring_texture(128)
	# v30 卡通火焰贴图缺失时的兜底（贴图文件由 tools/make_toon_fire_textures.gd 生成入库）：
	# 火舌回退到 fire 角色亮焰、烟团回退到 smoke——效果退化但不至于空白。
	if not _textures.has(&"flame_toon"):
		_textures[&"flame_toon"] = _textures.get(&"fire", _textures.get(&"glow", null))
	if not _textures.has(&"puff_toon"):
		_textures[&"puff_toon"] = _textures.get(&"smoke", _textures.get(&"glow", null))


## 扫描 res://assets/vfx/textures/ 下的图片文件（不存在 = 空数组，走程序化回退）。
func _scan_texture_files() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(VFX_TEX_DIR):
		return out
	var dir := DirAccess.open(VFX_TEX_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var lower := f.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".webp"):
			out.append(VFX_TEX_DIR + f)
	out.sort()
	return out


func _find_texture(files: Array[String], used: Array[String], keywords: Array) -> Texture2D:
	for path in files:
		if used.has(path):
			continue
		var base := path.get_file().to_lower()
		var hit := false
		for kw in keywords:
			if base.contains(String(kw)):
				hit = true
				break
		if not hit:
			continue
		var tex := _load_texture(path)
		if tex != null:
			used.append(path)
			return tex
	return null


## 加载贴图：优先 ResourceLoader（已导入），否则直接读源文件（Lead 刚放进来的 PNG 也能用）。
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.new()
		if img.load(abs_path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _texture_for_role(role: StringName) -> Texture2D:
	if role == &"":
		return null
	return _textures.get(role, null)


## 贴图角色 → 贴图（对外只读入口）：给「手工搭建粒子层」的特效复用同一份 CC0 贴图库
## （v29 巨龙吐息的四层火舌；缺贴图时返回程序化回退软光斑）。
func texture_for_role(role: StringName) -> Texture2D:
	return _texture_for_role(role)


func _make_glow_texture(size: int, power: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			# 双层光斑：小半径高亮核心（平台期更亮）+ 大半径柔光晕，避免单一幂次衰减太「扁」
			var core := pow(clampf(1.0 - d * 1.35, 0.0, 1.0), power * 0.55)
			var halo := pow(clampf(1.0 - d, 0.0, 1.0), power) * 0.6
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(maxf(core, halo), 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_star_texture(size: int, power: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) - c, float(y) - c)
			var d := p.length() / c
			# 主十字：细长四向（枪口闪光的骨架）
			var axis: float = maxf(1.0 - absf(p.x) / (c * 0.10), 1.0 - absf(p.y) / (c * 0.10))
			var cross_a: float = pow(clampf(axis, 0.0, 1.0), 3.0) * (1.0 - d) * 1.1
			# 斜向短芒：45° 四根更短更细 → 六芒/八芒星层次
			var pd := Vector2((p.x + p.y) * 0.7071, (p.x - p.y) * 0.7071)
			var diag: float = maxf(1.0 - absf(pd.x) / (c * 0.30), 1.0 - absf(pd.y) / (c * 0.30))
			diag = pow(clampf(diag, 0.0, 1.0), 3.5) * clampf(1.2 - d, 0.0, 1.0) * 0.5
			# 白热核心：中心小圆盘过曝，闪光「炸开」的亮点
			var core := pow(clampf(1.0 - d * 1.6, 0.0, 1.0), power * 0.6)
			var halo := pow(clampf(1.0 - d, 0.0, 1.0), power) * 0.5
			var a: float = maxf(maxf(cross_a, diag), maxf(core, halo))
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_ring_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			# 双环结构：外圈亮细环（冲击波前）+ 内圈柔宽环（气浪余韵）
			var band_outer := pow(clampf(1.0 - absf(d - 0.86) / 0.10, 0.0, 1.0), 1.5)
			var band_inner := pow(clampf(1.0 - absf(d - 0.52) / 0.24, 0.0, 1.0), 1.8) * 0.38
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(band_outer + band_inner, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# ============================================================================
# 生命周期：统一由本单例推进（缩放 / 扫动 / 淡入淡出 / 自动释放）
# ============================================================================

func _register_anim(node: Node, d: EffectDef, opts: Dictionary, priority: int = -1,
		effect_id: StringName = &"") -> void:
	if node == null:
		return
	var life := float(opts.get("lifetime", 1.0 if d == null else d.lifetime))
	if d != null and (d.kind == EffectDef.Kind.PARTICLES or d.kind == EffectDef.Kind.TRAIL):
		life += PARTICLE_TAIL
	var kind: int = EffectDef.Kind.PARTICLES if d == null else d.kind
	var prio: int = priority
	if prio < 0:
		prio = PRIORITY_FALLBACK if d == null else d.priority
	# v33：尺寸覆盖（网格类特效专用）——
	# - opts.scale  ：倍率，直接乘在 def 的缩放曲线上；
	# - opts.radius ：目标半径（米），按「1×1 面片半宽 = scale/2」换算成缩放（预警圈撑到 AoE 半径用）。
	var s_from: float = 0.0 if d == null else d.scale_from
	var s_to: float = 1.0 if d == null else d.scale_to
	if d != null and opts.has("radius") and d.scale_to > 0.001 and kind != EffectDef.Kind.PARTICLES:
		var r := maxf(float(opts["radius"]), 0.02)
		var k_r := (r * 2.0) / d.scale_to
		s_from *= k_r
		s_to = r * 2.0
	elif d != null and opts.has("scale") and kind != EffectDef.Kind.PARTICLES:
		var k_s := maxf(float(opts["scale"]), 0.02)
		s_from *= k_s
		s_to *= k_s
	if node is Node3D and (s_from != (0.0 if d == null else d.scale_from)):
		(node as Node3D).scale = Vector3.ONE * s_from
	var entry := {
		"node": node,
		"id": effect_id,
		"priority": prio,
		"t": 0.0,
		"life": maxf(life, 0.05),
		"kind": kind,
		"scale_from": s_from,
		"scale_to": s_to,
		"spin": 0.0 if d == null else d.spin_deg * float(opts.get("spin_scale", 1.0)),
		"rot0": (node as Node3D).rotation.y if node is Node3D else 0.0,
		"rise": 0.0 if d == null else d.rise,
		"fade_in": 0.16 if d == null else d.fade_in_end,
		"fade_out": 0.46 if d == null else d.fade_out_start,
		"pos0": (node as Node3D).global_position if node is Node3D else Vector3.ZERO,
	}
	_anims.append(entry)
	_active_effects += 1


func _process(delta: float) -> void:
	if _anims.is_empty():
		return
	var hold: float = debug_anim_progress
	var alive: Array = []
	for entry in _anims:
		var e: Dictionary = entry
		# 已释放实例赋给类型化变量会先抛错（AGENTS 已知坑）：先无类型接引用 → 校验 → 再转型。
		# 复合特效的根节点释放时会连带释放已登记的层节点，这里必须能容忍「条目还在、节点已走」。
		var node_v: Variant = e["node"]
		if not is_instance_valid(node_v):
			_active_effects = maxi(0, _active_effects - 1)
			continue
		var node := node_v as Node
		if hold < 0.0:
			e["t"] = float(e["t"]) + delta
			if float(e["t"]) >= float(e["life"]):
				_active_effects = maxi(0, _active_effects - 1)
				node.queue_free()
				continue
		_apply_anim(e, hold)
		alive.append(e)
	_anims = alive


func _apply_anim(e: Dictionary, hold: float) -> void:
	var node_v: Variant = e["node"]
	if not is_instance_valid(node_v):
		return
	var node := node_v as Node3D
	if node == null:
		return
	var p: float = clampf(float(e["t"]) / float(e["life"]), 0.0, 1.0)
	if hold >= 0.0:
		p = clampf(hold, 0.0, 1.0)
	var kind: int = e["kind"]
	if kind == EffectDef.Kind.PARTICLES:
		return                      # 粒子自身随时间演化，节点只负责按期释放
	# 尺寸：起手小 → 张开（用缓出曲线，前段变化快，像「甩出去」）
	var ease_out := 1.0 - pow(1.0 - p, 2.2)
	var s: float = lerpf(float(e["scale_from"]), float(e["scale_to"]), ease_out)
	# v33：预警圈微脉动（+5.5%，2.5 个周期）——读作「倒计时仍在走」
	if PULSE_IDS.has(StringName(e.get("id", &""))):
		s *= 1.0 + 0.055 * sin(p * TAU * 2.5)
	node.scale = Vector3.ONE * s
	if float(e["spin"]) != 0.0:
		node.rotation.y = float(e["rot0"]) + deg_to_rad(float(e["spin"])) * (p - 0.5)
	if float(e["rise"]) != 0.0:
		var rise := float(e["rise"])
		node.global_position = (e["pos0"] as Vector3) + Vector3.UP * (rise * p)
	# 淡入淡出：shader 内 progress 为逐实例 uniform；同时用实例透明度兜底
	var gi := node as GeometryInstance3D
	if gi == null:
		return
	gi.set_instance_shader_parameter("progress", p)
	var a: float = clampf(p / maxf(float(e["fade_in"]), 0.001), 0.0, 1.0)
	a *= 1.0 - smoothstep(float(e["fade_out"]), 1.0, p)
	gi.transparency = clampf(1.0 - a, 0.0, 1.0)


# ============================================================================
# 节流：同一单位 0.1s 内不重复生成同种特效
# ============================================================================

func _is_throttled(effect_id: StringName, opts: Dictionary) -> bool:
	var key: Variant = opts.get("throttle_key", null)
	if key == null:
		return false
	var now := Time.get_ticks_msec()
	var full := "%s|%s" % [str(key), String(effect_id)]
	if now < int(_throttle_until.get(full, 0)):
		return true
	_throttle_until[full] = now + int(maxf(float(opts.get("throttle_time", THROTTLE_DEFAULT)), 0.0) * 1000.0)
	return false
