-- Full-screen Stack Together renderer. No words: faces, next-piece previews
-- and a row meter on both sides of the well carry everything.
local Face=require("shared.face")
local T=require("games.coop.stack")
local V={}
local C={sky1={.045,.06,.13},sky2={.11,.07,.19},well={.03,.04,.08},ink={.95,.96,.9},mint={.36,.9,.73},gold={1,.81,.4},coral={.97,.44,.49}}
local blocks={{.34,.79,.91},{1,.81,.4},{.72,.50,.91},{.37,.86,.66},{.97,.44,.49},{.40,.56,.96},{1,.62,.33}}
local slots={{1,.58,.36},{.36,.9,.73}}
local CELL=40
local G
local function color(c,a) G.setColor(c[1],c[2],c[3],a or 1) end
local function hex(p)
  if p.color and p.color:match("^#%x%x%x%x%x%x$") then
    return {tonumber(p.color:sub(2,3),16)/255,tonumber(p.color:sub(4,5),16)/255,tonumber(p.color:sub(6,7),16)/255}
  end
  return slots[(p.slot-1)%2+1]
end
local function cell(kind,x,y,a,size)
  size=size or CELL; local c=blocks[kind]; a=a or 1
  color(c,a); G.rectangle("fill",x+1,y+1,size-2,size-2,size*.16)
  if a>.5 then
    color(C.ink,.28*a); G.rectangle("fill",x+size*.14,y+size*.12,size*.72,size*.14,size*.07)
    G.setColor(0,0,0,.18*a); G.rectangle("fill",x+size*.1,y+size*.76,size*.8,size*.12,size*.06)
  end
end
local function star(x,y,r,c,a)
  local pts={}
  for i=0,9 do local ang=-math.pi/2+i*math.pi/5; local rr=i%2==0 and r or r*.45; pts[#pts+1]=x+math.cos(ang)*rr; pts[#pts+1]=y+math.sin(ang)*rr end
  color(c,a); G.polygon("fill",pts)
end
local function background(g,w)
  for i=0,15 do
    local t=i/15; G.setColor(C.sky1[1]+(C.sky2[1]-C.sky1[1])*t,C.sky1[2]+(C.sky2[2]-C.sky1[2])*t,C.sky1[3]+(C.sky2[3]-C.sky1[3])*t)
    G.rectangle("fill",0,i*50,w,51)
  end
  -- Slowly falling ghost blocks in the background.
  for i=1,18 do
    local x=(i*263)%w; local y=((i*151)+g.time*(10+i%4*6))%900-60
    G.push(); G.translate(x,y); G.rotate(i+g.time*.05*(i%2==0 and 1 or -1))
    color(blocks[i%7+1],.05); G.rectangle("fill",-26,-26,52,52,9); G.pop()
  end
end
function V.draw(g)
  G=love.graphics
  local w=g.width or 1280
  local bw,bh=T.width*CELL,T.height*CELL
  local ox,oy=math.floor(w/2-bw/2),40
  background(g,w)
  -- Each half of the well is tinted with its owner's colour.
  color(C.well,.92); G.rectangle("fill",ox-10,oy-10,bw+20,bh+20,16)
  for i,p in ipairs(g.players) do color(hex(p),.05); G.rectangle("fill",ox+(p.lane-1)*CELL,oy,6*CELL,bh) end
  for y=1,T.height do for x=1,T.width do
    color(C.ink,.035); G.circle("fill",ox+(x-.5)*CELL,oy+(y-.5)*CELL,2)
    if g.board[y][x] then cell(g.board[y][x],ox+(x-1)*CELL,oy+(y-1)*CELL) end
  end end
  color(C.ink,.12); G.rectangle("fill",ox+bw/2-1,oy,2,bh)
  for _,p in ipairs(g.players) do
    local ghost=g.phase=="play" and T.dropY(g,p,p.x,p.rot)
    if ghost then for _,v in ipairs(T.cells(p.kind,p.rot)) do
      local x,y=ox+(p.x+v[1]-1)*CELL,oy+(ghost+v[2]-1)*CELL
      color(blocks[p.kind],.35); G.setLineWidth(2); G.rectangle("line",x+3,y+3,CELL-6,CELL-6,6)
    end end
    for _,v in ipairs(T.cells(p.kind,p.rot)) do
      local y=p.y+v[2]
      if y>=1 and y<=T.height then cell(p.kind,ox+(p.x+v[1]-1)*CELL,oy+(y-1)*CELL) end
    end
  end
  if g.flash>0 then color(C.mint,g.flash*.35); G.rectangle("fill",ox-10,oy-10,bw+20,bh+20,16) end
  -- Shared row meter on both outer edges of the well.
  local done=math.min(1,g.rows/math.max(1,g.target))
  for _,mx in ipairs({ox-30,ox+bw+20}) do
    color(C.ink,.08); G.rectangle("fill",mx,oy,10,bh,5)
    color(C.mint,.9); G.rectangle("fill",mx,oy+bh*(1-done),10,bh*done,5)
    for i=1,g.target-1 do color(C.well,.8); G.rectangle("fill",mx,oy+bh*i/g.target-1,10,2) end
  end
  -- Players: big face beside their half, next piece below it.
  for i,p in ipairs(g.players) do
    local side=p.lane==1 and -1 or 1
    local cx=side<0 and (ox-40)/2 or (ox+bw+40+w)/2
    local c=hex(p)
    color(c,.14); G.circle("fill",cx,250,92)
    Face.drawFace(p,cx,250,64,{outline=p.color or string.format("#%02x%02x%02x",c[1]*255,c[2]*255,c[3]*255),facing=-side})
    color(c,.1); G.rectangle("fill",cx-90,420,180,150,18)
    local cells=T.cells(p.next,0); local mw,mh=0,0
    for _,v in ipairs(cells) do mw=math.max(mw,v[1]+1); mh=math.max(mh,v[2]+1) end
    for _,v in ipairs(cells) do cell(p.next,cx-mw*17+v[1]*34,495-mh*17+v[2]*34,1,34) end
  end
  if g.phase=="won" then
    color(C.sky1,.55); G.rectangle("fill",0,0,w,800)
    for i=1,70 do
      local ang=i*2.4; local d=(g.time*90+i*23)%460
      local s=8+(i%4)*3; cell(i%7+1,w/2+math.cos(ang)*d-s/2,400+math.sin(ang)*d*.7-s/2,1-d/460,s*2)
    end
    star(w/2,380,95,C.gold,.95)
  elseif g.phase=="lost" then
    G.setColor(.2,.02,.05,.55); G.rectangle("fill",0,0,w,800)
    for i=0,3 do cell(i%7+1,w/2-80+i*40,380+math.sin(i*1.7)*14,.5,40) end
    G.setLineWidth(8); color(C.coral,.9); G.line(w/2-110,330,w/2+110,450); G.line(w/2+110,330,w/2-110,450)
  end
end
function V.render(g,overlay)
  G=love.graphics
  local w,h=G.getDimensions(); local width=g.width or 1280; local scale=math.min(w/width,h/800)
  G.clear(C.sky1[1],C.sky1[2],C.sky1[3]); G.push()
  G.translate((w-width*scale)/2,(h-800*scale)/2); G.scale(scale)
  V.draw(g); if overlay then overlay(G) end; G.pop()
end
return V
