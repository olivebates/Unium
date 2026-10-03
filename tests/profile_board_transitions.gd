extends SceneTree

var tile_draws := 0
var all_frames: Array[float] = []
var failures := 0

func _init() -> void:
	call_deferred("run")

func observe(puzzle: PuzzleBoard) -> void:
	var canvas: CanvasItem = puzzle.get("tile_canvas") if puzzle.get("tile_canvas") != null else puzzle
	canvas.draw.connect(func(): tile_draws += 1)

func measure(main: Control, number: int, direction: int = 0) -> void:
	var before_draws := tile_draws
	var started := Time.get_ticks_usec()
	main.play_level(number, [], direction)
	var setup_ms := (Time.get_ticks_usec() - started) / 1000.0
	observe(main.board)
	var frames: Array[float] = []
	var last := started
	var deadline := started + 2000000
	while is_instance_valid(main.screen_transition) and Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	if is_instance_valid(main.screen_transition):
		failures += 1
		push_error("Transition did not finish")
	if not "--baseline" in OS.get_cmdline_user_args() and tile_draws - before_draws > 5:
		failures += 1
		push_error("Static tile geometry was rebuilt repeatedly during a transition")
	all_frames.append_array(frames)
	frames.sort()
	print("Level %d: setup %.2f ms, transition frame p95 %.2f ms, worst %.2f ms, tile draws %d" % [number, setup_ms, frames[int(frames.size() * 0.95)], frames[-1], tile_draws - before_draws])
	await create_timer(0.08).timeout

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.unlocked_through = 40
	for number in [1, 6, 8, 9, 11, 26, 36]:
		main.store.get_level(number)
	main.show_menu()
	var deadline := Time.get_ticks_usec() + 15000000
	while (not main.menu_thumbnail_queue.is_empty() or main.menu_thumbnail_task >= 0) and Time.get_ticks_usec() < deadline:
		await process_frame
	Input.warp_mouse(Vector2(10, 10))
	await create_timer(0.15).timeout
	for cycle in range(2):
		await measure(main, 11)
		for number in [26, 36, 9, 8, 6, 1]:
			await measure(main, number, 1 if number > main.current_level else -1)
		main.show_menu()
		await create_timer(0.35).timeout
	all_frames.sort()
	print("Transition profile: %d frames, p95 %.2f ms, worst %.2f ms, failures %d" % [all_frames.size(), all_frames[int(all_frames.size() * 0.95)], all_frames[-1], failures])
	quit(1 if failures else 0)
