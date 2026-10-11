extends SceneTree
## Geometry and contact share these functions; check the route promises across biomes.
const C = preload("res://src/course.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	for seed_value in [1, 11, 42, 777]:
		for biome in C.BIOMES:
			for difficulty in 4:
				var c := C.new(seed_value, 900.0, difficulty, biome)
				var broad := 0
				var narrow := 0
				var count := 0
				for si in range(100, 850):
					var half := c.trail_half(si)
					if half >= 2.5: broad += 1
					if half < 1.6: narrow += 1
					count += 1
				check(float(broad) / count > 0.8, "%s/%d: most of trail must be broad" % [biome, difficulty])
				check(float(narrow) / count < 0.08, "%s/%d: narrow crossings must be rare" % [biome, difficulty])
				check(not c.roads.is_empty(), "%s/%d: missing paved section" % [biome, difficulty])
				var blocked := 0
				for o in c.obstacles:
					if o.kind == "rock" and o.r < 0.6: continue
					if absf(o.d - c.trail_d(o.s)) < maxf(c.trail_half(o.s), c.road_half(o.s)) + o.r - 0.001: blocked += 1
				check(blocked == 0, "%s/%d: %d solid obstacles intrude into marked route" % [biome, difficulty, blocked])
				for b in c.bands:
					var edge_min := INF
					var edge_max := -INF
					for d in range(-24, 25):
						edge_min = minf(edge_min, c.band_edge_s(b, d))
						edge_max = maxf(edge_max, c.band_edge_s(b, d))
					check(edge_max - edge_min > 3.0, "Band edge must have visible coves/spurs")
					var d: float = b.chutes[0].d
					# Old code chopped the smooth ramp off at +2m, leaving a hidden drop.
					var edge := c.band_edge_s(b, d)
					check(absf(c._bands_at(edge + 1.999, d) - c._bands_at(edge + 2.001, d)) < 0.01, "Chute must continue smoothly below ledge")
					var end: float = edge + maxf(9.0, b.h * 2.8) * 0.5
					check(absf(c._bands_at(end - 0.001, d) - c._bands_at(end + 0.001, d)) < 0.01, "Chute tail must join ground continuously")
				for sec in c.sections:
					if sec.kind != "chasm": continue
					var br: Dictionary = sec.bridges[0]
					var crossing := c.chasm_center_s(sec, br.d)
					check(c.trail_half(crossing) <= br.w * 0.5, "Trail paint must fit on narrow bridge")
					check(absf(c.trail_d(crossing) - br.d) + c.trail_half(crossing) <= br.w * 0.5 + 0.1, "Marked route must line up with bridge")
				for road in c.roads:
					var middle: float = road.s + road.len * 0.5
					var d := c.road_center(middle)
					check(c.surface(middle, d) == C.Surface.ASPHALT, "Road center must be asphalt")
					check(is_equal_approx(c.world(middle, d).y, c.height(middle, d)), "Road visual and physics height must agree")
					check(absf(c.height(road.s - 0.001, c.trail_d(road.s)) - c.height(road.s + 0.001, c.trail_d(road.s))) < 0.01, "Road entry smoothing must not create a step")
	print("Terrain variety: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
