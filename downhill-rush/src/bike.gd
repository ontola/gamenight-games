class_name Bike
extends RefCounted
## Rider and bike physics in track space. Pure data plus a static step, so the
## course generator can fly test riders over every jump before anyone rides it.

const G := 9.81
const RIDER_RADIUS := 0.35
const CRASH_TIME := 1.8
const INVULNERABLE := 1.3
const GRIP := 6.5              ## Sideways grip on dirt, m/s². Corner faster and you skid.
const RADIUS := 0.45           ## Each bike is two of these circles, front and back.
const HALF_LENGTH := 0.65

var s := 0.0
var d := 0.0
var y := 0.0
var v := 0.0            ## Speed along the heading (horizontal), m/s.
var vy := 0.0
var psi := 0.0          ## Heading relative to the track direction.
var pitch := 0.0        ## Bike pitch, radians, nose up positive.
var lean := 0.0         ## Visual lean into turns.
var grounded := true
var crashed := false
var crash_t := 0.0
var invulnerable := 0.0
var hard_landing := false   ## This step's landing was rough.
var landed := false         ## This step touched down after air time.
var launched := false       ## This step left the ground.
var air_time := 0.0
var wobble := 0.0
var crashes := 0
var crash_spin := Vector3.ZERO
var skid := 0.0         ## How hard the tyres are sliding this step, 0..1.
var skid_time := 0.0
var crash_reason := ""

func place(c: Course, p_s: float, p_d: float, p_v: float = 0.0) -> void:
	s = p_s
	d = p_d
	v = p_v
	vy = 0.0
	psi = 0.0
	y = c.height(s, d)
	vy = v * c.gradient(s, d).x
	grounded = true
	crashed = false

## `input`: steer (-1..1, right positive), pedal (0..1), brake (0..1),
## hop (bool, pressed this step), pitch (-1..1, nose up positive).
static func step(b: Bike, c: Course, input: Dictionary, dt: float) -> void:
	b.hard_landing = false
	b.landed = false
	b.launched = false
	b.invulnerable = maxf(0.0, b.invulnerable - dt)
	b.wobble = maxf(0.0, b.wobble - dt)
	if b.crashed:
		_step_crashed(b, c, dt)
		return
	var steer: float = clampf(input.get("steer", 0.0), -1.0, 1.0)
	var pedal: float = clampf(input.get("pedal", 0.0), 0.0, 1.0)
	var brake: float = clampf(input.get("brake", 0.0), 0.0, 1.0)
	if b.wobble > 0.0:
		steer += sin(b.wobble * 23.0) * 0.5
		pedal = 0.0
	var k := c.curvature(b.s)
	var path_scale := 1.0 / maxf(0.3, 1.0 - k * b.d)
	var wet := false
	var face := 0.0
	if b.grounded:
		var grad := c.gradient(b.s, b.d)
		var ground_grip := c.grip(b.s, b.d, grad.length())
		wet = ground_grip < 0.58 and c.in_water(b.s, b.d)
		var along := grad.x * cos(b.psi) + grad.y * sin(b.psi)
		var across := -grad.x * sin(b.psi) + grad.y * cos(b.psi)
		face = along
		var acc := -G * along / sqrt(1.0 + along * along)
		acc -= 0.12 + (6.0 if wet else 0.0)
		acc -= 0.0042 * b.v * b.v
		acc += pedal * 3.4 * clampf((12.5 - b.v) / 5.0, 0.0, 1.0)
		acc -= brake * 8.0 * (0.4 + 0.6 * ground_grip)
		b.v = maxf(0.0, b.v + acc * dt)
		var rate := minf(2.3, 15.0 / (b.v + 4.0)) * (1.25 if brake > 0.3 else 1.0)
		# Grip limits how hard you can turn at speed; braking hard eats into it.
		# Ask for more and the tyres slide: you scrub speed and run wide.
		var grip := GRIP * ground_grip * (1.0 - 0.35 * brake) / maxf(b.v, 1.0)
		var yaw := steer * rate
		b.skid = 0.0
		if absf(yaw) > grip:
			b.skid = clampf((absf(yaw) - grip) / grip, 0.0, 1.0)
			b.v = maxf(0.0, b.v - b.skid * 5.0 * dt)
			yaw = signf(yaw) * grip
		# Hold a big slide too long and the bike washes out from under you.
		b.skid_time = b.skid_time + dt if b.skid > 0.85 and b.v > 6.0 else maxf(0.0, b.skid_time - dt * 2.0)
		if b.skid_time > 0.6 and b.invulnerable <= 0.0:
			b.skid_time = 0.0
			_crash(b, "washout")
			return
		b.psi += yaw * dt
		# Side slopes pull you down the fall line, so every roll and hollow
		# needs a bit of counter-steer.
		b.d -= across * 1.4 * dt
		b.pitch = lerpf(b.pitch, atan(along), minf(1.0, dt * 18.0))
		b.lean = lerpf(b.lean, steer * clampf(b.v / 10.0, 0.0, 1.0) * 0.55, minf(1.0, dt * 8.0))
	else:
		b.air_time += dt
		b.vy -= G * dt
		b.v = maxf(0.0, b.v - 0.003 * b.v * b.v * dt)
		b.psi += steer * 0.9 * dt
		var flight := atan2(b.vy, maxf(b.v, 0.5))
		b.pitch = lerpf(b.pitch, flight, minf(1.0, dt * 2.2))
		b.pitch += float(input.get("pitch", 0.0)) * 2.6 * dt
		b.lean = lerpf(b.lean, steer * 0.3, minf(1.0, dt * 4.0))
	# The track turns underneath a rider who keeps their heading.
	b.psi -= k * b.v * cos(b.psi) * path_scale * dt
	b.psi = clampf(b.psi, -1.45, 1.45)
	b.s += b.v * cos(b.psi) * path_scale * dt
	b.d += b.v * sin(b.psi) * dt
	var limit := Course.CORRIDOR + 9.0
	if absf(b.d) > limit:
		b.d = signf(b.d) * limit
		b.psi *= 0.5
		b.v *= 0.97
	var ground := c.height(b.s, b.d)
	if b.grounded:
		var follow := (ground - b.y) / dt
		var free_y := b.y + (b.vy - G * dt) * dt
		if input.get("hop", false):
			b.vy = maxf(b.vy, 0.0) * 0.6 + 4.6 + maxf(b.vy, 0.0) * 0.4
			b.y += b.vy * dt
			b.grounded = false
			b.launched = true
			b.air_time = 0.0
		elif free_y > ground + 0.01 and follow < b.vy - G * dt:
			# The ground drops away faster than gravity can follow: airborne.
			b.vy -= G * dt
			b.y = free_y
			b.grounded = false
			b.launched = true
			b.air_time = 0.0
		elif face > 0.85 and b.v > 5.0 and b.invulnerable <= 0.0:
			# Rode straight into a face (cased a jump).
			_crash(b, "face")
			return
		else:
			b.y = ground
			b.vy = follow
	else:
		b.y += b.vy * dt
		if b.y <= ground:
			_land(b, c, ground)
			if b.crashed: return
	_collide_obstacles(b, c)

static func _land(b: Bike, c: Course, ground: float) -> void:
	var grad := c.gradient(b.s, b.d)
	var along := grad.x * cos(b.psi) + grad.y * sin(b.psi)
	var slope := atan(along)
	var path := atan2(b.vy, maxf(b.v, 0.1))
	var speed := sqrt(b.v * b.v + b.vy * b.vy)
	var impact := speed * sin(slope - path)
	var mismatch := absf(b.pitch - slope)
	b.y = ground
	b.grounded = true
	b.landed = true
	if (impact > 8.0 or mismatch > 1.05) and b.invulnerable <= 0.0:
		_crash(b, "landing")
		return
	b.v = speed * cos(slope - path)
	if impact > 5.2 or mismatch > 0.7:
		b.hard_landing = true
		b.v *= 0.55
		b.wobble = 0.6
	b.vy = b.v * along
	b.pitch = slope

static func _collide_obstacles(b: Bike, c: Course) -> void:
	if b.invulnerable > 0.0: return
	for o in c.obstacles_near(b.s):
		var ds: float = o.s - b.s
		var dd: float = o.d - b.d
		var r: float = o.r + RIDER_RADIUS
		if ds * ds + dd * dd > r * r: continue
		if b.y - c.height(o.s, o.d) > o.h: continue
		# How hard we're riding into it decides between a bump and a crash.
		var dist := sqrt(ds * ds + dd * dd)
		var n := Vector2(ds, dd) / maxf(dist, 0.001)
		var closing := Vector2(cos(b.psi), sin(b.psi)).dot(n) * b.v
		if closing > 5.5:
			_crash(b, "obstacle")
			return
		# Slower than that: push clear and slide round it.
		b.s -= n.x * (r - dist)
		b.d -= n.y * (r - dist)
		var vel := Vector2(cos(b.psi), sin(b.psi)) * b.v
		vel -= n * maxf(0.0, vel.dot(n))
		var away := -1.0 if b.d < o.d else 1.0
		var tangent := Vector2(-n.y, n.x)
		if tangent.y * away < 0.0: tangent = -tangent
		vel += tangent * 1.2
		b.v = vel.length() * 0.85
		b.psi = clampf(atan2(vel.y, maxf(vel.x, 0.05)), -1.45, 1.45)
		b.wobble = maxf(b.wobble, 0.3)

static func _crash(b: Bike, reason := "hit") -> void:
	b.crash_reason = reason
	b.crashed = true
	b.crash_t = CRASH_TIME
	b.crashes += 1
	b.grounded = true
	b.vy = 0.0
	b.v = minf(b.v, 9.0)
	b.crash_spin = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))

static func _step_crashed(b: Bike, c: Course, dt: float) -> void:
	b.crash_t -= dt
	b.v = move_toward(b.v, 0.0, 10.0 * dt)
	b.s += b.v * cos(b.psi) * dt
	b.d += b.v * sin(b.psi) * dt
	b.y = c.height(b.s, b.d)
	if b.crash_t > 0.0: return
	# Back on the bike where you landed, clear of rocks and trees.
	var here := clampf(b.d, -Course.CORRIDOR + 1.0, Course.CORRIDOR - 1.0)
	var best := here
	for candidate in [here, here - 1.5, here + 1.5, here - 3.0, here + 3.0]:
		var clear := true
		for o in c.obstacles_near(b.s):
			if Vector2(o.s - b.s, o.d - candidate).length() < o.r + 1.0: clear = false
		if clear:
			best = candidate
			break
	b.d = best
	b.psi = 0.0
	b.v = 3.0
	b.vy = 0.0
	b.y = c.height(b.s, b.d)
	b.crashed = false
	b.grounded = true
	b.pitch = 0.0
	b.invulnerable = INVULNERABLE
