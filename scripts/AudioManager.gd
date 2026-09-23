extends Node

## Central audio hub. Assign any AudioStream assets to the exported slots in the inspector.

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

@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var ui_player: AudioStreamPlayer = $UIPlayer
@onready var warning_player: AudioStreamPlayer = $WarningPlayer
@onready var danger_player: AudioStreamPlayer = $DangerPlayer
@onready var death_player: AudioStreamPlayer = $DeathPlayer
@onready var coin_player: AudioStreamPlayer = $CoinPlayer
@onready var powerup_player: AudioStreamPlayer = $PowerupPlayer

func _ready() -> void:
	music_player.volume_db = music_volume_db
	ui_player.volume_db = sfx_volume_db
	warning_player.volume_db = sfx_volume_db + 30
	danger_player.volume_db = sfx_volume_db
	death_player.volume_db = sfx_volume_db + 20
	coin_player.volume_db = sfx_volume_db
	powerup_player.volume_db = sfx_volume_db
	
	play_background_music()

func play_background_music() -> void:
	if bg_music_stream is AudioStreamMP3:
		bg_music_stream.loop = true
	_play_music(bg_music_stream)


func play_gameplay_music() -> void:
	if gameplay_music_stream is AudioStreamMP3:
		gameplay_music_stream.loop = true
	_play_music(gameplay_music_stream)

func _play_music(stream: AudioStream) -> void:
	if not music_enabled or not stream:
		return
	if music_player.stream == stream:
		music_player.stream_paused = false
		if not music_player.playing:
			music_player.play()
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(music_player, "volume_db", -40.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_music_tween.tween_callback(func() -> void:
		music_player.stream = stream
		music_player.stream_paused = false
		music_player.play()
	)
	_music_tween.tween_property(music_player, "volume_db", music_volume_db, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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

func play_ui() -> void:
	_play(ui_player, ui_stream)

func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if music_enabled:
		if music_player.stream and not music_player.playing:
			music_player.play()
	else:
		if _music_tween and _music_tween.is_valid():
			_music_tween.kill()
		music_player.stop()

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled

func play_warning() -> void:
	_play(warning_player, warning_stream)

func play_danger() -> void:
	_play(danger_player, danger_stream)

func play_death() -> void:
	_play(death_player, death_stream)

func play_coin(value: int) -> void:
	var stream := coin_stream
	if value >= 8 and epic_coin_stream:
		stream = epic_coin_stream
	elif value >= 3 and rare_coin_stream:
		stream = rare_coin_stream
	_play(coin_player, stream)

func play_powerup(kind: int) -> void:
	var stream := powerup_stream
	if kind == 0 and shield_stream:
		stream = shield_stream
	elif kind == 1 and score_boost_stream:
		stream = score_boost_stream
	elif kind == 2 and magnet_stream:
		stream = magnet_stream
	_play(powerup_player, stream)

func play_sfx(stream: AudioStream) -> void:
	_play(powerup_player, stream)

func _play(player: AudioStreamPlayer, stream: AudioStream) -> void:
	if not stream or not sfx_enabled:
		return
	player.stream = stream
	player.play()
