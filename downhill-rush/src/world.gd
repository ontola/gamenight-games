class_name MountainView
extends Node3D
## Turns a Course into meshes: faceted terrain, the dirt line, trees, rocks,
## flags at every take-off and the start and finish gates.

const CHUNK := 60.0
const GRASS := Color(0.47, 0.63, 0.28)
const GRASS_DARK := Color(0.28, 0.46, 0.25)
const MEADOW := Color(0.74, 0.7, 0.34)
const DIRT := Color(0.74, 0.5, 0.31)
const DIRT_DARK := Color(0.5, 0.33, 0.22)
const PACKED := Color(0.85, 0.63, 0.4)
const CHALK := Color(0.97, 0.92, 0.8)
const STONE := Color(0.6, 0.6, 0.62)
const TRUNK := Color(0.42, 0.3, 0.22)
const PINES := [Color(0.16, 0.36, 0.25), Color(0.2, 0.42, 0.27), Color(0.13, 0.3, 0.24), Color(0.26, 0.47, 0.27)]
const AUTUMN := [Color(0.88, 0.56, 0.24), Color(0.93, 0.74, 0.3), Color(0.78, 0.36, 0.22)]

var course: Course
var _rng := RandomNumberGenerator.new()
var _columns := PackedFloat32Array()


func build(c: Course) -> void:
	course = c
	_rng.seed = c.seed_value * 31 + 5
	for child in get_children():
		child.queue_free()
	_columns = _make_columns()
	var s := 0.0
	while s < c.total - 1.0:
		_terrain_chunk(s, minf(s + CHUNK, c.total - 1.0))
		s += CHUNK
	_props()
	_markers()
	_gate(Course.START_LINE, false)
	_gate(c.length, true)


func _make_columns() -> PackedFloat32Array:
	var cols := PackedFloat32Array()
	var d := -Course.EDGE
	while d < Course.EDGE + 0.01:
		cols.append(d)
		var ad := absf(d)
		d += 0.6 if ad < 7.5 else (1.5 if ad < 13.0 else 4.5)
	return cols


# ── Terrain ──────────────────────────────────────────────────────────────────

func _terrain_chunk(s0: float, s1: float) -> void:
	var lp := LowPoly.new()
	var rows: Array = []
	var s := s0
	var ss := PackedFloat32Array()
	while s <= s1 + 0.001:
		ss.append(s)
		var row := PackedVector3Array()
		for d in _columns:
			if absf(d) < 10.0:
				row.append(course.world(s, d))
			else:
				# Irregular facets on the hillside, a regular grid on the line.
				var js := course._detail.get_noise_2d(s * 3.0, d * 3.0) * 1.4
				var jd := course._detail.get_noise_2d(d * 3.0 + 50.0, s * 3.0) * 1.8
				row.append(course.world(s + js, d + jd))
		rows.append(row)
		s += Course.DS
	for r in rows.size() - 1:
		var a: PackedVector3Array = rows[r]
		var b: PackedVector3Array = rows[r + 1]
		for i in _columns.size() - 1:
			var sm: float = (ss[r] + ss[r + 1]) * 0.5
			var dm: float = (_columns[i] + _columns[i + 1]) * 0.5
			var flip := (r + i) % 2 == 0
			if flip:
				_face(lp, a[i], a[i + 1], b[i + 1], sm, dm)
				_face(lp, a[i], b[i + 1], b[i], sm, dm)
			else:
				_face(lp, a[i], a[i + 1], b[i], sm, dm)
				_face(lp, a[i + 1], b[i + 1], b[i], sm, dm)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	mi.name = "Terrain"
	add_child(mi)

func _face(lp: LowPoly, p0: Vector3, p1: Vector3, p2: Vector3, s: float, d: float) -> void:
	var n := (p2 - p0).cross(p1 - p0).normalized()
	var steep := 1.0 - absf(n.y)
	var ad := absf(d)
	var wobble := course._noise.get_noise_2d(s * 3.1, d * 3.1)
	var col: Color
	var edge := Course.TRACK_HALF + wobble * 0.7
	if ad < edge - 0.6:
		col = DIRT
		var f := course.feature_ahead(s, 0.0)
		if not f.is_empty() and s >= f.s0:
			col = _feature_color(f, s - f.s0, col)
	elif ad < edge + 0.5:
		col = DIRT.lerp(GRASS, 0.55)
	else:
		var patch := course._noise.get_noise_2d(s * 0.9 + 400.0, d * 0.9)
		col = GRASS.lerp(GRASS_DARK, clampf(patch * 1.6 + 0.4, 0.0, 1.0))
		if patch > 0.38: col = col.lerp(MEADOW, 0.6)
		if steep > 0.45: col = col.lerp(STONE, clampf((steep - 0.45) * 3.0, 0.0, 1.0))
	col = col.lightened(_rng.randf_range(-0.03, 0.05))
	lp.tri(p0, p1, p2, col)

func _feature_color(f: Dictionary, u: float, col: Color) -> Color:
	match int(f.kind):
		Course.Kind.GAP, Course.Kind.TABLE:
			if u < f.ramp - 0.7: return PACKED
			if u < f.ramp: return CHALK
			if u < f.ramp + f.gap: return DIRT_DARK.darkened(0.25) if int(f.kind) == Course.Kind.GAP else PACKED.darkened(0.06)
			return PACKED.lightened(0.05)
		Course.Kind.DROP:
			if u < f.ramp - 0.7: return PACKED.darkened(0.04)
			if u < f.ramp: return CHALK
			return PACKED.lightened(0.05)
		Course.Kind.ROLLERS, Course.Kind.STEP_UP:
			return col.lerp(PACKED, 0.5)
		Course.Kind.ROCKS:
			return col.lerp(STONE, 0.3)
	return col


# ── Props ────────────────────────────────────────────────────────────────────

func _props() -> void:
	# Meshes built once per chunk, in world space, so we skip per-instance
	# transforms entirely and keep the draw-call count low.
	var chunks := {}
	for o in course.obstacles:
		var key := int(o.s / CHUNK)
		if not chunks.has(key): chunks[key] = LowPoly.new()
		var lp: LowPoly = chunks[key]
		var p := course.world(o.s, o.d)
		if o.kind == "tree": _tree(lp, p)
		else: _rock(lp, p, o.r)
	# Decoration without collisions: bushes, grass tufts, flowers.
	var s := 0.0
	while s < course.total:
		var key := int(s / CHUNK)
		if not chunks.has(key): chunks[key] = LowPoly.new()
		var lp: LowPoly = chunks[key]
		for i in 5:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var d := side * _rng.randf_range(Course.TRACK_HALF + 0.6, Course.EDGE - 1.0)
			var ss := s + _rng.randf_range(0.0, 4.0)
			var p := course.world(ss, d)
			var roll := _rng.randf()
			if roll < 0.35:
				lp.blob(p + Vector3(0, 0.25, 0), Vector3(0.7, 0.5, 0.7) * _rng.randf_range(0.7, 1.4), PINES[_rng.randi() % PINES.size()].lightened(0.1), _rng, 2, 5)
			elif roll < 0.75:
				_tuft(lp, p)
			else:
				var flower: Color = [Color(0.95, 0.9, 0.7), Color(0.95, 0.6, 0.55), Color(0.75, 0.65, 0.95)][_rng.randi() % 3]
				for f in 3:
					var q := p + Vector3(_rng.randf_range(-0.5, 0.5), 0, _rng.randf_range(-0.5, 0.5))
					lp.cone(q, 0.07, 0.0, 0.22, 3, flower)
		s += 4.0
	for key in chunks:
		var mi := MeshInstance3D.new()
		mi.mesh = chunks[key].commit()
		mi.name = "Props%d" % key
		add_child(mi)

func _tree(lp: LowPoly, p: Vector3) -> void:
	var scale := _rng.randf_range(0.8, 1.35)
	var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.06))
	lp.cone(p - Vector3(0, 0.3, 0), 0.28 * scale, 0.2 * scale, 1.6 * scale, 5, TRUNK, tilt)
	if _rng.randf() < 0.82:
		var col: Color = PINES[_rng.randi() % PINES.size()]
		var y := 1.0 * scale
		var r := 1.7 * scale
		for layer in 3:
			lp.cone(p + tilt.y * y, r, 0.0, 2.6 * scale, 6, col.lightened(layer * 0.04), tilt, 0.0, _rng)
			y += 1.25 * scale
			r *= 0.72
	else:
		var col: Color = AUTUMN[_rng.randi() % AUTUMN.size()]
		lp.blob(p + tilt.y * 2.8 * scale, Vector3(1.6, 1.8, 1.6) * scale, col, _rng, 3, 6, 0.2)

func _rock(lp: LowPoly, p: Vector3, r: float) -> void:
	var col := STONE.lightened(_rng.randf_range(-0.12, 0.08))
	lp.blob(p + Vector3(0, r * 0.25, 0), Vector3(r, r * 0.8, r * _rng.randf_range(0.8, 1.2)), col, _rng, 3, 6, 0.22)

func _tuft(lp: LowPoly, p: Vector3) -> void:
	var col := GRASS.lerp(MEADOW, _rng.randf()).lightened(0.05)
	for i in 3:
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		lp.tri(p + dir * 0.12, p - dir * 0.12, p + dir.rotated(Vector3.UP, 1.4) * 0.1 + Vector3(0, 0.45, 0), col, p + Vector3(0, 0.2, 0) - dir.rotated(Vector3.UP, PI / 2) * 0.3)


# ── Readability: flags, signs, gates ─────────────────────────────────────────

func _markers() -> void:
	var lp := LowPoly.new()
	for f in course.features:
		match int(f.kind):
			Course.Kind.GAP, Course.Kind.TABLE:
				var lip: float = f.s0 + f.ramp
				_flag(lp, lip, Color(1.0, 0.55, 0.2))
				_flag(lp, f.s0 + f.ramp + f.gap + 1.5, Color(0.98, 0.96, 0.9))
				_sign(lp, f.s0 - 10.0, f)
			Course.Kind.DROP:
				_flag(lp, f.s0 + f.ramp, Color(0.92, 0.25, 0.2))
				_sign(lp, f.s0 - 6.0, f)
			Course.Kind.ROCKS:
				_flag(lp, f.s0, Color(0.95, 0.85, 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	mi.name = "Markers"
	add_child(mi)

func _flag(lp: LowPoly, s: float, color: Color) -> void:
	for side in [-1.0, 1.0]:
		var d: float = side * (Course.TRACK_HALF + 0.4)
		var p := course.world(s, d)
		var top := p + Vector3(0, 3.0, 0)
		lp.beam(p, top, 0.12, Color(0.95, 0.93, 0.88))
		var out: Vector3 = course.right(s) * side * 1.5
		lp.tri(top, top - Vector3(0, 1.0, 0), top + out - Vector3(0, 0.5, 0), color)

## A wooden sign before a jump. Its board says how fussy the jump is about
## speed: green lands almost anything, red needs exactly the right speed.
func _sign(lp: LowPoly, s: float, f: Dictionary) -> void:
	var window: float = f.get("speed_max", 10.0) - f.get("speed_min", 5.0)
	var col := Color(0.45, 0.75, 0.4) if window > 4.0 else (Color(0.98, 0.62, 0.22) if window > 2.4 else Color(0.9, 0.3, 0.25))
	var d := -(Course.TRACK_HALF + 1.2)
	var p := course.world(s, d)
	lp.beam(p, p + Vector3(0, 1.6, 0), 0.12, TRUNK)
	var right := course.right(s)
	var basis := Basis(right, Vector3.UP, -course.forward(s))
	lp.box(p + Vector3(0, 1.75, 0), Vector3(1.3, 0.8, 0.08), col, basis)
	# A white chevron so it reads as "jump" from far above.
	var c := p + Vector3(0, 1.75, 0) - course.forward(s) * 0.06
	lp.tri(c + right * -0.4 + Vector3(0, -0.2, 0), c + right * 0.4 + Vector3(0, -0.2, 0), c + Vector3(0, 0.25, 0), Color(1, 1, 0.96))

func _gate(s: float, finish: bool) -> void:
	var lp := LowPoly.new()
	var w := Course.TRACK_HALF + 1.2
	var left := course.world(s, -w)
	var right := course.world(s, w)
	var top := maxf(left.y, right.y) + 4.2
	var wood := TRUNK.lightened(0.1)
	lp.beam(left - Vector3(0, 0.5, 0), Vector3(left.x, top, left.z), 0.35, wood)
	lp.beam(right - Vector3(0, 0.5, 0), Vector3(right.x, top, right.z), 0.35, wood)
	var a := Vector3(left.x, top - 0.2, left.z)
	var b := Vector3(right.x, top - 0.2, right.z)
	var squares := 16
	var fwd := course.forward(s)
	for i in squares:
		for j in 2:
			var p0 := a.lerp(b, float(i) / squares) - Vector3(0, j * 0.5, 0)
			var p1 := a.lerp(b, float(i + 1) / squares) - Vector3(0, j * 0.5, 0)
			var col: Color
			if finish: col = Color(0.97, 0.97, 0.95) if (i + j) % 2 == 0 else Color(0.15, 0.16, 0.2)
			else: col = Color(0.95, 0.5, 0.3) if j == 0 else Color(0.98, 0.85, 0.45)
			lp.quad(p0, p1, p1 - Vector3(0, 0.5, 0), p0 - Vector3(0, 0.5, 0), col, (p0 + p1) * 0.5 - Vector3(0, 0.25, 0) + fwd)
	# Bunting along the line near the finish.
	if finish:
		for k in 8:
			var ss := s - 6.0 - k * 5.0
			for side in [-1.0, 1.0]:
				var p := course.world(ss, side * (Course.TRACK_HALF + 0.8))
				lp.beam(p, p + Vector3(0, 1.1, 0), 0.08, wood)
				lp.box(p + Vector3(0, 1.05, 0), Vector3(0.6, 0.35, 0.05), [Color(0.95, 0.5, 0.3), Color(0.45, 0.7, 0.9), Color(0.98, 0.85, 0.45)][k % 3], Basis(course.right(ss), Vector3.UP, -course.forward(ss)))
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	mi.name = "Finish" if finish else "Start"
	add_child(mi)
