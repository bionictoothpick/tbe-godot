extends Control
## Title screen with the level grid.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.2, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	m.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Images.get_texture("ButterflyOpen", 96)
	icon.custom_minimum_size = Vector2(64, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title := Label.new()
	title.text = "  The Butterfly Effect"
	title.add_theme_font_size_override("font_size", 40)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var count := Label.new()
	count.text = "%d / %d solved" % [Progress.completed_count(), Levels.paths.size()]
	count.add_theme_font_size_override("font_size", 18)
	head.add_child(count)
	var edit := Button.new()
	edit.text = "✎ Level Editor"
	edit.tooltip_text = "Make your own levels"
	edit.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/editor.tscn"))
	head.add_child(edit)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	head.add_child(quit)

	var sub := Label.new()
	sub.text = "Combine simple things to reach a simple goal — in the most complicated way possible."
	sub.modulate = Color(1, 1, 1, 0.75)
	v.add_child(sub)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	resized.connect(func(): grid.columns = maxi(2, int(size.x / 250)))

	for i in Levels.paths.size():
		var p := Levels.paths[i]
		var b := Button.new()
		var done := Progress.is_completed(p)
		b.text = "%s%s%d. %s" % ["✔ " if done else "", "★ " if Levels.is_user_level(p) else "", i + 1, Levels.title_of(p)]
		b.custom_minimum_size = Vector2(220, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.tooltip_text = Levels.title_of(p)
		if done:
			b.modulate = Color(0.75, 1.0, 0.75)
		b.pressed.connect(_play.bind(i))
		grid.add_child(b)


func _play(i: int) -> void:
	Levels.current = i
	get_tree().change_scene_to_file("res://scenes/game.tscn")
