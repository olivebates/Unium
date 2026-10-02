class_name PuzzleBoard
extends Control

signal path_changed
signal solved
signal paint_started
signal cell_painted(cell: int)
signal paint_finished

var width := 3
var height := 3
var tiles: Array = []
var path: Array = []
var tint := Color("a9dfcc")
var editing := false
var locked := false
var dragging := false
var hovered := -1
var previous_pointer := Vector2.ZERO
var line_group: CanvasGroup
var line: Line2D
var end_dot: Polygon2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line_group = CanvasGroup.new()
	line_group.modulate = Color.WHITE
	add_child(line_group)
	line = Line2D.new()
	line.default_color = Color.BLACK
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	line_group.add_child(line)
	end_dot = Polygon2D.new()
	end_dot.color = Color.BLACK
	line_group.add_child(end_dot)
	resized.connect(refresh)
	mouse_exited.connect(func(): hovered = -1; queue_redraw())
	set_process_input(true)

func configure(level: Dictionary, color: Color) -> void:
	width = int(level.width)
	height = int(level.height)
	tiles = level.tiles.duplicate()
	tint = color
	path.clear()
	dragging = false
	locked = false
	refresh()

func geometry() -> Dictionary:
	var cell_size := minf((size.x - 32.0) / width, (size.y - 32.0) / height)
	cell_size = minf(cell_size, 92.0)
	var board_size := Vector2(width, height) * cell_size
	return {"cell": cell_size, "origin": (size - board_size) * 0.5}

func center(cell: int) -> Vector2:
	var g := geometry()
	return g.origin + (Vector2(Puzzle.cell_vector(cell, width)) + Vector2(0.5, 0.5)) * g.cell

func cell_at(point: Vector2) -> int:
	var g := geometry()
	var local: Vector2 = (point - g.origin) / g.cell
	if local.x < 0 or local.y < 0 or local.x >= width or local.y >= height:
		return -1
	return int(local.y) * width + int(local.x)

func refresh() -> void:
	queue_redraw()
	if line == null:
		return
	var points := PackedVector2Array()
	for cell in path:
		points.append(center(cell))
	line.points = points
	line.width = geometry().cell * 0.15
	end_dot.visible = not path.is_empty()
	if not path.is_empty():
		var polygon := PackedVector2Array()
		for i in range(32):
			polygon.append(center(path.back()) + Vector2.from_angle(i * TAU / 32.0) * line.width * 0.68)
		end_dot.polygon = polygon

func _draw() -> void:
	if tiles.is_empty():
		return
	var g := geometry()
	var values := Puzzle.resolved_tiles(tiles, path)
	var gap: float = clampf(g.cell * 0.085, 3, 8)
	for cell in range(tiles.size()):
		var point: Vector2 = g.origin + Vector2(Puzzle.cell_vector(cell, width)) * g.cell
		var rect := Rect2(point + Vector2.ONE * gap * 0.5, Vector2.ONE * (g.cell - gap))
		var color := tile_color(values[cell], tint)
		if hovered == cell and not locked:
			color = color.lightened(0.08)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(maxi(3, int(g.cell * 0.12)))
		style.shadow_color = Color(0, 0, 0, 0.2)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 3)
		if values[cell] == 1:
			style.set_border_width_all(1)
			style.border_color = tint.darkened(0.68)
		draw_style_box(style, rect)
		if values[cell] == 2:
			draw_circle(rect.get_center(), maxf(1.5, g.cell * 0.025), Color("929b9f"), true, -1, true)
	if not path.is_empty():
		var radius: float = g.cell * 0.16
		draw_arc(center(path.back()), radius, 0, TAU, 40, Color.BLACK, 1.6, true)

static func tile_color(value: int, color: Color) -> Color:
	if value == 2:
		return Color("58616a")
	return color.darkened(0.80).lightened(0.30) if value == 1 else color

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position)
			accept_event()
		else:
			_end()
	if event is InputEventMouseMotion:
		hovered = cell_at(event.position)
		queue_redraw()
		if dragging:
			_trace(event.position)
		previous_pointer = event.position

func _input(event: InputEvent) -> void:
	# Global release prevents a stuck drag after leaving the board/window.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end()
	if event is InputEventScreenTouch:
		if event.pressed and get_global_rect().has_point(event.position) and not locked:
			_begin(event.position - global_position)
		else:
			_end()
	if event is InputEventScreenDrag and dragging:
		_trace(event.position - global_position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_end()

func _begin(point: Vector2) -> void:
	var cell := cell_at(point)
	if cell < 0:
		return
	previous_pointer = point
	if editing:
		dragging = true
		paint_started.emit()
		cell_painted.emit(cell)
	elif path.is_empty():
		dragging = true
		path.append(cell)
		_changed()
	elif cell == path.back():
		dragging = true

func _trace(point: Vector2) -> void:
	var steps := maxi(1, ceili(previous_pointer.distance_to(point) / (geometry().cell * 0.18)))
	for i in range(1, steps + 1):
		if locked or not dragging:
			break
		var cell := cell_at(previous_pointer.lerp(point, float(i) / steps))
		if cell < 0:
			continue
		if editing:
			cell_painted.emit(cell)
		elif not path.is_empty() and cell != path.back():
			if path.size() >= 2 and cell == path[-2]:
				path.pop_back()
				_changed()
			elif Puzzle.can_append(path, cell, width, height):
				path.append(cell)
				_changed()
	previous_pointer = point

func _end() -> void:
	if dragging and editing:
		paint_finished.emit()
	dragging = false

func _changed() -> void:
	refresh()
	path_changed.emit()
	if Puzzle.is_complete(tiles, path):
		locked = true
		dragging = false
		solved.emit()

func clear_path() -> void:
	path.clear()
	dragging = false
	locked = false
	refresh()
	path_changed.emit()
