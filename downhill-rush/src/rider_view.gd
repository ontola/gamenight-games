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
		var x: float = side * 0.12
		var knee := Vector3(x * 1.6, 0.66, 0.1)
		var foot := Vector3(x * 1.2, WHEEL + 0.05, -0.05 + side * 0.06)
		pants.beam(hip + Vector3(x, 0, 0), knee, 0.16, trousers)
		pants.beam(knee, foot + Vector3(0, 0.08, 0), 0.15, trousers)
		gear.box(foot + Vector3(0, -0.01, 0.04), Vector3(0.14, 0.1, 0.27), accent)
		gear.box(foot + Vector3(0, -0.055, 0.04), Vector3(0.15, 0.03, 0.28), Color(0.92, 0.9, 0.85))
		var elbow := Vector3(side * 0.34, 1.08, 0.1)
		shirt.beam(shoulder + Vector3(side * 0.19, 0, 0), shoulder + Vector3(side * 0.28, -0.12, 0.03), 0.16, color)
		skin.beam(shoulder + Vector3(side * 0.27, -0.1, 0.03), elbow, 0.085, tone)
		skin.beam(elbow, hands + Vector3(side * 0.3, 0, 0), 0.075, tone)
		gear.box(hands + Vector3(side * 0.3, 0, 0), Vector3(0.1, 0.09, 0.11), DARK)
	# Baggy tee: wider at the hem than at the chest.
	shirt.cone(hip + Vector3(0, -0.06, 0), 0.24, 0.21, (shoulder - hip).length() + 0.04, 6, color,
		Basis(Vector3.RIGHT, (shoulder - hip).angle_to(Vector3.UP)).scaled(Vector3(1.0, 1.0, 0.75)), 0.08)
	skin.beam(shoulder, shoulder + Vector3(0, 0.12, 0.04), 0.09, tone)
	var head := HEAD_AT
	skin.blob(head, Vector3(0.12, 0.14, 0.13), tone, _rng, 3, 7, 0.0)
	if style % 2 == 0:
		# Open-face lid with a peak, the 90s BMX staple.
		gear.blob(head + Vector3(0, 0.05, -0.01), Vector3(0.15, 0.13, 0.16), color.darkened(0.25), _rng, 3, 8, 0.0)
		gear.box(head + Vector3(0, 0.08, 0.15), Vector3(0.2, 0.025, 0.1), color.darkened(0.45), Basis(Vector3.RIGHT, 0.25))
		gear.box(head + Vector3(0, 0.15, 0.0), Vector3(0.05, 0.03, 0.3), accent)
	else:
		# Cap on backwards.
		gear.blob(head + Vector3(0, 0.07, 0), Vector3(0.135, 0.09, 0.14), accent, _rng, 2, 8, 0.0)
		gear.box(head + Vector3(0, 0.06, -0.17), Vector3(0.17, 0.02, 0.12), accent.darkened(0.3))
	var patterns := [Tex.plaid(), Tex.stripes(), Tex.cotton()]
	var mesh := skin.commit(null, Tex.material(Tex.cotton(), 3.0, false))
	shirt.commit(mesh, Tex.material(patterns[style % patterns.size()], 2.5, false))
	pants.commit(mesh, Tex.material(Tex.denim(), 3.0, false))
	gear.commit(mesh, Tex.material(Tex.cotton(), 3.0, false))
	return mesh

const HEAD_AT := Vector3(0, 1.5, 0.12)

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
