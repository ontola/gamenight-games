extends Node3D
const Clay = preload("res://src/clay.gd")
const Blast = preload("res://src/blast.gd")
var blast_views: Dictionary = {}
var blast_lights: Array[OmniLight3D] = []
var obstacles: Dictionary = {}
var bomb_views: Dictionary = {}
var pickup_views: Dictionary = {}
var flame_root: Node3D
var arena_root: Node3D
var burst_root: Node3D
var last_flames := ""
var clock := 0.0
var rng := RandomNumberGenerator.new()
var scenery: Node3D
var size := Vector2i.ZERO
# Half the playable width and depth, in tiles: the garden is built around it.
var hx := 5.5
var hz := 4.5

func world(c: Vector2) -> Vector3:
	return Vector3(c.x-(size.x-1)*.5,0,c.y-(size.y-1)*.5)

func build() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color("769151")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("d0d9db"); env.ambient_light_energy = .26
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env; add_child(env_node)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-52,-32,0); sun.light_color = Color("ffe7bd"); sun.light_energy = .74
	sun.shadow_enabled = true; sun.shadow_blur = 2.0; sun.directional_shadow_max_distance = 40; add_child(sun)
	arena_root = Node3D.new(); add_child(arena_root)
	flame_root = Node3D.new(); add_child(flame_root)
	burst_root = Node3D.new(); add_child(burst_root)

## Sand pit, bank, grass and onlookers sized to the round's garden; rebuilt only when the size changes.
func build_scenery(garden_size: Vector2i) -> void:
	if garden_size == size: return
	size = garden_size; hx = (size.x-2)*.5; hz = (size.y-2)*.5
	if scenery: scenery.free()
	scenery = Node3D.new(); add_child(scenery)
	rng.seed = 431+size.x*31+size.y
	build_terrain()
	build_grass()
	for i in int(420*hx*hz/24.75):
		var x := rng.randf_range(-hx+.1,hx-.1); var z := rng.randf_range(-hz+.1,hz-.1)
		var speck := rng.randf_range(.018,.055)
		Clay.ball(scenery,Vector3(x,-.005,z),Vector3(speck,speck*.45,speck),Color("8e7049").lerp(Color("d1ad78"),rng.randf()))
	for i in 85:
		var at := Vector3(rng.randf_range(-hx-3.5,hx+3.5),.49,rng.randf_range(-hz-3.5,hz+2.5))
		if absf(at.x)<hx+.7 and absf(at.z)<hz+.7: continue
		clover(at,rng.randf_range(.3,.75))
		if i%5==0: flower(at,rng.randf_range(.4,.85))
	Clay.rod(scenery,Vector3(-hx-2.5,.25,-hz-2.3),Vector3(hx+1.5,.6,-hz-3.1),.3,Color("74513b"))
	for i in int((2*hx+2)/3)+1:
		Clay.rod(scenery,Vector3(-hx-.5+i*3,.5,-hz-2.5),Vector3(-hx+.5+i*3,.7,-hz-3.7),.1,Color("74513b"))
	# A snail spectator and mushrooms establish the tiny scale.
	var snail := Vector3(hx+2.1,0,hz-1.5)
	Clay.ball(scenery,snail+Vector3(0,.22,0),Vector3(1.4,.4,.6),Color("cbac70"))
	Clay.ball(scenery,snail+Vector3(-.2,.65,0),Vector3(.9,.95,.8),Color("9c653e"))
	for i in 3:
		var ring := TorusMesh.new(); ring.inner_radius = .14+i*.08; ring.outer_radius = .17+i*.08
		var mesh := MeshInstance3D.new(); mesh.mesh = ring; mesh.material_override = Clay.material(Color("d4a16b")); mesh.position = snail+Vector3(-.2,.65,.4); mesh.rotation.x = PI/2; scenery.add_child(mesh)
	for side in [-1,1]:
		Clay.rod(scenery,snail+Vector3(.4,.3,side*.16),snail+Vector3(.7,.75,side*.22),.035,Color("cbac70"))
		Clay.ball(scenery,snail+Vector3(.7,.77,side*.22),Vector3(.12,.12,.12),Color("382d30"))
	for x in [-hx-2.7,-hx-1.9]:
		Clay.rod(scenery,Vector3(x,0,-hz+1.5),Vector3(x,.8,-hz+1.5),.11,Color("e5ce99"))
		Clay.ball(scenery,Vector3(x,.8,-hz+1.5),Vector3(.9,.35,.9),Color("dd7350"))

# The collision boundary remains the outer tile row. Only its presentation changes:
# a continuous eroded bank rises outside the playable cells, rather than a rock fence.
func build_terrain() -> void:
	var rings: Array[PackedVector3Array] = []
	var profiles := [Vector3(hx+.03,-.04,hz+.03),Vector3(hx+.22,.18,hz+.22),Vector3(hx+.68,.53,hz+.68),Vector3(hx+1.15,.49,hz+1.15),Vector3(hx+6.5,.43,hz+5.5)]
	var count := 192
	for r in profiles.size():
		var ring := PackedVector3Array(); var profile: Vector3 = profiles[r]
		for i in count+1:
			var a := i*TAU/count
			var rough := sin(a*19)*.025+sin(a*31+.8)*.018
			var x := signf(cos(a))*pow(absf(cos(a)),.20)*(profile.x+rough)
			var z := signf(sin(a))*pow(absf(sin(a)),.20)*(profile.z+rough)
			ring.append(Vector3(x,profile.y+(rough if r>0 else 0),z))
		rings.append(ring)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		for v in [Vector3(0,-.04,0),rings[0][i],rings[0][i+1]]:
			surface.set_color(Color("c09a68")); surface.add_vertex(v)
	for r in profiles.size()-1:
		var inner_color := Color("a78551") if r<2 else Color("49652b")
		var outer_color := Color("897046") if r<2 else Color("4a692a")
		for i in count:
			var vertices := [rings[r][i],rings[r+1][i],rings[r+1][i+1],rings[r][i],rings[r+1][i+1],rings[r][i+1]]
			for j in 6:
				surface.set_color(inner_color if j in [0,3,5] else outer_color); surface.add_vertex(vertices[j])
	surface.index(); surface.generate_normals()
	var ground := MeshInstance3D.new(); ground.mesh=surface.commit()
	ground.material_override=Clay.earth_material(Color.WHITE,.065); scenery.add_child(ground)

func build_grass() -> void:
	# One mesh for thousands of tapered, bent blades keeps the lush border inexpensive.
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in int(2400*(hx+5)*(hz+3.6)/(10.5*8.1)):
		var at := Vector3(rng.randf_range(-hx-5,hx+5),.49,rng.randf_range(-hz-4,hz+3.2))
		if absf(at.x)<hx+.62 and absf(at.z)<hz+.62: continue
		var height := rng.randf_range(.45,1.8)
		if at.z>4: height *= .50
		var width := rng.randf_range(.065,.16)
		var a := rng.randf()*TAU
		var side := Vector3(cos(a),0,sin(a))*width
		var bend := Vector3(sin(a),0,cos(a))*rng.randf_range(.15,.60)
		var base := Color("315325").lerp(Color("66832e"),rng.randf())
		var tip := Color("84a73c").lerp(Color("b3bd52"),rng.randf())
		for segment in 4:
			var t := segment/4.0; var u := (segment+1)/4.0
			var low := at+Vector3(0,height*t,0)+bend*t*t
			var high := at+Vector3(0,height*u,0)+bend*u*u
			var vs := [low-side*(1-t),high-side*(1-u),high+side*(1-u),low-side*(1-t),high+side*(1-u),low+side*(1-t)]
			for j in 6:
				surface.set_color(base.lerp(tip,t if j in [0,3,5] else u)); surface.add_vertex(vs[j])
	surface.generate_normals()
	var grass := MeshInstance3D.new(); grass.mesh=surface.commit()
	var material := StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true; material.cull_mode=BaseMaterial3D.CULL_DISABLED; material.roughness=.85
	grass.material_override=material; scenery.add_child(grass)

func flower(at: Vector3, height: float) -> void:
	Clay.rod(scenery,at,at+Vector3(.1,height,0),.035,Color("5e8535"))
	for i in 7:
		var a := i*TAU/7
		var petal := Clay.ball(scenery,at+Vector3(cos(a)*.22,height,sin(a)*.22),Vector3(.3,.12,.18),Color("fff0c8"))
		petal.rotation.y = -a
	Clay.ball(scenery,at+Vector3(0,height+.07,0),Vector3(.27,.15,.27),Color("e6b73f"))

func clover(at: Vector3, size: float) -> void:
	for i in 3:
		var a := i*TAU/3
		var leaf := Clay.ball(scenery,at+Vector3(cos(a)*size*.2,.14,sin(a)*size*.2),Vector3(size*.5,.12,size*.4),Color("6c9b48"))
		leaf.rotation.y = -a

func reset(match_state: RefCounted) -> void:
	build_scenery(Vector2i(match_state.w,match_state.h))
	for n in arena_root.get_children(): n.free()
	for n in flame_root.get_children(): n.free()
	for n in burst_root.get_children(): n.free()
	obstacles.clear(); bomb_views.clear(); pickup_views.clear(); blast_views.clear(); last_flames = ""
	for light in blast_lights: light.free()
	blast_lights.clear()
	for c in match_state.cells:
		var value: int = match_state.cells[c]
		if value == 1 and match_state.inside(c):
			obstacles[c] = Clay.pebble(arena_root,world(Vector2(c)),rng.randf())
		elif value == 2:
			obstacles[c] = Clay.sand_mound(arena_root,world(Vector2(c)),c.x+c.y*13)
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
			var face := Node3D.new(); n.add_child(face); face.rotation.x = deg_to_rad(-46)
			var kind: String = match_state.pickups[c].kind
			var color := Color("d1a34d") if kind == "range" else Color("438c78")
			Clay.ball(face,Vector3.ZERO,Vector3(.78,.78,.19),color)
			var icon := Sprite3D.new(); icon.texture = preload("res://assets/power-range.svg") if kind == "range" else preload("res://assets/power-bombs.svg")
			icon.pixel_size = .0055; icon.position.z = .105; icon.shaded = true; face.add_child(icon)
		pickup_views[c].position.y = .48+sin(clock*3+c.x)*.055
		pickup_views[c].rotation.y = sin(clock*1.8+c.y)*.16
	for c in pickup_views.keys():
		if not match_state.pickups.has(c): pickup_views[c].queue_free(); pickup_views.erase(c)
	var burning := {}
	for f in match_state.flames:
		burning[f.cell]=maxf(burning.get(f.cell,0),f.time)
	for c in burning:
		if not blast_views.has(c):
			var blast:=Blast.new(); flame_root.add_child(blast); blast.position=world(Vector2(c));
			var connections: Array[Vector2i]=[]
			for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				if burning.has(c+direction): connections.append(direction)
			blast.setup(c.x+c.y*71,connections)
			blast_views[c]=blast
		blast_views[c].animate(burning[c])
	for c in blast_views.keys():
		if not burning.has(c): blast_views[c].queue_free(); blast_views.erase(c)
	for light in blast_lights.duplicate():
		var age: float=light.get_meta("age")+dt; light.set_meta("age",age)
		if age>=.65: light.queue_free(); blast_lights.erase(light); continue
		light.light_energy=(1.6 if age<.06 else .75)*pow(1.0-age/.65,1.2)
		light.light_color=Color("ffe6a4").lerp(Color("ff8025"),age/.65)
	for e in match_state.events:
		if e.type == "boom":
			if blast_lights.size()>=4: blast_lights.pop_front().queue_free()
			var light:=OmniLight3D.new(); light.position=world(Vector2(e.cell))+Vector3(0,.8,0); light.omni_range=3.4; light.omni_attenuation=1.2; light.shadow_enabled=false; light.set_meta("age",0.0); add_child(light); blast_lights.append(light)
		if e.type in ["crack","out"]: burst(world(Vector2(e.cell)),Color("b99561") if e.type == "crack" else Color("f2e9bb"))
	for n in burst_root.get_children():
		var life: float = n.get_meta("life")-dt; n.set_meta("life",life)
		if life <= 0: n.queue_free(); continue
		var velocity: Vector3 = n.get_meta("v"); velocity.y -= dt*7; n.set_meta("v",velocity); n.position += velocity*dt; n.scale *= pow(.12,dt)

func burst(at: Vector3, color: Color) -> void:
	for i in 8:
		var n := Clay.ball(burst_root,at+Vector3(0,.35,0),Vector3.ONE*.16,color)
		n.set_meta("life",.65); n.set_meta("v",Vector3(rng.randf_range(-2,2),rng.randf_range(1,3),rng.randf_range(-2,2)))
