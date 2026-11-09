class_name CustomLevelEditor
extends Control

signal exited
signal publish_requested(level: Dictionary, solution: Array)
signal victory_started

var draft: Dictionary = {"width": 8, "height": 8, "tiles": [], "color": "a9dfcc", "name": "", "author": ""}
var board: PuzzleBoard
var brush := 1
var playtesting := false
var solution: Array = []
var test_path: Array = []
var publish_pending := false
var play_button: Button
var width_input: SpinBox
var height_input: SpinBox
var color_input: ColorPickerButton
var hue_slider: HSlider
var popup: Node
var tools: HBoxContainer
var feedback: Label
var palette: Array[Button] = []
var publishing := false
var import_text: TextEdit
var clipboard_callback: JavaScriptObject
var clipboard_error: JavaScriptObject
var export_button: Button
var import_button: Button
var winning := false
var background: ColorRect
var publish_button: Button
var publish_guard: Callable
var level_id := ""
var revision := 0
var restored_state: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var stroke_before: Dictionary = {}
var restoring := false
var initialized := false
var retain_draft := true
var color_swatch_style: StyleBoxFlat
const DRAFT_PATH := "user://editor_draft.save"
const DRAFT_KEY := "hearthline_editor_draft"
const SWATCH_SIZE := 54

func _ready() -> void:
	if draft.tiles.is_empty():
		draft.tiles.resize(int(draft.width) * int(draft.height))
		draft.tiles.fill(0)
	background = ColorRect.new()
	background.color = PuzzleBoard.background_color(Color(draft.color))
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	board = PuzzleBoard.new()
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size = Vector2(0, 100)
	layout.add_child(board)
	board.cell_painted.connect(_paint)
	board.light_painted.connect(func(cell: int): _paint(cell, 0))
	board.cell_sampled.connect(func(cell: int): _select_brush(int(draft.tiles[cell])))
	board.paint_started.connect(_begin_stroke)
	board.paint_finished.connect(_finish_stroke)
	board.solved.connect(_solved)
	var bar := PanelContainer.new()
	bar.name = "EditorBarPanel"
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = background.color.lightened(0.025)
	bar_style.set_content_margin_all(0)
	bar.add_theme_stylebox_override("panel", bar_style)
	layout.add_child(bar)
	var bar_margins := MarginContainer.new()
	bar_margins.name = "EditorBarPadding"
	for side in ["left", "right", "top", "bottom"]:
		bar_margins.add_theme_constant_override("margin_" + side, 16)
	bar.add_child(bar_margins)
	var bar_scroll := ScrollContainer.new()
	bar_scroll.name = "EditorBarScroll"
	bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar_margins.add_child(bar_scroll)
	var rows := HBoxContainer.new()
	rows.name = "EditorBar"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.alignment = BoxContainer.ALIGNMENT_END
	rows.add_theme_constant_override("separation", 6)
	bar_scroll.add_child(rows)
	tools = HBoxContainer.new()
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_theme_constant_override("separation", 6)
	rows.add_child(tools)
	for value in [1, 0, 2]:
		var swatch := _button("", func(): _select_brush(value))
		swatch.tooltip_text = ["White (2)", "Black (1)", "Gray (3)"][value]
		swatch.toggle_mode = true
		swatch.custom_minimum_size = Vector2.ONE * SWATCH_SIZE
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.set_meta("brush", value)
		palette.append(swatch)
		tools.add_child(swatch)
	width_input = _spin(int(draft.width))
	height_input = _spin(int(draft.height))
	width_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	height_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(width_input)
	var times := Label.new()
	times.text = "×"
	tools.add_child(times)
	tools.add_child(height_input)
	width_input.value_changed.connect(_resize_board)
	height_input.value_changed.connect(_resize_board)
	color_input = ColorPickerButton.new()
	color_input.custom_minimum_size = Vector2.ONE * SWATCH_SIZE
	color_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	color_input.tooltip_text = "Tile color"
	color_input.color = Color(draft.color)
	color_input.edit_alpha = false
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("233440")
		style.set_content_margin_all(4)
		style.set_corner_radius_all(8)
		color_input.add_theme_stylebox_override(state, style)
	color_input.color_changed.connect(_change_color)
	color_input.get_popup().visibility_changed.connect(func():
		if color_input.get_popup().visible:
			_begin_stroke()
		else:
			_finish_stroke()
	)
	tools.add_child(color_input)
	var picker := color_input.get_picker()
	picker.picker_shape = ColorPicker.SHAPE_NONE
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.hex_visible = false
	picker.sampler_visible = false
	picker.presets_visible = false
	hue_slider = HSlider.new()
	hue_slider.name = "HueSlider"
	hue_slider.max_value = 1.0
	hue_slider.step = 0.001
	hue_slider.custom_minimum_size = Vector2(256, 32)
	hue_slider.value = Color(draft.color).h
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 1.0 / 6, 2.0 / 6, 0.5, 4.0 / 6, 5.0 / 6, 1])
	var colors := PackedColorArray()
	for hue in gradient.offsets:
		colors.append(Color.from_hsv(hue, 1, 1))
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 16
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	var track := StyleBoxTexture.new()
	track.texture = texture
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	hue_slider.add_theme_stylebox_override("slider", track)
	hue_slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	hue_slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	picker.add_child(hue_slider)
	hue_slider.value_changed.connect(func(hue: float): _change_color(Color.from_hsv(hue, 1, 1)))
	# ColorPickerButton's built-in color fill is rectangular. Draw a rounded
	# swatch as a child while keeping the native picker and input behavior.
	color_input.self_modulate.a = 0
	var color_surface := Panel.new()
	color_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_swatch_style = StyleBoxFlat.new()
	color_swatch_style.bg_color = PuzzleBoard.tile_color(0, Color(draft.color))
	color_swatch_style.set_corner_radius_all(8)
	color_surface.add_theme_stylebox_override("panel", color_swatch_style)
	color_input.add_child(color_surface)
	color_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var picker_icon := TextureRect.new()
	picker_icon.name = "ColorPickerIcon"
	picker_icon.texture = preload("res://assets/color_picker.svg")
	picker_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_input.add_child(picker_icon)
	picker_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	picker_icon.offset_left = -14
	picker_icon.offset_top = -14
	picker_icon.offset_right = 14
	picker_icon.offset_bottom = 14
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(gap)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 6)
	rows.add_child(actions)
	feedback = Label.new()
	feedback.clip_text = true
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(feedback)
	export_button = _button("Export", _export)
	import_button = _button("Import", _import)
	actions.add_child(export_button)
	actions.add_child(import_button)
	play_button = _button("Play Puzzle", toggle_play)
	actions.add_child(play_button)
	publish_button = _button("Publish", request_publish)
	publish_button.name = "PublishLevel"
	actions.add_child(publish_button)
	CommunityStyle.accent(publish_button)
	actions.add_child(_button("Exit", func(): exited.emit()))
	if not restored_state.is_empty():
		brush = clampi(int(restored_state.get("brush", 1)), 0, 2)
		solution = LevelStore._valid_solution_path(draft, restored_state.get("solution", []))
	_select_brush(brush)
	_sync_board()
	initialized = true
	save_draft()

static func read_saved_draft() -> Dictionary:
	var saved := LevelStore._read_json(DRAFT_PATH)
	if OS.has_feature("web"):
		var encoded: Variant = JavaScriptBridge.eval("(() => { try { return localStorage.getItem('" + DRAFT_KEY + "') || ''; } catch (_) { return ''; } })()")
		if encoded is String and not encoded.is_empty():
			var decoded: Variant = JSON.parse_string(CommunityCodec._open(encoded, "HD1.").get_string_from_utf8())
			if decoded is Dictionary:
				saved = decoded
	if not saved.get("layout") is Dictionary or not CommunityCodec.valid_layout(saved.layout):
		return {}
	saved.layout.width = int(saved.layout.width)
	saved.layout.height = int(saved.layout.height)
	for index in range(saved.layout.tiles.size()):
		saved.layout.tiles[index] = int(saved.layout.tiles[index])
	if not Color.html_is_valid(str(saved.layout.get("color", ""))):
		saved.layout.color = "a9dfcc"
	return saved

static func clear_saved_draft() -> void:
	if FileAccess.file_exists(DRAFT_PATH):
		DirAccess.remove_absolute(DRAFT_PATH)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.removeItem('" + DRAFT_KEY + "'); } catch (_) {}")

func discard_draft() -> void:
	retain_draft = false
	clear_saved_draft()

func save_draft() -> void:
	if not initialized or not retain_draft:
		return
	var value := {"layout": draft, "solution": solution, "brush": brush, "level_id": level_id, "revision": revision}
	LevelStore._atomic_write(DRAFT_PATH, value)
	if OS.has_feature("web"):
		var encoded := CommunityCodec._seal(JSON.stringify(value).to_utf8_buffer(), "HD1.")
		JavaScriptBridge.eval("try { localStorage.setItem('" + DRAFT_KEY + "', " + JSON.stringify(encoded) + "); } catch (_) {}")

func _exit_tree() -> void:
	save_draft()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and initialized:
		_finish_stroke()
		save_draft()

func _state() -> Dictionary:
	return {"draft": draft.duplicate(true), "solution": solution.duplicate()}

func _begin_stroke() -> void:
	if stroke_before.is_empty() and not playtesting:
		stroke_before = _state()

func _commit(before: Dictionary) -> void:
	if not before.is_empty() and before.draft != draft:
		undo_stack.append(before)
		if undo_stack.size() > 100:
			undo_stack.pop_front()
		redo_stack.clear()
		save_draft()

func _finish_stroke() -> void:
	var before := stroke_before
	stroke_before = {}
	_commit(before)

func _restore_state(value: Dictionary) -> void:
	restoring = true
	draft = value.draft.duplicate(true)
	solution = value.solution.duplicate()
	test_path.clear()
	publish_pending = false
	feedback.text = ""
	width_input.set_value_no_signal(draft.width)
	height_input.set_value_no_signal(draft.height)
	color_input.color = Color(draft.color)
	_sync_board()
	restoring = false
	save_draft()

func undo() -> void:
	if playtesting or publishing or winning:
		return
	_finish_stroke()
	if not undo_stack.is_empty():
		redo_stack.append(_state())
		_restore_state(undo_stack.pop_back())

func redo() -> void:
	if playtesting or publishing or winning:
		return
	if not redo_stack.is_empty():
		undo_stack.append(_state())
		_restore_state(redo_stack.pop_back())

func _change_color(color: Color) -> void:
	if restoring or draft.color == color.to_html(false):
		return
	var before := _state()
	draft.color = color.to_html(false)
	_invalidate_solution()
	_sync_board()
	if stroke_before.is_empty():
		_commit(before)
	save_draft()

func _button(text: String, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.pressed.connect(action)
	return node

func _spin(value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 32
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size.x = 70
	return spin

func _select_brush(value: int) -> void:
	brush = value
	board.brush_preview = value
	board._redraw_tiles()
	for node in palette:
		node.button_pressed = int(node.get_meta("brush")) == value
		for state in ["normal", "hover", "pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = PuzzleBoard.tile_color(int(node.get_meta("brush")), Color(draft.color))
			style.set_content_margin_all(0)
			style.set_corner_radius_all(8)
			style.set_border_width_all(2 if node.button_pressed else 0)
			style.border_color = Color("eae345")
			node.add_theme_stylebox_override(state, style)
	save_draft()

func _sync_board() -> void:
	background.color = PuzzleBoard.background_color(Color(draft.color))
	color_swatch_style.bg_color = PuzzleBoard.tile_color(0, Color(draft.color))
	color_input.color = Color(draft.color)
	hue_slider.set_value_no_signal(Color(draft.color).h)
	board.configure(draft, Color(draft.color), LevelStore.DEFAULT_LINE_COLOR)
	board.editing = not playtesting
	board.path = test_path.duplicate() if playtesting else []
	board.refresh()
	board.locked = playtesting and not board.path.is_empty() and Puzzle.is_complete(draft.tiles, board.path)
	_select_brush(brush)

func _invalidate_solution() -> void:
	solution.clear()
	test_path.clear()
	publish_pending = false
	feedback.text = ""

func _paint(cell: int, value: int = -1) -> void:
	if playtesting or publishing:
		return
	var selected := brush if value < 0 else value
	if draft.tiles[cell] == selected:
		return
	var before := _state() if stroke_before.is_empty() else {}
	draft.tiles[cell] = selected
	_invalidate_solution()
	board.tiles[cell] = selected
	board.refresh()
	_commit(before)

func _resize_board(_value: float) -> void:
	if restoring:
		return
	var before := _state()
	var width := int(width_input.value)
	var height := int(height_input.value)
	var tiles: Array = []
	tiles.resize(width * height)
	tiles.fill(0)
	for y in range(mini(height, int(draft.height))):
		for x in range(mini(width, int(draft.width))):
			tiles[y * width + x] = draft.tiles[y * int(draft.width) + x]
	draft.width = width
	draft.height = height
	draft.tiles = tiles
	_invalidate_solution()
	_sync_board()
	_commit(before)

func toggle_play() -> void:
	if is_instance_valid(popup) or publishing or winning:
		return
	if playtesting:
		test_path = board.path.duplicate()
	playtesting = not playtesting
	play_button.text = "Edit Level" if playtesting else "Play Puzzle"
	_update_tools()
	for node in [width_input, height_input]:
		node.editable = not playtesting
	color_input.disabled = playtesting
	for node in palette:
		node.disabled = playtesting
	_sync_board()

func _update_tools() -> void:
	tools.visible = not playtesting
	export_button.visible = not playtesting
	import_button.visible = not playtesting
	feedback.visible = not playtesting
	publish_button.visible = not playtesting

func _solved() -> void:
	solution = board.path.duplicate()
	test_path = solution.duplicate()
	save_draft()
	feedback.text = "✓"
	winning = true
	play_button.disabled = true
	victory_started.emit()
	await VictoryPulse.play(board)
	if not is_inside_tree():
		return
	winning = false
	play_button.disabled = false
	if publish_pending:
		publish_pending = false
		publish_requested.emit(draft.duplicate(true), solution.duplicate())

func request_publish() -> void:
	if publishing or is_instance_valid(popup):
		return
	if publish_guard.is_valid() and not publish_guard.call():
		return
	if not draft.tiles.has(1):
		feedback.text = "Add a black tile"
		return
	if solution.is_empty():
		if not playtesting:
			toggle_play()
		publish_pending = true
		var dialog := CommunityDialog.new()
		popup = dialog
		dialog.panel_color = background.color
		dialog.confirm_text = "Play Puzzle"
		dialog.cancel_text = ""
		add_child(dialog)
		var message := Label.new()
		message.text = "Complete the puzzle to upload."
		dialog.body.add_child(message)
		board.locked = true
		dialog.confirmed.connect(func():
			popup = null
			board.locked = false
			dialog.queue_free()
		)
		dialog.canceled.connect(func():
			popup = null
			board.locked = false
			dialog.queue_free()
		)
		return
	publish_requested.emit(draft.duplicate(true), solution.duplicate())

func _string_dialog(title: String, text: String, importing: bool) -> void:
	var dialog := AcceptDialog.new()
	popup = dialog
	dialog.title = title
	dialog.size = Vector2i(600, 240)
	dialog.min_size = Vector2i(300, 180)
	dialog.get_ok_button().text = "Import" if importing else "Done"
	var input := TextEdit.new()
	input.custom_minimum_size = Vector2(280, 160)
	input.text = text
	input.editable = importing
	import_text = input if importing else null
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	dialog.add_child(input)
	if not importing:
		var copy := dialog.add_button("Copy", false, "copy")
		copy.pressed.connect(func():
			if OS.has_feature("web"):
				JavaScriptBridge.eval("navigator.clipboard?.writeText(" + JSON.stringify(text) + ")")
			else:
				DisplayServer.clipboard_set(text)
		)
	else:
		dialog.add_button("Cancel", true, "cancel").pressed.connect(dialog.hide)
		dialog.window_input.connect(func(event: InputEvent):
			if OS.has_feature("web") and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and (event.ctrl_pressed or event.meta_pressed):
				if _paste_web_import():
					dialog.set_input_as_handled()
		)
		dialog.confirmed.connect(func():
			var loaded := CommunityCodec.decode_level(input.text)
			if loaded.is_empty():
				feedback.text = "Invalid level"
				return
			var before := _state()
			draft = loaded
			_invalidate_solution()
			if playtesting:
				playtesting = false
				play_button.text = "Play Puzzle"
			width_input.set_value_no_signal(draft.width)
			height_input.set_value_no_signal(draft.height)
			width_input.editable = true
			height_input.editable = true
			color_input.disabled = false
			color_input.color = Color(draft.color)
			for node in palette:
				node.disabled = false
			_sync_board()
			_update_tools()
			_commit(before)
		)
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			popup = null
			import_text = null
			dialog.queue_free()
	)
	dialog.popup_centered()
	input.grab_focus()
	input.select_all()

func _export() -> void:
	_string_dialog("Export", CommunityCodec.encode_level(draft), false)

func _import() -> void:
	_string_dialog("Import", "", true)

func _paste_web_import() -> bool:
	var navigator := JavaScriptBridge.get_interface("navigator")
	if navigator == null or navigator.clipboard == null:
		return false
	var input := import_text
	# Web clipboard reads are asynchronous. Insert after the browser resolves
	# the read rather than using Godot's previous cached clipboard contents.
	clipboard_callback = JavaScriptBridge.create_callback(func(arguments: Array):
		if is_instance_valid(input) and not arguments.is_empty():
			input.text = str(arguments[0])
	)
	clipboard_error = JavaScriptBridge.create_callback(func(_arguments: Array):
		if is_instance_valid(input):
			feedback.text = "Paste failed"
	)
	navigator.clipboard.readText().then(clipboard_callback, clipboard_error)
	return true

func _input(event: InputEvent) -> void:
	if not visible or is_instance_valid(popup):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or get_viewport().gui_get_hovered_control() is ColorPicker:
			return
		if color_input.get_popup().visible:
			return
		if not playtesting and event.ctrl_pressed and event.keycode in [KEY_Z, KEY_Y]:
			get_viewport().set_input_as_handled()
			if event.keycode == KEY_Y or event.shift_pressed:
				redo()
			else:
				undo()
		elif not playtesting and not event.ctrl_pressed and not event.alt_pressed and event.keycode in [KEY_1, KEY_2, KEY_3]:
			_select_brush([1, 0, 2][event.keycode - KEY_1])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE and not event.ctrl_pressed and not event.alt_pressed:
			toggle_play()
			get_viewport().set_input_as_handled()
