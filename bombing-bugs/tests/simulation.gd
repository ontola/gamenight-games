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
	# The wilder power-ups.
	m = fresh(); clear_inside(m)
	m.bugs[0].pos = Vector2(1,3); m.bugs[0].kick = true
	m.bombs.append({"id":99,"cell":Vector2i(2,3),"owner":1,"range":1,"time":9.0,"passers":[],"slide":Vector2i.ZERO,"glide":0.0})
	m.cells[Vector2i(6,3)] = 2
	for tick in 120: m.step(1.0/60,[{"move":Vector2.RIGHT if tick < 10 else Vector2.ZERO}])
	check(m.bombs[0].cell == Vector2i(5,3) and m.bombs[0].slide == Vector2i.ZERO,"Kicked bomb must slide until the sand stops it: %s"%[m.bombs[0].cell])
	m = fresh(); clear_inside(m); m.bugs[0].pos = Vector2(1,3); m.cells[Vector2i(2,3)] = 2
	m.move_bug(0,Vector2.RIGHT,.5); check(m.bugs[0].pos.x < 1.3,"Sand must block a normal bug")
	m.bugs[0].ghost = true; m.move_bug(0,Vector2.RIGHT,.5); check(m.bugs[0].pos.x > 2,"A ghost bug walks through sand")
	m = fresh(); clear_inside(m); var slow := fresh(); clear_inside(slow)
	m.bugs[0].pos = Vector2(1,3); slow.bugs[0].pos = Vector2(1,3); m.collect(m.bugs[0],"speed")
	m.move_bug(0,Vector2.RIGHT,.5); slow.move_bug(0,Vector2.RIGHT,.5)
	check(m.bugs[0].pos.x > slow.bugs[0].pos.x+.1,"Speed must make a bug faster")
	m.collect(m.bugs[0],"mega"); check(m.bugs[0].range == Match.MAX_RANGE,"Mega fire maxes the range")
	m.collect(m.bugs[0],"range"); check(m.bugs[0].range == Match.MAX_RANGE,"A range pickup must not shrink mega fire")
	# Remote bombs wait for B, then all go off together.
	m = fresh(); clear_inside(m); m.bugs[0].pos = Vector2(1,3); m.collect(m.bugs[0],"remote"); m.collect(m.bugs[0],"capacity")
	m.step(.01,[{"bomb":true}]); m.bugs[0].pos = Vector2(3,3); m.step(.01,[{"bomb":true}])
	for tick in 600: m.step(1.0/60,[{}])
	check(m.bombs.size() == 2,"Remote bombs must not go off on their own")
	m.bugs[0].pos = Vector2(5,5); m.step(.01,[{"detonate":true}])
	check(m.bombs.is_empty() and m.events.any(func(e): return e.type == "detonate"),"B must set off every remote bomb")
	# Pierce blasts bore through a row of mounds; normal ones stop at the first.
	m = fresh(); clear_inside(m)
	for x in [3,4,5]: m.cells[Vector2i(x,3)] = 2
	check(Vector2i(4,3) not in m.blast(Vector2i(2,3),4,false,false),"A normal blast stops at the first mound")
	check(Vector2i(5,3) in m.blast(Vector2i(2,3),4,true,false),"A pierce blast bores through every mound in range")
	# Square bombs burn the full 3x3, but never rock.
	m = fresh(); clear_inside(m); m.cells[Vector2i(3,4)] = 1
	var sq: Array = m.blast(Vector2i(4,3),1,false,true)
	check(Vector2i(5,4) in sq and Vector2i(3,2) in sq and Vector2i(3,4) not in sq,"A square blast fills the 3x3 except rock")
	# Line bomb: planting again on your own bomb lays the rest in a row ahead.
	m = fresh(); clear_inside(m); m.bugs[0].pos = Vector2(1,3); m.bugs[0].heading = PI/2
	m.collect(m.bugs[0],"line"); m.bugs[0].capacity = 4
	m.step(.01,[{"bomb":true}]); m.step(.01,[{"bomb":true}])
	var cells_with_bombs: Array = m.bombs.map(func(b): return b.cell)
	check(m.bombs.size() == 4 and Vector2i(4,3) in cells_with_bombs,"A line bomb lays a row of bombs ahead: %s"%[cells_with_bombs])
	# Skull: a curse that wears off, and spreads by touch.
	m = fresh(); clear_inside(m); m.bugs[0].pos = Vector2(3,3); m.bugs[1].pos = Vector2(3.3,3)
	m.collect(m.bugs[0],"skull"); check(m.bugs[0].curse in Match.CURSES,"A skull curses the bug")
	m.bugs[0].curse = "slow"; m.step(.01,[{},{}])
	check(m.bugs[1].curse == "slow","A curse passes on by touch")
	m.bugs[1].pos = Vector2(7,7)
	for tick in int(Match.CURSE_TIME*60)+10: m.step(1.0/60,[{},{}])
	check(m.bugs[0].curse == "","A curse wears off")
	m = fresh(); clear_inside(m); var plain := fresh(); clear_inside(plain)
	m.bugs[0].pos = Vector2(1,3); plain.bugs[0].pos = Vector2(1,3); m.bugs[0].curse = "slow"; m.bugs[0].curse_time = 5
	m.step(.3,[{"move":Vector2.RIGHT}]); plain.step(.3,[{"move":Vector2.RIGHT}])
	check(m.bugs[0].pos.x < plain.bugs[0].pos.x-.2,"The slow curse slows a bug")
	# Bots armed with every bomb kind still finish their battles.
	var armed := 0
	for seed_value in 6:
		m = fresh(); m.start([{},{},{},{}],{},seed_value+40)
		for p in m.bugs:
			for kind in ["remote","pierce","square","line"]: m.collect(p,kind)
		for tick in 7200:
			var commands := []
			for i in m.bugs.size(): commands.append(m.bot(i,1.0/60) if m.bugs[i].alive else {})
			m.step(1.0/60,commands)
			if m.ended: armed += 1; break
	check(armed >= 4,"Bots with remote, pierce, square and line bombs should finish rounds; %d/6"%armed)
	var kinds := {}
	for i in 2000: kinds[m._power_kind()] = true
	check(kinds.size() == Match.POWER_ODDS.size(),"Every power-up must be able to drop")
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
