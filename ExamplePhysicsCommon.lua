local Physics = require 'physics' -- You would use the full 'https://...' raw URI to 'physics.lua' here


love.physics.setMeter(64)


MAIN_RELIABLE_CHANNEL = 0
TOUCHES_CHANNEL = 50


-- Define

function GameCommon:define()
    --
    -- User
    --

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })


    --
    -- Touches
    --

    -- We use `forwardToOrigin` (server forwards back to us) rather than `selfSend` (we receive the message
    -- immediately locally -- i.e., prediction) so that we're more aligned with what other clients see

    -- Client tells everyone about a touch press
    self:defineMessageKind('beginTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
    })

    -- Client tells everyone about a touch release
    self:defineMessageKind('endTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
    })

    -- Client tells everyone about touch position updates
    self:defineMessageKind('touchPosition', {
        reliable = false,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
        rate = 30,
    })
end


-- Start / stop

function GameCommon:start()
    self.mes = {}

    self.physics = Physics.new({ game = self })

    self.touches = {}
end


-- Mes

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Touches

function GameCommon.receivers:beginTouch(time, clientId, touchId, x, y, bodyId, localX, localY)
    -- Create touch entry
    local touch = {
        ended = false,
        clientId = clientId,
        x = x,
        y = y,
        localX = localX,
        localY = localY,
        bodyId = bodyId,
        positionHistory = {
            {
                time = time,
                x = x,
                y = y,
            },
        },
    }

    local body = self.physics:objectForId(bodyId)
    if body then
        -- Create local mouse joint
        local worldX, worldY = body:getWorldPoint(localX, localY)
        touch.mouseJoint = love.physics.newMouseJoint(body, worldX, worldY)
    end

    -- Add to tables
    self.touches[touchId] = touch
end

function GameCommon.receivers:endTouch(time, touchId, x, y)
    local touch = self.touches[touchId]
    if touch then
        -- Add the final position
        table.insert(touch.positionHistory, {
            time = time,
            x = x,
            y = y,
        })

        -- We'll actually remove the entry when we exhaust the history while interpolating
        touch.ended = true
    end
end

function GameCommon.receivers:touchPosition(time, touchId, x, y)
    local touch = self.touches[touchId]
    if touch then
        table.insert(touch.positionHistory, {
            time = time,
            x = x,
            y = y,
        })
    end
end


-- Update

function GameCommon:update(dt)
    -- Interpolate touches and move associated mouse joints
    do
        local interpTime = self.time - 0.12
        for touchId, touch in pairs(self.touches) do
            local history = touch.positionHistory

            -- Remove history that won't be needed anymore
            while #history > 2 and history[1].time < interpTime and history[2].time < interpTime do
                table.remove(history, 1)
            end

            -- If touch ended and all events are in the past, remove this touch
            if touch.ended and (#history <= 1 or history[2].time < interpTime) then
                if touch.mouseJoint then -- Destroy mouse joint
                    touch.mouseJoint:destroy()
                end

                self.touches[touchId] = nil
            else
                -- Update position
                if #history >= 2 then
                    -- Have two, interpolate
                    local f = (interpTime - history[1].time) / (history[2].time - history[1].time)

                    if f > 1 then -- If extrapolating, don't go too far
                        f = 1 + 0.2 * (f - 1)
                    end

                    local dx, dy = history[2].x - history[1].x, history[2].y - history[1].y
                    touch.x, touch.y = history[1].x + f * dx, history[1].y + f * dy
                elseif #history == 1 then
                    -- Have only one, just set
                    touch.x, touch.y = history[1].x, history[1].y
                end

                -- Move mouse joint if it has one
                if touch.mouseJoint then
                    touch.mouseJoint:setTarget(touch.x, touch.y)
                end
            end
        end
    end

    -- Update physics with a fixed rate of 144 Hz
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:updateWorld(worldId, dt, 144)
    end
end