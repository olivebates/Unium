extends SceneTree

const CelebrationLines = preload("res://scripts/celebration_lines.gd")

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
	var generated_crossings := 0
	for number in range(1, 151):
		var level := Puzzle.generate(number)
		var unique_cells: Dictionary = {}
		for cell in level.solution:
			unique_cells[cell] = true
		var crossing_count: int = level.solution.size() - unique_cells.size()
		generated_crossings += crossing_count
		check(crossing_count <= Puzzle.MAX_GENERATED_CROSSINGS, "Generated solution has at most three crossings in %d" % number)
		check(level == Puzzle.generate(number), "Seed %d is deterministic" % number)
		check(level.solution.size() == number + 26, "Exact solution length for %d" % number)
		check(level.width >= 3 and level.height >= 3, "Minimum dimensions")
		if number <= 23:
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
	check(generated_crossings > 0, "Generated paths use legal self-crossings")
	print("Generated crossings across 150 levels: %d" % generated_crossings)
	for settings in [[Vector2i(3, 3), 0, 41], [Vector2i(5, 6), 2, 42], [Vector2i(7, 7), 8, 43]]:
		var dimensions: Vector2i = settings[0]
		var limit: int = settings[1]
		var seed: int = settings[2]
		var custom := Puzzle.generate(1, dimensions, limit, seed)
		check(custom == Puzzle.generate(1, dimensions, limit, seed), "Editor generation is repeatable with a seed")
		check(custom.width == dimensions.x and custom.height == dimensions.y and custom.solution.size() <= dimensions.x * dimensions.y, "Editor generation respects the selected dimensions")
		var custom_path: Array = []
		var visited: Dictionary = {}
		for cell in custom.solution:
			check(Puzzle.can_append(custom_path, cell, dimensions.x, dimensions.y), "Editor generator follows legal moves")
			custom_path.append(cell)
			visited[cell] = true
		check(custom_path.size() - visited.size() <= limit, "Editor generator respects its crossover limit")
		check(Puzzle.is_complete(custom.tiles, custom_path), "Editor generator creates a solvable board")
	var generous := Puzzle.generate(1, Vector2i(7, 7), 8, 12)
	var generous_unique: Dictionary = {}
	for cell in generous.solution:
		generous_unique[cell] = true
	check(generous.solution.size() - generous_unique.size() > Puzzle.MAX_GENERATED_CROSSINGS, "Editor setting can allow more crossings than normal levels")
	var exact := Puzzle.generate(1, Vector2i(3, 3), 0, 41, 7)
	check(exact.solution.size() == 7 and Puzzle.is_complete(exact.tiles, exact.solution), "Editor move count sets the exact solution length")
	check(Puzzle.generate(1, Vector2i(3, 3), 0, 41, 10).is_empty(), "Impossible move counts fail without producing a shorter puzzle")
	var crossed_length := Puzzle.generate(1, Vector2i(5, 5), 1, 1, 26)
	check(crossed_length.solution.size() == 26 and Puzzle.is_complete(crossed_length.tiles, crossed_length.solution), "Editor can use a crossing to exceed the board's tile count")
	var exactly_three := Puzzle.generate(8, Vector2i(6, 7), 3, 1, 34, true)
	var three_unique: Dictionary = {}
	for cell in exactly_three.solution:
		three_unique[cell] = true
	check(exactly_three.solution.size() == 34 and exactly_three.solution.size() - three_unique.size() == 3 and Puzzle.is_complete(exactly_three.tiles, exactly_three.solution), "Editor generation uses exactly the requested three crossovers")
	check(Puzzle.generate(1, Vector2i(3, 3), 10, 41, 7, true).is_empty(), "Impossible exact crossover counts produce no level")
	for number in range(1, 30):
		if number % 5 != 0:
			check(Puzzle.palette(number) == Puzzle.palette(number + 1), "Five-level palette block")
		else:
			check(Puzzle.palette(number) != Puzzle.palette(number + 1), "Next palette block changes")
	check(Puzzle.palette(1) == Puzzle.palette(26), "Curated hue sequence repeats after five sets")
	check(absf(Puzzle.palette(1).h - 0.43) < 0.001 and absf(Puzzle.palette(6).h - 0.56) < 0.001 and absf(Puzzle.palette(11).h - 0.74) < 0.001, "Curated mint, sky, and lavender order")
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
	check(Puzzle.is_complete(dark, crossing), "A light tile at a crossed endpoint can finish a puzzle")
	check(not Puzzle.can_append([0, 1, 6, 7], 1, 5, 5), "Cannot cross a corner")
	var start_crossing: Array = [4, 5, 8, 7, 6, 3, 0, 1]
	check(Puzzle.can_append(start_crossing, 4, 3, 3), "Can cross the start perpendicular to its first edge")
	start_crossing.append(4)
	check(Puzzle.can_append(start_crossing, 7, 3, 3) and not Puzzle.can_append(start_crossing, 3, 3, 3), "Crossing the start must continue straight")
	check(not Puzzle.can_append([4, 5, 8, 7, 6, 3], 4, 3, 3), "Cannot enter the start from behind")
	var start_layout := Puzzle.resolved_tiles([0, 0, 0, 0, 0, 0, 0, 0, 0], start_crossing)
	check(start_layout[4] == 0 and Puzzle.is_complete(start_layout, start_crossing), "An overlapped start stays light and counts toward completion")
	check(not Puzzle.can_append([4], 5, 5, 5), "No row wrapping")
	check(Puzzle.resolved_tiles([2, 1, 0], [0, 1, 2]) == [2, 0, 1], "Gray is invariant")
	var hue := Color.from_hsv(0.62, 0.25, 0.82)
	var light_color := PuzzleBoard.tile_color(0, hue)
	var dark_color := PuzzleBoard.tile_color(1, hue)
	var background := PuzzleBoard.background_color(hue)
	var menu_background := PuzzleBoard.menu_background_color(hue)
	check(light_color.s <= 0.601 and dark_color.s <= 0.701, "Tile saturation stays within the soft palette")
	check(PuzzleBoard.luminance(light_color) > PuzzleBoard.luminance(dark_color) * 3.0, "Light and dark tiles stay visually distinct")
	check(is_equal_approx(light_color.h, dark_color.h), "Light and dark tiles share the base hue")
	check(is_equal_approx(background.s, 0.25) and background.v < 0.25, "Background is dark and softly tinted")
	check(is_equal_approx(menu_background.h, hue.h) and absf(PuzzleBoard.luminance(menu_background) - PuzzleBoard.luminance(background)) < 0.001, "Menu background uses the level's main hue at the same darkness as play")
	check(is_equal_approx(PuzzleBoard.line_color(hue).h, fposmod(hue.h + 2.0 / 12.0, 1.0)), "Cool purple line shifts 60 degrees toward warmer magenta")
	check(is_equal_approx(PuzzleBoard.line_color(Puzzle.palette(1)).h, fposmod(Puzzle.palette(1).h - 2.0 / 12.0, 1.0)), "Mint line shifts 60 degrees toward warmer yellow")
	check(is_equal_approx(PuzzleBoard.line_color(Puzzle.palette(6)).h, fposmod(Puzzle.palette(6).h - 2.0 / 12.0, 1.0)), "Sky line shifts 60 degrees toward warmer green")
	check(is_equal_approx(PuzzleBoard.button_color(hue).h, background.h) and is_equal_approx(PuzzleBoard.text_color(hue).h, background.h) and PuzzleBoard.luminance(PuzzleBoard.button_color(hue)) < PuzzleBoard.luminance(dark_color), "Text and quieter buttons share the background hue")
	check(is_equal_approx(background.h, fposmod(hue.h + 5.0 / 12.0, 1.0)), "Background uses the first split-complementary hue")
	check(is_equal_approx(PuzzleBoard.tile_color(2, hue).s, 0.07) and is_equal_approx(PuzzleBoard.tile_color(2, hue).v, 0.45), "Gray tiles remain subdued")
	check(not LevelStore.valid_level({"width": 3, "height": 3, "tiles": [0]}), "Reject malformed saved grid")
	check(LevelStore._previous_path("Godot/app_userdata/Unium", "levels.json") == ProjectSettings.globalize_path("user://levels.json").replace("Hearthline", "Unium"), "Renamed game reads Unium saves")
	check(LevelStore._previous_path("Godot/app_userdata/Afterglow", "levels.json") == ProjectSettings.globalize_path("user://levels.json").replace("Hearthline", "Afterglow"), "Renamed game reads Afterglow saves")
	check(LevelStore._previous_path("Godot/app_userdata/Glimmer", "levels.json") == ProjectSettings.globalize_path("user://levels.json").replace("Hearthline", "Glimmer"), "Renamed game reads Glimmer saves")
	check(LevelStore._previous_path("Godot/app_userdata/Strike-through", "levels.json") == ProjectSettings.globalize_path("user://levels.json").replace("Hearthline", "Strike-through"), "Renamed game reads Strike-through saves")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.hints.clear()
	main.store.credits = 0
	main.store.unlocked_through = 0
	main.store.levels.clear()
	main.store.colors.clear()
	main.store.line_colors.clear()
	# Check the whole hue wheel, including manually chosen colors.
	main.screen = "play"
	for degrees in range(0, 360, 15):
		var sample := Color.from_hsv(degrees / 360.0, 1.0, 1.0)
		main._apply_ui_palette(sample)
		var ink := PuzzleBoard.text_color(sample)
		check(ink.s <= 0.15, "Text remains a pale tint across hues")
		check(absf(PuzzleBoard.luminance(PuzzleBoard.tile_color(0, sample)) - PuzzleBoard.luminance(light_color)) < 0.01, "Light tiles have consistent perceived brightness across hues")
		check(absf(PuzzleBoard.luminance(PuzzleBoard.tile_color(1, sample)) - PuzzleBoard.luminance(dark_color)) < 0.01, "Dark tiles have consistent perceived brightness across hues")
		check(PuzzleBoard.line_color(sample).s <= 0.721 and absf(PuzzleBoard.luminance(PuzzleBoard.line_color(sample)) - PuzzleBoard.luminance(PuzzleBoard.line_color(hue))) < 0.001, "Warm analogous line keeps corrected brightness across hues")
		check(PuzzleBoard.luminance(PuzzleBoard.line_color(sample)) > PuzzleBoard.luminance(PuzzleBoard.tile_color(0, sample)), "Line is brighter than the light tiles across hues")
		for kind in ["Button", "PrimaryButton"]:
			for state in ["normal", "hover", "pressed"]:
				var fill: Color = main.palette_theme.get_stylebox(state, kind).bg_color
				check((PuzzleBoard.luminance(ink) + 0.05) / (PuzzleBoard.luminance(fill) + 0.05) >= 4.5, "Button text stays readable across hues and interaction states")
		var primary_fill: Color = main.palette_theme.get_stylebox("normal", "PrimaryButton").bg_color
		var secondary_fill: Color = main.palette_theme.get_stylebox("normal", "Button").bg_color
		check(PuzzleBoard.luminance(primary_fill) > PuzzleBoard.luminance(secondary_fill) * 1.5, "Primary buttons stand out from secondary buttons")
	main.screen = "menu"
	for degrees in range(0, 360, 15):
		var sample := Color.from_hsv(degrees / 360.0, 1.0, 1.0)
		main._apply_ui_palette(sample)
		var menu_ink := PuzzleBoard.menu_text_color(sample)
		check(is_equal_approx(main.palette_text.h, sample.h) and is_equal_approx(main.palette_button.h, sample.h), "Menu text and buttons follow the selected level's main hue")
		for kind in ["Button", "PrimaryButton"]:
			for state in ["normal", "hover", "pressed"]:
				var fill: Color = main.palette_theme.get_stylebox(state, kind).bg_color
				check((PuzzleBoard.luminance(menu_ink) + 0.05) / (PuzzleBoard.luminance(fill) + 0.05) >= 4.5, "Menu buttons remain readable across hues")
	main._apply_ui_palette(main.store.get_color(1))
	main.play_level(1)
	await create_timer(0.35).timeout
	while is_instance_valid(main.screen_transition):
		await process_frame
	check(main.board != null, "Gameplay scene loaded")
	check(main.completed_badge == null, "Unfinished puzzles have no completion badge")
	check(main.hint_button == null and main.credit_label.text == "0", "Level 1 has no hint button and starts with no credits")
	var phrases_seen := {}
	for phrase in CelebrationLines.LINES:
		phrases_seen[phrase] = true
	check(CelebrationLines.LINES.size() == 100 and phrases_seen.size() == 100, "Exactly 100 distinct celebration messages")
	check(main.find_children("", "Label", true, false).all(func(node): return node.text != "H e a r t h l i n e" or not node.is_visible_in_tree()), "Game title is hidden inside levels")
	check(main.content.get_child(0).text == "Level 1", "Level numbers have no leading zero")
	check(main.palette_theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(1))), "Play text uses the first split-complementary hue")
	check((main.palette_theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color.is_equal_approx(PuzzleBoard.button_color(main.store.get_color(1))), "Secondary buttons use the subdued split-complementary hue")
	check(main.palette_theme.get_color("font_shadow_color", "Label").a > 0.0, "Text has a shadow")
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items" and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "Game layout stretches to fill fullscreen")
	var play_controls := main.content.get_child(2) as HBoxContainer
	check(play_controls.get_child_count() == 5 and (play_controls.get_child(0) as Button).text == "▦ All puzzles" and play_controls.get_child(1).size_flags_horizontal == Control.SIZE_EXPAND_FILL and (play_controls.get_child(2) as Button).text == "← Previous puzzle" and (play_controls.get_child(3) as Button).text == "↻ Reset line" and (play_controls.get_child(4) as Button).text == "Next puzzle →", "Grid button returns to puzzles and navigation buttons align at the right")
	check(main.background_rect.color == PuzzleBoard.background_color(main.store.get_color(1)), "Entire play screen uses the level background")
	check((main.board_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == main.background_rect.color, "Play area shares the same background")
	var b: PuzzleBoard = main.board
	var left_dark := -1
	for cell in range(b.tiles.size()):
		if b.tiles[cell] != 1:
			continue
		var x := cell % b.width
		if left_dark < 0 or x < left_dark % b.width:
			left_dark = cell
	check(b.start_label.visible and not b.finish_label.visible and b.start_label.text == "Drag" and b.finish_label.text.is_empty(), "Level 1 shows Drag and leaves the finish tile blank")
	check((b.start_label.position + b.start_label.size * 0.5).is_equal_approx(b.center(left_dark)), "Drag sits on the leftmost dark tile")
	check(b.start_label.get_theme_color("font_color") == Color.WHITE and b.start_label.get_theme_color("font_outline_color") == Color.BLACK, "Drag has white text and a black outline")
	check(b.line.default_color == LevelStore.DEFAULT_LINE_COLOR and b.start_dot.color == b.line.default_color and b.line_group.modulate.a == 1.0, "Line and start marker use the saved area-six fallback color")
	check(b.line_shadow.default_color.a > 0.0 and b.line_shadow.position.y > 0.0, "Line has a raised shadow")
	b.configure({"width": 5, "height": 5, "tiles": all_light}, Color.WHITE)
	check(b.tile_rects.size() == 25 and b.tile_styles.size() == 3, "Board caches tile geometry and shares three base styles")
	check(not b.start_label.visible and not b.finish_label.visible, "Tutorial labels hide when the board has no dark tiles")
	b.show_solution_hint(0, true)
	b.show_solution_hint(0, false)
	check(b.hint_start_label.position.y < b.hint_finish_label.position.y and b.hint_start_label.get_theme_color("font_color") == Color.WHITE and b.hint_finish_label.get_theme_color("font_outline_color") == Color.BLACK, "Shared start and finish tile stacks white outlined hint labels")
	b.configure({"width": 5, "height": 5, "tiles": all_light}, Color.WHITE)
	b.path = [6, 7, 8, 13, 18, 17, 16, 11, 6]
	b.refresh()
	b._begin(b.center(6))
	check(b.path.is_empty() and not b.dragging, "Clicking the crossed start tile clears the whole line")
	b.configure({"width": 5, "height": 5, "tiles": all_light}, Color.WHITE)
	b._begin(b.center(5))
	check(b.path == [5], "Mouse down starts a single-tile line")
	b._end()
	check(b.path.is_empty() and not b.dragging, "Releasing a single-tile line clears it")
	b._begin(b.center(5))
	b._trace(b.center(7))
	check(b.path == [5, 6, 7], "Fast drag samples intermediate cells")
	var marker_center := Vector2.ZERO
	for point in b.start_dot.polygon:
		marker_center += point
	marker_center /= b.start_dot.polygon.size()
	check(marker_center.is_equal_approx(b.center(5)), "Line circle stays on its starting tile as the line grows")
	check(b.line_tween != null and b.line_tween.is_running() and b.tile_tweens.has(7), "Line and flipped tiles start 0.2-second transitions")
	await create_timer(0.24).timeout
	check(b.line.points.size() == 3 and b.line.points[-1].is_equal_approx(b.center(7)), "Line reaches its destination after the transition")
	check(b.tile_visuals[7].is_equal_approx(PuzzleBoard.tile_color(1, Color.WHITE)), "Flipped tile reaches its new color after the transition")
	b._end()
	b._begin(b.center(6))
	check(b.path == [5, 6] and b.dragging, "Clicking an earlier visited tile rewinds to that move")
	b._end()
	b._begin(b.center(6))
	b._trace(b.center(7))
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
	var curved_route: Array = [0, 1, 2, 7, 12]
	b.path = [0]
	b.refresh()
	b.path = curved_route.duplicate()
	b.refresh(true)
	await create_timer(0.04).timeout
	check(line_follows_route(b, curved_route), "Growing line tracks around route corners")
	await create_timer(0.22).timeout
	b._begin(b.center(1))
	check(b.path == [0, 1], "Clicking a previous move begins a multi-segment rewind")
	await create_timer(0.04).timeout
	check(line_follows_route(b, curved_route), "Rewinding line retracts along its existing path")
	b.clear_path()
	check(b.line_tween != null and b.line_tween.is_running(), "Reset line retracts along the route")
	await create_timer(0.24).timeout
	check(b.line.points.is_empty() and b.tile_visuals[0].is_equal_approx(PuzzleBoard.tile_color(0, Color.WHITE)), "Reset finishes with no line and restored tiles")
	b._begin(b.center(0))
	b._trace(b.center(18))
	check(b.path == [0, 1, 6, 7, 12, 13, 18], "Distant drag alternates horizontal and vertical moves toward the cursor")
	check(b.line_tween != null and b.line_tween.is_running(), "Distant drag animates along its full route")
	b._end()
	b.path = crossing.duplicate()
	b.refresh()
	b._begin(b.center(7))
	b._trace(b.center(13))
	check(b.path == crossing.slice(0, 7), "Blocked preferred direction falls back to the other direction and backtracks")
	b._end()
	var small_blank: Array = []
	small_blank.resize(9)
	small_blank.fill(0)
	b.configure({"width": 3, "height": 3, "tiles": small_blank}, Color.WHITE)
	var blocked_route: Array = [0, 1, 4, 5, 8, 7, 6, 3]
	b.path = blocked_route.duplicate()
	b.refresh()
	b._begin(b.center(3))
	b._trace(b.center(5))
	check(b.path == blocked_route, "Distant drag stops when both directions toward the cursor are blocked")
	b._end()
	main._toggle_editor()
	await process_frame
	check(main.screen == "editor", "Editor opens")
	var original: Dictionary = main.editor_data.duplicate(true)
	main._copy_editor_layout()
	main.editor_number_input.value = 2
	var destination: Dictionary = main.editor_data.duplicate(true)
	check(main.editor_level == 2 and destination != original, "Changing the editor level number loads that layout")
	main._paste_editor_layout()
	check(main.editor_data == original and main.undo_stack.size() == 1, "Paste copies dimensions and tiles to the selected level as one edit")
	main._editor_undo()
	check(main.editor_data == destination, "Undo restores the destination layout before paste")
	main._editor_redo()
	check(main.editor_data == original, "Redo restores the pasted layout")
	main.editor_number_input.value = 1
	check(main.editor_data == original and main.undo_stack.is_empty(), "Selecting another level loads it and resets level-specific history")
	var before_shift: Dictionary = main.editor_data.duplicate(true)
	var shift_fixture := {"width": 4, "height": 3, "tiles": [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]}
	main.editor_data = shift_fixture.duplicate(true)
	main._sync_editor()
	for direction in [
		[KEY_RIGHT, [0, 0, 1, 2, 1, 1, 2, 0, 2, 2, 0, 1]],
		[KEY_LEFT, [1, 2, 0, 0, 2, 0, 1, 1, 0, 1, 2, 2]],
		[KEY_UP, [1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0]],
		[KEY_DOWN, [2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1]]
	]:
		key(main, direction[0], true)
		key(main, direction[0], false)
		check(main.editor_data.tiles == direction[1] and main.undo_stack.size() == 1, "Arrow key shifts tiles one cell with wraparound")
		main._editor_undo()
		check(main.editor_data.tiles == shift_fixture.tiles, "Undo restores the tile shift")
		main._editor_redo()
		check(main.editor_data.tiles == direction[1], "Redo reapplies the tile shift")
		main._editor_undo()
	main.editor_data = before_shift
	main.undo_stack.clear()
	main.redo_stack.clear()
	main._sync_editor()
	var dark_cell: int = original.tiles.find(1)
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	right_press.position = main.board.center(dark_cell)
	main.board._gui_input(right_press)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.position = right_press.position
	main.board._gui_input(right_release)
	check(main.editor_data.tiles[dark_cell] == 0 and main.undo_stack.size() == 1, "Right click paints a tile light as one undoable stroke")
	main._editor_undo()
	check(main.editor_data == original, "Undo restores a right-clicked tile")
	main._editor_redo()
	check(main.editor_data.tiles[dark_cell] == 0, "Redo restores right-click light paint")
	main._editor_undo()
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
	var layouts_before_insert: Dictionary = main.store.levels.duplicate(true)
	main._insert_editor_level()
	check(main.store.levels.has("1") and main.store.get_level(1).tiles == main.editor_data.tiles and main.current_level == 2, "Editor inserts its current design and shifts the active level")
	main._editor_undo()
	check(main.store.levels == layouts_before_insert and main.current_level == 1, "Undo restores levels before insertion")
	main._editor_redo()
	check(main.store.levels.has("1"), "Redo restores inserted level")
	main._delete_editor_level()
	check(main.store.levels == layouts_before_insert and main.current_level == 1, "Editor deletion removes the saved level and restores numbering")
	main._editor_undo()
	check(main.store.levels.has("1") and main.current_level == 2, "Undo restores deleted level")
	main._editor_redo()
	check(main.store.levels == layouts_before_insert and main.current_level == 1, "Redo deletes the level again")
	var before_white_reset: Array = main.editor_data.tiles.duplicate()
	main._reset_all_white()
	check(not main.editor_data.tiles.has(1) and not main.editor_data.tiles.has(2), "Reset all to white clears dark and gray tiles")
	main._editor_undo()
	check(main.editor_data.tiles == before_white_reset, "White reset can be undone")
	main._editor_redo()
	check(not main.editor_data.tiles.has(1) and not main.editor_data.tiles.has(2), "White reset can be redone")
	var before_generated: Dictionary = main.editor_data.duplicate(true)
	var saved_before_generation: Dictionary = main.store.levels.duplicate(true)
	var history_before_generation: int = main.undo_stack.size()
	main.crossover_input.value = 0
	main.move_input.value = int(main.editor_data.width) * int(main.editor_data.height) + 1
	main._generate_editor_level()
	check(main.editor_data == before_generated and main.undo_stack.size() == history_before_generation and main.editor_message.text.contains("larger grid"), "Impossible editor move counts preserve the draft and undo history")
	main.move_input.value = 7
	main._generate_editor_level()
	check(main.editor_data.width == before_generated.width and main.editor_data.height == before_generated.height and main.editor_data.tiles.has(1), "Generate fills the editor at its current dimensions")
	check(main.undo_stack.size() == history_before_generation + 1 and main.store.levels == saved_before_generation, "Generated editor layout is one unsaved undoable edit")
	check(main.editor_message.text.contains("Generated 7 moves with exactly 0 crossovers"), "Editor uses and reports the chosen move and exact crossover count")
	main._editor_undo()
	check(main.editor_data == before_generated, "Undo restores the editor layout before generation")
	main._editor_redo()
	check(main.editor_data.tiles.has(1), "Redo restores the generated layout")
	main._editor_undo()
	main.crossover_input.value = 3
	main.move_input.value = 2
	main._generate_editor_level()
	check(main.editor_data == before_generated and main.editor_message.text.contains("Too many crossovers"), "Impossible exact crossover request leaves the editor draft unchanged")
	main.crossover_input.value = 0
	main.move_input.value = 7
	main.editor_data = {"width": 3, "height": 3, "tiles": [1, 1, 0, 0, 0, 0, 0, 0, 0]}
	main._sync_editor()
	var before_playtest: Dictionary = main.editor_data.duplicate(true)
	var before_playtest_history: int = main.undo_stack.size()
	key(main, KEY_SPACE, true)
	check(main.editor_playtesting and not main.board.editing and not main.width_input.editable and not main.move_input.editable and not main.crossover_input.editable, "Space starts editor playtest and disables building controls")
	key(main, KEY_SPACE, false)
	key(main, KEY_LEFT, true)
	key(main, KEY_LEFT, false)
	check(main.editor_data == before_playtest and main.undo_stack.size() == before_playtest_history, "Arrow keys leave the draft unchanged during playtest")
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(1))
	check(main.board.locked and main.screen == "editor" and main.store.completed.is_empty(), "Playtest solve stays in editor without saving progress")
	check(main.editor_mode_hint.text.begins_with("SOLVED"), "Playtest completion is visible in the editor header")
	check(main.store.has_solution(main.editor_level) and main.store.hint_endpoints(main.editor_level) == [0, 1], "Editor playtest records solution endpoints without completing the level")
	var editor_solution_reload := LevelStore.new()
	check(editor_solution_reload.hint_endpoints(main.editor_level) == [0, 1], "Editor solution endpoints survive reload")
	key(main, KEY_SPACE, true)
	check(not main.editor_playtesting and main.board.editing and main.board.path.is_empty(), "Space returns to building and clears test line")
	check(main.editor_data == before_playtest and main.board.tiles == before_playtest.tiles and main.undo_stack.size() == before_playtest_history, "Playtest preserves unsaved layout and undo history")
	main._paint_value(2, 1)
	main._save_editor()
	check(not main.store.has_solution(main.editor_level), "Saving an edited level forgets its recorded solution")
	key(main, KEY_SPACE, false)
	var history_size: int = main.undo_stack.size()
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_I, true, false, true)
	check(main.color_mode, "Shift+Z+I opens color mode")
	check(main.color_preview.path == [0, 1, 2] and Puzzle.resolved_tiles(main.color_preview.tiles, main.color_preview.path) == [0, 1, 0], "Color editor previews a line crossing light and dark tiles")
	main._select_color_target(true)
	var preview_line := Color("f2c53d")
	main._color_picker_changed(preview_line)
	check(main.line_custom_draft and main.color_preview.line.default_color.is_equal_approx(preview_line) and main.board.line.default_color.is_equal_approx(preview_line), "Picking a line color updates the preview and active board")
	main._save_color_selection()
	check(main.store.get_line_color(main.color_level).is_equal_approx(preview_line), "Color selector saves the manual line color for its area")
	main._copy_area_colors()
	check(not main.color_paste_button.disabled, "Copy colors enables paste")
	var copied_tile_hue: float = main.color_draft.h
	main._load_color_drafts(21)
	main._paste_area_colors()
	check(main.line_custom_draft and main.line_draft.is_equal_approx(preview_line) and is_equal_approx(main.color_draft.h, copied_tile_hue), "Paste restores both colors in another area")
	main._save_color_selection()
	check(main.store.get_line_color(21).is_equal_approx(preview_line) and absf(main.store.get_color(21).h - copied_tile_hue) < 0.005, "Pasted color scheme saves for the destination area")
	main._load_color_drafts(8)
	main._reset_line_draft()
	check(not main.line_custom_draft and main.color_preview.line.default_color.is_equal_approx(LevelStore.DEFAULT_LINE_COLOR), "Saved area-six color is the suggested default")
	main._save_color_selection()
	check(not main.store.line_colors.has(str(LevelStore.group_start(main.color_level))), "Suggested line color removes the area override")
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
	var custom := {"width": 3, "height": 3, "tiles": [1, 1, 2, 0, 0, 2, 0, 0, 0]}
	check(main.store.save_level(2, custom) == OK, "Custom level save succeeds")
	var custom_hue := Color("e7b4df")
	check(main.store.save_color(2, custom_hue) == OK, "Custom color save succeeds")
	var custom_line := Color("f2c53d")
	check(main.store.save_line_color(2, custom_line) == OK, "Custom line color save succeeds")
	for member in range(1, 6):
		check(is_equal_approx(main.store.get_color(member).h, custom_hue.h), "Edited color applies to all five levels")
		check(main.store.get_line_color(member).is_equal_approx(custom_line), "Edited line color applies to all five levels")
	check(main.store.save_color(7, Color("477fdb")) == OK, "Second color group saves")
	for member in range(6, 11):
		check(main.store.get_color(member) == main.store.get_color(6), "Second group shares its color")
	check(absf(main.store.get_color(6).h - Color("477fdb").h) < 0.005, "Saved color preserves the chosen hue")
	check(main.store.get_color(11) == Puzzle.palette(11), "Adjacent group stays independent")
	check(main.store.get_line_color(11).is_equal_approx(LevelStore.DEFAULT_LINE_COLOR), "Unedited areas use the saved area-six line color")
	check(main.store.mark_complete(1) == OK, "Progress save succeeds")
	check(main.store.credits == 1 and main.store.mark_complete(1) == OK and main.store.credits == 1, "A level awards exactly one credit, even when replayed")
	var reloaded := LevelStore.new()
	check(reloaded.credits == 1, "Earned credits survive reload")
	check(reloaded.get_level(2).tiles == custom.tiles, "Custom level survives reload")
	check(is_equal_approx(reloaded.get_color(5).h, custom_hue.h) and reloaded.get_color(5).s > 0.99, "Group color survives reload fully saturated")
	check(reloaded.get_line_color(5).is_equal_approx(custom_line), "Group line color survives reload")
	var legacy_color_path := "res://.test-user/legacy_colors.json"
	check(LevelStore._atomic_write(legacy_color_path, {"colors": {"4": "e7b4df"}}) == OK, "Legacy color fixture saved")
	var legacy_store := LevelStore.new()
	legacy_store.colors.clear()
	legacy_store._load_levels(legacy_color_path)
	check(is_equal_approx(legacy_store.get_color(1).h, custom_hue.h) and is_equal_approx(legacy_store.get_color(5).h, custom_hue.h), "Old per-level color applies to its group")
	check(reloaded.frontier() == 2 and reloaded.menu_unlocked() == 5 and reloaded.menu_levels() == [1, 2, 3, 4, 5], "The first five levels are available before three completions")
	main.play_level(2)
	await process_frame
	check(main.board.line.default_color.is_equal_approx(custom_line), "Saved line color appears in gameplay")
	main.board._begin(main.board.center(0))
	check(not main.board.locked and not main.store.completed.get("2", false), "One tile cannot trigger completion")
	main.board._trace(main.board.center(1))
	check(main.board.locked, "Solving locks input during celebration")
	check(main.store.completed.get("2", false), "Solving marks completed")
	check(main.store.credits == 2 and main.credit_label.text == "2", "A newly completed level awards a visible credit")
	check(is_instance_valid(main.completed_badge) and main.completed_badge.is_visible_in_tree() and main.completed_badge.size == Vector2(72, 72) and main.completed_badge.position.x > main.size.x - 120, "Solving shows a large completion badge at the top right")
	var celebration_text: Array = main.find_children("", "Label", true, false).map(func(node): return node.text)
	check("Level 2 complete!" in celebration_text and celebration_text.any(func(line): return line.ends_with("!") and (line.trim_suffix("!") + ".") in CelebrationLines.LINES), "Celebration chooses a short exclamation")
	var praise_labels: Array = main.find_children("", "Label", true, false).filter(func(node): return node.text.ends_with("!") and (node.text.trim_suffix("!") + ".") in CelebrationLines.LINES)
	check(praise_labels.size() == 1 and praise_labels[0].get_theme_color("font_color").is_equal_approx(PuzzleBoard.tile_color(0, main.store.get_color(2))), "Celebration subtext matches the light tile color")
	check(not "Take a breath. Your next puzzle is on its way." in celebration_text, "Celebration has no bottom sentence")
	await create_timer(2.7).timeout
	check(main.current_level == 3, "Celebration automatically advances")
	check(main.completed_badge == null, "An unfinished next puzzle has no completion badge")
	check(main.hint_button != null and main.hint_button.text == "Hint (-1 coin)" and main.hint_button.focus_mode == Control.FOCUS_NONE and not main.hint_button.disabled, "Hint shows its price and does not take Space key focus")
	main.hint_button.pressed.emit()
	check(main.store.credits == 1 and main.store.hint_stage(3) == 1 and main.hint_button.disabled and main.hint_busy, "Buying the first hint saves its reveal and blocks repeat clicks during animation")
	await create_timer(0.75).timeout
	check(main.board.hint_start_label.visible and main.board.hint_start_label.text == "Start" and main.board.hint_start_cell == main.hint_endpoints[0] and not main.hint_button.disabled, "The first purchased hint reveals the solution start")
	main.play_level(4)
	main.play_level(3)
	check(main.board.hint_start_label.visible and not main.board.hint_finish_label.visible and main.hint_row.visible and main.store.credits == 1, "The first hint remains on its level after navigating away and back")
	main.hint_button.pressed.emit()
	check(main.store.credits == 0 and main.store.hint_stage(3) == 2 and main.hint_button.disabled and main.hint_busy, "Buying the second hint saves its reveal and spends one more credit")
	await create_timer(0.75).timeout
	check(main.board.hint_finish_label.visible and main.board.hint_finish_label.text == "Finish" and main.board.hint_finish_cell == main.hint_endpoints[1] and not main.hint_row.visible, "The second hint reveals the finish and removes the Hint button")
	main.play_level(4)
	main.play_level(3)
	check(main.board.hint_start_label.visible and main.board.hint_finish_label.visible and not main.hint_row.visible and main.store.credits == 0, "Both hints remain visible and the button stays gone after revisiting")
	var hint_reload := LevelStore.new()
	check(hint_reload.hint_stage(3) == 2 and hint_reload.credits == 0, "Purchased hints and spent credits survive reload")
	main.play_level(2)
	await process_frame
	check(is_instance_valid(main.completed_badge) and main.completed_badge.is_visible_in_tree(), "Reopening a completed puzzle restores its badge")
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(1))
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_O, true, false, true)
	check(main.screen == "editor" and main.editor_level == 2, "Editor shortcut opens the active level during celebration")
	key(main, KEY_O, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	await create_timer(2.7).timeout
	check(main.screen == "editor" and main.current_level == 2, "Opening editor cancels pending level advance")
	main._toggle_editor()
	check(main.screen == "play" and main.board.path.is_empty(), "Closing editor restarts completed level cleanly")
	main.play_level(5)
	main.play_level(6)
	check(main.background_tween != null and main.background_tween.is_running(), "Changing five-level sets starts a fade")
	check(main.transition_old_shell.theme != main.active_shell.theme, "Moving screens keep independent palettes")
	check(main.background_rect.color == PuzzleBoard.background_color(main.store.get_color(5)), "Set transition begins with previous background")
	check(main.transition_old_shell.theme.get_color("font_color", "Label") == PuzzleBoard.text_color(main.store.get_color(5)), "Outgoing screen keeps its previous text color")
	await create_timer(0.08).timeout
	check(main.palette_theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(6))) and main.transition_old_shell.theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(5))), "Screen motion preserves both palettes without per-frame theme changes")
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(6))), "Set transition reaches the new background")
	check((main.board_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(main.background_rect.color), "Board and whole screen fade together")
	check(main.palette_theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(6))), "Text reaches the next adjacent color")
	check((main.palette_theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color.is_equal_approx(PuzzleBoard.button_color(main.store.get_color(6))), "Buttons reach the next adjacent color")
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_RIGHT, true, false, true)
	check(main.current_level == 7, "Shift+Z+Right opens the next level")
	key(main, KEY_RIGHT, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_LEFT, true, false, true)
	check(main.current_level == 6, "Shift+Z+Left opens the previous level")
	key(main, KEY_LEFT, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	main.show_menu()
	await process_frame
	check(main.screen == "menu", "Menu rebuilds completed screenshots")
	for number in range(3, 6):
		main.store.completed[str(number)] = true
	main.show_menu()
	await process_frame
	check(main.background_rect.color == PuzzleBoard.menu_background_color(main.store.get_color(6)), "Menu defaults to the current unsolved level's main hue")
	check(main.palette_text.is_equal_approx(PuzzleBoard.menu_text_color(main.store.get_color(6))) and main.palette_button.is_equal_approx(PuzzleBoard.menu_button_color(main.store.get_color(6))), "Menu text and buttons use the selected level's main hue")
	var level_cards: Array[Button] = main.menu_cards.duplicate()
	check(level_cards.size() == 10 and (main.menu_hint.get_child(0) as Label).text == "?" and main.menu_rows.get_child(0).get_child(10) == main.menu_hint, "The next locked group is hinted after the unlocked cards")
	var hint_style := main.menu_hint.get_theme_stylebox("panel") as StyleBoxFlat
	check(hint_style.border_width_left == 2 and hint_style.border_color == main.LOCKED_HINT_OUTLINE and main.menu_hint.mouse_filter == Control.MOUSE_FILTER_STOP, "Locked group hint has a red outline and accepts clicks")
	main.menu_hint.mouse_entered.emit()
	await create_timer(0.08).timeout
	check(main.menu_hint.scale.x > 1.02, "Locked group hint grows on hover")
	main.menu_hint.mouse_exited.emit()
	await create_timer(0.18).timeout
	check(main.menu_hint.scale.is_equal_approx(Vector2.ONE), "Locked group hint shrinks after hover")
	var hint_click := InputEventMouseButton.new()
	hint_click.button_index = MOUSE_BUTTON_LEFT
	hint_click.pressed = true
	main.menu_hint.gui_input.emit(hint_click)
	await create_timer(0.06).timeout
	check(main.screen == "menu" and main.position.length() > 0.0, "Clicking the locked group hint shakes the menu without opening a puzzle")
	var first_shake_offsets: Array = main.screen_shake_offsets.duplicate()
	check(first_shake_offsets.size() >= 8 and first_shake_offsets.all(func(offset): return offset.length() > 0.0), "Screen shake uses several nonzero movements")
	await create_timer(0.25).timeout
	check(main.position == Vector2.ZERO, "The screen shake returns the menu to its original position")
	main.menu_hint.gui_input.emit(hint_click)
	check(main.screen_shake_offsets != first_shake_offsets, "Each locked card click gets a new shake pattern")
	await create_timer(0.32).timeout
	check(main.position == Vector2.ZERO, "A second screen shake also returns to its original position")
	check(not level_cards.is_empty() and level_cards[0].size == Vector2(64, 64), "Menu level cards are 64 by 64")
	check(level_cards.all(func(node): return node.tooltip_text.is_empty()), "Level cards do not show hover popups")
	check(main.menu_rows.get_child_count() == 1 and (main.menu_rows.get_child(0) as HBoxContainer).alignment == BoxContainer.ALIGNMENT_BEGIN, "Menu rows align their cards from the left")
	check(main.content.get_child(0) is HBoxContainer and main.credit_label.text == str(main.store.credits), "Credits replace Play beside the menu title")
	check((main.content.get_child(0) as HBoxContainer).get_child(0).text == "H e a r t h l i n e", "Cozy menu title has spaced letters")
	check((main.content.get_child(0) as HBoxContainer).get_child(2) == main.credit_display, "Menu credit display sits at the top right")
	var thumbnail: TextureRect = level_cards[0].get_children().filter(func(node): return node is TextureRect)[0]
	check(thumbnail.position == Vector2.ZERO and thumbnail.size == Vector2(64, 64), "Screenshot fills the whole menu button")
	check(level_cards.all(func(card): return card.get_children().all(func(node): return not node is Label)), "Menu cards have no numbers or checkmarks")
	check(thumbnail.modulate == Color.WHITE and not level_cards[0].has_theme_stylebox_override("normal"), "Completed cards keep their original puzzle preview colors")
	var card_outline: Panel = level_cards[2].get_children().filter(func(node): return node is Panel)[0]
	var outline_style: StyleBoxFlat = card_outline.get_theme_stylebox("panel")
	check(outline_style.border_width_left == 2 and outline_style.corner_radius_top_left > 0 and outline_style.border_color == main.COMPLETED_CARD_OUTLINE, "Completed cards with a solution have a rounded green outline")
	var unfinished_outline: Panel = level_cards[5].get_children().filter(func(node): return node is Panel)[0]
	check((unfinished_outline.get_theme_stylebox("panel") as StyleBoxFlat).border_color == Color("eae345"), "Uncompleted level cards have yellow outlines")
	var unknown_outline: Panel = level_cards[1].get_children().filter(func(node): return node is Panel)[0]
	check((unknown_outline.get_theme_stylebox("panel") as StyleBoxFlat).border_color == main.NO_SOLUTION_OUTLINE, "Saved levels without a solution are red in the menu")
	level_cards[0].mouse_entered.emit()
	check(main.background_tween != null and main.background_tween.is_running(), "Menu hover starts a fade")
	check(level_cards[0].has_meta("hover_tween") and (level_cards[0].get_meta("hover_tween") as Tween).is_running(), "Menu hover starts the card growth animation")
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.menu_background_color(main.store.get_color(1))), "Menu background follows hovered level's main hue")
	check(main.palette_text.is_equal_approx(PuzzleBoard.menu_text_color(main.store.get_color(1))) and main.palette_button.is_equal_approx(PuzzleBoard.menu_button_color(main.store.get_color(1))), "Menu controls follow the hovered level's main hue")
	level_cards[0].mouse_exited.emit()
	await create_timer(0.38).timeout
	check(level_cards[0].scale.is_equal_approx(Vector2.ONE), "A level card shrinks after hover")
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.menu_background_color(main.store.get_color(1))) and main.menu_hovered_level == 1, "Menu retains the last hovered level palette")
	level_cards[5].mouse_entered.emit()
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.menu_background_color(main.store.get_color(6))) and main.menu_hovered_level == 6, "Hovering another level replaces the held palette")
	level_cards[5].mouse_exited.emit()
	check(main.menu_hovered_level == 6, "Leaving the next card also keeps its palette")
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_U, true, false, true)
	await process_frame
	check(main.rearrange_mode and main.menu_cards[0].get("rearranging"), "Shift+Z+U enables draggable menu cards")
	var first_slot: Vector2 = main.menu_cards[0].global_position
	var third_slot: Vector2 = main.menu_cards[2].global_position
	var drag_press := InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_LEFT
	drag_press.pressed = true
	main.menu_cards[0].gui_input.emit(drag_press)
	check(main.menu_drag_source == 1, "Pressing a rearrange card starts the menu drag")
	main._start_menu_drag(1, first_slot + Vector2(32, 32))
	main._update_menu_drag(third_slot + Vector2(8, 32))
	check(main.menu_dragging and main.menu_drag_target == 3 and is_instance_valid(main.menu_drag_icon), "Dragging previews insertion between levels")
	await create_timer(0.20).timeout
	check(main.menu_cards[1].global_position.distance_to(first_slot) < 1.0, "Insert preview animates shifted cards into the gap")
	main._cancel_menu_drag()
	main.rearrange_action = "swap"
	main._start_menu_drag(1, first_slot + Vector2(32, 32))
	main._update_menu_drag(third_slot + Vector2(32, 32))
	await create_timer(0.20).timeout
	check(main.menu_drag_target == 3 and main.menu_cards[2].global_position.distance_to(first_slot) < 1.0, "Swap preview animates the target into the dragged slot")
	var drag_release := InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_LEFT
	drag_release.position = Vector2(-100, -100)
	main._input(drag_release)
	check(main.menu_drag_source == 0 and not main.menu_dragging, "Releasing outside the selector cancels the drag")
	main.rearrange_action = "insert"
	key(main, KEY_U, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_U, true, false, true)
	check(not main.rearrange_mode and not main.menu_cards[0].get("rearranging"), "Shift+Z+U returns to level selection")
	key(main, KEY_U, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	main._toggle_rearrange()
	await process_frame
	main._start_menu_drag(1, main.menu_cards[0].global_position + Vector2(32, 32))
	main._update_menu_drag(main.menu_cards[2].global_position + Vector2(8, 32))
	key(main, KEY_ESCAPE, true)
	check(main.screen == "menu" and not main.rearrange_mode and main.menu_drag_source == 0 and not is_instance_valid(main.menu_drag_icon), "Escape closes rearrange mode and cancels its drag")
	key(main, KEY_ESCAPE, false)
	level_cards = main.menu_cards.duplicate()
	level_cards[0].mouse_entered.emit()
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_O, true, false, true)
	check(main.screen == "editor" and main.editor_level == 1, "Menu shortcut opens the hovered level")
	key(main, KEY_O, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_RIGHT, true, false, true)
	check(main.screen == "editor" and main.editor_level == 2 and main.editor_number_input.value == 2, "Shift+Z+Right loads the next editor level")
	key(main, KEY_RIGHT, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_LEFT, true, false, true)
	check(main.editor_level == 1 and main.editor_number_input.value == 1, "Shift+Z+Left loads the previous editor level")
	key(main, KEY_LEFT, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	main._toggle_editor_playtest()
	check(main.editor_playtesting, "Editor playtest starts before Escape")
	key(main, KEY_ESCAPE, true)
	check(main.screen == "menu" and not main.rearrange_mode and not main.color_mode and not main.editor_playtesting, "Escape leaves the editor for a normal menu")
	key(main, KEY_ESCAPE, false)
	main._toggle_color_editor()
	check(main.color_mode, "Menu color overlay opens")
	key(main, KEY_ESCAPE, true)
	check(main.screen == "menu" and not main.color_mode and not is_instance_valid(main.overlay), "Escape closes the color overlay")
	key(main, KEY_ESCAPE, false)
	main.menu_cards[0].mouse_entered.emit()
	await create_timer(0.38).timeout
	main.play_level(1)
	check(main.background_tween != null and main.background_tween.is_running() and main.background_rect.color.is_equal_approx(PuzzleBoard.menu_background_color(main.store.get_color(1))), "Opening a level fades from its menu hue")
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(1))), "Opening a level reaches the play background hue")
	key(main, KEY_ESCAPE, true)
	check(main.screen == "menu" and not main.rearrange_mode and not main.color_mode, "Escape leaves play for the main menu")
	key(main, KEY_ESCAPE, false)
	var shifted_store := LevelStore.new()
	shifted_store.mirror_project = false
	shifted_store.levels.clear()
	shifted_store.completed.clear()
	var first_layout := {"width": 3, "height": 3, "tiles": [1, 0, 0, 0, 0, 0, 0, 0, 0]}
	var next_layout := {"width": 3, "height": 3, "tiles": [0, 1, 0, 0, 0, 0, 0, 0, 0]}
	var later_layout := {"width": 3, "height": 3, "tiles": [0, 0, 1, 0, 0, 0, 0, 0, 0]}
	check(shifted_store.save_level(4, first_layout) == OK and shifted_store.save_level(6, next_layout) == OK and shifted_store.save_level(9, later_layout) == OK, "Sparse custom level fixtures save")
	check(shifted_store.mark_complete(4) == OK and shifted_store.mark_complete(6) == OK, "Completed level fixtures save")
	shifted_store.hints = {"6": 1}
	check(shifted_store.insert_level(6, first_layout) == OK, "Insert persists a new custom level")
	check(shifted_store.hint_stage(7) == 1 and shifted_store.hint_stage(6) == 0, "Insertion moves purchased hints with their puzzle")
	check(shifted_store.get_level(6).tiles == first_layout.tiles and shifted_store.get_level(7).tiles == next_layout.tiles and shifted_store.get_level(10).tiles == later_layout.tiles, "Insertion shifts all later sparse custom levels up")
	check(not shifted_store.completed.has("6") and shifted_store.completed.has("7"), "Insertion shifts completion records with level numbers")
	var shifted_reload := LevelStore.new()
	check(shifted_reload.get_level(7).tiles == next_layout.tiles and shifted_reload.get_level(10).tiles == later_layout.tiles, "Inserted level numbering survives reload")
	check(shifted_store.delete_level(6) == OK, "Delete persists a saved custom level removal")
	check(shifted_store.hint_stage(6) == 1 and shifted_store.hint_stage(7) == 0, "Deletion moves purchased hints back with their puzzle")
	check(shifted_store.get_level(6).tiles == next_layout.tiles and shifted_store.get_level(9).tiles == later_layout.tiles and not shifted_store.levels.has("10"), "Deletion shifts later custom levels down")
	check(shifted_store.completed.has("6") and not shifted_store.completed.has("7"), "Deletion shifts completion records back")
	check(shifted_store.delete_level(5) == ERR_DOES_NOT_EXIST, "Generated levels cannot be deleted as custom levels")
	var reorder_store := LevelStore.new()
	reorder_store.mirror_project = false
	reorder_store.levels.clear()
	reorder_store.completed.clear()
	reorder_store.unlocked_through = 0
	check(reorder_store.save_level(2, first_layout) == OK and reorder_store.complete_first(3) == OK, "Rearrange fixtures save")
	reorder_store.hints = {"1": 1, "3": 2}
	var original_one := reorder_store.get_level(1)
	var original_three := reorder_store.get_level(3)
	check(reorder_store.rearrange_level(1, 3, "insert", true) == OK, "Insert moves a dragged level after the target")
	check(reorder_store.get_level(1).tiles == first_layout.tiles and reorder_store.get_level(2).tiles == original_three.tiles and reorder_store.get_level(3).tiles == original_one.tiles, "Insert shifts puzzles into their new slots")
	check(reorder_store.rearrange_level(2, 4, "swap") == OK, "Swap exchanges the dragged and target levels")
	check(reorder_store.get_level(4).tiles == original_three.tiles and not reorder_store.completed.has("2") and reorder_store.completed.has("4") and reorder_store.menu_unlocked() == 10, "Swap carries completion and preserves unlocked groups")
	check(reorder_store.rearrange_level(4, 1, "insert", false) == OK and reorder_store.get_level(1).tiles == original_three.tiles, "Insert also moves a dragged level before the target")
	check(reorder_store.hint_stage(1) == 2 and reorder_store.hint_stage(4) == 1, "Rearranging keeps purchased hints with their puzzles")
	check(reorder_store.rearrange_level(1, 1, "swap") == ERR_INVALID_PARAMETER, "Dropping a level on itself leaves the order alone")
	var reorder_reload := LevelStore.new()
	check(reorder_reload.get_level(1).tiles == original_three.tiles and reorder_reload.menu_unlocked() == 10 and reorder_reload.hint_stage(1) == 2, "Rearranged puzzles, hints, and unlock range survive reload")
	var unlock_store := LevelStore.new()
	unlock_store.completed.clear()
	unlock_store.unlocked_through = 0
	check(unlock_store.menu_unlocked() == 5 and unlock_store.menu_levels() == [1, 2, 3, 4, 5], "Five levels are available at the start")
	unlock_store.completed = {"1": true, "3": true}
	check(unlock_store.menu_unlocked() == 5, "Two completions keep the next group locked")
	unlock_store.completed["5"] = true
	check(unlock_store.menu_unlocked() == 10 and unlock_store.menu_levels() == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "Any three completions unlock the next group of five")
	unlock_store.completed["6"] = true
	unlock_store.completed["8"] = true
	check(unlock_store.menu_unlocked() == 10, "The next group still needs three completions")
	unlock_store.completed["10"] = true
	check(unlock_store.menu_unlocked() == 15, "Three completions in the second group unlock another five")
	check(unlock_store.adjacent_uncompleted(15, 1) == 2 and unlock_store.adjacent_uncompleted(2, -1) == 15 and unlock_store.adjacent_uncompleted(5, 1) == 7, "Puzzle navigation skips completed levels and wraps within unlocked groups")
	check(unlock_store.adjacent_level(15, 1) == 1 and unlock_store.adjacent_level(1, -1) == 15 and unlock_store.adjacent_level(5, 1) == 6, "Adjacent navigation includes completed levels and wraps within unlocked groups")
	unlock_store.unlocked_through = 15
	unlock_store.completed = {"1": true}
	check(unlock_store.menu_unlocked() == 15, "A group stays available after its completion records move")
	main.show_menu()
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_M, true, false, true)
	check(main.store.frontier() == 100 and main.store.completed.has("99"), "Shift+Z+M completes and unlocks the first 99 levels")
	var menu_scroll := main.content.get_child(main.content.get_child_count() - 1) as ScrollContainer
	check(main.menu_cards.size() == 105 and main.menu_columns <= 15 and main.menu_rows.get_child_count() == ceili(106.0 / main.menu_columns) and (main.menu_rows.get_child(0) as HBoxContainer).alignment == BoxContainer.ALIGNMENT_BEGIN and menu_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_ALWAYS, "Menu shows every unlocked group in one scrollable grid")
	check(main.credit_label.text == str(main.store.credits), "Unlock shortcut refreshes the menu credits")
	key(main, KEY_M, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_B, true, false, true)
	main.menu_cards[11].pressed.emit()
	check(main.screen == "menu" and main.store.completed.size() == 12 and main.store.frontier() == 13 and main.menu_cards.size() == 15, "Shift+Z+B click completes through the selected level and stays in the menu")
	check(not main.store.completed.has("99") and main.store.unlocked_through == 15, "Shift+Z+B click clears later completion and recalculates unlocked groups")
	main.menu_cards[4].pressed.emit()
	check(main.store.completed.size() == 5 and main.store.frontier() == 6 and main.menu_cards.size() == 10, "A second Shift+Z+B click replaces the completion cutoff")
	var click_reload := LevelStore.new()
	check(click_reload.completed.size() == 5 and click_reload.frontier() == 6 and click_reload.menu_unlocked() == 10, "Clicked completion cutoff survives reload")
	key(main, KEY_B, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	main.play_level(20)
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_N, true, false, true)
	check(main.store.frontier() == 2 and main.store.completed.size() == 1 and main.store.completed.has("1"), "Shift+Z+N clears completion except level 1")
	check(main.screen == "menu" and main.menu_cards.size() == 5 and main.credit_label.text == "1", "Reset shortcut restores the first unlocked group and one credit")
	key(main, KEY_N, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	var progress_reload := LevelStore.new()
	check(progress_reload.frontier() == 2, "Reset completion survives reload")
	main.store.completed = {"1": true, "3": true, "4": true, "7": true}
	main.show_menu()
	var shown_numbers: Array = main.menu_cards.map(func(card): return int(card.get("level_number")))
	check(shown_numbers == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "Menu includes every level in unlocked groups across completion gaps")
	check(main.credit_label.text == str(main.store.credits), "Menu rebuild preserves the credit display")
	main._toggle_rearrange()
	await process_frame
	main._start_menu_drag(4, main.menu_cards[3].global_position + Vector2(32, 32))
	main._update_menu_drag(main.menu_cards[6].global_position + Vector2(32, 32))
	check(main.menu_drag_source == 4 and main.menu_drag_target == 7, "Rearrange preview reaches later levels in an unlocked group")
	main._cancel_menu_drag()
	check(main.store.rearrange_level(7, 2, "swap") == OK, "Unfinished and completed levels can be rearranged")
	main.show_menu()
	shown_numbers = main.menu_cards.map(func(card): return int(card.get("level_number")))
	check(shown_numbers == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "Rearranging keeps the unlocked groups visible")
	main.play_level(10)
	play_controls = main.content.get_child(2) as HBoxContainer
	(play_controls.get_child(4) as Button).pressed.emit()
	check(main.current_level == 10 and main.screen_shake_tween.is_running(), "Next puzzle at the last unlocked level shakes without wrapping")
	check(main.find_children("", "Label", true, false).any(func(node): return node.text == "Complete more puzzles..." and node.get_theme_color("font_outline_color") == Color.BLACK), "Locked next puzzle shows outlined floating feedback")
	play_controls = main.content.get_child(2) as HBoxContainer
	(play_controls.get_child(2) as Button).pressed.emit()
	check(main.current_level == 9, "Previous puzzle button visits the adjacent level")
	print("%d checks, %d failures in %.2fs" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failures else 0)

func key(main: Control, code: Key, down: bool, ctrl: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	main._input(event)

func line_follows_route(board: PuzzleBoard, route: Array) -> bool:
	var visible: PackedVector2Array = board.line.points
	if visible.is_empty() or visible.size() > route.size():
		return false
	for index in range(visible.size() - 1):
		if not visible[index].is_equal_approx(board.center(route[index])):
			return false
	if visible.size() == 1:
		return true
	var start: Vector2 = board.center(route[visible.size() - 2])
	var finish: Vector2 = board.center(route[visible.size() - 1])
	var segment := finish - start
	var offset: Vector2 = visible[-1] - start
	return absf(segment.cross(offset)) < 0.1 and offset.dot(segment) >= -0.1 and offset.dot(segment) <= segment.length_squared() + 0.1
