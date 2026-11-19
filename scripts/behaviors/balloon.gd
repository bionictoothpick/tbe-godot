extends ObjectBehavior
## Helium balloon: floats up, pops on sharp objects or when squashed.

enum { FLOATING, POPPING, POPPED, GONE }

var _timer := 0.0


func setup() -> void:
	body.linear_damp = 0.6
	body.angular_damp = 0.4


func physics_tick(delta: float) -> void:
	match body.state:
		FLOATING:
			# lift slightly more than its weight, applied above the center
			# so the balloon stays upright
			var lift := body.mass * 9.81 * 1.12
			body.apply_force(TBE.to_px(Vector2(0, lift)), Vector2(0, -0.1 * TBE.PPM).rotated(body.rotation))
		POPPING:
			_timer -= delta
			if _timer <= 0:
				body.set_state(POPPED)
				_timer = 1.2
		POPPED:
			_timer -= delta
			if _timer <= 0:
				body.set_state(GONE)
				body.visible = false
				body.freeze = true


func on_impact(impulse: float, other: Node, at: Vector2) -> void:
	if body.state != FLOATING:
		return
	var sharp := TbeObject.is_sharp_contact(other, at)
	if sharp or impulse > 1.8:
		pop()


func on_explosion(_s: float) -> void:
	pop()


func pop() -> void:
	if body.state != FLOATING:
		return
	body.set_state(POPPING)
	Sfx.play("pop")
	_timer = 0.3
	# the rubber remains are tiny and don't block anything anymore
	body.collision_layer = 0
	body.collision_mask = 0
	world.detach_joints(body)
