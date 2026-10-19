local A = { enabled = true, sources = {}, last = {}, spread = { shot = 0.12, hit = 0.1, burst = 0.08 } }
function A.load()
	if not love.sound or not love.audio then
		return
	end
	for name, frequency in pairs({
		point = 740,
		finish = 980,
		blast = 90,
		hurt = 65,
		pickup = 880,
		pulse = 180,
	}) do
		local rate, count = 22050, 3308
		local data = love.sound.newSoundData(count, rate, 16, 1)
		for i = 0, count - 1 do
			local envelope = (1 - i / count) ^ 2
			data:setSample(i, math.sin(i / rate * frequency * math.pi * 2 * (1 - i / count * 0.65)) * envelope * 0.12)
		end
		A.sources[name] = love.audio.newSource(data, "static")
	end
	-- Shots, hits and kills fire constantly, so they are short, soft clicks:
	-- a puff of high-passed noise over a quick ping instead of a sine blip.
	-- A.play varies their pitch so a stream of them never drones.
	local function click(name, ms, ping, noiseLevel, pingLevel, body)
		local rate = 22050
		local count = math.floor(rate * ms / 1000)
		local data = love.sound.newSoundData(count, rate, 16, 1)
		local seed, last, phase = 7, 0, 0
		for i = 0, count - 1 do
			local t = i / count
			seed = (seed * 1103515245 + 12345) % 2147483648
			local white = seed / 1073741824 - 1
			local high = white - last
			last = white
			phase = phase + ping * (1 - t * 0.3) / rate
			local attack = math.min(1, i / 12)
			local sample = high * noiseLevel * (1 - t) ^ 6
				+ math.sin(phase * math.pi * 2) * pingLevel * (1 - t) ^ 3
				+ math.sin(i / rate * body * math.pi * 2) * pingLevel * 0.6 * (1 - t) ^ 8
			data:setSample(i, sample * attack)
		end
		A.sources[name] = love.audio.newSource(data, "static")
	end
	click("shot", 28, 2600, 0.035, 0.012, 900)
	click("hit", 34, 1900, 0.07, 0.035, 420)
	click("burst", 60, 1500, 0.11, 0.07, 260)
	-- A pilot going down: a long falling wail over a crackle, unmistakable
	-- next to the short blips of the rest of the set.
	local rate, count = 22050, 19845
	local data = love.sound.newSoundData(count, rate, 16, 1)
	local phase, noise, held = 0, 0, 0
	for i = 0, count - 1 do
		local t = i / count
		phase = phase + (620 * (1 - t) ^ 2.2 + 55) / rate
		if i % 6 == 0 then
			held = (((i * 1103515245 + 12345) % 2147483648) / 1073741824) - 1
		end
		noise = noise * 0.7 + held * 0.3
		local tone = math.sin(phase * math.pi * 2) + 0.35 * (phase % 1 < 0.5 and 1 or -1)
		local envelope = math.min(1, i / 300) * (1 - t) ^ 1.6
		data:setSample(i, (tone * 0.13 + noise * 0.09 * (1 - t)) * envelope)
	end
	A.sources.death = love.audio.newSource(data, "static")
end
function A.play(name)
	local source = A.sources[name]
	local now = love.timer and love.timer.getTime() or 0
	if A.last[name] and now - A.last[name] < (name == "shot" and 0.07 or 0.045) then
		return
	end
	if A.enabled and source then
		A.last[name] = now
		source:stop()
		local spread = A.spread[name]
		if spread then
			source:setPitch(1 + (math.random() * 2 - 1) * spread)
		end
		source:play()
	end
end
function A.mute()
	A.enabled = false
	for _, source in pairs(A.sources) do
		source:stop()
	end
end
return A
