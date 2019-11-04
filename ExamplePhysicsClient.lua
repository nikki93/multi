local copas = require 'copas'


require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    self.photoImages = {}

    self.mouseJointId = nil
end


-- Connect / disconnect

function GameClient:connect()
    GameCommon.connect(self)

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Full state

function GameClient.receivers:fullState(time, state)
    -- Read `me`s and load photos -- here we merge because we may have set our own `me` already
    for clientId, me in pairs(state.mes) do
        self.mes[clientId] = me
        self:loadPhotoImage(clientId)
    end
end


-- Mes

function GameClient:loadPhotoImage(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end

function GameClient.receivers:me(time, clientId, me)
    GameCommon.receivers.me(self, time, clientId, me)

    self:loadPhotoImage(clientId)
end


-- Update

function GameClient:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end

    -- Move mouse joint target
    if self.mouseJointId then
        self:send({
            kind = 'physics_setTarget',
            reliable = false,
        }, self.mouseJointId, love.mouse.getPosition())
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
    if key == 'return' then
        self:send({ kind = 'createMainWorld' })
    end
end


-- Mouse

function GameClient:mousepressed(x, y, button)
    if button == 1 then
        if self.mainWorld then
            local body
            self.mainWorld:queryBoundingBox(
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

            network.async(function() -- Unset as owner after a slight delay
                copas.sleep(0.8)
                self:send({
                    kind = 'physics_setOwner',
                }, bodyId, nil)
            end)

            self:send({
                kind = 'physics_destroyObject',
            }, self.mouseJointId)
            self.mouseJointId = nil
        end
    end
end


-- Draw

function GameClient:draw()
    if self.mainWorld then
        for _, body in ipairs(self.mainWorld:getBodies()) do
            local bodyId = self.physicsObjectToId[body]
            local ownerId = self.physicsObjectIdToOwnerId[bodyId]

            -- White if no owner, green if owned by us, red if owner by other
            if ownerId then
                if ownerId ~= self.clientId then
                    love.graphics.setColor(1, 0, 0)
                else
                    love.graphics.setColor(0, 1, 0)
                end
            else
                love.graphics.setColor(1, 1, 1)
            end

            -- Draw shapes
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

            -- Draw owner avatar
            if ownerId then
                local image = self.photoImages[ownerId]
                if image then
                    local x, y = body:getPosition()
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.draw(image, x - 15, y - 15, 0, 30 / image:getWidth(), 30 / image:getHeight())
                end
            end
        end
    end
end