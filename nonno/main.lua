-- Il Nonno e la Coppa rubata - Love2D 11.5, retro 320x240 @ 60 Hz.
io.stdout:setvbuf("no")
local R = require("lib.retro")
local T = require("lib.text")
local I = require("lib.input")

G = { scenes = {}, img = {}, frame = 0 }
local STEP = 1 / 60
local acc = 0
local test

-- under test, a Lua error must end the process instead of showing the blue screen
for _, a in ipairs(arg or {}) do
    if a == "--test" then
        function love.errorhandler(msg)
            print("ERROR " .. debug.traceback(tostring(msg), 2))
            os.exit(2)
        end
    end
end

function G.switch(name, ...)
    G.scene = G.scenes[name]
    G.sceneName = name
    G.scene.enter(...)
end

function love.load(args)
    R.init()
    T.init()
    for _, n in ipairs({ "nonno_portrait", "nonno", "crab", "tiles", "bg_sky", "bg_sea", "bg_palms" }) do
        G.img[n] = love.graphics.newImage("assets/" .. n .. ".png")
    end
    G.scenes.story = require("scenes.story")
    G.scenes.level = require("scenes.level")
    for _, a in ipairs(args or {}) do
        if a == "--test" then test = require("test.autotest") end
    end
    G.switch("story")
    if test then test.start() end
end

function love.resize(w, h) R.resize(w, h) end

local function step()
    I.update()
    if I.pressed("select") then R.scanlines = not R.scanlines end
    G.scene.update()
    G.frame = G.frame + 1
    if test then test.update() end
end

function love.update(dt)
    if test then step() return end         -- tests: exactly one step per frame
    acc = math.min(acc + dt, 4 * STEP)
    while acc >= STEP do
        step()
        acc = acc - STEP
    end
end

function love.draw()
    R.begin()
    G.scene.draw()
    if test then test.afterDraw() end
    R.finish()
    I.drawTouch()
end
