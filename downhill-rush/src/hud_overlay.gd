class_name HudOverlay
extends Control
## Immediate-mode HUD drawing: the progress strip and edge warnings.

var course: Course
var players: Array = []
var camera: Camera3D
var racing := false
var poofs: Array = []
var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	for p in poofs: p.t += delta
	poofs = poofs.filter(func(p): return p.t < 0.8)

func _draw() -> void:
	if course == null: return
	_draw_progress()
	if racing and camera: _draw_warnings()
	for p in poofs:
		var r: float = 20.0 + p.t * 140.0
		var col: Color = p.color
		col.a = 1.0 - p.t / 0.8
		draw_arc(p.at, r, 0, TAU, 32, col, 8.0 * (1.0 - p.t), true)
		draw_circle(p.at, r * 0.35, Color(1, 1, 1, col.a * 0.6))

## A strip across the top: the run from start to finish with each rider's
## position, so everyone can see who is leading and how far is left.
func _draw_progress() -> void:
	var w := size.x * 0.4
	var x0 := (size.x - w) * 0.5
	var y := 46.0
	draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(0.12, 0.13, 0.17, 0.7), 12.0, true)
	draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(0.99, 0.97, 0.92, 0.9), 6.0, true)
	# Features as small ticks so the run's shape is visible.
	for f in course.features:
		if not f.has("speed_min"): continue
		var fx: float = x0 + w * _progress(f.s0)
		draw_line(Vector2(fx, y - 9), Vector2(fx, y + 9), Color(1.0, 0.55, 0.2, 0.9), 3.0)
	# Finish flag.
	for k in 4:
		for j in 2:
			var c := Color.WHITE if (k + j) % 2 == 0 else Color(0.12, 0.13, 0.17)
			draw_rect(Rect2(x0 + w + 6 + k * 6, y - 12 + j * 6, 6, 6), c)
	for p in players:
		var b: Bike = p.bike
		var px := x0 + w * _progress(b.s)
		var col: Color = p.color
		if p.out:
			col = Color(0.55, 0.55, 0.58, 0.8)
		draw_circle(Vector2(px, y), 11.0, Color(0.12, 0.13, 0.17))
		draw_circle(Vector2(px, y), 8.0, col)

func _progress(s: float) -> float:
	return clampf((s - Course.START_LINE) / (course.length - Course.START_LINE), 0.0, 1.0)

## Riders falling behind, towards the top or left edge, get a pulsing arrow
## in their colour at the edge, pointing back into the screen.
func _draw_warnings() -> void:
	var centre := size * 0.5
	for p in players:
		if p.out: continue
		var b: Bike = p.bike
		var at := course.world(b.s, b.d, b.y + 0.8)
		if camera.is_position_behind(at): continue
		var sp := camera.unproject_position(at)
		var danger := clampf((size.y * 0.2 - sp.y) / (size.y * 0.2), 0.0, 1.0)
		danger = maxf(danger, clampf((size.x * 0.14 - sp.x) / (size.x * 0.14), 0.0, 1.0))
		if danger <= 0.0: continue
		var pulse := 0.6 + 0.4 * sin(_time * 14.0)
		var pos := sp.clamp(Vector2(30, 30), size - Vector2(30, 30))
		var dir := (centre - pos).normalized()
		var side := Vector2(-dir.y, dir.x)
		var col: Color = p.color
		col.a = danger * pulse
		var pts := PackedVector2Array([pos - side * 26.0, pos + side * 26.0, pos + dir * 36.0])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.12, 0.13, 0.17, col.a), 3.0, true)
