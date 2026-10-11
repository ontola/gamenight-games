extends SceneTree
## Exercise actual rider nodes, independently of trajectory/physics.

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _init() -> void:
	call_deferred("run")

func state(b: Bike) -> Array:
	return [b.s, b.d, b.y, b.v, b.vy, b.psi, b.pitch, b.lean, b.grounded, b.crashed, b.pedaling]

func foot(view: RiderView) -> Vector3:
	return view.bike.transform.affine_inverse() * (view.rider.transform * view._legs[0].shoe.position)

func run() -> void:
	var c := Course.new(42, 900.0)
	for hz in [30, 60, 120]:
		var b := Bike.new()
		b.place(c, 20.0, 0.0)
		b.grounded = false
		b.y += 10.0
		b.pedaling = 1.0
		var view := RiderView.new()
		root.add_child(view)
		view.setup(Color.CORAL, "Animation test")
		view.pose(b, c, 0.0)
		var before := state(b)
		var start_foot := foot(view)
		var rear_before := view.rear_wheel.basis
		for frame in hz / 4: view.pose(b, c, 1.0 / hz)
		check(view._crank > 1.5, "Stationary airborne throttle turns crank @%dHz" % hz)
		check(foot(view).distance_to(start_foot) > 0.15, "Airborne legs follow the crank @%dHz" % hz)
		check(not view.rear_wheel.basis.is_equal_approx(rear_before), "Stationary airborne throttle rotates rear wheel @%dHz" % hz)
		check(view.front_wheel.basis.is_equal_approx(Basis.IDENTITY), "Undriven front wheel stays still without takeoff spin @%dHz" % hz)
		check(state(b) == before, "Posing cannot change bike trajectory or controls @%dHz" % hz)
		b.pedaling = 0.0
		var release_rate := view._rear_spin_rate
		for frame in hz: view.pose(b, c, 1.0 / hz)
		check(view._rear_spin_rate > release_rate * 0.8 and view._rear_spin_rate < release_rate, "Rear wheel coasts after releasing airborne throttle @%dHz" % hz)
		check(absf(cos(view._crank)) < 0.001, "Coasting feet settle level @%dHz" % hz)
		b.grounded = true
		b.v = 12.0
		view.pose(b, c, 1.0 / hz)
		var rolling := b.v / (RiderView.WHEEL * RiderView.SCALE)
		check(is_equal_approx(view._front_spin_rate, rolling) and is_equal_approx(view._rear_spin_rate, rolling), "Ground contact synchronizes both wheels with travel @%dHz" % hz)
		b.grounded = false
		b.v = 0.0 # Wheel inertia must not be reset by the horizontal speed.
		for frame in hz: view.pose(b, c, 1.0 / hz)
		check(view._front_spin_rate > rolling * 0.8 and is_equal_approx(view._front_spin_rate, view._rear_spin_rate), "Both free wheels retain takeoff spin @%dHz" % hz)
		b.crashed = true
		b.pedaling = 1.0
		var crash_rate := view._rear_spin_rate
		for frame in hz: view.pose(b, c, 1.0 / hz)
		check(view._rear_spin_rate < crash_rate, "Crashing stops pedal drive @%dHz" % hz)
		view.free()
	print("Rider animation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
