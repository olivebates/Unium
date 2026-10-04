class_name Puzzle
extends RefCounted

const DEFAULT_EDITOR_CROSSINGS := 3
const AUTOMATIC_MIN_MOVES := 50
const AUTOMATIC_MAX_MOVES := 80
const AUTOMATIC_MIN_CROSSINGS := 7
const AUTOMATIC_MAX_CROSSINGS := 10

static func cell_vector(cell: int, width: int) -> Vector2i:
	return Vector2i(cell % width, cell / width)

static func neighbors(cell: int, width: int, height: int) -> Array[int]:
	var result: Array[int] = []
	var p := cell_vector(cell, width)
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var q: Vector2i = p + d
		if q.x >= 0 and q.y >= 0 and q.x < width and q.y < height:
			result.append(q.y * width + q.x)
	return result

static func can_append(path: Array, cell: int, width: int, height: int) -> bool:
	if cell < 0 or cell >= width * height:
		return false
	if path.is_empty():
		return true
	var end: int = path.back()
	if cell not in neighbors(end, width, height):
		return false
	var direction := cell_vector(cell, width) - cell_vector(end, width)
	# A second visit is an overpass: keep travelling in the incoming direction.
	if path.count(end) == 2:
		var incoming := cell_vector(end, width) - cell_vector(path[-2], width)
		if direction != incoming:
			return false
	var visits := path.count(cell)
	if visits == 0:
		return true
	if visits >= 2:
		return false
	var index := path.find(cell)
	if index == 0:
		# The start has an outgoing edge but no incoming edge. Enter across it,
		# never from behind or along the edge the line first used.
		var first_out := cell_vector(path[1], width) - cell_vector(cell, width)
		return first_out.x * direction.x + first_out.y * direction.y == 0
	if index == path.size() - 1:
		return false
	var first_in := cell_vector(cell, width) - cell_vector(path[index - 1], width)
	var first_out := cell_vector(path[index + 1], width) - cell_vector(cell, width)
	return first_in == first_out and first_in.x * direction.x + first_in.y * direction.y == 0

static func resolved_tiles(tiles: Array, path: Array) -> Array:
	var result := tiles.duplicate()
	for cell in path:
		if result[cell] != 2:
			result[cell] = 1 - result[cell]
	return result

static func is_complete(tiles: Array, path: Array) -> bool:
	return not path.is_empty() and not resolved_tiles(tiles, path).has(1)

static func palette(level: int) -> Color:
	var group := int((level - 1) / 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = group + 7319
	# Golden-angle spacing plus small seeded variation keeps neighboring groups
	# over 119 degrees apart without repeating a short fixed palette.
	return Color.from_hsv(fposmod(0.43 + group * 0.38196601125 + rng.randf_range(-0.025, 0.025), 1.0), 1.0, 1.0)

static func generate(level: int, fixed_dimensions: Vector2i = Vector2i.ZERO, max_crossings: int = DEFAULT_EDITOR_CROSSINGS, random_seed: int = -1, requested_moves: int = 0, exact_crossings: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level if random_seed < 0 else random_seed
	if fixed_dimensions == Vector2i.ZERO and requested_moves == 0 and not exact_crossings:
		return _generate_automatic(rng)
	var moves := requested_moves if requested_moves > 0 else level + 26
	var width := fixed_dimensions.x
	var height := fixed_dimensions.y
	if width >= 3 and height >= 3:
		# An untouched editor move count is shortened to fit a smaller board.
		if requested_moves == 0:
			moves = mini(moves, width * height)
	else:
		var maximum_side := maxi(7, ceili(sqrt(float(moves))))
		var dimensions: Array[Vector2i] = []
		for w in range(3, maximum_side + 1):
			for h in range(3, maximum_side + 1):
				if w * h >= moves:
					dimensions.append(Vector2i(w, h))
		var dim := dimensions[rng.randi_range(0, dimensions.size() - 1)]
		width = dim.x
		height = dim.y
	if exact_crossings and max_crossings > width * height:
		return {}
	var crossing_limit := clampi(max_crossings, 0, width * height)
	if moves < 2 or moves > width * height + crossing_limit or (exact_crossings and moves - crossing_limit < 2):
		return {}
	var solution: Array = []
	var found_solution := false
	# Bounded randomized depth-first search; every step uses the player's rules.
	for attempt in range(8):
		solution = [rng.randi_range(0, width * height - 1)]
		var crossings := 0
		var choices: Array = [_ordered_neighbors(solution, width, height, rng)]
		var budget := 2200
		while not solution.is_empty() and budget > 0:
			budget -= 1
			if solution.size() == moves and solution.count(solution.back()) == 1 and (not exact_crossings or crossings == crossing_limit):
				break
			if choices.back().is_empty() or solution.size() == moves:
				var removed: int = solution.pop_back()
				if solution.has(removed):
					crossings -= 1
				choices.pop_back()
				continue
			var next: int = choices.back().pop_back()
			var is_crossing := solution.has(next)
			if is_crossing and crossings >= crossing_limit:
				continue
			if can_append(solution, next, width, height):
				solution.append(next)
				if is_crossing:
					crossings += 1
				choices.append(_ordered_neighbors(solution, width, height, rng))
		if solution.size() == moves and solution.count(solution.back()) == 1 and (not exact_crossings or crossings == crossing_limit):
			found_solution = true
			break
	if not found_solution:
		if moves > width * height or (exact_crossings and crossing_limit > 0):
			return {}
		# Guaranteed solvable fallback, mirrored and transposed by the seed.
		solution = []
		var flip_x := rng.randf() < 0.5
		var flip_y := rng.randf() < 0.5
		var vertical := rng.randf() < 0.5
		for major in range(width if vertical else height):
			for minor in range(height if vertical else width):
				var span := height if vertical else width
				var cross := minor if major % 2 == 0 else span - 1 - minor
				var x := major if vertical else cross
				var y := cross if vertical else major
				if flip_x:
					x = width - 1 - x
				if flip_y:
					y = height - 1 - y
				solution.append(y * width + x)
		solution.resize(moves)
	var tiles: Array = []
	tiles.resize(width * height)
	tiles.fill(0)
	tiles = resolved_tiles(tiles, solution)
	return {"width": width, "height": height, "tiles": tiles, "solution": solution, "moves": moves}

static func _generate_automatic(rng: RandomNumberGenerator) -> Dictionary:
	var source_width := rng.randi_range(12, 15)
	var source_height := rng.randi_range(12, 15)
	var route: Array = []
	var route_width := source_width
	# Pick a legal segment of a randomized weave. Work is bounded; the final
	# compact weave always offers a 50–80 tile segment with 7–10 crossovers.
	for attempt in range(4):
		route_width = rng.randi_range(9, source_width) if attempt < 3 else 9
		var route_height := rng.randi_range(8, source_height) if attempt < 3 else 8
		var weave := _automatic_weave(route_width, route_height, rng)
		route = _automatic_segment(weave, route_width * route_height, rng)
		if not route.is_empty():
			break
	# Place the route on the initial canvas before orienting and cropping it.
	var positions: Array[Vector2i] = []
	var transpose := rng.randf() < 0.5
	var flip_x := rng.randf() < 0.5
	var flip_y := rng.randf() < 0.5
	for cell in route:
		var p := cell_vector(cell, route_width)
		if flip_x:
			p.x = source_width - 1 - p.x
		if flip_y:
			p.y = source_height - 1 - p.y
		if transpose:
			p = Vector2i(p.y, p.x)
		positions.append(p)
	if transpose:
		var swap := source_width
		source_width = source_height
		source_height = swap
	var minimum := positions[0]
	var maximum := positions[0]
	for p in positions:
		minimum = minimum.min(p)
		maximum = maximum.max(p)
	# Keep the whole legal route, including light crossover tiles, then add
	# exactly one light row/column on each side of the tight crop.
	var width := maximum.x - minimum.x + 3
	var height := maximum.y - minimum.y + 3
	var solution: Array = []
	for p in positions:
		solution.append((p.y - minimum.y + 1) * width + p.x - minimum.x + 1)
	if rng.randf() < 0.5:
		solution.reverse()
	var tiles: Array = []
	tiles.resize(width * height)
	tiles.fill(0)
	tiles = resolved_tiles(tiles, solution)
	return {"width": width, "height": height, "tiles": tiles, "solution": solution, "moves": solution.size(), "source_width": source_width, "source_height": source_height}

static func _automatic_weave(width: int, height: int, rng: RandomNumberGenerator) -> Array:
	var row_count := rng.randi_range(3, 4) if height >= 10 else 3
	var column_count := rng.randi_range(3, 4) if width >= 11 else 3
	var rows := _shuffled(range(1, height - row_count - 1), rng).slice(0, row_count)
	var columns := _shuffled(range(2, width - column_count - 1), rng).slice(0, column_count)
	rows.sort()
	columns.sort()
	for i in range(row_count):
		rows[i] += i
	for i in range(column_count):
		columns[i] += i
	var route: Array = [int(rows[0]) * width + (width - 2 if row_count % 2 else 1)]
	for i in range(row_count):
		var end_x := 1 if (row_count - i) % 2 else width - 2
		_extend_route(route, width, Vector2i(end_x, rows[i]))
		if i < row_count - 1:
			_extend_route(route, width, Vector2i(end_x, rows[i + 1]))
	_extend_route(route, width, Vector2i(0, rows.back()))
	_extend_route(route, width, Vector2i(0, height - 1))
	_extend_route(route, width, Vector2i(columns[0], height - 1))
	for i in range(column_count):
		var end_y := 0 if i % 2 == 0 else height - 2
		_extend_route(route, width, Vector2i(columns[i], end_y))
		if i < column_count - 1:
			_extend_route(route, width, Vector2i(columns[i + 1], end_y))
	var tail_y := 0 if column_count % 2 else height - 2
	_extend_route(route, width, Vector2i(width - 1, tail_y))
	_extend_route(route, width, Vector2i(width - 1, height - 1 if column_count % 2 else 0))
	return route

static func _automatic_segment(route: Array, area: int, rng: RandomNumberGenerator) -> Array:
	var by_length: Dictionary = {}
	for start in range(route.size() - AUTOMATIC_MIN_MOVES + 1):
		var visits := PackedByteArray()
		visits.resize(area)
		var crossings := 0
		for end in range(start, mini(route.size(), start + AUTOMATIC_MAX_MOVES)):
			var cell: int = route[end]
			if visits[cell] == 1:
				crossings += 1
			visits[cell] += 1
			if crossings > AUTOMATIC_MAX_CROSSINGS:
				break
			var length := end - start + 1
			if length >= AUTOMATIC_MIN_MOVES and crossings >= AUTOMATIC_MIN_CROSSINGS and visits[route[start]] == 1 and visits[cell] == 1:
				if not by_length.has(length):
					by_length[length] = []
				by_length[length].append(start)
	if by_length.is_empty():
		return []
	var lengths := by_length.keys()
	var length: int = lengths[rng.randi_range(0, lengths.size() - 1)]
	var starts: Array = by_length[length]
	var start: int = starts[rng.randi_range(0, starts.size() - 1)]
	return route.slice(start, start + length)

static func _extend_route(route: Array, width: int, target: Vector2i) -> void:
	var current := cell_vector(route.back(), width)
	while current != target:
		current += Vector2i(signi(target.x - current.x), signi(target.y - current.y))
		route.append(current.y * width + current.x)

static func suggest_gray_tiles(layout: Dictionary) -> Dictionary:
	var width := int(layout.width)
	var height := int(layout.height)
	var tiles: Array = layout.tiles
	var adjacent: Array = []
	var groups := PackedInt32Array()
	groups.resize(tiles.size())
	groups.fill(-1)
	for cell in range(tiles.size()):
		adjacent.append(neighbors(cell, width, height))
	# Label dark islands once so bridges can be found without a route search.
	var group := 0
	for cell in range(tiles.size()):
		if tiles[cell] != 1 or groups[cell] >= 0:
			continue
		var pending: Array[int] = [cell]
		groups[cell] = group
		while not pending.is_empty():
			var current: int = pending.pop_back()
			for near in adjacent[current]:
				if tiles[near] == 1 and groups[near] < 0:
					groups[near] = group
					pending.append(near)
		group += 1
	if group == 0:
		return {}
	var visits := PackedByteArray()
	visits.resize(tiles.size())
	var endpoints: Array = [layout.get("solution_start", -1), layout.get("solution_end", -1)]
	var solution: Array = layout.get("solution", [])
	if not solution.is_empty():
		endpoints.append(solution.front())
		endpoints.append(solution.back())
		for cell in solution:
			visits[cell] += 1
	var eligible := PackedByteArray()
	eligible.resize(tiles.size())
	for cell in range(tiles.size()):
		# Keep every dark target, known endpoint, and existing gray patch intact.
		if tiles[cell] != 0 or cell in endpoints:
			continue
		eligible[cell] = 1
		for near in adjacent[cell]:
			if tiles[near] == 2:
				eligible[cell] = 0
				break
	var best: Dictionary = {}
	for cell in range(tiles.size()):
		if not eligible[cell]:
			continue
		var candidates: Array = [[cell]]
		for near in adjacent[cell]:
			if near > cell and eligible[near]:
				candidates.append([cell, near])
		for cells in candidates:
			var touching_groups: Dictionary = {}
			var touching_dark: Dictionary = {}
			var crossing := false
			for candidate in cells:
				crossing = crossing or visits[candidate] == 2
				for near in adjacent[candidate]:
					if tiles[near] == 1:
						touching_groups[groups[near]] = true
						touching_dark[near] = true
			var score := 0
			var reason := ""
			if touching_groups.size() >= 2:
				score = 100 + mini(touching_groups.size(), 4) * 8
				reason = "a bridge between dark groups"
			elif cells.size() == 1 and crossing and touching_dark.size() >= 2:
				score = 90
				reason = "extra freedom at a solution crossover"
			elif cells.size() == 1 and touching_dark.size() >= 3:
				score = 70
				reason = "a junction with several dark neighbors"
			if score == 0:
				continue
			# Prefer a single purposeful tile over a larger patch.
			score += touching_dark.size() * 2 - (cells.size() - 1) * 24
			if score > int(best.get("score", 0)):
				best = {"cells": cells, "reason": reason, "score": score}
	return best

static func _shuffled(values: Array, rng: RandomNumberGenerator) -> Array:
	var result := values.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = result[i]
		result[i] = result[j]
		result[j] = swap
	return result

static func _ordered_neighbors(path: Array, width: int, height: int, rng: RandomNumberGenerator) -> Array:
	var candidates := _shuffled(neighbors(path.back(), width, height), rng)
	# The search pops from the end. Try legal overpasses first when available.
	var crossings: Array = []
	var other: Array = []
	for cell in candidates:
		if path.has(cell) and can_append(path, cell, width, height):
			crossings.append(cell)
		else:
			other.append(cell)
	return other + crossings
