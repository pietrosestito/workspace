function love.conf(t)
    t.identity = "nonno"
    t.version = "11.5"
    t.window.title = "Il Nonno e la Coppa rubata"
    t.window.width = 640           -- R36S panel: 320x240 x2
    t.window.height = 480
    t.window.resizable = true
    t.window.vsync = 1
    t.modules.physics = false
    t.modules.video = false
end
