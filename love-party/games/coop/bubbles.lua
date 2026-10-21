local U=require("shared.util")
-- The arena is the whole screen: 800 units tall, as wide as the display aspect.
local B={id="bubble-buddies",title="BUBBLE BUDDIES",floor=748,ceiling=0,width=1280}
B.settings={
 {key="hearts",label="Team hearts (next round)",kind="number",default=6,min=2,max=12},
 {key="waves",label="Waves to clear (next round)",kind="number",default=5,min=1,max=10},
 {key="wave_seconds",label="Seconds per wave (next round)",kind="number",default=80,min=30,max=150},
 {key="powerups",label="Power-ups",kind="toggle",default=true}}
local radii={20,34,54}; local bounce={-500,-660,-810}; local speed={230,180,135}
local GRAVITY=780
-- Pickups: timed powers last this long; the rest act once.
B.kinds={"multi","ghost","rapid","speed","shield","freeze","dynamite","heart"}
B.duration={multi=10,ghost=8,rapid=10,speed=8}
local weights={multi=3,ghost=3,rapid=2,speed=2,shield=2,freeze=1.5,dynamite=1,heart=1}
local clamp=U.clamp
local function bubble(size,x,y,dir) return {size=size,x=x,y=y,r=radii[size],vx=dir*speed[size],vy=bounce[size]} end
local function event(g,name) g.events[#g.events+1]=name end
function B.wave(g,n)
  g.wave=n; g.bubbles={}; g.ropes={}; g.pickups={}; g.freeze=0
  g.clock=g.settings.wave_seconds; g.phase="ready"; g.timer=1.5
  local count=math.min(4,n+1)
  for i=1,count do
    g.bubbles[i]=bubble(n<3 and 2 or 3,g.width*i/(count+1),170+(i%2)*70,i%2==0 and 1 or -1)
  end
  for i,p in ipairs(g.players) do p.x=g.width*i/(#g.players+1); p.out=0; p.invuln=2; p.cooldown=0 end
end
function B.new(seats,rng,settings)
  settings=settings or {hearts=6,waves=5,wave_seconds=80,powerups=true}
  if type(rng)~="function" then rng=U.rng(tonumber(rng) or 1) end
  local g={players={},settings=settings,hearts=settings.hearts,phase="play",events={},time=0,popped=0,flash=0,
    width=B.width,floor=B.floor,ceiling=B.ceiling,rng=rng,bursts={}}
  for _,s in ipairs(seats) do
    g.players[#g.players+1]={slot=s.slot,name=s.name,avatar=s.avatar,bot=s.bot,power={},facing=1}
  end
  B.wave(g,1); return g
end
-- Keep world units uniform while using the actual display aspect ratio.
function B.resize(g,w,h)
  local width=800*w/math.max(1,h)
  if math.abs(width-g.width)<.01 then return end
  local ratio=width/g.width
  for _,list in ipairs({g.players,g.bubbles,g.ropes,g.pickups,g.bursts}) do
    for _,v in ipairs(list) do v.x=v.x*ratio end
  end
  g.width=width
end
function B.obstacles(g)
  local c=g.width/2
  if g.wave==2 or g.wave==4 then return {{x=c-130,y=g.floor-300,w=260,h=18}} end
  if g.wave>=3 then
    local s=math.sin(g.time*.5)*95
    return {{x=c-380+s,y=g.floor-266,w=180,h=18},{x=c+195-s,y=g.floor-316,w=180,h=18}}
  end
  return {}
end
function B.roll(g)
  local total=0
  for _,k in ipairs(B.kinds) do if k~="heart" or g.hearts<g.settings.hearts then total=total+weights[k] end end
  local pick=g.rng()*total
  for _,k in ipairs(B.kinds) do
    if k~="heart" or g.hearts<g.settings.hearts then
      pick=pick-weights[k]; if pick<=0 then return k end
    end
  end
  return "multi"
end
function B.bot(g,p)
  local best,score=0,-math.huge
  for _,move in ipairs({0,-1,1}) do
    local x=clamp(p.x+move*85,30,g.width-30)
    local risk=0; local nearest=1000
    for _,b in ipairs(g.bubbles) do
      local futureX=b.x+b.vx*.25
      local futureY=b.y+b.vy*.25+GRAVITY*.25*.25
      if futureY>g.floor-b.r then futureY=g.floor-b.r end
      local gap=math.abs(x-futureX)
      if futureY>g.floor-125 then risk=risk+math.max(0,b.r+76-gap)*5 end
      nearest=math.min(nearest,math.abs(x-b.x))
    end
    for _,k in ipairs(g.pickups) do nearest=math.min(nearest,math.abs(x-k.x)*.6) end
    local value=-risk-nearest*.10-math.abs(x-p.x)*.015
    if value>score then best,score=move,value end
  end
  return {move=best,fire=true}
end
local function fire(g,p)
  local active=0; for _,r in ipairs(g.ropes) do if r.slot==p.slot then active=active+1 end end
  local rapid=(p.power.rapid or 0)>0
  local lanes=(p.power.multi or 0)>0 and {-34,0,34} or {0}
  if active+#lanes>(rapid and 9 or #lanes) then return end
  local ghost=(p.power.ghost or 0)>0
  for _,dx in ipairs(lanes) do
    g.ropes[#g.ropes+1]={x=clamp(p.x+dx,4,g.width-4),y=g.floor-44,life=ghost and 3.2 or 1,slot=p.slot,ghost=ghost}
  end
  p.cooldown=rapid and .16 or .28; event(g,"fire")
end
local function pop(g,b,i)
  table.remove(g.bubbles,i)
  if b.size>1 then
    for _,dir in ipairs({-1,1}) do
      local c=bubble(b.size-1,b.x+dir*5,b.y,dir); c.immune=.35; g.bubbles[#g.bubbles+1]=c
    end
  end
  g.bursts[#g.bursts+1]={x=b.x,y=b.y,r=b.r,size=b.size,t=0}
  g.popped=g.popped+1; event(g,"pop")
  if g.settings.powerups~=false and g.rng()<.17 then
    g.pickups[#g.pickups+1]={kind=B.roll(g),x=b.x,y=b.y,vy=-180,life=8}
  end
end
local function collect(g,p,k)
  if B.duration[k.kind] then p.power[k.kind]=B.duration[k.kind]
  elseif k.kind=="shield" then p.shield=true
  elseif k.kind=="freeze" then g.freeze=3.5
  elseif k.kind=="heart" then g.hearts=math.min(g.settings.hearts,g.hearts+1)
  elseif k.kind=="dynamite" then
    -- Split every bubble down to the smallest size, Pang style.
    local done=false
    while not done do
      done=true
      for i=#g.bubbles,1,-1 do if g.bubbles[i].size>1 then pop(g,g.bubbles[i],i); done=false end end
    end
    g.flash=math.max(g.flash,.25)
  end
  g.bursts[#g.bursts+1]={x=p.x,y=g.floor-30,r=40,kind=k.kind,t=0}
  event(g,"pickup")
end
function B.step(g,inputs,dt)
  if g.phase=="won" or g.phase=="lost" then return end
  g.time=g.time+dt; g.flash=math.max(0,g.flash-dt)
  for i=#g.bursts,1,-1 do local f=g.bursts[i]; f.t=f.t+dt; if f.t>.6 then table.remove(g.bursts,i) end end
  if g.phase=="ready" or g.phase=="clear" then
    g.timer=g.timer-dt
    if g.timer<=0 then
      if g.phase=="clear" then
        if g.wave>=g.settings.waves then g.phase="won" else g.hearts=math.min(g.settings.hearts,g.hearts+1); B.wave(g,g.wave+1) end
      else g.phase="play" end
    end
    return
  end
  g.clock=g.clock-dt
  if g.clock<=0 then g.phase="lost"; g.reason="time"; return end
  for _,p in ipairs(g.players) do
    p.out=math.max(0,p.out-dt); p.invuln=math.max(0,p.invuln-dt); p.cooldown=math.max(0,p.cooldown-dt)
    for k,t in pairs(p.power) do p.power[k]=t>dt and t-dt or nil end
    if p.out<=0 then
      local a=p.bot and B.bot(g,p) or (inputs[p.slot] or {})
      local move=a.move or 0
      if move~=0 then p.facing=move end
      p.x=clamp(p.x+move*((p.power.speed or 0)>0 and 480 or 300)*dt,30,g.width-30)
      if a.fire and p.cooldown<=0 then fire(g,p) end
    end
  end
  for i=#g.ropes,1,-1 do
    local r=g.ropes[i]; r.y=math.max(g.ceiling,r.y-1100*dt); r.life=r.life-dt
    if r.life<=0 then table.remove(g.ropes,i) end
  end
  for i=#g.pickups,1,-1 do
    local k=g.pickups[i]
    k.vy=k.vy+900*dt; k.y=math.min(g.floor-18,k.y+k.vy*dt); k.life=k.life-dt
    local taken=false
    for _,p in ipairs(g.players) do
      if not taken and p.out<=0 and math.abs(k.x-p.x)<42 and k.y>g.floor-90 then collect(g,p,k); taken=true end
    end
    if taken or k.life<=0 then table.remove(g.pickups,i) end
  end
  g.freeze=math.max(0,g.freeze-dt)
  local blocks=B.obstacles(g)
  for _,b in ipairs(g.bubbles) do
    b.immune=b.immune and b.immune>dt and b.immune-dt or nil
    if g.freeze<=0 then
      local oldBottom=b.y+b.r
      b.vy=b.vy+GRAVITY*dt; b.x=b.x+b.vx*dt; b.y=b.y+b.vy*dt
      if b.x-b.r<0 then b.x=b.r; b.vx=math.abs(b.vx) end
      if b.x+b.r>g.width then b.x=g.width-b.r; b.vx=-math.abs(b.vx) end
      if b.y-b.r<g.ceiling then b.y=g.ceiling+b.r; b.vy=math.abs(b.vy) end
      if b.y+b.r>=g.floor then b.y=g.floor-b.r; b.vy=bounce[b.size] end
      for _,r in ipairs(blocks) do
        if b.vy>0 and oldBottom<=r.y and b.y+b.r>=r.y and b.x>r.x-b.r*.5 and b.x<r.x+r.w+b.r*.5 then b.y=r.y-b.r; b.vy=bounce[b.size] end
      end
    end
  end
  for i=#g.bubbles,1,-1 do
    local b=g.bubbles[i]; local popped=false
    for j=#g.ropes,1,-1 do
      local r=g.ropes[j]
      if not b.immune and math.abs(b.x-r.x)<b.r+4 and b.y+b.r>=r.y then
        -- A ghost rope stays up and keeps popping until it fades.
        if not r.ghost then table.remove(g.ropes,j) end
        pop(g,b,i); popped=true; break
      end
    end
    if not popped then for _,p in ipairs(g.players) do
      if p.out<=0 and p.invuln<=0 and (b.x-p.x)^2+(b.y-(g.floor-27))^2<(b.r+25)^2 then
        if p.shield then
          p.shield=false; p.invuln=1.5; event(g,"hit")
        else
          g.hearts=g.hearts-1; p.out=1.2; p.invuln=3; p.power={}; g.flash=.3; event(g,"hurt")
          if g.hearts<=0 then g.phase="lost"; g.reason="hearts"; return end
        end
      end
    end end
  end
  if #g.bubbles==0 then g.phase="clear"; g.timer=1.5; g.pickups={}; event(g,"clear") end
end
function B.render(g,overlay) require("games.coop.bubbles_view").render(g,overlay) end
return B
