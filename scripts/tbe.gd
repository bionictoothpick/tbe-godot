class_name TBE
extends RefCounted
## Shared constants and helpers.
##
## Levels and object definitions use meters with Y pointing up (like the
## original game). Godot uses pixels with Y pointing down. Physics runs at
## PPM pixels per meter, so Godot's default gravity (980 px/s²) is 9.8 m/s².

const PPM := 100.0

const LAYER_SOLID := 1
const LAYER_GHOST := 2


static func to_px(meters: Vector2) -> Vector2:
	return Vector2(meters.x * PPM, -meters.y * PPM)


static func to_m(px: Vector2) -> Vector2:
	return Vector2(px.x / PPM, -px.y / PPM)


## Parses "Bar@(0.1,-0.2)" into ["Bar", Vector2(0.1, -0.2)].
static func parse_anchor(s: String) -> Array:
	var at := s.find("@")
	if at < 0:
		return [s.strip_edges(), Vector2.ZERO]
	var id := s.substr(0, at).strip_edges()
	var nums := s.substr(at + 1).replace("(", "").replace(")", "").split(",")
	var off := Vector2.ZERO
	if nums.size() >= 2:
		off = Vector2(nums[0].to_float(), nums[1].to_float())
	return [id, off]


## Converts the simple HTML used in level texts to BBCode.
static func html_to_bbcode(s: String) -> String:
	var r := s
	for pair in [["<br>", "\n"], ["<br/>", "\n"], ["<br />", "\n"], ["<i>", "[i]"], ["</i>", "[/i]"],
			["<b>", "[b]"], ["</b>", "[/b]"], ["&lt;", "<"], ["&gt;", ">"], ["&amp;", "&"]]:
		r = r.replace(pair[0], pair[1])
	return r


static func prop(props: Dictionary, key: String, default: Variant = null) -> Variant:
	if props.has(key):
		return props[key]
	# level files are not consistent about capitalisation ("object" vs "Object")
	for k in props:
		if String(k).to_lower() == key.to_lower():
			return props[k]
	return default
