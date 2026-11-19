extends ObjectBehavior
## Detonator box: when something pushes its handle down, it rings the dynamite
## whose ID matches this box's PhoneNumber property.

enum { ARMED, ACTIVATED, RINGING, DONE }

var _timer := 0.0


func on_impact(impulse: float, other: Node, _at: Vector2) -> void:
	if body.state != ARMED or not (other is PhysicsBody2D):
		return
	# only pushes on the handle (the top side of the box) count
	var local: Vector2 = body.to_local(other.global_position)
	if local.y < -body.size_m.y * 0.25 * TBE.PPM and impulse > 0.05:
		body.set_state(ACTIVATED)
		_timer = 0.5


func physics_tick(delta: float) -> void:
	if body.state in [ARMED, DONE]:
		return
	_timer -= delta
	if _timer > 0:
		return
	if body.state == ACTIVATED:
		body.set_state(RINGING)
		Sfx.play("ring", 0.7)
		_timer = 0.5
		world.ring_phone(str(TBE.prop(body.props, "PhoneNumber", "")))
	elif body.state == RINGING:
		body.set_state(DONE)
