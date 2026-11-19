class_name World
extends Node2D
## Builds a level's objects, runs the simulation and checks the goals.

signal won
signal failed(reason: String)
signal note_requested(pages: Array, kind: String)

## Types that connect other objects instead of being objects themselves.
const JOINT_TYPES := ["PivotPoint", "Link", "Glue", "TranslationGuide"]

var level: LevelData
var objects: Array[TbeObject] = []
var by_id := {}
var unsupported := {}         # type -> count
var simulating := false
var sim_time := 0.0
var finished := false
var ground: StaticBody2D

var _joint_specs: Array = []
var _overlap_dirty := true


func build(a_level: LevelData, player_specs: Array) -> void:
	level = a_level
	clear()
	ground = StaticBody2D.new()
	ground.name = "Ground"
	# like the original game: an invisible solid ground below y = 0
	ground.collision_layer = TBE.LAYER_SOLID
	ground.collision_mask = TBE.LAYER_SOLID
	var gs := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(100.0, 2.0) * TBE.PPM
	gs.shape = box
	gs.position = TBE.to_px(Vector2(50.01, -1.0))
	ground.add_child(gs)
	var gm := PhysicsMaterial.new()
	gm.friction = 0.3
	gm.bounce = 0.0
	ground.physics_material_override = gm
	add_child(ground)
	for s in level.predefined:
		_create(s, false, -1)
	for ps in player_specs:
		_create(ps["spec"], true, ps["toolbox_index"])
	for js in _joint_specs:
		_create_joint(js)
	for o in objects:
		o.attach(self)
	queue_redraw()
	_overlap_dirty = true


func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	objects.clear()
	by_id.clear()
	unsupported.clear()
	_joint_specs.clear()
	simulating = false
	finished = false
	sim_time = 0.0


func _create(s: Dictionary, player: bool, tb_index: int) -> TbeObject:
	var type: String = s.get("type", "")
	if type in JOINT_TYPES:
		_joint_specs.append(s)
		return null
	var d := Catalog.get_def(type)
	if d == null:
		unsupported[type] = unsupported.get(type, 0) + 1
		d = _placeholder_def(type)
	var o := TbeObject.new()
	o.setup(d, s)
	o.player_placed = player
	o.toolbox_index = tb_index
	add_child(o)
	objects.append(o)
	if o.obj_id != "":
		by_id[o.obj_id] = o
	var pivot_prop := str(TBE.prop(o.props, "PivotPoint", "")).strip_edges()
	if pivot_prop != "" and pivot_prop.contains("("):
		# level files can pin any object: PivotPoint = (x, y) in object coordinates
		var nums := pivot_prop.replace("(", "").replace(")", "").split(",")
		if nums.size() >= 2:
			_pin(o, null, o.to_global(TBE.to_px(Vector2(nums[0].to_float(), nums[1].to_float()))))
	elif d.has_pivot:
		var sc := Vector2(o.size_m.x / maxf(d.width, 0.0001), o.size_m.y / maxf(d.height, 0.0001))
		_pin(o, null, o.to_global(TBE.to_px(d.pivot * sc)))
	var guide = TBE.prop(o.props, "TranslationGuide")
	if guide != null and str(guide).strip_edges() != "":
		_rail(o, float(guide))
	o.changed.connect(func(): _overlap_dirty = true)
	return o


## Adds a player object while editing.
func add_player_object(s: Dictionary, tb_index: int) -> TbeObject:
	var o := _create(s, true, tb_index)
	if o:
		o.attach(self)
	_overlap_dirty = true
	return o


func remove_object(o: TbeObject) -> void:
	objects.erase(o)
	if o.obj_id != "":
		by_id.erase(o.obj_id)
	remove_child(o)
	o.queue_free()
	_overlap_dirty = true


func mark_dirty() -> void:
	_overlap_dirty = true


func player_specs() -> Array:
	var out: Array = []
	for o in objects:
		if o.player_placed:
			out.append({"spec": o.to_spec(), "toolbox_index": o.toolbox_index})
	return out


func _placeholder_def(type: String) -> ObjectDef:
	var d := ObjectDef.new()
	d.type_name = type
	d.display_name = type + " (not available yet)"
	d.image = "NotFound"
	d.shape = ObjectDef.Shape.RECT
	d.width = 0.3
	d.height = 0.3
	return d


# -------------------------------------------------------------------- joints

func _anchor(text: String) -> Array:
	## -> [body or null, global px point or null]
	var a := TBE.parse_anchor(text)
	var o: TbeObject = by_id.get(a[0])
	if o == null:
		return [null, null]
	return [o, o.to_global(TBE.to_px(a[1]))]


func _create_joint(s: Dictionary) -> void:
	var p: Dictionary = s.get("props", {})
	var type: String = s["type"]
	var here := TBE.to_px(Vector2(s.get("x", 0.0), s.get("y", 0.0)))
	var a1 := _anchor(str(TBE.prop(p, "object1", TBE.prop(p, "object", ""))))
	var a2 := _anchor(str(TBE.prop(p, "object2", "")))
	if a1[0] == null:
		if str(TBE.prop(p, "object1", "")) != "":
			push_warning("%s: object '%s' not found" % [type, TBE.prop(p, "object1", "")])
		return
	match type:
		"PivotPoint":
			var at: Vector2 = a1[1] if str(TBE.prop(p, "object1", "")).contains("@") else here
			var j := _pin(a1[0], a2[0], at)
			j.disable_collision = str(TBE.prop(p, "collide", "false")).strip_edges() != "true"
			var speed = TBE.prop(p, "Speed")
			if speed != null and str(speed).strip_edges() != "":
				# a motor: turns object1 at Speed rad/s (positive = clockwise, like the original)
				j.motor_enabled = true
				j.motor_target_velocity = float(speed)
		"Glue":
			var j := _pin(a1[0], a2[0], a1[1])
			j.angular_limit_enabled = true
			j.angular_limit_lower = 0.0
			j.angular_limit_upper = 0.0
		"Link":
			if a2[0] == null:
				return
			_link(a1[0], a1[1], a2[0], a2[1], str(TBE.prop(p, "ImageName", "#604020")))
		_:
			unsupported[type] = unsupported.get(type, 0) + 1


## Box2D ignores bounciness for impacts slower than 1 m/s, so resting things
## settle. Godot has no such rule, so each frame a moving object only keeps
## its bounciness when something is about to hit something at more than that
## speed: either it moves fast itself, or a fast object is coming at it (a
## resting volleyball hit by a bowling ball must still bounce away).
func _update_bounce(delta: float) -> void:
	var fast: Array[TbeObject] = []
	for o in objects:
		if o.speed_mps() > TbeObject.BOUNCE_THRESHOLD:
			fast.append(o)
	for o in objects:
		if not o.can_bounce():
			continue
		var on := o.speed_mps() > TbeObject.BOUNCE_THRESHOLD
		if not on:
			var ro := maxf(o.size_m.x, o.size_m.y) * 0.5
			for f in fast:
				if f == o:
					continue
				var rel_v := (f.linear_velocity - o.linear_velocity) / TBE.PPM      # m/s
				var to_o := (o.global_position - f.global_position) / TBE.PPM       # m
				var reach := ro + maxf(f.size_m.x, f.size_m.y) * 0.5 + rel_v.length() * delta * 4.0 + 0.05
				if to_o.length() < reach and rel_v.dot(to_o.normalized()) > TbeObject.BOUNCE_THRESHOLD:
					on = true
					break
		o.set_bouncy(on)


## Lets `o` only slide along a straight line at `angle` (radians, 0 = right),
## without rotating, like the original's TranslationGuide.
func _rail(o: TbeObject, angle: float) -> void:
	var dir := Vector2(cos(angle), -sin(angle))          # pixels, y down
	var length := 100.0 * TBE.PPM
	var g := GrooveJoint2D.new()
	g.length = length
	g.initial_offset = length * 0.5
	g.rotation = atan2(-dir.x, dir.y)                    # the groove runs along local +Y
	g.position = o.global_position - dir * length * 0.5
	add_child(g)
	g.node_a = g.get_path_to(ground)
	g.node_b = g.get_path_to(o)
	g.disable_collision = true
	o.lock_rotation = true


func _pin(a: PhysicsBody2D, b: PhysicsBody2D, at: Vector2) -> PinJoint2D:
	var j := PinJoint2D.new()
	j.position = at
	j.softness = 0.0
	add_child(j)
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b if b else ground)
	j.disable_collision = true
	return j


## Removes every joint attached to `body` (e.g. a popped balloon lets go).
func detach_joints(body: PhysicsBody2D) -> void:
	for c in get_children():
		if c is Joint2D and (c.get_node_or_null(c.node_a) == body or c.get_node_or_null(c.node_b) == body):
			c.queue_free()


func _link(a: PhysicsBody2D, pa: Vector2, b: PhysicsBody2D, pb: Vector2, color: String) -> void:
	var bar := LinkBar.new()
	bar.setup(pa, pb, Color.html(color) if color.begins_with("#") else Color(0.4, 0.25, 0.1))
	add_child(bar)
	_pin(a, bar, pa)
	_pin(b, bar, pb)
	bar.add_to_group("links")


# ---------------------------------------------------------------- simulation

func start() -> void:
	simulating = true
	finished = false
	sim_time = 0.0
	for o in objects:
		o.set_simulating(true)
	for l in get_tree().get_nodes_in_group("links"):
		l.freeze = false


func _physics_process(delta: float) -> void:
	if simulating:
		sim_time += delta
		_update_bounce(delta)
		if not finished and sim_time > 0.1:
			_check_goals()
	elif _overlap_dirty:
		_overlap_dirty = false
		_update_overlaps()


func object_died(o: TbeObject, reason: String) -> void:
	if simulating and not finished:
		finished = true
		failed.emit(reason if reason != "" else "%s didn't make it." % o.def.display_name)


func _check_goals() -> void:
	if level.goals.is_empty():
		return
	var all_met := true
	for g in level.goals:
		var met := _goal_met(g)
		if g["is_fail"]:
			if met:
				finished = true
				failed.emit("A fail condition was triggered.")
				return
		elif not met:
			all_met = false
	if all_met:
		finished = true
		won.emit()


func _goal_met(g: Dictionary) -> bool:
	var p: Dictionary = g["props"]
	match g["type"]:
		"distance":
			var a: TbeObject = by_id.get(TBE.prop(p, "object1", ""))
			var b: TbeObject = by_id.get(TBE.prop(p, "object2", ""))
			if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
				return false
			var d := a.center_m().distance_to(b.center_m())
			if TBE.prop(p, "lessthan") != null:
				return d < float(TBE.prop(p, "lessthan"))
			if TBE.prop(p, "morethan") != null:
				return d > float(TBE.prop(p, "morethan"))
		"positionchange":
			var o: TbeObject = by_id.get(TBE.prop(p, "object", ""))
			if o == null or not is_instance_valid(o) or not o.is_inside_tree():
				return false
			var c := o.center_m()
			for k in p:
				var v = p[k]
				match String(k).to_lower():
					# a millimeter of slack, so an object that starts exactly on
					# the line doesn't count as having crossed it
					"xover": return c.x > float(v) + 0.001
					"xbelow": return c.x < float(v) - 0.001
					"yover": return c.y > float(v) + 0.001
					"ybelow": return c.y < float(v) - 0.001
					"xchanged": return absf(c.x - o.start_center_m.x) > 0.02
					"ychanged": return absf(c.y - o.start_center_m.y) > 0.02
					"anglechanged": return absf(angle_difference(o.angle_m(), o.start_angle)) > 0.05
					"anythingchanged":
						return c.distance_to(o.start_center_m) > 0.02 or absf(angle_difference(o.angle_m(), o.start_angle)) > 0.05
		"statechange":
			var o: TbeObject = by_id.get(TBE.prop(p, "object", ""))
			if o == null or not is_instance_valid(o):
				return false
			if TBE.prop(p, "morethan") != null:
				return o.state > int(float(TBE.prop(p, "morethan")))
			return o.state != 0
	return false


## Radial blast. `radius` in meters, `strength` impulse in N·s at the center.
func explode(center_px: Vector2, radius: float, strength: float, source: Node = null) -> void:
	for o: TbeObject in objects.duplicate():
		if o == source or not is_instance_valid(o):
			continue
		var off := o.global_position - center_px
		var dist := off.length() / TBE.PPM
		if dist > radius:
			continue
		var s := strength * (1.0 - dist / radius)
		if o.behavior:
			o.behavior.on_explosion(s)
		if not o.is_static and is_instance_valid(o):
			o.apply_central_impulse(off.normalized() * s * TBE.PPM)


## The detonator box "phones" the dynamite with matching ID.
func ring_phone(number: String) -> void:
	var o: TbeObject = by_id.get(number)
	if o and o.behavior and o.behavior.has_method("ring"):
		o.behavior.ring()


# ------------------------------------------------------------------- editing

## The object under a point: first by exact outline, then (if nothing was hit)
## by picture box, so thin things like ramps can be grabbed anywhere on
## their image.
func pick(global_px: Vector2, player_only: bool) -> TbeObject:
	for exact in [true, false]:
		var best: TbeObject = null
		for o in objects:
			if player_only and not o.player_placed:
				continue
			var hit := o.contains_global_point(global_px) if exact else o.picture_contains_global_point(global_px)
			if hit and (best == null or o.z_index >= best.z_index):
				best = o
		if best:
			return best
	return null


func any_overlap() -> bool:
	for o in objects:
		if o.overlapping:
			return true
	return false


func _update_overlaps() -> void:
	var space := get_world_2d().direct_space_state
	for o in objects:
		var was := o.overlapping
		o.overlapping = o.player_placed and o.collision_layer != 0 and _overlaps(space, o)
		if was != o.overlapping:
			o.queue_redraw()


func _overlaps(space: PhysicsDirectSpaceState2D, o: TbeObject) -> bool:
	for c in o.get_children():
		if not c is CollisionShape2D:
			continue
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = c.shape
		q.transform = c.global_transform
		q.collision_mask = TBE.LAYER_SOLID
		q.exclude = [o.get_rid()]
		var pts := space.collide_shape(q, 16)
		for i in range(0, pts.size() - 1, 2):
			# fixed objects carry a 1 cm skin each (see TbeObject.SKIN), so allow
			# 2 cm for that plus a little slack before calling it an overlap
			if pts[i].distance_to(pts[i + 1]) > (2.0 * TbeObject.SKIN + 0.01) * TBE.PPM:
				return true
	return false


func _draw() -> void:
	if level == null:
		return
	var size_px := level.scene_size * TBE.PPM
	var rect := Rect2(Vector2(0, -size_px.y), size_px)
	var stops := level.background
	if stops.is_empty():
		stops = [{"pos": 0.0, "color": Color(0.72, 0.85, 1.0)}, {"pos": 1.0, "color": Color(0.93, 0.97, 1.0)}]
	var cols := PackedColorArray()
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(rect.position.x, rect.position.y + t * rect.size.y))
		cols.append(_grad(stops, t))
	for i in n:
		var quad := PackedVector2Array([pts[i], pts[i] + Vector2(rect.size.x, 0), pts[i + 1] + Vector2(rect.size.x, 0), pts[i + 1]])
		draw_polygon(quad, PackedColorArray([cols[i], cols[i], cols[i + 1], cols[i + 1]]))
	draw_rect(rect, Color(0, 0, 0, 0.35), false, 2.0)


static func _grad(stops: Array, t: float) -> Color:
	if t <= stops[0]["pos"]:
		return stops[0]["color"]
	for i in range(1, stops.size()):
		if t <= stops[i]["pos"]:
			var a = stops[i - 1]
			var b = stops[i]
			return a["color"].lerp(b["color"], (t - a["pos"]) / maxf(0.0001, b["pos"] - a["pos"]))
	return stops[-1]["color"]
