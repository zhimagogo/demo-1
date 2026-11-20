extends Node
## ============================================================================
## AudioManager —— 音效播放单例（autoload）。
## 接口齐全；当前仓库无音频资产，缺资源时静默 no-op。
## 后续把 ogg/wav/mp3 放到 res://assets/audio/<sfx_id>.<ext> 即自动激活，调用方无需改动。
## ============================================================================

const POOL_SIZE: int = 12
const AUDIO_DIR: String = "res://assets/audio/"

var _streams: Dictionary = {}            # StringName -> AudioStream（含 null 表示已查过不存在）
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _idx_2d: int = 0
var _idx_3d: int = 0

# ---- 循环环境声（v3）：雨 / 蟋蟀 / 鸟鸣。专用播放器 + 音量渐变 ----
var _loop_players: Dictionary = {}       # StringName -> AudioStreamPlayer
var _loop_targets: Dictionary = {}       # StringName -> 目标音量（渐变终点）


func _ready() -> void:
	for i in POOL_SIZE:
		var p2 := AudioStreamPlayer.new()
		p2.name = "Audio2D_%d" % i
		add_child(p2)
		_players_2d.append(p2)
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "Audio3D_%d" % i
		p3.max_distance = 40.0
		add_child(p3)
		_players_3d.append(p3)


func _process(delta: float) -> void:
	# 循环声音量渐变（起播淡入 / 停止淡出）
	for id in _loop_targets.keys():
		var player: AudioStreamPlayer = _loop_players.get(id)
		if player == null or not is_instance_valid(player):
			continue
		var target: float = _loop_targets[id]
		var cur: float = player.volume_db
		var target_db := linear_to_db(clampf(target, 0.0001, 1.0))
		var next_db := lerpf(cur, target_db, delta * 2.0)
		player.volume_db = next_db
		if target <= 0.0 and db_to_linear(next_db) < 0.004:
			player.stop()
			_loop_targets.erase(id)


## 播放音效。pos 非 INF 时按 3D 定位，否则非空间。缺资源 / 空 id 静默。
func play_sfx(sfx_id: StringName, pos: Vector3 = Vector3.INF) -> void:
	if sfx_id == &"":
		return
	var stream := _get_stream(sfx_id)
	if stream == null:
		return
	if pos == Vector3.INF:
		var p: AudioStreamPlayer = _players_2d[_idx_2d]
		_idx_2d = (_idx_2d + 1) % POOL_SIZE
		p.stream = stream
		p.play()
	else:
		var p3: AudioStreamPlayer3D = _players_3d[_idx_3d]
		_idx_3d = (_idx_3d + 1) % POOL_SIZE
		p3.stream = stream
		p3.global_position = pos
		p3.play()


## 预加载（可选）：启动时显式登记 id→stream 映射。
func register(sfx_id: StringName, stream: AudioStream) -> void:
	if stream != null:
		_streams[sfx_id] = stream


## 播放循环环境声（雨 / 蟋蟀 / 鸟鸣）。同 id 重复调用只调目标音量；volume 0 = 淡出停止。
func play_loop(sfx_id: StringName, volume: float = 0.6) -> void:
	var player: AudioStreamPlayer = _loop_players.get(sfx_id)
	if player == null or not is_instance_valid(player):
		var stream := _get_stream(sfx_id)
		if stream == null:
			return
		player = AudioStreamPlayer.new()
		player.name = "Loop_%s" % String(sfx_id)
		player.stream = stream
		player.volume_db = linear_to_db(0.0001)
		add_child(player)
		player.play()
		_loop_players[sfx_id] = player
	_loop_targets[sfx_id] = clampf(volume, 0.0, 1.0)


## 停止某个循环声（淡出后自动 stop）。
func stop_loop(sfx_id: StringName) -> void:
	if _loop_players.has(sfx_id):
		_loop_targets[sfx_id] = 0.0


func _get_stream(sfx_id: StringName) -> AudioStream:
	if _streams.has(sfx_id):
		return _streams[sfx_id]
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = AUDIO_DIR + String(sfx_id) + ext
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			if s != null:
				_streams[sfx_id] = s
				return s
	_streams[sfx_id] = null   # 标记已查、不存在，避免反复查盘
	return null
