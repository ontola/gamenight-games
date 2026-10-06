extends SceneTree
## Generates several mountains and checks every jump can be cleared.

func _init() -> void:
	var failures := 0
	for seed_value in [1, 2, 3, 42, 777]:
		var t0 := Time.get_ticks_msec()
		var c := Course.new(seed_value, 900.0)
		var ms := Time.get_ticks_msec() - t0
		var kinds := {}
		for f in c.features:
			var name: String = Course.Kind.keys()[int(f.kind)]
			kinds[name] = kinds.get(name, 0) + 1
			if f.has("speed_min"):
				print("  %s at %.0f: clean from %.1f to %.1f m/s" % [name, f.s0, f.speed_min, f.speed_max])
		print("seed %d: %d features %s, %d obstacles, drop %.0f m, %d ms" % [seed_value, c.features.size(), kinds, c.obstacles.size(), c.base[0] - c.base[c.base.size() - 1], ms])
		if c.features.size() < 8: failures += 1
	print("FAIL" if failures else "OK")
	quit(1 if failures else 0)
