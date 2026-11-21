-- Retro display: everything is drawn on a 320x240 canvas, then scaled by an
-- integer factor (nearest neighbour) and centred. Optional scanlines shader.
local R = { W = 320, H = 240, scale = 1, ox = 0, oy = 0, scanlines = true }

local SHADER = [[
extern number scale;
extern number oy;
extern number strength;
vec4 effect(vec4 col, Image tex, vec2 uv, vec2 sc) {
    vec4 p = Texel(tex, uv);
    float row = mod(floor(sc.y - oy), scale);
    float dark = step(scale - max(1.0, floor(scale / 2.0)), row);
    return vec4(p.rgb * (1.0 - strength * dark), 1.0) * col;
}
]]

function R.init()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
    R.canvas = love.graphics.newCanvas(R.W, R.H)
    R.shader = love.graphics.newShader(SHADER)
    R.resize(love.graphics.getDimensions())
end

function R.resize(w, h)
    R.scale = math.max(1, math.floor(math.min(w / R.W, h / R.H)))
    R.ox = math.floor((w - R.W * R.scale) / 2)
    R.oy = math.floor((h - R.H * R.scale) / 2)
end

function R.begin()
    love.graphics.setCanvas(R.canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
end

function R.finish()
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    if R.scanlines and R.scale >= 2 then
        R.shader:send("scale", R.scale)
        R.shader:send("oy", R.oy)
        R.shader:send("strength", 0.35)
        love.graphics.setShader(R.shader)
    end
    love.graphics.draw(R.canvas, R.ox, R.oy, 0, R.scale, R.scale)
    love.graphics.setShader()
end

return R
