function love.conf(t)
    t.screen.width = 1024
    t.screen.height = 768
    t.screen.fullscreen = true
    --t.screen.vsync = false -- XXX
    t.title = "speedrun"

    -- disable unused modules
    t.modules.joystick = false
    t.modules.mouse = false
    t.modules.sound = true
    t.modules.physics = false
end
