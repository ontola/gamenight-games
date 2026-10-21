-- The three late bosses. Every beam shows a thin flickering line before it
-- burns, and every phase change flashes a ring, so nothing hits unannounced.
local U = require("shared.util")
local B = {}
B.specs = {
	prism = { hp = 130, r = 26, speed = 0, value = 1600, boss = true },
	sun = { hp = 300, r = 54, speed = 28, value = 2400, boss = true },
	singularity = { hp = 520, r = 60, speed = 0, value = 6000, boss = true, final = true },
	node = { hp = 1, r = 15, speed = 0, value = 0, armor = true },
}
B.colors = {
	prism = { 0.75, 0.95, 1 },
	sun = { 1, 0.62, 0.18 },
	singularity = { 0.78, 0.4, 1 },
	node = { 0.55, 0.3, 0.95 },
}
-- Beam timings in seconds: off, warn, live.
local SUN_CYCLE = { 2.2, 1.2, 2.6 }
local CORE_CYCLE = { 2.6, 1.2, 2.2 }
local TWIN_CYCLE = { 1.8, 1.1, 2.1 }
local function shoot(s, M, x, y, a, speed)
	if #s.hostile < M.limits.hostile then
		s.hostile[#s.hostile + 1] = { x = x, y = y, vx = math.cos(a) * speed, vy = math.sin(a) * speed, ttl = 7 }
	end
end
local function cycle(clock, timing)
	local t = clock % (timing[1] + timing[2] + timing[3])
	if t < timing[1] then return nil end
	return t < timing[1] + timing[2] and "warn" or "live"
end
local function distance(px, py, x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	local t = math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / math.max(1, dx * dx + dy * dy)))
	return U.length(px - x1 - dx * t, py - y1 - dy * t)
end
local function burnBeams(s, M, e)
	for _, beam in ipairs(e.beams) do
		if beam.state == "live" then
			for _, p in ipairs(s.players) do
				if p.hp > 0 and distance(p.x, p.y, beam[1], beam[2], beam[3], beam[4]) < 9 + 11 then
					M.hurt(s, p)
				end
			end
		end
	end
end
-- Arms radiate from the centre and keep turning while they burn.
local function arms(e, count, state, length)
	e.beams = {}
	if not state then return end
	for i = 1, count do
		local a = e.armAngle + i * math.pi * 2 / count
		e.beams[i] = { e.x + math.cos(a) * e.r, e.y + math.sin(a) * e.r, e.x + math.cos(a) * length, e.y + math.sin(a) * length, state = state }
	end
end
function B.spawned(s, M, e, delay)
	e.beams, e.clock, e.armAngle = {}, 0, 0
	if e.kind == "prism" and not s.spawningTwin then
		s.spawningTwin = true
		local twin = M.spawn(s, "prism", s.width - e.x, e.y, delay)
		s.spawningTwin = nil
		if twin then
			e.twin, twin.twin, twin.follower = twin, e, true
		end
	elseif e.kind == "singularity" then
		e.phase, e.nodes = 1, {}
		B.shield(s, M, e, delay)
	end
end
function B.shield(s, M, e, delay)
	for _, node in ipairs(e.nodes) do node.dead = true end
	e.nodes = {}
	for i = 1, 8 do
		local node = M.spawn(s, "node", e.x, e.y, delay or 0.3)
		if not node then break end
		node.head, node.slot = e, i
		e.nodes[#e.nodes + 1] = node
	end
end
-- Shield nodes ride a ring around the core and die with it.
function B.node(s, M, e)
	if e.head.dead then
		M.kill(s, e)
		return
	end
	local h = e.head
	local a = (h.spin or 0) + e.slot * math.pi / 4
	local radius = h.phase == 3 and 150 or 125
	e.x, e.y = h.x + math.cos(a) * radius, h.y + math.sin(a) * radius
end
function B.step(s, M, e, dx, dy, length, dt)
	e.clock = e.clock + dt
	local enraged = e.hp < e.maxHp / 2
	if e.kind == "prism" then
		local lead = e.follower and e.twin and not e.twin.dead and e.twin or e
		if lead == e then
			e.orbit = (e.orbit or 0) + dt * (e.twin and not e.twin.dead and 0.32 or 0.6)
		end
		local cx, cy = s.width / 2, s.height / 2
		local radius = math.min(s.width, s.height) * 0.36 + math.sin(s.time * 0.6) * 60
		local a = lead.orbit + (lead == e and 0 or math.pi)
		local tx, ty = cx + math.cos(a) * radius * 1.35, cy + math.sin(a) * radius
		e.x, e.y = e.x + (tx - e.x) * math.min(1, dt * 2), e.y + (ty - e.y) * math.min(1, dt * 2)
		e.fire = e.fire - dt
		if e.twin and not e.twin.dead then
			-- The leader owns the beam strung between the twins.
			if lead == e then
				local state = cycle(e.clock, TWIN_CYCLE)
				e.beams = state and { { e.x, e.y, e.twin.x, e.twin.y, state = state } } or {}
				burnBeams(s, M, e)
			end
			if e.fire <= 0 then
				e.fire = 2.6
				for i = -1, 1 do shoot(s, M, e.x, e.y, math.atan2(dy, dx) + i * 0.22, 210) end
			end
		else
			-- Alone, the survivor spins a dense spiral.
			e.beams = {}
			if e.fire <= 0 then
				e.fire = 0.14
				e.armAngle = e.armAngle + 0.5
				for i = 0, 2 do shoot(s, M, e.x, e.y, e.armAngle + i * math.pi * 2 / 3, 170) end
			end
		end
		return 0
	elseif e.kind == "sun" then
		local cx, cy = s.width / 2 + math.sin(s.time * 0.3) * 180, s.height / 2 + math.cos(s.time * 0.4) * 90
		e.x, e.y = e.x + (cx - e.x) * dt * 0.6, e.y + (cy - e.y) * dt * 0.6
		e.armAngle = e.armAngle + dt * (enraged and 0.55 or 0.38)
		arms(e, enraged and 4 or 3, cycle(e.clock, SUN_CYCLE), 1600)
		burnBeams(s, M, e)
		e.fire = e.fire - dt
		if e.fire <= 0 then
			-- Solar flare: a ring with a wide gap to slip through.
			e.fire = enraged and 2.2 or 3
			local gap = s.rng() * math.pi * 2
			for i = 0, 23 do
				local a = gap + i * math.pi / 12
				if i > 2 then shoot(s, M, e.x, e.y, a, 165) end
			end
		end
		return 0
	elseif e.kind == "singularity" then
		local phase = e.hp > e.maxHp * 2 / 3 and 1 or e.hp > e.maxHp / 3 and 2 or 3
		if phase ~= e.phase then
			e.phase = phase
			M.ring(s, e.x, e.y, 260, B.colors.singularity)
			M.ring(s, e.x, e.y, 180, { 1, 1, 1 })
			s.shake = 5
			e.clock, e.summon = 0, 3
			B.shield(s, M, e, 0.8)
		end
		e.x, e.y = e.x + (s.width / 2 - e.x) * dt, e.y + (s.height / 2 - e.y) * dt
		e.spin = (e.spin or 0) + dt * (phase == 3 and 1.1 or 0.7)
		-- The event horizon drags everyone in; a dash breaks free.
		local pull = ({ 55, 85, 125 })[phase]
		for _, p in ipairs(s.players) do
			if p.hp > 0 and p.dash == 0 then
				local x, y = e.x - p.x, e.y - p.y
				local d = math.max(1, U.length(x, y))
				p.x, p.y = p.x + x / d * pull * dt, p.y + y / d * pull * dt
			end
		end
		e.fire = e.fire - dt
		if e.fire <= 0 then
			e.fire = phase == 1 and 0.16 or 0.13
			e.armAngle = e.armAngle + 0.29
			local count = phase == 3 and 3 or 2
			for i = 0, count - 1 do
				shoot(s, M, e.x, e.y, e.armAngle + i * math.pi * 2 / count, phase == 3 and 175 or 150)
			end
		end
		if phase >= 2 then
			e.beamAngle = (e.beamAngle or 0) - dt * (phase == 3 and 0.45 or 0.3)
			local save = e.armAngle
			e.armAngle = e.beamAngle
			arms(e, phase == 3 and 4 or 2, cycle(e.clock, CORE_CYCLE), 1600)
			e.armAngle = save
			burnBeams(s, M, e)
			e.summon = (e.summon or 3) - dt
			if e.summon <= 0 then
				-- Echoes of the earlier waves pour in from the edges.
				e.summon = phase == 3 and 7 or 10
				for i = 1, 4 do
					local a = s.rng() * math.pi * 2
					M.spawn(s, i == 4 and "dasher" or "chaser", s.width / 2 + math.cos(a) * s.width * 0.48, s.height / 2 + math.sin(a) * s.height * 0.46, 1.2)
				end
			end
		else
			e.beams = {}
		end
		return 0
	end
end
function B.killed(s, M, e)
	e.beams = {}
	if e.kind == "prism" and e.twin and not e.twin.dead then
		M.ring(s, e.twin.x, e.twin.y, 120, B.colors.prism)
	elseif e.kind == "singularity" then
		s.won = true
		s.victoryClock = 0
		M.ring(s, e.x, e.y, 400, { 1, 1, 1 })
		M.ring(s, e.x, e.y, 260, B.colors.singularity)
		s.hostile = {}
		for _, other in ipairs(s.enemies) do
			if other ~= e and not other.dead then M.kill(s, other) end
		end
	end
end
return B
