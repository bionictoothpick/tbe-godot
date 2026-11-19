extends Node
## Plays level 2 with simulated *real* mouse events (they go through Godot's
## full input pipeline, GUI included), like a player would. Run windowed:
##   godot --path . res://tools/input_test.tscn

var game: Node


func _check(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/in_%s.png" % n)


func _frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func _move(to: Vector2, steps := 1, from := Vector2(-1, -1)) -> void:
	var start := from if from.x >= 0 else get_viewport().get_mouse_position()
	for i in steps:
		var p := start.lerp(to, float(i + 1) / steps)
		var e := InputEventMouseMotion.new()
		e.position = p
		e.global_position = p
		e.relative = (to - start) / steps
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _down else 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await _frames(1)
	_last = to


var _down := false
var _last := Vector2.ZERO


func _button(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = button
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	_down = pressed and button == MOUSE_BUTTON_LEFT
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	await _frames(2)


func _click(at: Vector2) -> void:
	await _move(at, 1, _last)
	await _button(at, true)
	await _button(at, false)


func _drag(from: Vector2, to: Vector2) -> void:
	await _move(from, 1, _last)
	await _button(from, true)
	await _move(to, 12, from)
	await _button(to, false)


func _screen_of(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _find_button(root: Node, text_part: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if n is Button and n.is_visible_in_tree() and n.text.contains(text_part):
			return n
	return null


func _ready() -> void:
	Progress.use_sandbox()
	Input.use_accumulated_input = false
	Levels.current = 1
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _frames(10)
	var go := _find_button(game, "Let's go")
	_check(go != null, "intro dialog shows")
	await _click(_screen_of(go))
	_check(game.dialog_layer.get_child_count() == 0 or game.dialog_layer.get_children().all(func(c): return c.is_queued_for_deletion()), "intro closes on click")

	# drag the ramp from the toolbox into the scene
	var ramp_btn := _find_button(game, "Right Ramp")
	_check(ramp_btn != null and not ramp_btn.disabled, "ramp available in toolbox")
	var target := Vector2(300, 380)
	await _drag(_screen_of(ramp_btn), target)
	var placed: Array = game.world.objects.filter(func(o): return o.player_placed)
	_check(placed.size() == 1, "ramp placed by dragging from the toolbox")
	await _shot("1_after_toolbox_drag")
	if placed.is_empty():
		get_tree().quit()
		return
	var ramp: TbeObject = placed[0]
	var screen_pos: Vector2 = game.get_viewport().get_canvas_transform() * ramp.global_position
	_check(screen_pos.distance_to(target) < 30, "ramp ended under the mouse (%s vs %s)" % [screen_pos, target])

	# drag it again inside the scene
	var target2 := screen_pos + Vector2(80, -60)
	await _drag(screen_pos, target2)
	var screen_pos2: Vector2 = game.get_viewport().get_canvas_transform() * ramp.global_position
	_check(screen_pos2.distance_to(target2) < 30, "placed ramp can be dragged again")

	# grab it by its picture, away from the thin collision outline
	var corner_local: Vector2 = Vector2(0.35, -0.35) * ramp.size_m * TBE.PPM
	var corner_world: Vector2 = ramp.to_global(corner_local)
	_check(not ramp.contains_global_point(corner_world), "test point is off the ramp's thin outline")
	var grab: Vector2 = game.get_viewport().get_canvas_transform() * corner_world
	var before: Vector2 = ramp.global_position
	await _drag(grab, grab + Vector2(-60, 40))
	_check(ramp.global_position.distance_to(before) > 20, "ramp can be grabbed anywhere on its picture")
	screen_pos2 = game.get_viewport().get_canvas_transform() * ramp.global_position

	# right-click returns it to the toolbox
	await _move(screen_pos2, 1, _last)
	await _button(screen_pos2, true, MOUSE_BUTTON_RIGHT)
	await _button(screen_pos2, false, MOUSE_BUTTON_RIGHT)
	placed = game.world.objects.filter(func(o): return o.player_placed)
	_check(placed.is_empty(), "right-click puts it back in the toolbox")
	# click-to-place: click the toolbox item, move, click in the scene
	ramp_btn = _find_button(game, "Right Ramp")
	await _click(_screen_of(ramp_btn))
	_check(game.carrying, "a click on the toolbox picks the item up")
	var target3 := Vector2(420, 330)
	await _move(target3, 10, _last)
	await _click(target3)
	placed = game.world.objects.filter(func(o): return o.player_placed)
	_check(placed.size() == 1 and not game.carrying, "the next click places it")
	if placed.size() == 1:
		var sp: Vector2 = game.get_viewport().get_canvas_transform() * placed[0].global_position
		_check(sp.distance_to(target3) < 30, "placed where clicked (%s)" % sp)
	await _shot("2_end")
	get_tree().quit()
