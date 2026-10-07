-- Headless rule checks: HEXSTEAD_TEST=1 love hexstead
local R = require("rules")
local Bot = require("bot")
local json = require("vendor.json")

local function rng(seed)
	return function(a, b)
		seed = (seed * 16807) % 2147483647
		local r = (seed - 1) / 2147483646
		if a then
			return a + math.floor(r * (b - a + 1))
		end
		return r
	end
end

local function check(ok, message)
	if not ok then
		error(message, 2)
	end
end

local function roster(n)
	local out = {}
	for i = 1, n do
		out[i] = { id = "p" .. i, name = "P" .. i, bot = true }
	end
	return out
end

-- Boards: 19 connected fields, one lake, no touching 6s and 8s.
for seedValue = 1, 60 do
	local b = R.board(rng(seedValue))
	check(#b.tiles == 19, "19 tiles")
	local lakes, nums = 0, {}
	for _, t in ipairs(b.tiles) do
		if not t.res then
			lakes = lakes + 1
			check(b.storm == t.id, "the storm starts on the lake")
		else
			nums[#nums + 1] = t.num
		end
		check(#t.verts == 6, "every field has six corners")
	end
	check(lakes == 1 and #nums == 18, "one lake, 18 numbered fields")
	for _, e in ipairs(b.edges) do
		check(e.a ~= e.b, "edges join two corners")
	end
end

-- Rules: turn order, refusals and the opening.
do
	local s = R.new(roster(3), rng(7))
	check(s.phase == "setup_hamlet" and s.turn == 1, "player 1 opens")
	check(not R.act(s, 2, { a = "hamlet", id = 1 }), "out of turn is refused")
	check(not R.act(s, 1, { a = "roll" }), "no rolling during setup")
	local spot = R.hamletSpots(s, 1)[1]
	check(R.act(s, 1, { a = "hamlet", id = spot }), "first hamlet")
	for _, n in ipairs(s.verts[spot].adj) do
		check(not R.act(s, 1, { a = "road", id = -1 }), "bad road refused")
		check(not (function()
			for _, v in ipairs(R.hamletSpots(s, 2)) do
				if v == n then
					return true
				end
			end
		end)(), "neighbouring corners stay free")
	end
	check(R.act(s, 1, { a = "road", id = R.roadSpots(s, 1)[1] }), "first road")
	check(s.turn == 2, "setup moves on")
	-- Finish the opening with bots; the order snakes back.
	local order = {}
	while s.phase:match("^setup") do
		if s.phase == "setup_hamlet" then
			order[#order + 1] = s.turn
		end
		check(R.act(s, s.turn, Bot.choose(s, s.turn)), "bot setup move")
	end
	check(table.concat(order, ",") == "2,3,3,2,1", "snake order, got " .. table.concat(order, ","))
	for _, p in ipairs(s.players) do
		check(p.built.hamlet == 2 and p.built.road == 2, "two hamlets and roads each")
		check(R.cards(p) >= 1, "second hamlet pays out")
	end
	check(s.phase == "roll" and s.turn == 1, "player 1 rolls first")
	check(not R.act(s, 1, { a = "end" }), "roll before ending")
end

-- Whole games: bots always finish, and every view encodes as JSON.
local turns = 0
for seedValue = 1, 25 do
	local players = 3 + seedValue % 2
	local s = R.new(roster(players), rng(seedValue * 31))
	local steps = 0
	while s.phase ~= "over" do
		steps = steps + 1
		check(steps < 20000, "game " .. seedValue .. " never ended")
		local choice = Bot.choose(s, s.turn)
		local ok, why = R.act(s, s.turn, choice)
		if not ok then
			error("bot move refused: " .. tostring(why) .. " " .. json.encode(choice))
		end
		if choice.a == "end" then
			turns = turns + 1
		end
		for _, p in ipairs(s.players) do
			for _, res in ipairs(R.RESOURCES) do
				check(p.hand[res] >= 0, "no negative cards")
			end
		end
		if steps % 50 == 0 then
			local text = json.encode(R.view(s, s.turn))
			check(#text < 60000, "views stay small")
		end
	end
	check(R.vp(s.players[s.winner]) >= R.GOAL, "the winner reached the goal")
	-- Hamlets never touch.
	for _, v in ipairs(s.verts) do
		if v.owner then
			for _, n in ipairs(v.adj) do
				check(not s.verts[n].owner, "hamlets keep their distance")
			end
		end
	end
	check(not R.act(s, s.turn, { a = "roll" }), "nothing after the end")
end
print(("hexstead: 25 bot games finished, %d turns"):format(turns))
