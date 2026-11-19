extends Node
## Drives the level editor end to end (run windowed):
## build a level, add a goal, move a piece to the toolbox, save, reopen,
## test-play with the piece placed, and expect a win.

func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shots/ed_%s.png" % n)

func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)

func _place(ed, type: String, x: float, y: float, id := "", angle := 0.0) -> void:
	ed._palette_drag(type)
	ed.dragging = false
	ed._set_spec("x", x)
	ed._set_spec("y", y)
	ed._set_spec("angle", angle)
	if id != "":
		ed._set_spec("id", id)

func _ready() -> void:
	Progress.use_sandbox()
	DirAccess.make_dir_recursive_absolute("user://shots")
	Levels.editor_level = null
	var ed: Node = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	for i in 5: await get_tree().process_frame
	ed.level.title = "Editor Test Level"
	await _shot("0_palette")
	_place(ed, "BowlingBall", 0.7, 1.6, "ball")
	_place(ed, "RightRamp", 1.0, 0.6)
	_place(ed, "PivotPoint", 3.0, 3.0)
	ed._select(2)
	ed.tabs.current_tab = 1
	await _shot("1_built")
	_check(ed.world.by_id.has("ball"), "ball has ID in world")
	_check(ed.level.predefined.size() == 4, "4 items (floor, ball, ramp, pivot)")
	# a goal: ball must roll past x = 4
	ed._goal_add()
	ed._goal_change_kind(ed.level.goals[0], 2)
	ed._goal_set(ed.level.goals[0], "xover", "4.0")
	_check(ed.level.goals[0]["props"].get("object") == "ball" and ed.level.goals[0]["props"].get("xover") == "4.0", "goal set up")
	# remove the pivot, rotate & undo, move the ramp to the toolbox
	ed._select(3)
	ed._delete_selected()
	ed._select(2)
	ed._rotate_selected(0.5)
	ed._undo_step()
	_check(absf(float(ed.level.predefined[2].get("angle", 0))) < 0.001, "undo restores rotation")
	ed._select(2)
	ed._move_to_toolbox()
	_check(ed.level.toolbox.size() == 1 and ed.level.predefined.size() == 2, "ramp moved to toolbox")
	ed.tabs.current_tab = 3
	await _shot("2_goals")
	ed._save()
	var path: String = Levels.editor_path
	_check(FileAccess.file_exists(path), "saved to " + path)
	_check(Levels.paths.has(path), "listed in levels")
	var re := LevelData.load_file(path)
	_check(re.title == "Editor Test Level" and re.predefined.size() == 2 and re.toolbox.size() == 1 and re.goals.size() == 1, "reload matches")
	# test-play: put the ramp back where it belongs and play
	_check(ed.prepare_test(), "test file written")
	ed.queue_free()
	await get_tree().process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	for i in 5: await get_tree().process_frame
	game._close_dialogs()
	game._clear_board()
	game._start_toolbox_drag(0)
	game.dragging.global_position = TBE.to_px(Vector2(1.0, 0.6))
	game.dragging = null
	game.world.mark_dirty()
	game._start_toolbox_drag(0)
	_check(game.dragging == null, "toolbox refuses a second ramp when count is 1")
	for i in 5: await get_tree().physics_frame
	var won := [false]
	game.world.won.connect(func(): won[0] = true)
	game._toggle_play()
	for i in 600:
		await get_tree().physics_frame
		if won[0]: break
	await get_tree().create_timer(1.5).timeout
	await _shot("3_test_won")
	_check(won[0], "test-play won")
	_check(not Progress.is_completed(Levels.TEST_FILE), "test play does not count as solved")
	DirAccess.remove_absolute(path)
	get_tree().quit()
