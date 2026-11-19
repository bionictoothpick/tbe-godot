extends Node
## Remembers completed levels and the player's solutions (user://progress.json).

const FILE := "user://progress.json"

var data := {"levels": {}}
## When true, nothing is read from or written to disk (used by the test tools
## so they never touch the player's real progress).
var sandbox := false


## Switch to a throw-away, empty progress (for automated tests).
func use_sandbox() -> void:
	sandbox = true
	data = {"levels": {}}


func _ready() -> void:
	if FileAccess.file_exists(FILE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if parsed is Dictionary and parsed.has("levels"):
			data = parsed


func _entry(level_path: String) -> Dictionary:
	if not data["levels"].has(level_path):
		data["levels"][level_path] = {}
	return data["levels"][level_path]


func is_completed(level_path: String) -> bool:
	return data["levels"].get(level_path, {}).get("completed", false)


func completed_count() -> int:
	var n := 0
	for k in data["levels"]:
		if data["levels"][k].get("completed", false):
			n += 1
	return n


func mark_completed(level_path: String, solution: Array) -> void:
	var e := _entry(level_path)
	e["completed"] = true
	e["winning_solution"] = solution
	_write()


## The player's saved arrangement for this level (Save button / auto-save).
func save_solution(level_path: String, solution: Array) -> void:
	_entry(level_path)["solution"] = solution
	_write()


func get_solution(level_path: String) -> Array:
	return data["levels"].get(level_path, {}).get("solution", [])


func get_winning_solution(level_path: String) -> Array:
	return data["levels"].get(level_path, {}).get("winning_solution", [])


func _write() -> void:
	if sandbox:
		return
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
