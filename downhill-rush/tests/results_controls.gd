extends SceneTree

class TestControls extends RefCounted:
	var commands := {"pedal": 1.0, "steer": 0.4, "brake": 0.0, "hop": false}
	var reads := 0
	func bike_input() -> Dictionary:
		reads += 1
		return commands.duplicate()

class FlatCourse extends Course:
	func height(_s: float, _d: float) -> float: return 0.0
	func gradient(_s: float, _d: float) -> Vector2: return Vector2.ZERO
	func curvature(_s: float) -> float: return 0.0
	func heading(_s: float) -> float: return 0.0
	func grip(_s: float, _d: float, _slope: float = -1.0) -> float: return 1.0
	func water_depth(_s: float, _d: float) -> float: return 0.0
	func obstacles_near(_s: float) -> Array: return []

var failures := 0
func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var Main = load("res://src/main.gd")
	var game = Main.new()
	game.course = FlatCourse.new(42, 900.0)
	for phase in [Main.Phase.ROUND_OVER, Main.Phase.MATCH_OVER]:
		for finished in [false, true]:
			var controls := TestControls.new()
			var bike := Bike.new()
			bike.place(game.course, 30.0, 0.0, 8.0)
			var loser := Bike.new()
			loser.place(game.course, 15.0, 3.0, 5.0)
			var loser_controls := TestControls.new()
			game.players.assign([
				{"bike": bike, "controls": controls, "bot": null, "out": false, "finished": finished, "wins": 1},
				{"bike": loser, "controls": loser_controls, "bot": null, "out": true, "finished": false, "wins": 0},
			])
			game.phase = phase
			game.round_winner = 0
			var initial_speed := bike.v
			for i in 30: game._physics_process(Main.PHYSICS_DT)
			check(controls.reads == 30 and bike.pedaling > .9 and bike.v > initial_speed, "winner can pedal during %s, finished=%s" % [phase, finished])
			check(absf(bike.psi) > .01, "winner can steer during results")
			check(loser.s == 15.0 and loser_controls.reads == 0, "eliminated rider stays out")
			check(game.race_time == 0.0 and game.players[0].wins == 1 and game.round_winner == 0, "results cannot rescore or advance race timer")
			controls.commands = {"pedal": 0.0, "brake": 1.0, "steer": 0.0, "hop": true}
			game._physics_process(Main.PHYSICS_DT)
			check(not bike.grounded and bike.brake_locked, "winner can hop and brake during results")
	game.free()
	print("RESULTS_CONTROLS_RESULT ", failures, " failures")
	quit(1 if failures else 0)
