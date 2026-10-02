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
	check(not Puzzle.is_complete(dark, crossing), "Cannot finish mid-crossing")
	check(not Puzzle.can_append([0, 1, 6, 7], 1, 5, 5), "Cannot cross a corner")
	check(not Puzzle.can_append([0, 1, 6, 5], 0, 5, 5), "Cannot revisit start")
	check(not Puzzle.can_append([4], 5, 5, 5), "No row wrapping")
	check(Puzzle.resolved_tiles([2, 1, 0], [0, 1, 2]) == [2, 0, 1], "Gray is invariant")
	var hue := Color.from_hsv(0.62, 0.25, 0.82)
	var light_color := PuzzleBoard.tile_color(0, hue)
	var dark_color := PuzzleBoard.tile_color(1, hue)
	var background := PuzzleBoard.background_color(hue)
	check(light_color.s <= 0.601 and dark_color.s <= 0.701, "Tile saturation stays within the soft palette")
	check(PuzzleBoard.luminance(light_color) > PuzzleBoard.luminance(dark_color) * 3.0, "Light and dark tiles stay visually distinct")
	check(is_equal_approx(light_color.h, dark_color.h), "Light and dark tiles share the base hue")
	check(is_equal_approx(background.s, 0.25) and background.v < 0.25, "Background is dark and softly tinted")
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
	main.store.levels.clear()
	main.store.colors.clear()
	main.store.line_colors.clear()
	# Check the whole hue wheel, including manually chosen colors.
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
				var fill: Color = main.theme.get_stylebox(state, kind).bg_color
				check((PuzzleBoard.luminance(ink) + 0.05) / (PuzzleBoard.luminance(fill) + 0.05) >= 4.5, "Button text stays readable across hues and interaction states")
		var primary_fill: Color = main.theme.get_stylebox("normal", "PrimaryButton").bg_color
		var secondary_fill: Color = main.theme.get_stylebox("normal", "Button").bg_color
		check(PuzzleBoard.luminance(primary_fill) > PuzzleBoard.luminance(secondary_fill) * 1.5, "Primary buttons stand out from secondary buttons")
	main._apply_ui_palette(main.store.get_color(1))
	main.play_level(1)
	await create_timer(0.35).timeout
	check(main.board != null, "Gameplay scene loaded")
	var phrases_seen := {}
	for phrase in CelebrationLines.LINES:
		phrases_seen[phrase] = true
	check(CelebrationLines.LINES.size() == 100 and phrases_seen.size() == 100, "Exactly 100 distinct celebration messages")
	check(main.find_children("", "Label", true, false).all(func(node): return node.text != "H e a r t h l i n e"), "Game title is hidden inside levels")
	check(main.content.get_child(0).text == "Level 1", "Level numbers have no leading zero")
	check(main.theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(1))), "Play text uses the first split-complementary hue")
	check((main.theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color.is_equal_approx(PuzzleBoard.button_color(main.store.get_color(1))), "Secondary buttons use the subdued split-complementary hue")
	check(main.theme.get_color("font_shadow_color", "Label").a > 0.0, "Text has a shadow")
	check(ProjectSettings.get_setting("display/window/size/mode") == 3, "Game starts fullscreen")
	check(main.content.get_child(2) is HBoxContainer and (main.content.get_child(2) as HBoxContainer).get_child_count() == 2, "Reset line is inline with All puzzles")
	check(main.background_rect.color == PuzzleBoard.background_color(main.store.get_color(1)), "Entire play screen uses the level background")
	check((main.board_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == main.background_rect.color, "Play area shares the same background")
	var b: PuzzleBoard = main.board
	check(b.line.default_color == PuzzleBoard.line_color(main.store.get_color(1)) and b.start_dot.color == b.line.default_color and b.line_group.modulate.a == 1.0, "Line and start marker use the opaque warm analogous color")
	check(b.line_shadow.default_color.a > 0.0 and b.line_shadow.position.y > 0.0, "Line has a raised shadow")
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
	var before_playtest: Dictionary = main.editor_data.duplicate(true)
	var before_playtest_history: int = main.undo_stack.size()
	key(main, KEY_SPACE, true)
	check(main.editor_playtesting and not main.board.editing and not main.width_input.editable, "Space starts editor playtest and disables building controls")
	key(main, KEY_SPACE, false)
	main.board.configure({"width": 3, "height": 3, "tiles": [1, 1, 0, 0, 0, 0, 0, 0, 0]}, Color.RED)
	main.board._begin(main.board.center(0))
	main.board._trace(main.board.center(1))
	check(main.board.locked and main.screen == "editor" and main.store.completed.is_empty(), "Playtest solve stays in editor without saving progress")
	check(main.editor_mode_hint.text.begins_with("SOLVED"), "Playtest completion is visible in the editor header")
	key(main, KEY_SPACE, true)
	check(not main.editor_playtesting and main.board.editing and main.board.path.is_empty(), "Space returns to building and clears test line")
	check(main.editor_data == before_playtest and main.board.tiles == before_playtest.tiles and main.undo_stack.size() == before_playtest_history, "Playtest preserves unsaved layout and undo history")
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
	check(not main.line_custom_draft and main.color_preview.line.default_color.is_equal_approx(PuzzleBoard.line_color(main.color_draft)), "Suggested line color can be restored")
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
	check(main.store.get_line_color(11).is_equal_approx(PuzzleBoard.line_color(main.store.get_color(11))), "Unedited areas use the warm analogous line color")
	check(main.store.mark_complete(1) == OK, "Progress save succeeds")
	var reloaded := LevelStore.new()
	check(reloaded.get_level(2).tiles == custom.tiles, "Custom level survives reload")
	check(is_equal_approx(reloaded.get_color(5).h, custom_hue.h) and reloaded.get_color(5).s > 0.99, "Group color survives reload fully saturated")
	check(reloaded.get_line_color(5).is_equal_approx(custom_line), "Group line color survives reload")
	var legacy_color_path := "res://.test-user/legacy_colors.json"
	check(LevelStore._atomic_write(legacy_color_path, {"colors": {"4": "e7b4df"}}) == OK, "Legacy color fixture saved")
	var legacy_store := LevelStore.new()
	legacy_store.colors.clear()
	legacy_store._load_levels(legacy_color_path)
	check(is_equal_approx(legacy_store.get_color(1).h, custom_hue.h) and is_equal_approx(legacy_store.get_color(5).h, custom_hue.h), "Old per-level color applies to its group")
	check(reloaded.frontier() == 2, "Only next unsolved level unlocks")
	main.play_level(2)
	await process_frame
	check(main.board.line.default_color.is_equal_approx(custom_line), "Saved line color appears in gameplay")
	main.board._begin(main.board.center(0))
	check(not main.board.locked and not main.store.completed.get("2", false), "One tile cannot trigger completion")
	main.board._trace(main.board.center(1))
	check(main.board.locked, "Solving locks input during celebration")
	check(main.store.completed.get("2", false), "Solving marks completed")
	var celebration_text: Array = main.find_children("", "Label", true, false).map(func(node): return node.text)
	check("Level 2 complete!" in celebration_text and celebration_text.any(func(line): return line.ends_with("!") and (line.trim_suffix("!") + ".") in CelebrationLines.LINES), "Celebration chooses a short exclamation")
	var praise_labels: Array = main.find_children("", "Label", true, false).filter(func(node): return node.text.ends_with("!") and (node.text.trim_suffix("!") + ".") in CelebrationLines.LINES)
	check(praise_labels.size() == 1 and praise_labels[0].get_theme_color("font_color").is_equal_approx(PuzzleBoard.tile_color(0, main.store.get_color(2))), "Celebration subtext matches the light tile color")
	check(not "Take a breath. Your next puzzle is on its way." in celebration_text, "Celebration has no bottom sentence")
	await create_timer(2.7).timeout
	check(main.current_level == 3, "Celebration automatically advances")
	main.play_level(2)
	await process_frame
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
	check(main.palette_tween != null and main.palette_tween.is_running(), "Text and button colors fade with the level set")
	check(main.background_rect.color == PuzzleBoard.background_color(main.store.get_color(5)), "Set transition begins with previous background")
	check(main.theme.get_color("font_color", "Label") == PuzzleBoard.text_color(main.store.get_color(5)), "Palette transition begins with previous text color")
	await create_timer(0.30).timeout
	check(not main.theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(5))) and not main.theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(6))), "Text color interpolates during the fade")
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(6))), "Set transition reaches the new background")
	check((main.board_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.is_equal_approx(main.background_rect.color), "Board and whole screen fade together")
	check(main.theme.get_color("font_color", "Label").is_equal_approx(PuzzleBoard.text_color(main.store.get_color(6))), "Text reaches the next adjacent color")
	check((main.theme.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color.is_equal_approx(PuzzleBoard.button_color(main.store.get_color(6))), "Buttons reach the next adjacent color")
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
	check(main.background_rect.color == PuzzleBoard.background_color(main.store.get_color(6)), "Menu defaults to the current unsolved level color")
	var level_cards := root.find_children("", "Button", true, false).filter(func(node): return node.tooltip_text.begins_with("Play level "))
	check(not level_cards.is_empty() and level_cards[0].size == Vector2(64, 64), "Menu level cards are 64 by 64")
	check(main.menu_rows.get_child_count() == 1 and (main.menu_rows.get_child(0) as HBoxContainer).alignment == BoxContainer.ALIGNMENT_CENTER, "Short menu row is centered")
	check(main.content.get_child(0) is HBoxContainer and (main.content.get_child(0) as HBoxContainer).get_children().any(func(node): return node is Button and node.text == "Play level 6   →"), "Play button sits beside the title")
	check((main.content.get_child(0) as HBoxContainer).get_child(0).text == "H e a r t h l i n e", "Cozy menu title has spaced letters")
	check(main.content.get_child(0).get_child(2).theme_type_variation == "PrimaryButton", "Play level uses the prominent button style")
	var thumbnail: TextureRect = level_cards[0].get_children().filter(func(node): return node is TextureRect)[0]
	check(thumbnail.position == Vector2.ZERO and thumbnail.size == Vector2(64, 64), "Screenshot fills the whole menu button")
	var text_labels: Array = level_cards[0].get_children().filter(func(node): return node is Label)
	check(text_labels[0].get_theme_constant("outline_size") == 3 and text_labels[0].get_theme_color("font_outline_color") == Color.BLACK, "Menu labels have black outlines")
	check(text_labels[0].text == "1" and text_labels[0].get_theme_color("font_color") == PuzzleBoard.text_color(main.store.get_color(1)), "Card number has no padding and uses its level text color")
	check(text_labels[1].get_theme_font_size("font_size") == 18, "Completed checkmark is larger")
	var card_outline: Panel = level_cards[0].get_children().filter(func(node): return node is Panel)[0]
	var outline_style: StyleBoxFlat = card_outline.get_theme_stylebox("panel")
	check(outline_style.border_width_left == 2 and outline_style.corner_radius_top_left > 0 and outline_style.border_color == PuzzleBoard.tile_color(0, main.store.get_color(1)), "Cards have a rounded light-tile outline")
	level_cards[0].mouse_entered.emit()
	check(main.background_tween != null and main.background_tween.is_running(), "Menu hover starts a fade")
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(1))), "Menu background follows hovered level")
	level_cards[0].mouse_exited.emit()
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(1))) and main.menu_hovered_level == 1, "Menu retains the last hovered level palette")
	level_cards[5].mouse_entered.emit()
	await create_timer(0.38).timeout
	check(main.background_rect.color.is_equal_approx(PuzzleBoard.background_color(main.store.get_color(6))) and main.menu_hovered_level == 6, "Hovering another level replaces the held palette")
	level_cards[5].mouse_exited.emit()
	check(main.menu_hovered_level == 6, "Leaving the next card also keeps its palette")
	level_cards[0].mouse_entered.emit()
	key(main, KEY_SHIFT, true, false, true)
	key(main, KEY_Z, true, false, true)
	key(main, KEY_O, true, false, true)
	check(main.screen == "editor" and main.editor_level == 1, "Menu shortcut opens the hovered level")
	key(main, KEY_O, false, false, true)
	key(main, KEY_Z, false, false, true)
	key(main, KEY_SHIFT, false)
	var shifted_store := LevelStore.new()
	shifted_store.mirror_project = false
	shifted_store.levels.clear()
	shifted_store.completed.clear()
	var first_layout := {"width": 3, "height": 3, "tiles": [1, 0, 0, 0, 0, 0, 0, 0, 0]}
	var next_layout := {"width": 3, "height": 3, "tiles": [0, 1, 0, 0, 0, 0, 0, 0, 0]}
	var later_layout := {"width": 3, "height": 3, "tiles": [0, 0, 1, 0, 0, 0, 0, 0, 0]}
	check(shifted_store.save_level(4, first_layout) == OK and shifted_store.save_level(6, next_layout) == OK and shifted_store.save_level(9, later_layout) == OK, "Sparse custom level fixtures save")
	check(shifted_store.mark_complete(4) == OK and shifted_store.mark_complete(6) == OK, "Completed level fixtures save")
	check(shifted_store.insert_level(6, first_layout) == OK, "Insert persists a new custom level")
	check(shifted_store.get_level(6).tiles == first_layout.tiles and shifted_store.get_level(7).tiles == next_layout.tiles and shifted_store.get_level(10).tiles == later_layout.tiles, "Insertion shifts all later sparse custom levels up")
	check(not shifted_store.completed.has("6") and shifted_store.completed.has("7"), "Insertion shifts completion records with level numbers")
	var shifted_reload := LevelStore.new()
	check(shifted_reload.get_level(7).tiles == next_layout.tiles and shifted_reload.get_level(10).tiles == later_layout.tiles, "Inserted level numbering survives reload")
	check(shifted_store.delete_level(6) == OK, "Delete persists a saved custom level removal")
	check(shifted_store.get_level(6).tiles == next_layout.tiles and shifted_store.get_level(9).tiles == later_layout.tiles and not shifted_store.levels.has("10"), "Deletion shifts later custom levels down")
	check(shifted_store.completed.has("6") and not shifted_store.completed.has("7"), "Deletion shifts completion records back")
	check(shifted_store.delete_level(5) == ERR_DOES_NOT_EXIST, "Generated levels cannot be deleted as custom levels")
	main.show_menu()
	key(main, KEY_CTRL, true, true)
	key(main, KEY_Z, true, true)
	key(main, KEY_M, true, true)
	check(main.store.frontier() == 100 and main.store.completed.has("99"), "Ctrl+Z+M completes and unlocks the first 99 levels")
	check(main.menu_cards.size() == 30 and main.menu_columns <= 15 and main.menu_rows.get_child_count() == ceili(30.0 / main.menu_columns) and (main.menu_rows.get_child(0) as HBoxContainer).alignment == BoxContainer.ALIGNMENT_CENTER, "Menu centers each row with up to 15 level cards")
	key(main, KEY_M, false, true)
	key(main, KEY_Z, false, true)
	key(main, KEY_CTRL, false)
	key(main, KEY_CTRL, true, true)
	key(main, KEY_Z, true, true)
	key(main, KEY_N, true, true)
	check(main.store.frontier() == 2 and main.store.completed.size() == 1 and main.store.completed.has("1"), "Ctrl+Z+N clears completion except level 1")
	check(main.menu_cards.size() == 2, "Reset progress removes locked levels from the menu")
	key(main, KEY_N, false, true)
	key(main, KEY_Z, false, true)
	key(main, KEY_CTRL, false)
	var progress_reload := LevelStore.new()
	check(progress_reload.frontier() == 2, "Reset completion survives reload")
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
