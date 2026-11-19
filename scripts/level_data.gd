class_name LevelData
extends RefCounted
## A level: info, scene size, objects, the player's toolbox, and goals.
## Reads and writes the original TBE level XML format, so all classic levels
## work unchanged and new levels stay compatible.

var path := ""
var title := "Untitled"
var author := ""
var license := ""
var description := ""
var date := ""
var scene_size := Vector2(8, 5)          # meters
var background: Array = []               # [{pos: float, color: Color}]
var predefined: Array = []               # object specs
var toolbox: Array = []                  # [{spec: Dictionary, count: int}]
var goals: Array = []                    # [{type, is_fail, props}]
var hints: Array = []                    # [{x, y, number, object}]


## Deep copy (used for undo and test-play).
func clone() -> LevelData:
	var c := LevelData.new()
	for k in ["path", "title", "author", "license", "description", "date", "scene_size"]:
		c.set(k, get(k))
	c.background = background.duplicate(true)
	c.predefined = predefined.duplicate(true)
	c.toolbox = toolbox.duplicate(true)
	c.goals = goals.duplicate(true)
	c.hints = hints.duplicate(true)
	return c


## A fresh, empty level with a floor.
static func new_level() -> LevelData:
	var l := LevelData.new()
	l.title = "My Level"
	l.license = "CC0"
	l.description = "Describe the goal here."
	l.date = Time.get_date_string_from_system()
	l.scene_size = Vector2(6, 4)
	l.predefined = [{"type": "Floor", "x": 3.0, "y": 0.05, "w": 6.0, "h": 0.1, "angle": 0.0, "props": {}}]
	return l


static func load_file(file_path: String) -> LevelData:
	var lvl := LevelData.new()
	lvl.path = file_path
	var p := XMLParser.new()
	if p.open(file_path) != OK:
		push_error("Cannot open level " + file_path)
		return null
	var stack: Array[String] = []
	var section := ""            # predefined / toolbox / goals
	var cur_obj := {}            # object spec being read
	var cur_goal := {}
	var cur_item := {}
	var prop_key := ""
	var text_target := ""        # which element's text we are reading
	var grad_pos := 0.0
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := p.get_node_name()
				var empty := p.is_empty()
				var a := _attrs(p)
				match tag:
					"predefined": section = "predefined"
					"toolbox": section = "toolbox"
					"goals": section = "goals"
					"scenesize":
						lvl.scene_size = Vector2(float(a.get("width", "8")), float(a.get("height", "5")))
					"toolboxitem":
						cur_item = {"count": int(a.get("count", "1")), "spec": {}}
						if empty:
							cur_item = {}
					"object":
						cur_obj = _spec_from_attrs(a)
						if empty:
							_finish_object(lvl, section, cur_obj, cur_item)
							cur_obj = {}
					"goal":
						cur_goal = {"type": a.get("type", ""), "is_fail": a.get("isFail", "false") == "true", "props": {}}
						if empty:
							lvl.goals.append(cur_goal)
					"property":
						prop_key = a.get("key", "")
						text_target = "property"
						if empty:
							_set_prop(cur_obj, cur_goal, prop_key, "")
					"gradientstop":
						grad_pos = float(a.get("pos", "0"))
						text_target = "gradientstop"
					"hint":
						lvl.hints.append({"x": float(a.get("X", "0")), "y": float(a.get("Y", "0")),
								"number": int(a.get("number", "0")), "object": a.get("object", "")})
					"title", "author", "license", "description", "date", "tooltip":
						text_target = tag
				if empty and tag in ["predefined", "toolbox", "goals"]:
					section = ""
				if not empty:
					stack.append(tag)
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				var t := _decode(p.get_node_data())
				if t.strip_edges() == "":
					continue
				match text_target:
					"property": _set_prop(cur_obj, cur_goal, prop_key, t.strip_edges())
					"gradientstop":
						var c := t.strip_edges().split(";")
						if c.size() >= 3:
							lvl.background.append({"pos": grad_pos, "color": Color(float(c[0]), float(c[1]), float(c[2]),
									float(c[3]) if c.size() > 3 else 1.0)})
					"title": lvl.title = t.strip_edges()
					"author": lvl.author = t.strip_edges()
					"license": lvl.license = t.strip_edges()
					"description": lvl.description = t.strip_edges()
					"date": lvl.date = t.strip_edges()
					"tooltip":
						if not cur_obj.is_empty():
							cur_obj["tooltip"] = t.strip_edges()
			XMLParser.NODE_ELEMENT_END:
				var tag := p.get_node_name()
				if not stack.is_empty():
					stack.pop_back()
				text_target = ""
				match tag:
					"object":
						_finish_object(lvl, section, cur_obj, cur_item)
						cur_obj = {}
					"toolboxitem":
						if not cur_item.is_empty() and not cur_item["spec"].is_empty():
							lvl.toolbox.append(cur_item)
						cur_item = {}
					"goal":
						lvl.goals.append(cur_goal)
						cur_goal = {}
					"predefined", "toolbox", "goals":
						section = ""
	return lvl


static func _attrs(p: XMLParser) -> Dictionary:
	var a := {}
	for i in p.get_attribute_count():
		a[p.get_attribute_name(i)] = _decode(p.get_attribute_value(i))
	return a


static func _decode(s: String) -> String:
	return s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&apos;", "'").replace("&amp;", "&")


static func _spec_from_attrs(a: Dictionary) -> Dictionary:
	var s := {"type": a.get("type", ""), "props": {}}
	if a.has("ID"): s["id"] = a["ID"]
	if a.has("X"): s["x"] = float(a["X"])
	if a.has("Y"): s["y"] = float(a["Y"])
	if a.has("width"): s["w"] = float(a["width"])
	if a.has("height"): s["h"] = float(a["height"])
	if a.has("angle"): s["angle"] = float(a["angle"])
	return s


static func _set_prop(obj: Dictionary, goal: Dictionary, key: String, value: String) -> void:
	if not obj.is_empty():
		obj["props"][key] = value
	elif not goal.is_empty():
		goal["props"][key] = value


static func _finish_object(lvl: LevelData, section: String, obj: Dictionary, item: Dictionary) -> void:
	if obj.is_empty():
		return
	if section == "toolbox" and not item.is_empty():
		item["spec"] = obj
	elif section == "predefined":
		lvl.predefined.append(obj)


# ------------------------------------------------------------------ writing

func save_file(file_path: String) -> Error:
	var x := PackedStringArray()
	x.append("<!DOCTYPE mydocument>")
	x.append("<tbe-level>")
	x.append("    <levelinfo>")
	for pair in [["title", title], ["author", author], ["license", license], ["description", description], ["date", date]]:
		x.append("        <%s>%s</%s>" % [pair[0], _esc(pair[1]), pair[0]])
	x.append("    </levelinfo>")
	x.append("    <toolbox>")
	for item in toolbox:
		x.append("        <toolboxitem count=\"%d\">" % item["count"])
		_write_object(x, item["spec"], "            ")
		x.append("        </toolboxitem>")
	x.append("    </toolbox>")
	x.append("    <scene>")
	x.append("        <scenesize width=\"%s\" height=\"%s\"/>" % [scene_size.x, scene_size.y])
	x.append("        <predefined>")
	for s in predefined:
		_write_object(x, s, "            ")
	x.append("        </predefined>")
	if not background.is_empty():
		x.append("        <background>")
		for g in background:
			var c: Color = g["color"]
			x.append("            <gradientstop pos=\"%.2f\">%.2f;%.2f;%.2f;%.2f</gradientstop>" % [g["pos"], c.r, c.g, c.b, c.a])
		x.append("        </background>")
	x.append("    </scene>")
	x.append("    <goals>")
	for g in goals:
		x.append("        <goal isFail=\"%s\" type=\"%s\">" % ["true" if g["is_fail"] else "false", g["type"]])
		for k in g["props"]:
			x.append("            <property key=\"%s\">%s</property>" % [_esc(k), _esc(str(g["props"][k]))])
		x.append("        </goal>")
	x.append("    </goals>")
	x.append("    <hints/>")
	x.append("</tbe-level>")
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string("\n".join(x) + "\n")
	path = file_path
	return OK


static func _write_object(x: PackedStringArray, s: Dictionary, indent: String) -> void:
	var attrs := "type=\"%s\"" % _esc(s["type"])
	if s.has("id") and s["id"] != "": attrs += " ID=\"%s\"" % _esc(s["id"])
	for pair in [["x", "X"], ["y", "Y"], ["w", "width"], ["h", "height"], ["angle", "angle"]]:
		if s.has(pair[0]):
			attrs += " %s=\"%s\"" % [pair[1], snappedf(float(s[pair[0]]), 0.0001)]
	var p: Dictionary = s.get("props", {})
	if p.is_empty() and not s.has("tooltip"):
		x.append(indent + "<object %s/>" % attrs)
		return
	x.append(indent + "<object %s>" % attrs)
	for k in p:
		x.append(indent + "    <property key=\"%s\">%s</property>" % [_esc(k), _esc(str(p[k]))])
	if s.has("tooltip"):
		x.append(indent + "    <tooltip>%s</tooltip>" % _esc(s["tooltip"]))
	x.append(indent + "</object>")


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
