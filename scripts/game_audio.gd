extends Node

const CLICK := preload("res://music/Click.mp3")
const PLACE := preload("res://music/Place.ogg")
const VICTORY := preload("res://music/Victory.ogg")
const BACKGROUND_MUSIC := [preload("res://music/bg1.mp3"), preload("res://music/bg2.mp3")]
const MAX_TILE_VOICES := 32
const SETTINGS_PATH := "user://settings.cfg"
const MUSIC_BASE_VOLUME := 0.25
const CLICK_BASE_VOLUME := 0.0625
const PLACE_BASE_VOLUME := 0.5
const MUSIC_FADE_DURATION := 0.2

var rng := RandomNumberGenerator.new()
var tile_players: Array[AudioStreamPlayer] = []
var next_voice := 0
var victory_player: AudioStreamPlayer
var music_player: AudioStreamPlayer
var music_index := 0
var music_volume := 0.5
var sfx_volume := 0.5
var music_gain := 0.0
var music_active := false
var music_fade: Tween

func _ready() -> void:
	rng.randomize()
	_ensure_bus("Music")
	_ensure_bus("SFX")
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		music_volume = _stored_volume(settings, "music_volume")
		sfx_volume = _stored_volume(settings, "sfx_volume")
	_apply_volume("Music", music_volume)
	_apply_volume("SFX", sfx_volume)
	victory_player = AudioStreamPlayer.new()
	victory_player.stream = VICTORY
	victory_player.bus = "SFX"
	add_child(victory_player)
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_linear = 0.0
	music_player.finished.connect(_advance_music)
	add_child(music_player)
	_play_music()

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		# Growing the bus count avoids add_bus(-1) misrouting Web sample audio.
		AudioServer.bus_count += 1
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

func _stored_volume(settings: ConfigFile, key: String) -> float:
	var value: Variant = settings.get_value("audio", key, 0.5)
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return 0.5

func _apply_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume("Music", music_volume)
	_save_settings()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume("SFX", sfx_volume)
	_save_settings()

func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "music_volume", music_volume)
	settings.set_value("audio", "sfx_volume", sfx_volume)
	settings.save(SETTINGS_PATH)

func _play_music() -> void:
	music_player.stream = BACKGROUND_MUSIC[music_index]
	music_player.play()

func _advance_music() -> void:
	music_index = (music_index + 1) % BACKGROUND_MUSIC.size()
	_play_music()

func set_music_active(active: bool) -> void:
	if music_active == active:
		return
	music_active = active
	if music_fade:
		music_fade.kill()
	music_fade = create_tween()
	music_fade.tween_method(_set_music_gain, music_gain, 1.0 if active else 0.0, MUSIC_FADE_DURATION)

func _set_music_gain(value: float) -> void:
	music_gain = value
	music_player.volume_linear = MUSIC_BASE_VOLUME * music_gain

func play_click(_cell: int) -> void:
	_play_tile(CLICK)

func play_place(_cell: int) -> void:
	_play_tile(PLACE)

func _play_tile(stream: AudioStream) -> void:
	var player: AudioStreamPlayer
	for voice in tile_players:
		if not voice.playing:
			player = voice
			break
	if player == null:
		if tile_players.size() < MAX_TILE_VOICES:
			player = AudioStreamPlayer.new()
			player.bus = "SFX"
			add_child(player)
			tile_players.append(player)
		else:
			player = tile_players[next_voice]
			next_voice = (next_voice + 1) % MAX_TILE_VOICES
	# Separate voices preserve each tile's pitch while rapid steps overlap.
	player.stop()
	player.stream = stream
	player.volume_linear = CLICK_BASE_VOLUME if stream == CLICK else PLACE_BASE_VOLUME
	player.pitch_scale = rng.randf_range(0.8, 1.2)
	player.play()

func play_victory() -> void:
	victory_player.play()
