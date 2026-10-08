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
var steering: Node3D       ## Fork, bars and front wheel; turns as you steer.
var tag: Label3D
var dust: CPUParticles3D
var _was_crashed := false
var _crash_yaw := 0.0         ## World heading when the crash began.
var _bike_basis := Basis()
var blood: CPUParticles3D
var _parts: Array[Dictionary] = []   ## Body parts the ragdoll moves: node, rest frame, joints.
var _splats_seen := 0
# The rider's body moves on its own over the bike: pitch and roll have their
# own inertia, and the legs are a spring that soaks up the bike's bumps.
var _pitch := 0.0        ## Rider's world pitch, nose-up positive.
var _pitch_v := 0.0
var _roll := 0.0         ## Rider's world roll.
var _roll_v := 0.0
var _squat := 0.0        ## Hips below the ready stance, model units (negative = lower).
var _squat_v := 0.0
var _shift := 0.0        ## Weight fore (+) or aft (-) over the bike, model units.
var _shift_v := 0.0
var _reach := 0.0        ## Extra forward lean to keep the hands on the bars, radians.
const BELLY := Vector3(0, 1.02, 0.12)   ## Front of the tummy, rider model units.
var _last_y := INF
var _last_vy := 0.0
var _last_v := 0.0
const BLOOD := Color(0.55, 0.04, 0.05)
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
	_build_steering()
	front_wheel = _wheel(FRONT_AXLE - HEAD, steering)
	rear_wheel = _wheel(Vector3(0, WHEEL, -WHEELBASE * 0.5))
	rider = Node3D.new()
	body.add_child(rider)
	_build_rider()
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
	blood = CPUParticles3D.new()
	blood.amount = 10
	blood.lifetime = 0.6
	blood.one_shot = true
	blood.explosiveness = 0.9
	blood.local_coords = false
	blood.emitting = false
	var drop := BoxMesh.new()
	drop.size = Vector3.ONE * 0.09
	var red := StandardMaterial3D.new()
	red.albedo_color = BLOOD
	red.roughness = 0.3
	drop.material = red
	blood.mesh = drop
	blood.direction = Vector3(0, 1, 0)
	blood.spread = 60.0
	blood.initial_velocity_min = 1.5
	blood.initial_velocity_max = 3.5
	blood.gravity = Vector3(0, -12, 0)
	add_child(blood)

func set_player_name(p_name: String) -> void:
	tag.text = p_name.to_upper()

func _wheel(at: Vector3, parent: Node3D = null) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	(parent if parent else bike).add_child(pivot)
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
	lp.box(seat + Vector3(0, 0.03, -0.02), Vector3(0.12, 0.05, 0.24), DARK)
	# Pegs on the rear axle; the front ones turn with the fork.
	lp.beam(rear + Vector3(-0.2, 0, 0), rear + Vector3(0.2, 0, 0), 0.06, Color(0.75, 0.75, 0.78))
	return lp.commit()

## Fork, stem, bars, number plate and front wheel turn together about the
## head tube, which leans back like a real one.
const HEAD := Vector3(0, 0.66, 0.36)
const FRONT_AXLE := Vector3(0, WHEEL, WHEELBASE * 0.5)
const GRIP := Vector3(0.32, 0.3, -0.06)   ## Left grip, relative to the head tube top.

func _build_steering() -> void:
	steering = Node3D.new()
	steering.position = HEAD
	bike.add_child(steering)
	var lp := LowPoly.new()
	var axle := FRONT_AXLE - HEAD
	lp.beam(Vector3.ZERO, axle, 0.06, DARK)                                  # fork
	lp.beam(Vector3.ZERO, Vector3(0, 0.3, -0.06), 0.05, DARK)               # tall BMX stem and riser bars
	lp.beam(Vector3(-0.34, 0.3, -0.06), Vector3(0.34, 0.3, -0.06), 0.045, DARK)
	lp.beam(Vector3(0, 0.12, -0.03), Vector3(0, 0.3, -0.06), 0.03, DARK)
	for side in [-1.0, 1.0]:
		lp.beam(Vector3(side * 0.26, 0.3, -0.06), Vector3(side * 0.37, 0.3, -0.06), 0.06, Color(0.2, 0.2, 0.22))  # grips
	lp.beam(axle + Vector3(-0.2, 0, 0), axle + Vector3(0.2, 0, 0), 0.06, Color(0.75, 0.75, 0.78))  # front pegs
	lp.box(Vector3(0, 0.16, 0.04), Vector3(0.26, 0.16, 0.03), Color(0.98, 0.97, 0.92), Basis(Vector3.RIGHT, -0.25))  # number plate
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	steering.add_child(mi)

## Turn the bars: about the head tube's axis, right positive.
func _steer(angle: float) -> void:
	steering.basis = Basis((FRONT_AXLE - HEAD).normalized(), angle)

## A BMX rider stood on the pedals: knees bent, elbows out, baggy clothes.
## Built as body parts (torso, head, upper arms, forearms; legs separately)
## so a crash can throw them around as a ragdoll. Each garment is its own
## surface so it can carry its own texture.
func _build_rider() -> void:
	var tone: Color = SKINS[style % SKINS.size()]
	var torso := _kit()
	var head_kit := _kit()
	var shoulder := Vector3(0, 1.3, 0.06)
	for side in [-1.0, 1.0]:
		var left: bool = side > 0.0
		var upper := _kit()
		var fore := _kit()
		# Shoulder, short sleeve, then bare arm out to the grips.
		var arm_top: Vector3 = Ragdoll.POSE[Ragdoll.SHOULDER_L if left else Ragdoll.SHOULDER_R]
		var elbow: Vector3 = Ragdoll.POSE[Ragdoll.ELBOW_L if left else Ragdoll.ELBOW_R]
		var hand: Vector3 = Ragdoll.POSE[Ragdoll.HAND_L if left else Ragdoll.HAND_R]
		upper.shirt.beam(arm_top, arm_top.lerp(elbow, 0.4), 0.105, color)
		upper.skin.beam(arm_top.lerp(elbow, 0.4), elbow, 0.08, tone)
		fore.skin.beam(elbow, hand, 0.07, tone)
		fore.gear.box(hand, Vector3(0.09, 0.08, 0.09), DARK)
		_add_part(upper, Ragdoll.SHOULDER_L if left else Ragdoll.SHOULDER_R, Ragdoll.ELBOW_L if left else Ragdoll.ELBOW_R)
		_add_part(fore, Ragdoll.ELBOW_L if left else Ragdoll.ELBOW_R, Ragdoll.HAND_L if left else Ragdoll.HAND_R)
	# Tee: one smooth torso from the waist up through sloping shoulders, so
	# nothing bulges out at the back.
	_torso(torso.shirt, HIP + Vector3(0, -0.04, 0), shoulder + Vector3(0, 0.02, 0), color)
	torso.skin.beam(shoulder, shoulder + Vector3(0, 0.1, 0.04), 0.08, tone)
	_add_part(torso, Ragdoll.PELVIS, Ragdoll.CHEST)
	var head := HEAD_AT
	var gear: LowPoly = head_kit.gear
	head_kit.skin.blob(head, Vector3(0.105, 0.125, 0.115), tone, _rng, 6, 12, 0.0)
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
	_add_part(head_kit, Ragdoll.CHEST, Ragdoll.HEAD)

func _kit() -> Dictionary:
	return {"skin": LowPoly.new(), "shirt": LowPoly.new(), "gear": LowPoly.new()}

## One body part: its mesh, and the frame it has in the rest pose, set by the
## joint it hangs from (`a`) and the one it points at (`b`).
func _add_part(kit: Dictionary, a: int, b: int) -> void:
	var patterns := [Tex.plaid(), Tex.stripes(), Tex.cotton()]
	var mesh: ArrayMesh = kit.skin.commit(null, Tex.material(Tex.cotton(), 3.0, false))
	kit.shirt.commit(mesh, Tex.material(patterns[style % patterns.size()], 2.5, false))
	kit.gear.commit(mesh, Tex.material(Tex.cotton(), 3.0, false))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rider.add_child(mi)
	var side: Vector3 = Ragdoll.POSE[Ragdoll.SHOULDER_L] - Ragdoll.POSE[Ragdoll.SHOULDER_R]
	_parts.append({"node": mi, "a": a, "b": b, "rest": _joint_frame(Ragdoll.POSE[a], Ragdoll.POSE[b], side).affine_inverse()})

## A frame at `a`, y pointing at `b`, x as close to `side` as it can be.
static func _joint_frame(a: Vector3, b: Vector3, side: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := side - y * side.dot(y)
	x = x.normalized() if x.length() > 0.001 else y.cross(Vector3.FORWARD).normalized()
	return Transform3D(Basis(x, y, x.cross(y)), a)

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
		# The pedal sits on the bike; the hips ride on the body, which moves
		# over the bike, so bring the pedal into the body's frame.
		var foot := rider.transform.affine_inverse() * (bike.transform * (CRANK_AT + Vector3(side * 0.13, cos(a) * CRANK_R, sin(a) * CRANK_R)))
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
	if not b.crashed: _ride_body(b, delta)
	_steer(b.steer_angle)
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
	if not b.crashed: _pose_arms()
	var crashing := b.crashed and b.rider_body != null
	if crashing:
		if not _was_crashed:
			_crash_yaw = yaw_world
			_bike_basis = Basis.from_euler(Vector3(-b.pitch, 0, b.lean))
			_splats_seen = 0
			dust.restart()
		_pose_crash(b, c, delta)
	elif _was_crashed:
		rider.transform = Transform3D.IDENTITY
		_pitch = b.pitch
		_pitch_v = 0.0
		_squat = -0.2
		_squat_v = 0.0
		for part in _parts: part.node.transform = Transform3D.IDENTITY
		_pose_legs()
		body.scale = Vector3.ONE * SCALE
		body.rotation = Vector3(-b.pitch, 0, b.lean)
	_was_crashed = crashing
	visible = b.invulnerable <= 0.0 or b.crashed or int(b.invulnerable * 10.0) % 2 == 0
	var scraping := crashing and ((b.rider_body.grounded and b.rider_body.v.length() > 1.5) or b.rider_body.hit > 2.5 or b.bike_body.hit > 1.5)
	dust.emitting = (b.grounded and b.v > 7.0 and not b.crashed) or b.landed or scraping or b.skid > 0.2

## Body over bike. The bike follows every bump and slope; the rider's mass
## doesn't. Their pitch and roll chase a calmer target with their own lag,
## the legs act as a spring-damper against the bike's vertical jolts (and
## a landing drops them into a squat), and weight goes back on steep
## descents and forward when the bike slows hard. Knees and elbows make up
## the difference, through the IK on legs and arms.
func _ride_body(b: Bike, delta: float) -> void:
	if delta <= 0.0: return
	var y := position.y
	var vy := 0.0 if _last_y == INF else (y - _last_y) / delta
	var ay := 0.0 if _last_y == INF else clampf((vy - _last_vy) / delta, -60.0, 60.0)
	var along := clampf((b.v - _last_v) / delta, -30.0, 30.0)
	_last_y = y
	_last_vy = vy
	_last_v = b.v
	# Pitch: mostly level, leaning a little with the slope.
	var want_pitch := b.pitch * 0.45 if b.grounded else b.pitch * 0.6
	_pitch_v += (70.0 * (want_pitch - _pitch) - 13.0 * _pitch_v) * delta
	_pitch += _pitch_v * delta
	# Roll: the bike leans more than the body in a turn.
	_roll_v += (70.0 * (b.lean * 0.5 - _roll) - 13.0 * _roll_v) * delta
	_roll += _roll_v * delta
	# Legs: the bike's vertical acceleration pushes the body down into them.
	var stance := -0.04 - 0.08 * clampf(absf(b.pitch), 0.0, 1.0)
	var jolt := -ay / SCALE * 0.012 if b.grounded else 0.0
	if b.landed: _squat_v -= clampf(0.5 + b.severity * 1.2, 0.0, 1.8)
	_squat_v += (150.0 * (stance - _squat) - 14.0 * _squat_v + jolt * 60.0) * delta
	_squat = clampf(_squat + _squat_v * delta, -0.24, 0.06)
	# Weight back down steep pitches, forward when the bike slows.
	var want_shift := clampf(b.pitch * 0.22 - along * 0.006, -0.16, 0.1)
	_shift_v += (90.0 * (want_shift - _shift) - 15.0 * _shift_v) * delta
	_shift += _shift_v * delta
	# The body turns about the pedals, where it stands on the bike.
	var pivot := CRANK_AT
	var turn := Basis.from_euler(Vector3(b.pitch - _pitch + _reach, 0.0, _roll - b.lean))
	var at := pivot + Vector3(0.0, _squat, _shift)
	rider.transform = Transform3D(turn, at - turn * pivot)
	# Bars out of reach (bike pitched far forward): lean a little further over
	# them, at most ~20°, easing in and out. Never so far the belly meets the
	# bars: it stays at least 12 cm behind them.
	var want_reach := 0.35 if _grip_overreach() > 0.0 else 0.0
	_reach = move_toward(_reach, want_reach, 1.0 * delta)
	var belly := bike.transform.affine_inverse() * (rider.transform * BELLY)
	var bars_z := HEAD.z + GRIP.z
	var crowding := belly.z - (bars_z - 0.12)
	if crowding > 0.0:
		_reach = maxf(0.0, _reach - crowding * 3.0)
		_shift -= crowding

## How far the grips are beyond the arms' reach, model units (0 if within).
func _grip_overreach() -> float:
	var to_rider := rider.transform.affine_inverse() * bike.transform
	var worst := 0.0
	for left in [true, false]:
		var side := 1.0 if left else -1.0
		var sh: Vector3 = Ragdoll.POSE[Ragdoll.SHOULDER_L if left else Ragdoll.SHOULDER_R]
		var el: Vector3 = Ragdoll.POSE[Ragdoll.ELBOW_L if left else Ragdoll.ELBOW_R]
		var ha: Vector3 = Ragdoll.POSE[Ragdoll.HAND_L if left else Ragdoll.HAND_R]
		var reach := ((el - sh).length() + (ha - el).length()) * 0.94
		var grip := to_rider * (steering.transform * Vector3(GRIP.x * side, GRIP.y, GRIP.z))
		worst = maxf(worst, (grip - sh).length() - reach)
	return worst

## Hands on the grips: two-bone IK from each shoulder, elbows out and back.
func _pose_arms() -> void:
	var to_rider := rider.transform.affine_inverse() * bike.transform
	var side_axis: Vector3 = Ragdoll.POSE[Ragdoll.SHOULDER_L] - Ragdoll.POSE[Ragdoll.SHOULDER_R]
	for part in _parts:
		var upper: bool = part.a == Ragdoll.SHOULDER_L or part.a == Ragdoll.SHOULDER_R
		var fore: bool = part.a == Ragdoll.ELBOW_L or part.a == Ragdoll.ELBOW_R
		if not upper and not fore: continue
		var left: bool = part.a == Ragdoll.SHOULDER_L or part.a == Ragdoll.ELBOW_L
		var side := 1.0 if left else -1.0
		var sh: Vector3 = Ragdoll.POSE[Ragdoll.SHOULDER_L if left else Ragdoll.SHOULDER_R]
		var el: Vector3 = Ragdoll.POSE[Ragdoll.ELBOW_L if left else Ragdoll.ELBOW_R]
		var ha: Vector3 = Ragdoll.POSE[Ragdoll.HAND_L if left else Ragdoll.HAND_R]
		var l1 := (el - sh).length()
		var l2 := (ha - el).length()
		var grip := to_rider * (steering.transform * Vector3(GRIP.x * side, GRIP.y, GRIP.z))
		var to := grip - sh
		var dist := clampf(to.length(), 0.05, l1 + l2 - 0.005)
		var dir := to.normalized()
		var reach := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
		var rise := sqrt(maxf(0.0, l1 * l1 - reach * reach))
		var pole := Vector3(side, 0.35, -0.5).normalized()
		var bend := (pole - dir * pole.dot(dir)).normalized()
		var elbow := sh + dir * reach + bend * rise
		var hand := sh + dir * dist
		if upper: part.node.transform = _joint_frame(sh, elbow, side_axis) * part.rest
		else: part.node.transform = _joint_frame(elbow, hand, side_axis) * part.rest

## The rider is a ragdoll: every body part follows its two joints. The bike
## tumbles on its own and settles on its side.
func _pose_crash(b: Bike, c: Course, delta: float) -> void:
	var rag: Ragdoll = b.rider_body
	var bb: Tumble = b.bike_body
	_bike_basis = (_bike_basis * Basis.from_euler(bb.spin * delta)).orthonormalized()
	if bb.grounded: _bike_basis = _lie_down(_bike_basis, Vector3.UP, delta * 6.0)
	# The root follows the bike's slide and turns with it; undo that turn so
	# the tumble keeps its own heading.
	var turn := Basis(Vector3.UP, _crash_yaw - rotation.y)
	body.basis = turn * _bike_basis * Basis.from_scale(Vector3.ONE * SCALE)
	_keep_bike_above_ground(b, c)
	var w: Array[Vector3] = []
	for q in rag.pts: w.append(c.world(q.x, q.z, q.y))
	var side := w[Ragdoll.SHOULDER_L] - w[Ragdoll.SHOULDER_R]
	var scale := Transform3D(Basis.from_scale(Vector3.ONE * SCALE), Vector3.ZERO)
	for part in _parts:
		part.node.global_transform = _joint_frame(w[part.a], w[part.b], side) * scale * part.rest
	for leg in _legs:
		var left: bool = leg.side > 0.0
		var hip := w[Ragdoll.HIP_L if left else Ragdoll.HIP_R]
		var knee := w[Ragdoll.KNEE_L if left else Ragdoll.KNEE_R]
		var ankle := w[Ragdoll.FOOT_L if left else Ragdoll.FOOT_R]
		_stretch_world(leg.thigh, hip, knee)
		_stretch_world(leg.shin, knee, ankle)
		var rest_up: Vector3 = Ragdoll.POSE[Ragdoll.KNEE_L] - Ragdoll.POSE[Ragdoll.FOOT_L]
		var rest := _joint_frame(Vector3(0, 0.08, 0), Vector3(0, 0.08, 0) + rest_up, Vector3.RIGHT).affine_inverse()
		leg.shoe.global_transform = _joint_frame(ankle, knee, side) * scale * rest
	# A little blood where you hit the ground hard.
	while _splats_seen < rag.splats.size():
		var splat: Dictionary = rag.splats[_splats_seen]
		_splats_seen += 1
		_splat(c, splat.at, splat.size)

## The tumbling bike is one ball to the physics, but its wheels and bars
## reach well beyond it. Lift it so no part of it ends up under the ground.
const BIKE_EXTENTS := [
	Vector3(0, 0, WHEELBASE * 0.5), Vector3(0, 0, -WHEELBASE * 0.5),
	Vector3(0, WHEEL * 2.0, WHEELBASE * 0.5), Vector3(0, WHEEL * 2.0, -WHEELBASE * 0.5),
	Vector3(0, WHEEL, WHEELBASE * 0.5 + WHEEL), Vector3(0, WHEEL, -WHEELBASE * 0.5 - WHEEL),
	Vector3(0.34, 0.96, 0.3), Vector3(-0.34, 0.96, 0.3), Vector3(0, 0.66, -0.2),
	Vector3(0.2, WHEEL, WHEELBASE * 0.5), Vector3(-0.2, WHEEL, -WHEELBASE * 0.5),
]

func _keep_bike_above_ground(b: Bike, c: Course) -> void:
	var xf := body.global_transform
	var root := global_position
	var fwd := c.forward(b.s)
	var right := c.right(b.s)
	var lift := 0.0
	for q in BIKE_EXTENTS:
		var at: Vector3 = xf * q
		var off := at - root
		var ground := c.height(b.s + off.dot(fwd), b.d + off.dot(right))
		lift = maxf(lift, ground + 0.03 - at.y)
	position.y += lift

func _stretch_world(node: Node3D, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.normalized().y) < 0.9 else Vector3.RIGHT)
	node.global_transform = Transform3D(basis * Basis.from_scale(Vector3(SCALE, SCALE, dir.length())), from)

## A dark red splash on the ground, flat on the slope, with a few drops
## around it, plus a spray of droplets. It stays for the round.
func _splat(c: Course, at: Vector3, size: float) -> void:
	var g := c.gradient(at.x, at.z)
	var n := (c.forward(at.x) * -g.x + Vector3.UP + c.right(at.x) * -g.y).normalized()
	var x := n.cross(c.forward(at.x)).normalized()
	var lp := LowPoly.new()
	var rim: Array[Vector3] = []
	var k := 9
	for i in k:
		var a := TAU * i / k
		var r := size * _rng.randf_range(0.45, 0.95)
		rim.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i in k:
		lp.tri(Vector3.ZERO, rim[(i + 1) % k], rim[i], BLOOD.darkened(_rng.randf_range(0.0, 0.25)))
	for i in 4:
		var a := _rng.randf() * TAU
		var o := Vector3(cos(a), 0.0, sin(a)) * size * _rng.randf_range(1.0, 1.8)
		var r := size * _rng.randf_range(0.08, 0.18)
		lp.tri(o + Vector3(r, 0, 0), o + Vector3(-r * 0.5, 0, -r), o + Vector3(-r * 0.5, 0, r), BLOOD)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_transform = Transform3D(Basis(x, n, x.cross(n)), c.world(at.x, at.z, at.y) + n * 0.04)
	blood.global_position = c.world(at.x, at.z, at.y) + n * 0.3
	blood.restart()

## Turn a body so its `up` axis lies flat, along whichever way it is already falling.
static func _lie_down(basis: Basis, up: Vector3, rate: float) -> Basis:
	var u := basis * up
	var flat := Vector3(u.x, 0.0, u.z)
	if flat.length() < 0.05: flat = basis.z
	flat = Vector3(flat.x, 0.0, flat.z).normalized()
	var q := Quaternion(u.normalized(), flat)
	return (Basis(Quaternion.IDENTITY.slerp(q, minf(1.0, rate))) * basis).orthonormalized()
