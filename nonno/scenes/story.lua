-- Story scene: big portrait + typewriter text, then the portrait shrinks
-- (nearest-neighbour zoom, like the arcade boards did) down to the gameplay sprite.
local T = require("lib.text")
local I = require("lib.input")
local S = {}

local PAGES = {
    "Estate. Il torneo di beach volley è finito.",
    "Ma nella notte il Toro ha rubato la Coppa!",
    "Il Nonno si alza dalla sdraio...",
    "\"Andiamo a riprendercela.\"",
}
local SHRINK = 70       -- frames
local FLASH = 8
local P0 = { x = 14, y = 240 - 30 - 188 }   -- portrait top-left at 2x (bottom on the sand)
local P1 = { x = 52, y = 208 - 47 }         -- where the level's player stands, at 0.5x

function S.enter()
    S.page, S.chars, S.t, S.phase = 1, 0, 0, "text"
end

local function finishText() return S.chars >= #T.clean(PAGES[S.page]) end

function S.update()
    S.t = S.t + 1
    if I.pressed("start") then G.switch("level") return end
    if S.phase == "text" then
        if S.t % 2 == 0 and not finishText() then S.chars = S.chars + 1 end
        if I.pressed("a") then
            if not finishText() then S.chars = #T.clean(PAGES[S.page])
            elseif S.page < #PAGES then S.page, S.chars = S.page + 1, 0
            else S.phase, S.t = "shrink", 0 end
        end
    elseif S.phase == "shrink" and S.t >= SHRINK + FLASH then
        G.switch("level")
    end
end

local function ground()
    love.graphics.draw(G.img.bg_sky, 0, 0)
    love.graphics.draw(G.img.bg_sea, 0, 110)
    love.graphics.draw(G.img.bg_palms, 0, 88)
    local tiles = G.img.tiles
    S.q = S.q or { love.graphics.newQuad(0, 0, 16, 16, tiles), love.graphics.newQuad(16, 0, 16, 16, tiles) }
    for x = 0, 19 do
        love.graphics.draw(tiles, S.q[1], x * 16, 208)
        love.graphics.draw(tiles, S.q[2], x * 16, 224)
    end
end

function S.draw()
    ground()
    local img = G.img.nonno_portrait
    if S.phase == "text" then
        love.graphics.draw(img, P0.x, P0.y, 0, 2, 2)
        -- name plate + text box
        love.graphics.setColor(0.05, 0.05, 0.15, 1)
        love.graphics.rectangle("fill", 154, 24, 158, 104)
        love.graphics.setColor(1, 0.85, 0.4, 1)
        love.graphics.rectangle("line", 154.5, 24.5, 157, 103)
        T.print("NONNO", 162, 30, { 1, 0.85, 0.4 })
        local shown = T.clean(PAGES[S.page]):sub(1, S.chars)
        for i, line in ipairs(T.wrap(shown, 24)) do T.print(line, 162, 44 + (i - 1) * 12) end
        if finishText() and math.floor(S.t / 20) % 2 == 0 then T.print("A", 300, 114, { 1, 0.85, 0.4 }) end
        T.print("START: SALTA", 4, 4, { 0.7, 0.7, 0.8 })
    else
        local k = math.min(S.t / SHRINK, 1)
        local e = k * k * (3 - 2 * k)                         -- smoothstep
        local sc = 2 + (0.5 - 2) * e
        local x = P0.x + (P1.x - P0.x) * e
        local y = P0.y + (P1.y - P0.y) * e
        love.graphics.draw(img, math.floor(x), math.floor(y), 0, sc, sc)
        if S.t >= SHRINK then                                -- white flash, 2-colour, no blending
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.rectangle("fill", 0, 0, 320, 240)
        end
    end
end

return S
