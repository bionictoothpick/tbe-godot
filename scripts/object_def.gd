@tool
class_name ObjectDef
extends Resource
## Describes one kind of object (a domino, a bowling ball, a ramp...).
##
## To add a new object to the game: duplicate any .tres file in
## res://objects/defs/, give it a new `type_name`, and tweak the values in the
## Inspector. It shows up automatically in the level editor palette and can be
## used in levels by that type name. All sizes are in meters, Y points up.

enum Shape { RECT, CIRCLE, POLYGON, NONE }

## Unique name used in level files, e.g. "BowlingBall".
@export var type_name: String = ""
## Name shown to players.
@export var display_name: String = ""
## Shown when hovering the object.
@export_multiline var tooltip: String = ""
## Palette group in the level editor.
@export var category: String = "Misc"

@export_group("Look")
## Image basename in res://assets/images (without extension).
## Extra states (for animated objects) can follow, separated by ';'.
@export var image: String = ""
## Draw order; higher is in front.
@export var z_value: float = 2.0

@export_group("Physics")
@export var shape: Shape = Shape.RECT
@export var width: float = 0.5
@export var height: float = 0.5
## Mass in kg. 0 means fixed in place (a static obstacle).
@export var mass: float = 0.0
@export_range(0.0, 1.0) var bounciness: float = 0.1
@export var friction: float = 0.3
## Convex polygons in meters (at default width/height), for POLYGON shapes.
@export var polygons: Array[PackedVector2Array] = []
## When set, the object is pinned to the world at this local point (meters).
@export var has_pivot: bool = false
@export var pivot: Vector2 = Vector2.ZERO
## No collisions at all (pure decoration).
@export var no_collision: bool = false

@export_group("Player")
## Default for toolbox items: may the player resize it? "none", "horizontal",
## "vertical" or "totalresize". Levels override this with a "Resizable" property.
@export var resizable: String = "none"
## Default for toolbox items: may the player rotate it? Levels override this
## with a "Rotatable" property. (The original game defaulted to false.)
@export var rotatable: bool = false

@export_group("Behavior")
## Optional script extending ObjectBehavior that adds special abilities
## (flying, floating, exploding...).
@export var behavior: Script
## Extra default properties (same keys as in level files).
@export var extra: Dictionary = {}


func image_states() -> PackedStringArray:
	return image.split(";", false)
