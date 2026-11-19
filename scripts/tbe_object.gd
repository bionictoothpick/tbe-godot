class_name TbeObject
extends RigidBody2D
## One object in a level, built from an ObjectDef plus a "spec" dictionary:
##   {type, id, x, y, w, h, angle, props: {}, tooltip}
## x/y/w/h are meters (Y up), angle is radians counter-clockwise.

signal changed

var def: ObjectDef
var spec: Dictionary
var props: Dictionary = {}
var size_m := Vector2.ONE          # meters
var obj_id := ""
var behavior: ObjectBehavior
var is_static := false
var player_placed := false
var toolbox_index := -1
## Current visual state (index into the def's image list). Goals can test it.
var state := 0
var start_center_m := Vector2.ZERO
var start_angle := 0.0
var overlapping := false
var selected := false
var dead := false
var simulating := false
# collision sounds (see _impact_sounds)
var _touching := {}
var _prev_v := Vector2.ZERO
var _hit_v0 := Vector2.ZERO
var _hit_wait := 0
var _hit_best := 0.0
var _hit_other := 0

var tooltip := ""
var _bouncy_mat: PhysicsMaterial
var _dead_mat: PhysicsMaterial

## Like Box2D (the original engine), impacts slower than this don't bounce,
## so objects settle instead of jittering and rolling away.
## (World._update_bounce applies it.)
const BOUNCE_THRESHOLD := 1.0   # m/s
var _tex_px := 256.0
var _tex_scale := 1.0


func setup(a_def: ObjectDef, a_spec: Dictionary) -> void:
	def = a_def
	spec = a_spec
	props = def.extra.duplicate()
	props.merge(a_spec.get("props", {}), true)
	obj_id = a_spec.get("id", "")
	name = obj_id if obj_id != "" else def.type_name
	var w: float = a_spec.get("w", def.width)
	var h: float = a_spec.get("h", def.height)
	if def.shape == ObjectDef.Shape.CIRCLE and TBE.prop(props, "Radius") != null:
		w = float(TBE.prop(props, "Radius")) * 2.0
		h = w
	size_m = Vector2(w, h)
	position = TBE.to_px(Vector2(a_spec.get("x", 0.0), a_spec.get("y", 0.0)))
	rotation = -float(a_spec.get("angle", 0.0))
	start_center_m = TBE.to_m(position)
	start_angle = -rotation

	var m: float = def.mass
	if TBE.prop(props, "Mass") != null and str(TBE.prop(props, "Mass")) != "":
		m = float(TBE.prop(props, "Mass"))
	is_static = m <= 0.0
	mass = maxf(m, 0.001)

	var mat := PhysicsMaterial.new()
	mat.bounce = float(TBE.prop(props, "Bounciness", def.bounciness))
	# Box2D (the original engine) uses the larger bounciness of two touching
	# objects; Godot adds them. Fixed objects are usually the less bouncy
	# partner, so zero theirs to get roughly the original behavior.
	if is_static and mat.bounce < 0.5:
		mat.bounce = 0.0
	mat.friction = float(TBE.prop(props, "Friction", def.friction))
	physics_material_override = mat
	_bouncy_mat = mat
	_dead_mat = mat.duplicate()
	_dead_mat.bounce = 0.0

	var z := float(TBE.prop(props, "ZValue", def.z_value))
	z_index = int(round(z * 10.0))
	var no_coll: bool = def.no_collision or str(TBE.prop(props, "NoCollision", "")).to_lower() == "true"
	collision_layer = 0 if no_coll else TBE.LAYER_SOLID
	collision_mask = 0 if no_coll else TBE.LAYER_SOLID
	contact_monitor = true
	max_contacts_reported = 8
	# While the player arranges things, objects are frozen in STATIC mode so
	# they can be moved freely. (KINEMATIC mode made dragged objects lag and
	# jump, because physics kept writing an older position back.)
	# Continuous collision detection is only switched on when Play starts:
	# STATIC freezing plus CCD made bodies jump when unfrozen (Godot 4.7).
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	continuous_cd = RigidBody2D.CCD_MODE_DISABLED
	freeze = true
	input_pickable = false
	_build_shapes()

	tooltip = a_spec.get("tooltip", "")
	if tooltip == "":
		tooltip = def.display_name + ("\n" + def.tooltip if def.tooltip != "" else "")

	if def.behavior:
		behavior = def.behavior.new()
		behavior.body = self


func attach(world: Node) -> void:
	if behavior:
		behavior.world = world
		behavior.setup()
	queue_redraw()


func _build_shapes() -> void:
	for c in get_children():
		if c is CollisionShape2D:
			remove_child(c)
			c.queue_free()
	var px := size_m * TBE.PPM
	match def.shape:
		ObjectDef.Shape.RECT:
			var s := RectangleShape2D.new()
			s.size = px
			_add_shape(s)
		ObjectDef.Shape.CIRCLE:
			var c := CircleShape2D.new()
			c.radius = px.x * 0.5
			_add_shape(c)
		ObjectDef.Shape.POLYGON:
			var polys: Array = def.polygons
			var custom = TBE.prop(props, "Polygons")
			if custom != null:
				polys = parse_polygons(str(custom))
			var sc := Vector2(size_m.x / maxf(def.width, 0.0001), size_m.y / maxf(def.height, 0.0001))
			if custom != null:
				# like the original: fit the outline's bounding box to the object size
				var box := polygon_bounds(str(custom))
				sc = Vector2(size_m.x / maxf(box.x, 0.0001), size_m.y / maxf(box.y, 0.0001))
			for poly: PackedVector2Array in polys:
				var pts := PackedVector2Array()
				for p in poly:
					pts.append(TBE.to_px(p * sc))
				var cp := ConvexPolygonShape2D.new()
				cp.set_point_cloud(pts)
				_add_shape(cp)
		ObjectDef.Shape.NONE:
			# decorations still need a pick area for clicking/tooltips, but no physics
			var s := RectangleShape2D.new()
			s.size = px
			_add_shape(s)


## Box2D (the original engine) gives every polygon a 1 cm "skin", so fixed
## objects reach slightly past their drawn edges. Levels were designed with
## that (e.g. a pin standing right on the edge of a floor), so fixed shapes
## get the same skin here.
const SKIN := 0.01   # meters


func _add_shape(s: Shape2D) -> void:
	if is_static and collision_layer != 0:
		var skin := SKIN * TBE.PPM
		if s is RectangleShape2D:
			s.size += Vector2(skin, skin) * 2.0
		elif s is CircleShape2D:
			s.radius += skin
		elif s is ConvexPolygonShape2D:
			var grown := Geometry2D.offset_polygon(s.points, skin, Geometry2D.JOIN_MITER)
			if not grown.is_empty():
				s.set_point_cloud(grown[0])
	var cs := CollisionShape2D.new()
	cs.shape = s
	add_child(cs)


static func polygon_bounds(text: String) -> Vector2:
	var re := RegEx.create_from_string("\\(\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*\\)")
	var r := Rect2()
	var first := true
	for m in re.search_all(text):
		var p := Vector2(m.get_string(1).to_float(), m.get_string(2).to_float())
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	return r.size


static func parse_polygons(text: String) -> Array:
	var out: Array = []
	for part in text.split(";", false):
		var pts := PackedVector2Array()
		var re := RegEx.create_from_string("\\(\\s*([-\\d.]+)\\s*,\\s*([-\\d.]+)\\s*\\)")
		for m in re.search_all(part):
			pts.append(Vector2(m.get_string(1).to_float(), m.get_string(2).to_float()))
		if pts.size() >= 3:
			out.append(pts)
	return out


# ---------------------------------------------------------------- simulation

func set_simulating(on: bool) -> void:
	simulating = on
	freeze = (not on) or is_static
	if not on:
		continuous_cd = RigidBody2D.CCD_MODE_DISABLED
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	else:
		if not is_static:
			continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		if behavior:
			behavior.on_play_start()


func _physics_process(delta: float) -> void:
	if not simulating:
		return
	if behavior:
		behavior.physics_tick(delta)


func _integrate_forces(st: PhysicsDirectBodyState2D) -> void:
	if not simulating:
		return
	_impact_sounds(st)
	if behavior == null:
		return
	for i in st.get_contact_count():
		var imp := st.get_contact_impulse(i).length() / TBE.PPM
		behavior.on_impact(imp, st.get_contact_collider_object(i), st.get_contact_collider_position(i))


## Plays a collision sound when a new contact appears. How hard the hit was
## is measured by how much this object's velocity changed over the next two
## steps (Godot reports no impulse on the step a bounce happens).
func _impact_sounds(st: PhysicsDirectBodyState2D) -> void:
	var now := {}
	for i in st.get_contact_count():
		var id := st.get_contact_collider_id(i)
		now[id] = true
		if not _touching.has(id) and _hit_wait == 0:
			_hit_wait = 2
			_hit_v0 = _prev_v
			_hit_other = id
			_hit_best = 0.0
	_touching = now
	_prev_v = st.linear_velocity
	if _hit_wait > 0:
		_hit_best = maxf(_hit_best, (st.linear_velocity - _hit_v0).length() / TBE.PPM)
		_hit_wait -= 1
		if _hit_wait == 0:
			Sfx.impact(self, _hit_best, _hit_other)


## True if `other` is a sharp object at point `at`.
static func is_sharp_contact(other: Object, at: Vector2) -> bool:
	return other is TbeObject and other.behavior != null and other.behavior.is_sharp_at(at)


## May the player rotate this toolbox item? (level "Rotatable" property)
func can_rotate() -> bool:
	var v = TBE.prop(props, "Rotatable")
	return def.rotatable if v == null else str(v).strip_edges().to_lower() == "true"


## How the player may resize it: "none", "horizontal", "vertical", "totalresize".
func resize_mode() -> String:
	var v = TBE.prop(props, "Resizable")
	var r := def.resizable if v == null else str(v).strip_edges().to_lower()
	return r if r in ["horizontal", "vertical", "totalresize"] else "none"


## Bounciness on or off (see World._update_bounce).
func set_bouncy(on: bool) -> void:
	var want := _bouncy_mat if on else _dead_mat
	if physics_material_override != want:
		physics_material_override = want


## Speed in m/s, counting spin at the rim.
func speed_mps() -> float:
	return linear_velocity.length() / TBE.PPM + absf(angular_velocity) * maxf(size_m.x, size_m.y) * 0.5


func can_bounce() -> bool:
	return not is_static and _bouncy_mat != null and _bouncy_mat.bounce > 0.0


func center_m() -> Vector2:
	return TBE.to_m(global_position)


func angle_m() -> float:
	return -global_rotation


func set_state(s: int) -> void:
	if state != s:
		state = s
		queue_redraw()
		changed.emit()


func current_image() -> String:
	var states := def.image_states()
	var custom = TBE.prop(props, "ImageName")
	if custom != null and str(custom) != "":
		states = str(custom).split(";", false)
	if states.is_empty():
		return ""
	return states[clampi(state, 0, states.size() - 1)]


## Current spec (position, angle and size as they are now).
func to_spec() -> Dictionary:
	var s := spec.duplicate(true)
	var c := TBE.to_m(position)
	s["x"] = snappedf(c.x, 0.001)
	s["y"] = snappedf(c.y, 0.001)
	s["angle"] = snappedf(-rotation, 0.0001)
	s["w"] = snappedf(size_m.x, 0.001)
	s["h"] = snappedf(size_m.y, 0.001)
	return s


func set_size_m(new_size: Vector2) -> void:
	size_m = Vector2(maxf(new_size.x, 0.02), maxf(new_size.y, 0.02))
	_build_shapes()
	queue_redraw()


# ------------------------------------------------------------------- drawing

func set_texture_detail(px_per_m_on_screen: float) -> void:
	var want := maxf(size_m.x, size_m.y) * px_per_m_on_screen * 1.25
	var sc: float = Images.screen_scale()
	if absf(want - _tex_px) > _tex_px * 0.4 or absf(sc - _tex_scale) > _tex_scale * 0.25:
		_tex_px = want
		_tex_scale = sc
		queue_redraw()


func _draw() -> void:
	var px := size_m * TBE.PPM
	var rect := Rect2(-px * 0.5, px)
	var img := current_image()
	if img == "Empty":
		pass
	elif img.begins_with("#"):
		draw_rect(rect, Color.html(img))
	else:
		var tex := Images.get_texture(img, _tex_px)
		if tex:
			_draw_texture_fitted(tex, rect)
		else:
			_draw_fallback(rect)
	if overlapping:
		_draw_outline(Color(1, 0.15, 0.1, 0.9), 3.0)
	elif selected:
		_draw_outline(Color(1, 0.85, 0.2, 0.95), 2.0)


func _draw_texture_fitted(tex: Texture2D, rect: Rect2) -> void:
	var ts := tex.get_size()
	var tex_aspect := ts.x / maxf(ts.y, 1.0)
	var rect_aspect := rect.size.x / maxf(rect.size.y, 0.001)
	var is_raster: bool = not Images._paths.get(current_image(), "").ends_with(".svg")
	if is_raster and (rect_aspect > tex_aspect * 2.5 or rect_aspect < tex_aspect / 2.5):
		# long floors/walls: tile the texture instead of stretching it
		var s := minf(rect.size.x, rect.size.y) / minf(ts.x, ts.y)
		draw_set_transform(rect.position, 0.0, Vector2(s, s))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, rect.size / s), true)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(tex, rect, false)


func _draw_fallback(rect: Rect2) -> void:
	var col := Color(0.55, 0.45, 0.35) if is_static else Color(0.35, 0.55, 0.85)
	match def.shape:
		ObjectDef.Shape.CIRCLE:
			draw_circle(Vector2.ZERO, rect.size.x * 0.5, col)
		_:
			for c in get_children():
				if c is CollisionShape2D and c.shape is ConvexPolygonShape2D:
					draw_colored_polygon(c.shape.points, col)
				elif c is CollisionShape2D and c.shape is RectangleShape2D:
					draw_rect(rect, col)


func _draw_outline(col: Color, width: float) -> void:
	for c in get_children():
		if not c is CollisionShape2D:
			continue
		var s: Shape2D = c.shape
		if s is RectangleShape2D:
			draw_rect(Rect2(-s.size * 0.5, s.size), col, false, width)
		elif s is CircleShape2D:
			draw_arc(Vector2.ZERO, s.radius, 0, TAU, 32, col, width)
		elif s is ConvexPolygonShape2D:
			var pts: PackedVector2Array = s.points.duplicate()
			pts.append(pts[0])
			draw_polyline(pts, col, width)


## True if a global (pixel) point is inside this object.
## True if a global (pixel) point is on this object's picture (its full
## width x height box). Thin shapes such as ramps are much easier to grab
## this way than by their collision outline.
func picture_contains_global_point(p: Vector2) -> bool:
	var half := size_m * TBE.PPM * 0.5
	return Rect2(-half, half * 2.0).grow(3).has_point(to_local(p))


func contains_global_point(p: Vector2) -> bool:
	var local := to_local(p)
	for c in get_children():
		if not c is CollisionShape2D:
			continue
		var s: Shape2D = c.shape
		if s is RectangleShape2D and Rect2(-s.size * 0.5, s.size).grow(4).has_point(local):
			return true
		if s is CircleShape2D and local.length() <= s.radius + 4:
			return true
		if s is ConvexPolygonShape2D and Geometry2D.is_point_in_polygon(local, s.points):
			return true
	return false
