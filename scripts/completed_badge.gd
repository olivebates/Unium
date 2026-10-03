extends Control

const GREEN := Color("55df89")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72, 72)

func _draw() -> void:
	var center := size * 0.5
	var unit := minf(size.x, size.y) / 72.0
	draw_arc(center, 29.0 * unit, 0.0, TAU, 64, GREEN, 8.0 * unit, true)
	var mark := PackedVector2Array([
		center + Vector2(-17, 0) * unit,
		center + Vector2(-5, 11) * unit,
		center + Vector2(14, -11) * unit,
	])
	draw_polyline(mark, GREEN, 9.0 * unit, true)
	draw_circle(mark[0], 4.5 * unit, GREEN)
	draw_circle(mark[2], 4.5 * unit, GREEN)
