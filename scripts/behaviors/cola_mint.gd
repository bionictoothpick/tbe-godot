extends ObjectBehavior
## Cola bottle with a mint inside: a good bump starts a reaction, after which
## it sprays a long stream of cola out of the top (and recoils).

enum { NORMAL, FOAMING, BLOWING, EMPTY }

const BOTTLE_MASS := 0.2
const SPLAT_MASS := 0.015

var _countdown := 0
var _seq := 0
var _cola := 1.5
var _thrust := 2.0


func on_play_start() -> void:
	_cola = maxf(0.0, body.mass - BOTTLE_MASS)
	_thrust = float(TBE.prop(body.props, "Thrust", 2.0))
	_seq = 0


func on_impact(impulse: float, _other: Node, _at: Vector2) -> void:
	if body.state == NORMAL and impulse > 0.6:
		body.set_state(FOAMING)
		_countdown = 100


func on_explosion(_s: float) -> void:
	if body.state == NORMAL:
		body.set_state(FOAMING)
		_countdown = 20


func physics_tick(_delta: float) -> void:
	match body.state:
		FOAMING:
			_countdown -= 1
			if _countdown <= 0:
				body.set_state(BLOWING)
				Sfx.play("fizz", 0.8)
		BLOWING:
			_blow()


func _blow() -> void:
	_seq += 1
	var h: float
	if _seq < 40:
		h = -_seq * _seq / 400.0 + 0.1 * _seq + 1.5
	else:
		h = 1.5 - 3.0 * (_seq - 40) / 220.0
	if h <= 0.0 or _cola <= 0.0:
		body.set_state(EMPTY)
		return
	var v := sqrt(2.0 * 9.81 * h)
	var up := Vector2.UP.rotated(body.rotation)          # bottle's top, in pixels
	var mouth := body.global_position + up * body.size_m.y * 0.6 * TBE.PPM
	var up_m := Vector2(up.x, -up.y)
	if _seq % 2 == 0:
		Droplet.spawn(world, mouth, up_m * v + body.linear_velocity / TBE.PPM * Vector2(1, -1),
				SPLAT_MASS, Color(0.3, 0.15, 0.05, 0.9), 1.0)
	_cola -= SPLAT_MASS
	body.mass = maxf(BOTTLE_MASS, BOTTLE_MASS + _cola)
	# action = -reaction (with the original's "thrust" boost)
	body.apply_central_impulse(-up * SPLAT_MASS * v * _thrust * TBE.PPM)
