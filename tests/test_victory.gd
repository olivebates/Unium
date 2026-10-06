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

func capture(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.test-user/" + filename + ".png")

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.completed.clear()
	main.store.hints.clear()
	main.store.unlocked_through = 0
	main.store.credits = 0
	main.store.complete_first(99)
	main.show_menu()
	check(main.store.menu_unlocked() == 101 and main.menu_cards.size() == 101 and main.menu_hint == null, "Normal group progression ends at level 101")
	check(not main.menu_thumbnail_queue.has(101) and not main.store.cache.has(101), "The victory menu card never generates a puzzle")
	check(main.store.rearrange_level(100, 101, "swap") == ERR_INVALID_PARAMETER, "Rearrangement cannot move a puzzle into the victory slot")
	main.play_level(100)
	await create_timer(0.35).timeout
	main._complete_level()
	var next_buttons: Array = main.completion_layer.find_children("", "Button", true, false).filter(func(node): return node.text == "Next Puzzle")
	check(next_buttons.size() == 1, "Completing level 100 offers Next Puzzle")
	next_buttons[0].pressed.emit()
	await create_timer(0.35).timeout
	check(main.current_level == 101 and main.screen == "play" and main.board == null and main.board_panel == null and main.hint_button == null, "Next opens the victory screen without puzzle controls")
	check(not is_instance_valid(main.screen_transition), "The puzzle-to-victory transition completes")
	check(main.find_children("", "Label", true, false).any(func(node): return node.text == "Congradulations on completing all the levels!"), "Victory preserves the requested heading")
	var body: RichTextLabel = main.find_child("VictoryMessage", true, false)
	check(body.get_parsed_text() == main.VICTORY_MESSAGE + "\n" + main.VICTORY_DISCORD and body.meta_clicked.is_connected(main._open_victory_link), "The requested invitation contains a clickable Discord link")
	var buttons: Array = main.active_shell.find_children("", "Button", true, false).filter(func(node): return node.name != "SettingsButton")
	check(buttons.size() == 2 and buttons[0].text == "Back to Puzzle Selection" and buttons[1].text.contains("Previous puzzle"), "Victory offers selection and previous navigation")
	var credits: int = main.store.credits
	main._complete_level()
	check(main.store.credits == credits and not main.store.completed.has("101") and main.store.purchase_hint(101) == ERR_UNAVAILABLE, "Victory cannot grant a completion credit or charge for a hint")
	var fireworks: Control = main.find_child("VictoryFireworks", true, false)
	check(fireworks.mouse_filter == Control.MOUSE_FILTER_IGNORE and fireworks.size.is_equal_approx(main.size), "Fireworks cover the screen and allow clicks through")
	check(not fireworks.rockets.is_empty() and fireworks.rockets[0].start.y > fireworks.size.y and fireworks.rockets[0].target.y < fireworks.size.y * 0.6, "Rockets launch from the bottom toward the sky")
	for frame in range(1800):
		fireworks._process(1.0 / 60.0)
	check(fireworks.launched > 30 and fireworks.exploded > 25 and not fireworks.sparks.is_empty(), "Fireworks continue launching and exploding for thirty seconds")
	check(fireworks.sparks.size() < 1000 and fireworks.rockets.size() < 6, "Expired fireworks are removed to keep the continuous effect bounded")
	check(fireworks.sparks.any(func(spark): return absf(spark.color.h - fireworks.sparks[0].color.h) > 0.1), "Bouquets contain multiple colors")
	await capture("victory")
	root.size = Vector2i(760, 680)
	await process_frame
	await process_frame
	await process_frame
	check(body.get_global_rect().end.x < main.size.x and body.get_global_rect().position.x >= 0.0 and body.size.y >= body.get_content_height(), "The message wraps and remains fully visible at the minimum window size")
	await capture("victory-small")
	main._open_adjacent_level(-1)
	await create_timer(0.35).timeout
	check(main.current_level == 100 and is_instance_valid(main.board) and not is_instance_valid(fireworks), "Previous returns to level 100 and frees the fireworks")
	main.show_menu()
	await create_timer(0.35).timeout
	main._select_menu_level(101)
	check(main.current_level == 101 and main.pending_menu_level == 0, "The menu opens victory immediately without waiting for a thumbnail")
	await create_timer(0.35).timeout
	fireworks = main.find_child("VictoryFireworks", true, false)
	main._return_to_menu()
	await create_timer(0.35).timeout
	check(main.screen == "menu" and main.menu_cards.size() == 101 and not is_instance_valid(fireworks), "Returning restores puzzle selection and stops the effect")
	main.play_level(101)
	main.show_menu()
	main.play_level(100)
	await create_timer(0.35).timeout
	check(main.current_level == 100 and is_instance_valid(main.board) and main.find_child("VictoryFireworks", true, false) == null and not is_instance_valid(main.screen_transition), "Interrupted victory transitions clean up correctly")
	print("Victory checks: %d, failures: %d" % [checks, failures])
	quit(1 if failures else 0)
