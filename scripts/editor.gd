extends Node
## In-game level editor.
##
## Drag objects from the palette into the scene, then move (drag), rotate
## (wheel / Q,E), resize (yellow dots) and fine-tune them in the Properties
## tab. The Toolbox tab sets what the player gets; the Goals tab sets what
## must happen to win. Test plays the level; Save writes user://levels/*.xml.

const PANEL_W := 340.0
const TOP_H := 52.0
const ROT_STEP := deg_to_rad(15.0)
const ROT_FINE := deg_to_rad(1.0)
const JOINT_TYPES := ["PivotPoint", "Glue", "Link"]
const JOINT_INFO := {
	"PivotPoint": "Pivot: object1 rotates around this point (attached to object2, or to the world if empty).",
	"Glue": "Glue: sticks object1 and object2 rigidly together.",
	"Link": "Link: a stiff bar between object1 and object2 (use Name@(x,y) for attachment points).",
}

var level: LevelData
var world: World
var camera: Camera2D
var overlay: Node2D            # joint markers + resize handles
var ui: CanvasLayer
var tabs: TabContainer
var props_box: VBoxContainer
var toolbox_list: VBoxContainer
var goals_list: VBoxContainer
var title_label: Label
var status_label: Label
var toast_label: Label
var dialog_layer: Control

var sel := -1                  # index into level.predefined
var dragging := false
var drag_offset := Vector2.ZERO
var resizing := ""             # "", "h", "v", "c"
var panning := false
var dirty := false
var _zoom := 1.0
var _undo: Array[LevelData] = []
var _redo: Array[LevelData] = []
var _drag_start_state: LevelData


# Mouse positions come from the input events themselves (not from a separate
# "current mouse" lookup, which can lag behind the events).
var _mouse_screen := Vector2.ZERO


func _track_mouse(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position


func _mouse_world() -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * _mouse_screen


func _ready() -> void:
	world = World.new()
	add_child(world)
	overlay = Node2D.new()
	overlay.z_index = 4000
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_build_ui()
	get_viewport().size_changed.connect(_fit_camera)
	Levels.testing = false
	if Levels.editor_level == null:
		Levels.editor_level = LevelData.new_level()
		Levels.editor_path = ""
	level = Levels.editor_level
	_rebuild()
	_fit_camera()
	_refresh_all()


# ================================================================ world sync

func _rebuild() -> void:
	for i in level.predefined.size():
		level.predefined[i]["_ei"] = i
	world.build(level, [])
	for o in world.objects:
		o.set_texture_detail(TBE.PPM * _zoom)
		o.selected = o.spec.get("_ei", -2) == sel
	overlay.queue_redraw()
	_update_title()


func _object_for(index: int) -> TbeObject:
	for o in world.objects:
		if o.spec.get("_ei", -1) == index:
			return o
	return null


func _is_joint(index: int) -> bool:
	return index >= 0 and index < level.predefined.size() and level.predefined[index]["type"] in JOINT_TYPES


## Remember the current state for undo, then mark the level changed.
func _checkpoint() -> void:
	_undo.append(level.clone())
	if _undo.size() > 100:
		_undo.pop_front()
	_redo.clear()
	dirty = true


func _commit_object(o: TbeObject) -> void:
	var i: int = o.spec.get("_ei", -1)
	if i >= 0:
		var s := o.to_spec()
		s.erase("_ei")
		level.predefined[i] = s
	_rebuild()


func _undo_step() -> void:
	if _undo.is_empty():
		return
	_redo.append(level.clone())
	_restore(_undo.pop_back())


func _redo_step() -> void:
	if _redo.is_empty():
		return
	_undo.append(level.clone())
	_restore(_redo.pop_back())


func _restore(l: LevelData) -> void:
	l.path = level.path
	level = l
	Levels.editor_level = l
	sel = -1
	dirty = true
	_rebuild()
	_fit_camera()
	_refresh_all()


# ======================================================================= UI

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = TOP_H
	root.add_child(top)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	top.add_child(bar)
	bar.add_child(_button("☰ Menu", "Back to the main menu", _go_menu))
	bar.add_child(_button("🗋 New", "Start a new level", _new_level))
	bar.add_child(_button("📂 Open", "Edit an existing level", _open_dialog))
	bar.add_child(_button("💾 Save", "Save to your levels (Ctrl+S)", _save))
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title_label)
	bar.add_child(_button("↶", "Undo (Ctrl+Z)", _undo_step))
	bar.add_child(_button("↷", "Redo (Ctrl+Y)", _redo_step))
	bar.add_child(_button("⛶ Fit", "Fit the scene in view", _fit_camera))
	var test := _button("▶ Test", "Play this level", _test_play)
	test.custom_minimum_size.x = 90
	bar.add_child(test)

	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_bottom = 1.0
	side.offset_left = -PANEL_W
	side.offset_top = TOP_H
	root.add_child(side)
	tabs = TabContainer.new()
	side.add_child(tabs)
	tabs.add_child(_scroll_tab("Add", _build_palette()))
	props_box = VBoxContainer.new()
	tabs.add_child(_scroll_tab("Edit", props_box))
	toolbox_list = VBoxContainer.new()
	tabs.add_child(_scroll_tab("Toolbox", toolbox_list))
	goals_list = VBoxContainer.new()
	tabs.add_child(_scroll_tab("Goals", goals_list))
	var settings := VBoxContainer.new()
	settings.name = "settings"
	tabs.add_child(_scroll_tab("Level", settings))

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(10, -28)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 4)
	status_label.add_theme_font_size_override("font_size", 13)
	root.add_child(status_label)
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position.y = TOP_H + 10
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(toast_label)
	dialog_layer = Control.new()
	dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dialog_layer)


func _scroll_tab(tab_name: String, content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _label(text: String, size := 14, dim := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if dim:
		l.modulate = Color(1, 1, 1, 0.65)
	return l


func _build_palette() -> Control:
	var v := VBoxContainer.new()
	v.add_child(_label("Drag into the scene. Wheel / Q,E rotates, yellow dots resize, Del deletes, Ctrl+D duplicates. Ctrl+wheel zooms, middle-drag pans.", 12, true))
	var cats := Catalog.categories()
	var names := cats.keys()
	names.sort()
	names.append("Joints")
	for cat in names:
		v.add_child(_label(cat, 16))
		var flow := HFlowContainer.new()
		v.add_child(flow)
		if cat == "Joints":
			for jt in JOINT_TYPES:
				flow.add_child(_palette_button(jt, jt, null, JOINT_INFO[jt]))
			continue
		for d: ObjectDef in cats[cat]:
			var img := d.image_states()[0] if not d.image_states().is_empty() else ""
			flow.add_child(_palette_button(d.type_name, d.display_name, Images.get_texture(img, 96), d.tooltip))
	return v


func _palette_button(type: String, text: String, icon: Texture2D, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(88, 78)
	b.tooltip_text = text + ("\n" + tip if tip != "" else "")
	b.clip_text = true
	if icon:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = text
	b.add_theme_font_size_override("font_size", 11)
	b.button_down.connect(_palette_drag.bind(type))
	return b


func _toast(text: String, seconds := 3.0) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(toast_label, "modulate:a", 0.0, 0.5)


func _update_title() -> void:
	var where := Levels.editor_path.get_file() if Levels.editor_path != "" else "not saved yet"
	title_label.text = "✎ %s%s  (%s)" % [level.title, " *" if dirty else "", where]


func _refresh_all() -> void:
	_refresh_props()
	_refresh_toolbox()
	_refresh_goals()
	_refresh_settings()
	_update_title()


func _fit_camera() -> void:
	var vp := get_viewport().get_visible_rect().size
	var avail := vp - Vector2(PANEL_W, TOP_H) - Vector2(40, 40)
	var size_px := level.scene_size * TBE.PPM
	_set_zoom(minf(avail.x / size_px.x, avail.y / size_px.y))
	camera.position = Vector2(size_px.x * 0.5, -size_px.y * 0.5) + Vector2(PANEL_W * 0.5, -TOP_H * 0.5) / _zoom


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.05, 20.0)
	camera.zoom = Vector2(_zoom, _zoom)
	for o in world.objects:
		o.set_texture_detail(TBE.PPM * _zoom)
	overlay.queue_redraw()


# ============================================================= input

func _mouse_m() -> Vector2:
	return TBE.to_m(_mouse_world())


func _palette_drag(type: String) -> void:
	_checkpoint()
	var m := _mouse_m()
	var s := {"type": type, "x": m.x, "y": m.y, "angle": 0.0, "props": {}}
	var d := Catalog.get_def(type)
	if d:
		s["w"] = d.width
		s["h"] = d.height
	else:
		s["w"] = 1.0
		s["h"] = 1.0
		s["props"] = {"object1": "", "object2": ""}
	level.predefined.append(s)
	sel = level.predefined.size() - 1
	_rebuild()
	dragging = true
	drag_offset = Vector2.ZERO
	_refresh_props()
	tabs.current_tab = 1


func _input(event: InputEvent) -> void:
	_track_mouse(event)
	if dragging and event is InputEventMouseMotion:
		_drag_to(_mouse_world())
		get_viewport().set_input_as_handled()
	elif dragging and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		_end_drag()
		get_viewport().set_input_as_handled()
	elif resizing != "" and event is InputEventMouseMotion:
		_resize_to(_mouse_world())
		get_viewport().set_input_as_handled()
	elif resizing != "" and event is InputEventMouseButton and not event.pressed:
		resizing = ""
		var o := _object_for(sel)
		if o:
			_commit_object(o)
		_refresh_props()
	elif panning and event is InputEventMouseMotion:
		camera.position -= event.relative / _zoom
	elif panning and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		panning = false


func _unhandled_input(event: InputEvent) -> void:
	if not dialog_layer.get_children().is_empty():
		return
	var mp := _mouse_world()
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_left_click(mp)
			MOUSE_BUTTON_MIDDLE:
				panning = true
			MOUSE_BUTTON_RIGHT:
				var i := _pick(mp)
				if i >= 0:
					_select(i)
					_delete_selected()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var up: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP
				if event.ctrl_pressed or _pick(mp) < 0 and sel < 0:
					var before := mp
					_set_zoom(_zoom * (1.15 if up else 1.0 / 1.15))
					camera.position += before - _mouse_world()
				else:
					var i := _pick(mp)
					if i < 0:
						i = sel
					if not _is_joint(i):
						_select(i)
						_rotate_selected((ROT_FINE if event.shift_pressed else ROT_STEP) * (1 if up else -1))
	elif event is InputEventMouseMotion:
		var m := TBE.to_m(mp)
		var hover := _pick(mp)
		var what := ""
		if hover >= 0:
			var hs: Dictionary = level.predefined[hover]
			what = "   %s%s" % [hs["type"], (" \"%s\"" % hs["id"]) if hs.get("id", "") != "" else ""]
		status_label.text = "x %.2f  y %.2f m%s" % [m.x, m.y, what]
	elif event is InputEventKey and event.pressed:
		var k: Key = event.keycode
		if event.ctrl_pressed:
			match k:
				KEY_Z:
					if event.shift_pressed:
						_redo_step()
					else:
						_undo_step()
				KEY_Y: _redo_step()
				KEY_S: _save()
				KEY_D: _duplicate_selected()
			return
		match k:
			KEY_DELETE, KEY_BACKSPACE: _delete_selected()
			KEY_Q: _rotate_selected(ROT_FINE if event.shift_pressed else ROT_STEP)
			KEY_E: _rotate_selected(-(ROT_FINE if event.shift_pressed else ROT_STEP))
			KEY_ESCAPE: _select(-1)
			KEY_LEFT: _nudge(Vector2(-1, 0), event.shift_pressed)
			KEY_RIGHT: _nudge(Vector2(1, 0), event.shift_pressed)
			KEY_UP: _nudge(Vector2(0, 1), event.shift_pressed)
			KEY_DOWN: _nudge(Vector2(0, -1), event.shift_pressed)


func _left_click(mp: Vector2) -> void:
	var h := _handle_at(mp)
	if h != "":
		_checkpoint()
		resizing = h
		return
	var i := _pick(mp)
	_select(i)
	if i >= 0:
		_drag_start_state = level.clone()
		dragging = true
		drag_offset = _sel_pos_px() - mp


## Index of the object or joint marker under a global point, or -1.
func _pick(mp: Vector2) -> int:
	# joint markers first (they are small and sit on top)
	for i in level.predefined.size():
		if _is_joint(i) and _joint_pos_px(i).distance_to(mp) < 10.0 / _zoom:
			return i
	var o := world.pick(mp, false)
	return o.spec.get("_ei", -1) if o else -1


func _sel_pos_px() -> Vector2:
	if _is_joint(sel):
		return _joint_pos_px(sel)
	var o := _object_for(sel)
	return o.global_position if o else Vector2.ZERO


func _joint_pos_px(i: int) -> Vector2:
	var s: Dictionary = level.predefined[i]
	return TBE.to_px(Vector2(s.get("x", 0.0), s.get("y", 0.0)))


func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(5, 5)) if Input.is_key_pressed(KEY_SHIFT) else p


func _drag_to(mp: Vector2) -> void:
	var p := _snap(mp + drag_offset)
	if _is_joint(sel):
		var m := TBE.to_m(p)
		level.predefined[sel]["x"] = snappedf(m.x, 0.001)
		level.predefined[sel]["y"] = snappedf(m.y, 0.001)
	else:
		var o := _object_for(sel)
		if o:
			o.global_position = p
	overlay.queue_redraw()


func _end_drag() -> void:
	# dropped on the side panel = delete (handy when dragging out of the palette)
	var screen := _mouse_screen
	if screen.x > get_viewport().get_visible_rect().size.x - PANEL_W:
		if _drag_start_state:
			_undo.append(_drag_start_state)
		_delete_selected(false)
		return
	if _drag_start_state:
		_undo.append(_drag_start_state)
		_redo.clear()
		_drag_start_state = null
	dirty = true
	var o := _object_for(sel)
	if o:
		_commit_object(o)
	else:
		_rebuild()
	_refresh_props()
	_refresh_goals()


func _nudge(dir: Vector2, big: bool) -> void:
	if sel < 0:
		return
	_checkpoint()
	var s: Dictionary = level.predefined[sel]
	var step := 0.05 if big else 0.01
	s["x"] = snappedf(float(s.get("x", 0.0)) + dir.x * step, 0.001)
	s["y"] = snappedf(float(s.get("y", 0.0)) + dir.y * step, 0.001)
	_rebuild()
	_refresh_props()


func _rotate_selected(by: float) -> void:
	if sel < 0 or _is_joint(sel):
		return
	_checkpoint()
	var s: Dictionary = level.predefined[sel]
	s["angle"] = snappedf(fposmod(float(s.get("angle", 0.0)) + by + PI, TAU) - PI, 0.0001)
	_rebuild()
	_refresh_props()


func _select(i: int) -> void:
	# commit any half-typed field to the object it belongs to first
	get_viewport().gui_release_focus()
	sel = i
	for o in world.objects:
		var on: bool = o.spec.get("_ei", -2) == i
		if o.selected != on:
			o.selected = on
			o.queue_redraw()
	overlay.queue_redraw()
	_refresh_props()


func _delete_selected(checkpoint := true) -> void:
	if sel < 0:
		return
	if checkpoint:
		_checkpoint()
	level.predefined.remove_at(sel)
	sel = -1
	dirty = true
	_rebuild()
	_refresh_props()
	_refresh_goals()


func _duplicate_selected() -> void:
	if sel < 0:
		return
	_checkpoint()
	var s: Dictionary = level.predefined[sel].duplicate(true)
	s.erase("id")
	s["x"] = float(s.get("x", 0.0)) + 0.1
	s["y"] = float(s.get("y", 0.0)) + 0.1
	level.predefined.append(s)
	sel = level.predefined.size() - 1
	_rebuild()
	_refresh_props()


# ------------------------------------------------------------- resizing

func _handle_points() -> Dictionary:
	var o := _object_for(sel)
	if o == null:
		return {}
	var half := o.size_m * TBE.PPM * 0.5
	if o.def.shape == ObjectDef.Shape.CIRCLE:
		return {"c": o.to_global(Vector2(half.x, -half.y))}
	return {"h": o.to_global(Vector2(half.x, 0)), "v": o.to_global(Vector2(0, -half.y)),
			"c": o.to_global(Vector2(half.x, -half.y))}


func _handle_at(mp: Vector2) -> String:
	var pts := _handle_points()
	for k in pts:
		if pts[k].distance_to(mp) < 9.0 / _zoom:
			return k
	return ""


func _resize_to(mp: Vector2) -> void:
	var o := _object_for(sel)
	if o == null:
		return
	var local := o.to_local(mp) / TBE.PPM          # meters, y down
	var s := o.size_m
	var new_size := s
	if resizing in ["h", "c"]:
		new_size.x = maxf(0.02, local.x + s.x * 0.5)
	if resizing in ["v", "c"]:
		new_size.y = maxf(0.02, -local.y + s.y * 0.5)
	if o.def.shape == ObjectDef.Shape.CIRCLE:
		new_size = Vector2.ONE * maxf(new_size.x, new_size.y)
	if Input.is_key_pressed(KEY_SHIFT):
		new_size = new_size.snapped(Vector2(0.05, 0.05)).max(Vector2(0.05, 0.05))
	# keep the opposite (bottom-left) side in place
	var shift := Vector2((new_size.x - s.x) * 0.5, -(new_size.y - s.y) * 0.5) * TBE.PPM
	o.global_position += shift.rotated(o.rotation)
	o.set_size_m(new_size)
	if TBE.prop(o.props, "Radius") != null:
		o.props["Radius"] = str(snappedf(new_size.x * 0.5, 0.001))
		o.spec["props"]["Radius"] = o.props["Radius"]
	o.set_texture_detail(TBE.PPM * _zoom)
	overlay.queue_redraw()


func _draw_overlay() -> void:
	# joints: a marker plus lines to what they connect
	for i in level.predefined.size():
		if not _is_joint(i):
			continue
		var s: Dictionary = level.predefined[i]
		var p := _joint_pos_px(i)
		var col := Color(1, 0.5, 0.1) if i != sel else Color(1, 0.9, 0.2)
		for key in ["object1", "object2"]:
			var a := TBE.parse_anchor(str(TBE.prop(s.get("props", {}), key, "")))
			var o: TbeObject = world.by_id.get(a[0])
			if o:
				var target := o.to_global(TBE.to_px(a[1]))
				overlay.draw_dashed_line(p, target, col, 2.0 / _zoom, 6.0 / _zoom)
				overlay.draw_circle(target, 3.0 / _zoom, col)
		overlay.draw_circle(p, 8.0 / _zoom, Color(0, 0, 0, 0.6))
		overlay.draw_circle(p, 6.0 / _zoom, col)
		overlay.draw_string(ThemeDB.fallback_font, p + Vector2(9, -9) / _zoom, s["type"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 / _zoom) if _zoom < 1 else 12, col)
	for k in _handle_points().values():
		overlay.draw_circle(k, 7.0 / _zoom, Color(1, 0.85, 0.2))
		overlay.draw_arc(k, 7.0 / _zoom, 0, TAU, 20, Color.BLACK, 1.5 / _zoom)


# ======================================================= properties tab

func _clear(c: Control) -> void:
	for ch in c.get_children():
		ch.queue_free()


func _refresh_props() -> void:
	_clear(props_box)
	if sel < 0 or sel >= level.predefined.size():
		props_box.add_child(_label("Click an object in the scene to edit it.", 14, true))
		return
	var s: Dictionary = level.predefined[sel]
	var d := Catalog.get_def(s["type"])
	props_box.add_child(_label(d.display_name if d else s["type"], 18))
	if _is_joint(sel):
		props_box.add_child(_label(JOINT_INFO.get(s["type"], ""), 12, true))
	var grid := GridContainer.new()
	grid.columns = 2
	props_box.add_child(grid)
	_field(grid, "Name (ID)", s.get("id", ""), func(v): _set_spec("id", v.strip_edges()),
			"Give objects a name to use them in goals, joints and properties.")
	_num_field(grid, "X (m)", s.get("x", 0.0), func(v): _set_spec("x", v))
	_num_field(grid, "Y (m)", s.get("y", 0.0), func(v): _set_spec("y", v))
	if not _is_joint(sel):
		_num_field(grid, "Width (m)", s.get("w", d.width if d else 1.0), func(v): _set_spec("w", maxf(v, 0.01)))
		_num_field(grid, "Height (m)", s.get("h", d.height if d else 1.0), func(v): _set_spec("h", maxf(v, 0.01)))
		_num_field(grid, "Angle (°)", rad_to_deg(float(s.get("angle", 0.0))), func(v): _set_spec("angle", snappedf(deg_to_rad(v), 0.0001)))
		var p: Dictionary = s.get("props", {})
		_field(grid, "Mass (kg)", str(p.get("Mass", "")), func(v): _set_prop("Mass", v),
				"Empty = default. 0 = fixed in place.", "%s (default)" % (d.mass if d else 0))
		_field(grid, "Bounciness", str(p.get("Bounciness", "")), func(v): _set_prop("Bounciness", v),
				"0..1. Empty = default.", "%s (default)" % (d.bounciness if d else 0))
		_field(grid, "Friction", str(p.get("Friction", "")), func(v): _set_prop("Friction", v),
				"Empty = default.", "%s (default)" % (d.friction if d else 0))
		_field(grid, "Image", str(p.get("ImageName", "")), func(v): _set_prop("ImageName", v),
				"Image name from assets/images (empty = default). Separate animation states with ;",
				(d.image_states()[0] if d and not d.image_states().is_empty() else ""))
		_field(grid, "Tooltip", s.get("tooltip", ""), func(v): _set_spec("tooltip", v))
	else:
		var ids := _ids()
		_field(grid, "object1", str(TBE.prop(s.get("props", {}), "object1", "")), func(v): _set_prop("object1", v),
				"Name of an object, optionally with an attachment point: Bar@(0.5,0)\nKnown: " + ", ".join(ids))
		_field(grid, "object2", str(TBE.prop(s.get("props", {}), "object2", "")), func(v): _set_prop("object2", v),
				"Second object (empty = the world).\nKnown: " + ", ".join(ids))

	# other properties (Post-it pages, PhoneNumber, target "object", ...) as key = value lines
	var known := ["Mass", "Bounciness", "Friction", "ImageName", "object1", "object2"]
	var lines := PackedStringArray()
	for k in s.get("props", {}):
		if k not in known:
			lines.append("%s = %s" % [k, s["props"][k]])
	props_box.add_child(_label("More properties (key = value per line):", 13))
	props_box.add_child(_label(_hint_for(s["type"]), 11, true))
	var te := TextEdit.new()
	te.text = "\n".join(lines)
	te.custom_minimum_size.y = 120
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.focus_exited.connect(func(): _set_extra_props(te.text))
	props_box.add_child(te)

	var row := HBoxContainer.new()
	props_box.add_child(row)
	row.add_child(_button("⧉ Duplicate", "Ctrl+D", _duplicate_selected))
	row.add_child(_button("🗑 Delete", "Del", func(): _delete_selected()))
	if not _is_joint(sel) and d and not d.no_collision:
		props_box.add_child(_button("➜ Move to player's toolbox", "Take this object out of the scene and give it to the player instead.", _move_to_toolbox))


func _hint_for(type: String) -> String:
	match type:
		"Butterfly": return "object = name of the thing it flies to (e.g. Flower)"
		"DetonatorBox": return "PhoneNumber = name of the dynamite it sets off"
		"PostItTutorial", "PostItHint", "PostItMisc": return "page1 = first page text, page2 = ... (<br> = new line)"
		"ColaMintBottle": return "Thrust = push strength (default 2.0)"
		"PolyObject": return "Polygons = (x,y)=(x,y)=(x,y);(next polygon)"
		"CustomBall": return "Radius = ball radius in meters"
		"Scenery": return "ZValue = draw order (higher is in front)"
	return "e.g. ZValue = 3 (draw order), NoCollision = true"


func _grid_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.custom_minimum_size.x = 92
	return l


func _field(grid: GridContainer, label: String, value: String, cb: Callable, tip := "", placeholder := "") -> void:
	var l := _grid_label(label)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.tooltip_text = tip
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_submitted.connect(func(t): cb.call(t))
	e.focus_exited.connect(func():
		if e.text != value:
			cb.call(e.text))
	grid.add_child(e)


func _num_field(grid: GridContainer, label: String, value: float, cb: Callable) -> void:
	grid.add_child(_grid_label(label))
	var sb := SpinBox.new()
	sb.step = 0.001
	sb.min_value = -1000
	sb.max_value = 1000
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.value = snappedf(value, 0.001)
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(v): cb.call(v))
	grid.add_child(sb)


func _set_spec(key: String, value: Variant) -> void:
	if sel < 0:
		return
	var s: Dictionary = level.predefined[sel]
	if s.get(key) == value:
		return
	_checkpoint()
	if key == "id":
		_rename_id(str(s.get("id", "")), str(value))
	if typeof(value) == TYPE_STRING and value == "" and key in ["id", "tooltip"]:
		s.erase(key)
	else:
		s[key] = value
	_rebuild()
	if key == "id":
		_refresh_goals()


func _set_prop(key: String, value: String) -> void:
	if sel < 0:
		return
	var s: Dictionary = level.predefined[sel]
	if not s.has("props"):
		s["props"] = {}
	var v := value.strip_edges()
	if str(s["props"].get(key, "")) == v:
		return
	_checkpoint()
	if v == "":
		s["props"].erase(key)
	else:
		s["props"][key] = v
	_rebuild()


func _set_extra_props(text: String) -> void:
	if sel < 0 or sel >= level.predefined.size():
		return
	var s: Dictionary = level.predefined[sel]
	var keep := {}
	for k in s.get("props", {}):
		if k in ["Mass", "Bounciness", "Friction", "ImageName", "object1", "object2"]:
			keep[k] = s["props"][k]
	for line in text.split("\n", false):
		var eq := line.find("=")
		if eq > 0:
			keep[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	if keep == s.get("props", {}):
		return
	_checkpoint()
	s["props"] = keep
	_rebuild()


## Keep goals and joints pointing at an object when it is renamed.
func _rename_id(old: String, new: String) -> void:
	if old == "" or old == new:
		return
	for g in level.goals:
		for k in g["props"]:
			if str(g["props"][k]) == old:
				g["props"][k] = new
	for s in level.predefined:
		for k in s.get("props", {}):
			var v := str(s["props"][k])
			if v == old or v.begins_with(old + "@"):
				s["props"][k] = new + v.substr(old.length())


func _ids() -> Array:
	var out := []
	for s in level.predefined:
		if s.get("id", "") != "":
			out.append(s["id"])
	return out


func _move_to_toolbox() -> void:
	if sel < 0:
		return
	_checkpoint()
	var s: Dictionary = level.predefined[sel].duplicate(true)
	level.predefined.remove_at(sel)
	s.erase("_ei")
	s.erase("id")
	s["x"] = 0.0
	s["y"] = 0.0
	# stack identical items into one toolbox entry
	for item in level.toolbox:
		var t: Dictionary = item["spec"]
		if t["type"] == s["type"] and is_equal_approx(float(t.get("w", 0)), float(s.get("w", 0))) \
				and is_equal_approx(float(t.get("h", 0)), float(s.get("h", 0))) and t.get("props", {}) == s.get("props", {}):
			item["count"] = int(item["count"]) + 1
			_after_toolbox_change()
			return
	level.toolbox.append({"spec": s, "count": 1})
	_after_toolbox_change()


func _after_toolbox_change() -> void:
	sel = -1
	_rebuild()
	_refresh_props()
	_refresh_toolbox()
	tabs.current_tab = 2
	_toast("Moved to the player's toolbox.")


# ========================================================== toolbox tab

func _refresh_toolbox() -> void:
	_clear(toolbox_list)
	toolbox_list.add_child(_label("What the player gets to place. Tip: build the solution in the scene first, then use \"Move to player's toolbox\" on each piece.", 12, true))
	for i in level.toolbox.size():
		var item: Dictionary = level.toolbox[i]
		var t: Dictionary = item["spec"]
		var d := Catalog.get_def(t["type"])
		var row := HBoxContainer.new()
		toolbox_list.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if d and not d.image_states().is_empty():
			icon.texture = Images.get_texture(d.image_states()[0], 64)
		row.add_child(icon)
		var name_l := _label("%s\n%.2f × %.2f m" % [d.display_name if d else t["type"], float(t.get("w", d.width if d else 0)), float(t.get("h", d.height if d else 0))], 12)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_l)
		var count := SpinBox.new()
		count.min_value = 1
		count.max_value = 99
		count.value = int(item["count"])
		count.value_changed.connect(_toolbox_set_count.bind(i))
		row.add_child(count)
		row.add_child(_button("↩", "Put one back into the scene (to adjust it)", _toolbox_to_scene.bind(i)))
		row.add_child(_button("✕", "Remove from toolbox", _toolbox_remove.bind(i)))
		var perm := HBoxContainer.new()
		toolbox_list.add_child(perm)
		var rot := CheckBox.new()
		rot.text = "player may rotate"
		rot.button_pressed = _toolbox_flag(t, "Rotatable", d.rotatable if d else false)
		rot.toggled.connect(_toolbox_set_rotatable.bind(i))
		perm.add_child(rot)
		var rs := OptionButton.new()
		for m in RESIZE_MODES:
			rs.add_item(m[1])
		var cur := str(TBE.prop(t.get("props", {}), "Resizable", d.resizable if d else "none")).strip_edges().to_lower()
		for k in RESIZE_MODES.size():
			if RESIZE_MODES[k][0] == cur:
				rs.selected = k
		rs.item_selected.connect(_toolbox_set_resizable.bind(i))
		rs.tooltip_text = "May the player resize it?"
		perm.add_child(rs)
		toolbox_list.add_child(HSeparator.new())
	toolbox_list.add_child(HSeparator.new())
	var add_row := HBoxContainer.new()
	toolbox_list.add_child(add_row)
	var pick := OptionButton.new()
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.fit_to_longest_item = false
	var types := Catalog.defs.keys()
	types.sort()
	for t in types:
		if not Catalog.get_def(t).no_collision:
			pick.add_item(t)
	add_row.add_child(pick)
	add_row.add_child(_button("+ Add", "Add this object type to the toolbox",
			func(): _toolbox_add(pick.get_item_text(pick.selected))))


const RESIZE_MODES := [["none", "fixed size"], ["horizontal", "resize: width"],
		["vertical", "resize: height"], ["totalresize", "resize: both"]]


func _toolbox_flag(spec: Dictionary, key: String, default: bool) -> bool:
	var v = TBE.prop(spec.get("props", {}), key)
	return default if v == null else str(v).strip_edges().to_lower() == "true"


func _toolbox_set_rotatable(on: bool, i: int) -> void:
	_checkpoint()
	var t: Dictionary = level.toolbox[i]["spec"]
	if not t.has("props"):
		t["props"] = {}
	t["props"]["Rotatable"] = "true" if on else "false"


func _toolbox_set_resizable(idx: int, i: int) -> void:
	_checkpoint()
	var t: Dictionary = level.toolbox[i]["spec"]
	if not t.has("props"):
		t["props"] = {}
	t["props"]["Resizable"] = RESIZE_MODES[idx][0]


func _toolbox_set_count(v: float, i: int) -> void:
	_checkpoint()
	level.toolbox[i]["count"] = int(v)


func _toolbox_add(type: String) -> void:
	var d := Catalog.get_def(type)
	if d == null:
		return
	_checkpoint()
	level.toolbox.append({"spec": {"type": type, "x": 0.0, "y": 0.0, "w": d.width, "h": d.height, "angle": 0.0, "props": {}}, "count": 1})
	_refresh_toolbox()


func _toolbox_remove(i: int) -> void:
	_checkpoint()
	level.toolbox.remove_at(i)
	_refresh_toolbox()


func _toolbox_to_scene(i: int) -> void:
	_checkpoint()
	var item: Dictionary = level.toolbox[i]
	var s: Dictionary = item["spec"].duplicate(true)
	s["x"] = level.scene_size.x * 0.5
	s["y"] = level.scene_size.y * 0.5
	level.predefined.append(s)
	item["count"] = int(item["count"]) - 1
	if item["count"] <= 0:
		level.toolbox.remove_at(i)
	sel = level.predefined.size() - 1
	_rebuild()
	_refresh_toolbox()
	_refresh_props()


# ============================================================ goals tab

const GOAL_KINDS := [
	# [label, type, condition key, needs value, needs object2]
	["is closer than … m to", "distance", "lessthan", true, true],
	["is farther than … m from", "distance", "morethan", true, true],
	["moves right of x =", "positionchange", "xover", true, false],
	["moves left of x =", "positionchange", "xbelow", true, false],
	["moves above y =", "positionchange", "yover", true, false],
	["moves below y =", "positionchange", "ybelow", true, false],
	["moves sideways at all", "positionchange", "xchanged", false, false],
	["moves up/down at all", "positionchange", "ychanged", false, false],
	["rotates at all", "positionchange", "anglechanged", false, false],
	["moves or rotates at all", "positionchange", "anythingchanged", false, false],
	["changes state (pops, explodes…)", "statechange", "statechanged", false, false],
]


func _goal_kind(g: Dictionary) -> int:
	for k in GOAL_KINDS.size():
		var gk: Array = GOAL_KINDS[k]
		if gk[1] == g["type"]:
			for key in g["props"]:
				if String(key).to_lower() == gk[2]:
					return k
	return -1


func _refresh_goals() -> void:
	_clear(goals_list)
	goals_list.add_child(_label("The player wins when all \"Win when\" goals are true at the same time. Any \"Lose when\" goal ends the level as a failure.", 12, true))
	var ids := _ids()
	if ids.is_empty():
		goals_list.add_child(_label("⚠ Give objects a Name (ID) in the Selected tab to use them in goals.", 13))
	for gi in level.goals.size():
		var g: Dictionary = level.goals[gi]
		var box := PanelContainer.new()
		goals_list.add_child(box)
		var v := VBoxContainer.new()
		box.add_child(v)
		var head := HBoxContainer.new()
		v.add_child(head)
		var fail := OptionButton.new()
		fail.add_item("Win when")
		fail.add_item("Lose when")
		fail.selected = 1 if g["is_fail"] else 0
		fail.item_selected.connect(func(idx): _goal_set_fail(idx == 1, g))
		fail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(fail)
		head.add_child(_button("✕", "Delete goal", _goal_delete.bind(gi)))
		var obj_key := "object1" if g["type"] == "distance" else "object"
		v.add_child(_id_picker(ids, str(TBE.prop(g["props"], obj_key, "")), func(id): _goal_set(g, obj_key, id)))
		var kind := OptionButton.new()
		for gk in GOAL_KINDS:
			kind.add_item(gk[0])
		var k := _goal_kind(g)
		kind.selected = k
		kind.item_selected.connect(func(idx): _goal_change_kind(g, idx))
		v.add_child(kind)
		if k >= 0 and GOAL_KINDS[k][3]:
			var val := LineEdit.new()
			val.placeholder_text = "value"
			val.text = str(TBE.prop(g["props"], GOAL_KINDS[k][2], ""))
			val.text_submitted.connect(func(t): _goal_set(g, GOAL_KINDS[k][2], t))
			val.focus_exited.connect(func(): _goal_set(g, GOAL_KINDS[k][2], val.text))
			v.add_child(val)
		if k >= 0 and GOAL_KINDS[k][4]:
			v.add_child(_id_picker(ids, str(TBE.prop(g["props"], "object2", "")), func(id): _goal_set(g, "object2", id)))
	goals_list.add_child(_button("+ Add goal", "", _goal_add))


func _id_picker(ids: Array, current: String, cb: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.add_item("(choose object)")
	for id in ids:
		ob.add_item(id)
		if id == current:
			ob.selected = ob.item_count - 1
	if current != "" and current not in ids:
		ob.add_item(current + " (missing!)")
		ob.selected = ob.item_count - 1
	ob.item_selected.connect(func(idx):
		if idx > 0:
			cb.call(ob.get_item_text(idx)))
	return ob


func _goal_set_fail(on: bool, g: Dictionary) -> void:
	_checkpoint()
	g["is_fail"] = on


func _goal_delete(gi: int) -> void:
	_checkpoint()
	level.goals.remove_at(gi)
	_refresh_goals()


func _goal_add() -> void:
	_checkpoint()
	var ids := _ids()
	var first: String = ids[0] if not ids.is_empty() else ""
	level.goals.append({"type": "positionchange", "is_fail": false, "props": {"object": first, "anythingchanged": ""}})
	_refresh_goals()


func _goal_set(g: Dictionary, key: String, value: String) -> void:
	if str(g["props"].get(key, "")) == value:
		return
	_checkpoint()
	g["props"][key] = value
	_refresh_goals.call_deferred()


func _goal_change_kind(g: Dictionary, idx: int) -> void:
	_checkpoint()
	var gk: Array = GOAL_KINDS[idx]
	var obj := str(TBE.prop(g["props"], "object", TBE.prop(g["props"], "object1", "")))
	var p := {}
	if gk[1] == "distance":
		p = {"object1": obj, "object2": str(TBE.prop(g["props"], "object2", "")), gk[2]: "0.3"}
	else:
		p = {"object": obj, gk[2]: "1.0" if gk[3] else ""}
	g["type"] = gk[1]
	g["props"] = p
	_refresh_goals.call_deferred()


# ========================================================= settings tab

func _refresh_settings() -> void:
	var box: VBoxContainer = tabs.get_node("Level/settings")
	_clear(box)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	_field(grid, "Title", level.title, func(v): _set_level("title", v))
	_field(grid, "Author", level.author, func(v): _set_level("author", v))
	_field(grid, "License", level.license, func(v): _set_level("license", v), "e.g. CC0 or GPL-2.0")
	_num_field(grid, "Width (m)", level.scene_size.x, func(v): _set_level("scene_size", Vector2(maxf(v, 0.5), level.scene_size.y)))
	_num_field(grid, "Height (m)", level.scene_size.y, func(v): _set_level("scene_size", Vector2(level.scene_size.x, maxf(v, 0.5))))
	box.add_child(_label("Description (shown when the level starts; <br> = new line):", 13))
	var te := TextEdit.new()
	te.text = level.description
	te.custom_minimum_size.y = 120
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.focus_exited.connect(func(): _set_level("description", te.text))
	box.add_child(te)
	box.add_child(_label("Sky colors (top → bottom):", 13))
	var row := HBoxContainer.new()
	box.add_child(row)
	var stops := level.background
	var top_c: Color = stops[0]["color"] if stops.size() > 0 else Color(0.72, 0.85, 1.0)
	var bot_c: Color = stops[-1]["color"] if stops.size() > 1 else Color(0.93, 0.97, 1.0)
	for pair in [[top_c, 0], [bot_c, 1]]:
		var cp := ColorPickerButton.new()
		cp.color = pair[0]
		cp.custom_minimum_size = Vector2(80, 32)
		cp.color_changed.connect(_set_sky.bind(pair[1]))
		row.add_child(cp)


func _set_level(key: String, value: Variant) -> void:
	if level.get(key) == value:
		return
	_checkpoint()
	level.set(key, value)
	if key == "scene_size":
		world.queue_redraw()
		_fit_camera()
	_update_title()


func _set_sky(c: Color, which: int) -> void:
	if level.background.size() < 2:
		level.background = [{"pos": 0.0, "color": Color(0.72, 0.85, 1.0)}, {"pos": 1.0, "color": Color(0.93, 0.97, 1.0)}]
	level.background[0 if which == 0 else -1]["color"] = c
	dirty = true
	world.queue_redraw()


# ===================================================== files & test play

func _clean_copy() -> LevelData:
	var l := level.clone()
	for s in l.predefined:
		s.erase("_ei")
	return l


func _save() -> void:
	if Levels.editor_path == "" or not Levels.is_user_level(Levels.editor_path):
		Levels.editor_path = _unique_path(Levels.user_path_for(level.title))
	var err := _clean_copy().save_file(Levels.editor_path)
	if err != OK:
		_toast("Could not save (error %d)" % err)
		return
	dirty = false
	Levels.reload()
	_update_title()
	_toast("Saved to My Levels — it's at the end of the level list.")


func _unique_path(p: String) -> String:
	if not FileAccess.file_exists(p):
		return p
	var base := p.get_basename()
	var n := 2
	while FileAccess.file_exists("%s_%d.xml" % [base, n]):
		n += 1
	return "%s_%d.xml" % [base, n]


func _test_play() -> void:
	if prepare_test():
		get_tree().change_scene_to_file("res://scenes/game.tscn")


## Writes the level to the test file and switches the game to test mode.
func prepare_test() -> bool:
	DirAccess.make_dir_recursive_absolute(Levels.USER_DIR)
	var err := _clean_copy().save_file(Levels.TEST_FILE)
	if err != OK:
		_toast("Could not prepare the test (error %d)" % err)
		return false
	Levels.editor_level = level
	Levels.testing = true
	return true


func _new_level() -> void:
	_confirm_discard(func():
		_undo.clear()
		_redo.clear()
		Levels.editor_path = ""
		dirty = false
		sel = -1
		level = LevelData.new_level()
		Levels.editor_level = level
		_rebuild()
		_fit_camera()
		_refresh_all())


func _open_dialog() -> void:
	_confirm_discard(_show_open_list)


func _show_open_list() -> void:
	var shade := _dialog_shell("Open a level")
	var v: VBoxContainer = shade.get_meta("content")
	v.add_child(_label("Built-in levels are copied into My Levels when you save.", 12, true))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(460, 420)
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for i in Levels.paths.size():
		var p: String = Levels.paths[i]
		var b := _button("%s%d. %s" % ["★ " if Levels.is_user_level(p) else "", i + 1, Levels.title_of(p)], p, _open_path.bind(p))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	v.add_child(_button("Cancel", "", _close_dialogs))


func _open_path(p: String) -> void:
	_close_dialogs()
	var l := LevelData.load_file(p)
	if l == null:
		_toast("Could not open " + p)
		return
	_undo.clear()
	_redo.clear()
	level = l
	Levels.editor_level = l
	Levels.editor_path = p if Levels.is_user_level(p) else ""
	dirty = false
	sel = -1
	_rebuild()
	_fit_camera()
	_refresh_all()


func _confirm_discard(then: Callable) -> void:
	if not dirty:
		then.call()
		return
	var shade := _dialog_shell("Discard unsaved changes?")
	var v: VBoxContainer = shade.get_meta("content")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	row.add_child(_button("Cancel", "", _close_dialogs))
	row.add_child(_button("Save first", "", _discard_then.bind(then, true)))
	row.add_child(_button("Discard", "", _discard_then.bind(then, false)))


func _discard_then(then: Callable, save_first: bool) -> void:
	_close_dialogs()
	if save_first:
		_save()
	then.call()


func _dialog_shell(title: String) -> Control:
	_close_dialogs()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.4)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(_label(title, 22))
	shade.set_meta("content", v)
	return shade


func _close_dialogs() -> void:
	_clear(dialog_layer)


func _go_menu() -> void:
	_confirm_discard(func():
		Levels.editor_level = null
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
