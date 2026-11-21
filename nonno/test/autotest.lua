-- Headless play-through: `love . --test` (with xvfb-run on a server).
-- Drives the inputs, checks the game state, saves screenshots, exits 0 on success.
local I = require("lib.input")
local R = require("lib.retro")
local A = {}
local log, fails, shots, want = {}, 0, {}, nil
local t, phase, jumpHold, maxX = 0, "menu", 0, 0
local seen = {}

local function check(cond, msg)
    print((cond and "ok   " or "FAIL ") .. msg)
    if not cond then fails = fails + 1 end
end

local function shot(name) want = name end

function A.start()
    print("save dir: " .. love.filesystem.getSaveDirectory())
    check(G.sceneName == "menu", "boots into the menu")
    I.script = function() return A.buttons() end
end

local function bot()
    local L = G.scenes.level
    local p = L.p
    local b = { right = true }
    local front = p.x + p.w + 2
    local feet = p.y + p.h
    local danger = L.solid(L.at(front + 4, feet - 4)) or L.solid(L.at(front + 4, feet - 20))
    local gap = p.ground and not L.solid(L.at(front + 18, feet + 2)) and L.at(front + 18, feet + 2) ~= "="
    for _, c in ipairs(L.crabs) do
        if c.dead == 0 and c.x > p.x and c.x - (p.x + p.w) < 34 and math.abs(c.y - p.y - p.h + c.h) < 20 then danger = true end
    end
    local target = false
    for _, c in ipairs(L.crabs) do
        if c.dead == 0 and c.x > p.x + 30 and c.x - p.x < 130 and math.abs(c.y + c.h - p.y - p.h) < 4 then target = true end
    end
    if p.ground and target and #L.balls == 0 and p.throw == 0 and t % 2 == 0 then b.b = true end
    if jumpHold > 0 then
        jumpHold = jumpHold - 1
        b.a = true
    elseif p.ground and (danger or gap) then
        jumpHold = 22
        b.a = nil                      -- release for one frame so the press is new
    end
    return b
end

function A.buttons()
    t = t + 1
    if phase == "menu" then
        if t == 20 then return { a = true } end
        return {}
    elseif phase == "story" then
        if t % 30 == 0 then return { a = true } end
        return {}
    elseif phase == "level" then
        local b = bot()
        if jumpHold == 22 then jumpHold = 21; return { right = true } end
        return b
    end
    return {}
end

function A.update()
    local S = G.scenes.story
    if phase == "menu" then
        if t == 5 then shot("0_menu") end
        if G.sceneName == "story" then
            check(true, "A on STORIA starts the story")
            phase, t = "story", 0
        end
    elseif phase == "story" then
        if G.sceneName == "story" then
            if S.page == 1 and S.chars == 10 and not seen.p1 then seen.p1 = true; shot("1_story") end
            if S.page == 2 then seen.p2 = true end
            if S.phase == "shrink" and S.t == 35 then shot("2_shrink") end
        else
            check(seen.p1 and seen.p2, "A advances the story pages")
            check(G.sceneName == "level", "story ends with the shrink into the level")
            phase, t = "level", 0
            shot("3_level_start")
        end
    elseif phase == "level" then
        local L = G.scenes.level
        maxX = math.max(maxX, L.p.x)
        if not seen.mid and L.p.x > 700 then seen.mid = true; shot("4_level_mid") end
        if not seen.air and not L.p.ground and L.p.vy < 0 and L.p.x > 250 then seen.air = true; shot("5_jump") end
        if not seen.ball and #L.balls > 0 and L.balls[1].life == 150 - 8 then seen.ball = true; shot("5b_throw") end
        if not seen.knock then
            for _, c in ipairs(L.crabs) do if c.dead < 0 and c.vy > -1 and c.vy < 0 then seen.knock = true; shot("5c_knock") end end
        end
        if L.state ~= "play" then
            check(L.state == "clear", "the bot reaches the goal (" .. L.state .. ", x=" .. math.floor(maxX) .. ")")
            check(L.throws >= 1 and L.hits >= 1, "B throws the ball and it knocks crabs out (" .. L.throws .. " throws, " .. L.hits .. " hits)")
            check(L.stomps + L.hits >= 3, "crabs defeated: " .. L.stomps .. " stomped, " .. L.hits .. " by the ball")
            check(L.lives >= 1, "lives left: " .. L.lives)
            phase, t = "end", 0
        elseif t > 60 * 120 then
            check(false, "level finished within 2 minutes (x=" .. math.floor(maxX) .. ")")
            phase, t = "end", 0
        end
    elseif phase == "end" then
        if t >= 70 and not seen.clear then seen.clear = true; shot("6_clear") end
        if t >= 76 and not seen.win then
            seen.win = true
            love.graphics.captureScreenshot("7_window_scanlines.png")
        end
        if t >= 78 and not seen.wide then                -- Android phone: 20:9 + touch pad
            seen.wide = true
            love.window.setMode(1200, 540, { resizable = true })
            R.resize(love.graphics.getDimensions())
            I.touchMode = true
        end
        if t >= 82 and not seen.wideShot then
            seen.wideShot = true
            check(R.scale == 2 and R.ox == 280, "20:9 screen: integer 2x scale, centred")
            love.graphics.captureScreenshot("8_android_wide.png")
        end
        if t >= 88 then
            print(fails == 0 and "all checks passed" or (fails .. " checks failed"))
            love.event.quit(fails == 0 and 0 or 1)
        end
    end
end

function A.afterDraw()
    if want then
        local name = want
        want = nil
        love.graphics.setCanvas()
        R.canvas:newImageData():encode("png", name .. ".png")
        love.graphics.setCanvas(R.canvas)
    end
end

return A
