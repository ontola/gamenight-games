extends RefCounted
## A short jingle per power-up, so every pickup is recognisable by ear.
## Each jingle is a list of notes: [start Hz, end Hz, seconds, wave, vibrato depth].
const RATE := 22050
const JINGLES := {
	"capacity": [[523.0,523.0,.07,"tri",0.0],[784.0,784.0,.11,"tri",0.0]],
	"range": [[330.0,1240.0,.24,"sine",0.0]],
	"speed": [[784.0,784.0,.035,"tri",0.0],[988.0,988.0,.035,"tri",0.0],[1175.0,1175.0,.035,"tri",0.0],[1568.0,1568.0,.09,"tri",0.0]],
	"kick": [[110.0,60.0,.06,"sine",0.0],[300.0,620.0,.16,"sine",.04]],
	"ghost": [[880.0,420.0,.42,"sine",.035]],
	"mega": [[523.0,523.0,.06,"square",0.0],[659.0,659.0,.06,"square",0.0],[784.0,784.0,.06,"square",0.0],[1047.0,1047.0,.26,"square",.012]],
	"remote": [[1320.0,1320.0,.05,"square",0.0],[0.0,0.0,.04,"sine",0.0],[1320.0,1320.0,.05,"square",0.0],[1760.0,1760.0,.08,"square",0.0]],
	"pierce": [[2200.0,700.0,.2,"saw",0.0]],
	"square": [[440.0,440.0,.045,"square",0.0],[554.0,554.0,.045,"square",0.0],[659.0,659.0,.045,"square",0.0],[880.0,880.0,.1,"square",0.0]],
	"line": [[700.0,700.0,.05,"tri",0.0],[0.0,0.0,.025,"sine",0.0],[700.0,700.0,.05,"tri",0.0],[0.0,0.0,.025,"sine",0.0],[940.0,940.0,.09,"tri",0.0]],
	"skull": [[392.0,392.0,.11,"saw",.02],[370.0,370.0,.11,"saw",.02],[349.0,349.0,.11,"saw",.02],[311.0,280.0,.32,"saw",.03]],
	"detonate": [[1500.0,1500.0,.03,"square",0.0],[220.0,120.0,.05,"sine",0.0]],
	"cursed": [[330.0,330.0,.08,"saw",.02],[294.0,260.0,.18,"saw",.03]],
}

static func build_all() -> Dictionary:
	var out := {}
	for kind in JINGLES: out[kind] = clip(JINGLES[kind])
	return out

static func clip(notes: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	var phase := 0.0
	for note in notes:
		var n := int(float(note[2])*RATE)
		var start := data.size()
		data.resize(start+n*2)
		for i in n:
			var t := float(i)/RATE; var k := float(i)/n
			var f: float = lerpf(note[0],note[1],k)*(1.0+note[4]*sin(TAU*7.0*t))
			phase = fmod(phase+f/RATE,1.0)
			var v := 0.0
			match note[3]:
				"sine": v = sin(TAU*phase)
				"tri": v = 1.0-4.0*absf(phase-.5)
				"square": v = (1.0 if phase < .5 else -1.0)*.55
				"saw": v = (phase*2.0-1.0)*.6
			# Quick attack, gentle tail per note: chirpy, never clicky.
			var env := minf(t*400.0,1.0)*pow(1.0-k,1.6)
			data.encode_s16(start+i*2,int(clampf(v*env*(0.0 if note[0] == 0.0 else .8),-1,1)*24000))
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = RATE; wav.data = data
	return wav
