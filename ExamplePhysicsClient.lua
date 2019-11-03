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

    -- Common update
    GameCommon.update(self, dt)
end


-- Keyboard

function GameClient:keypressed(key)
    if key == 'space' then
        self:send({ kind = 'createMainWorld' })
    end
end

-- Draw

function GameClient:draw()
    if self.mainWorldId then
        local world = self.physicsObjects[self.mainWorldId]
        for _, body in ipairs(world:getBodies()) do
            for _, fixture in ipairs(body:getFixtures()) do
                local shape = fixture:getShape()
                local ty = shape:getType()
                if ty == 'circle' then
                    love.graphics.circle('fill', body:getX(), body:getY(), shape:getRadius())
                elseif ty == 'polygon' then
                    love.graphics.polygon('fill', body:getWorldPoints(shape:getPoints()))
                elseif ty == 'edge' then
                elseif ty == 'chain' then
                end
            end
        end
    end
end