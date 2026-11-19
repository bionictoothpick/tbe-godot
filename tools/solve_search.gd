extends Node
## Tries many placements of one toolbox item in a level and reports the ones
## that win. Env: LEVEL (1-based), TB (toolbox index), plus ranges
## X0,X1,Y0,Y1,STEP (meters), ANGLES (comma list, degrees), SECONDS.
## Also requires the object named by MUST_ID to end with x between
## MUST_X0..MUST_X1 and y below MUST_YMAX (e.g. "volleyball is in the hole").

func _env(k: String, d: float) -> float:
	return float(OS.get_environment(k)) if OS.has_environment(k) else d


func _ready() -> void:
	Progress.use_sandbox()
	var lvl := LevelData.load_file(Levels.paths[int(_env("LEVEL", 3)) - 1])
	var tb := int(_env("TB", 0))
	var item: Dictionary = lvl.toolbox[tb]
	var angles := (OS.get_environment("ANGLES") if OS.has_environment("ANGLES") else "0").split(",")
	var step := _env("STEP", 0.05)
	var secs := _env("SECONDS", 25.0)
	var found := 0
	var x := _env("X0", 0.5)
	while x <= _env("X1", 1.5) + 0.0001:
		var y := _env("Y0", 0.3)
		while y <= _env("Y1", 1.0) + 0.0001:
			for a in angles:
				var s: Dictionary = item["spec"].duplicate(true)
				s["x"] = x
				s["y"] = y
				s["angle"] = deg_to_rad(float(a))
				var w := World.new()
				add_child(w)
				w.build(lvl, [{"spec": s, "toolbox_index": tb}])
				await get_tree().physics_frame
				await get_tree().physics_frame
				if w.any_overlap():
					w.queue_free()
					continue
				var res := ["none", 0.0]
				w.won.connect(func(): res[0] = "WON"; res[1] = w.sim_time)
				w.failed.connect(func(_r): res[0] = "fail"; res[1] = w.sim_time)
				w.start()
				for f in int(secs * 60):
					await get_tree().physics_frame
					if res[0] != "none":
						break
				var ok: bool = res[0] == "WON"
				var note := ""
				if ok and OS.has_environment("MUST_ID"):
					var o: TbeObject = w.by_id.get(OS.get_environment("MUST_ID"))
					if o == null:   # no object with that name: match by type instead
						for cand in w.objects:
							if cand.def.type_name == OS.get_environment("MUST_ID"):
								o = cand
					var c := o.center_m() if o else Vector2(-99, -99)
					ok = c.x >= _env("MUST_X0", -99) and c.x <= _env("MUST_X1", 99) and c.y <= _env("MUST_YMAX", 99)
					note = " %s at (%.2f, %.2f)" % [OS.get_environment("MUST_ID"), c.x, c.y]
				if ok:
					found += 1
					print("SOLUTION x=%.2f y=%.2f angle=%s won at %.1fs%s" % [x, y, a, res[1], note])
				w.queue_free()
				await get_tree().process_frame
			y += step
		x += step
	print("done, %d solutions" % found)
	get_tree().quit()
