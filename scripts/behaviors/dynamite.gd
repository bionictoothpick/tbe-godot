extends ObjectBehavior
## Dynamite: explodes shortly after its detonator box "calls" it
## (the detonator's PhoneNumber must match this dynamite's ID).

enum { IDLE, RINGING, ACTIVE, BOOM, GONE }

var _timer := 0.0


func ring() -> void:
	if body.state == IDLE:
		body.set_state(RINGING)
		_timer = 0.2


func on_explosion(_s: float) -> void:
	if body.state == IDLE:
		body.set_state(ACTIVE)
		_timer = 0.05


func physics_tick(delta: float) -> void:
	if body.state in [IDLE, GONE]:
		return
	_timer -= delta
	if _timer > 0:
		return
	match body.state:
		RINGING:
			body.set_state(ACTIVE)
			_timer = 0.1
		ACTIVE:
			_explode()
		BOOM:
			body.set_state(GONE)
			body.visible = false


func _explode() -> void:
	body.set_state(BOOM)
	_timer = 0.4
	body.collision_layer = 0
	body.collision_mask = 0
	body.freeze = true
	var center := body.global_position
	# like the original: debris flying out in all directions at 20 m/s
	var n := 13
	for i in n:
		var a := TAU * i / n
		Droplet.spawn(world, center + Vector2.from_angle(a) * 12.0, Vector2.from_angle(a) * 20.0,
				0.8 / n, Color(0.25, 0.2, 0.15), 0.5)
	world.explode(center, 1.2, 1.5, body)
