--- A simple, readable Hexstead player for AI seats and for players whose
--- phone has gone away. One action per call, so the TV can show each step.
local R = require("rules")
local Bot = {}

local function cornerValue(s, vid)
	local v, value, kinds = s.verts[vid], 0, {}
	for _, tid in ipairs(v.tiles) do
		local t = s.tiles[tid]
		if t.res then
			value = value + R.pips(t.num)
			if not kinds[t.res] then
				kinds[t.res] = true
				value = value + 1
			end
		end
	end
	return value
end

local function best(list, score)
	local top, topScore = nil, -math.huge
	for _, item in ipairs(list) do
		local value = score(item)
		if value > topScore then
			top, topScore = item, value
		end
	end
	return top
end

--- Roads that lead toward good open corners.
local function roadValue(s, i, eid)
	local e = s.edges[eid]
	local value = 0
	for _, end_ in ipairs({ e.a, e.b }) do
		local v = s.verts[end_]
		if not v.owner then
			local free = true
			for _, other in ipairs(v.adj) do
				if s.verts[other].owner then
					free = false
				end
			end
			value = math.max(value, (free and 3 or 0) + cornerValue(s, end_))
		end
	end
	return value + s.rng(0, 2)
end

local function missing(p, kind)
	local out = {}
	for res, n in pairs(R.COST[kind]) do
		if p.hand[res] < n then
			out[#out + 1] = res
		end
	end
	return out
end

--- Swap a surplus for a card the next build needs.
local function trade(s, i, kind)
	local p = s.players[i]
	local need = missing(p, kind)
	if #need == 0 then
		return nil
	end
	for _, res in ipairs(R.RESOURCES) do
		local keep = R.COST[kind][res] or 0
		if p.hand[res] - keep >= R.rate(s, res) then
			return { a = "bank", give = res, get = need[1] }
		end
	end
end

function Bot.choose(s, i)
	local p = s.players[i]
	if s.phase == "setup_hamlet" then
		return { a = "hamlet", id = best(R.hamletSpots(s, i), function(v)
			return cornerValue(s, v) + s.rng(0, 1)
		end) }
	elseif s.phase == "setup_road" then
		return { a = "road", id = best(R.roadSpots(s, i), function(e)
			return roadValue(s, i, e)
		end) }
	elseif s.phase == "roll" then
		return { a = "roll" }
	elseif s.phase == "storm" then
		return { a = "storm", id = best(R.stormSpots(s), function(tid)
			local t, value = s.tiles[tid], 0
			for _, vid in ipairs(t.verts) do
				local owner = s.verts[vid].owner
				if owner == i then
					value = value - 10
				elseif owner then
					value = value + R.pips(t.num) + R.cards(s.players[owner]) / 4
				end
			end
			return value
		end) }
	elseif s.phase ~= "build" then
		return nil
	end
	local function can(kind)
		return R.canAfford(p, kind) and p.built[kind] < R.LIMIT[kind]
	end
	local towns, hamlets = R.townSpots(s, i), R.hamletSpots(s, i)
	if can("town") and #towns > 0 then
		return { a = "town", id = best(towns, function(v)
			return cornerValue(s, v)
		end) }
	end
	if can("hamlet") and #hamlets > 0 then
		return { a = "hamlet", id = best(hamlets, function(v)
			return cornerValue(s, v)
		end) }
	end
	if can("festival") and R.vp(p) >= R.GOAL - 2 then
		return { a = "festival" }
	end
	local goal = #hamlets > 0 and p.built.hamlet < R.LIMIT.hamlet and "hamlet"
		or #towns > 0 and "town" or "road"
	local swap = trade(s, i, goal)
	if swap then
		return swap
	end
	if goal == "road" and can("road") then
		local roads = R.roadSpots(s, i)
		if #roads > 0 then
			return { a = "road", id = best(roads, function(e)
				return roadValue(s, i, e)
			end) }
		end
	end
	if can("festival") then
		return { a = "festival" }
	end
	return { a = "end" }
end

return Bot
