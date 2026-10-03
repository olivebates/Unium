extends Control

const CelebrationLines = preload("res://scripts/celebration_lines.gd")
const RearrangeCard = preload("res://scripts/rearrange_card.gd")

const BG := Color("0c1219")
const PANEL := Color("141e28")
const TEXT := Color("e8eee9")
const MUTED := Color("88979e")
const ACCENT := Color("b6ead3")
const MENU_PAGE_SIZE := 30
const MENU_MAX_COLUMNS := 15

var store := LevelStore.new()
var screen := "menu"
var current_level := 1
var board: PuzzleBoard
var board_panel: PanelContainer
var background_rect: ColorRect
var background_tween: Tween
var palette_tween: Tween
var palette_text := Color.WHITE
var palette_button := Color.BLACK
var menu_hovered_level := 0
var content: VBoxContainer
var overlay: Control
var toast: Label
var toast_timer := 0.0
var transition_id := 0
var menu_page := 0
var rearrange_mode := false
var rearrange_action := "insert"
var menu_rows: VBoxContainer
var menu_cards: Array[Button] = []
var menu_columns := 0
var menu_thumbnail_cache: Dictionary = {}
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
var width_input: SpinBox
var height_input: SpinBox
var move_input: SpinBox
var editor_generation_moves := -1
var crossover_input: SpinBox
var editor_required_crossings := Puzzle.MAX_GENERATED_CROSSINGS
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
	_build_theme()
	resized.connect(_update_menu_columns)
	show_menu()

func _update_menu_columns() -> void:
	if not is_instance_valid(menu_rows):
		return
	var columns := mini(MENU_MAX_COLUMNS, maxi(1, int((size.x - 88 + 12) / 76)))
	menu_rows.custom_minimum_size.x = columns * 64 + (columns - 1) * 12
	if columns == menu_columns and menu_rows.get_child_count() > 0:
		return
	menu_columns = columns
	for row in menu_rows.get_children():
		for card in row.get_children():
			row.remove_child(card)
		menu_rows.remove_child(row)
		row.queue_free()
	for first in range(0, menu_cards.size(), columns):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)
		menu_rows.add_child(row)
		for index in range(first, mini(first + columns, menu_cards.size())):
			row.add_child(menu_cards[index])

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

func _apply_ui_palette(color: Color) -> void:
	_apply_ui_colors(_ui_text_color(color), _ui_button_color(color))

func _ui_text_color(color: Color) -> Color:
	return PuzzleBoard.menu_text_color(color) if screen == "menu" else PuzzleBoard.text_color(color)

func _ui_button_color(color: Color) -> Color:
	return PuzzleBoard.menu_button_color(color) if screen == "menu" else PuzzleBoard.button_color(color)

func _apply_ui_colors(light: Color, dark: Color) -> void:
	palette_text = light
	palette_button = dark
	for kind in ["Label", "Button", "LineEdit", "SpinBox"]:
		theme.set_color("font_color", kind, light)
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		theme.set_color(state, "Button", light)
	_style_buttons("Button", dark, light)
	_style_buttons("PrimaryButton", PuzzleBoard.balanced_color(dark.h, 0.50, 0.12), light)

func _style_buttons(kind: String, base: Color, text_color: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var fill := base
		if state == "hover":
			fill = PuzzleBoard.balanced_color(base.h, base.s, PuzzleBoard.luminance(base) + 0.012)
		elif state == "pressed":
			fill = PuzzleBoard.balanced_color(base.h, base.s, maxf(0.02, PuzzleBoard.luminance(base) - 0.012))
		var style := box(fill, 12)
		style.content_margin_left = 20
		style.content_margin_right = 20
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = text_color
			style.set_border_width_all(2)
		theme.set_stylebox(state, kind, style)

func _animate_ui_palette(target_color: Color, duration: float, from_text: Color, from_button: Color) -> void:
	if palette_tween and palette_tween.is_running():
		palette_tween.kill()
	var target_text := _ui_text_color(target_color)
	var target_button := _ui_button_color(target_color)
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

func _shell() -> void:
	_cancel_menu_drag()
	transition_id += 1
	if background_tween and background_tween.is_running():
		background_tween.kill()
	background_tween = null
	if palette_tween and palette_tween.is_running():
		palette_tween.kill()
	palette_tween = null
	for child in get_children():
		remove_child(child)
		child.queue_free()
	board = null
	board_panel = null
	menu_rows = null
	menu_cards.clear()
	menu_columns = 0
	background_rect = null
	toast = null
	overlay = null
	background_rect = ColorRect.new()
	background_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background_rect)
	_set_background_for_level(editor_level if screen == "editor" else (current_level if screen == "play" else (menu_hovered_level if menu_hovered_level > 0 else store.frontier())))
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
	if screen == "menu":
		var header := HBoxContainer.new()
		content.add_child(header)
		header.add_child(label("H e a r t h l i n e", 28))
		spacer(header)
		header.add_child(button("Play level %d   →" % store.frontier(), func(): play_level(store.frontier()), true))
		var separator := HSeparator.new()
		separator.modulate = Color(1, 1, 1, 0.16)
		content.add_child(separator)

func show_menu() -> void:
	screen = "menu"
	color_mode = false
	_shell()
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
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var rows := VBoxContainer.new()
	menu_rows = rows
	rows.add_theme_constant_override("separation", 12)
	var centered_rows := HBoxContainer.new()
	centered_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centered_rows)
	spacer(centered_rows)
	centered_rows.add_child(rows)
	spacer(centered_rows)
	var unlocked := store.menu_unlocked()
	menu_page = clampi(menu_page, 0, int((unlocked - 1) / MENU_PAGE_SIZE))
	var first := 1 if rearrange_mode else menu_page * MENU_PAGE_SIZE + 1
	var last := unlocked + 1 if rearrange_mode else mini(unlocked + 1, (menu_page + 1) * MENU_PAGE_SIZE + 1)
	for number in range(first, last):
		menu_cards.append(_level_card(number))
	_update_menu_columns()
	if unlocked > MENU_PAGE_SIZE and not rearrange_mode:
		var pages := HBoxContainer.new()
		content.add_child(pages)
		var previous := button("← Previous", func(): menu_page -= 1; show_menu())
		previous.disabled = menu_page == 0
		pages.add_child(previous)
		spacer(pages)
		pages.add_child(label("Page %d" % (menu_page + 1), 14, MUTED))
		spacer(pages)
		var next := button("Next →", func(): menu_page += 1; show_menu())
		next.disabled = (menu_page + 1) * MENU_PAGE_SIZE >= unlocked
		pages.add_child(next)

func _level_card(number: int) -> Button:
	var card := RearrangeCard.new()
	card.level_number = number
	card.rearranging = rearrange_mode
	card.mouse_default_cursor_shape = Control.CURSOR_MOVE if rearrange_mode else Control.CURSOR_POINTING_HAND
	if rearrange_mode:
		card.drag_pressed.connect(_start_menu_drag)
	else:
		card.pressed.connect(func(): play_level(number))
	card.mouse_entered.connect(func():
		if screen == "menu" and not color_mode and menu_drag_source == 0:
			menu_hovered_level = number
			_set_background_for_level(number, true)
	)
	card.custom_minimum_size = Vector2(64, 64)
	card.size_flags_horizontal = Control.SIZE_FILL
	var preview := TextureRect.new()
	preview.position = Vector2.ZERO
	preview.size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(preview)
	var level := store.get_level(number)
	var tint := store.get_color(number)
	var line_tint := store.get_line_color(number)
	var signature := hash([level.width, level.height, level.tiles, tint.to_html(), line_tint.to_html()])
	var cached: Dictionary = menu_thumbnail_cache.get(number, {})
	if cached.get("signature") == signature:
		preview.texture = cached.texture
	else:
		# Render each level once, then release its viewport. Dragging only moves textures.
		var viewport := SubViewport.new()
		viewport.size = Vector2i(128, 128)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		viewport.gui_disable_input = true
		preview.add_child(viewport)
		var miniature := PuzzleBoard.new()
		miniature.size = Vector2(128, 128)
		miniature.thumbnail_mode = true
		viewport.add_child(miniature)
		miniature.configure(level, tint, line_tint)
		miniature.locked = true
		miniature.set_process_input(false)
		preview.texture = viewport.get_texture()
		_cache_menu_thumbnail(number, signature, viewport, preview)
	var number_label := label("%d" % number, 11)
	number_label.position = Vector2(5, 45)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_label(number_label)
	card.add_child(number_label)
	if store.completed.get(str(number), false):
		var checkmark := label("✓", 18)
		checkmark.position = Vector2(41, 39)
		checkmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_outline_label(checkmark)
		card.add_child(checkmark)
	var outline := Panel.new()
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := box(Color.TRANSPARENT, 9)
	outline_style.border_color = PuzzleBoard.tile_color(0, store.get_color(number))
	outline_style.set_border_width_all(2)
	outline.add_theme_stylebox_override("panel", outline_style)
	card.add_child(outline)
	return card

func _cache_menu_thumbnail(number: int, signature: int, viewport: SubViewport, preview: TextureRect) -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport) or not is_instance_valid(preview):
		return
	if not preview.is_inside_tree():
		return
	var snapshot := viewport.get_texture().get_image()
	if snapshot.is_empty():
		return
	var texture := ImageTexture.create_from_image(snapshot)
	menu_thumbnail_cache[number] = {"signature": signature, "texture": texture}
	preview.texture = texture
	viewport.queue_free()

func _start_menu_drag(source: int, pointer: Vector2) -> void:
	if not rearrange_mode or screen != "menu":
		return
	_cancel_menu_drag()
	menu_drag_source = source
	menu_drag_origin = pointer

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
		var source_card := menu_cards[menu_drag_source - 1]
		source_card.modulate.a = 0.0
		menu_drag_icon = TextureRect.new()
		menu_drag_icon.texture = (source_card.get_child(0) as TextureRect).texture
		menu_drag_icon.size = Vector2(64, 64)
		menu_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		menu_drag_icon.stretch_mode = TextureRect.STRETCH_SCALE
		menu_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		menu_drag_icon.modulate.a = 0.9
		var number_label := label("%d" % menu_drag_source, 11)
		number_label.position = Vector2(5, 45)
		number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_outline_label(number_label)
		menu_drag_icon.add_child(number_label)
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
			target = index + 1
	if target == menu_drag_source:
		target = 0
	var after := target > 0 and pointer.x >= slots[target - 1].x + 32.0
	if target != menu_drag_target or after != menu_drag_after:
		menu_drag_target = target
		menu_drag_after = after
		_animate_menu_drag_preview(slots)

func _animate_menu_drag_preview(slots: Array[Vector2]) -> void:
	var order: Array[int] = []
	for index in range(menu_cards.size()):
		order.append(index)
	if menu_drag_target > 0:
		var source_index := menu_drag_source - 1
		var target_index := menu_drag_target - 1
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
		if index == menu_drag_source - 1:
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
	menu_page = 0
	show_menu()

func _rearrange_level(source: int, target: int, after: bool) -> void:
	var result := store.rearrange_level(source, target, rearrange_action, after)
	if result != OK:
		_show_toast("Levels could not be rearranged: " + error_string(result))
		return
	menu_hovered_level = 0
	show_menu()

func _outline_label(node: Label) -> void:
	node.add_theme_constant_override("outline_size", 3)
	node.add_theme_color_override("font_outline_color", Color.BLACK)

func play_level(number: int, restore: Array = []) -> void:
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
	var fade_duration := 0.60 if changing_set else 0.30
	current_level = number
	screen = "play"
	color_mode = false
	_shell()
	var level := store.get_level(number)
	content.add_child(label("Level %d" % number, 38))
	var panel := PanelContainer.new()
	board_panel = panel
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", box(PuzzleBoard.background_color(tint), 24))
	content.add_child(panel)
	var play_area := Control.new()
	play_area.custom_minimum_size = Vector2(340, 320)
	panel.add_child(play_area)
	board = PuzzleBoard.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play_area.add_child(board)
	board.configure(level, tint, store.get_line_color(number))
	board.path = restore.duplicate()
	board.refresh()
	board.solved.connect(_complete_level)
	var controls := HBoxContainer.new()
	content.add_child(controls)
	controls.add_child(button("← All puzzles", show_menu))
	controls.add_child(button("↻ Reset line", func(): board.clear_path()))
	if changing_set or not previous_background.is_equal_approx(PuzzleBoard.background_color(tint)):
		_animate_level_background(previous_background, PuzzleBoard.background_color(tint), fade_duration)
	if changing_set or not previous_text.is_equal_approx(PuzzleBoard.text_color(tint)):
		_animate_ui_palette(tint, fade_duration, previous_text, previous_button)

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
		play_level(current_level + 1)

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
	var unlock_chord: bool = event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_M) and _only_keys([KEY_CTRL, KEY_Z, KEY_M])
	var reset_chord: bool = event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed and not event.meta_pressed and pressed_keys.has(KEY_Z) and pressed_keys.has(KEY_N) and _only_keys([KEY_CTRL, KEY_Z, KEY_N])
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
			play_level(current_level + step)
	elif screen == "editor":
		var next := editor_level + step
		if next < 1 or next > 100000:
			return
		if editor_playtesting:
			_toggle_editor_playtest()
		_select_editor_level(float(next))

func _return_to_menu() -> void:
	if screen == "menu" and not rearrange_mode and not color_mode:
		return
	rearrange_mode = false
	color_mode = false
	editor_playtesting = false
	menu_hovered_level = 0
	menu_page = 0
	return_screen = "menu"
	pending_undo = false
	chord_active = false
	show_menu()

func _change_completion(unlock: bool) -> void:
	var result := store.complete_first(99) if unlock else store.reset_completion_to_first()
	if result != OK:
		_show_toast("Progress could not be saved: " + error_string(result))
		return
	menu_page = 0
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
	content.add_child(label("Neutral tiles never flip. Custom layouts are saved exactly as drawn; solvability is up to you.", 13, MUTED))

func _toggle_editor_playtest() -> void:
	if screen != "editor" or not is_instance_valid(board):
		return
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
		editor_message.text = "Solved! Press Space to return to building."

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
	var layout := {"width": int(generated.width), "height": int(generated.height), "tiles": generated.tiles.duplicate()}
	if editor_data != layout:
		_record_edit()
		editor_data = layout
		_sync_editor()
	var unique_cells: Dictionary = {}
	for cell in generated.solution:
		unique_cells[cell] = true
	var used: int = generated.solution.size() - unique_cells.size()
	editor_message.text = "Generated %d moves with exactly %d crossovers. Save to keep it." % [moves, used]

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
	return {"_structure": true, "levels": store.levels.duplicate(true), "completed": store.completed.duplicate(true), "editor_level": editor_level, "editor_data": editor_data.duplicate(true), "current_level": current_level, "saved_path": saved_path.duplicate()}

func _restore_structure(snapshot: Dictionary) -> void:
	store.levels = snapshot.levels.duplicate(true)
	store.completed = snapshot.completed.duplicate(true)
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
	toast.position = Vector2(44, 8)
	toast.z_index = 100
	add_child(toast)
	toast_timer = 5.0

func _process(delta: float) -> void:
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0 and is_instance_valid(toast):
			toast.queue_free()
