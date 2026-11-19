extends Node
## Opens the menu and level 2, places the toolbox ramp, plays, and saves
## screenshots to user://shots/. Run windowed (not headless).

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png("user://shots/%s.png" % name)
	print("shot ", ProjectSettings.globalize_path("user://shots/%s.png" % name))

func _ready() -> void:
	Progress.use_sandbox()
	var menu: Node = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	for i in 10: await get_tree().process_frame
	await _shot("1_menu")
	menu.queue_free()
	Levels.current = int(OS.get_environment("LEVEL")) - 1 if OS.has_environment("LEVEL") else 1
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	for i in 10: await get_tree().process_frame
	await _shot("2_intro")
	game._close_dialogs()
	if not game.level.toolbox.is_empty():
		game._start_toolbox_drag(0)
		var o: TbeObject = game.dragging
		o.global_position = TBE.to_px(Vector2(float(OS.get_environment("PX")) if OS.has_environment("PX") else 1.0,
				float(OS.get_environment("PY")) if OS.has_environment("PY") else 1.4))
		game.dragging = null
		game.world.mark_dirty()
		game._refresh_toolbox()
	for i in 10: await get_tree().physics_frame
	game._update_buttons()
	await _shot("3_placed")
	game._toggle_play()
	for i in 150: await get_tree().physics_frame
	await _shot("4_running")
	for i in 300: await get_tree().physics_frame
	await _shot("5_later")
	get_tree().quit()
