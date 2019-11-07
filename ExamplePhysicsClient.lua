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


-- Mouse / touch

function GameClient:mousepressed(x, y, button, isTouch)
    if isTouch then -- Handle through `:touchpressed`
        return
    end

    if button == 1 then
        self:touchpressed('mouse', x, y)
    end
end

function GameClient:mousereleased(x, y, button, isTouch)
    if isTouch then -- Handle through `:touchreleased`
        return
    end

    if button == 1 then
        self:touchreleased('mouse', x, y)
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

function GameClient:touchreleased(loveTouchId, x, y)
    local localTouch = self.localTouches[loveTouchId]
    if localTouch then
        self:send({ kind = 'removeTouch' }, localTouch.touchId, x, y)
        self.localTouches[loveTouchId] = nil
    end
end


-- Draw

function GameClient:draw()
    if self.mainWorld then
        love.graphics.setLineWidth(2)

        local touchLines = {}

        for _, body in ipairs(self.mainWorld:getBodies()) do
            local bodyId = self.physicsObjectToId[body]
            local holderId

            -- Collect touch lines and note holder id
            for touchId, touch in pairs(self.touches) do
                if touch.bodyId == bodyId then
                    holderId = touch.clientId

                    local startX, startY = body:getWorldPoint(touch.localX, touch.localY)

                    local localTouchX, localTouchY
                    for loveTouchId, localTouch in pairs(self.localTouches) do
                        if localTouch.touchId == touchId then
                            if loveTouchId == 'mouse' then
                                localTouchX, localTouchY = love.mouse.getPosition()
                            else
                                localTouchX, localTouchY = love.touch.getPosition(loveTouchId)
                            end
                            break
                        end
                    end

                    table.insert(touchLines, { startX, startY, localTouchX or touch.x, localTouchY or touch.y })
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
                    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                elseif ty == 'chain' then
                    love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
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

        -- Draw touch lines
        love.graphics.setColor(1, 0, 1)
        for _, touchLine in ipairs(touchLines) do
            love.graphics.line(unpack(touchLine))
            love.graphics.circle('fill', touchLine[3], touchLine[4], 5)
        end
    end


    local pingText = ''
    if self.connected then
        pingText = '    ping: ' ..self.client.getPing()
    end

    love.graphics.setColor(0, 0, 0)
    love.graphics.print('fps: ' .. love.timer.getFPS() .. pingText, 22, 2)
end