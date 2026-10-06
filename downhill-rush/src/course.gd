class_name Course
extends RefCounted
## A procedurally generated mountain run.
##
## Everything lives in track space: `s` is the distance along the centre line
## (downhill), `d` the sideways offset (positive is the rider's right). Height
## is the analytic function `height(s, d)`; the rendered terrain samples the
## same function, so what you see is what you ride.

const DS := 1.0
const TRACK_HALF := 3.4        ## Width of the packed-dirt line, each side.
const FEATURE_FADE := 4.0      ## Features blend into the hillside over this distance.
const EDGE := 70.0             ## Terrain extends this far sideways.
const START_FLAT := 75.0
const START_LINE := 50.0     ## Riders line up here, with hillside behind for the camera.
const RUNOUT := 60.0

enum Kind { GAP, TABLE, DROP, ROLLERS, ROCKS, STEP_UP }

var seed_value := 0
var length := 900.0            ## Finish line position.
var total := 960.0             ## Generated length including run-out.
var theta := PackedFloat32Array()   ## Heading of the centre line per sample.
var cx := PackedFloat32Array()
var cz := PackedFloat32Array()
var base := PackedFloat32Array()    ## Centre-line height before features.
var curv := PackedFloat32Array()    ## Signed curvature (1/m), positive turns right.
var features: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []   ## {s, d, r, h, kind}
var _buckets: Dictionary = {}           ## int(s/10) -> Array of obstacle indices
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()


func _init(p_seed: int = 1, p_length: float = 900.0) -> void:
	seed_value = p_seed
	length = p_length
	total = length + RUNOUT
	_rng.seed = p_seed
	_noise.seed = p_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.012
	_noise.fractal_octaves = 3
	_detail.seed = p_seed + 77
	_detail.noise_type = FastNoiseLite.TYPE_VALUE
	_detail.frequency = 0.35
	_generate_line()
	_place_features()
	_place_obstacles()


# ── Centre line ──────────────────────────────────────────────────────────────

func _generate_line() -> void:
	var n := int(total / DS) + 2
	theta.resize(n); cx.resize(n); cz.resize(n); base.resize(n); curv.resize(n)
	# Curvature plan: a twisting trail. Mostly tight corners you have to brake
	# for, sometimes a fast sweeper, short straights in between.
	var plan := PackedFloat32Array(); plan.resize(n)
	var i := int(START_FLAT / DS)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var heading_budget := 0.0
	while i < n:
		var straight := _rng.randi_range(8, 30) if _rng.randf() < 0.7 else _rng.randi_range(35, 60)
		i += straight
		var tight := _rng.randf() < 0.65
		var radius := _rng.randf_range(16.0, 34.0) if tight else _rng.randf_range(45.0, 90.0)
		var turn_len := _rng.randi_range(14, 26) if tight else _rng.randi_range(25, 50)
		# Keep the overall direction downhill (+Z): turn back when drifting.
		if absf(heading_budget) > 0.5: side = -signf(heading_budget)
		elif _rng.randf() < 0.7: side = -side
		var k := side / radius
		for j in turn_len:
			if i + j >= n: break
			var t := float(j) / turn_len
			plan[i + j] = k * minf(1.0, sin(t * PI) * 1.6)
		heading_budget += k * turn_len * 0.8
		i += turn_len
	# Grade plan: a steep-ish mountain with mellow and steep pitches.
	var grade := PackedFloat32Array(); grade.resize(n)
	var g := 0.2
	var target := 0.2
	for j in n:
		if j % 35 == 0: target = _rng.randf_range(0.06, 0.42) if _rng.randf() < 0.8 else 0.03
		g = lerpf(g, target, 0.06)
		grade[j] = 0.06 if j * DS < START_FLAT else g
	# Integrate.
	var th := 0.0
	var x := 0.0
	var z := 0.0
	var y := 0.0
	for j in n:
		var th_next := clampf(th + plan[j] * DS, -1.35, 1.35)
		curv[j] = (th_next - th) / DS
		th = th_next
		theta[j] = th
		cx[j] = x; cz[j] = z; base[j] = y
		x += sin(th) * DS
		z += cos(th) * DS
		y -= grade[j] * DS


func _sample(arr: PackedFloat32Array, s: float) -> float:
	var f := clampf(s / DS, 0.0, arr.size() - 1.001)
	var i := int(f)
	return lerpf(arr[i], arr[i + 1], f - i)

func heading(s: float) -> float: return _sample(theta, s)
func curvature(s: float) -> float: return _sample(curv, s)
func base_height(s: float) -> float: return _sample(base, s)

func forward(s: float) -> Vector3:
	var th := heading(s)
	return Vector3(sin(th), 0, cos(th))

## Positive `d` lies on the rider's right.
func right(s: float) -> Vector3:
	var th := heading(s)
	return Vector3(-cos(th), 0, sin(th))

func world(s: float, d: float, y: float = INF) -> Vector3:
	var p := Vector3(_sample(cx, s), 0, _sample(cz, s)) + right(s) * d
	p.y = height(s, d) if y == INF else y
	return p


# ── Height ───────────────────────────────────────────────────────────────────

func height(s: float, d: float) -> float:
	var h := base_height(s)
	var ad := absf(d)
	# The run is cut into a steep mountainside: rock wall on the uphill side,
	# a drop into a ravine with a stream on the other. Which side is which
	# swaps slowly along the run.
	if ad > TRACK_HALF:
		var o := ad - TRACK_HALF
		var wall := clampf(wall_side(s) * signf(d) * 1.6, -1.0, 1.0) * 0.5 + 0.5
		var rise := 0.4 * o + 1.5 * maxf(0.0, o - 1.5) * (1.0 - smoothstep(10.0, 22.0, o) * 0.6)
		var fall := -1.25 * pow(maxf(0.0, o - 1.0), 1.15)
		h += clampf(lerpf(fall, rise, wall), -RAVINE, 14.0) + _noise.get_noise_2d(s, d) * minf(o * 0.3, 4.0)
	# Banked turns: raise the outside of the bend.
	var k := curvature(s)
	if ad < TRACK_HALF + FEATURE_FADE:
		var bank := clampf(k * 160.0, -1.0, 1.0) * 0.22
		var w := _fade(ad)
		h += bank * clampf(d, -TRACK_HALF, TRACK_HALF) * w
		# Roots, ruts and off-camber: the trail is never quite flat.
		h += (_detail.get_noise_2d(s, d) * 0.16 + camber(s) * d) * w
	h += _features_at(s, d)
	return h

const RAVINE := 15.0            ## Deepest the ravine beside the run gets.
const WATER := 13.0             ## Stream surface below the run.

## +1 when the rock wall is on the right, -1 when it's on the left.
func wall_side(s: float) -> float:
	return clampf(_noise.get_noise_1d(s * 0.35 + 900.0) * 10.0, -1.0, 1.0)

## Sideways tilt of the trail (rise per metre to the right).
func camber(s: float) -> float:
	if s < START_FLAT: return 0.0
	return _noise.get_noise_1d(s * 1.7 + 300.0) * 0.16

## Centre of the worn single-track inside the wider rideable line.
func path_offset(s: float) -> float:
	return _detail.get_noise_1d(s * 0.6 + 77.0) * 1.8

func _fade(ad: float) -> float:
	if ad <= TRACK_HALF: return 1.0
	if ad >= TRACK_HALF + FEATURE_FADE: return 0.0
	var t := (ad - TRACK_HALF) / FEATURE_FADE
	return 1.0 - t * t * (3.0 - 2.0 * t)

func _features_at(s: float, d: float) -> float:
	var ad := absf(d)
	if ad >= TRACK_HALF + FEATURE_FADE: return 0.0
	var total_h := 0.0
	for f in features:
		var u: float = s - f.s0
		if u < -0.5 or u > f.len + 0.5: continue
		total_h += feature_profile(f, u) * _fade(ad)
	return total_h

## Height a feature adds at `u` metres past its start.
static func feature_profile(f: Dictionary, u: float) -> float:
	match int(f.kind):
		Kind.GAP, Kind.TABLE:
			var lr: float = f.ramp
			var h: float = f.h
			var gap: float = f.gap
			var land: float = f.land
			if u < 0: return 0.0
			if u < lr: return h * pow(u / lr, 1.7)
			if u < lr + gap:
				if int(f.kind) == Kind.TABLE: return h
				var t := (u - lr) / gap
				# Steep sides down into the gap, then back up to the knuckle.
				if t < 0.75: return lerpf(h, -0.4, smoothstep(0.0, 0.25, t))
				return lerpf(-0.4, h * 0.85, smoothstep(0.75, 1.0, t))
			var knuckle: float = h * (0.85 if int(f.kind) == Kind.GAP else 1.0)
			var v := u - lr - gap
			if v < 1.0: return knuckle
			if v < land: return knuckle * (1.0 - smoothstep(1.0, land, v) * 1.0)
			return 0.0
		Kind.DROP:
			# A shelf rising out of the slope, a ledge, then a steep landing.
			var lr: float = f.ramp
			var h: float = f.h
			var land: float = f.land
			if u < 0: return 0.0
			if u < lr: return h * smoothstep(0.0, 1.0, u / lr)
			if u < lr + 0.6: return lerpf(h, h * 0.45, (u - lr) / 0.6)
			var v := u - lr - 0.6
			if v < land: return h * 0.45 * (1.0 - v / land)
			return 0.0
		Kind.STEP_UP:
			var h: float = f.h
			if u < 0: return 0.0
			if u < 3.0: return h * smoothstep(0.0, 3.0, u)
			if u < f.len - 6.0: return h
			return h * (1.0 - smoothstep(f.len - 6.0, f.len, u))
		Kind.ROLLERS:
			var wl: float = f.wave
			var a: float = f.h
			if u < 0 or u > f.len: return 0.0
			return a * 0.5 * (1.0 - cos(u / wl * TAU))
	return 0.0

## Ground slope along s and d (rise per metre).
func gradient(s: float, d: float) -> Vector2:
	var e := 0.15
	return Vector2((height(s + e, d) - height(s - e, d)) / (2 * e),
		(height(s, d + e) - height(s, d - e)) / (2 * e))


# ── Features ─────────────────────────────────────────────────────────────────

func _max_curv(s0: float, s1: float) -> float:
	var m := 0.0
	var s := s0
	while s <= s1:
		m = maxf(m, absf(curvature(s)))
		s += 2.0
	return m

func _place_features() -> void:
	var s := START_FLAT + 25.0
	var last_kind := -1
	while s < length - 50.0:
		var straightish := _max_curv(s, s + 30.0) < 1.0 / 70.0
		var roll := _rng.randf()
		var f := {}
		if straightish and roll < 0.32 and last_kind != Kind.GAP:
			var h := _rng.randf_range(1.0, 1.7)
			f = {"kind": Kind.GAP, "ramp": _rng.randf_range(4.0, 5.5), "h": h,
				"gap": _rng.randf_range(3.5, 6.5), "land": _rng.randf_range(7.0, 9.0)}
		elif straightish and roll < 0.5:
			f = {"kind": Kind.TABLE, "ramp": _rng.randf_range(4.0, 5.5), "h": _rng.randf_range(0.9, 1.5),
				"gap": _rng.randf_range(4.0, 7.0), "land": _rng.randf_range(6.0, 8.0)}
		elif straightish and roll < 0.66 and last_kind != Kind.DROP:
			f = {"kind": Kind.DROP, "ramp": _rng.randf_range(10.0, 16.0), "h": _rng.randf_range(2.2, 3.2),
				"land": _rng.randf_range(6.0, 8.0)}
			f.len = f.ramp + 0.6 + f.land
		elif roll < 0.8 or (not straightish and roll < 0.86):
			f = {"kind": Kind.ROLLERS, "wave": _rng.randf_range(6.0, 8.5), "h": _rng.randf_range(0.45, 0.75)}
			f.len = f.wave * _rng.randi_range(3, 5)
		elif roll < 0.9:
			f = {"kind": Kind.STEP_UP, "h": _rng.randf_range(0.5, 0.8)}
			f.len = _rng.randf_range(14.0, 20.0)
		else:
			f = {"kind": Kind.ROCKS}
			f.len = _rng.randf_range(22.0, 34.0)
		if not f.has("len"):
			f.len = f.ramp + f.gap + f.land
		f.s0 = s
		features.append(f)
		last_kind = int(f.kind)
		s += f.len + _rng.randf_range(14.0, 34.0)
	_calibrate_jumps()

## Find the take-off speeds that land each jump cleanly, using the same
## physics the riders use. Jumps nobody could clear are softened.
func _calibrate_jumps() -> void:
	for f in features:
		if int(f.kind) not in [Kind.GAP, Kind.TABLE, Kind.DROP]: continue
		for attempt in 4:
			var window := _speed_window(f)
			if window.y > window.x:
				f.speed_min = window.x
				f.speed_max = window.y
				break
			# Too hard: shrink the gap/height and try again.
			if f.has("gap"): f.gap *= 0.75
			f.h *= 0.85
			if f.has("gap"): f.len = f.ramp + f.gap + f.land
		if not f.has("speed_min"):
			f.kind = Kind.TABLE
			f.speed_min = 3.0
			f.speed_max = 14.0

func _speed_window(f: Dictionary) -> Vector2:
	var lo := INF
	var hi := -INF
	var v := 4.0
	while v <= 22.0:
		var b := Bike.new()
		b.place(self, f.s0 - 1.5, 0.0, v)
		var ok := true
		for step in 180:
			Bike.step(b, self, {}, 1.0 / 60.0)
			if b.crashed or b.hard_landing:
				ok = false
				break
			if b.s > f.s0 + f.len + 4.0 and b.grounded: break
		if ok and b.s > f.s0 + f.len:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		v += 0.5
	return Vector2(lo, hi)

func feature_ahead(s: float, within: float) -> Dictionary:
	for f in features:
		if f.s0 + f.len >= s and f.s0 <= s + within: return f
	return {}


# ── Obstacles ────────────────────────────────────────────────────────────────

func _place_obstacles() -> void:
	# Trees and boulders off the line. Kept out of the camera's way near start.
	var s := 0.0
	while s < total:
		for side in [-1.0, 1.0]:
			var count := _rng.randi_range(2, 8)
			for c in count:
				var d: float = side * _rng.randf_range(TRACK_HALF + 2.0, EDGE - 2.0)
				var ss := s + _rng.randf_range(0.0, 6.0)
				# Forests come in clumps with open meadows between them.
				var dense := _noise.get_noise_2d(ss * 1.7 + 900.0, d * 1.7) > -0.05
				if not dense and _rng.randf() < 0.85: continue
				if _rng.randf() < 0.78:
					_add_obstacle(ss, d, 0.45, 9.0, "tree")
				else:
					var r := _rng.randf_range(0.7, 1.8)
					_add_obstacle(ss, d, r, r * 0.9, "rock")
		s += 6.0
	# Rocks in rock gardens sit on the line with gaps to thread.
	for f in features:
		if int(f.kind) != Kind.ROCKS: continue
		var u := 3.0
		while u < f.len - 3.0:
			var gap_d := _rng.randf_range(-2.0, 2.0)
			for d in [-2.7, -1.35, 0.0, 1.35, 2.7]:
				if absf(d - gap_d) < 1.2: continue
				if _rng.randf() < 0.55:
					var r := _rng.randf_range(0.35, 0.6)
					_add_obstacle(f.s0 + u + _rng.randf_range(-1.0, 1.0), d + _rng.randf_range(-0.4, 0.4), r, r * 0.8, "rock")
			u += _rng.randf_range(5.0, 7.5)
	# A few lone trees and stumps encroach on the edges of the line.
	for k in int(length / 60.0):
		var ss := _rng.randf_range(START_FLAT + 20.0, length - 20.0)
		if not feature_ahead(ss - 8.0, 16.0).is_empty(): continue
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		_add_obstacle(ss, side * _rng.randf_range(TRACK_HALF - 0.3, TRACK_HALF + 1.5), 0.45, 9.0, "tree")

func _add_obstacle(s: float, d: float, r: float, h: float, kind: String) -> void:
	if s < START_FLAT and absf(d) < TRACK_HALF + 4.0: return
	if s > length - 6.0 and s < length + 6.0 and absf(d) < TRACK_HALF + 3.0: return
	var index := obstacles.size()
	obstacles.append({"s": s, "d": d, "r": r, "h": h, "kind": kind})
	var key := int(s / 10.0)
	if not _buckets.has(key): _buckets[key] = []
	_buckets[key].append(index)

func obstacles_near(s: float) -> Array:
	var out: Array = []
	var key := int(s / 10.0)
	for k in [key - 1, key, key + 1]:
		for index in _buckets.get(k, []):
			out.append(obstacles[index])
	return out
