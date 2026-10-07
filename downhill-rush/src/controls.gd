class_name Controls
extends RefCounted
## Reads one rider's controls from a GameNight seat, a local pad or a
## keyboard half, and turns them into bike input with press edges.
##
## Pad: point the left stick where you want to go on screen, A hops, RT/X
## pedals, LT/B brakes. In the air the stick twists the bike and the brake
## lifts the nose.

enum Source { SEAT, PAD, KEYS }

const DEADZONE := 0.2
const KEYSETS := [
	{"left": KEY_A, "right": KEY_D, "pedal": KEY_W, "brake": KEY_S, "hop": KEY_SPACE},
	{"left": KEY_LEFT, "right": KEY_RIGHT, "pedal": KEY_UP, "brake": KEY_DOWN, "hop": KEY_ENTER},
]

var source := Source.KEYS
var id := 0                ## Seat index, pad device or keyset.
var _held := {}

func _init(p_source: Source, p_id: int) -> void:
	source = p_source
	id = p_id

## Raw state: steer, pedal, brake, pitch plus held buttons a, start.
func raw() -> Dictionary:
	match source:
		Source.SEAT:
			var frame := GameNight.frame_for_seat(id)
			var lx := GameNight.axis(frame, 0)
			var ly := GameNight.axis(frame, 1)
			if GameNight.button(frame, 12): lx = -1.0
			if GameNight.button(frame, 13): lx = 1.0
			var lt := maxf(0.0, GameNight.axis(frame, 4))
			var rt := maxf(0.0, GameNight.axis(frame, 5))
			return _aim(_shape(lx, ly, rt, lt, GameNight.button(frame, 0), GameNight.button(frame, 1),
				GameNight.button(frame, 2) or GameNight.button(frame, 5) or GameNight.button(frame, 10),
				GameNight.button(frame, 4) or GameNight.button(frame, 11), GameNight.button(frame, 7)), lx, ly)
		Source.PAD:
			var lx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
			var ly := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT): lx = -1.0
			if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT): lx = 1.0
			return _aim(_shape(lx, ly, Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT), Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT),
				Input.is_joy_button_pressed(id, JOY_BUTTON_A), Input.is_joy_button_pressed(id, JOY_BUTTON_B),
				Input.is_joy_button_pressed(id, JOY_BUTTON_X) or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER) or Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP),
				Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN),
				Input.is_joy_button_pressed(id, JOY_BUTTON_START)), lx, ly)
		_:
			var k: Dictionary = KEYSETS[id]
			var lx := float(Input.is_physical_key_pressed(k.right)) - float(Input.is_physical_key_pressed(k.left))
			var up := Input.is_physical_key_pressed(k.pedal)
			var down := Input.is_physical_key_pressed(k.brake)
			var hop := Input.is_physical_key_pressed(k.hop)
			if id == 1: hop = hop or Input.is_physical_key_pressed(KEY_KP_ENTER) or Input.is_physical_key_pressed(KEY_KP_0)
			return _shape(lx, (-1.0 if up else 0.0) + (1.0 if down else 0.0), 1.0 if up else 0.0, 1.0 if down else 0.0, hop, false, false, false, false)

func _shape(lx: float, ly: float, rt: float, lt: float, a: bool, b: bool, x: bool, lb: bool, start: bool) -> Dictionary:
	if absf(lx) < DEADZONE: lx = 0.0
	if absf(ly) < DEADZONE: ly = 0.0
	var pedal := maxf(rt, 1.0 if x else 0.0)
	var brake := maxf(lt, 1.0 if (b or lb) else 0.0)
	return {"steer": lx, "pedal": pedal if pedal > 0.25 else 0.0, "brake": brake if brake > 0.25 else 0.0, "a": a, "start": start}

## The stick as a direction on screen; the game turns it into steering.
func _aim(r: Dictionary, lx: float, ly: float) -> Dictionary:
	r["stick"] = Vector2(lx, ly)
	return r

## Bike input for this physics step, with `hop` true only on the press.
func bike_input() -> Dictionary:
	var r := raw()
	r["hop"] = pressed("a", r.a)
	return r

## True once when `button` goes down.
func pressed(button: String, down: bool) -> bool:
	var was: bool = _held.get(button, false)
	_held[button] = down
	return down and not was

func label() -> String:
	match source:
		Source.PAD: return "Pad %d" % (id + 1)
		Source.KEYS: return "WASD + Space" if id == 0 else "Arrows + Enter"
	return "Seat %d" % (id + 1)
