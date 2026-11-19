extends Node
## The play screen: toolbox, placing objects, play/pause/reset, goals.

const PANEL_W := 250.0
const TOP_H := 52.0
const ROT_STEP := deg_to_rad(15.0)
const ROT_FINE := deg_to_rad(1.0)

enum Mode { EDIT, RUNNING, PAUSED }

var level: LevelData
var level_path := ""
var mode := Mode.EDIT
var snapshot: Array = []       # player objects as they were before Play

var world: World
var camera: Camera2D
var ui: CanvasLayer
var toolbox_box: VBoxContainer
var play_btn: Button
var fast_btn: Button
var sound_btn: Button
var status_label: Label
var hover_label: Label
var toast_label: Label
var title_label: Label
var dialog_layer: Control

var selected: TbeObject
var dragging: TbeObject
var drag_offset := Vector2.ZERO
var drag_from_toolbox := false
## True while an item picked from the toolbox with a click (not a drag)
## follows the mouse until the next click places it.
var carrying := false
var _drag_entered_scene := false
var _input_log: FileAccess
var resizing := ""             # "", "h", "v"
var _zoom := 1.0
var _speed := 1


# Mouse positions come from the input events themselves (not from a separate
# "current mouse" lookup, which can lag behind the events).
var _mouse_screen := Vector2.ZERO


func _track_mouse(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position


func _mouse_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * _mouse_screen


## Input diagnostics, off by default. When on, the game writes a log of mouse
## handling to user://input_log.txt (rewritten at each start) and saves a
## screenshot to user://diag/ whenever an item is dropped (last 8 kept).
## Turn on with Project Settings > Tbe > Debug > Input Diagnostics, or by
## starting the game with:  godot --path . -- --input-diagnostics
var diagnostics: bool = bool(ProjectSettings.get_setting("tbe/debug/input_diagnostics", false)) \
		or "--input-diagnostics" in OS.get_cmdline_user_args()


func _log(msg: String) -> void:
	if not diagnostics:
		return
	if _input_log == null:
		_input_log = FileAccess.open("user://input_log.txt", FileAccess.WRITE)
	if _input_log:
		_input_log.store_line("%8.3f %s" % [Time.get_ticks_msec() / 1000.0, msg])
		_input_log.flush()


var _shot_n := 0
var _motion_n := 0


## Saves what the window shows to user://diag/ (last 8 kept), for diagnosis.
func _diag_shot(tag: String) -> void:
	if not diagnostics:
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("user://diag")
	_shot_n += 1
	var f := "user://diag/%02d_%s.png" % [_shot_n % 8, tag]
	get_viewport().get_texture().get_image().save_png(f)
	_log("screenshot " + f)


func _screen_of_obj(o: TbeObject) -> Vector2:
	return get_viewport().get_canvas_transform() * o.global_position if o else Vector2(-1, -1)


func _in_scene_area(screen: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return screen.x < vp.x - PANEL_W and screen.y > TOP_H


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = World.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	world.won.connect(_on_won)
	world.failed.connect(_on_failed)
	world.note_requested.connect(_show_note)
	_build_ui()
	get_viewport().size_changed.connect(_fit_camera)
	load_level(Levels.current_path())


func load_level(p: String) -> void:
	level_path = p
	level = LevelData.load_file(p)
	if level == null:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if Levels.testing:
		title_label.text = "Testing: " + level.title
	else:
		title_label.text = "%d. %s" % [Levels.current + 1, level.title]
	var saved := Progress.get_solution(p)
	snapshot = _valid_solution(saved)
	_rebuild()
	_fit_camera()
	if not snapshot.is_empty():
		_toast("Your saved solution was restored.")
	_show_intro()


func _valid_solution(sol: Array) -> Array:
	## Keep only items the toolbox actually provides.
	var used := {}
	var out: Array = []
	for item in sol:
		var i := int(item.get("toolbox_index", -1))
		if i < 0 or i >= level.toolbox.size():
			continue
		if str(item["spec"].get("type", "")) != str(level.toolbox[i]["spec"]["type"]):
			continue
		used[i] = used.get(i, 0) + 1
		if used[i] > int(level.toolbox[i]["count"]):
			continue
		out.append({"spec": item["spec"], "toolbox_index": i})
	return out


func _rebuild() -> void:
	selected = null
	dragging = null
	world.build(level, snapshot)
	mode = Mode.EDIT
	get_tree().paused = false
	_set_speed(1)
	_refresh_toolbox()
	_update_buttons()
	_update_detail()
	if not world.unsupported.is_empty():
		_toast("Not available yet in this version: " + ", ".join(world.unsupported.keys()))


# ======================================================================= UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	# --- top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_H
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	top.add_child(bar)
	if Levels.testing:
		bar.add_child(_button("✎ Back to editor", "Return to the level editor", func(): _go_menu()))
	else:
		bar.add_child(_button("☰ Levels", "Back to the level list", func(): _go_menu()))
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	bar.add_child(title_label)
	bar.add_child(_button("🎯 Goal", "What do I need to do?", func(): _show_intro()))
	bar.add_child(_button("💾 Save", "Save how you placed your items", func(): _save_solution()))
	bar.add_child(_button("🧹 Clear", "Put every item back in the toolbox", func(): _clear_board()))
	bar.add_child(VSeparator.new())
	bar.add_child(_button("⟲ Reset", "Stop and put everything back (R)", func(): _reset()))
	play_btn = _button("▶ Play", "Start the machine (Space)", func(): _toggle_play())
	play_btn.custom_minimum_size.x = 100
	bar.add_child(play_btn)
	fast_btn = _button("⏩ 1×", "Simulation speed", func(): _set_speed(_speed * 2 if _speed < 4 else 1))
	bar.add_child(fast_btn)
	sound_btn = _button("", "Sound on/off (M)", func(): _toggle_sound())
	bar.add_child(sound_btn)
	_update_sound_btn()

	# --- toolbox panel
	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -PANEL_W
	side.offset_top = TOP_H
	root.add_child(side)
	var sv := VBoxContainer.new()
	side.add_child(sv)
	var tl := Label.new()
	tl.text = "Toolbox"
	tl.add_theme_font_size_override("font_size", 20)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(tl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	toolbox_box = VBoxContainer.new()
	toolbox_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(toolbox_box)
	var help := Label.new()
	help.text = "Drag an item into the scene, or click it, then click where it goes.\nWheel or Q/E: rotate (if allowed)\nYellow dot: resize (if allowed)\nRight-click / Del: back to toolbox"
	help.add_theme_font_size_override("font_size", 12)
	help.modulate = Color(1, 1, 1, 0.7)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	sv.add_child(help)

	# --- status / hover / toast
	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(10, -30)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 4)
	root.add_child(status_label)
	hover_label = Label.new()
	hover_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hover_label.add_theme_constant_override("outline_size", 5)
	hover_label.add_theme_font_size_override("font_size", 13)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hover_label)
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position.y = TOP_H + 10
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(toast_label)

	dialog_layer = Control.new()
	dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dialog_layer)


func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _refresh_toolbox() -> void:
	for c in toolbox_box.get_children():
		c.queue_free()
	var used := {}
	for o in world.objects:
		if o.player_placed:
			used[o.toolbox_index] = used.get(o.toolbox_index, 0) + 1
	if level.toolbox.is_empty():
		var l := Label.new()
		l.text = "(empty — just press Play)"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toolbox_box.add_child(l)
	for i in level.toolbox.size():
		var item: Dictionary = level.toolbox[i]
		var left: int = int(item["count"]) - used.get(i, 0)
		var d := Catalog.get_def(item["spec"]["type"])
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 64
		b.text = "  %s   × %d" % [d.display_name if d else item["spec"]["type"], left]
		b.tooltip_text = d.tooltip if d else ""
		b.disabled = left <= 0 or mode != Mode.EDIT
		if d:
			var img := d.image_states()[0] if not d.image_states().is_empty() else ""
			var custom = TBE.prop(item["spec"].get("props", {}), "ImageName")
			if custom != null:
				img = str(custom).split(";")[0]
			var tex := Images.get_texture(img, 64)
			if tex:
				b.icon = tex
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 52)
		b.button_down.connect(_start_toolbox_drag.bind(i))
		toolbox_box.add_child(b)


func _update_buttons() -> void:
	match mode:
		Mode.EDIT: play_btn.text = "▶ Play"
		Mode.RUNNING: play_btn.text = "⏸ Pause"
		Mode.PAUSED: play_btn.text = "▶ Resume"
	var msg := ""
	if mode == Mode.EDIT and world.any_overlap():
		msg = "Some of your items overlap (red). Move them apart before playing."
	status_label.text = msg


func _toast(text: String, seconds := 3.5) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func _fit_camera() -> void:
	if level == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var avail := vp - Vector2(PANEL_W, TOP_H) - Vector2(30, 30)
	var size_px := level.scene_size * TBE.PPM
	_zoom = minf(avail.x / size_px.x, avail.y / size_px.y)
	camera.zoom = Vector2(_zoom, _zoom)
	var center := Vector2(size_px.x * 0.5, -size_px.y * 0.5)
	camera.position = center + Vector2(PANEL_W * 0.5, -TOP_H * 0.5) / _zoom
	_update_detail()


func _update_detail() -> void:
	for o in world.objects:
		o.set_texture_detail(TBE.PPM * _zoom)


# ================================================================ dialogs

func _dialog(title: String, body_bbcode: String, buttons: Array) -> Control:
	_close_dialogs()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(t)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = body_bbcode
	rt.custom_minimum_size.x = 420
	v.add_child(rt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for b in buttons:
		var btn := _button(b[0], "", b[1])
		btn.custom_minimum_size = Vector2(110, 38)
		row.add_child(btn)
	return shade


func _close_dialogs() -> void:
	for c in dialog_layer.get_children():
		c.queue_free()


func _show_intro() -> void:
	var text := TBE.html_to_bbcode(level.description)
	if level.author != "":
		text += "\n\n[i][color=#aaaaaa]Level by %s[/color][/i]" % level.author
	_dialog(level.title, text, [["Let's go!", _close_dialogs]])


func _show_note(pages: Array, kind: String, page := 0) -> void:
	if pages.is_empty():
		return
	var buttons: Array = []
	if page > 0:
		buttons.append(["◀ Back", func(): _show_note(pages, kind, page - 1)])
	if page < pages.size() - 1:
		buttons.append(["Next ▶", func(): _show_note(pages, kind, page + 1)])
	else:
		buttons.append(["Close", _close_dialogs])
	_dialog("Note  %d/%d" % [page + 1, pages.size()], "[font_size=20]%s[/font_size]" % pages[page], buttons)


func _on_won() -> void:
	Sfx.play("win")
	if not Levels.testing:
		Progress.mark_completed(level_path, snapshot)
	Progress.save_solution(level_path, snapshot)
	await get_tree().create_timer(1.2, false).timeout
	if Levels.testing:
		_dialog("🦋 It works!", "Your level can be solved.", [["Watch again", _watch_again], ["✎ Back to editor", _go_menu]])
		return
	var has_next := Levels.current + 1 < Levels.paths.size()
	var buttons: Array = [["Watch again", _watch_again],
			["Levels", _go_menu]]
	if has_next:
		buttons.append(["Next level ▶", _next_level])
	_dialog("🦋 Level complete!", "Well done! Your solution has been saved.", buttons)


func _on_failed(reason: String) -> void:
	Sfx.play("fail")
	await get_tree().create_timer(0.8, false).timeout
	_dialog("Oops!", reason + "\n\nReset and try a different idea.",
			[["Keep watching", _close_dialogs], ["⟲ Reset", _close_and_reset]])


func _watch_again() -> void:
	_close_dialogs()
	_reset()
	_toggle_play()


func _close_and_reset() -> void:
	_close_dialogs()
	_reset()


func _next_level() -> void:
	_close_dialogs()
	Levels.current += 1
	load_level(Levels.current_path())


func _go_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	if mode == Mode.EDIT:
		_autosave()
	if Levels.testing:
		Levels.testing = false
		get_tree().change_scene_to_file("res://scenes/editor.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ============================================================== play flow

func _toggle_play() -> void:
	match mode:
		Mode.EDIT:
			if world.any_overlap():
				_toast("Some of your items overlap (shown in red). Move them apart first.")
				return
			_close_dialogs()
			snapshot = world.player_specs()
			_autosave()
			_select(null)
			mode = Mode.RUNNING
			world.start()
			_refresh_toolbox()
		Mode.RUNNING:
			mode = Mode.PAUSED
			get_tree().paused = true
		Mode.PAUSED:
			mode = Mode.RUNNING
			get_tree().paused = false
	_update_buttons()


func _reset() -> void:
	if mode == Mode.EDIT:
		return
	_rebuild()


func _toggle_sound() -> void:
	Sfx.set_muted(not Sfx.muted)
	_update_sound_btn()


func _update_sound_btn() -> void:
	sound_btn.text = "🔇" if Sfx.muted else "🔊"


func _set_speed(s: int) -> void:
	_speed = s
	Engine.time_scale = float(s)
	Engine.max_physics_steps_per_frame = 8 * s
	fast_btn.text = "⏩ %d×" % s


func _save_solution() -> void:
	var sol := world.player_specs() if mode == Mode.EDIT else snapshot
	Progress.save_solution(level_path, sol)
	_toast("Solution saved — it will be here when you come back.")


func _autosave() -> void:
	Progress.save_solution(level_path, world.player_specs() if mode == Mode.EDIT else snapshot)


func _clear_board() -> void:
	if mode != Mode.EDIT:
		_rebuild()
	for o in world.objects.duplicate():
		if o.player_placed:
			world.remove_object(o)
	selected = null
	_refresh_toolbox()
	_update_buttons()
	_autosave()


# ============================================================ edit input

func _start_toolbox_drag(index: int) -> void:
	if mode != Mode.EDIT:
		return
	var item: Dictionary = level.toolbox[index]
	var used := 0
	for o in world.objects:
		if o.player_placed and o.toolbox_index == index:
			used += 1
	if used >= int(item["count"]):
		return
	var s: Dictionary = item["spec"].duplicate(true)
	var m := TBE.to_m(_mouse_world())
	s["x"] = m.x
	s["y"] = m.y
	s.erase("id")
	var o := world.add_player_object(s, index)
	if o == null:
		return
	o.set_texture_detail(TBE.PPM * _zoom)
	_select(o)
	dragging = o
	Sfx.play("pick", 0.6)
	drag_offset = Vector2.ZERO
	drag_from_toolbox = true
	carrying = false
	_drag_entered_scene = false
	_log("toolbox pick %s at %s" % [item["spec"]["type"], _mouse_screen])
	_refresh_toolbox()


func _input(event: InputEvent) -> void:
	_track_mouse(event)
	if event is InputEventMouseButton:
		_log("button %d %s at %s  dragging=%s carrying=%s mode=%d dialogs=%d" % [event.button_index,
				"down" if event.pressed else "up", event.position, dragging != null, carrying, mode,
				dialog_layer.get_child_count() if dialog_layer else -1])
	# drags that started on the toolbox continue over the scene
	if dragging and event is InputEventMouseMotion:
		if _in_scene_area(event.position):
			_drag_entered_scene = true
		_drag_to(_mouse_world())
		_motion_n += 1
		if _motion_n % 15 == 1:
			_log("  drag motion mouse %s object %s" % [event.position, _screen_of_obj(dragging)])
		get_viewport().set_input_as_handled()
	elif dragging and carrying and event is InputEventMouseButton and event.pressed:
		# an item picked up with a click: the next click places it (or cancels)
		get_viewport().set_input_as_handled()
		carrying = false
		if event.button_index == MOUSE_BUTTON_LEFT and _in_scene_area(event.position):
			_drag_to(_mouse_world())
			_end_drag()
		else:
			var o := dragging
			dragging = null
			_return_to_toolbox(o)
	elif dragging and carrying and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
	elif dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		if drag_from_toolbox and not _drag_entered_scene and not _in_scene_area(event.position):
			# a click (not a drag) on the toolbox: keep carrying it until the next click
			carrying = true
			_log("carrying (click-to-place)")
			_toast("Click in the scene to place it. Right-click to cancel.")
		else:
			_end_drag()
	elif resizing != "" and event is InputEventMouseMotion:
		_resize_to(_mouse_world())
		get_viewport().set_input_as_handled()
	elif resizing != "" and event is InputEventMouseButton and not event.pressed:
		resizing = ""
		world.mark_dirty()
		_autosave()


func _unhandled_input(event: InputEvent) -> void:
	if not dialog_layer.get_children().is_empty():
		return
	var mp := _mouse_world()
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_left_click(mp)
			MOUSE_BUTTON_RIGHT:
				if mode == Mode.EDIT:
					var o := world.pick(mp, true)
					if o:
						_return_to_toolbox(o)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var target := dragging if dragging else world.pick(mp, true)
				if mode == Mode.EDIT and target and not target.can_rotate():
					_toast("This item can't be rotated in this level.", 2.0)
				if mode == Mode.EDIT and target and target.can_rotate():
					var step := ROT_FINE if event.shift_pressed else ROT_STEP
					_rotate(target, step if event.button_index == MOUSE_BUTTON_WHEEL_UP else -step)
	elif event is InputEventMouseMotion:
		_update_hover(mp, event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _toggle_play()
			KEY_R: _reset()
			KEY_M: _toggle_sound()
			KEY_DELETE, KEY_BACKSPACE:
				if selected and mode == Mode.EDIT:
					_return_to_toolbox(selected)
			KEY_Q, KEY_E:
				if selected and mode == Mode.EDIT and not selected.can_rotate():
					_toast("This item can't be rotated in this level.", 2.0)
				if selected and mode == Mode.EDIT and selected.can_rotate():
					var step := ROT_FINE if event.shift_pressed else ROT_STEP
					_rotate(selected, step if event.keycode == KEY_Q else -step)
			KEY_ESCAPE:
				if dragging and carrying:
					carrying = false
					var o := dragging
					dragging = null
					_return_to_toolbox(o)
				else:
					_select(null)


func _left_click(mp: Vector2) -> void:
	if mode == Mode.EDIT and selected and _handle_at(mp) != "":
		resizing = _handle_at(mp)
		return
	var o := world.pick(mp, mode == Mode.EDIT)
	_log("click: window %s zoom %.2f picked %s at screen %s" % [get_viewport().get_visible_rect().size, _zoom,
			o.def.type_name if o else "nothing", _screen_of_obj(o)])
	if mode == Mode.EDIT and o:
		_select(o)
		dragging = o
		drag_offset = o.global_position - mp
		drag_from_toolbox = false
		return
	# clicking non-player things: post-it notes etc.
	var any := world.pick(mp, false)
	if any and any.behavior:
		if mode == Mode.EDIT:
			any.behavior.on_clicked_in_edit()
		else:
			any.behavior.on_clicked()
		return
	_select(null)


func _drag_to(mp: Vector2) -> void:
	var p := mp + drag_offset
	if Input.is_key_pressed(KEY_SHIFT):
		p = p.snapped(Vector2(5, 5))
	dragging.global_position = p
	dragging.queue_redraw()
	world.mark_dirty()
	_redraw_handles()


func _end_drag() -> void:
	var o := dragging
	dragging = null
	# dropped back onto the toolbox panel (or outside the scene)?
	var screen := _mouse_screen
	var vp := get_viewport().get_visible_rect().size
	if screen.x > vp.x - PANEL_W or screen.y < TOP_H:
		_log("dropped outside the scene at %s -> back to toolbox" % screen)
		_return_to_toolbox(o)
		return
	_log("placed %s: mouse %s, object now at screen %s" % [o.def.type_name, screen, _screen_of_obj(o)])
	_diag_shot("drop")
	Sfx.play("drop", 0.6)
	world.mark_dirty()
	_autosave()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_update_buttons()


func _rotate(o: TbeObject, by: float) -> void:
	o.rotation -= by
	o.queue_redraw()
	world.mark_dirty()
	_redraw_handles()
	_autosave()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_update_buttons()


func _return_to_toolbox(o: TbeObject) -> void:
	if o == selected:
		_select(null)
	if o == dragging:
		dragging = null
	world.remove_object(o)
	Sfx.play("pick", 0.5, 0.7)
	_refresh_toolbox()
	_autosave()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_update_buttons()


func _select(o: TbeObject) -> void:
	if selected and is_instance_valid(selected):
		selected.selected = false
		selected.queue_redraw()
	selected = o
	if o:
		o.selected = true
		o.queue_redraw()
	_redraw_handles()


func _update_hover(mp: Vector2, screen_pos: Vector2) -> void:
	var o := world.pick(mp, false)
	if o and o.def.type_name != "Scenery" and not dragging:
		var hint := ""
		if o.player_placed and mode == Mode.EDIT:
			hint = "\n(drag to move%s%s)" % [", wheel to rotate" if o.can_rotate() else "",
					", yellow dot to resize" if o.resize_mode() != "none" else ""]
		elif o.behavior and o.def.behavior and o.def.behavior.resource_path.ends_with("postit.gd"):
			hint = "\n(click to read)"
		hover_label.text = o.tooltip + hint
		hover_label.position = screen_pos + Vector2(16, 16)
		var vp := get_viewport().get_visible_rect().size
		hover_label.position.x = minf(hover_label.position.x, vp.x - PANEL_W - hover_label.size.x - 4)
	else:
		hover_label.text = ""


# ------------------------------------------------------------- resizing

var _handles: Node2D


func _handle_points(o: TbeObject) -> Dictionary:
	var pts := {}
	var r := o.resize_mode()
	var half := o.size_m * TBE.PPM * 0.5
	if r == "horizontal" or r == "totalresize":
		pts["h"] = o.to_global(Vector2(half.x, 0))
	if r == "vertical" or r == "totalresize":
		pts["v"] = o.to_global(Vector2(0, -half.y))
	return pts


func _handle_at(mp: Vector2) -> String:
	if selected == null:
		return ""
	var pts := _handle_points(selected)
	for k in pts:
		if pts[k].distance_to(mp) < 10.0 / _zoom:
			return k
	return ""


func _redraw_handles() -> void:
	if _handles == null:
		_handles = Node2D.new()
		_handles.z_index = 4000
		_handles.draw.connect(_draw_handles)
		world.add_sibling(_handles)
	_handles.queue_redraw()


func _draw_handles() -> void:
	if selected == null or not is_instance_valid(selected) or mode != Mode.EDIT:
		return
	for k in _handle_points(selected).values():
		_handles.draw_circle(k, 7.0 / _zoom, Color(1, 0.85, 0.2))
		_handles.draw_arc(k, 7.0 / _zoom, 0, TAU, 20, Color.BLACK, 1.5 / _zoom)


func _resize_to(mp: Vector2) -> void:
	var o := selected
	if o == null:
		return
	var local := o.to_local(mp)
	var s := o.size_m
	# grow away from the opposite side so that side stays put
	if resizing == "h":
		var new_w := maxf(0.05, (local.x / TBE.PPM) + s.x * 0.5)
		o.global_position += Vector2((new_w - s.x) * 0.5 * TBE.PPM, 0).rotated(o.rotation)
		o.set_size_m(Vector2(new_w, s.y))
	elif resizing == "v":
		var new_h := maxf(0.05, (-local.y / TBE.PPM) + s.y * 0.5)
		o.global_position += Vector2(0, -(new_h - s.y) * 0.5 * TBE.PPM).rotated(o.rotation)
		o.set_size_m(Vector2(s.x, new_h))
	o.set_texture_detail(TBE.PPM * _zoom)
	world.mark_dirty()
	_redraw_handles()
