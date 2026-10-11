extends Node3D
## Short, bounded world-space tyre strips. Contact loss ends a strip immediately.
const LIMIT := 240
const LIFETIME := 14.0
const WIDTH := 0.15
var segments: Array = []
var _last: Array = [null, null]
var _time := 0.0
var _placement := -1
var _mesh := ImmediateMesh.new()

func _ready() -> void:
	top_level = true
	transform = Transform3D.IDENTITY
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var view := MeshInstance3D.new()
	view.mesh = _mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)

func sample(b: Bike, c: Course, delta: float) -> void:
	if _placement != b.placement_id:
		_last = [null, null]
		_placement = b.placement_id
	_time += delta
	var changed := false
	while not segments.is_empty() and _time - segments[0].time > LIFETIME:
		segments.pop_front()
		changed = true
	for wheel in 2:
		var contact := _contact(b, c, 1.0 if wheel == 0 else -1.0)
		if contact.is_empty():
			_last[wheel] = null
			continue
		var point: Vector3 = contact.point
		if _last[wheel] != null:
			var distance: float = point.distance_to(_last[wheel])
			if distance < 0.12: continue
			# Respawns, course changes and large simulation skips never draw a bridge.
			if distance < 2.0:
				segments.append({"a": _last[wheel], "b": point, "time": _time, "color": contact.color})
				changed = true
		_last[wheel] = point
	while segments.size() > LIMIT: segments.pop_front()
	if changed: _redraw()

func _contact(b: Bike, c: Course, side: float) -> Dictionary:
	if not b.grounded or b.crashed or not b.brake_locked or b.v < 0.3: return {}
	var along := side * RiderView.WHEELBASE * RiderView.SCALE * 0.5
	var s := b.s + cos(b.psi) * cos(b.pitch) * along * Bike.path_scale(c, b.s, b.d)
	var d := b.d + sin(b.psi) * cos(b.pitch) * along
	var ground := c.height(s, d) + Bike._rock_lift(c, s, d)
	# Do not project a wheel hanging over a ledge down onto distant terrain.
	if absf(b.y + sin(b.pitch) * along - ground) > 0.3 or c.water_depth(s, d) > 0.1: return {}
	var color := Color("4c3829")
	if c.surface(s, d) == Course.Surface.ASPHALT: color = Color("202328")
	elif c.biome == "snow": color = Color("86929c")
	return {"point": c.world(s, d, ground + 0.025), "color": color}

func _redraw() -> void:
	_mesh.clear_surfaces()
	if segments.is_empty(): return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in segments:
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		var edge := (b - a).cross(Vector3.UP).normalized() * WIDTH * 0.5
		_mesh.surface_set_color(segment.color)
		for vertex in [a - edge, a + edge, b + edge, a - edge, b + edge, b - edge]:
			_mesh.surface_add_vertex(vertex)
	_mesh.surface_end()
