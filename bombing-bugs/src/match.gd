extends RefCounted
## Pure simulation: no rendering, input devices or host connection required.
const RADIUS := 0.26
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const LAYOUTS := ["Clover garden", "Seed crossroads", "Pebble islands", "Scattered stones", "Boulder field"]
const SIZES := {"Small": Vector2i(11,9), "Medium": Vector2i(13,11), "Large": Vector2i(15,13)}
# Odd sizes keep the outer wall and the classic pillar grid lined up.
const AUTO_SIZES := {2: [Vector2i(11,9), Vector2i(13,9)], 3: [Vector2i(13,11), Vector2i(15,9)], 4: [Vector2i(13,11), Vector2i(15,11), Vector2i(15,13)]}
# Power-up odds when a sand mound hides one: the classic pair stays common,
# the wild ones are rare enough to feel like a find.
const POWER_ODDS := [["capacity",.30],["range",.30],["speed",.15],["kick",.10],["ghost",.08],["mega",.07]]
const MAX_RANGE := 12
const KICK_SPEED := 7.0
const DEFAULTS := {"ai_players":3, "teams":"Free-for-all", "arena":"Surprise me", "size":"Auto", "friendly_fire":false, "fuse":24, "speed":32, "crates":55, "pickups":true}
var settings: Dictionary = DEFAULTS.duplicate()
var w := 13
var h := 11
var layout := "Clover garden"
var cells: Dictionary = {}
var bugs: Array[Dictionary] = []
var bombs: Array[Dictionary] = []
var flames: Array[Dictionary] = []
var pickups: Dictionary = {}
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var ended := false
var winner := -2
var next_bomb := 0
var age := 0.0
var seed_value := 0

func spawns() -> Array[Vector2i]:
	return [Vector2i(1,1), Vector2i(w-2,h-2), Vector2i(w-2,1), Vector2i(1,h-2)]

func inside(c: Vector2i) -> bool:
	return c.x > 0 and c.y > 0 and c.x < w-1 and c.y < h-1

func start(roster: Array, options: Dictionary, seed_value: int) -> void:
	settings = DEFAULTS.duplicate()
	settings.merge(options, true)
	rng.seed = seed_value
	self.seed_value = seed_value
	cells.clear(); bugs.clear(); bombs.clear(); flames.clear(); pickups.clear(); events.clear()
	ended = false; winner = -2; age = 0.0; next_bomb = 0
	var size: Vector2i = SIZES.get(settings.size, Vector2i.ZERO)
	if size == Vector2i.ZERO:
		var options_for: Array = AUTO_SIZES[clampi(roster.size(),2,4)]
		size = options_for[rng.randi() % options_for.size()]
	w = size.x; h = size.y
	layout = settings.arena if settings.arena in LAYOUTS else LAYOUTS[rng.randi() % LAYOUTS.size()]
	var rocks := _rocks()
	for y in h:
		for x in w:
			var c := Vector2i(x,y)
			cells[c] = 1 if rocks.has(c) else (2 if rng.randf() < float(settings.crates)/100.0 else 0)
	for s in spawns():
		cells[s] = 0
		for d in DIRS:
			if inside(s + d) and cells[s + d] == 2: cells[s + d] = 0
	var spots := spawns()
	for i in mini(roster.size(), 4):
		var p: Dictionary = roster[i].duplicate(true)
		p.merge({"pos":Vector2(spots[i]), "alive":true, "range":2, "capacity":1, "speed":0, "kick":false, "ghost":false, "team":i % 2 if settings.teams == "Teams" else i, "heading":0.0, "moving":false, "target":Vector2(spots[i]), "brain":0.0},true)
		bugs.append(p)

## Rock cells for this round: the border plus the layout's interior rocks.
func _rocks() -> Dictionary:
	for attempt in 12:
		var rocks := {}
		for y in h:
			for x in w:
				var c := Vector2i(x,y)
				if not inside(c) or _rock(c): rocks[c] = true
		# Random layouts mirror one quarter so every corner spawn sees the same garden.
		if layout in ["Scattered stones", "Boulder field"]:
			for c in rocks.keys():
				for m in [Vector2i(w-1-c.x,c.y), Vector2i(c.x,h-1-c.y), Vector2i(w-1-c.x,h-1-c.y)]: rocks[m] = true
		for s in spawns():
			rocks.erase(s)
			for d in DIRS:
				if inside(s+d): rocks.erase(s+d)
		if _connected(rocks): return rocks
	layout = "Clover garden"
	return _rocks()

func _rock(c: Vector2i) -> bool:
	var pillar := c.x % 2 == 0 and c.y % 2 == 0
	match layout:
		"Seed crossroads": return pillar and c.x != w/2 and c.y != h/2
		"Pebble islands":
			# Two open pillar columns; a small garden opens its middle row instead.
			if w >= 13: return pillar and c.x != 4 and c.x != w-5
			return pillar and c.y != h/2
		"Scattered stones":
			# Free-standing stones, never touching: open lanes in every direction.
			if c.x > w/2 or c.y > h/2: return false
			return (c.x+c.y) % 2 == 0 and rng.randf() < 0.32
		"Boulder field":
			# The pillar grid, with some pillars gone and others grown into long boulders.
			if c.x > w/2 or c.y > h/2: return false
			if pillar: return rng.randf() < 0.8
			return (c.x % 2 == 0 or c.y % 2 == 0) and rng.randf() < 0.18
	return pillar

## Every open cell must be reachable from every spawn once the sand is gone.
func _connected(rocks: Dictionary) -> bool:
	var first: Vector2i = spawns()[0]
	var seen := {first: true}; var queue := [first]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in DIRS:
			var n: Vector2i = c+d
			if inside(n) and not seen.has(n) and not rocks.has(n): seen[n] = true; queue.append(n)
	for y in range(1,h-1):
		for x in range(1,w-1):
			if not rocks.has(Vector2i(x,y)) and not seen.has(Vector2i(x,y)): return false
	return true

func tile(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))

func bomb_at(c: Vector2i) -> int:
	for i in bombs.size():
		if bombs[i].cell == c: return i
	return -1

func solid(c: Vector2i, who: int) -> bool:
	var value: int = cells.get(c,1)
	# A ghost bug wanders through sand and bombs; only rock stops it.
	var ghost: bool = who >= 0 and who < bugs.size() and bugs[who].ghost
	if value == 1 or (value == 2 and not ghost): return true
	var bi := bomb_at(c)
	return bi >= 0 and not ghost and not bombs[bi].passers.has(who)

func fits(pos: Vector2, who: int) -> bool:
	for y in range(floori(pos.y-RADIUS+0.5), floori(pos.y+RADIUS+0.5)+1):
		for x in range(floori(pos.x-RADIUS+0.5), floori(pos.x+RADIUS+0.5)+1):
			if solid(Vector2i(x,y),who): return false
	return true

func move_bug(who: int, direction: Vector2, dt: float) -> void:
	var p: Dictionary = bugs[who]
	var v: Vector2 = direction.limit_length() * float(settings.speed)/10.0 * (1.0+0.18*p.speed) * dt
	var steps := maxi(1, ceili(v.length()/0.07))
	v /= steps
	var old: Vector2 = p.pos
	for _s in steps:
		var pos: Vector2 = p.pos
		if fits(pos + Vector2(v.x,0),who): pos.x += v.x
		elif absf(v.x) > absf(v.y):
			var center := roundf(pos.y)
			if absf(center-pos.y) < 0.38:
				var assist := Vector2(pos.x, move_toward(pos.y,center,absf(v.x)))
				if fits(assist,who): pos = assist
		if fits(pos + Vector2(0,v.y),who): pos.y += v.y
		elif absf(v.y) > absf(v.x):
			var center := roundf(pos.x)
			if absf(center-pos.x) < 0.38:
				var assist := Vector2(move_toward(pos.x,center,absf(v.y)),pos.y)
				if fits(assist,who): pos = assist
		p.pos = pos
	p.moving = old.distance_to(p.pos) > 0.001
	if p.moving: p.heading = atan2((p.pos-old).x,(p.pos-old).y)
	for b in bombs:
		if absf(p.pos.x-b.cell.x) > 0.5+RADIUS or absf(p.pos.y-b.cell.y) > 0.5+RADIUS: b.passers.erase(who)

func place(who: int) -> bool:
	if ended or not bugs[who].alive: return false
	var p: Dictionary = bugs[who]
	var c := tile(p.pos)
	var count := 0
	for b in bombs:
		if b.owner == who: count += 1
	if count >= p.capacity or bomb_at(c) >= 0 or cells[c] != 0: return false
	var passers := []
	for i in bugs.size():
		if absf(bugs[i].pos.x-c.x) < 0.5+RADIUS and absf(bugs[i].pos.y-c.y) < 0.5+RADIUS: passers.append(i)
	bombs.append({"id":next_bomb,"cell":c,"owner":who,"range":p.range,"time":float(settings.fuse)/10.0,"passers":passers,"slide":Vector2i.ZERO,"glide":0.0})
	next_bomb += 1
	events.append({"type":"plant","cell":c})
	return true

func rays(c: Vector2i, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [c]
	for d in DIRS:
		for n in range(1,reach+1):
			var t: Vector2i = c+d*n
			if cells.get(t,1) == 1: break
			out.append(t)
			if cells.get(t) == 2 or bomb_at(t) >= 0: break
	return out

func explode(index: int) -> void:
	var b: Dictionary = bombs[index]
	bombs.remove_at(index)
	var hit := rays(b.cell,b.range)
	events.append({"type":"boom","cell":b.cell,"cells":hit})
	for c in hit:
		flames.append({"cell":c,"owner":b.owner,"time":0.65})
		pickups.erase(c)
		if cells[c] == 2:
			cells[c] = 0
			events.append({"type":"crack","cell":c})
			if settings.pickups and rng.randf() < 0.4:
				# Only reveal after this blast has ended.
				pickups[c] = {"kind": _power_kind(), "wait":0.7}
		var chain := bomb_at(c)
		if chain >= 0: bombs[chain].time = 0.0

func _power_kind() -> String:
	var roll := rng.randf()
	for entry in POWER_ODDS:
		roll -= entry[1]
		if roll < 0: return entry[0]
	return "capacity"

func collect(p: Dictionary, kind: String) -> void:
	match kind:
		"capacity": p.capacity = mini(p.capacity+1,4)
		"range": p.range = mini(p.range+1,5) if p.range < 5 else p.range
		"speed": p.speed = mini(p.speed+1,3)
		"kick": p.kick = true
		"ghost": p.ghost = true
		"mega": p.range = MAX_RANGE

func bug_in(c: Vector2i) -> bool:
	for b in bugs:
		if b.alive and tile(b.pos) == c: return true
	return false

## A kicker walking into a bomb sends it sliding until something stops it.
func kick(who: int, move: Vector2) -> void:
	var p: Dictionary = bugs[who]
	if not p.kick or move.length() < .5: return
	var dir := Vector2i(1 if move.x > 0 else -1,0) if absf(move.x) > absf(move.y) else Vector2i(0,1 if move.y > 0 else -1)
	var ahead: Vector2i = tile(p.pos)+dir
	var bi := bomb_at(ahead)
	if bi < 0 or bombs[bi].passers.has(who) or bombs[bi].slide != Vector2i.ZERO: return
	if Vector2(ahead).distance_to(p.pos) > 0.5+RADIUS+0.08: return
	bombs[bi].slide = dir; bombs[bi].glide = 0.0
	events.append({"type":"kick","cell":ahead,"who":who})

func slide_bombs(dt: float) -> void:
	for b in bombs:
		if b.slide == Vector2i.ZERO: continue
		var next: Vector2i = b.cell+b.slide
		if cells.get(next,1) != 0 or bomb_at(next) >= 0 or bug_in(next):
			b.slide = Vector2i.ZERO; b.glide = 0.0; continue
		b.glide += dt*KICK_SPEED
		if b.glide >= 1.0:
			b.cell = next; b.glide -= 1.0; b.passers.clear()

func step(dt: float, commands: Array) -> void:
	events.clear()
	age += dt
	for i in bugs.size():
		if not bugs[i].alive: continue
		var cmd: Dictionary = commands[i] if i < commands.size() else {}
		move_bug(i,cmd.get("move",Vector2.ZERO),dt)
		if cmd.get("bomb",false): place(i)
		kick(i,cmd.get("move",Vector2.ZERO))
	slide_bombs(dt)
	for b in bombs: b.time -= dt
	var more := true
	while more:
		more = false
		for i in bombs.size():
			if bombs[i].time <= 0:
				explode(i); more = true; break
	for f in flames: f.time -= dt
	flames = flames.filter(func(f: Dictionary) -> bool: return f.time > 0)
	for c in pickups: pickups[c].wait -= dt
	# Results are locked, but survivors and lingering effects keep moving.
	if ended: return
	for i in bugs.size():
		var p: Dictionary = bugs[i]
		if not p.alive: continue
		var c := tile(p.pos)
		for f in flames:
			if f.cell != c: continue
			if f.owner != i and bugs[f.owner].team == p.team and not settings.friendly_fire: continue
			p.alive = false
			events.append({"type":"out","cell":c,"who":i})
			break
		if p.alive and pickups.has(c) and pickups[c].wait <= 0:
			var kind: String = pickups[c].kind
			collect(p,kind)
			pickups.erase(c)
			events.append({"type":"pickup","cell":c,"who":i,"kind":kind})
	var teams := {}
	for p in bugs:
		if p.alive: teams[p.team] = true
	if bugs.size() >= 2 and teams.size() <= 1:
		ended = true
		winner = int(teams.keys()[0]) if teams.size() == 1 else -1

func danger(extra: Vector2i = Vector2i(-99,-99), reach: int = 2) -> Dictionary:
	var out := {}
	for b in bombs:
		for c in rays(b.cell,b.range): out[c] = true
	for f in flames: out[f.cell] = true
	if extra.x != -99:
		for c in rays(extra,reach): out[c] = true
	return out

func path_to_safe(who: int, hazards: Dictionary, seek_target: bool) -> Array:
	var start_cell := tile(bugs[who].pos)
	var queue: Array = [start_cell]
	var prev := {start_cell: start_cell}
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]; head += 1
		var goal := not hazards.has(c) and c != start_cell
		if seek_target:
			goal = goal and worthwhile(c,who)
		if goal:
			var path: Array = [c]
			while prev[path[0]] != start_cell: path.push_front(prev[path[0]])
			return path
		for d in DIRS:
			var n: Vector2i = c+d
			if prev.has(n) or cells.get(n,1) != 0 or bomb_at(n) >= 0: continue
			if seek_target and hazards.has(n): continue
			prev[n] = c; queue.append(n)
	return []

func worthwhile(c: Vector2i, who: int) -> bool:
	for d in DIRS:
		if cells.get(c+d,1) == 2: return true
	for i in bugs.size():
		if i == who or not bugs[i].alive or bugs[i].team == bugs[who].team: continue
		if tile(bugs[i].pos) in rays(c,bugs[who].range): return true
	return pickups.has(c)

func bot(who: int, dt: float) -> Dictionary:
	var p: Dictionary = bugs[who]
	var c := tile(p.pos)
	var hazards := danger()
	var centered: bool = p.pos.distance_to(p.target) < 0.015
	var plant := false
	if centered:
		p.pos = Vector2(c)
		if not hazards.has(c) and worthwhile(c,who):
			var escape := path_to_safe(who,danger(c,p.range),false)
			if not escape.is_empty() and escape.size()/ (float(settings.speed)/10.0) + 0.6 < float(settings.fuse)/10.0:
				plant = place(who)
				hazards = danger()
		var path := path_to_safe(who,hazards,not hazards.has(c))
		p.target = Vector2(path[0]) if not path.is_empty() else Vector2(c)
	var delta: Vector2 = p.target-p.pos
	# Slow the final step to land exactly on a corridor centre.
	var magnitude := minf(1.0,delta.length()/maxf(0.001, float(settings.speed)/10.0*(1.0+0.18*p.speed)*dt))
	return {"move":delta.normalized()*magnitude, "bomb":false, "planted":plant}
