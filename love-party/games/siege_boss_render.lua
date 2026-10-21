-- Drawing for the Prism Twins, the Solar Warden and the Singularity.
local R = {}
local function bar(G, e, c, width)
	G.setColor(0.15, 0.1, 0.2)
	G.rectangle("fill", e.x - width / 2, e.y - e.r - 22, width, 6)
	G.setColor(c[1], c[2], c[3])
	G.rectangle("fill", e.x - width / 2, e.y - e.r - 22, width * math.max(0, e.hp / e.maxHp), 6)
end
local function ngon(G, mode, x, y, r, n, angle)
	local points = {}
	for i = 1, n do
		local a = angle + i * math.pi * 2 / n
		points[#points + 1] = x + math.cos(a) * r
		points[#points + 1] = y + math.sin(a) * r
	end
	G.polygon(mode, points)
end
function R.beams(G, s)
	for _, e in ipairs(s.enemies) do
		local c = e.kind == "singularity" and { 0.85, 0.5, 1 } or e.kind == "sun" and { 1, 0.75, 0.3 } or { 0.7, 0.95, 1 }
		for _, b in ipairs(e.beams or {}) do
			if b.state == "warn" then
				G.setColor(c[1], c[2], c[3], 0.3 + 0.45 * math.abs(math.sin(s.time * 22)))
				G.setLineWidth(2)
				G.line(b[1], b[2], b[3], b[4])
			else
				G.setColor(c[1], c[2], c[3], 0.18)
				G.setLineWidth(34)
				G.line(b[1], b[2], b[3], b[4])
				G.setColor(c[1], c[2], c[3], 0.55)
				G.setLineWidth(16)
				G.line(b[1], b[2], b[3], b[4])
				G.setColor(1, 1, 1, 0.95)
				G.setLineWidth(5)
				G.line(b[1], b[2], b[3], b[4])
			end
		end
	end
end
function R.draw(G, s, e, c, fonts)
	local flash = e.flash > 0
	local t = s.time
	if e.kind == "prism" then
		local a = t * (e.twin and not e.twin.dead and 0.8 or 2.2)
		G.setColor(c[1], c[2], c[3], 0.15)
		ngon(G, "fill", e.x, e.y, e.r * 1.6, 4, a)
		G.setLineWidth(2)
		G.setColor(flash and { 1, 1, 1 } or c)
		ngon(G, "line", e.x, e.y, e.r * 1.25, 4, a)
		ngon(G, "line", e.x, e.y, e.r * 0.8, 4, -a * 1.5)
		for i = 0, 2 do
			local h = (t * 0.3 + i / 3) % 1
			G.setColor(0.5 + 0.5 * math.sin(h * 6.28), 0.5 + 0.5 * math.sin(h * 6.28 + 2.1), 0.5 + 0.5 * math.sin(h * 6.28 + 4.2), 0.7)
			ngon(G, "line", e.x, e.y, e.r * (0.35 + i * 0.12), 4, a * (i + 1))
		end
		bar(G, e, c, 70)
	elseif e.kind == "sun" then
		for i = 4, 1, -1 do
			G.setColor(1, 0.45 + i * 0.08, 0.1, 0.07 * (5 - i))
			G.circle("fill", e.x, e.y, e.r * (1 + i * 0.22 + 0.04 * math.sin(t * 3 + i)))
		end
		G.setColor(flash and { 1, 1, 1 } or { 1, 0.78, 0.3 })
		G.circle("fill", e.x, e.y, e.r)
		G.setColor(1, 0.95, 0.7)
		G.circle("fill", e.x, e.y, e.r * 0.62)
		G.setLineWidth(3)
		G.setColor(1, 0.55, 0.15, 0.85)
		for i = 1, 12 do
			local a = i * math.pi / 6 + t * 0.4
			local l = e.r * (1.25 + 0.2 * math.sin(t * 4 + i * 1.7))
			G.line(e.x + math.cos(a) * e.r * 1.05, e.y + math.sin(a) * e.r * 1.05, e.x + math.cos(a) * l, e.y + math.sin(a) * l)
		end
		bar(G, e, c, 110)
	elseif e.kind == "singularity" then
		local phase = e.phase or 1
		local hue = t * (0.2 + phase * 0.15)
		G.setLineWidth(3)
		for i = 1, 7 do
			local k = i / 7
			local r = e.r * (1.3 + k * 1.6)
			G.setColor(0.6 + 0.4 * math.sin(hue + k * 4), 0.35 + 0.3 * math.sin(hue + k * 4 + 2), 1, 0.5 * (1 - k) + 0.08)
			G.push()
			G.translate(e.x, e.y)
			G.rotate(t * (0.6 + k) * (i % 2 == 0 and 1 or -1))
			G.ellipse("line", 0, 0, r, r * (0.32 + 0.1 * math.sin(t + i)))
			G.pop()
		end
		G.setColor(0, 0, 0)
		G.circle("fill", e.x, e.y, e.r)
		G.setColor(flash and { 1, 1, 1 } or { 1, 0.85, 1, 0.9 })
		G.setLineWidth(3)
		G.circle("line", e.x, e.y, e.r + 2)
		G.setColor(0.7, 0.4, 1, 0.35 + 0.25 * math.sin(t * 5))
		G.setLineWidth(8)
		G.circle("line", e.x, e.y, e.r + 9)
		bar(G, e, c, 160)
	elseif e.kind == "node" then
		local a = (e.head and e.head.spin or 0) * 2 + e.slot
		G.setColor(c[1], c[2], c[3], 0.2)
		ngon(G, "fill", e.x, e.y, e.r * 1.3, 3, a)
		G.setLineWidth(2)
		G.setColor(flash and { 1, 1, 1 } or { 0.8, 0.6, 1 })
		ngon(G, "line", e.x, e.y, e.r, 3, a)
	else
		return false
	end
	return true
end
-- A boss name and long health bar across the top while a boss is on the field.
function R.banner(G, s, fonts, specs)
	local total, max, name = 0, 0, nil
	for _, e in ipairs(s.enemies) do
		if specs[e.kind].boss and not e.dead then
			total, max = total + math.max(0, e.hp), max + e.maxHp
		end
	end
	if max == 0 then return end
	local W = require("games.siege_waves")
	name = s.wave % 4 == 0 and W.bosses[math.min(#W.bosses, s.wave / 4)].name or ""
	local w = math.min(620, s.width * 0.5)
	local x = s.width / 2 - w / 2
	G.setFont(fonts.small)
	G.setColor(1, 0.85, 1, 0.9)
	G.printf(name, 0, 52, s.width, "center")
	G.setColor(0.12, 0.08, 0.18, 0.9)
	G.rectangle("fill", x, 72, w, 7, 3, 3)
	G.setColor(0.9, 0.45, 1)
	G.rectangle("fill", x, 72, w * total / max, 7, 3, 3)
end
return R
