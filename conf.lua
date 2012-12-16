function love.conf(t)
    t.screen.width = 1200
    t.screen.height = 600
    --t.screen.vsync = false -- XXX
    t.title = "simchase"

    -- disable unused modules
    t.modules.joystick = false
    t.modules.mouse = false
    t.modules.sound = true
    t.modules.physics = false
end
