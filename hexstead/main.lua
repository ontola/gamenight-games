--- Hexstead: build on a random island. The TV shows the board; each player's
--- cards and choices live on their phone (the GameNight app opens the phone
--- page by itself). AI seats, and players whose phone is away, are played by
--- bots so the table never stalls.
local R = require("rules")
local Bot = require("bot")
local Render = require("render")
local Window = require("net.window")

local managed = os.getenv("GAMENIGHT") == "1"
local GAME = os.getenv("GAMENIGHT_GAME_ID") or "hexstead"
--- Seconds a player without a phone gets before the bot takes their turn.
local AWAY_GRACE = 15
local BOT_STEP = tonumber(os.getenv("HEXSTEAD_BOT_STEP")) or 0.9

local net, session, phase = nil, nil, "idle"
local state, roster
local phones = {} -- player id -> open phone screens
local botClock, awayClock, overClock = 0, 0, 0
local sentEvents = -1
local shotClock

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

local function seed()
	return tonumber(os.getenv("HEXSTEAD_SEED")) or (os.time() % 2147483646 + 1)
end

local function send(message)
	if net then
		net:send(message)
	end
end

local function hasPhone(p)
	return p.id and (phones[p.id] or 0) > 0
end

--- Who decides for this seat right now: its phone, or a bot.
local function botTurn(i)
	local p = state.players[i]
	return p.bot or (not hasPhone(p) and awayClock >= AWAY_GRACE)
end

local function sendView(p, i)
	if p.id and hasPhone(p) then
		send({ type = "companion_message", player_id = p.id, data = R.view(state, i) })
	end
end

local function broadcast()
	if not state then
		return
	end
	for i, p in ipairs(state.players) do
		sendView(p, i)
	end
	sentEvents = state.events
end

local function newGame()
	state = R.new(roster, rng(seed()))
	botClock, awayClock, overClock = 0, 0, 0
	broadcast()
end

local function act(i, action)
	local before = state.phase
	local ok, why = R.act(state, i, action)
	if ok then
		awayClock = 0
		broadcast()
		if state.phase == "over" and before ~= "over" and session then
			send({ type = "finished", session = session })
		end
	end
	return ok, why
end

local function rosterFrom(seats, players)
	local out = {}
	for _, seat in ipairs(seats) do
		local o = seat.occupant
		if o.kind ~= "empty" then
			local entry = { id = o.player_id, bot = o.kind == "ai", name = "Bot " .. (seat.index + 1) }
			for _, player in ipairs(players) do
				if player.id == o.player_id then
					entry.name, entry.color = player.name, player.color
				end
			end
			out[#out + 1] = entry
		end
	end
	-- Hexstead needs company: fill up to three with bots.
	local names = { "Bramble", "Cobble", "Thistle" }
	while #out < 3 do
		out[#out + 1] = { bot = true, name = names[#out] }
	end
	-- Player colours must differ on the board even when profiles agree.
	local used = {}
	for i, p in ipairs(out) do
		if not p.color or used[p.color] then
			for _, c in ipairs(R.COLORS) do
				if not used[c] then
					p.color = c
					break
				end
			end
		end
		used[p.color] = true
		out[i] = p
	end
	return out
end

--- Phone page files live inside the game; GameNight needs a real folder.
local function installPhonePage()
	local files = { "index.html", "phone.js", "phone.css" }
	love.filesystem.createDirectory("phone")
	for _, name in ipairs(files) do
		local data = love.filesystem.read("phone/" .. name)
		if data then
			love.filesystem.write("phone/" .. name, data)
		end
	end
	return love.filesystem.getSaveDirectory() .. "/phone"
end

local function receive(m)
	if m.type == "welcome" then
		send({ type = "declare_companion", root = installPhonePage(), entry = "index.html" })
	elseif m.type == "prepare" and m.game == GAME then
		session = m.session
		roster = rosterFrom(m.seats or {}, m.players or {})
		newGame()
		phase = "ready"
		send({ type = "ready", session = session })
	elseif m.type == "start" and m.session == session then
		phase = "running"
		Window.show(function()
			Render.draw(state, {})
		end)
	elseif m.type == "pause" and m.session == session then
		phase = "paused"
		Window.hide()
	elseif m.type == "resume" and m.session == session then
		phase = "running"
		Window.show(function()
			Render.draw(state, {})
		end)
	elseif m.type == "dispose" and m.session == session then
		session, state, phase = nil, nil, "idle"
		Window.hide()
	elseif m.type == "companion_presence" then
		phones[m.player_id] = math.max(0, (phones[m.player_id] or 0) + (m.connected and 1 or -1))
		if m.connected and state then
			for i, p in ipairs(state.players) do
				if p.id == m.player_id then
					sendView(p, i)
				end
			end
		end
	elseif m.type == "companion_message" and state and type(m.data) == "table" then
		for i, p in ipairs(state.players) do
			if p.id == m.player_id then
				local ok, why = act(i, m.data)
				if not ok then
					send({ type = "companion_message", player_id = p.id, data = { t = "error", text = why } })
				end
			end
		end
	end
end

function love.load()
	if os.getenv("HEXSTEAD_TEST") == "1" then
		local ok, err = pcall(require, "tests.rules")
		print(ok and "hexstead tests passed" or err)
		love.event.quit(ok and 0 or 1)
		return
	end
	if managed then
		Window.prepare()
		net = require("net.transport").new(os.getenv("GAMENIGHT_ADDR") or "127.0.0.1:7912", GAME,
			os.getenv("GAMENIGHT_TOKEN"))
	else
		roster = rosterFrom({}, {})
		table.insert(roster, 1, { bot = true, name = "Juniper", color = R.COLORS[5] })
		newGame()
		phase = "running"
	end
end

function love.update(dt)
	if net then
		local ok, err = net:poll(receive)
		if not ok then
			print("GameNight disconnected: " .. tostring(err))
			love.event.quit()
			return
		end
	end
	if not state or phase ~= "running" then
		return
	end
	-- Development aid: keep a fresh capture of the TV in the save folder.
	if os.getenv("HEXSTEAD_SHOTS") == "1" then
		shotClock = (shotClock or 0) + dt
		if shotClock > 2 then
			shotClock = 0
			love.graphics.captureScreenshot("tv.png")
		end
	end
	if state.phase == "over" then
		overClock = overClock + dt
		if overClock > 12 then
			newGame()
		end
	else
		local p = state.players[state.turn]
		if not p.bot and not hasPhone(p) then
			awayClock = awayClock + dt
		end
		if botTurn(state.turn) then
			botClock = botClock + dt
			if botClock >= BOT_STEP then
				botClock = 0
				local choice = Bot.choose(state, state.turn)
				if not choice or not act(state.turn, choice) then
					act(state.turn, { a = "end" })
				end
			end
		else
			botClock = 0
		end
	end
	if state.events ~= sentEvents then
		broadcast()
	end
end

function love.draw()
	if not state then
		return
	end
	local banner
	if state.phase ~= "over" then
		local p = state.players[state.turn]
		if not p.bot and not hasPhone(p) then
			banner = awayClock < AWAY_GRACE
					and (p.name .. ": open the GameNight app on your phone to play your turn ("
						.. math.ceil(AWAY_GRACE - awayClock) .. ")")
				or (p.name .. "'s phone is away, so a bot plays this turn.")
		end
	else
		banner = "New island in " .. math.max(0, math.ceil(12 - overClock)) .. "…"
	end
	Render.draw(state, {
		banner = banner,
		status = function(i)
			local p = state.players[i]
			if p.bot then
				return " · bot"
			end
			return hasPhone(p) and " · on phone" or " · no phone"
		end,
	})
end

function love.keypressed(key)
	if key == "escape" and session and phase == "running" then
		send({ type = "request_overlay" })
	elseif key == "escape" and not managed then
		love.event.quit()
	end
end
