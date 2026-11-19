extends Node
## All object types, loaded from res://objects/defs/*.tres.
## Add a new object by dropping a new ObjectDef .tres in that folder.

const DEF_DIR := "res://objects/defs/"

var defs := {}   # type_name -> ObjectDef


func _ready() -> void:
	for f in ResourceLoader.list_directory(DEF_DIR):
		if not (f.ends_with(".tres") or f.ends_with(".res")):
			continue
		var d := load(DEF_DIR + f) as ObjectDef
		if d == null or d.type_name.is_empty():
			push_warning("Skipping invalid object definition: " + f)
			continue
		defs[d.type_name] = d


func get_def(type_name: String) -> ObjectDef:
	return defs.get(type_name)


func has_type(type_name: String) -> bool:
	return defs.has(type_name)


func categories() -> Dictionary:
	var out := {}
	for d: ObjectDef in defs.values():
		if not out.has(d.category):
			out[d.category] = []
		out[d.category].append(d)
	for c in out:
		out[c].sort_custom(func(a, b): return a.display_name < b.display_name)
	return out
