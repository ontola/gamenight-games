class_name Hud
extends CanvasLayer
## Everything drawn over the mountain, in a sticker-and-signpaint style:
## Bungee Shade for the shouting, Bungee for names and scores, Lilita One
## for anything you actually have to read.

const INK := Color(0.11, 0.1, 0.14)
const PAPER := Color(0.99, 0.96, 0.88)
const SUN := Color(1.0, 0.78, 0.25)
const OUT_LINES := ["%s GOT DROPPED!", "BYE BYE %s!", "%s IS TOAST!", "%s ATE DIRT!", "SO LONG, %s!", "%s WENT HOME!"]
const WIN_LINES := ["%s SURVIVES!", "%s SENDS IT!", "%s RULES THE HILL!", "%s TAKES IT!"]

static var _fonts := {}

var _overlay: HudOverlay
var _title: Label
var _title_card: PanelContainer
var _subtitle: Label
var _center: Label
var _center_sub: Label
var _scores: VBoxContainer
var _toasts: VBoxContainer
var _join: PanelContainer
var _join_title: Label
var _join_text: Label
var _hint: Label
var _paused: Label
var _players: Array = []
var _course: Course
var _rng := RandomNumberGenerator.new()
var _last_count := -1
var _pop := 0.0


static func _font(path: String) -> FontFile:
	if not _fonts.has(path): _fonts[path] = load(path)
	return _fonts[path]

static func font_display() -> FontFile: return _font("res://assets/fonts/BungeeShade-Regular.ttf")
static func font_bold() -> FontFile: return _font("res://assets/fonts/Bungee-Regular.ttf")
static func font_body() -> FontFile: return _font("res://assets/fonts/LilitaOne-Regular.ttf")


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_overlay = HudOverlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	# Mountain name on a tilted sticker.
	_title = _label(30, INK, font_bold())
	_title_card = _sticker(_title, SUN, -3.0)
	_title_card.position = Vector2(30, 22)
	root.add_child(_title_card)
	_subtitle = _label(22, PAPER, font_body())
	_subtitle.position = Vector2(38, 86)
	root.add_child(_subtitle)
	_scores = VBoxContainer.new()
	_scores.add_theme_constant_override("separation", 6)
	_scores.anchor_left = 1.0
	_scores.anchor_right = 1.0
	_scores.offset_left = -320
	_scores.offset_right = -26
	_scores.offset_top = 22
	_scores.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_scores)
	_center = _label(150, SUN, font_display())
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.anchor_top = 0.28
	_center.anchor_bottom = 0.28
	_center.anchor_left = 0.0
	_center.anchor_right = 1.0
	_center.pivot_offset = Vector2(800, 90)
	root.add_child(_center)
	_center_sub = _label(36, PAPER, font_bold())
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.anchor_top = 0.52
	_center_sub.anchor_bottom = 0.52
	_center_sub.anchor_left = 0.0
	_center_sub.anchor_right = 1.0
	root.add_child(_center_sub)
	_hint = _label(26, PAPER, font_body())
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.offset_top = -64
	root.add_child(_hint)
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.position = Vector2(30, 128)
	root.add_child(_toasts)
	_paused = _label(90, PAPER, font_display())
	_paused.text = "PAUSED"
	_paused.set_anchors_preset(Control.PRESET_CENTER)
	_paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused.anchor_left = 0.0
	_paused.anchor_right = 1.0
	_paused.visible = false
	root.add_child(_paused)
	_join = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.1, 0.14, 0.86)
	style.set_corner_radius_all(26)
	style.set_border_width_all(6)
	style.border_color = SUN
	style.content_margin_left = 56
	style.content_margin_right = 56
	style.content_margin_top = 30
	style.content_margin_bottom = 36
	_join.add_theme_stylebox_override("panel", style)
	_join.anchor_left = 0.5
	_join.anchor_right = 0.5
	_join.anchor_top = 0.5
	_join.anchor_bottom = 0.5
	_join.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_join.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_join.add_child(column)
	_join_title = _label(84, SUN, font_display())
	_join_title.text = "DOWNHILL\nRUSH"
	_join_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_title.add_theme_constant_override("line_spacing", -18)
	column.add_child(_join_title)
	var tagline := _label(26, Color(0.98, 0.55, 0.45), font_bold())
	tagline.text = "LAST ONE ON SCREEN WINS"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)
	_join_text = _label(30, PAPER, font_body())
	_join_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_join_text)
	_join.visible = false
	root.add_child(_join)

func _label(size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 7) if color != INK else 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A label on a rounded, ink-bordered card, slightly askew like a sticker.
func _sticker(content: Control, bg: Color, degrees: float) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(12)
	style.set_border_width_all(4)
	style.border_color = INK
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 2
	style.shadow_offset = Vector2(4, 5)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 2
	card.add_theme_stylebox_override("panel", style)
	card.rotation_degrees = degrees
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if content is Label:
		content.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	card.add_child(content)
	return card

func set_mountain(name: String, course: Course) -> void:
	_course = course
	_title.text = name.to_upper()
	_overlay.course = course

func title() -> String:
	return _title.text

func set_players(players: Array) -> void:
	_players = players
	_overlay.players = players

func set_paused(value: bool) -> void:
	_paused.visible = value

func show_phase(phase: int, main: Node) -> void:
	_join.visible = phase == 0
	_center.text = ""
	_center_sub.text = ""
	_hint.text = ""
	_center_sub.anchor_top = 0.52
	_center.add_theme_font_size_override("font_size", 150)
	match phase:
		0:
			var lines := ["Press A, Space or Enter to join", ""]
			for p in main.players:
				lines.append("%s  ·  %s" % [p.name, p.controls.label() if p.controls else "bot"])
			if main.players.is_empty(): lines.append("Nobody on the hill yet")
			lines.append("")
			lines.append("Bots: %s   (press B to %s)" % (["on, filling up to four riders", "turn them off"] if main.bots_enabled else ["off", "add some"]))
			lines.append("Rider one: press A again to drop in")
			_join_text.text = "\n".join(lines)
		1:
			_hint.text = "Steer: stick    Pedal: RT / X    Brake: LT / B    Hop: A    Air: stick tilts the bike"
		3:
			var w: int = main.round_winner
			_center.add_theme_font_size_override("font_size", 96)
			if w >= 0:
				_center.text = WIN_LINES[_rng.randi() % WIN_LINES.size()] % main.players[w].name.to_upper()
				_center.add_theme_color_override("font_color", main.players[w].color.lightened(0.15))
			else:
				_center.text = "NOBODY MADE IT"
				_center.add_theme_color_override("font_color", PAPER)
			_center_sub.text = "NEXT MOUNTAIN INCOMING"
			_pop = 0.0
		4:
			var w: int = main.match_winner
			_center.add_theme_font_size_override("font_size", 110)
			_center.text = "%s\nWINS IT ALL!" % main.players[w].name.to_upper()
			_center.add_theme_color_override("font_color", main.players[w].color.lightened(0.15))
			var ranked: Array = main.players.duplicate()
			ranked.sort_custom(func(a, b): return a.wins > b.wins)
			var lines := []
			for p in ranked: lines.append("%s   %d" % [p.name.to_upper(), p.wins])
			_center_sub.text = "\n".join(lines)
			_center_sub.anchor_top = 0.62
			_pop = 0.0

func update(main: Node, delta: float) -> void:
	var phase: int = main.phase
	_overlay.camera = main.camera
	_overlay.racing = phase == 2
	_overlay.queue_redraw()
	_pop += delta
	if phase == 1:
		var left := 3.0 - float(main.phase_time)
		var n := int(ceil(left))
		_center.text = str(n) if left > 0.0 else ""
		if n != _last_count: _pop = 0.0
		_last_count = n
		_center.add_theme_color_override("font_color", [Color(0.6, 0.95, 0.4), SUN, Color(0.98, 0.45, 0.4)][clampi(n - 1, 0, 2)])
	elif phase == 2 and main.phase_time < 0.9:
		_center.text = "SEND IT!"
		_center.add_theme_color_override("font_color", SUN)
		if _last_count != 0: _pop = 0.0
		_last_count = 0
	elif phase == 2:
		_center.text = ""
		_last_count = -1
	# Big text lands with a little bounce.
	var s := 1.0 + 0.35 * exp(-_pop * 9.0) * cos(_pop * 22.0)
	_center.pivot_offset = _center.size * 0.5
	_center.scale = Vector2(s, s)
	_center.rotation_degrees = -4.0 * exp(-_pop * 6.0)
	_subtitle.text = "" if main.round_number == 0 else "Round %d · first to %d" % [main.round_number, main.rounds_to_win]
	_refresh_scores(main)
	for t in _toasts.get_children():
		t.set_meta("age", t.get_meta("age") + delta)
		var age: float = t.get_meta("age")
		t.modulate.a = clampf(3.0 - age, 0.0, 1.0)
		t.scale = Vector2.ONE * (1.0 + 0.3 * exp(-age * 10.0))
		if age > 3.0: t.queue_free()

## Riders in race order: whoever is furthest down the mountain on top, and
## the ones who are out below them, crossed through.
func _refresh_scores(main: Node) -> void:
	var players: Array = main.players
	while _scores.get_child_count() < players.size():
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		var name := _label(22, INK, font_bold())
		var card := _sticker(name, PAPER, 0.0)
		var strike := ColorRect.new()
		strike.color = Color(INK, 0.85)
		strike.anchor_left = -0.03
		strike.anchor_right = 1.03
		strike.anchor_top = 0.5
		strike.anchor_bottom = 0.5
		strike.offset_top = -2
		strike.offset_bottom = 3
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.add_child(strike)
		row.add_child(card)
		_scores.add_child(row)
	while _scores.get_child_count() > players.size():
		var last := _scores.get_child(_scores.get_child_count() - 1)
		_scores.remove_child(last)
		last.queue_free()
	var order: Array = players.duplicate()
	order.sort_custom(func(a, b):
		if a.out != b.out: return not a.out
		if a.out: return a.out_rank > b.out_rank
		return a.bike != null and b.bike != null and a.bike.s > b.bike.s)
	for i in order.size():
		var p: Dictionary = order[i]
		var card: PanelContainer = _scores.get_child(i).get_child(0)
		var l: Label = card.get_child(0)
		var pips := ""
		for k in main.rounds_to_win: pips += "★" if k < p.wins else "·"
		var place := "%d " % (i + 1) if main.phase == 2 and not p.out else ""
		l.text = "%s%s %s" % [place, p.name.to_upper(), pips]
		var style: StyleBoxFlat = card.get_theme_stylebox("panel")
		style.bg_color = p.color if not p.out else Color(0.55, 0.55, 0.58)
		card.rotation_degrees = 2.0 if i % 2 == 0 else -2.0
		card.modulate.a = 0.7 if p.out else 1.0
		l.get_child(0).visible = p.out

func toast(text: String, color: Color) -> void:
	var l := _label(26, INK, font_bold())
	l.text = text
	var card := _sticker(l, color, _rng.randf_range(-4.0, 3.0))
	card.set_meta("age", 0.0)
	_toasts.add_child(card)

func eliminated(name: String, color: Color) -> void:
	toast(OUT_LINES[_rng.randi() % OUT_LINES.size()] % name.to_upper(), color)

func poof(at: Vector2, color: Color) -> void:
	_overlay.poofs.append({"at": at, "color": color, "t": 0.0})
