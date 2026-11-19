extends Node
## The ordered list of levels (res://assets/levels/levels.xml) plus any levels
## the player made (user://levels/*.xml).

const LEVEL_DIR := "res://assets/levels/"
const USER_DIR := "user://levels/"

var paths: Array[String] = []
var titles := {}
var current := 0

## Level editor state, kept here so it survives a test-play round trip.
var editor_level: LevelData = null    # the level being edited (unsaved changes included)
var editor_path := ""                 # where it is saved ("" = never saved)
var testing := false                  # Game is test-playing the editor level
const TEST_FILE := "user://levels/_editor_test.xml"


func _ready() -> void:
	reload()


func reload() -> void:
	paths.clear()
	titles.clear()
	var text := FileAccess.get_file_as_string(LEVEL_DIR + "levels.xml")
	# drop commented-out entries
	var no_comments := RegEx.create_from_string("(?s)<!--.*?-->").sub(text, "", true)
	for m in RegEx.create_from_string("<level>\\s*(.*?)\\s*</level>").search_all(no_comments):
		var p := LEVEL_DIR + m.get_string(1)
		if FileAccess.file_exists(p):
			paths.append(p)
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var d := DirAccess.open(USER_DIR)
	if d:
		var files := d.get_files()
		files.sort()
		for f in files:
			if f.ends_with(".xml") and not f.begins_with("_"):
				paths.append(USER_DIR + f)


func title_of(p: String) -> String:
	if not titles.has(p):
		var t := "?"
		var text := FileAccess.get_file_as_string(p)
		var m := RegEx.create_from_string("<title>\\s*(.*?)\\s*</title>").search(text)
		if m:
			t = m.get_string(1)
		titles[p] = t
	return titles[p]


func current_path() -> String:
	if testing:
		return TEST_FILE
	return paths[current] if current < paths.size() else ""


## A file name in user://levels for a level title.
func user_path_for(title: String) -> String:
	var base := title.to_lower().validate_filename().replace(" ", "_")
	if base == "":
		base = "level"
	return USER_DIR + base + ".xml"


func is_user_level(p: String) -> bool:
	return p.begins_with(USER_DIR)
