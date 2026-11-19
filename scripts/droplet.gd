class_name Droplet
extends RigidBody2D
## A small short-lived particle that really pushes things: cola spray and
## explosion debris. Droplets don't collide with each other.

var color := Color(0.35, 0.18, 0.05)
var radius_px := 4.0
var life := 1.5


static func spawn(parent: Node, at_px: Vector2, velocity_mps: Vector2, kg: float, c: Color, seconds: float) -> Droplet:
	var d := Droplet.new()
	d.color = c
	d.life = seconds
	d.mass = kg
	d.position = at_px
	d.collision_layer = TBE.LAYER_GHOST
	d.collision_mask = TBE.LAYER_SOLID
	d.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var cs := CollisionShape2D.new()
	var s := CircleShape2D.new()
	s.radius = d.radius_px
	cs.shape = s
	d.add_child(cs)
	d.z_index = 25
	parent.add_child(d)
	d.linear_velocity = TBE.to_px(velocity_mps)
	return d


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0:
		queue_free()
	elif life < 0.3:
		modulate.a = life / 0.3


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius_px, color)
