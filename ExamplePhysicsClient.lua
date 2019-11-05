local copas = require 'copas'


require 'client' -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    self.photoImages = {}

    -- Client-local touch state
    self.localTouches = {} -- Indexed by love touch id
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

    -- Common update
    GameCommon.update(self, dt)

    -- Send touch updates
    for loveTouchId, localTouch in pairs(self.localTouches) do
        local x, y
        if loveTouchId == 'mouse' then
            x, y = love.mouse.getPosition()
        else
            x, y = love.touch.getPosition(loveTouchId)
        end
        self:send({ kind = 'touchPosition' }, localTouch.touchId, x, y)
        localTouch.prevX, localTouch.prevY = x, y
    end

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


-- Mouse / touch

function GameClient:mousepressed(x, y, button)
    if button == 1 then
        self:touchpressed('mouse', x, y)
    end
end

function GameClient:mousereleased(x, y, button)
    if button == 1 then
        self:touchreleased('mouse')
    end
end

function GameClient:touchpressed(loveTouchId, x, y)
    if self.mainWorld then
        local body, bodyId
        self.mainWorld:queryBoundingBox(
            x - 1, y - 1, x + 1, y + 1,
            function(fixture)
                if fixture:testPoint(x, y) then
                    local candidateBody = fixture:getBody()
                    local candidateBodyId = self.physicsObjectToId[candidateBody]

                    for _, touch in pairs(self.touches) do
                        if touch.bodyId == candidateBodyId and touch.clientId ~= self.clientId then
                            return true
                        end
                    end

                    body, bodyId = candidateBody, candidateBodyId
                    return false
                end
                return true
            end)
        if body then
            local localX, localY = body:getLocalPoint(x, y)
            local touchId = self:generateId()

            self:send({ kind = 'addTouch' }, self.clientId, touchId, x, y, bodyId, localX, localY)

            self.localTouches[loveTouchId] = {
                touchId = touchId,
                prevX = x,
                prevY = y,
            }
        end
    end
end

function GameClient:touchreleased(loveTouchId)
    local localTouch = self.localTouches[loveTouchId]
    if localTouch then
        self:send({ kind = 'removeTouch' }, localTouch.touchId)
        self.localTouches[loveTouchId] = nil
    end
end


-- Draw

function GameClient:draw()
    if self.mainWorld then
        for _, body in ipairs(self.mainWorld:getBodies()) do
            local bodyId = self.physicsObjectToId[body]
            local holderId
            for _, touch in pairs(self.touches) do
                if touch.bodyId == bodyId then
                    holderId = touch.clientId
                    break
                end
            end

            -- White if no holder, green if held by us, red if held by other
            if holderId then
                if holderId ~= self.clientId then
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
            if holderId then
                local image = self.photoImages[holderId]
                if image then
                    local x, y = body:getPosition()
                    love.graphics.setColor(1, 1, 1)
                    love.graphics.draw(image, x - 15, y - 15, 0, 30 / image:getWidth(), 30 / image:getHeight())
                end
            end
        end
    end
end