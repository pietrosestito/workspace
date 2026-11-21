-- Headless fight: `love . --test-fight`. CPU vs CPU (Nonno and Toro), whole match.
local I = require("lib.input")
local R = require("lib.retro")
local A = {}
local fails, t, want, seen = 0, 0, nil, {}

local function check(cond, msg)
    print((cond and "ok   " or "FAIL ") .. msg)
    if not cond then fails = fails + 1 end
end

function A.start()
    print("save dir: " .. love.filesystem.getSaveDirectory())
    I.script = function() return {} end
    G.switch("fight", { p1ai = true, seed = 7 })
    check(G.sceneName == "fight" and G.scenes.fight.phase == "vs", "fight starts with the VS screen")
end

function A.update()
    t = t + 1
    local F = G.scenes.fight
    if F.phase == "vs" and F.pt == 60 then want = "f1_vs" end
    if F.phase == "intro" and F.round == 1 and F.pt == 70 then want = "f2_round" end
    if F.phase == "fight" then
        for _, e in ipairs(F.fx) do
            if not seen.hit and not e.blue and e.t == 1 then seen.hit = true; want = "f3_hit" end
            if not seen.block and e.blue and e.t == 1 then seen.block = true; want = "f4_block" end
        end
        if not seen.ball and F.proj[1] and F.proj[1].t == 12 then seen.ball = true; want = "f5_ball" end
        local tf = F.f[2]
        if not seen.charge and tf.state == "attack" and tf.mname == "charge" and tf.mt == 14 then seen.charge = true; want = "f6_charge" end
        if not seen.jump and F.f[1].state == "attack" and F.f[1].mname == "jk" and F.f[1].mt == 6 then seen.jump = true; want = "f6b_jumpkick" end
    end
    if F.phase == "ko" and F.pt == 40 and not seen.ko then seen.ko = true; want = "f7_ko" end
    if F.phase == "end" and F.pt == 70 then
        want = "f8_end"
        local s = F.stats
        check(s.hits[1] > 0 and s.hits[2] > 0, ("both fighters land hits (%d / %d)"):format(s.hits[1], s.hits[2]))
        check(s.blocks[1] + s.blocks[2] > 0, ("blocks happen (%d / %d)"):format(s.blocks[1], s.blocks[2]))
        check(s.specials[1] > 0, "the Nonno throws the volleyball special (" .. s.specials[1] .. ")")
        check(s.specials[2] > 0, "the Toro uses the charge special (" .. s.specials[2] .. ")")
        check(s.rounds >= 2, "at least two rounds (" .. s.rounds .. ")")
        local w1, w2 = F.f[1].wins, F.f[2].wins
        check(math.max(w1, w2) == 2 or s.rounds == 5, ("match ends best of 3 (%d-%d)"):format(w1, w2))
        check(seen.hit and seen.ko, "hit sparks and a K.O. were shown")
    end
    if F.phase == "end" and F.pt == 80 then
        print(fails == 0 and "all checks passed" or (fails .. " checks failed"))
        love.event.quit(fails == 0 and 0 or 1)
    end
    if t > 60 * 60 * 8 then
        check(false, "match finished within 8 minutes")
        love.event.quit(1)
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
