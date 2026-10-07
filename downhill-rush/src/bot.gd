class_name Bot
extends RefCounted
## A computer rider using ordinary controls. There is no trail, so it reads
## the slope ahead: it scores a fan of lines for cliffs, trees and boulders,
## picks the cheapest, and brakes for whatever that line throws at it.

var skill := 0.8
var _target_d := 0.0
var _rethink := 0.0
var _caution := 0.0     ## > 0 while the chosen line has a ledge coming up.
var _stuck := 0.0
var _progress_s := 0.0
var _rng := RandomNumberGenerator.new()

func _init(p_seed: int, p_skill: float) -> void:
	_rng.seed = p_seed
	skill = p_skill

func start_at(d: float) -> void:
	_target_d = d
	_rethink = 0.0

func think(b: Bike, c: Course, dt: float) -> Dictionary:
	if b.crashed: return {}
	# Stuck against something: pick a line well to one side.
	if b.s > _progress_s + 1.0 or b.s < _progress_s - 5.0:
		_progress_s = b.s
		_stuck = 0.0
	else:
		_stuck += dt
	if _stuck > 0.8:
		_stuck = 0.0
		_progress_s = b.s
		_target_d = b.d + (4.0 if _rng.randf() < 0.5 else -4.0)
		_rethink = 1.5
	_rethink -= dt
	if _rethink <= 0.0:
		_rethink = lerpf(0.5, 0.2, skill) + _rng.randf() * 0.15
		_choose_line(b, c)
	# Rough ground and steep pitches want a calmer pace.
	var steep := (c.height_rough(b.s + 4.0, b.d) - c.height_rough(b.s + 8.0, b.d)) / 4.0
	var target_v := 7.0 + skill * 3.5 - maxf(0.0, steep - 0.3) * 8.0
	if _caution > 0.0: target_v = minf(target_v, 4.5 + skill)
	if c.in_water(b.s + 4.0, b.d): target_v = minf(target_v, 7.0)
	var look := 5.0 + b.v * 0.4
	# In a gully there is only one way down: follow the path.
	var gully := c.section_at(b.s + look, "gully")
	if not gully.is_empty() and c.gully_fade(gully, b.s + look) > 0.2:
		_target_d = c.gully_line(gully, b.s + look)
		target_v = minf(target_v, 6.0 + skill * 1.5)
	var desired := atan2(_target_d - b.d, look)
	var across := (c.height_rough(b.s, b.d + 0.5) - c.height_rough(b.s, b.d - 0.5))
	var feed := c.curvature(b.s) * b.v / maxf(0.4, minf(2.3, 15.0 / (b.v + 4.0)))
	# Lean into the side slope so it doesn't drag us off the line.
	var steer := clampf((desired - b.psi) * 3.0 + feed + across * 0.6, -1.0, 1.0)
	# Never ask the tyres for more than they have.
	var rate := minf(2.3, 15.0 / (b.v + 4.0))
	var hold := Bike.GRIP * c.grip(b.s, b.d, 0.5) / maxf(b.v, 1.0) / rate
	steer = clampf(steer, -hold, hold)
	# Something solid right in front: swerve and scrub speed.
	var heading := Vector2(cos(b.psi), sin(b.psi))
	for o in c.obstacles_near(b.s):
		if o.kind == "rock" and o.r < 0.6: continue
		var rel := Vector2(o.s - b.s, o.d - b.d)
		var along := rel.dot(heading)
		if along < 0.0 or along > 3.0 + b.v * 0.5: continue
		var side := heading.x * rel.y - heading.y * rel.x
		if absf(side) < o.r + 0.7:
			steer = -signf(side) if absf(side) > 0.05 else 1.0
			target_v = minf(target_v, 4.0)
	target_v = maxf(target_v, 2.5)
	var pedal := 0.0
	var brake := 0.0
	if b.v < target_v - 0.6: pedal = 1.0
	elif b.v > target_v + 0.4: brake = clampf((b.v - target_v) / 2.5, 0.25, 1.0)
	var hop := false
	if b.grounded and b.invulnerable <= 0.0:
		for o in c.obstacles_near(b.s):
			var ahead: float = o.s - b.s
			if o.r < 0.6 and ahead > 0.6 and ahead < 1.2 + b.v * 0.12 and absf(o.d - b.d) < o.r + 0.4:
				hop = _rng.randf() < 0.4 + skill * 0.6
	if not b.grounded:
		# In the air: square the bike up for the landing and keep off the levers.
		return {"steer": clampf(-b.yaw * 3.0, -1.0, 1.0)}
	return {"steer": steer, "pedal": pedal, "brake": brake, "hop": hop}

## Score lines across the slope over the next stretch and aim for the best.
func _choose_line(b: Bike, c: Course) -> void:
	var reach := 18.0 + b.v * 1.6
	var near: Array = []
	for o in c.obstacles_near(b.s + reach * 0.5):
		if o.s > b.s and o.s < b.s + reach: near.append(o)
	var best := b.d
	var best_cost := INF
	var best_ledge := false
	var dd := -Course.CORRIDOR + 1.5
	while dd <= Course.CORRIDOR - 1.5:
		var cost := absf(dd - b.d) * 0.12 + dd * dd * 0.002
		var ledge := false
		var u := 2.0
		while u < reach:
			var s := b.s + u
			# The line drifts from here to dd as we ride towards it.
			var d := lerpf(b.d, dd, clampf(u / 12.0, 0.0, 1.0))
			# Height lost over the next 1.5 m beyond what the slope itself loses.
			var drop := c.height_rough(s, d) - c.height_rough(s + 1.5, d) - (c.base_height(s) - c.base_height(s + 1.5))
			if drop > 1.2:
				cost += drop * (6.0 if drop > 2.5 else 1.5)
				ledge = true
			if c.in_water(s, d): cost += 0.3
			if not c.inside(s, d, 1.0): cost += 3.0
			if c.water_depth(s, d) > 0.2: cost += 4.0
			u += 1.5
		for o in near:
			var d_at := lerpf(b.d, dd, clampf((o.s - b.s) / 12.0, 0.0, 1.0))
			if absf(o.d - d_at) < o.r + 1.1:
				cost += 1.0 if o.kind == "rock" and o.r < 0.6 else 6.0
		cost += _rng.randf() * (1.0 - skill) * 3.0
		if cost < best_cost:
			best_cost = cost
			best = dd
			best_ledge = ledge
		dd += 1.5
	_target_d = best
	_caution = 1.0 if best_ledge else 0.0
	# A big cliff coming up: head for the nearest chute in good time.
	var band := c.band_ahead(b.s, reach + 25.0)
	if not band.is_empty() and band.h > 3.0:
		var pick := INF
		for chute in band.chutes:
			if absf(chute.d - b.d) < absf(pick - b.d): pick = chute.d
		_target_d = pick
		_caution = 1.0 if band.s - b.s < 30.0 else _caution
	# A gorge: line up with a rock bridge well before it.
	var gorge := c.section_at(b.s + reach + 10.0, "chasm")
	if gorge.is_empty(): gorge = c.section_at(b.s + 12.0, "chasm")
	if gorge.is_empty(): gorge = c.section_at(b.s, "chasm")
	if not gorge.is_empty() and gorge.cs + gorge.w > b.s:
		var pick := INF
		for br in gorge.bridges:
			if absf(br.d - b.d) < absf(pick - b.d): pick = br.d
		_target_d = pick
		_caution = 1.0 if gorge.cs - b.s < 30.0 else _caution
