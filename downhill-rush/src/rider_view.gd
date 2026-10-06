class_name RiderView
extends Node3D
## A low-poly rider on a bike, posed from a Bike state each frame.

const SCALE := 1.45
const DARK := Color(0.2, 0.21, 0.25)
const SKIN := Color(0.93, 0.76, 0.62)

var color := Color.WHITE
var body: Node3D           ## Pitches and leans with the bike.
var rider: Node3D          ## Tumbles away from the bike in a crash.
var front_wheel: Node3D
var rear_wheel: Node3D
var tag: Label3D
var dust: CPUParticles3D
var _was_crashed := false
var _rng := RandomNumberGenerator.new()


func setup(p_color: Color, p_name: String) -> void:
	color = p_color
	_rng.seed = hash(p_name)
	body = Node3D.new()
	add_child(body)
	var frame := MeshInstance3D.new()
	frame.mesh = _frame_mesh()
	body.add_child(frame)
	front_wheel = _wheel(Vector3(0, 0.36, 0.56))
	rear_wheel = _wheel(Vector3(0, 0.36, -0.56))
	rider = Node3D.new()
	body.add_child(rider)
	var rider_mesh := MeshInstance3D.new()
	rider_mesh.mesh = _rider_mesh()
	rider.add_child(rider_mesh)
	body.scale = Vector3.ONE * SCALE
	tag = Label3D.new()
	tag.text = p_name + "\n▼"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0011
	tag.font_size = 20
	tag.outline_size = 9
	tag.modulate = p_color.lightened(0.25)
	tag.outline_modulate = Color(0.08, 0.09, 0.12, 0.9)
	tag.no_depth_test = true
	tag.render_priority = 10
	tag.position = Vector3(0, 3.2, 0)
	tag.line_spacing = -8
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
	tag.text = p_name + "\n▼"

func _wheel(at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	body.add_child(pivot)
	var lp := LowPoly.new()
	lp.ring(Vector3.ZERO, 0.32, 0.055, DARK, 12)
	lp.beam(Vector3(0, -0.3, 0), Vector3(0, 0.3, 0), 0.025, Color(0.75, 0.75, 0.78))
	lp.beam(Vector3(0, 0, -0.3), Vector3(0, 0, 0.3), 0.025, Color(0.75, 0.75, 0.78))
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	pivot.add_child(mi)
	return pivot

func _frame_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var paint := color
	var bb := Vector3(0, 0.38, 0.0)
	var seat := Vector3(0, 0.88, -0.18)
	var head := Vector3(0, 0.95, 0.42)
	lp.beam(bb, seat, 0.07, paint)                       # seat tube
	lp.beam(seat, head, 0.07, paint)                     # top tube
	lp.beam(bb, head - Vector3(0, 0.12, 0), 0.08, paint) # down tube
	lp.beam(bb, Vector3(0, 0.36, -0.56), 0.05, paint)    # chain stay
	lp.beam(seat, Vector3(0, 0.36, -0.56), 0.05, paint)  # seat stay
	lp.beam(head, Vector3(0, 0.36, 0.56), 0.06, DARK)    # fork
	lp.beam(head, head + Vector3(0, 0.18, -0.04), 0.05, DARK)
	lp.beam(head + Vector3(-0.38, 0.18, -0.04), head + Vector3(0.38, 0.18, -0.04), 0.04, DARK)
	lp.box(seat + Vector3(0, 0.05, -0.02), Vector3(0.12, 0.05, 0.28), DARK)
	return lp.commit()

func _rider_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var jersey := color
	var hip := Vector3(0, 1.02, -0.12)
	var shoulder := Vector3(0, 1.42, 0.2)
	var hands := Vector3(0, 1.13, 0.38)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.13
		var knee := Vector3(x * 1.3, 0.78, 0.18)
		var foot := Vector3(x, 0.4, 0.02 + side * 0.08)
		lp.beam(hip + Vector3(x, 0, 0), knee, 0.13, DARK)
		lp.beam(knee, foot, 0.11, DARK)
		lp.box(foot + Vector3(0, -0.02, 0.04), Vector3(0.1, 0.07, 0.2), Color(0.15, 0.15, 0.17))
		var elbow := Vector3(side * 0.24, 1.22, 0.24)
		lp.beam(shoulder + Vector3(side * 0.18, 0, 0), elbow, 0.1, jersey)
		lp.beam(elbow, hands + Vector3(side * 0.3, 0, 0), 0.09, jersey.darkened(0.05))
	lp.beam(hip, shoulder, 0.36, jersey)
	lp.box(shoulder + Vector3(0, -0.05, -0.02), Vector3(0.44, 0.16, 0.22), jersey)
	# Number plate: a white board on the bars, readable from above.
	var head := shoulder + Vector3(0, 0.25, 0.12)
	lp.blob(head, Vector3(0.13, 0.15, 0.14), SKIN, _rng, 3, 6, 0.03)
	lp.blob(head + Vector3(0, 0.05, -0.02), Vector3(0.17, 0.14, 0.2), color.darkened(0.05), _rng, 3, 7, 0.03)
	lp.box(head + Vector3(0, 0.12, 0.18), Vector3(0.26, 0.03, 0.1), color.darkened(0.25))
	lp.box(head + Vector3(0, -0.02, 0.14), Vector3(0.2, 0.06, 0.04), Color(0.2, 0.22, 0.28))
	return lp.commit()

func pose(b: Bike, c: Course, delta: float) -> void:
	position = c.world(b.s, b.d, b.y)
	# Our track frame has +d on the right, so heading turns the other way.
	var yaw_world := c.heading(b.s) - b.psi
	rotation = Vector3(0, yaw_world, 0)
	body.rotation = Vector3(-b.pitch, 0, b.lean)
	var spin := b.v / (0.36 * SCALE) * delta
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
