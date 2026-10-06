extends SceneTree
## Rides each test mountain with a few simple strategies and reports crashes
## and times, so balance changes have numbers behind them.

func _ride(c: Course, mode: String, seed_value: int) -> Dictionary:
	var b := Bike.new()
	b.place(c, Course.START_LINE, 0.0)
	var bot := Bot.new(seed_value, 0.8)
	var t := 0.0
	var dt := 1.0 / 120.0
	while b.s < c.length and t < 240.0:
		var input := {}
		if mode == "bot":
			input = bot.think(b, c, dt)
		else:
			var steer := clampf((atan2(-b.d, 8.0) - b.psi) * 3.0 + c.curvature(b.s) * b.v / maxf(0.4, minf(2.3, 15.0 / (b.v + 4.0))), -1, 1)
			input = {"steer": steer, "pedal": 1.0 if mode == "pedal" else 0.0}
		Bike.step(b, c, input, dt)
		t += dt
	return {"time": t, "crashes": b.crashes}

func _init() -> void:
	var ok := true
	for seed_value in [1, 2, 3, 42, 777]:
		var c := Course.new(seed_value, 900.0)
		var line := "seed %d:" % seed_value
		for mode in ["coast", "pedal", "bot"]:
			var r := _ride(c, mode, seed_value)
			line += "  %s %.0fs %d crashes" % [mode, r.time, r.crashes]
			if mode == "bot" and (r.crashes > 3 or r.time > 120.0): ok = false
		print(line)
	print("OK" if ok else "FAIL")
	quit(0 if ok else 1)
