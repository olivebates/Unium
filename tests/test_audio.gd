extends SceneTree

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.unlocked_through = 5
	main.store.levels["1"] = {"width": 3, "height": 3, "tiles": [1, 2, 0, 1, 1, 1, 1, 1, 1]}
	main.play_level(1)
	await create_timer(0.35).timeout
	var audio = main.game_audio
	var added: Array[int] = []
	var removed: Array[int] = []
	main.board.line_tile_added.connect(func(cell: int): added.append(cell))
	main.board.line_tile_removed.connect(func(cell: int): removed.append(cell))
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(2))
	check(added == [0, 1, 2] and removed.is_empty(), "A fast drag adds every entered tile, including gray and light tiles")
	check(audio.tile_players.size() == 3 and audio.tile_players.all(func(voice): return voice.playing and voice.stream == audio.CLICK), "Each addition starts an independent click voice without Place.ogg")
	var first_pitch: float = audio.tile_players[0].pitch_scale
	check(audio.tile_players.all(func(voice): return voice.pitch_scale >= 0.8 and voice.pitch_scale <= 1.2), "All tile pitches are within 0.8 to 1.2")
	check(audio.tile_players.any(func(voice): return voice.pitch_scale != first_pitch), "Tile pitches vary independently")
	main.board._trace(main.board.center(2))
	check(added.size() == 3 and removed.is_empty(), "Remaining on the same tile does not repeat its sound")
	main.board._trace(main.board.center(0))
	check(added == [0, 1, 2] and removed == [2, 1], "Backtracking removes each tile without adding another")
	check(audio.tile_players.size() == 5 and audio.tile_players.slice(3).all(func(voice): return voice.playing and voice.stream.resource_path == "res://music/Place.ogg"), "Backtracking plays Place.ogg for each removed tile")
	check(audio.tile_players[0].pitch_scale == first_pitch, "Removal sounds leave an overlapping addition's pitch unchanged")
	main.board.clear_path()
	check(added.size() == 3 and removed == [2, 1, 0], "Reset emits removal for the remaining tile")
	main.board.path = [0, 1, 4, 5, 8, 7, 6, 3]
	main.board.refresh()
	main.board._begin(main.board.center(3))
	var count := added.size() + removed.size()
	main.board._trace(main.board.center(5))
	check(added.size() + removed.size() == count, "Blocked moves and resuming an endpoint do not emit line-edit sounds")
	main.board._end()
	main.board._begin(main.board.center(4))
	check(main.board.path == [0, 1, 4] and removed.slice(3) == [3, 6, 7, 8, 5] and added.size() == 3, "Clicking an earlier tile sounds only the removed tail")
	main.board._begin(main.board.center(0))
	check(main.board.path.is_empty() and removed.slice(8) == [4, 1, 0], "Clicking the start sounds removal of the whole line")
	main.board._begin(main.board.center(0))
	main.board._end()
	check(added.back() == 0 and removed.back() == 0, "Releasing a single-tile line sounds its addition and removal")
	main.board._begin(main.board.center(0))
	count = added.size() + removed.size()
	main.board.clear_path(false)
	check(added.size() + removed.size() == count, "Programmatic clears can stay silent")
	main.board._end()
	main.board.editing = true
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(2))
	main.board._end()
	check(added.size() + removed.size() == count, "Editor painting does not emit gameplay sounds")
	for cell in range(100):
		if cell % 2 == 0:
			audio.play_click(cell)
		else:
			audio.play_place(cell)
	check(audio.tile_players.size() == audio.MAX_TILE_VOICES and audio.tile_players.all(func(voice): return voice.pitch_scale >= 0.8 and voice.pitch_scale <= 1.2), "Very rapid additions and removals keep the voice pool bounded and pitches valid")
	main.store.levels["2"] = {"width": 3, "height": 3, "tiles": [1, 1, 0, 0, 0, 0, 0, 0, 0]}
	main.play_level(2)
	await create_timer(0.35).timeout
	check(main.game_audio == audio and not audio.victory_player.playing, "Navigation preserves the audio controller without playing victory")
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(1))
	check(main.store.completed.has("2") and audio.victory_player.playing and audio.victory_player.stream.resource_path == "res://music/Victory.ogg" and audio.victory_player.pitch_scale == 1.0, "Solving the puzzle plays Victory.ogg at its original pitch")
	main._open_adjacent_level(1)
	check(main.game_audio == audio and audio.victory_player.playing, "Next Puzzle does not cut off the victory sound")
	main.show_menu()
	check(main.game_audio == audio and audio.victory_player.playing, "Returning to selection does not cut off the victory sound")
	audio.victory_player.stop()
	main.play_level(2)
	await create_timer(0.35).timeout
	check(not audio.victory_player.playing, "Revisiting a completed level is silent until it is solved again")
	main._complete_level()
	check(audio.victory_player.playing, "Solving a previously completed level still plays victory")
	audio.victory_player.stop()
	main._complete_level()
	check(not audio.victory_player.playing, "Duplicate completion calls do not replay victory")
	main.play_level(101)
	main._complete_level()
	check(not audio.victory_player.playing, "Opening the final message screen does not count as solving another puzzle")
	print("Audio checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
