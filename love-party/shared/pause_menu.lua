-- Start opens a pause menu in the house style: the game title, Resume,
-- Restart (which applies the settings below it), then every setting the game
-- exposes to the GameNight host. No button hints.
return function(M)
    local function rows()
        local out = { { label = "Resume" }, { label = "Restart", restart = true } }
        for _, spec in ipairs(M.settings) do
            out[#out + 1] = { label = spec.label:gsub(" %(.*", ""), spec = spec }
        end
        return out
    end
    local function step(spec, value, delta)
        if spec.kind == "toggle" then return not value end
        if spec.kind == "number" then
            local stride = spec.step or 1
            return math.max(spec.min, math.min(spec.max, value + delta * stride))
        end
        for i, v in ipairs(spec.options) do
            if v == value then return spec.options[(i - 1 + delta) % #spec.options + 1] end
        end
        return value
    end
    function M.menuUpdate(s, dt, input, change)
        local before = s.menuInput or {}
        s.menuInput = input
        local function pressed(k) return input[k] and not before[k] end
        if pressed("start") then
            s.paused = not s.paused
            s.menuRow = 1
            return true
        end
        if not s.paused then return false end
        if pressed("cancel") then s.paused = false; return true end
        local list = rows()
        if pressed("down") then s.menuRow = s.menuRow % #list + 1 end
        if pressed("up") then s.menuRow = (s.menuRow - 2) % #list + 1 end
        local row = list[s.menuRow]
        if row.spec and (pressed("left") or pressed("right") or pressed("accept")) then
            change(row.spec.key, step(row.spec, M.preferences()[row.spec.key], pressed("left") and -1 or 1))
        elseif pressed("accept") then
            s.paused = false
            if row.restart then M.restart(s) end
        end
        return true
    end
    function M.menuDraw(s, g, fonts)
        if not s.paused then return end
        local w = s.width or 1280
        local list = rows()
        local height = 150 + #list * 46
        local x, y = w / 2 - 300, 400 - height / 2
        g.setColor(0.01, 0.015, 0.035, 0.85)
        g.rectangle("fill", 0, 0, w, 800)
        g.setColor(0.06, 0.09, 0.16)
        g.rectangle("fill", x, y, 600, height, 18, 18)
        g.setFont(fonts.title)
        g.setColor(0.3, 0.92, 0.83)
        g.printf(M.title, x, y + 28, 600, "center")
        g.setFont(fonts.small)
        g.setColor(0.55, 0.65, 0.75)
        g.printf("Changes start with Restart or the next round", x, y + 72, 600, "center")
        local preferences = M.preferences()
        for i, row in ipairs(list) do
            local ry = y + 110 + (i - 1) * 46
            if i == s.menuRow then
                g.setColor(0.16, 0.26, 0.4)
                g.rectangle("fill", x + 20, ry - 7, 560, 40, 8, 8)
            end
            g.setFont(fonts.body)
            g.setColor(1, 1, 1)
            g.print(row.label, x + 40, ry)
            if row.spec then
                local value = preferences[row.spec.key]
                if type(value) == "boolean" then value = value and "On" or "Off" end
                if row.spec.suffix then value = tostring(value) .. row.spec.suffix end
                g.setColor(0.6, 0.9, 1)
                g.printf("‹  " .. tostring(value):upper() .. "  ›", x + 300, ry, 260, "right")
            end
        end
    end
end
