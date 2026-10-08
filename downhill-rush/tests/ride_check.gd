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
			var steer := clampf((atan2(-b.d, 8.0) - b.psi) * 3.0 + c.curvature(b.s) * b.v / maxf(0.4, Bike.turn_rate(b.v)), -1, 1)
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
			# The mountain is meant to be dangerous: a careful rider still falls.
			if mode == "bot" and (r.crashes > 12 or r.time > 150.0): ok = false
		print(line)
	# Every difficulty, and a snowy mountain with ice, still gets a bot down.
	for diff in Course.DIFFICULTIES.size():
		var line := "%s:" % Course.DIFFICULTIES[diff]
		for seed_value in [5, 9]:
			var c := Course.new(seed_value, 900.0, diff, "snow" if seed_value == 5 else "")
			var r := _ride(c, "bot", seed_value)
			line += "  seed %d %s %.0fs %d crashes" % [seed_value, c.biome, r.time, r.crashes]
			if r.time >= 240.0 or (diff <= 1 and (r.crashes > 12 or r.time > 150.0)): ok = false
		print(line)
	print("OK" if ok else "FAIL")
	quit(0 if ok else 1)
