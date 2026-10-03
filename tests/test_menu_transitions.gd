extends SceneTree

var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.test-user/" + filename + ".png")

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.unlocked_through = 105
	var layout := {"width": 5, "height": 3, "tiles": [1, 0, 1, 0, 1, 0, 2, 0, 2, 0, 1, 0, 1, 0, 1]}
	if "--generated" in OS.get_cmdline_user_args():
		main.store.levels.clear()
		main.store.cache.clear()
	else:
		for number in range(1, 106):
			main.store.levels[str(number)] = layout.duplicate(true)
	var started := Time.get_ticks_usec()
	main.show_menu()
	var cold_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(main.find_children("", "SubViewport", true, false).is_empty(), "The menu creates no thumbnail viewports or physics worlds")
	check(main.find_children("", "PuzzleBoard", true, false).is_empty(), "The menu creates no live puzzle boards")
	check(main.menu_thumbnail_queue.size() == 105, "Thumbnail preparation is deferred instead of blocking menu construction")
	var frame_times: Array[float] = []
	var last := Time.get_ticks_usec()
	var deadline := last + 60000000
	while not main.menu_thumbnail_queue.is_empty() or main.menu_thumbnail_task >= 0:
		await process_frame
		var now := Time.get_ticks_usec()
		frame_times.append((now - last) / 1000.0)
		last = now
		if now > deadline:
			break
	check(main.menu_cards.all(func(card): return (card.get_child(0) as TextureRect).texture != null), "All thumbnails finish without GPU readback")
	started = Time.get_ticks_usec()
	main.show_menu()
	var warm_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(main.menu_thumbnail_queue.is_empty(), "Returning to an unchanged menu reuses every cached thumbnail")
	await settle()
	await capture("transition-menu")
	var card: Button = main.menu_cards[1]
	card.mouse_entered.emit()
	await create_timer(0.2).timeout
	check((card.get_child(0) as Control).scale.x > 1.04, "Thumbnail hover growth survives palette updates and container layout")
	card.mouse_exited.emit()
	await create_timer(0.2).timeout
	check((card.get_child(0) as Control).scale.is_equal_approx(Vector2.ONE), "Thumbnail returns to its original size")
	main.play_level(2)
	await settle()
	check(is_instance_valid(main.screen_transition) and main.transition_board == main.board, "Opening a menu level animates the actual board")
	check(main.board.scale.x < 1.0 and not main.board.is_processing_input(), "Opening starts at thumbnail scale with drawing suspended")
	await create_timer(0.07).timeout
	await capture("transition-open")
	await create_timer(0.3).timeout
	check(not is_instance_valid(main.screen_transition) and main.board.scale == Vector2.ONE and main.board.is_processing_input(), "Opening restores the full puzzle and drawing input")
	var old_board: PuzzleBoard = main.board
	started = Time.get_ticks_usec()
	main.show_menu()
	var return_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(main.menu_cards[1] == card, "Returning reuses the existing menu controls")
	await settle()
	await create_timer(0.06).timeout
	check(is_instance_valid(old_board) and old_board.scale.x < 1.0 and main.menu_cards[1].modulate.a == 0.0, "Returning shrinks the puzzle into its menu card")
	await capture("transition-close")
	await create_timer(0.25).timeout
	check(not is_instance_valid(main.screen_transition) and main.menu_cards[1].modulate.a == 1.0, "Returning reveals the destination card and releases the outgoing board")
	main.play_level(2)
	await create_timer(0.3).timeout
	main._open_adjacent_level(1)
	await settle()
	await create_timer(0.06).timeout
	check(main.current_level == 3 and main.transition_old_shell.position.x < 0.0 and main.transition_new_shell.position.x > 0.0, "Forward navigation pushes the old puzzle left")
	await capture("transition-forward")
	await create_timer(0.25).timeout
	main._open_adjacent_level(-1)
	await settle()
	await create_timer(0.06).timeout
	check(main.current_level == 2 and main.transition_old_shell.position.x > 0.0 and main.transition_new_shell.position.x < 0.0, "Backward navigation pushes the old puzzle right")
	await capture("transition-backward")
	await create_timer(0.25).timeout
	main.play_level(105)
	await create_timer(0.3).timeout
	main._open_adjacent_level(1)
	await settle()
	await create_timer(0.06).timeout
	check(main.current_level == 1 and main.transition_new_shell.position.x > 0.0, "Wrapping forward keeps the forward animation direction")
	main._open_adjacent_level(-1)
	await settle()
	await create_timer(0.06).timeout
	check(main.current_level == 105 and main.transition_new_shell.position.x < 0.0, "Wrapping backward keeps the backward animation direction")
	main.size = Vector2(1120, 680)
	main.show_menu()
	await create_timer(0.3).timeout
	check(main.menu_scroll.scroll_vertical > 0, "Returning reveals a level below the top of the scrollable menu")
	main.play_level(4)
	main.show_menu()
	main.play_level(5)
	await create_timer(0.35).timeout
	check(main.screen == "play" and main.current_level == 5 and not is_instance_valid(main.screen_transition) and main.board.is_processing_input(), "Interrupted transitions restore the latest screen without stranded overlays")
	main.store.completed["5"] = true
	main.show_menu()
	await create_timer(0.3).timeout
	var completed_card: Button = main.menu_cards[4]
	var completed_outline: Panel = completed_card.get_children().filter(func(node): return node is Panel)[0]
	check((completed_outline.get_theme_stylebox("panel") as StyleBoxFlat).border_color == main.COMPLETED_CARD_OUTLINE and (completed_card.get_child(0) as TextureRect).modulate == Color.WHITE, "Changed completion refreshes the green outline and preserves the puzzle preview colors")
	main.store.unlocked_through = 110
	main.store.levels.erase("106")
	main.store.cache.erase(106)
	main.show_menu()
	main._select_menu_level(106)
	check(main.screen == "menu", "Selecting an uncached generated puzzle leaves the menu responsive while it loads")
	main._return_to_menu()
	check(main.pending_menu_level == 0 and main.screen == "menu", "Escape cancels a pending puzzle selection")
	main._select_menu_level(106)
	deadline = Time.get_ticks_usec() + 15000000
	while main.screen == "menu" and Time.get_ticks_usec() < deadline:
		await process_frame
	check(main.screen == "play" and main.current_level == 106, "A generated puzzle opens once background preparation finishes")
	frame_times.sort()
	print("105-card menu: build %.2f ms, cached rebuild %.2f ms, retained return %.2f ms, preparation frame p95 %.2f ms, worst %.2f ms" % [cold_ms, warm_ms, return_ms, frame_times[int(frame_times.size() * 0.95)], frame_times[-1]])
	print("Menu/transition checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
