extends SceneTree

class FlatCourse extends Course:
	func height(_s: float, _d: float) -> float: return 0.0
	func gradient(_s: float, _d: float) -> Vector2: return Vector2.ZERO
	func curvature(_s: float) -> float: return 0.0
	func heading(_s: float) -> float: return 0.0
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return []
	func trail_d(_s: float) -> float: return 0.0
	func edges(_s: float) -> Vector2: return Vector2(-15, 15)
	func in_chasm(_s: float, _d: float) -> bool: return false
	func world(s: float, d: float, y: float = INF) -> Vector3: return Vector3(-d, 0.0 if is_inf(y) else y, s)

var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var game = load("res://tests/lives_fixture.gd").new()
	root.add_child(game)
	game.set_physics_process(false)
	game.course = FlatCourse.new(42, 900.0)
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	game.camera.position = Vector3(0, 45, 50)
	game.camera.look_at(Vector3(0, 0, 35))
	game.focus_s = 35.0
	var first: Dictionary = game._add_player("First", null, null, Color.CORAL)
	var second: Dictionary = game._add_player("Second", null, null, Color.SKY_BLUE)
	first.bike.place(game.course, 30.0, 0.0, 5.0)
	second.bike.place(game.course, 32.0, 3.0, 5.0)
	game.phase = game.Phase.RACE
	check(first.lives == 3 and second.lives == 3, "three lives by default")
	for life in [2, 1]:
		Bike._crash(first.bike, "test")
		game._physics_process(game.PHYSICS_DT)
		check(first.lives == life and not first.out and game.phase == game.Phase.RACE, "crash costs one life without ending two-player race")
		var other_distance: float = second.bike.s
		for i in 175: game._physics_process(game.PHYSICS_DT)
		check(first.lives == life and first.respawn_left == 0.0 and not first.bike.crashed, "one debit per crash, automatic protected recovery")
		check(second.bike.s > other_distance, "other rider keeps moving during recovery")
		check(first.bike.invulnerable > 0.0 and first.bike.s > 30.0, "respawn catches up on the trail with protection")
		first.bike.invulnerable = 0.0
	Bike._crash(first.bike, "test")
	game._physics_process(game.PHYSICS_DT)
	check(first.lives == 0 and first.out and game.round_winner == 1, "third crash eliminates rider and last survivor wins")
	check(second.wins == 1 and game.phase == game.Phase.ROUND_OVER, "only final elimination awards the round")
	game._on_setting("lives", 9)
	check(game.lives_per_rider == 5 and second.lives == 3, "life setting is bounded and does not rewrite current round")
	game.phase = game.Phase.RACE
	first.out = false
	first.lives = 3
	first.bike.place(game.course, -100.0, 0.0)
	first.bike.invulnerable = 0.0
	first.offscreen = 0.3
	game._referee()
	check(first.lives == 2 and first.respawn_left > 0.0 and game.phase == game.Phase.RACE, "falling off screen costs one life, not the round")
	for i in 100: game._referee()
	check(first.lives == 2, "offscreen recovery cannot charge additional lives")
	second.bike.s = game.course.length + 1.0
	game._referee()
	check(game.round_winner == 1 and game.phase == game.Phase.ROUND_OVER, "finish line still wins while opponent recovers")
	game.focus_s = game.course.length - 2.0
	game._respawn_rider(first)
	check(first.bike.s < game.course.length, "catch-up respawn never crosses finish line")
	game.free()
	print("LIVES_RESULT ", failures, " failures")
	quit(1 if failures else 0)
