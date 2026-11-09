extends SceneTree

var failures := 0
var checks := 0

class MockCommunity extends CommunityService:
	var replies: Array[Dictionary] = []
	var actions: Array[String] = []
	func request(_action: String, _args: Dictionary = {}) -> Dictionary:
		actions.append(_action)
		var result: Dictionary = replies.pop_front() if not replies.is_empty() else {"levels": [], "replays": [], "cursor": null}
		await get_tree().process_frame
		return result

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	CustomLevelEditor.clear_saved_draft()
	var initial_preferences := ConfigFile.new()
	initial_preferences.load(CommunityService.IDENTITY_PATH)
	initial_preferences.set_value("preferences", "custom_levels_notice_seen", false)
	initial_preferences.save(CommunityService.IDENTITY_PATH)
	var level := {"width": 3, "height": 3, "tiles": [1, 1, 0, 0, 0, 0, 2, 0, 0], "name": "Tæst 🦊", "author": "Åuthor", "color": "d892fa"}
	var code := CommunityCodec.encode_level(level)
	check(CommunityCodec.decode_level(code) == level, "Encrypted compressed level preserves metadata, dimensions, tile types and color")
	check(code != CommunityCodec.encode_level(level), "Each export has a new random IV")
	check(CommunityCodec.decode_level("bad").is_empty(), "Invalid imports are rejected")
	check(CommunityCodec.decode_level(code.left(12)).is_empty(), "Truncated imports are rejected")
	var maximum := level.duplicate(true)
	maximum.width = 32
	maximum.height = 32
	maximum.tiles.resize(1024)
	maximum.tiles.fill(0)
	maximum.tiles[1023] = 2
	check(CommunityCodec.decode_level(CommunityCodec.encode_level(maximum)) == maximum, "32 by 32 round trip")
	maximum.width = 33
	check(CommunityCodec.encode_level(maximum).is_empty(), "Oversized imports rejected")
	var inputs := [[0, 0], [9000, 1], [20, -1], [30, 1]]
	var replay_code := CommunityCodec.encode_replay(inputs)
	var replay := CommunityCodec.decode_replay(replay_code, 9)
	check(replay == [[0, 0], [5000, 1], [20, -1], [30, 1]], "Replays keep tile inputs, undo and trim long idle gaps")
	check(CommunityCodec.decode_replay(replay_code, 1).is_empty(), "Replay tile bounds validated")
	var fixture := FileAccess.open("res://.test-user/community-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"level": level, "code": code, "events": replay, "replayCode": replay_code, "proofCode": CommunityCodec.encode_replay([[0, 0], [200, 1]])}))
	fixture.close()
	var save := {"completed": {"1": true}, "path": [1, 2, 3], "text": "é"}
	check(LevelStore._atomic_write("user://community_test.save", save) == OK, "Compressed save written")
	var restored := LevelStore._read_json("user://community_test.save")
	check(restored.get("text") == "é" and restored.get("completed", {}).get("1") == true and restored.get("path", []).size() == 3, "Compressed save restored")
	var legacy := FileAccess.open("user://community_legacy.json", FileAccess.WRITE)
	legacy.store_string(JSON.stringify(save))
	legacy.close()
	check(LevelStore._read_json("user://community_legacy.json").get("text") == "é", "Legacy JSON saves still load")
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.play_level(1)
	main._finish_screen_transition()
	await create_timer(0.25).timeout
	await process_frame
	main.board.path = [0, 1]
	main.board.refresh()
	var original: Array = main.board.path.duplicate()
	var old_completed: Dictionary = main.store.completed.duplicate(true)
	var footer: Control = main.get_node("CommunityFooter")
	check(is_equal_approx(footer.size.y, 16.0), "Footer exactly 16 pixels tall")
	check(is_equal_approx(footer.get_global_rect().end.y, main.size.y), "Footer flush with bottom edge")
	check(main.status_bar.get_child(main.status_bar.get_child_count() - 1).name == "CustomLevelsButton", "Custom Levels to the right of Settings")
	main._open_custom_levels()
	await process_frame
	var hub = main.community_hub
	check(hub.view == "notice" and hub.browser_panel == null and hub.service.get_child_count() == 0, "First Custom Levels entry waits before creating the list or fetching levels")
	check(hub.modal.body.get_child(0).text == "To avoid spoilers, consider solving the first 20 puzzles before using custom levels." and hub.modal.cancel_button.text == "Back" and hub.modal.confirm_button.text == "Confirm", "Custom Levels warning has the requested message and Back/Confirm buttons")
	hub.modal.cancel_button.pressed.emit()
	await process_frame
	check(main.community_hub == null and main.is_processing_input() and main.board.path == original, "Warning Back keeps the list closed and restores the main puzzle")
	main._open_custom_levels()
	await process_frame
	hub = main.community_hub
	check(hub.view == "notice" and not hub.service.custom_levels_notice_seen, "Backing out does not acknowledge the warning")
	hub.modal.confirm_button.pressed.emit()
	await process_frame
	check(hub.view == "browser" and hub.service.custom_levels_notice_seen, "Confirm acknowledges the warning and opens Custom Levels")
	check(main.active_shell.visible and main.active_shell.process_mode == Node.PROCESS_MODE_DISABLED, "Campaign visible and paused behind the selector")
	check(hub.browser_panel.size.x < main.size.x and hub.browser_panel.size.y < main.size.y, "Selector is a centered window")
	check(hub.campaign_background == main.background_rect.color and main.game_audio.music_active, "Selector inherits the current background and keeps music active")
	var mock := MockCommunity.new()
	hub.remove_child(hub.service)
	hub.service.queue_free()
	hub.service = mock
	hub.add_child(mock)
	var listing := {"id": "test", "revision": 1, "name": level.name, "author": level.author, "code": code, "score": 2, "replayCount": 3}
	mock.replies.append({"levels": [listing], "cursor": null})
	hub.show_browser()
	await process_frame
	await process_frame
	check(not hub.more_button.visible, "No More button on the last level page")
	var yellow: Color = hub.editor_button.get_theme_stylebox("normal").bg_color
	var standard: Color = hub.theme.get_stylebox("normal", "Button").bg_color
	check(absf(yellow.h - CommunityStyle.ACCENT_HUE) < 0.01 and absf(yellow.s - standard.s) < 0.01 and absf(PuzzleBoard.luminance(yellow) - PuzzleBoard.luminance(standard)) < 0.001, "Editor orange matches the saturation and brightness of other buttons")
	check(hub.editor_button.get_parent() == hub.more_button.get_parent(), "Selector bottom buttons share one row")
	var card: Button = hub.rows.get_child(0).get_child(0)
	check(card.text.is_empty() and card.find_child("LevelName", true, false).text == level.name, "Level titles have no parenthesized score")
	check(card.find_child("Author", true, false).text == level.author and card.find_child("Author", true, false).horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "Author stays right aligned without a prefix")
	check(card.find_child("PuzzlePreview", true, false).layout.tiles == level.tiles, "Selector thumbnail shows the actual puzzle")
	var thumbnail: Control = card.find_child("PuzzlePreview", true, false)
	var name_label: Label = card.find_child("LevelName", true, false)
	check(is_equal_approx(thumbnail.global_position.y, name_label.global_position.y) and is_equal_approx(thumbnail.get_global_rect().end.y, name_label.get_parent().get_global_rect().end.y), "Thumbnail aligns with the name and stats block")
	check(card.size.y < 96 and card.get_child(0).get_theme_constant("margin_top") == 16 and card.get_child(0).get_theme_constant("margin_bottom") == 16, "Level rows are shorter with 16 pixels around the text")
	check(card.find_child("ScoreCount", true, false).text == "2" and card.find_child("ReplayCount", true, false).text == "3", "Compact score and replay counts are separate from the title")
	card.mouse_entered.emit()
	await create_timer(0.18).timeout
	check(card.find_child("PuzzlePreview", true, false).scale.x > 1, "Hover gently enlarges the thumbnail")
	card.mouse_exited.emit()
	mock.replies.append({"levels": [listing], "cursor": "next"})
	hub._fetch_levels(false)
	await process_frame
	await process_frame
	check(hub.more_button.visible, "More appears when another level page exists")
	mock.replies.append({"levels": [], "cursor": null})
	hub._fetch_levels(true)
	await process_frame
	await process_frame
	check(not hub.more_button.visible, "More disappears after the final level page")
	mock.replies.append({"replays": [{"id": "own", "owned": true, "author": "Fox", "duration": 12345, "code": replay_code}, {"id": "other", "owned": false, "author": "Guest", "duration": 15000, "code": replay_code}], "cursor": null})
	hub.show_replays(listing)
	await process_frame
	await process_frame
	check(not hub.replay_more_button.visible, "No More button on the last replay page")
	var replay_card: Button = hub.rows.get_child(0).get_child(0)
	check(replay_card.find_child("ReplayTime", true, false).text == "12.3s" and replay_card.find_child("Author", true, false).text == "Fox", "Replay row has duration on the left and unprefixed author on the right")
	check(replay_card.get_child(0).get_theme_constant("margin_top") == 6 and replay_card.get_child(0).get_theme_constant("margin_bottom") == 6, "Replay text padding is halved")
	check(replay_card.size.y == 46, "Replay rows are shorter after padding is halved")
	check(hub.rows.get_child(0).find_child("DeleteReplay", true, false) != null and hub.rows.get_child(1).find_child("DeleteReplay", true, false) == null, "Only owned replays have a delete button")
	hub._confirm_delete_replay(listing, {"id": "own"})
	check(is_instance_valid(hub.modal) and hub.modal.confirm_text == "Delete", "Replay deletion opens a confirmation")
	hub.modal.dismiss()
	check(hub.rows.get_child_count() == 2, "Canceling replay deletion preserves the list")
	hub._confirm_delete_replay(listing, {"id": "own"})
	mock.replies.append({"ok": true})
	mock.replies.append({"replays": [], "cursor": null})
	hub.modal.confirmed.emit()
	await process_frame
	await process_frame
	await process_frame
	check(hub.rows.get_child_count() == 0 and not is_instance_valid(hub.modal), "Confirmed replay deletion refreshes the list")
	check(hub.replay_more_button.get_parent().name == "ReplayActions", "Replay navigation shares a single row")
	mock.replies.append({"replays": [], "cursor": "replay-next"})
	hub._fetch_replays(listing, false)
	await process_frame
	await process_frame
	check(hub.replay_more_button.visible, "More appears when another replay page exists")
	mock.replies.append({"replays": [], "cursor": null})
	hub._fetch_replays(listing, true)
	await process_frame
	await process_frame
	check(not hub.replay_more_button.visible, "More disappears after the final replay page")
	hub.open_editor()
	await process_frame
	check(not is_instance_valid(hub.modal) and hub.editor.popup == null, "Opening the editor does not show the Custom Levels warning")
	hub.show_browser()
	hub.open_editor()
	await process_frame
	check(not is_instance_valid(hub.modal) and hub.editor.popup == null, "Reopening the editor does not repeat the notice")
	var saved_preferences := ConfigFile.new()
	saved_preferences.load(CommunityService.IDENTITY_PATH)
	check(saved_preferences.get_value("preferences", "custom_levels_notice_seen", false), "The confirmed Custom Levels warning flag persists to disk")
	var editor: CustomLevelEditor = hub.editor
	await process_frame
	var editor_bar: Control = editor.find_child("EditorBar", true, false)
	var bar_padding: MarginContainer = editor.find_child("EditorBarPadding", true, false)
	for side in ["left", "right", "top", "bottom"]:
		check(bar_padding.get_theme_constant("margin_" + side) == 16, "Editor bar has 16 pixels of " + side + " padding")
	check(editor_bar is HBoxContainer and editor.play_button.get_theme_font_size("font_size") == 16, "Editor uses one row of readable controls")
	for control in [editor.palette[0], editor.width_input, editor.height_input, editor.color_input, editor.export_button, editor.import_button, editor.play_button]:
		check(control.size.y >= 34, "Editor control has its original height: " + str(control.size))
		check(absf(control.get_global_rect().get_center().y - editor.palette[0].get_global_rect().get_center().y) <= 1, "Editor controls share one vertical center")
	check(editor_bar.get_global_rect().end.x <= editor.size.x - 16, "Editor controls fit within the padded bar")
	for swatch in editor.palette + [editor.color_input]:
		check(swatch.size.x == swatch.size.y and swatch.get_theme_stylebox("normal").corner_radius_top_left > 0, "Palette and color picker are rounded squares")
	check(editor.color_input.find_child("ColorPickerIcon", true, false) != null, "Color picker has its own icon")
	check(editor.color_swatch_style.bg_color == PuzzleBoard.tile_color(0, Color(editor.draft.color)), "Color picker swatch matches the light tiles")
	var picker: ColorPicker = editor.color_input.get_picker()
	check(picker.picker_shape == ColorPicker.SHAPE_NONE and not picker.sliders_visible and not picker.color_modes_visible and not picker.hex_visible and not picker.sampler_visible and not picker.presets_visible and editor.hue_slider.visible, "Color popup shows only the hue slider")
	check(editor.publish_button.get_index() == editor.play_button.get_index() + 1 and editor.publish_button.get_parent() == editor.play_button.get_parent(), "Publish sits between Play Puzzle and Exit")
	check(absf(editor.publish_button.get_theme_stylebox("normal").bg_color.h - CommunityStyle.ACCENT_HUE) < 0.01, "Publish uses the same orange accent")
	check(editor.draft.tiles.count(0) == 64 and editor.board.editing, "Editor starts with a white 8 by 8 grid")
	var initial_tiles: Array = editor.draft.tiles.duplicate()
	editor.board._begin(editor.board.center(0))
	editor.board._trace(editor.board.center(2))
	editor.board._end()
	check(editor.undo_stack.size() == 1 and editor.draft.tiles[0] == 1 and editor.draft.tiles[2] == 1, "A full paint stroke is one undo operation")
	var undo_key := InputEventKey.new()
	undo_key.keycode = KEY_Z
	undo_key.ctrl_pressed = true
	undo_key.pressed = true
	editor._input(undo_key)
	check(editor.draft.tiles == initial_tiles, "Ctrl+Z undoes the whole stroke")
	undo_key.keycode = KEY_Y
	editor._input(undo_key)
	check(editor.draft.tiles[0] == 1 and editor.draft.tiles[2] == 1, "Ctrl+Y restores the stroke")
	editor.undo()
	var brush_key := InputEventKey.new()
	brush_key.keycode = KEY_3
	brush_key.pressed = true
	editor._input(brush_key)
	check(editor.brush == 2 and editor.board.brush_preview == 2 and editor.draft.tiles == initial_tiles, "Brush shortcut selects a gray ghost without painting")
	brush_key.keycode = KEY_1
	editor._input(brush_key)
	editor._paint(0)
	check(editor.draft.tiles[0] == 1, "Left paint uses selected brush")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = editor.board.center(0)
	editor.board._gui_input(right)
	check(editor.draft.tiles[0] == 0, "Right click paints white")
	editor.board._end_light()
	editor._paint(1, 2)
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	middle.position = editor.board.center(1)
	editor.board._gui_input(middle)
	check(editor.brush == 2 and editor.palette[2].button_pressed, "Middle click samples gray into selected palette brush")
	editor._paint(2)
	check(editor.draft.tiles[2] == 2, "Sampled brush paints the selected type")
	editor.width_input.value = 32
	editor.height_input.value = 32
	check(editor.draft.tiles.size() == 1024 and editor.draft.tiles[1] == 2, "Resizing preserves grid contents up to 32 by 32")
	editor.undo()
	check(editor.draft.width == 32 and editor.draft.height == 8, "Resize is undoable")
	editor.redo()
	check(editor.draft.width == 32 and editor.draft.height == 32, "Resize is redoable")
	var old_color: String = editor.draft.color
	editor._change_color(Color("cc9955"))
	editor.undo()
	check(editor.draft.color == old_color, "Color changes are undoable")
	var saved_draft := CustomLevelEditor.read_saved_draft()
	check(saved_draft.layout.tiles == editor.draft.tiles and int(saved_draft.brush) == editor.brush, "Draft autosave stores layout and selected brush")
	editor.exited.emit()
	hub.open_editor()
	editor = hub.editor
	check(editor.draft.width == 32 and editor.draft.height == 32 and editor.draft.tiles[1] == 2, "Reopening the editor resumes the autosaved draft")
	editor._import()
	editor.import_text.text = code
	editor.popup.confirmed.emit()
	editor.popup.hide()
	await process_frame
	check(editor.draft.width == 3 and editor.draft.tiles == level.tiles, "Import replaces the draft as one edit")
	editor.undo()
	check(editor.draft.width == 32 and editor.draft.height == 32, "Undo restores the draft before import")
	editor.redo()
	check(editor.draft.width == 3 and editor.draft.tiles == level.tiles, "Redo restores the imported puzzle")
	editor.draft = level.duplicate(true)
	editor._sync_board()
	editor.request_publish()
	check(editor.playtesting and editor.publish_pending and is_instance_valid(editor.popup), "Publishing unsolved level requires playtest first")
	check(editor.popup.body.get_child(0).text == "Complete the puzzle to upload.", "Publish prerequisite popup has exact requested text")
	check(not editor.tools.visible and not editor.export_button.visible and not editor.import_button.visible and not editor.feedback.visible and editor.play_button.text == "Edit Level", "Playtest hides building tools and keeps Edit Level and Exit")
	editor.popup.confirmed.emit()
	editor.board._begin(editor.board.center(0))
	editor.board._trace_toward(1)
	check(editor.solution == [0, 1] and editor.winning and not is_instance_valid(hub.modal), "Victory starts before the publish dialog")
	await create_timer(0.5).timeout
	check(not is_instance_valid(hub.modal), "Publish dialog stays closed during the victory animation")
	await create_timer(0.6).timeout
	check(is_instance_valid(hub.modal) and hub.modal is CommunityDialog, "Publish opens after one second using the game's dialog design")
	check(hub.modal.find_child("PuzzlePreview", true, false).layout.tiles == level.tiles, "Publish previews the exact puzzle")
	check(hub.modal.find_child("SolvedBadge", true, false) == null, "Publish dialog has no solved checkmark")
	hub.modal.dismiss()
	await process_frame
	editor.toggle_play()
	check(editor.board.editing and editor.solution == [0, 1], "Return to edit preserves the validated solution")
	editor._paint(2, 1)
	check(editor.solution.is_empty(), "Editing invalidates completion")
	main._close_custom_levels()
	await process_frame
	check(main.board.path == original and main.active_shell.visible and main.is_processing_input(), "Exiting restores exact campaign path and input")
	check(main.store.completed == old_completed, "Custom playtest leaves campaign completion unchanged")
	main._open_custom_levels()
	await process_frame
	hub = main.community_hub
	var item := {"id": "test", "revision": 1, "name": level.name, "author": level.author, "code": code}
	var replay_item := {"code": CommunityCodec.encode_replay([[100, 0], [200, 1]])}
	hub.watch_replay(item, replay_item)
	hub._process(0.1)
	hub.replay_playing = false
	hub._seek_replay(0)
	check(hub.board.path.is_empty(), "Timeline starts before first input")
	hub._seek_replay(100)
	check(hub.board.path == [0], "Timeline applies first move at exact timestamp")
	hub._seek_replay(300)
	check(hub.board.path == [0, 1], "Timeline seeks forward to completion")
	hub._seek_replay(400)
	check(hub.board.line.points[-1].is_equal_approx(hub.board.center(0).lerp(hub.board.center(1), 0.5)), "Replay line interpolates smoothly between timestamped inputs")
	hub._seek_replay(500)
	check(hub.board.line.points[-1].is_equal_approx(hub.board.center(1)), "Replay finishes its final line animation")
	hub._seek_replay(50)
	check(hub.board.path.is_empty(), "Timeline scrubs backward")
	hub.play_level(item)
	await process_frame
	var actions_before: Rect2 = hub.play_actions.get_global_rect()
	check(hub.play_actions.get_child(0).text == "Reset" and hub.play_actions.get_child(1).text == "Back", "Back is to the right of Reset")
	hub.board._begin(hub.board.center(0))
	hub.board._trace_toward(1)
	check(hub.winning and not is_instance_valid(hub.modal), "Custom solve delays the end dialog")
	await create_timer(1.1).timeout
	check(is_instance_valid(hub.modal) and hub.vote_score.text == "0", "Win dialog shows the net vote count")
	await process_frame
	await process_frame
	check(hub.board.get_global_rect().end.x <= hub.modal.panel.global_position.x, "Result panel leaves the entire completed route visible")
	check(hub.play_actions.get_global_rect() == actions_before, "Puzzle controls stay fixed on the right while the dialog opens")
	check(hub.modal.title_label.text == level.name and hub.modal.title_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and hub.modal.body.get_child(0).text == "By: " + level.author and hub.modal.body.get_child(0).get_theme_font_size("font_size") < hub.modal.title_label.get_theme_font_size("font_size"), "Result has a centered puzzle title and smaller By author underneath")
	check(hub.modal.find_child("VotePrompt", true, false).text == "Vote", "Vote label sits inline before the arrows")
	check(hub.vote_score.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN and hub.votes[0].get_parent().alignment == BoxContainer.ALIGNMENT_CENTER and is_equal_approx(hub.vote_score.position.x - hub.votes[0].position.x, hub.votes[1].position.x - hub.vote_score.position.x), "Votes form a centered evenly spaced group")
	check(hub.votes[1].position.x - hub.votes[0].position.x <= 72, "Vote arrows and text sit close together")
	check(hub.modal.actions.alignment == BoxContainer.ALIGNMENT_CENTER, "Result actions are centered")
	check(hub.modal.actions.get_child(0).name == "PublishReplay" and hub.modal.actions.get_child(0).visible and hub.modal.find_child("PlayAgain", true, false) != null, "Publish Replay is visible after winning beside Play Again")
	check(hub.modal.actions.get_child(0).theme_type_variation == "PrimaryButton" and hub.modal.confirm_button.theme_type_variation == "Button" and hub.modal.actions.get_child(0).get_theme_stylebox("normal").bg_color != hub.modal.confirm_button.get_theme_stylebox("normal").bg_color, "Publish Replay is highlighted instead of Back")
	check(hub.votes[0].get_theme_stylebox("normal") is StyleBoxEmpty and hub.votes[0].get_theme_color("icon_normal_color") == Color.WHITE, "Vote arrows are white without button backgrounds")
	hub.selected.vote = -1
	hub.selected.score = -1
	hub._update_votes(true)
	check(hub.vote_score.text == "-1" and hub.votes[1].get_theme_color("icon_normal_color") == hub.VOTE_ORANGE and hub.votes[0].get_theme_color("icon_normal_color") == Color.WHITE, "Only the selected arrow is orange and net votes update")
	await create_timer(0.1).timeout
	check(hub.vote_score.scale.x > 1, "Changing a vote bounces the net count")
	await create_timer(0.2).timeout
	check(hub.vote_score.scale.is_equal_approx(Vector2.ONE), "Vote count settles after its bounce")
	hub.selected.created = Time.get_unix_time_from_system() * 1000
	hub.selected.rawScore = -3
	hub._update_votes()
	check(hub.vote_score.text == "0" and hub.selected.rawScore == -3, "First-day votes display zero without losing the negative total")
	check(hub._display_score(hub.selected) == 0, "The selector uses the same first-day score floor")
	hub.selected.created -= 86400001
	hub._update_votes()
	check(hub.vote_score.text == "-3", "Negative vote totals display after the first day")
	hub.selected.created = Time.get_unix_time_from_system() * 1000
	hub.selected.rawScore = 0
	hub.selected.vote = 0
	mock = MockCommunity.new()
	hub.remove_child(hub.service)
	hub.service.queue_free()
	hub.service = mock
	hub.add_child(mock)
	mock.replies.append({"score": 0, "rawScore": -1, "created": hub.selected.created})
	hub.votes[1].pressed.emit()
	check(hub.vote_score.text == "0", "An optimistic first-day downvote never flashes negative")
	await process_frame
	await process_frame
	check(hub.selected.rawScore == -1 and hub.vote_score.text == "0", "Vote responses preserve the underlying negative total")
	mock.replies.append({"score": 1, "rawScore": 1, "created": hub.selected.created})
	hub.votes[0].pressed.emit()
	await process_frame
	await process_frame
	check(hub.selected.rawScore == 1 and hub.vote_score.text == "1", "Switching votes calculates from the real total instead of its display floor")
	var result_dialog: CommunityDialog = hub.modal
	hub._publish_replay()
	var replay_inputs: Array = hub.modal.body.find_children("", "LineEdit", true, false)
	check(replay_inputs.size() == 1 and replay_inputs[0].placeholder_text == "Author", "Replay publishing asks only for an author")
	check(not result_dialog.is_processing_input(), "Only the top publish dialog handles Escape")
	hub.modal.dismiss()
	check(hub.modal == result_dialog and result_dialog.is_processing_input(), "Canceling replay publication restores the result dialog")
	result_dialog.find_child("PlayAgain", true, false).pressed.emit()
	check(hub.view == "play" and hub.board.path.is_empty() and hub.events.is_empty(), "Play Again starts a fresh attempt and replay recording")
	hub._finish_play(false)
	check(hub.modal.cancel_button.text == "Nevermind" and hub.modal.confirm_button.text == "Leave", "Leave dialog offers Nevermind and Leave")
	check(not hub.modal.find_child("PublishReplay", true, false).visible, "Unfinished puzzles hide Publish Replay")
	var leave_dialog: CommunityDialog = hub.modal
	hub._publish_replay()
	check(hub.modal == leave_dialog, "Unfinished puzzles cannot open the replay upload dialog")
	hub.modal.confirmed.emit()
	check(hub.view == "browser" and main.community_hub == hub, "Puzzle Back returns to Custom Levels and keeps the main game saved")
	hub._after_publish("test")
	check(hub.view == "browser" and is_instance_valid(hub.browser_panel), "Successful upload returns to a refreshed level selector")
	hub.open_editor(level)
	hub._after_publish("published-draft")
	check(CustomLevelEditor.read_saved_draft().is_empty(), "Publishing clears the saved draft without exit recreating it")
	hub.service.publish_available_at_ms = 0
	hub.open_editor(level, "owned", 1)
	editor = hub.editor
	editor.solution = [0, 1]
	editor.request_publish()
	var publish_dialog: CommunityDialog = hub.modal
	var publish_count: int = mock.actions.count("publish")
	publish_dialog.confirmed.emit()
	check(hub.modal != publish_dialog and hub.modal.body.get_child(0).text == "This will remove all votes and replays on your level", "Republishing asks for the exact votes and replays confirmation")
	check(mock.actions.count("publish") == publish_count, "Republishing waits for confirmation before contacting the server")
	hub.modal.dismiss()
	check(hub.modal == publish_dialog and editor.popup == publish_dialog and publish_dialog.visible, "Canceling confirmation restores the publish form and editor input guard")
	publish_dialog.confirmed.emit()
	mock.replies.append({"error": "publish_cooldown", "retryAfterMs": 60000})
	hub.modal.confirmed.emit()
	await process_frame
	await process_frame
	check(hub.modal.name == "PublishCooldown" and hub.modal.body.get_child(0).text == "Hold it there, partner.\n\nYou're publishing a bit too fast.\n1:00", "Server cooldown opens the exact requested popup with time remaining")
	await create_timer(1.1).timeout
	check(hub.modal.body.get_child(0).text.ends_with("0:59"), "Publish cooldown counts down while open")
	hub.modal.confirmed.emit()
	check(hub.modal == publish_dialog and editor.popup == publish_dialog, "Closing cooldown preserves the publish form")
	var cooldown_publish_count: int = mock.actions.count("publish")
	publish_dialog.confirmed.emit()
	check(hub.modal != publish_dialog and hub.modal.body.get_child(0).text.begins_with("Hold it there, partner.") and mock.actions.count("publish") == cooldown_publish_count, "Known cooldown prevents another upload attempt")
	hub.modal.confirmed.emit()
	mock.publish_available_at_ms = Time.get_unix_time_from_system() * 1000 - 1
	publish_dialog.confirmed.emit()
	mock.replies.append({"id": "owned", "revision": 2})
	hub.modal.confirmed.emit()
	await process_frame
	await process_frame
	await process_frame
	check(hub.view == "browser", "Confirmed republish proceeds once the personal cooldown expires")
	hub.open_editor(level)
	editor = hub.editor
	mock.remember_publish_cooldown(65000)
	editor.request_publish()
	check(not editor.playtesting and hub.modal.name == "PublishCooldown" and hub.modal.body.get_child(0).text.ends_with("1:05"), "Cooldown popup appears before asking to solve an unfinished draft")
	var restored_service := CommunityService.new()
	root.add_child(restored_service)
	check(restored_service.publish_remaining_ms() > 63000, "Personal publish cooldown persists across reopening the service")
	restored_service.queue_free()
	hub.modal.confirmed.emit()
	mock.publish_available_at_ms = 0
	mock._save_identity()
	hub.open_editor(level)
	editor = hub.editor
	editor.exited.emit()
	check(hub.view == "browser" and main.community_hub == hub, "Editor Exit returns to Custom Levels")
	hub.open_editor(level)
	var back := InputEventKey.new()
	back.keycode = KEY_ESCAPE
	back.pressed = true
	hub._input(back)
	check(hub.view == "browser", "Editor Escape returns to Custom Levels")
	hub.open_editor(level)
	editor = hub.editor
	editor.toggle_play()
	editor.board._begin(editor.board.center(0))
	editor.board._trace_toward(1)
	main._close_custom_levels()
	await create_timer(1.1).timeout
	check(main.community_hub == null and main.is_processing_input(), "Exiting during victory cannot reopen a community dialog")
	main._open_custom_levels()
	await process_frame
	hub = main.community_hub
	hub._input(back)
	check(main.community_hub == null and main.is_processing_input(), "Escape closes the selector without accessing a detached viewport")
	main.queue_free()
	await process_frame
	print("Community: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
