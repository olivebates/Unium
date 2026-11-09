extends SceneTree

var checks := 0
var failures := 0

func _init() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1120, 820)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.store.mirror_project = false
	main.play_level(2)
	main._finish_screen_transition()
	await process_frame
	var button_size: Vector2 = main.settings_button.size
	var base_size := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var rendered_sizes: Array[Vector2] = []
	for dimensions in [Vector2i(1120, 820), Vector2i(1920, 1080), Vector2i(760, 680), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var scale := minf(dimensions.x / base_size.x, dimensions.y / base_size.y) * float(ProjectSettings.get_setting("display/window/stretch/scale", 1.0))
		check(main.size.distance_to(Vector2(dimensions) / scale) < 2, "Scaled game fills window " + str(dimensions))
		check(main.settings_button.size == button_size, "Button proportions stay consistent at " + str(dimensions))
		check(main.palette_theme.default_font_size == 16, "Font design size scales with the viewport")
		check(main.get_node("CommunityFooter").size.y == 16, "Footer design size scales with the viewport")
		rendered_sizes.append(main.settings_button.size * scale)
		check(main.board.size.y > 0 and main.board.get_global_rect().end.y < main.size.y, "Board adapts to available height")
		for action in main.content.get_child(2).get_children():
			if action is Button:
				check(action.get_global_rect().end.x <= main.size.x and action.get_global_rect().end.y <= main.size.y, "Game action stays inside the viewport: " + action.text)
	check(rendered_sizes[1].x > rendered_sizes[0].x, "GUI grows in a larger window")
	check(rendered_sizes[2].x < rendered_sizes[0].x and rendered_sizes[3].x < rendered_sizes[0].x, "GUI shrinks in smaller windows")
	check(is_equal_approx(float(ProjectSettings.get_setting("display/window/stretch/scale")), 0.75), "Global interface is 25 percent smaller")
	main._open_custom_levels()
	if main.community_hub.view == "notice":
		main.community_hub.modal.confirmed.emit()
	var hub = main.community_hub
	check(hub.browser_gui.scale.is_equal_approx(Vector2.ONE * (0.5 / 0.75)), "Custom selector uses half-size controls overall")
	check((hub.browser_gui.size * hub.browser_gui.scale).is_equal_approx(hub.browser_panel.size), "Smaller selector controls retain all available window space")
	main.community_hub.open_editor()
	var editor: CustomLevelEditor = main.community_hub.editor
	root.size = Vector2i(760, 680)
	await process_frame
	await process_frame
	var scroll: ScrollContainer = editor.find_child("EditorBarScroll", true, false)
	check(not scroll.get_h_scroll_bar().visible, "Smaller GUI allows the editor toolbar to fit the narrow window")
	check(editor.palette[0].size == Vector2(54, 54) and editor.play_button.get_theme_font_size("font_size") == 16, "Editor brush and text proportions stay consistent")
	check(scroll.get_global_rect().end.x <= editor.size.x and editor.board.size.x <= editor.size.x, "Scrollable toolbar does not widen the game")
	main.queue_free()
	await process_frame
	print("Window layout: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
