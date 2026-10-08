class_name Tumble
extends RefCounted
## A body thrown in a crash: a ball of `radius` in track space that falls,
## bounces, slides with Coulomb friction and spins. Rider and bike each get
## one, so you sail over the bars, skid down the slope and come to rest
## wherever the mountain lets you. On a slope steeper than the friction can
## hold you keep sliding, the way you would.
##
## Positions and velocities are (s, y, d): along the run, up, across.

var p := Vector3.ZERO
var v := Vector3.ZERO
var spin := Vector3.ZERO    ## Angular velocity about the body's own axes, rad/s.
var radius := 0.6
var bounce := 0.3           ## Share of the impact speed that comes back.
var mu := 0.7               ## Sliding friction against the ground.
var grounded := false
var rest := 0.0             ## How long the body has lain still.
var hit := 0.0              ## Hardest impact this step, m/s (for dust and sound).

func _init(p_pos: Vector3, p_vel: Vector3, p_radius: float, p_bounce: float, p_mu: float) -> void:
	p = p_pos
	v = p_vel
	radius = p_radius
	bounce = p_bounce
	mu = p_mu

func step(c: Course, dt: float) -> void:
	hit = 0.0
	v.y -= Bike.G * dt
	# Water drags hard; you wallow to a stop.
	if c.water_depth(p.x, p.z) > 0.25 and p.y < c.water_level(p.x) + radius:
		v *= exp(-3.5 * dt)
	p += v * dt
	var ground := c.height(p.x, p.z) + radius
	grounded = p.y <= ground + 0.02
	if p.y <= ground:
		var g := c.gradient(p.x, p.z)
		var n := Vector3(-g.x, 1.0, -g.y).normalized()
		p.y = ground
		var vn := v.dot(n)
		var vt := v - n * vn
		if vn < 0.0:
			hit = -vn
			# The normal impulse also sets how much friction can take off.
			var speed := vt.length()
			vt *= maxf(0.0, speed - mu * hit) / maxf(speed, 0.001)
			vn = hit * bounce if hit > 1.2 else 0.0
			# Hitting the ground knocks the spin down and turns some of the
			# slide into rolling end over end.
			var roll := Vector3(vt.length() / radius, 0.0, 0.0)
			spin = spin.lerp(roll, 0.25) * (0.75 if hit > 1.2 else 1.0)
		v = vt + n * vn
		spin *= exp(-2.5 * dt)
	_push_off_obstacles(c)
	rest = rest + dt if grounded and v.length() < 0.6 else 0.0

## Trees and rocks are solid: bounce off them instead of sliding through.
func _push_off_obstacles(c: Course) -> void:
	for o in c.obstacles_near(p.x):
		var gap := Vector2(p.x - o.s, p.z - o.d)
		var reach: float = o.r + radius * 0.7
		if gap.length_squared() > reach * reach: continue
		if p.y - c.height(o.s, o.d) > o.h + radius: continue
		var dist := gap.length()
		var n := gap / maxf(dist, 0.001)
		p.x = o.s + n.x * reach
		p.z = o.d + n.y * reach
		var vh := Vector2(v.x, v.z)
		var into := vh.dot(n)
		if into < 0.0:
			hit = maxf(hit, -into)
			vh -= n * into * 1.35
			v.x = vh.x * 0.8
			v.z = vh.y * 0.8
