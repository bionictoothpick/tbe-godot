class_name LinkBar
extends RigidBody2D
## A light rigid bar connecting two objects (the "Link" from level files).

var color := Color(0.4, 0.25, 0.1)
var half := Vector2.ZERO


func setup(a: Vector2, b: Vector2, c: Color) -> void:
	color = c
	position = (a + b) * 0.5
	half = (b - a) * 0.5
	mass = 0.05
	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	var cs := CollisionShape2D.new()
	var seg := SegmentShape2D.new()
	seg.a = -half
	seg.b = half
	cs.shape = seg
	add_child(cs)
	z_index = 30


func _draw() -> void:
	draw_line(-half, half, color, 3.0, true)
	draw_circle(-half, 3.0, color.darkened(0.3))
	draw_circle(half, 3.0, color.darkened(0.3))
