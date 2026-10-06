class_name Hud
extends CanvasLayer
## Everything drawn over the mountain: the run's progress strip, scores,
## countdown, eliminations and the warning arrows for riders about to drop
## off the bottom of the screen.

const INK := Color(0.12, 0.13, 0.17)
const PAPER := Color(0.99, 0.97, 0.92)

var _overlay: HudOverlay
var _title: Label
var _subtitle: Label
var _center: Label
var _center_sub: Label
var _scores: VBoxContainer
var _toasts: VBoxContainer
var _join: PanelContainer
var _join_text: Label
var _hint: Label
var _paused: Label
var _players: Array = []
var _course: Course


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_overlay = HudOverlay.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)
	_title = _label(34, PAPER)
	_title.position = Vector2(36, 22)
	root.add_child(_title)
	_subtitle = _label(22, PAPER.darkened(0.08))
	_subtitle.position = Vector2(38, 66)
	root.add_child(_subtitle)
	_scores = VBoxContainer.new()
	_scores.add_theme_constant_override("separation", 2)
	_scores.anchor_left = 1.0
	_scores.anchor_right = 1.0
	_scores.offset_left = -300
	_scores.offset_right = -30
	_scores.offset_top = 24
	_scores.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(_scores)
	_center = _label(120, PAPER)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.anchor_top = 0.32
	_center.anchor_bottom = 0.32
	_center.anchor_left = 0.0
	_center.anchor_right = 1.0
	root.add_child(_center)
	_center_sub = _label(32, PAPER)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.anchor_top = 0.5
	_center_sub.anchor_bottom = 0.5
	_center_sub.anchor_left = 0.0
	_center_sub.anchor_right = 1.0
	root.add_child(_center_sub)
	_hint = _label(22, PAPER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.offset_top = -60
	root.add_child(_hint)
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(36, 120)
	root.add_child(_toasts)
	_paused = _label(64, PAPER)
	_paused.text = "Paused"
	_paused.set_anchors_preset(Control.PRESET_CENTER)
	_paused.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused.anchor_left = 0.0
	_paused.anchor_right = 1.0
	_paused.visible = false
	root.add_child(_paused)
	_join = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.72)
	style.set_corner_radius_all(18)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 32
	style.content_margin_bottom = 32
	_join.add_theme_stylebox_override("panel", style)
	_join.set_anchors_preset(Control.PRESET_CENTER)
	_join.anchor_left = 0.5
	_join.anchor_right = 0.5
	_join.anchor_top = 0.5
	_join.anchor_bottom = 0.5
	_join.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_join.grow_vertical = Control.GROW_DIRECTION_BOTH
	_join_text = _label(30, PAPER)
	_join_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join.add_child(_join_text)
	_join.visible = false
	root.add_child(_join)

func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(6, size / 6))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func set_mountain(name: String, course: Course) -> void:
	_course = course
	_title.text = name
	_overlay.course = course

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
	match phase:
		0:
			var lines := ["DOWNHILL RUSH", "", "Press A (or Space / Enter) to join", ""]
			for p in main.players:
				lines.append("●  %s  ·  %s" % [p.name, p.controls.label() if p.controls else "bot"])
			if main.players.is_empty(): lines.append("Nobody yet")
			lines.append("")
			lines.append("Bots fill up to four riders: %s  (B toggles)" % ("on" if main.bots_enabled else "off"))
			lines.append("Rider 1: press A again to drop in")
			_join_text.text = "\n".join(lines)
		1:
			_hint.text = "Steer: stick   ·   Pedal: RT / X   ·   Brake: LT / B   ·   Hop: A   ·   In the air: stick up/down tilts"
		3:
			var w: int = main.round_winner
			if w >= 0:
				_center.text = "%s takes it!" % main.players[w].name
				_center.add_theme_color_override("font_color", main.players[w].color.lightened(0.2))
			else:
				_center.text = "Nobody made it"
				_center.add_theme_color_override("font_color", PAPER)
			_center_sub.text = "Next mountain coming up"
		4:
			var w: int = main.match_winner
			_center.text = "%s wins!" % main.players[w].name
			_center.add_theme_color_override("font_color", main.players[w].color.lightened(0.2))
			var ranked: Array = main.players.duplicate()
			ranked.sort_custom(func(a, b): return a.wins > b.wins)
			var lines := []
			for p in ranked: lines.append("%s   %d" % [p.name, p.wins])
			_center_sub.text = "\n".join(lines)

func update(main: Node, delta: float) -> void:
	var phase: int = main.phase
	_overlay.camera = main.camera
	_overlay.racing = phase == 2
	_overlay.queue_redraw()
	if phase == 1:
		var left := 3.0 - float(main.phase_time)
		_center.text = str(int(ceil(left))) if left > 0.0 else ""
		_center.add_theme_color_override("font_color", PAPER)
	elif phase == 2 and main.phase_time < 0.8:
		_center.text = "GO!"
		_center.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	elif phase == 2:
		_center.text = ""
	_subtitle.text = "" if main.round_number == 0 else "Round %d  ·  first to %d" % [main.round_number, main.rounds_to_win]
	_refresh_scores(main)
	for t in _toasts.get_children():
		t.set_meta("age", t.get_meta("age") + delta)
		var age: float = t.get_meta("age")
		t.modulate.a = clampf(3.0 - age, 0.0, 1.0)
		if age > 3.0: t.queue_free()

func _refresh_scores(main: Node) -> void:
	var players: Array = main.players
	while _scores.get_child_count() < players.size():
		_scores.add_child(_label(26, PAPER))
	while _scores.get_child_count() > players.size():
		var last := _scores.get_child(_scores.get_child_count() - 1)
		_scores.remove_child(last)
		last.queue_free()
	for i in players.size():
		var p: Dictionary = players[i]
		var l: Label = _scores.get_child(i)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pips := ""
		for k in main.rounds_to_win: pips += "●" if k < p.wins else "○"
		l.text = "%s  %s" % [p.name, pips]
		l.add_theme_color_override("font_color", p.color.lightened(0.15) if not p.out else Color(0.6, 0.6, 0.62))

func toast(text: String, color: Color) -> void:
	var l := _label(30, color.lightened(0.2))
	l.text = text
	l.set_meta("age", 0.0)
	_toasts.add_child(l)

func poof(at: Vector2, color: Color) -> void:
	_overlay.poofs.append({"at": at, "color": color, "t": 0.0})
