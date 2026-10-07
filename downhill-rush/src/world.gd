class_name MountainView
extends Node3D
## Turns a Course into meshes: faceted terrain with cliffs, scree and
## streams, trees, boulders, undergrowth and the start and finish gates.

const CHUNK := 60.0
const GRASS := Color(0.47, 0.63, 0.28)
const GRASS_DARK := Color(0.28, 0.46, 0.25)
const MEADOW := Color(0.74, 0.7, 0.34)
const DIRT := Color(0.74, 0.5, 0.31)
const DIRT_DARK := Color(0.5, 0.33, 0.22)
const PACKED := Color(0.85, 0.63, 0.4)
const CHALK := Color(0.97, 0.92, 0.8)
const STONE := Color(0.6, 0.6, 0.62)
const CLIFF := Color(0.42, 0.4, 0.4)
const SCREE := Color(0.68, 0.64, 0.58)
const SAND := Color(0.7, 0.66, 0.52)
const WATER_COL := Color(0.1, 0.36, 0.55, 0.88)
const FERN := Color(0.3, 0.55, 0.22)
const FOREST_FLOOR := Color(0.3, 0.36, 0.2)
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
	_gate(Course.START_LINE, false)
	_gate(c.length, true)


func _make_columns() -> PackedFloat32Array:
	var cols := PackedFloat32Array()
	var d := -Course.EDGE
	while d < Course.EDGE + 0.01:
		cols.append(d)
		var ad := absf(d)
		d += 0.8 if ad < Course.CORRIDOR + 3.0 else (2.0 if ad < Course.CORRIDOR + 12.0 else 5.0)
	return cols


# ── Terrain ──────────────────────────────────────────────────────────────────

const ROW := 0.5   ## Fine rows so ledges are as sharp on screen as under the wheels.

func _terrain_chunk(s0: float, s1: float) -> void:
	var lp := LowPoly.new()
	var rows: Array = []
	var s := s0
	var ss := PackedFloat32Array()
	while s <= s1 + 0.001:
		ss.append(s)
		var row := PackedVector3Array()
		for d in _columns:
			if absf(d) < Course.CORRIDOR + 3.0:
				row.append(course.world(s, d))
			else:
				# Irregular facets on the valley walls.
				var js := course._detail.get_noise_2d(s * 3.0, d * 3.0) * 1.4
				var jd := course._detail.get_noise_2d(d * 3.0 + 50.0, s * 3.0) * 1.8
				row.append(course.world(s + js, d + jd))
		rows.append(row)
		s += ROW
	# Colours live on the vertices and blend across each facet, so dirt fades
	# into grass and rock into scree instead of stepping cell by cell.
	var cols: Array = []
	for r in rows.size():
		var row: PackedVector3Array = rows[mini(r, rows.size() - 2)]
		var nxt: PackedVector3Array = rows[mini(r, rows.size() - 2) + 1]
		var crow := PackedColorArray()
		crow.resize(_columns.size())
		for i in _columns.size():
			var j := mini(i, _columns.size() - 2)
			crow[i] = _vertex_color(row[j], row[j + 1], nxt[j], ss[r], _columns[i])
		cols.append(crow)
	for r in rows.size() - 1:
		var a: PackedVector3Array = rows[r]
		var b: PackedVector3Array = rows[r + 1]
		var ca: PackedColorArray = cols[r]
		var cb: PackedColorArray = cols[r + 1]
		for i in _columns.size() - 1:
			if (r + i) % 2 == 0:
				lp.tri3(a[i], a[i + 1], b[i + 1], ca[i], ca[i + 1], cb[i + 1])
				lp.tri3(a[i], b[i + 1], b[i], ca[i], cb[i + 1], cb[i])
			else:
				lp.tri3(a[i], a[i + 1], b[i], ca[i], ca[i + 1], cb[i])
				lp.tri3(a[i + 1], b[i + 1], b[i], ca[i + 1], cb[i + 1], cb[i])
	# Streams: a sheet of water sitting in each ditch.
	var water := LowPoly.new()
	for st in course.streams:
		if st.s < s0 - 4.0 or st.s > s1 + 4.0: continue
		var d := -Course.CORRIDOR - 6.0
		while d < Course.CORRIDOR + 6.0:
			var d1 := d + 1.0
			var c0: float = course._stream_line(st, d)
			var c1: float = course._stream_line(st, d1)
			var y0 := course.height(c0, d) + 0.42
			var y1 := course.height(c1, d1) + 0.42
			water.quad(course.world(c0 - 1.1, d, y0), course.world(c0 + 1.1, d, y0),
				course.world(c1 + 1.1, d1, y1), course.world(c1 - 1.1, d1, y1), Color.WHITE)
			d = d1
	if not water.is_empty():
		var wm := MeshInstance3D.new()
		wm.mesh = water.commit(null, _water_material())
		wm.name = "Water"
		add_child(wm)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit(null, Tex.material(Tex.grit(), 0.7, true))
	mi.name = "Terrain"
	add_child(mi)

static var _water_mat: StandardMaterial3D

static func _water_material() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = WATER_COL
		_water_mat.albedo_texture = Tex.ripples()
		_water_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_water_mat.uv1_triplanar = true
		_water_mat.uv1_world_triplanar = true
		_water_mat.uv1_scale = Vector3.ONE * 0.35
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.roughness = 0.45
		_water_mat.metallic_specular = 0.3
		_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_mat

func _vertex_color(p0: Vector3, p1: Vector3, p2: Vector3, s: float, d: float) -> Color:
	var n := (p2 - p0).cross(p1 - p0).normalized()
	var steep := 1.0 - absf(n.y)
	var slope := sqrt(maxf(0.0, 1.0 - n.y * n.y)) / maxf(absf(n.y), 0.05)
	var col: Color
	match course.surface(s, d, slope):
		Course.Surface.WATER: col = SAND
		Course.Surface.SCREE: col = SCREE.lerp(STONE, course._detail.get_noise_2d(s * 2.0, d * 2.0) * 0.5 + 0.5)
		Course.Surface.DIRT: col = DIRT.lerp(DIRT_DARK, clampf(course._noise.get_noise_2d(s * 6.0, d * 6.0) + 0.3, 0.0, 0.6))
		_:
			var patch := course._noise.get_noise_2d(s * 0.9 + 400.0, d * 0.9)
			col = GRASS.lerp(GRASS_DARK, clampf(patch * 1.6 + 0.4, 0.0, 1.0))
			if patch > 0.38: col = col.lerp(MEADOW, 0.6)
	# Steeper ground is darker, so pitches read from straight above.
	col = col.darkened(clampf(steep * 0.6, 0.0, 0.3))
	var edge := course.edges(s)
	var wall := maxf(d - edge.y, edge.x - d)
	if wall > 1.0:
		# Valley sides: forest floor with grey outcrops breaking through.
		var crag := course._noise.get_noise_2d(s * 2.5 + 1200.0, d * 2.5)
		col = GRASS_DARK.lerp(FOREST_FLOOR, clampf(course._noise.get_noise_2d(s * 1.5, d * 1.5) + 0.5, 0.0, 1.0))
		col = col.darkened(clampf(steep * 0.4, 0.0, 0.25))
		if crag > 0.15 or steep > 0.8: col = col.lerp(CLIFF.lightened(crag * 0.4), clampf((crag - 0.15) * 5.0 + maxf(0.0, steep - 0.8) * 5.0, 0.0, 1.0))
	elif steep > 0.35:
		# Ledges and cliff faces are bare rock, so they read from far above.
		col = col.lerp(CLIFF, clampf((steep - 0.35) * 3.0, 0.0, 1.0))
	return col.lightened(_rng.randf_range(-0.03, 0.04))


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
		for i in 9:
			var d := _rng.randf_range(-Course.EDGE + 1.0, Course.EDGE - 1.0)
			var ss := s + _rng.randf_range(0.0, 4.0)
			if course.surface(ss, d) in [Course.Surface.WATER, Course.Surface.SCREE, Course.Surface.ROCK]: continue
			var p := course.world(ss, d)
			var roll := _rng.randf()
			if roll < 0.25:
				_fern(lp, p)
			elif roll < 0.4:
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
		mi.mesh = chunks[key].commit(null, Tex.material(Tex.grit(), 1.6, true))
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

## A fan of long leaves, the bracken that lines every forest trail.
func _fern(lp: LowPoly, p: Vector3) -> void:
	var n := _rng.randi_range(5, 8)
	var scale := _rng.randf_range(0.7, 1.3)
	for k in n:
		var a := TAU * k / n + _rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := dir.cross(Vector3.UP) * 0.16 * scale
		var tip := p + dir * 1.1 * scale + Vector3(0, 0.25, 0)
		var mid := p + dir * 0.5 * scale + Vector3(0, 0.55 * scale, 0)
		var col := FERN.lightened(_rng.randf_range(-0.08, 0.12))
		lp.tri(p, mid + side, mid - side, col)
		lp.tri(mid + side, tip, mid - side, col.lightened(0.06))

func _tuft(lp: LowPoly, p: Vector3) -> void:
	var col := GRASS.lerp(MEADOW, _rng.randf()).lightened(0.05)
	for i in 3:
		var a := _rng.randf() * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		lp.tri(p + dir * 0.12, p - dir * 0.12, p + dir.rotated(Vector3.UP, 1.4) * 0.1 + Vector3(0, 0.45, 0), col, p + Vector3(0, 0.2, 0) - dir.rotated(Vector3.UP, PI / 2) * 0.3)


# ── Gates ────────────────────────────────────────────────────────────────────

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
