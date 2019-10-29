require 'lib.client' -- You would use the full 'https://...' raw URI to 'lib/client.lua' here


require 'ExampleShooterCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data

    self.photos = {}

    self.shotTimer = 0
end


-- Utils

function GameClient:loadPhoto(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photos[clientId] = love.graphics.newImage(photoUrl)
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
    self:loadPhoto(clientId)
end

function GameClient.receivers:fullState(time, state)
    -- Read players
    self.players = state.players

    -- Read `me`s and load photos
    self.mes = state.mes
    for clientId, me in pairs(self.mes) do
        self:loadPhoto(clientId)
    end

    -- Read bullets
    self.bullets = state.bullets

    -- Read walls
    self.walls = state.walls
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

        ownPlayer.x, ownPlayer.y = ownPlayer.x + ownPlayer.vx * dt, ownPlayer.y + ownPlayer.vy * dt
    end

    -- Handle shooting
    if ownPlayer then
        self.shotTimer = self.shotTimer - dt

        if love.mouse.isDown(1) and self.shotTimer <= 0 then
            self.shotTimer = 1 / SHOOT_RATE

            local mouseX, mouseY = love.mouse.getPosition()
            local dirX, dirY = mouseX - ownPlayer.x, mouseY - ownPlayer.y

            self:send({ kind = 'shoot' }, self.clientId, ownPlayer.x, ownPlayer.y, dirX, dirY)
        end
    end

    -- Do common update
    GameCommon.update(self, dt)

    -- Send own player position
    if ownPlayer then
        self:send({
            kind = 'playerPositionVelocity',
        }, self.clientId, ownPlayer.x, ownPlayer.y, ownPlayer.vx, ownPlayer.vy)
    end
end


-- Draw

function GameClient:draw()
    -- Not connected?
    if not self.connected then
        return
    end

    -- Draw players
    love.graphics.setColor(1, 1, 1)
    for clientId, player in pairs(self.players) do
        if self.photos[clientId] then
            local photo = self.photos[clientId]
            love.graphics.draw(
                photo,
                player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
                0,
                PLAYER_SIZE / photo:getWidth(), PLAYER_SIZE / photo:getHeight())
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
        love.graphics.circle('fill', bullet.x, bullet.y, BULLET_RADIUS)
    end

    -- Draw walls
    love.graphics.setColor(1, 1, 1)
    for wallId, wall in pairs(self.walls) do
        love.graphics.rectangle('fill', wall.x, wall.y, wall.width, wall.height)
    end
end