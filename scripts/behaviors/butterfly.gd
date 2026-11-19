extends ObjectBehavior
## Flies towards the object named in its "object" property (usually a flower).
## Very fragile: a hard bump kills it, and so does anything sharp.

enum { STILL, OPEN, HALF, DEAD }

var target_m := Vector2.ZERO
var _countdown := 1

const FLY_SPEED := 0.12  # m/s, like the original (it is a slow flier)
const BOB_HEIGHT := 0.05  # m
const BOB_PERIOD := 0.9   # s
var _t := 0.0


func setup() -> void:
	body.angular_damp = 0.8
	body.set_state(OPEN)


func on_play_start() -> void:
	var t_id := str(TBE.prop(body.props, "object", ""))
	var t: TbeObject = world.by_id.get(t_id)
	target_m = t.start_center_m if t else body.start_center_m
	_countdown = 1
	_t = 0.0


func physics_tick(_delta: float) -> void:
	if body.state == DEAD:
		return
	# Steer gently towards the target: lift against gravity plus a soft
	# correction towards the wanted speed. (The original per-flap impulse
	# formula oscillated wildly in Godot's solver.)
	var c := body.center_m()
	var v := TBE.to_m(body.linear_velocity)      # m/s, y up
	# like the original, it bobs up and down as it flaps
	_t += _delta
	var bob := BOB_HEIGHT * sin(TAU * _t / BOB_PERIOD)
	var to_target := target_m + Vector2(0, bob) - c
	var want := Vector2(clampf(to_target.x * 1.5, -FLY_SPEED, FLY_SPEED),
			clampf(to_target.y * 1.5, -0.4, 0.6))
	var acc := (want - v) * 4.0 + Vector2(0, 9.81)
	acc.y = maxf(acc.y, 0.0)                     # wings only push upwards
	body.apply_force(TBE.to_px(acc * body.mass), Vector2(0, -0.01 * TBE.PPM).rotated(body.rotation))
	# flap animation
	_countdown -= 1
	if _countdown <= 0:
		_countdown = 10
		body.set_state(HALF if body.state == OPEN else OPEN)


func on_impact(impulse: float, other: Node, at: Vector2) -> void:
	if body.state == DEAD:
		return
	var sharp := TbeObject.is_sharp_contact(other, at)
	# the flower (target) is soft
	if other is TbeObject and other.obj_id == str(TBE.prop(body.props, "object", "")):
		return
	if sharp or impulse > 0.008:
		_die()


func on_explosion(_s: float) -> void:
	_die()


func _die() -> void:
	body.set_state(DEAD)
	body.modulate = Color(0.6, 0.6, 0.6)
	world.object_died(body, "The butterfly got hurt!")
