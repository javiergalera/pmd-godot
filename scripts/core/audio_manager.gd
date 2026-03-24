extends Node
## Global audio manager (autoload).
##
## Manages background music and sound effects through AudioStreamPlayer nodes.
## Music crossfades automatically. SFX play on a pooled set of players
## so multiple sounds can overlap without cutting each other off.

const SFX_POOL_SIZE := 8

# ── Audio stream paths ──
const _MUSIC_DUNGEON_PATH := "res://audio/music/2d/background_music.mp3"
const _SFX_PLAYER_ATTACK_PATH := "res://audio/sfx/2d/player_attack.mp3"
const _SFX_ENEMY_ATTACK_PATH := "res://audio/sfx/2d/enemy_attack.mp3"
const _SFX_STAIRS_PATH := "res://audio/sfx/2d/stairs.mp3"

# ── 3D audio stream paths ──
const _MUSIC_DUNGEON_3D_PATH := "res://audio/music/3d/background_music.mp3"
const _SFX_PLAYER_ATTACK_3D_PATH := "res://audio/sfx/3d/player_attack.wav"
const _SFX_ENEMY_ATTACK_3D_PATH := "res://audio/sfx/3d/enemy_attack.wav"
const _SFX_STAIRS_3D_PATH := "res://audio/sfx/3d/stairs.wav"

var _music_dungeon: AudioStream
var _sfx_player_attack: AudioStream
var _sfx_enemy_attack: AudioStream
var _sfx_stairs: AudioStream

# ── 3D streams ──
var _music_dungeon_3d: AudioStream
var _sfx_player_attack_3d: AudioStream
var _sfx_enemy_attack_3d: AudioStream
var _sfx_stairs_3d: AudioStream

# ── Nodes ──
var _music_player: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0

# ── Volume (linear) ──
var music_volume: float = 0.8:
	set(v):
		music_volume = clampf(v, 0.0, 1.0)
		if _music_player:
			_music_player.volume_db = linear_to_db(music_volume)

var sfx_volume: float = 1.0:
	set(v):
		sfx_volume = clampf(v, 0.0, 1.0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_audio_streams()

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	_music_player.volume_db = linear_to_db(music_volume)
	add_child(_music_player)

	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)

	_ensure_audio_buses()

func _load_audio_streams() -> void:
	_music_dungeon = _safe_load(_MUSIC_DUNGEON_PATH)
	_sfx_player_attack = _safe_load(_SFX_PLAYER_ATTACK_PATH)
	_sfx_enemy_attack = _safe_load(_SFX_ENEMY_ATTACK_PATH)
	_sfx_stairs = _safe_load(_SFX_STAIRS_PATH)
	_music_dungeon_3d = _safe_load(_MUSIC_DUNGEON_3D_PATH)
	_sfx_player_attack_3d = _safe_load(_SFX_PLAYER_ATTACK_3D_PATH)
	_sfx_enemy_attack_3d = _safe_load(_SFX_ENEMY_ATTACK_3D_PATH)
	_sfx_stairs_3d = _safe_load(_SFX_STAIRS_3D_PATH)

func _safe_load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("AudioManager: missing audio file: %s" % path)
		return null
	return load(path)

func _is_3d_mode() -> bool:
	var settings = get_node_or_null("/root/GameSettings")
	return settings != null and settings.use_3d

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  MUSIC
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func play_music(stream: AudioStream, fade_in: float = 1.0) -> void:
	if _music_player.stream == stream and _music_player.playing:
		return
	if _music_player.playing and fade_in > 0.0:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -40.0, fade_in * 0.5)
		await tw.finished
	_music_player.stream = stream
	_music_player.volume_db = -40.0
	_music_player.play()
	var tw2 := create_tween()
	tw2.tween_property(_music_player, "volume_db", linear_to_db(music_volume), fade_in * 0.5)

func stop_music(fade_out: float = 1.0) -> void:
	if not _music_player.playing:
		return
	if fade_out <= 0.0:
		_music_player.stop()
		return
	var tw := create_tween()
	tw.tween_property(_music_player, "volume_db", -40.0, fade_out)
	await tw.finished
	_music_player.stop()

func play_dungeon_music() -> void:
	if _is_3d_mode():
		play_music(_music_dungeon_3d)
	else:
		play_music(_music_dungeon)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  SFX
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func play_sfx(stream: AudioStream, volume_linear: float = -1.0) -> void:
	if stream == null:
		return
	var player := _sfx_pool[_sfx_index]
	_sfx_index = (_sfx_index + 1) % SFX_POOL_SIZE
	player.stream = stream
	var vol := sfx_volume if volume_linear < 0.0 else volume_linear
	player.volume_db = linear_to_db(vol)
	player.play()

func play_player_attack() -> void:
	if _is_3d_mode():
		play_sfx(_sfx_player_attack_3d)
	else:
		play_sfx(_sfx_player_attack)

func play_enemy_attack() -> void:
	if _is_3d_mode():
		play_sfx(_sfx_enemy_attack_3d)
	else:
		play_sfx(_sfx_enemy_attack)

func play_stairs() -> void:
	if _is_3d_mode():
		play_sfx(_sfx_stairs_3d)
	else:
		play_sfx(_sfx_stairs)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  AUDIO BUS SETUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index(&"Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"Music")
		AudioServer.set_bus_send(idx, &"Master")
	if AudioServer.get_bus_index(&"SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"SFX")
		AudioServer.set_bus_send(idx, &"Master")
