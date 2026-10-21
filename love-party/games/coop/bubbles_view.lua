-- Full-screen Bubble Buddies renderer. No words on screen: hearts, wave dots,
-- a time bar along the top and drawn power-up icons carry all information.
local Face=require("shared.face")
local B=require("games.coop.bubbles")
local V={}
local C={sky1={.05,.08,.16},sky2={.10,.07,.20},ink={.95,.96,.9},dim={.48,.56,.66},mint={.36,.9,.73},
  orange={1,.58,.36},gold={1,.81,.4},coral={.97,.44,.49},ice={.6,.88,1},violet={.72,.5,.91},ground={.07,.10,.17}}
local sizes={{.37,.86,.66},{.34,.79,.91},{.72,.50,.91}}
local slots={{1,.58,.36},{.36,.9,.73},{1,.81,.4},{.61,.53,1}}
local icon={multi=C.gold,ghost=C.ice,rapid=C.orange,speed=C.mint,shield={.45,.7,1},freeze=C.ice,dynamite=C.coral,heart=C.coral}
local G
local function color(c,a) G.setColor(c[1],c[2],c[3],a or 1) end
local function hex(p)
  if p.color and p.color:match("^#%x%x%x%x%x%x$") then
    return {tonumber(p.color:sub(2,3),16)/255,tonumber(p.color:sub(4,5),16)/255,tonumber(p.color:sub(6,7),16)/255}
  end
  return slots[(p.slot-1)%4+1]
end
local function heart(x,y,s,c,a)
  color(c,a)
  G.circle("fill",x-s*.5,y-s*.2,s*.55); G.circle("fill",x+s*.5,y-s*.2,s*.55)
  G.polygon("fill",x-s*1.04,y,x+s*1.04,y,x,y+s*1.15)
end
local function star(x,y,r,c,a)
  local pts={}
  for i=0,9 do local ang=-math.pi/2+i*math.pi/5; local rr=i%2==0 and r or r*.45; pts[#pts+1]=x+math.cos(ang)*rr; pts[#pts+1]=y+math.sin(ang)*rr end
  color(c,a); G.polygon("fill",pts)
end
-- One small glyph per power, drawn inside a pickup bubble or above a player.
function V.glyph(kind,x,y,s,a)
  local c=icon[kind]; G.setLineWidth(math.max(2,s*.16))
  if kind=="multi" then
    for i=-1,1 do color(c,a); G.rectangle("fill",x+i*s*.42-s*.07,y-s*.55,s*.14,s*1.1); G.polygon("fill",x+i*s*.42,y-s*.8,x+i*s*.42-s*.17,y-s*.5,x+i*s*.42+s*.17,y-s*.5) end
  elseif kind=="ghost" then
    color(c,a*.35); G.rectangle("fill",x-s*.2,y-s*.8,s*.4,s*1.5,s*.15)
    color(c,a); G.rectangle("line",x-s*.2,y-s*.8,s*.4,s*1.5,s*.15)
  elseif kind=="rapid" then
    color(c,a); for i=0,2 do local yy=y-s*.6+i*s*.45; G.polygon("fill",x-s*.55,yy+s*.35,x,yy,x+s*.55,yy+s*.35) end
  elseif kind=="speed" then
    color(c,a); for i=0,1 do local xx=x-s*.45+i*s*.5; G.polygon("fill",xx,y-s*.6,xx+s*.5,y,xx,y+s*.6) end
  elseif kind=="shield" then
    color(c,a); G.polygon("fill",x-s*.6,y-s*.6,x+s*.6,y-s*.6,x+s*.55,y+s*.05,x,y+s*.75,x-s*.55,y+s*.05)
    color(C.ink,a*.5); G.polygon("fill",x-s*.35,y-s*.42,x,y-s*.42,x,y+s*.45,x-s*.32,y)
  elseif kind=="freeze" then
    color(c,a); for i=0,2 do local ang=i*math.pi/3; G.line(x-math.cos(ang)*s*.75,y-math.sin(ang)*s*.75,x+math.cos(ang)*s*.75,y+math.sin(ang)*s*.75) end
  elseif kind=="dynamite" then
    color(c,a); G.rectangle("fill",x-s*.3,y-s*.4,s*.6,s*1.05,s*.1)
    color(C.gold,a); G.line(x,y-s*.4,x+s*.25,y-s*.75); star(x+s*.3,y-s*.8,s*.25,C.gold,a)
  elseif kind=="heart" then heart(x,y-s*.15,s*.6,c,a) end
end
local function background(g,w)
  local h=800
  -- Vertical gradient in a few bands, then soft drifting blobs.
  for i=0,15 do
    local t=i/15; G.setColor(C.sky1[1]+(C.sky2[1]-C.sky1[1])*t,C.sky1[2]+(C.sky2[2]-C.sky1[2])*t,C.sky1[3]+(C.sky2[3]-C.sky1[3])*t)
    G.rectangle("fill",0,i*h/16,w,h/16+1)
  end
  for i=1,14 do
    local x=(i*397+g.time*(8+i%5*3))%(w+200)-100; local y=60+(i*173)%560
    color(sizes[i%3+1],.03); G.circle("fill",x,y,60+(i*37)%90)
  end
  for i=1,40 do
    local x=(i*211)%w; local y=(i*97)%(g.floor-40)
    color(C.ink,.06+.05*math.sin(g.time*1.3+i)); G.circle("fill",x,y,1.6)
  end
end
local function hud(g,w)
  -- Time bar along the very top edge.
  local t=math.max(0,g.clock/g.settings.wave_seconds)
  color(C.ink,.08); G.rectangle("fill",0,0,w,6)
  color(t<.2 and C.coral or C.mint,.85); G.rectangle("fill",0,0,w*t,6)
  for i=1,g.settings.hearts do heart(34+(i-1)*34,38,11,i<=g.hearts and C.coral or C.ink,i<=g.hearts and .95 or .14) end
  for i=1,g.settings.waves do
    local x=w-30-(g.settings.waves-i)*24
    color(C.gold,i<g.wave and .95 or i==g.wave and .95 or .16)
    if i==g.wave then G.setLineWidth(3); G.circle("line",x,36,8) else G.circle("fill",x,36,7) end
  end
end
local function bubble(b,frozen)
  local c=frozen and C.ice or sizes[b.size]
  color(c,.2); G.circle("fill",b.x,b.y,b.r)
  color(c,.12); G.circle("fill",b.x,b.y,b.r*.72)
  G.setLineWidth(3); color(c,.95); G.circle("line",b.x,b.y,b.r)
  color(C.ink,.7); G.circle("fill",b.x-b.r*.32,b.y-b.r*.36,b.r*.16)
  color(C.ink,.35); G.circle("fill",b.x-b.r*.08,b.y-b.r*.52,b.r*.07)
end
local function rope(g,r)
  local c=r.ghost and C.ice or C.gold
  local a=r.ghost and (.75+.25*math.sin(g.time*14+r.x)) * math.min(1,r.life*2) or 1
  if r.ghost then color(c,a*.18); G.rectangle("fill",r.x-12,r.y,24,g.floor-r.y,10); color(c,a*.3); G.rectangle("fill",r.x-6,r.y,12,g.floor-r.y,6) end
  color(c,a); G.rectangle("fill",r.x-2,r.y,4,g.floor-r.y,2)
  G.polygon("fill",r.x,r.y-10,r.x-9,r.y+5,r.x+9,r.y+5)
end
local function player(g,p)
  local x,y=p.x,g.floor-27; local c=hex(p)
  if p.out>0 then
    -- Knocked out: a faded face with a ring that fills until they are back.
    color(c,.25); G.circle("fill",x,y,27)
    G.setLineWidth(4); color(c,.9); G.arc("line","open",x,y,33,-math.pi/2,-math.pi/2+math.pi*2*(1-p.out/1.2))
    return
  end
  local blink=p.invuln>0 and math.floor(g.time*10)%2==1
  color(C.ground,.6); G.ellipse("fill",x,g.floor+3,26,6)
  if p.shield then color(icon.shield,.25+.1*math.sin(g.time*6)); G.circle("fill",x,y,40); G.setLineWidth(2); color(icon.shield,.8); G.circle("line",x,y,40) end
  if (p.power.speed or 0)>0 then for i=1,3 do color(C.mint,.25/i); G.circle("fill",x-p.facing*i*12,y,26) end end
  Face.drawFace(p,x,y,27,{outline=p.color or string.format("#%02x%02x%02x",c[1]*255,c[2]*255,c[3]*255),facing=p.facing,alpha=blink and .35 or 1})
  -- Active timed powers float above the head with a shrinking bar.
  local list={}; for _,k in ipairs(B.kinds) do if p.power[k] then list[#list+1]=k end end
  for i,k in ipairs(list) do
    local ix=x+(i-(#list+1)/2)*30; local left=p.power[k]/B.duration[k]
    local a=left<.25 and (math.floor(g.time*8)%2==0 and .4 or 1) or 1
    V.glyph(k,ix,y-56,11,a)
    color(icon[k],.85); G.rectangle("fill",ix-11,y-40,22*left,3)
  end
end
function V.draw(g)
  G=love.graphics
  local w=g.width
  background(g,w)
  local frozen=g.freeze>0
  for _,r in ipairs(B.obstacles(g)) do
    color(C.gold,.18); G.rectangle("fill",r.x-4,r.y-4,r.w+8,r.h+8,9)
    color(C.gold); G.rectangle("fill",r.x,r.y,r.w,r.h,6)
  end
  color(C.ground); G.rectangle("fill",0,g.floor,w,800-g.floor)
  color(C.mint,.85); G.rectangle("fill",0,g.floor,w,4)
  for _,r in ipairs(g.ropes) do rope(g,r) end
  for _,f in ipairs(g.bursts) do
    local t=f.t/.6
    if f.kind then color(icon[f.kind],1-t); G.setLineWidth(3); G.circle("line",f.x,f.y,f.r*(1+t*1.5))
    else
      local c=sizes[f.size]
      for i=0,7 do local ang=i*math.pi/4+f.size; local d=f.r*(.6+t*1.4); color(c,1-t); G.circle("fill",f.x+math.cos(ang)*d,f.y+math.sin(ang)*d,4*(1-t)+1) end
      G.setLineWidth(2); color(c,(1-t)*.6); G.circle("line",f.x,f.y,f.r*(1+t*.6))
    end
  end
  for _,b in ipairs(g.bubbles) do bubble(b,frozen) end
  if frozen then color(C.ice,.06+.04*math.sin(g.time*5)); G.rectangle("fill",0,0,w,g.floor) end
  for _,k in ipairs(g.pickups) do
    if k.life>1.5 or math.floor(g.time*10)%2==0 then
      local bob=math.sin(g.time*5+k.x)*3
      color(icon[k.kind],.18); G.circle("fill",k.x,k.y+bob,18)
      G.setLineWidth(2); color(icon[k.kind],.9); G.circle("line",k.x,k.y+bob,18)
      V.glyph(k.kind,k.x,k.y+bob,12,1)
    end
  end
  for _,p in ipairs(g.players) do player(g,p) end
  hud(g,w)
  if g.phase=="ready" then
    -- Wave intro: the wave dot pulses in the middle of the screen.
    local t=1-g.timer/1.5
    for i=1,g.wave do color(C.gold,math.sin(t*math.pi)*.9); G.circle("fill",w/2+(i-(g.wave+1)/2)*40,330,12) end
  elseif g.phase=="clear" then
    local t=1-g.timer/1.5
    heart(w/2,330-t*40,26+t*12,C.coral,math.sin(t*math.pi))
  elseif g.phase=="won" then
    color(C.sky1,.55); G.rectangle("fill",0,0,w,800)
    for i=1,60 do
      local ang=i*2.4; local d=(g.time*90+i*23)%420
      star(w/2+math.cos(ang)*d,380+math.sin(ang)*d*.7,6+(i%4)*3,sizes[i%3+1],1-d/420)
    end
    star(w/2,370,90,C.gold,.95)
  elseif g.phase=="lost" then
    color({.2,.02,.05},.55); G.rectangle("fill",0,0,w,800)
    heart(w/2,360,70,C.coral,.35); G.setLineWidth(8); color(C.sky1,.9)
    G.line(w/2-10,300,w/2+14,340,w/2-12,375,w/2+8,420)
  end
  if g.flash>0 then color(C.coral,g.flash*.45); G.rectangle("fill",0,0,w,800) end
end
function V.render(g,overlay)
  G=love.graphics
  local w,h=G.getDimensions(); local scale=math.min(w/g.width,h/800)
  G.clear(C.sky1[1],C.sky1[2],C.sky1[3]); G.push()
  G.translate((w-g.width*scale)/2,(h-800*scale)/2); G.scale(scale)
  V.draw(g); if overlay then overlay(G) end; G.pop()
end
return V
