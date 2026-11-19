extends Node
## Simulates one level and prints object positions. Set LEVEL env var (1-based).

func _ready() -> void:
	Progress.use_sandbox()
	var i := int(OS.get_environment("LEVEL")) - 1
	var watch := OS.get_environment("WATCH").split(",", false)
	var lvl := LevelData.load_file(Levels.paths[i])
	var w := World.new()
	add_child(w)
	w.build(lvl, [])
	w.won.connect(func(): print("WON at ", w.sim_time))
	w.failed.connect(func(r): print("FAILED at ", w.sim_time, " ", r))
	await get_tree().physics_frame
	await get_tree().physics_frame
	w.start()
	for f in int(OS.get_environment("FRAMES")) if OS.has_environment("FRAMES") else 1800:
		await get_tree().physics_frame
		if f % 30 == 0:
			var line := "t=%.1f " % w.sim_time
			for o in w.objects:
				if watch.is_empty() and o.is_static: continue
				if not watch.is_empty() and o.obj_id not in watch and o.def.type_name not in watch: continue
				var c := o.center_m()
				line += "%s(%.2f,%.2f,%.0f°) " % [o.obj_id if o.obj_id != "" else o.def.type_name, c.x, c.y, rad_to_deg(o.angle_m())]
			print(line)
	get_tree().quit()
