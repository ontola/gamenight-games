extends RefCounted
## Explosion sounds ported from Growing Guns (scripts/sfx.gd): a saturated
## bang (thwack + swept noise + kick drum + sub rumble, wrapped in tanh) and a
## brown-noise rumble whose length and depth grow with the blast radius. Both
## layers are mixed into one clip per radius bucket and variant.
const MIX_RATE := 44100.0
## Blast radii in Growing Guns metres; a one-cell pop maps to the first, a
## garden-wide mega blast to the last.
const RADII := [5.0,8.0,11.0,14.0,18.0]
const VARIANTS := 2

## clips[bucket][variant] -> AudioStreamWAV
static func build_all() -> Array:
	var out := []
	for r in RADII:
		var row := []
		for v in VARIANTS: row.append(clip(r,v))
		out.append(row)
	return out

## Which bucket a blast of `cells` burning cells sounds like.
static func bucket(cells: int) -> int:
	var radius := 3.0+sqrt(float(maxi(cells,1)))*2.2
	var best := 0
	for i in RADII.size():
		if absf(RADII[i]-radius) < absf(RADII[best]-radius): best = i
	return best

## Loudness in dB for a blast of `cells` cells: a lone pop sits well under a mega blast.
static func volume_db(cells: int) -> float:
	return lerpf(-9.0,0.0,clampf(log(float(maxi(cells,1)))/log(45.0),0.0,1.0))

static func clip(radius: float, variant: int) -> AudioStreamWAV:
	var bang := _bang(radius,variant)
	var rumble := _rumble(radius,variant)
	var n := maxi(bang.size(),rumble.size())
	var mixed := PackedFloat32Array(); mixed.resize(n)
	var peak := 0.0
	for i in n:
		var s := (bang[i] if i < bang.size() else 0.0)+(rumble[i]*.75 if i < rumble.size() else 0.0)
		mixed[i] = s; peak = maxf(peak,absf(s))
	var data := PackedByteArray(); data.resize(n*2)
	var gain := .95/maxf(peak,.001)
	for i in n: data.encode_s16(i*2,int(clampf(mixed[i]*gain,-1,1)*32000))
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = int(MIX_RATE); wav.data = data
	return wav

static func _bang(radius: float, variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new(); rng.seed = hash([radius,variant,"bang"])
	var bright_jit := lerpf(.85,1.15,rng.randf())
	var thwack_decay := lerpf(180.0,280.0,rng.randf())
	var thwack_drive := lerpf(4.0,8.0,rng.randf())
	var dur_jit := lerpf(.92,1.10,rng.randf())
	var r_norm := clampf(radius/6.0,.3,4.0)
	var kick_f0 := 220.0*lerpf(.88,1.12,rng.randf())
	var kick_f1 := clampf(55.0/sqrt(r_norm),28.0,80.0)*lerpf(.92,1.10,rng.randf())
	var kick_sweep_rate := lerpf(70.0,95.0,rng.randf())
	var kick_decay := clampf(35.0/sqrt(r_norm),10.0,40.0)
	var kick_gain := lerpf(.55,.95,clampf((r_norm-1.0)/3.0,0.0,1.0))
	var sub_cutoff_k := lerpf(.005,.010,rng.randf())
	var sub_decay := clampf(3.5/sqrt(r_norm),1.2,4.0)
	var dur := clampf((.4+radius*.08)*dur_jit,.4,1.6)
	var n := int(dur*MIX_RATE)
	var thwack_cutoff_k := lerpf(.10,.16,rng.randf())
	var noise_brightness := clampf(.45*bright_jit,.05,.95)
	var noise_decay := lerpf(8.0,15.0,rng.randf())
	var out := PackedFloat32Array(); out.resize(n)
	var lp := 0.0; var thwack_lp := 0.0; var sub_lp := 0.0; var kick_phase := 0.0; var kick_lp := 0.0
	for i in n:
		var t := float(i)/MIX_RATE
		var env := exp(-t*1.4)*pow(1.0-t/dur,.6)
		thwack_lp = lerpf(thwack_lp,rng.randf_range(-1.0,1.0),thwack_cutoff_k)
		var thwack := tanh(thwack_lp*thwack_drive)*1.5*exp(-t*thwack_decay)
		lp = lerpf(lp,rng.randf_range(-1.0,1.0),noise_brightness)
		var kick_freq := kick_f1+(kick_f0-kick_f1)*exp(-t*kick_sweep_rate)
		kick_phase += TAU*kick_freq/MIX_RATE
		kick_lp = lerpf(kick_lp,sin(kick_phase),.30)
		sub_lp = lerpf(sub_lp,rng.randf_range(-1.0,1.0),sub_cutoff_k)
		out[i] = tanh((thwack+lp*.5*exp(-t*noise_decay)+kick_lp*exp(-t*kick_decay)*kick_gain+sub_lp*3.5*exp(-t*sub_decay)*.7)*env*1.4)
	return out

static func _rumble(radius: float, variant: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new(); rng.seed = hash([radius,variant,"rumble"])
	var r_norm := clampf(radius,2.0,24.0)/24.0
	var dur := clampf(.3+r_norm*r_norm*4.7,.3,5.0)
	var n := int(dur*MIX_RATE)
	var cutoff := clampf(220.0-radius*7.0,55.0,200.0)+rng.randf_range(-15.0,15.0)
	var lp_k := clampf(TAU*cutoff/MIX_RATE,.005,.4)
	var attack_dur := lerpf(.05,.12,rng.randf())
	var ease_power := lerpf(2.4,3.0,rng.randf())
	var gain := 1.5*sqrt(6.0/maxf(6.0,radius))
	var body_dur := maxf(dur-attack_dur,.0001)
	var brown := 0.0; var lp := 0.0
	var out := PackedFloat32Array(); out.resize(n)
	for i in n:
		var t := float(i)/MIX_RATE
		var env := clampf(t/attack_dur,0.0,1.0)*pow(1.0-clampf((t-attack_dur)/body_dur,0.0,1.0),ease_power)
		brown = brown*.998+rng.randf_range(-1.0,1.0)*.03
		lp = lerpf(lp,brown,lp_k)
		out[i] = tanh(lp*env*gain)
	return out
