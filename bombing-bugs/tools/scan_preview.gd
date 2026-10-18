extends SceneTree
## Finds store clip moments: plays bot rounds for each garden and seed and prints
## when blasts, pickups, knock-outs and the end happen. Same round seeds as
## main.gd (--seed=N gives round 1 seed N+71).
##   godot --headless --path bombing-bugs --script tools/scan_preview.gd
const Match = preload("res://src/match.gd")

func _init() -> void:
	for arena in Match.LAYOUTS:
		for teams in ["Free-for-all","Teams"]:
			for seed_base in [431,500,600,700]:
				var m := Match.new()
				var roster := []
				for i in 4: roster.append({"name":"B%d"%i,"bot":true})
				m.start(roster,{"arena":arena,"teams":teams},seed_base+71)
				var log := []
				var booms := 0
				for k in 60*120:
					var inputs: Array = []
					for i in m.bugs.size(): inputs.append(m.bot(i,1.0/60) if m.bugs[i].alive else {})
					m.step(1.0/60,inputs)
					for e in m.events:
						if e.type == "boom": booms += 1
						if e.type in ["out","pickup"]: log.append("%s%d@%.1f" % ["X" if e.type == "out" else "+", e.get("who",-1), m.age])
					if m.ended: log.append("END@%.1f w%d" % [m.age,m.winner]); break
				print("%s | %dx%d | %s | seed %d | booms %d | %s" % [m.layout,m.w,m.h,teams,seed_base,booms," ".join(log)])
	quit()
