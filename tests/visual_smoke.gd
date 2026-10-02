extends SceneTree

func _init() -> void:
	call_deferred("run")

func capture(filename: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.test-user/" + filename + ".png")

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.store.levels.clear()
	main.store.colors.clear()
	main.store.line_colors.clear()
	main.store.completed.clear()
	main.show_menu()
	await capture("first-menu")
	for number in range(1, 100):
		main.store.completed[str(number)] = true
	main.show_menu()
	await capture("menu-15")
	main.store.completed.clear()
	for number in range(1, 20):
		main.store.completed[str(number)] = true
	main.show_menu()
	await capture("menu-partial")
	main.store.completed.clear()
	for number in range(1, 8):
		main.store.completed[str(number)] = true
	main.show_menu()
	await capture("menu")
	var first_card: Button = main.find_children("", "Button", true, false).filter(func(node): return node.tooltip_text == "Play level 1")[0]
	first_card.mouse_entered.emit()
	await create_timer(0.35).timeout
	await capture("menu-hover")
	first_card.mouse_exited.emit()
	await capture("menu-held")
	main.play_level(8)
	await create_timer(0.65).timeout
	await capture("play")
	var solution: Array = main.store.get_level(8).solution
	main.board.path = solution.slice(0, 5)
	main.board.refresh()
	await capture("line")
	main._toggle_editor()
	await capture("editor")
	main._toggle_editor_playtest()
	main.board._begin(main.board.center(0))
	await capture("editor-playtest")
	main._toggle_editor_playtest()
	main._toggle_color_editor()
	await capture("color")
	main._select_color_target(true)
	main.color_picker.color = Color("f2c53d")
	main._color_picker_changed(main.color_picker.color)
	await capture("line-color")
	for number in [1, 6, 11, 16, 21]:
		main.play_level(number)
		main.board.path = main.store.get_level(number).solution.slice(0, 5)
		main.board.refresh()
		await create_timer(0.65).timeout
		await capture("palette-%d" % number)
	main._complete_level()
	await create_timer(0.4).timeout
	await capture("celebration")
	quit()
