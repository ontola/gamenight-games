local M = {}
local Gravity=require("games.siege_gravity")
local Siege = require("games.siege")
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
	-- A ringed planet hangs low in one corner.
	local px, py, pr = w * 0.86, h * 0.86, h * 0.22
	G.setColor(c2[1] * 0.12, c2[2] * 0.12, c2[3] * 0.18)
	G.circle("fill", px, py, pr)
	-- Light the far side only: a crescent cut out by the stencil.
	G.stencil(function() G.circle("fill", px - pr * 0.3, py - pr * 0.25, pr * 1.02) end, "replace", 1)
	G.setStencilTest("equal", 0)
	for i = 0, 5 do
		G.setColor(c2[1] * 0.5, c2[2] * 0.5, c2[3] * 0.6, 0.18)
		G.circle("fill", px + i * 2, py + i * 2, pr - i * 4)
	end
	G.setStencilTest()
	G.setColor(c1[1], c1[2], c1[3], 0.35)
	G.setLineWidth(3)
	G.ellipse("line", px, py, pr * 1.7, pr * 0.32)
	G.setColor(c1[1], c1[2], c1[3], 0.15)
	G.setLineWidth(9)
	G.ellipse("line", px, py, pr * 1.85, pr * 0.38)
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
		G.setColor(0.4, 1, 0.8, math.min(1, q.ttl))
		G.setLineWidth(2)
		polygon(q.x, q.y, 15, 4, s.time)
		G.setFont(fonts.small)
		G.printf(({ spread = "S", pierce = "P", rapid = "R", repair = "+" })[q.kind], q.x - 12, q.y - 8, 24, "center")
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
		if e.warm > 0 then
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
				G.circle("fill", p.x + (i - 2) * 7, p.y + 28, 2)
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
	end
end
return M
