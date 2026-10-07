--- Hexstead rules: a random island of hex fields, dice that make the fields
--- produce, and hamlets, towns, roads and festivals to buy with what they
--- produce. Pure Lua (no LÖVE), so tests run it headless.
local R = {}

R.RESOURCES = { "timber", "clay", "wool", "grain", "ore" }
R.LABEL = { timber = "Timber", clay = "Clay", wool = "Wool", grain = "Grain", ore = "Ore" }
R.COST = {
	road = { timber = 1, clay = 1 },
	hamlet = { timber = 1, clay = 1, wool = 1, grain = 1 },
	town = { grain = 2, ore = 3 },
	festival = { wool = 1, grain = 1, ore = 1 },
}
R.LIMIT = { road = 15, hamlet = 5, town = 4, festival = 2 }
R.GOAL = 8
--- A storm makes anyone holding more than this lose half their hand.
R.HAND_LIMIT = 9
R.COLORS = { "#e8553e", "#3d8fe0", "#f2c230", "#8a5cd6", "#3fbf7f", "#f08acb" }

local SQRT3 = math.sqrt(3)
local DIRS = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }
local FIELDS = { "timber", "timber", "timber", "timber", "clay", "clay", "clay", "wool", "wool",
	"wool", "wool", "grain", "grain", "grain", "grain", "ore", "ore", "ore" }
local NUMBERS = { 2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12 }

--- How many of 36 rolls hit each number.
function R.pips(n)
	if not n then
		return 0
	end
	return 6 - math.abs(7 - n)
end

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function copy(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

--- Grow a random connected island of 19 hexes. Every round gets a new
--- coastline, so no two boards play alike.
local function island(rng)
	local cells, seen, frontier = {}, { ["0,0"] = true }, {}
	local function add(q, r)
		cells[#cells + 1] = { q = q, r = r }
		for _, d in ipairs(DIRS) do
			local nq, nr = q + d[1], r + d[2]
			local key = nq .. "," .. nr
			-- Keep the island compact enough to read from the couch.
			if not seen[key] and math.max(math.abs(nq), math.abs(nr), math.abs(nq + nr)) <= 3 then
				seen[key] = true
				frontier[#frontier + 1] = { q = nq, r = nr }
			end
		end
	end
	add(0, 0)
	while #cells < 19 do
		-- Prefer cells with more land around them, so the island stays solid.
		local best, bestScore = nil, -1
		for i, c in ipairs(frontier) do
			local around = 0
			for _, other in ipairs(cells) do
				local dq, dr = other.q - c.q, other.r - c.r
				if math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) == 1 then
					around = around + 1
				end
			end
			local score = around * 10 + rng(0, 14)
			if score > bestScore then
				best, bestScore = i, score
			end
		end
		local c = table.remove(frontier, best)
		add(c.q, c.r)
	end
	return cells
end

local function neighbours(a, b)
	local dq, dr = a.q - b.q, a.r - b.r
	return math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr)) == 1
end

--- Build the board: tiles, the corners where hamlets go (vertices) and the
--- sides where roads go (edges).
function R.board(rng)
	local cells = island(rng)
	local lake = rng(1, #cells)
	local fields = shuffle(copy(FIELDS), rng)
	local numbers
	-- 6s and 8s never touch, so no corner is a jackpot.
	for _ = 1, 200 do
		numbers = shuffle(copy(NUMBERS), rng)
		local ok, k = true, 0
		local placed = {}
		for i, c in ipairs(cells) do
			if i ~= lake then
				k = k + 1
				placed[i] = numbers[k]
			end
		end
		for i, a in ipairs(cells) do
			for j, b in ipairs(cells) do
				if i < j and placed[i] and placed[j] and R.pips(placed[i]) == 5 and R.pips(placed[j]) == 5
					and neighbours(a, b) then
					ok = false
				end
			end
		end
		if ok then
			numbers = placed
			break
		end
		numbers = placed
	end
	local tiles, verts, edges, vertAt, edgeAt = {}, {}, {}, {}, {}
	local k = 0
	for i, c in ipairs(cells) do
		local tile = {
			id = i,
			q = c.q,
			r = c.r,
			x = SQRT3 * (c.q + c.r / 2),
			y = 1.5 * c.r,
			verts = {},
		}
		if i ~= lake then
			k = k + 1
			tile.res, tile.num = fields[k], numbers[i]
		end
		tiles[i] = tile
	end
	local function vertex(x, y)
		local key = math.floor(x * 100 + 0.5) .. "," .. math.floor(y * 100 + 0.5)
		if not vertAt[key] then
			local v = { id = #verts + 1, x = x, y = y, tiles = {}, adj = {}, edges = {} }
			verts[v.id] = v
			vertAt[key] = v
		end
		return vertAt[key]
	end
	for _, tile in ipairs(tiles) do
		local ring = {}
		for c = 0, 5 do
			local a = math.rad(60 * c - 30)
			local v = vertex(tile.x + math.cos(a), tile.y + math.sin(a))
			ring[#ring + 1] = v
			tile.verts[#tile.verts + 1] = v.id
			v.tiles[#v.tiles + 1] = tile.id
		end
		for c = 1, 6 do
			local a, b = ring[c], ring[c % 6 + 1]
			local lo, hi = math.min(a.id, b.id), math.max(a.id, b.id)
			local key = lo .. "-" .. hi
			if not edgeAt[key] then
				local e = { id = #edges + 1, a = lo, b = hi }
				edges[e.id] = e
				edgeAt[key] = e
				a.adj[#a.adj + 1], b.adj[#b.adj + 1] = b.id, a.id
				a.edges[#a.edges + 1], b.edges[#b.edges + 1] = e.id, e.id
			end
		end
	end
	return { tiles = tiles, verts = verts, edges = edges, storm = lake }
end

--- A new game for these players (`{id, name, color, bot}`), in seat order.
function R.new(roster, rng)
	local s = R.board(rng)
	s.rng = rng
	s.players = {}
	for i, p in ipairs(roster) do
		local hand = {}
		for _, res in ipairs(R.RESOURCES) do
			hand[res] = 0
		end
		s.players[i] = {
			index = i,
			id = p.id,
			name = p.name or ("Player " .. i),
			color = p.color or R.COLORS[(i - 1) % #R.COLORS + 1],
			bot = p.bot == true,
			hand = hand,
			built = { road = 0, hamlet = 0, town = 0, festival = 0 },
		}
	end
	-- Setup: everyone places a hamlet and a road, then again in reverse.
	s.setup = {}
	for i = 1, #s.players do
		s.setup[#s.setup + 1] = i
	end
	for i = #s.players, 1, -1 do
		s.setup[#s.setup + 1] = i
	end
	s.setupStep = 1
	s.turn = s.setup[1]
	s.phase = "setup_hamlet"
	s.round = 1
	s.market = R.RESOURCES[rng(1, #R.RESOURCES)]
	s.log = {}
	s.events = 0
	R.say(s, "A new island rises. Place your first hamlets.")
	return s
end

function R.say(s, text)
	table.insert(s.log, 1, text)
	while #s.log > 6 do
		table.remove(s.log)
	end
	s.events = s.events + 1
end

function R.vp(p)
	return p.built.hamlet + 2 * p.built.town + p.built.festival
end

function R.cards(p)
	local n = 0
	for _, res in ipairs(R.RESOURCES) do
		n = n + p.hand[res]
	end
	return n
end

function R.canAfford(p, kind)
	for res, n in pairs(R.COST[kind]) do
		if p.hand[res] < n then
			return false
		end
	end
	return true
end

local function pay(p, kind)
	for res, n in pairs(R.COST[kind]) do
		p.hand[res] = p.hand[res] - n
	end
end

local function freeCorner(s, v)
	if v.owner then
		return false
	end
	for _, other in ipairs(v.adj) do
		if s.verts[other].owner then
			return false
		end
	end
	return true
end

--- Corners where player `i` may put a hamlet now.
function R.hamletSpots(s, i)
	local out = {}
	for _, v in ipairs(s.verts) do
		if freeCorner(s, v) then
			local reached = s.phase == "setup_hamlet"
			if not reached then
				for _, e in ipairs(v.edges) do
					if s.edges[e].owner == i then
						reached = true
					end
				end
			end
			if reached then
				out[#out + 1] = v.id
			end
		end
	end
	return out
end

--- Sides where player `i` may put a road now.
function R.roadSpots(s, i)
	local out = {}
	for _, e in ipairs(s.edges) do
		if not e.owner then
			local ok = false
			if s.phase == "setup_road" then
				ok = e.a == s.lastHamlet or e.b == s.lastHamlet
			else
				for _, end_ in ipairs({ e.a, e.b }) do
					local v = s.verts[end_]
					if v.owner == i then
						ok = true
					elseif not v.owner then
						for _, other in ipairs(v.edges) do
							if other ~= e.id and s.edges[other].owner == i then
								ok = true
							end
						end
					end
				end
			end
			if ok then
				out[#out + 1] = e.id
			end
		end
	end
	return out
end

function R.townSpots(s, i)
	local out = {}
	for _, v in ipairs(s.verts) do
		if v.owner == i and v.kind == "hamlet" then
			out[#out + 1] = v.id
		end
	end
	return out
end

function R.stormSpots(s)
	local out = {}
	for _, t in ipairs(s.tiles) do
		if t.id ~= s.storm then
			out[#out + 1] = t.id
		end
	end
	return out
end

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local function checkWin(s, i)
	if R.vp(s.players[i]) >= R.GOAL then
		s.winner = i
		s.phase = "over"
		R.say(s, s.players[i].name .. " wins with " .. R.vp(s.players[i]) .. " points!")
	end
end

local function nextSetup(s)
	s.setupStep = s.setupStep + 1
	if s.setupStep > #s.setup then
		s.turn = 1
		s.phase = "roll"
		R.say(s, s.players[1].name .. " rolls first.")
	else
		s.turn = s.setup[s.setupStep]
		s.phase = "setup_hamlet"
	end
end

local function produce(s, sum)
	local got = {}
	for _, t in ipairs(s.tiles) do
		if t.num == sum and t.id ~= s.storm then
			for _, vid in ipairs(t.verts) do
				local v = s.verts[vid]
				if v.owner then
					local n = v.kind == "town" and 2 or 1
					local p = s.players[v.owner]
					p.hand[t.res] = p.hand[t.res] + n
					got[v.owner] = (got[v.owner] or 0) + n
				end
			end
		end
	end
	return got
end

local function loseRandom(s, p, n)
	for _ = 1, n do
		local pool = {}
		for _, res in ipairs(R.RESOURCES) do
			for _ = 1, p.hand[res] do
				pool[#pool + 1] = res
			end
		end
		if #pool == 0 then
			return
		end
		local res = pool[s.rng(1, #pool)]
		p.hand[res] = p.hand[res] - 1
	end
end

--- Apply one action by player `i`. Returns true, or nil and why not.
--- Actions: {a="place", id=vertex} in setup, {a="road", id=edge},
--- {a="hamlet", id=vertex}, {a="town", id=vertex}, {a="festival"},
--- {a="roll"}, {a="storm", id=tile}, {a="bank", give=res, get=res},
--- {a="end"}.
function R.act(s, i, action)
	if s.phase == "over" then
		return nil, "The game is over."
	end
	if i ~= s.turn then
		return nil, "Wait for your turn."
	end
	local p = s.players[i]
	local a = action.a
	if s.phase == "setup_hamlet" then
		if a ~= "hamlet" or not contains(R.hamletSpots(s, i), action.id) then
			return nil, "Pick a free corner for your hamlet."
		end
		local v = s.verts[action.id]
		v.owner, v.kind = i, "hamlet"
		p.built.hamlet = p.built.hamlet + 1
		s.lastHamlet = v.id
		s.phase = "setup_road"
		-- The second hamlet starts you off with what it touches.
		if s.setupStep > #s.players then
			for _, tid in ipairs(v.tiles) do
				local t = s.tiles[tid]
				if t.res then
					p.hand[t.res] = p.hand[t.res] + 1
				end
			end
		end
		R.say(s, p.name .. " founded a hamlet.")
		return true
	elseif s.phase == "setup_road" then
		if a ~= "road" or not contains(R.roadSpots(s, i), action.id) then
			return nil, "Pick a side next to your new hamlet."
		end
		s.edges[action.id].owner = i
		p.built.road = p.built.road + 1
		nextSetup(s)
		return true
	elseif s.phase == "roll" then
		if a ~= "roll" then
			return nil, "Roll the dice first."
		end
		local d1, d2 = s.rng(1, 6), s.rng(1, 6)
		s.dice = { d1, d2 }
		local sum = d1 + d2
		if sum == 7 then
			for _, other in ipairs(s.players) do
				local n = R.cards(other)
				if n > R.HAND_LIMIT then
					loseRandom(s, other, math.floor(n / 2))
					R.say(s, other.name .. " lost " .. math.floor(n / 2) .. " cards to the storm.")
				end
			end
			s.phase = "storm"
			R.say(s, p.name .. " rolled 7. A storm is coming!")
		else
			local got = produce(s, sum)
			local any = next(got) ~= nil
			R.say(s, p.name .. " rolled " .. sum .. (any and "." or ". Nothing grows."))
			s.phase = "build"
		end
		return true
	elseif s.phase == "storm" then
		if a ~= "storm" or not contains(R.stormSpots(s), action.id) then
			return nil, "Move the storm to another field."
		end
		s.storm = action.id
		local victims = {}
		for _, vid in ipairs(s.tiles[action.id].verts) do
			local owner = s.verts[vid].owner
			if owner and owner ~= i and R.cards(s.players[owner]) > 0 and not contains(victims, owner) then
				victims[#victims + 1] = owner
			end
		end
		if #victims > 0 then
			local victim = s.players[victims[s.rng(1, #victims)]]
			local before = {}
			for _, res in ipairs(R.RESOURCES) do
				before[res] = victim.hand[res]
			end
			loseRandom(s, victim, 1)
			for _, res in ipairs(R.RESOURCES) do
				if victim.hand[res] < before[res] then
					p.hand[res] = p.hand[res] + 1
				end
			end
			R.say(s, p.name .. " took a card from " .. victim.name .. ".")
		else
			R.say(s, "The storm settles over an empty field.")
		end
		s.phase = "build"
		return true
	end
	-- Build phase.
	if a == "road" or a == "hamlet" or a == "town" then
		local spots = a == "road" and R.roadSpots(s, i) or a == "hamlet" and R.hamletSpots(s, i)
			or R.townSpots(s, i)
		if not R.canAfford(p, a) then
			return nil, "You need more cards for that."
		end
		if p.built[a] >= R.LIMIT[a] then
			return nil, "You have no " .. a .. "s left."
		end
		if not contains(spots, action.id) then
			return nil, "You can't build there."
		end
		pay(p, a)
		if a == "road" then
			s.edges[action.id].owner = i
		else
			local v = s.verts[action.id]
			v.owner, v.kind = i, a
			if a == "town" then
				p.built.hamlet = p.built.hamlet - 1
			end
		end
		p.built[a] = p.built[a] + 1
		R.say(s, p.name .. " built a " .. a .. ".")
		checkWin(s, i)
		return true
	elseif a == "festival" then
		if p.built.festival >= R.LIMIT.festival then
			return nil, "You already held two festivals."
		end
		if not R.canAfford(p, "festival") then
			return nil, "A festival takes wool, grain and ore."
		end
		pay(p, "festival")
		p.built.festival = p.built.festival + 1
		R.say(s, p.name .. " threw a festival!")
		checkWin(s, i)
		return true
	elseif a == "bank" then
		local give, get = action.give, action.get
		if not R.LABEL[give] or not R.LABEL[get] or give == get then
			return nil, "Pick two different resources."
		end
		local rate = R.rate(s, give)
		if p.hand[give] < rate then
			return nil, "The bank wants " .. rate .. " " .. R.LABEL[give] .. "."
		end
		p.hand[give] = p.hand[give] - rate
		p.hand[get] = p.hand[get] + 1
		R.say(s, p.name .. " traded " .. rate .. " " .. R.LABEL[give] .. " for " .. R.LABEL[get] .. ".")
		return true
	elseif a == "end" then
		s.turn = s.turn % #s.players + 1
		if s.turn == 1 then
			s.round = s.round + 1
			-- The market wants something new each round.
			local options = {}
			for _, res in ipairs(R.RESOURCES) do
				if res ~= s.market then
					options[#options + 1] = res
				end
			end
			s.market = options[s.rng(1, #options)]
			R.say(s, "Market day: the bank takes " .. R.LABEL[s.market] .. " at 2 for 1.")
		end
		s.phase = "roll"
		s.dice = nil
		return true
	end
	return nil, "Roll, build, trade or end your turn."
end

--- Cards of `res` the bank wants for one card of your choice.
function R.rate(s, res)
	return res == s.market and 2 or 4
end

--- What player `i` sees on their phone.
function R.view(s, i)
	local p = s.players[i]
	local you = {
		index = i,
		color = p.color,
		name = p.name,
		hand = p.hand,
		vp = R.vp(p),
		built = p.built,
		turn = s.turn == i,
	}
	local legal = {}
	if s.turn == i then
		if s.phase == "setup_hamlet" then
			legal.hamlet = R.hamletSpots(s, i)
		elseif s.phase == "setup_road" then
			legal.road = R.roadSpots(s, i)
		elseif s.phase == "storm" then
			legal.storm = R.stormSpots(s)
		elseif s.phase == "build" then
			for _, kind in ipairs({ "road", "hamlet", "town" }) do
				if R.canAfford(p, kind) and p.built[kind] < R.LIMIT[kind] then
					legal[kind] = kind == "road" and R.roadSpots(s, i) or kind == "hamlet"
						and R.hamletSpots(s, i) or R.townSpots(s, i)
				end
			end
			legal.festival = R.canAfford(p, "festival") and p.built.festival < R.LIMIT.festival
		end
	end
	local tiles, verts, edges, players = {}, {}, {}, {}
	for _, t in ipairs(s.tiles) do
		tiles[#tiles + 1] = { id = t.id, x = t.x, y = t.y, res = t.res, num = t.num }
	end
	for _, v in ipairs(s.verts) do
		verts[#verts + 1] = { id = v.id, x = v.x, y = v.y, owner = v.owner, kind = v.kind }
	end
	for _, e in ipairs(s.edges) do
		local a, b = s.verts[e.a], s.verts[e.b]
		edges[#edges + 1] = { id = e.id, x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y, owner = e.owner }
	end
	for _, other in ipairs(s.players) do
		players[#players + 1] = {
			name = other.name,
			color = other.color,
			vp = R.vp(other),
			cards = R.cards(other),
		}
	end
	return {
		t = "view",
		you = you,
		phase = s.phase,
		turn = s.turn,
		dice = s.dice,
		storm = s.storm,
		market = s.market,
		goal = R.GOAL,
		cost = R.COST,
		rates = { timber = R.rate(s, "timber"), clay = R.rate(s, "clay"), wool = R.rate(s, "wool"),
			grain = R.rate(s, "grain"), ore = R.rate(s, "ore") },
		legal = legal,
		players = players,
		tiles = tiles,
		verts = verts,
		edges = edges,
		log = s.log,
		winner = s.winner,
	}
end

return R
