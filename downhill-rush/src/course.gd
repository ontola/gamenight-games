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
const CORRIDOR := 26.0         ## The valley floor never reaches further than this either side.
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
## The run is a string of stretches, each with its own character, so no two
## minutes ride the same: {kind, s, len, grade, ...}. Kinds: band (cliff),
## turn (the valley swings hard to one side), flat (a bench to pedal across),
## kicker (jumps built into the slope), gully (one narrow, steep path between
## boulders), slalom (rows of trees and rocks with gaps), open (bare mountain).
var sections: Array[Dictionary] = []
var view := PackedFloat32Array()    ## Smoothed heading: the map's main direction, for the camera.
## Streams across the slope: {s, wiggle, phase}.
var streams: Array[Dictionary] = []
var obstacles: Array[Dictionary] = []   ## {s, d, r, h, kind, look}
## What kind of mountain this is: alpine, forest, autumn or desert. It picks
## the set pieces, the trees and the colours.
var biome := "alpine"
const BIOMES := ["alpine", "forest", "autumn", "desert"]
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
	biome = BIOMES[_rng.randi() % BIOMES.size()]
	_plan_sections()
	_generate_line()
	_place_streams()
	_place_obstacles()


# ── Fall line ────────────────────────────────────────────────────────────────

func _plan_sections() -> void:
	var bag: Array[String] = []
	var last := ""
	var s := START_FLAT + 30.0
	while s < length - 70.0:
		if bag.is_empty():
			bag = ["band", "band", "turn", "turn", "flat", "kicker", "kicker", "gully", "slalom", "open", "chasm", "lake"]
			if biome == "desert": bag = ["band", "band", "turn", "turn", "kicker", "kicker", "gully", "slalom", "chasm", "chasm", "open"]
			elif biome != "alpine": bag.append("lake")
			for k in range(bag.size() - 1, 0, -1):
				var m := _rng.randi_range(0, k)
				var tmp := bag[k]; bag[k] = bag[m]; bag[m] = tmp
		var kind: String = bag.pop_back()
		if kind == last and not bag.is_empty():
			bag.push_front(kind)
			kind = bag.pop_back()
		last = kind
		var sec := {"kind": kind, "s": s, "len": 30.0, "grade": -1.0}
		match kind:
			"band":
				var big := _rng.randf() < 0.5
				var h := _rng.randf_range(4.5, 7.0) if big else _rng.randf_range(1.4, 2.6)
				# The shelf above a ledge rises out of the slope; keep it gentle
				# enough that a rider who stalls there can still roll on.
				var approach := maxf(_rng.randf_range(14.0, 20.0), h * 4.2)
				var b := {"s": s + approach + 4.0, "h": h, "approach": approach, "chutes": []}
				for k in (_rng.randi_range(1, 2) if big else _rng.randi_range(2, 3)):
					var e := edges(b.s)
					b.chutes.append({"d": _rng.randf_range(e.x + 4.0, e.y - 4.0), "w": _rng.randf_range(2.5, 4.5)})
				bands.append(b)
				sec.len = approach + 16.0
				sec.grade = 0.42
			"turn":
				sec.len = _rng.randf_range(52.0, 60.0)
				sec.angle = _rng.randf_range(1.0, 1.25)
				sec.grade = _rng.randf_range(0.3, 0.45)
			"flat":
				sec.len = _rng.randf_range(25.0, 40.0)
				sec.grade = 0.08
			"kicker":
				sec.len = 40.0
				sec.grade = 0.34
				sec.lips = []
				var d0 := _rng.randf_range(-CORRIDOR + 6.0, CORRIDOR - 6.0)
				for k in _rng.randi_range(1, 3):
					var d := d0 + (k - 1) * _rng.randf_range(9.0, 12.0) * (1.0 if d0 < 0.0 else -1.0)
					var ls := s + 20.0 + _rng.randf_range(-4.0, 4.0)
					var e := edges(ls)
					sec.lips.append({"s": ls, "d": clampf(d, e.x + 4.0, e.y - 4.0),
						"w": _rng.randf_range(2.5, 4.0), "h": _rng.randf_range(1.0, 1.6), "run": _rng.randf_range(5.0, 7.0)})
			"gully":
				sec.len = _rng.randf_range(55.0, 80.0)
				sec.grade = 0.5
				sec.d0 = _rng.randf_range(-3.0, 3.0)
				sec.amp = _rng.randf_range(2.5, 4.5)
				sec.freq = TAU / _rng.randf_range(26.0, 40.0)
				sec.hw = 2.3
			"slalom":
				sec.len = _rng.randf_range(40.0, 55.0)
				sec.grade = 0.36
			"open":
				sec.len = _rng.randf_range(20.0, 40.0)
			"lake":
				# A tarn on a bench: flat water you can ride round, or into.
				sec.len = _rng.randf_range(34.0, 44.0)
				sec.grade = 0.05
				sec.cs = s + sec.len * 0.5
				sec.rs = _rng.randf_range(8.0, 12.0)
				sec.rd = _rng.randf_range(6.0, 10.0)
				var e := edges(sec.cs)
				sec.cd = _rng.randf_range(e.x + sec.rd * 0.4, e.y - sec.rd * 0.4)
			"chasm":
				# A gorge right across the slope: cross on a rock bridge, or
				# hit the ramp and fly it.
				sec.len = 34.0
				sec.grade = 0.3
				sec.cs = s + 22.0
				sec.w = _rng.randf_range(5.5, 7.5)
				sec.depth = _rng.randf_range(9.0, 14.0)
				var e := edges(sec.cs)
				sec.bridges = []
				for k in _rng.randi_range(1, 2):
					sec.bridges.append({"d": _rng.randf_range(e.x + 3.0, e.y - 3.0), "w": _rng.randf_range(1.8, 2.6)})
				var rd := _rng.randf_range(e.x + 4.0, e.y - 4.0)
				for br in sec.bridges:
					if absf(rd - br.d) < 6.0: rd = clampf(br.d + (7.0 if br.d < 0.0 else -7.0), e.x + 4.0, e.y - 4.0)
				sec.ramp = {"d": rd, "w": 2.6, "h": 1.5, "run": 6.0}
		sections.append(sec)
		s += sec.len + _rng.randf_range(8.0, 18.0)

func section_at(s: float, kind: String = "") -> Dictionary:
	for sec in sections:
		if s >= sec.s and s < sec.s + sec.len and (kind == "" or sec.kind == kind): return sec
	return {}

func _generate_line() -> void:
	var n := int(total / DS) + 2
	theta.resize(n); cx.resize(n); cz.resize(n); base.resize(n); curv.resize(n); view.resize(n)
	# Between the set pieces the fall line wanders gently.
	var plan := PackedFloat32Array(); plan.resize(n)
	var i := int(START_FLAT / DS)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	while i < n:
		i += _rng.randi_range(6, 24)
		var radius := _rng.randf_range(45.0, 110.0)
		var turn_len := _rng.randi_range(18, 40)
		side = -side if _rng.randf() < 0.7 else side
		for j in turn_len:
			if i + j >= n: break
			plan[i + j] = side / radius * sin(float(j) / turn_len * PI)
		i += turn_len
	# Steep, steeper, and the set pieces' own grades.
	var grade := PackedFloat32Array(); grade.resize(n)
	var g := 0.3
	var target := 0.3
	for j in n:
		var sj := j * DS
		if j % 30 == 0: target = _rng.randf_range(0.28, 0.55)
		var sec := section_at(sj)
		var want: float = sec.grade if not sec.is_empty() and sec.grade >= 0.0 else target
		g = lerpf(g, want, 0.12)
		grade[j] = 0.06 if sj < START_FLAT else (0.08 if sj > length + 8.0 else g)
	var th := 0.0
	var x := 0.0
	var z := 0.0
	var y := 0.0
	var turn_dir := {}
	for j in n:
		var sj := j * DS
		var k := plan[j]
		var sec := section_at(sj, "turn")
		if not sec.is_empty():
			# A hard swing to one side, away from wherever the valley has wandered.
			if not turn_dir.has(sec.s):
				turn_dir[sec.s] = -signf(th) if absf(th) > 0.25 else (1.0 if _rng.randf() < 0.5 else -1.0)
				sec.dir = turn_dir[sec.s]
			var t: float = (sj - sec.s) / sec.len
			k = turn_dir[sec.s] * sec.angle / (0.64 * sec.len) * sin(t * PI)
		var th_next := clampf(th + k * DS, -1.3, 1.3)
		curv[j] = (th_next - th) / DS
		th = th_next
		theta[j] = th
		cx[j] = x; cz[j] = z; base[j] = y
		x += sin(th) * DS
		z += cos(th) * DS
		y -= grade[j] * DS
	# The camera keeps to the valley's overall direction, so bends and swings
	# show up on screen as riding off to one side.
	var half := 110
	for j in n:
		var acc := 0.0
		var cnt := 0
		for q in range(maxi(0, j - half), mini(n, j + half + 1), 3):
			acc += theta[q]
			cnt += 1
		view[j] = acc / cnt

func _sample(arr: PackedFloat32Array, s: float) -> float:
	var f := clampf(s / DS, 0.0, arr.size() - 1.001)
	var i := int(f)
	return lerpf(arr[i], arr[i + 1], f - i)

func heading(s: float) -> float: return _sample(theta, s)
func curvature(s: float) -> float: return _sample(curv, s)
func base_height(s: float) -> float: return _sample(base, s)
func view_heading(s: float) -> float: return _sample(view, s)

## Where the valley walls start on the left and right (x, y). Never wider
## than CORRIDOR; at the start and finish the valley is full width.
func edges(s: float) -> Vector2:
	var w := _wild(s)
	# The valley floor drifts from side to side and swells and narrows, each
	# bank on its own, so the way down never runs straight for long.
	var mid := valley_mid(s)
	var l := 10.0 + 8.0 * (0.5 + 0.5 * _noise.get_noise_2d(s * 1.3 + 5000.0, 0.0))
	var r := 10.0 + 8.0 * (0.5 + 0.5 * _noise.get_noise_2d(s * 1.3 + 9000.0, 0.0))
	return Vector2(lerpf(-CORRIDOR + 6.0, clampf(mid - l, -CORRIDOR, CORRIDOR - 20.0), w), lerpf(CORRIDOR - 6.0, clampf(mid + r, -CORRIDOR + 20.0, CORRIDOR), w))

## Middle of the valley floor at s, wandering left and right of the fall line.
func valley_mid(s: float) -> float:
	return _wild(s) * 11.0 * _noise.get_noise_2d(s * 0.75 + 3000.0, 0.0)

## True if d is inside the valley floor at s.
func inside(s: float, d: float, margin := 0.0) -> bool:
	var e := edges(s)
	return d > e.x + margin and d < e.y - margin

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
	# Valley walls keep the field together. They wander in and out, so the
	# valley pinches and opens like a real one.
	var edge := edges(s)
	var o := maxf(d - edge.y, edge.x - d)
	if o > 0.0:
		# Hillsides, not walls: how steeply they rise wanders, and they're
		# heaped with knolls and spurs.
		var lump := _noise.get_noise_2d(s * 2.2 + 600.0, d * 2.2)
		h += o * (0.45 + 0.35 * (lump + 0.5)) + 0.012 * o * o
		h += _noise.get_noise_2d(s * 1.6, d * 1.6) * minf(o * 0.5, 6.0)
	var across := d - valley_mid(s)
	h += 0.006 * across * across
	# Rolls, spines and hollows, then rubble on top. Calm round a lake.
	var calm := _lake_calm(s, d)
	wild *= calm
	h += wild * (_noise.get_noise_2d(s * 4.0, d * 4.0) * 1.9 + _noise.get_noise_2d(s * 14.0 + 300.0, d * 14.0) * 0.35)
	h += wild * _detail.get_noise_2d(s, d) * 0.16
	h += _bands_at(s, d)
	h += _set_pieces_at(s, d)
	h -= _stream_at(s, d)
	return h

## Kicker lips and gully banks.
func _set_pieces_at(s: float, d: float) -> float:
	var h := 0.0
	for sec in sections:
		if s < sec.s - 2.0 or s > sec.s + sec.len + 2.0: continue
		if sec.kind == "kicker":
			for lip in sec.lips:
				var u: float = s - lip.s
				if u < -lip.run or u > 0.6: continue
				var side := 1.0 - smoothstep(lip.w, lip.w + 1.2, absf(d - lip.d))
				if side <= 0.0: continue
				# A ramp that kicks up at the end, then the lip drops away.
				var up: float = lip.h * pow((u + lip.run) / lip.run, 2.2) if u <= 0.0 else lip.h * (1.0 - u / 0.6)
				h += up * side
		elif sec.kind == "chasm":
			var u: float = s - sec.cs
			var half: float = sec.w * 0.5
			var ramp: Dictionary = sec.ramp
			if u > -half - ramp.run and u < -half:
				var side := 1.0 - smoothstep(ramp.w, ramp.w + 1.0, absf(d - ramp.d))
				h += ramp.h * pow((u + half + ramp.run) / ramp.run, 2.2) * side
			if absf(u) < half:
				var hole: float = 1.0 - smoothstep(half - 0.5, half, absf(u))
				for br in sec.bridges:
					hole *= smoothstep(br.w * 0.5, br.w * 0.5 + 0.4, absf(d - br.d))
				h -= hole * sec.depth
		elif sec.kind == "lake":
			var q := _lake_q(sec, s, d)
			if q < 1.6:
				# A bowl under the water and a low grassy rim round it.
				h -= 2.4 * (1.0 - smoothstep(0.25, 1.05, q))
				h += 0.7 * exp(-pow((q - 1.18) / 0.16, 2.0))
		elif sec.kind == "gully":
			var off := absf(d - gully_line(sec, s))
			var e := gully_fade(sec, s)
			h += e * smoothstep(sec.hw, sec.hw + 2.2, off) * (1.7 + 0.7 * _noise.get_noise_2d(s * 3.0 + 50.0, d * 3.0))
	return h

func _lake_q(sec: Dictionary, s: float, d: float) -> float:
	var a: float = (s - sec.cs) / sec.rs
	var b: float = (d - sec.cd) / sec.rd
	# A wobbly shoreline, not an ellipse.
	var wob := 1.0 + 0.18 * sin(atan2(b, a) * 3.0 + sec.cs) + 0.1 * sin(atan2(b, a) * 5.0)
	return sqrt(a * a + b * b) / wob

func _lake_calm(s: float, d: float) -> float:
	for sec in sections:
		if sec.kind == "lake" and absf(s - sec.cs) < sec.rs * 1.6:
			return smoothstep(0.9, 1.5, _lake_q(sec, s, d))
	return 1.0

## The lake's surface height, or -INF where there is no lake.
func water_level(s: float) -> float:
	for sec in sections:
		if sec.kind == "lake" and absf(s - sec.cs) < sec.rs * 1.5:
			return base_height(sec.cs) - 0.45
	return -INF

## How deep the lake is here; 0 on dry ground.
func water_depth(s: float, d: float) -> float:
	var level := water_level(s)
	if level == -INF: return 0.0
	var sec := section_at(s, "lake")
	if sec.is_empty() or _lake_q(sec, s, d) > 1.18: return 0.0
	return maxf(0.0, level - height(s, d))

## Ground far below the slope: you're at the bottom of a gorge.
func in_chasm(s: float, d: float) -> bool:
	var sec := section_at(s, "chasm")
	return not sec.is_empty() and height(s, d) < base_height(s) - 3.0

## Centre of the gully path at s.
func gully_line(sec: Dictionary, s: float) -> float:
	return valley_mid(s) + sec.d0 + sec.amp * sin((s - sec.s) * sec.freq)

func gully_fade(sec: Dictionary, s: float) -> float:
	return smoothstep(sec.s, sec.s + 8.0, s) * (1.0 - smoothstep(sec.s + sec.len - 8.0, sec.s + sec.len, s))

func on_path(s: float, d: float) -> bool:
	var g := section_at(s, "gully")
	if not g.is_empty() and gully_fade(g, s) > 0.3 and absf(d - gully_line(g, s)) < g.hw + 0.4: return true
	var k := section_at(s, "kicker")
	if not k.is_empty():
		for lip in k.lips:
			if s - lip.s > -lip.run - 2.0 and s - lip.s < 0.6 and absf(d - lip.d) < lip.w + 0.6: return true
	return false

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
	if water_depth(s, d) > 0.05: return true
	for st in streams:
		if absf(s - _stream_line(st, d)) < 1.1: return true
	return false

## What the ground is made of, for grip and for paint.
func surface(s: float, d: float, slope: float = -1.0) -> int:
	if in_water(s, d): return Surface.WATER
	if on_path(s, d): return Surface.DIRT
	if slope < 0.0: slope = gradient(s, d).length()
	if slope > 1.3: return Surface.ROCK
	# Warp the patch noise so dirt and scree come in winding, uneven shapes.
	var ws := s + _noise.get_noise_2d(s * 3.0 + 3100.0, d * 3.0) * 6.0
	var wd := d + _noise.get_noise_2d(d * 3.0 + 4100.0, s * 3.0) * 6.0
	if _wild(s) > 0.5 and _noise.get_noise_2d(ws * 2.2 + 700.0, wd * 2.2) > 0.32: return Surface.SCREE
	if _noise.get_noise_2d(ws * 3.0 + 1500.0, wd * 3.0) > 0.18: return Surface.DIRT
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

func _place_streams() -> void:
	if biome == "desert": return
	var s := START_FLAT + 80.0
	while s < length - 40.0:
		var clear := true
		for sec in sections:
			if sec.kind != "open" and sec.kind != "flat" and s > sec.s - 6.0 and s < sec.s + sec.len + 6.0: clear = false
		if clear:
			streams.append({"s": s, "wiggle": _rng.randf_range(0.08, 0.2), "phase": _rng.randf() * TAU})
			s += _rng.randf_range(120.0, 200.0)
		else:
			s += 10.0

func band_ahead(s: float, within: float) -> Dictionary:
	for b in bands:
		if b.s >= s and b.s <= s + within: return b
	return {}


# ── Obstacles ────────────────────────────────────────────────────────────────

func _place_obstacles() -> void:
	_place_set_piece_obstacles()
	var s := START_FLAT
	while s < length - 10.0:
		# Forest clumps with gaps to thread, boulder fields, loose rocks.
		var d := -CORRIDOR - 14.0
		while d < CORRIDOR + 14.0:
			var ss := s + _rng.randf_range(0.0, 4.0)
			var dd := d + _rng.randf_range(-1.0, 1.0)
			var forest := _noise.get_noise_2d(ss * 1.4 + 900.0, dd * 1.4)
			var rocky := _noise.get_noise_2d(ss * 1.8 + 2300.0, dd * 1.8)
			var roll := _rng.randf()
			var e := edges(ss)
			var wall := maxf(dd - e.y, e.x - dd)
			if wall > 1.5 and roll < 0.3 and _noise.get_noise_2d(ss * 2.5 + 1200.0, dd * 2.5) < 0.15:
				# The valley sides are wooded.
				_add_obstacle(ss, dd, 0.45, 9.0, "tree")
			elif forest > 0.12 and roll < 0.38:
				_add_obstacle(ss, dd, 0.45, 9.0, "tree")
			elif rocky > 0.18 and roll < 0.22:
				var r := _rng.randf_range(0.8, 2.0)
				_add_obstacle(ss, dd, r, r * 0.9, "rock")
			elif roll < 0.035:
				var r := _rng.randf_range(0.3, 0.55)
				_add_obstacle(ss, dd, r, r * 0.8, "rock")
			d += 3.0
		s += 4.0

## Gully banks thick with boulders and pines; slalom rows with a few gaps.
func _place_set_piece_obstacles() -> void:
	for sec in sections:
		if sec.kind == "gully":
			var s: float = sec.s + 6.0
			while s < sec.s + sec.len - 4.0:
				var mid := gully_line(sec, s)
				var d := -CORRIDOR - 4.0
				while d < CORRIDOR + 4.0:
					var dd := d + _rng.randf_range(-0.6, 0.6)
					var off := absf(dd - mid)
					if off > sec.hw + 1.6 and _rng.randf() < 0.75:
						if _rng.randf() < 0.4: _add_obstacle(s, dd, 0.45, 9.0, "tree", true)
						else:
							var r := _rng.randf_range(0.7, 1.5)
							_add_obstacle(s, dd, r, r * 0.9, "rock", true)
					elif off < sec.hw - 0.6 and _rng.randf() < 0.05:
						_add_obstacle(s, dd, 0.4, 0.32, "rock", true)
					d += 2.4
				s += _rng.randf_range(2.2, 3.2)
		elif sec.kind == "slalom":
			# A thicket of trees and boulders with two or three lanes winding
			# through it. No rows: it should look grown, not planted.
			var lanes: Array = []
			for k in _rng.randi_range(2, 3):
				lanes.append({"off": _rng.randf_range(-9.0, 9.0), "amp": _rng.randf_range(2.0, 5.0),
					"freq": TAU / _rng.randf_range(18.0, 34.0), "phase": _rng.randf() * TAU})
			var s: float = sec.s + 4.0
			while s < sec.s + sec.len - 2.0:
				var d := -CORRIDOR - 2.0
				while d < CORRIDOR + 2.0:
					var ps := s + _rng.randf_range(-0.9, 0.9)
					var pd := d + _rng.randf_range(-0.9, 0.9)
					var clear := false
					for lane in lanes:
						var at: float = valley_mid(ps) + lane.off + lane.amp * sin(ps * lane.freq + lane.phase)
						if absf(pd - at) < 1.9: clear = true
					if not clear and _rng.randf() < 0.62:
						if _noise.get_noise_2d(ps * 3.0 + 800.0, pd * 3.0) > 0.0:
							_add_obstacle(ps, pd, 0.45, 9.0, "tree", true)
						else:
							var r := _rng.randf_range(0.6, 1.3)
							_add_obstacle(ps, pd, r, r * 0.9, "rock", true)
					d += 2.3
				s += 2.3

func _add_obstacle(s: float, d: float, r: float, h: float, kind: String, set_piece := false) -> void:
	if not set_piece:
		var sec := section_at(s)
		if not sec.is_empty() and sec.kind in ["gully", "slalom"]: return
		if not sec.is_empty() and sec.kind == "chasm" and absf(s - sec.cs) < sec.w * 0.5 + 8.0: return
		if water_depth(s, d) > 0.0 or _lake_calm(s, d) < 0.6: return
		if on_path(s, d) or on_path(s + 6.0, d): return
	if s < START_FLAT + 8.0: return
	if s > length - 12.0 and s < length + 6.0 and absf(d) < TRACK_HALF + 3.0: return
	for b in bands:
		if absf(s - b.s) < r + 1.5: return
	if _stream_at(s, d) > 0.2: return
	var index := obstacles.size()
	var look := kind
	if kind == "tree":
		look = tree_look(s, d)
		if look == "cactus": r = 0.35
	obstacles.append({"s": s, "d": d, "r": r, "h": h, "kind": kind, "look": look})
	var key := int(s / 10.0)
	if not _buckets.has(key): _buckets[key] = []
	_buckets[key].append(index)

## Which tree grows here. Each biome has its own mix, and the mix drifts
## along the run, so you ride through pine stands, then birches, then oaks.
func tree_look(s: float, d: float) -> String:
	var zone := _noise.get_noise_2d(s * 0.6 + 7000.0, d * 0.3)
	var roll := _rng.randf()
	match biome:
		"alpine":
			if zone > 0.25: return "birch" if roll < 0.7 else "pine"
			return "pine" if roll < 0.6 else ("fir" if roll < 0.93 else "dead")
		"forest":
			if zone > 0.2: return "pine" if roll < 0.7 else "fir"
			if zone < -0.3: return "birch" if roll < 0.7 else "oak"
			return "oak" if roll < 0.65 else ("pine" if roll < 0.9 else "birch")
		"autumn":
			if zone > 0.2: return "birch" if roll < 0.75 else "autumn"
			return "autumn" if roll < 0.6 else ("oak" if roll < 0.8 else "fir")
		"desert":
			if zone > 0.3: return "dead" if roll < 0.6 else "cactus"
			return "cactus" if roll < 0.8 else ("dead" if roll < 0.95 else "joshua")
	return "pine"

func obstacles_near(s: float) -> Array:
	var out: Array = []
	var key := int(s / 10.0)
	for k in [key - 1, key, key + 1]:
		for index in _buckets.get(k, []):
			out.append(obstacles[index])
	return out
