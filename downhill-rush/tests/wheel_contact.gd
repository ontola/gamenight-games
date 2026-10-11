extends SceneTree

class FlatCourse extends Course:
	var rocks: Array = []
	func height(_s: float, _d: float) -> float: return 0.0
	func gradient(_s: float, _d: float) -> Vector2: return Vector2.ZERO
	func curvature(_s: float) -> float: return 0.0
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return rocks

class SlopedCourse extends FlatCourse:
	func height(s: float, d: float) -> float: return -0.3 * s + 0.2 * d
	func gradient(_s: float, _d: float) -> Vector2: return Vector2(-0.3, 0.2)

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	for hz in [60, 120, 240]:
		for h in [0.15, 0.35, 0.6]:
			var c := FlatCourse.new(1, 200.0)
			c.rocks = [{"s": 10.0, "d": 0.0, "r": 0.45, "h": h, "kind": "rock"}]
			var b := Bike.new()
			b.place(c, 7.0, 0.0, 1.5)
			var peak := 0.0
			var backwards := false
			for tick in hz * 8:
				var before := b.s
				Bike.step(b, c, {"pedal": 0.4 if b.v < 2.0 else 0.0}, 1.0 / hz)
				peak = maxf(peak, b.y)
				backwards = backwards or b.s < before - 0.001
				if b.crashed or b.s > 13.0: break
			check(not b.crashed and b.s > 13.0, "low-speed rock crossing h=%s hz=%s: %s at %.2f" % [h, hz, b.crash_reason, b.s])
			check(not backwards, "rock must not push the rider backwards")
			check(peak > h * 0.25, "bike must climb the stone, not pass through it")
	# A glancing low-rock contact must not become a solid collision in the air.
	var c := FlatCourse.new(1, 200.0)
	c.rocks = [{"s": 10.0, "d": 0.0, "r": 0.45, "h": 0.35, "kind": "rock"}]
	var b := Bike.new()
	b.place(c, 9.6, 0.0, 3.0)
	b.grounded = false
	b.y = 0.1
	Bike._collide_obstacles(b, c)
	check(is_equal_approx(b.s, 9.6) and is_equal_approx(b.v, 3.0), "airborne low-rock contact must not repel")
	# Tall obstacles retain the existing high-speed crash response.
	for kind in ["rock", "tree"]:
		c.rocks = [{"s": 10.0, "d": 0.0, "r": 0.6, "h": 1.3, "kind": kind}]
		b = Bike.new()
		b.place(c, 9.2, 0.0, 12.0)
		Bike._collide_obstacles(b, c)
		check(b.crashed and b.crash_reason == "obstacle", "high-speed %s must still crash" % kind)
	# The rock support must join the underlying hillside continuously on
	# its downhill and cross-slope edges, not introduce an artificial ledge.
	var hillside := SlopedCourse.new(1, 200.0)
	hillside.rocks = [{"s": 10.0, "d": 0.0, "r": 0.45, "h": 0.15, "kind": "rock"}]
	for axis in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var inside: Vector2 = Vector2(10.0, 0.0) + axis * 0.799
		var outside: Vector2 = Vector2(10.0, 0.0) + axis * 0.801
		check(absf(Bike._rock_lift(hillside, inside.x, inside.y) - Bike._rock_lift(hillside, outside.x, outside.y)) < 0.0001, "stone must merge smoothly with the hillside")
	# Difficulty changes the mountain, never the rider's crash tolerance.
	for difficulty in Course.DIFFICULTIES.size():
		var mountain := FlatCourse.new(1, 200.0, difficulty)
		check(is_equal_approx(mountain.crash_limit, 1.15), "difficulty must not change crash tolerance")
		mountain.rocks = [{"s": 10.0, "d": 0.0, "r": 0.6, "h": 1.3, "kind": "rock"}]
		for speed in [2.0, 12.0]:
			b = Bike.new()
			b.place(mountain, 9.2, 0.0, speed)
			Bike._collide_obstacles(b, mountain)
			check(b.crashed == (speed == 12.0), "same impact must have same outcome across difficulty")
	print("WHEEL_CONTACT_PASS" if failures == 0 else "WHEEL_CONTACT_FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
