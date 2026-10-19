class_name Bike
extends RefCounted
## Rider and bike physics in track space. Pure data plus a static step, so the
## course generator can fly test riders over every jump before anyone rides it.

const G := 9.81
const RIDER_RADIUS := 0.35
const CRASH_MIN := 1.1        ## A crash lasts at least this long...
const CRASH_MAX := 2.8        ## ...and gives up waiting for you to stop sliding after this.
const INVULNERABLE := 1.3
const GRIP := 18.0             ## Sideways grip on dirt, m/s². Corner faster and you skid.
const RADIUS := 0.45           ## Each bike is two of these circles, front and back.
const HALF_LENGTH := 0.65
const AXLE := 0.6             ## Front axle height above the ground, m.
const WHEEL_REACH := 0.35     ## How far in front of the front axle the tyre reaches.
const BRAKE_LOCK := 0.8       ## Firm trigger pressure locks wheel rotation.

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
var crash_t := 0.0      ## Time since the crash began.
var rider_body: Tumble  ## In a crash: the rider, thrown clear.
var bike_body: Tumble   ## In a crash: the bike, skidding on its own.
var invulnerable := 0.0
var hard_landing := false   ## This step's landing was rough.
var landed := false         ## This step touched down after air time.
var launched := false       ## This step left the ground.
var air_time := 0.0
var wobble := 0.0
var shove := Vector2.ZERO  ## Sideways drift from a hit by another rider, m/s (s, d).
var bumped := 0.0       ## Cooldown after a rider hit, so one contact costs once.
var crashes := 0
var skid := 0.0         ## How hard the tyres are sliding this step, 0..1.
var skid_time := 0.0
var brake_locked := false
var placement_id := 0  ## Separates contact trails across respawns.
var crash_reason := ""
var yaw := 0.0          ## Bike twisted away from the direction of travel (in the air).
var severity := 0.0     ## How bad the last landing was; above 1 is a crash.
var pinned := 0.0       ## How long we've been stuck against rocks or trees.
var touching := false   ## Leaning on an obstacle this step.
var steer_angle := 0.0  ## Handlebar angle, radians, right positive (for the bars).
var pedaling := 0.0     ## How hard the rider is pedalling, for the legs.
var _stuck_s := 0.0     ## Last position with meaningful movement in any direction.
var _stuck_d := 0.0
var _stuck_t := 0.0

func place(c: Course, p_s: float, p_d: float, p_v: float = 0.0) -> void:
	placement_id += 1
	s = p_s
	d = p_d
	_stuck_s = s
	_stuck_d = d
	_stuck_t = 0.0
	pinned = 0.0
	shove = Vector2.ZERO
	bumped = 0.0
	v = p_v
	vy = 0.0
	psi = 0.0
	y = c.height(s, d)
	vy = v * c.gradient(s, d).x
	grounded = true
	crashed = false
	brake_locked = false
	skid = 0.0

## `input`: steer (-1..1, right positive), pedal (0..1), brake (0..1),
## hop (bool, pressed this step). In the air brake lifts the nose.
## Steering goes through the front wheel, like a real bike: turn the bars by
## an angle and the bike follows an arc of radius wheelbase / tan(angle), so
## the turn rate grows with speed and a bike at a standstill can't spin on
## the spot. Full lock is wide at walking pace and narrows as you go faster.
const WHEELBASE_M := 2.15
static func steer_lock(v: float) -> float:
	return lerpf(0.9, 0.4, clampf(v / 12.0, 0.0, 1.0))

## How fast full lock turns the bike at speed `v`, rad/s.
static func turn_rate(v: float) -> float:
	return v * tan(steer_lock(v)) / WHEELBASE_M

## Course.right = (-cos(theta), 0, sin(theta)), so world_s = (1 + k*d)
## times course.forward. Convert world metres to distance along the centreline.
static func path_scale(c: Course, s: float, d: float) -> float:
	return 1.0 / maxf(0.3, 1.0 + c.curvature(s) * d)

static func step(b: Bike, c: Course, input: Dictionary, dt: float) -> void:
	b.hard_landing = false
	b.landed = false
	b.launched = false
	b.skid = 0.0
	b.brake_locked = false
	b.invulnerable = maxf(0.0, b.invulnerable - dt)
	b.wobble = maxf(0.0, b.wobble - dt)
	b.bumped = maxf(0.0, b.bumped - dt)
	if b.crashed:
		_step_crashed(b, c, dt)
		return
	var steer: float = clampf(input.get("steer", 0.0), -1.0, 1.0)
	var pedal: float = clampf(input.get("pedal", 0.0), 0.0, 1.0)
	var brake: float = clampf(input.get("brake", 0.0), 0.0, 1.0)
	b.pedaling = pedal
	b.brake_locked = brake >= BRAKE_LOCK
	if b.brake_locked:
		pedal = 0.0
		b.pedaling = 0.0
	if b.wobble > 0.0:
		steer += sin(b.wobble * 23.0) * 0.5
		pedal = 0.0
	var k := c.curvature(b.s)
	var scale := path_scale(c, b.s, b.d)
	var wet := false
	var face := 0.0
	if b.grounded:
		var grad := riding_gradient(b, c)
		grad.x *= scale
		var ground_grip := c.grip(b.s, b.d, grad.length())
		wet = ground_grip < 0.58 and c.in_water(b.s, b.d)
		var along := grad.x * cos(b.psi) + grad.y * sin(b.psi)
		var across := -grad.x * sin(b.psi) + grad.y * cos(b.psi)
		face = along
		var acc := -G * along / sqrt(1.0 + along * along)
		acc -= 0.12 + (6.0 if wet else 0.0)
		acc -= 0.0042 * b.v * b.v
		acc += pedal * 9.0 * clampf((16.0 - b.v) / 6.0, 0.0, 1.0)
		# Locked rubber slides instead of rolling: strong longitudinal drag,
		# but less grip than a tyre braking just below its traction limit.
		acc -= brake * 18.0 * (0.4 + 0.6 * ground_grip) * (0.85 if b.brake_locked else 1.0)
		b.v = maxf(0.0, b.v + acc * dt)
		var rate := turn_rate(b.v) * (1.4 if brake > 0.3 else 1.0)
		# Grip limits how hard you can turn at speed; braking hard eats into it.
		# Ask for more and the tyres slide: you scrub speed and run wide.
		var grip := GRIP * ground_grip * (0.45 if b.brake_locked else 1.0 - 0.35 * brake) / maxf(b.v, 1.0)
		var yaw := steer * rate
		b.skid = 0.0
		if absf(yaw) > grip:
			b.skid = clampf((absf(yaw) - grip) / grip, 0.0, 1.0)
			b.v = maxf(0.0, b.v - b.skid * 5.0 * dt)
			yaw = signf(yaw) * grip
		if b.brake_locked: b.skid = maxf(b.skid, clampf(b.v / 2.0, 0.0, 1.0))
		b.psi += yaw * dt
		b.steer_angle = lerpf(b.steer_angle, steer * steer_lock(b.v), minf(1.0, dt * 14.0))
		# Side slopes pull you down the fall line, so every roll and hollow
		# needs a bit of counter-steer.
		b.d -= across * 1.4 * dt
		b.pitch = lerpf(b.pitch, atan(along), minf(1.0, dt * 18.0))
		b.lean = lerpf(b.lean, steer * clampf(b.v / 10.0, 0.0, 1.0) * 0.55, minf(1.0, dt * 8.0))
	else:
		b.air_time += dt
		b.vy -= G * dt
		b.v = maxf(0.0, b.v - 0.003 * b.v * b.v * dt)
		# In the air the spinning wheels and the rider keep the bike lined up
		# with where it's flying. Steering can only nudge it off line a little
		# (enough to correct a crooked take-off), and it lines up again by itself.
		# Full stick points it ~14° off line: enough to see and to come down
		# a little turned (see _land), never enough to land crooked.
		b.yaw = move_toward(b.yaw, steer * 0.25, 1.5 * dt)
		# The bars still turn with the stick, so you can see your input.
		b.steer_angle = lerpf(b.steer_angle, steer * steer_lock(b.v), minf(1.0, dt * 14.0))
		# Riders hold the bike nearer level than the arc they fly, ready for
		# the landing; the nose still drops on a long fall.
		var flight := atan2(b.vy, maxf(b.v, 0.5)) * 0.55
		b.pitch = lerpf(b.pitch, flight, minf(1.0, dt * 2.2))
		# Grabbing the brake in the air lifts the nose for a back-wheel landing.
		b.pitch += brake * 1.6 * dt
		b.lean = lerpf(b.lean, steer * 0.3, minf(1.0, dt * 4.0))
	# World heading is theta - psi: when the track turns underneath an
	# airborne rider, psi increases with theta to preserve their flight line.
	var ds := b.v * cos(b.psi) * scale * dt
	b.s += ds
	b.d += b.v * sin(b.psi) * dt
	b.psi += k * ds
	# A hit from another rider carries you sideways for a moment, without
	# turning the bike: the rider's weight moves, the wheels follow.
	if b.shove != Vector2.ZERO:
		b.s += b.shove.x * scale * dt
		b.d += b.shove.y * dt
		b.shove = b.shove.move_toward(Vector2.ZERO, 6.0 * dt)
	# The stick can point uphill too. Preserve a full heading, rather than
	# silently stopping the bars at 83 degrees from the downhill direction.
	b.psi = wrapf(b.psi, -PI, PI)
	var limit := Course.CORRIDOR + 9.0
	if absf(b.d) > limit:
		b.d = signf(b.d) * limit
		b.psi *= 0.5
		b.v *= 0.97
	var ground := riding_height(b, c, b.s, b.d)
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
		elif b.invulnerable <= 0.0 and c.water_depth(b.s, b.d) > 0.5:
			# Rode into the deep end.
			_crash(b, "splash")
			return
		elif face > 1.0 and face * b.v > 5.0 * c.crash_limit and b.invulnerable <= 0.0:
			# Rode into a bank steeper than 45°: the front wheel stops dead (cased a jump).
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
	b.touching = false
	_collide_obstacles(b, c, steer)
	if not b.grounded or b.crashed:
		b.skid = 0.0
	# Wedged in a pocket of rocks: hop off and walk the bike out.
	# Same when you've ground to a halt on a bank without braking.
	var stalled := b.grounded and b.v < 0.8 and brake < 0.1
	b.pinned = b.pinned + dt if (b.touching and b.v < 4.5) or stalled else maxf(0.0, b.pinned - dt * 2.0)
	# Rocking back and forth in a thicket without getting anywhere counts too.
	if Vector2(b.s - b._stuck_s, b.d - b._stuck_d).length() > 1.5 or (brake > 0.3 and b.v < 0.3):
		b._stuck_s = b.s
		b._stuck_d = b.d
		b._stuck_t = 0.0
	else:
		b._stuck_t += dt
	if (b.pinned > (1.0 if b.touching else 2.0) or b._stuck_t > 3.0) and b.invulnerable <= 0.0:
		# Truly stuck, or stopped dead: a bike can't stand up by itself, so
		# you topple over, and get going again on clear ground past whatever
		# held you.
		b.pinned = 0.0
		b._stuck_t = 0.0
		_crash(b, "stuck")

## How bad a touchdown is, 0 for perfect. Three things count, and they add
## up: how hard you hit the ground (speed into the slope), how far the bike's
## pitch is from the slope (nose first is far worse than back wheel first),
## and how crooked the bike is to where you're going. Above 1 you crash.
## A short hop off a bump you barely saw counts the angles for far less: only
## real jumps have to be landed well.
## How bad a touchdown is; above the course's crash limit you go down.
## What puts you down is the angle, not the bump: legs soak up the impact
## (only a truly huge one, ~16 m/s into the slope, is too much), but the bike
## has to meet the ground the way it's pointing. Nose first more than ~35°
## off the slope and the front wheel digs in and pitches you over; back wheel
## first is fine up to ~57°; land crooked and the tyres slide sideways, and
## past ~5 m/s of that they let go. Short hops off bumps you didn't see
## coming are mostly forgiven.
static func landing_severity(impact: float, pitch_error: float, yaw: float, speed: float, air_time: float = 1.0) -> float:
	var hit := maxf(0.0, impact) / 16.0
	var nose := (-pitch_error / 0.6) if pitch_error < 0.0 else (pitch_error / 1.0)
	var crooked := speed * sin(minf(absf(yaw), PI * 0.5)) / 5.0
	var hop := lerpf(0.5, 1.0, smoothstep(0.25, 0.6, air_time))
	return maxf(hit, maxf(nose, crooked) * hop)

static func _land(b: Bike, c: Course, ground: float) -> void:
	var grad := riding_gradient(b, c)
	grad.x *= path_scale(c, b.s, b.d)
	var along := grad.x * cos(b.psi) + grad.y * sin(b.psi)
	var slope := atan(along)
	var path := atan2(b.vy, maxf(b.v, 0.1))
	var speed := sqrt(b.v * b.v + b.vy * b.vy)
	var impact := speed * sin(slope - path)
	b.severity = landing_severity(impact, b.pitch - slope, b.yaw, speed, b.air_time)
	b.y = ground
	b.grounded = true
	b.landed = true
	if b.invulnerable <= 0.0 and b.severity > c.crash_limit:
		_crash(b, "landing")
		return
	# Project the incoming velocity onto the final contact direction. v is
	# HORIZONTAL speed: storing tangent speed here adds energy on every slope.
	var next_psi := wrapf(b.psi + b.yaw * 0.3, -PI, PI)
	var next_along := grad.x * cos(next_psi) + grad.y * sin(next_psi)
	b.v = maxf(0.0, (b.v * cos(next_psi - b.psi) + b.vy * next_along) / (1.0 + next_along * next_along))
	if b.severity > 0.6 * c.crash_limit:
		# Rough: you stay on, but it costs speed and you wobble.
		b.hard_landing = true
		b.v *= lerpf(0.8, 0.45, clampf((b.severity / c.crash_limit - 0.6) / 0.4, 0.0, 1.0))
		b.wobble = 0.6
	# Landing crooked turns you a little towards where the bike points.
	b.psi = next_psi
	b.yaw = 0.0
	b.vy = b.v * next_along
	b.pitch = atan(next_along)

## Rounded stones below axle height form part of the riding surface. The
## tyre radius rounds their shoulder; each axle samples it independently.
## Gravity, pedalling and the normal ground/air contact solve the climb,
## rather than injecting a jump impulse every time a rock is touched.
static func _rock_lift(c: Course, s: float, d: float, nearby = null) -> float:
	var lift := 0.0
	if nearby == null: nearby = c.obstacles_near(s)
	for o in nearby:
		if o.kind != "rock" or o.h >= AXLE * 1.1: continue
		var reach: float = o.r + WHEEL_REACH
		var q2 := Vector2(s - o.s, d - o.d).length_squared() / (reach * reach)
		if q2 >= 1.0: continue
		# A smooth rounded crown, tangent to the ground at its edge.
		var crown: float = (o.h + c.height(o.s, o.d) - c.height(s, d)) * (1.0 - q2) * (1.0 - q2)
		lift = maxf(lift, crown)
	return lift

static func riding_height(b: Bike, c: Course, s: float, d: float, nearby = null) -> float:
	if nearby == null: nearby = c.obstacles_near(s)
	var axle := Vector2(cos(b.psi), sin(b.psi)) * HALF_LENGTH
	var front := _rock_lift(c, s + axle.x, d + axle.y, nearby)
	var rear := _rock_lift(c, s - axle.x, d - axle.y, nearby)
	return c.height(s, d) + (front + rear) * 0.5

static func riding_gradient(b: Bike, c: Course) -> Vector2:
	var e := 0.08
	var nearby := c.obstacles_near(b.s)
	return Vector2(
		(riding_height(b, c, b.s + e, b.d, nearby) - riding_height(b, c, b.s - e, b.d, nearby)) / (2.0 * e),
		(riding_height(b, c, b.s, b.d + e, nearby) - riding_height(b, c, b.s, b.d - e, nearby)) / (2.0 * e))

static func _collide_obstacles(b: Bike, c: Course, steer := 0.0) -> void:
	if b.invulnerable > 0.0: return
	for o in c.obstacles_near(b.s):
		var ds: float = o.s - b.s
		var dd: float = o.d - b.d
		var r: float = o.r + RIDER_RADIUS
		if ds * ds + dd * dd > r * r: continue
		if b.y - c.height(o.s, o.d) > o.h: continue
		var dist := sqrt(ds * ds + dd * dd)
		var n := Vector2(ds, dd) / maxf(dist, 0.001)
		var heading := Vector2(cos(b.psi), sin(b.psi))
		# Anything lower than the front axle the wheel just rolls over.
		var small: bool = o.kind == "rock" and o.h < AXLE * 1.1
		# What throws you over the bars is the front wheel catching: hitting
		# something taller than the axle nearly head-on, so the wheel stops
		# dead while you keep going. Clip it at an angle and you glance off.
		var front := Vector2(b.s, b.d) + heading * HALF_LENGTH
		var to_front := Vector2(o.s, o.d) - front
		var catches: bool = not small and to_front.length() < o.r + WHEEL_REACH and heading.dot(to_front.normalized()) > cos(deg_to_rad(40.0))
		# Trees don't give: ride into a trunk at speed, from any angle or out
		# of the air, and you go down. Only a slow brush past one is let off.
		if o.kind == "tree":
			var into := heading.dot(n) * b.v
			if into > 2.5 * c.crash_limit or (b.v > 7.0 * c.crash_limit and into > 0.0):
				_crash(b, "obstacle")
				return
		if catches:
			var closing := heading.dot(to_front.normalized()) * b.v
			# A trunk stops the wheel at walking pace; a rounded boulder the
			# wheel can partly climb, the less the lower it is.
			var limit: float = (2.5 if o.kind == "tree" else lerpf(7.0, 2.5, clampf((o.h - AXLE) / 1.2, 0.0, 1.0))) * c.crash_limit
			if closing > limit:
				_crash(b, "obstacle")
				return
		if small:
			# Low rocks support the tyres through riding_height. Never turn
			# them into a wall on the frame after the front wheel lifts off.
			continue
		# Otherwise you scrape along it. A bike can't be turned by what it
		# touches, so the heading stays; you're pushed clear and lose the part
		# of your speed that went into it. Ride into it slowly and you just stop.
		b.touching = true
		b.s -= n.x * (r - dist)
		b.d -= n.y * (r - dist)
		var into := maxf(0.0, heading.dot(n)) * b.v
		b.v = maxf(0.0, b.v - into * 1.2)
		b.wobble = maxf(b.wobble, 0.3)

## Two riders touching: see Main._bump_riders.
static func collide(ba: Bike, bb: Bike) -> void:
	if absf(ba.y - bb.y) > 1.2: return
	if absf(ba.s - bb.s) > 3.0 or absf(ba.d - bb.d) > 3.0: return
	var ua := Vector2(cos(ba.psi), sin(ba.psi)) * HALF_LENGTH
	var ub := Vector2(cos(bb.psi), sin(bb.psi)) * HALF_LENGTH
	var pa := Vector2(ba.s, ba.d)
	var pb := Vector2(bb.s, bb.d)
	var best := INF
	var normal := Vector2.ZERO
	for sa in [-1.0, 1.0]:
		for sb in [-1.0, 1.0]:
			var delta: Vector2 = (pb + ub * sb) - (pa + ua * sa)
			var dist := delta.length()
			if dist < best:
				best = dist
				normal = delta / dist if dist > 0.001 else Vector2(0, 1)
	var overlap := RADIUS * 2.0 - best
	if overlap <= 0.0: return
	ba.s -= normal.x * overlap * 0.5; ba.d -= normal.y * overlap * 0.5
	bb.s += normal.x * overlap * 0.5; bb.d += normal.y * overlap * 0.5
	var va := Vector2(cos(ba.psi), sin(ba.psi)) * ba.v + ba.shove
	var vb := Vector2(cos(bb.psi), sin(bb.psi)) * bb.v + bb.shove
	var closing := (va - vb).dot(normal)
	# Bikes that touch always drift apart, so they can't hook into each other
	# and grind to a halt side by side.
	ba.shove -= normal * maxf(0.0, 1.2 + ba.shove.dot(normal))
	bb.shove += normal * maxf(0.0, 1.2 - bb.shove.dot(normal))
	if closing <= 0.0: return
	# The hit itself goes sideways, into both riders' balance, not into a
	# head-on stop. It costs once per contact.
	if ba.bumped > 0.0 and bb.bumped > 0.0: return
	# Half of the hit trades speed along each bike's heading (a rear-ender
	# slows you and speeds them up), the rest becomes sideways drift.
	var impulse := closing * 0.75
	ba.v = maxf(0.0, ba.v - impulse * 0.5 * normal.dot(Vector2(cos(ba.psi), sin(ba.psi))))
	bb.v = maxf(0.0, bb.v + impulse * 0.5 * normal.dot(Vector2(cos(bb.psi), sin(bb.psi))))
	ba.shove -= normal * impulse * 0.5
	bb.shove += normal * impulse * 0.5
	if closing > 1.0:
		knock(ba, closing, -normal)
		knock(bb, closing, normal)

## A hit from another rider: it knocks you off balance. You lose some speed,
## the bike lurches to the side you were hit towards and the bars wobble for a
## moment. A hit alone never puts you down. `hit` is the closing speed, m/s;
## `away` the direction you're pushed in (s, d).
static func knock(b: Bike, hit: float, away: Vector2) -> void:
	if b.crashed or b.invulnerable > 0.0: return
	b.bumped = 0.4
	b.wobble = maxf(b.wobble, clampf(0.25 + hit * 0.07, 0.25, 0.9))
	b.v *= 1.0 - clampf(hit * 0.035, 0.03, 0.25)
	var right := Vector2(-sin(b.psi), cos(b.psi))
	b.lean = clampf(b.lean + away.dot(right) * clampf(hit * 0.06, 0.08, 0.45), -0.7, 0.7)

## Rider and bike part ways. What happens next is physics: each is thrown
## with the speed it had, the rider over the bars if the bike stopped dead.
static func _crash(b: Bike, reason := "hit") -> void:
	b.brake_locked = false
	b.skid = 0.0
	b.crash_reason = reason
	b.crashed = true
	b.crash_t = 0.0
	b.crashes += 1
	var vel := Vector3(b.v * cos(b.psi), b.vy, b.v * sin(b.psi))
	var flat := Vector3(vel.x, 0.0, vel.z)
	var rider_vel := vel
	var bike_vel := vel
	match reason:
		"obstacle", "face":
			# The bike stops; you don't. Over the bars and up.
			rider_vel = vel * 0.95 + Vector3.UP * (1.5 + flat.length() * 0.2)
			bike_vel = -flat * 0.12 + Vector3.UP * 1.0
		"landing":
			rider_vel = vel * 0.9 + Vector3.UP * 0.8
			bike_vel = vel * 0.75 + Vector3.UP * 0.5
		"washout":
			# The wheels slide out sideways and you go down on your hip.
			var side := Vector3(-sin(b.psi), 0.0, cos(b.psi)) * signf(b.lean if absf(b.lean) > 0.01 else 1.0)
			rider_vel = flat * 0.9 + side * 1.5
			bike_vel = flat * 0.8 - side * 1.0
		"stuck":
			# Stopped dead: you just tip over to one side.
			var side := Vector3(-sin(b.psi), 0.0, cos(b.psi)) * (1.0 if randf() < 0.5 else -1.0)
			rider_vel = side * 1.3 + Vector3.UP * 0.4
			bike_vel = -side * 0.4
		"splash":
			rider_vel = vel * 0.4 + Vector3.UP * 1.0
			bike_vel = vel * 0.3
		_:
			rider_vel = vel * 0.85 + Vector3.UP * 1.2
			bike_vel = vel * 0.7
	# The rider goes limp: a ragdoll, flipping over the bars faster the
	# harder the bike stopped.
	var flip := (flat - Vector3(bike_vel.x, 0.0, bike_vel.z)).length() * 0.35
	b.rider_body = Ragdoll.new(Vector3(b.s, b.y, b.d), b.psi, b.pitch, rider_vel, flip, RiderView.SCALE)
	b.bike_body = Tumble.new(Vector3(b.s, b.y + 0.45, b.d), bike_vel, 0.45, 0.35, 0.55)
	b.bike_body.spin = Vector3(randf_range(-3.0, 3.0), randf_range(-4.0, 4.0) + b.yaw * 3.0, randf_range(-6.0, 6.0))
	b.grounded = true
	b.vy = 0.0
	b.yaw = 0.0

static func _step_crashed(b: Bike, c: Course, dt: float) -> void:
	b.crash_t += dt
	b.rider_body.step(c, dt)
	b.bike_body.step(c, dt)
	# The bike is what's left on the course: it carries the rider's place in
	# the race until they're back on it.
	var bp := b.bike_body.p
	var bv := b.bike_body.v
	b.s = bp.x
	b.d = clampf(bp.z, -Course.CORRIDOR - 9.0, Course.CORRIDOR + 9.0)
	b.bike_body.p.z = b.d
	b.y = bp.y - b.bike_body.radius
	b.v = Vector2(bv.x, bv.z).length()
	if b.v > 0.3: b.psi = clampf(atan2(bv.z, maxf(bv.x, 0.05)), -1.45, 1.45)
	var still := b.rider_body.rest > 0.35 and b.bike_body.rest > 0.2
	if b.crash_t < CRASH_MIN or (not still and b.crash_t < CRASH_MAX): return
	# Back on the bike on the trail, level with where you came down (a bit
	# further on if you were stuck), pointing along it, clear of rocks and trees.
	var at := b.s + (4.0 if b.crash_reason == "stuck" else 1.0)
	var spot := clear_spot(c, at, c.trail_d(at), false)
	b.s = spot.x
	b.d = spot.y
	b.psi = clampf(atan2(c.trail_d(b.s + 3.0) - c.trail_d(b.s), 3.0), -1.0, 1.0)
	b.v = 4.0
	b.vy = 0.0
	b.y = c.height(b.s, b.d)
	b.crashed = false
	b.grounded = true
	b.pitch = 0.0
	b.yaw = 0.0
	b.invulnerable = INVULNERABLE
	b.rider_body = null
	b.bike_body = null

## The nearest place around (s, d) with no rock or tree within reach, inside
## the valley. With `ahead`, also looks a little further down the slope.
static func clear_spot(c: Course, s: float, d: float, ahead: bool) -> Vector2:
	var e := c.edges(s)
	var here := clampf(d, e.x + 1.0, e.y - 1.0)
	# Out of a lake or a gorge, look much further: the far bank or the far side.
	var far := c.water_depth(s, d) > 0.2 or c.in_chasm(s, d)
	var steps := [0.0, 1.5, 3.0] if ahead else [0.0]
	if far: steps = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 13.0, 16.0, 20.0, 25.0]
	var offsets := [0.0, -1.5, 1.5, -3.0, 3.0, -4.5, 4.5]
	if far: offsets += [-7.0, 7.0, -10.0, 10.0, -13.0, 13.0]
	for ds in steps:
		for dd in offsets:
			var p := Vector2(s + ds, clampf(here + dd, e.x + 1.0, e.y - 1.0))
			var clear := c.water_depth(p.x, p.y) < 0.1 and not c.in_chasm(p.x, p.y)
			for o in c.obstacles_near(p.x):
				if Vector2(o.s - p.x, o.d - p.y).length() < o.r + 1.0: clear = false
			if clear: return p
	return Vector2(s, here)
