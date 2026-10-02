class_name LevelStore
extends RefCounted

const LEVELS_PATH := "user://levels.json"
const SOURCE_PATH := "res://data/levels.json"
const PROGRESS_PATH := "user://progress.json"
const PREVIOUS_USER_FOLDER := "Godot/app_userdata/Unium"

var levels: Dictionary = {}
var colors: Dictionary = {}
var completed: Dictionary = {}
var cache: Dictionary = {}
var persistence_error := ""
var mirror_project := true

func _init() -> void:
	_load_levels(SOURCE_PATH)
	_load_levels(_previous_path("levels.json"))
	_load_levels(LEVELS_PATH)
	var progress := _read_json(PROGRESS_PATH)
	if progress.is_empty():
		progress = _read_json(_previous_path("progress.json"))
	if progress.get("completed") is Dictionary:
		for key in progress.completed:
			if str(key).is_valid_int() and int(key) > 0 and progress.completed[key] == true:
				completed[str(key)] = true

static func _previous_path(filename: String) -> String:
	return OS.get_data_dir().path_join(PREVIOUS_USER_FOLDER).path_join(filename)

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
		for key in data.colors:
			if str(key).is_valid_int() and int(key) > 0 and data.colors[key] is String and Color.html_is_valid(data.colors[key]):
				colors[str(key)] = data.colors[key]

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
	return Color(colors[str(number)]) if colors.has(str(number)) else Puzzle.palette(number)

func frontier() -> int:
	var number := 1
	while completed.get(str(number), false):
		number += 1
	return number

func mark_complete(number: int) -> Error:
	completed[str(number)] = true
	return _atomic_write(PROGRESS_PATH, {"completed": completed})

func save_level(number: int, value: Dictionary) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	levels[str(number)] = {"width": int(value.width), "height": int(value.height), "tiles": value.tiles.duplicate()}
	return save_levels()

func save_color(number: int, color: Color) -> Error:
	colors[str(number)] = color.to_html(false)
	return save_levels()

func save_levels() -> Error:
	var data := {"version": 1, "levels": levels, "colors": colors}
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
