extends Node3D
## One bomb's blast, ported from Growing Guns' layered explosion (violence.gd):
## lumpy fire clouds along every burning cell, flame tongues licking down the
## rays, additive embers, lingering dust smoke, a flash and a fireball light,
## and a scorch mark left on the sand. Each layer is one MultiMesh driven by a
## single `anim` uniform; game time drives it, so pausing freezes the blast.
const FIRE_LIFE := .72
const BILLOW_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float anim = 0.0;
uniform float is_fire = 0.0;
uniform float edge_power = 2.1;
uniform float lump_amount = 0.32;
uniform float growth_min = 0.35;
uniform float tail_power = 1.5;
uniform vec3 smoke_tint : source_color = vec3(1.0);
varying float v_age;
varying float v_heat;
varying vec3 v_body;
varying float v_opk;
varying float v_shade;
void vertex() {
 float seed = INSTANCE_CUSTOM.x;
 float delay = INSTANCE_CUSTOM.y;
 v_heat = INSTANCE_CUSTOM.z;
 v_body = COLOR.rgb;
 v_opk = COLOR.a;
 v_age = clamp((anim-delay)*(1.0+INSTANCE_CUSTOM.w)/max(1.0-delay,0.001),0.0,1.0);
 float s = seed*100.0;
 float a = sin(VERTEX.x*6.3+s)*sin(VERTEX.y*5.1+s*1.7)*sin(VERTEX.z*7.2+s*.9);
 float b = sin(VERTEX.x*13.0+s*2.1)*sin(VERTEX.z*11.0+s*1.3);
 float c = sin(VERTEX.x*21.0+s*3.3)*sin(VERTEX.y*18.0+s*2.1)*sin(VERTEX.z*25.0+s*1.5);
 v_shade = (a*.7+b*.3)*.55+c*.45;
 VERTEX += NORMAL*(a*.7+b*.3)*lump_amount;
 VERTEX *= mix(growth_min,1.0,v_age);
}
void fragment() {
 float facing = abs(dot(normalize(NORMAL),normalize(VIEW)));
 float fres = pow(1.0-facing,edge_power);
 float fade_in = smoothstep(0.0,.12,v_age);
 float t = clamp((v_age-.12)/.88,0.0,1.0);
 float fade_out = pow(1.0-t,tail_power)*(1.0-smoothstep(.5,1.0,t));
 ALPHA = v_opk*fade_in*fade_out*smoothstep(0.0,.85,facing);
 vec2 px_cell = floor(UV*vec2(8.0,5.0));
 float cell_band = mod(px_cell.x+px_cell.y,3.0)-1.0;
 if (is_fire > .5) {
  float heat = clamp(v_heat+cell_band*.06,0.0,1.0);
  float age_cool = 1.0-smoothstep(0.0,.75,v_age);
  float fire_band = clamp(heat*.6+facing*.25+age_cool*.15,0.0,1.0);
  vec3 color = vec3(.03,.025,.02);
  color = mix(color,vec3(.30,.09,.025),smoothstep(.05,.34,fire_band));
  color = mix(color,vec3(1.0,.24,.04),smoothstep(.30,.54,fire_band));
  color = mix(color,vec3(1.0,.62,.12),smoothstep(.52,.74,fire_band));
  color = mix(color,vec3(1.0,.95,.72),smoothstep(.74,.94,fire_band));
  // HDR like Growing Guns: the hot core blooms through the garden's glow pass.
  ALBEDO = color*mix(.5,3.2,fire_band*fire_band);
 } else {
  float shade = clamp(.45+.85*(v_shade*.5+.5)+cell_band*.05,0.0,1.0);
  vec3 body = v_body*shade;
  body = mix(body,body*.35,fres);
  ALBEDO = body*smoke_tint;
 }
}
"""
const SPARK_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_add;
uniform float anim = 0.0;
uniform vec3 tint : source_color = vec3(1.0,.7,.3);
uniform float brightness = 2.0;
uniform float size_scale = 1.0;
uniform float elong_max = 8.0;
varying float v_b;
void vertex() {
 vec3 travel = INSTANCE_CUSTOM.xyz;
 float delay = INSTANCE_CUSTOM.w;
 float size = COLOR.r*size_scale;
 float elong = 1.0+COLOR.g*(elong_max-1.0);
 float age = clamp((anim-delay)/max(1.0-delay,.001),0.0,1.0);
 float prog = 1.0-pow(1.0-age,2.0);
 float dist = length(travel);
 vec3 dir = dist > .0001 ? travel/dist : vec3(0.0,1.0,0.0);
 vec3 upv = abs(dir.y) < .99 ? vec3(0.0,1.0,0.0) : vec3(1.0,0.0,0.0);
 vec3 ex = normalize(cross(upv,dir));
 vec3 ez = cross(dir,ex);
 vec3 v = VERTEX*size;
 v.y *= mix(1.0,elong,prog);
 // Sparks arc: fly out decelerating, then gravity pulls them back to the sand.
 VERTEX = ex*v.x+dir*v.y+ez*v.z+travel*prog-vec3(0.0,age*age*dist*.6,0.0);
 v_b = (1.0-smoothstep(.35,1.0,age))*COLOR.a;
}
void fragment() {
 ALBEDO = tint*brightness;
 ALPHA = v_b;
}
"""
const SCORCH_CODE := """shader_type spatial;
render_mode unshaded, depth_draw_never, shadows_disabled;
uniform float fade = 1.0;
uniform float seed = 0.0;
void fragment() {
 vec2 p = UV*2.0-1.0;
 float a = atan(p.y,p.x);
 float edge = .8+.07*sin(a*3.0+seed)+.04*sin(a*7.0+seed*2.3);
 float d = length(p)/edge;
 ALBEDO = vec3(.11,.075,.05);
 ALPHA = (1.0-smoothstep(.15,1.0,d))*.5*fade;
}
"""
static var billow_shader: Shader
static var spark_shader: Shader
static var scorch_shader: Shader
static var puff_mesh: SphereMesh
static var spark_mesh: SphereMesh
var layers: Array = []   # [material, life, start delay, rise node or null, rise]
var lights: Array = []   # [light, peak, hold, decay, color]
var scorch: ShaderMaterial
var age := 0.0
var size := 1.0

## cells: every burning cell of this blast (the bomb's own cell first).
## world_of maps a cell to its world position.
func setup(cells: Array, world_of: Callable, seed_value: int) -> void:
	if billow_shader == null:
		billow_shader = Shader.new(); billow_shader.code = BILLOW_CODE
		spark_shader = Shader.new(); spark_shader.code = SPARK_CODE
		scorch_shader = Shader.new(); scorch_shader.code = SCORCH_CODE
		puff_mesh = SphereMesh.new(); puff_mesh.radius = .5; puff_mesh.height = 1.0; puff_mesh.radial_segments = 16; puff_mesh.rings = 9
		spark_mesh = SphereMesh.new(); spark_mesh.radius = .06; spark_mesh.height = .12; spark_mesh.radial_segments = 5; spark_mesh.rings = 3
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var center: Vector2i = cells[0]
	var origin: Vector3 = world_of.call(Vector2(center))
	position = origin
	size = float(cells.size())
	# Bigger blasts burn a touch longer, the way GG scales life with radius.
	var big := clampf((size-5.0)/30.0,0.0,1.0)
	var fire_puffs: Array = []
	var smoke_puffs: Array = []
	var tongues: Array = []
	for c in cells:
		var at: Vector3 = world_of.call(Vector2(c))-origin
		var is_center: bool = c == center
		var steps: int = absi(c.x-center.x)+absi(c.y-center.y)
		var stagger := steps*.035
		for i in (9 if is_center else 4):
			var off := Vector3(rng.randf_range(-.3,.3),rng.randf_range(.15,.6)+(i*.09 if is_center else 0.0),rng.randf_range(-.3,.3))
			var heat := (1.0 if is_center else .8)*rng.randf_range(.75,1.0)
			fire_puffs.append([at+off,rng.randf_range(.75,1.2)*(1.3 if is_center else 1.0),stagger+rng.randf_range(0,.12),heat,Vector3.ZERO,1.0])
		if rng.randf() < (1.0 if is_center else .45):
			smoke_puffs.append([at+Vector3(rng.randf_range(-.2,.2),rng.randf_range(.3,.7),rng.randf_range(-.2,.2)),rng.randf_range(.8,1.4),stagger+.22+rng.randf_range(0,.1)])
	# Flame tongues shoot out from the centre and from each ray's tip.
	for i in 5:
		var a := rng.randf()*TAU
		tongues.append([Vector3(0,.4,0),.6,rng.randf_range(0,.06),.9,Vector3(cos(a)*.35,1.0,sin(a)*.35).normalized(),2.2])
	for c in cells:
		if c == center: continue
		var d: Vector2i = (c-center).sign()
		if cells.has(c+d): continue
		var dir := Vector3(d.x,.35,d.y).normalized()
		var at: Vector3 = world_of.call(Vector2(c))-origin
		var steps: int = absi(c.x-center.x)+absi(c.y-center.y)
		tongues.append([at+Vector3(0,.3,0),.55,steps*.035+.04,.8,dir,2.4])
	_billow(fire_puffs,true,FIRE_LIFE+big*.25,0.0,rng)
	_billow(tongues,true,.5+big*.15,0.0,rng)
	_billow(smoke_puffs,false,1.6+big*1.2,.9+big*.6,rng)
	_sparks(cells,world_of,origin,rng)
	# Flash: a short white pop, then the warm fireball glow (GG's two lights).
	var reach := clampf(2.4+size*.12,2.6,7.0)
	_light(Vector3(0,1.0,0),reach,2.2+big*1.6,.03,.12,Color("fff2d6"))
	_light(Vector3(0,.7,0),reach*1.3,1.4+big*1.0,.08,.5+big*.3,Color("ff9a3c"))
	var mark := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size = Vector2.ONE*clampf(1.4+size*.05,1.4,2.6); mark.mesh = quad
	mark.rotation.x = -PI/2; mark.position.y = .012
	scorch = ShaderMaterial.new(); scorch.shader = scorch_shader; scorch.set_shader_parameter("seed",rng.randf()*10)
	mark.material_override = scorch; mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mark)

func _billow(puffs: Array, fire: bool, life: float, rise: float, rng: RandomNumberGenerator) -> void:
	if puffs.is_empty(): return
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.use_custom_data = true
	mm.mesh = puff_mesh; mm.instance_count = puffs.size()
	for i in puffs.size():
		var p: Array = puffs[i]
		var scale: float = p[1]
		var basis := Basis.IDENTITY.scaled(Vector3.ONE*scale)
		if fire and p.size() > 4 and p[5] > 1.01:
			# Stretch along the tongue's direction (scale the columns, as GG does).
			var dir: Vector3 = p[4]
			var up := Vector3.UP if absf(dir.y) < .95 else Vector3.RIGHT
			var ex := up.cross(dir).normalized(); var ez := dir.cross(ex)
			basis = Basis(ex*scale,dir*scale*p[5],ez*scale)
			p[0] += dir*scale*.5
		mm.set_instance_transform(i,Transform3D(basis,p[0]))
		if fire:
			mm.set_instance_color(i,Color(1,1,1,rng.randf_range(.8,.95)))
			mm.set_instance_custom_data(i,Color(rng.randf(),p[2]/life,p[3],rng.randf_range(0,.6)))
		else:
			# Dusty garden smoke: sandy grey rather than GG's black battlefield smoke.
			var g := rng.randf_range(.58,.78)
			mm.set_instance_color(i,Color(g*1.06,g,g*.9,rng.randf_range(.5,.72)))
			mm.set_instance_custom_data(i,Color(rng.randf(),p[2]/life,0,rng.randf_range(0,.5)))
	var node := MultiMeshInstance3D.new(); node.multimesh = mm; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-14,-1,-14),Vector3(28,8,28))
	var mat := ShaderMaterial.new(); mat.shader = billow_shader
	mat.set_shader_parameter("is_fire",1.0 if fire else 0.0)
	mat.set_shader_parameter("tail_power",2.2 if fire else .5)
	mat.set_shader_parameter("lump_amount",.32 if fire else .26)
	if not fire: mat.set_shader_parameter("smoke_tint",Color("d9cdb8"))
	node.material_override = mat; add_child(node)
	layers.append([mat,life,node,rise])

func _sparks(cells: Array, world_of: Callable, origin: Vector3, rng: RandomNumberGenerator) -> void:
	var count := clampi(int(size*2.0),12,50)
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.use_custom_data = true
	mm.mesh = spark_mesh; mm.instance_count = count
	for i in count:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var from: Vector3 = world_of.call(Vector2(c))-origin+Vector3(0,.3,0)
		var a := rng.randf()*TAU; var elev := rng.randf_range(.2,1.3)
		var dir := Vector3(cos(a)*cos(elev),sin(elev),sin(a)*cos(elev))
		var travel := dir*rng.randf_range(.6,1.8)
		var sz := rng.randf_range(.5,1.2)
		mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,from))
		mm.set_instance_color(i,Color(sz,rng.randf_range(.2,.7),1,rng.randf_range(.6,1.0)))
		mm.set_instance_custom_data(i,Color(travel.x,travel.y,travel.z,rng.randf_range(0,.15)))
	var node := MultiMeshInstance3D.new(); node.multimesh = mm; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = AABB(Vector3(-14,-1,-14),Vector3(28,8,28))
	var mat := ShaderMaterial.new(); mat.shader = spark_shader
	mat.set_shader_parameter("tint",Color("ff9a3a")); mat.set_shader_parameter("brightness",2.0); mat.set_shader_parameter("elong_max",3.0); mat.set_shader_parameter("size_scale",1.0)
	node.material_override = mat; add_child(node)
	layers.append([mat,.55+clampf(size/60.0,0,.35),node,0.0])

func _light(at: Vector3, reach: float, peak: float, hold: float, decay: float, color: Color) -> void:
	var light := OmniLight3D.new(); light.position = at; light.omni_range = reach; light.omni_attenuation = 1.1
	light.shadow_enabled = false; light.light_color = color; light.light_energy = peak; add_child(light)
	lights.append([light,peak,hold,decay])

## Advances the blast; returns false once every layer has burnt out.
func update(dt: float) -> bool:
	age += dt
	var alive := false
	for layer in layers:
		var t := clampf(age/float(layer[1]),0,1)
		layer[0].set_shader_parameter("anim",t)
		if layer[3] > 0: layer[2].position.y = layer[3]*t
		if t < 1: alive = true
		layer[2].visible = t < 1
	for l in lights:
		var light: OmniLight3D = l[0]
		var k := 1.0 if age < l[2] else maxf(0.0,1.0-(age-l[2])/l[3])
		light.light_energy = l[1]*k*k
		light.visible = k > 0
	# The scorch mark outlives the fire and slowly weathers away.
	scorch.set_shader_parameter("fade",clampf(1.0-(age-3.0)/4.0,0,1))
	return alive or age < 7.0
