class_name LevelStore
extends RefCounted

const LEVELS_PATH := "user://levels.json"
const SOURCE_PATH := "res://data/levels.json"
const PROGRESS_PATH := "user://progress.json"
const DEFAULT_LINE_COLOR := Color("eae345")
const GROUP_SIZE := 5
const GROUP_COMPLETIONS_REQUIRED := 3
const PREVIOUS_USER_FOLDERS := ["Godot/app_userdata/Unium", "Godot/app_userdata/Afterglow", "Godot/app_userdata/Glimmer", "Godot/app_userdata/Strike-through"]

var levels: Dictionary = {}
var colors: Dictionary = {}
var line_colors: Dictionary = {}
var completed: Dictionary = {}
var hints: Dictionary = {}
var credits := 0
var unlocked_through := 0
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
	if progress.get("hints") is Dictionary:
		for key in progress.hints:
			var stage: Variant = progress.hints[key]
			if str(key).is_valid_int() and int(key) > 0 and (stage is int or stage is float) and int(stage) == stage and int(stage) in [1, 2]:
				hints[str(key)] = int(stage)
	if progress.get("unlocked_through") is int or progress.get("unlocked_through") is float:
		unlocked_through = maxi(0, int(progress.unlocked_through))
	credits = maxi(0, int(progress.credits)) if progress.get("credits") is int or progress.get("credits") is float else completed.size()

static func _previous_path(folder: String, filename: String) -> String:
	return OS.get_data_dir().path_join(folder).path_join(filename)

static func group_start(number: int) -> int:
	return int((number - 1) / GROUP_SIZE) * GROUP_SIZE + 1

func _load_levels(path: String) -> void:
	var data := _read_json(path)
	if data.get("levels") is Dictionary:
		for key in data.levels:
			if str(key).is_valid_int() and int(key) > 0 and valid_level(data.levels[key]):
				var value: Dictionary = data.levels[key]
				levels[str(key)] = _stored_layout(value)
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

static func _valid_solution_endpoints(value: Dictionary) -> bool:
	var first: Variant = value.get("solution_start")
	var last: Variant = value.get("solution_end")
	if not (first is int or first is float) or not (last is int or last is float):
		return false
	return int(first) == first and int(last) == last and int(first) >= 0 and int(last) >= 0 and int(first) < value.tiles.size() and int(last) < value.tiles.size()

static func _valid_solution_path(value: Dictionary, source: Variant) -> Array[int]:
	var path: Array[int] = []
	if not source is Array or source.size() < 2 or source.size() > value.tiles.size() * 2:
		return path
	var visited: Array = []
	for raw in source:
		if not (raw is int or raw is float) or int(raw) != raw or not Puzzle.can_append(visited, int(raw), int(value.width), int(value.height)):
			return []
		visited.append(int(raw))
		path.append(int(raw))
	return path if Puzzle.is_complete(value.tiles, visited) else []

static func _stored_layout(value: Dictionary) -> Dictionary:
	var normalized: Array = []
	for tile in value.tiles:
		normalized.append(int(tile))
	var layout := {"width": int(value.width), "height": int(value.height), "tiles": normalized}
	var solution := _valid_solution_path(layout, value.get("solution"))
	if not solution.is_empty():
		layout["solution"] = solution
		layout["solution_start"] = solution.front()
		layout["solution_end"] = solution.back()
	elif _valid_solution_endpoints(value):
		layout["solution_start"] = int(value.solution_start)
		layout["solution_end"] = int(value.solution_end)
	return layout

func get_level(number: int) -> Dictionary:
	var key := str(number)
	if levels.has(key):
		return levels[key].duplicate(true)
	if not cache.has(number):
		cache[number] = Puzzle.generate(number)
	return cache[number].duplicate(true)

func has_solution(number: int) -> bool:
	var key := str(number)
	return not levels.has(key) or _valid_solution_endpoints(levels[key])

func hint_endpoints(number: int) -> Array[int]:
	var level := get_level(number)
	if _valid_solution_endpoints(level):
		return [int(level.solution_start), int(level.solution_end)]
	if level.get("solution") is Array and not level.solution.is_empty():
		return [int(level.solution.front()), int(level.solution.back())]
	return []

func get_color(number: int) -> Color:
	var group := str(group_start(number))
	return Color(colors[group]) if colors.has(group) else Puzzle.palette(number)

func get_line_color(number: int, _tile_color: Color = Color.TRANSPARENT) -> Color:
	var group := str(group_start(number))
	if line_colors.has(group):
		return Color(line_colors[group])
	return DEFAULT_LINE_COLOR

func frontier() -> int:
	var number := 1
	while completed.get(str(number), false):
		number += 1
	return number

func menu_unlocked() -> int:
	var last := group_start(maxi(1, unlocked_through)) + GROUP_SIZE - 1
	while _completed_in_group(last - GROUP_SIZE + 1) >= GROUP_COMPLETIONS_REQUIRED:
		last += GROUP_SIZE
	return last

func _completed_in_group(first: int) -> int:
	var count := 0
	for number in range(first, first + GROUP_SIZE):
		if completed.get(str(number), false):
			count += 1
	return count

func menu_levels() -> Array[int]:
	var numbers: Array[int] = []
	for number in range(1, menu_unlocked() + 1):
		numbers.append(number)
	return numbers

func adjacent_uncompleted(current: int, direction: int) -> int:
	var last := menu_unlocked()
	for offset in range(1, last + 1):
		var number := posmod(current - 1 + direction * offset, last) + 1
		if not completed.get(str(number), false):
			return number
	return current

func adjacent_level(current: int, direction: int) -> int:
	var last := menu_unlocked()
	return posmod(current - 1 + direction, last) + 1

func mark_complete(number: int) -> Error:
	if not completed.get(str(number), false):
		completed[str(number)] = true
		credits += 1
	return save_progress()

func spend_credit() -> Error:
	if credits <= 0:
		return ERR_UNAVAILABLE
	credits -= 1
	var result := save_progress()
	if result != OK:
		credits += 1
	return result

func hint_stage(number: int) -> int:
	return int(hints.get(str(number), 0))

func hint_cost(number: int) -> int:
	return 2 if hint_stage(number) == 0 else 1

func purchase_hint(number: int) -> Error:
	var cost := hint_cost(number)
	if number < 1 or credits < cost or hint_stage(number) >= 2:
		return ERR_UNAVAILABLE
	var key := str(number)
	var previous := hint_stage(number)
	credits -= cost
	hints[key] = previous + 1
	var result := save_progress()
	if result != OK:
		credits += cost
		if previous == 0:
			hints.erase(key)
		else:
			hints[key] = previous
	return result

func complete_first(number: int) -> Error:
	for level in range(1, number + 1):
		if not completed.get(str(level), false):
			completed[str(level)] = true
			credits += 1
	return save_progress()

func set_completion_through(number: int) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	completed.clear()
	for level in range(1, number + 1):
		completed[str(level)] = true
	unlocked_through = 0
	credits = number
	return save_progress()

func reset_completion_to_first() -> Error:
	completed = {"1": true}
	hints.clear()
	unlocked_through = 0
	credits = 1
	return save_progress()

func reset_all_progress() -> Error:
	var previous_completed := completed.duplicate(true)
	var previous_hints := hints.duplicate(true)
	var previous_credits := credits
	var previous_unlocked := unlocked_through
	completed.clear()
	hints.clear()
	credits = 0
	unlocked_through = 0
	# An explicit empty record prevents a deleted save from importing old
	# progress from the legacy game folders on the next launch.
	var result := _atomic_write(PROGRESS_PATH, {"completed": {}, "unlocked_through": 0, "credits": 0, "hints": {}})
	if result != OK:
		completed = previous_completed
		hints = previous_hints
		credits = previous_credits
		unlocked_through = previous_unlocked
	return result

func save_progress() -> Error:
	unlocked_through = menu_unlocked()
	return _atomic_write(PROGRESS_PATH, {"completed": completed, "unlocked_through": unlocked_through, "credits": credits, "hints": hints})

func save_level(number: int, value: Dictionary) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	levels[str(number)] = _stored_layout(value)
	return save_levels()

func record_editor_solution(number: int, value: Dictionary, path: Array) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	var solution := _valid_solution_path(value, path)
	if solution.is_empty():
		return ERR_INVALID_DATA
	var layout := {"width": int(value.width), "height": int(value.height), "tiles": value.tiles.duplicate(), "solution": solution, "solution_start": solution.front(), "solution_end": solution.back()}
	var key := str(number)
	var previous: Variant = levels.get(key)
	levels[key] = layout
	var result := save_levels()
	if result != OK:
		if previous == null:
			levels.erase(key)
		else:
			levels[key] = previous
	return result

func insert_level(number: int, value: Dictionary) -> Error:
	if number < 1 or not valid_level(value):
		return ERR_INVALID_DATA
	var previous_levels := levels
	var previous_completed := completed
	var previous_hints := hints
	var shifted_levels := {}
	for key in levels:
		var index := int(key)
		shifted_levels[str(index + 1 if index >= number else index)] = levels[key]
	shifted_levels[str(number)] = _stored_layout(value)
	var shifted_completed := {}
	for key in completed:
		var index := int(key)
		shifted_completed[str(index + 1 if index >= number else index)] = completed[key]
	var shifted_hints := {}
	for key in hints:
		var index := int(key)
		shifted_hints[str(index + 1 if index >= number else index)] = hints[key]
	levels = shifted_levels
	completed = shifted_completed
	hints = shifted_hints
	return _save_shifted_levels(previous_levels, previous_completed, previous_hints)

func delete_level(number: int) -> Error:
	if number < 1:
		return ERR_INVALID_PARAMETER
	if not levels.has(str(number)):
		return ERR_DOES_NOT_EXIST
	var previous_levels := levels
	var previous_completed := completed
	var previous_hints := hints
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
	var shifted_hints := {}
	for key in hints:
		var index := int(key)
		if index != number:
			shifted_hints[str(index - 1 if index > number else index)] = hints[key]
	levels = shifted_levels
	completed = shifted_completed
	hints = shifted_hints
	return _save_shifted_levels(previous_levels, previous_completed, previous_hints)

func rearrange_level(source: int, target: int, action: String, after: bool = false) -> Error:
	var visible := menu_levels()
	if source not in visible or target not in visible or source == target:
		return ERR_INVALID_PARAMETER
	var unlocked := maxi(menu_unlocked(), maxi(source, target))
	if action != "insert" and action != "swap":
		return ERR_INVALID_PARAMETER
	var previous_levels := levels
	var previous_completed := completed
	var previous_hints := hints
	var previous_unlocked := unlocked_through
	var first := mini(source, target)
	var last := maxi(source, target)
	var layouts: Array[Dictionary] = []
	var progress: Array[bool] = []
	var reveals: Array[int] = []
	for number in range(first, last + 1):
		layouts.append(get_level(number))
		progress.append(completed.get(str(number), false))
		reveals.append(hint_stage(number))
	if action == "swap":
		var left := source - first
		var right := target - first
		var held_layout := layouts[left]
		layouts[left] = layouts[right]
		layouts[right] = held_layout
		var held_progress := progress[left]
		progress[left] = progress[right]
		progress[right] = held_progress
		var held_reveals := reveals[left]
		reveals[left] = reveals[right]
		reveals[right] = held_reveals
	else:
		var removed_layout: Dictionary = layouts.pop_at(source - first)
		var removed_progress: bool = progress.pop_at(source - first)
		var removed_reveals: int = reveals.pop_at(source - first)
		var insertion := target - first + (1 if after else 0)
		if source < target or (source == target and after):
			insertion -= 1
		layouts.insert(insertion, removed_layout)
		progress.insert(insertion, removed_progress)
		reveals.insert(insertion, removed_reveals)
	levels = levels.duplicate(true)
	completed = completed.duplicate(true)
	hints = hints.duplicate(true)
	for offset in range(layouts.size()):
		var number := first + offset
		var layout := layouts[offset]
		levels[str(number)] = _stored_layout(layout)
		if progress[offset]:
			completed[str(number)] = true
		else:
			completed.erase(str(number))
		if reveals[offset] > 0:
			hints[str(number)] = reveals[offset]
		else:
			hints.erase(str(number))
	unlocked_through = unlocked
	return _save_shifted_levels(previous_levels, previous_completed, previous_hints, previous_unlocked)

static func _endpoints_from_layout(layout: Dictionary) -> Array[int]:
	if _valid_solution_endpoints(layout):
		return [int(layout.solution_start), int(layout.solution_end)]
	if layout.get("solution") is Array and not layout.solution.is_empty():
		return [int(layout.solution.front()), int(layout.solution.back())]
	return []

func _save_shifted_levels(previous_levels: Dictionary, previous_completed: Dictionary, previous_hints: Dictionary, previous_unlocked: int = -1) -> Error:
	var result := save_levels()
	if result == OK:
		result = save_progress()
	if result != OK:
		levels = previous_levels
		completed = previous_completed
		hints = previous_hints
		if previous_unlocked >= 0:
			unlocked_through = previous_unlocked
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
