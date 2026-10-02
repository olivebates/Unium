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
	var started := Time.get_ticks_msec()
	for number in range(1, 151):
		var level := Puzzle.generate(number)
		check(level == Puzzle.generate(number), "Seed %d is deterministic" % number)
		check(level.solution.size() == number + 6, "Exact solution length for %d" % number)
		check(level.width >= 3 and level.height >= 3, "Minimum dimensions")
		if number <= 43:
			check(level.width <= 7 and level.height <= 7, "Original board size range")
		else:
			check(level.width > 7 or level.height > 7, "Larger boards preserve growing solutions")
		check(level.tiles.has(1), "Puzzle starts unsolved")
		var path: Array = []
		for cell in level.solution:
			check(Puzzle.can_append(path, cell, level.width, level.height), "Legal generated move in %d" % number)
			path.append(cell)
		check(Puzzle.is_complete(level.tiles, path), "Generated solution solves %d" % number)
		var unseen: Array = []
		for cell in range(level.tiles.size()):
			if level.tiles[cell] == 2:
				unseen.append(cell)
		check(not unseen.is_empty(), "Gray clumps exist in %d" % number)
		while not unseen.is_empty():
			var component: Array = [unseen.pop_back()]
			var cursor := 0
			var touches := false
			while cursor < component.size():
				for near in Puzzle.neighbors(component[cursor], level.width, level.height):
					if level.tiles[near] == 1:
						touches = true
					if near in unseen:
						unseen.erase(near)
						component.append(near)
				cursor += 1
			check(component.size() >= 2 and component.size() <= 4, "Gray component size 2–4")
			check(touches, "Gray component touches a dark tile")
	for number in range(1, 30):
		if number % 5 != 0:
			check(Puzzle.palette(number) == Puzzle.palette(number + 1), "Five-level palette block")
		else:
			check(Puzzle.palette(number) != Puzzle.palette(number + 1), "Next palette block changes")
	# A route crossing its horizontal middle section vertically.
	var crossing: Array = [5, 6, 7, 8, 9, 14, 13, 12]
	check(Puzzle.can_append(crossing, 7, 5, 5), "Perpendicular straight crossing accepted")
	crossing.append(7)
	check(Puzzle.can_append(crossing, 2, 5, 5), "Crossing exits straight")
	check(not Puzzle.can_append(crossing, 6, 5, 5), "Crossing cannot turn left")
	check(not Puzzle.can_append(crossing, 8, 5, 5), "Crossing cannot turn right")
	var all_light: Array = []
	all_light.resize(25)
	all_light.fill(0)
	var dark := Puzzle.resolved_tiles(all_light, crossing)
	check(dark[7] == 0, "Crossed tile flips back")
	check(not Puzzle.is_complete(dark, crossing), "Cannot finish mid-crossing")
	check(not Puzzle.can_append([0, 1, 6, 7], 1, 5, 5), "Cannot cross a corner")
	check(not Puzzle.can_append([0, 1, 6, 5], 0, 5, 5), "Cannot revisit start")
	check(not Puzzle.can_append([4], 5, 5, 5), "No row wrapping")
	check(Puzzle.resolved_tiles([2, 1, 0], [0, 1, 2]) == [2, 0, 1], "Gray is invariant")
	check(PuzzleBoard.tile_color(1, Color.WHITE).is_equal_approx(Color.WHITE.darkened(0.80).lightened(0.30)), "Dark tile is 30 percent lighter")
	check(not LevelStore.valid_level({"width": 3, "height": 3, "tiles": [0]}), "Reject malformed saved grid")
	check(LevelStore._previous_path("levels.json") == ProjectSettings.globalize_path("user://levels.json").replace("Afterglow", "Unium"), "Renamed game reads the original save folder")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.levels.clear()
	main.store.colors.clear()
	main.play_level(1)
	await process_frame
	check(main.board != null, "Gameplay scene loaded")
	var b: PuzzleBoard = main.board
	check(b.line.default_color == Color.BLACK and b.end_dot.color == Color.BLACK and b.line_group.modulate.a == 1.0, "Line is opaque black")
	b.configure({"width": 5, "height": 5, "tiles": all_light}, Color.WHITE)
	b._begin(b.center(5))
	b._trace(b.center(7))
	check(b.path == [5, 6, 7], "Fast drag samples intermediate cells")
	b._end()
	b._begin(b.center(20))
	check(not b.dragging and b.path == [5, 6, 7], "Cannot start a second line")
	b._begin(b.center(7))
	check(b.dragging, "Endpoint resumes line")
	b._trace(b.center(6))
	check(b.path == [5, 6], "Backward drag undoes last tile")
	b._end()
	b.path = crossing.duplicate()
	b.refresh()
	b._begin(b.center(7))
	b._trace(b.center(12))
	check(b.path == [5, 6, 7, 8, 9, 14, 13, 12], "Undo through crossing")
	b.clear_path()
	main._toggle_editor()
	await process_frame
	check(main.screen == "editor", "Editor opens")
	var original: Dictionary = main.editor_data.duplicate(true)
	main.stroke_before = original.duplicate(true)
	main.brush = (int(original.tiles[0]) + 1) % 3
	main._paint_cell(0)
	main._finish_stroke()
	check(main.undo_stack.size() == 1, "Paint stroke creates one undo entry")
	main._editor_undo()
	check(main.editor_data == original, "Undo restores editor tiles")
	main._editor_redo()
	check(main.editor_data != original, "Redo reapplies editor stroke")
	main.width_input.value = int(original.width) + 1
	check(main.editor_data.width == int(original.width) + 1, "Editor resizing")
	main._editor_undo()
	check(main.editor_data.width == original.width, "Undo restores dimensions")
	var before_white_reset: Array = main.editor_data.tiles.duplicate()
	main._reset_all_white()
	check(not main.editor_data.tiles.has(1) and not main.editor_data.tiles.has(2), "Reset all to white clears dark and gray tiles")
	main._editor_undo()
	check(main.editor_data.tiles == before_white_reset, "White reset can be undone")
	main._editor_redo()
	check(not main.editor_data.tiles.has(1) and not main.editor_data.tiles.has(2), "White reset can be redone")
	var history_size: int = main.undo_stack.size()
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_I, true, false, true)
	check(main.color_mode, "Shift+Z+I opens color mode")
	key(main, KEY_I, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	check(main.undo_stack.size() == history_size, "Color shortcut does not trigger undo")
	main._toggle_color_editor()
	check(not main.color_mode, "Color mode closes")
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_O, true)
	key(main, KEY_X, true, false, true)
	check(main.screen == "editor", "Old editor shortcut does not toggle")
	key(main, KEY_O, false)
	key(main, KEY_X, false, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_O, true, false, true)
	check(main.screen == "play", "Shift+Z+O closes editor")
	key(main, KEY_O, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	# Save only inside the isolated APPDATA supplied by the test command.
	var custom := {"width": 3, "height": 3, "tiles": [1, 0, 2, 0, 0, 2, 0, 0, 0]}
	check(main.store.save_level(2, custom) == OK, "Custom level save succeeds")
	check(main.store.save_color(2, Color("e7b4df")) == OK, "Custom color save succeeds")
	check(main.store.mark_complete(1) == OK, "Progress save succeeds")
	var reloaded := LevelStore.new()
	check(reloaded.get_level(2).tiles == custom.tiles, "Custom level survives reload")
	check(reloaded.get_color(2).is_equal_approx(Color("e7b4df")), "Color survives reload")
	check(reloaded.frontier() == 2, "Only next unsolved level unlocks")
	main.play_level(2)
	await process_frame
	main.board._begin(main.board.center(0))
	check(main.board.locked, "Solving locks input during celebration")
	check(main.store.completed.get("2", false), "Solving marks completed")
	await create_timer(2.7).timeout
	check(main.current_level == 3, "Celebration automatically advances")
	main.show_menu()
	await process_frame
	check(main.screen == "menu", "Menu rebuilds completed screenshots")
	var level_cards := root.find_children("", "Button", true, false).filter(func(node): return node.tooltip_text.begins_with("Play level "))
	check(not level_cards.is_empty() and level_cards[0].size == Vector2(64, 64), "Menu level cards are 64 by 64")
	print("%d checks, %d failures in %.2fs" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures else 0)

func key(main: Control, code: Key, down: bool, ctrl: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	main._input(event)
