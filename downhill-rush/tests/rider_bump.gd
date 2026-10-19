extends SceneTree
## Two riders that run into each other must not hook together and stall (they
## used to grind to a halt side by side and then both topple). A hit knocks
## both off balance and costs some speed, but nobody stops or falls.

func _pair(c: Course, angle: float, gap: float, behind: float, va: float, vb: float) -> Dictionary:
	var a := Bike.new()
	var b := Bike.new()
	a.place(c, Course.START_LINE + 40.0 - behind, -gap * 0.5, va)
	b.place(c, Course.START_LINE + 40.0, gap * 0.5, vb)
	a.psi = angle
	b.psi = -angle
	var dt := 1.0 / 120.0
	var wobbled := false
	var t := 0.0
	var min_v := INF
	while t < 2.5:
		Bike.step(a, c, {}, dt)
		Bike.step(b, c, {}, dt)
		Bike.collide(a, b)
		wobbled = wobbled or (a.wobble > 0.0 and b.wobble > 0.0)
		if t > 0.3: min_v = minf(min_v, minf(a.v, b.v))
		t += dt
	return {"crashes": a.crashes + b.crashes, "wobbled": wobbled, "min_v": min_v,
		"apart": Vector2(a.s - b.s, a.d - b.d).length(), "va": a.v, "vb": b.v}

func _init() -> void:
	var c := Course.new(3, 900.0)
	var ok := true
	var side := _pair(c, 0.35, 1.2, 0.0, 9.0, 9.0)
	print("side by side: ", side)
	if side.crashes > 0 or not side.wobbled or side.min_v < 3.0: ok = false
	var rear := _pair(c, 0.0, 0.0, 2.0, 12.0, 6.0)
	print("rear-ender: ", rear)
	if rear.crashes > 0 or not rear.wobbled or rear.vb <= 6.0: ok = false
	print("rider bump OK" if ok else "rider bump FAILED")
	quit(0 if ok else 1)
