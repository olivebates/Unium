class_name VictoryPulse
extends Control

const DURATION := 1.0
var board: PuzzleBoard
var progress := 0.0

static func play(target: PuzzleBoard) -> void:
	var pulse := VictoryPulse.new()
	pulse.name = "VictoryPulse"
	pulse.board = target
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(pulse)
	var tween := pulse.create_tween()
	tween.tween_method(func(value: float):
		pulse.progress = value
		pulse.queue_redraw()
	, 0.0, 1.0, DURATION)
	await target.get_tree().create_timer(DURATION).timeout
	if is_instance_valid(pulse):
		pulse.queue_free()

func _draw() -> void:
	if not is_instance_valid(board) or board.path.is_empty():
		return
	var cell: float = board.geometry().cell
	var points := PackedVector2Array()
	for index in board.path:
		points.append(board.center(int(index)))
	if points.size() > 1:
		draw_polyline(points, Color(1, 1, 1, sin(progress * PI) * 0.42), maxf(2, cell * 0.24), true)
	var tip := mini(points.size() - 1, int(progress * points.size()))
	draw_circle(points[tip], cell * (0.12 + sin(progress * PI) * 0.08), Color(1, 1, 1, 1.0 - progress))
	draw_arc(points[-1], cell * (0.2 + progress * 1.8), 0, TAU, 64, Color(1, 1, 1, sin(progress * PI) * 0.65), 3, true)
