extends Node3D
const Clay = preload("res://src/clay.gd")
const COLORS := [Color("f1634c"),Color("bf784b"),Color("f7c74c"),Color("3ebeb0")]
var body: Node3D
var legs: Array[Node3D] = []
var wings: Array[Node3D] = []
var marker: MeshInstance3D
var kind := 0
var phase := 0.0

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
		Clay.ball(body,Vector3(side*.125,.50,.454),Vector3(.15,.18,.08),Color("fff5d9"))
		Clay.ball(body,Vector3(side*.125,.51,.493),Vector3(.071,.09,.035),dark)
		Clay.ball(body,Vector3(side*.125-.013,.54,.513),Vector3(.025,.025,.012),Color.WHITE)
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
		rotation.z = lerp_angle(rotation.z,PI*.5,dt*9)
		position.y = move_toward(position.y,-.16,dt)
		marker.visible = false
		return
	rotation.y = lerp_angle(rotation.y,heading,1.0-exp(-dt*14))
	body.position.y = sin(phase)*(.035 if moving else .012)
	body.rotation.z = sin(phase*.5)*(.055 if moving else .015)
	for i in legs.size(): legs[i].rotation.y = sin(phase+(i%2)*PI)*(.5 if moving else .04)
	for i in wings.size(): wings[i].rotation.z = (1 if i == 0 else -1)*(.15+sin(phase*2)*.12)
