extends SceneTree
## Airborne momentum and touchdown energy, measured in world space too.

class TestCourse extends Course:
	var grade := 0.0
	var bend := 0.0
	func height(s: float, _d: float) -> float: return grade * s
	func curvature(_s: float) -> float: return bend
	func heading(s: float) -> float: return bend * s
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return []
	func world(s: float, d: float, y: float = INF) -> Vector3:
		var centre := Vector3(0, 0, s) if is_zero_approx(bend) else Vector3((1.0 - cos(bend * s)) / bend, 0, sin(bend * s) / bend)
		var p := centre + right(s) * d
		p.y = height(s, d) if y == INF else y
		return p

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _flying(c: Course, s: float, d: float) -> Bike:
	var b := Bike.new()
	b.place(c, s, d, 10.0)
	b.grounded = false
	b.y += 35.0
	b.vy = 2.0
	b.invulnerable = 100.0
	return b

func _flight(c: Course, s: float, d: float, hz: int, label: String, tolerance := 0.02) -> void:
	var coast := _flying(c, s, d)
	var pedal := _flying(c, s, d)
	var initial_direction := c.forward(s)
	var fastest := 0.0
	for frame in hz:
		var before := c.world(coast.s, coast.d, coast.y)
		var speed := coast.v
		Bike.step(coast, c, {}, 1.0 / hz)
		Bike.step(pedal, c, {"pedal": 1.0}, 1.0 / hz)
		var travel := c.world(coast.s, coast.d, coast.y) - before
		fastest = maxf(fastest, Vector2(travel.x, travel.z).length() * hz / speed)
	var direction := c.forward(coast.s) * cos(coast.psi) + c.right(coast.s) * sin(coast.psi)
	var error := initial_direction.angle_to(direction)
	check(not coast.grounded and not coast.crashed, "%s stays airborne" % label)
	check(coast.v < 10.0 and fastest <= 1.0 + tolerance, "%s world speed ratio %.3f must not gain horizontal speed" % [label, fastest])
	check(error < tolerance, "%s fixed-world heading error %.3f rad" % [label, error])
	check(is_equal_approx(coast.s, pedal.s) and is_equal_approx(coast.d, pedal.d) and is_equal_approx(coast.y, pedal.y) and is_equal_approx(coast.v, pedal.v), "%s pedalling in air must not change trajectory" % label)
	check(absf(coast.vy - (2.0 - Bike.G)) < 0.001, "%s vertical fall is ordinary gravity" % label)
	print("%s: world-speed ratio %.3f, heading error %.3f" % [label, fastest, error])

func _hop(c: Course, label: String) -> void:
	var coast := Bike.new()
	var pedal := Bike.new()
	for b in [coast, pedal]:
		b.place(c, 30.0, 8.0, 10.0)
		b.invulnerable = 100.0
		Bike.step(b, c, {"hop": true}, 1.0 / 120.0)
	check(coast.launched, "%s launches from actual wheel contact" % label)
	var incoming_energy := 0.0
	for frame in 360:
		incoming_energy = coast.v * coast.v + pow(coast.vy - Bike.G / 120.0, 2)
		Bike.step(coast, c, {}, 1.0 / 120.0)
		Bike.step(pedal, c, {"pedal": 1.0}, 1.0 / 120.0)
		if coast.landed: break
	check(coast.landed and not coast.crashed, "%s completes hop and landing" % label)
	check(absf(coast.v - pedal.v) < 0.0001 and absf(coast.s - pedal.s) < 0.0001, "%s air pedalling cannot boost landing speed or distance" % label)
	check(coast.v * coast.v + coast.vy * coast.vy <= incoming_energy + 0.001, "%s landing cannot add kinetic energy" % label)

func _init() -> void:
	for hz in [60, 120, 240]:
		for grade in [0.0, -0.5, 0.35]:
			var c := TestCourse.new(1, 200.0)
			c.grade = grade
			_flight(c, 30.0, 0.0, hz, "straight slope %.2f @%dHz" % [grade, hz])
		for bend in [-0.025, 0.025]:
			for d in [-8.0, 8.0]:
				var c := TestCourse.new(1, 200.0)
				c.bend = bend
				_flight(c, 30.0, d, hz, "curve %.3f offset %.0f @%dHz" % [bend, d, hz])
	# Actual generated courses validate Course.world's coordinate convention,
	# with a little tolerance for its one-metre, piecewise-linear centreline.
	for seed_value in [1, 42, 777]:
		var c := Course.new(seed_value, 900.0)
		var at := 100.0
		for s in range(100, 750):
			if absf(c.curvature(s)) > absf(c.curvature(at)): at = s
		for d in [-8.0, 8.0]: _flight(c, at, d, 120, "generated %d offset %.0f" % [seed_value, d], 0.06)
	for grade in [0.0, -0.5]:
		for bend in [0.0, 0.025]:
			var c := TestCourse.new(1, 200.0)
			c.grade = grade
			c.bend = bend
			_hop(c, "hop slope %.2f curve %.3f" % [grade, bend])
	for grade in [-0.8, -0.5, 0.0, 0.5]:
		var c := TestCourse.new(1, 200.0)
		c.grade = grade
		for vertical in [grade * 10.0, -9.0]:
			var b := _flying(c, 30.0, 0.0)
			b.vy = vertical
			b.pitch = atan(grade)
			b.air_time = 0.8
			var before := b.v * b.v + b.vy * b.vy
			Bike._land(b, c, c.height(b.s, b.d))
			var after := b.v * b.v + b.vy * b.vy
			check(after <= before + 0.001, "touchdown on %.2f slope must not create energy (%.2f -> %.2f)" % [grade, before, after])
			if is_equal_approx(vertical, grade * 10.0):
				check(absf(b.v - 10.0) < 0.001, "slope-aligned touchdown must preserve horizontal speed")
			var settled := b.v
			for bounce in 8: Bike._land(b, c, c.height(b.s, b.d))
			check(b.v <= settled + 0.001, "repeated contact must not pump speed")
	print("Air speed: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
