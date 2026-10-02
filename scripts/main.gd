extends Control

const BG := Color("0c1219")
const PANEL := Color("141e28")
const TEXT := Color("e8eee9")
const MUTED := Color("88979e")
const ACCENT := Color("b6ead3")

var store := LevelStore.new()
var screen := "menu"
var current_level := 1
var board: PuzzleBoard
var content: VBoxContainer
var overlay: Control
var toast: Label
var toast_timer := 0.0
var transition_id := 0
var menu_page := 0
var pressed_keys: Dictionary = {}
var chord_active := false
var pending_undo := false
var editor_level := 1
var editor_data: Dictionary
var undo_stack: Array = []
var redo_stack: Array = []
var stroke_before: Dictionary = {}
var brush := 1
var editor_message: Label
var width_input: SpinBox
var height_input: SpinBox
var brush_buttons: Array[Button] = []
var restoring_editor := false
var return_screen := "menu"
var saved_path: Array = []
var color_mode := false
var color_level := 1
var color_draft := Color.WHITE

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	_build_theme()
	show_menu()

func _build_theme() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 16
	theme_resource.set_color("font_color", "Label", TEXT)
	theme_resource.set_color("font_color", "Button", TEXT)
	theme_resource.set_color("font_hover_color", "Button", Color.WHITE)
	theme_resource.set_color("font_pressed_color", "Button", TEXT)
	theme_resource.set_constant("outline_size", "Label", 0)
	theme_resource.set_constant("separation", "VBoxContainer", 14)
	theme_resource.set_constant("separation", "HBoxContainer", 14)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var color := PANEL
		if state == "hover":
			color = Color("233440")
		if state == "pressed":
			color = Color("30483e")
		var style := box(color, 12)
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = ACCENT
			style.set_border_width_all(2)
		theme_resource.set_stylebox(state, "Button", style)
	theme = theme_resource

func box(color: Color, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func button(text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	if primary:
		var style := box(ACCENT, 12)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 14
		style.content_margin_bottom = 14
		node.add_theme_stylebox_override("normal", style)
		node.add_theme_color_override("font_color", BG)
	return node

func spacer(parent: Control) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func _shell() -> void:
	transition_id += 1
	for child in get_children():
		remove_child(child)
		child.queue_free()
	board = null
	toast = null
	overlay = null
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 28)
	add_child(margins)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	margins.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	header.add_child(label("a f t e r g l o w", 28, ACCENT))
	var separator := HSeparator.new()
	separator.modulate = Color(1, 1, 1, 0.16)
	content.add_child(separator)

func show_menu() -> void:
	screen = "menu"
	color_mode = false
	_shell()
	var menu_actions := HBoxContainer.new()
	content.add_child(menu_actions)
	spacer(menu_actions)
	menu_actions.add_child(button("Play level %02d   →" % store.frontier(), func(): play_level(store.frontier()), true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = mini(12, maxi(1, int((size.x - 88 + 12) / 76)))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var unlocked := store.frontier()
	menu_page = clampi(menu_page, 0, int((unlocked - 1) / 24))
	for number in range(menu_page * 24 + 1, mini(unlocked + 1, menu_page * 24 + 25)):
		grid.add_child(_level_card(number))
	if unlocked > 24:
		var pages := HBoxContainer.new()
		content.add_child(pages)
		var previous := button("← Previous", func(): menu_page -= 1; show_menu())
		previous.disabled = menu_page == 0
		pages.add_child(previous)
		spacer(pages)
		pages.add_child(label("Page %d" % (menu_page + 1), 14, MUTED))
		spacer(pages)
		var next := button("Next →", func(): menu_page += 1; show_menu())
		next.disabled = (menu_page + 1) * 24 >= unlocked
		pages.add_child(next)

func _level_card(number: int) -> Button:
	var card := button("", func(): play_level(number))
	card.custom_minimum_size = Vector2(64, 64)
	card.size_flags_horizontal = Control.SIZE_FILL
	card.tooltip_text = "Play level %d" % number
	var preview := TextureRect.new()
	preview.position = Vector2(4, 4)
	preview.size = Vector2(56, 43)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(preview)
	# The thumbnail is a live offscreen screenshot using the actual board renderer.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 200)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.gui_disable_input = true
	preview.add_child(viewport)
	var miniature := PuzzleBoard.new()
	miniature.size = Vector2(240, 200)
	viewport.add_child(miniature)
	miniature.configure(store.get_level(number), store.get_color(number))
	miniature.locked = true
	miniature.set_process_input(false)
	preview.texture = viewport.get_texture()
	var number_label := label("%02d" % number, 11)
	number_label.position = Vector2(7, 47)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(number_label)
	if store.completed.get(str(number), false):
		var checkmark := label("✓", 13, store.get_color(number))
		checkmark.position = Vector2(46, 46)
		checkmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(checkmark)
	return card

func play_level(number: int, restore: Array = []) -> void:
	current_level = number
	screen = "play"
	color_mode = false
	_shell()
	var level := store.get_level(number)
	var tint := store.get_color(number)
	content.add_child(label("Level %02d" % number, 38))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(PANEL, 24))
	content.add_child(panel)
	var play_area := Control.new()
	play_area.custom_minimum_size = Vector2(340, 320)
	panel.add_child(play_area)
	board = PuzzleBoard.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_area.add_child(board)
	board.configure(level, tint)
	board.path = restore.duplicate()
	board.refresh()
	board.solved.connect(_complete_level)
	var reset_button := button("↻ Reset line", func(): board.clear_path())
	var reset_style := box(Color("283846"), 10)
	reset_button.add_theme_stylebox_override("normal", reset_style)
	reset_button.anchor_left = 1.0
	reset_button.anchor_top = 1.0
	reset_button.anchor_right = 1.0
	reset_button.anchor_bottom = 1.0
	reset_button.offset_left = -152
	reset_button.offset_top = -62
	reset_button.offset_right = -16
	reset_button.offset_bottom = -16
	play_area.add_child(reset_button)
	var controls := HBoxContainer.new()
	content.add_child(controls)
	controls.add_child(button("← All puzzles", show_menu))

func _complete_level() -> void:
	var result := store.mark_complete(current_level)
	if result != OK:
		_show_toast("Progress could not be saved: " + error_string(result))
	var token := transition_id
	var tint := store.get_color(current_level)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.04, 0.06, 0.86)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(veil)
	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center_container)
	var message := VBoxContainer.new()
	message.add_theme_constant_override("separation", 16)
	center_container.add_child(message)
	for item in [["✦", 64, tint], ["Beautifully connected.", 40, TEXT], ["Congratulations — level %02d complete!" % current_level, 18, tint], ["Take a breath. Your next puzzle is on its way.", 15, MUTED]]:
		var text_label := label(item[0], item[1], item[2])
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.add_child(text_label)
	layer.modulate.a = 0
	var fade := create_tween()
	fade.tween_property(layer, "modulate:a", 1.0, 0.35)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(48):
		var spark := ColorRect.new()
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.color = tint.lightened(rng.randf_range(0, 0.4))
		spark.size = Vector2(rng.randf_range(3, 8), rng.randf_range(5, 12))
		spark.position = size * 0.5
		layer.add_child(spark)
		var destination := size * 0.5 + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160, 440)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(spark, "position", destination, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "rotation", rng.randf_range(-5, 5), 1.6)
		tween.tween_property(spark, "modulate:a", 0.0, 1.4).set_delay(0.3)
	await get_tree().create_timer(2.5).timeout
	if token == transition_id and screen == "play":
		play_level(current_level + 1)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.keycode
	if event.pressed:
		pressed_keys[key] = true
	else:
		pressed_keys.erase(key)
	var only_editor_keys := _only_keys([KEY_SHIFT, KEY_Z, KEY_O])
	var only_color_keys := _only_keys([KEY_SHIFT, KEY_Z, KEY_I])
	var editor_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_O) and only_editor_keys
	var color_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_I) and only_color_keys
	if (editor_chord or color_chord) and not chord_active:
		chord_active = true
		pending_undo = false
		get_viewport().set_input_as_handled()
		if editor_chord:
			_toggle_editor()
		else:
			_toggle_color_editor()
		return
	if not editor_chord and not color_chord:
		chord_active = false
	if screen == "editor" and not color_mode:
		if key == KEY_Z and event.pressed and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed and not pressed_keys.has(KEY_I):
			# Defer until release to distinguish Ctrl+Z from Ctrl+Z+I.
			pending_undo = true
			get_viewport().set_input_as_handled()
		elif key == KEY_Z and not event.pressed and pending_undo:
			pending_undo = false
			_editor_undo()
			get_viewport().set_input_as_handled()
		elif key == KEY_Y and event.pressed and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
			_editor_redo()
			get_viewport().set_input_as_handled()

func _only_keys(allowed: Array) -> bool:
	for key in pressed_keys:
		if key not in allowed:
			return false
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		pressed_keys.clear()
		chord_active = false
		pending_undo = false

func _toggle_editor() -> void:
	if screen == "play" and is_instance_valid(board) and board.locked and not color_mode:
		return
	if color_mode:
		_toggle_color_editor()
	if screen == "editor":
		if return_screen == "play":
			play_level(current_level, saved_path)
		else:
			show_menu()
		return
	return_screen = screen
	saved_path = board.path.duplicate() if is_instance_valid(board) else []
	editor_level = current_level if screen == "play" else store.frontier()
	editor_data = store.get_level(editor_level)
	undo_stack.clear()
	redo_stack.clear()
	_show_editor()

func _show_editor() -> void:
	screen = "editor"
	_shell()
	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	title_row.add_child(label("Level workshop", 34))
	spacer(title_row)
	title_row.add_child(label("SHIFT + Z + O TO RETURN", 12, MUTED))
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workspace)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(PANEL, 22))
	workspace.add_child(panel)
	board = PuzzleBoard.new()
	board.custom_minimum_size = Vector2(320, 330)
	board.editing = true
	panel.add_child(board)
	board.configure(editor_data, store.get_color(editor_level))
	board.paint_started.connect(func(): stroke_before = editor_data.duplicate(true))
	board.cell_painted.connect(_paint_cell)
	board.paint_finished.connect(_finish_stroke)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.custom_minimum_size.x = 245
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(controls_scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 9)
	controls_scroll.add_child(controls)
	controls.add_child(label("SAVE AS LEVEL", 12, MUTED))
	var number_input := _spin(editor_level, 1, 100000)
	controls.add_child(number_input)
	number_input.value_changed.connect(func(value: float): editor_level = int(value); board.tint = store.get_color(editor_level); board.refresh())
	controls.add_child(button("Load level", func():
		_finish_stroke()
		_record_edit()
		editor_data = store.get_level(editor_level)
		_sync_editor()
		editor_message.text = "Loaded level %d." % editor_level
	))
	controls.add_child(label("GRID DIMENSIONS", 12, MUTED))
	var dimensions := HBoxContainer.new()
	controls.add_child(dimensions)
	width_input = _spin(editor_data.width, 3, 128)
	height_input = _spin(editor_data.height, 3, 128)
	dimensions.add_child(width_input)
	dimensions.add_child(label("×", 18, MUTED))
	dimensions.add_child(height_input)
	width_input.value_changed.connect(func(_v): _resize_editor())
	height_input.value_changed.connect(func(_v): _resize_editor())
	controls.add_child(label("PAINT TILES", 12, MUTED))
	brush_buttons.clear()
	for value in range(3):
		var brush_button := button(["○  White / light", "●  Black / dark", "•  Gray / neutral"][value], func(): _set_brush(value))
		brush_button.toggle_mode = true
		controls.add_child(brush_button)
		brush_buttons.append(brush_button)
	_set_brush(brush)
	controls.add_child(button("Reset all to white", _reset_all_white))
	controls.add_child(button("Save level %s" % "→", _save_editor, true))
	var edit_actions := HBoxContainer.new()
	controls.add_child(edit_actions)
	edit_actions.add_child(button("Undo", _editor_undo))
	edit_actions.add_child(button("Redo", _editor_redo))
	controls.add_child(label("Ctrl + Z / Ctrl + Y\nEach paint stroke is one edit.", 12, MUTED))
	editor_message = label("Paint, then save to replace\nthe generated puzzle.", 13, ACCENT)
	editor_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(editor_message)
	content.add_child(label("Neutral tiles never flip. Custom layouts are saved exactly as drawn; solvability is up to you.", 13, MUTED))

func _spin(value: float, minimum: float, maximum: float) -> SpinBox:
	var node := SpinBox.new()
	node.min_value = minimum
	node.max_value = maximum
	node.step = 1
	node.value = value
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.custom_minimum_size.x = 82
	return node

func _set_brush(value: int) -> void:
	brush = value
	for i in range(brush_buttons.size()):
		brush_buttons[i].button_pressed = i == value

func _reset_all_white() -> void:
	board._end()
	_finish_stroke()
	if not editor_data.tiles.has(1) and not editor_data.tiles.has(2):
		editor_message.text = "The board is already all white."
		return
	_record_edit()
	editor_data.tiles.fill(0)
	board.tiles = editor_data.tiles.duplicate()
	board.refresh()
	editor_message.text = "Board cleared. Paint dark tiles before saving."

func _record_edit() -> void:
	undo_stack.append(editor_data.duplicate(true))
	if undo_stack.size() > 200:
		undo_stack.pop_front()
	redo_stack.clear()

func _paint_cell(cell: int) -> void:
	if editor_data.tiles[cell] == brush:
		return
	editor_data.tiles[cell] = brush
	board.tiles[cell] = brush
	board.refresh()

func _finish_stroke() -> void:
	if not stroke_before.is_empty() and stroke_before != editor_data:
		undo_stack.append(stroke_before)
		redo_stack.clear()
	stroke_before = {}

func _resize_editor() -> void:
	if restoring_editor:
		return
	_finish_stroke()
	_record_edit()
	var width := int(width_input.value)
	var height := int(height_input.value)
	var tiles: Array = []
	tiles.resize(width * height)
	tiles.fill(0)
	for y in range(mini(height, editor_data.height)):
		for x in range(mini(width, editor_data.width)):
			tiles[y * width + x] = editor_data.tiles[y * int(editor_data.width) + x]
	editor_data = {"width": width, "height": height, "tiles": tiles}
	_sync_editor()

func _sync_editor() -> void:
	restoring_editor = true
	width_input.value = editor_data.width
	height_input.value = editor_data.height
	restoring_editor = false
	board.configure(editor_data, store.get_color(editor_level))

func _editor_undo() -> void:
	_finish_stroke()
	if undo_stack.is_empty():
		return
	redo_stack.append(editor_data.duplicate(true))
	editor_data = undo_stack.pop_back()
	_sync_editor()
	editor_message.text = "Undid the last edit."

func _editor_redo() -> void:
	_finish_stroke()
	if redo_stack.is_empty():
		return
	undo_stack.append(editor_data.duplicate(true))
	editor_data = redo_stack.pop_back()
	_sync_editor()
	editor_message.text = "Redid the last edit."

func _save_editor() -> void:
	_finish_stroke()
	if not editor_data.tiles.has(1):
		editor_message.text = "Add at least one dark tile\nto make a playable puzzle."
		return
	var result := store.save_level(editor_level, editor_data)
	if result == OK:
		if editor_level == current_level:
			saved_path.clear()
		editor_message.text = "Level %d saved.\n%s" % [editor_level, store.persistence_error if not store.persistence_error.is_empty() else "It now replaces the generated level."]
	else:
		editor_message.text = "Save failed: " + error_string(result)

func _toggle_color_editor() -> void:
	if screen == "play" and is_instance_valid(board) and board.locked and not color_mode:
		return
	if color_mode:
		color_mode = false
		if is_instance_valid(overlay):
			overlay.queue_free()
			overlay = null
		if is_instance_valid(board):
			board.locked = false
			board.tint = store.get_color(editor_level if screen == "editor" else current_level)
			board.refresh()
		if screen == "menu":
			show_menu()
		elif screen == "play":
			play_level(current_level, board.path.duplicate())
		return
	color_mode = true
	transition_id += 1
	if is_instance_valid(board):
		board._end()
		board.locked = true
	color_level = editor_level if screen == "editor" else (current_level if screen == "play" else store.frontier())
	color_draft = store.get_color(color_level)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.8)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(veil)
	var center_container := CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center_container)
	var panel := PanelContainer.new()
	var style := box(PANEL, 22)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	center_container.add_child(panel)
	var controls := VBoxContainer.new()
	controls.custom_minimum_size.x = 380
	panel.add_child(controls)
	controls.add_child(label("Make it your hue.", 30))
	controls.add_child(label("SHIFT + Z + I TO RETURN", 12, MUTED))
	var picker := ColorPicker.new()
	picker.edit_alpha = false
	picker.color = color_draft
	picker.can_add_swatches = false
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	var number_input := _spin(color_level, 1, 100000)
	controls.add_child(label("LEVEL NUMBER", 12, MUTED))
	controls.add_child(number_input)
	controls.add_child(picker)
	var feedback := label("Light tiles use this hue; dark tiles use its shade.", 13, MUTED)
	controls.add_child(feedback)
	number_input.value_changed.connect(func(value: float):
		color_level = int(value)
		color_draft = store.get_color(color_level)
		picker.color = color_draft
	)
	picker.color_changed.connect(func(color: Color):
		color_draft = color
		if is_instance_valid(board) and color_level == (editor_level if screen == "editor" else current_level):
			board.tint = color
			board.refresh()
	)
	controls.add_child(button("Save level color", func():
		var result := store.save_color(color_level, color_draft)
		feedback.text = "Color saved for level %d." % color_level if result == OK else "Save failed: " + error_string(result)
	, true))

func _show_toast(message: String) -> void:
	if is_instance_valid(toast):
		toast.queue_free()
	toast = label(message, 14, ACCENT)
	toast.position = Vector2(44, 8)
	toast.z_index = 100
	add_child(toast)
	toast_timer = 5.0

func _process(delta: float) -> void:
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0 and is_instance_valid(toast):
			toast.queue_free()
