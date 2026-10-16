extends SceneTree

class FlatCourse extends Course:
	func height(_s: float, _d: float) -> float: return 0.0
	func gradient(_s: float, _d: float) -> Vector2: return Vector2.ZERO
	func curvature(_s: float) -> float: return 0.0
	func heading(_s: float) -> float: return 0.0
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return []

var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://tests/lives_fixture.gd").new()
	root.add_child(game)
	game.course = FlatCourse.new(42, 900.0)
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	var up_dir := -Vector3.BACK.rotated(Vector3.UP, deg_to_rad(-45.0))
	game.camera.position = -up_dir * 26.0 + Vector3.UP * 27.0
	game.camera.look_at(Vector3.ZERO, up_dir)
	var basis: Basis = game.camera.global_transform.basis
	var sdk = root.get_node("GameNight")
	sdk.phase = "running"
	sdk.party = {"seats": [{"index": 0, "controller": "pad"}]}
	var ControlsScript = load("res://src/controls.gd")
	var controls = ControlsScript.new(ControlsScript.Source.SEAT, 0)
	for direction in [Vector2.UP, Vector2(1,-1), Vector2.RIGHT, Vector2(1,1), Vector2.DOWN, Vector2(-1,1), Vector2.LEFT, Vector2(-1,-1)]:
		var stick: Vector2 = direction.normalized()
		sdk._frames = {"pad": {"buttons": 0, "axes": [int(stick.x * 32767), int(stick.y * 32767), 0, 0, 0, 0]}}
		sdk._frame_at = Time.get_ticks_msec()
		var input: Dictionary = controls.raw()
		check(input.stick.distance_to(stick) < .001, "Managed input preserves diagonal %s" % direction)
		var bike := Bike.new()
		bike.place(game.course, 100.0, 0.0, 4.0)
		var aligned := false
		for tick in 600:
			Bike.step(bike, game.course, {"steer": game._aim_steer(bike, input.stick), "pedal": .1}, 1.0 / 120.0)
			var motion := Vector3(-sin(bike.psi), 0, cos(bike.psi))
			var projected := Vector2(motion.dot(basis.x), -motion.dot(basis.y)).normalized()
			if projected.dot(stick) > .995:
				aligned = true
				break
		check(aligned and not bike.crashed, "Bike can turn toward screen direction %s" % direction)
	# Slow, deliberate uphill/sideways riding is movement, not a stuck bike.
	for heading in [PI, PI * .5, -PI * .5]:
		var bike := Bike.new()
		bike.place(game.course, 100.0, 0.0, 1.0)
		bike.psi = heading
		for tick in 480: Bike.step(bike, game.course, {"pedal": .03}, 1.0 / 120.0)
		check(not bike.crashed, "Slow movement at heading %s does not trip stuck recovery" % heading)
		if heading == PI: check(bike.s < 96.0, "Uphill heading actually travels back up the trail")
	# A hop landing must preserve an uphill heading rather than snap downhill.
	var landing := Bike.new()
	landing.place(game.course, 100.0, 0.0, 4.0)
	landing.psi = PI - .1
	landing.grounded = false
	landing.vy = -1.0
	landing.air_time = .1
	Bike._land(landing, game.course, 0.0)
	check(absf(wrapf(landing.psi - (PI - .1), -PI, PI)) < .001, "Landing preserves uphill heading")
	game.free()
	print("STEERING_RESULT %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
