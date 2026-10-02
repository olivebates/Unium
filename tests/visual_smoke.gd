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
	main.store.completed.clear()
	main.show_menu()
	await capture("first-menu")
	for number in range(1, 8):
		main.store.completed[str(number)] = true
	main.show_menu()
	await capture("menu")
	main.play_level(8)
	await capture("play")
	var solution: Array = main.store.get_level(8).solution
	main.board.path = solution.slice(0, 5)
	main.board.refresh()
	await capture("line")
	main._toggle_editor()
	await capture("editor")
	main._toggle_color_editor()
	await capture("color")
	quit()
