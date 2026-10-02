class_name Puzzle
extends RefCounted

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
	if index == 0 or index == path.size() - 1:
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
	# Finish after leaving a crossing, so both traversals really are straight.
	return not path.is_empty() and path.count(path.back()) == 1 and not resolved_tiles(tiles, path).has(1)

static func palette(level: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90517 + int((level - 1) / 5) * 719
	return Color.from_hsv(rng.randf(), rng.randf_range(0.28, 0.48), 0.94)

static func generate(level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = level
	var moves := level + 6
	var maximum_side := maxi(7, ceili(sqrt(float(moves))))
	var dimensions: Array[Vector2i] = []
	for w in range(3, maximum_side + 1):
		for h in range(3, maximum_side + 1):
			if w * h >= moves:
				dimensions.append(Vector2i(w, h))
	var dim := dimensions[rng.randi_range(0, dimensions.size() - 1)]
	var width := dim.x
	var height := dim.y
	var solution: Array = []
	# Bounded randomized depth-first search; every step uses the player's rules.
	for attempt in range(8):
		solution = [rng.randi_range(0, width * height - 1)]
		var choices: Array = [_shuffled(neighbors(solution.back(), width, height), rng)]
		var budget := 2200
		while not solution.is_empty() and budget > 0:
			budget -= 1
			if solution.size() == moves and solution.count(solution.back()) == 1:
				break
			if choices.back().is_empty() or solution.size() == moves:
				solution.pop_back()
				choices.pop_back()
				continue
			var next: int = choices.back().pop_back()
			if can_append(solution, next, width, height):
				solution.append(next)
				choices.append(_shuffled(neighbors(next, width, height), rng))
		if solution.size() == moves and solution.count(solution.back()) == 1:
			break
	if solution.size() != moves or solution.count(solution.back()) != 1:
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
	var groups := maxi(1, int(width * height / 15))
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
