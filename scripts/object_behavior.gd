class_name ObjectBehavior
extends RefCounted
## Base class for special object abilities. Extend this, then point an
## ObjectDef's `behavior` at your script. All hooks are optional.
##
## Units: `body` is a RigidBody2D in pixels; use TBE.PPM to convert.
## Impulses passed to on_impact are in N·s (meters), like the original game.

var body: TbeObject
var world: Node   # the World node


## Called once after the body was built (edit mode).
func setup() -> void:
	pass


## Called when the player presses Play.
func on_play_start() -> void:
	pass


## Called every physics frame while simulating.
func physics_tick(_delta: float) -> void:
	pass


## Called for each contact while simulating. `impulse` is in N·s,
## `at` is the contact point (global pixels).
func on_impact(_impulse: float, _other: Node, _at: Vector2) -> void:
	pass


## Called when the player clicks this object while simulating.
## Return true if the click was used.
func on_clicked() -> bool:
	return false


## Called when the player clicks this object while editing (e.g. Post-it notes).
func on_clicked_in_edit() -> bool:
	return false


## Sharp objects pop balloons and hurt butterflies. `at` is a global point,
## so objects can be sharp on one side only.
func is_sharp_at(_at: Vector2) -> bool:
	return false


## Called by explosions. `strength` is an impulse in N·s at the body's center.
func on_explosion(_strength: float) -> void:
	pass
