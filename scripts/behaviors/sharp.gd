extends ObjectBehavior
## Cactus, bed of nails, circular saw: pops balloons and hurts butterflies.
## Extra properties (set them in the ObjectDef):
##   "SharpAbove": only the part above this local height (meters, at the
##                 default size) is sharp, e.g. the nails, not the board.
##   "Spin": "true" makes it rotate (circular saw).


func is_sharp_at(at: Vector2) -> bool:
	var limit = body.props.get("SharpAbove")
	if limit == null:
		return true
	var local_m := TBE.to_m(body.to_local(at))
	return local_m.y / body.size_m.y >= float(limit) / body.def.height - 0.02


func physics_tick(_delta: float) -> void:
	if str(body.props.get("Spin", "")) == "true":
		body.angular_velocity = -12.0
