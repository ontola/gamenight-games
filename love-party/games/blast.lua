local U = require("shared.util")
local M = {
    untimed = true,
	title = "BLAST PARTY",
	tagline = "Small bombs. Big betrayals.",
	id = "blast-party",
	controls = "MOVE stick / keys   BOMB A / action   DETONATE B / secondary",
	width = 19,
	height = 11,
	powers = { "remote", "kick", "star", "range", "capacity", "speed", "cross" },
}
require("shared.settings").bind(M, {
    {key="ai_players", label="AI opponents (next round, up to 4 total)", kind="number", default=0, min=0, max=3},
    {key="teams", label="Mode (next round)", kind="choice", default="Free-for-all", options={"Free-for-all", "Teams"}},
    {key="arena", label="Arena (next round)", kind="choice", default="Random", options={"Random", "Courtyard", "Crossroads", "Arcades", "Pillars"}},
    {key="friendly_fire", label="Team damage (next round)", kind="toggle", default=false},
    {key="pickups", label="Pickup chance % (next round)", kind="number", default=25, min=0, max=60},
    {key="crates", label="Crate density % (next round)", kind="number", default=62, min=20, max=85},
    {key="fuse", label="Bomb fuse (next round)", kind="choice", default="2.3 s", options={"1.0 s","1.5 s","2.0 s","2.3 s","3.0 s","4.0 s"}},
})

local directions = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local diagonals = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local spawns = { { 1, 1 }, { 17, 9 }, { 1, 9 }, { 17, 1 } }
function M.key(x, y)
	return y * M.width + x
end
local function tile(s, x, y)
    if x < 0 or x >= M.width or y < 0 or y >= M.height then return "wall" end
	return s.tiles[M.key(x, y)] or "wall"
end
local function bombAt(s, x, y)
	for _, b in ipairs(s.bombs) do
		if not b.dead and b.x == x and b.y == y then
			return b
		end
	end
end
local function occupied(s, x, y)
	for _, p in ipairs(s.players) do
		if p.alive and math.abs(p.x-x) < 0.8 and math.abs(p.y-y) < 0.8 then
			return true
		end
	end
	return false
end
local layouts = {"Courtyard", "Crossroads", "Arcades", "Pillars"}
function M.generate(rng, settings)
    settings = settings or M.preferences()
    local layout = settings.arena or "Random"
    if layout == "Random" then layout = layouts[rng(1,#layouts)] end
    local tiles, drops = {}, {}
    -- Mirror a designed skeleton; vary crates and drops independently of it.
    -- All fixed barriers have routes around them, and corner exits stay clear.
    for y=0,10 do
        for x=0,18 do
            local mx,my = math.min(x,18-x),math.min(y,10-y)
            local k=M.key(mx,my)
            if tiles[k]==nil then
                local safe=mx+my<=5
                local wall=mx==0 or my==0
                if not wall and not safe then
                    if layout=="Pillars" then wall=mx%2==0 and my%2==0
                    elseif layout=="Courtyard" then wall=(mx==4 and my>=3 and my<=4) or (my==2 and mx>=6 and mx<=7)
                    elseif layout=="Crossroads" then wall=mx%3==0 and my%3==0
                    elseif layout=="Arcades" then wall=my==3 and mx>=3 and mx<=7 and mx~=5 end
                end
                local kind=wall and "wall" or (not safe and rng()<settings.crates/100 and "crate" or "floor")
                tiles[k]=kind
                if kind=="crate" and rng()<settings.pickups/100 then drops[k]=M.powers[rng(1,#M.powers)] end
            end
            tiles[M.key(x,y)],drops[M.key(x,y)]=tiles[k],drops[k]
        end
    end
    return tiles,drops,layout
end
local function roster(s)
    local result, occupiedSlots = {}, {}
    for _,p in ipairs(s.roster) do
        result[#result+1]=p; occupiedSlots[p.slot or #result]=true
    end
    local bots=math.min(s.settings.ai_players,4-#result)
    for slot=1,4 do
        if bots>0 and not occupiedSlots[slot] then
            result[#result+1]={slot=slot,name="CPU "..slot,bot=true,localBot=true,score=0}
            bots=bots-1
        end
    end
    table.sort(result,function(a,b) return (a.slot or 0)<(b.slot or 0) end)
    s.players=result
end
local function reset(s)
	s.settings = M.preferences()
	roster(s)
	s.tiles, s.drops, s.layout = M.generate(s.rng, s.settings)
	s.bombs, s.flames, s.items = {}, {}, {}
	s.round = (s.round or 0) + 1
	s.theme = s.rng(1, 3)
	s.roundTime = 0
	s.settle = nil
	s.intermission = nil
	for i, p in ipairs(s.players) do
		p.x, p.y = spawns[i][1], spawns[i][2]
        p.team = s.settings.teams == "Teams" and ((i-1)%2+1) or i
		p.renderX, p.renderY = p.x, p.y
		p.alive, p.range, p.capacity, p.speed = true, 2, 2, 6
		p.remote, p.kick, p.shape = false, false, "cross"
		p.dx, p.dy = 1, 0
		p.moveClock = 0
		p.actionHeld, p.secondaryHeld = false, false
		p.botClock = 0
		p.lastPickup, p.pickupNotice = nil, 0
	end
	-- Visible opening prizes encourage leaving the safe spawn pockets.
	local available = {}
	for y = 1, 9 do
		for x = 4, 14 do
			if tile(s, x, y) == "floor" then
				available[#available + 1] = { x, y }
			end
		end
	end
	for _, power in ipairs({ "range", "capacity" }) do
		if #available > 0 then
			local v = table.remove(available, s.rng(1, #available))
			s.items[M.key(v[1], v[2])] = power
		end
	end
end
function M.new(players, rng)
	local s = { roster = players, players = players, rng = rng, time = 0 }
	reset(s)
	return s
end
function M.blastCells(s, b)
	local cells = { { b.x, b.y } }
	local rays = directions
	local reach = b.range
	if b.shape == "star" then
		rays = {}
		for _, v in ipairs(directions) do
			rays[#rays + 1] = v
		end
		for _, v in ipairs(diagonals) do
			rays[#rays + 1] = v
		end
	end
	for _, v in ipairs(rays) do
		for n = 1, reach do
			local x, y = b.x + v[1] * n, b.y + v[2] * n
			local kind = tile(s, x, y)
			if kind == "wall" then
				break
			end
			cells[#cells + 1] = { x, y }
			if kind == "crate" or bombAt(s, x, y) then
				break
			end
		end
	end
	return cells
end
function M.placeBomb(s, p)
    local x,y=math.floor(p.x+.5),math.floor(p.y+.5)
	if not p.alive or bombAt(s, x, y) then
		return nil
	end
	local count = 0
	for _, b in ipairs(s.bombs) do
		if not b.dead and b.owner == p then
			count = count + 1
		end
	end
	if count >= p.capacity then
		return nil
	end
	local b = {
		x = x,
		y = y,
        pass = {},
		owner = p,
		range = p.range,
		shape = p.shape,
		dx = p.dx,
		dy = p.dy,
		remote = p.remote,
		fuse = p.remote and math.huge or tonumber(s.settings.fuse:match("^[%d.]+")),
		slideClock = 0,
	}
    for _,other in ipairs(s.players) do
        if math.abs(other.x-x)<.8 and math.abs(other.y-y)<.8 then b.pass[other]=true end
    end
	s.bombs[#s.bombs + 1] = b
	return b
end
function M.pickup(p, power)
    if power == "beam" or power == "diagonal" then return end
	p.lastPickup, p.pickupNotice = power, 2.5
	if power == "remote" then
		p.remote = true
	elseif power == "kick" then
		p.kick = true
	elseif power == "range" then
		p.range = math.min(5, p.range + 1)
	elseif power == "capacity" then
		p.capacity = math.min(5, p.capacity + 1)
	elseif power == "speed" then
		p.speed = math.min(9, p.speed + 1)
	else
		p.shape = power
	end
end
local function explode(s, first)
	s.blastCount = (s.blastCount or 0) + 1
	local queue = { first }
	local queued = { [first] = true }
	local destroyed = {}
	local index = 1
	-- Keep crates intact until the whole chain has traced its rays. A second
	-- blast in this chain must not pass through a crate the first one destroyed.
	while index <= #queue do
		local b = queue[index]
		index = index + 1
		if not b.dead then
			local cells = M.blastCells(s, b)
			b.dead = true
			for _, v in ipairs(cells) do
				local k = M.key(v[1], v[2])
				s.flames[k] = { ttl = 0.55, owner = b.owner, shape = b.shape }
				local chained = bombAt(s, v[1], v[2])
				if chained and not queued[chained] then
					queued[chained] = true
					queue[#queue + 1] = chained
				end
				if tile(s, v[1], v[2]) == "crate" then
					destroyed[k] = true
				else
					s.items[k] = nil
				end
			end
		end
	end
	for k in pairs(destroyed) do
		s.tiles[k] = "floor"
		s.items[k] = s.drops[k]
		s.drops[k] = nil
	end
end
local function killInFlame(s, p)
	local flame = s.flames[M.key(math.floor(p.x+.5), math.floor(p.y+.5))]
	if p.alive and flame then
        if s.settings.teams == "Teams" and not s.settings.friendly_fire and flame.owner ~= p and flame.owner.team == p.team then return end
		p.alive = false
		p.score = p.score - 1
		if flame.owner ~= p and (s.settings.teams ~= "Teams" or flame.owner.team ~= p.team) then
			flame.owner.score = flame.owner.score + 1
		end
	end
end
local function moveBomb(s, b, dx, dy)
	local x, y = b.x + dx, b.y + dy
	if tile(s, x, y) ~= "floor" or bombAt(s, x, y) or occupied(s, x, y) then
		return false
	end
	b.x, b.y = x, y
	return true
end
local radius = 0.27
local function free(s,p,x,y,dx,dy)
    for ty=math.floor(y-radius+.5),math.floor(y+radius+.5) do
        for tx=math.floor(x-radius+.5),math.floor(x+radius+.5) do
            if tile(s,tx,ty)~="floor" then return false end
            local bomb=bombAt(s,tx,ty)
            if bomb and not (bomb.pass and bomb.pass[p]) then
                if not p.kick or (dx==0 and dy==0) or not moveBomb(s,bomb,dx,dy) then return false end
                bomb.sx,bomb.sy,bomb.slideClock=dx,dy,0
            end
        end
    end
    return true
end
local function axisMove(s,p,step,horizontal)
    if step==0 then return end
    local dx,dy=horizontal and (step>0 and 1 or -1) or 0, not horizontal and (step>0 and 1 or -1) or 0
    local x,y=p.x+(horizontal and step or 0),p.y+(not horizontal and step or 0)
    if free(s,p,x,y,dx,dy) then p.x,p.y=x,y; return end
    -- Slide towards a nearby corridor centre when a corner catches the body.
    -- The correction is speed-limited, collision-checked, and never teleports.
    local v=horizontal and p.y or p.x
    local target=math.floor(v+.5)
    if math.abs(v-target)>.001 and math.abs(v-target)<=.4 then
        local correction=U.clamp(target-v,-math.abs(step),math.abs(step))
        local ax,ay=horizontal and p.x or p.x+correction,horizontal and p.y+correction or p.y
        local aheadx,aheady=horizontal and x or target,horizontal and target or y
        if free(s,p,aheadx,aheady,0,0) and free(s,p,ax,ay,0,0) then p.x,p.y=ax,ay end
    end
end
local function movePlayer(s,p,c,dt)
    local x,y=c.x or 0,c.y or 0
    local magnitude=math.sqrt(x*x+y*y)
    if magnitude<.2 then return end
    if magnitude>1 then x,y=x/magnitude,y/magnitude end
    if math.abs(x)>math.abs(y) then p.dx,p.dy=x>0 and 1 or -1,0
    else p.dx,p.dy=0,y>0 and 1 or -1 end
    local distance=p.speed*dt
    local steps=math.max(1,math.ceil(distance/.08))
    for _=1,steps do
        axisMove(s,p,x*distance/steps,true)
        axisMove(s,p,y*distance/steps,false)
        for _,bomb in ipairs(s.bombs) do
            if bomb.pass and (math.abs(p.x-bomb.x)>=.5+radius or math.abs(p.y-bomb.y)>=.5+radius) then bomb.pass[p]=nil end
        end
        killInFlame(s,p)
        if not p.alive then break end
    end
end
function M.update(s, dt, inputs)
	s.time = s.time + dt
	if s.intermission then
		s.intermission = s.intermission - dt
		if s.intermission <= 0 then
			reset(s)
		end
		return
	end
	s.roundTime = s.roundTime + dt
	for k, f in pairs(s.flames) do
		f.ttl = f.ttl - dt
		if f.ttl <= 0 then
			s.flames[k] = nil
		end
	end
	for i, p in ipairs(s.players) do
		local c = inputs[i]
		p.pickupNotice = math.max(0, (p.pickupNotice or 0) - dt)
		killInFlame(s, p)
		if p.alive then
			if c.action and not p.actionHeld then
				M.placeBomb(s, p)
			end
			if c.secondary and not p.secondaryHeld then
				for _, b in ipairs(s.bombs) do
					if b.owner == p and b.remote then
						b.fuse = 0
					end
				end
			end
			movePlayer(s, p, c, dt)
			local k = M.key(math.floor(p.x+.5), math.floor(p.y+.5))
			if s.items[k] and not s.flames[k] then
				M.pickup(p, s.items[k])
				s.items[k] = nil
			end
		end
		p.actionHeld, p.secondaryHeld = c.action, c.secondary
		p.renderX, p.renderY = p.x, p.y
	end
	for _, b in ipairs(s.bombs) do
		if b.sx and not b.dead then
			b.slideClock = b.slideClock + dt
			if b.slideClock >= 0.075 then
				b.slideClock = b.slideClock - 0.075
				if not moveBomb(s, b, b.sx, b.sy) then
					b.sx, b.sy = nil, nil
				end
			end
		end
		if not b.owner.alive then
			b.fuse = math.min(b.fuse, tonumber(s.settings.fuse:match("^[%d.]+")))
		end
		b.fuse = b.fuse - dt
		if s.flames[M.key(b.x, b.y)] then
			b.fuse = 0
		end
		if b.fuse <= 0 and not b.dead then
			explode(s, b)
		end
	end
	for i = #s.bombs, 1, -1 do
		if s.bombs[i].dead then
			table.remove(s.bombs, i)
		end
	end
	local alive, teams = 0, {}
	for _, p in ipairs(s.players) do
		killInFlame(s, p)
		if p.alive then
			alive = alive + 1
            teams[p.team] = true
		end
	end
	local teamCount=0; for _ in pairs(teams) do teamCount=teamCount+1 end
	if teamCount <= 1 and #s.players > 1 then
		s.settle = (s.settle or 0) + dt
		if s.settle > 0.65 then
			for _, p in ipairs(s.players) do
				if teams[p.team] then
					p.score = p.score + 3
				end
			end
			s.intermission = 1.7
		end
	end
end
function M.bot(s, p)
    local px,py=math.floor(p.x+.5),math.floor(p.y+.5)
	if not p.alive then
		return { x = 0, y = 0 }
	end
	if p.botClock and p.botClock > s.time then
		return p.botInput
	end
	p.botClock = s.time + 0.16
	local danger = {}
	for _, b in ipairs(s.bombs) do
		for _, v in ipairs(M.blastCells(s, b)) do
			danger[M.key(v[1], v[2])] = true
		end
	end
	for k in pairs(s.flames) do
		danger[k] = true
	end
	local adjacent = false
	for _, v in ipairs(directions) do
		if tile(s, px + v[1], py + v[2]) == "crate" then
			adjacent = true
		end
	end
	local choices = {}
	for _, v in ipairs(directions) do
		local x, y = px + v[1], py + v[2]
		if tile(s, x, y) == "floor" and not bombAt(s, x, y) then
			local score = s.rng() * 2 + (danger[M.key(x, y)] and -10 or 5)
			if s.items[M.key(x, y)] then
				score = score + 6
			end
			choices[#choices + 1] = { x = v[1], y = v[2], score = score }
		end
	end
	table.sort(choices, function(a, b)
		return a.score > b.score
	end)
	local c = choices[1] or { x = 0, y = 0 }
	-- Bot bombs are deliberately occasional; humans get the same rules.
	c.action = adjacent and not danger[M.key(px, py)] and #choices > 1 and s.rng() < 0.18
	c.secondary = not danger[M.key(px, py)] and s.rng() < 0.15
	p.botInput = c
	return c
end
-- Only effective upgrades: replacing a blast pattern removes the old badge.
function M.upgrades(p)
    local result = {}
    local function add(id, amount)
        if amount > 0 then result[#result + 1] = { id = id, amount = amount } end
    end
    add("capacity", p.capacity - 2)
    add("range", p.range - 2)
    add("speed", p.speed - 6)
    add("kick", p.kick and 1 or 0)
    add("remote", p.remote and 1 or 0)
    if p.shape ~= "cross" then add(p.shape, 1) end
    return result
end
function M.describe(p)
	if not p.alive then
		return "OUT - back next round"
	end
	local names = { cross = "CROSS", star = "STAR" }
	return names[p.shape]
		.. "  "
		.. p.capacity
		.. "B / "
		.. p.range
		.. "R"
		.. (p.remote and "  REM" or "")
		.. (p.kick and "  KICK" or "")
end
-- Host roster changes preserve current players until a fresh arena; identity
-- updates still apply immediately. Local AI never claims a physical controller.
function M.party(s, incoming, presence)
    local current={}
    for _,p in ipairs(incoming) do
        p.presence="active"
        for _,status in ipairs(presence or {}) do if status.player_id==p.id then p.presence=status.state end end
    end
    for _,p in ipairs(s.players) do if not p.localBot then current[p.id or p.slot]=p end end
    s.roster={}
    for _,p in ipairs(incoming) do
        local existing=current[p.id or p.slot]
        if existing then
            for _,key in ipairs({"name","color","controller","avatar","skin_color","presence"}) do existing[key]=p[key] end
            p=existing
        end
        s.roster[#s.roster+1]=p
    end
    return incoming
end
M.restart = reset
require("games.blast_menu")(M)
return M
