extends Node
## Headless check: loads every level, simulates it for a few seconds with an
## empty toolbox and reports results. Run:
##   godot --headless --fixed-fps 60 --path . res://tools/smoke_test.tscn

const SECONDS := 30.0

func _ready() -> void:
	Progress.use_sandbox()
	print("defs: ", Catalog.defs.size(), "  levels: ", Levels.paths.size())
	var unsupported := {}
	for i in Levels.paths.size():
		var p := Levels.paths[i]
		var lvl := LevelData.load_file(p)
		var w := World.new()
		add_child(w)
		w.build(lvl, [])
		var result := ["running"]
		w.won.connect(func(): result[0] = "WON at %.1fs" % w.sim_time)
		w.failed.connect(func(r): result[0] = "failed at %.1fs: %s" % [w.sim_time, r])
		await get_tree().physics_frame
		await get_tree().physics_frame
		w.start()
		var frames := int(SECONDS * 60)
		for f in frames:
			await get_tree().physics_frame
			if result[0] != "running":
				break
		for t in w.unsupported:
			unsupported[t] = unsupported.get(t, 0) + 1
		print("%2d %-38s objs=%3d tb=%d goals=%d  %s %s" % [i + 1, lvl.title.left(38), w.objects.size(),
				lvl.toolbox.size(), lvl.goals.size(), result[0], ("UNSUPPORTED " + str(w.unsupported.keys())) if not w.unsupported.is_empty() else ""])
		w.queue_free()
		await get_tree().process_frame
	print("unsupported types: ", unsupported)
	get_tree().quit()
