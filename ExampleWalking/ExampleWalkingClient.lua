Game = Game or {}
require('../client', { root = true }) -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExampleWalkingCommon'


-- Start / stop

function Game.Client:start()
    Game.Common.start(self)

    -- Client-local data
    self.photos = {}
end


-- Utils

function Game.Client:loadPhoto(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photos[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Connect / disconnect

function Game.Client:connect()
    Game.Common.connect(self)

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Receivers

function Game.Client.receivers:me(time, clientId, me)
    Game.Common.receivers.me(self, time, clientId, me)

    -- When we get a `me`, load the photo
    self:loadPhoto(clientId)
end

function Game.Client.receivers:fullState(time, state)
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

function Game.Client:update(dt)
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
    Game.Common.update(self)

    -- Send own player position
    if ownPlayer then
        self:send({
            kind = 'playerPositionVelocity',
        }, self.clientId, ownPlayer.x, ownPlayer.y, ownPlayer.vx, ownPlayer.vy)
    end
end


-- Draw

function Game.Client:draw()
    -- Draw players
    for clientId, player in pairs(self.players) do
        if self.photos[clientId] then
            local photo = self.photos[clientId]
            love.graphics.draw(photo, player.x - 20, player.y - 20, 0, 40 / photo:getWidth(), 40 / photo:getHeight())
        else
            love.graphics.rectangle('fill', player.x - 20, player.y - 20, 40, 40)
        end
    end
end
