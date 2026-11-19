extends Node
## Headless check for sound effects: every sound is built, and every level
## runs 20 s with an empty toolbox. Prints which sounds played in the first
## 15 s and in the last 5 s. Once things have settled the last column should
## be nearly empty: resting objects must not keep clicking. Run:
##   godot --headless --fixed-fps 60 --path . res://tools/sound_test.tscn

func _ready() -> void:
	Progress.use_sandbox()
	Sfx.muted = false
	var names := ["hit_wood", "hit_metal", "hit_ball", "hit_soft", "pop", "boom", "ring", "fizz",
			"squish", "pick", "drop", "click", "win", "fail"]
	for n in names:
		var s: AudioStreamWAV = Sfx._streams.get(n)
		print("%-10s %s" % [n, "%.2fs" % s.get_length() if s else "MISSING"])
	var total := {}
	for i in Levels.paths.size():
		var lvl := LevelData.load_file(Levels.paths[i])
		var w := World.new()
		add_child(w)
		w.build(lvl, [])
		await get_tree().physics_frame
		await get_tree().physics_frame
		Sfx.counts = {}
		w.start()
		for f in 15 * 60:
			await get_tree().physics_frame
		var early := Sfx.counts.duplicate()
		Sfx.counts = {}
		for f in 5 * 60:
			await get_tree().physics_frame
		for k in early:
			total[k] = total.get(k, 0) + early[k]
		print("%2d %-30s first 15 s: %s   last 5 s: %s" % [i + 1, lvl.title.left(30), early, Sfx.counts])
		w.queue_free()
		await get_tree().process_frame
	print("total: ", total)
	get_tree().quit()
