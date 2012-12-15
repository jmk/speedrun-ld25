
--
-- Globals
--
_alive = undefined
_level = undefined

--
-- Functions
--

function reset()
    _alive = true
    _level = 0
end

function drawDebug()
    -- Debug output
    love.graphics.print("Level: " .. _level, 10, 10)

    local status
    if (_alive) then
        status = "ALIVE"
    else
        status = "DEAD"
    end
    love.graphics.print(status, 10, 30)

    love.graphics.setColor(255, 0, 255)
    local width = (love.graphics.getWidth() - 30) * _level
    love.graphics.rectangle("fill", 10, 50, width, 5)
end

--
-- Love entry points
--

function love.load()
    reset()

    -- Graphics setup
    love.graphics.setFont(love.graphics.newFont(18))
end

function love.draw()
    drawDebug()
end

function love.update(dt)
    if (not _alive) then
        return
    end

    local addRate = 0.75
    local subRate = 0.5

    if (love.keyboard.isDown(" ")) then
        _level = _level + (dt * addRate)
    else
        _level = _level - (dt * subRate)
    end

    if (_level < 0) then
        _level = 0
    end

    if (_level >= 1) then
        _alive = false
    end
end

function love.keypressed(key, unicode)
    if (key == "escape") then
        love.event.quit()
    elseif (key == " " and not _alive) then
        -- XXX game restart hack
        reset()
    end
end
