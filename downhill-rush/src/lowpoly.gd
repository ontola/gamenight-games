class_name LowPoly
extends RefCounted
## Flat-shaded mesh builder. Every triangle gets its own normal and colour,
## which is the whole low-poly look. Tex adds chunky textures on top.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()

static var _material: StandardMaterial3D

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
		_material.metallic_specular = 0.15
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

## Adds a triangle facing away from `inside` (or up when `inside` is INF).
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3 = Vector3.INF) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12: return
	n = n.normalized()
	var flip := false
	if inside == Vector3.INF: flip = n.y < 0.0
	else: flip = n.dot((a + b + c) / 3.0 - inside) < 0.0
	if flip:
		n = -n
		var t := b; b = c; c = t
	verts.append(a); verts.append(b); verts.append(c)
	normals.append(n); normals.append(n); normals.append(n)
	colors.append(color); colors.append(color); colors.append(color)

## A triangle facing up with its own colour at each corner, blended across.
func tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (c - a).cross(b - a)
	if n.length_squared() < 1e-12: return
	n = n.normalized()
	if n.y < 0.0:
		n = -n
		var t := b; b = c; c = t
		var tc := cb; cb = cc; cc = tc
	verts.append(a); verts.append(b); verts.append(c)
	normals.append(n); normals.append(n); normals.append(n)
	colors.append(ca); colors.append(cb); colors.append(cc)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3 = Vector3.INF) -> void:
	tri(a, b, c, color, inside)
	tri(a, c, d, color, inside)

## Cone or truncated cone along local up of `basis`, starting at `base`.
func cone(base: Vector3, r0: float, r1: float, height: float, segments: int, color: Color,
		basis: Basis = Basis.IDENTITY, shade: float = 0.0, rng: RandomNumberGenerator = null) -> void:
	var up := basis.y.normalized() * height
	var center := base + up * 0.5
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in segments:
		var a := TAU * i / segments
		var dir := basis.x.normalized() * cos(a) + basis.z.normalized() * sin(a)
		var j := 1.0 if rng == null else rng.randf_range(0.85, 1.15)
		ring0.append(base + dir * r0 * j)
		ring1.append(base + up + dir * r1 * j)
	for i in segments:
		var k := (i + 1) % segments
		var col := _shade(color, shade * sin(TAU * i / segments))
		if r1 <= 0.001:
			tri(ring0[i], ring0[k], base + up, col, center)
		else:
			quad(ring0[i], ring0[k], ring1[k], ring1[i], col, center)
	for i in range(1, segments - 1):
		tri(ring0[0], ring0[i], ring0[i + 1], _shade(color, -0.2), center)
		if r1 > 0.001: tri(ring1[0], ring1[i], ring1[i + 1], color, center)

func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for z in [-1, 1]:
		for y in [-1, 1]:
			for x in [-1, 1]:
				p.append(center + basis * Vector3(h.x * x, h.y * y, h.z * z))
	var faces := [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]
	for f in faces:
		quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], color, center)

## Box spanning two points, for struts, limbs and posts.
func beam(a: Vector3, b: Vector3, thickness: float, color: Color) -> void:
	var dir := b - a
	if dir.length() < 0.001: return
	var z := dir.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized()
	var y := z.cross(x).normalized()
	box((a + b) * 0.5, Vector3(thickness, thickness, dir.length()), color, Basis(x, y, z))

## A lumpy low-poly blob: rocks, bushes, heads.
func blob(center: Vector3, radius: Vector3, color: Color, rng: RandomNumberGenerator, rings: int = 3, segments: int = 6, jitter: float = 0.18) -> void:
	var pts: Array = []
	for r in rings + 1:
		var row: Array[Vector3] = []
		var phi := PI * r / rings
		for i in segments:
			var a := TAU * (i + (0.5 if r % 2 else 0.0)) / segments
			var dir := Vector3(sin(phi) * cos(a), cos(phi), sin(phi) * sin(a))
			var j := 1.0 + (rng.randf_range(-jitter, jitter) if r > 0 and r < rings else 0.0)
			row.append(center + dir * radius * j)
		pts.append(row)
	for r in rings:
		for i in segments:
			var k := (i + 1) % segments
			var col := color.lightened(rng.randf_range(-0.04, 0.08)) if rng else color
			var a: Vector3 = pts[r][i]
			var b: Vector3 = pts[r][k]
			var c: Vector3 = pts[r + 1][k]
			var d: Vector3 = pts[r + 1][i]
			if r == 0: tri(a, c, d, col, center)
			elif r == rings - 1: tri(a, b, d, col, center)
			else: quad(a, b, c, d, col, center)

## The top half of an ellipsoid, open at the bottom: helmets and caps.
func dome(center: Vector3, radius: Vector3, color: Color, rings: int = 4, segments: int = 10) -> void:
	var pts: Array = []
	for r in rings + 1:
		var row: Array[Vector3] = []
		var phi := PI * 0.5 * r / rings
		for i in segments:
			var a := TAU * i / segments
			row.append(center + Vector3(sin(phi) * cos(a), cos(phi), sin(phi) * sin(a)) * radius)
		pts.append(row)
	for r in rings:
		for i in segments:
			var k := (i + 1) % segments
			if r == 0: tri(pts[0][i], pts[1][k], pts[1][i], color, center)
			else: quad(pts[r][i], pts[r][k], pts[r + 1][k], pts[r + 1][i], color, center)

## A tyre: a coarse torus in the local YZ plane around `center`.
func ring(center: Vector3, radius: float, tube: float, color: Color, segments: int = 10) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(0, cos(a0), sin(a0))
		var d1 := Vector3(0, cos(a1), sin(a1))
		var corners := []
		for side in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(side)
		for j in 4:
			var s0: Vector2 = corners[j]
			var s1: Vector2 = corners[(j + 1) % 4]
			var p00 := center + d0 * (radius + s0.y * tube) + Vector3(s0.x * tube, 0, 0)
			var p01 := center + d0 * (radius + s1.y * tube) + Vector3(s1.x * tube, 0, 0)
			var p10 := center + d1 * (radius + s0.y * tube) + Vector3(s0.x * tube, 0, 0)
			var p11 := center + d1 * (radius + s1.y * tube) + Vector3(s1.x * tube, 0, 0)
			var mid := center + (d0 + d1).normalized() * radius
			quad(p00, p10, p11, p01, color, mid)

func is_empty() -> bool:
	return verts.is_empty()

func commit(mesh: ArrayMesh = null, mat: Material = null) -> ArrayMesh:
	if mesh == null: mesh = ArrayMesh.new()
	if verts.is_empty(): return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat if mat else material())
	return mesh

static func _shade(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)
