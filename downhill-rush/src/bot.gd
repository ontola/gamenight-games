class_name Bot
extends RefCounted
## A computer rider using ordinary controls: it steers for a line, judges
## its speed before each jump and hops rocks it cannot avoid.

var skill := 0.8
var line := 0.0
var _line_target := 0.0
var _retarget := 0.0
var _rng := RandomNumberGenerator.new()
var _jump_bias := 0.0
var _last_feature := -1.0

func _init(p_seed: int, p_skill: float) -> void:
	_rng.seed = p_seed
	skill = p_skill

func think(b: Bike, c: Course, dt: float) -> Dictionary:
	if b.crashed: return {}
	_retarget -= dt
	if _retarget <= 0.0:
		_retarget = _rng.randf_range(1.5, 4.0)
		_line_target = _rng.randf_range(-1.6, 1.6)
	line = move_toward(line, _line_target, dt * 1.2)
	var target_d := line
	var target_v := 11.5 + skill * 5.5
	var f := c.feature_ahead(b.s, 26.0 + b.v * 0.8)
	if not f.is_empty():
		if f.s0 != _last_feature:
			_last_feature = f.s0
			# Weaker riders misjudge more often.
			_jump_bias = _rng.randf_range(-1.0, 1.0) * (1.0 - skill) * 3.0
		if f.has("speed_min") and b.s < f.s0:
			target_d = clampf(line * 0.3, -1.0, 1.0)
			target_v = lerpf(f.speed_min, f.speed_max, 0.4) + _jump_bias
		elif int(f.kind) == Course.Kind.ROCKS:
			target_d = _gap(b, c)
			target_v = 9.0 + skill * 2.0
	var look := 6.0 + b.v * 0.45
	var desired := atan2(target_d - b.d, look)
	var feed := c.curvature(b.s) * b.v / maxf(0.4, minf(2.3, 15.0 / (b.v + 4.0)))
	var steer := clampf((desired - b.psi) * 3.0 + feed, -1.0, 1.0)
	var pedal := 0.0
	var brake := 0.0
	if b.v < target_v - 0.6: pedal = 1.0
	elif b.v > target_v + 0.6: brake = clampf((b.v - target_v) / 3.0, 0.2, 1.0)
	var hop := false
	if b.grounded and b.invulnerable <= 0.0:
		for o in c.obstacles_near(b.s):
			var ahead: float = o.s - b.s
			if o.kind == "rock" and ahead > 0.6 and ahead < 1.2 + b.v * 0.12 and absf(o.d - b.d) < o.r + 0.4:
				hop = _rng.randf() < 0.4 + skill * 0.6
	return {"steer": steer, "pedal": pedal, "brake": brake, "hop": hop}

## Pick the widest gap between rocks over the next stretch.
func _gap(b: Bike, c: Course) -> float:
	var best := 0.0
	var best_clear := -INF
	var rocks := c.obstacles_near(b.s + 8.0)
	var dd := -2.8
	while dd <= 2.8:
		var clear := INF
		for o in rocks:
			if o.s < b.s or o.s > b.s + 16.0: continue
			clear = minf(clear, absf(o.d - dd) - o.r)
		clear -= absf(dd - b.d) * 0.15
		if clear > best_clear:
			best_clear = clear
			best = dd
		dd += 0.5
	return best
