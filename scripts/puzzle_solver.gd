extends RefCounted

# Incremental depth-first search. Light tiles must be visited zero or twice,
# dark tiles once, and gray tiles can be used without changing their value.
# advance() yields its work to the caller after a small time budget.
var status := "searching"
var solution: Array = []
var nodes := 0
var width: int
var height: int
var tiles: Array
var path: Array = []
var last_checked_path: Array = []
var popped_since_check: Array = []
var visits := PackedByteArray()
var first_in := PackedByteArray()
var first_out := PackedByteArray()
var adjacent: Array = []
var starts: Array = []
var choices: Array = []
var dark_left := 0
var open_light := 0
var known_path: Array = []
var known_prefix: Array = []
var deferred_starts: Array = []
var start_budget := 1024
var start_nodes := 0
var unwinding := false
var prepared_cells := 0
var prepared := false
var start_buckets: Dictionary = {}
var preferred_start := -1

func _init(layout: Dictionary) -> void:
	width = int(layout.width)
	height = int(layout.height)
	tiles = layout.tiles.duplicate()
	visits.resize(tiles.size())
	first_in.resize(tiles.size())
	first_out.resize(tiles.size())
	preferred_start = int(layout.get("solution_start", -1))
	if layout.get("solution") is Array:
		known_path = layout.solution.duplicate()

func advance(budget_usec: int = 2500) -> void:
	var deadline := Time.get_ticks_usec() + maxi(1, budget_usec)
	while status == "searching" and Time.get_ticks_usec() < deadline:
		# Generated drafts may already carry a solution. Validate it against the
		# current tiles and rules before using it; painting can make it stale.
		if not known_path.is_empty():
			var cell: int = known_path[known_prefix.size()]
			if not Puzzle.can_append(known_prefix, cell, width, height):
				known_path.clear()
				known_prefix.clear()
				continue
			known_prefix.append(cell)
			if known_prefix.size() == known_path.size():
				if known_prefix.size() >= 2 and Puzzle.is_complete(tiles, known_prefix):
					solution = known_prefix.duplicate()
					status = "solved"
				known_path.clear()
				known_prefix.clear()
			continue
		# Preparing even the largest editor grid is spread across frames too.
		if prepared_cells < tiles.size():
			var cell := prepared_cells
			adjacent.append(Puzzle.neighbors(cell, width, height))
			if tiles[cell] == 1:
				dark_left += 1
			var score := _start_score(cell)
			if not start_buckets.has(score):
				start_buckets[score] = []
			start_buckets[score].append(cell)
			prepared_cells += 1
			continue
		if not prepared:
			var scores := start_buckets.keys()
			scores.sort()
			for score in scores:
				starts.append_array(start_buckets[score])
			start_buckets.clear()
			if preferred_start >= 0 and preferred_start < tiles.size():
				starts.erase(preferred_start)
				starts.append(preferred_start)
			start_budget = maxi(start_budget, dark_left * 4)
			prepared = true
		# Try every possible start before spending an unbounded amount of work
		# on one. Later passes give unfinished starts progressively more time.
		if not path.is_empty() and (unwinding or nodes - start_nodes >= start_budget):
			if not unwinding:
				deferred_starts.append(path.front())
				unwinding = true
			choices.pop_back()
			_pop()
			continue
		if path.is_empty():
			unwinding = false
			if starts.is_empty():
				if deferred_starts.is_empty():
					status = "unsolvable"
					_update_checked_path()
					return
				starts = deferred_starts.duplicate()
				starts.reverse()
				deferred_starts.clear()
				start_budget *= 8
			start_nodes = nodes
			_push(starts.pop_back())
			choices.append(_next_choices())
		elif choices.back().is_empty():
			choices.pop_back()
			_pop()
		else:
			_push(choices.back().pop_back())
			if dark_left == 0 and open_light == 0 and path.size() >= 2:
				solution = path.duplicate()
				status = "solved"
				_update_checked_path()
				return
			# This is an overestimate of future reachability: it permits turns
			# through unvisited light cells, so it cannot reject a legal route.
			if nodes % 16 == 0 and not _targets_reachable():
				choices.append([])
			else:
				choices.append(_next_choices())
	_update_checked_path()

func _update_checked_path() -> void:
	# Reconstruct the most recently tested branch once per frame, including
	# any tail already popped while backtracking. Avoid copying every node.
	if status == "solved":
		last_checked_path = solution.duplicate()
	elif not known_prefix.is_empty():
		last_checked_path = known_prefix.duplicate()
	elif nodes > 0:
		last_checked_path = path.duplicate()
		for i in range(popped_since_check.size() - 1, -1, -1):
			last_checked_path.append(popped_since_check[i])

func _direction(from: int, to: int) -> int:
	var delta := to - from
	if delta == 1:
		return 1
	if delta == width:
		return 2
	if delta == -1:
		return 3
	return 4

func _perpendicular(a: int, b: int) -> bool:
	return a > 0 and b > 0 and a % 2 != b % 2

func _can_enter(cell: int, direction: int) -> bool:
	if visits[cell] == 0:
		return true
	if visits[cell] == 2 or tiles[cell] == 1:
		return false
	if cell == path.front():
		return _perpendicular(first_out[cell], direction)
	return first_in[cell] == first_out[cell] and _perpendicular(first_in[cell], direction)

func _next_choices() -> Array:
	var result: Array = []
	var current: int = path.back()
	var forced := 0
	if visits[current] == 2:
		forced = _direction(path[-2], current)
	elif tiles[current] == 0 and path.size() > 1:
		# Turning on the first visit would prevent crossing this light tile
		# later, leaving it dark with no way to restore it.
		forced = first_in[current]
	for cell in adjacent[current]:
		var direction := _direction(current, cell)
		if (forced == 0 or direction == forced) and _can_enter(cell, direction):
			result.append(cell)
	result.sort_custom(func(a: int, b: int): return _move_score(a) < _move_score(b))
	return result

func _start_score(cell: int) -> int:
	var degree := 0
	for next in adjacent[cell]:
		if tiles[next] != 0:
			degree += 1
	return (100 if tiles[cell] == 1 else (20 if tiles[cell] == 2 else 0)) - degree * 4 - adjacent[cell].size()

func _move_score(cell: int) -> int:
	if tiles[cell] == 0:
		return 120 if visits[cell] == 1 else -20
	if tiles[cell] == 2:
		return 20
	var exits := 0
	for next in adjacent[cell]:
		if _can_enter(next, _direction(cell, next)):
			exits += 1
	return 100 - exits

func _push(cell: int) -> void:
	popped_since_check.clear()
	var direction := 0
	if not path.is_empty():
		var previous: int = path.back()
		direction = _direction(previous, cell)
		if visits[previous] == 1:
			first_out[previous] = direction
	if visits[cell] == 0:
		first_in[cell] = direction
		first_out[cell] = 0
	if tiles[cell] == 1:
		dark_left -= 1
	elif tiles[cell] == 0:
		open_light += 1 if visits[cell] == 0 else -1
	visits[cell] += 1
	path.append(cell)
	nodes += 1

func _pop() -> void:
	var cell: int = path.pop_back()
	popped_since_check.append(cell)
	visits[cell] -= 1
	if tiles[cell] == 1:
		dark_left += 1
	elif tiles[cell] == 0:
		open_light += -1 if visits[cell] == 0 else 1
	if visits[cell] == 0:
		first_in[cell] = 0
		first_out[cell] = 0
	if not path.is_empty() and visits[path.back()] == 1:
		first_out[path.back()] = 0

func _targets_reachable() -> bool:
	# Keep an individual search step short on very large editor grids. Local
	# parity and crossing constraints still apply without these extra scans.
	if tiles.size() > 512:
		return true
	# Once the start is chosen, at most one unvisited dark tile can have only
	# one available edge: that tile must be the finish. A visited dark tile
	# cannot be used again because it would remain dark after its second visit.
	var dead_ends := 0
	var tip: int = path.back()
	for cell in range(tiles.size()):
		if tiles[cell] == 0 and visits[cell] == 1:
			var first_axis: int = first_out[cell] if cell == path.front() else first_in[cell]
			if first_axis == 0:
				continue
			var cross_edges := 0
			for next in adjacent[cell]:
				var direction := _direction(cell, next)
				if _perpendicular(first_axis, direction) and (next == tip or _can_enter(next, direction)):
					cross_edges += 1
			if cross_edges == 0:
				return false
			if cross_edges == 1:
				dead_ends += 1
				if dead_ends > 1:
					return false
		if tiles[cell] != 1 or visits[cell] != 0:
			continue
		var degree := 0
		for next in adjacent[cell]:
			if next == tip or _can_enter(next, _direction(cell, next)):
				degree += 1
		if degree == 0:
			return false
		if degree == 1:
			dead_ends += 1
			if dead_ends > 1:
				return false
	var seen := PackedByteArray()
	seen.resize(tiles.size())
	var pending: Array = [path.back()]
	seen[path.back()] = 1
	var cursor := 0
	while cursor < pending.size():
		var current: int = pending[cursor]
		cursor += 1
		for cell in adjacent[current]:
			if seen[cell] == 0 and _can_enter(cell, _direction(current, cell)):
				seen[cell] = 1
				pending.append(cell)
	for cell in range(tiles.size()):
		if seen[cell] == 0 and ((tiles[cell] == 1 and visits[cell] == 0) or (tiles[cell] == 0 and visits[cell] == 1)):
			return false
	return true
