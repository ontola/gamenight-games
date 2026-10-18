extends SceneTree
const Match = preload("res://src/match.gd")
var failures := 0
var assertions := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; push_error(message)

func fresh(options: Dictionary = {}) -> RefCounted:
	var m := Match.new()
	m.start([{"name":"A"},{"name":"B"},{"name":"C"},{"name":"D"}],options,73)
	return m

func clear_inside(m: RefCounted) -> void:
	for c in m.cells:
		if m.inside(c): m.cells[c] = 0

func _init() -> void:
	var m := fresh()
	clear_inside(m)
	m.move_bug(0,Vector2.RIGHT,1.0/60)
	check(m.bugs[0].pos.x > 1 and m.bugs[0].pos.x < 1.1,"Movement must be continuous, not tile-based")
	var m2 := fresh(); clear_inside(m2)
	for i in 120: m2.move_bug(0,Vector2.RIGHT,1.0/120)
	var m3 := fresh(); clear_inside(m3)
	for i in 30: m3.move_bug(0,Vector2.RIGHT,1.0/30)
	check(m2.bugs[0].pos.distance_to(m3.bugs[0].pos) < .01,"Movement depends on frame rate")
	m = fresh(); clear_inside(m); m.cells[Vector2i(3,1)] = 1
	m.move_bug(0,Vector2.RIGHT,3)
	check(m.bugs[0].pos.x < 2.25,"Movement tunnels through rocks")
	m = fresh(); clear_inside(m)
	check(m.place(0),"First bomb should plant")
	check(not m.place(0),"Bomb capacity ignored")
	m.move_bug(0,Vector2.RIGHT,.5)
	check(m.bugs[0].pos.x > 2,"Must be able to leave own bomb")
	m.move_bug(0,Vector2.LEFT,.5)
	check(m.bugs[0].pos.x > 1.75,"Cannot re-enter solid bomb")
	m = fresh(); clear_inside(m)
	m.bugs[0].pos = Vector2(5,5); m.bugs[0].range = 4
	m.cells[Vector2i(6,5)] = 2
	check(Vector2i(6,5) in m.rays(Vector2i(5,5),4),"Blast should hit first seed")
	check(Vector2i(7,5) not in m.rays(Vector2i(5,5),4),"Blast must stop at seed")
	check(Vector2i(6,6) not in m.rays(Vector2i(5,5),4),"No diagonal blasts")
	m.cells[Vector2i(6,5)] = 0; m.bugs[1].pos = Vector2(7,5)
	m.place(0); m.place(1); m.bombs[0].time = 0
	m.step(.016,[])
	check(m.bombs.is_empty(),"Bomb chain must detonate immediately")
	m = fresh({"teams":"Teams","friendly_fire":false}); clear_inside(m)
	m.bugs[2].pos = Vector2(3,1)
	m.flames.append({"cell":Vector2i(3,1),"owner":0,"time":.5}); m.step(.01,[])
	check(m.bugs[2].alive,"Friendly fire should be off")
	m.flames.append({"cell":Vector2i(1,1),"owner":0,"time":.5}); m.step(.01,[])
	check(not m.bugs[0].alive,"Own bombs must still hurt")
	check(not m.ended,"A surviving teammate keeps team in round")
	m.bugs[2].alive = false; m.step(.01,[])
	check(m.ended and m.winner == 1,"Wrong team winner")
	m = fresh()
	for i in 4: m.bugs[i].alive = false
	m.step(.01,[]); check(m.ended and m.winner == -1,"Simultaneous elimination must draw")
	m = fresh(); m.age = 5000; m.step(.1,[])
	check(not m.ended,"There must be no time-based winner")
	var sizes_seen := {}
	var layouts_seen := {}
	for layout in ["Surprise me"]+Match.LAYOUTS:
		for size in ["Auto"]+Match.SIZES.keys():
			for players in [2,3,4]:
				for seed_value in 12:
					var roster := []
					for i in players: roster.append({})
					m = Match.new(); m.start(roster,{"arena":layout,"size":size},seed_value)
					sizes_seen[Vector2i(m.w,m.h)] = true; layouts_seen[m.layout] = true
					check(m.w % 2 == 1 and m.h % 2 == 1,"Garden sizes must be odd")
					if size == "Auto": check(Vector2i(m.w,m.h) in Match.AUTO_SIZES[players],"Auto size must follow player count")
					if layout != "Surprise me": check(m.layout == layout or m.layout == "Clover garden","Chosen layout ignored")
					for spawn in m.spawns():
						var exits := 0
						for d in Match.DIRS:
							if m.cells.get(spawn+d,1) == 0: exits += 1
						check(exits >= 2,"Spawn must have two exits: %s %dx%d"%[m.layout,m.w,m.h])
					for c in m.cells:
						if not m.inside(c): check(m.cells[c] == 1,"Border must be solid")
					# Destroying sand must leave a connected permanent arena.
					var first: Vector2i = m.spawns()[0]
					var seen := {first:true}; var queue := [first]
					while not queue.is_empty():
						var c: Vector2i = queue.pop_front()
						for d in Match.DIRS:
							var n: Vector2i = c+d
							if not seen.has(n) and m.cells.get(n,1) != 1: seen[n] = true; queue.append(n)
					for c in m.cells:
						if m.cells[c] != 1: check(seen.has(c),"Disconnected arena: %s"%m.layout)
	check(sizes_seen.size() >= 5,"Expected varied garden sizes")
	check(layouts_seen.size() == Match.LAYOUTS.size(),"Every layout must be reachable: %s"%[layouts_seen.keys()])
	# A result locks the winner, not the winner's controls or the arena effects.
	m = fresh(); clear_inside(m)
	for i in [1,2,3]: m.bugs[i].alive = false
	m.step(.01,[])
	check(m.ended and m.winner == 0,"Survivor should win")
	var before: Vector2 = m.bugs[0].pos
	m.flames.append({"cell":Vector2i(1,1),"owner":0,"time":.4})
	m.step(.1,[{"move":Vector2.RIGHT,"bomb":true}])
	check(m.bugs[0].pos.x > before.x,"Winner must remain controllable during results")
	check(m.bugs[0].alive and m.winner == 0,"Lingering hazards must not change the result")
	check(m.bombs.is_empty(),"Results input must not plant new bombs")
	m.step(1,[])
	check(m.flames.is_empty() and not m.bugs[0].moving,"Effects should expire and released input should stop movement")
	m = fresh(); clear_inside(m)
	for kind in ["capacity","range"]:
		m.pickups[Vector2i(1,1)] = {"kind":kind,"wait":0}
		var original: int = m.bugs[0][kind]
		m.step(.01,[])
		check(m.bugs[0][kind] == original+1,"Pickup must increase the correct stat")
		check(m.events.any(func(e): return e.type == "pickup" and e.who == 0 and e.kind == kind),"HUD needs the collector and pickup kind")
	var completed := 0
	for seed_value in 10:
		m = fresh(); m.start([{},{},{},{}],{},seed_value)
		for tick in 7200:
			var commands := []
			for i in m.bugs.size(): commands.append(m.bot(i,1.0/60) if m.bugs[i].alive else {})
			m.step(1.0/60,commands)
			if m.ended: completed += 1; break
	check(completed >= 8,"AI battles should progress to elimination; completed %d/10"%completed)
	print("Bombing Bugs: %d assertions, %d failures, %d/10 AI rounds completed"%[assertions,failures,completed])
	quit(1 if failures else 0)
