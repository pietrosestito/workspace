-- Unified buttons: left right up down a b start select.
-- Sources: keyboard, gamepads (R36S, Android pads), plain joysticks, touch overlay.
local R = require("lib.retro")
local I = { cur = {}, prev = {}, touchMode = false, script = nil }
local BUTTONS = { "left", "right", "up", "down", "a", "b", "x", "y", "start", "select" }

local KEYS = {
    left = { "left" }, right = { "right" }, up = { "up" }, down = { "down" },
    a = { "z", "space" }, b = { "x" }, x = { "s" }, y = { "a" },
    start = { "return", "escape" }, select = { "tab", "rshift" },
}
local PAD = {
    left = { "dpleft" }, right = { "dpright" }, up = { "dpup" }, down = { "dpdown" },
    a = { "a" }, b = { "b" }, x = { "x" }, y = { "y" }, start = { "start" }, select = { "back" },
}

-- touch zones in screen coordinates (recomputed every frame: screens rotate)
local function zones()
    local w, h = love.graphics.getDimensions()
    local s = math.min(w, h) / 6
    return {
        left = { s * 0.9, h - s * 1.1, s * 0.75 },
        right = { s * 2.6, h - s * 1.1, s * 0.75 },
        a = { w - s * 0.8, h - s * 1.7, s * 0.6 },          -- SNES-style diamond
        b = { w - s * 1.8, h - s * 0.8, s * 0.6 },
        x = { w - s * 1.8, h - s * 2.6, s * 0.6 },
        y = { w - s * 2.8, h - s * 1.7, s * 0.6 },
        start = { w - s * 0.6, s * 0.5, s * 0.4 },
    }
end

local function pollTouch(st)
    local touches = love.touch.getTouches()
    if #touches > 0 then I.touchMode = true end
    if not I.touchMode then return end
    local z = zones()
    for _, id in ipairs(touches) do
        local tx, ty = love.touch.getPosition(id)
        for name, c in pairs(z) do
            if (tx - c[1]) ^ 2 + (ty - c[2]) ^ 2 <= (c[3] * 1.25) ^ 2 then st[name] = true end
        end
    end
end

function I.update()
    I.prev = I.cur
    local st = {}
    if I.script then
        st = I.script() or {}
    else
        for _, b in ipairs(BUTTONS) do
            for _, k in ipairs(KEYS[b]) do
                if love.keyboard.isDown(k) then st[b] = true; I.touchMode = false end
            end
        end
        for _, j in ipairs(love.joystick.getJoysticks()) do
            if j:isGamepad() then
                for _, b in ipairs(BUTTONS) do
                    for _, k in ipairs(PAD[b]) do
                        if j:isGamepadDown(k) then st[b] = true end
                    end
                end
                local ax, ay = j:getGamepadAxis("leftx"), j:getGamepadAxis("lefty")
                if ax < -0.5 then st.left = true elseif ax > 0.5 then st.right = true end
                if ay < -0.5 then st.up = true elseif ay > 0.5 then st.down = true end
            else                                   -- unmapped stick: hat + first buttons
                local hat = j:getHatCount() > 0 and j:getHat(1) or "c"
                if hat:find("l") then st.left = true end
                if hat:find("r") then st.right = true end
                if hat:find("u") then st.up = true end
                if hat:find("d") then st.down = true end
                if j:getAxisCount() >= 2 then
                    if j:getAxis(1) < -0.5 then st.left = true elseif j:getAxis(1) > 0.5 then st.right = true end
                end
                if j:isDown(1) then st.a = true end
                if j:getButtonCount() >= 2 and j:isDown(2) then st.b = true end
                if j:getButtonCount() >= 4 then
                    if j:isDown(3) then st.x = true end
                    if j:isDown(4) then st.y = true end
                end
            end
        end
        if next(st) then I.touchMode = false end
        pollTouch(st)
    end
    I.cur = st
end

function I.down(b) return I.cur[b] == true end
function I.pressed(b) return I.cur[b] == true and not I.prev[b] end

-- drawn in screen space, after the retro canvas, only when touch is in use
function I.drawTouch()
    if not I.touchMode then return end
    local labels = { a = "A", b = "B", x = "X", y = "Y", start = "II" }
    local s = R.scale
    for name, c in pairs(zones()) do
        love.graphics.setColor(1, 1, 1, I.cur[name] and 0.45 or 0.2)
        love.graphics.circle("fill", c[1], c[2], c[3])
        love.graphics.setColor(1, 1, 1, 0.8)
        local x, y, r = c[1], c[2], c[3] * 0.4
        if name == "left" then love.graphics.polygon("fill", x - r, y, x + r, y - r, x + r, y + r)
        elseif name == "right" then love.graphics.polygon("fill", x + r, y, x - r, y - r, x - r, y + r)
        else love.graphics.print(labels[name], x - #labels[name] * 3 * s, y - 4 * s, 0, s, s) end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return I
