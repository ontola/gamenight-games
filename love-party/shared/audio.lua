local A = { enabled = true, sources = {}, last = {} }
function A.load()
	if not love.sound or not love.audio then
		return
	end
	for name, frequency in pairs({
		point = 740,
		hit = 160,
		finish = 980,
		blast = 90,
		shot = 1100,
		burst = 120,
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
