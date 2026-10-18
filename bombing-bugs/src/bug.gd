extends Node3D
const Clay = preload("res://src/clay.gd")
const COLORS := [Color("f1634c"),Color("bf784b"),Color("f7c74c"),Color("3ebeb0")]
var body: Node3D
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var marker: MeshInstance3D
var kind := 0
var phase := 0.0
# Death: flipped on its back, charred, a little fire on the belly, then it falls apart.
var dead_time := -1.0
var charred: Array = []   # [material, original colour]
var flames: Array[MeshInstance3D] = []
var wisps: Array[MeshInstance3D] = []
var pieces: Array = []    # [node, velocity, spin]
var flame_material: StandardMaterial3D
var flame_core: StandardMaterial3D
var smoke_material: StandardMaterial3D
const CHAR := Color("1c1612")
## Set by main.gd while a skull curse sits on this bug: little purple wisps circle its head.
var cursed := false
var hex: Node3D
## Laying a bomb: a little squat with the eyes squeezed shut, like laying an egg.
var lay_time := -1.0
var eyes: Array[Node3D] = []
const LAY_TIME := .42

func build(index: int, player_color: Color) -> void:
	kind = index % 4
	body = Node3D.new(); add_child(body)
	var dark := Color("382d30")
	var color: Color = COLORS[kind]
	# Marker uses the host's player colour; insect species retain recognisable colours.
	marker = MeshInstance3D.new()
	var ring := TorusMesh.new(); ring.inner_radius = .31; ring.outer_radius = .37; ring.rings = 24; ring.ring_segments = 8
	marker.mesh = ring; marker.material_override = Clay.material(player_color)
	marker.position.y = .035; marker.scale.y = .35; add_child(marker)
	if kind == 1:
		Clay.ball(body,Vector3(0,.37,-.25),Vector3(.39,.38,.48),color)
		Clay.ball(body,Vector3(0,.34,.02),Vector3(.24,.27,.27),color.darkened(.12))
	else:
		Clay.ball(body,Vector3(0,.37,-.12),Vector3(.64,.47,.70),color)
		if kind == 0:
			for p in [Vector3(-.18,.52,-.26),Vector3(.18,.52,-.26),Vector3(-.22,.49,-.01),Vector3(.22,.49,-.01)]:
				Clay.ball(body,p,Vector3(.16,.055,.16),dark)
			Clay.rod(body,Vector3(0,.605,-.37),Vector3(0,.605,.11),.014,dark)
		elif kind == 2:
			for z in [-.25,-.01]: Clay.ball(body,Vector3(0,.38,z),Vector3(.65,.48,.12),dark)
			for side in [-1,1]:
				var wing := Clay.ball(body,Vector3(side*.25,.65,-.18),Vector3(.45,.08,.27),Color("f4eecb"))
				wing.rotation.z = side*.2; wings.append(wing)
		else:
			Clay.rod(body,Vector3(0,.61,-.39),Vector3(0,.61,.13),.014,Color("237a78"))
			Clay.ball(body,Vector3(-.12,.58,-.24),Vector3(.16,.035,.24),Color("88d7bd"))
	var head_color := dark if kind == 0 else color
	Clay.ball(body,Vector3(0,.42,.29),Vector3(.45,.44,.41),head_color)
	for side in [-1,1]:
		# Each eye sits in its own pivot so it can squint shut.
		var eye := Node3D.new(); body.add_child(eye); eye.position = Vector3(side*.125,.505,.47); eyes.append(eye)
		Clay.ball(eye,Vector3(0,-.005,-.016),Vector3(.15,.18,.08),Color("fff5d9"))
		Clay.ball(eye,Vector3(0,.005,.023),Vector3(.071,.09,.035),dark)
		Clay.ball(eye,Vector3(-.013,.035,.043),Vector3(.025,.025,.012),Color.WHITE)
		Clay.rod(body,Vector3(side*.12,.59,.27),Vector3(side*.22,.82,.3),.023,dark)
		Clay.ball(body,Vector3(side*.22,.83,.3),Vector3(.07,.07,.07),dark)
		for j in 3:
			var pivot := Node3D.new(); body.add_child(pivot); pivot.position = Vector3(side*.19,.25,.12-j*.19)
			Clay.rod(pivot,Vector3.ZERO,Vector3(side*.21,-.1,.06),.034,dark)
			Clay.ball(pivot,Vector3(side*.23,-.16,.08),Vector3(.13,.10,.14),dark)
			legs.append(pivot)
	Clay.ball(body,Vector3(0,.345,.485),Vector3(.115,.065,.025),dark)

func animate(dt: float, moving: bool, heading: float, alive: bool) -> void:
	phase += dt*(18.0 if moving else 2.4)
	if not alive:
		if hex: hex.visible = false
		_die(dt)
		return
	if cursed and hex == null:
		hex = Node3D.new(); add_child(hex); hex.position.y = .95
		for i in 3: Clay.ball(hex,Vector3(cos(i*TAU/3)*.3,0,sin(i*TAU/3)*.3),Vector3.ONE*.11,Color("8a5cc4"),1.5)
	if hex:
		hex.visible = cursed
		hex.rotation.y += dt*4.0; hex.position.y = .95+sin(phase*.3)*.04
	rotation.y = lerp_angle(rotation.y,heading,1.0-exp(-dt*14))
	body.position.y = sin(phase)*(.035 if moving else .012)
	body.rotation.z = sin(phase*.5)*(.055 if moving else .015)
	for i in legs.size(): legs[i].rotation.y = sin(phase+(i%2)*PI)*(.5 if moving else .04)
	for i in wings.size(): wings[i].rotation.z = (1 if i == 0 else -1)*(.15+sin(phase*2)*.12)
	_lay(dt)

func lay() -> void:
	if dead_time < 0: lay_time = 0.0

func _lay(dt: float) -> void:
	if lay_time < 0: return
	lay_time += dt
	# Down into the knees, a brief squeeze, back up: a bell curve over LAY_TIME.
	var k := clampf(lay_time/LAY_TIME,0,1)
	var squat := sin(k*PI)*sin(k*PI)
	body.position.y -= .06*squat
	body.scale = Vector3(1.0+.05*squat,1.0-.08*squat,1.0+.05*squat)
	body.rotation.x = -.12*squat
	for i in legs.size(): legs[i].rotation.z = (-1 if i < 3 else 1)*.35*squat
	for eye in eyes: eye.scale.y = 1.0-.82*clampf(squat*1.6,0,1)
	if k >= 1.0:
		lay_time = -1.0; body.scale = Vector3.ONE; body.rotation.x = 0
		for leg in legs: leg.rotation.z = 0
		for eye in eyes: eye.scale.y = 1.0

func _die(dt: float) -> void:
	if dead_time < 0: _start_dying()
	dead_time += dt
	var t := dead_time
	# Blown up and over: a hop with a half somersault, landing on its back.
	var flip := smoothstep(0.0,.5,t)
	var angle := PI*flip
	body.rotation.z = angle
	# Once the fire dies down the husk sags flat.
	var slump := smoothstep(2.3,3.6,t)
	body.position = Vector3(.37*sin(angle),.37-.37*cos(angle)-.14*flip+sin(clampf(t/.5,0,1)*PI)*.55-.1*slump,0)
	body.scale = Vector3(1.0+.1*slump,1.0-.22*slump,1.0+.1*slump)
	# Scorched black within a blink; the embers in the char glow out.
	var burn := clampf(t/.2,0,1)
	var glow := maxf(0.0,1.0-t/1.6)*(.75+.25*sin(t*31.0))
	for entry in charred:
		var m: StandardMaterial3D = entry[0]
		m.albedo_color = (entry[1] as Color).lerp(CHAR,burn)
		m.emission_energy_multiplier = glow*.3*burn
	for i in legs.size():
		if legs[i].top_level: continue
		legs[i].rotation.x = sin(t*28.0+i*1.7)*.7*clampf(t-.45,0,1)*exp(-t*1.3)
	# A small fire licks the upturned belly, then gutters out.
	var fire_left := clampf((2.6-t)/.8,0,1)*smoothstep(.35,.6,t)
	for i in flames.size():
		var f := flames[i]
		var flicker := .75+.25*sin(t*(23.0+i*7.0)+i)*sin(t*(13.0+i*3.0))
		f.visible = fire_left > 0
		f.scale = Vector3(.26,.6*flicker,.26)*[1.0,.8,.5][i]*fire_left
		f.position = Vector3(sin(t*9.0+i*2.0)*.04+[-.06,.07,0.0][i],.58+f.scale.y*.4,cos(t*7.0+i)*.04)
	for i in wisps.size():
		var w := wisps[i]
		var life := fmod(t*.6+i/6.0,1.0)
		var strength := clampf((3.6-t)/1.2,0,1)*smoothstep(.4,.8,t)
		w.visible = strength > 0
		w.position = Vector3(sin(life*5.0+i)*.1+life*.25,.8+life*1.2,cos(life*4.0+i)*.08)
		w.scale = Vector3.ONE*(.22+life*.4)*strength*(1.0-life*.4)
	if t >= 2.4 and pieces.is_empty(): _fall_apart()
	for p in pieces:
		var node: Node3D = p[0]
		var v: Vector3 = p[1]
		if v == Vector3.ZERO: continue
		v.y -= 5.0*dt
		node.global_position += v*dt
		node.rotate(p[2].normalized(),p[2].length()*dt)
		if node.global_position.y < p[3]:
			node.global_position.y = p[3]
			v = Vector3.ZERO if absf(v.y) < 1.2 else Vector3(v.x*.4,-v.y*.3,v.z*.4)
		p[1] = v

func _start_dying() -> void:
	dead_time = 0.0
	marker.visible = false
	lay_time = -1.0; body.scale = Vector3.ONE; body.rotation.x = 0
	for leg in legs: leg.rotation.z = 0
	for eye in eyes: eye.scale.y = 1.0
	var stack: Array[Node] = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var source: StandardMaterial3D = n.material_override
			var m := source.duplicate() as StandardMaterial3D
			m.emission_enabled = true; m.emission = Color("ff5a1a"); m.emission_energy_multiplier = 0.0
			n.material_override = m
			charred.append([m,source.albedo_color])
	if flame_material == null:
		flame_material = StandardMaterial3D.new(); flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_material.albedo_color = Color("e2561a"); flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flame_core = flame_material.duplicate(); flame_core.albedo_color = Color("ffc24a")
		smoke_material = StandardMaterial3D.new(); smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke_material.albedo_color = Color(.36,.33,.3,.32); smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var f := Clay.ball(self,Vector3(0,.7,0),Vector3.ONE*.01,Color.WHITE); f.material_override = flame_core if i == 2 else flame_material
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; f.visible = false; flames.append(f)
	for i in 6:
		var w := Clay.ball(self,Vector3(0,.8,0),Vector3.ONE*.01,Color.WHITE); w.material_override = smoke_material
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; w.visible = false; wisps.append(w)

## The burnt husk crumbles: legs, wings and head drop off gently and stay where they land.
func _fall_apart() -> void:
	var random := RandomNumberGenerator.new(); random.seed = kind*977+int(global_position.x*31.0+global_position.z*17.0)
	var head := Node3D.new(); body.add_child(head); head.position = Vector3(0,.44,.33)
	for n in body.get_children():
		if (n is MeshInstance3D or n in eyes) and n.position.z > .2 and n.position.y > .3:
			n.reparent(head)
	var loose: Array[Node3D] = [head]
	loose.append_array(legs); loose.append_array(wings)
	for n in loose:
		var at := n.global_transform
		n.top_level = true; n.global_transform = at
		var out := n.global_position-global_position; out.y = 0
		out = (out.normalized() if out.length() > .01 else Vector3.RIGHT.rotated(Vector3.UP,random.randf()*TAU))
		var speed := random.randf_range(.12,.35)*(.6 if n == head else 1.0)
		pieces.append([n,out*speed+Vector3(0,random.randf_range(.1,.4),0),Vector3(random.randf_range(-1.5,1.5),random.randf_range(-1,1),random.randf_range(-1.5,1.5)),.2 if n == head else .08])
