class_name PauseMenu
extends CanvasLayer
## The Start menu: pauses the race and lets anyone with a pad or keys restart
## it, or change difficulty, landscape, mountain length and bots. Choices
## take effect on the next mountain; "New race" builds one straight away.

signal closed
signal chosen(action: String)

const ROW_FONT := 40

var main: Node
var _panel: PanelContainer
var _rows: VBoxContainer
var _hint: Label
var _items: Array = []      ## {id, label, values?}
var _index := 0
var _held := {}             ## Edge detection per controller and button.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.1, 0.14, 0.92)
	style.set_corner_radius_all(26)
	style.set_border_width_all(6)
	style.border_color = Hud.SUN
	style.content_margin_left = 64
	style.content_margin_right = 64
	style.content_margin_top = 30
	style.content_margin_bottom = 34
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_override("font", Hud.font_display())
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Hud.PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	_hint = Label.new()
	_hint.add_theme_font_override("font", Hud.font_body())
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.add_theme_color_override("font_color", Hud.PAPER.darkened(0.3))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = "Stick or arrows to choose, A or Enter to pick, Start or Esc to close\nSettings apply from the next mountain; New race starts one now"
	column.add_child(_hint)
	visible = false

func open() -> void:
	_items = [
		{"id": "resume", "label": "Resume"},
		{"id": "new_race", "label": "New race"},
		{"id": "difficulty", "label": "Difficulty", "values": Course.DIFFICULTIES},
		{"id": "landscape", "label": "Landscape", "values": ["random"] + Course.BIOMES},
		{"id": "mountain", "label": "Mountain", "values": ["short", "medium", "long"]},
	]
	if not main.managed:
		_items.append({"id": "bots", "label": "Bots", "values": ["off", "on"]})
		_items.append({"id": "leave", "label": "Back to join screen"})
	_index = 0
	# Buttons already down (the Start that opened us) must be let go first.
	_held.clear()
	for c in _controls(): _poll(c, true)
	visible = true
	_draw()

func close() -> void:
	visible = false
	closed.emit()

func _value(id: String) -> String:
	match id:
		"difficulty": return main.difficulty
		"landscape": return main.landscape
		"mountain": return main.mountain_length
		"bots": return "on" if main.bots_enabled else "off"
	return ""

func _set_value(id: String, value: String) -> void:
	match id:
		"difficulty": main.difficulty = value
		"landscape": main.landscape = value
		"mountain": main.mountain_length = value
		"bots": main.bots_enabled = value == "on"

func _draw() -> void:
	for child in _rows.get_children(): child.queue_free()
	for i in _items.size():
		var item: Dictionary = _items[i]
		var row := Label.new()
		var on := i == _index
		var text: String = item.label
		if item.has("values"): text += ":  %s  %s  %s" % ["‹" if on else " ", _value(item.id).to_upper(), "›" if on else " "]
		row.text = ("▶  " if on else "    ") + text
		row.add_theme_font_override("font", Hud.font_bold())
		row.add_theme_font_size_override("font_size", ROW_FONT)
		row.add_theme_color_override("font_color", Hud.SUN if on else Hud.PAPER)
		_rows.add_child(row)

func _controls() -> Array:
	var out := []
	for p in main.players:
		# Keyboards are read as key events below.
		if p.controls and not p.bot and p.controls.source != Controls.Source.KEYS: out.append(p.controls)
	return out

func _process(_delta: float) -> void:
	if not visible: return
	for c in _controls():
		var e := _poll(c, false)
		if e.close: close(); return
		if e.move != 0: _move(e.move)
		if e.side != 0: _side(e.side)
		if e.pick: _pick(); return

## Fresh presses on one controller: menu up/down, left/right, pick, close.
func _poll(c: Controls, prime: bool) -> Dictionary:
	var r := c.raw()
	var stick: Vector2 = r.get("stick", Vector2(r.steer, 0.0))
	var up := stick.y < -0.5
	var down := stick.y > 0.5
	var buttons := {"up": up, "down": down, "left": r.steer < -0.5, "right": r.steer > 0.5, "a": r.a, "start": r.start}
	var fresh := {}
	var key := c.get_instance_id()
	for b in buttons:
		var was: bool = _held.get("%d%s" % [key, b], false)
		_held["%d%s" % [key, b]] = buttons[b]
		fresh[b] = buttons[b] and not was and not prime
	return {"move": int(fresh.down) - int(fresh.up), "side": int(fresh.right) - int(fresh.left), "pick": fresh.a, "close": fresh.start}

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: close()
		KEY_UP, KEY_W: _move(-1)
		KEY_DOWN, KEY_S: _move(1)
		KEY_LEFT, KEY_A: _side(-1)
		KEY_RIGHT, KEY_D: _side(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _pick()
		_: return
	get_viewport().set_input_as_handled()

func _move(step: int) -> void:
	_index = wrapi(_index + step, 0, _items.size())
	_draw()

func _side(step: int) -> void:
	var item: Dictionary = _items[_index]
	if not item.has("values"): return
	var values: Array = item.values
	var at := maxi(0, values.find(_value(item.id)))
	_set_value(item.id, values[wrapi(at + step, 0, values.size())])
	_draw()

func _pick() -> void:
	var item: Dictionary = _items[_index]
	if item.has("values"):
		_side(1)
		return
	visible = false
	if item.id == "resume": closed.emit()
	else: chosen.emit(item.id)
