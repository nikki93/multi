require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data
    self.photoImages = {}
end


-- Mes

function GameClient:loadPhoto(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end

function GameClient.receivers:me(time, clientId, me)
    GameCommon.receivers.me(self, time, clientId, me)

    self:loadPhoto(clientId)
end


-- Connect / disconnect

function GameClient:connect()
    GameCommon.connect(self)

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Update

function GameClient:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end
end


-- Draw

function GameClient:draw()
end