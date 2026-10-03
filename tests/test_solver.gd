extends SceneTree

const Solver = preload("res://scripts/puzzle_solver.gd")
var checks := 0
var failures := 0
var reachable_masks: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func enumerate_routes(path: Array, mask: int) -> void:
	if path.size() >= 2:
		reachable_masks[mask] = true
	for cell in Puzzle.neighbors(path.back(), 3, 3):
		if Puzzle.can_append(path, cell, 3, 3):
			path.append(cell)
			enumerate_routes(path, mask ^ (1 << cell))
			path.pop_back()

func legal_solution(layout: Dictionary, path: Array) -> bool:
	if path.size() < 2:
		return false
	var prefix: Array = []
	for cell in path:
		if not Puzzle.can_append(prefix, cell, layout.width, layout.height):
			return false
		prefix.append(cell)
	return Puzzle.is_complete(layout.tiles, path)

func solve(layout: Dictionary, timeout_ms: int = 2000) -> RefCounted:
	var search := Solver.new(layout)
	var deadline := Time.get_ticks_msec() + timeout_ms
	while search.status == "searching" and Time.get_ticks_msec() < deadline:
		search.advance()
	return search

func wait_for_editor(main: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while main.editor_solver != null and Time.get_ticks_msec() < deadline:
		await process_frame

func run() -> void:
	var started := Time.get_ticks_msec()
	# Independent exhaustive reference: enumerate routes using the player's
	# rules, then compare every 3x3 dark/light layout against the solver.
	for cell in range(9):
		enumerate_routes([cell], 1 << cell)
	for gray_mask in [0, 16, 7, 341]:
		for dark_mask in range(512):
			if dark_mask & gray_mask:
				continue
			var tiles: Array = []
			for cell in range(9):
				tiles.append(2 if gray_mask & (1 << cell) else (1 if dark_mask & (1 << cell) else 0))
			var expected := false
			for mask in reachable_masks:
				if (int(mask) & (511 ^ gray_mask)) == dark_mask:
					expected = true
					break
			var layout := {"width": 3, "height": 3, "tiles": tiles}
			var search := solve(layout)
			check(search.status != "searching", "Small board search finishes")
			check((search.status == "solved") == expected, "Solver matches exhaustive reference for dark=%d gray=%d" % [dark_mask, gray_mask])
			if search.status == "solved":
				check(legal_solution(layout, search.solution), "Returned route follows the player's rules and clears every tile")
	var simple := {"width": 3, "height": 3, "tiles": [1, 1, 0, 0, 0, 0, 0, 0, 0]}
	var stale := simple.duplicate(true)
	stale.solution = [3, 4]
	check(legal_solution(stale, solve(stale).solution), "A stale cached solution falls back to searching the current tiles")
	stale.solution = [0, 2]
	check(legal_solution(stale, solve(stale).solution), "An illegal cached solution is ignored")
	var generated := Puzzle.generate(24)
	var known := solve(generated)
	check(known.status == "solved" and known.nodes == 0 and known.solution == generated.solution, "An unchanged generated draft reuses its validated solution")
	generated.erase("solution")
	var ongoing := Solver.new(generated)
	var slice_started := Time.get_ticks_usec()
	ongoing.advance()
	check(Time.get_ticks_usec() - slice_started < 25000 and ongoing.status == "searching", "A difficult puzzle yields control while its search continues")
	var smaller := Puzzle.generate(1, Vector2i(5, 5), 0, 41, 12)
	smaller.erase("solution")
	var found := solve(smaller)
	check(found.status == "solved" and legal_solution(smaller, found.solution), "Search solves a generated board without its original path")
	var large_tiles: Array = []
	large_tiles.resize(128 * 128)
	large_tiles.fill(1)
	var large := Solver.new({"width": 128, "height": 128, "tiles": large_tiles})
	slice_started = Time.get_ticks_usec()
	large.advance()
	check(Time.get_ticks_usec() - slice_started < 25000 and large.prepared_cells < large_tiles.size(), "Preparing a maximum-size editor grid also yields control")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.hints.clear()
	main.store.credits = 0
	main.store.levels.clear()
	main._toggle_editor()
	main.editor_data = simple.duplicate(true)
	main._sync_editor()
	var history: Array = main.undo_stack.duplicate(true)
	main.editor_solve_button.pressed.emit()
	check(main.editor_playtesting and main.board.locked and main.editor_solve_button.text == "Cancel solve" and not main.editor_solve_button.disabled, "Solve starts a cancellable search in playtest mode")
	await wait_for_editor(main)
	check(main.editor_playtesting and main.board.locked and legal_solution(simple, main.board.path), "The found line is displayed as a solved playtest")
	check(main.editor_data == simple and main.undo_stack == history, "Solving preserves the editor layout and edit history")
	check(main.store.completed.is_empty() and main.store.credits == 0 and main.store.hint_endpoints(main.editor_level) == [main.board.path.front(), main.board.path.back()], "Solving records endpoints without awarding completion or credits")
	main._toggle_editor_playtest()
	check(main.board.editing and main.board.path.is_empty() and not main.editor_solve_button.disabled, "Space-to-build behavior restores editing after a solution")
	main.editor_solve_button.pressed.emit()
	main.editor_solve_button.pressed.emit()
	await process_frame
	check(main.editor_solver == null and not main.editor_playtesting and main.board.editing and main.board.path.is_empty(), "Cancel stops the search without a late solution replacing the draft")
	main.editor_solve_button.pressed.emit()
	main._navigate_level(1)
	await process_frame
	check(main.editor_solver == null and not main.editor_playtesting and main.board.editing, "Changing editor levels cancels the old search")
	main.editor_data = {"width": 3, "height": 3, "tiles": [1, 0, 0, 0, 0, 0, 0, 0, 1]}
	main._sync_editor()
	main.editor_solve_button.pressed.emit()
	await wait_for_editor(main)
	check(not main.editor_playtesting and main.board.editing and main.editor_message.text.contains("No legal solution"), "An impossible layout returns to editing with an honest result")
	main.editor_data = simple.duplicate(true)
	main._sync_editor()
	main.editor_solve_button.pressed.emit()
	main._return_to_menu()
	await process_frame
	check(main.screen == "menu" and main.editor_solver == null, "Leaving the editor cancels any search")
	print("Solver checks: %d, failures: %d, %.2fs" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures else 0)
