require "gob"
require "sprite"
require "util"

--
-- Globals
--
local _alive
local _elapsed
local _dramaticPause
local _gameOver

local _copSpeed
local _copSpeedCurrent
local _copAccel

local _speed
local _damage
local _accel
local _turnAccel
local _pos

local _lastCarSpawn
local _carSpawnInterval

local _debug = false

--
-- Constants
--
local _dramaticPauseTime = 0.5
local _carSpawnIntervalMax = 0.25
local _carSpeedBase = 100
local _speedFactor = .1 -- increases difficulty
local _copSpeedIncrement = 0.00 -- XXX
local _damageIncrement = 0.15

local _perspOffset = 8
local _roadOffset = 60
local _roadHeight = 120
local _laneCount = 6
local _laneHeight = _roadHeight / _laneCount
local _roadTop = _roadOffset - _perspOffset
local _roadBottom = _roadOffset + _roadHeight
local _roadSpeed = 300

local _width = 400
local _height = 200

--
-- Game entities
--

function makeHitbox(width, perspFudge)
    return {
        x = 8,
        y = _perspOffset + 2,
        w = width - 16,
        h = 12,
    }
end

local _sprites = {
    -- Gameplay
    player = Sprite:new("player.png", {
        hitbox = makeHitbox(32),
        center = { x = 0, y = -3 },
    }),

    -- Background
    bg = Sprite:new("bg.png"),
    fg = Sprite:new("fg.png"),
    cop = Sprite:new("cop.png", {
        hitbox = { x = 0, y = _perspOffset, w = 32, h = 120 },
    }),

    -- Effects
    smoke = Sprite:new("smoke.png"),
    explosion = Sprite:newAnim("explosion.png", 17, {
        center = { x = 8, y = 8 },
    }),
}

local _carSprites = {
    Sprite:new("car.png", {
        hitbox = makeHitbox(32),
    }),
    Sprite:new("bus.png", {
        hitbox = makeHitbox(48),
    }),
    Sprite:new("semi.png", {
        hitbox = makeHitbox(64),
    }),
}

local _bg1 = Gob:new({
    sprite = _sprites.bg
})
local _bg2 = Gob:new({
    sprite = _sprites.bg
})
local _fg1 = Gob:new({
    sprite = _sprites.fg
})
local _fg2 = Gob:new({
    sprite = _sprites.fg
})

local _player = Gob:new({
    x = 0,
    y = 0,
    sprite = _sprites.player,
    smoke1 = love.graphics.newParticleSystem(_sprites.smoke.image, 50),
    smoke2 = love.graphics.newParticleSystem(_sprites.smoke.image, 20),
})

local _cops = Gob:new({
    sprite = _sprites.cop
})

local _lanes = {}

local _numberFont = love.graphics.newImageFont(
    loadImage("numberFont.png"), "1234567890.:")

local _gameOverImage = loadImage("gameover.png")
local _attractModeImage = loadImage("attractMode.png")

local _explosions = {}

--
-- Audio
--

local _sounds = {
    engine = love.audio.newSource("rsrc/engine.mp3", "static"),
    brokenEngine = love.audio.newSource("rsrc/engineBroken.mp3", "static"),
    brokenEngine2 = love.audio.newSource("rsrc/engineBroken2.mp3", "static"),
    brokenEngine3 = love.audio.newSource("rsrc/engineBroken3.mp3", "static"),
    crash = love.audio.newSource("rsrc/crash.mp3", "static"),
    boomEcho = love.audio.newSource("rsrc/boomEcho.mp3", "static"),
}

local _booms = {
}

for i = 1, 10 do
    local b = love.audio.newSource("rsrc/boom.mp3", "static")
    table.insert(_booms, b)
end

_sounds.engine:setLooping(true)
_sounds.brokenEngine:setLooping(true)
_sounds.brokenEngine2:setLooping(true)
_sounds.brokenEngine3:setLooping(true)

--
-- Functions
--

function reset(firstTime)
    _alive = true
    _elapsed = 0
    _dramaticPause = _dramaticPauseTime
    _gameOver = false
    _attractMode = false

    _copSpeed = 0.1
    _copSpeedCurrent = _copSpeed
    _copAccel = 0.1

    _speed = 0.2
    _damage = 0
    _accel = 0.3
    _turnAccel = 0.0
    _pos = 0.0

    _lastCarSpawn = 0
    _carSpawnInterval = 1

    _lanes = {}
    for i = 1, _laneCount do
        table.insert(_lanes, {})
    end

    _cops.alive = true
    _cops.visible = true

    _player.alive = true
    _player.visible = true

    _player.smoke1:stop()
    _player.smoke1:reset()
    _player.smoke2:stop()
    _player.smoke2:reset()

    silence()

    _engineSound = _sounds.engine
    _engineSound:play()

    if (firstTime) then
        -- XXX hacky setup for title screen
        _alive = false
        _gameOver = true
        _attractMode = true

        _cops.alive = false
        _cops.visible = false

        _player.alive = false
        _player.visible = false

        _engineSound:stop()

        -- Spawn a few cars in random locations
        for x = 1, 10 do
            spawnCar(true)
        end
    end
end

function die()
    _alive = false
    _dramaticPause = _dramaticPauseTime
end

function boom()
    if (not _alive) then
        -- Death sequence
        return
    end

    for _, b in pairs(_booms) do
        if (b:isStopped()) then
            b:play()
            return
        end
    end
end

function silence()
    if (_engineSound) then
        _engineSound:stop()
    end 
    for _, b in pairs(_sounds) do
        b:stop()
        b:rewind()
    end
    for _, b in pairs(_booms) do
        b:stop()
        b:rewind()
    end
end

function updateGame(dt)
    _elapsed = _elapsed + dt

    local addRate = 0.5
    local subRate = 0.5

    -- Update player speed
    if (love.keyboard.isDown(" ")) then
        _accel = _accel + (addRate * dt)
        _accel = math.min(1, _accel)
    else
        _accel = _accel - (subRate * dt)
        _accel = math.max(-1, _accel)
    end

    _accel = _accel - _damage / 100

    local maxSpeed = 0.9
    _speed = _speed + (_accel * dt)

    if (_speed > maxSpeed) then
        _speed = maxSpeed
        _accel = 0
    end

    -- Update (vertical) position
    local turnRate = 15
    local maxTurnAccel = 4

    if (love.keyboard.isDown("down")) then
        _turnAccel = _turnAccel + (turnRate * dt)
        _turnAccel = math.min(maxTurnAccel, _turnAccel)
    elseif (love.keyboard.isDown("up")) then
        _turnAccel = _turnAccel - (turnRate * dt)
        _turnAccel = math.max(-maxTurnAccel, _turnAccel)
    else
        -- Return to center
        if (_turnAccel > 0) then
            _turnAccel = _turnAccel - (turnRate * dt * 2)
            _turnAccel = math.max(0, _turnAccel)
        else
            _turnAccel = _turnAccel + (turnRate * dt * 2)
            _turnAccel = math.min(0, _turnAccel)
        end
    end

    _pos = _pos + (_turnAccel * dt)

    -- Keep car on the road
    _pos = clamp(_pos, -1, 1)
    if (_pos >= 1 or _pos <= -1) then
        _turnAccel = 0
    end

    -- Update cops' speed
    if (_copSpeedCurrent < _copSpeed) then
        _copSpeedCurrent = _copSpeedCurrent + (_copAccel * dt)
    end

    -- Update engine sound
    if (_damage > 0) then
        local newSound = _engineSound
        if (_damage < 0.3) then
            newSound = _sounds.brokenEngine
        elseif (_damage < 0.6) then
            newSound = _sounds.brokenEngine2
        else
            newSound = _sounds.brokenEngine3
        end

        if (_engineSound ~= newSound
            and not _engineSound:isPaused()) then
            _engineSound:stop()
            _engineSound = newSound
            _engineSound:play()
        end
    end

    _engineSound:setPitch(1.5 + _damage + (_accel / 2))
end

function updateBg(dt)
    local boost = -_speedFactor * _elapsed
    boost = clamp(0, -2, boost)
    local dx = -_roadSpeed * dt + boost
    local w = _bg1:getWidth()

    _bg1.x = _bg1.x + dx

    if (_bg1.x < -w) then
        _bg1.x = _bg1.x + w
    end

    _bg2.x = _bg1.x + w

    -- Sync foreground to background
    _fg1.x = _bg1.x
    _fg2.x = _bg2.x
end

function updateCars(dt)
    -- Spawn cars
    if (_lastCarSpawn < 0) then
        spawnCar()

        local x = math.min(1.0, _elapsed / 30.0)
        local t = lerp(_carSpawnInterval, _carSpawnIntervalMax, x)
        _lastCarSpawn = math.random() * t

        -- XXX TODO check for collisions
    else
        _lastCarSpawn = _lastCarSpawn - dt
    end

    -- Update cars
    for _, lane in pairs(_lanes) do
        for i, c in pairs(lane) do
            c:update(dt)

            local boost = -_speedFactor * _elapsed
            local dx = c.speed * dt + boost
            c.x = c.x + dx

            if (c.turnAccel) then
                local dy = c.turnSpeed * dt
                c.y = c.y + dy
                c.angle = c.turnSpeed / -540

                c.turnSpeed = c.turnSpeed + c.turnAccel
            end
        end
    end
end

function updateCops(dt)
    _cops.x = _copSpeedCurrent * _width - 32
    _cops.y = _roadOffset - _perspOffset
end

function updateExplosions(dt)
    for i, x in pairs(_explosions) do
        x:update(dt)
        local boost = -_speedFactor * _elapsed
        boost = clamp(0, -2, boost)
        x.x = x.x + (-_roadSpeed * dt) + boost

        -- XXX HACK
        if (x.x < -50) then
            table.remove(_explosions, i)
        end
    end
end

function updatePlayer(dt)
    _player.x = _speed * _width

    local y = (_pos + 1) / 2.0;
    _player.y = lerp(_roadTop, _roadBottom - _player:getHeight(), y)

    -- Update related objects
    _player.smoke1:update(dt)
    _player.smoke1:setPosition(
        _player.x + 8,
        _player.y + 12)
    _player.smoke2:update(dt)
    _player.smoke2:setPosition(
        _player.x + 8,
        _player.y + 12)
end

function checkCollisions()
    -- cops
    if (_alive and _player:hitGob(_cops)) then
        die()
        silence()
    end

    -- cars
    local top = _roadOffset - _laneHeight
    local bottom = _roadOffset + _roadHeight - _laneHeight

    for _, lane in pairs(_lanes) do
        for i, c in pairs(lane) do
            if (c.alive and _player:hitGob(c)) then
                c.alive = false

                if (_alive) then
                    _sounds.crash:play()
                end

                -- Make the car swerve off
                if (_turnAccel == 0) then
                    c.turnAccel = randf(-6.0, 6.0)
                else
                    c.turnAccel = _turnAccel * 3
                end

                c.turnSpeed = _turnAccel * 2

                -- Uh-oh, hit a car, the cops will not be pleased
                _copSpeed = _copSpeed + _copSpeedIncrement
                _damage = _damage + _damageIncrement

                local p = _player.smoke1
                p:start()
                p:setEmissionRate(5 + _damage * 40)
                p:setSpeed(100, 120)
                p:setSpread(math.pi / 15)
                p:setLifetime(-1)
                p:setParticleLife(0.5)
                p:setDirection(math.pi)
                p:setTangentialAcceleration(20, 100)
                p:setSpin(-8, 8)
                p:setSizes(1.0, 2.0)
                p:setColors(255, 255, 255, 224, 58, 128, 255, 0)

                if (_damage > 0.2) then
                    p = _player.smoke2
                    p:start()
                    p:setEmissionRate(1 + _damage * 10)
                    p:setSpeed(80, 90)
                    p:setSpread(math.pi / 15)
                    p:setLifetime(-1)
                    p:setParticleLife(0.75)
                    p:setDirection(math.pi)
                    p:setTangentialAcceleration(20, 100)
                    p:setSpin(-4, 4)
                    p:setSizes(1.0, 3.0)
                    p:setColors(0, 0, 0, 192, 58, 128, 255, 0)
                end
            end

            if (_attractMode) then
                -- Special case for intro; quietly remove when offscreen
                if (c.x + c:getWidth() < 0) then
                    table.remove(lane, i)
                end
            else
                if (c.x <= _cops:getWorldSpaceBbox().br_x) then
                    -- Car intersected with police line
                    c.alive = false
                end

                if (not c.alive and c.visible) then
                    if (c.y < top or c.y > bottom
                        or c.x <= _cops:getWorldSpaceBbox().br_x) then
                        -- Explosions!
                        boom()

                        for i = 1, math.random(8, 10) do
                            spawnExplosion(c.x, c.y, c:getWidth(), c:getHeight())
                        end

                        c.visible = false
                        table.remove(lane, i)
                    end
                end
            end
        end
    end
end

function spawnCar(randomX)
    local x = _width
    local laneIndex = math.random(1, _laneCount)
    local y = (laneIndex - 1) * _laneHeight + _roadOffset

    if (randomX) then
        x = math.random(_width)
    end

    y = y + 2 - _perspOffset -- fudge

    local c = Gob:new({
        x = x,
        y = y,
        sprite = _carSprites[math.random(#_carSprites)],
        speed = -_carSpeedBase
    })

    -- Make sure it doesn't overlap with another car in the same lane
    local lane = _lanes[laneIndex]

    local pad = 5
    local xMin = x - pad
    local xMax = x + c:getWidth() + pad

    for _, otherCar in pairs(lane) do
        if (xMax > otherCar.x
            and xMin < otherCar.x + otherCar:getWidth()) then
            -- Overlap detected; bail
            -- XXX might be better to try and find another lane
            return
        end
    end

    table.insert(lane, c)
end

function spawnExplosion(x, y, w, h)
    local x1 = randf(x, x + w)
    local y1 = randf(y, y + h)

    local x = Gob:new({
        x = x1,
        y = y1,
        sprite = _sprites.explosion,
        fps = 30,
        speed = -_carSpeedBase,
        time = randf(0.0, 1.0),
        angle = randf(0, math.pi * 2)
    })

    table.insert(_explosions, x)
end

function drawDebug()
    if (not _debug) then
        return
    end

    function fmt(n)
        return string.format("%.2f", n)
    end

    love.graphics.push()
    love.graphics.setColor(0, 0, 0)
    love.graphics.setFont(love.graphics.newFont(9))

    -- Debug output
    love.graphics.print(
        "Speed: " .. fmt(_speed)
        .. " Accel: " .. fmt(_accel)
        .. " Damage: " .. fmt(_damage),
        10, 10)
    love.graphics.print(
        "Pos: " .. fmt(_pos)
        .. " Turn: " .. fmt(_turnAccel),
        10, 20)
    love.graphics.print("Time: " .. fmt(_elapsed), 10, 30)

    local status
    if (_alive) then
        status = "ALIVE"
    else
        status = "DEAD"
    end
    love.graphics.print(status, 10, 40)

    -- player speed
    love.graphics.setColor(255, 0, 255)
    local width = (_width - 20) * _speed
    love.graphics.rectangle("fill", 10, 3, width, 5)

    -- min speed
    love.graphics.setColor(0, 255, 255)
    local width = (_width - 20) * _copSpeed
    love.graphics.rectangle("fill", 10, 3, width, 5)

    -- draw hitboxes
    love.graphics.setColor(0, 255, 255, 192)
    for _, lane in pairs(_lanes) do
        for _, c in pairs(lane) do
            c:drawHitbox()
        end
    end
    _player:drawHitbox()
    _cops:drawHitbox()

    love.graphics.pop()
end

function drawExplosions()
    for _, x in pairs(_explosions) do
        x:draw()
    end
end

function drawOverlay()
    love.graphics.push()
    love.graphics.setFont(_numberFont)

    local min = _elapsed / 60
    local sec = _elapsed % 60

    -- XXX hmm, can't get this to work the same way as printf() ...
    local str = ""
    if (min >= 1) then
        str = str .. string.format("%d", min)
    end
    if (sec < 10) then
        str = str .. string.format(":0%.2f", sec)
    else
        str = str .. string.format(":%.2f", sec)
    end

    -- Time overlay
    if (not _attractMode) then
--    local x = (_width - _numberFont:getWidth(str)) / 2
        local x = 160
        love.graphics.print(str, x, 10)
    end

    function drawCentered(img)
        local x = (_width - img:getWidth()) / 2
        local y = (_height - img:getHeight()) / 2
        love.graphics.draw(img, x, y)
    end

    -- Game over?
    if (_gameOver) then
        if (_attractMode) then
            drawCentered(_attractModeImage)
        else
            drawCentered(_gameOverImage)
        end
    end

    love.graphics.pop()
end

function drawPlayer()
    _player:draw()
    love.graphics.draw(_player.smoke1)
    love.graphics.draw(_player.smoke2)
end

--
-- Love entry points
--

function love.load()
    -- Initialize for first-time startup
    reset(true)

    -- Graphics setup
    love.graphics.setFont(love.graphics.newImageFont(
        loadImage("font.png"),
        " abcdefghijklmnopqrstuvwxyz"
        .. "ABCDEFGHIJKLMNOPQRSTUVWXYZ0"
        .. "123456789.,!?-+/():;%&`'*#=[]\""))
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(3.0, 3.0)

    _bg1:draw()
    _bg2:draw()
    _cops:draw()

    -- Cheap-ass depth sort
    local playerDrawn = false
    for i = 1, _laneCount do
        local lane = _lanes[i]

        if (not playerDrawn) then
            local y = _roadHeight / _laneCount * (i-1) + _roadOffset
            if (y > _player:getWorldSpaceBbox().ul_y) then
                drawPlayer()
                playerDrawn = true
            end
        end

        for _, c in pairs(lane) do
            c:draw()
        end
    end

    if (not playerDrawn) then
        drawPlayer()
    end

    _fg1:draw()
    _fg2:draw()

    drawExplosions()
    drawOverlay()

    drawDebug()
    love.graphics.pop()
end

function love.update(dt)
    if (_alive) then
        updateGame(dt)
        updateBg(dt)
        updatePlayer(dt)
        updateCars(dt)
        updateCops(dt)
        updateExplosions(dt)
        checkCollisions()
    elseif (_dramaticPause > 0) then
        _dramaticPause = _dramaticPause - dt
    else
        if (not _gameOver) then
            _gameOver = true

            -- Boom, oom, oom, oom ...
            _sounds.boomEcho:play()

            _player.smoke1:stop()
            _player.smoke2:stop()

            _player.alive = false
            _player.visible = false

            for i = 1, math.random(15, 20) do
                spawnExplosion(
                    _player.x, _player.y,
                    _player:getWidth(), _player:getHeight())
            end
        end

        dt = dt / 4
        updateBg(dt)
        updatePlayer(dt)
        updateCars(dt)
        updateExplosions(dt)
        checkCollisions()
    end
end

function love.keypressed(key, unicode)
    if (key == "escape") then
        love.event.quit()
    elseif (key == "d") then
        _debug = not _debug
    elseif (key == "return" and not _alive) then
        -- XXX game restart hack
        reset()
    end
end
