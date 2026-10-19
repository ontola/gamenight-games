extends SceneTree
## Cars on the roads, bolting wildlife and charging bears all knock riders off.

func _init() -> void:
	var ok := true
	var c: Course = null
	for seed_value in range(1, 60):
		var t := Course.new(seed_value, 900.0, 1, "forest")
		if not t.roads.is_empty():
			c = t
			break
	var view := MountainView.new()
	view.course = c
	var traffic := Traffic.new(c, view)
	root.add_child(view)
	view.add_child(traffic)
	var dt := 1.0 / 120.0

	# A rider waiting on the road gets hit by the next car.
	var road: Dictionary = c.roads[0]
	var b := Bike.new()
	var d := c.trail_d(road.s)
	b.place(c, road.s, d, 0.0)
	var t := 0.0
	while t < 20.0 and not b.crashed:
		b.s = c.road_line(road, b.d) - 1.45
		traffic.step([b], dt)
		t += dt
	print("car: crashed=%s reason=%s after %.1fs" % [b.crashed, b.crash_reason, t])
	if not b.crashed or b.crash_reason != "car": ok = false
	if b.crashed:
		# Thrown hard enough to bleed.
		for k in 120: Bike.step(b, c, {}, dt)
		print("car: %d blood splats" % b.rider_body.splats.size() if b.rider_body else "car: rider back up")
		if b.rider_body and b.rider_body.splats.is_empty(): ok = false

	# A bear charges a rider standing near it.
	if traffic.bears.is_empty():
		print("no bear"); ok = false
	else:
		var bear: Dictionary = traffic.bears[0]
		var r := Bike.new()
		r.place(c, bear.s + 6.0, bear.d, 0.0)
		t = 0.0
		while t < 5.0 and not r.crashed:
			traffic.step([r], dt)
			t += dt
		print("bear: crashed=%s reason=%s after %.1fs" % [r.crashed, r.crash_reason, t])
		if not r.crashed or r.crash_reason != "bear": ok = false

	# Riding fast into a deer puts you down; it bolts first if it sees you.
	var deer := Node3D.new()
	var head := Node3D.new(); head.name = "Head"; deer.add_child(head)
	deer.set_meta("course_position", Vector2(300.0, c.trail_d(300.0)))
	deer.set_meta("kind", "deer"); deer.set_meta("hare", false); deer.set_meta("phase", 0.0); deer.set_meta("ground_y", 0.0)
	view.add_child(deer)
	view._ambient.append(deer)
	var moved := false
	var start: Vector2 = deer.get_meta("course_position")
	var rb := Bike.new()
	rb.place(c, 291.0, c.trail_d(300.0), 12.0)
	traffic.step([rb], dt)
	moved = deer.get_meta("course_position") != start
	print("deer bolts when a rider comes close: %s" % moved)
	if not moved: ok = false
	# Now one it never saw coming: right in front of the wheel.
	traffic._fleeing.clear()
	deer.set_meta("course_position", Vector2(rb.s + 0.5, rb.d))
	traffic.step([rb], dt)
	print("deer hit at 12 m/s: crashed=%s reason=%s" % [rb.crashed, rb.crash_reason])
	if not rb.crashed or rb.crash_reason != "animal": ok = false

	print("traffic OK" if ok else "traffic FAILED")
	quit(0 if ok else 1)
