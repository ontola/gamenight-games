extends Node3D
const Clay = preload("res://src/clay.gd")
var obstacles: Dictionary = {}
var bomb_views: Dictionary = {}
var pickup_views: Dictionary = {}
var flame_root: Node3D
var arena_root: Node3D
var burst_root: Node3D
var last_flames := ""
var clock := 0.0
var rng := RandomNumberGenerator.new()

func world(c: Vector2) -> Vector3:
	return Vector3(c.x-6,0,c.y-5)

func build() -> void:
	rng.seed = 431
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("769151")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("d7e0ed"); env.ambient_light_energy = .35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env; add_child(env_node)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55,-30,0); sun.light_color = Color("fff4de"); sun.light_energy = .85
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 40; add_child(sun)
	Clay.ball(self,Vector3(0,-.8,0),Vector3(40,1.4,35),Color("64803c"))
	Clay.ball(self,Vector3(0,-.56,0),Vector3(16,.9,14),Color("b78e55"))
	# A rounded soil patch, with a flat top and no intersecting ground surfaces.
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim: Array[Vector3] = []
	for i in 65:
		var a := i*TAU/64
		rim.append(Vector3(signf(cos(a))*pow(absf(cos(a)),.42)*7.0,-.04,signf(sin(a))*pow(absf(sin(a)),.42)*6.0))
	for i in 64:
		for v in [Vector3(0,-.04,0),rim[i],rim[i+1]]:
			surface.set_normal(Vector3.UP); surface.add_vertex(v)
	var ground := MeshInstance3D.new(); ground.mesh = surface.commit()
	ground.material_override = Clay.material(Color("bc9566")); add_child(ground)
	for i in 220:
		var x := rng.randf_range(-6.6,6.6); var z := rng.randf_range(-5.5,5.5)
		var s := rng.randf_range(.025,.085)
		Clay.ball(self,Vector3(x,-.005,z),Vector3(s,s*.3,s),Color("9a784c").lerp(Color("dfba83"),rng.randf()))
	for i in 150:
		var a := rng.randf()*TAU
		var x := cos(a)*rng.randf_range(7.4,10.8)
		var z := sin(a)*rng.randf_range(6.1,8.6)
		if absf(x) < 6.9 and absf(z) < 5.9: continue
		var h := rng.randf_range(.6,2.4)
		# Front foliage stays low enough to never hide a player.
		if z > 4: h *= .45
		for j in 3:
			var leaf := Clay.ball(self,Vector3(x+j*.09,h*.5-.2,z),Vector3(.15,h,.075),Color("639b3c").lerp(Color("a8bd47"),rng.randf()))
			leaf.rotation.z = rng.randf_range(-.5,.5)
		if i % 9 == 0: flower(Vector3(x,0,z),h+0.3)
	for i in 20:
		var x := rng.randf_range(-9,9); var z := rng.randf_range(-8,-6)
		clover(Vector3(x,0,z),rng.randf_range(.4,1.1))
	Clay.rod(self,Vector3(-8,.25,-6.8),Vector3(7,.6,-7.6),.3,Color("74513b"))
	for i in 4:
		Clay.rod(self,Vector3(-6+i*3,.5,-7),Vector3(-5+i*3,.7,-8.2),.1,Color("74513b"))
	# A snail spectator and mushrooms establish the tiny scale.
	Clay.ball(self,Vector3(7.6,.22,3),Vector3(1.4,.4,.6),Color("cbac70"))
	Clay.ball(self,Vector3(7.4,.65,3),Vector3(.9,.95,.8),Color("9c653e"))
	for i in 3:
		var ring := TorusMesh.new(); ring.inner_radius = .14+i*.08; ring.outer_radius = .17+i*.08
		var mesh := MeshInstance3D.new(); mesh.mesh = ring; mesh.material_override = Clay.material(Color("d4a16b")); mesh.position = Vector3(7.4,.65,3.4); mesh.rotation.x = PI/2; add_child(mesh)
	for side in [-1,1]:
		Clay.rod(self,Vector3(8,.3,3+side*.16),Vector3(8.3,.75,3+side*.22),.035,Color("cbac70"))
		Clay.ball(self,Vector3(8.3,.77,3+side*.22),Vector3(.12,.12,.12),Color("382d30"))
	for x in [-8.2,-7.4]:
		Clay.rod(self,Vector3(x,0,-3),Vector3(x,.8,-3),.11,Color("e5ce99"))
		Clay.ball(self,Vector3(x,.8,-3),Vector3(.9,.35,.9),Color("dd7350"))
	arena_root = Node3D.new(); add_child(arena_root)
	flame_root = Node3D.new(); add_child(flame_root)
	burst_root = Node3D.new(); add_child(burst_root)

func flower(at: Vector3, height: float) -> void:
	Clay.rod(self,at,at+Vector3(.1,height,0),.035,Color("5e8535"))
	for i in 7:
		var a := i*TAU/7
		var petal := Clay.ball(self,at+Vector3(cos(a)*.22,height,sin(a)*.22),Vector3(.3,.12,.18),Color("fff0c8"))
		petal.rotation.y = -a
	Clay.ball(self,at+Vector3(0,height+.07,0),Vector3(.27,.15,.27),Color("e6b73f"))

func clover(at: Vector3, size: float) -> void:
	for i in 3:
		var a := i*TAU/3
		var leaf := Clay.ball(self,at+Vector3(cos(a)*size*.2,.14,sin(a)*size*.2),Vector3(size*.5,.12,size*.4),Color("6c9b48"))
		leaf.rotation.y = -a

func reset(match_state: RefCounted) -> void:
	for n in arena_root.get_children(): n.free()
	for n in flame_root.get_children(): n.free()
	for n in burst_root.get_children(): n.free()
	obstacles.clear(); bomb_views.clear(); pickup_views.clear(); last_flames = ""
	for c in match_state.cells:
		var value: int = match_state.cells[c]
		if value == 1: obstacles[c] = Clay.pebble(arena_root,world(Vector2(c)),rng.randf())
		elif value == 2:
			obstacles[c] = Clay.seed(arena_root,world(Vector2(c)),(c.x+c.y*3)%3)
			obstacles[c].rotation.y = rng.randf()*TAU

func sync(match_state: RefCounted, dt: float) -> void:
	clock += dt
	for c in obstacles.keys():
		if match_state.cells[c] == 0:
			obstacles[c].queue_free(); obstacles.erase(c)
	var ids := {}
	for b in match_state.bombs:
		ids[b.id] = true
		if not bomb_views.has(b.id):
			bomb_views[b.id] = Clay.bomb(arena_root); bomb_views[b.id].position = world(Vector2(b.cell))
		var pulse := 1.0+sin(clock*(16 if b.time < 1 else 7))*.07
		bomb_views[b.id].scale = Vector3(pulse,2-pulse,pulse)
	for id in bomb_views.keys():
		if not ids.has(id): bomb_views[id].queue_free(); bomb_views.erase(id)
	for c in match_state.pickups:
		if match_state.pickups[c].wait > 0: continue
		if not pickup_views.has(c):
			var n := Node3D.new(); arena_root.add_child(n); n.position = world(Vector2(c)); pickup_views[c] = n
			var color := Color("f9bd43") if match_state.pickups[c].kind == "range" else Color("6dd2c4")
			Clay.ball(n,Vector3.ZERO,Vector3(.38,.4,.38),color,0.3)
			var label := Label3D.new(); label.text = "+" if match_state.pickups[c].kind == "capacity" else "↑"; label.font_size = 70; label.pixel_size = .006; label.position = Vector3(0,.08,.22); label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; n.add_child(label)
		pickup_views[c].position.y = .35+sin(clock*3)*.07
	for c in pickup_views.keys():
		if not match_state.pickups.has(c): pickup_views[c].queue_free(); pickup_views.erase(c)
	var signature := str(match_state.flames.map(func(f: Dictionary) -> Vector2i: return f.cell))
	if signature != last_flames:
		last_flames = signature
		for n in flame_root.get_children(): n.queue_free()
		for f in match_state.flames:
			var at := world(Vector2(f.cell))
			Clay.ball(flame_root,at+Vector3(0,.18,0),Vector3(.98,.40,.98),Color("ef6428"),.12)
			Clay.ball(flame_root,at+Vector3(0,.34,0),Vector3(.64,.5,.62),Color("ffbc3e"),.15)
			Clay.ball(flame_root,at+Vector3(.1,.65,0),Vector3(.28,.34,.29),Color("ffe38a"),.1)
	for e in match_state.events:
		if e.type in ["crack","out"]: burst(world(Vector2(e.cell)),Color("d2a169") if e.type == "crack" else Color("f2e9bb"))
	for n in burst_root.get_children():
		var life: float = n.get_meta("life")-dt; n.set_meta("life",life)
		if life <= 0: n.queue_free(); continue
		var velocity: Vector3 = n.get_meta("v"); velocity.y -= dt*7; n.set_meta("v",velocity); n.position += velocity*dt; n.scale *= pow(.12,dt)

func burst(at: Vector3, color: Color) -> void:
	for i in 8:
		var n := Clay.ball(burst_root,at+Vector3(0,.35,0),Vector3.ONE*.16,color)
		n.set_meta("life",.65); n.set_meta("v",Vector3(rng.randf_range(-2,2),rng.randf_range(1,3),rng.randf_range(-2,2)))
