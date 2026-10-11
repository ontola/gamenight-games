extends SceneTree
## Ambient scenery stays outside the riding line and road visuals match the
## same analytically sampled asphalt used by the bikes.

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + message)
	if not ok: failures += 1

func _run() -> void:
	for biome in ["alpine", "forest", "autumn", "desert", "snow"]:
		var c := Course.new(42, 900.0, 1, biome)
		var view := MountainView.new()
		root.add_child(view)
		view.build(c)
		_check(not view._ambient.is_empty(), "%s has ambient wildlife" % biome)
		var safe := true
		var animated := false
		for animal in view._ambient:
			var sd: Vector2 = animal.get_meta("course_position")
			if absf(sd.y - c.trail_d(sd.x)) < c.trail_half(sd.x) + 3.0: safe = false
			if not animal.find_children("*", "CollisionObject3D", true, false).is_empty(): safe = false
			if c.surface(sd.x, sd.y) in [Course.Surface.WATER, Course.Surface.ROCK, Course.Surface.ASPHALT]: safe = false
			var head := animal.get_node("Head") as Node3D
			var before := head.rotation
			view._process(0.1)
			animated = animated or not head.rotation.is_equal_approx(before)
		_check(safe, "%s wildlife stays off the trail, water and asphalt without collision bodies" % biome)
		_check(animated, "%s wildlife animates" % biome)
		_check(not c.roads.is_empty() and not view.find_children("Asphalt", "MeshInstance3D", true, false).is_empty(), "%s renders its actual asphalt surfaces" % biome)
		_check(not view.find_children("RoadMarkings", "MeshInstance3D", true, false).is_empty(), "%s road is marked for two lanes" % biome)
		var cars := view.find_children("ParkedCar*", "MeshInstance3D", true, false)
		_check(not cars.is_empty(), "%s has a parked support car" % biome)
		for car in cars:
			_check(car.transform.basis.y.y > 0.8, "support car follows the ground upright")
			var sd: Vector2 = car.get_meta("course_position")
			_check(absf(sd.y - c.trail_d(sd.x)) > c.trail_half(sd.x) + 3.0 and not c.on_road(sd.x, sd.y, 1.0), "support car keeps road and both dirt-trail approaches clear")
		for road in c.roads:
			var across := c.world(c.road_line(road, 12.0), 12.0) - c.world(c.road_line(road, -12.0), -12.0)
			_check(absf(across.normalized().dot(c.forward(road.s))) < 0.5, "painted road crosses the fall line")
		print("    %d animals, %d parked cars" % [view._ambient.size(), view.find_children("ParkedCar*", "MeshInstance3D", true, false).size()])
		root.remove_child(view)
		view.free()
	print("SCENERY CHECKS PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
