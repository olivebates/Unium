extends Control

const GOLD := Color("f4c75b")
const EDGE := Color("a66b25")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.43
	draw_circle(center, radius, GOLD)
	draw_arc(center, radius - 1.5, 0.0, TAU, 48, EDGE, maxf(2.0, radius * 0.16), true)
	draw_arc(center, radius * 0.48, 0.0, TAU, 48, Color("ffe9a2"), maxf(1.0, radius * 0.12), true)
