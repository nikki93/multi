require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsPlatformerCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    self.photoImages = {}
end


-- Connect / disconnect

function GameClient:connect()
    GameCommon.connect(self)

    self.connectTime = love.timer.getTime()

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Mes

function GameClient.receivers:me(time, clientId, me)
    GameCommon.receivers.me(self, time, clientId, me)

    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Update

function GameClient:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end

    -- Common update
    GameCommon.update(self, dt)

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end


-- Draw

function GameClient:draw()
    local worldId, world = self.physics:getWorld()
    if world then
        for _, body in ipairs(world:getBodies()) do
            local bodyId = self.physics:idForObject(body)

            -- Draw shapes
            for _, fixture in ipairs(body:getFixtures()) do
                local shape = fixture:getShape()
                local ty = shape:getType()
                if ty == 'circle' then
                    love.graphics.circle('fill', body:getX(), body:getY(), shape:getRadius())
                elseif ty == 'polygon' then
                    love.graphics.polygon('fill', body:getWorldPoints(shape:getPoints()))
                elseif ty == 'edge' then
                    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                elseif ty == 'chain' then
                    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                end
            end
        end
    end


    local networkText = ''
    if self.connected then
        local timeSinceConnect = love.timer.getTime() - self.connectTime

        networkText = networkText .. '    ping: ' .. self.client.getPing() .. 'ms'
        networkText = networkText .. '    down: ' .. math.floor(0.001 * (self.client.getENetHost():total_received_data() / timeSinceConnect)) .. 'kbps'
        networkText = networkText .. '    up: ' .. math.floor(0.001 * (self.client.getENetHost():total_sent_data() / timeSinceConnect)) .. 'kbps'
    end

    love.graphics.setColor(0, 0, 0)
    love.graphics.print('fps: ' .. love.timer.getFPS() .. networkText, 22, 2)
end