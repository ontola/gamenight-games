extends Node3D
const Clay = preload("res://src/clay.gd")
const Explosion = preload("res://src/explosion.gd")
const POWER_ICONS := {"capacity":preload("res://assets/power-bombs.svg"),"range":preload("res://assets/power-range.svg"),"speed":preload("res://assets/power-speed.svg"),"kick":preload("res://assets/power-kick.svg"),"ghost":preload("res://assets/power-ghost.svg"),"mega":preload("res://assets/power-mega.svg"),"remote":preload("res://assets/power-remote.svg"),"pierce":preload("res://assets/power-pierce.svg"),"square":preload("res://assets/power-square.svg"),"line":preload("res://assets/power-line.svg"),"skull":preload("res://assets/power-skull.svg")}
const POWER_COLORS := {"capacity":Color("438c78"),"range":Color("d1a34d"),"speed":Color("5d9db8"),"kick":Color("c4704c"),"ghost":Color("9a86c9"),"mega":Color("c8382c"),"remote":Color("c95454"),"pierce":Color("a46aae"),"square":Color("d19a3e"),"line":Color("5f9e62"),"skull":Color("4f4066")}
var blast_views: Dictionary = {}
var next_blast := 0
## Camera shake the last blasts left behind; main.gd reads and decays it.
var shake := 0.0
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
	# Only HDR fire blooms (as in Growing Guns); everything lit stays below the threshold.
	env.glow_enabled = true; env.glow_hdr_threshold = 1.0; env.glow_intensity = .9; env.glow_bloom = 0.0; env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env_node.environment = env; add_child(env_node)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-52,-32,0); sun.light_color = Color("ffe7bd"); sun.light_energy = .74
	sun.shadow_enabled = true; sun.shadow_blur = 2.0; sun.directional_shadow_max_distance = 40; add_child(sun)
	arena_root = Node3D.new(); add_child(arena_root)
	flame_root = Node3D.new(); add_child(flame_root)
	burst_root = Node3D.new(); add_child(burst_root)

## Sand pit, bank, grass and onlookers sized to the round's garden; rebuilt only when the size changes.
# Meadow moods: each round draws one and jitters it, so no two gardens look alike.
const MOODS := [
	{"soil":Color("6f5b40"),"moss":Color("6a8a45"),"base":Color("365c2a"),"tip":Color("a9c95a"),"flowers":[Color("fff0c8"),Color("f7d34f")]},
	{"soil":Color("8a7650"),"moss":Color("8a9150"),"base":Color("5a6a32"),"tip":Color("d6c879"),"flowers":[Color("f4e2a0"),Color("e98a5d")]},
	{"soil":Color("5e4b35"),"moss":Color("557a40"),"base":Color("2c5530"),"tip":Color("9ccf66"),"flowers":[Color("f2b8d0"),Color("ffffff")]},
	{"soil":Color("7a6142"),"moss":Color("7f8648"),"base":Color("4d5c2a"),"tip":Color("cfb055"),"flowers":[Color("c9a0e8"),Color("fff0c8")]},
]
const GRASS_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform float gust = 1.0;
varying float tip;
void vertex() {
 tip = UV.y;
 vec3 world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 float t = TIME;
 // Two slow waves plus a travelling gust: blades lean together, not in lockstep.
 float wave = sin(t*1.7+world.x*.55+world.z*.35)*.6+sin(t*2.9+world.x*1.3-world.z*.9)*.25;
 float g = pow(max(sin(t*.45-world.x*.18+world.z*.07),0.0),3.0)*gust;
 float bend = UV.y*UV.y*clamp(UV.x,.3,2.5)*.6;
 VERTEX.x += (wave*.11+g*.32)*bend;
 VERTEX.z += (wave*.05+g*.12)*bend;
 // Soft, up-facing normals: lit like a lawn, not like folded paper.
 NORMAL = normalize(mix(NORMAL,vec3(0.0,1.0,0.0),.65));
}
void fragment() {
 // Roots sit in the shade of the clump; tips catch the sun.
 ALBEDO = COLOR.rgb*mix(.45,1.08,smoothstep(0.0,.75,tip));
 ROUGHNESS = .8;
 BACKLIGHT = COLOR.rgb*.35*tip;
}
"""
const MEADOW_SHADER := """shader_type spatial;
render_mode cull_disabled;
uniform vec4 soil : source_color;
uniform vec4 moss : source_color;
uniform vec2 offset;
varying vec3 world;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p = world.xz+offset;
 float patches = noise(p*.45)*.6+noise(p*1.3)*.3+noise(p*5.0)*.1;
 float grain = noise(p*23.0)*.5+noise(p*61.0)*.5;
 vec3 meadow = mix(soil.rgb, moss.rgb, smoothstep(.22,.58,patches));
 meadow *= .9+grain*.2;
 // Vertex alpha marks the meadow; the sandy bank keeps its own colours.
 ALBEDO = mix(COLOR.rgb*(.92+grain*.16), meadow, COLOR.a);
 ROUGHNESS = .95;
}
"""
var mood: Dictionary = {}
var swaying: Array[Node3D] = []
var snail_node: Node3D
var round_seed := -1

## Sand pit, bank, meadow and onlookers. Rebuilt each round from the round seed,
## so the garden around the same arena still looks a little different every time.
func build_scenery(garden_size: Vector2i, seed_value: int) -> void:
	if garden_size == size and seed_value == round_seed: return
	size = garden_size; round_seed = seed_value; hx = (size.x-2)*.5; hz = (size.y-2)*.5
	if scenery: scenery.free()
	swaying.clear()
	scenery = Node3D.new(); add_child(scenery)
	rng.seed = seed_value*7919+size.x*31+size.y
	mood = MOODS[rng.randi() % MOODS.size()].duplicate()
	for key in ["soil","moss","base","tip"]:
		var c: Color = mood[key]
		mood[key] = Color.from_hsv(wrapf(c.h+rng.randf_range(-.025,.025),0,1),clampf(c.s*rng.randf_range(.85,1.1),0,1),clampf(c.v*rng.randf_range(.92,1.06),0,1))
	build_terrain()
	build_grass()
	for i in int(420*hx*hz/24.75):
		var x := rng.randf_range(-hx+.1,hx-.1); var z := rng.randf_range(-hz+.1,hz-.1)
		var speck := rng.randf_range(.018,.055)
		Clay.ball(scenery,Vector3(x,-.005,z),Vector3(speck,speck*.45,speck),Color("8e7049").lerp(Color("d1ad78"),rng.randf()))
	var flower_colors: Array = mood.flowers
	for i in 110:
		var at := Vector3(rng.randf_range(-hx-4,hx+4),.45,rng.randf_range(-hz-3.5,hz+2.8))
		if absf(at.x)<hx+1.3 and absf(at.z)<hz+1.3: continue
		clover(at,rng.randf_range(.5,1.1))
		if rng.randf() < .3:
			var stem_at := at+Vector3(rng.randf_range(-.3,.3),0,rng.randf_range(-.3,.3))
			# Daisies stand taller than the bugs, except along the front edge where they'd hide the sand.
			var height := rng.randf_range(1.1,2.3)
			var front := stem_at.z-(hz+.62)
			if front > -.62 and absf(stem_at.x) < hx+2.5: height = minf(height,(front-.5)*.9)
			if height > .5: flower(stem_at,height,flower_colors[rng.randi() % flower_colors.size()])
	# One back-edge prop: a fallen twig, a row of pebbles or nothing at all.
	match rng.randi() % 3:
		0:
			Clay.rod(scenery,Vector3(-hx-2.5,.25,-hz-2.3),Vector3(hx+1.5,.6,-hz-3.1),.3,Color("74513b"))
			for i in int((2*hx+2)/3)+1:
				Clay.rod(scenery,Vector3(-hx-.5+i*3,.5,-hz-2.5),Vector3(-hx+.5+i*3,.7,-hz-3.7),.1,Color("74513b"))
		1:
			for i in 9:
				var at := Vector3(rng.randf_range(-hx-2,hx+2),.45,-hz-rng.randf_range(2.2,3.4))
				Clay.pebble(scenery,at,rng.randf()).scale *= rng.randf_range(.5,.9)
	# A snail spectator and mushrooms establish the tiny scale; their spots change per round.
	var side := 1.0 if rng.randf() < .7 else -1.0
	snail_node = Node3D.new(); scenery.add_child(snail_node)
	snail_node.position = Vector3(side*(hx+2.1),0,rng.randf_range(-hz+.5,hz-1.0)); snail_node.scale.x = side
	snail_node.set_meta("home",snail_node.position)
	Clay.ball(snail_node,Vector3(0,.22,0),Vector3(1.4,.4,.6),Color("cbac70"))
	Clay.ball(snail_node,Vector3(-.2,.65,0),Vector3(.9,.95,.8),Color("9c653e"))
	for i in 3:
		var ring := TorusMesh.new(); ring.inner_radius = .14+i*.08; ring.outer_radius = .17+i*.08
		var mesh := MeshInstance3D.new(); mesh.mesh = ring; mesh.material_override = Clay.material(Color("d4a16b")); mesh.position = Vector3(-.2,.65,.4); mesh.rotation.x = PI/2; snail_node.add_child(mesh)
	for s in [-1,1]:
		var stalk := _sway_node(snail_node,Vector3(.4,.3,s*.16),2.5)
		Clay.rod(stalk,Vector3.ZERO,Vector3(.3,.45,s*.06),.035,Color("cbac70"))
		Clay.ball(stalk,Vector3(.3,.47,s*.06),Vector3(.12,.12,.12),Color("382d30"))
	var cap := Color("dd7350") if rng.randf() < .6 else Color("c8a46a")
	var mx := -side*(hx+rng.randf_range(1.8,2.6)); var mz := rng.randf_range(-hz+.5,hz-.5)
	for i in rng.randi_range(1,3):
		var m := _sway_node(scenery,Vector3(mx-side*i*.8,0,mz+rng.randf_range(-.3,.3)),.6)
		var height := rng.randf_range(.9,1.6)
		Clay.rod(m,Vector3.ZERO,Vector3(0,height,0),.11,Color("e5ce99"))
		Clay.ball(m,Vector3(0,height,0),Vector3(1.2,.45,1.2)*rng.randf_range(.8,1.15),cap)

## A pivot that _process rocks gently; children lean with the meadow's wind.
func _sway_node(parent: Node3D, at: Vector3, strength: float) -> Node3D:
	var n := Node3D.new(); n.position = at; parent.add_child(n)
	n.set_meta("strength",strength); n.set_meta("phase",rng.randf()*TAU)
	swaying.append(n)
	return n

func _process(dt: float) -> void:
	var t := Time.get_ticks_msec()/1000.0
	for n in swaying:
		var at := n.global_position
		var strength: float = n.get_meta("strength")
		# Same waves as the grass shader, so flowers lean with the blades around them.
		var wave := sin(t*1.7+at.x*.55+at.z*.35)*.6+sin(t*2.9+at.x*1.3-at.z*.9+n.get_meta("phase"))*.25
		var gust := pow(maxf(sin(t*.45-at.x*.18+at.z*.07),0.0),3.0)
		n.rotation.z = -(wave*.06+gust*.16)*strength
		n.rotation.x = (wave*.03+gust*.06)*strength
	if snail_node:
		# The snail inches along its edge of the garden and back.
		var home: Vector3 = snail_node.get_meta("home")
		snail_node.position.z = home.z+sin(t*.07)*.9
		snail_node.position.y = absf(sin(t*1.1))*.015

# The collision boundary remains the outer tile row. Only its presentation changes:
# a continuous eroded bank rises outside the playable cells, rather than a rock fence.
func build_terrain() -> void:
	var rings: Array[PackedVector3Array] = []
	var profiles := [Vector3(hx+.03,-.04,hz+.03),Vector3(hx+.22,.18,hz+.22),Vector3(hx+.68,.53,hz+.68),Vector3(hx+1.15,.49,hz+1.15),Vector3(hx+7.5,.43,hz+6.5)]
	var count := 192
	for r in profiles.size():
		var ring := PackedVector3Array(); var profile: Vector3 = profiles[r]
		for i in count:
			var a := i*TAU/count
			var rough := sin(a*19)*.025+sin(a*31+.8)*.018
			var x := signf(cos(a))*pow(absf(cos(a)),.20)*(profile.x+rough)
			var z := signf(sin(a))*pow(absf(sin(a)),.20)*(profile.z+rough)
			ring.append(Vector3(x,profile.y+(rough if r>0 else 0),z))
		# Close the loop on the very same vertex, or the seam at angle 0 cracks open as a bright line.
		ring.append(ring[0])
		rings.append(ring)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sand := Color("c09a68"); sand.a = 0
	for i in count:
		for v in [Vector3(0,-.04,0),rings[0][i],rings[0][i+1]]:
			surface.set_color(sand); surface.add_vertex(v)
	for r in profiles.size()-1:
		# Alpha 1 hands the colour to the meadow shader: soil and moss patches.
		var inner_color := Color("a78551",0) if r<2 else Color("8a7046",1)
		var outer_color := Color("897046",0) if r<2 else Color("8a7046",1)
		if r == 1: outer_color = Color("897046",.6)
		for i in count:
			var vertices := [rings[r][i],rings[r+1][i],rings[r+1][i+1],rings[r][i],rings[r+1][i+1],rings[r][i+1]]
			for j in 6:
				surface.set_color(inner_color if j in [0,3,5] else outer_color); surface.add_vertex(vertices[j])
	surface.index(); surface.generate_normals()
	var ground := MeshInstance3D.new(); ground.mesh=surface.commit()
	var shader := Shader.new(); shader.code = MEADOW_SHADER
	var material := ShaderMaterial.new(); material.shader = shader
	material.set_shader_parameter("soil",mood.soil); material.set_shader_parameter("moss",mood.moss)
	material.set_shader_parameter("offset",Vector2(rng.randf_range(0,100),rng.randf_range(0,100)))
	ground.material_override = material; scenery.add_child(ground)

## Thousands of curved, folded blades in clumps, so soil shows between tufts.
## One mesh and a wind shader keep it cheap; UV.y carries the height for the sway.
func build_grass() -> void:
	var verts := PackedVector3Array(); var normals := PackedVector3Array(); var colors := PackedColorArray(); var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	var reach := Vector2(hx+6,hz+4.5)
	var clumps := int(660*(reach.x*reach.y)/(11.5*9.0))
	var base_color: Color = mood.base; var tip_color: Color = mood.tip
	for c in clumps:
		var center := Vector3(rng.randf_range(-reach.x,reach.x),.47,rng.randf_range(-reach.y,reach.y-1.2))
		if absf(center.x)<hx+.75 and absf(center.z)<hz+.75: continue
		var radius := rng.randf_range(.25,.7)
		var lush := rng.randf_range(.65,1.2)
		for b in rng.randi_range(7,18):
			var off := Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*radius
			var at := center+Vector3(off.x,0,off.y)
			# Blades start past the bank's crest, where the meadow is level; on the slope they poke through as slivers.
			if absf(at.x)<hx+1.1 and absf(at.z)<hz+1.1: continue
			# Grass towers over a bug: blades stand two to three bugs tall.
			var height := rng.randf_range(1.0,2.7)*lush
			var width := rng.randf_range(.07,.15)*(.7+height*.2)
			var a := rng.randf()*TAU
			var side := Vector3(cos(a),0,sin(a))
			var facing := Vector3(-sin(a),0,cos(a))
			var lean := facing*rng.randf_range(.1,.4)*height+Vector3(off.x,0,off.y)*.4
			# Blades beside the arena lean away from it, never over it.
			if absf(at.x) > hx+.62 and absf(at.z) < hz+1.5: lean.x = absf(lean.x)*signf(at.x)
			var front := at.z-(hz+.62)
			if front > -.62 and absf(at.x) < hx+2.5:
				# The camera looks over the front edge, so the grass there is swept
				# aside: leaning outward and only as tall as it can be without its
				# tips reaching over the sand (ortho camera at ~46 degrees).
				var sweep := rng.randf_range(.3,.5)
				lean.z = sweep*height
				height = minf(height,maxf(.12,front/(1.0-sweep)))
				lean.z = sweep*height
			var shade := rng.randf()
			var low_c := base_color.lerp(mood.soil,rng.randf()*.25)
			var high_c := tip_color.lerp(base_color,shade*.35)
			var start := verts.size()
			var rows := 5
			for r in rows:
				var t := float(r)/(rows-1)
				# Wide at the root, curving to a fine point; the centre rib sits forward.
				var w := width*(1.0-pow(t,1.6))
				var p := at+Vector3(0,height*t,0)+lean*t*t
				var color := low_c.lerp(high_c,t)
				for k in [-1,0,1]:
					verts.append(p+side*w*k+facing*(w*.45 if k == 0 else 0.0))
					normals.append((facing+Vector3(0,.4,0)).normalized())
					colors.append(color); uvs.append(Vector2(height,t))
			for r in rows-1:
				var i0 := start+r*3
				for k in 2:
					indices.append_array([i0+k,i0+3+k,i0+k+1, i0+k+1,i0+3+k,i0+4+k])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var grass := MeshInstance3D.new(); grass.mesh = mesh
	var shader := Shader.new(); shader.code = GRASS_SHADER
	var material := ShaderMaterial.new(); material.shader = shader; material.set_shader_parameter("gust",rng.randf_range(.6,1.3))
	grass.material_override = material; scenery.add_child(grass)

func flower(at: Vector3, height: float, petals: Color) -> void:
	var stem := _sway_node(scenery,at,1.0)
	var lean := Vector3(rng.randf_range(-.15,.15),0,rng.randf_range(-.1,.1))*height
	Clay.rod(stem,Vector3.ZERO,Vector3(0,height,0)+lean,.045,Color("5e8535"))
	var leaf := Clay.ball(stem,Vector3(.12,height*.35,0),Vector3(.32,.07,.14),Color("6c9b48")); leaf.rotation.z = .5
	var head := Node3D.new(); head.position = Vector3(0,height,0)+lean; head.rotation = Vector3(rng.randf_range(.15,.4),rng.randf()*TAU,0); stem.add_child(head)
	var span := rng.randf_range(.38,.5)
	for i in 9:
		var a := i*TAU/9
		var petal := Clay.ball(head,Vector3(cos(a)*span,0,sin(a)*span),Vector3(span*1.25,.1,span*.55),petals)
		petal.rotation.y = -a
	Clay.ball(head,Vector3(0,.06,0),Vector3(span*1.0,.22,span*1.0),Color("e6b73f") if petals != Color("f7d34f") else Color("c9862f"))

func clover(at: Vector3, leaf_size: float) -> void:
	var tuft := _sway_node(scenery,at,.5)
	var leaf_color := (mood.moss as Color).lerp(Color("6c9b48"),.6)
	for i in 3:
		var a := i*TAU/3
		var leaf := Clay.ball(tuft,Vector3(cos(a)*leaf_size*.2,.14,sin(a)*leaf_size*.2),Vector3(leaf_size*.5,.12,leaf_size*.4),leaf_color)
		leaf.rotation.y = -a

func reset(match_state: RefCounted) -> void:
	build_scenery(Vector2i(match_state.w,match_state.h),match_state.seed_value)
	for n in arena_root.get_children(): n.free()
	for n in flame_root.get_children(): n.free()
	for n in burst_root.get_children(): n.free()
	obstacles.clear(); bomb_views.clear(); pickup_views.clear(); blast_views.clear(); last_flames = ""; shake = 0.0
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
			bomb_views[b.id] = Clay.bomb(arena_root)
			_mark_bomb(bomb_views[b.id],b)
		# Kicked bombs glide between cells instead of hopping.
		bomb_views[b.id].position = world(Vector2(b.cell)+Vector2(b.get("slide",Vector2i.ZERO))*b.get("glide",0.0))
		# Remote bombs sit still with a blinking light; fused ones pulse faster as they run out.
		var pulse := 1.0+sin(clock*(16 if b.time < 1 and not b.get("remote",false) else 7))*.07
		var blink: Node3D = bomb_views[b.id].get_node_or_null("Blink")
		if blink: blink.visible = b.get("remote",false) and fmod(clock,.6) < .3
		bomb_views[b.id].scale = Vector3(pulse,2-pulse,pulse)
	for id in bomb_views.keys():
		if not ids.has(id): bomb_views[id].queue_free(); bomb_views.erase(id)
	for c in match_state.pickups:
		if match_state.pickups[c].wait > 0: continue
		if not pickup_views.has(c):
			var n := Node3D.new(); arena_root.add_child(n); n.position = world(Vector2(c)); pickup_views[c] = n
			var face := Node3D.new(); n.add_child(face); face.rotation.x = deg_to_rad(-46)
			var kind: String = match_state.pickups[c].kind
			Clay.ball(face,Vector3.ZERO,Vector3(.78,.78,.19),POWER_COLORS[kind])
			var icon := Sprite3D.new(); icon.texture = POWER_ICONS[kind]
			icon.pixel_size = .0055; icon.position.z = .105; icon.shaded = true; face.add_child(icon)
		pickup_views[c].position.y = .48+sin(clock*3+c.x)*.055
		pickup_views[c].rotation.y = sin(clock*1.8+c.y)*.16
	for c in pickup_views.keys():
		if not match_state.pickups.has(c): pickup_views[c].queue_free(); pickup_views.erase(c)
	for id in blast_views.keys():
		if not blast_views[id].update(dt): blast_views[id].queue_free(); blast_views.erase(id)
	for e in match_state.events:
		if e.type == "boom":
			var blast := Explosion.new(); flame_root.add_child(blast)
			blast.setup(e.cells,world,e.cell.x*71+e.cell.y*13+next_blast)
			blast_views[next_blast] = blast; next_blast += 1
			shake = minf(shake+.05+e.cells.size()*.012,.5)
		if e.type in ["crack","out"]: burst(world(Vector2(e.cell)),Color("b99561") if e.type == "crack" else Color("3a302a"))
	for n in burst_root.get_children():
		var life: float = n.get_meta("life")-dt; n.set_meta("life",life)
		if life <= 0: n.queue_free(); continue
		var velocity: Vector3 = n.get_meta("v"); velocity.y -= dt*7; n.set_meta("v",velocity); n.position += velocity*dt; n.scale *= pow(.12,dt)

## Bomb kinds read at a glance: an antenna for remote, purple spikes for pierce, amber corners for square.
func _mark_bomb(view: Node3D, b: Dictionary) -> void:
	if b.get("remote",false):
		Clay.rod(view,Vector3(-.12,.45,0),Vector3(-.2,.82,0),.022,Color("3b3b3b"))
		var tip := Clay.ball(view,Vector3(-.2,.84,0),Vector3.ONE*.1,Color("ff3a2a"),3); tip.name = "Blink"
	if b.get("pierce",false):
		for i in 4:
			var a := i*TAU/4+PI/4
			Clay.rod(view,Vector3(cos(a)*.22,.25,sin(a)*.22),Vector3(cos(a)*.4,.25,sin(a)*.4),.045,Color("b06ad0"))
	if b.get("square",false):
		for i in 4:
			var a := i*TAU/4+PI/4
			Clay.ball(view,Vector3(cos(a)*.42,.06,sin(a)*.42),Vector3(.16,.08,.16),Color("ffb347"),1.2)

func burst(at: Vector3, color: Color) -> void:
	for i in 8:
		var n := Clay.ball(burst_root,at+Vector3(0,.35,0),Vector3.ONE*.16,color)
		n.set_meta("life",.65); n.set_meta("v",Vector3(rng.randf_range(-2,2),rng.randf_range(1,3),rng.randf_range(-2,2)))
