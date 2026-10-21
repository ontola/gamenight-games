class_name Traffic
extends Node3D
## What else is moving on the mountain: cars on the roads, wildlife that bolts
## when a rider comes close, and the odd bear that charges. Everything lives in
## mountain space like the riders, and anything big enough knocks you off.

const CAR_HALF_LENGTH := 1.9
const CAR_HALF_WIDTH := 0.95
const LANE := 1.45            ## Cars keep right of the road's centre line.
const BEAR_RADIUS := 0.85
const BEAR_SPEED := 7.5       ## A bear outruns a slow rider, not a fast one.
const BEAR_SIGHT := 15.0
const BEAR_LEASH := 28.0      ## How far a bear chases from its patch.

var course: Course
var view: MountainView
var cars: Array[Dictionary] = []    ## {road, d, dir, speed, node}
var bears: Array[Dictionary] = []   ## {s, d, home, heading, charge, rest, node}
var _next_car: Array[float] = []    ## Per road: seconds until the next car.
var hikers: Array[Dictionary] = [] ## {s, d, dir, home_d, aside, wait, down, node}
var _fleeing := {}                  ## animal -> {dir: Vector2, speed, left}
var _rng := RandomNumberGenerator.new()

func _init(c: Course, v: MountainView) -> void:
	course = c
	view = v
	name = "Traffic"
	_rng.seed = c.seed_value * 13 + 7
	for road in course.roads: _next_car.append(_rng.randf_range(0.0, 2.5))
	_place_bears()
	_place_hikers()

## One physics step: move everything, then see who got hit.
func step(bikes: Array, dt: float) -> void:
	var lead := -INF
	for b in bikes: lead = maxf(lead, b.s)
	_step_cars(bikes, lead, dt)
	_step_animals(bikes, dt)
	_step_bears(bikes, dt)
	_step_hikers(bikes, dt)

# ── Cars ─────────────────────────────────────────────────────────────────────

func _step_cars(bikes: Array, lead: float, dt: float) -> void:
	for i in course.roads.size():
		var road: Dictionary = course.roads[i]
		# Traffic only runs on roads someone is about to ride across, or is on.
		if road.s < lead - 40.0 or road.s > lead + 140.0: continue
		_next_car[i] -= dt
		if _next_car[i] <= 0.0:
			_next_car[i] = _rng.randf_range(2.5, 6.0)
			var dir := 1.0 if _rng.randf() < 0.5 else -1.0
			var car := {"road": road, "d": -dir * (float(road.max_d) - 2.0), "dir": dir,
				"speed": _rng.randf_range(12.0, 17.0), "node": _car_mesh()}
			add_child(car.node)
			cars.append(car)
	for car in cars.duplicate():
		var road: Dictionary = car.road
		car.d += car.dir * car.speed * dt
		if absf(car.d) > float(road.max_d) - 1.0:
			car.node.queue_free()
			cars.erase(car)
			continue
		var cs := car_s(car)
		_place_car(car, cs)
		for b in bikes:
			if b.crashed or b.invulnerable > 0.0: continue
			if b.y > course.height(cs, car.d) + 1.7: continue  # Jumped clean over the bonnet.
			if absf(b.d - car.d) < CAR_HALF_LENGTH + Bike.RADIUS and absf(b.s - cs) < CAR_HALF_WIDTH + Bike.RADIUS:
				# Thrown the way the car was going, and up over the bonnet.
				var push := Vector3(signf(b.s - cs) * 1.5, 2.5 + car.speed * 0.15, car.dir * car.speed * 0.85)
				Bike.struck(b, push, "car")

## Where along the mountain the car is: on its lane of the road.
func car_s(car: Dictionary) -> float:
	return course.road_line(car.road, car.d) - car.dir * LANE

func _place_car(car: Dictionary, cs: float) -> void:
	var ahead := course.world(course.road_line(car.road, car.d + car.dir * 0.6) - car.dir * LANE, car.d + car.dir * 0.6)
	var behind := course.world(course.road_line(car.road, car.d - car.dir * 0.6) - car.dir * LANE, car.d - car.dir * 0.6)
	var forward := (ahead - behind).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	car.node.transform = Transform3D(Basis(-right, up, -forward), course.world(cs, car.d))

func _car_mesh() -> MeshInstance3D:
	var lp := LowPoly.new()
	var paint: Color = [Color("c94d46"), Color("3f6fb5"), Color("e7c14b"), Color("f0ece0"), Color("3c8a63")][_rng.randi() % 5]
	var glass := Color("304756")
	var rubber := Color("293038")
	lp.box(Vector3(0, 0.7, 0), Vector3(1.8, 0.65, 3.8), paint)
	lp.box(Vector3(0, 1.22, 0.25), Vector3(1.6, 0.6, 2.0), glass)
	lp.box(Vector3(0, 1.56, 0.25), Vector3(1.7, 0.12, 2.15), paint)
	for x in [-0.85, 0.85]:
		for z in [-1.2, 1.2]: lp.ring(Vector3(x, 0.4, z), 0.32, 0.11, rubber, 10)
		lp.box(Vector3(x * 0.7, 0.8, -1.92), Vector3(0.32, 0.18, 0.05), Color("fff1b7"))
		lp.box(Vector3(x * 0.7, 0.8, 1.92), Vector3(0.32, 0.18, 0.05), Color("c94d46"))
	lp.box(Vector3(0, 0.46, -1.92), Vector3(1.82, 0.13, 0.08), Color("c6c7bb"))
	lp.box(Vector3(0, 0.46, 1.92), Vector3(1.82, 0.13, 0.08), Color("c6c7bb"))
	var mi := MeshInstance3D.new()
	mi.name = "Car"
	mi.mesh = lp.commit()
	return mi

# ── Wildlife ─────────────────────────────────────────────────────────────────
# Sheep, deer and hares graze beside the trail. Ride up on them and they bolt,
# not always the smart way: plenty run straight across your line.

func _step_animals(bikes: Array, dt: float) -> void:
	for animal in view._ambient:
		if not is_instance_valid(animal): continue
		var at: Vector2 = animal.get_meta("course_position")
		var kind: String = animal.get_meta("kind", "sheep")
		var radius := 0.35 if kind == "hare" else 0.6
		var near: Bike = null
		var best := INF
		for b in bikes:
			if b.crashed: continue
			var dist := Vector2(b.s - at.x, b.d - at.y).length()
			if dist < best:
				best = dist
				near = b
		if near == null: continue
		var run: Dictionary = _fleeing.get(animal, {})
		var spook := 7.0 if kind == "sheep" else 10.0
		if run.is_empty() and best < spook:
			# Bolt sideways, to whichever side it picks in its panic.
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var dir := Vector2(_rng.randf_range(-0.2, 0.5), side).normalized()
			var speed := 3.5 if kind == "sheep" else (8.0 if kind == "deer" else 7.0)
			run = {"dir": dir, "speed": speed, "left": _rng.randf_range(1.8, 3.0)}
			_fleeing[animal] = run
		if not run.is_empty():
			run.left -= dt
			if run.left <= 0.0:
				_fleeing.erase(animal)
			else:
				at += run.dir * run.speed * dt
				if absf(at.y) > Course.CORRIDOR + 12.0: run.dir.y = -run.dir.y
				animal.set_meta("course_position", at)
				var p := course.world(at.x, at.y)
				animal.position = p
				animal.set_meta("ground_y", p.y)
				var ahead := course.world(at.x + run.dir.x, at.y + run.dir.y)
				animal.rotation.y = atan2(-(ahead.x - p.x), -(ahead.z - p.z))
		# Hitting one at speed puts you over the bars. Slowly, you just bump it.
		if best < radius + Bike.RADIUS and near.grounded and near.invulnerable <= 0.0:
			var fall_speed := 7.0 if kind == "hare" else 3.5
			if near.v > fall_speed:
				Bike._crash(near, "animal")
			else:
				near.v *= 0.5
				near.wobble = maxf(near.wobble, 0.5)
			# Off it goes, the other way.
			var away := Vector2(at.x - near.s, at.y - near.d).normalized()
			_fleeing[animal] = {"dir": away, "speed": 9.0, "left": 2.5}

# ── Bears ────────────────────────────────────────────────────────────────────
# A bear or two lives in the woods beside the trail. Come close and it charges
# at you; keep your speed up and you leave it behind.

func _place_bears() -> void:
	if course.biome == "desert": return
	var count := 2 if course.length > 700.0 else 1
	for k in count:
		for attempt in 20:
			var s := _rng.randf_range(160.0, course.length - 80.0)
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var d := course.trail_d(s) + side * (course.trail_half(s) + _rng.randf_range(7.0, 12.0))
			if course.in_water(s, d) or course.gradient(s, d).length() > 0.6: continue
			var bear := {"s": s, "d": d, "home": Vector2(s, d), "heading": PI, "charge": 0.0, "rest": 0.0, "node": _bear_mesh()}
			add_child(bear.node)
			bears.append(bear)
			_place_bear(bear)
			break

func _step_bears(bikes: Array, dt: float) -> void:
	for bear in bears:
		bear.rest = maxf(0.0, bear.rest - dt)
		var pos := Vector2(bear.s, bear.d)
		var target: Bike = null
		var best := INF
		for b in bikes:
			if b.crashed or b.invulnerable > 0.0: continue
			var dist := Vector2(b.s - pos.x, b.d - pos.y).length()
			if dist < best:
				best = dist
				target = b
		var home: Vector2 = bear.home
		if target and best < BEAR_SIGHT and bear.rest <= 0.0 and pos.distance_to(home) < BEAR_LEASH:
			# Charge where the rider is going to be, not where they are.
			bear.charge += dt
			var lead := Vector2(cos(target.psi), sin(target.psi)) * target.v * clampf(best / BEAR_SPEED, 0.0, 1.0) * 0.6
			var to := Vector2(target.s, target.d) + lead - pos
			bear.heading = atan2(to.y, to.x)
			pos += to.normalized() * BEAR_SPEED * dt
			if bear.charge > 4.0:
				bear.charge = 0.0
				bear.rest = 3.0
		else:
			bear.charge = 0.0
			# Amble back to its patch.
			var back := home - pos
			if back.length() > 1.0:
				bear.heading = atan2(back.y, back.x)
				pos += back.normalized() * 1.6 * dt
		bear.s = pos.x
		bear.d = pos.y
		_place_bear(bear)
		if target and Vector2(target.s - pos.x, target.d - pos.y).length() < BEAR_RADIUS + Bike.RADIUS and target.y < course.height(pos.x, pos.y) + 1.6:
			var swipe := Vector2(cos(bear.heading), sin(bear.heading)) * 5.0
			Bike.struck(target, Vector3(swipe.x, 2.0, swipe.y), "bear")
			bear.rest = 4.0
			bear.charge = 0.0

func _place_bear(bear: Dictionary) -> void:
	var p := course.world(bear.s, bear.d)
	var ahead := course.world(bear.s + cos(bear.heading), bear.d + sin(bear.heading))
	bear.node.position = p
	bear.node.rotation.y = atan2(-(ahead.x - p.x), -(ahead.z - p.z))
	# A lumbering gallop while it charges.
	var gallop: float = sin(Time.get_ticks_msec() * 0.018) * 0.12 if bear.charge > 0.0 else 0.0
	bear.node.get_child(0).position.y = absf(gallop)

func _bear_mesh() -> Node3D:
	var lp := LowPoly.new()
	var fur := Color("5b3d27") if course.biome != "snow" else Color("ece8dc")
	var dark := fur.darkened(0.45)
	lp.blob(Vector3(0, 1.0, 0.1), Vector3(0.75, 0.62, 1.05), fur, _rng, 3, 8, 0.1)
	lp.blob(Vector3(0, 1.22, -0.5), Vector3(0.62, 0.5, 0.5), fur.darkened(0.05), _rng, 3, 8, 0.08)
	lp.blob(Vector3(0, 1.2, -1.15), Vector3(0.36, 0.34, 0.4), fur, _rng, 3, 6, 0.05)
	lp.blob(Vector3(0, 1.08, -1.5), Vector3(0.18, 0.15, 0.2), fur.lightened(0.25), _rng, 2, 6, 0.03)
	lp.box(Vector3(0, 1.13, -1.68), Vector3(0.12, 0.08, 0.06), dark)
	for x in [-0.22, 0.22]:
		lp.blob(Vector3(x, 1.52, -1.1), Vector3(0.1, 0.1, 0.06), fur.darkened(0.15), _rng, 2, 5, 0.02)
		lp.box(Vector3(x * 0.6, 1.3, -1.48), Vector3(0.06, 0.06, 0.04), Color("151515"))
	for x in [-0.42, 0.42]:
		for z in [-0.45, 0.6]:
			lp.beam(Vector3(x, 0.05, z), Vector3(x, 0.85, z), 0.26, fur.darkened(0.12))
			lp.box(Vector3(x, 0.06, z - 0.06), Vector3(0.3, 0.12, 0.38), dark)
	var mi := MeshInstance3D.new()
	mi.mesh = lp.commit()
	var bear := Node3D.new()
	bear.name = "Bear"
	bear.add_child(mi)
	return bear

# ── Hikers ───────────────────────────────────────────────────────────────────
# People out for a walk on the trail. Hear a rider coming and they step aside,
# but not all of them in time. Ride into one and you both go down.

const HIKER_RADIUS := 0.55
const HIKER_WALK := 1.1

func _place_hikers() -> void:
	var s := Course.START_LINE + 70.0
	while s < course.length - 40.0:
		var group := 1 if _rng.randf() < 0.6 else 2
		var dir := 1.0 if _rng.randf() < 0.5 else -1.0  # Walking down or back up.
		for k in group:
			var hs := s + k * 1.6
			var d := course.trail_d(hs) + _rng.randf_range(-0.6, 0.6) * course.trail_half(hs) + k * 0.7
			if course.in_water(hs, d): continue
			var hiker := {"s": hs, "d": d, "dir": dir, "home": 0.0, "aside": 0.0, "wait": 0.0,
				"heard": false, "react": _rng.randf_range(0.0, 0.9), "down": 0.0, "node": _hiker_mesh()}
			add_child(hiker.node)
			hikers.append(hiker)
			_place_hiker(hiker, 0.0)
		s += _rng.randf_range(70.0, 130.0)

func _step_hikers(bikes: Array, dt: float) -> void:
	for h in hikers:
		var pos := Vector2(h.s, h.d)
		# Who's coming: the nearest rider closing in from up the trail.
		var near: Bike = null
		var best := INF
		for b in bikes:
			if b.crashed: continue
			var dist := Vector2(b.s - pos.x, b.d - pos.y).length()
			if dist < best:
				best = dist
				near = b
		if h.down > 0.0:
			# Knocked flat: lie there a moment, then get up again.
			h.down -= dt
			_place_hiker(h, dt)
			continue
		var coming: bool = near != null and best < 11.0 and near.s < h.s + 1.0
		if coming and not h.heard:
			h.heard = true
			h.wait = h.react
			# Off the trail on the nearer side, a step past its edge.
			var mid := course.trail_d(h.s)
			var side: float = signf(h.d - mid) if absf(h.d - mid) > 0.1 else (1.0 if _rng.randf() < 0.5 else -1.0)
			h.aside = mid + side * (course.trail_half(h.s) + 2.0)
		if h.heard:
			h.wait -= dt
			if h.wait <= 0.0:
				# Hurry aside.
				h.d = move_toward(h.d, h.aside, 2.6 * dt)
			if not coming and best > 14.0:
				h.heard = false
		else:
			# Stroll along the trail.
			h.s += h.dir * HIKER_WALK * dt
			var mid := course.trail_d(h.s)
			h.d = lerpf(h.d, clampf(h.d, mid - course.trail_half(h.s) * 0.7, mid + course.trail_half(h.s) * 0.7), dt)
		_place_hiker(h, dt)
		if near and best < HIKER_RADIUS + Bike.RADIUS and near.grounded and near.invulnerable <= 0.0:
			if near.v > 4.0:
				# Over the bars, and the hiker goes flying too.
				Bike.struck(near, Vector3(cos(near.psi), 0.6, sin(near.psi)) * 1.2, "hiker")
			else:
				near.v *= 0.4
				near.wobble = maxf(near.wobble, 0.6)
			h.down = 3.0 if near.v > 2.0 or near.crashed else 1.2
			h.heard = false

func _place_hiker(h: Dictionary, dt: float) -> void:
	var node: Node3D = h.node
	var p := course.world(h.s, h.d)
	node.position = p
	var facing: Vector2 = Vector2(h.dir, 0.0) if not h.heard else Vector2(0.0, signf(h.aside - h.d) if absf(h.aside - h.d) > 0.05 else h.dir)
	var ahead := course.world(h.s + facing.x, h.d + facing.y)
	node.rotation.y = atan2(-(ahead.x - p.x), -(ahead.z - p.z))
	var body: Node3D = node.get_child(0)
	var walking: bool = h.down <= 0.0 and (not h.heard or (h.wait <= 0.0 and absf(h.aside - h.d) > 0.05))
	if walking: h.phase = float(h.get("phase", 0.0)) + dt * 7.0
	var swing: float = sin(float(h.get("phase", 0.0))) * 0.45 if walking else 0.0
	body.get_node("LegL").rotation.x = swing
	body.get_node("LegR").rotation.x = -swing
	body.position.y = absf(sin(float(h.get("phase", 0.0)))) * 0.04 if walking else 0.0
	# Flat on their back after a hit.
	body.rotation.x = lerpf(body.rotation.x, -1.45 if h.down > 0.0 else 0.0, minf(1.0, dt * 9.0))

func _hiker_mesh() -> Node3D:
	var shirts := [Color("d9534f"), Color("3f7fd9"), Color("e7c14b"), Color("4f9a6a"), Color("9b59b6"), Color("e67e22")]
	var shirt: Color = shirts[_rng.randi() % shirts.size()]
	var skin: Color = [Color("f1c7a1"), Color("c8946b"), Color("8d5a3b")][_rng.randi() % 3]
	var trousers := Color("39424e") if _rng.randf() < 0.5 else Color("7a6a4f")
	var root := Node3D.new()
	root.name = "Hiker"
	# Drawn at the riders' scale, so they read from the camera.
	root.scale = Vector3.ONE * RiderView.SCALE * 0.9
	var body := Node3D.new()
	root.add_child(body)
	var lp := LowPoly.new()
	lp.box(Vector3(0, 1.17, 0), Vector3(0.42, 0.56, 0.26), shirt)
	lp.box(Vector3(0, 1.2, 0.2), Vector3(0.34, 0.44, 0.18), Color("5b4636"))  # Backpack.
	lp.blob(Vector3(0, 1.6, 0), Vector3(0.13, 0.15, 0.13), skin, _rng, 3, 6, 0.02)
	lp.cone(Vector3(0, 1.7, 0), 0.2, 0.1, 0.12, 8, shirt.darkened(0.35))  # Sun hat.
	for x in [-0.27, 0.27]:
		lp.beam(Vector3(x, 1.4, 0), Vector3(x * 1.1, 0.95, -0.05), 0.09, shirt)
	var torso := MeshInstance3D.new()
	torso.mesh = lp.commit()
	body.add_child(torso)
	for side in [["LegL", -0.11], ["LegR", 0.11]]:
		var leg := Node3D.new()
		leg.name = side[0]
		leg.position = Vector3(side[1], 0.9, 0)
		var lpl := LowPoly.new()
		lpl.beam(Vector3.ZERO, Vector3(0, -0.82, 0), 0.13, trousers)
		lpl.box(Vector3(0, -0.86, -0.05), Vector3(0.14, 0.09, 0.24), Color("2b2622"))
		var mi := MeshInstance3D.new()
		mi.mesh = lpl.commit()
		leg.add_child(mi)
		body.add_child(leg)
	# A walking pole.
	var pole := LowPoly.new()
	pole.beam(Vector3(0.32, 1.0, -0.1), Vector3(0.36, 0.0, -0.3), 0.03, Color("b9b9b9"))
	var pm := MeshInstance3D.new()
	pm.mesh = pole.commit()
	body.add_child(pm)
	return root
