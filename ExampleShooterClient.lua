require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExampleShooterCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data

    self.photoImages = {}
    self.overlayText = love.graphics.newText(love.graphics.newFont(14))

    self.shotTimer = 0

    self.showDebugInfo = false
end


-- Utils

function GameClient:loadPhotoImage(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Connect / disconnect

function GameClient:connect()
    GameCommon.connect(self)

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Receivers

function GameClient.receivers:me(time, clientId, me)
    GameCommon.receivers.me(self, time, clientId, me)

    -- When we get a `me`, load the photo
    self:loadPhotoImage(clientId)
end

function GameClient.receivers:fullState(time, state)
    -- Read players
    self.players = state.players
    for playerId, player in pairs(self.players) do
        self:addPlayerBump(player)
    end

    -- Read `me`s and load photos -- here we merge because we may have set our own `me` already
    for clientId, me in pairs(state.mes) do
        self.mes[clientId] = me
        self:loadPhotoImage(clientId)
    end

    -- Read bullets
    self.bullets = state.bullets
    for bulletId, bullet in pairs(self.bullets) do
        self:addBulletBump(bullet)
    end

    -- Read walls
    self.walls = state.walls
    for bulletId, wall in pairs(self.walls) do
        self:addWallBump(wall)
    end
end

function GameClient.receivers:bulletPositionVelocity(time, bulletId, x, y, vx, vy)
    local bullet = self.bullets[bulletId]
    if bullet then
        bullet.x, bullet.y, bullet.vx, bullet.vy = x, y, vx, vy
        self.bumpWorld:update(bullet, bullet.x, bullet.y)
        self:moveBullet(bullet, self.time - time)
    end
end


-- Update

function GameClient:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end

    -- Keep a reference to our own player
    local ownPlayer = self.players[self.clientId]

    -- Move own player
    if ownPlayer then
        -- Set velocity based on keys
        ownPlayer.vx, ownPlayer.vy = 0, 0
        if love.keyboard.isDown('left') or love.keyboard.isDown('a') then
            ownPlayer.vx = ownPlayer.vx - PLAYER_SPEED
        end
        if love.keyboard.isDown('right') or love.keyboard.isDown('d') then
            ownPlayer.vx = ownPlayer.vx + PLAYER_SPEED
        end
        if love.keyboard.isDown('up') or love.keyboard.isDown('w') then
            ownPlayer.vy = ownPlayer.vy - PLAYER_SPEED
        end
        if love.keyboard.isDown('down') or love.keyboard.isDown('s') then
            ownPlayer.vy = ownPlayer.vy + PLAYER_SPEED
        end

        -- Move with collision response
        local targetX, targetY = ownPlayer.x + ownPlayer.vx * dt, ownPlayer.y + ownPlayer.vy * dt
        self:walkPlayerTo(ownPlayer, targetX, targetY)
    end

    -- Handle shooting
    if ownPlayer then
        self.shotTimer = self.shotTimer - dt

        if love.mouse.isDown(1) and self.shotTimer <= 0 then
            self.shotTimer = 1 / SHOOT_RATE

            local mouseX, mouseY = love.mouse.getPosition()

            self:send({ kind = 'shoot' }, self.clientId, ownPlayer.x, ownPlayer.y, mouseX,  mouseY)
        end
    end

    -- Move bullets
    for bulletId, bullet in pairs(self.bullets) do
        self:moveBullet(bullet, dt)
    end

    -- Do common update
    GameCommon.update(self, dt)

    -- Send own player position
    if ownPlayer then
        self:send({
            kind = 'playerPositionVelocity',
        }, self.clientId, ownPlayer.spawnCount, ownPlayer.x, ownPlayer.y, ownPlayer.vx, ownPlayer.vy)
    end
end


-- Keyboard

function GameClient:keypressed(key)
    if key == 'return' then
        self.showDebugInfo = not self.showDebugInfo
    end
end


-- Draw

-- Some cool FX

local moonshine = require 'https://raw.githubusercontent.com/nikki93/moonshine/9e04869e3ceaa76c42a69c52a954ea7f6af0469c/init.lua'

local effect

local function setupEffect()
    effect = moonshine(moonshine.effects.glow)
    effect.glow.strength = 1.6
end
setupEffect()

function love.resize()
    setupEffect()
end

local visibilityCanvas = love.graphics.newCanvas()

function GameClient:draw()
    -- Not connected?
    if not self.connected then
        return
    end

    effect(function()
        -- Background
        local STRIP_WIDTH = 800 / 80
        for i = 0, 800 / STRIP_WIDTH do
            local t = 0.1 * i + 1.2 * love.timer.getTime()
            love.graphics.setColor(
                0.08 + 0.06 * (1 + math.sin(t)),
                0.08 + 0.04 * (1 + math.sin(t + 0.4)),
                0.08 + 0.06 * (1 + math.sin(t + 0.8)))
            love.graphics.rectangle('fill', i * STRIP_WIDTH, 0, STRIP_WIDTH, 450)
        end

        -- Draw players
        for clientId, player in pairs(self.players) do
            if self.photoImages[clientId] then
                love.graphics.setColor(1.5 * player.r, 1.5 * player.g, 1.5 * player.b)
                love.graphics.rectangle(
                    'fill',
                    player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
                    PLAYER_SIZE, PLAYER_SIZE, 4)
                love.graphics.setColor(player.r, player.g, player.b)
                local image = self.photoImages[clientId]
                love.graphics.draw(
                    image,
                    player.x - 0.45 * PLAYER_SIZE, player.y - 0.45 * PLAYER_SIZE,
                    0,
                    0.9 * PLAYER_SIZE / image:getWidth(), 0.9 * PLAYER_SIZE / image:getHeight())
            else
                love.graphics.rectangle(
                    'fill',
                    player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
                    PLAYER_SIZE, PLAYER_SIZE)
            end
        end

        -- Draw bullets
        for bulletId, bullet in pairs(self.bullets) do
            local player = self.players[bullet.clientId]
            if player then
                love.graphics.setColor(player.r, player.g, player.b)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.push()
            love.graphics.translate(bullet.x, bullet.y)
            love.graphics.rotate(math.atan2(bullet.vy, bullet.vx))
            love.graphics.ellipse('fill', 0, 0, 3.5 * BULLET_DRAW_RADIUS, 0.6 * BULLET_DRAW_RADIUS)
            love.graphics.pop()
        end

        -- Draw walls
        love.graphics.setLineWidth(3)
        for wallId, wall in pairs(self.walls) do
            love.graphics.setColor(0.9, 0.9, 0.9)
            love.graphics.rectangle('line', wall.x - 0.1, wall.y - 0.1, wall.width + 0.2, wall.height + 0.2, 2)
        end

        -- Draw shadows
        do
            local ownPlayer = self.players[self.clientId]
            if ownPlayer then
                -- We'll do this from multiple light positions
                local function drawShadows(lightX, lightY)
                    for wallId, wall in pairs(self.walls) do
                        local wallPoints = {
                            wall.x, wall.y,
                            wall.x + wall.width, wall.y,
                            wall.x + wall.width, wall.y + wall.height,
                            wall.x, wall.y + wall.height,
                            wall.x, wall.y, -- Repeat for wrapping
                        }
                        for i = 1, #wallPoints - 2, 2 do
                            local uX, uY = wallPoints[i], wallPoints[i + 1]
                            local vX, vY = wallPoints[i + 2], wallPoints[i + 3]
                            local uFarX, uFarY = uX + 1000 * (uX - lightX), uY + 1000 * (uY - lightY)
                            local vFarX, vFarY = vX + 1000 * (vX - lightX), vY + 1000 * (vY - lightY)
                            love.graphics.polygon('fill', uX, uY, uFarX, uFarY, vFarX, vFarY, vX, vY, uX, uY)
                        end
                    end
                end

                local function drawPenumbras(count, offset)
                    for i = 0, count - 1 do
                        local angle = 2 * math.pi / count * i
                        drawShadows(
                            ownPlayer.x + offset * math.cos(angle),
                            ownPlayer.y + offset * math.sin(angle))
                    end
                end

                love.graphics.push('all')
                love.graphics.setBlendMode('multiply', 'premultiplied')

                -- First, lighter shadows from offset positions -- creates penumbra effect
                -- local NUM_OFFSETS = 8
                -- for i = 1, NUM_OFFSETS do
                --     local darkness = 0.9 + (i / NUM_OFFSETS) * 0.1
                --     love.graphics.setColor(darkness, darkness, darkness)
                --     drawPenumbras(8, (i / NUM_OFFSETS) * 0.2 * PLAYER_SIZE)
                -- end

                -- Then, fully dark shadows from player's exact position
                love.graphics.setColor(0, 0, 0)
                drawShadows(ownPlayer.x, ownPlayer.y)

                love.graphics.pop('all')
            end
        end

        -- Draw text overlay
        do
            local textFormat = {}

            -- Score
            local playersByScore = {}
            for clientId, player in pairs(self.players) do
                table.insert(playersByScore, player)
            end
            table.sort(playersByScore, function(a, b)
                if a.score == b.score then
                    return a.clientId > b.clientId
                end
                return a.score > b.score
            end)
            for _, player in ipairs(playersByScore) do
                local username = self.mes[player.clientId] and self.mes[player.clientId].username or '<no name>'

                table.insert(textFormat, { 1.4 * player.r, 1.4 * player.g, 1.4 * player.b })
                table.insert(textFormat, username .. ': ' .. player.score .. '\n')
            end

            -- Debug info
            if self.showDebugInfo then
                table.insert(textFormat, { 1, 1, 1 })
                table.insert(textFormat, '\nfps: ' .. love.timer.getFPS() .. '\n' .. 'ping: ' .. self.client.getPing())
            end

            self.overlayText:setf(textFormat, 800, 'left')
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle(
                'fill',
                10, 10,
                self.overlayText:getWidth() + 20, self.overlayText:getHeight() + 20,
                5)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(self.overlayText, 20, 20)
        end
    end)
end