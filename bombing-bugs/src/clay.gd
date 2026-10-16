extends RefCounted
## Small shared mesh vocabulary keeps the garden and bugs in one art style.
static var materials: Dictionary = {}

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key := str(color)+str(glow)
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.86
	if glow > 0:
		m.emission_enabled = true; m.emission = color; m.emission_energy_multiplier = glow
	materials[key] = m
	return m

static func ball(parent: Node3D, at: Vector3, size: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5; mesh.height = 1.0; mesh.radial_segments = 16; mesh.rings = 8
	node.mesh = mesh; node.material_override = material(color,glow)
	node.position = at; node.scale = size
	parent.add_child(node)
	return node

static func rod(parent: Node3D, from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = width; mesh.height = maxf(width*2.0,from.distance_to(to)); mesh.radial_segments = 8; mesh.rings = 4
	node.mesh = mesh; node.material_override = material(color)
	node.position = (from+to)*0.5
	var direction := (to-from).normalized()
	node.quaternion = Quaternion(Vector3.UP,direction) if direction != Vector3.ZERO else Quaternion.IDENTITY
	parent.add_child(node)
	return node

static func seed(parent: Node3D, at: Vector3, variant: int = 0) -> Node3D:
	var n := Node3D.new(); parent.add_child(n); n.position = at
	if variant % 3 == 0:
		ball(n,Vector3(0,.3,0),Vector3(.67,.62,.58),Color("ad602e"))
		ball(n,Vector3(0,.55,0),Vector3(.73,.23,.64),Color("6c442e"))
		rod(n,Vector3(0,.6,0),Vector3(.08,.78,.03),.045,Color("654328"))
		for i in 7:
			var a := i*TAU/7
			ball(n,Vector3(cos(a)*.24,.61,sin(a)*.21),Vector3(.12,.07,.12),Color("96683b"))
	elif variant % 3 == 1:
		var shell := ball(n,Vector3(0,.29,0),Vector3(.58,.52,.77),Color("d6a461"))
		shell.rotation.z = .18
		for i in 5:
			var x := (i-2)*.09
			rod(n,Vector3(x,.4,-.26),Vector3(x,.52,.23),.018,Color("a66f3e"))
	else:
		ball(n,Vector3(0,.25,0),Vector3(.62,.46,.78),Color("73533c"))
		for x in [-.16,0.0,.16]:
			rod(n,Vector3(x,.35,-.28),Vector3(x,.45,.22),.027,Color("e3c994"))
	return n

static func pebble(parent: Node3D, at: Vector3, variant: float) -> Node3D:
	var n := Node3D.new(); parent.add_child(n); n.position = at
	var color := Color("737f70").lerp(Color("8d9784"),variant)
	var body := ball(n,Vector3(0,.33,0),Vector3(.91,.70,.87),color)
	body.rotation = Vector3(variant*.2,variant*2,-variant*.15)
	ball(n,Vector3(-.17,.61,.06),Vector3(.43,.15,.42),Color("71934c"))
	ball(n,Vector3(-.27,.48,.29),Vector3(.19,.16,.17),Color("8baf56"))
	return n

static func bomb(parent: Node3D) -> Node3D:
	var n := Node3D.new(); parent.add_child(n)
	ball(n,Vector3(0,.25,0),Vector3(.55,.51,.55),Color("49322d"))
	ball(n,Vector3(0,.46,0),Vector3(.34,.14,.34),Color("97623b"))
	rod(n,Vector3(0,.5,0),Vector3(.10,.72,0),.032,Color("d6b47b"))
	ball(n,Vector3(.1,.73,0),Vector3(.11,.11,.11),Color("ffbd41"),2)
	return n
