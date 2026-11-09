class_name CommunityPreview
extends Control

var layout: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if not CommunityCodec.valid_layout(layout):
		return
	var tint := Color(str(layout.get("color", "a9dfcc")))
	var background := StyleBoxFlat.new()
	background.bg_color = PuzzleBoard.background_color(tint)
	background.set_corner_radius_all(8)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var width := int(layout.width)
	var height := int(layout.height)
	var cell := minf((size.x - 8) / width, (size.y - 8) / height)
	var origin := (size - Vector2(width, height) * cell) * 0.5
	var gap := clampf(cell * 0.09, 0.25, 3)
	var styles: Array[StyleBoxFlat] = []
	for value in range(3):
		var style := StyleBoxFlat.new()
		style.bg_color = PuzzleBoard.tile_color(value, tint)
		style.set_corner_radius_all(maxi(0, int(cell * 0.12)))
		styles.append(style)
	for index in range(layout.tiles.size()):
		var point := origin + Vector2(index % width, int(index / width)) * cell
		draw_style_box(styles[int(layout.tiles[index])], Rect2(point + Vector2.ONE * gap * 0.5, Vector2.ONE * (cell - gap)))
