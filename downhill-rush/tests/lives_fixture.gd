extends "res://src/main.gd"

# Run the real referee/physics without generating scenery or an asynchronous
# next mountain. The fixture keeps result handling observable in headless tests.
func _ready() -> void: pass
func _process(_dt: float) -> void: pass
func _prepare_next() -> void: pass
func _end_round(winner: int) -> void:
	round_winner = winner
	if winner >= 0: players[winner].wins += 1
	phase = Phase.ROUND_OVER
