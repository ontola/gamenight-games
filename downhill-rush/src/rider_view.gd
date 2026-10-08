class_name RiderView
extends Node3D
## A low-poly BMX rider, posed from a Bike state each frame.

const SCALE := 2.2
const WHEEL := 0.27
const WHEELBASE := 0.98
const DARK := Color(0.13, 0.13, 0.15)
const RIM := Color(0.78, 0.8, 0.84)

const SKINS := [Color(0.93, 0.76, 0.62), Color(0.62, 0.43, 0.3), Color(0.8, 0.6, 0.45), Color(0.42, 0.29, 0.21)]
const TROUSERS := [Color(0.35, 0.45, 0.65), Color(0.18, 0.18, 0.2), Color(0.72, 0.62, 0.45), Color(0.45, 0.5, 0.42)]
const ACCENTS := [Color(0.98, 0.9, 0.3), Color(0.98, 0.96, 0.9), Color(0.25, 0.9, 0.85), Color(0.98, 0.45, 0.6),
	Color(0.6, 0.95, 0.4), Color(1.0, 0.65, 0.2), Color(0.7, 0.55, 1.0), Color(0.95, 0.3, 0.25)]

var color := Color.WHITE
var accent := Color.WHITE
var style := 0
var body: Node3D           ## Pitches and leans with the bike.
var bike: Node3D           ## Spins on its own for tailwhips.
var rider: Node3D          ## Tumbles away from the bike in a crash.
var front_wheel: Node3D
var rear_wheel: Node3D
var tag: Label3D
var dust: CPUParticles3D
var _was_crashed := false
var _whip := 0.0
var _whip_rate := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()
## Legs are separate pieces so the feet can go round with the cranks:
## per side {thigh, shin, shoe} nodes, each a unit-length mesh stretched in place.
var _legs: Array = []
var _crank := 0.0

const HIP := Vector3(0, 0.92, -0.2)
const CRANK_AT := Vector3(0, WHEEL + 0.06, -0.03)
const CRANK_R := 0.16
const THIGH := 0.4
const SHIN := 0.42


func setup(p_color: Color, p_name: String, p_style: int = 0) -> void:
	color = p_color
	style = p_style
	accent = ACCENTS[(p_style * 3 + 1) % ACCENTS.size()]
	if accent.is_equal_approx(color) or absf(accent.h - color.h) < 0.06: accent = Color(0.98, 0.97, 0.92)
	_rng.seed = hash(p_name)
	body = Node3D.new()
	add_child(body)
	bike = Node3D.new()
	body.add_child(bike)
	var frame := MeshInstance3D.new()
	frame.mesh = _frame_mesh()
	bike.add_child(frame)
	front_wheel = _wheel(Vector3(0, WHEEL, WHEELBASE * 0.5))
	rear_wheel = _wheel(Vector3(0, WHEEL, -WHEELBASE * 0.5))
	rider = Node3D.new()
	body.add_child(rider)
	var rider_mesh := MeshInstance3D.new()
	rider_mesh.mesh = _rider_mesh()
	rider.add_child(rider_mesh)
	_build_legs()
	body.scale = Vector3.ONE * SCALE
	tag = Label3D.new()
	tag.text = p_name.to_upper()
	tag.font = Hud.font_bold()
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0011
	tag.font_size = 22
	tag.outline_size = 10
	tag.modulate = p_color.lightened(0.3)
	tag.outline_modulate = Color(0.08, 0.09, 0.12, 0.95)
	tag.no_depth_test = true
	tag.render_priority = 10
	tag.position = Vector3(0, 1.0, 0)
	tag.offset = Vector2(0, 130)
	add_child(tag)
	dust = CPUParticles3D.new()
	dust.amount = 14
	dust.lifetime = 0.9
	dust.local_coords = false
	dust.emitting = false
	var puff := SphereMesh.new()
	puff.radius = 0.3
	puff.height = 0.5
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.64, 0.46, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	puff.material = mat
	dust.mesh = puff
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 50.0
	dust.initial_velocity_min = 0.5
	dust.initial_velocity_max = 1.6
	dust.gravity = Vector3(0, 0.6, 0)
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	dust.scale_amount_curve = curve
	dust.position = Vector3(0, 0.1, -0.7)
	add_child(dust)

func set_player_name(p_name: String) -> void:
	tag.text = p_name.to_upper()

func _wheel(at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	bike.add_child(pivot)
	var lp := LowPoly.new()
	# 20-inch BMX wheel: knobbly tyre, silver rim, hub and laced spokes.
	var tyre := WHEEL - 0.035
	lp.ring(Vector3.ZERO, tyre, 0.035, DARK, 20)
	lp.ring(Vector3.ZERO, tyre - 0.045, 0.012, RIM, 20)
	lp.beam(Vector3(-0.035, 0, 0), Vector3(0.035, 0, 0), 0.035, RIM.darkened(0.3))
	for k in 16:
		var a := TAU * k / 16.0
		var side := 0.025 if k % 2 == 0 else -0.025
		lp.beam(Vector3(side, 0, 0), Vector3(0, cos(a + 0.2), sin(a + 0.2)) * (tyre - 0.05), 0.008, RIM.darkened(0.15))
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	pivot.add_child(mi)
	return pivot

func _frame_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var paint := color
	var rear := Vector3(0, WHEEL, -WHEELBASE * 0.5)
	var front := Vector3(0, WHEEL, WHEELBASE * 0.5)
	var bb := Vector3(0, WHEEL + 0.03, -0.05)
	var seat := Vector3(0, 0.62, -0.18)
	var head := Vector3(0, 0.66, 0.36)
	lp.beam(bb, seat, 0.07, paint)                       # short seat tube
	lp.beam(seat, head, 0.075, paint)                    # top tube
	lp.beam(bb, head - Vector3(0, 0.08, 0), 0.085, paint) # down tube
	lp.beam(bb, rear, 0.055, paint)                      # chain stay
	lp.beam(seat, rear, 0.05, paint)                     # seat stay
	lp.beam(head, front, 0.06, DARK)                     # fork
	lp.beam(head, head + Vector3(0, 0.3, -0.06), 0.05, DARK) # tall BMX stem and riser bars
	lp.beam(head + Vector3(-0.34, 0.3, -0.06), head + Vector3(0.34, 0.3, -0.06), 0.045, DARK)
	lp.beam(head + Vector3(0, 0.12, -0.03), head + Vector3(0, 0.3, -0.06), 0.03, DARK)
	lp.box(seat + Vector3(0, 0.03, -0.02), Vector3(0.12, 0.05, 0.24), DARK)
	# Pegs on both axles and a number plate on the bars, readable from above.
	for axle in [rear, front]:
		lp.beam(axle + Vector3(-0.2, 0, 0), axle + Vector3(0.2, 0, 0), 0.06, Color(0.75, 0.75, 0.78))
	lp.box(head + Vector3(0, 0.16, 0.04), Vector3(0.26, 0.16, 0.03), Color(0.98, 0.97, 0.92), Basis(Vector3.RIGHT, -0.25))
	return lp.commit()

## A BMX rider stood on the pedals: knees bent, elbows out, baggy clothes.
## Each garment is its own surface so it can carry its own texture.
func _rider_mesh() -> ArrayMesh:
	var skin := LowPoly.new()
	var shirt := LowPoly.new()
	var pants := LowPoly.new()
	var gear := LowPoly.new()
	var tone: Color = SKINS[style % SKINS.size()]
	var trousers: Color = TROUSERS[(style / 2) % TROUSERS.size()]
	var hip := Vector3(0, 0.92, -0.2)
	var shoulder := Vector3(0, 1.3, 0.06)
	var hands := Vector3(0, 0.96, 0.3)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.1
		# Shoulder, short sleeve, then bare arm out to the grips.
		var arm_top := shoulder + Vector3(side * 0.17, -0.06, -0.01)
		var elbow := Vector3(side * 0.3, 1.06, 0.14)
		shirt.beam(arm_top, arm_top.lerp(elbow, 0.4), 0.105, color)
		skin.beam(arm_top.lerp(elbow, 0.4), elbow, 0.08, tone)
		skin.beam(elbow, hands + Vector3(side * 0.28, 0, 0), 0.07, tone)
		gear.box(hands + Vector3(side * 0.28, 0, 0), Vector3(0.09, 0.08, 0.09), DARK)
	# Tee: one smooth torso from the waist up through sloping shoulders, so
	# nothing bulges out at the back.
	_torso(shirt, hip + Vector3(0, -0.04, 0), shoulder + Vector3(0, 0.02, 0), color)
	skin.beam(shoulder, shoulder + Vector3(0, 0.1, 0.04), 0.08, tone)
	var head := HEAD_AT
	skin.blob(head, Vector3(0.105, 0.125, 0.115), tone, _rng, 6, 12, 0.0)
	# Eyes, so there's a face under the lid.
	for side in [-1.0, 1.0]:
		gear.box(head + Vector3(side * 0.042, 0.01, 0.108), Vector3(0.022, 0.03, 0.012), Color(0.08, 0.07, 0.07))
	# Hair peeking out at the back and sides.
	var hair: Color = [Color(0.2, 0.13, 0.08), Color(0.08, 0.07, 0.06), Color(0.75, 0.55, 0.3), Color(0.45, 0.22, 0.1)][(style + 1) % 4]
	gear.dome(head + Vector3(0, -0.02, -0.015), Vector3(0.112, 0.12, 0.118), hair, 3, 12)
	if style % 2 == 0:
		# Open-face lid with a short peak, the 90s BMX staple.
		gear.dome(head + Vector3(0, 0.01, -0.01), Vector3(0.135, 0.15, 0.145), color.darkened(0.25), 5, 14)
		gear.box(head + Vector3(0, 0.07, 0.13), Vector3(0.16, 0.018, 0.07), color.darkened(0.45), Basis(Vector3.RIGHT, 0.3))
		gear.box(head + Vector3(0, 0.158, -0.02), Vector3(0.04, 0.012, 0.12), accent)
	else:
		# Cap on backwards.
		gear.dome(head + Vector3(0, 0.03, 0), Vector3(0.12, 0.1, 0.125), accent, 4, 14)
		gear.box(head + Vector3(0, 0.04, -0.16), Vector3(0.14, 0.015, 0.1), accent.darkened(0.3), Basis(Vector3.RIGHT, -0.15))
	var patterns := [Tex.plaid(), Tex.stripes(), Tex.cotton()]
	var mesh := skin.commit(null, Tex.material(Tex.cotton(), 3.0, false))
	shirt.commit(mesh, Tex.material(patterns[style % patterns.size()], 2.5, false))
	pants.commit(mesh, Tex.material(Tex.denim(), 3.0, false))
	gear.commit(mesh, Tex.material(Tex.cotton(), 3.0, false))
	return mesh

const HEAD_AT := Vector3(0, 1.5, 0.12)

func _build_legs() -> void:
	var trousers: Color = TROUSERS[(style / 2) % TROUSERS.size()]
	var denim := Tex.material(Tex.denim(), 3.0, false)
	var cotton := Tex.material(Tex.cotton(), 3.0, false)
	for side in [-1.0, 1.0]:
		var leg := {"side": side}
		for part in ["thigh", "shin"]:
			var lp := LowPoly.new()
			lp.beam(Vector3.ZERO, Vector3(0, 0, -1), 0.15 if part == "thigh" else 0.13, trousers)
			var mi := MeshInstance3D.new()
			mi.mesh = lp.commit(null, denim)
			rider.add_child(mi)
			leg[part] = mi
		var shoe := LowPoly.new()
		shoe.box(Vector3(0, -0.01, 0.04), Vector3(0.12, 0.09, 0.25), accent)
		shoe.box(Vector3(0, -0.05, 0.04), Vector3(0.13, 0.03, 0.26), Color(0.92, 0.9, 0.85))
		var smi := MeshInstance3D.new()
		smi.mesh = shoe.commit(null, cotton)
		rider.add_child(smi)
		leg.shoe = smi
		_legs.append(leg)
	_pose_legs()

## Feet on the pedals, knees found by two-bone IK, bent forward and a little out.
func _pose_legs() -> void:
	for leg in _legs:
		var side: float = leg.side
		var a := _crank + (0.0 if side > 0.0 else PI)
		var foot := CRANK_AT + Vector3(side * 0.13, cos(a) * CRANK_R, sin(a) * CRANK_R)
		var hip := HIP + Vector3(side * 0.1, 0, 0)
		var to_foot := foot - hip
		var dist := clampf(to_foot.length(), 0.1, THIGH + SHIN - 0.01)
		var dir := to_foot.normalized()
		var along := (THIGH * THIGH - SHIN * SHIN + dist * dist) / (2.0 * dist)
		var rise := sqrt(maxf(0.0, THIGH * THIGH - along * along))
		var bend := Vector3(0, -dir.z, dir.y).normalized()
		if bend.z < 0.0: bend = -bend
		var knee := hip + dir * along + bend * rise + Vector3(side * 0.06, 0, 0)
		_stretch(leg.thigh, hip, knee)
		_stretch(leg.shin, knee, foot + Vector3(0, 0.08, 0))
		leg.shoe.position = foot

func _stretch(node: Node3D, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var basis := Basis.looking_at(dir, Vector3.RIGHT if absf(dir.normalized().x) < 0.9 else Vector3.UP)
	node.transform = Transform3D(basis * Basis.from_scale(Vector3(1, 1, dir.length())), from)

## Elliptical rings from waist to neck: (height 0..1, half width, half depth).
const TORSO_RINGS := [Vector3(0.0, 0.15, 0.1), Vector3(0.45, 0.16, 0.105), Vector3(0.8, 0.185, 0.11), Vector3(0.93, 0.15, 0.095), Vector3(1.0, 0.07, 0.06)]

func _torso(lp: LowPoly, from: Vector3, to: Vector3, col: Color) -> void:
	var axis := to - from
	var up := axis.normalized()
	var side := Vector3.RIGHT
	var front := side.cross(up).normalized() * -1.0
	if front.z < 0.0: front = -front
	var n := 10
	var rings: Array = []
	for r in TORSO_RINGS:
		var ring: Array[Vector3] = []
		for i in n:
			var a := TAU * i / n
			ring.append(from + axis * r.x + side * cos(a) * r.y + front * sin(a) * r.z)
		rings.append(ring)
	var centre := from + axis * 0.5
	for k in rings.size() - 1:
		for i in n:
			var j := (i + 1) % n
			lp.quad(rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], col, centre)
	for i in range(1, n - 1):
		lp.tri(rings[0][0], rings[0][i], rings[0][i + 1], col, centre)
		var top: Array = rings[rings.size() - 1]
		lp.tri(top[0], top[i], top[i + 1], col, centre)

func pose(b: Bike, c: Course, delta: float) -> void:
	position = c.world(b.s, b.d, b.y)
	# Our track frame has +d on the right, so heading turns the other way.
	var yaw_world := c.heading(b.s) - b.psi - b.yaw
	rotation = Vector3(0, yaw_world, 0)
	body.rotation = Vector3(-b.pitch, 0, b.lean)
	_time += delta
	var spin := b.v / (WHEEL * SCALE) * delta
	# Pump over the bumps and lean in; in the air, long jumps get a tailwhip.
	rider.position.y = sin(_time * (3.0 + b.v * 0.5)) * 0.025 if b.grounded and not b.crashed else rider.position.y
	if b.grounded or b.crashed:
		_whip = 0.0
		_whip_rate = 0.0
	elif _whip_rate == 0.0 and b.air_time > 0.1:
		# Only whip when the flight is long enough to finish the turn.
		var h := b.y - c.height(b.s, b.d)
		var left := (b.vy + sqrt(maxf(0.0, b.vy * b.vy + 2.0 * Bike.G * h))) / Bike.G
		_whip_rate = TAU / (left - 0.1) if left > 0.55 else -1.0
	elif _whip_rate > 0.0:
		_whip = minf(TAU, _whip + _whip_rate * delta)
	bike.rotation.y = _whip
	front_wheel.rotate_x(spin)
	rear_wheel.rotate_x(spin)
	# Pedalling turns the cranks with the back wheel; coasting, the feet
	# settle level, the way BMX riders stand on the pedals.
	if b.pedaling > 0.1 and b.grounded and not b.crashed:
		_crank += maxf(spin / 2.2, 7.0 * delta)
	else:
		var level := roundf((_crank - PI * 0.5) / PI) * PI + PI * 0.5
		_crank = move_toward(_crank, level, 4.0 * delta)
	_crank = fmod(_crank, TAU * 100.0)
	_pose_legs()
	if b.crashed:
		if not _was_crashed:
			rider.position = Vector3.ZERO
			rider.rotation = Vector3.ZERO
			dust.restart()
			dust.emitting = true
		var t := Bike.CRASH_TIME - b.crash_t
		rider.position = Vector3(0, maxf(0.0, 1.2 * t - 3.0 * t * t) - minf(t, 0.5) * 0.9, minf(t * 2.5, 1.6))
		rider.rotation += b.crash_spin * delta * maxf(0.0, 1.0 - t)
		body.rotation.z = lerpf(body.rotation.z, 1.35, minf(1.0, delta * 10.0))
	elif _was_crashed:
		rider.position = Vector3.ZERO
		rider.rotation = Vector3.ZERO
	_was_crashed = b.crashed
	visible = b.invulnerable <= 0.0 or b.crashed or int(b.invulnerable * 10.0) % 2 == 0
	dust.emitting = (b.grounded and b.v > 7.0 and not b.crashed) or b.landed or b.crashed or b.skid > 0.2
