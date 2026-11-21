-- 1-vs-1 fight in the style of the early-90s arcade fighters.
-- Y light punch, X heavy punch, B light kick, A heavy kick; hold back to block,
-- down + back to block low. Specials: Nonno  down, down-forward, forward + punch (volleyball);
-- Toro  hold back, then forward + punch (horn charge). Best of 3 rounds, 60 seconds each.
local T = require("lib.text")
local I = require("lib.input")
local F = {}

local GROUND, ARENA = 214, 480                 -- arena wider than the screen: the camera follows
local LEFT, RIGHT, MAXGAP = 28, ARENA - 28, 250
local GRAV, JUMPV, JUMPX = 0.32, -6.8, 2.2
local WALKF, WALKB = 1.9, 1.5
local HITSTOP, ROUND_TIME, ROUNDS_TO_WIN = 6, 60, 2
local CHARGE = 40                    -- frames of "back" for the Toro's charge

local MOVES = {
    lp = { seq = { { "lp1", 3 }, { "lp2", 4, true }, { "lp1", 6 } }, dmg = 4, stun = 14, bstun = 10, push = 2.0, level = "mid", chain = true },
    hp = { seq = { { "hp1", 6 }, { "hp2", 5, true }, { "hp1", 12 } }, dmg = 9, stun = 20, bstun = 14, push = 3.0, level = "mid" },
    lk = { seq = { { "lk1", 4 }, { "lk2", 5, true }, { "lk1", 8 } }, dmg = 5, stun = 15, bstun = 11, push = 2.0, level = "mid", chain = true },
    hk = { seq = { { "hk1", 8 }, { "hk2", 6, true }, { "hk1", 14 } }, dmg = 11, stun = 22, bstun = 15, push = 3.5, level = "mid" },
    ck = { seq = { { "ck1", 5 }, { "ck2", 6, true }, { "ck1", 12 } }, dmg = 7, stun = 18, bstun = 12, push = 2.5, level = "low", crouch = true },
    jk = { seq = { { "jk", 40, true } }, dmg = 8, stun = 18, bstun = 12, push = 2.0, level = "air", air = true },
    ball = { seq = { { "sp1", 10 }, { "sp2", 22 } }, spawn = 10, special = true },
    charge = { seq = { { "sp1", 10 }, { "sp2", 22, true }, { "sp1", 12 } }, dmg = 13, stun = 24, bstun = 16, push = 5,
               level = "mid", dash = 4.5, special = true },
}
local BALL = { dmg = 10, stun = 18, bstun = 12, push = 2.0, level = "mid", chip = 2 }

local CHARS = {
    nonno = { name = "NONNO", special = "ball" },
    toro = { name = "TORO", special = "charge" },
}

local quads = {}
local function quad(img, x, y, w, h)
    local k = tostring(img) .. x .. ":" .. y .. ":" .. w
    quads[k] = quads[k] or love.graphics.newQuad(x, y, w, h, img)
    return quads[k]
end

-- ------------------------------------------------------------------ fighters
local function newFighter(ch, x, dir, ctrl)
    local f = {
        ch = ch, info = CHARS[ch], img = G.img["f_" .. ch],
        data = love.filesystem.load("assets/f_" .. ch .. ".lua")(),
        x = x, y = GROUND, vx = 0, vy = 0, dir = dir, hp = 100, wins = 0,
        state = "idle", t = 0, stun = 0, frame = "idle1", ctrl = ctrl,
        prev = {}, hist = {}, charge = 0, chargeKeep = 0,
    }
    return f
end

local function resetFighter(f, x, dir)
    f.x, f.y, f.vx, f.vy, f.dir, f.hp = x, GROUND, 0, 0, dir, 100
    f.state, f.t, f.stun, f.move, f.frame, f.hist = "idle", 0, 0, nil, "idle1", {}
end

-- buttons relative to the facing direction
local function rel(f, b)
    local fwd = f.dir > 0 and b.right or (f.dir < 0 and b.left)
    local back = f.dir > 0 and b.left or (f.dir < 0 and b.right)
    return { fwd = fwd, back = back, up = b.up, down = b.down }
end

local function startMove(f, name)
    f.state, f.move, f.mname, f.mt, f.hitDone = "attack", MOVES[name], name, 0, false
    if f.move.special then F.stats.specials[f.side] = F.stats.specials[f.side] + 1 end
end

-- quarter circle forward in the recent history (down, down-forward, forward)
local function qcf(f)
    local stage = 0
    for i = math.max(1, #f.hist - 20), #f.hist do
        local h = f.hist[i]
        if stage == 0 and h.down and not h.fwd then stage = 1
        elseif stage == 1 and h.down and h.fwd then stage = 2
        elseif stage == 2 and h.fwd and not h.down then return true end
    end
    return false
end

local function attackButton(f, p, r)
    if p.y then return "lp" end
    if p.x then return "hp" end
    if p.b then return r.down and "ck" or "lk" end
    if p.a then return r.down and "ck" or "hk" end
end

local function freeState(f)
    return f.state == "idle" or f.state == "walk" or f.state == "crouch"
end

local function updateFighter(f, o)
    local b = f.ctrl()
    local p = {}
    for k, v in pairs(b) do if v and not f.prev[k] then p[k] = true end end
    f.prev = b
    local r = rel(f, b)
    f.hist[#f.hist + 1] = r
    if #f.hist > 30 then table.remove(f.hist, 1) end
    if r.back and not r.fwd then f.charge, f.chargeKeep = f.charge + 1, 10
    elseif f.chargeKeep > 0 then f.chargeKeep = f.chargeKeep - 1
    else f.charge = 0 end
    f.t = f.t + 1
    local punch = p.y or p.x

    if f.state == "ko" then
        f.vy = f.vy + GRAV
        f.y = math.min(GROUND, f.y + f.vy)
        f.x = f.x + f.vx
        if f.y >= GROUND then f.vx = f.vx * 0.8 end
        f.frame = f.t < 18 and "ko1" or "ko2"
        return
    elseif f.state == "win" then
        f.frame = "win"
        return
    elseif f.state == "hit" or f.state == "block" then
        f.stun = f.stun - 1
        f.x = f.x + f.vx
        f.vx = f.vx * 0.8
        if f.y < GROUND then
            f.vy = f.vy + GRAV
            f.y = math.min(GROUND, f.y + f.vy)
        end
        f.frame = f.state == "hit" and "hit" or (f.crouchBlock and "cblock" or "block")
        if f.stun <= 0 and f.y >= GROUND then f.state = "idle" end
        return
    elseif f.state == "attack" then
        local m = f.move
        f.mt = f.mt + 1
        local acc, cur = 0, nil
        for _, s in ipairs(m.seq) do
            acc = acc + s[2]
            if f.mt <= acc then cur = s break end
        end
        if m.air or f.y < GROUND then
            f.vy = f.vy + GRAV
            f.y = f.y + f.vy
            f.x = f.x + f.vx
            if f.y >= GROUND then f.y, f.vy, f.vx = GROUND, 0, 0; f.state = "idle" return end
        end
        if m.spawn and f.mt == m.spawn and not F.proj[f.side] then
            F.proj[f.side] = { x = f.x + 50 * f.dir, y = f.y - 92, vx = 3.6 * f.dir, owner = f, t = 0 }
        end
        if m.dash and cur and cur[3] then f.x = f.x + m.dash * f.dir end
        if m.chain and f.hitDone then                          -- combo: cancel into the next attack
            local nxt = attackButton(f, p, r)
            if nxt then startMove(f, nxt) return end
        end
        if not cur then
            f.state = f.y < GROUND and "jump" or "idle"
        else
            f.frame, f.active = cur[1], cur[3]
            return
        end
    end

    if f.state == "jump" then
        f.vy = f.vy + GRAV
        f.y = f.y + f.vy
        f.x = f.x + f.vx
        f.frame = "jump"
        if (p.a or p.b or p.x or p.y) and f.vy > -4 then startMove(f, "jk") return end
        if f.y >= GROUND then f.y, f.vy, f.vx, f.state = GROUND, 0, 0, "idle" end
        return
    end

    -- free on the ground: face the opponent, then specials > attacks > jump > crouch > walk
    if freeState(f) then
        f.dir = o.x >= f.x and 1 or -1
        r = rel(f, b)
        if punch and f.info.special == "ball" and qcf(f) and not F.proj[f.side] then startMove(f, "ball") return end
        if punch and f.info.special == "charge" and f.charge >= CHARGE and r.fwd then startMove(f, "charge") return end
        local atk = attackButton(f, p, r)
        if atk then startMove(f, atk) return end
        if r.up then
            f.state, f.vy, f.vx = "jump", JUMPV, (r.fwd and JUMPX or (r.back and -JUMPX or 0)) * f.dir
            f.frame = "jump"
            return
        end
        if r.down then
            f.state, f.frame = "crouch", "crouch"
        elseif r.fwd or r.back then
            f.state = "walk"
            f.x = f.x + (r.fwd and WALKF or -WALKB) * f.dir
            local cyc = { "walk1", "walk2", "walk3", "walk4" }
            local k = math.floor(f.t / 8) % 4 + 1
            f.frame = cyc[r.fwd and k or (5 - k)]
        else
            f.state = "idle"
            f.frame = math.floor(f.t / 20) % 2 == 0 and "idle1" or "idle2"
        end
    end
end

-- world-space hurt box and hit circle of the current frame
local function hurtBox(f)
    local h = f.data[f.frame].hurt
    local x0, x1 = h[1], h[3]
    if f.dir < 0 then x0, x1 = -x1, -x0 end
    return f.x + x0 + 3, f.y + h[2] + 2, f.x + x1 - 3, f.y + h[4]
end

local function hitPoint(f)
    local h = f.data[f.frame].hit
    if not h then return nil end
    return f.x + h[1] * f.dir, f.y + h[2], h[3]
end

local function circleRect(cx, cy, r, x0, y0, x1, y1)
    local nx = math.max(x0, math.min(cx, x1))
    local ny = math.max(y0, math.min(cy, y1))
    return (cx - nx) ^ 2 + (cy - ny) ^ 2 <= r * r
end

local function spark(x, y, blue)
    F.fx[#F.fx + 1] = { x = x, y = y, t = 0, blue = blue }
end

-- returns true when the hit landed (not blocked)
local function applyHit(atk, def, m, hx, hy, fromX)
    local r = { down = def.prev.down }
    local away = (fromX < def.x and def.prev.right) or (fromX >= def.x and def.prev.left)
    local canBlock = def.y >= GROUND and (freeState(def) or def.state == "block") and away
    if canBlock and m.level == "low" and not r.down then canBlock = false end
    if canBlock and m.level == "air" and r.down then canBlock = false end
    local dirPush = def.x >= fromX and 1 or -1
    if canBlock then
        def.state, def.stun, def.vx, def.crouchBlock = "block", m.bstun, m.push * dirPush, r.down
        def.hp = math.max(1, def.hp - (m.chip or 0))
        F.stats.blocks[def.side] = F.stats.blocks[def.side] + 1
        spark(hx, hy, true)
        F.hitstop = 3
        return false
    end
    def.hp = math.max(0, def.hp - m.dmg)
    def.state, def.stun, def.vx, def.move = "hit", m.stun, m.push * dirPush, nil
    if def.y < GROUND then def.vy = -2 end
    F.stats.hits[atk.side] = F.stats.hits[atk.side] + 1
    spark(hx, hy, false)
    F.hitstop, F.shake = HITSTOP, 6
    if def.hp <= 0 then
        def.state, def.t, def.vy, def.vx = "ko", 0, -4, 2.5 * dirPush
        F.hitstop = 30
    end
    return true
end

local function resolve()
    local A, B = F.f[1], F.f[2]
    for _, pair in ipairs({ { A, B }, { B, A } }) do
        local atk, def = pair[1], pair[2]
        if atk.state == "attack" and atk.active and not atk.hitDone and def.state ~= "ko" then
            local hx, hy, rr = hitPoint(atk)
            if hx and circleRect(hx, hy, rr, hurtBox(def)) then
                atk.hitDone = true
                applyHit(atk, def, atk.move, hx, hy, atk.x)
            end
        end
    end
    -- projectiles
    for side = 1, 2 do
        local pr = F.proj[side]
        if pr then
            pr.x, pr.t = pr.x + pr.vx, pr.t + 1
            local def = F.f[3 - side]
            if def.state ~= "ko" and circleRect(pr.x, pr.y, 7, hurtBox(def)) then
                applyHit(pr.owner, def, BALL, pr.x, pr.y, pr.x - pr.vx * 5)
                F.proj[side] = nil
            elseif pr.x < F.cam - 20 or pr.x > F.cam + 340 then
                F.proj[side] = nil
            end
        end
    end
    -- push boxes and walls
    local dx = B.x - A.x
    if math.abs(dx) < 40 and math.abs(A.y - B.y) < 80 then
        local push = (40 - math.abs(dx)) / 2
        local s = dx >= 0 and 1 or -1
        A.x, B.x = A.x - push * s, B.x + push * s
    end
    local mid = (A.x + B.x) / 2                         -- both always on screen
    for _, f in ipairs(F.f) do
        f.x = math.max(LEFT, math.min(RIGHT, math.max(mid - MAXGAP / 2, math.min(mid + MAXGAP / 2, f.x))))
    end
    F.cam = math.max(0, math.min(ARENA - 320, (A.x + B.x) / 2 - 160))
end

-- ------------------------------------------------------------------ CPU
-- Plans short sequences of relative inputs; reacts to attacks and projectiles.
function F.newAI(side, seed, blockRate)
    local rng = love.math.newRandomGenerator(seed)
    local queue = {}
    local function push(b, n) queue[#queue + 1] = { b = b, n = n } end
    local function plan(f, o)
        local dist = math.abs(o.x - f.x)
        local incoming = F.proj[3 - side]
        if incoming and math.abs(incoming.x - f.x) < 140 then
            if rng:random() < 0.5 then push({ up = true, fwd = true }, 3); push({}, 20)
            else push({ back = true }, 30) end
            return
        end
        if o.state == "attack" and dist < 130 and rng:random() < blockRate then
            push({ back = true, down = o.move and o.move.level == "low" }, 16)
            return
        end
        local r = rng:random()
        if dist > 130 then
            if f.info.special == "ball" and r < 0.35 then
                push({ down = true }, 3); push({ down = true, fwd = true }, 3); push({ fwd = true }, 2)
                push({ fwd = true, y = true }, 2); push({}, 12)
            elseif f.info.special == "charge" and r < 0.4 then
                push({ back = true }, CHARGE + 4); push({ fwd = true, y = true }, 3); push({}, 14)
            else
                push({ fwd = true }, 14 + rng:random(0, 14))
            end
        elseif dist > 88 then
            if r < 0.22 then push({ up = true, fwd = true }, 3); push({}, 12); push({ b = true }, 2); push({}, 24)
            elseif r < 0.32 then push({ back = true }, 16)
            else push({ fwd = true }, 10) end
        else
            if r < 0.25 then push({ y = true }, 2); push({}, 5); push({ y = true }, 2); push({}, 5); push({ x = true }, 2); push({}, 14)
            elseif r < 0.45 then push({ a = true }, 2); push({}, 24)
            elseif r < 0.6 then push({ down = true, b = true }, 2); push({ down = true }, 18)
            elseif r < 0.75 then push({ x = true }, 2); push({}, 18)
            elseif r < 0.88 then push({ back = true }, 12)
            else push({ b = true }, 2); push({}, 8); push({ y = true }, 2); push({}, 12) end
        end
    end
    return function()
        local f, o = F.f[side], F.f[3 - side]
        if not f or F.phase ~= "fight" then return {} end
        if #queue == 0 then plan(f, o) end
        local step = queue[1]
        step.n = step.n - 1
        if step.n <= 0 then table.remove(queue, 1) end
        local s = step.b
        local fwdKey = f.dir > 0 and "right" or "left"
        local backKey = f.dir > 0 and "left" or "right"
        return { [fwdKey] = s.fwd, [backKey] = s.back, up = s.up, down = s.down, a = s.a, b = s.b, x = s.x, y = s.y }
    end
end

local function playerCtrl()
    if F.phase ~= "fight" then return {} end
    return { left = I.down("left"), right = I.down("right"), up = I.down("up"), down = I.down("down"),
             a = I.down("a"), b = I.down("b"), x = I.down("x"), y = I.down("y") }
end

-- ------------------------------------------------------------------ rounds
function F.enter(opts)
    opts = opts or {}
    F.stats = { hits = { 0, 0 }, blocks = { 0, 0 }, specials = { 0, 0 }, rounds = 0 }
    local c1 = opts.p1ai and F.newAI(1, opts.seed or 11, 0.3) or playerCtrl
    F.f = { newFighter("nonno", 170, 1, c1), newFighter("toro", 310, -1, F.newAI(2, (opts.seed or 11) + 1, 0.35)) }
    F.cam = 80
    F.f[1].side, F.f[2].side = 1, 2
    F.round, F.phase, F.pt = 0, "vs", 0
    F.proj, F.fx, F.hitstop, F.shake = {}, {}, 0, 0
end

local function startRound()
    F.round = F.round + 1
    resetFighter(F.f[1], 170, 1)
    resetFighter(F.f[2], 310, -1)
    F.cam = 80
    F.proj, F.fx = {}, {}
    F.timer, F.phase, F.pt = ROUND_TIME, "intro", 0
end

local function endRound(winner)
    F.stats.rounds = F.stats.rounds + 1
    F.winner = winner
    if winner then
        winner.wins = winner.wins + 1
        winner.state, winner.t = "win", 0
    end
    F.phase, F.pt = "roundend", 0
end

function F.update()
    F.pt = F.pt + 1
    F.shake = math.max(0, F.shake - 1)
    if F.phase == "vs" then
        if F.pt > 120 or (F.pt > 20 and (I.pressed("start") or I.pressed("a"))) then startRound() end
        return
    elseif F.phase == "intro" then
        if F.pt >= 100 then F.phase, F.pt = "fight", 0 end
    elseif F.phase == "end" then
        if F.pt > 60 and (I.pressed("start") or I.pressed("a")) then G.switch("menu") end
        return
    end
    if F.phase == "fight" and I.pressed("start") then F.paused = not F.paused end
    if F.paused then return end
    if F.hitstop > 0 then
        F.hitstop = F.hitstop - 1
        return
    end
    local A, B = F.f[1], F.f[2]
    updateFighter(A, B)
    updateFighter(B, A)
    resolve()
    for i = #F.fx, 1, -1 do
        F.fx[i].t = F.fx[i].t + 1
        if F.fx[i].t > 10 then table.remove(F.fx, i) end
    end
    if F.phase == "fight" then
        if F.pt % 60 == 0 then F.timer = F.timer - 1 end
        if A.state == "ko" or B.state == "ko" then
            F.phase, F.pt, F.koText = "ko", 0, "K.O."
        elseif F.timer <= 0 then
            F.phase, F.pt, F.koText = "ko", 0, "TEMPO!"
        end
    elseif F.phase == "ko" and F.pt > 90 then
        local w
        if A.hp > B.hp then w = A elseif B.hp > A.hp then w = B end
        endRound(w)
    elseif F.phase == "roundend" and F.pt > 120 then
        if A.wins >= ROUNDS_TO_WIN or B.wins >= ROUNDS_TO_WIN or F.round >= 5 then
            F.phase, F.pt = "end", 0
        else
            startRound()
        end
    end
end

-- ------------------------------------------------------------------ drawing
local function drawFighter(f, scale, x, y)
    local D = f.data
    local i, fs = D[f.frame].i, D.size
    love.graphics.draw(f.img, quad(f.img, (i % D.cols) * fs, math.floor(i / D.cols) * fs, fs, fs),
        math.floor(x or (f.x - F.cam)), math.floor(y or f.y), 0, f.dir * (scale or 1), scale or 1, D.ox, D.oy)
end

-- tile a 320-wide layer with a parallax factor
local function layer(img, y, k)
    local off = -math.floor(F.cam * k) % img:getWidth()
    for x = off - img:getWidth(), 320, img:getWidth() do love.graphics.draw(img, x, y) end
end

local function stage()
    love.graphics.draw(G.img.bg_sky, 0, 0)
    layer(G.img.bg_sea, 110, 0.3)
    layer(G.img.bg_palms, 88, 0.6)
    local tiles = G.img.tiles
    local off = -math.floor(F.cam) % 16
    for x = off - 16, 320, 16 do
        love.graphics.draw(tiles, quad(tiles, 0, 0, 16, 16), x, 208)
        love.graphics.draw(tiles, quad(tiles, 16, 0, 16, 16), x, 224)
    end
end

local function bar(x, w, hp, right)
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", x - 1, 17, w + 2, 9)
    love.graphics.setColor(0.75, 0.1, 0.15)
    love.graphics.rectangle("fill", x, 18, w, 7)
    love.graphics.setColor(1, 0.85, 0.2)
    local fw = math.floor(w * hp / 100)
    love.graphics.rectangle("fill", right and x or x + w - fw, 18, fw, 7)
    love.graphics.setColor(1, 1, 1)
end

local function hud()
    local A, B = F.f[1], F.f[2]
    bar(14, 124, A.hp, false)
    bar(182, 124, B.hp, true)
    T.print(A.info.name, 14, 29, { 1, 0.85, 0.4 })
    T.print(B.info.name, 306 - T.width(B.info.name), 29, { 1, 0.85, 0.4 })
    for k = 1, ROUNDS_TO_WIN do
        love.graphics.setColor(k <= A.wins and { 1, 0.85, 0.2 } or { 0.2, 0.2, 0.3 })
        love.graphics.rectangle("fill", 128 - (k - 1) * 9, 29, 7, 7)
        love.graphics.setColor(k <= B.wins and { 1, 0.85, 0.2 } or { 0.2, 0.2, 0.3 })
        love.graphics.rectangle("fill", 185 + (k - 1) * 9, 29, 7, 7)
    end
    love.graphics.setColor(1, 1, 1)
    T.big(string.format("%02d", math.max(0, F.timer or ROUND_TIME)), 14, 2, { 1, 1, 1 })
end

function F.draw()
    if F.phase == "vs" then
        love.graphics.setColor(0.12, 0.1, 0.3)
        love.graphics.rectangle("fill", 0, 0, 320, 240)
        love.graphics.setColor(0.4, 0.08, 0.1)
        love.graphics.polygon("fill", 190, 0, 320, 0, 320, 240, 130, 240)
        love.graphics.setColor(1, 1, 1)
        local slide = math.max(0, 40 - F.pt) * 4
        drawFighter(F.f[1], 1, 84 - slide, 206)
        drawFighter(F.f[2], 1, 236 + slide, 206)
        T.print(F.f[1].info.name, 20, 210, { 1, 0.85, 0.4 })
        T.print(F.f[2].info.name, 300 - T.width(F.f[2].info.name), 210, { 1, 0.85, 0.4 })
        if F.pt > 40 then T.big("VS", 30, 4, { 1, 0.9, 0.3 }) end
        return
    end
    love.graphics.push()
    if F.shake > 0 then love.graphics.translate((F.shake % 2) * 4 - 2, 0) end
    stage()
    -- shadows (solid, no alpha)
    love.graphics.setColor(196 / 255, 156 / 255, 90 / 255)
    for _, f in ipairs(F.f) do love.graphics.ellipse("fill", math.floor(f.x - F.cam), GROUND - 1, 26, 4) end
    love.graphics.setColor(1, 1, 1)
    local A, B = F.f[1], F.f[2]
    local first, second = A, B
    if A.state == "attack" then first, second = B, A end
    drawFighter(first)
    drawFighter(second)
    for side = 1, 2 do
        local pr = F.proj[side]
        if pr then
            local k = math.floor(pr.t / 4) % 2
            love.graphics.draw(G.img.bigball, quad(G.img.bigball, k * 16, 0, 16, 16), math.floor(pr.x - 8 - F.cam), math.floor(pr.y - 8))
        end
    end
    for _, e in ipairs(F.fx) do
        local k = (e.t < 5 and 0 or 1) + (e.blue and 2 or 0)
        love.graphics.draw(G.img.spark, quad(G.img.spark, k * 15, 0, 15, 13), math.floor(e.x - 15 - F.cam), math.floor(e.y - 13), 0, 2, 2)
    end
    love.graphics.pop()
    hud()
    if F.phase == "intro" then
        if F.pt < 60 then T.big("ROUND " .. F.round, 46, 3, { 1, 1, 1 })
        else T.big("COMBATTI!", 46, 3, { 1, 0.85, 0.3 }) end
    elseif F.phase == "ko" then
        T.big(F.koText, 44, 4, { 1, 0.3, 0.3 })
    elseif F.phase == "roundend" then
        T.big(F.winner and ("VINCE " .. F.winner.info.name) or "PAREGGIO", 50, 2, { 1, 0.85, 0.3 })
    elseif F.phase == "end" then
        local A2, B2 = F.f[1], F.f[2]
        local w = A2.wins > B2.wins and A2 or (B2.wins > A2.wins and B2 or nil)
        T.big(w and (w.info.name .. " CAMPIONE!") or "PAREGGIO", 46, 2, { 1, 0.85, 0.3 })
        if F.pt > 60 then T.center("PREMI START", 64, { 0.7, 0.9, 1 }) end
    end
    if F.paused then T.big("PAUSA", 46, 3, { 1, 0.85, 0.3 }) end
end

return F
