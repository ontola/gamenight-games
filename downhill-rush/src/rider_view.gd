class_name RiderView
extends Node3D
## A low-poly BMX rider, posed from a Bike state each frame.

const SCALE := 2.2
const WHEEL := 0.27
const WHEELBASE := 0.98
const DARK := Color(0.2, 0.21, 0.25)
const SKIN := Color(0.93, 0.76, 0.62)

## The extra on top of each helmet. From above, that is what people spot.
const HATS := ["mohawk", "horns", "cat ears", "propeller", "unicorn", "crown", "antenna", "comb"]
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
var cape: Node3D
var spinner: Node3D        ## Propellers and antennas that react to speed.
var tag: Label3D
var dust: CPUParticles3D
var marker: MeshInstance3D
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
	_extras()
	body.scale = Vector3.ONE * SCALE
	marker = MeshInstance3D.new()
	marker.mesh = _marker_mesh()
	marker.top_level = true
	add_child(marker)
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
	# 20-inch BMX wheel: fat tyre, mag-style spokes in the frame colour.
	lp.ring(Vector3.ZERO, WHEEL - 0.05, 0.06, DARK, 12)
	for k in 3:
		var a := TAU * k / 3.0
		lp.beam(Vector3.ZERO, Vector3(0, cos(a), sin(a)) * (WHEEL - 0.08), 0.04, color.darkened(0.2))
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

## A BMX rider stands on the pedals: knees bent, elbows out, and a head two
## sizes too big, because from above the helmet is the character.
func _rider_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var jersey := color
	var hip := Vector3(0, 0.95, -0.2)
	var shoulder := Vector3(0, 1.3, 0.08)
	var hands := Vector3(0, 0.96, 0.3)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.14
		var knee := Vector3(x * 1.5, 0.7, 0.08)
		var foot := Vector3(x * 1.2, WHEEL + 0.05, -0.05 + side * 0.06)
		lp.beam(hip + Vector3(x, 0, 0), knee, 0.14, DARK)
		lp.beam(knee, foot, 0.12, DARK)
		lp.box(foot + Vector3(0, -0.02, 0.04), Vector3(0.13, 0.09, 0.24), accent)
		var elbow := Vector3(side * 0.36, 1.1, 0.1)
		lp.beam(shoulder + Vector3(side * 0.2, 0, 0), elbow, 0.11, jersey)
		lp.beam(elbow, hands + Vector3(side * 0.3, 0, 0), 0.1, jersey.darkened(0.05))
		lp.blob(hands + Vector3(side * 0.3, 0, 0), Vector3(0.07, 0.07, 0.07), accent, _rng, 2, 5, 0.0)
	lp.beam(hip, shoulder, 0.4, jersey)
	lp.box(shoulder + Vector3(0, -0.04, -0.02), Vector3(0.5, 0.17, 0.24), jersey)
	# A stripe down the back of the jersey in the accent colour.
	lp.beam(hip + Vector3(0, 0.05, -0.19), shoulder + Vector3(0, 0, -0.13), 0.12, accent)
	var head := HEAD_AT
	lp.blob(head, Vector3(0.3, 0.28, 0.32), color.darkened(0.05), _rng, 4, 8, 0.02)
	lp.box(head + Vector3(0, 0.25, -0.02), Vector3(0.1, 0.07, 0.55), accent)
	lp.box(head + Vector3(0, -0.01, 0.27), Vector3(0.38, 0.12, 0.08), Color(0.15, 0.17, 0.22))
	lp.box(head + Vector3(0, -0.17, 0.25), Vector3(0.26, 0.1, 0.1), color.darkened(0.3))
	# Big round eyes on the visor: daft from up close, a bit of life from above.
	for side in [-1.0, 1.0]:
		lp.blob(head + Vector3(side * 0.1, 0.0, 0.335), Vector3(0.07, 0.07, 0.03), Color.WHITE, _rng, 2, 6, 0.0)
		lp.blob(head + Vector3(side * 0.1, 0.01, 0.36), Vector3(0.032, 0.032, 0.015), Color(0.05, 0.05, 0.08), _rng, 2, 5, 0.0)
	_hat(lp, head)
	if style % 3 == 1:
		# Backpack with a little flag.
		lp.box(shoulder + Vector3(0, -0.15, -0.24), Vector3(0.34, 0.36, 0.18), accent.darkened(0.15))
		lp.beam(shoulder + Vector3(0.12, -0.1, -0.3), shoulder + Vector3(0.12, 0.55, -0.32), 0.025, DARK)
		lp.tri(shoulder + Vector3(0.12, 0.55, -0.32), shoulder + Vector3(0.12, 0.35, -0.32), shoulder + Vector3(0.12, 0.45, -0.62), accent)
	return lp.commit()

const HEAD_AT := Vector3(0, 1.62, 0.16)

func _hat(lp: LowPoly, head: Vector3) -> void:
	var top := head + Vector3(0, 0.26, 0)
	match HATS[style % HATS.size()]:
		"mohawk":
			for k in 6:
				var z := 0.22 - k * 0.09
				lp.box(top + Vector3(0, 0.1 - absf(z) * 0.3, z), Vector3(0.06, 0.24 - absf(z) * 0.4, 0.07), accent)
		"horns":
			for side in [-1.0, 1.0]:
				lp.cone(head + Vector3(side * 0.24, 0.16, 0.02), 0.08, 0.0, 0.32, 5, Color(0.97, 0.94, 0.85), Basis(Vector3.FORWARD, side * -0.9))
		"cat ears":
			for side in [-1.0, 1.0]:
				lp.cone(head + Vector3(side * 0.16, 0.2, 0.0), 0.11, 0.0, 0.2, 3, accent, Basis(Vector3.FORWARD, side * -0.35))
		"unicorn":
			lp.cone(head + Vector3(0, 0.2, 0.18), 0.07, 0.0, 0.42, 5, Color(1.0, 0.85, 0.35), Basis(Vector3.RIGHT, 0.6))
		"crown":
			for k in 5:
				var a := TAU * k / 5.0
				lp.cone(top + Vector3(cos(a) * 0.14, -0.05, sin(a) * 0.14), 0.06, 0.0, 0.18, 4, Color(1.0, 0.82, 0.25))
			lp.cone(top - Vector3(0, 0.07, 0), 0.17, 0.17, 0.06, 8, Color(1.0, 0.82, 0.25))
		"comb":
			for k in 4:
				lp.blob(top + Vector3(0, 0.02, 0.15 - k * 0.1), Vector3(0.05, 0.09, 0.06), Color(0.92, 0.2, 0.2), _rng, 2, 5, 0.0)

## Parts that move: capes, propellers and antennas.
func _extras() -> void:
	var hat: String = HATS[style % HATS.size()]
	if hat == "propeller" or hat == "antenna":
		spinner = Node3D.new()
		spinner.position = HEAD_AT + Vector3(0, 0.28, 0)
		rider.add_child(spinner)
		var lp := LowPoly.new()
		if hat == "propeller":
			lp.beam(Vector3.ZERO, Vector3(0, 0.12, 0), 0.04, DARK)
			lp.box(Vector3(0, 0.13, 0), Vector3(0.7, 0.02, 0.1), accent)
			lp.box(Vector3(0, 0.13, 0), Vector3(0.1, 0.02, 0.7), Color(0.98, 0.45, 0.6) if accent != Color(0.98, 0.45, 0.6) else Color.WHITE)
		else:
			lp.beam(Vector3.ZERO, Vector3(0, 0.45, 0), 0.025, DARK)
			lp.blob(Vector3(0, 0.5, 0), Vector3(0.07, 0.07, 0.07), accent, _rng, 2, 6, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = lp.commit()
		spinner.add_child(mi)
	if style % 3 == 2:
		# A cape that streams out behind at speed.
		cape = Node3D.new()
		cape.position = Vector3(0, 1.36, -0.08)
		rider.add_child(cape)
		var lp := LowPoly.new()
		lp.quad(Vector3(-0.25, 0, 0), Vector3(0.25, 0, 0), Vector3(0.36, -0.75, -0.05), Vector3(-0.36, -0.75, -0.05), accent, Vector3(0, -0.3, 0.3))
		var mi := MeshInstance3D.new()
		mi.mesh = lp.commit()
		cape.add_child(mi)

## A disc of the player's colour on the ground under the rider. From straight
## above it says who is who, and in the air it shows where you will land.
func _marker_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var n := 20
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		lp.quad(o0 * 1.3, o1 * 1.3, o1 * 1.55, o0 * 1.55, Color.WHITE)
	var mesh := lp.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh

func pose(b: Bike, c: Course, delta: float) -> void:
	position = c.world(b.s, b.d, b.y)
	marker.global_position = c.world(b.s, b.d) + Vector3(0, 0.18, 0)
	marker.visible = not b.crashed
	# Our track frame has +d on the right, so heading turns the other way.
	var yaw_world := c.heading(b.s) - b.psi
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
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, -clampf(b.v / 12.0, 0.1, 1.25) + sin(_time * 14.0) * 0.12, minf(1.0, delta * 8.0))
	if spinner:
		spinner.rotate_y(delta * (4.0 + b.v * 2.2))
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
	dust.emitting = (b.grounded and b.v > 7.0 and not b.crashed) or b.landed or b.crashed
