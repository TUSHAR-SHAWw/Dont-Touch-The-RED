extends Node

## Central audio hub. Assign any AudioStream assets to the exported slots in the inspector.
##
## Music plays on a "Music" bus and every sound effect on an "SFX" bus (both are
## created automatically if the project doesn't define them). Volume sliders and
## mute toggles act on the buses, so they also affect sounds that are already playing.
## Sound effects use a small pool of voices, so rapid sounds overlap instead of cutting
## each other off.

## Matches the `kind` ints passed to play_powerup().
enum PowerupKind { SHIELD, SCORE_BOOST, MAGNET }

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

const SILENT_DB := -40.0
const FADE_OUT_TIME := 0.22
const FADE_IN_TIME := 0.28

const VOICE_COUNT := 12
## Ignore the same sound being triggered again within this many ms (stops double-hits).
const MIN_RETRIGGER_MSEC := 30

const RARE_COIN_VALUE := 3
const EPIC_COIN_VALUE := 8

## Per-sound loudness trims (dB, relative to the SFX bus). Prefer normalising the
## audio files themselves; these are here to match the old balance.
const WARNING_BOOST_DB := 18.0
const DEATH_BOOST_DB := 12.0

@export_group("Music")
@export var bg_music_stream: AudioStream
@export var gameplay_music_stream: AudioStream
@export_range(-40.0, 6.0, 0.5) var music_volume_db := -12.0

@export_group("SFX")
@export var ui_stream: AudioStream
@export var warning_stream: AudioStream
@export var danger_stream: AudioStream
@export var death_stream: AudioStream
@export var coin_stream: AudioStream
@export var rare_coin_stream: AudioStream
@export var epic_coin_stream: AudioStream
@export var powerup_stream: AudioStream
@export var shield_stream: AudioStream
@export var score_boost_stream: AudioStream
@export var magnet_stream: AudioStream
@export_range(-40.0, 6.0, 0.5) var sfx_volume_db := -6.0

var music_enabled := true
var sfx_enabled := true

var _music_tween: Tween
## The track the game last asked for, even if music was muted at the time.
var _requested_music: AudioStream
var _music_bus_idx := -1
var _sfx_bus_idx := -1
var _voices: Array[AudioStreamPlayer] = []
var _steal_index := 0
var _last_play_msec := {}

@onready var music_player: AudioStreamPlayer = $MusicPlayer


func _ready() -> void:
	# Keep fading and playing while the tree is paused (pause menu, etc.).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_bus_idx = _ensure_bus(MUSIC_BUS)
	_sfx_bus_idx = _ensure_bus(SFX_BUS)
	_apply_bus_volumes()

	# The bus carries the user's music volume; the player volume is only used for fades.
	music_player.bus = MUSIC_BUS
	music_player.volume_db = 0.0

	for i in range(VOICE_COUNT):
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)

	_enable_loop(bg_music_stream)
	_enable_loop(gameplay_music_stream)
	play_background_music()


# ---------------------------------------------------------------------------
# Buses / volume
# ---------------------------------------------------------------------------

func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _apply_bus_volumes() -> void:
	if _music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_music_bus_idx, music_volume_db)
	if _sfx_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus_idx, sfx_volume_db)
		# The slider's lowest value means silent, not just very quiet.
		AudioServer.set_bus_mute(_sfx_bus_idx, not sfx_enabled or sfx_volume_db <= SILENT_DB + 0.5)


## For a settings slider.
func set_music_volume_db(db: float) -> void:
	music_volume_db = db
	_apply_bus_volumes()


## For a settings slider.
func set_sfx_volume_db(db: float) -> void:
	sfx_volume_db = db
	_apply_bus_volumes()


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	# WAV loops are best set in the import settings.


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

func play_background_music() -> void:
	_play_music(bg_music_stream)


func play_gameplay_music() -> void:
	_play_music(gameplay_music_stream)


func _play_music(stream: AudioStream) -> void:
	if not stream:
		return
	# Remember the request even while muted, so unmuting plays the right track.
	_requested_music = stream
	if not music_enabled:
		return

	if music_player.stream == stream:
		# Already the current track: cancel any fade towards another one and bring it back.
		_kill_music_tween()
		music_player.stream_paused = false
		if not music_player.playing:
			music_player.volume_db = 0.0
			music_player.play()
		elif music_player.volume_db < -0.1:
			_music_tween = _new_music_tween()
			_music_tween.tween_property(music_player, "volume_db", 0.0, FADE_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return

	_kill_music_tween()
	_music_tween = _new_music_tween()
	if music_player.playing:
		_music_tween.tween_property(music_player, "volume_db", SILENT_DB, FADE_OUT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_music_tween.tween_callback(_swap_music.bind(stream))
	_music_tween.tween_property(music_player, "volume_db", 0.0, FADE_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _swap_music(stream: AudioStream) -> void:
	music_player.stream = stream
	music_player.volume_db = SILENT_DB
	music_player.stream_paused = false
	music_player.play()


func _new_music_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _kill_music_tween() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()


func pause_background_music() -> void:
	if music_player.stream == bg_music_stream and music_player.playing:
		music_player.stream_paused = true


func resume_background_music() -> void:
	if music_player.stream == bg_music_stream and music_player.stream_paused:
		music_player.stream_paused = false


func pause_gameplay_music() -> void:
	if music_player.stream == gameplay_music_stream and music_player.playing:
		music_player.stream_paused = true


func resume_gameplay_music() -> void:
	if music_player.stream == gameplay_music_stream and music_player.stream_paused:
		music_player.stream_paused = false


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if enabled:
		# Restore the last requested track, at full fade level.
		music_player.volume_db = 0.0
		_play_music(_requested_music)
	else:
		_kill_music_tween()
		music_player.stop()
		music_player.volume_db = 0.0


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	# Muting the bus also silences sounds that are already playing.
	_apply_bus_volumes()


func play_ui() -> void:
	_play(ui_stream)


func play_warning() -> void:
	_play(warning_stream, WARNING_BOOST_DB)


func play_danger() -> void:
	_play(danger_stream)


func play_death() -> void:
	_play(death_stream, DEATH_BOOST_DB)


func play_coin(value: int, pitch := 1.0) -> void:
	var stream := coin_stream
	if value >= EPIC_COIN_VALUE and epic_coin_stream:
		stream = epic_coin_stream
	elif value >= RARE_COIN_VALUE and rare_coin_stream:
		stream = rare_coin_stream
	_play(stream, 0.0, pitch)


func play_powerup(kind: int) -> void:
	var stream := powerup_stream
	if kind == PowerupKind.SHIELD and shield_stream:
		stream = shield_stream
	elif kind == PowerupKind.SCORE_BOOST and score_boost_stream:
		stream = score_boost_stream
	elif kind == PowerupKind.MAGNET and magnet_stream:
		stream = magnet_stream
	_play(stream)


## Bright pickup sound for gems (reuses the epic coin sample, pitched up).
func play_gem() -> void:
	_play(epic_coin_stream if epic_coin_stream else coin_stream, 0.0, 1.35)


func play_revive() -> void:
	_play(score_boost_stream if score_boost_stream else powerup_stream)


func play_purchase() -> void:
	_play(rare_coin_stream if rare_coin_stream else coin_stream, 0.0, 0.9)


func play_error() -> void:
	_play(ui_stream, 0.0, 0.6)


func play_sfx(stream: AudioStream, boost_db := 0.0) -> void:
	_play(stream, boost_db)


func _play(stream: AudioStream, boost_db := 0.0, pitch := 1.0) -> void:
	if not stream or not sfx_enabled:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play_msec.get(stream, -1000)) < MIN_RETRIGGER_MSEC:
		return
	_last_play_msec[stream] = now

	var voice := _free_voice()
	voice.stream = stream
	voice.volume_db = boost_db
	voice.pitch_scale = pitch
	voice.play()


## First idle voice, or the next one in round-robin order if all are busy.
func _free_voice() -> AudioStreamPlayer:
	for voice in _voices:
		if not voice.playing:
			return voice
	var stolen := _voices[_steal_index]
	_steal_index = (_steal_index + 1) % _voices.size()
	return stolen
