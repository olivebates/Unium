class_name PuzzleBoard
extends Control

const HUE_STEP := 1.0 / 12.0
const SPLIT_UI_OFFSET := 5.0 * HUE_STEP
const WARM_ANCHOR_HUE := 35.0 / 360.0
const LINE_HUE_SHIFT := 2.0 * HUE_STEP
const MOVE_DURATION := 0.2

signal path_changed
signal solved
signal paint_started
signal cell_painted(cell: int)
signal light_painted(cell: int)
signal paint_finished

var width := 3
var height := 3
var tiles: Array = []
var path: Array = []
var tint := Color("a9dfcc")
var stroke_color := Color.TRANSPARENT
var editing := false
var locked := false
var dragging := false
var right_dragging := false
var hovered := -1
var previous_pointer := Vector2.ZERO
var line_group: CanvasGroup
var line_shadow: Line2D
var line: Line2D
var start_dot_shadow: Polygon2D
var start_dot: Polygon2D
var thumbnail_mode := false
var line_tween: Tween
var tile_tweens: Dictionary = {}
var tile_visuals: Array[Color] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line_group = CanvasGroup.new()
	line_group.modulate = Color.WHITE
	add_child(line_group)
	line_shadow = Line2D.new()
	line_shadow.default_color = Color(0, 0, 0, 0.22)
	line_shadow.position = Vector2(0, 3)
	line_shadow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line_shadow.end_cap_mode = Line2D.LINE_CAP_ROUND
	line_shadow.joint_mode = Line2D.LINE_JOINT_ROUND
	line_shadow.antialiased = true
	line_group.add_child(line_shadow)
	start_dot_shadow = Polygon2D.new()
	start_dot_shadow.color = Color(0, 0, 0, 0.22)
	start_dot_shadow.position = Vector2(0, 3)
	line_group.add_child(start_dot_shadow)
	line = Line2D.new()
	line.default_color = line_color(tint)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	line_group.add_child(line)
	start_dot = Polygon2D.new()
	start_dot.color = line_color(tint)
	line_group.add_child(start_dot)
	resized.connect(refresh)
	mouse_exited.connect(func(): hovered = -1; queue_redraw())
	set_process_input(true)

func configure(level: Dictionary, color: Color, line_override: Color = Color.TRANSPARENT) -> void:
	width = int(level.width)
	height = int(level.height)
	tiles = level.tiles.duplicate()
	tint = color
	stroke_color = line_override
	path.clear()
	dragging = false
	right_dragging = false
	locked = false
	tile_visuals.clear()
	refresh()

func geometry() -> Dictionary:
	var cell_size := minf((size.x - 32.0) / width, (size.y - 32.0) / height)
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

func refresh(animate: bool = false) -> void:
	var values := Puzzle.resolved_tiles(tiles, path)
	var palette := [tile_color(0, tint), tile_color(1, tint), tile_color(2, tint)]
	if not animate or tile_visuals.size() != values.size():
		for tween in tile_tweens.values():
			if tween and tween.is_running():
				tween.kill()
		tile_tweens.clear()
		tile_visuals.resize(values.size())
		for cell in range(values.size()):
			tile_visuals[cell] = palette[values[cell]]
	else:
		for cell in range(values.size()):
			var target: Color = palette[values[cell]]
			if tile_visuals[cell].is_equal_approx(target):
				continue
			if tile_tweens.has(cell) and tile_tweens[cell].is_running():
				tile_tweens[cell].kill()
			var tween := create_tween()
			tween.tween_method(Callable(self, "_set_tile_visual").bind(cell), tile_visuals[cell], target, MOVE_DURATION).set_trans(Tween.TRANS_SINE)
			tile_tweens[cell] = tween
	queue_redraw()
	if line == null:
		return
	var points := PackedVector2Array()
	for cell in path:
		points.append(center(cell))
	line.default_color = stroke_color if stroke_color.a > 0.0 else line_color(tint)
	start_dot.color = line.default_color
	line.width = geometry().cell * 0.15
	line_shadow.width = line.width + 3.0
	if line_tween and line_tween.is_running():
		line_tween.kill()
	if animate and not thumbnail_mode and not line.points.is_empty():
		_animate_line_along_path(line.points, points)
	else:
		_set_visual_line(points)

func _animate_line_along_path(initial: PackedVector2Array, target: PackedVector2Array) -> void:
	if target.is_empty():
		var route_length := _polyline_length(initial)
		if route_length <= 0.001:
			_set_visual_line(target)
			return
		line_tween = create_tween()
		line_tween.tween_method(func(progress: float):
			_set_visual_line(_clip_polyline(initial, route_length * (1.0 - progress)))
		, 0.0, 1.0, MOVE_DURATION).set_trans(Tween.TRANS_SINE)
		line_tween.tween_callback(func(): _set_visual_line(target))
		return
	var common := 0
	while common < mini(initial.size(), target.size()) and initial[common].is_equal_approx(target[common]):
		common += 1
	if common == 0:
		_set_visual_line(target)
		return
	var old_length := _polyline_length(initial)
	var old_common := _polyline_length(initial, common)
	var new_common := _polyline_length(target, common)
	var retreat := old_length - old_common
	# If a previous extension is still moving along the next segment, keep going
	# from its visible tip instead of briefly rewinding to the last tile center.
	if initial.size() == common + 1 and common < target.size():
		var from_point: Vector2 = target[common - 1]
		var to_point: Vector2 = target[common]
		var tip: Vector2 = initial[-1]
		var segment := to_point - from_point
		if segment.length_squared() > 0.0 and absf(segment.cross(tip - from_point)) < 0.01 and (tip - from_point).dot(segment) >= 0.0 and (tip - from_point).dot(segment) <= segment.length_squared():
			retreat = 0.0
			new_common += from_point.distance_to(tip)
	var advance := maxf(0.0, _polyline_length(target) - new_common)
	var travel := retreat + advance
	if travel <= 0.001:
		_set_visual_line(target)
		return
	line_tween = create_tween()
	line_tween.tween_method(func(progress: float):
		var distance := travel * progress
		if distance <= retreat:
			_set_visual_line(_clip_polyline(initial, old_length - distance))
		else:
			_set_visual_line(_clip_polyline(target, new_common + distance - retreat))
	, 0.0, 1.0, MOVE_DURATION).set_trans(Tween.TRANS_SINE)
	line_tween.tween_callback(func(): _set_visual_line(target))

func _polyline_length(points: PackedVector2Array, count: int = -1) -> float:
	var limit := points.size() if count < 0 else mini(count, points.size())
	var result := 0.0
	for index in range(1, limit):
		result += points[index - 1].distance_to(points[index])
	return result

func _clip_polyline(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var clipped := PackedVector2Array([points[0]])
	var remaining := distance
	for index in range(1, points.size()):
		var segment: float = points[index - 1].distance_to(points[index])
		if remaining < segment:
			clipped.append(points[index - 1].lerp(points[index], remaining / segment))
			return clipped
		clipped.append(points[index])
		remaining -= segment
	return clipped

func _set_tile_visual(color: Color, cell: int) -> void:
	tile_visuals[cell] = color
	queue_redraw()

func _set_visual_line(points: PackedVector2Array) -> void:
	line.points = points
	line_shadow.points = points
	start_dot.visible = not points.is_empty()
	start_dot_shadow.visible = start_dot.visible
	if not points.is_empty():
		var polygon := PackedVector2Array()
		for i in range(32):
			polygon.append(points[0] + Vector2.from_angle(i * TAU / 32.0) * line.width * 0.68)
		start_dot.polygon = polygon
		start_dot_shadow.polygon = polygon

func _draw() -> void:
	if tiles.is_empty():
		return
	if thumbnail_mode:
		draw_rect(Rect2(Vector2.ZERO, size), background_color(tint))
	var g := geometry()
	var values := Puzzle.resolved_tiles(tiles, path)
	var gap: float = clampf(g.cell * 0.085, 3, 8)
	for cell in range(tiles.size()):
		var point: Vector2 = g.origin + Vector2(Puzzle.cell_vector(cell, width)) * g.cell
		var rect := Rect2(point + Vector2.ONE * gap * 0.5, Vector2.ONE * (g.cell - gap))
		var color: Color = tile_visuals[cell] if tile_visuals.size() == values.size() else tile_color(values[cell], tint)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(maxi(3, int(g.cell * 0.12)))
		style.shadow_color = Color(0, 0, 0, 0.2)
		style.shadow_size = 3
		style.shadow_offset = Vector2(0, 3)
		if values[cell] == 1:
			style.set_border_width_all(1)
			style.border_color = color.darkened(0.25)
		if hovered == cell and not locked:
			style.set_border_width_all(2)
			style.border_color = Color.BLACK
		draw_style_box(style, rect)

static func line_color(color: Color) -> Color:
	var toward_warm := fposmod(WARM_ANCHOR_HUE - color.h + 0.5, 1.0) - 0.5
	var direction := 1.0 if toward_warm >= 0.0 else -1.0
	return balanced_color(fposmod(color.h + direction * LINE_HUE_SHIFT, 1.0), 0.72, 0.62)

static func button_color(color: Color) -> Color:
	return balanced_color(fposmod(color.h + SPLIT_UI_OFFSET, 1.0), 0.35, 0.055)

static func text_color(color: Color) -> Color:
	return balanced_color(fposmod(color.h + SPLIT_UI_OFFSET, 1.0), 0.14, 0.84)

static func tile_color(value: int, color: Color) -> Color:
	if value == 2:
		return Color.from_hsv(0.57, 0.07, 0.45)
	return balanced_color(color.h, 0.70 if value == 1 else 0.60, 0.10 if value == 1 else 0.45)

static func background_color(color: Color) -> Color:
	return balanced_color(fposmod(color.h + SPLIT_UI_OFFSET, 1.0), 0.25, 0.022)

static func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722

static func balanced_color(hue: float, saturation: float, brightness: float) -> Color:
	# Match perceived brightness across hues. Light blue needs less saturation
	# than yellow to reach the same luminance without clipping the RGB channels.
	if luminance(Color.from_hsv(hue, saturation, 1.0)) < brightness:
		var low_saturation := 0.0
		var high_saturation := saturation
		for iteration in range(16):
			var middle := (low_saturation + high_saturation) * 0.5
			if luminance(Color.from_hsv(hue, middle, 1.0)) >= brightness:
				low_saturation = middle
			else:
				high_saturation = middle
		saturation = low_saturation
	var low_value := 0.0
	var high_value := 1.0
	for iteration in range(16):
		var middle := (low_value + high_value) * 0.5
		if luminance(Color.from_hsv(hue, saturation, middle)) < brightness:
			low_value = middle
		else:
			high_value = middle
	return Color.from_hsv(hue, saturation, (low_value + high_value) * 0.5)

func _gui_input(event: InputEvent) -> void:
	if locked:
		return
	if editing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_begin_light(event.position)
			accept_event()
		else:
			_end_light()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position)
			accept_event()
		else:
			_end()
	if event is InputEventMouseMotion:
		hovered = cell_at(event.position)
		queue_redraw()
		if dragging or right_dragging:
			_trace(event.position)
		previous_pointer = event.position

func _input(event: InputEvent) -> void:
	# Global release prevents a stuck drag after leaving the board/window.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_end_light()
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
		_end_light()

func _begin(point: Vector2) -> void:
	if right_dragging:
		_end_light()
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
	else:
		var visit := path.rfind(cell)
		if visit >= 0:
			dragging = true
			if visit < path.size() - 1:
				path.resize(visit + 1)
				_changed()

func _begin_light(point: Vector2) -> void:
	var cell := cell_at(point)
	if cell < 0:
		return
	if dragging:
		_end()
	previous_pointer = point
	right_dragging = true
	paint_started.emit()
	light_painted.emit(cell)

func _trace(point: Vector2) -> void:
	if locked or not (dragging or right_dragging):
		return
	var steps := maxi(1, ceili(previous_pointer.distance_to(point) / (geometry().cell * 0.18)))
	if editing:
		for i in range(1, steps + 1):
			var painted_cell := cell_at(previous_pointer.lerp(point, float(i) / steps))
			if painted_cell < 0:
				continue
			if right_dragging:
				light_painted.emit(painted_cell)
			else:
				cell_painted.emit(painted_cell)
	elif not path.is_empty():
		var target := cell_at(point)
		if target < 0:
			# A drag leaving the board still heads toward the last tile it crossed.
			for i in range(1, steps + 1):
				var sampled_cell := cell_at(previous_pointer.lerp(point, float(i) / steps))
				if sampled_cell >= 0:
					target = sampled_cell
		if target >= 0:
			_trace_toward(target)
	previous_pointer = point

func _trace_toward(target: int) -> void:
	var target_position := Puzzle.cell_vector(target, width)
	var last_axis := -1
	if path.size() >= 2:
		var end_position := Puzzle.cell_vector(path.back(), width)
		var previous_position := Puzzle.cell_vector(path[-2], width)
		last_axis = 0 if end_position.x != previous_position.x else 1
	var changed := false
	# Every accepted move reduces the distance to the cursor by one tile.
	for move in range(width + height):
		var end_position := Puzzle.cell_vector(path.back(), width)
		var difference := target_position - end_position
		if difference == Vector2i.ZERO:
			break
		var preferred_axis := 1 - last_axis if last_axis >= 0 else (0 if absi(difference.x) >= absi(difference.y) else 1)
		var moved := false
		for axis in [preferred_axis, 1 - preferred_axis]:
			var direction := Vector2i.ZERO
			if axis == 0 and difference.x != 0:
				direction.x = 1 if difference.x > 0 else -1
			elif axis == 1 and difference.y != 0:
				direction.y = 1 if difference.y > 0 else -1
			if direction == Vector2i.ZERO:
				continue
			var next_position: Vector2i = end_position + direction
			var next_cell := next_position.y * width + next_position.x
			if path.size() >= 2 and next_cell == path[-2]:
				path.pop_back()
			elif Puzzle.can_append(path, next_cell, width, height):
				path.append(next_cell)
			else:
				continue
			last_axis = axis
			changed = true
			moved = true
			break
		if not moved or (path.size() >= 2 and Puzzle.is_complete(tiles, path)):
			break
	if changed:
		_changed()

func _end() -> void:
	if dragging and editing:
		paint_finished.emit()
	elif dragging and path.size() == 1 and not locked:
		clear_path()
	dragging = false

func _end_light() -> void:
	if right_dragging:
		paint_finished.emit()
	right_dragging = false

func _changed() -> void:
	refresh(true)
	path_changed.emit()
	if path.size() >= 2 and Puzzle.is_complete(tiles, path):
		locked = true
		dragging = false
		solved.emit()

func clear_path() -> void:
	path.clear()
	dragging = false
	locked = false
	refresh(true)
	path_changed.emit()
