-- Same validated settings as the companion app; applied at the next arena.
return function(B)
    local function rows()
        local out={{label="Resume"}}
        for _,spec in ipairs(B.settings) do out[#out+1]={label=spec.label:gsub(" %(.*", ""),spec=spec} end
        out[#out+1]={label="Start new round",restart=true}
        return out
    end
    function B.menuUpdate(s,dt,input,change)
        local before=s.menuInput or {}
        s.menuInput=input
        local function pressed(k) return input[k] and not before[k] end
        if pressed("start") then s.paused=not s.paused; s.menuRow=s.menuRow or 1; return true end
        if not s.paused then return false end
        -- Do not turn the A press that closes this menu into a planted bomb.
        for _,p in ipairs(s.players) do p.actionHeld,p.secondaryHeld=true,true end
        if pressed("cancel") then s.paused=false; return true end
        local list=rows()
        if pressed("down") then s.menuRow=(s.menuRow or 1)%#list+1 end
        if pressed("up") then s.menuRow=((s.menuRow or 1)-2)%#list+1 end
        local row=list[s.menuRow or 1]
        if row.spec and (pressed("left") or pressed("right") or pressed("accept")) then
            local spec=row.spec
            local value=B.preferences()[spec.key]
            local delta=pressed("left") and -1 or 1
            if spec.kind=="toggle" then value=not value
            elseif spec.kind=="number" then value=math.max(spec.min,math.min(spec.max,value+delta*((spec.key=="crates" or spec.key=="pickups") and 5 or 1)))
            else
                for i,v in ipairs(spec.options) do
                    if v==value then value=spec.options[(i-1+delta)%#spec.options+1]; break end
                end
            end
            change(spec.key,value)
        elseif pressed("accept") then
            if row.restart then B.restart(s) end
            s.paused=false
            for _,p in ipairs(s.players) do p.actionHeld,p.secondaryHeld=true,true end
        end
        return true
    end
    function B.menuDraw(s,g,fonts)
        if not s.paused then return end
        g.setColor(.015,.02,.04,.88);g.rectangle("fill",0,0,1280,800)
        g.setColor(.09,.13,.21);g.rectangle("fill",330,75,620,650,20,20)
        g.setFont(fonts.title);g.setColor(1,.85,.45);g.printf("BLAST PARTY · PAUSED",350,95,580,"center")
        g.setFont(fonts.small);g.setColor(.75,.82,.91)
        g.printf("Settings apply next round. Start new round to use them now.",350,140,580,"center")
        local preferences=B.preferences()
        for i,row in ipairs(rows()) do
            local y=180+(i-1)*44
            if i==(s.menuRow or 1) then
                g.setColor(.24,.32,.49);g.rectangle("fill",350,y-5,580,39,8,8)
            end
            g.setFont(fonts.body);g.setColor(1,1,1);g.print(row.label,368,y)
            if row.spec then
                local value=preferences[row.spec.key]
                if type(value)=="boolean" then value=value and "On" or "Off" end
                g.setColor(.6,.9,1);g.printf("< "..tostring(value).." >",645,y,265,"right")
            end
        end
        g.setFont(fonts.small);g.setColor(.75,.82,.91)
        g.printf("AI fill empty places only · 4 players maximum",350,644,580,"center")
        g.printf("Stick / D-pad: choose & change     A: select     B / Start: resume",350,680,580,"center")
    end
end
