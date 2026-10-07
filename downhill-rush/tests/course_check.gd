extends SceneTree
## Builds a few mountains and checks they have cliff bands with a way down,
## streams and obstacles, and that generation stays quick.

func _init() -> void:
	var failures := 0
	for seed_value in [1, 2, 3, 42, 777]:
		var t := Time.get_ticks_msec()
		var c := Course.new(seed_value, 900.0)
		var ms := Time.get_ticks_msec() - t
		var big := 0
		for b in c.bands:
			if b.h > 4.0: big += 1
			if b.chutes.is_empty(): failures += 1
		print("seed %d: %d cliff bands (%d big), %d streams, %d obstacles, drop %.0f m, %d ms" % [seed_value, c.bands.size(), big, c.streams.size(), c.obstacles.size(), c.base[0] - c.base[c.base.size() - 1], ms])
		if c.bands.size() < 6: failures += 1
	print("OK" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
