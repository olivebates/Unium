extends RefCounted

# This job owns its data. No scene-tree or shared LevelStore access on the worker.
var number := 1
var signature := 0
var layout: Dictionary = {}
var tint := Color.WHITE
var result: Dictionary = {}

func run() -> void:
	var level := layout if not layout.is_empty() else Puzzle.generate(number)
	var width: int = level.width
	var height: int = level.height
	var cell := 96.0 / maxi(width, height)
	var origin := (Vector2(128, 128) - Vector2(width, height) * cell) * 0.5
	var gap := minf(cell * 0.22, clampf(cell * 0.085, 3.0, 8.0))
	var edge := cell - gap
	var radius := minf(edge * 0.3, maxf(1.0, cell * 0.12))
	var palette := [PuzzleBoard.tile_color(0, tint).to_html(false), PuzzleBoard.tile_color(1, tint).to_html(false), PuzzleBoard.tile_color(2, tint).to_html(false)]
	var parts := PackedStringArray()
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><rect width="128" height="128" rx="16" fill="#%s"/>' % PuzzleBoard.background_color(tint).to_html(false))
	for index in range(level.tiles.size()):
		var point := origin + Vector2(index % width, index / width) * cell + Vector2.ONE * gap * 0.5
		parts.append('<rect x="%.3f" y="%.3f" width="%.3f" height="%.3f" rx="%.3f" fill="#%s"/>' % [point.x, point.y, edge, edge, radius, palette[int(level.tiles[index])]])
	parts.append('</svg>')
	var image := Image.new()
	var error := image.load_svg_from_string("".join(parts))
	result = {"level": level, "image": image, "error": error}
