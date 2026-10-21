local M = {}
local Gravity=require("games.siege_gravity")
local Siege = require("games.siege")
local BossRender = require("games.siege_boss_render")
-- Each wave drifts the sky to a new pair of nebula colours.
local skies = {
	{ { 0.10, 0.30, 0.75 }, { 0.75, 0.15, 0.55 } },
	{ { 0.05, 0.55, 0.55 }, { 0.35, 0.15, 0.80 } },
	{ { 0.80, 0.30, 0.10 }, { 0.55, 0.10, 0.45 } },
	{ { 0.15, 0.60, 0.30 }, { 0.10, 0.25, 0.70 } },
}
local stars, blob
local function prepare(G)
	if stars then return end
	-- A fixed seed keeps the sky identical between frames and machines.
	local seed = 7
	local function rand()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	stars = {}
	for i = 1, 220 do
		local layer = i % 3 + 1
		stars[i] = { x = rand(), y = rand(), layer = layer, size = 0.6 + layer * 0.45 * rand(), twinkle = rand() * 6.28 }
	end
	local data = love.image.newImageData(128, 128)
	data:mapPixel(function(x, y)
		local d = math.sqrt((x - 63.5) ^ 2 + (y - 63.5) ^ 2) / 64
		local a = math.max(0, 1 - d) ^ 2.2
		return 1, 1, 1, a
	end)
	blob = G.newImage(data)
	blob:setFilter("linear", "linear")
end
local function mix(a, b, t)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end
function M.background(s, G)
	prepare(G)
	local w, h, t = s.width, s.height, s.time
	-- Blend toward the next wave's sky over the first seconds of a wave.
	local index = math.max(0, s.wave - 1)
	local from = skies[(math.max(0, index - 1)) % #skies + 1]
	local to = skies[index % #skies + 1]
	local k = s.wavePhase == "attack" and math.min(1, (s.waveClock or 0) / 4) or 1
	if s.wavePhase ~= "attack" then from = to end
	local c1, c2 = mix(from[1], to[1], k), mix(from[2], to[2], k)
	G.setColor(0.012, 0.016, 0.04)
	G.rectangle("fill", -10, -10, w + 20, h + 20)
	G.setBlendMode("add")
	-- Large slow nebula clouds.
	local clouds = {
		{ 0.22, 0.30, 1.10, c1, 0.2 }, { 0.78, 0.65, 1.25, c2, 0.18 }, { 0.55, 0.15, 0.80, c2, 0.11 },
		{ 0.10, 0.85, 0.90, c2, 0.1 }, { 0.90, 0.20, 0.70, c1, 0.12 }, { 0.45, 0.60, 0.65, c1, 0.08 },
	}
	for i, c in ipairs(clouds) do
		local x = c[1] * w + math.sin(t * 0.03 + i) * 40
		local y = c[2] * h + math.cos(t * 0.025 + i * 2) * 30
		local scale = c[3] * h / 128 * (1 + 0.05 * math.sin(t * 0.2 + i))
		G.setColor(c[4][1], c[4][2], c[4][3], c[5])
		G.draw(blob, x, y, t * 0.01 * (i % 2 == 0 and 1 or -1), scale * 1.4, scale, 64, 64)
	end
	-- Parallax stars drift slowly; nearer layers move faster and twinkle.
	for _, star in ipairs(stars) do
		local speed = star.layer * 4
		local x = (star.x * w - t * speed) % (w + 20) - 10
		local y = (star.y * h + t * speed * 0.35) % (h + 20) - 10
		local alpha = 0.25 + star.layer * 0.18 + 0.2 * math.sin(t * (1 + star.layer) + star.twinkle)
		G.setColor(0.75, 0.85, 1, alpha)
		G.circle("fill", x, y, star.size)
	end
	G.setBlendMode("alpha")
	-- Each boss stage has its own landmark, growing stranger toward the end.
	local stage, fade = M.stage(s)
	if fade < 1 and stage > 1 then M.landmark(stage - 1, G, w, h, t, 1 - fade) end
	M.landmark(stage, G, w, h, t, fade)
end
-- Stage 1..6 follows the boss every fourth wave; a new stage fades in.
function M.stage(s)
	local wave = math.max(1, s.wave)
	local stage = math.min(6, math.ceil(wave / 4))
	local first = (wave - 1) % 4 == 0 and s.wavePhase == "attack"
	return stage, first and math.min(1, (s.waveClock or 0) / 4) or 1
end
local function glow(G, x, y, r, color, alpha)
	G.setBlendMode("add")
	G.setColor(color[1], color[2], color[3], alpha)
	G.draw(blob, x, y, 0, r / 64, r / 64, 64, 64)
	G.setBlendMode("alpha")
end
local function planet(G, px, py, pr, base, bands, light, a)
	G.stencil(function() G.circle("fill", px, py, pr) end, "replace", 1)
	G.setStencilTest("equal", 1)
	G.setColor(base[1], base[2], base[3], a)
	G.circle("fill", px, py, pr)
	for i, b in ipairs(bands) do
		G.setColor(b[1], b[2], b[3], a * 0.8)
		G.rectangle("fill", px - pr, py - pr + (i - 1) * pr * 2 / #bands, pr * 2, pr * 2 / #bands * 0.55)
	end
	-- Night side: darken away from the light.
	for i = 1, 8 do
		G.setColor(0, 0, 0.02, a * 0.11)
		G.circle("fill", px + light[1] * pr * (0.2 + i * 0.07), py + light[2] * pr * (0.2 + i * 0.07), pr)
	end
	G.setStencilTest()
end
function M.landmark(stage, G, w, h, t, a)
	if stage == 1 then
		-- Saturn, low in the corner.
		local px, py, pr = w * 0.84, h * 0.82, h * 0.2
		G.setColor(0.85, 0.72, 0.45, 0.25 * a)
		G.setLineWidth(10)
		G.arc("line", "open", px, py, pr * 1.85, math.pi * 1.06, math.pi * 1.94, 40)
		planet(G, px, py, pr, { 0.55, 0.45, 0.28 }, { { 0.7, 0.58, 0.36 }, { 0.48, 0.38, 0.24 }, { 0.75, 0.63, 0.4 }, { 0.5, 0.4, 0.26 }, { 0.68, 0.56, 0.35 } }, { 1, 0.8 }, 0.55 * a)
		G.push()
		G.translate(px, py)
		G.rotate(-0.25)
		G.setColor(0.9, 0.78, 0.5, 0.5 * a)
		G.setLineWidth(4)
		G.ellipse("line", 0, 0, pr * 1.75, pr * 0.36)
		G.setColor(0.75, 0.62, 0.4, 0.3 * a)
		G.setLineWidth(10)
		G.ellipse("line", 0, 0, pr * 1.95, pr * 0.42)
		G.pop()
	elseif stage == 2 then
		-- A storm giant with a red eye, and two moons.
		local px, py, pr = w * 0.12, h * 0.16, h * 0.34
		glow(G, px, py, pr * 1.6, { 0.9, 0.5, 0.3 }, 0.12 * a)
		planet(G, px, py, pr, { 0.6, 0.42, 0.3 }, { { 0.8, 0.6, 0.42 }, { 0.55, 0.35, 0.25 }, { 0.85, 0.7, 0.5 }, { 0.6, 0.38, 0.28 }, { 0.8, 0.62, 0.45 }, { 0.5, 0.33, 0.24 }, { 0.78, 0.6, 0.42 } }, { -0.7, -0.7 }, 0.6 * a)
		G.setColor(0.85, 0.3, 0.2, 0.55 * a)
		G.ellipse("fill", px + pr * 0.35, py + pr * 0.35, pr * 0.2, pr * 0.11)
		for i = 1, 2 do
			local m = t * 0.05 * i + i * 2
			G.setColor(0.75, 0.75, 0.8, 0.5 * a)
			G.circle("fill", px + math.cos(m) * pr * (1.5 + i * 0.4), py + math.sin(m) * pr * 0.5 + pr * 0.6, 6 + i * 4)
		end
	elseif stage == 3 then
		-- A burning sun just off the edge.
		local px, py, pr = w * 0.92, h * 0.12, h * 0.3
		glow(G, px, py, pr * 4.5, { 1, 0.4, 0.1 }, 0.35 * a)
		glow(G, px, py, pr * 2.4, { 1, 0.7, 0.2 }, 0.45 * a)
		G.setColor(1, 0.7, 0.25, 0.85 * a)
		G.circle("fill", px, py, pr)
		G.setColor(1, 0.92, 0.6, 0.9 * a)
		G.circle("fill", px, py, pr * 0.8)
		G.setLineWidth(3)
		for i = 1, 18 do
			local ang = i * math.pi / 9 + t * 0.05
			local l = pr * (1.15 + 0.35 * math.abs(math.sin(t * 0.7 + i * 1.3)))
			G.setColor(1, 0.55, 0.15, 0.45 * a)
			G.line(px + math.cos(ang) * pr, py + math.sin(ang) * pr, px + math.cos(ang) * l, py + math.sin(ang) * l)
		end
	elseif stage == 4 then
		-- Deep inside a glowing nebula; colours slowly cycle.
		for i = 1, 9 do
			local hue = t * 0.05 + i * 0.7
			local x = w * (0.5 + 0.45 * math.sin(i * 2.3 + t * 0.02))
			local y = h * (0.5 + 0.42 * math.cos(i * 1.7 + t * 0.017))
			glow(G, x, y, h * (0.35 + (i % 3) * 0.15), { 0.5 + 0.5 * math.sin(hue), 0.4 + 0.4 * math.sin(hue + 2.1), 0.6 + 0.4 * math.sin(hue + 4.2) }, 0.22 * a)
		end
		-- Dark pillars rise through the gas.
		for i = 1, 3 do
			local x = w * (0.2 + i * 0.22)
			G.setColor(0.01, 0.01, 0.03, 0.45 * a)
			G.polygon("fill", x - 40, h, x - 14, h * (0.45 + i * 0.07), x + 18, h * (0.5 + i * 0.05), x + 50, h)
		end
	elseif stage == 5 then
		-- A supernova: shock fronts keep rolling out from a white core.
		local px, py = w * 0.7, h * 0.4
		for i = 0, 3 do
			local k = (t * 0.12 + i / 4) % 1
			G.setColor(1, 0.5 + 0.4 * (1 - k), 0.8 * k, (1 - k) * 0.45 * a)
			G.setLineWidth(3 + 10 * (1 - k))
			G.circle("line", px, py, 30 + k * w * 0.8)
		end
		glow(G, px, py, h * 0.9, { 1, 0.3, 0.6 }, 0.25 * a)
		glow(G, px, py, h * 0.35, { 1, 0.9, 0.7 }, 0.7 * a)
		G.setLineWidth(2)
		for i = 1, 28 do
			local ang = i * 0.2244 + math.sin(i * 7.1)
			local l = h * (0.15 + 0.35 * ((t * 0.1 + i * 0.37) % 1))
			G.setColor(1, 0.85, 0.6, 0.35 * a)
			G.line(px + math.cos(ang) * l * 0.4, py + math.sin(ang) * l * 0.4, px + math.cos(ang) * l, py + math.sin(ang) * l)
		end
		G.setColor(1, 1, 1, a)
		G.circle("fill", px, py, 9)
	else
		-- The black hole: a huge accretion disk, a lensing ring and a hue shift.
		local px, py, pr = w * 0.5, h * 0.5, h * 0.17
		for i = 1, 3 do
			local hue = t * 0.3 + i * 2
			glow(G, px, py, h * (0.5 + i * 0.3), { 0.5 + 0.5 * math.sin(hue), 0.3 + 0.3 * math.sin(hue + 2), 0.8 + 0.2 * math.sin(hue + 4) }, 0.16 * a)
		end
		G.setBlendMode("add")
		for i = 1, 14 do
			local k = i / 14
			local hue = t * 0.4 + k * 5
			G.setColor(0.6 + 0.4 * math.sin(hue), 0.4 + 0.4 * math.sin(hue + 2.1), 0.8 + 0.2 * math.sin(hue + 4.2), 0.22 * a * (1 - k * 0.6))
			G.setLineWidth(4 + k * 6)
			G.push()
			G.translate(px, py)
			G.rotate(0.18 + math.sin(t * 0.1) * 0.05)
			G.ellipse("line", 0, 0, pr * (1.6 + k * 3.2), pr * (0.28 + k * 0.5))
			G.pop()
		end
		G.setBlendMode("alpha")
		G.setColor(0, 0, 0, 0.95 * a)
		G.circle("fill", px, py, pr)
		G.setColor(1, 0.9, 0.8, 0.6 * a)
		G.setLineWidth(3)
		G.circle("line", px, py, pr * 1.08)
		-- Stars spiral inward and vanish at the horizon.
		for i = 1, 60 do
			local k = 1 - ((t * 0.06 + i * 0.137) % 1)
			local ang = i * 2.39 + (1 - k) * 9 + t * 0.2
			local r = pr * 1.1 + k * h * 0.9
			G.setColor(0.9, 0.85, 1, 0.6 * a * k)
			G.circle("fill", px + math.cos(ang) * r, py + math.sin(ang) * r * 0.75, 1.2 + k)
		end
	end
end
-- Pickups read at a glance: a heart heals, a fan of three shots spreads,
-- an arrow through a wall pierces and a lightning bolt fires faster.
M.pickupColors = { repair = { 1, 0.3, 0.42 }, spread = { 1, 0.75, 0.2 }, pierce = { 1, 0.45, 0.85 }, rapid = { 0.25, 1, 1 } }
M.pickupNames = { repair = "LIFE", spread = "SPREAD", pierce = "PIERCE", rapid = "RAPID" }
function M.pickup(G, kind, x, y, alpha, time, fonts)
	local c = M.pickupColors[kind]
	local pulse = 1 + 0.08 * math.sin(time * 6)
	G.setColor(c[1], c[2], c[3], 0.16 * alpha)
	G.circle("fill", x, y, 21 * pulse)
	G.setColor(c[1], c[2], c[3], alpha)
	G.setLineWidth(2)
	G.circle("line", x, y, 18 * pulse)
	if kind == "repair" then
		G.circle("fill", x - 4.5, y - 3, 5.2)
		G.circle("fill", x + 4.5, y - 3, 5.2)
		G.polygon("fill", x - 9.4, y - 1.2, x + 9.4, y - 1.2, x, y + 10)
	elseif kind == "spread" then
		G.setLineWidth(2.5)
		for i = -1, 1 do
			local a = -math.pi / 2 + i * 0.55
			G.line(x - 0.0, y + 8, x + math.cos(a) * 13, y + 8 + math.sin(a) * 13)
			G.circle("fill", x + math.cos(a) * 13, y + 8 + math.sin(a) * 13, 2.4)
		end
	elseif kind == "pierce" then
		G.rectangle("fill", x - 1, y - 10, 4, 7)
		G.rectangle("fill", x - 1, y + 3, 4, 7)
		G.setLineWidth(2.5)
		G.line(x - 12, y, x + 8, y)
		G.polygon("fill", x + 13, y, x + 6, y - 5, x + 6, y + 5)
	else
		G.polygon("fill", x + 3, y - 12, x - 7, y + 2, x - 1, y + 2, x - 4, y + 12, x + 7, y - 3, x + 1, y - 3)
	end
	G.setFont(fonts.small)
	G.setColor(c[1], c[2], c[3], 0.85 * alpha)
	G.printf(M.pickupNames[kind], x - 50, y + 22, 100, "center")
end
function M.draw(s, G, fonts, playerColor)
	local function tint(c, a)
		G.setColor(c[1], c[2], c[3], a or 1)
	end
	local function polygon(x, y, r, n, angle)
		local points = {}
		for i = 1, n do
			local a = angle + i * math.pi * 2 / n
			points[#points + 1] = x + math.cos(a) * r
			points[#points + 1] = y + math.sin(a) * r
		end
		G.polygon("line", points)
	end
	local sx, sy = G.transformPoint(0, 0)
	local ex, ey = G.transformPoint(s.width, s.height)
	G.setScissor(sx, sy, ex - sx, ey - sy)
	G.push()
	G.translate(math.sin(s.time * 83) * s.shake, math.cos(s.time * 97) * s.shake * 0.6)
	M.background(s, G)
	G.setColor(0.08, 0.14, 0.2, 0.55)
	G.setLineWidth(1)
	for x=0,s.width,40 do
        local line={}
        for y=0,s.height+20,20 do local wx,wy=Gravity.warp(s,x,y);line[#line+1]=wx;line[#line+1]=wy end
        G.line(line)
    end
    for y=0,s.height,40 do
        local line={}
        for x=0,s.width+20,20 do local wx,wy=Gravity.warp(s,x,y);line[#line+1]=wx;line[#line+1]=wy end
        G.line(line)
    end
    Gravity.drawFlow(s,G)
    Gravity.draw(s,G)
	for _, r in ipairs(s.rings) do
		tint(r.color, r.ttl / 0.35 * 0.7)
		G.setLineWidth(2)
		G.circle("line", r.x, r.y, r.r * (1 - r.ttl / 0.4))
	end
	for _, q in ipairs(s.pickups) do
		M.pickup(G, q.kind, q.x, q.y + math.sin(s.time * 3 + q.x) * 2, math.min(1, q.ttl), s.time, fonts)
	end
	for _, b in ipairs(s.shots) do
		local c = ({pierce={1,0.45,0.85},spread={1,0.75,0.2},rapid={0.25,1,1}})[b.special] or playerColor(b.owner)
		tint(c, 0.18)
		G.setLineWidth(b.special and 12 or 7)
		G.line(b.x - b.vx * 0.018, b.y - b.vy * 0.018, b.x, b.y)
		tint(c)
		G.setLineWidth(b.special=="pierce" and 5 or b.special and 3 or 2)
		G.line(b.x - b.vx * 0.014, b.y - b.vy * 0.014, b.x, b.y)
	end
	for _, b in ipairs(s.hostile) do
		G.setColor(1, 0.4, 0.15, 0.2)
		G.circle("fill", b.x, b.y, 9)
		G.setColor(1, 0.7, 0.35)
		G.circle("fill", b.x, b.y, 4)
	end
	for _, e in ipairs(s.enemies) do
		local c = Siege.enemyColors[e.kind]
		local tough = Siege.specs[e.kind].boss
		local n = ({ boss = 8, hive = 6, splitter = 6, weaver = 3, shard = 3, dasher = 3, orbiter = 5, serpent = 7, segment = 6 })[e.kind] or 4
		local angle = e.kind == "fort" and math.pi / 4 or s.time * 0.7 + e.phase
		if e.kind == "dasher" then
			local p = e.lockX and (e.aim or e.rush) and { e.lockX, e.lockY }
			angle = p and math.atan2(p[2], p[1]) or angle
		elseif e.kind == "serpent" and e.segments[1] then
			angle = math.atan2(e.y - e.segments[1].y, e.x - e.segments[1].x)
		elseif e.kind == "segment" or e.kind == "hive" then
			angle = e.phase
		end
		if e.warm <= 0 and BossRender.draw(G, s, e, c, fonts) then
			-- drawn by the late-boss renderer
		elseif e.warm > 0 then
			tint(c, 0.25)
			G.setLineWidth(1)
			G.circle("line", e.x, e.y, e.r + e.warm * 22)
			tint(c, 0.65)
			G.circle("line", e.x, e.y, 5)
		else
			tint(c, 0.15)
			G.setLineWidth(7)
			polygon(e.x, e.y, e.r, n, angle)
			if e.kind == "dasher" and e.aim and e.aim > 0 then
				-- The charge line flashes before the rush.
				tint(c, 0.25 + 0.4 * math.sin(s.time * 40) ^ 2)
				G.setLineWidth(2)
				G.line(e.x, e.y, e.x + e.lockX * 300, e.y + e.lockY * 300)
				G.setLineWidth(7)
			elseif e.kind == "orbiter" then
				G.circle("line", e.x, e.y, e.r * 0.45)
			elseif e.kind == "hive" then
				for i = 1, 6 do
					local a = i * math.pi / 3 + e.phase
					polygon(e.x + math.cos(a) * 26, e.y + math.sin(a) * 26, 12, 6, e.phase)
				end
			elseif e.kind == "serpent" then
				G.circle("line", e.x, e.y, e.r * 0.4)
			end
			if tough then
				polygon(e.x,e.y,e.r*0.65,n,-angle)
				G.setColor(0.15,0.1,0.2)
				G.rectangle("fill",e.x-38,e.y-e.r-14,76,5)
				tint(c)
				G.rectangle("fill",e.x-38,e.y-e.r-14,76*math.max(0,e.hp/e.maxHp),5)
			end
			tint(e.flash > 0 and { 1, 1, 1 } or c)
			G.setLineWidth(2)
			polygon(e.x, e.y, e.r, n, angle)
			if e.kind == "fort" then
				G.circle("line", e.x, e.y, 6)
			elseif e.kind == "hive" then
				for i = 1, 6 do
					local a = i * math.pi / 3 + e.phase
					polygon(e.x + math.cos(a) * 26, e.y + math.sin(a) * 26, 12, 6, e.phase)
				end
			elseif e.kind == "serpent" then
				local fx, fy = math.cos(angle), math.sin(angle)
				G.circle("fill", e.x + fx * 8 - fy * 7, e.y + fy * 8 + fx * 7, 3)
				G.circle("fill", e.x + fx * 8 + fy * 7, e.y + fy * 8 - fx * 7, 3)
			elseif e.kind == "orbiter" then
				G.circle("line", e.x, e.y, e.r * 0.45)
			end
		end
	end
	BossRender.beams(G, s)
	for _, p in ipairs(s.particles) do
		tint(p.color, math.min(1, p.ttl * 3))
		G.setLineWidth(2)
		G.line(p.x, p.y, p.x - p.vx * 0.022, p.y - p.vy * 0.022)
	end
	for _, p in ipairs(s.players) do
		local c = playerColor(p)
		tint(c)
		G.setLineWidth(2)
		if p.hp == 0 then
			G.circle("line", p.x, p.y, 20 + math.sin(s.time * 5) * 3)
			G.line(p.x - 7, p.y, p.x + 7, p.y)
			G.line(p.x, p.y - 7, p.x, p.y + 7)
			if p.revive > 0 then
				G.arc(
					"line",
					"open",
					p.x,
					p.y,
					27,
					-math.pi / 2,
					-math.pi / 2 + math.pi * 2 * math.min(1, p.revive / 1.2)
				)
			end
			G.setFont(fonts.small)
			G.printf("REVIVE", p.x - 45, p.y + 30, 90, "center")
		else
			local ax, ay = p.aimX, p.aimY
			local points = {
				p.x + ax * 17,
				p.y + ay * 17,
				p.x - ax * 12 - ay * 11,
				p.y - ay * 12 + ax * 11,
				p.x - ax * 5,
				p.y - ay * 5,
				p.x - ax * 12 + ay * 11,
				p.y - ay * 12 - ax * 11,
			}
			tint(c, 0.18)
			G.setLineWidth(8)
			G.polygon("line", points)
			tint(c)
			G.setLineWidth(2)
			G.polygon("line", points)
			if p.invul > 0 then
				tint(c, 0.35 + 0.2 * math.sin(s.time * 20))
				G.circle("line", p.x, p.y, 23)
			end
			if p.dash > 0 then
				tint(c, 0.45)
				G.setLineWidth(5)
				G.line(p.x, p.y, p.x - p.dashX * 48, p.y - p.dashY * 48)
			end
			tint(c)
			local upgrades = {}
			for _, kind in ipairs({ "spread", "pierce", "rapid" }) do
				if p.powers[kind] then upgrades[#upgrades + 1] = kind:upper() .. " " .. tostring(p.powers[kind]) end
			end
			if #upgrades > 0 then
				G.setFont(fonts.small)
				G.setColor(0.85, 1, 0.95)
				G.printf(table.concat(upgrades, " + "), p.x - 110, p.y + 38, 220, "center")
			end
			tint(c)
			for i = 1, p.hp do
				G.circle("fill", p.x + (i - (p.hp + 1) / 2) * 7, p.y + 28, 2)
			end
		end
	end
	G.pop()
	G.setScissor()
	G.setFont(fonts.small)
	G.setColor(0.55, 0.7, 0.75, 0.8)
	if s.wavePhase == "rest" then
		G.printf("WAVE " .. (s.wave + 1) .. "  /  " .. math.ceil(s.waveRest), 0, 65, s.width, "center")
	elseif s.waveClock < 2 then
		G.printf("WAVE " .. s.wave .. "  /  " .. s.waveName, 0, 65, s.width, "center")
	else
		BossRender.banner(G, s, fonts, Siege.specs)
	end
end
return M
