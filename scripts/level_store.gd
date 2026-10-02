class_name LevelStore
extends RefCounted

const LEVELS_PATH := "user://levels.json"
const SOURCE_PATH := "res://data/levels.json"
const PROGRESS_PATH := "user://progress.json"
const PREVIOUS_USER_FOLDERS := ["Godot/app_userdata/Unium", "Godot/app_userdata/Afterglow", "Godot/app_userdata/Glimmer", "Godot/app_userdata/Strike-through"]

var levels: Dictionary = {}
var colors: Dictionary = {}
var line_colors: Dictionary = {}
var completed: Dictionary = {}
var cache: Dictionary = {}
var persistence_error := ""
var mirror_project := true

func _init() -> void:
	_load_levels(SOURCE_PATH)
	for folder in PREVIOUS_USER_FOLDERS:
		_load_levels(_previous_path(folder, "levels.json"))
	_load_levels(LEVELS_PATH)
	var progress := _read_json(PROGRESS_PATH)
	if progress.is_empty():
		for index in range(PREVIOUS_USER_FOLDERS.size() - 1, -1, -1):
			progress = _read_json(_previous_path(PREVIOUS_USER_FOLDERS[index], "progress.json"))
			if not progress.is_empty():
				break
	if progress.get("completed") is Dictionary:
		for key in progress.completed:
			if str(key).is_valid_int() and int(key) > 0 and progress.completed[key] == true:
				completed[str(key)] = true

static func _previous_path(folder: String, filename: String) -> String:
	return OS.get_data_dir().path_join(folder).path_join(filename)

static func group_start(number: int) -> int:
	return int((number - 1) / 5) * 5 + 1

func _load_levels(path: String) -> void:
	var data := _read_json(path)
	if data.get("levels") is Dictionary:
		for key in data.levels:
			if str(key).is_valid_int() and int(key) > 0 and valid_level(data.levels[key]):
				var value: Dictionary = data.levels[key]
				var normalized: Array = []
				for tile in value.tiles:
					normalized.append(int(tile))
				levels[str(key)] = {"width": int(value.width), "height": int(value.height), "tiles": normalized}
	if data.get("colors") is Dictionary:
		var identifiers: Array[int] = []
		for key in data.colors:
			if str(key).is_valid_int() and int(key) > 0 and data.colors[key] is String and Color.html_is_valid(data.colors[key]):
				identifiers.append(int(key))
		identifiers.sort()
		var imported_groups: Dictionary = {}
		for number in identifiers:
			var group := str(group_start(number))
			if not imported_groups.has(group):
				imported_groups[group] = data.colors[str(number)]
		for group in imported_groups:
			colors[group] = imported_groups[group]
	if data.get("line_colors") is Dictionary:
		for key in data.line_colors:
			if str(key).is_valid_int() and int(key) > 0 and data.line_colors[key] is String and Color.html_is_valid(data.line_colors[key]):
				var line_color := Color(data.line_colors[key])
				line_colors[str(group_start(int(key)))] = Color(line_color.r, line_color.g, line_color.b).to_html(false)

static func valid_level(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not (value.get("width") is float or value.get("width") is int) or not (value.get("height") is float or value.get("height") is int):
		return false
	var width := int(value.width)
	var height := int(value.height)
	if width != value.width or height != value.height:
		return false
	if width < 3 or height < 3 or width > 128 or height > 128:
		return false
	if not value.get("tiles") is Array or value.tiles.size() != width * height:
		return false
	for tile in value.tiles:
		if not (tile is int or tile is float):
			return false
		if int(tile) != tile or int(tile) < 0 or int(tile) > 2:
			return false
	return true

func get_level(number: int) -> Dictionary:
	var key := str(number)
	if levels.has(key):
		return levels[key].duplicate(true)
	if not cache.has(number):
		cache[number] = Puzzle.generate(number)
	return cache[number].duplicate(true)

func get_color(number: int) -> Color:
	var group := str(group_start(number))
	return Color(colors[group]) if colors.has(group) else Puzzle.palette(number)

func get_line_color(number: int, tile_color: Color = Color.TRANSPARENT) -> Color:
	var group := str(group_start(number))
	if line_colors.has(group):
		return Color(line_colors[group])
	return PuzzleBoard.line_color(tile_color if tile_color.a > 0.0 else get_color(number))

func frontier() -> int:
	var number := 1
	while completed.get(str(number), false):
		number += 1
	return number

func mark_complete(number: int) -> Error:
	completed[str(number)] = true
	return save_progress()

func complete_first(number: int) -> Error:
	for level in range(1, number + 1):
		completed[str(level)] = true
	return save_progress()

func reset_completion_to_first() -> Error:
	completed = {"1": true}
	return save_progress()

func save_progress() -> Error:
	return _atomic_write(PROGRESS_PATH, {"completed": completed})

func save_level(number: int, value: Dictionary) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	levels[str(number)] = {"width": int(value.width), "height": int(value.height), "tiles": value.tiles.duplicate()}
	return save_levels()

func insert_level(number: int, value: Dictionary) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	var previous_levels := levels
	var previous_completed := completed
	var shifted_levels := {}
	for key in levels:
		var index := int(key)
		shifted_levels[str(index + 1 if index >= number else index)] = levels[key]
	shifted_levels[str(number)] = {"width": int(value.width), "height": int(value.height), "tiles": value.tiles.duplicate()}
	var shifted_completed := {}
	for key in completed:
		var index := int(key)
		shifted_completed[str(index + 1 if index >= number else index)] = completed[key]
	levels = shifted_levels
	completed = shifted_completed
	return _save_shifted_levels(previous_levels, previous_completed)

func delete_level(number: int) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	if not levels.has(str(number)):
		return ERR_DOES_NOT_EXIST
	var previous_levels := levels
	var previous_completed := completed
	var shifted_levels := {}
	for key in levels:
		var index := int(key)
		if index != number:
			shifted_levels[str(index - 1 if index > number else index)] = levels[key]
	var shifted_completed := {}
	for key in completed:
		var index := int(key)
		if index != number:
			shifted_completed[str(index - 1 if index > number else index)] = completed[key]
	levels = shifted_levels
	completed = shifted_completed
	return _save_shifted_levels(previous_levels, previous_completed)

func _save_shifted_levels(previous_levels: Dictionary, previous_completed: Dictionary) -> Error:
	var result := save_levels()
	if result == OK:
		result = save_progress()
	if result != OK:
		levels = previous_levels
		completed = previous_completed
		save_levels()
		save_progress()
	return result

func save_color(number: int, color: Color) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	colors[str(group_start(number))] = Color.from_hsv(color.h, 1.0, 1.0).to_html(false)
	return save_levels()

func save_line_color(number: int, color: Color) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	line_colors[str(group_start(number))] = Color(color.r, color.g, color.b).to_html(false)
	return save_levels()

func save_area_colors(number: int, tile_color: Color, line_color: Color, custom_line: bool) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	var group := str(group_start(number))
	colors[group] = Color.from_hsv(tile_color.h, 1.0, 1.0).to_html(false)
	if custom_line:
		line_colors[group] = Color(line_color.r, line_color.g, line_color.b).to_html(false)
	else:
		line_colors.erase(group)
	return save_levels()

func save_levels() -> Error:
	var data := {"version": 1, "levels": levels, "colors": colors, "line_colors": line_colors}
	var result := _atomic_write(LEVELS_PATH, data)
	if result != OK:
		persistence_error = "Could not save levels: " + error_string(result)
		return result
	# During development, also persist overrides in the project's levels file.
	# Exported builds use the writable user data file.
	if mirror_project and not OS.has_feature("template"):
		var source_result := _atomic_write(SOURCE_PATH, data)
		if source_result != OK:
			persistence_error = "Saved to user data; project levels file is read-only."
			return OK
	persistence_error = ""
	return OK

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _atomic_write(path: String, value: Dictionary) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(value, "  ") + "\n")
	file.flush()
	file.close()
	return DirAccess.rename_absolute(temporary, path)
