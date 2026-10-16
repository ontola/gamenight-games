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

# Fine world-space grain breaks up the flat procedural surfaces without textures.
static func earth_material(color: Color, grain: float = .14) -> ShaderMaterial:
	var key := str(color)+"earth"+str(grain)
	if materials.has(key): return materials[key]
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color;
uniform float grain = 0.14;
varying vec3 world;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float n=noise(world*17.0)*.45+noise(world*65.0)*.35+noise(world*3.0)*.2;
 ALBEDO=tint.rgb*COLOR.rgb*(1.0+(n-.5)*grain*3.0);
 ROUGHNESS=.96;

}
"""
	var m := ShaderMaterial.new(); m.shader = shader
	m.set_shader_parameter("tint",color); m.set_shader_parameter("grain",grain)
	materials[key] = m
	return m

static func stone_shape(parent: Node3D, at: Vector3, seed_value: int, sand: bool) -> Node3D:
	var n := Node3D.new(); parent.add_child(n); n.position = at
	var random := RandomNumberGenerator.new(); random.seed = seed_value
	var rings: Array[PackedVector3Array] = []
	var sides := 14
	var phases: Array[float] = []
	for j in sides: phases.append(random.randf_range(.86,1.12))
	var height := random.randf_range(.54,.72) if sand else random.randf_range(.69,.88)
	for r in 7:
		var t := float(r)/6
		var ring := PackedVector3Array()
		var radius := .48*pow(maxf(0,1.0-t),.7) if sand else .47*pow(sin((t*.85+.10)*PI),.36)
		if r == 6: radius = .015 if sand else .19
		for j in sides:
			var a := j*TAU/sides
			var jitter := random.randf_range(.92,1.08)
			var y := t*height + sin(a*3+seed_value)*.035*sin(t*PI)
			ring.append(Vector3(cos(a)*radius*phases[j]*jitter+t*.07,y-.025,sin(a)*radius*phases[j]*jitter-t*.04))
		rings.append(ring)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in 6:
		for j in sides:
			var k := (j+1)%sides
			for v in [rings[r][j],rings[r][k],rings[r+1][j],rings[r][k],rings[r+1][k],rings[r+1][j]]:
				surface.set_color(Color.WHITE); surface.add_vertex(v)
	for j in sides:
		for v in [Vector3(.07,height-.025,-.04),rings[6][j],rings[6][(j+1)%sides]]:
			surface.set_color(Color.WHITE); surface.add_vertex(v)
	surface.index(); surface.generate_normals()
	var body := MeshInstance3D.new(); body.mesh=surface.commit()
	body.material_override=earth_material(Color("b68a50") if sand else Color("88877d"),.07 if sand else .15)
	n.add_child(body)
	# Loose grains at a mound's foot; small irregular moss patches at rock bases.
	for i in (9 if sand else 6):
		var a := random.randf()*TAU
		var radius := random.randf_range(.34,.45)
		var size := random.randf_range(.035,.09) if sand else random.randf_range(.06,.16)
		var y := .015 if sand else random.randf_range(.06,.20)
		var speck := ball(n,Vector3(cos(a)*radius,y,sin(a)*radius),Vector3(size,size*.45,size),Color("cfac70") if sand else Color("52632b").lerp(Color("7b893c"),random.randf()))
		speck.rotation=Vector3(random.randf(),a,random.randf())
	return n

static func sand_mound(parent: Node3D, at: Vector3, variant: int) -> Node3D:
	return stone_shape(parent,at,variant*7919+37,true)

static func pebble(parent: Node3D, at: Vector3, variant: float) -> Node3D:
	return stone_shape(parent,at,int(variant*99999),false)

static func bomb(parent: Node3D) -> Node3D:
	var n := Node3D.new(); parent.add_child(n)
	ball(n,Vector3(0,.25,0),Vector3(.55,.51,.55),Color("49322d"))
	ball(n,Vector3(0,.46,0),Vector3(.34,.14,.34),Color("97623b"))
	rod(n,Vector3(0,.5,0),Vector3(.10,.72,0),.032,Color("d6b47b"))
	ball(n,Vector3(.1,.73,0),Vector3(.11,.11,.11),Color("ffbd41"),2)
	return n
