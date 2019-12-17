Game = Game or {}
require('../client', { root = true }) -- You would use the full 'https://...' raw URI to 'client.lua' here


require 'ExamplePhysicsDraggingCommon'


-- Start / stop

function Game.Client:start()
    Game.Common.start(self)

    self.photoImages = {}

    -- Client-local touch state
    self.localTouches = {} -- love touch id / 'mouse' -> `touchId`
end


-- Connect / disconnect

function Game.Client:connect()
    Game.Common.connect(self)

    self.connectTime = love.timer.getTime()

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Mes

function Game.Client.receivers:me(time, clientId, me)
    Game.Common.receivers.me(self, time, clientId, me)

    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Update

function Game.Client:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end

    -- Common update
    Game.Common.update(self, dt)

    -- Send touch updates
    for loveTouchId, touchId in pairs(self.localTouches) do
        local x, y
        if loveTouchId == 'mouse' then
            x, y = love.mouse.getPosition()
        else
            x, y = love.touch.getPosition(loveTouchId)
        end
        self:send({ kind = 'touchPosition' }, touchId, x, y)
    end

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end


-- Mouse / touch

function Game.Client:mousepressed(x, y, button, isTouch)
    if isTouch then -- Handle through `:touchpressed`
        return
    end

    if button == 1 then
        self:touchpressed('mouse', x, y)
    end
end

function Game.Client:mousereleased(x, y, button, isTouch)
    if isTouch then -- Handle through `:touchreleased`
        return
    end

    if button == 1 then
        self:touchreleased('mouse', x, y)
    end
end

function Game.Client:touchpressed(loveTouchId, x, y)
    local worldId, world = self.physics:getWorld()
    if world then
        -- Find body under touch
        local body, bodyId
        world:queryBoundingBox(
            x - 1, y - 1, x + 1, y + 1,
            function(fixture)
                -- The query only tests AABB overlap -- check if we've actually touched the shape
                if fixture:testPoint(x, y) then
                    local candidateBody = fixture:getBody()
                    local candidateBodyId = self.physics:idForObject(candidateBody)

                    -- Skip if the body isn't networked
                    if not candidateBodyId then
                        return true
                    end

                    -- Skip if owned by someone else
                    for _, touch in pairs(self.touches) do
                        if touch.bodyId == candidateBodyId and touch.clientId ~= self.clientId then
                            return true
                        end
                    end

                    -- Seems good!
                    body, bodyId = candidateBody, candidateBodyId
                    return false
                end
                return true
            end)

        -- If found, add this touch
        if body then
            local localX, localY = body:getLocalPoint(x, y)
            local touchId = self:generateId()

            self:send({ kind = 'beginTouch' }, self.clientId, touchId, x, y, bodyId, localX, localY)

            self.localTouches[loveTouchId] = touchId
        end
    end
end

function Game.Client:touchreleased(loveTouchId, x, y)
    local touchId = self.localTouches[loveTouchId]
    if touchId then
        self:send({ kind = 'endTouch' }, touchId, x, y)
        self.localTouches[loveTouchId] = nil
    end
end


-- Draw

function Game.Client:draw()
    local worldId, world = self.physics:getWorld()
    if world then
        local touchLines = {}

        for _, body in ipairs(world:getBodies()) do
            local bodyId = self.physics:idForObject(body)
            local holderId

            -- Collect touch lines and note holder id
            for touchId, touch in pairs(self.touches) do
                if touch.bodyId == bodyId then
                    holderId = touch.clientId

                    local startX, startY = body:getWorldPoint(touch.localX, touch.localY)

                    local localTouchX, localTouchY
                    for loveTouchId, candidateTouchId in pairs(self.localTouches) do
                        if candidateTouchId == touchId then
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
        love.graphics.setLineWidth(2)
        love.graphics.setColor(1, 0, 1)
        for _, touchLine in ipairs(touchLines) do
            love.graphics.line(unpack(touchLine))
            love.graphics.circle('fill', touchLine[3], touchLine[4], 5)
        end
    end


    local networkText = ''
    if self.connected then
        local timeSinceConnect = love.timer.getTime() - self.connectTime

        networkText = networkText .. '    ping: ' .. self.client.getPing() .. 'ms'
        networkText = networkText .. '    down: ' .. math.floor(0.001 * (self.client.getENetHost():total_received_data() / timeSinceConnect)) .. 'kbps'
        networkText = networkText .. '    up: ' .. math.floor(0.001 * (self.client.getENetHost():total_sent_data() / timeSinceConnect)) .. 'kbps'
        networkText = networkText .. '    mem: ' .. math.floor(collectgarbage('count') / 1024) .. 'mb'
    end

    love.graphics.setColor(0, 0, 0)
    love.graphics.print('fps: ' .. love.timer.getFPS() .. networkText, 22, 2)
end
