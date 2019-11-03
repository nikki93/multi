require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    self.photoImages = {}

    self.mouseJointId = nil
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

    -- Move mouse joint target
    if self.mouseJointId then
        self:physics_setTarget(self.mouseJointId, love.mouse.getPosition())
    end

    -- Common update
    GameCommon.update(self, dt)

    -- Send body syncs
    for objId in pairs(self.physicsOwnerIdToObjectIds[self.clientId]) do
        local obj = self.physicsIdToObject[objId]
        if obj and obj:typeOf('Body') then
            self:send({
                kind = 'physics_clientBodySync',
            }, objId, self:physics_getBodySync(obj))
        end
    end
end


-- Keyboard

function GameClient:keypressed(key)
    if key == 'space' then
        self:send({ kind = 'createMainWorld' })
    end
end


-- Mouse

function GameClient:mousepressed(x, y, button)
    if button == 1 then
        if self.mainWorldId then
            local body
            self.physicsIdToObject[self.mainWorldId]:queryBoundingBox(
                x - 1, y - 1, x + 1, y + 1,
                function(fixture)
                    body = fixture:getBody()
                    return false
                end)
            if body then
                local bodyId = self.physicsObjectToId[body]
                local ownerId = self.physicsObjectIdToOwnerId[bodyId]
                if not (ownerId ~= nil and ownerId ~= self.clientId) then
                    self:send({
                        kind = 'physics_setOwner',
                    }, bodyId, self.clientId)
                    self.mouseJointId = self:physics_newMouseJoint(bodyId, x, y)
                end
            end
        end
    end
end

function GameClient:mousereleased(x, y, button)
    if button == 1 then
        if self.mouseJointId then
            local body = self.physicsIdToObject[self.mouseJointId]:getBodies()
            local bodyId = self.physicsObjectToId[body]
            self:send({
                kind = 'physics_setOwner',
            }, bodyId, nil)
            self:send({
                kind = 'physics_destroyObject',
            }, self.mouseJointId)
            self.mouseJointId = nil
        end
    end
end


-- Draw

function GameClient:draw()
    if self.mainWorldId then
        local world = self.physicsIdToObject[self.mainWorldId]
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