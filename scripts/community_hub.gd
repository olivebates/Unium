extends Control

const EditorScene = preload("res://custom_level_editor.tscn")
const ICONS := {
	"edit": preload("res://assets/community_edit.svg"),
	"delete": preload("res://assets/community_delete.svg"),
	"replay": preload("res://assets/community_replay.svg"),
}
signal closed

var service: CommunityService
var shell: VBoxContainer
var rows: VBoxContainer
var feedback: Label
var search: LineEdit
var sort_by := "Hot"
var search_text := ""
var view := ""
var generation := 0
var next_cursor: Variant = null
var editor: CustomLevelEditor
var editing_id := ""
var editing_revision := 0
var board: PuzzleBoard
var selected: Dictionary = {}
var events: Array = []
var last_event_time := 0
var replay_events: Array = []
var replay_paths: Array = []
var replay_times: Array = []
var replay_position := 0.0
var replay_duration := 0.0
var replay_playing := false
var replay_seeking := false
var timeline: HSlider
var replay_button: Button
var replay_cursor: Variant = null
var modal: CommunityDialog
var votes: Array[Button] = []
var pending := false
var campaign_background := Color("0c1219")
var audio: Node
var browser_panel: PanelContainer
var vote_score: Label
var winning := false
var replay_render_index := -2
var replay_input_duration := 0.0
var published_id := ""
var more_button: Button
var replay_more_button: Button
var editor_button: Button
var vote_score_tween: Tween
var play_actions: HBoxContainer
const VOTE_ARROW = preload("res://assets/community_upvote.svg")
const VOTE_ORANGE := Color("ff8a3d")
const REPLAY_MOVE_MS := 200.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_fit_browser_panel)
	_style_fields()
	service = CommunityService.new()
	add_child(service)
	if service.custom_levels_notice_seen:
		show_browser()
	else:
		view = "notice"
		var dialog := _dialog("", "Confirm", "Back")
		dialog.panel.custom_minimum_size.x = 440
		var message := _label("To avoid spoilers, consider solving the first 20 puzzles before using custom levels.", 18)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		dialog.body.add_child(message)
		dialog.confirmed.connect(func():
			service.remember_custom_levels_notice()
			show_browser()
		)
		dialog.canceled.connect(func(): closed.emit())
		dialog.cancel_button.grab_focus()

func _style_fields() -> void:
	for kind in ["LineEdit", "TextEdit"]:
		for state in ["normal", "focus", "read_only"]:
			var style := CommunityDialog.surface(campaign_background.lightened(0.045))
			style.set_corner_radius_all(10)
			style.shadow_size = 0
			style.set_content_margin_all(12)
			if state == "focus":
				style.border_color = Color("b6ead3")
			theme.set_stylebox(state, kind, style)

func _dialog(title: String, confirm: String, cancel: String = "Cancel") -> CommunityDialog:
	var previous := modal
	if is_instance_valid(previous):
		previous.set_process_input(false)
		previous.hide()
	var dialog := CommunityDialog.new()
	dialog.heading = title
	dialog.confirm_text = confirm
	dialog.cancel_text = cancel
	dialog.panel_color = campaign_background
	add_child(dialog)
	if is_instance_valid(previous) and previous.right_docked:
		dialog.dock_right()
	modal = dialog
	dialog.canceled.connect(func(): _close_dialog(dialog, previous))
	return dialog

func _close_dialog(dialog: CommunityDialog, previous: CommunityDialog = null) -> void:
	if modal == dialog:
		modal = previous if is_instance_valid(previous) else null
		if is_instance_valid(previous):
			previous.set_process_input(true)
			previous.show()
	if is_instance_valid(editor) and editor.popup == dialog:
		editor.popup = previous if is_instance_valid(previous) else null
	dialog.queue_free()

func _fit_browser_panel() -> void:
	if is_instance_valid(browser_panel):
		browser_panel.size = Vector2(minf(960, size.x - 64), minf(660, size.y - 64))
		browser_panel.position = (size - browser_panel.size) * 0.5

func _button(text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(callback)
	return result

func _label(text: String, font_size: int = 18) -> Label:
	var result := Label.new()
	result.text = text
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", font_size)
	return result

func _spacer(parent: Control) -> void:
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(gap)

func _clear(next_view: String) -> void:
	if vote_score_tween:
		vote_score_tween.kill()
		vote_score_tween = null
	generation += 1
	view = next_view
	replay_playing = false
	replay_seeking = false
	pending = false
	winning = false
	board = null
	editor = null
	modal = null
	browser_panel = null
	more_button = null
	replay_more_button = null
	editor_button = null
	play_actions = null
	for node in get_children():
		if node == service:
			continue
		remove_child(node)
		node.queue_free()
	var background := ColorRect.new()
	var windowed := next_view in ["browser", "replays"]
	background.color = Color(0.01, 0.02, 0.03, 0.55) if windowed else campaign_background
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var parent: Control = self
	if windowed:
		browser_panel = PanelContainer.new()
		browser_panel.name = "CustomLevelsWindow"
		browser_panel.add_theme_stylebox_override("panel", CommunityDialog.surface(campaign_background))
		add_child(browser_panel)
		_fit_browser_panel()
		parent = browser_panel
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 24)
	parent.add_child(margins)
	shell = VBoxContainer.new()
	margins.add_child(shell)

func _scroll() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func show_browser() -> void:
	_clear("browser")
	var header := HBoxContainer.new()
	shell.add_child(header)
	header.add_child(_label("Custom Levels", 28))
	_spacer(header)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 5)
	shell.add_child(filters)
	for filter in ["Hot", "Today", "Week", "Month", "Year", "All time"]:
		var choice := _button(filter, func():
			sort_by = filter
			show_browser()
		)
		choice.toggle_mode = true
		choice.button_pressed = sort_by == filter
		filters.add_child(choice)
	search = LineEdit.new()
	search.placeholder_text = "Level name or author"
	search.text = search_text
	shell.add_child(search)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.3
	search.add_child(timer)
	search.text_changed.connect(func(text: String):
		search_text = text
		generation += 1
		timer.start()
	)
	timer.timeout.connect(func(): _fetch_levels(false))
	rows = _scroll()
	feedback = _label("")
	shell.add_child(feedback)
	var footer := HBoxContainer.new()
	footer.name = "SelectorActions"
	shell.add_child(footer)
	footer.add_child(_button("Back", func(): closed.emit()))
	footer.add_child(_button("Refresh", func(): _fetch_levels(false)))
	more_button = _button("More", func():
		if next_cursor != null:
			_fetch_levels(true)
	)
	more_button.hide()
	footer.add_child(more_button)
	_spacer(footer)
	editor_button = _button("Level Editor", func(): open_editor())
	footer.add_child(editor_button)
	CommunityStyle.accent(editor_button)
	_fetch_levels(false)

func _fetch_levels(append: bool) -> void:
	if view != "browser":
		return
	generation += 1
	var ticket := generation
	var query := {"sort": sort_by, "search": search_text, "cursor": next_cursor if append else null}
	more_button.disabled = true
	if not append:
		more_button.hide()
	feedback.text = "…"
	var result := await service.request("list", query)
	# Continue across ranked pages that contain no search matches.
	while not result.has("error") and result.get("levels", []).is_empty() and result.get("cursor") != null:
		if not is_inside_tree() or view != "browser" or ticket != generation:
			return
		query.cursor = result.cursor
		result = await service.request("list", query)
	if not is_inside_tree() or view != "browser" or ticket != generation:
		return
	feedback.text = str(result.get("error", ""))
	more_button.disabled = false
	if result.has("error"):
		return
	if not append:
		for node in rows.get_children():
			rows.remove_child(node)
			node.queue_free()
	next_cursor = result.get("cursor")
	more_button.visible = next_cursor != null
	for item in result.get("levels", []):
		if item is Dictionary:
			_level_row(item)
	if not published_id.is_empty():
		feedback.text = "✓"
		published_id = ""

func _icon(kind: String, callback: Callable) -> Button:
	var result := _button("", callback)
	result.icon = ICONS[kind]
	result.tooltip_text = kind.capitalize()
	result.custom_minimum_size = Vector2(40, 40)
	result.add_theme_constant_override("icon_max_width", 22)
	return result

func _level_row(item: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	rows.add_child(row)
	var play := _button("", func(): play_level(item))
	play.name = "LevelCard"
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.custom_minimum_size.x = 100
	row.add_child(play)
	var content := _card_content(play, 16)
	var preview := _preview(CommunityCodec.decode_level(str(item.get("code", ""))), 36)
	content.add_child(preview)
	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation", 5)
	content.add_child(details)
	var title := _label(str(item.get("name", "")), 20)
	title.name = "LevelName"
	details.add_child(title)
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 14)
	details.add_child(stats)
	_stat(stats, VOTE_ARROW, _display_score(item), "ScoreCount")
	_stat(stats, ICONS.replay, int(item.get("replayCount", 0)), "ReplayCount")
	var content_height := details.get_combined_minimum_size().y
	preview.custom_minimum_size = Vector2.ONE * content_height
	play.custom_minimum_size.y = content_height + 32
	content.add_child(_author(str(item.get("author", ""))))
	_hover_card(play, preview)
	if str(item.get("id", "")) == published_id:
		play.modulate = Color("ffd49e")
		play.create_tween().tween_property(play, "modulate", Color.WHITE, 0.8)
	if service.owned.has(item.get("id")):
		row.add_child(_icon("edit", func():
			var level := CommunityCodec.decode_level(str(item.get("code", "")))
			if not level.is_empty():
				open_editor(level, str(item.id), int(item.get("revision", 1)))
		))
		row.add_child(_icon("delete", func(): _confirm_delete(item)))
	row.add_child(_icon("replay", func(): show_replays(item)))

func _card_content(parent: Button, vertical_padding: int = 12) -> HBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", vertical_padding)
	margin.add_theme_constant_override("margin_bottom", vertical_padding)
	parent.add_child(margin)
	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	return content

func _preview(level: Dictionary, side: int) -> CommunityPreview:
	var preview := CommunityPreview.new()
	preview.name = "PuzzlePreview"
	preview.layout = level
	preview.custom_minimum_size = Vector2(side, side)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return preview

func _author(value: String, width: int = 180) -> Label:
	var author := _label(value, 14)
	author.name = "Author"
	author.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	author.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	author.size_flags_horizontal = Control.SIZE_SHRINK_END
	author.custom_minimum_size.x = width
	author.mouse_filter = Control.MOUSE_FILTER_IGNORE
	author.tooltip_text = value
	return author

func _stat(parent: Control, texture: Texture2D, count: int, key: String) -> void:
	var stat := HBoxContainer.new()
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.add_theme_constant_override("separation", 4)
	parent.add_child(stat)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(14, 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.add_child(icon)
	var value := _label(str(count), 13)
	value.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	value.name = key
	value.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.add_child(value)

func _hover_card(card: Button, preview: Control = null) -> void:
	var motion: Array[Tween] = []
	var animate := func(hovered: bool):
		if not motion.is_empty():
			motion[0].kill()
			motion.clear()
		var tween := card.create_tween().set_parallel(true)
		motion.append(tween)
		if is_instance_valid(preview):
			preview.pivot_offset = preview.size * 0.5
			tween.tween_property(preview, "scale", Vector2.ONE * (1.045 if hovered else 1.0), 0.14).set_trans(Tween.TRANS_SINE)
		tween.tween_property(card, "self_modulate", Color(1.08, 1.08, 1.08) if hovered else Color.WHITE, 0.14)
	card.mouse_entered.connect(func(): animate.call(true))
	card.mouse_exited.connect(func(): animate.call(false))

func _confirm_delete(item: Dictionary) -> void:
	if is_instance_valid(modal):
		return
	var dialog := _dialog("Delete level", "Delete")
	dialog.body.add_child(_label("Delete “%s”?" % str(item.name)))
	dialog.confirmed.connect(func():
		_close_dialog(dialog)
		var result := await service.request("delete", {"id": item.id, "revision": item.revision})
		if not is_inside_tree():
			return
		if view == "browser":
			feedback.text = str(result.get("error", ""))
			if not result.has("error"):
				_fetch_levels(false)
	)

func open_editor(level: Dictionary = {}, id: String = "", revision: int = 0) -> void:
	var saved := CustomLevelEditor.read_saved_draft()
	var resume := level.is_empty() or (not id.is_empty() and str(saved.get("level_id", "")) == id and int(saved.get("revision", 0)) == revision)
	if resume and not saved.is_empty():
		level = saved.layout
		id = str(saved.get("level_id", ""))
		revision = int(saved.get("revision", 0))
	_clear("editor")
	# The editor is a separate scene; no campaign layout or progress is modified.
	shell.get_parent().hide()
	editing_id = id
	editing_revision = revision
	editor = EditorScene.instantiate()
	editor.publish_guard = _can_publish_level
	editor.level_id = id
	editor.revision = revision
	if resume:
		editor.restored_state = saved
	if not level.is_empty():
		editor.draft = level.duplicate(true)
	add_child(editor)
	editor.exited.connect(show_browser)
	editor.publish_requested.connect(_publish_dialog)
	if is_instance_valid(audio):
		editor.board.line_tile_added.connect(audio.play_click)
		editor.board.line_tile_removed.connect(audio.play_place)
		editor.victory_started.connect(audio.play_victory)

func _publish_dialog(level: Dictionary, solution: Array) -> void:
	if is_instance_valid(modal):
		return
	if not _can_publish_level():
		return
	var dialog := _dialog("Publish Level", "Publish")
	editor.popup = dialog
	var preview_center := CenterContainer.new()
	dialog.body.add_child(preview_center)
	preview_center.add_child(_preview(level, 144))
	var fields := VBoxContainer.new()
	fields.custom_minimum_size.x = 300
	dialog.body.add_child(fields)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Puzzle Name"
	name_input.max_length = 80
	name_input.text = str(level.get("name", ""))
	fields.add_child(name_input)
	var author := LineEdit.new()
	author.placeholder_text = "Author"
	author.max_length = 48
	author.text = str(level.get("author", ""))
	fields.add_child(author)
	name_input.text_changed.connect(func(value: String):
		if is_instance_valid(editor):
			editor.draft.name = value
			editor.save_draft()
	)
	author.text_changed.connect(func(value: String):
		if is_instance_valid(editor):
			editor.draft.author = value
			editor.save_draft()
	)
	var error := _label("")
	fields.add_child(error)
	var upload := func():
		if pending:
			return
		if not _can_publish_level():
			return
		pending = true
		editor.publishing = true
		dialog.set_busy(true)
		level.name = name_input.text.strip_edges()
		level.author = author.text.strip_edges()
		var code := CommunityCodec.encode_level(level)
		var proof: Array = []
		for cell in solution:
			proof.append([0, cell])
		var result := await service.request("publish", {"id": editing_id, "revision": editing_revision, "code": code, "proof": CommunityCodec.encode_replay(proof)})
		if not is_inside_tree():
			return
		pending = false
		if not is_instance_valid(dialog) or not is_instance_valid(editor):
			return
		editor.publishing = false
		dialog.set_busy(false)
		if result.has("error"):
			if result.error == "publish_cooldown":
				service.remember_publish_cooldown(int(result.get("retryAfterMs", 0)))
				_show_publish_cooldown(service.publish_remaining_ms())
				return
			error.text = str(result.error)
			return
		_after_publish(str(result.id))
	dialog.confirmed.connect(func():
		if pending:
			return
		if name_input.text.strip_edges().is_empty() or author.text.strip_edges().is_empty():
			error.text = "Puzzle Name · Author"
			return
		if not _can_publish_level():
			return
		if editing_id.is_empty():
			upload.call()
			return
		var confirmation := _dialog("Publish Level", "Publish")
		var warning := _label("This will remove all votes and replays on your level", 18)
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		confirmation.body.add_child(warning)
		editor.popup = confirmation
		confirmation.cancel_button.grab_focus()
		confirmation.confirmed.connect(func():
			_close_dialog(confirmation, dialog)
			upload.call()
		)
	)
	name_input.grab_focus()

func _can_publish_level() -> bool:
	var remaining := service.publish_remaining_ms()
	if remaining > 0:
		_show_publish_cooldown(remaining)
		return false
	return true

func _show_publish_cooldown(remaining_ms: int) -> void:
	var previous := modal
	var dialog := _dialog("", "OK", "")
	dialog.name = "PublishCooldown"
	dialog.panel.custom_minimum_size.x = 420
	var message := _label("", 18)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	dialog.body.add_child(message)
	var deadline := Time.get_ticks_msec() + remaining_ms
	var update := func():
		var seconds := maxi(0, ceili(float(deadline - Time.get_ticks_msec()) / 1000))
		message.text = "Hold it there, partner.\n\nYou're publishing a bit too fast.\n%d:%02d" % [int(seconds / 60), seconds % 60]
	update.call()
	var countdown := Timer.new()
	countdown.wait_time = 0.1
	dialog.add_child(countdown)
	countdown.timeout.connect(update)
	countdown.start()
	if is_instance_valid(editor):
		editor.popup = dialog
	dialog.confirmed.connect(func(): _close_dialog(dialog, previous))
	dialog.confirm_button.grab_focus()

func _after_publish(level_id: String) -> void:
	if is_instance_valid(editor):
		editor.discard_draft()
	published_id = level_id
	search_text = ""
	sort_by = "Hot"
	show_browser()

func _play_board(item: Dictionary, replay: bool = false) -> bool:
	var level := CommunityCodec.decode_level(str(item.get("code", "")))
	if level.is_empty():
		feedback = _label("Invalid level")
		shell.add_child(feedback)
		shell.add_child(_button("Back", show_browser))
		return false
	selected = item.duplicate(true)
	var header := HBoxContainer.new()
	shell.add_child(header)
	header.add_child(_label(str(level.name), 26))
	header.add_child(_author(str(level.author)))
	board = PuzzleBoard.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(board)
	board.configure(level, Color(level.color), LevelStore.DEFAULT_LINE_COLOR)
	board.locked = replay
	if is_instance_valid(audio) and not replay:
		board.line_tile_added.connect(audio.play_click)
		board.line_tile_removed.connect(audio.play_place)
	return true

func play_level(item: Dictionary) -> void:
	_clear("play")
	if not _play_board(item):
		return
	events.clear()
	last_event_time = Time.get_ticks_msec()
	board.line_tile_added.connect(func(cell: int): _record(cell))
	board.line_tile_removed.connect(func(_cell: int): _record(-1))
	board.solved.connect(_puzzle_solved)
	play_actions = HBoxContainer.new()
	play_actions.name = "PuzzleActions"
	play_actions.alignment = BoxContainer.ALIGNMENT_END
	add_child(play_actions)
	var reset := _button("Reset", func(): board.clear_path())
	reset.name = "ResetPuzzle"
	play_actions.add_child(reset)
	var back := _button("Back", func(): _finish_play(false))
	back.name = "BackToCustomLevels"
	play_actions.add_child(back)
	play_actions.minimum_size_changed.connect(_position_play_actions)
	_position_play_actions()

func _position_play_actions() -> void:
	if not is_instance_valid(play_actions):
		return
	var height := play_actions.get_combined_minimum_size().y
	play_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	play_actions.offset_left = 24
	play_actions.offset_right = -24
	play_actions.offset_top = -24 - height
	play_actions.offset_bottom = -24
	var margins := shell.get_parent() as MarginContainer
	margins.add_theme_constant_override("margin_bottom", int(height) + 38)

func _record(cell: int) -> void:
	var now := Time.get_ticks_msec()
	if events.size() < CommunityCodec.MAX_EVENTS:
		events.append([mini(now - last_event_time, 5000), cell])
	last_event_time = now

func _puzzle_solved() -> void:
	winning = true
	var ticket := generation
	if is_instance_valid(audio):
		audio.play_victory()
	await VictoryPulse.play(board)
	if not is_inside_tree() or generation != ticket:
		return
	winning = false
	_finish_play(true)

func _finish_play(won: bool) -> void:
	if is_instance_valid(modal) or winning:
		return
	board._end()
	board.locked = true
	var dialog := _dialog(str(selected.get("name", "")), "Back" if won else "Leave", "" if won else "Nevermind")
	dialog.title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog.confirm_button.theme_type_variation = "Button"
	dialog.dock_right()
	var play_margins := shell.get_parent() as MarginContainer
	play_margins.add_theme_constant_override("margin_right", 424)
	dialog.veil.color = Color(0.01, 0.02, 0.03, 0.42)
	var content := dialog.body
	var author := _label("By: " + str(selected.get("author", "")), 14)
	author.name = "PuzzleAuthor"
	author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(author)
	var voting := HBoxContainer.new()
	voting.alignment = BoxContainer.ALIGNMENT_CENTER
	voting.add_theme_constant_override("separation", 0)
	content.add_child(voting)
	var vote_prompt := _label("Vote", 16)
	vote_prompt.name = "VotePrompt"
	vote_prompt.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	vote_prompt.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vote_prompt.custom_minimum_size.x = 36
	vote_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	voting.add_child(vote_prompt)
	votes.clear()
	var error := _label("")
	error.hide()
	for direction in [1, -1]:
		var vote := _button("", func():
			for node in votes:
				node.disabled = true
			var value: int = 0 if int(selected.get("vote", 0)) == direction else direction
			var previous := int(selected.get("vote", 0))
			var previous_score := int(selected.get("rawScore", selected.get("score", 0)))
			selected.vote = value
			selected.rawScore = previous_score + value - previous
			selected.score = _display_score(selected)
			_update_votes(true)
			var result := await service.request("vote", {"id": selected.id, "value": value, "revision": selected.revision})
			if not is_instance_valid(dialog):
				return
			error.text = str(result.get("error", ""))
			error.visible = result.has("error")
			if not result.has("error"):
				selected.rawScore = int(result.get("rawScore", result.get("score", selected.rawScore)))
				if result.has("created"):
					selected.created = result.created
				selected.score = _display_score(selected)
			else:
				selected.vote = previous
				selected.rawScore = previous_score
				selected.score = _display_score(selected)
			for node in votes:
				node.disabled = false
			_update_votes(true)
		)
		vote.icon = VOTE_ARROW
		vote.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vote.add_theme_constant_override("icon_max_width", 28)
		vote.custom_minimum_size = Vector2(36, 44)
		vote.tooltip_text = "Upvote" if direction == 1 else "Downvote"
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			vote.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		if direction == -1:
			vote.icon = preload("res://assets/community_downvote.svg")
		vote.set_meta("direction", direction)
		votes.append(vote)
		voting.add_child(vote)
		if direction == 1:
			vote_score = _label(str(_display_score(selected)), 24)
			vote_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vote_score.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			vote_score.custom_minimum_size.x = 36
			voting.add_child(vote_score)
	_update_votes()
	var publish := _button("Publish Replay", _publish_replay)
	publish.name = "PublishReplay"
	publish.theme_type_variation = "PrimaryButton"
	publish.visible = won
	publish.disabled = events.is_empty() or events.size() >= CommunityCodec.MAX_EVENTS
	dialog.actions.add_theme_constant_override("separation", 6)
	dialog.actions.alignment = BoxContainer.ALIGNMENT_CENTER
	dialog.actions.add_child(publish)
	dialog.actions.move_child(publish, 0)
	if won:
		var again := _button("Play Again", func(): play_level(selected.duplicate(true)))
		again.name = "PlayAgain"
		dialog.actions.add_child(again)
		dialog.actions.move_child(again, dialog.confirm_button.get_index())
	for action in dialog.actions.get_children():
		if action is Button:
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				var style := action.get_theme_stylebox(state, "PrimaryButton" if action == publish else "Button").duplicate() as StyleBoxFlat
				style.content_margin_left = 8
				style.content_margin_right = 8
				action.add_theme_stylebox_override(state, style)
	content.add_child(error)
	dialog.confirmed.connect(show_browser)
	dialog.canceled.connect(func():
		board.locked = won
		play_margins.add_theme_constant_override("margin_right", 24)
	)

func _display_score(item: Dictionary) -> int:
	var score := int(item.get("rawScore", item.get("score", 0)))
	if item.has("created") and Time.get_unix_time_from_system() * 1000 < float(item.created) + 86400000:
		return maxi(0, score)
	return score

func _update_votes(animate: bool = false) -> void:
	if is_instance_valid(vote_score):
		var changed := vote_score.text != str(_display_score(selected))
		vote_score.text = str(_display_score(selected))
		if changed and animate:
			if vote_score_tween:
				vote_score_tween.kill()
			vote_score.scale = Vector2.ONE
			vote_score.pivot_offset = vote_score.size * 0.5
			vote_score_tween = create_tween()
			vote_score_tween.tween_property(vote_score, "scale", Vector2.ONE * 1.18, 0.09).set_trans(Tween.TRANS_SINE)
			vote_score_tween.tween_property(vote_score, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_SINE)
	for node in votes:
		var color := VOTE_ORANGE if int(node.get_meta("direction")) == int(selected.get("vote", 0)) else Color.WHITE
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]:
			node.add_theme_color_override(state, color)

func _publish_replay() -> void:
	if pending or not is_instance_valid(board) or not Puzzle.is_complete(board.tiles, board.path):
		return
	var name_dialog := _dialog("Publish Replay", "Publish")
	name_dialog.body.add_child(_label("Author", 14))
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Author"
	name_input.max_length = 48
	name_input.custom_minimum_size.x = 260
	name_dialog.body.add_child(name_input)
	var upload_error := _label("")
	name_dialog.body.add_child(upload_error)
	name_dialog.confirmed.connect(func():
		if pending or name_input.text.strip_edges().is_empty():
			return
		pending = true
		name_dialog.set_busy(true)
		var result := await service.request("publishReplay", {"id": selected.id, "revision": selected.revision, "author": name_input.text.strip_edges(), "code": CommunityCodec.encode_replay(events)})
		pending = false
		if not is_instance_valid(name_dialog):
			return
		name_dialog.set_busy(false)
		if result.has("error"):
			upload_error.text = str(result.error)
			return
		_after_publish(str(selected.id))
	)
	name_input.grab_focus()

func show_replays(item: Dictionary) -> void:
	_clear("replays")
	selected = item.duplicate(true)
	var header := HBoxContainer.new()
	shell.add_child(header)
	header.add_child(_label(str(item.name), 28))
	header.add_child(_author(str(item.author)))
	rows = _scroll()
	feedback = _label("…")
	shell.add_child(feedback)
	var footer := HBoxContainer.new()
	footer.name = "ReplayActions"
	shell.add_child(footer)
	footer.add_child(_button("Back", show_browser))
	replay_more_button = _button("More", func():
		if replay_cursor != null:
			_fetch_replays(item, true)
	)
	replay_more_button.hide()
	footer.add_child(replay_more_button)
	replay_cursor = null
	_fetch_replays(item, false)

func _fetch_replays(item: Dictionary, append: bool) -> void:
	if view != "replays":
		return
	generation += 1
	var ticket := generation
	replay_more_button.disabled = true
	var result := await service.request("replays", {"id": item.id, "cursor": replay_cursor if append else null})
	if not is_inside_tree() or ticket != generation:
		return
	feedback.text = str(result.get("error", ""))
	replay_more_button.disabled = false
	if result.has("error"):
		return
	replay_cursor = result.get("cursor")
	replay_more_button.visible = replay_cursor != null
	if not append:
		for row in rows.get_children():
			rows.remove_child(row)
			row.queue_free()
	for replay in result.get("replays", []):
		var wrapper := HBoxContainer.new()
		wrapper.add_theme_constant_override("separation", 4)
		rows.add_child(wrapper)
		var row := _button("", func():
			var recorded := item.duplicate(true)
			recorded.code = str(replay.get("levelCode", item.code))
			watch_replay(recorded, replay)
		)
		row.name = "ReplayCard"
		row.custom_minimum_size.y = 46
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_replay_button_padding(row)
		wrapper.add_child(row)
		var content := _card_content(row, 6)
		var duration := _label("%.1fs" % (float(replay.duration) / 1000.0))
		duration.name = "ReplayTime"
		duration.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		duration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(duration)
		content.add_child(_author(str(replay.author)))
		_hover_card(row)
		if bool(replay.get("owned", false)):
			var remove := _icon("delete", func(): _confirm_delete_replay(item, replay))
			remove.name = "DeleteReplay"
			remove.tooltip_text = "Delete replay"
			_replay_button_padding(remove)
			wrapper.add_child(remove)

func _replay_button_padding(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := theme.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, style)

func _confirm_delete_replay(item: Dictionary, replay: Dictionary) -> void:
	if is_instance_valid(modal):
		return
	var dialog := _dialog("Delete replay", "Delete")
	dialog.body.add_child(_label("Delete this replay?"))
	var error := _label("")
	dialog.body.add_child(error)
	dialog.confirmed.connect(func():
		if pending:
			return
		pending = true
		dialog.set_busy(true)
		dialog.confirm_button.text = "Deleting…"
		var ticket := generation
		var result := await service.request("deleteReplay", {"id": replay.id})
		if not is_inside_tree() or generation != ticket or not is_instance_valid(dialog):
			return
		pending = false
		dialog.set_busy(false)
		if result.has("error"):
			error.text = str(result.error)
			return
		_close_dialog(dialog)
		_fetch_replays(item, false)
	)

func watch_replay(item: Dictionary, replay: Dictionary) -> void:
	_clear("replay")
	if not _play_board(item, true):
		return
	replay_events = CommunityCodec.decode_replay(str(replay.code), board.tiles.size())
	replay_times.clear()
	replay_paths.clear()
	var path: Array = []
	var time := 0
	for event in replay_events:
		time += int(event[0])
		if int(event[1]) == -2:
			path.clear()
		elif int(event[1]) == -1:
			if path.is_empty():
				break
			path.pop_back()
		elif Puzzle.can_append(path, int(event[1]), board.width, board.height):
			path.append(int(event[1]))
		else:
			break
		replay_times.append(time)
		# Sparse checkpoints bound memory and allow quick seeking in long replays.
		if replay_times.size() % 128 == 1:
			replay_paths.append(path.duplicate())
	replay_input_duration = float(time)
	replay_duration = replay_input_duration + REPLAY_MOVE_MS
	replay_position = 0.0
	replay_render_index = -2
	timeline = HSlider.new()
	timeline.max_value = maxf(1, replay_duration)
	timeline.step = 1
	timeline.value_changed.connect(_seek_replay)
	timeline.drag_started.connect(func(): replay_seeking = true)
	timeline.drag_ended.connect(func(_changed: bool): replay_seeking = false)
	shell.add_child(timeline)
	var controls := HBoxContainer.new()
	shell.add_child(controls)
	controls.add_child(_button("Back", func(): show_replays(item)))
	_spacer(controls)
	replay_button = _button("Pause", func():
		if replay_position >= replay_duration:
			replay_position = 0
		replay_playing = not replay_playing
		replay_button.text = "Pause" if replay_playing else "Play"
	)
	controls.add_child(replay_button)
	replay_playing = true
	_seek_replay(0)

func _replay_path(index: int) -> Array:
	var path: Array = []
	var first := 0
	if index >= 0:
		var checkpoint := int(index / 128)
		path = replay_paths[checkpoint].duplicate()
		first = checkpoint * 128 + 1
	for cursor in range(first, index + 1):
		var action := int(replay_events[cursor][1])
		if action == -2:
			path.clear()
		elif action == -1:
			path.pop_back()
		else:
			path.append(action)
	return path

func _seek_replay(value: float) -> void:
	replay_position = value
	var index := replay_times.bsearch(value, false) - 1
	var path := _replay_path(index)
	if index != replay_render_index:
		board.path = path
		board.refresh()
		replay_render_index = index
	if index < 0:
		board._set_visual_line(PackedVector2Array())
		return
	# Equal timestamps are one ordered burst. Interpolate its entire route,
	# preserving corners, instead of resetting the line animation every frame.
	var first := index
	while first > 0 and replay_times[first - 1] == replay_times[index]:
		first -= 1
	var initial := PackedVector2Array()
	for cell in _replay_path(first - 1):
		initial.append(board.center(int(cell)))
	var target := PackedVector2Array()
	for cell in path:
		target.append(board.center(int(cell)))
	var duration := REPLAY_MOVE_MS
	if index + 1 < replay_times.size():
		duration = minf(duration, float(replay_times[index + 1] - replay_times[index]))
	var progress := clampf((value - float(replay_times[index])) / maxf(1, duration), 0, 1)
	board._set_visual_line(_sample_line(initial, target, progress))

func _sample_line(initial: PackedVector2Array, target: PackedVector2Array, progress: float) -> PackedVector2Array:
	if initial.is_empty() or progress >= 1:
		return target
	if target.is_empty():
		return board._clip_polyline(initial, board._polyline_length(initial) * (1 - progress)) if progress < 1 else target
	var common := 0
	while common < mini(initial.size(), target.size()) and initial[common].is_equal_approx(target[common]):
		common += 1
	if common == 0:
		return target
	var before := board._polyline_length(initial)
	var shared := board._polyline_length(initial, common)
	var retreat := before - shared
	var advance := board._polyline_length(target) - shared
	var distance := (retreat + advance) * progress
	return board._clip_polyline(initial, before - distance) if distance < retreat else board._clip_polyline(target, shared + distance - retreat)

func _process(delta: float) -> void:
	if view == "replay" and replay_playing and not replay_seeking:
		replay_position = minf(replay_duration, replay_position + delta * 1000)
		timeline.set_value_no_signal(replay_position)
		_seek_replay(replay_position)
		if replay_position >= replay_duration:
			replay_playing = false
			replay_button.text = "Play"

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if is_instance_valid(modal):
		return
	if view == "editor" and is_instance_valid(editor):
		if is_instance_valid(editor.popup) or editor.color_input.get_popup().visible:
			return
	# Navigation can remove this node synchronously. Consume the key while
	# the viewport is still available, before returning to another screen.
	get_viewport().set_input_as_handled()
	if view == "play":
		_finish_play(false)
	elif view == "replay":
		show_replays(selected)
	elif view == "replays":
		show_browser()
	elif view == "editor":
		show_browser()
	else:
		closed.emit()
