extends Node3D
## Small, bounded version of Growing Guns' layered fire/ember lighting approach.
## Game time drives every layer, so pause freezes effects with the match.
var fire: ShaderMaterial
var embers: MultiMeshInstance3D
var phase := 0.0
static var fire_shader: Shader
static var puff_mesh: SphereMesh

func setup(seed_value: int, connections: Array[Vector2i]) -> void:
	var random := RandomNumberGenerator.new(); random.seed=seed_value
	phase=random.randf()*TAU
	if fire_shader == null:
		fire_shader=Shader.new()
		fire_shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float age=0.0;
varying float shade;
varying float heat;
void vertex() {
 float s=INSTANCE_CUSTOM.x*30.0;
 float a=sin(VERTEX.x*11.0+s+age*12.0)*sin(VERTEX.y*13.0+s)*sin(VERTEX.z*12.0+s);
 float b=sin(VERTEX.x*25.0+s)*sin(VERTEX.z*27.0+s+age*18.0);
 shade=a*.65+b*.35;
 heat=INSTANCE_CUSTOM.y;
 VERTEX+=NORMAL*shade*.13;
 float grow=smoothstep(0.0,.08,age);
 VERTEX*=mix(.35,1.0,grow);
 VERTEX.y+=age*.25;
}
void fragment() {
 float facing=abs(dot(normalize(NORMAL),normalize(VIEW)));
 float temperature=clamp(heat*.45+facing*.3+shade*.24+(1.0-age)*.2,0.0,1.0);
 vec3 c=mix(vec3(.82,.045,.003),vec3(1.0,.32,.015),smoothstep(.2,.55,temperature));
 c=mix(c,vec3(1.0,.78,.16),smoothstep(.5,.78,temperature));
 c=mix(c,vec3(1.0,.98,.78),smoothstep(.76,.98,temperature));
 ALBEDO=c;
 EMISSION=c*.3;
 ALPHA=smoothstep(.04,.6,facing)*(1.0-smoothstep(.78,1.0,age));
}
"""
		puff_mesh=SphereMesh.new(); puff_mesh.radius=.5; puff_mesh.height=1.0; puff_mesh.radial_segments=16; puff_mesh.rings=10
	var mm:=MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.use_custom_data=true; mm.mesh=puff_mesh; mm.instance_count=11+connections.size()*2
	for i in 11:
		var a:=random.randf()*TAU
		var spread:=0.0 if i==0 else random.randf_range(.12,.33)
		var width:=random.randf_range(.28,.48) if i>0 else .66
		var height:=random.randf_range(.33,.78) if i>0 else .38
		var tilt:=Basis(Vector3(cos(a),0,sin(a)),random.randf_range(-.5,.5))
		mm.set_instance_transform(i,Transform3D(tilt.scaled(Vector3(width,height,width)),Vector3(cos(a)*spread,.12+height*.28,sin(a)*spread)))
		mm.set_instance_custom_data(i,Color(random.randf(),random.randf_range(.45,.95),0,0))
	for direction_index in connections.size():
		var direction: Vector2i=connections[direction_index]
		for j in 2:
			var at:=Vector3(direction.x,0,direction.y)*(.29+j*.20)+Vector3(0,.16,0)
			mm.set_instance_transform(11+direction_index*2+j,Transform3D(Basis.IDENTITY.scaled(Vector3(.38,.30,.38)),at))
			mm.set_instance_custom_data(11+direction_index*2+j,Color(random.randf(),.95,0,0))
	var mesh:=MultiMeshInstance3D.new(); mesh.multimesh=mm; mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(mesh)
	fire=ShaderMaterial.new(); fire.shader=fire_shader; mesh.material_override=fire
	var sparks:=MultiMesh.new(); sparks.transform_format=MultiMesh.TRANSFORM_3D; sparks.instance_count=8
	var spark:=SphereMesh.new(); spark.radius=.5; spark.height=1.0; spark.radial_segments=6; spark.rings=3; sparks.mesh=spark
	embers=MultiMeshInstance3D.new(); embers.multimesh=sparks
	var mat:=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; mat.albedo_color=Color("ffe9a3"); mat.emission_enabled=true; mat.emission=Color("ffc24c"); mat.emission_energy_multiplier=.6
	embers.material_override=mat; embers.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(embers)

func animate(remaining: float) -> void:
	var age:=clampf(1.0-remaining/.65,0,1)
	fire.set_shader_parameter("age",age)
	for i in 8:
		var a:=i*TAU/8+phase
		var radius:=.15+age*.55
		var height:=.18+sin(age*PI)*(.6+float(i%3)*.25)
		var length:=.09*(1-age)+.015
		var basis:=Basis(Vector3.FORWARD,a).scaled(Vector3(.018,length,.018))
		embers.multimesh.set_instance_transform(i,Transform3D(basis,Vector3(cos(a)*radius,height,sin(a)*radius)))
