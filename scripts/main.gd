extends Control

const CelebrationLines = preload("res://scripts/celebration_lines.gd")
const RearrangeCard = preload("res://scripts/rearrange_card.gd")
const MenuThumbnailJob = preload("res://scripts/menu_thumbnail_job.gd")
const CompletedBadge = preload("res://scripts/completed_badge.gd")
const CoinIcon = preload("res://scripts/coin_icon.gd")
const PuzzleSolver = preload("res://scripts/puzzle_solver.gd")
const SCREEN_TRANSITION_DURATION := 0.2

const BG := Color("0c1219")
const PANEL := Color("141e28")
const TEXT := Color("e8eee9")
const MUTED := Color("88979e")
const ACCENT := Color("b6ead3")
const UNFINISHED_OUTLINE := Color("eae345")
const COMPLETED_CARD_OUTLINE := Color("60d98d")
const LOCKED_HINT_OUTLINE := Color("ed5b61")
const NO_SOLUTION_OUTLINE := Color("f05462")
const MENU_MAX_COLUMNS := 15

var store := LevelStore.new()
var screen := "menu"
var current_level := 1
var board: PuzzleBoard
var board_panel: PanelContainer
var completed_badge: Control
var credit_display: HBoxContainer
var credit_label: Label
var hint_button: Button
var hint_stage := 0
var hint_busy := false
var hint_endpoints: Array[int] = []
var background_rect: ColorRect
var background_tween: Tween
var palette_tween: Tween
var palette_text := Color.WHITE
var palette_button := Color.BLACK
var palette_theme: Theme
var menu_hovered_level := 0
var content: VBoxContainer
var overlay: Control
var toast: Label
var toast_timer := 0.0
var transition_id := 0
var rearrange_mode := false
var rearrange_action := "insert"
var menu_rows: VBoxContainer
var menu_cards: Array[Button] = []
var menu_hint: PanelContainer
var screen_shake_tween: Tween
var screen_shake_offsets: Array[Vector2] = []
var shake_rng := RandomNumberGenerator.new()
var menu_columns := 0
var menu_thumbnail_cache: Dictionary = {}
var menu_thumbnail_queue: Array[int] = []
var menu_thumbnail_task := -1
var menu_thumbnail_job: RefCounted
var pending_menu_level := 0
var menu_scroll: ScrollContainer
var menu_scroll_position := 0
var screen_transition: Control
var screen_transition_tween: Tween
var transition_new_shell: Control
var transition_board: PuzzleBoard
var transition_old_board: PuzzleBoard
var transition_board_parent: Control
var transition_hidden_card: Control
var saved_menu: Dictionary = {}
var outgoing_menu: Dictionary = {}
var active_menu_signature := 0
var active_shell: Control
var held_shell: Control
var transition_old_shell: Control
var menu_drag_source := 0
var menu_drag_target := 0
var menu_drag_after := false
var menu_drag_origin := Vector2.ZERO
var menu_dragging := false
var menu_drag_icon: TextureRect
var menu_drag_tweens: Dictionary = {}
var menu_drag_destinations: Dictionary = {}
var pressed_keys: Dictionary = {}
var chord_active := false
var pending_undo := false
var editor_level := 1
var editor_data: Dictionary
var copied_editor_data: Dictionary = {}
var undo_stack: Array = []
var redo_stack: Array = []
var stroke_before: Dictionary = {}
var brush := 1
var editor_message: Label
var editor_mode_hint: Label
var editor_controls: VBoxContainer
var editor_playtesting := false
var editor_solver: RefCounted
var editor_solve_button: Button
var width_input: SpinBox
var height_input: SpinBox
var move_input: SpinBox
var editor_generation_moves := -1
var crossover_input: SpinBox
var editor_required_crossings := Puzzle.DEFAULT_EDITOR_CROSSINGS
var editor_number_input: SpinBox
var brush_buttons: Array[Button] = []
var restoring_editor := false
var return_screen := "menu"
var saved_path: Array = []
var color_mode := false
var color_previous_board_locked := false
var color_level := 1
var color_draft := Color.WHITE
var line_draft := Color.WHITE
var line_custom_draft := false
var copied_area_colors: Dictionary = {}
var color_selecting_line := false
var color_picker_loading := false
var color_picker: ColorPicker
var color_preview: PuzzleBoard
var color_tile_button: Button
var color_line_button: Button
var color_feedback: Label
var color_group_label: Label
var color_paste_button: Button

func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	shake_rng.randomize()
	_build_theme()
	resized.connect(func():
		_finish_screen_transition()
		_update_menu_columns()
	)
	show_menu()

func _update_menu_columns() -> void:
	if not is_instance_valid(menu_rows):
		return
	var columns := mini(MENU_MAX_COLUMNS, maxi(1, int((size.x - 88 - 16 + 12) / 76)))
	menu_rows.custom_minimum_size.x = columns * 64 + (columns - 1) * 12
	if columns == menu_columns and menu_rows.get_child_count() > 0:
		return
	menu_columns = columns
	for row in menu_rows.get_children():
		for item in row.get_children():
			row.remove_child(item)
		menu_rows.remove_child(row)
		row.queue_free()
	var items: Array[Control] = []
	items.assign(menu_cards)
	if is_instance_valid(menu_hint):
		items.append(menu_hint)
	for first in range(0, items.size(), columns):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		menu_rows.add_child(row)
		for index in range(first, mini(first + columns, items.size())):
			row.add_child(items[index])

func _build_theme() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font_size = 16
	theme_resource.set_type_variation("PrimaryButton", "Button")
	theme_resource.set_color("font_color", "Label", TEXT)
	theme_resource.set_color("font_color", "Button", TEXT)
	theme_resource.set_color("font_hover_color", "Button", Color.WHITE)
	theme_resource.set_color("font_pressed_color", "Button", TEXT)
	theme_resource.set_constant("outline_size", "Label", 0)
	theme_resource.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.22))
	theme_resource.set_constant("shadow_offset_x", "Label", 1)
	theme_resource.set_constant("shadow_offset_y", "Label", 1)
	theme_resource.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.22))
	theme_resource.set_constant("outline_size", "Button", 1)
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
	palette_theme = theme_resource.duplicate(true)

func _apply_ui_palette(color: Color) -> void:
	_apply_ui_colors(_ui_text_color(color), _ui_button_color(color))

func _ui_text_color(color: Color) -> Color:
	return PuzzleBoard.menu_text_color(color) if screen == "menu" else PuzzleBoard.text_color(color)

func _ui_button_color(color: Color) -> Color:
	return PuzzleBoard.menu_button_color(color) if screen == "menu" else PuzzleBoard.button_color(color)

func _apply_ui_colors(light: Color, dark: Color) -> void:
	if palette_text.is_equal_approx(light) and palette_button.is_equal_approx(dark):
		return
	palette_text = light
	palette_button = dark
	palette_theme.set_block_signals(true)
	for kind in ["Label", "Button", "LineEdit", "SpinBox"]:
		palette_theme.set_color("font_color", kind, light)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		palette_theme.set_color(state, "Button", light)
	_style_buttons("Button", dark, light)
	_style_buttons("PrimaryButton", PuzzleBoard.balanced_color(dark.h, 0.50, 0.12), light)
	palette_theme.set_block_signals(false)
	palette_theme.emit_changed()

func _style_buttons(kind: String, base: Color, text_color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := base
		if state == "hover":
			fill = PuzzleBoard.balanced_color(base.h, base.s, PuzzleBoard.luminance(base) + 0.012)
		elif state == "pressed":
			fill = PuzzleBoard.balanced_color(base.h, base.s, maxf(0.02, PuzzleBoard.luminance(base) - 0.012))
		if not palette_theme.has_stylebox(state, kind):
			var initial := box(fill, 12)
			initial.content_margin_left = 20
			initial.content_margin_right = 20
			initial.content_margin_top = 12
			initial.content_margin_bottom = 12
			palette_theme.set_stylebox(state, kind, initial)
		var style := palette_theme.get_stylebox(state, kind) as StyleBoxFlat
		style.bg_color = fill
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = text_color
			style.set_border_width_all(2)

func _animate_ui_palette(target_color: Color, duration: float, from_text: Color, from_button: Color) -> void:
	if palette_tween and palette_tween.is_running():
		palette_tween.kill()
	var target_text := _ui_text_color(target_color)
	var target_button := _ui_button_color(target_color)
	if from_text.is_equal_approx(target_text) and from_button.is_equal_approx(target_button):
		return
	_apply_ui_colors(from_text, from_button)
	palette_tween = create_tween()
	palette_tween.tween_method(func(progress: float):
		_apply_ui_colors(from_text.lerp(target_text, progress), from_button.lerp(target_button, progress))
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE)

func box(color: Color, radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func label(text: String, font_size: int = 16, _color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	return node

func button(text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	if primary:
		node.theme_type_variation = "PrimaryButton"
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	return node

func spacer(parent: Control) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func _take_outgoing_shell() -> Control:
	_finish_screen_transition()
	held_shell = active_shell
	held_shell.process_mode = Node.PROCESS_MODE_DISABLED
	return held_shell

func _finish_screen_transition() -> void:
	if screen_transition_tween:
		screen_transition_tween.kill()
	screen_transition_tween = null
	if is_instance_valid(transition_board) and is_instance_valid(transition_board_parent):
		transition_board.reparent(transition_board_parent)
		transition_board.scale = Vector2.ONE
		transition_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		transition_board.set_process_input(true)
	if is_instance_valid(transition_new_shell):
		transition_new_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		transition_new_shell.modulate = Color.WHITE
	if is_instance_valid(transition_hidden_card):
		transition_hidden_card.modulate.a = 1.0
	if not outgoing_menu.is_empty():
		_discard_saved_menu()
		var retained: Control = outgoing_menu.wrapper
		retained.hide()
		retained.modulate = Color.WHITE
		retained.position = Vector2.ZERO
		for card in outgoing_menu.cards:
			if card.has_meta("hover_tween"):
				(card.get_meta("hover_tween") as Tween).kill()
			for child in card.get_children():
				if child is Control:
					child.scale = Vector2.ONE
		saved_menu = outgoing_menu
		outgoing_menu = {}
	elif is_instance_valid(transition_old_shell):
		remove_child(transition_old_shell)
		transition_old_shell.queue_free()
	if is_instance_valid(screen_transition):
		remove_child(screen_transition)
		screen_transition.queue_free()
	if is_instance_valid(board) and screen == "play":
		board.set_process_input(true)
	screen_transition = null
	transition_new_shell = null
	transition_board = null
	transition_old_board = null
	transition_board_parent = null
	transition_hidden_card = null
	transition_old_shell = null

func _menu_signature() -> int:
	return hash([store.menu_unlocked(), store.completed, store.credits, store.levels, store.colors])

func _discard_saved_menu() -> void:
	if not saved_menu.is_empty() and is_instance_valid(saved_menu.wrapper):
		if saved_menu.wrapper.get_parent() == self:
			remove_child(saved_menu.wrapper)
		saved_menu.wrapper.queue_free()
	saved_menu = {}

func _restore_saved_menu() -> void:
	var wrapper: Control = saved_menu.wrapper
	active_shell = wrapper
	wrapper.theme = palette_theme
	wrapper.show()
	wrapper.process_mode = Node.PROCESS_MODE_INHERIT
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content = saved_menu.content
	menu_rows = saved_menu.rows
	menu_cards.assign(saved_menu.cards)
	menu_hint = saved_menu.hint
	menu_scroll = saved_menu.scroll
	menu_columns = saved_menu.columns
	credit_display = saved_menu.credit_display
	credit_label = saved_menu.credit_label
	active_menu_signature = saved_menu.signature
	saved_menu = {}
	_update_menu_columns()
	for card in menu_cards:
		var number := int(card.get("level_number"))
		var cached: Dictionary = menu_thumbnail_cache.get(number, {})
		if cached.get("signature") == _thumbnail_signature(number):
			(card.get_child(0) as TextureRect).texture = cached.texture
		else:
			menu_thumbnail_queue.append(number)

func _card_board_transform(puzzle: PuzzleBoard, card_rect: Rect2) -> Dictionary:
	var cell := 96.0 / maxi(puzzle.width, puzzle.height)
	var origin := (Vector2(128, 128) - Vector2(puzzle.width, puzzle.height) * cell) * 0.5
	var geometry := puzzle.geometry()
	var factor: float = (cell * card_rect.size.x / 128.0) / geometry.cell
	return {"position": card_rect.position + origin * card_rect.size / 128.0 - geometry.origin * factor, "scale": Vector2.ONE * factor}

func _start_screen_transition(outgoing: Control, kind: String, old_board: PuzzleBoard = null, card_rect: Rect2 = Rect2(), source_card: Control = null, direction: int = 1) -> void:
	var layer := Control.new()
	layer.theme = palette_theme
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	screen_transition = layer
	transition_old_shell = outgoing
	held_shell = null
	var incoming := active_shell
	transition_new_shell = incoming
	incoming.modulate.a = 0.0
	if is_instance_valid(board):
		board.set_process_input(false)
	if is_instance_valid(old_board):
		old_board.set_process_input(false)
	var blocker := Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(blocker)
	# Let containers resolve the destination once; animate transforms thereafter.
	await get_tree().process_frame
	if not is_instance_valid(layer) or screen_transition != layer:
		return
	await get_tree().process_frame
	if not is_instance_valid(layer) or screen_transition != layer:
		return
	if kind == "close":
		var index := _menu_card_index(current_level)
		if index >= 0:
			menu_scroll.ensure_control_visible(menu_cards[index])
			await get_tree().process_frame
			if not is_instance_valid(layer) or screen_transition != layer:
				return
	var tween := create_tween().set_parallel(true)
	screen_transition_tween = tween
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if kind == "slide":
		incoming.modulate.a = 1.0
		if is_instance_valid(old_board) and is_instance_valid(board):
			var old_rect := old_board.get_global_rect()
			var new_rect := board.get_global_rect()
			transition_old_board = old_board
			transition_board = board
			transition_board_parent = board.get_parent() as Control
			old_board.reparent(layer)
			old_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			old_board.size = old_rect.size
			old_board.position = old_rect.position
			board.reparent(layer)
			board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			board.size = new_rect.size
			board.position = new_rect.position + Vector2(size.x * direction, 0)
			outgoing.hide()
			tween.tween_property(old_board, "position:x", old_rect.position.x - size.x * direction, SCREEN_TRANSITION_DURATION)
			tween.tween_property(board, "position:x", new_rect.position.x, SCREEN_TRANSITION_DURATION)
		else:
			incoming.position.x = size.x * direction
			tween.tween_property(outgoing, "position:x", -size.x * direction, SCREEN_TRANSITION_DURATION)
			tween.tween_property(incoming, "position:x", 0.0, SCREEN_TRANSITION_DURATION)
	else:
		var moving_board := board if kind == "open" else old_board
		if kind == "close":
			var index := _menu_card_index(current_level)
			if index >= 0:
				source_card = menu_cards[index]
				card_rect = source_card.get_global_rect()
		if is_instance_valid(moving_board) and card_rect.has_area():
			var full_rect := moving_board.get_global_rect()
			if kind == "open":
				transition_board = moving_board
				transition_board_parent = moving_board.get_parent() as Control
			moving_board.reparent(layer)
			moving_board.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			moving_board.size = full_rect.size
			moving_board.position = full_rect.position
			moving_board.process_mode = Node.PROCESS_MODE_INHERIT
			var small := _card_board_transform(moving_board, card_rect)
			if is_instance_valid(source_card):
				transition_hidden_card = source_card
				source_card.modulate.a = 0.0
			if kind == "open":
				moving_board.position = small.position
				moving_board.scale = small.scale
				tween.tween_property(moving_board, "position", full_rect.position, SCREEN_TRANSITION_DURATION)
				tween.tween_property(moving_board, "scale", Vector2.ONE, SCREEN_TRANSITION_DURATION)
			else:
				tween.tween_property(moving_board, "position", small.position, SCREEN_TRANSITION_DURATION)
				tween.tween_property(moving_board, "scale", small.scale, SCREEN_TRANSITION_DURATION)
			layer.move_child(blocker, -1)
		tween.tween_property(outgoing, "modulate:a", 0.0, SCREEN_TRANSITION_DURATION)
		tween.tween_property(incoming, "modulate:a", 1.0, SCREEN_TRANSITION_DURATION)
	tween.finished.connect(_finish_screen_transition)

func _shell(restore_menu: bool = false) -> void:
	editor_solver = null
	editor_solve_button = null
	_finish_screen_transition()
	if screen_shake_tween and screen_shake_tween.is_running():
		screen_shake_tween.kill()
	screen_shake_tween = null
	position = Vector2.ZERO
	_cancel_menu_drag()
	menu_thumbnail_queue.clear()
	pending_menu_level = 0
	transition_id += 1
	if background_tween and background_tween.is_running():
		background_tween.kill()
	background_tween = null
	if palette_tween and palette_tween.is_running():
		palette_tween.kill()
	palette_tween = null
	# Each screen owns its palette. Moving/fading screens must not invalidate
	# each other's controls (or the retained menu) on every animation frame.
	palette_theme = palette_theme.duplicate(true)
	for child in get_children():
		if child == held_shell or (not saved_menu.is_empty() and child == saved_menu.wrapper):
			continue
		remove_child(child)
		child.queue_free()
	board = null
	board_panel = null
	completed_badge = null
	credit_display = null
	credit_label = null
	hint_button = null
	hint_stage = 0
	hint_busy = false
	hint_endpoints.clear()
	menu_rows = null
	menu_cards.clear()
	menu_hint = null
	menu_scroll = null
	menu_columns = 0
	background_rect = null
	toast = null
	overlay = null
	background_rect = ColorRect.new()
	background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background_rect)
	move_child(background_rect, 0)
	_set_background_for_level(editor_level if screen == "editor" else (current_level if screen == "play" else (menu_hovered_level if menu_hovered_level > 0 else store.frontier())))
	if restore_menu:
		_restore_saved_menu()
		return
	active_shell = Control.new()
	active_shell.theme = palette_theme
	active_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(active_shell)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margins.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 28)
	active_shell.add_child(margins)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	margins.add_child(content)
	if screen == "menu":
		var header := HBoxContainer.new()
		content.add_child(header)
		header.add_child(label("H e a r t h l i n e", 28))
		spacer(header)
		credit_display = _credits_widget()
		header.add_child(credit_display)
		var separator := HSeparator.new()
		separator.modulate = Color(1, 1, 1, 0.16)
		content.add_child(separator)

func show_menu() -> void:
	_finish_screen_transition()
	var old_board := board
	var outgoing: Control = _take_outgoing_shell() if screen == "play" and is_instance_valid(board) else null
	screen = "menu"
	color_mode = false
	var restore_menu: bool = not rearrange_mode and not saved_menu.is_empty() and saved_menu.signature == _menu_signature()
	if not restore_menu:
		_discard_saved_menu()
	_shell(restore_menu)
	if restore_menu:
		if outgoing:
			_start_screen_transition(outgoing, "close", old_board)
		return
	if rearrange_mode:
		var tools_row := HBoxContainer.new()
		content.add_child(tools_row)
		tools_row.add_child(label("Rearrange levels", 18))
		tools_row.add_child(button("Insert", func(): _set_rearrange_action("insert"), rearrange_action == "insert"))
		tools_row.add_child(button("Swap", func(): _set_rearrange_action("swap"), rearrange_action == "swap"))
		spacer(tools_row)
		tools_row.add_child(button("Done", _toggle_rearrange))
		content.add_child(label("Choose Insert or Swap, then drag between or over levels to preview the move. Insert uses the left or right half for before or after.", 14, MUTED))
	var scroll := ScrollContainer.new()
	menu_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	menu_rows = rows
	rows.add_theme_constant_override("separation", 12)
	var centered_rows := HBoxContainer.new()
	centered_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hover_margin := MarginContainer.new()
	hover_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		hover_margin.add_theme_constant_override("margin_" + side, 4)
	scroll.add_child(hover_margin)
	hover_margin.add_child(centered_rows)
	spacer(centered_rows)
	centered_rows.add_child(rows)
	spacer(centered_rows)
	var visible_levels := store.menu_levels()
	for number in visible_levels:
		menu_cards.append(_level_card(number))
	menu_hint = _locked_group_hint()
	_update_menu_columns()
	active_menu_signature = _menu_signature()
	scroll.set_deferred("scroll_vertical", menu_scroll_position)
	if outgoing:
		_start_screen_transition(outgoing, "close", old_board)

func _locked_group_hint() -> PanelContainer:
	var hint := PanelContainer.new()
	hint.custom_minimum_size = Vector2(64, 64)
	hint.size_flags_horizontal = Control.SIZE_FILL
	hint.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hint.pivot_offset = Vector2(32, 32)
	var hint_style := box(Color("46505a"), 9)
	hint_style.border_color = LOCKED_HINT_OUTLINE
	hint_style.set_border_width_all(2)
	hint.add_theme_stylebox_override("panel", hint_style)
	var question := label("?", 32)
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(question)
	hint.mouse_entered.connect(func(): _animate_locked_hint(hint, true))
	hint.mouse_exited.connect(func(): _animate_locked_hint(hint, false))
	hint.gui_input.connect(_on_locked_hint_input)
	return hint

func _animate_locked_hint(hint: PanelContainer, hovered: bool) -> void:
	if not is_instance_valid(hint) or not hint.is_inside_tree():
		return
	if hint.has_meta("hover_tween"):
		var previous: Tween = hint.get_meta("hover_tween")
		if previous.is_running():
			previous.kill()
	var tween := hint.create_tween()
	hint.set_meta("hover_tween", tween)
	tween.tween_property(hint, "scale", Vector2.ONE * (1.08 if hovered else 1.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_locked_hint_input(event: InputEvent) -> void:
	if screen != "menu" or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	_show_locked_feedback(get_global_mouse_position())
	get_viewport().set_input_as_handled()

func _show_locked_feedback(pointer: Vector2) -> void:
	_shake_screen()
	var feedback := label("Complete more puzzles...", 18)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.add_theme_color_override("font_color", Color.WHITE)
	feedback.add_theme_color_override("font_outline_color", Color.BLACK)
	feedback.add_theme_constant_override("outline_size", 5)
	feedback.z_index = 100
	add_child(feedback)
	feedback.reset_size()
	var local_pointer: Vector2 = get_global_transform().affine_inverse() * pointer
	feedback.position = Vector2(clampf(local_pointer.x - feedback.size.x * 0.5, 8, maxf(8, size.x - feedback.size.x - 8)), clampf(local_pointer.y - 24, 8, size.y - feedback.size.y - 8))
	var tween := feedback.create_tween().set_parallel(true)
	tween.tween_property(feedback, "position:y", feedback.position.y - 70, 1.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(feedback, "modulate:a", 0.0, 1.05)
	tween.finished.connect(feedback.queue_free)

func _shake_screen() -> void:
	if screen_shake_tween and screen_shake_tween.is_running():
		screen_shake_tween.kill()
	position = Vector2.ZERO
	screen_shake_offsets.clear()
	screen_shake_tween = create_tween()
	var hops := shake_rng.randi_range(8, 10)
	for index in range(hops):
		var strength := 1.0 - float(index) / float(hops)
		var distance := shake_rng.randf_range(5.0, 12.0) * strength + 1.5
		var offset := Vector2.from_angle(shake_rng.randf_range(-PI, PI)) * distance
		screen_shake_offsets.append(offset)
		screen_shake_tween.tween_property(self, "position", offset, shake_rng.randf_range(0.017, 0.023)).set_trans(Tween.TRANS_SINE)
	screen_shake_tween.tween_property(self, "position", Vector2.ZERO, 0.035).set_trans(Tween.TRANS_SINE)

func _level_card(number: int) -> Button:
	var card := RearrangeCard.new()
	card.level_number = number
	card.rearranging = rearrange_mode
	card.mouse_default_cursor_shape = Control.CURSOR_MOVE if rearrange_mode else Control.CURSOR_POINTING_HAND
	if rearrange_mode:
		card.drag_pressed.connect(_start_menu_drag)
	else:
		card.pressed.connect(func(): _on_menu_card_pressed(number))
	card.mouse_entered.connect(func():
		if screen == "menu" and not color_mode and menu_drag_source == 0:
			menu_hovered_level = number
			_set_background_for_level(number, true)
			if not rearrange_mode:
				_animate_menu_card_hover(card, true)
	)
	card.mouse_exited.connect(func():
		if not rearrange_mode:
			_animate_menu_card_hover(card, false)
	)
	card.custom_minimum_size = Vector2(64, 64)
	card.size_flags_horizontal = Control.SIZE_FILL
	card.pivot_offset = Vector2(32, 32)
	var preview := TextureRect.new()
	preview.position = Vector2.ZERO
	preview.size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(preview)
	var completed: bool = store.completed.get(str(number), false)
	var signature := _thumbnail_signature(number)
	var cached: Dictionary = menu_thumbnail_cache.get(number, {})
	if cached.get("signature") == signature:
		preview.texture = cached.texture
	else:
		menu_thumbnail_queue.append(number)
	var outline := Panel.new()
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := box(Color.TRANSPARENT, 9)
	if not store.has_solution(number):
		outline_style.bg_color = Color("c73648", 0.24)
		outline_style.border_color = NO_SOLUTION_OUTLINE
	else:
		outline_style.border_color = COMPLETED_CARD_OUTLINE if completed else UNFINISHED_OUTLINE
	outline_style.set_border_width_all(2)
	outline.add_theme_stylebox_override("panel", outline_style)
	card.add_child(outline)
	return card

func _animate_menu_card_hover(card: Control, hovered: bool) -> void:
	if not is_instance_valid(card) or not card.is_inside_tree():
		return
	if card.has_meta("hover_tween"):
		var previous: Tween = card.get_meta("hover_tween")
		if previous.is_running():
			previous.kill()
	var tween := card.create_tween()
	card.set_meta("hover_tween", tween)
	tween.set_parallel(true)
	# Container layout resets the Button's transform when the palette changes.
	# Its visual children have stable geometry and can grow without relayout.
	for child in card.get_children():
		if child is Control:
			child.pivot_offset = Vector2(32, 32) - child.position
			tween.tween_property(child, "scale", Vector2.ONE * (1.08 if hovered else 1.0), 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _thumbnail_signature(number: int) -> int:
	return hash([number, store.levels.get(str(number), {}), store.get_color(number).to_html()])

func _select_menu_level(number: int) -> void:
	if store.levels.has(str(number)) or store.cache.has(number):
		play_level(number)
	else:
		pending_menu_level = number
		menu_thumbnail_queue.erase(number)
		menu_thumbnail_queue.push_front(number)

func _on_menu_card_pressed(number: int) -> void:
	if screen == "menu" and pressed_keys.has(KEY_SHIFT) and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_B) and _only_keys([KEY_SHIFT, KEY_Z, KEY_B]):
		var result := store.set_completion_through(number)
		if result != OK:
			_show_toast("Progress could not be saved: " + error_string(result))
			return
		menu_scroll_position = menu_scroll.scroll_vertical if is_instance_valid(menu_scroll) else 0
		menu_hovered_level = 0
		show_menu()
		return
	_select_menu_level(number)

func _process_menu_thumbnails() -> void:
	if menu_thumbnail_task >= 0:
		if not WorkerThreadPool.is_task_completed(menu_thumbnail_task):
			return
		WorkerThreadPool.wait_for_task_completion(menu_thumbnail_task)
		menu_thumbnail_task = -1
		var number: int = menu_thumbnail_job.number
		var result: Dictionary = menu_thumbnail_job.result
		if not store.levels.has(str(number)) and menu_thumbnail_job.signature == _thumbnail_signature(number):
			store.cache[number] = result.level
		if result.error == OK and menu_thumbnail_job.signature == _thumbnail_signature(number):
			var texture := ImageTexture.create_from_image(result.image)
			menu_thumbnail_cache[number] = {"signature": menu_thumbnail_job.signature, "texture": texture}
			var index := _menu_card_index(number)
			if screen == "menu" and index >= 0:
				(menu_cards[index].get_child(0) as TextureRect).texture = texture
		menu_thumbnail_job = null
		if screen == "menu" and pending_menu_level == number:
			play_level(number)
			return
	if screen != "menu" or menu_thumbnail_queue.is_empty() or is_instance_valid(screen_transition):
		return
	if pending_menu_level == 0 and is_instance_valid(menu_scroll):
		var visible_rect := menu_scroll.get_global_rect()
		for queued in menu_thumbnail_queue:
			var index := _menu_card_index(queued)
			if index >= 0 and visible_rect.intersects(menu_cards[index].get_global_rect()):
				menu_thumbnail_queue.erase(queued)
				menu_thumbnail_queue.push_front(queued)
				break
	var number: int = menu_thumbnail_queue.pop_front()
	var cached: Dictionary = menu_thumbnail_cache.get(number, {})
	if cached.get("signature") == _thumbnail_signature(number) and (store.levels.has(str(number)) or store.cache.has(number)):
		return
	var job := MenuThumbnailJob.new()
	job.number = number
	job.signature = _thumbnail_signature(number)
	job.tint = store.get_color(number)
	if store.levels.has(str(number)) or store.cache.has(number):
		job.layout = store.get_level(number)
	menu_thumbnail_job = job
	menu_thumbnail_task = WorkerThreadPool.add_task(job.run)

func _exit_tree() -> void:
	if menu_thumbnail_task >= 0:
		WorkerThreadPool.wait_for_task_completion(menu_thumbnail_task)
	saved_menu = {}

func _start_menu_drag(source: int, pointer: Vector2) -> void:
	if not rearrange_mode or screen != "menu" or _menu_card_index(source) < 0:
		return
	_cancel_menu_drag()
	menu_drag_source = source
	menu_drag_origin = pointer

func _menu_card_index(number: int) -> int:
	for index in range(menu_cards.size()):
		if int(menu_cards[index].get("level_number")) == number:
			return index
	return -1

func _menu_drag_slots() -> Array[Vector2]:
	var slots: Array[Vector2] = []
	for card in menu_cards:
		slots.append(card.get_parent().global_position + Vector2(card.get_index() * 76, 0))
	return slots

func _update_menu_drag(pointer: Vector2) -> void:
	if menu_drag_source == 0 or not rearrange_mode:
		return
	if not menu_dragging:
		if pointer.distance_to(menu_drag_origin) < 6.0:
			return
		menu_dragging = true
		var source_card := menu_cards[_menu_card_index(menu_drag_source)]
		source_card.modulate.a = 0.0
		menu_drag_icon = TextureRect.new()
		menu_drag_icon.theme = palette_theme
		menu_drag_icon.texture = (source_card.get_child(0) as TextureRect).texture
		menu_drag_icon.size = Vector2(64, 64)
		menu_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		menu_drag_icon.stretch_mode = TextureRect.STRETCH_SCALE
		menu_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu_drag_icon.modulate.a = 0.9
		add_child(menu_drag_icon)
		menu_drag_icon.size = Vector2(64, 64)
	menu_drag_icon.position = pointer - Vector2(32, 32)
	var slots := _menu_drag_slots()
	var target := 0
	var distance := INF
	for index in range(slots.size()):
		if not Rect2(slots[index], Vector2(64, 64)).grow(8).has_point(pointer):
			continue
		var candidate := pointer.distance_squared_to(slots[index] + Vector2(32, 32))
		if candidate < distance:
			distance = candidate
			target = int(menu_cards[index].get("level_number"))
	if target == menu_drag_source:
		target = 0
	var after := target > 0 and pointer.x >= slots[_menu_card_index(target)].x + 32.0
	if target != menu_drag_target or after != menu_drag_after:
		menu_drag_target = target
		menu_drag_after = after
		_animate_menu_drag_preview(slots)

func _animate_menu_drag_preview(slots: Array[Vector2]) -> void:
	var order: Array[int] = []
	for index in range(menu_cards.size()):
		order.append(index)
	var source_index := _menu_card_index(menu_drag_source)
	if menu_drag_target > 0:
		var target_index := _menu_card_index(menu_drag_target)
		if rearrange_action == "swap":
			order[source_index] = target_index
			order[target_index] = source_index
		else:
			var moved: int = order.pop_at(source_index)
			var insertion := target_index + (1 if menu_drag_after else 0)
			if source_index < target_index:
				insertion -= 1
			order.insert(insertion, moved)
	var destinations: Array[int] = []
	destinations.resize(order.size())
	for slot in range(order.size()):
		destinations[order[slot]] = slot
	for index in range(menu_cards.size()):
		if index == source_index:
			continue
		var card := menu_cards[index]
		var destination: Vector2 = slots[destinations[index]] - card.get_parent().global_position
		if menu_drag_destinations.has(index) and (menu_drag_destinations[index] as Vector2).is_equal_approx(destination):
			continue
		menu_drag_destinations[index] = destination
		if menu_drag_tweens.has(index):
			(menu_drag_tweens[index] as Tween).kill()
			menu_drag_tweens.erase(index)
		if card.position.is_equal_approx(destination):
			continue
		var tween := create_tween()
		tween.tween_property(card, "position", destination, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		menu_drag_tweens[index] = tween

func _finish_menu_drag(pointer: Vector2) -> void:
	_update_menu_drag(pointer)
	var source := menu_drag_source
	var target := menu_drag_target
	var after := menu_drag_after
	var dropped := menu_dragging and target > 0
	_cancel_menu_drag()
	if dropped:
		_rearrange_level(source, target, after)

func _cancel_menu_drag() -> void:
	for tween in menu_drag_tweens.values():
		if tween is Tween:
			tween.kill()
	menu_drag_tweens.clear()
	menu_drag_destinations.clear()
	for card in menu_cards:
		if is_instance_valid(card) and card.get_parent() != null:
			card.position = Vector2(card.get_index() * 76, 0)
			card.modulate.a = 1.0
	if is_instance_valid(menu_drag_icon):
		menu_drag_icon.queue_free()
	menu_drag_icon = null
	menu_drag_source = 0
	menu_drag_target = 0
	menu_drag_after = false
	menu_dragging = false

func _set_rearrange_action(action: String) -> void:
	rearrange_action = action
	show_menu()

func _toggle_rearrange() -> void:
	if screen != "menu":
		return
	rearrange_mode = not rearrange_mode
	show_menu()

func _rearrange_level(source: int, target: int, after: bool) -> void:
	var result := store.rearrange_level(source, target, rearrange_action, after)
	if result != OK:
		_show_toast("Levels could not be rearranged: " + error_string(result))
		return
	menu_hovered_level = 0
	show_menu()

func play_level(number: int, restore: Array = [], navigation_direction: int = 0) -> void:
	_finish_screen_transition()
	var old_screen := screen
	var old_number := current_level
	var old_board := board
	var source_card: Control
	var card_rect := Rect2()
	if screen == "menu":
		menu_scroll_position = menu_scroll.scroll_vertical if is_instance_valid(menu_scroll) else 0
		var index := _menu_card_index(number)
		if index >= 0:
			source_card = menu_cards[index]
			card_rect = (source_card.get_child(0) as Control).get_global_rect()
	var outgoing: Control = _take_outgoing_shell() if (screen == "menu" or (screen == "play" and number != current_level)) and is_instance_valid(content) else null
	var retained_menu: Dictionary = {}
	if outgoing and old_screen == "menu" and not rearrange_mode:
		retained_menu = {"wrapper": outgoing, "signature": active_menu_signature, "content": content, "rows": menu_rows, "cards": menu_cards.duplicate(), "hint": menu_hint, "scroll": menu_scroll, "columns": menu_columns, "credit_display": credit_display, "credit_label": credit_label}
	var previous_text := palette_text
	var previous_button := palette_button
	var previous_level := -1
	if screen == "play":
		previous_level = current_level
	elif screen == "menu":
		previous_level = menu_hovered_level if menu_hovered_level > 0 else store.frontier()
	var previous_background: Color = background_rect.color if is_instance_valid(background_rect) else (PuzzleBoard.background_color(store.get_color(previous_level)) if previous_level > 0 else BG)
	var changing_set := previous_level > 0 and LevelStore.group_start(previous_level) != LevelStore.group_start(number)
	var tint := store.get_color(number)
	var fade_duration := SCREEN_TRANSITION_DURATION
	current_level = number
	screen = "play"
	color_mode = false
	_shell()
	var level := store.get_level(number)
	content.add_child(label("Level %d" % number, 38))
	_show_completed_badge()
	_show_play_credits()
	var panel := PanelContainer.new()
	board_panel = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(PuzzleBoard.background_color(tint), 24))
	content.add_child(panel)
	var play_area := Control.new()
	play_area.custom_minimum_size = Vector2(340, 320)
	panel.add_child(play_area)
	board = PuzzleBoard.new()
	board.show_start_finish = number == 1
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_area.add_child(board)
	board.configure(level, tint, store.get_line_color(number))
	board.path = restore.duplicate()
	board.refresh()
	board.solved.connect(_complete_level)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	content.add_child(controls)
	controls.add_child(button("▦ All puzzles", show_menu))
	if number != 1:
		hint_endpoints = store.hint_endpoints(number)
		hint_stage = store.hint_stage(number)
		if hint_endpoints.size() == 2:
			if hint_stage >= 1:
				board.show_solution_hint(hint_endpoints[0], true)
			if hint_stage >= 2:
				board.show_solution_hint(hint_endpoints[1], false)
		hint_button = button("", _use_hint, true)
		hint_button.focus_mode = Control.FOCUS_NONE
		hint_button.icon = CoinIcon.TEXTURE
		hint_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint_button.add_theme_constant_override("icon_max_width", 22)
		controls.add_child(hint_button)
		_update_hint_button()
	spacer(controls)
	controls.add_child(button("← Previous puzzle", func(): _open_adjacent_level(-1)))
	controls.add_child(button("↻ Reset line", func(): board.clear_path()))
	controls.add_child(button("Skip →", func(): _open_adjacent_level(1)))
	if changing_set or not previous_background.is_equal_approx(PuzzleBoard.background_color(tint)):
		_animate_level_background(previous_background, PuzzleBoard.background_color(tint), fade_duration)
	if not outgoing and (changing_set or not previous_text.is_equal_approx(PuzzleBoard.text_color(tint))):
		_animate_ui_palette(tint, fade_duration, previous_text, previous_button)
	if outgoing:
		outgoing_menu = retained_menu
		var direction := navigation_direction if navigation_direction != 0 else (1 if number > old_number else -1)
		_start_screen_transition(outgoing, "open" if old_screen == "menu" else "slide", old_board, card_rect, source_card, direction)

func _open_adjacent_level(direction: int) -> void:
	if direction > 0 and current_level >= store.menu_unlocked():
		_show_locked_feedback(get_global_mouse_position())
		return
	var next := store.adjacent_level(current_level, direction)
	if next != current_level:
		play_level(next, [], direction)

func _show_completed_badge() -> void:
	if screen != "play" or not store.completed.get(str(current_level), false) or is_instance_valid(completed_badge):
		return
	completed_badge = CompletedBadge.new()
	active_shell.add_child(completed_badge)
	completed_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	completed_badge.offset_left = -116
	completed_badge.offset_right = -44
	completed_badge.offset_top = 20
	completed_badge.offset_bottom = 92
	_position_play_credits()

func _credits_widget() -> HBoxContainer:
	var display := HBoxContainer.new()
	display.add_theme_constant_override("separation", 8)
	var icon := CoinIcon.new()
	display.add_child(icon)
	credit_label = label(str(store.credits), 24)
	display.add_child(credit_label)
	return display

func _show_play_credits() -> void:
	credit_display = _credits_widget()
	active_shell.add_child(credit_display)
	_position_play_credits()

func _position_play_credits() -> void:
	if not is_instance_valid(credit_display) or screen != "play":
		return
	var right := -132 if is_instance_valid(completed_badge) else -44
	credit_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	credit_display.offset_left = right - 120
	credit_display.offset_right = right
	credit_display.offset_top = 34
	credit_display.offset_bottom = 72

func _update_credits_display() -> void:
	if is_instance_valid(credit_label):
		credit_label.text = str(store.credits)
	_update_hint_button()

func _update_hint_button() -> void:
	if not is_instance_valid(hint_button):
		return
	hint_button.visible = hint_stage < 2
	var cost := store.hint_cost(current_level)
	hint_button.text = "Hint -%d" % cost
	hint_button.tooltip_text = "Reveal the %s (%d coin%s)." % ["start" if hint_stage == 0 else "finish", cost, "s" if cost != 1 else ""]
	hint_button.disabled = hint_busy or store.credits < cost or hint_endpoints.size() != 2

func _use_hint() -> void:
	if screen != "play" or hint_busy or hint_stage >= 2:
		return
	if store.credits < store.hint_cost(current_level) or hint_endpoints.size() != 2:
		return
	var result := store.purchase_hint(current_level)
	if result != OK:
		_show_toast("Credit could not be spent: " + error_string(result))
		return
	hint_busy = true
	_update_credits_display()
	_shake_screen()
	var token := transition_id
	var cell: int = hint_endpoints[hint_stage]
	var coin := CoinIcon.new()
	add_child(coin)
	coin.size = Vector2(30, 30)
	coin.z_index = 90
	var inverse := get_global_transform().affine_inverse()
	coin.position = inverse * credit_display.get_global_rect().get_center() - coin.size * 0.5
	var destination: Vector2 = inverse * (board.get_global_transform() * board.center(cell)) - coin.size * 0.5
	var fall := coin.create_tween().set_parallel(true)
	fall.tween_property(coin, "position", destination, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(coin, "rotation", TAU, 0.38)
	await get_tree().create_timer(0.39).timeout
	if is_instance_valid(coin):
		coin.queue_free()
	if token != transition_id or screen != "play" or not is_instance_valid(board):
		return
	var hint_label := board.show_solution_hint(cell, hint_stage == 0)
	if not is_instance_valid(hint_label):
		hint_busy = false
		_update_hint_button()
		return
	hint_stage += 1
	hint_label.modulate.a = 0.0
	hint_label.create_tween().tween_property(hint_label, "modulate:a", 1.0, 0.27).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.28).timeout
	if token != transition_id or screen != "play":
		return
	hint_busy = false
	_update_hint_button()

func _open_adjacent_uncompleted(direction: int) -> void:
	var next := store.adjacent_uncompleted(current_level, direction)
	if next != current_level:
		play_level(next, [], direction)

func _set_board_tint(color: Color, selected_line: Color = Color.TRANSPARENT) -> void:
	if not palette_text.is_equal_approx(PuzzleBoard.text_color(color)):
		_animate_ui_palette(color, 0.20, palette_text, palette_button)
	if background_tween and background_tween.is_running():
		background_tween.kill()
	if is_instance_valid(board):
		board.tint = color
		board.stroke_color = selected_line if selected_line.a > 0.0 else store.get_line_color(editor_level if screen == "editor" else current_level, color)
		board.refresh()
	if is_instance_valid(board_panel):
		board_panel.add_theme_stylebox_override("panel", box(PuzzleBoard.background_color(color), 24 if screen == "play" else 22))
	if is_instance_valid(background_rect):
		background_rect.color = PuzzleBoard.background_color(color)

func _set_background_for_level(number: int, animate: bool = false) -> void:
	var level_color := store.get_color(number)
	if animate:
		_animate_ui_palette(level_color, 0.30, palette_text, palette_button)
	else:
		if palette_tween and palette_tween.is_running():
			palette_tween.kill()
		_apply_ui_palette(level_color)
	if is_instance_valid(background_rect):
		var target := PuzzleBoard.menu_background_color(level_color) if screen == "menu" else PuzzleBoard.background_color(level_color)
		if background_tween and background_tween.is_running():
			background_tween.kill()
		if animate and background_rect.color != target:
			background_tween = create_tween()
			background_tween.tween_property(background_rect, "color", target, 0.30).set_trans(Tween.TRANS_SINE)
		else:
			background_rect.color = target

func _animate_level_background(previous: Color, target: Color, duration: float = 0.60) -> void:
	if previous == target or not is_instance_valid(background_rect):
		return
	background_rect.color = previous
	var panel_style := box(previous, 24)
	board_panel.add_theme_stylebox_override("panel", panel_style)
	background_tween = create_tween().set_parallel(true)
	background_tween.tween_property(background_rect, "color", target, duration).set_trans(Tween.TRANS_SINE)
	background_tween.tween_property(panel_style, "bg_color", target, duration).set_trans(Tween.TRANS_SINE)

func _complete_level() -> void:
	var result := store.mark_complete(current_level)
	_update_credits_display()
	_show_completed_badge()
	if result != OK:
		_show_toast("Progress could not be saved: " + error_string(result))
	var token := transition_id
	var tint := store.get_color(current_level)
	var layer := Control.new()
	layer.theme = palette_theme
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
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var praise: String = CelebrationLines.LINES[rng.randi_range(0, CelebrationLines.LINES.size() - 1)].trim_suffix(".") + "!"
	var celebration_lines := [["✦", 64, tint], ["Level %d complete!" % current_level, 40, TEXT], [praise, 18, tint]]
	for index in range(celebration_lines.size()):
		var item: Array = celebration_lines[index]
		var text_label := label(item[0], item[1], item[2])
		if index == 2:
			text_label.add_theme_color_override("font_color", PuzzleBoard.tile_color(0, tint))
		text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.add_child(text_label)
	layer.modulate.a = 0
	var fade := create_tween()
	fade.tween_property(layer, "modulate:a", 1.0, 0.35)
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
		if current_level >= store.menu_unlocked():
			layer.queue_free()
			_show_locked_feedback(get_global_mouse_position())
		else:
			_open_adjacent_uncompleted(1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and menu_drag_source > 0:
		_update_menu_drag(event.position)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and menu_drag_source > 0:
		_finish_menu_drag(event.position)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or event.echo:
		return
	var key: int = event.keycode
	if event.pressed:
		pressed_keys[key] = true
	else:
		pressed_keys.erase(key)
	if key == KEY_ESCAPE and event.pressed:
		_return_to_menu()
		get_viewport().set_input_as_handled()
		return
	var only_editor_keys := _only_keys([KEY_SHIFT, KEY_Z, KEY_O])
	var only_color_keys := _only_keys([KEY_SHIFT, KEY_Z, KEY_I])
	var only_rearrange_keys := _only_keys([KEY_SHIFT, KEY_Z, KEY_U])
	var editor_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_O) and only_editor_keys
	var color_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_I) and only_color_keys
	var rearrange_chord: bool = screen == "menu" and event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_U) and only_rearrange_keys
	var previous_chord: bool = (screen == "play" or screen == "editor") and not color_mode and event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_LEFT) and _only_keys([KEY_SHIFT, KEY_Z, KEY_LEFT])
	var next_chord: bool = (screen == "play" or screen == "editor") and not color_mode and event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_RIGHT) and _only_keys([KEY_SHIFT, KEY_Z, KEY_RIGHT])
	var unlock_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_M) and _only_keys([KEY_SHIFT, KEY_Z, KEY_M])
	var reset_chord: bool = event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_N) and _only_keys([KEY_SHIFT, KEY_Z, KEY_N])
	if (editor_chord or color_chord or rearrange_chord or previous_chord or next_chord or unlock_chord or reset_chord) and event.pressed and not chord_active:
		chord_active = true
		pending_undo = false
		get_viewport().set_input_as_handled()
		if editor_chord:
			_toggle_editor()
		elif color_chord:
			_toggle_color_editor()
		elif rearrange_chord:
			_toggle_rearrange()
		elif previous_chord:
			_navigate_level(-1)
		elif next_chord:
			_navigate_level(1)
		elif unlock_chord or reset_chord:
			_change_completion(unlock_chord)
		return
	if not editor_chord and not color_chord and not rearrange_chord and not previous_chord and not next_chord and not unlock_chord and not reset_chord:
		chord_active = false
	if screen == "editor" and not color_mode:
		if key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and event.pressed and not editor_playtesting and not event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			var direction := Vector2i.ZERO
			match key:
				KEY_LEFT:
					direction = Vector2i.LEFT
				KEY_RIGHT:
					direction = Vector2i.RIGHT
				KEY_UP:
					direction = Vector2i.UP
				KEY_DOWN:
					direction = Vector2i.DOWN
			_shift_editor_tiles(direction)
			get_viewport().set_input_as_handled()
			return
		if key == KEY_SPACE and event.pressed and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			_toggle_editor_playtest()
			get_viewport().set_input_as_handled()
			return
		if editor_playtesting:
			return
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

func _navigate_level(step: int) -> void:
	if screen == "play":
		if current_level + step >= 1:
			play_level(current_level + step, [], step)
	elif screen == "editor":
		var next := editor_level + step
		if next < 1 or next > 100000:
			return
		if editor_playtesting:
			_toggle_editor_playtest()
		_select_editor_level(float(next))

func _return_to_menu() -> void:
	pending_menu_level = 0
	if screen == "menu" and not rearrange_mode and not color_mode:
		return
	rearrange_mode = false
	color_mode = false
	editor_playtesting = false
	menu_hovered_level = 0
	return_screen = "menu"
	pending_undo = false
	chord_active = false
	show_menu()

func _change_completion(unlock: bool) -> void:
	var result := store.complete_first(99) if unlock else store.reset_completion_to_first()
	if result != OK:
		_show_toast("Progress could not be saved: " + error_string(result))
		return
	menu_hovered_level = 0
	show_menu()

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
	if color_mode:
		_toggle_color_editor()
	if screen == "editor":
		if return_screen == "play":
			play_level(current_level, saved_path)
		else:
			show_menu()
		return
	return_screen = screen
	saved_path = board.path.duplicate() if is_instance_valid(board) and not board.locked else []
	editor_level = current_level if screen == "play" else (menu_hovered_level if menu_hovered_level > 0 else store.frontier())
	editor_data = store.get_level(editor_level)
	undo_stack.clear()
	redo_stack.clear()
	_show_editor()

func _show_editor() -> void:
	screen = "editor"
	editor_playtesting = false
	_shell()
	var title_row := HBoxContainer.new()
	content.add_child(title_row)
	title_row.add_child(label("Level workshop", 34))
	spacer(title_row)
	var title_hints := VBoxContainer.new()
	title_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_child(title_hints)
	editor_mode_hint = label("BUILD MODE · SPACE TO PLAYTEST", 12, ACCENT)
	editor_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_hints.add_child(editor_mode_hint)
	var leave_hint := label("SHIFT + Z + O TO RETURN", 12, MUTED)
	leave_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_hints.add_child(leave_hint)
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workspace)
	var panel := PanelContainer.new()
	board_panel = panel
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(PuzzleBoard.background_color(store.get_color(editor_level)), 22))
	workspace.add_child(panel)
	board = PuzzleBoard.new()
	board.custom_minimum_size = Vector2(320, 330)
	board.editing = true
	panel.add_child(board)
	board.configure(editor_data, store.get_color(editor_level), store.get_line_color(editor_level))
	board.solved.connect(_editor_playtest_solved)
	board.paint_started.connect(func(): stroke_before = editor_data.duplicate(true))
	board.cell_painted.connect(_paint_cell)
	board.light_painted.connect(_paint_light_cell)
	board.paint_finished.connect(_finish_stroke)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.custom_minimum_size.x = 245
	controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(controls_scroll)
	var controls := VBoxContainer.new()
	editor_controls = controls
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 9)
	controls_scroll.add_child(controls)
	editor_solve_button = button("Solve puzzle", _solve_editor, true)
	editor_solve_button.focus_mode = Control.FOCUS_NONE
	controls.add_child(editor_solve_button)
	controls.add_child(label("SAVE AS LEVEL", 12, MUTED))
	var number_input := _spin(editor_level, 1, 100000)
	editor_number_input = number_input
	controls.add_child(number_input)
	number_input.value_changed.connect(_select_editor_level)
	var layout_transfer := HBoxContainer.new()
	controls.add_child(layout_transfer)
	layout_transfer.add_child(button("Copy", _copy_editor_layout))
	layout_transfer.add_child(button("Paste", _paste_editor_layout))
	controls.add_child(button("Insert level here", _insert_editor_level))
	controls.add_child(button("Delete saved level", _delete_editor_level))
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
	if editor_generation_moves < 2:
		editor_generation_moves = mini(editor_level + 26, int(editor_data.width) * int(editor_data.height))
	controls.add_child(label("MOVES (TILES IN LINE)", 12, MUTED))
	move_input = _spin(editor_generation_moves, 2, 32768)
	controls.add_child(move_input)
	move_input.value_changed.connect(func(value: float): editor_generation_moves = int(value))
	controls.add_child(label("REQUIRED CROSSOVERS", 12, MUTED))
	crossover_input = _spin(editor_required_crossings, 0, 16384)
	controls.add_child(crossover_input)
	crossover_input.value_changed.connect(func(value: float): editor_required_crossings = int(value))
	controls.add_child(button("Generate random level", _generate_editor_level))
	var gray_suggestion := button("Suggest gray tiles", _suggest_editor_gray_tiles)
	gray_suggestion.tooltip_text = "Apply a small gray bridge, junction, or crossover. Ctrl + Z undoes the placement."
	gray_suggestion.focus_mode = Control.FOCUS_NONE
	controls.add_child(gray_suggestion)
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
	controls.add_child(label("Arrow keys shift tiles by one; edges wrap.", 12, MUTED))
	editor_message = label("Paint, then save to replace\nthe generated puzzle.", 13, ACCENT)
	editor_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(editor_message)
	controls.move_child(editor_message, 1)
	content.add_child(label("Neutral tiles never flip. Solve puzzle finds a legal line and shows it in playtest mode.", 13, MUTED))

func _solve_editor() -> void:
	if editor_solver != null:
		_toggle_editor_playtest()
		editor_message.text = "Search cancelled. The puzzle is unchanged."
		return
	if screen != "editor" or editor_playtesting or color_mode:
		return
	_toggle_editor_playtest()
	board.locked = true
	editor_mode_hint.text = "SOLVING · SPACE TO CANCEL"
	editor_message.text = "Searching for a legal line…"
	editor_solve_button.text = "Cancel solve"
	editor_solve_button.disabled = false
	var token := transition_id
	var layout := editor_data.duplicate(true)
	if not layout.get("solution") is Array:
		var saved := store.get_level(editor_level)
		if saved.width == layout.width and saved.height == layout.height and saved.tiles == layout.tiles and saved.get("solution") is Array:
			layout["solution"] = saved.solution.duplicate()
	var search := PuzzleSolver.new(layout)
	editor_solver = search
	# Let the status and Cancel button draw before exploring routes.
	await get_tree().process_frame
	if token != transition_id or screen != "editor" or editor_solver != search:
		return
	var started := Time.get_ticks_msec()
	while editor_solver == search and token == transition_id and screen == "editor":
		search.advance()
		if search.status == "solved":
			editor_solver = null
			editor_solve_button.text = "Solve puzzle"
			editor_solve_button.disabled = true
			board.path = search.solution.duplicate()
			board.refresh(true)
			_editor_playtest_solved()
			editor_message.text += " Line length: %d tiles." % board.path.size()
			return
		if search.status == "unsolvable":
			_toggle_editor_playtest()
			editor_message.text = "No legal solution exists for this layout."
			return
		board.path = search.last_checked_path.duplicate()
		board.refresh()
		editor_message.text = "Searching… %s paths checked (%ds).\nLast path: %d tiles.\nCancel to keep editing." % [search.nodes, (Time.get_ticks_msec() - started) / 1000, board.path.size()]
		await get_tree().process_frame

func _toggle_editor_playtest() -> void:
	if screen != "editor" or not is_instance_valid(board):
		return
	editor_solver = null
	if is_instance_valid(editor_solve_button):
		editor_solve_button.text = "Solve puzzle"
	board._end()
	board._end_light()
	_finish_stroke()
	editor_playtesting = not editor_playtesting
	board.clear_path()
	board.editing = not editor_playtesting
	_set_editor_tools_enabled(not editor_playtesting)
	if editor_playtesting:
		editor_mode_hint.text = "PLAYTEST MODE · SPACE TO BUILD"
		editor_message.text = "Draw a line to test this layout."
	else:
		_sync_editor()
		editor_mode_hint.text = "BUILD MODE · SPACE TO PLAYTEST"
		editor_message.text = "Returned to building. Test line cleared."

func _set_editor_tools_enabled(enabled: bool) -> void:
	if not is_instance_valid(editor_controls):
		return
	var pending: Array[Node] = [editor_controls]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Button:
			(node as Button).disabled = not enabled
		elif node is SpinBox:
			(node as SpinBox).editable = enabled
		for child in node.get_children():
			pending.append(child)

func _editor_playtest_solved() -> void:
	if editor_playtesting:
		editor_mode_hint.text = "SOLVED · SPACE TO BUILD"
		var result := store.record_editor_solution(editor_level, editor_data, board.path)
		editor_message.text = "Solved! Start and finish saved. Press Space to build." if result == OK else "Solution could not be saved: " + error_string(result)

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
	board._end_light()
	_finish_stroke()
	if not editor_data.tiles.has(1) and not editor_data.tiles.has(2):
		editor_message.text = "The board is already all white."
		return
	_record_edit()
	_forget_editor_solution()
	editor_data.tiles.fill(0)
	board.tiles = editor_data.tiles.duplicate()
	board.refresh()
	editor_message.text = "Board cleared. Paint dark tiles before saving."

func _generate_editor_level() -> void:
	if editor_playtesting:
		return
	board._end()
	board._end_light()
	_finish_stroke()
	var width := int(width_input.value)
	var height := int(height_input.value)
	var moves := int(move_input.value)
	if moves > width * height + editor_required_crossings:
		editor_message.text = "%d moves need a larger grid or more crossovers." % moves
		return
	if moves - editor_required_crossings < 2:
		editor_message.text = "Too many crossovers for %d moves." % moves
		return
	var generated := Puzzle.generate(editor_level, Vector2i(width, height), editor_required_crossings, randi(), moves, true)
	if generated.is_empty():
		editor_message.text = "No line found with %d moves and exactly %d crossovers. Try again or change settings." % [moves, editor_required_crossings]
		return
	var before := _structural_snapshot()
	var result := store.record_editor_solution(editor_level, generated, generated.solution)
	if result != OK:
		editor_message.text = "Generated puzzle could not be saved: " + error_string(result)
		return
	undo_stack.append(before)
	redo_stack.clear()
	editor_data = store.get_level(editor_level)
	if editor_level == current_level:
		saved_path.clear()
	_sync_editor()
	var unique_cells: Dictionary = {}
	for cell in generated.solution:
		unique_cells[cell] = true
	var used: int = generated.solution.size() - unique_cells.size()
	editor_message.text = "Generated and saved %d moves with exactly %d crossovers, including the solution." % [moves, used]

func _suggest_editor_gray_tiles() -> void:
	if screen != "editor" or editor_playtesting or color_mode:
		return
	board._end()
	board._end_light()
	_finish_stroke()
	var layout := editor_data.duplicate(true)
	if not layout.has("solution"):
		var saved := store.get_level(editor_level)
		if saved.width == layout.width and saved.height == layout.height and saved.tiles == layout.tiles:
			for field in ["solution", "solution_start", "solution_end"]:
				if saved.has(field):
					layout[field] = saved[field]
	var suggestion := Puzzle.suggest_gray_tiles(layout)
	if suggestion.is_empty():
		editor_message.text = "No useful gray placement found. Try a layout with light gaps between dark groups."
		return
	_record_edit()
	_forget_editor_solution()
	for cell in suggestion.cells:
		editor_data.tiles[cell] = 2
	_sync_editor()
	editor_message.text = "Added %d gray tile%s for %s. Ctrl + Z to undo; Save level to keep it." % [suggestion.cells.size(), "" if suggestion.cells.size() == 1 else "s", suggestion.reason]

func _copy_editor_layout() -> void:
	board._end()
	board._end_light()
	_finish_stroke()
	copied_editor_data = editor_data.duplicate(true)
	editor_message.text = "Layout copied. Select a level number and paste."

func _select_editor_level(value: float) -> void:
	if restoring_editor or editor_level == int(value):
		return
	board._end()
	board._end_light()
	_finish_stroke()
	editor_level = int(value)
	editor_data = store.get_level(editor_level)
	undo_stack.clear()
	redo_stack.clear()
	_sync_editor()
	editor_message.text = "Level %d loaded. Copy and paste to reuse a layout." % editor_level

func _paste_editor_layout() -> void:
	if copied_editor_data.is_empty():
		editor_message.text = "Copy a layout first."
		return
	board._end()
	board._end_light()
	_finish_stroke()
	if editor_data == copied_editor_data:
		editor_message.text = "This layout is already pasted."
		return
	_record_edit()
	editor_data = copied_editor_data.duplicate(true)
	_sync_editor()
	editor_message.text = "Layout pasted into level %d. Save to keep it." % editor_level

func _record_edit() -> void:
	undo_stack.append(editor_data.duplicate(true))
	if undo_stack.size() > 200:
		undo_stack.pop_front()
	redo_stack.clear()

func _forget_editor_solution() -> void:
	editor_data.erase("solution")
	editor_data.erase("solution_start")
	editor_data.erase("solution_end")

func _shift_editor_tiles(direction: Vector2i) -> void:
	if screen != "editor" or color_mode or editor_playtesting:
		return
	board._end()
	board._end_light()
	_finish_stroke()
	var width := int(editor_data.width)
	var height := int(editor_data.height)
	var shifted: Array = []
	shifted.resize(width * height)
	for y in range(height):
		for x in range(width):
			var destination_x := (x + direction.x + width) % width
			var destination_y := (y + direction.y + height) % height
			shifted[destination_y * width + destination_x] = editor_data.tiles[y * width + x]
	if shifted == editor_data.tiles:
		return
	_record_edit()
	_forget_editor_solution()
	editor_data.tiles = shifted
	_sync_editor()
	editor_message.text = "Shifted all tiles one space. Save level to keep it."

func _paint_cell(cell: int) -> void:
	_paint_value(cell, brush)

func _paint_light_cell(cell: int) -> void:
	_paint_value(cell, 0)

func _paint_value(cell: int, value: int) -> void:
	if editor_data.tiles[cell] == value:
		return
	_forget_editor_solution()
	editor_data.tiles[cell] = value
	board.tiles[cell] = value
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
	editor_number_input.value = editor_level
	width_input.value = editor_data.width
	height_input.value = editor_data.height
	restoring_editor = false
	board.configure(editor_data, store.get_color(editor_level), store.get_line_color(editor_level))
	_set_board_tint(store.get_color(editor_level))

func _editor_undo() -> void:
	_finish_stroke()
	if undo_stack.is_empty():
		return
	var previous: Dictionary = undo_stack.pop_back()
	if previous.get("_structure", false):
		redo_stack.append(_structural_snapshot())
		_restore_structure(previous)
	else:
		redo_stack.append(editor_data.duplicate(true))
		editor_data = previous
		_sync_editor()
	editor_message.text = "Undid the last edit."

func _editor_redo() -> void:
	_finish_stroke()
	if redo_stack.is_empty():
		return
	var next: Dictionary = redo_stack.pop_back()
	if next.get("_structure", false):
		undo_stack.append(_structural_snapshot())
		_restore_structure(next)
	else:
		undo_stack.append(editor_data.duplicate(true))
		editor_data = next
		_sync_editor()
	editor_message.text = "Redid the last edit."

func _structural_snapshot() -> Dictionary:
	return {"_structure": true, "levels": store.levels.duplicate(true), "completed": store.completed.duplicate(true), "hints": store.hints.duplicate(true), "editor_level": editor_level, "editor_data": editor_data.duplicate(true), "current_level": current_level, "saved_path": saved_path.duplicate()}

func _restore_structure(snapshot: Dictionary) -> void:
	store.levels = snapshot.levels.duplicate(true)
	store.completed = snapshot.completed.duplicate(true)
	store.hints = snapshot.hints.duplicate(true)
	var result := store.save_levels()
	if result == OK:
		result = store.save_progress()
	editor_level = int(snapshot.editor_level)
	current_level = int(snapshot.current_level)
	saved_path = snapshot.saved_path.duplicate()
	editor_data = snapshot.editor_data.duplicate(true)
	_sync_editor()
	if result != OK:
		editor_message.text = "Could not save restored levels: " + error_string(result)

func _insert_editor_level() -> void:
	board._end()
	board._end_light()
	_finish_stroke()
	if not editor_data.tiles.has(1):
		editor_message.text = "Add at least one dark tile before inserting."
		return
	var before := _structural_snapshot()
	var result := store.insert_level(editor_level, editor_data)
	if result != OK:
		editor_message.text = "Insert failed: " + error_string(result)
		return
	undo_stack.append(before)
	redo_stack.clear()
	if current_level >= editor_level:
		current_level += 1
	saved_path.clear()
	_sync_editor()
	editor_message.text = "Inserted level %d. Later custom levels moved up." % editor_level

func _delete_editor_level() -> void:
	board._end()
	board._end_light()
	_finish_stroke()
	if not store.levels.has(str(editor_level)):
		editor_message.text = "Level %d has no saved layout to delete." % editor_level
		return
	var before := _structural_snapshot()
	var result := store.delete_level(editor_level)
	if result != OK:
		editor_message.text = "Delete failed: " + error_string(result)
		return
	undo_stack.append(before)
	redo_stack.clear()
	if current_level > editor_level:
		current_level -= 1
	saved_path.clear()
	editor_data = store.get_level(editor_level)
	_sync_editor()
	editor_message.text = "Deleted level %d. Later custom levels moved down." % editor_level

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
	if editor_solver != null:
		_toggle_editor_playtest()
	if screen == "play" and is_instance_valid(board) and board.locked and not color_mode:
		return
	if color_mode:
		color_mode = false
		if is_instance_valid(overlay):
			overlay.queue_free()
			overlay = null
		if is_instance_valid(board):
			board.locked = color_previous_board_locked
			_set_board_tint(store.get_color(editor_level if screen == "editor" else current_level))
		if screen == "menu":
			show_menu()
		elif screen == "play":
			play_level(current_level, board.path.duplicate())
		return
	color_mode = true
	transition_id += 1
	if is_instance_valid(board):
		color_previous_board_locked = board.locked
		board._end()
		board._end_light()
		board.locked = true
	color_level = editor_level if screen == "editor" else (current_level if screen == "play" else (menu_hovered_level if menu_hovered_level > 0 else store.frontier()))
	color_selecting_line = false
	overlay = Control.new()
	overlay.theme = palette_theme
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
	controls.custom_minimum_size.x = 700
	panel.add_child(controls)
	controls.add_child(label("Choose your colors.", 30))
	controls.add_child(label("SHIFT + Z + I TO RETURN", 12, MUTED))
	var picker := ColorPicker.new()
	color_picker = picker
	picker.edit_alpha = false
	picker.custom_minimum_size.x = 400
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.can_add_swatches = false
	picker.color_modes_visible = false
	picker.sliders_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	var number_input := _spin(color_level, 1, 100000)
	controls.add_child(label("LEVEL NUMBER", 12, MUTED))
	controls.add_child(number_input)
	color_group_label = label("", 13, MUTED)
	controls.add_child(color_group_label)
	var transfer_row := HBoxContainer.new()
	controls.add_child(transfer_row)
	transfer_row.add_child(button("Copy colors", _copy_area_colors))
	color_paste_button = button("Paste colors", _paste_area_colors)
	color_paste_button.disabled = copied_area_colors.is_empty()
	transfer_row.add_child(color_paste_button)
	var palette_row := HBoxContainer.new()
	controls.add_child(palette_row)
	palette_row.add_child(picker)
	var preview_column := VBoxContainer.new()
	preview_column.custom_minimum_size.x = 285
	palette_row.add_child(preview_column)
	preview_column.add_child(label("LIVE PREVIEW", 12, MUTED))
	color_preview = PuzzleBoard.new()
	color_preview.custom_minimum_size = Vector2(285, 145)
	color_preview.size = Vector2(285, 145)
	color_preview.thumbnail_mode = true
	preview_column.add_child(color_preview)
	color_preview.configure({"width": 3, "height": 1, "tiles": [1, 0, 1]}, color_draft, line_draft)
	color_preview.path = [0, 1, 2]
	color_preview.refresh()
	color_preview.locked = true
	color_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_preview.set_process_input(false)
	color_tile_button = button("Tile hue", func(): _select_color_target(false))
	preview_column.add_child(color_tile_button)
	color_line_button = button("Line color", func(): _select_color_target(true))
	preview_column.add_child(color_line_button)
	preview_column.add_child(button("Use suggested line color", _reset_line_draft))
	color_feedback = label("Tile brightness stays fixed. Choose any line color.", 13, MUTED)
	controls.add_child(color_feedback)
	number_input.value_changed.connect(func(value: float): _load_color_drafts(int(value)))
	picker.color_changed.connect(_color_picker_changed)
	controls.add_child(button("Save area colors", _save_color_selection, true))
	_load_color_drafts(color_level)

func _load_color_drafts(number: int) -> void:
	if LevelStore.group_start(number) == LevelStore.group_start(color_level) and is_instance_valid(color_preview) and not color_group_label.text.is_empty():
		color_level = number
		return
	color_level = number
	color_draft = Color.from_hsv(store.get_color(number).h, 1.0, 1.0)
	line_custom_draft = store.line_colors.has(str(LevelStore.group_start(number)))
	line_draft = store.get_line_color(number)
	color_group_label.text = "Levels %d–%d share these colors." % [LevelStore.group_start(number), LevelStore.group_start(number) + 4]
	_update_color_controls()

func _select_color_target(select_line: bool) -> void:
	color_selecting_line = select_line
	_update_color_controls()

func _update_color_controls() -> void:
	color_picker_loading = true
	color_picker.color = line_draft if color_selecting_line else color_draft
	color_picker_loading = false
	color_tile_button.theme_type_variation = "" if color_selecting_line else "PrimaryButton"
	color_line_button.theme_type_variation = "PrimaryButton" if color_selecting_line else ""
	_update_color_preview()

func _update_color_preview() -> void:
	if is_instance_valid(color_preview):
		color_preview.tint = color_draft
		color_preview.stroke_color = line_draft
		color_preview.refresh()

func _color_picker_changed(color: Color) -> void:
	if color_picker_loading:
		return
	if color_selecting_line:
		line_draft = Color(color.r, color.g, color.b)
		line_custom_draft = true
	else:
		color_draft = color
		if not line_custom_draft:
			line_draft = LevelStore.DEFAULT_LINE_COLOR
	_update_color_preview()
	if is_instance_valid(board) and LevelStore.group_start(color_level) == LevelStore.group_start(editor_level if screen == "editor" else current_level):
		_set_board_tint(color_draft, line_draft)

func _reset_line_draft() -> void:
	line_custom_draft = false
	line_draft = LevelStore.DEFAULT_LINE_COLOR
	_update_color_controls()
	if is_instance_valid(board) and LevelStore.group_start(color_level) == LevelStore.group_start(editor_level if screen == "editor" else current_level):
		_set_board_tint(color_draft, line_draft)

func _copy_area_colors() -> void:
	copied_area_colors = {"tile": color_draft, "line": line_draft, "custom_line": line_custom_draft}
	color_paste_button.disabled = false
	color_feedback.text = "Colors copied. Choose another level and paste."

func _paste_area_colors() -> void:
	if copied_area_colors.is_empty():
		return
	color_draft = copied_area_colors.tile
	line_draft = copied_area_colors.line
	line_custom_draft = copied_area_colors.custom_line
	_update_color_controls()
	if is_instance_valid(board) and LevelStore.group_start(color_level) == LevelStore.group_start(editor_level if screen == "editor" else current_level):
		_set_board_tint(color_draft, line_draft)
	color_feedback.text = "Colors pasted. Save area colors to keep them."

func _save_color_selection() -> void:
	var result := store.save_area_colors(color_level, color_draft, line_draft, line_custom_draft)
	var start := LevelStore.group_start(color_level)
	color_feedback.text = "Colors saved for levels %d–%d." % [start, start + 4] if result == OK else "Save failed: " + error_string(result)

func _show_toast(message: String) -> void:
	if is_instance_valid(toast):
		toast.queue_free()
	toast = label(message, 14, ACCENT)
	toast.theme = palette_theme
	toast.position = Vector2(44, 8)
	toast.z_index = 100
	add_child(toast)
	toast_timer = 5.0

func _process(delta: float) -> void:
	_process_menu_thumbnails()
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0 and is_instance_valid(toast):
			toast.queue_free()
