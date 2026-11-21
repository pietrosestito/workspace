-- Title menu: story mode or the 1-vs-1 challenge.
local T = require("lib.text")
local I = require("lib.input")
local M = {}
local ITEMS = { { "STORIA", "story" }, { "SFIDA: NONNO CONTRO TORO", "fight" } }

function M.enter() M.sel, M.t = 1, 0 end

function M.update()
    M.t = M.t + 1
    if I.pressed("down") then M.sel = M.sel % #ITEMS + 1 end
    if I.pressed("up") then M.sel = (M.sel - 2) % #ITEMS + 1 end
    if M.t > 10 and (I.pressed("a") or I.pressed("start")) then G.switch(ITEMS[M.sel][2]) end
end

function M.draw()
    love.graphics.draw(G.img.bg_sky, 0, 0)
    love.graphics.draw(G.img.bg_sea, 0, 110)
    love.graphics.draw(G.img.bg_palms, 0, 88)
    T.big("IL NONNO", 30, 4, { 1, 0.85, 0.3 })
    T.big("E LA COPPA RUBATA", 66, 2, { 1, 1, 1 })
    love.graphics.draw(G.img.nonno_portrait, 6, 240 - 94 - 6)
    for i, it in ipairs(ITEMS) do
        local y = 132 + (i - 1) * 16
        local col = i == M.sel and { 1, 0.85, 0.3 } or { 0.8, 0.8, 0.9 }
        T.print(it[1], 92, y, col)
        if i == M.sel and math.floor(M.t / 15) % 2 == 0 then
            love.graphics.setColor(col)
            love.graphics.polygon("fill", 82, y, 87, y + 3, 82, y + 6)
            love.graphics.setColor(1, 1, 1)
        end
    end
    T.print("SELECT: SCANLINE", 186, 228, { 0.6, 0.6, 0.7 })
end

return M
