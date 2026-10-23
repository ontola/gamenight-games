return function()
  local T,B=require("games.coop.stack"),require("games.coop.bubbles")
  local seats={{slot=1,name="P1"},{slot=2,name="P2"}}
  local n=0
  local function check(name,f) f(); n=n+1; print("PASS "..name) end
  check("a half row waits for the teammate",function()
    local g=T.new(seats)
    for x=1,6 do g.board[18][x]=1 end
    assert(T.clear(g)==0 and g.rows==0)
    for x=7,12 do g.board[18][x]=2 end
    assert(T.clear(g)==1 and g.rows==1 and #g.board==18)
  end)
  check("multiple rows clear and stacks settle",function()
    local g=T.new(seats); g.board[16][3]=4
    for y=17,18 do for x=1,12 do g.board[y][x]=2 end end
    assert(T.clear(g)==2 and g.board[18][3]==4)
  end)
  check("piece movement cannot cross the shared seam",function()
    local g=T.new(seats); local p=g.players[1]
    assert(not T.fits(g,p,7,3,0))
    p=g.players[2]; assert(not T.fits(g,p,4,3,0))
  end)
  check("hard drop locks four cells and produces the next piece",function()
    local g=T.new(seats); T.step(g,{[1]={drop=true}},1/120)
    local count=0; for _,r in ipairs(g.board) do for _ in pairs(r) do count=count+1 end end
    assert(count==4 and g.players[1].y==1)
  end)
  check("shared target wins and terminal state freezes",function()
    local g=T.new(seats); g.rows=11
    for x=1,12 do g.board[18][x]=2 end
    T.clear(g); assert(g.phase=="won")
    local time=g.time; T.step(g,{},1); assert(g.time==time)
  end)
  check("blocked spawn loses cleanly",function()
    local g=T.new(seats)
    for y=1,4 do for x=1,6 do g.board[y][x]=1 end end
    T.spawn(g,g.players[1]); assert(g.phase=="lost")
  end)
  check("large bubbles split into exactly two smaller bubbles",function()
    local g=B.new(seats); g.phase="play"
    g.bubbles={{size=3,x=600,y=300,r=52,vx=0,vy=0}}
    g.ropes={{slot=1,x=600,y=280,life=1}}
    B.step(g,{},1/120)
    assert(#g.bubbles==2 and g.bubbles[1].size==2 and g.bubbles[2].size==2 and g.popped==1)
  end)
  check("last small bubble clears wave and restores a shared heart",function()
    local g=B.new(seats); g.phase="play"; g.hearts=4
    g.bubbles={{size=1,x=600,y=300,r=18,vx=0,vy=0}}; g.ropes={{slot=1,x=600,y=280,life=1}}
    B.step(g,{},1/120); assert(g.phase=="clear")
    B.step(g,{},1.6); assert(g.wave==2 and g.hearts==5)
  end)
  check("damage shares hearts and respects invulnerability",function()
    local g=B.new(seats); g.phase="play"; local p=g.players[1]; p.invuln=0
    g.bubbles={{size=1,x=p.x,y=B.floor-25,r=18,vx=0,vy=0}}
    B.step(g,{},1/120); assert(g.hearts==5 and p.out>0)
    B.step(g,{},1/120); assert(g.hearts==5)
  end)
  check("timer and fifth wave produce terminal results",function()
    local g=B.new(seats); g.phase="play"; g.clock=.001; B.step(g,{},1/120); assert(g.phase=="lost")
    g=B.new(seats); g.phase="clear"; g.wave=g.settings.waves; g.timer=.001; B.step(g,{},1/120); assert(g.phase=="won")
  end)
  check("multi rope power fires three parallel ropes",function()
    local g=B.new(seats); g.phase="play"; g.bubbles={{size=1,x=40,y=100,r=20,vx=0,vy=0}}
    local p=g.players[1]; p.power.multi=5
    B.step(g,{[1]={fire=true}},1/120); assert(#g.ropes==3)
    B.step(g,{[1]={fire=true}},.3); assert(#g.ropes==3)
  end)
  check("no power makes the next shot wait longer than a plain rope",function()
    local function wait(power)
      local g=B.new(seats); g.phase="play"; g.bubbles={{size=1,x=40,y=100,r=20,vx=0,vy=0}}
      local p=g.players[1]; if power then p.power[power]=30 end
      B.step(g,{[1]={fire=true}},1/120); local first=#g.ropes
      for i=1,600 do B.step(g,{[1]={fire=true}},1/120); if #g.ropes>first then return i end end
      return math.huge
    end
    local plain=wait()
    for _,power in ipairs({"multi","ghost","rapid","speed"}) do assert(wait(power)<=plain,power) end
  end)
  check("ghost rope lingers and pops more than one bubble",function()
    local g=B.new(seats); g.phase="play"
    g.bubbles={{size=1,x=600,y=300,r=20,vx=0,vy=0},{size=1,x=600,y=500,r=20,vx=0,vy=0},{size=1,x=40,y=60,r=20,vx=0,vy=0}}
    g.ropes={{slot=1,x=600,y=200,life=3,ghost=true}}
    B.step(g,{},1/120); assert(g.popped==2 and #g.ropes==1)
    for _=1,120 do B.step(g,{},1/120) end; assert(#g.ropes==1)
  end)
  check("shield absorbs a hit and dynamite splits every bubble",function()
    local g=B.new(seats); g.phase="play"; local p=g.players[1]; p.invuln=0; p.shield=true
    g.bubbles={{size=1,x=p.x,y=B.floor-25,r=20,vx=0,vy=0}}
    B.step(g,{},1/120); assert(g.hearts==6 and not p.shield and p.out==0)
    g=B.new(seats); g.phase="play"; g.settings.powerups=false
    g.bubbles={{size=3,x=300,y=200,r=54,vx=0,vy=0}}
    g.pickups={{kind="dynamite",x=g.players[1].x,y=B.floor-18,vy=0,life=5}}
    B.step(g,{},1/120); assert(#g.bubbles==4)
    for _,b in ipairs(g.bubbles) do assert(b.size==1) end
  end)
  check("the arena follows the screen aspect",function()
    local g=B.new(seats); local x=g.players[2].x
    B.resize(g,1920,1080); assert(math.abs(g.width-800*16/9)<.01 and math.abs(g.players[2].x-x*g.width/1280)<.01)
  end)
  check("stack rounds draw their pieces from the round generator",function()
    local U=require("shared.util"); local seen={}
    for seed=1,12 do local g=T.new(seats,U.rng(seed*7919)); seen[g.players[1].kind..g.players[1].next..g.players[2].kind]=true end
    local n=0; for _ in pairs(seen) do n=n+1 end; assert(n>=6)
  end)
  check("restart from the start menu keeps players and applies settings",function()
    local M=require("games.coop")(T); local U=require("shared.util")
    local s=M.new({{slot=1,name="A",id="a"},{slot=2,name="B",id="b"}},U.rng(5))
    s.rows=3; assert(M.setting("target",20)); M.restart(s)
    assert(s.rows==0 and s.target==20 and s.restarted and s.players[2].id=="b")
    M.setting("target",12)
  end)
  check("bubble waves keep getting harder",function()
    local last=0
    for n=1,40 do
      local sizes,pace=B.layout(n); local cost=0
      for _,size in ipairs(sizes) do cost=cost+2^(size-1) end
      assert(cost>=last and pace>=1 and #sizes<=7); last=cost
    end
    local big=B.layout(8); assert(big[1]==4)
  end)
  check("CPU crews can clear rows and pop bubbles",function()
    local bots={{slot=1,bot=true},{slot=2,bot=true}}
    local rows,pops=0,0
    for seed=1,5 do
      local g=T.new(bots,seed*1723)
      for _=1,14400 do T.step(g,{},1/120); g.events={} end
      rows=rows+g.rows
    end
    local g=B.new(bots)
    for _=1,14400 do B.step(g,{},1/120); g.events={} end
    pops=g.popped
    print("CPU rows:",rows,"bubbles:",pops,"wave:",g.wave)
    assert(rows>=5 and pops>=8)
  end)
  print(n.." co-op checks passed")
end
