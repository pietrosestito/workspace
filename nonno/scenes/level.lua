-- Platform level: 16x16 tile map, three parallax layers, crabs, a goal.
local T = require("lib.text")
local I = require("lib.input")
local L = {}

local TS = 16
local GRAV, MAXFALL = 0.35, 6
local ACC, FRICTION, MAXRUN = 0.25, 0.2, 2.0
local JUMP, JUMPCUT = -6.2, -2.0
local COYOTE, BUFFER = 6, 6
-- Nonno: 40x52 sprite, 14x44 hitbox
local FW, FH = 40, 52
local PW, PH, POX, POY = 14, 44, 13, 8
local RUNCYCLE = { "run1", "run2", "run3", "run4" }
local THROW_WIND, THROW_END = 6, 14      -- frames of throw1, then throw2; the ball leaves at THROW_WIND
local BALL_LIFE = 150
local FRAMES = {}                        -- name -> index, from the order written by mkassets.py
do
    local i = 0
    for name in love.filesystem.read("assets/nonno.txt"):gmatch("%S+") do FRAMES[name] = i; i = i + 1 end
end

local quads = {}

local function quad(img, x, y, w, h)
    local k = tostring(img) .. x .. ":" .. y
    quads[k] = quads[k] or love.graphics.newQuad(x, y, w, h, img)
    return quads[k]
end

local function loadMap(path)
    local rows = {}
    for line in love.filesystem.lines(path) do
        if #line > 0 then rows[#rows + 1] = line end
    end
    local m = { w = #rows[1], h = #rows, cell = {}, crabs = {} }
    for y, row in ipairs(rows) do
        m.cell[y] = {}
        for x = 1, #row do
            local c = row:sub(x, x)
            if c == "P" then m.px, m.py = (x - 1) * TS, y * TS; c = "."
            elseif c == "C" then m.crabs[#m.crabs + 1] = { (x - 1) * TS - 4, y * TS }; c = "."
            elseif c == "G" then m.gx, m.gy = (x - 1) * TS, (y - 1) * TS; c = "." end
            m.cell[y][x] = c
        end
    end
    return m
end

local function at(px, py)   -- tile char at a pixel position
    local x, y = math.floor(px / TS) + 1, math.floor(py / TS) + 1
    if x < 1 or x > L.map.w then return "#" end
    if y < 1 or y > L.map.h then return "." end
    return L.map.cell[y][x]
end
local function solid(c) return c == "#" or c == "B" end
L.at, L.solid = at, solid

-- axis-separated move of a box {x,y,w,h,vx,vy}; returns hit flags
local function move(o, oneway)
    local hitX, ground = false, false
    o.x = o.x + o.vx
    local edge = o.vx > 0 and o.x + o.w - 0.01 or o.x
    for _, yy in ipairs({ o.y, o.y + o.h / 2, o.y + o.h - 0.01 }) do
        if solid(at(edge, yy)) then
            if o.vx > 0 then o.x = math.floor((edge) / TS) * TS - o.w
            else o.x = (math.floor(edge / TS) + 1) * TS end
            o.vx, hitX = 0, true
            break
        end
    end
    local oldBottom = o.y + o.h
    o.y = o.y + o.vy
    for _, xx in ipairs({ o.x + 1, o.x + o.w - 1 }) do
        if o.vy > 0 then
            local c = at(xx, o.y + o.h)
            local top = math.floor((o.y + o.h) / TS) * TS
            if solid(c) or (oneway and c == "=" and oldBottom <= top + 0.01) then
                o.y, o.vy, ground = top - o.h, 0, true
                break
            end
        elseif o.vy < 0 and solid(at(xx, o.y)) then
            o.y, o.vy = (math.floor(o.y / TS) + 1) * TS, 0
            break
        end
    end
    return hitX, ground
end

function L.enter()
    L.map = loadMap("levels/spiaggia.txt")
    L.lives, L.stomps, L.hits, L.throws = 3, 0, 0, 0
    L.respawn()
end

function L.respawn()
    local m = L.map
    L.p = { x = m.px + POX, y = m.py - PH, w = PW, h = PH, vx = 0, vy = 0,
            dir = 1, ground = true, coyote = 0, buffer = 0, inv = 0, anim = 0, throw = 0 }
    L.balls = {}
    L.crabs = {}
    for _, c in ipairs(m.crabs) do
        L.crabs[#L.crabs + 1] = { x = c[1], y = c[2] - 12, w = 20, h = 12, vx = -0.5, vy = 0, dead = 0 }
    end
    L.cam, L.state, L.t, L.shake = 0, "play", 0, 0
end

local function hurt(p, fromX)
    L.lives = L.lives - 1
    p.inv, p.vy = 90, -3.5
    p.vx = (p.x + p.w / 2 < fromX) and -2 or 2
    L.shake = 10
    if L.lives <= 0 then L.state, L.t = "over", 0 end
end

local function updatePlayer()
    local p = L.p
    local ix = (I.down("right") and 1 or 0) - (I.down("left") and 1 or 0)
    if p.inv > 60 then ix = 0 end                       -- knock-back: no control
    if ix ~= 0 then
        p.vx = math.max(-MAXRUN, math.min(MAXRUN, p.vx + ix * ACC))
        p.dir = ix
    elseif p.vx > 0 then p.vx = math.max(0, p.vx - FRICTION)
    elseif p.vx < 0 then p.vx = math.min(0, p.vx + FRICTION) end

    p.buffer = I.pressed("a") and BUFFER or math.max(0, p.buffer - 1)
    p.coyote = p.ground and COYOTE or math.max(0, p.coyote - 1)
    if p.buffer > 0 and p.coyote > 0 then
        p.vy, p.buffer, p.coyote = JUMP, 0, 0
    end
    if not I.down("a") and p.vy < JUMPCUT then p.vy = JUMPCUT end
    p.vy = math.min(MAXFALL, p.vy + GRAV)

    local _, g = move(p, true)
    p.ground = g
    p.x = math.max(0, p.x)
    p.inv = math.max(0, p.inv - 1)
    p.anim = p.anim + math.abs(p.vx)

    -- B: volleyball. On the ground it flies in an arc, in the air it is a spike.
    if I.pressed("b") and p.throw == 0 and #L.balls == 0 and p.inv <= 60 then p.throw = 1 end
    if p.throw > 0 then
        p.throw = p.throw + 1
        if p.throw == THROW_WIND then
            local sx = p.x - POX
            local bx = p.dir > 0 and sx + 33 or sx + FW - 33 - 8
            L.balls[1] = { x = bx, y = p.y - POY + 30, w = 8, h = 8, life = BALL_LIFE, bounces = 0,
                           vx = 3.5 * p.dir, vy = p.ground and -2.5 or 2.5 }
            L.throws = L.throws + 1
        end
        if p.throw > THROW_END then p.throw = 0 end
    end

    if p.y > 260 then                                  -- fell in the sea
        L.lives = L.lives - 1
        L.shake = 10
        if L.lives <= 0 then L.state, L.t = "over", 0 else L.respawn() end
        return
    end
    -- goal
    if p.x + p.w > L.map.gx + 4 and p.x < L.map.gx + 12 and p.y + p.h > L.map.gy then
        L.state, L.t = "clear", 0
    end
end

local function overlap(a, b)
    return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end

local function updateBalls()
    for i = #L.balls, 1, -1 do
        local b = L.balls[i]
        b.life = b.life - 1
        b.vy = math.min(MAXFALL, b.vy + 0.15)
        local vy = b.vy
        local hitX, ground = move(b, true)
        if ground then
            b.bounces = b.bounces + 1
            b.vy = -math.abs(vy) * 0.65
        end
        if hitX then b.vx = 0; b.life = math.min(b.life, 10) end
        for _, c in ipairs(L.crabs) do
            if c.dead == 0 and overlap(b, c) then
                c.dead, c.vy, c.vx = -1, -3.5, (b.vx >= 0 and 1 or -1)
                b.vx, b.vy = -b.vx * 0.4, -3
                L.hits = L.hits + 1
                L.shake = 4
            end
        end
        if b.life <= 0 or b.bounces > 3 or b.y > 260 or math.abs(b.x - L.cam - 160) > 200 then
            table.remove(L.balls, i)
        end
    end
end

local function updateCrabs()
    local p = L.p
    for _, c in ipairs(L.crabs) do
        if c.dead < 0 then                                  -- knocked out by the ball: flies off
            c.x, c.vy = c.x + c.vx, c.vy + GRAV
            c.y = c.y + c.vy
            if c.y > 260 then c.dead = 99 end
        elseif c.dead > 0 then
            c.dead = c.dead + 1
        elseif math.abs(c.x - L.cam - 160) < 220 then      -- only near the screen
            c.vy = math.min(MAXFALL, c.vy + GRAV)
            local hit, g = move(c, true)
            local ahead = c.vx > 0 and c.x + c.w + 1 or c.x - 1
            if hit or (g and not solid(at(ahead, c.y + c.h + 2)) and at(ahead, c.y + c.h + 2) ~= "=") then
                c.vx = -c.vx
            end
            if c.y > 260 then c.dead = 99 end
            -- player contact
            if p.x < c.x + c.w and p.x + p.w > c.x and p.y < c.y + c.h and p.y + p.h > c.y then
                if p.vy > 0 and p.y + p.h - p.vy <= c.y + 6 then
                    c.dead, p.vy = 1, -4.5
                    L.stomps = L.stomps + 1
                    L.shake = 4
                elseif p.inv == 0 then
                    hurt(p, c.x + c.w / 2)
                end
            end
        end
    end
end

function L.update()
    L.t = L.t + 1
    L.shake = math.max(0, L.shake - 1)
    if L.state == "play" then
        if I.pressed("start") then L.state = "pause" return end
        updatePlayer()
        if L.state == "play" then updateBalls(); updateCrabs() end
        local target = L.p.x + L.p.w / 2 - 140
        L.cam = math.max(0, math.min(L.map.w * TS - 320, target))
    elseif L.state == "pause" then
        if I.pressed("start") then L.state = "play" end
    elseif L.state == "clear" or L.state == "over" then
        if L.t > 60 and (I.pressed("start") or I.pressed("a")) then G.switch("story") end
    end
end

-- tile a layer horizontally with a parallax factor
local function layer(img, y, f)
    local off = -math.floor(L.cam * f) % img:getWidth()
    for x = off - img:getWidth(), 320, img:getWidth() do love.graphics.draw(img, x, y) end
end

function L.draw()
    local sx = L.shake > 0 and ((L.t % 2) * 2 - 1) * 2 or 0
    love.graphics.draw(G.img.bg_sky, 0, 0)
    love.graphics.push()
    love.graphics.translate(sx, 0)
    layer(G.img.bg_sea, 110, 0.15)
    layer(G.img.bg_palms, 88, 0.4)                       -- trunks end on the sand line (y 208)
    -- sea visible in the pits
    love.graphics.setColor(60 / 255, 100 / 255, 170 / 255)
    love.graphics.rectangle("fill", 0, 211, 320, 29)
    love.graphics.setColor(110 / 255, 150 / 255, 200 / 255)
    for x = -math.floor(L.cam * 0.7 + L.t / 4) % 24 - 24, 320, 24 do
        love.graphics.rectangle("fill", x, 212 + (math.floor(x / 24) % 2) * 6, 8, 1)
    end
    love.graphics.setColor(1, 1, 1)
    -- tiles
    local cam = math.floor(L.cam)
    local tiles = G.img.tiles
    local x0 = math.floor(cam / TS) + 1
    for y = 1, L.map.h do
        for x = x0, math.min(L.map.w, x0 + 21) do
            local c, q = L.map.cell[y][x], nil
            if c == "#" then q = (y > 1 and L.map.cell[y - 1][x] == "#") and 1 or 0
            elseif c == "B" then q = 2
            elseif c == "=" then q = 3 end
            if q then love.graphics.draw(tiles, quad(tiles, q * 16, 0, 16, 16), (x - 1) * TS - cam, (y - 1) * TS) end
        end
    end
    love.graphics.draw(tiles, quad(tiles, 64, 0, 16, 16), L.map.gx - cam, L.map.gy - math.floor(L.t / 10) % 2)
    -- crabs
    local crab = G.img.crab
    for _, c in ipairs(L.crabs) do
        if c.dead == 0 then
            local f = math.floor(L.t / 12) % 2
            love.graphics.draw(crab, quad(crab, f * 24, 0, 24, 16), math.floor(c.x - 2 - cam), math.floor(c.y + c.h - 16))
        elseif c.dead < 0 then                                   -- upside down
            love.graphics.draw(crab, quad(crab, 0, 0, 24, 16), math.floor(c.x - 2 - cam), math.floor(c.y + c.h), 0, 1, -1)
        elseif c.dead < 20 then                                  -- squashed
            love.graphics.draw(crab, quad(crab, 0, 8, 24, 8), math.floor(c.x - 2 - cam), math.floor(c.y + c.h - 8))
        end
    end
    -- Nonno
    local p = L.p
    if p.inv == 0 or math.floor(L.t / 3) % 2 == 0 then
        local f
        if p.inv > 60 then f = "hurt"
        elseif p.throw > 0 then f = p.throw < THROW_WIND and "throw1" or "throw2"
        elseif not p.ground then f = p.vy < 0 and "jump" or "fall"
        elseif math.abs(p.vx) > 0.1 then f = RUNCYCLE[math.floor(p.anim / 8) % 4 + 1]
        else f = math.floor(L.t / 40) % 2 == 0 and "idle" or "idle2" end
        local img = G.img.nonno
        local x = math.floor(p.x - POX - cam)
        if p.dir < 0 then x = x + FW end
        love.graphics.draw(img, quad(img, FRAMES[f] * FW, 0, FW, FH), x, math.floor(p.y - POY), 0, p.dir, 1)
        if p.throw > 0 and p.throw < THROW_WIND then          -- ball held up in the hand
            local hx = p.dir > 0 and (p.x - POX + 36) or (p.x - POX + FW - 36 - 8)
            love.graphics.draw(G.img.ball, quad(G.img.ball, 0, 0, 8, 8), math.floor(hx - cam), math.floor(p.y - POY + 18))
        end
    end
    for _, b in ipairs(L.balls) do
        local f = math.floor(L.t / 4) % 2
        love.graphics.draw(G.img.ball, quad(G.img.ball, f * 8, 0, 8, 8), math.floor(b.x - cam), math.floor(b.y))
    end
    love.graphics.pop()
    -- HUD
    T.print("NONNO", 6, 6, { 1, 0.85, 0.4 })
    for i = 1, 3 do
        love.graphics.setColor(i <= L.lives and { 0.9, 0.15, 0.2 } or { 0.25, 0.1, 0.15 })
        love.graphics.rectangle("fill", 44 + (i - 1) * 9, 6, 7, 7)
    end
    love.graphics.setColor(1, 1, 1)
    T.print("GRANCHI " .. (L.stomps + L.hits), 250, 6)
    if L.state == "pause" then T.center("PAUSA", 110, { 1, 0.85, 0.4 })
    elseif L.state == "clear" then
        T.center("UNA COPPA? E' FINTA!", 90, { 1, 0.85, 0.4 })
        T.center("IL TORO E' PIU' AVANTI...", 104)
        if L.t > 60 then T.center("FINE DEMO - PREMI START", 130, { 0.7, 0.9, 1 }) end
    elseif L.state == "over" then
        T.center("GAME OVER", 104, { 1, 0.4, 0.4 })
    end
end

return L
