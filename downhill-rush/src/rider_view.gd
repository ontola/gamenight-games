class_name RiderView
extends Node3D
## A low-poly BMX rider, posed from a Bike state each frame.

const SCALE := 2.0
const WHEEL := 0.27
const WHEELBASE := 0.98
const DARK := Color(0.2, 0.21, 0.25)
const SKIN := Color(0.93, 0.76, 0.62)

var color := Color.WHITE
var body: Node3D           ## Pitches and leans with the bike.
var rider: Node3D          ## Tumbles away from the bike in a crash.
var front_wheel: Node3D
var rear_wheel: Node3D
var tag: Label3D
var dust: CPUParticles3D
var marker: MeshInstance3D
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
	front_wheel = _wheel(Vector3(0, WHEEL, WHEELBASE * 0.5))
	rear_wheel = _wheel(Vector3(0, WHEEL, -WHEELBASE * 0.5))
	rider = Node3D.new()
	body.add_child(rider)
	var rider_mesh := MeshInstance3D.new()
	rider_mesh.mesh = _rider_mesh()
	rider.add_child(rider_mesh)
	body.scale = Vector3.ONE * SCALE
	marker = MeshInstance3D.new()
	marker.mesh = _marker_mesh()
	marker.top_level = true
	add_child(marker)
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
	tag.position = Vector3(0, 1.0, 0)
	tag.offset = Vector2(0, 120)
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
	lp.box(head + Vector3(0, 0.22, 0.02), Vector3(0.36, 0.26, 0.03), Color(0.98, 0.97, 0.92), Basis(Vector3.RIGHT, -0.25))
	return lp.commit()

## A BMX rider stands on the pedals: knees bent, weight forward, elbows out.
func _rider_mesh() -> ArrayMesh:
	var lp := LowPoly.new()
	var jersey := color
	var hip := Vector3(0, 1.0, -0.2)
	var shoulder := Vector3(0, 1.42, 0.12)
	var hands := Vector3(0, 0.96, 0.3)
	for side in [-1.0, 1.0]:
		var x: float = side * 0.14
		var knee := Vector3(x * 1.4, 0.72, 0.08)
		var foot := Vector3(x * 1.2, WHEEL + 0.05, -0.05 + side * 0.06)
		lp.beam(hip + Vector3(x, 0, 0), knee, 0.13, DARK)
		lp.beam(knee, foot, 0.11, DARK)
		lp.box(foot + Vector3(0, -0.02, 0.04), Vector3(0.11, 0.08, 0.22), Color(0.95, 0.95, 0.92))
		var elbow := Vector3(side * 0.34, 1.16, 0.12)
		lp.beam(shoulder + Vector3(side * 0.19, 0, 0), elbow, 0.1, jersey)
		lp.beam(elbow, hands + Vector3(side * 0.3, 0, 0), 0.09, jersey.darkened(0.05))
	lp.beam(hip, shoulder, 0.36, jersey)
	lp.box(shoulder + Vector3(0, -0.04, -0.02), Vector3(0.46, 0.16, 0.22), jersey)
	# Full-face helmet in the player colour with a stripe: the part you see most from above.
	var head := shoulder + Vector3(0, 0.24, 0.1)
	lp.blob(head, Vector3(0.19, 0.18, 0.21), color.darkened(0.05), _rng, 3, 7, 0.03)
	lp.box(head + Vector3(0, 0.15, 0.0), Vector3(0.07, 0.06, 0.4), Color(0.98, 0.97, 0.92))
	lp.box(head + Vector3(0, -0.02, 0.17), Vector3(0.24, 0.08, 0.06), Color(0.2, 0.22, 0.28))
	lp.box(head + Vector3(0, -0.12, 0.17), Vector3(0.18, 0.08, 0.08), color.darkened(0.3))
	return lp.commit()

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
		lp.quad(o0 * 1.25, o1 * 1.25, o1 * 1.6, o0 * 1.6, Color.WHITE)
	var mesh := lp.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh

func pose(b: Bike, c: Course, delta: float) -> void:
	position = c.world(b.s, b.d, b.y)
	marker.global_position = c.world(b.s, b.d) + Vector3(0, 0.12, 0)
	marker.visible = not b.crashed
	# Our track frame has +d on the right, so heading turns the other way.
	var yaw_world := c.heading(b.s) - b.psi
	rotation = Vector3(0, yaw_world, 0)
	body.rotation = Vector3(-b.pitch, 0, b.lean)
	var spin := b.v / (WHEEL * SCALE) * delta
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
