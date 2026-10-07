class_name Course
extends RefCounted
## A procedurally generated mountainside. There is no trail: riders pick their
## own line down a steep, rough slope broken by cliff bands, boulder fields,
## forest, scree and streams.
##
## Everything lives in mountain space: `s` is the distance along the fall line
## (downhill), `d` the sideways offset (positive is the rider's right). Height
## is the analytic function `height(s, d)`; the rendered terrain samples the
## same function, so what you see is what you ride.

const DS := 1.0
const CORRIDOR := 18.0         ## Rideable width each side; beyond it the valley walls rise.
const TRACK_HALF := 3.4        ## Half width of the start and finish gates.
const EDGE := 70.0             ## Terrain extends this far sideways.
const START_FLAT := 75.0
const START_LINE := 50.0       ## Riders line up here, with hillside behind for the camera.
const RUNOUT := 60.0

enum Surface { GRASS, DIRT, ROCK, SCREE, WATER }

var seed_value := 0
var length := 900.0            ## Finish line position.
var total := 960.0             ## Generated length including run-out.
var theta := PackedFloat32Array()   ## Heading of the fall line per sample.
var cx := PackedFloat32Array()
var cz := PackedFloat32Array()
var base := PackedFloat32Array()    ## Mean height of the slope.
var curv := PackedFloat32Array()    ## Signed curvature (1/m), positive turns right.
## Cliff bands across the slope: {s, h, approach, chutes: [{d, w}]}. Above each
## one the slope eases into a shelf, then drops off a ledge. Chutes are the
## few places the ledge is a rideable ramp instead.
var bands: Array[Dictionary] = []
## Streams across the slope: {s, wiggle, phase}.
var streams: Array[Dictionary] = []
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
	_place_bands()
	_place_streams()
	_place_obstacles()


# ── Fall line ────────────────────────────────────────────────────────────────

func _generate_line() -> void:
	var n := int(total / DS) + 2
	theta.resize(n); cx.resize(n); cz.resize(n); base.resize(n); curv.resize(n)
	# The fall line bends gently, so the camera swings with the mountain.
	var plan := PackedFloat32Array(); plan.resize(n)
	var i := int(START_FLAT / DS)
	var heading_budget := 0.0
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	while i < n:
		i += _rng.randi_range(30, 90)
		var radius := _rng.randf_range(70.0, 160.0)
		var turn_len := _rng.randi_range(25, 55)
		if absf(heading_budget) > 0.45: side = -signf(heading_budget)
		elif _rng.randf() < 0.7: side = -side
		var k := side / radius
		for j in turn_len:
			if i + j >= n: break
			plan[i + j] = k * sin(float(j) / turn_len * PI)
		heading_budget += k * turn_len * 0.64
		i += turn_len
	# Steep, steeper, and the odd bench to catch your breath.
	var grade := PackedFloat32Array(); grade.resize(n)
	var g := 0.3
	var target := 0.3
	for j in n:
		if j % 30 == 0: target = _rng.randf_range(0.28, 0.62) if _rng.randf() < 0.82 else 0.12
		g = lerpf(g, target, 0.07)
		grade[j] = 0.06 if j * DS < START_FLAT else (0.08 if j * DS > length + 8.0 else g)
	var th := 0.0
	var x := 0.0
	var z := 0.0
	var y := 0.0
	for j in n:
		var th_next := clampf(th + plan[j] * DS, -1.2, 1.2)
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

## How wild the ground is: 0 on the start and finish, 1 on the mountain.
func _wild(s: float) -> float:
	return smoothstep(START_FLAT - 10.0, START_FLAT + 25.0, s) * (1.0 - smoothstep(length - 25.0, length - 5.0, s))

func height(s: float, d: float) -> float:
	var h := base_height(s)
	var ad := absf(d)
	var wild := _wild(s)
	# Valley walls keep the field together.
	if ad > CORRIDOR:
		var o := ad - CORRIDOR
		h += 0.9 * pow(o, 1.35) + _noise.get_noise_2d(s, d) * minf(o * 0.3, 5.0)
	h += 0.004 * d * d
	# Rolls, spines and hollows, then rubble on top.
	h += wild * (_noise.get_noise_2d(s * 4.0, d * 4.0) * 1.9 + _noise.get_noise_2d(s * 14.0 + 300.0, d * 14.0) * 0.35)
	h += wild * _detail.get_noise_2d(s, d) * 0.16
	h += _bands_at(s, d)
	h -= _stream_at(s, d)
	return h

func _bands_at(s: float, d: float) -> float:
	var total_h := 0.0
	for b in bands:
		var u: float = s - b.s
		if u < -b.approach or u > 2.0: continue
		var lift: float = b.h * (0.75 + 0.25 * _noise.get_noise_1d(d * 3.0 + b.s))
		# The shelf builds up over the approach, so the ground eases off
		# before the ledge, then the full height drops away at once.
		var shelf := smoothstep(-b.approach, -b.approach * 0.35, u)
		var w := _ledge_width(b, d)
		var off := 1.0 - smoothstep(-w * 0.5, w * 0.5, u)
		total_h += lift * shelf * off
	return total_h

## 0.6 m: a ledge you fly off. Inside a chute it stretches into a ramp you can roll.
func _ledge_width(b: Dictionary, d: float) -> float:
	var w := 0.6
	for c in b.chutes:
		var t: float = 1.0 - smoothstep(c.w * 0.5, c.w * 0.5 + 1.5, absf(d - c.d))
		w = maxf(w, lerpf(0.6, maxf(9.0, b.h * 2.8), t))
	return w

func _stream_line(st: Dictionary, d: float) -> float:
	return st.s + sin(d * st.wiggle + st.phase) * 3.0

func _stream_at(s: float, d: float) -> float:
	var depth := 0.0
	for st in streams:
		var u: float = s - _stream_line(st, d)
		if absf(u) > 4.0: continue
		depth = maxf(depth, 0.8 * exp(-u * u / 2.2))
	return depth

## A coarse height lookup for planning (bots), filled in one 1 m row at a time
## as it's first asked for. Physics always uses the exact `height`.
var _rough_rows := {}
const _ROUGH_HALF := 24

func height_rough(s: float, d: float) -> float:
	var i := int(floor(s))
	var fs := s - i
	var fd := clampf(d + _ROUGH_HALF, 0.0, _ROUGH_HALF * 2 - 0.001)
	var j := int(fd)
	var r0 := _rough_row(i)
	var r1 := _rough_row(i + 1)
	var a := lerpf(r0[j], r0[j + 1], fd - j)
	var b := lerpf(r1[j], r1[j + 1], fd - j)
	return lerpf(a, b, fs)

func _rough_row(i: int) -> PackedFloat32Array:
	if _rough_rows.has(i): return _rough_rows[i]
	var row := PackedFloat32Array()
	row.resize(_ROUGH_HALF * 2 + 1)
	for j in row.size():
		row[j] = height(float(i), float(j - _ROUGH_HALF))
	_rough_rows[i] = row
	return row

## Ground slope along s and d (rise per metre).
func gradient(s: float, d: float) -> Vector2:
	var e := 0.15
	return Vector2((height(s + e, d) - height(s - e, d)) / (2 * e),
		(height(s, d + e) - height(s, d - e)) / (2 * e))

func in_water(s: float, d: float) -> bool:
	for st in streams:
		if absf(s - _stream_line(st, d)) < 1.1: return true
	return false

## What the ground is made of, for grip and for paint.
func surface(s: float, d: float, slope: float = -1.0) -> int:
	if in_water(s, d): return Surface.WATER
	if slope < 0.0: slope = gradient(s, d).length()
	if slope > 1.3: return Surface.ROCK
	if _wild(s) > 0.5 and _noise.get_noise_2d(s * 2.2 + 700.0, d * 2.2) > 0.32: return Surface.SCREE
	if _noise.get_noise_2d(s * 3.0 + 1500.0, d * 3.0) > 0.18: return Surface.DIRT
	return Surface.GRASS

## How well tyres hold on the ground here, relative to packed dirt.
func grip(s: float, d: float, slope: float = -1.0) -> float:
	match surface(s, d, slope):
		Surface.WATER: return 0.55
		Surface.SCREE: return 0.6
		Surface.ROCK: return 0.85
		Surface.GRASS: return 0.9
	return 1.0


# ── Cliff bands and streams ──────────────────────────────────────────────────

func _place_bands() -> void:
	var s := START_FLAT + 45.0
	while s < length - 40.0:
		var big := _rng.randf() < 0.45
		var b := {"s": s, "h": _rng.randf_range(4.5, 7.0) if big else _rng.randf_range(1.4, 2.6),
			"approach": _rng.randf_range(14.0, 24.0), "chutes": []}
		# Big cliffs have one or two ways down; small ledges a few.
		for k in (_rng.randi_range(1, 2) if big else _rng.randi_range(2, 3)):
			b.chutes.append({"d": _rng.randf_range(-CORRIDOR + 4.0, CORRIDOR - 4.0), "w": _rng.randf_range(2.5, 4.5)})
		bands.append(b)
		s += _rng.randf_range(55.0, 95.0)

func _place_streams() -> void:
	var s := START_FLAT + 80.0
	while s < length - 40.0:
		var clear := true
		for b in bands:
			if s > b.s - b.approach - 6.0 and s < b.s + 8.0: clear = false
		if clear:
			streams.append({"s": s, "wiggle": _rng.randf_range(0.08, 0.2), "phase": _rng.randf() * TAU})
			s += _rng.randf_range(140.0, 220.0)
		else:
			s += 10.0

func band_ahead(s: float, within: float) -> Dictionary:
	for b in bands:
		if b.s >= s and b.s <= s + within: return b
	return {}


# ── Obstacles ────────────────────────────────────────────────────────────────

func _place_obstacles() -> void:
	var s := START_FLAT
	while s < length - 10.0:
		# Forest clumps with gaps to thread, boulder fields, loose rocks.
		var d := -CORRIDOR - 6.0
		while d < CORRIDOR + 6.0:
			var ss := s + _rng.randf_range(0.0, 4.0)
			var dd := d + _rng.randf_range(-1.0, 1.0)
			var forest := _noise.get_noise_2d(ss * 1.4 + 900.0, dd * 1.4)
			var rocky := _noise.get_noise_2d(ss * 1.8 + 2300.0, dd * 1.8)
			var roll := _rng.randf()
			if forest > 0.12 and roll < 0.38:
				_add_obstacle(ss, dd, 0.45, 9.0, "tree")
			elif rocky > 0.18 and roll < 0.22:
				var r := _rng.randf_range(0.8, 2.0)
				_add_obstacle(ss, dd, r, r * 0.9, "rock")
			elif roll < 0.035:
				var r := _rng.randf_range(0.3, 0.55)
				_add_obstacle(ss, dd, r, r * 0.8, "rock")
			d += 3.0
		s += 4.0

func _add_obstacle(s: float, d: float, r: float, h: float, kind: String) -> void:
	if s < START_FLAT + 8.0: return
	if s > length - 12.0 and s < length + 6.0 and absf(d) < TRACK_HALF + 3.0: return
	for b in bands:
		if absf(s - b.s) < r + 1.5: return
	if _stream_at(s, d) > 0.2: return
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
