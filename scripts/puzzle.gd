class_name Puzzle
extends RefCounted

const MAX_GENERATED_CROSSINGS := 3

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
	# Curated hues repeat in a predictable five-set cycle; level layout still uses its seed.
	const HUES := [0.43, 0.56, 0.74, 0.025, 0.10] # mint, sky, lavender, coral, amber
	var group := int((level - 1) / 5)
	return Color.from_hsv(HUES[group % HUES.size()], 1.0, 1.0)

static func generate(level: int, fixed_dimensions: Vector2i = Vector2i.ZERO, max_crossings: int = MAX_GENERATED_CROSSINGS, random_seed: int = -1, requested_moves: int = 0, exact_crossings: bool = false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level if random_seed < 0 else random_seed
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
	# Separate connected islands of 2–4 neutral tiles, touching a remaining dark tile.
	var gray: Array[int] = []
	var groups := mini(maxi(1, int(width * height / 15)), maxi(1, int(moves / 8)))
	for group in range(groups):
		for attempt in range(50):
			var seed_cell := rng.randi_range(0, tiles.size() - 1)
			var cluster: Array[int] = [seed_cell]
			var desired := rng.randi_range(2, 4)
			for growth in range(20):
				if cluster.size() == desired:
					break
				var from: int = cluster[rng.randi_range(0, cluster.size() - 1)]
				var nearby := neighbors(from, width, height)
				var candidate: int = nearby[rng.randi_range(0, nearby.size() - 1)]
				if candidate not in cluster:
					cluster.append(candidate)
			var valid := cluster.size() == desired
			var touches_black := false
			for cell in cluster:
				if cell in gray or cell == solution[0] or cell == solution[-1]:
					valid = false
				for adjacent in neighbors(cell, width, height):
					if adjacent in gray:
						valid = false
					if adjacent not in cluster and tiles[adjacent] == 1:
						touches_black = true
			if valid and touches_black:
				for cell in cluster:
					gray.append(cell)
					tiles[cell] = 2
				break
	return {"width": width, "height": height, "tiles": tiles, "solution": solution, "moves": moves}

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
