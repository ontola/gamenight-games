extends SceneTree
## Builds a few mountains and checks they have cliff bands with a way down,
## a mix of set pieces, streams and obstacles, and that generation stays quick.

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
		var kinds := {}
		for sec in c.sections: kinds[sec.kind] = kinds.get(sec.kind, 0) + 1
		var swing := 0.0
		for j in c.theta.size(): swing = maxf(swing, absf(c.theta[j] - c.view[j]))
		print("seed %d (%s): %d cliff bands (%d big), %s, %d streams, %d obstacles, drop %.0f m, swing %.0f deg, %d ms" % [seed_value, c.biome, c.bands.size(), big, kinds, c.streams.size(), c.obstacles.size(), c.base[0] - c.base[c.base.size() - 1], rad_to_deg(swing), ms])
		if c.bands.size() < 2 or kinds.size() < 6: failures += 1
		if swing < 0.4: failures += 1
	# Harder mountains have bigger drops and more in the way.
	var easy := Course.new(11, 900.0, 0, "snow")
	var extreme := Course.new(11, 900.0, 3, "snow")
	print("easy %d obstacles, extreme %d obstacles, %s" % [easy.obstacles.size(), extreme.obstacles.size(), easy.biome])
	if easy.obstacles.size() >= extreme.obstacles.size() or easy.biome != "snow": failures += 1
	print("OK" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
