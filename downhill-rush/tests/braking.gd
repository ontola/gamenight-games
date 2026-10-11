extends SceneTree

class FlatCourse extends Course:
	func height(_s: float, _d: float) -> float: return 0.0
	func gradient(_s: float, _d: float) -> Vector2: return Vector2.ZERO
	func curvature(_s: float) -> float: return 0.0
	func heading(_s: float) -> float: return 0.0
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return []
	func world(s: float, d: float, y: float = INF) -> Vector3:
		return Vector3(-d, 0.0 if is_inf(y) else y, s)

var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var c := FlatCourse.new(42, 900.0)
	for hz in [30, 60, 120]:
		var light := Bike.new()
		var hard := Bike.new()
		light.place(c, 20.0, 0.0, 12.0)
		hard.place(c, 20.0, 0.0, 12.0)
		var view := RiderView.new()
		root.add_child(view)
		view.setup(Color.CORAL, "Brake test")
		for tick in hz / 2:
			Bike.step(light, c, {"brake": 0.4}, 1.0 / hz)
			Bike.step(hard, c, {"brake": 1.0, "pedal": 1.0}, 1.0 / hz)
			view.pose(hard, c, 1.0 / hz)
		check(hard.brake_locked and hard.v < light.v and hard.v > 0.0, "Hard brake locks and slows more than light brake @%d" % hz)
		check(not light.brake_locked and light.skid == 0.0, "Light brake keeps tyre rolling @%d" % hz)
		check(view._front_spin_rate == 0.0 and view._rear_spin_rate == 0.0 and hard.pedaling == 0.0, "Locked wheel and crank animations stop @%d" % hz)
		var marks = view.skid_marks
		check(marks.segments.size() > 6, "Grounded hard braking draws contact marks @%d" % hz)
		view.hide()
		check(marks.is_visible_in_tree(), "Track marks persist through rider visibility flash")
		view.show()
		var count: int = marks.segments.size()
		Bike.step(hard, c, {"brake": 1.0, "hop": true}, 1.0 / hz)
		view.pose(hard, c, 1.0 / hz)
		check(hard.brake_locked and hard.skid == 0.0 and not hard.grounded, "Takeoff keeps the wheel brake but clears ground skid in the same tick")
		for tick in hz / 4:
			Bike.step(hard, c, {"brake": 1.0}, 1.0 / hz)
			view.pose(hard, c, 1.0 / hz)
		check(marks.segments.size() == count, "Airborne brake never draws ground marks")
		check(marks._last == [null, null], "Contact loss breaks both trail endpoints")
		hard.pedaling = 1.0
		view.pose(hard, c, 1.0 / hz)
		check(view._front_spin_rate == 0.0 and view._rear_spin_rate == 0.0, "Airborne hard brake stops both wheels and overrides throttle")
		var air_coast := Bike.new()
		air_coast.place(c, hard.s, hard.d, hard.v)
		air_coast.grounded = false
		air_coast.y = hard.y
		air_coast.vy = hard.vy
		Bike.step(air_coast, c, {}, 1.0 / hz)
		Bike.step(hard, c, {"brake": 1.0, "pedal": 1.0}, 1.0 / hz)
		check(is_equal_approx(hard.v, air_coast.v) and is_equal_approx(hard.vy, air_coast.vy), "Airborne wheel lock applies no ground braking force")
		hard.place(c, 20.0, 0.0, 12.0)
		Bike.step(hard, c, {"brake": 1.0}, 1.0 / hz)
		view.pose(hard, c, 1.0 / hz)
		check(marks.segments.size() == count, "Respawn starts a fresh strip without bridging")
		Bike.step(hard, c, {}, 1.0 / hz)
		view.pose(hard, c, 1.0 / hz)
		check(not hard.brake_locked and view._front_spin_rate > 0.0 and view._rear_spin_rate > 0.0, "Brake release restores rolling immediately")
		check(marks.segments.size() == count, "Rolling leaves no new skid marks")
		# Sample a long straight skid to check bounded geometry and expiry.
		hard.brake_locked = true
		hard.pitch = 0.0
		hard.y = 0.0
		for tick in 400:
			hard.s += 0.2
			marks.sample(hard, c, 0.01)
		check(marks.segments.size() == marks.LIMIT, "Skid mesh stays bounded")
		hard.crashed = true
		marks.sample(hard, c, marks.LIFETIME + 0.1)
		check(marks.segments.is_empty(), "Old strips expire even while crashed")
		view.free()
	await process_frame
	print("Braking: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
