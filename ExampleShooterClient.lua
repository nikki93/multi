require 'lib.client' -- You would use the full 'https://...' raw URI to 'lib/client.lua' here


require 'ExampleShooterCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data

    self.photoImages = {}
    self.scoreText = love.graphics.newText(love.graphics.newFont(14))

    self.shotTimer = 0
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

function GameClient.receivers:bulletPosition(time, bulletId, x, y)
    local bullet = self.bullets[bulletId]
    if bullet then
        local dt = self.time - time
        bullet.x, bullet.y = x + bullet.vx * dt, y + bullet.vy * dt
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

    -- Move bullets, no collision check (server handles bullet collisions)
    for bulletId, bullet in pairs(self.bullets) do
        bullet.x, bullet.y = bullet.x + bullet.vx * dt, bullet.y + bullet.vy * dt
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
                    player.x - 0.475 * PLAYER_SIZE, player.y - 0.475 * PLAYER_SIZE,
                    0,
                    0.95 * PLAYER_SIZE / image:getWidth(), 0.95 * PLAYER_SIZE / image:getHeight())
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
                love.graphics.setColor(1.4 * player.r, 1.4 * player.g, 1.4 * player.b)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.circle('fill', bullet.x, bullet.y, BULLET_DRAW_RADIUS)
        end

        -- Draw walls
        love.graphics.setLineWidth(3)
        for wallId, wall in pairs(self.walls) do
            love.graphics.setColor(1.4 * wall.r, 1.4 * wall.g, 1.4 * wall.b)
            love.graphics.rectangle('line', wall.x - 0.1, wall.y - 0.1, wall.width + 0.2, wall.height + 0.2, 2)
        end
        for wallId, wall in pairs(self.walls) do
            love.graphics.setColor(0.8 * wall.r, 0.8 * wall.g, 0.8 * wall.b)
            love.graphics.rectangle('fill', wall.x, wall.y, wall.width, wall.height)
        end

        -- Draw score
        do
            local scoreFormat = {}

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

                table.insert(scoreFormat, { 1.4 * player.r, 1.4 * player.g, 1.4 * player.b })
                table.insert(scoreFormat, username .. ': ' .. player.score .. '\n')
            end
            self.scoreText:setf(scoreFormat, 800, 'left')

            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle(
                'fill',
                10, 10,
                self.scoreText:getWidth() + 20, self.scoreText:getHeight() + 20,
                5)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(self.scoreText, 20, 20)
        end
    end)
end