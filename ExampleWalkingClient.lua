require 'lib.client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExampleWalkingCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data
    self.photoImages = {}
end


-- Utils

function GameClient:loadPhoto(clientId)
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
    self:loadPhoto(clientId)
end

function GameClient.receivers:fullState(time, state)
    -- Read players
    for clientId, player in pairs(state.players) do
        self.players[clientId] = player
    end

    -- Read `me`s and load photos
    for clientId, me in pairs(state.mes) do
        self.mes[clientId] = me

        self:loadPhoto(clientId)
    end
end


-- Update

local PLAYER_SPEED = 200

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

    -- Do common update
    GameCommon.update(self)

    -- Send own player position
    if ownPlayer then
        self:send({
            kind = 'playerPositionVelocity',
        }, self.clientId, ownPlayer.x, ownPlayer.y, ownPlayer.vx, ownPlayer.vy)
    end
end


-- Draw

function GameClient:draw()
    -- Draw players
    for clientId, player in pairs(self.players) do
        if self.photoImages[clientId] then
            local image = self.photoImages[clientId]
            love.graphics.draw(image, player.x - 20, player.y - 20, 0, 40 / image:getWidth(), 40 / image:getHeight())
        else
            love.graphics.rectangle('fill', player.x - 20, player.y - 20, 40, 40)
        end
    end
end