extends Node3D
const PLAY_FONT = preload("res://assets/fonts/DynaPuff.ttf")
const Match = preload("res://src/match.gd")
const Garden = preload("res://src/garden.gd")
const BoomSound = preload("res://src/boom_sound.gd")
const PickupSound = preload("res://src/pickup_sound.gd")
const Bug = preload("res://src/bug.gd")
const Clay = preload("res://src/clay.gd")
const SETTINGS := [
	{"key":"ai_players","label":"AI bugs (next round)","kind":"number","default":3,"min":0,"max":3},
	{"key":"teams","label":"Teams (next round)","kind":"choice","default":"Free-for-all","options":["Free-for-all","Teams"]},
	{"key":"arena","label":"Garden (next round)","kind":"choice","default":"Surprise me","options":["Surprise me","Clover garden","Seed crossroads","Pebble islands","Scattered stones","Boulder field"]},
	{"key":"size","label":"Garden size (next round)","kind":"choice","default":"Auto","options":["Auto","Small","Medium","Large"]},
	{"key":"friendly_fire","label":"Friendly fire (next round)","kind":"toggle","default":false},
	{"key":"fuse","label":"Fuse, tenths of a second (next round)","kind":"number","default":24,"min":15,"max":40},
	{"key":"speed","label":"Speed, tenths of a tile/s (next round)","kind":"number","default":32,"min":20,"max":50},
	{"key":"crates","label":"Sand cover % (next round)","kind":"number","default":55,"min":20,"max":75},
	{"key":"pickups","label":"Power-ups (next round)","kind":"toggle","default":true},
	{"key":"sound","label":"Sound effects (live)","kind":"toggle","default":true},
]
# The menu shows the everyday choices; the fiddly ones sit one level down.
const BASIC_SETTINGS := ["ai_players","teams","arena","size"]
const ADVANCED_SETTINGS := ["friendly_fire","fuse","speed","crates","pickups","sound"]
const PALETTE := [Color("ef7056"),Color("6fc4d1"),Color("f7cd52"),Color("b6a1e6")]
var sim := Match.new()
var garden: Node3D
var camera: Camera3D
var views: Array[Node3D] = []
var settings: Dictionary = Match.DEFAULTS.duplicate()
var roster: Array = []
var host_seats: Array = []
var host_players: Array = []
var managed := false
var session := ""
var active := false
var host_paused := false
var menu_open := false
var initial_menu := true
var countdown := 0.0
var result_time := 0.0
var round_index := 0
var held := {}
var menu_index := 0
var menu_rows: Array[Button] = []
var menu_items: Array = []
var menu_page := "main"
var menu_list: VBoxContainer
var menu_help: Label
var overlay: PanelContainer
var menu_title: Label
var banner: Label
var hint: Label
var badges: HBoxContainer
var title: TextureRect
## The big name over the garden while the first round counts down (the only
## start screen a GameNight launch has, since the host skips the menu).
var title_card: TextureRect
var intro := true
var sound: AudioStreamPlayer
var clips := {}
var boom_player: AudioStreamPlayer
## Growing Guns explosion clips per size bucket, synthesised off the main thread.
var boom_clips: Array = []
var boom_task := -1
var frame_count := 0
var shot_path := ""
var demo := false
var seed_base := 431
var skip := 0.0
var rng := RandomNumberGenerator.new()
var ui_clock := 0.0

func _ready() -> void:
	rng.randomize(); settings.sound = true
	managed = GameNight.launched_by_daemon
	# A hand-started preview stays offline: the SDK only connects when
	# GameNight launched us (or GAMENIGHT_ADDR asks for a development host).
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo": demo = true
		if arg.begins_with("--screenshot="): shot_path = arg.substr(13)
		# Store clip takes (tools/capture_preview.sh): a fixed round, set up and fast-forwarded.
		if arg.begins_with("--seed="): seed_base = int(arg.substr(7))
		if arg.begins_with("--arena="): settings.arena = arg.substr(8)
		if arg == "--teams": settings.teams = "Teams"
		if arg.begins_with("--size="): settings.size = arg.substr(7)
		if arg.begins_with("--skip="): skip = float(arg.substr(7))
	GameNight.game_id = "bombing-bugs"
	GameNight.prepared.connect(_prepared)
	GameNight.started.connect(func(_id: String): active = true; host_paused = false; countdown = 2.0)
	GameNight.paused.connect(func(_id: String): host_paused = true; _trace("pause"))
	GameNight.resumed.connect(func(_id: String): _trace("resume"); host_paused = false)
	GameNight.disposed.connect(func(_id: String): _trace("dispose"); active = false; session = ""; menu_open = false; overlay.hide())
	GameNight.setting_changed.connect(_setting)
	GameNight.roster_changed.connect(_roster_changed)
	GameNight.declare_settings(SETTINGS)
	garden = Garden.new(); add_child(garden); garden.build()
	camera = Camera3D.new(); add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.keep_aspect = Camera3D.KEEP_WIDTH; camera.size = 18.0
	camera.current = true; _frame_camera(13,11)
	_build_ui(); _build_audio()
	_warm_up_shaders()
	if managed:
		banner.text = "Getting the garden ready…"
	else:
		_new_round()
		if demo:
			for p in sim.bugs: p.bot = true
			active = true; countdown = 0
			_fast_forward(skip)
		else: _open_menu(true)

func _fast_forward(seconds: float) -> void:
	# Bots play on unseen at the physics rate, so the take opens mid-round.
	for _i in int(seconds*60):
		if sim.ended: break
		var inputs: Array = []
		for i in sim.bugs.size(): inputs.append(sim.bot(i,1.0/60) if sim.bugs[i].alive else {})
		sim.step(1.0/60,inputs)
		garden.sync(sim,1.0/60)
	_update_badges()

func _local_roster() -> Array:
	var out: Array = []
	var devices := Input.get_connected_joypads()
	if devices.is_empty(): out.append({"name":"Ladybug","source":"keys","device":0,"bot":false,"color":PALETTE[0]})
	else:
		for device in devices.slice(0,4): out.append({"name":"Player %d" % (out.size()+1),"source":"pad","device":device,"bot":false,"color":PALETTE[out.size()]})
	return out

func _make_roster() -> Array:
	var out: Array = []
	if not managed: out = _local_roster()
	else:
		for seat in host_seats:
			var occupant: Dictionary = seat.get("occupant",{})
			if out.size() >= 4: break
			if occupant.get("kind") == "local":
				var profile := {}
				for pp in host_players:
					if pp.get("id") == occupant.get("player_id"): profile = pp; break
				out.append({"id":occupant.get("player_id",""),"name":profile.get("name","Player %d"%(out.size()+1)),"source":"seat","device":int(seat.get("index",out.size())),"bot":false,"profile":profile,"color":Color.from_string(str(profile.get("color","")),PALETTE[out.size()])})
			elif occupant.get("kind") == "ai": out.append({"name":"AI bug","bot":true,"color":PALETTE[out.size()]})
	var humans := out.size()
	for i in mini(int(settings.ai_players),4-humans):
		out.append({"name":["Pip · AI","Nibbles · AI","Buzz · AI","Bean · AI"][out.size()],"bot":true,"color":PALETTE[out.size()]})
	return out

func _new_round() -> void:
	roster = _make_roster()
	if roster.is_empty():
		banner.text = "Connect a controller to join"; active = false; return
	round_index += 1
	sim.start(roster,settings,seed_base+round_index*71)
	garden.reset(sim)
	_frame_camera(sim.w,sim.h)
	for view in views: view.queue_free()
	views.clear()
	for i in sim.bugs.size():
		var v := Bug.new(); add_child(v); v.build(i,sim.bugs[i].color); views.append(v)
		v.position = garden.world(sim.bugs[i].pos)
	_update_badges()
	result_time = 0; countdown = 3.0 if intro else 2.0
	# Controls speak for themselves; the hint line only returns between rounds.
	hint.text = ""
	if demo:
		for p in sim.bugs: p.bot = true

## Three-quarter view (Garden.CAM_PITCH/CAM_YAW) sized so the whole pit and its
## bank fit on screen with the same breathing room for every garden size.
func _frame_camera(cols: int, rows: int) -> void:
	var hx := (cols-2)*.5+1.2; var hz := (rows-2)*.5+1.2
	var pitch := deg_to_rad(Garden.CAM_PITCH); var yaw := deg_to_rad(Garden.CAM_YAW)
	var back := Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))
	# Nudge the aim down a little so the player badges along the top have room.
	var target := Vector3(0,0,-.35)
	camera.position = target+back*30.0; camera.look_at(target)
	var right := camera.global_basis.x; var up := camera.global_basis.y
	var w := 0.0; var h := 0.0
	for c in [Vector3(-hx,0,-hz),Vector3(hx,0,-hz),Vector3(hx,0,hz),Vector3(-hx,0,hz),Vector3(-hx,.6,-hz),Vector3(hx,.6,-hz)]:
		w = maxf(w,absf(c.dot(right))); h = maxf(h,absf((c-target).dot(up)))
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x/maxf(view.y,1.0)
	camera.size = maxf(w*2.0,h*2.0*aspect)*1.12

func _prepared(id: String, seats: Array, players: Array) -> void:
	session = id; host_seats = seats; host_players = players; active = false; host_paused = false
	menu_open = false; overlay.hide(); initial_menu = false
	GameNight.notify_progress(id,25,"Planting the garden")
	_new_round()
	GameNight.notify_progress(id,90,"Bugs ready")
	await get_tree().process_frame
	await get_tree().process_frame
	GameNight.notify_ready(id)
	_trace("ready")

func _trace(event: String) -> void:
	if "--test-state" not in OS.get_cmdline_user_args(): return
	var positions := []
	for p in sim.bugs: positions.append([p.pos.x,p.pos.y])
	print("TEST_STATE "+JSON.stringify({"event":event,"age":sim.age,"positions":positions,"menu":menu_open,"options":sim.settings,"pending":settings}))

func _roster_changed(seats: Array, players: Array, _presence: Array) -> void:
	host_seats = seats; host_players = players
	for bug in sim.bugs:
		for profile in players:
			if bug.get("id", "missing") == profile.get("id",""):
				bug.name = profile.get("name",bug.name); bug.profile = profile
	_update_badges()

func _setting(key: String, value: Variant) -> void:
	for spec in SETTINGS:
		if spec.key != key: continue
		match spec.kind:
			"number": settings[key] = clampi(int(value),spec.min,spec.max)
			"choice":
				if value in spec.options: settings[key] = value
			"toggle":
				if value is bool: settings[key] = value
	if menu_open: _refresh_menu()

func _raw(p: Dictionary) -> Dictionary:
	var dir := Vector2.ZERO
	var a := false; var start := false; var b := false; var back := false
	if p.get("source") == "seat":
		var f := GameNight.frame_for_seat(p.device)
		dir = Vector2(GameNight.axis(f,0),GameNight.axis(f,1))
		if GameNight.button(f,10): dir.y = -1
		if GameNight.button(f,11): dir.y = 1
		if GameNight.button(f,12): dir.x = -1
		if GameNight.button(f,13): dir.x = 1
		a = GameNight.button(f,0); b = GameNight.button(f,1); start = GameNight.button(f,7); back = GameNight.button(f,6)
	elif p.get("source") == "pad":
		var id: int = p.device
		dir = Vector2(Input.get_joy_axis(id,JOY_AXIS_LEFT_X),Input.get_joy_axis(id,JOY_AXIS_LEFT_Y))
		if Input.is_joy_button_pressed(id,JOY_BUTTON_DPAD_UP): dir.y = -1
		if Input.is_joy_button_pressed(id,JOY_BUTTON_DPAD_DOWN): dir.y = 1
		if Input.is_joy_button_pressed(id,JOY_BUTTON_DPAD_LEFT): dir.x = -1
		if Input.is_joy_button_pressed(id,JOY_BUTTON_DPAD_RIGHT): dir.x = 1
		a = Input.is_joy_button_pressed(id,JOY_BUTTON_A); b = Input.is_joy_button_pressed(id,JOY_BUTTON_B); start = Input.is_joy_button_pressed(id,JOY_BUTTON_START); back = Input.is_joy_button_pressed(id,JOY_BUTTON_BACK)
	else:
		dir = Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		a = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER)
		start = Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_P)
		b = Input.is_physical_key_pressed(KEY_BACKSPACE) or Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SHIFT)
	if dir.length() < .2: dir = Vector2.ZERO
	return {"move":dir.limit_length(),"a":a,"start":start,"b":b,"back":back}

func _edge(key: String, down: bool) -> bool:
	var old: bool = held.get(key,false); held[key] = down; return down and not old

func _physics_process(dt: float) -> void:
	if managed and (not active or host_paused): return
	var inputs: Array = []
	var nav := Vector2.ZERO
	var confirm := false; var pause_press := false; var close := false
	for i in sim.bugs.size():
		var p: Dictionary = sim.bugs[i]
		if p.bot: inputs.append({}); continue
		var r := _raw(p)
		var pressed := _edge("a%d"%i,r.a)
		pause_press = _edge("start%d"%i,r.start) or pause_press
		close = _edge("b%d"%i,r.b) or close
		if _edge("back%d"%i,r.back) and managed: GameNight.request_overlay(); return
		confirm = confirm or pressed
		if r.move.length() > nav.length(): nav = r.move
		# B sets off remote bombs (the same press also closes menus, which pause play).
		inputs.append({"move":r.move,"bomb":pressed,"detonate":_edge("det%d"%i,r.b)})
	if pause_press:
		if menu_open: _close_menu()
		else: _open_menu(false)
		return
	var up := _edge("up",nav.y < -.5)
	var down := _edge("down",nav.y > .5)
	var left := _edge("left",nav.x < -.5)
	var right := _edge("right",nav.x > .5)
	if menu_open:
		if up or down: menu_index = posmod(menu_index+(1 if down else -1),menu_rows.size()); _refresh_menu()
		if (left or right) and menu_items[menu_index].has("key"): _menu_action(menu_index,1 if right else -1)
		if confirm: _menu_action(menu_index,1)
		if close:
			if menu_page == "advanced": _show_page("main")
			else: _close_menu()
		return
	if not active: return
	if countdown > 0:
		countdown -= dt; banner.text = "%s  ·  %d" % [sim.layout,ceili(countdown)] if countdown > .4 else "SCUTTLE!"; return
	if sim.ended:
		result_time += dt
		if (confirm and result_time > .7) or result_time > 6:
			_new_round()
			return
		for i in sim.bugs.size():
			if sim.bugs[i].bot and sim.bugs[i].alive: inputs[i] = sim.bot(i,dt)
		sim.step(dt,inputs)
		garden.sync(sim,dt)
		return
	for i in sim.bugs.size():
		if sim.bugs[i].bot and sim.bugs[i].alive: inputs[i] = sim.bot(i,dt)
	sim.step(dt,inputs)
	garden.sync(sim,dt)
	var blasted := 0
	for event in sim.events:
		if event.type == "boom": blasted += event.cells.size(); continue
		if event.type == "plant" and event.who < views.size(): views[event.who].lay()
		if event.type == "pickup": _play_sound("pickup:"+str(event.kind))
		elif event.type in clips: _play_sound(event.type)
		if event.type in ["out","pickup","cursed","cured"]: _update_badges(int(event.get("who",-1)) if event.type == "pickup" else -1)
	# Chained bombs in one tick are one bigger bang: louder and deeper with every burning cell.
	if blasted > 0: _play_boom(blasted)
	if sim.ended:
		banner.text = "A garden-sized draw!" if sim.winner == -1 else _winner_name()+" wins!"
		hint.text = "A / Space  ·  Another round     Start  ·  Options"
		_update_badges()
		if managed: GameNight.notify_finished(session)
	else: banner.text = ""

func _winner_name() -> String:
	if sim.settings.teams == "Teams": return "Team %d" % (sim.winner+1)
	for p in sim.bugs:
		if p.team == sim.winner: return p.name
	return "Bug"

func _process(dt: float) -> void:
	if host_paused: return
	ui_clock += dt
	if title_card:
		if active and countdown <= 0: intro = false
		title_card.visible = intro and not menu_open and (managed or active)
		title_card.modulate.a = clampf(countdown/.5,0,1) if active else 1.0
	# A little hand-cut wobble on the celebration, never on names or stats.
	banner.pivot_offset = banner.size*.5
	banner.rotation = sin(ui_clock*2.6)*.012 if sim.ended else 0.0
	banner.scale = Vector2.ONE*(1.0+sin(ui_clock*3)*.015) if sim.ended else Vector2.ONE
	for i in mini(views.size(),sim.bugs.size()):
		var p: Dictionary = sim.bugs[i]
		var pos: Vector3 = garden.world(p.pos)
		views[i].position.x = pos.x; views[i].position.z = pos.z
		views[i].cursed = p.curse != ""
		views[i].animate(dt,p.moving and not menu_open,p.heading,p.alive)
	# Blasts jolt the camera, harder for bigger ones; clock-driven so takes stay reproducible.
	garden.shake = maxf(garden.shake-dt*1.4,0.0)
	var jolt: float = garden.shake*garden.shake*camera.size*.04
	camera.h_offset = sin(ui_clock*71.0)*jolt; camera.v_offset = cos(ui_clock*57.0)*jolt
	frame_count += 1
	if not shot_path.is_empty() and frame_count == 60:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		get_tree().quit()

func _panel(bg: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg
	s.corner_radius_top_left = 22; s.corner_radius_top_right = 15; s.corner_radius_bottom_left = 17; s.corner_radius_bottom_right = 25
	s.set_content_margin_all(14); s.set_border_width_all(3); s.border_color = border
	s.shadow_color = Color("42351e45"); s.shadow_size = 3; s.shadow_offset = Vector2(1,4)
	return s

func _label(text: String, size: int, color: Color = Color("493b2b")) -> Label:
	var l := Label.new(); l.text = text; l.add_theme_font_size_override("font_size",size); l.add_theme_color_override("font_color",color)
	l.add_theme_font_override("font",PLAY_FONT)
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new(); add_child(layer)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE; layer.add_child(root)
	badges = HBoxContainer.new(); root.add_child(badges); badges.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE); badges.offset_left = 40; badges.offset_right = -40; badges.offset_top = 18; badges.offset_bottom = 90; badges.add_theme_constant_override("separation",24); badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner = _label("",44); root.add_child(banner); banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); banner.position = Vector2(300,112); banner.size = Vector2(1000,70); banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; banner.add_theme_color_override("font_color",Color("fff0bb")); banner.add_theme_color_override("font_outline_color",Color("4b4328")); banner.add_theme_constant_override("outline_size",8)
	hint = _label("",18); root.add_child(hint); hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE); hint.offset_top = -45; hint.offset_bottom = -12; hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; hint.add_theme_color_override("font_color",Color("fff3ce")); hint.add_theme_color_override("font_outline_color",Color("3d3928")); hint.add_theme_constant_override("outline_size",5)
	hint.text = ""
	var center := CenterContainer.new(); root.add_child(center); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = PanelContainer.new(); center.add_child(overlay); overlay.custom_minimum_size = Vector2(560,0)
	var card := _panel(Color("fff3e0f5"),Color("886842")); card.set_content_margin_all(26); overlay.add_theme_stylebox_override("panel",card)
	var box := VBoxContainer.new(); overlay.add_child(box); box.add_theme_constant_override("separation",10)
	# The game's name heads the main menu page, at the start and on pause.
	title = _game_logo(); box.add_child(title); title.custom_minimum_size = Vector2(550, 155)
	menu_title = _label("Ready to rumble?",30); menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(menu_title)
	menu_list = VBoxContainer.new(); box.add_child(menu_list); menu_list.add_theme_constant_override("separation",6)
	menu_help = _label("",15); menu_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; menu_help.add_theme_color_override("font_color",Color("8a7558")); box.add_child(menu_help)
	overlay.hide()
	title_card = _game_logo(); root.add_child(title_card)
	title_card.position = Vector2(450, 190); title_card.size = Vector2(700, 345)
	title_card.visible = false
	sound = AudioStreamPlayer.new(); sound.volume_db = -16; add_child(sound)

const FLAGS := ["kick","ghost","remote","pierce","square","line"]
const TIPS := {"capacity":"Bombs at once","range":"Blast range in tiles","speed":"Extra speed","kick":"Kicks bombs","ghost":"Walks through sand and bombs",
	"remote":"Remote bombs: B sets them off","pierce":"Blasts bore through sand","square":"Blasts fill the 3x3 around the bomb","line":"Plant again on your bomb to lay a row","skull":"Cursed"}
const CURSE_NAMES := {"slow":"Slow","reverse":"Reversed","drop":"Leaky"}

func _update_badges(upgraded: int = -1) -> void:
	if not badges: return
	for n in badges.get_children(): badges.remove_child(n); n.queue_free()
	for i in sim.bugs.size():
		var p: Dictionary = sim.bugs[i]
		# Bare text on the garden: the player's colour, a dark outline, no card.
		var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",0); box.mouse_filter = Control.MOUSE_FILTER_IGNORE; badges.add_child(box)
		var text: String = p.name
		if sim.settings.teams == "Teams": text += " · T%d"%(p.team+1)
		var label := _label(text,20,p.color.lightened(.25)); label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; box.add_child(label)
		label.add_theme_color_override("font_outline_color",Color("2f2a1c")); label.add_theme_constant_override("outline_size",7)
		# Wraps onto a second row once a bug has collected a whole garden of power-ups.
		var stats := HFlowContainer.new(); stats.add_theme_constant_override("h_separation",5); stats.add_theme_constant_override("v_separation",2); box.add_child(stats)
		for kind in ["capacity","range","speed"]+FLAGS+["skull"]:
			if (kind == "speed" and p.speed == 0) or (kind in FLAGS and not p[kind]) or (kind == "skull" and p.curse == ""): continue
			var shown: String = "mega" if kind == "range" and p.range >= Match.MAX_RANGE else kind
			var icon := TextureRect.new(); icon.texture = garden.POWER_ICONS[shown]; icon.custom_minimum_size = Vector2(26,26); icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; stats.add_child(icon)
			icon.tooltip_text = TIPS[kind]
			if kind in FLAGS: continue
			if kind == "skull":
				var curse := _label(CURSE_NAMES[p.curse],16,Color("e6dcff")); stats.add_child(curse)
				curse.add_theme_color_override("font_outline_color",Color("2f2a1c")); curse.add_theme_constant_override("outline_size",6)
				continue
			var value := _label("MAX" if shown == "mega" else str(p[kind]),20,Color("fff3ce")); stats.add_child(value)
			value.add_theme_color_override("font_outline_color",Color("2f2a1c")); value.add_theme_constant_override("outline_size",6)
		if not p.alive: box.modulate.a = .35
		if i == upgraded:
			box.modulate = Color(1.6,1.6,1.3)
			create_tween().tween_property(box,"modulate",Color.WHITE,.35)

func _open_menu(first: bool) -> void:
	initial_menu = first; menu_open = true; overlay.show(); banner.text = ""
	_show_page("main")
	_trace("menu")

func _close_menu() -> void:
	if initial_menu:
		_new_round(); active = true; initial_menu = false
	menu_open = false; overlay.hide()
	if sim.ended: banner.text = "A garden-sized draw!" if sim.winner == -1 else _winner_name()+" wins!"

func _show_page(page: String) -> void:
	menu_page = page; menu_index = 0
	menu_items = []
	if page == "main":
		menu_items.append({"action":"play"})
		if not initial_menu: menu_items.append({"action":"restart"})
		for key in BASIC_SETTINGS: menu_items.append({"key":key})
		menu_items.append({"action":"more"})
	else:
		for key in ADVANCED_SETTINGS: menu_items.append({"key":key})
		menu_items.append({"action":"back"})
	for n in menu_list.get_children(): menu_list.remove_child(n); n.queue_free()
	menu_rows.clear()
	for i in menu_items.size():
		var b := Button.new(); menu_list.add_child(b); b.custom_minimum_size = Vector2(500,52 if menu_items[i].get("action") == "play" else 44); b.focus_mode = Control.FOCUS_NONE
		for state in ["normal","hover","pressed"]: b.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var row := HBoxContainer.new(); b.add_child(row); row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); row.offset_left = 18; row.offset_right = -18; row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := _label("",22 if menu_items[i].get("action") == "play" else 19); caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL; caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row.add_child(caption)
		var value := _label("",19,Color("6b5636")); value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; row.add_child(value)
		if menu_items[i].has("action"): caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.mouse_entered.connect(func(): menu_index = i; _refresh_menu())
		b.pressed.connect(func(): _menu_action(i,-1 if b.get_local_mouse_position().x < b.size.x*.5 and menu_items[i].has("key") else 1))
		menu_rows.append(b)
	_refresh_menu()

func _display(key: String) -> String:
	var value: Variant = settings.get(key)
	match key:
		"ai_players": return "None" if int(value) == 0 else str(value)
		"fuse": return "%.1f s"%(float(value)/10)
		"speed": return "%.1f"%(float(value)/10)
		"crates": return "%d%%"%int(value)
	if value is bool: return "On" if value else "Off"
	return str(value)

func _refresh_menu() -> void:
	menu_title.text = ("Ready to rumble?" if initial_menu else "Take a breather") if menu_page == "main" else "More options"
	# The name shows whenever Start opens the menu, so everyone learns what they're playing.
	title.visible = menu_page == "main"
	# Controls speak for themselves: no button hints in the menu.
	menu_help.visible = false
	for i in menu_items.size():
		var item: Dictionary = menu_items[i]
		var row := menu_rows[i].get_child(0)
		var caption: Label = row.get_child(0); var value: Label = row.get_child(1)
		var selected := i == menu_index
		if item.has("key"):
			var spec: Dictionary = {}
			for candidate in SETTINGS:
				if candidate.key == item.key: spec = candidate
			caption.text = spec.label.get_slice(" (",0).get_slice(",",0)
			value.text = ("‹  %s  ›" if selected else "%s") % _display(item.key)
		else:
			caption.text = {"play":"Play" if initial_menu else "Resume","more":"More options  ›","back":"‹  Back","restart":"New round · apply options"}[item.action]
			value.text = ""
		var primary: bool = item.get("action") == "play"
		var fill := Color("cee79a") if selected else (Color("f6dc8f") if primary else Color("00000000"))
		var line := Color("6b8745") if selected else (Color("c99d45") if primary else Color("00000000"))
		var style := _panel(fill,line); style.set_content_margin_all(0)
		if not selected and not primary: style.shadow_size = 0
		menu_rows[i].add_theme_stylebox_override("normal",style); menu_rows[i].add_theme_stylebox_override("hover",style); menu_rows[i].add_theme_stylebox_override("pressed",style)

func _menu_action(index: int, direction: int) -> void:
	var item: Dictionary = menu_items[index]
	match item.get("action",""):
		"play": _close_menu(); return
		"more": _show_page("advanced"); return
		"back": _show_page("main"); return
		"restart": _new_round(); active = true; initial_menu = false; _close_menu(); return
	var spec: Dictionary = {}
	for candidate in SETTINGS:
		if candidate.key == item.key: spec = candidate
	var v: Variant = settings.get(spec.key,spec.default)
	match spec.kind:
		"number": v = clampi(int(v)+direction,spec.min,spec.max)
		"choice": v = spec.options[posmod(spec.options.find(v)+direction,spec.options.size())]
		"toggle": v = not v
	_setting(spec.key,v)
	if managed: GameNight.set_setting(spec.key,v)
	_refresh_menu()

func _build_audio() -> void:
	# Soft procedural percussion: no music, no harsh looping engine/noise layer.
	var noise := RandomNumberGenerator.new(); noise.seed = 19
	for kind in ["boom","pickup","out","kick"]:
		var samples := PackedByteArray()
		var seconds := .45 if kind == "boom" else .13
		var count := int(22050*seconds)
		samples.resize(count*2)
		var smoothed := 0.0
		for i in count:
			var t := float(i)/22050; var fraction := float(i)/count
			var envelope := minf(t*100,1.0)*pow(1-fraction,3)
			smoothed = lerpf(smoothed,noise.randf_range(-1,1),.15)
			var frequency: float = {"plant":120.0,"pickup":660.0,"kick":220.0}.get(kind,80.0)
			var value := sin(TAU*frequency*t*(1-fraction*.3))*.45
			if kind == "boom": value = smoothed*.6+sin(TAU*70*t)*.4
			samples.encode_s16(i*2,int(clampf(value*envelope,-1,1)*22000))
		var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = 22050; wav.data = samples; clips[kind] = wav
	var jingles := PickupSound.build_all()
	for kind in jingles: clips[("" if kind in ["detonate","cursed","lay"] else "pickup:")+kind] = jingles[kind]
	clips.plant = clips.lay
	clips.line = clips.lay
	sound.max_polyphony = 4
	boom_player = AudioStreamPlayer.new(); boom_player.max_polyphony = 6; add_child(boom_player)
	boom_task = WorkerThreadPool.add_task(func(): boom_clips = BoomSound.build_all(),false,"Explosion sounds")

func _play_boom(cells: int) -> void:
	if not settings.sound: return
	if boom_clips.is_empty() and boom_task >= 0 and WorkerThreadPool.is_task_completed(boom_task):
		WorkerThreadPool.wait_for_task_completion(boom_task); boom_task = -1
	if boom_clips.is_empty():
		_play_sound("boom"); return
	var row: Array = boom_clips[BoomSound.bucket(cells)]
	boom_player.stream = row[rng.randi() % row.size()]
	boom_player.volume_db = -7.0+BoomSound.volume_db(cells)
	boom_player.pitch_scale = rng.randf_range(.96,1.04)
	boom_player.play()

func _play_sound(kind: String) -> void:
	if not settings.sound: return
	sound.stream = clips[kind]; sound.pitch_scale = rng.randf_range(.95,1.05); sound.play()

func _exit_tree() -> void:
	if boom_task >= 0: WorkerThreadPool.wait_for_task_completion(boom_task)

## Compile every blast and death shader before play (the Growing Guns ShaderWarmup
## pattern): draw a whole explosion, a charred burning husk and an extra omni light
## once at sub-pixel scale, so the first real bomb doesn't stall on pipeline compiles.
func _warm_up_shaders() -> void:
	var rig := Node3D.new(); rig.position = Vector3(0,1,0); rig.scale = Vector3.ONE*.001; add_child(rig)
	var blast: Node3D = Garden.Explosion.new(); rig.add_child(blast)
	blast.setup([Vector2i(0,0),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,2)],func(c: Vector2) -> Vector3: return Vector3(c.x,0,c.y),1)
	blast.update(.1)
	var husk := Bug.new(); rig.add_child(husk); husk.build(0,Color.WHITE)
	# 1.6 s in: charred, glowing embers, belly fire and smoke all showing, not yet apart.
	husk.animate(.8,false,0,false); husk.animate(.8,false,0,false)
	# Lit materials (sand, rock, grass, clay) need their omni-light variants too.
	var light := OmniLight3D.new(); light.omni_range = 60; light.light_energy = .001; light.shadow_enabled = false; add_child(light)
	if DisplayServer.get_name() != "headless": RenderingServer.force_draw(true)
	var done := get_tree().create_timer(.15)
	done.timeout.connect(rig.queue_free); done.timeout.connect(light.queue_free)

func _game_logo() -> TextureRect:
	var logo := TextureRect.new()
	logo.texture = preload("res://assets/branding/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return logo
