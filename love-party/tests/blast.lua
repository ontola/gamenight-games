local B = require("games.blast")
local U = require("shared.util")
local function arena()
	local players = { { slot = 1, name = "A", score = 0 }, { slot = 2, name = "B", score = 0 } }
	local s = B.new(players, U.rng(1))
	for y = 1, 9 do
		for x = 1, 17 do
			s.tiles[B.key(x, y)] = "floor"
		end
	end
	s.drops, s.items = {}, {}
	players[1].x, players[1].y = 5, 5
	players[2].x, players[2].y = 16, 8
	return s, players[1], players[2]
end
local idle = { { x = 0, y = 0 }, { x = 0, y = 0 } }
local function has(s, x, y)
	return s.flames[B.key(x, y)] ~= nil
end
local tests = {}
function tests.seeded_levels_have_safe_spawns_and_connected_terrain()
	local fingerprints = {}
	for seed = 1, 120 do
		local settings=B.preferences(); settings.arena=({"Courtyard","Crossroads","Arcades","Pillars"})[seed%4+1]
        local a = B.generate(U.rng(seed),settings)
		local b = B.generate(U.rng(seed),settings)
		local signature = {}
		for k = 0, 208 do
			assert(a[k] == b[k])
			signature[#signature + 1] = a[k]
		end
		fingerprints[table.concat(signature)] = true
		for _, v in ipairs({ { 1, 1 }, { 17, 9 }, { 1, 9 }, { 17, 1 } }) do
			assert(a[B.key(v[1], v[2])] == "floor")
			local exits = 0
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				if a[B.key(v[1] + d[1], v[2] + d[2])] == "floor" then
					exits = exits + 1
				end
			end
			assert(exits >= 2, "spawn must have two escape routes")
		end
		-- Crates can be removed; fixed geometry must never partition the arena.
		local queue = { { 1, 1 } }
		local visited = { [B.key(1, 1)] = true }
		local i = 1
		while i <= #queue do
			local v = queue[i]
			i = i + 1
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local x, y = v[1] + d[1], v[2] + d[2]
				local k = B.key(x, y)
				if a[k] and a[k] ~= "wall" and not visited[k] then
					visited[k] = true
					queue[#queue + 1] = { x, y }
				end
			end
		end
		for k, kind in pairs(a) do
			if kind ~= "wall" then
				assert(visited[k], "isolated tile")
			end
		end
	end
	local n = 0
	for _ in pairs(fingerprints) do
		n = n + 1
	end
	assert(n > 100, "levels should vary")
end
function tests.crates_stop_blast_and_reveal_power()
	local s, p = arena()
	p.range = 4
	s.tiles[B.key(7, 5)] = "crate"
	s.drops[B.key(7, 5)] = "kick"
	local b = B.placeBomb(s, p)
	b.fuse = 0
	B.update(s, 0.01, idle)
	assert(has(s, 7, 5) and not has(s, 8, 5))
	assert(s.tiles[B.key(7, 5)] == "floor")
	assert(s.items[B.key(7, 5)] == "kick")
end
function tests.solid_walls_block_every_shape()
	for _, shape in ipairs({ "cross", "star" }) do
		local s, p = arena()
		p.shape = shape
		p.range = 4
		local dx, dy = 1, shape == "diagonal" and 1 or 0
		s.tiles[B.key(5 + dx, 5 + dy)] = "wall"
		local b = B.placeBomb(s, p)
		b.fuse = 0
		B.update(s, 0.01, idle)
		assert(not has(s, 5 + dx, 5 + dy))
		assert(not has(s, 5 + dx * 2, 5 + dy * 2))
	end
end
function tests.explosion_shapes_are_distinct()
	local counts = { cross = 9, star = 17 }
	for shape, count in pairs(counts) do
		local s, p = arena()
		p.shape = shape
		local b = B.placeBomb(s, p)
		b.fuse = 0
		B.update(s, 0.01, idle)
		local n = 0
		for _ in pairs(s.flames) do
			n = n + 1
		end
		assert(n == count, shape)
		if shape == "diagonal" then
			assert(has(s, 6, 6) and not has(s, 6, 5))
		end
		if shape == "beam" then
			assert(has(s, 9, 5) and not has(s, 5, 6))
		end
	end
end
function tests.remote_waits_for_its_owner_and_chains()
	local s, p, q = arena()
	p.remote = true
	local a = B.placeBomb(s, p)
	p.x, p.y = 1, 1
	B.update(s, 20, idle)
	assert(#s.bombs == 1 and a.fuse > 0 and next(s.flames) == nil)
	B.update(s, 0.01, { { x = 0, y = 0 }, { x = 0, y = 0, secondary = true } })
	assert(#s.bombs == 1, "other player cannot detonate")
	q.x, q.y = 7, 5
	local b = B.placeBomb(s, q)
	q.x, q.y = 16, 8
	B.update(s, 0.01, { { x = 0, y = 0, secondary = true }, { x = 0, y = 0 } })
	assert(#s.bombs == 0 and b.dead and has(s, 9, 5), "remote must trigger the chain")
end
function tests.kick_rolls_without_resetting_fuse_or_owner()
	local s, p, q = arena()
	p.x, p.y = 3, 5
	p.kick = true
	q.x, q.y = 4, 5
	local b = B.placeBomb(s, q)
	q.x, q.y = 16, 8
	B.update(s, 0.05, { { x = 1, y = 0 }, { x = 0, y = 0 } })
	assert(p.x > 3 and p.x < 4 and b.x == 5 and b.owner == q and b.fuse < 2.3)
	B.update(s, 0.08, idle)
	assert(b.x == 6 and b.fuse < 2.22)
	s.tiles[B.key(7, 5)] = "wall"
	B.update(s, 0.08, idle)
	assert(b.x == 6 and not b.sx)
end
function tests.no_kick_no_pass_and_one_bomb_per_press()
	local s, p, q = arena()
	p.x, p.y = 3, 5
	q.x, q.y = 4, 5
	B.placeBomb(s, q)
	q.x, q.y = 16, 8
	B.update(s, 0.01, { { x = 1, y = 0 }, { x = 0, y = 0 } })
	assert(p.x > 3 and p.x < 3.24)
	B.update(s, 0.01, { { x = 0, y = 0, action = true }, { x = 0, y = 0 } })
	assert(#s.bombs == 2)
	p.x = 2
	B.update(s, 0.01, { { x = 0, y = 0, action = true }, { x = 0, y = 0 } })
	assert(#s.bombs == 2)
	B.update(s, 0.01, idle)
	B.update(s, 0.01, { { x = 0, y = 0, action = true }, { x = 0, y = 0 } })
	assert(#s.bombs == 3)
end
function tests.powerups_apply_only_to_future_bombs()
	local s, p = arena()
	local before = B.placeBomb(s, p)
	for _, power in ipairs({ "remote", "kick", "star", "range", "capacity", "speed" }) do
		B.pickup(p, power)
	end
	assert(p.remote and p.kick and p.shape == "star" and p.range == 3 and p.capacity == 3 and p.speed == 7)
	assert(before.shape == "cross" and before.range == 2 and not before.remote)
end
function tests.round_replaces_level_and_resets_powers_without_losing_score()
	local s, p, q = arena()
	p.kick = true
	p.score = 9
	q.alive = false
	for _ = 1, 300 do
		B.update(s, 0.01, idle)
	end
	assert(s.round == 2 and p.alive and q.alive and not p.kick and p.score == 12)
end
function tests.pickup_badges_match_effective_upgrades_and_reset()
 local s,p=arena()
 assert(#B.upgrades(p)==0)
 B.pickup(p,"range"); B.pickup(p,"range"); B.pickup(p,"kick")
 B.pickup(p,"star")
 local badges={}
 for _,v in ipairs(B.upgrades(p)) do badges[v.id]=v.amount end
 assert(badges.range==2 and badges.kick==1 and badges.star==1 and not badges.diagonal and not badges.beam)
 assert(p.lastPickup=="star" and p.pickupNotice>0)
 s.intermission=0.01; B.update(s,0.02,idle)
 assert(#B.upgrades(p)==0 and p.lastPickup==nil)
end
function tests.pickups_are_sparse_with_two_opening_prizes()
 local crates,drops=0,0
 for seed=1,100 do
  local s=B.new({{score=0},{score=0}},U.rng(seed)); local opening=0
  for _ in pairs(s.items) do opening=opening+1 end
  assert(opening==2)
  for _,kind in pairs(s.tiles) do if kind=="crate" then crates=crates+1 end end
  for _ in pairs(s.drops) do drops=drops+1 end
 end
 assert(drops/crates<0.32 and drops/crates>0.18)
end
function tests.continuous_movement_is_frame_rate_independent_and_turns_freely()
    local a,p=arena();local b,q=arena()
    local input={{x=.6,y=.8},{x=0,y=0}}
    B.update(a,.1,input)
    for _=1,10 do B.update(b,.01,input) end
    assert(math.abs(p.x-q.x)<.00001 and math.abs(p.y-q.y)<.00001)
    assert(p.x>5 and p.x<6 and p.y>5 and p.y<6)
    assert(p.renderX==p.x and p.renderY==p.y)
    B.update(a,.02,{{x=-1,y=0},{x=0,y=0}})
    assert(p.x<q.x,"direction changes immediately")
end
function tests.collision_does_not_tunnel_and_corners_are_forgiving()
    local s,p=arena()
    s.tiles[B.key(6,5)]="wall"
    B.update(s,1,{{x=1,y=0},{x=0,y=0}})
    assert(p.x<5.24,"must stop before wall even with large dt")
    p.x,p.y=5,4.7
    s.tiles[B.key(6,4)]="wall"
    s.tiles[B.key(6,5)]="floor"
    for _=1,20 do B.update(s,.01,{{x=1,y=0},{x=0,y=0}}) end
    assert(p.x>5.5 and p.y>=4.77 and p.y<=5,"slide around nearby corner")
end
function tests.bomb_is_grid_aligned_and_cannot_be_reentered()
    local s,p=arena();p.x=5.15
    local b=B.placeBomb(s,p);assert(b.x==5 and b.y==5)
    for _=1,20 do B.update(s,.01,{{x=1,y=0},{x=0,y=0}}) end
    assert(p.x>6)
    for _=1,20 do B.update(s,.01,{{x=-1,y=0},{x=0,y=0}}) end
    assert(p.x>5.77,"cannot walk back into a planted bomb")
end
function tests.no_timer_finish_or_retired_pickups()
    assert(B.untimed)
    for _,power in ipairs(B.powers) do assert(power~="beam" and power~="diagonal") end
    local s,p=arena();B.pickup(p,"beam");B.pickup(p,"diagonal");assert(p.shape=="cross")
    B.update(s,180,idle);assert(not s.over and not s.intermission)
end
function tests.bots_fill_free_slots_and_team_elimination_ends_round()
    B.setting("ai_players",3); B.setting("teams","Teams")
    local s=B.new({{slot=1,id="human",score=0,name="P1"},{slot=3,id="other",score=0,name="P2"}},U.rng(3))
    assert(#s.players==4 and not s.players[1].bot and not s.players[3].bot)
    assert(s.players[2].localBot and s.players[4].localBot)
    assert(s.players[1].team==s.players[3].team)
    s.players[2].alive=false
    B.update(s,.8,{{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0}})
    assert(not s.intermission,"one fallen rival does not finish teams")
    s.players[4].alive=false
    B.update(s,.8,{{x=0,y=0},{x=0,y=0},{x=0,y=0},{x=0,y=0}})
    assert(s.intermission and s.players[1].score==3 and s.players[3].score==3)
    B.setting("ai_players",0);B.setting("teams","Free-for-all")
end
function tests.menu_is_edge_triggered_and_uses_shared_settings()
    local s,p=arena(); local sent={}
    local function change(key,value) assert(B.setting(key,value));sent[key]=value end
    assert(B.menuUpdate(s,.01,{start=true},change) and s.paused)
    B.menuUpdate(s,.01,{start=true},change);assert(s.paused)
    B.menuUpdate(s,.01,{},change);B.menuUpdate(s,.01,{down=true},change)
    B.menuUpdate(s,.01,{},change);B.menuUpdate(s,.01,{right=true},change)
    assert(sent.ai_players==1 and #s.players==2,"roster must wait for next round")
    B.menuUpdate(s,.01,{cancel=true},change);assert(not s.paused and p.actionHeld)
    B.setting("ai_players",0)
end
local count = 0
for name, fn in pairs(tests) do
	fn()
	count = count + 1
	print("PASS blast: " .. name)
end
print("PASS " .. count .. " blast tests")
return true
