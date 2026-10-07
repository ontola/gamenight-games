--- The TV: the island, everyone's pieces, whose turn it is and the dice.
--- Cards are private, so the TV only ever shows how many each player holds.
local R = require("rules")
local Render = {}

local FIELD = {
	timber = { 0.18, 0.49, 0.29 },
	clay = { 0.77, 0.39, 0.23 },
	wool = { 0.62, 0.83, 0.42 },
	grain = { 0.91, 0.76, 0.29 },
	ore = { 0.55, 0.56, 0.64 },
}
local LAKE = { 0.29, 0.64, 0.79 }
local SEA = { 0.07, 0.2, 0.29 }
local INK = { 0.12, 0.1, 0.09 }
local PAPER = { 0.98, 0.95, 0.86 }
local fonts = {}

local function font(size)
	size = math.floor(size)
	if not fonts[size] then
		fonts[size] = love.graphics.newFont(size)
	end
	return fonts[size]
end

local function hex(color)
	local r, g, b = color:match("#(%x%x)(%x%x)(%x%x)")
	return { tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255 }
end

local function hexagon(x, y, size)
	local pts = {}
	for c = 0, 5 do
		local a = math.rad(60 * c - 30)
		pts[#pts + 1] = x + math.cos(a) * size
		pts[#pts + 1] = y + math.sin(a) * size
	end
	return pts
end

--- Small marks so fields read without relying on colour alone.
local function glyph(res, x, y, s)
	love.graphics.setColor(0, 0, 0, 0.22)
	if res == "timber" then
		for _, dx in ipairs({ -0.32, 0, 0.32 }) do
			love.graphics.polygon("fill", x + dx * s - 0.14 * s, y - 0.32 * s, x + dx * s + 0.14 * s,
				y - 0.32 * s, x + dx * s, y - 0.62 * s)
		end
	elseif res == "clay" then
		for row = 0, 1 do
			for col = -1, 1 do
				love.graphics.rectangle("fill", x + (col * 0.26 - 0.11 + row * 0.13) * s, y - (0.6 - row * 0.14) * s,
					0.22 * s, 0.1 * s)
			end
		end
	elseif res == "wool" then
		for _, dx in ipairs({ -0.18, 0.05, 0.25 }) do
			love.graphics.circle("fill", x + dx * s, y - 0.47 * s, 0.13 * s)
		end
	elseif res == "grain" then
		love.graphics.setLineWidth(math.max(2, s * 0.05))
		for _, dx in ipairs({ -0.25, -0.08, 0.08, 0.25 }) do
			love.graphics.line(x + dx * s, y - 0.3 * s, x + dx * s, y - 0.66 * s)
		end
	elseif res == "ore" then
		love.graphics.polygon("fill", x - 0.36 * s, y - 0.3 * s, x - 0.1 * s, y - 0.66 * s, x + 0.12 * s, y - 0.3 * s)
		love.graphics.polygon("fill", x, y - 0.3 * s, x + 0.2 * s, y - 0.56 * s, x + 0.38 * s, y - 0.3 * s)
	end
end

local function house(x, y, s, color, town)
	local w, h = (town and 0.34 or 0.24) * s, (town and 0.3 or 0.22) * s
	local pts = { x - w, y + h * 0.7, x - w, y - h * 0.2, x, y - h, x + w, y - h * 0.2, x + w, y + h * 0.7 }
	if town then
		pts = { x - w, y + h * 0.7, x - w, y - h * 0.5, x - w * 0.2, y - h * 0.5, x - w * 0.2, y - h * 1.2,
			x + w * 0.4, y - h * 1.6, x + w, y - h * 1.2, x + w, y + h * 0.7 }
	end
	love.graphics.setColor(color)
	love.graphics.polygon("fill", pts)
	love.graphics.setColor(PAPER)
	love.graphics.setLineWidth(math.max(2, s * 0.05))
	love.graphics.polygon("line", pts)
end

local function die(x, y, s, n)
	love.graphics.setColor(PAPER)
	love.graphics.rectangle("fill", x, y, s, s, s * 0.16)
	love.graphics.setColor(INK)
	local spots = {
		{ { 0.5, 0.5 } },
		{ { 0.27, 0.27 }, { 0.73, 0.73 } },
		{ { 0.27, 0.27 }, { 0.5, 0.5 }, { 0.73, 0.73 } },
		{ { 0.27, 0.27 }, { 0.73, 0.27 }, { 0.27, 0.73 }, { 0.73, 0.73 } },
		{ { 0.27, 0.27 }, { 0.73, 0.27 }, { 0.5, 0.5 }, { 0.27, 0.73 }, { 0.73, 0.73 } },
		{ { 0.27, 0.25 }, { 0.73, 0.25 }, { 0.27, 0.5 }, { 0.73, 0.5 }, { 0.27, 0.75 }, { 0.73, 0.75 } },
	}
	for _, p in ipairs(spots[n] or {}) do
		love.graphics.circle("fill", x + p[1] * s, y + p[2] * s, s * 0.09)
	end
end

local PHASE = {
	setup_hamlet = "places a hamlet",
	setup_road = "places a road",
	roll = "rolls the dice",
	storm = "moves the storm",
	build = "builds and trades",
}

function Render.draw(s, info)
	local W, H = love.graphics.getDimensions()
	love.graphics.clear(SEA)
	if not s then
		love.graphics.setColor(PAPER)
		love.graphics.printf("Hexstead", 0, H * 0.45, W, "center")
		return
	end
	local panel = math.max(W * 0.3, 320)
	-- Fit the island into the space left of the panel.
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, v in ipairs(s.verts) do
		minX, maxX = math.min(minX, v.x), math.max(maxX, v.x)
		minY, maxY = math.min(minY, v.y), math.max(maxY, v.y)
	end
	local areaW, areaH = W - panel, H
	local size = math.min((areaW * 0.88) / (maxX - minX), (areaH * 0.86) / (maxY - minY))
	local ox = areaW / 2 - (minX + maxX) / 2 * size
	local oy = areaH / 2 - (minY + maxY) / 2 * size
	local function at(x, y)
		return ox + x * size, oy + y * size
	end

	-- Shallow water around the coast.
	love.graphics.setColor(0.1, 0.29, 0.4)
	for _, t in ipairs(s.tiles) do
		local x, y = at(t.x, t.y)
		love.graphics.polygon("fill", hexagon(x, y, size * 1.18))
	end
	for _, t in ipairs(s.tiles) do
		local x, y = at(t.x, t.y)
		love.graphics.setColor(t.res and FIELD[t.res] or LAKE)
		love.graphics.polygon("fill", hexagon(x, y, size * 0.97))
		if t.res then
			glyph(t.res, x, y, size)
			local hot = R.pips(t.num) == 5
			love.graphics.setColor(PAPER)
			love.graphics.circle("fill", x, y + size * 0.12, size * 0.3)
			love.graphics.setColor(hot and { 0.75, 0.16, 0.12 } or INK)
			local f = font(size * 0.3)
			love.graphics.setFont(f)
			love.graphics.printf(tostring(t.num), x - size, y + size * 0.12 - f:getHeight() / 2 - size * 0.03,
				size * 2, "center")
			-- Dots: how likely the number is.
			for d = 1, R.pips(t.num) do
				love.graphics.circle("fill", x + (d - (R.pips(t.num) + 1) / 2) * size * 0.07, y + size * 0.33,
					size * 0.022)
			end
		end
		if s.dice and t.num == s.dice[1] + s.dice[2] and t.id ~= s.storm then
			love.graphics.setColor(1, 1, 1, 0.8)
			love.graphics.setLineWidth(math.max(3, size * 0.07))
			love.graphics.polygon("line", hexagon(x, y, size * 0.9))
		end
	end
	-- The storm cloud.
	do
		local t = s.tiles[s.storm]
		local x, y = at(t.x, t.y)
		love.graphics.setColor(0.2, 0.22, 0.3, 0.9)
		for _, c in ipairs({ { -0.28, 0.02, 0.24 }, { 0, -0.1, 0.3 }, { 0.3, 0.02, 0.22 }, { 0.02, 0.12, 0.26 } }) do
			love.graphics.circle("fill", x + c[1] * size, y + c[2] * size, c[3] * size)
		end
		love.graphics.setColor(1, 0.85, 0.3)
		love.graphics.polygon("fill", x - 0.02 * size, y + 0.18 * size, x + 0.1 * size, y + 0.18 * size,
			x, y + 0.42 * size, x + 0.04 * size, y + 0.28 * size, x - 0.08 * size, y + 0.28 * size)
	end
	for _, e in ipairs(s.edges) do
		if e.owner then
			local a, b = s.verts[e.a], s.verts[e.b]
			local x1, y1 = at(a.x, a.y)
			local x2, y2 = at(b.x, b.y)
			local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
			x1, y1 = mx + (x1 - mx) * 0.78, my + (y1 - my) * 0.78
			x2, y2 = mx + (x2 - mx) * 0.78, my + (y2 - my) * 0.78
			love.graphics.setColor(PAPER)
			love.graphics.setLineWidth(size * 0.17)
			love.graphics.line(x1, y1, x2, y2)
			love.graphics.setColor(hex(s.players[e.owner].color))
			love.graphics.setLineWidth(size * 0.11)
			love.graphics.line(x1, y1, x2, y2)
		end
	end
	for _, v in ipairs(s.verts) do
		if v.owner then
			local x, y = at(v.x, v.y)
			house(x, y, size, hex(s.players[v.owner].color), v.kind == "town")
		end
	end

	-- Side panel.
	local px = W - panel
	love.graphics.setColor(0.05, 0.13, 0.19)
	love.graphics.rectangle("fill", px, 0, panel, H)
	local pad = panel * 0.07
	local y = pad
	love.graphics.setColor(PAPER)
	love.graphics.setFont(font(panel * 0.1))
	love.graphics.print("Hexstead", px + pad, y)
	y = y + panel * 0.14
	love.graphics.setFont(font(panel * 0.045))
	love.graphics.setColor(0.75, 0.82, 0.86)
	love.graphics.printf("First to " .. R.GOAL .. " points. Your cards are on your phone.", px + pad, y,
		panel - pad * 2)
	y = y + panel * 0.15
	local rowH = panel * 0.15
	for i, p in ipairs(s.players) do
		local active = s.turn == i and s.phase ~= "over"
		if active then
			love.graphics.setColor(1, 1, 1, 0.1)
			love.graphics.rectangle("fill", px + pad * 0.5, y - rowH * 0.12, panel - pad, rowH, 10)
		end
		love.graphics.setColor(hex(p.color))
		love.graphics.circle("fill", px + pad + rowH * 0.25, y + rowH * 0.3, rowH * 0.22)
		love.graphics.setColor(PAPER)
		love.graphics.setFont(font(panel * 0.06))
		love.graphics.print(p.name, px + pad + rowH * 0.62, y)
		love.graphics.setFont(font(panel * 0.042))
		love.graphics.setColor(0.75, 0.82, 0.86)
		local status = info.status and info.status(i) or ""
		love.graphics.print(R.cards(p) .. " cards" .. status, px + pad + rowH * 0.62, y + rowH * 0.42)
		love.graphics.setFont(font(panel * 0.09))
		love.graphics.setColor(PAPER)
		love.graphics.printf(tostring(R.vp(p)), px, y + rowH * 0.02, panel - pad, "right")
		y = y + rowH
	end
	y = y + panel * 0.03
	local current = s.players[s.turn]
	love.graphics.setFont(font(panel * 0.055))
	if s.phase == "over" then
		love.graphics.setColor(hex(s.players[s.winner].color))
		love.graphics.printf(s.players[s.winner].name .. " wins!", px + pad, y, panel - pad * 2)
	else
		love.graphics.setColor(hex(current.color))
		love.graphics.printf(current.name .. " " .. (PHASE[s.phase] or ""), px + pad, y, panel - pad * 2)
	end
	y = y + panel * 0.1
	if s.dice then
		local d = panel * 0.14
		die(px + pad, y, d, s.dice[1])
		die(px + pad + d * 1.2, y, d, s.dice[2])
		love.graphics.setColor(PAPER)
		love.graphics.setFont(font(d * 0.6))
		love.graphics.print("= " .. (s.dice[1] + s.dice[2]), px + pad + d * 2.55, y + d * 0.12)
	end
	y = y + panel * 0.2
	love.graphics.setFont(font(panel * 0.042))
	love.graphics.setColor(FIELD[s.market])
	love.graphics.printf("Market: " .. R.LABEL[s.market] .. " trades 2 for 1", px + pad, y, panel - pad * 2)
	y = y + panel * 0.09
	for n, line in ipairs(s.log) do
		love.graphics.setColor(0.75, 0.82, 0.86, 1 - (n - 1) * 0.14)
		love.graphics.printf(line, px + pad, y, panel - pad * 2)
		local _, wrapped = font(panel * 0.042):getWrap(line, panel - pad * 2)
		y = y + #wrapped * font(panel * 0.042):getHeight() + 4
	end
	if info.banner then
		love.graphics.setColor(0, 0, 0, 0.6)
		love.graphics.rectangle("fill", 0, H - panel * 0.16, W - panel, panel * 0.16)
		love.graphics.setColor(PAPER)
		love.graphics.setFont(font(panel * 0.05))
		love.graphics.printf(info.banner, 0, H - panel * 0.12, W - panel, "center")
	end
end

return Render
