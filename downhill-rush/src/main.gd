extends Node3D
## Downhill Rush: everyone rides the same mountain on one screen. The camera
## follows the leader; drop off the bottom of the screen and you are out.
## Last rider standing, or first through the finish, takes the round.

enum Phase { JOIN, COUNTDOWN, RACE, ROUND_OVER, MATCH_OVER, IDLE }

const PALETTE := ["#ff7547", "#4cb5f5", "#ffd23f", "#7bd389", "#c77dff", "#ff5d8f", "#f2efe4", "#3ddbd9"]
const BOT_NAMES := ["Gnarly Gus", "Mudpie", "Turbo Tess", "Sir Skid", "Wobbles", "Dusty", "Bonk", "Pebble"]
const LENGTHS := {"short": 600.0, "medium": 800.0, "long": 1200.0}
const SETTINGS := [
	{"key": "rounds_to_win", "label": "Rounds to win", "kind": "number", "default": 3, "min": 1, "max": 9},
	{"key": "mountain", "label": "Mountain length (next round)", "kind": "choice", "default": "medium", "options": ["short", "medium", "long"]},
]
const MAX_RIDERS := 8
const PHYSICS_DT := 1.0 / 120.0

var phase := Phase.IDLE
var players: Array[Dictionary] = []
var course: Course
var mountain: MountainView
var camera: Camera3D
var sun: DirectionalLight3D
var hud: Hud
var round_number := 0
var rounds_to_win := 3
var mountain_length := "medium"
var phase_time := 0.0
var race_time := 0.0
var focus_s := 0.0
var focus_d := 0.0
var cam_yaw := 0.0
var round_winner := -1
var match_winner := -1
var managed := false
var session := ""
var demo := false
var bots_enabled := true
var _riders_root: Node3D
var _shot_path := ""
var _shot_time := 0.0
var _seed_override := -1
var _skip := 0.0
var _shot_phase := "race"
var _shot_frames := 0
var _shot_air := false
var _showcase := false
var _out_order := 0
var _rng := RandomNumberGenerator.new()
var _join_pads := {}


func _ready() -> void:
	_rng.randomize()
	GameNight.game_id = "downhill-rush"
	_parse_args()
	_build_environment()
	_riders_root = Node3D.new()
	add_child(_riders_root)
	hud = Hud.new()
	add_child(hud)
	if "--no-hud" in OS.get_cmdline_user_args(): hud.visible = false
	managed = GameNight.launched_by_daemon
	GameNight.prepared.connect(_on_prepared)
	GameNight.started.connect(_on_started)
	GameNight.paused.connect(func(_s: String) -> void: _set_paused(true))
	GameNight.resumed.connect(func(_s: String) -> void: _set_paused(false))
	GameNight.disposed.connect(_on_disposed)
	GameNight.roster_changed.connect(_on_roster)
	GameNight.setting_changed.connect(_on_setting)
	GameNight.declare_settings(SETTINGS)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_new_course()
	if managed:
		_enter(Phase.IDLE)
	elif demo:
		for i in 6: _add_bot()
		_start_match()
	else:
		_enter(Phase.JOIN)

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--demo": demo = true
		elif arg.begins_with("--shot="): _shot_path = arg.substr(7)
		elif arg.begins_with("--shot-time="): _shot_time = float(arg.substr(12))
		elif arg.begins_with("--seed="): _seed_override = int(arg.substr(7))
		elif arg.begins_with("--length="): mountain_length = arg.substr(9)
		elif arg.begins_with("--skip="): _skip = float(arg.substr(7))
		elif arg.begins_with("--shot-phase="): _shot_phase = arg.substr(13)
		elif arg == "--shot-air": _shot_air = true
		elif arg == "--showcase": _showcase = true


# ── Scene ────────────────────────────────────────────────────────────────────

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.62, 0.85)
	sky_mat.sky_horizon_color = Color(0.86, 0.88, 0.86)
	sky_mat.ground_horizon_color = Color(0.8, 0.84, 0.82)
	sky_mat.ground_bottom_color = Color(0.5, 0.58, 0.5)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.64, 0.78)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.85, 0.92)
	env.fog_density = 0.0022
	env.fog_sky_affect = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.15
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.5
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_blur = 1.5
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 52.0
	camera.near = 0.5
	camera.far = 400.0
	add_child(camera)
	camera.make_current()

func _new_course() -> void:
	var seed_value := _seed_override if _seed_override >= 0 else _rng.randi_range(1, 999999)
	if _seed_override >= 0: _seed_override += 1
	course = Course.new(seed_value, LENGTHS.get(mountain_length, 900.0))
	if mountain: mountain.queue_free()
	mountain = MountainView.new()
	add_child(mountain)
	mountain.build(course)
	hud.set_mountain(_mountain_name(seed_value), course)
	focus_s = Course.START_LINE + 2.0
	focus_d = 0.0
	cam_yaw = course.heading(10.0)
	_update_camera(1.0)

func _mountain_name(seed_value: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var a := ["Pine", "Granite", "Fox", "Misty", "Larch", "Eagle", "Bramble", "Echo", "Juniper", "Marmot", "Cloud", "Ember"]
	var b := ["Ridge", "Peak", "Hollow", "Run", "Gully", "Spur", "Crest", "Couloir", "Bluff", "Saddle"]
	return "%s %s" % [a[r.randi() % a.size()], b[r.randi() % b.size()]]


# ── Players ──────────────────────────────────────────────────────────────────

func _add_player(p_name: String, controls: Controls, bot: Bot, color: Color, id: String = "") -> Dictionary:
	var p := {"name": p_name, "controls": controls, "bot": bot, "color": color, "id": id,
		"bike": Bike.new(), "view": null, "wins": 0, "out": false, "offscreen": 0.0, "finished": false, "out_rank": 0}
	players.append(p)
	return p

func _add_bot() -> void:
	var index := players.size()
	_add_player(BOT_NAMES[index % BOT_NAMES.size()], null, Bot.new(_rng.randi(), _rng.randf_range(0.62, 0.95)), Color(PALETTE[index % PALETTE.size()]))

func _spawn_riders() -> void:
	for child in _riders_root.get_children():
		child.queue_free()
	var n := players.size()
	for i in n:
		var p: Dictionary = players[i]
		var row := i / 3
		var col := i % 3
		var across := mini(n - row * 3, 3)
		var d := (col - (across - 1) * 0.5) * 2.4
		p.bike = Bike.new()
		p.bike.place(course, Course.START_LINE - 2.0 - row * 3.2, d, 0.0)
		p.out = false
		p.finished = false
		p.offscreen = 0.0
		var view := RiderView.new()
		_riders_root.add_child(view)
		view.setup(p.color, p.name, i)
		view.pose(p.bike, course, 0.0)
		p.view = view
		if p.bot: p.bot.start_at(d)


# ── Flow ─────────────────────────────────────────────────────────────────────

func _enter(next: Phase) -> void:
	phase = next
	phase_time = 0.0
	hud.show_phase(phase, self)

func _start_match() -> void:
	for p in players: p.wins = 0
	round_number = 0
	match_winner = -1
	_start_round(false)

func _start_round(regenerate: bool = true) -> void:
	round_number += 1
	if regenerate: _new_course()
	_spawn_riders()
	focus_s = Course.START_LINE - 4.0
	race_time = 0.0
	round_winner = -1
	_out_order = 0
	hud.set_players(players)
	_enter(Phase.COUNTDOWN)

func _end_round(winner: int) -> void:
	round_winner = winner
	var outs := []
	for p in players: outs.append("%s:%s%s" % [p.name, "out%d" % p.out_rank if p.out else "in", "(%dx)" % p.bike.crashes])
	print("Round %d on %s after %.1fs: winner %s  %s" % [round_number, hud.title(), race_time, players[winner].name if winner >= 0 else "-", " ".join(outs)])
	if winner >= 0:
		players[winner].wins += 1
		if players[winner].wins >= rounds_to_win: match_winner = winner
	if managed and not session.is_empty(): GameNight.notify_finished(session)
	_enter(Phase.MATCH_OVER if match_winner >= 0 else Phase.ROUND_OVER)

func _process(delta: float) -> void:
	phase_time += delta
	match phase:
		Phase.JOIN: _join_input()
		Phase.COUNTDOWN:
			if phase_time >= 3.0:
				_enter(Phase.RACE)
				_fast_forward()
		Phase.ROUND_OVER:
			if phase_time >= 4.0: _start_round()
		Phase.MATCH_OVER:
			if phase_time >= 8.0: _start_match_again()
	# Names show at the start, then only for riders about to drop off screen.
	var names := phase != Phase.RACE or phase_time < 4.0
	var view_size := get_viewport().get_visible_rect().size
	for p in players:
		if p.view and is_instance_valid(p.view):
			p.view.pose(p.bike, course, delta)
			var danger := false
			if not names and not p.out:
				var sp := camera.unproject_position(p.view.position)
				danger = sp.y > view_size.y * 0.75 or sp.x < view_size.x * 0.08 or sp.x > view_size.x * 0.92
			p.view.tag.visible = names or danger
	_update_camera(delta)
	hud.update(self, delta)
	var shot_ready: bool = Phase.keys()[phase].to_lower() == _shot_phase and phase_time >= _shot_time
	if _shot_air and shot_ready:
		var flying := 0
		for p in players:
			if not p.out and not p.bike.grounded and p.bike.air_time > 0.25: flying += 1
		shot_ready = flying >= 2
	_shot_frames = _shot_frames + 1 if shot_ready else 0
	if not _shot_path.is_empty() and _shot_frames > 3:
		var image := get_viewport().get_texture().get_image()
		image.save_png(_shot_path)
		print("Saved screenshot ", _shot_path)
		_shot_path = ""
		get_tree().quit()

## Screenshot and test helper: simulate the opening of the race instantly.
func _fast_forward() -> void:
	var steps := int(_skip / PHYSICS_DT)
	_skip = 0.0
	for i in steps:
		_physics_process(PHYSICS_DT)
		_update_camera(PHYSICS_DT)
		phase_time += PHYSICS_DT
		if phase != Phase.RACE: break

func _start_match_again() -> void:
	_new_course()
	_start_match()

func _physics_process(_delta: float) -> void:
	if phase == Phase.COUNTDOWN:
		for p in players:
			if p.controls: p.controls.bike_input()  # Track edges so a held A doesn't hop at "go".
		return
	if phase != Phase.RACE and phase != Phase.ROUND_OVER and phase != Phase.MATCH_OVER: return
	var racing := phase == Phase.RACE
	if racing: race_time += PHYSICS_DT
	for p in players:
		if p.out: continue
		var b: Bike = p.bike
		var input := {}
		if p.finished: input = {"brake": 0.6}
		elif p.bot: input = p.bot.think(b, course, PHYSICS_DT)
		elif p.controls: input = p.controls.bike_input()
		if not racing and not p.finished: input = {"brake": 0.5}
		Bike.step(b, course, input, PHYSICS_DT)
	_bump_riders()
	if racing: _referee()

## Riders are solid: each bike is two circles, front and back wheel. Overlaps
## are pushed apart completely and the bikes trade momentum, so you can
## shoulder someone off the line, and a big hit knocks a rider off balance.
func _bump_riders() -> void:
	for i in players.size():
		var a: Dictionary = players[i]
		if a.out or a.bike.crashed: continue
		for j in range(i + 1, players.size()):
			var b: Dictionary = players[j]
			if b.out or b.bike.crashed: continue
			_collide(a.bike, b.bike)

func _collide(ba: Bike, bb: Bike) -> void:
	if absf(ba.y - bb.y) > 1.2: return
	if absf(ba.s - bb.s) > 3.0 or absf(ba.d - bb.d) > 3.0: return
	var ua := Vector2(cos(ba.psi), sin(ba.psi)) * Bike.HALF_LENGTH
	var ub := Vector2(cos(bb.psi), sin(bb.psi)) * Bike.HALF_LENGTH
	var pa := Vector2(ba.s, ba.d)
	var pb := Vector2(bb.s, bb.d)
	var best := INF
	var normal := Vector2.ZERO
	for sa in [-1.0, 1.0]:
		for sb in [-1.0, 1.0]:
			var delta: Vector2 = (pb + ub * sb) - (pa + ua * sa)
			var dist := delta.length()
			if dist < best:
				best = dist
				normal = delta / dist if dist > 0.001 else Vector2(0, 1)
	var overlap := Bike.RADIUS * 2.0 - best
	if overlap <= 0.0: return
	ba.s -= normal.x * overlap * 0.5; ba.d -= normal.y * overlap * 0.5
	bb.s += normal.x * overlap * 0.5; bb.d += normal.y * overlap * 0.5
	var va := Vector2(cos(ba.psi), sin(ba.psi)) * ba.v
	var vb := Vector2(cos(bb.psi), sin(bb.psi)) * bb.v
	var closing := (va - vb).dot(normal)
	if closing <= 0.0: return
	var impulse := closing * 0.75
	va -= normal * impulse
	vb += normal * impulse
	for pair in [[ba, va], [bb, vb]]:
		var bike: Bike = pair[0]
		var vel: Vector2 = pair[1]
		bike.v = maxf(0.0, vel.x) if vel.length() < 0.01 else vel.length()
		if vel.length() > 0.5: bike.psi = clampf(atan2(vel.y, maxf(vel.x, 0.1)), -1.45, 1.45)
		if closing > 3.5: bike.wobble = maxf(bike.wobble, 0.35)
		if closing > 7.5 and bike.invulnerable <= 0.0 and randf() < 0.5:
			Bike._crash(bike)

## Eliminations by the camera, finishes and the end of the round.
func _referee() -> void:
	var view := get_viewport().get_visible_rect().size
	var alive: Array[int] = []
	for i in players.size():
		var p: Dictionary = players[i]
		if p.out: continue
		var b: Bike = p.bike
		if b.s >= course.length and not p.finished:
			p.finished = true
			_end_round(i)
			return
		var at := course.world(b.s, b.d, b.y + 0.8)
		var screen := camera.unproject_position(at)
		var off := camera.is_position_behind(at) or screen.y < -12.0 or screen.y > view.y + 12.0 or screen.x < -12.0 or screen.x > view.x + 12.0
		# Only falling behind counts: a leader can never ride off the front.
		var gone := off and b.s < focus_s
		p.offscreen = p.offscreen + PHYSICS_DT if gone else 0.0
		if p.offscreen > 0.2:
			p.out = true
			_out_order += 1
			p.out_rank = _out_order
			hud.eliminated(p.name, p.color)
			hud.poof(screen.clamp(Vector2(30, 30), view - Vector2(30, 60)), p.color)
			if p.view: p.view.visible = false
			continue
		alive.append(i)
	if players.size() > 1 and alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else _last_out())
	elif players.size() == 1 and alive.is_empty():
		_end_round(-1)

func _last_out() -> int:
	var best := -1
	var rank := -1
	for i in players.size():
		if players[i].out_rank > rank:
			rank = players[i].out_rank
			best = i
	return best


# ── Camera ───────────────────────────────────────────────────────────────────

## A top-down camera that follows the leader down the mountain.
## It never backs up and creeps forward on its own, so stragglers drop off
## the bottom edge.
func _update_camera(delta: float) -> void:
	var lead := -INF
	var sum_d := 0.0
	var count := 0
	for p in players:
		if p.out: continue
		lead = maxf(lead, p.bike.s)
		sum_d += p.bike.d
		count += 1
	if phase in [Phase.COUNTDOWN, Phase.JOIN, Phase.IDLE]:
		focus_s = lerpf(focus_s, Course.START_LINE + 2.0, 1.0 - exp(-delta * 3.0))
	elif count > 0:
		var target := lead
		var follow := lerpf(focus_s, target, 1.0 - exp(-delta * 4.0))
		if phase == Phase.RACE:
			var pace := minf(2.0 + race_time * 0.1, 7.0)
			focus_s = maxf(focus_s + pace * delta, follow)
		else:
			focus_s = maxf(focus_s, follow)
	if count > 0:
		focus_d = lerpf(focus_d, clampf(sum_d / count, -7.0, 7.0), 1.0 - exp(-delta * 1.5))
	focus_s = minf(focus_s, course.total - 30.0)
	var yaw_target := course.heading(focus_s + 8.0)
	cam_yaw = lerp_angle(cam_yaw, yaw_target, 1.0 - exp(-delta * 1.8))
	var fwd := Vector3(sin(cam_yaw), 0, cos(cam_yaw))
	var focus := course.world(focus_s, focus_d, course.base_height(focus_s))
	# Top-down, tilted just enough that jumps and trees keep their shape.
	if _showcase and phase != Phase.RACE:
		# Screenshot helper: face the start grid to show off the riders.
		var grid := course.world(Course.START_LINE - 3.5, 0.0)
		var gate := mountain.get_node_or_null("Start")
		if gate: gate.visible = false
		camera.position = course.world(Course.START_LINE + 6.5, 5.0) + Vector3.UP * 5.5
		camera.look_at(grid + Vector3.UP * 1.6, Vector3.UP)
	else:
		# Downhill runs to the bottom right. The leader rides near that corner
		# and sees least of what's coming; the pack behind sees it all.
		var centre := course.world(focus_s - 11.0, focus_d, course.base_height(focus_s - 11.0)) if phase == Phase.RACE else focus
		var up_dir := -fwd.rotated(Vector3.UP, deg_to_rad(-45.0))
		camera.position = centre - up_dir * 17.0 + Vector3.UP * 28.0
		camera.look_at(centre, up_dir)
	sun.rotation = Vector3(deg_to_rad(-44.0), cam_yaw + deg_to_rad(140.0), 0)


# ── Standalone join screen ───────────────────────────────────────────────────

func _join_input() -> void:
	# Keyboard halves and every connected pad can join or start.
	var candidates: Array[Controls] = [Controls.new(Controls.Source.KEYS, 0), Controls.new(Controls.Source.KEYS, 1)]
	for device in Input.get_connected_joypads():
		candidates.append(Controls.new(Controls.Source.PAD, device))
	for c in candidates:
		var key := "%d:%d" % [c.source, c.id]
		var r := c.raw()
		var was: bool = _join_pads.get(key, true)
		_join_pads[key] = r.a or r.start
		if not (r.a or r.start) or was: continue
		var existing := -1
		for i in players.size():
			var pc: Controls = players[i].controls
			if pc and pc.source == c.source and pc.id == c.id: existing = i
		if existing == -1 and players.size() < MAX_RIDERS:
			var color := Color(PALETTE[players.size() % PALETTE.size()])
			var p := _add_player("P%d" % (players.size() + 1), c, null, color)
			c.pressed("a", true)
			hud.toast("%s joined (%s)" % [p.name, c.label()], color)
			hud.show_phase(phase, self)
		elif existing == 0 or r.start:
			_begin_standalone()
			return
	if Input.is_physical_key_pressed(KEY_B) and not _join_pads.get("bots", false):
		bots_enabled = not bots_enabled
		hud.show_phase(phase, self)
	_join_pads["bots"] = Input.is_physical_key_pressed(KEY_B)

func _begin_standalone() -> void:
	var humans := players.size()
	if bots_enabled:
		while players.size() < maxi(4, humans + 1) and players.size() < MAX_RIDERS:
			_add_bot()
	_start_match()

func _unhandled_input(event: InputEvent) -> void:
	if managed: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if phase == Phase.JOIN: get_tree().quit()
		else: _set_paused(not get_tree().paused)


# ── GameNight ────────────────────────────────────────────────────────────────

func _on_prepared(session_id: String, seats: Array, party_players: Array) -> void:
	session = session_id
	players.clear()
	var by_id := {}
	for pp in party_players: by_id[str(pp.get("id", ""))] = pp
	for seat in seats:
		var occupant: Dictionary = seat.get("occupant", {})
		var kind := str(occupant.get("kind", "empty"))
		var index := int(seat.get("index", players.size()))
		if players.size() >= MAX_RIDERS: break
		if kind == "local":
			var profile: Dictionary = by_id.get(str(occupant.get("player_id", "")), {})
			var color := _profile_color(profile, players.size())
			_add_player(str(profile.get("name", "Rider %d" % (index + 1))), Controls.new(Controls.Source.SEAT, index), null, color, str(occupant.get("player_id", "")))
		elif kind == "ai":
			_add_bot()
	if players.is_empty(): _add_bot()
	_new_course()
	_spawn_riders()
	hud.set_players(players)
	_enter(Phase.IDLE)
	GameNight._send({"type": "participation", "session": session_id, "instant_join": false})
	# Let one frame render before telling the host we're ready.
	await get_tree().process_frame
	await get_tree().process_frame
	GameNight.notify_ready(session_id)

func _profile_color(profile: Dictionary, index: int) -> Color:
	var raw := str(profile.get("color", ""))
	if raw.begins_with("#") and Color.html_is_valid(raw): return Color(raw)
	return Color(PALETTE[index % PALETTE.size()])

func _on_started(session_id: String) -> void:
	if session_id != session: return
	_set_paused(false)
	_start_match_from_prepared()

func _start_match_from_prepared() -> void:
	for p in players: p.wins = 0
	round_number = 0
	match_winner = -1
	_start_round(false)

func _on_disposed(_session_id: String) -> void:
	var summary := []
	for p in players: summary.append("%s %.1fm" % [p.name, p.bike.s])
	print("Downhill Rush: session disposed; riders at ", ", ".join(summary))
	session = ""
	_set_paused(false)
	players.clear()
	for child in _riders_root.get_children(): child.queue_free()
	_enter(Phase.IDLE)

func _on_roster(_seats: Array, party_players: Array, _presence: Array) -> void:
	var by_id := {}
	for pp in party_players: by_id[str(pp.get("id", ""))] = pp
	for i in players.size():
		var p: Dictionary = players[i]
		if p.id.is_empty() or not by_id.has(p.id): continue
		var profile: Dictionary = by_id[p.id]
		p.name = str(profile.get("name", p.name))
		if p.view: p.view.set_player_name(p.name)
	hud.set_players(players)

func _on_setting(key: String, value: Variant) -> void:
	if key == "rounds_to_win": rounds_to_win = clampi(int(value), 1, 9)
	elif key == "mountain" and LENGTHS.has(str(value)): mountain_length = str(value)

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	hud.set_paused(value)
