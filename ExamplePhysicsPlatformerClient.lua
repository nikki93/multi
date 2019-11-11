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

    -- Keep a reference to our own player
    local ownPlayer = self.players[self.clientId]
    local ownPlayerBody = ownPlayer and self.physics:objectForId(ownPlayer.bodyId)

    -- Own player walking
    if ownPlayer then
        local left = love.keyboard.isDown('left') or love.keyboard.isDown('a')
        local right = love.keyboard.isDown('right') or love.keyboard.isDown('d')

        if left or right and not (left and right) then
            local MAX_VELOCITY, ACCELERATION = 280, 3200

            local vx, vy = ownPlayerBody:getLinearVelocity()
            if vx < MAX_VELOCITY and right then
                newVx = math.min(MAX_VELOCITY, vx + ACCELERATION * dt)
            end
            if vx > -MAX_VELOCITY and left then
                newVx = math.max(-MAX_VELOCITY, vx - ACCELERATION * dt)
            end

            ownPlayerBody:applyLinearImpulse(newVx - vx, 0)
        end
    end

    -- Own player jumping
    if ownPlayer then
        -- Find out if we're groundd
        local grounded = false
        local x, y = ownPlayerBody:getPosition()
        for _, contact in pairs(ownPlayerBody:getContacts()) do
            local x1, y1, x2, y2 = contact:getPositions()
            if (y1 and y1 > y) or (y2 and y2 > y) then
                grounded = true
                break
            end
        end

        local JUMP_TIMESLOP = 0.1 -- Allow player to be this early in pressing the jump key
        if self.jumpRequestTime and love.timer.getTime() - self.jumpRequestTime < JUMP_TIMESLOP then
            local JUMP_VELOCITY = 900
            local vx, vy = ownPlayerBody:getLinearVelocity()
            if vy > -JUMP_VELOCITY then
                if grounded then
                    ownPlayerBody:applyLinearImpulse(0, -JUMP_VELOCITY - vy)
                    self.jumpRequestTime = nil
                end
            end
        end
    end

    -- Common update
    GameCommon.update(self, dt)

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end


-- Keyboard

function GameClient:keypressed(key)
    if key == 'up' or key == 'return' then
        self.jumpRequestTime = love.timer.getTime()
    end
end


-- Draw

function GameClient:draw()
    do -- Physics wireframes
        local worldId, world = self.physics:getWorld()
        if world then
            for _, body in ipairs(world:getBodies()) do
                local bodyId = self.physics:idForObject(body)

                -- Draw shapes
                for _, fixture in ipairs(body:getFixtures()) do
                    local shape = fixture:getShape()
                    local ty = shape:getType()
                    if ty == 'circle' then
                        love.graphics.circle('line', body:getX(), body:getY(), shape:getRadius())
                    elseif ty == 'polygon' then
                        love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                    elseif ty == 'edge' then
                        love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                    elseif ty == 'chain' then
                        love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
                    end
                end
            end
        end
    end

    do -- Text overlay
        local networkText = ''
        if self.connected then
            local timeSinceConnect = love.timer.getTime() - self.connectTime
            networkText = networkText .. '    ping: ' .. self.client.getPing() .. 'ms'
            networkText = networkText .. '    down: ' .. math.floor(0.001 * (self.client.getENetHost():total_received_data() / timeSinceConnect)) .. 'kbps'
            networkText = networkText .. '    up: ' .. math.floor(0.001 * (self.client.getENetHost():total_sent_data() / timeSinceConnect)) .. 'kbps'
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.print('fps: ' .. love.timer.getFPS() .. networkText, 22, 2)
    end
end