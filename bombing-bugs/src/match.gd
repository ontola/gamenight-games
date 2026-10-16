extends RefCounted
## Pure simulation: no rendering, input devices or host connection required.
const W := 13
const H := 11
const RADIUS := 0.26
const DIRS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SPAWNS := [Vector2i(1,1), Vector2i(W-2,H-2), Vector2i(W-2,1), Vector2i(1,H-2)]
const DEFAULTS := {"ai_players":3, "teams":"Free-for-all", "arena":"Clover garden", "friendly_fire":false, "fuse":24, "speed":32, "crates":55, "pickups":true}
var settings: Dictionary = DEFAULTS.duplicate()
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

func start(roster: Array, options: Dictionary, seed_value: int) -> void:
	settings = DEFAULTS.duplicate()
	settings.merge(options, true)
	rng.seed = seed_value
	cells.clear(); bugs.clear(); bombs.clear(); flames.clear(); pickups.clear(); events.clear()
	ended = false; winner = -2; age = 0.0; next_bomb = 0
	for y in H:
		for x in W:
			var c := Vector2i(x,y)
			var wall := x == 0 or y == 0 or x == W-1 or y == H-1 or (x % 2 == 0 and y % 2 == 0)
			# Each layout opens different loops without blocking corner exits.
			if x > 0 and y > 0 and x < W-1 and y < H-1:
				if settings.arena == "Seed crossroads" and (x == W/2 or y == H/2): wall = false
				if settings.arena == "Pebble islands" and (x == 4 or x == 8): wall = false
			cells[c] = 1 if wall else (2 if rng.randf() < float(settings.crates)/100.0 else 0)
	for s in SPAWNS:
		cells[s] = 0
		for d in DIRS:
			var c: Vector2i = s + d
			if c.x > 0 and c.y > 0 and c.x < W-1 and c.y < H-1: cells[c] = 0
	for i in mini(roster.size(), 4):
		var p: Dictionary = roster[i].duplicate(true)
		p.merge({"pos":Vector2(SPAWNS[i]), "alive":true, "range":2, "capacity":1, "team":i % 2 if settings.teams == "Teams" else i, "heading":0.0, "moving":false, "target":Vector2(SPAWNS[i]), "brain":0.0},true)
		bugs.append(p)

func tile(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))

func bomb_at(c: Vector2i) -> int:
	for i in bombs.size():
		if bombs[i].cell == c: return i
	return -1

func solid(c: Vector2i, who: int) -> bool:
	if cells.get(c,1) != 0: return true
	var bi := bomb_at(c)
	return bi >= 0 and not bombs[bi].passers.has(who)

func fits(pos: Vector2, who: int) -> bool:
	for y in range(floori(pos.y-RADIUS+0.5), floori(pos.y+RADIUS+0.5)+1):
		for x in range(floori(pos.x-RADIUS+0.5), floori(pos.x+RADIUS+0.5)+1):
			if solid(Vector2i(x,y),who): return false
	return true

func move_bug(who: int, direction: Vector2, dt: float) -> void:
	var p: Dictionary = bugs[who]
	var v := direction.limit_length() * float(settings.speed)/10.0 * dt
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
	bombs.append({"id":next_bomb,"cell":c,"owner":who,"range":p.range,"time":float(settings.fuse)/10.0,"passers":passers})
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
	events.append({"type":"boom","cell":b.cell})
	for c in rays(b.cell,b.range):
		flames.append({"cell":c,"owner":b.owner,"time":0.65})
		pickups.erase(c)
		if cells[c] == 2:
			cells[c] = 0
			events.append({"type":"crack","cell":c})
			if settings.pickups and rng.randf() < 0.4:
				# Only reveal after this blast has ended.
				pickups[c] = {"kind": "range" if rng.randf() < 0.5 else "capacity", "wait":0.7}
		var chain := bomb_at(c)
		if chain >= 0: bombs[chain].time = 0.0

func step(dt: float, commands: Array) -> void:
	events.clear()
	age += dt
	for i in bugs.size():
		if not bugs[i].alive: continue
		var cmd: Dictionary = commands[i] if i < commands.size() else {}
		move_bug(i,cmd.get("move",Vector2.ZERO),dt)
		if cmd.get("bomb",false): place(i)
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
			p[kind] = mini(p[kind]+1, 5 if kind == "range" else 4)
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
	var magnitude := minf(1.0,delta.length()/maxf(0.001, float(settings.speed)/10.0*dt))
	return {"move":delta.normalized()*magnitude, "bomb":false, "planted":plant}
