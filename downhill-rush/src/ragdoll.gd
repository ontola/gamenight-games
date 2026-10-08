class_name Ragdoll
extends Tumble
## The thrown rider as a ragdoll: fifteen points (pelvis, chest, head,
## shoulders, elbows, hands, hips, knees, feet) held together by sticks of
## fixed length, integrated with Verlet. Each point falls, hits the ground
## along its normal, slides with Coulomb friction and bounces off trees and
## rocks; the sticks make the limbs flop the way a body does.
##
## Track space like Tumble: (s, y, d). `p`, `v`, `grounded`, `rest` and `hit`
## describe the whole body so Bike can treat it as one.

enum { PELVIS, CHEST, HEAD, SHOULDER_L, SHOULDER_R, ELBOW_L, ELBOW_R, HAND_L, HAND_R,
	HIP_L, HIP_R, KNEE_L, KNEE_R, FOOT_L, FOOT_R }

## The rest pose in rider model units (x left, y up, z forward), stood on the
## pedals. RiderView builds its body parts around the same points.
const POSE := [
	Vector3(0, 0.92, -0.2), Vector3(0, 1.3, 0.06), Vector3(0, 1.5, 0.12),
	Vector3(0.17, 1.24, 0.05), Vector3(-0.17, 1.24, 0.05),
	Vector3(0.33, 1.06, 0.17), Vector3(-0.33, 1.06, 0.17),
	Vector3(0.31, 0.96, 0.41), Vector3(-0.31, 0.96, 0.41),
	Vector3(0.1, 0.92, -0.2), Vector3(-0.1, 0.92, -0.2),
	Vector3(0.16, 0.66, 0.1), Vector3(-0.16, 0.66, 0.1),
	Vector3(0.13, 0.4, -0.03), Vector3(-0.13, 0.4, -0.03),
]
const RADII := [0.12, 0.13, 0.13, 0.08, 0.08, 0.06, 0.06, 0.05, 0.05, 0.08, 0.08, 0.07, 0.07, 0.07, 0.07]
## Torso and head form a rigid frame; arms and legs hang off it.
const STICKS := [
	[PELVIS, CHEST], [CHEST, SHOULDER_L], [CHEST, SHOULDER_R], [SHOULDER_L, SHOULDER_R],
	[PELVIS, HIP_L], [PELVIS, HIP_R], [HIP_L, HIP_R], [SHOULDER_L, HIP_L], [SHOULDER_R, HIP_R],
	[SHOULDER_L, HIP_R], [SHOULDER_R, HIP_L], [PELVIS, SHOULDER_L], [PELVIS, SHOULDER_R],
	[CHEST, HIP_L], [CHEST, HIP_R],
	[CHEST, HEAD], [SHOULDER_L, HEAD], [SHOULDER_R, HEAD],
	[SHOULDER_L, ELBOW_L], [ELBOW_L, HAND_L], [SHOULDER_R, ELBOW_R], [ELBOW_R, HAND_R],
	[HIP_L, KNEE_L], [KNEE_L, FOOT_L], [HIP_R, KNEE_R], [KNEE_R, FOOT_R],
]
## Elbows and knees can't fold flat: hands and feet keep this share of the
## straight-limb reach.
const FOLD := [[SHOULDER_L, HAND_L], [SHOULDER_R, HAND_R], [HIP_L, FOOT_L], [HIP_R, FOOT_R]]
const ITERATIONS := 8
const SPLAT_SPEED := 3.5   ## A point hitting harder than this bleeds a little.

var pts: Array[Vector3] = []
var _prev: Array[Vector3] = []
var _rad: Array[float] = []
var _len: Array[float] = []
var _fold: Array[float] = []
var splats: Array[Dictionary] = []   ## {at: track position, size}, newest last.
var _splat_wait := 0.0
var _touching := 0   ## Points on the ground after the last step.
var _ground: Array[float] = []     ## Ground under each point, sampled once per step.
var _normal: Array[Vector3] = []   ## Its normal, sampled when the point first touches.

## `base` is the bike's ground point, `psi` its heading, `vel` the speed the
## rider is thrown with and `flip` how fast they pitch over the bars.
func _init(base: Vector3, psi: float, pitch: float, vel: Vector3, flip: float, scale: float) -> void:
	super(base, vel, 0.55, 0.15, 0.75)
	var fwd := Vector3(cos(psi), 0.0, sin(psi))
	var left := Vector3(sin(psi), 0.0, -cos(psi))
	var tilt := Basis(left, -pitch)
	var dt := 1.0 / 120.0
	var pelvis: Vector3 = POSE[PELVIS]
	for i in POSE.size():
		var q: Vector3 = POSE[i]
		var at := base + tilt * (fwd * q.z + Vector3.UP * q.y + left * q.x) * scale
		# Pitching over the bars: the higher up, the faster forward.
		var r := (q - pelvis) * scale
		var spin := fwd * r.y * flip - Vector3.UP * r.z * flip
		var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.6), randf_range(-0.6, 0.6))
		pts.append(at)
		_prev.append(at - (vel + spin + jitter) * dt)
		_rad.append(RADII[i] * scale)
	for st in STICKS:
		_len.append((POSE[st[0]] - POSE[st[1]]).length() * scale)
	for f in FOLD:
		_fold.append((POSE[f[0]] - POSE[f[1]]).length() * scale * 0.55)
	_update_body(dt)

func step(c: Course, dt: float) -> void:
	hit = 0.0
	_splat_wait = maxf(0.0, _splat_wait - dt)
	var gravity := Vector3(0.0, -Bike.G * dt * dt, 0.0)
	var wet := c.water_depth(pts[PELVIS].x, pts[PELVIS].z) > 0.25
	for i in pts.size():
		var cur := pts[i]
		var vel := (cur - _prev[i]) * (0.95 if wet else 0.998)
		_prev[i] = cur
		pts[i] = cur + vel + gravity
	# Sampling the mountain is the costly part, so do it once per point per step.
	_ground.resize(pts.size())
	_normal.resize(pts.size())
	for i in pts.size():
		_ground[i] = c.height(pts[i].x, pts[i].z)
		_normal[i] = Vector3.ZERO
	for k in ITERATIONS:
		_constrain()
		if k == ITERATIONS / 2 - 1 or k == ITERATIONS - 1: _collide(c, dt, k == ITERATIONS - 1)
	_update_body(dt)

func _constrain() -> void:
	for k in STICKS.size():
		var a: int = STICKS[k][0]
		var b: int = STICKS[k][1]
		var delta := pts[b] - pts[a]
		var dist := maxf(delta.length(), 0.0001)
		var fix := delta * (0.5 * (dist - _len[k]) / dist)
		pts[a] += fix
		pts[b] -= fix
	for k in FOLD.size():
		var a: int = FOLD[k][0]
		var b: int = FOLD[k][1]
		var delta := pts[b] - pts[a]
		var dist := maxf(delta.length(), 0.0001)
		if dist >= _fold[k]: continue
		var fix := delta * (0.5 * (dist - _fold[k]) / dist)
		pts[a] += fix
		pts[b] -= fix

## Ground and obstacles. Friction takes off as much sideways motion as the
## push out of the ground allows (Coulomb), so a body slides on steep ground
## and stops on gentle ground.
func _collide(c: Course, dt: float, final: bool) -> void:
	var near := c.obstacles_near(pts[PELVIS].x)
	if final: _touching = 0
	for i in pts.size():
		var q := pts[i]
		var ground := _ground[i] + _rad[i]
		if q.y < ground:
			if _normal[i] == Vector3.ZERO:
				var g := c.gradient(q.x, q.z)
				_normal[i] = Vector3(-g.x, 1.0, -g.y).normalized()
			var n := _normal[i]
			var push := (ground - q.y) * n.y
			var moved := q - _prev[i]
			var into := -moved.dot(n)
			q += n * push
			var slide := moved + n * into
			var keep := maxf(0.0, slide.length() - mu * (push + maxf(0.0, into))) / maxf(slide.length(), 0.0001)
			# Bounce a little of the impact back; the rest is soaked up.
			var back := n * (maxf(0.0, into) * bounce)
			_prev[i] = q - slide * keep - back
			if final:
				_touching += 1
				var speed := maxf(0.0, into) / dt
				hit = maxf(hit, speed)
				if speed > SPLAT_SPEED and _splat_wait <= 0.0 and splats.size() < 8:
					splats.append({"at": Vector3(q.x, ground - _rad[i], q.z), "size": clampf(speed / 9.0, 0.35, 1.0)})
					_splat_wait = 0.15
		for o in near:
			var gap := Vector2(q.x - o.s, q.z - o.d)
			var reach: float = o.r + _rad[i]
			if gap.length_squared() > reach * reach: continue
			if q.y - _ground[i] > o.h + _rad[i]: continue
			var n := gap / maxf(gap.length(), 0.0001)
			q.x = o.s + n.x * reach
			q.z = o.d + n.y * reach
			if final:
				var speed := -Vector2(q.x - _prev[i].x, q.z - _prev[i].z).dot(n) / dt
				hit = maxf(hit, speed)
		pts[i] = q

func _update_body(dt: float) -> void:
	var sum := Vector3.ZERO
	var before := Vector3.ZERO
	for i in pts.size():
		sum += pts[i]
		before += _prev[i]
	p = sum / pts.size()
	v = (sum - before) / pts.size() / dt
	grounded = _touching >= 3
	rest = rest + dt if grounded and v.length() < 0.6 else 0.0
