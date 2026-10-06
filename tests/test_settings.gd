extends SceneTree

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")
	create_timer(20.0).timeout.connect(func():
		push_error("Settings test timed out")
		quit(1)
	)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-user/" + filename + ".png")

func settle_transition(main: Control) -> void:
	while is_instance_valid(main.get("screen_transition")):
		await process_frame

func run() -> void:
	# Like the progress tests, run with isolated user data (see README).
	if FileAccess.file_exists("user://settings.cfg"):
		DirAccess.remove_absolute("user://settings.cfg")
	var main = load("res://main.tscn").instantiate()
	main.store.mirror_project = false
	main.store.completed = {"1": true}
	main.store.credits = 123
	root.add_child(main)
	main.show_menu()
	await process_frame
	await process_frame
	var audio = main.game_audio
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	check(audio.music_volume == 0.5 and audio.sfx_volume == 0.5, "Both volumes default to 50 percent")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 0.5) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx_bus)), 0.5), "Music and SFX buses start at half volume")
	check(audio.music_player.playing and audio.music_player.stream == audio.BACKGROUND_MUSIC[0], "Background music starts with bg1")
	check(audio.music_player.volume_linear == 0.0, "The initial main menu is silent while the playlist keeps playing")
	for expected_index in [1, 0, 1, 0]:
		if DisplayServer.get_name() == "headless":
			# The headless Dummy audio driver does not decode tracks to their end.
			audio.music_player.stop()
			audio.music_player.finished.emit()
		else:
			audio.music_player.seek(audio.music_player.stream.get_length() - 0.03)
			await create_timer(0.3).timeout
		check(audio.music_index == expected_index and audio.music_player.stream == audio.BACKGROUND_MUSIC[expected_index] and audio.music_player.playing, "Track completion alternates background music to track %d" % (expected_index + 1))
	check(main.settings_button.icon == main.CogIcon and main.settings_button.get_global_rect().end.x <= main.size.x - 43 and main.credit_display.get_global_rect().end.x < main.settings_button.get_global_rect().position.x, "The vector cog sits at the top right with credits to its left")
	check(main.content.find_children("", "Button", true, false).all(func(node): return node.text != "Delete Progress"), "Progress deletion is absent from the main menu")
	main.settings_button.pressed.emit()
	await process_frame
	await process_frame
	var music_slider: HSlider = main.settings_layer.find_child("MusicVolume", true, false)
	var sfx_slider: HSlider = main.settings_layer.find_child("SfxVolume", true, false)
	check(music_slider.value == 50 and sfx_slider.value == 50, "Both settings sliders initially show 50 percent")
	check(main.settings_layer.find_children("", "Button", true, false).any(func(node): return node.text == "Delete Progress"), "Settings contains the red progress deletion button")
	var delete_button: Button = main.settings_layer.find_children("", "Button", true, false).filter(func(node): return node.text == "Delete Progress")[0]
	var footer: HBoxContainer = delete_button.get_parent()
	check(delete_button.size.x < footer.size.x * 0.4 and delete_button.size.y <= 36 and is_equal_approx(delete_button.get_global_rect().position.x, footer.get_global_rect().position.x) and is_equal_approx(delete_button.get_global_rect().end.y, footer.get_global_rect().end.y), "The small delete button stays at the bottom left of the settings footer")
	await capture("settings-menu")
	audio.play_click(0)
	audio.play_place(1)
	check(audio.tile_players[0].bus == "SFX" and is_equal_approx(audio.tile_players[0].volume_linear, 0.0625) and audio.tile_players[1].bus == "SFX" and is_equal_approx(audio.tile_players[1].volume_linear, 0.5), "Click has 6.25 percent base volume and Place has half base volume")
	check(is_equal_approx(db_to_linear(audio.tile_players[0].volume_db + AudioServer.get_bus_volume_db(sfx_bus)), 0.03125), "Click combines 6.25 percent base volume with the default half SFX volume")
	check(audio.victory_player.bus == "SFX" and audio.victory_player.volume_db == 0.0, "Victory follows SFX volume without the tile-only base reduction")
	music_slider.value = 100
	check(audio.music_player.volume_linear == 0.0, "Changing Music volume in the main menu keeps the music silent")
	music_slider.value = 25
	sfx_slider.value = 75
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), 0.25) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(sfx_bus)), 0.75), "Sliders independently apply their bus volumes immediately")
	music_slider.value = 0
	sfx_slider.value = 0
	check(AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(sfx_bus) and audio.music_player.playing, "Zero mutes both buses while music keeps progressing")
	music_slider.value = 25
	sfx_slider.value = 75
	check(not AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(sfx_bus), "Increasing volume restores both buses")
	var persisted := ConfigFile.new()
	check(persisted.load(audio.SETTINGS_PATH) == OK and persisted.get_value("audio", "music_volume") == 0.25 and persisted.get_value("audio", "sfx_volume") == 0.75, "Both preferences are saved separately from progress")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._input(escape)
	check(main.settings_layer == null and main.screen == "menu", "Escape closes settings without leaving the current screen")
	var playhead: float = audio.music_player.get_playback_position()
	main.play_level(1)
	# Step the midpoint explicitly so renderer stalls cannot skip the assertion.
	audio.music_fade.pause()
	audio.music_fade.custom_step(0.08)
	check(is_equal_approx(audio.music_player.volume_linear, 0.1), "Entering a puzzle fades music in linearly over 0.2 seconds")
	audio.music_fade.play()
	await create_timer(0.27).timeout
	await settle_transition(main)
	check(is_equal_approx(audio.music_player.volume_linear, 0.25) and is_equal_approx(db_to_linear(audio.music_player.volume_db + AudioServer.get_bus_volume_db(music_bus)), 0.0625), "After 0.2 seconds music reaches quarter base volume times the chosen slider volume")
	check(main.game_audio == audio and audio.music_player.get_playback_position() >= playhead, "Puzzle navigation preserves the music playhead")
	check(main.completed_badge.get_global_rect().end.x < main.credit_display.get_global_rect().position.x and main.credit_display.get_global_rect().end.x < main.settings_button.get_global_rect().position.x and main.completed_badge.size == Vector2(72, 72), "Completed puzzles display checkmark, credits, then cog without overlap")
	await capture("settings-play")
	main._open_settings()
	check(main.board.locked and not main.board.is_processing_input(), "Opening settings blocks board input")
	check(main.settings_layer.find_child("MusicVolume", true, false).value == 25 and main.settings_layer.find_child("SfxVolume", true, false).value == 75, "Reopening settings retains the selected volumes")
	root.size = Vector2i(760, 680)
	await process_frame
	await process_frame
	await process_frame
	var panel: Control = main.settings_layer.find_child("MusicVolume", true, false).get_parent().get_parent().get_parent()
	check(panel.get_global_rect().position.x >= 0 and panel.get_global_rect().end.x <= main.size.x, "Settings fits at the minimum window size")
	await capture("settings-small")
	main._close_settings()
	check(not main.board.locked and main.board.is_processing_input(), "Closing settings restores board input")
	main._open_settings()
	main._begin_delete_progress()
	main._cancel_delete_progress()
	check(is_instance_valid(main.settings_layer) and main.store.completed.get("1", false), "Cancelling deletion from a puzzle preserves settings and progress")
	main._close_settings()
	main._toggle_editor()
	check(is_instance_valid(main.settings_button), "The editor also offers settings")
	main._open_settings()
	main._close_settings()
	main._return_to_menu()
	audio.music_fade.pause()
	audio.music_fade.custom_step(0.08)
	check(is_equal_approx(audio.music_player.volume_linear, 0.15), "Returning to the menu fades music out linearly over 0.2 seconds")
	audio.music_fade.play()
	await create_timer(0.27).timeout
	await settle_transition(main)
	check(audio.music_player.volume_linear == 0.0 and audio.music_player.playing, "The menu reaches true silence without stopping the playlist")
	check(main.settings_button.is_visible_in_tree() and main.credit_label.text == "123", "Returning restores the menu's cog and credits")
	main._open_settings()
	main._begin_delete_progress()
	for confirmation in range(2):
		main._advance_delete_progress()
		await process_frame
	main._advance_delete_progress()
	check(main.settings_layer == null and main.screen == "menu" and main.store.completed.is_empty() and main.credit_label.text == "0", "Confirmed deletion closes settings and refreshes the initial menu")
	check(audio.music_volume == 0.25 and audio.sfx_volume == 0.75 and FileAccess.file_exists(audio.SETTINGS_PATH), "Deleting progress preserves volume preferences")
	main.play_level(1)
	await create_timer(0.06).timeout
	main.show_menu()
	await create_timer(0.06).timeout
	main.play_level(1)
	await create_timer(0.35).timeout
	check(is_equal_approx(audio.music_player.volume_linear, 0.25), "Interrupted music fades settle at the newest puzzle's volume")
	main.show_menu()
	await create_timer(0.3).timeout
	check(audio.music_player.volume_linear == 0.0, "Returning after interrupted fades still reaches zero")
	var restored_audio = main.GameAudio.new()
	root.add_child(restored_audio)
	check(restored_audio.music_volume == 0.25 and restored_audio.sfx_volume == 0.75, "A fresh audio controller restores saved volumes")
	restored_audio.queue_free()
	print("Settings/music checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
