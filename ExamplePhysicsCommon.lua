love.physics.setMeter(64)


MAIN_RELIABLE_CHANNEL = 0

PHYSICS_RELIABLE_CHANNEL = 100
PHYSICS_SERVER_SYNCS_CHANNEL = 101
PHYSICS_CLIENT_SYNCS_CHANNEL = 102

TOUCHES_CHANNEL = 50


-- Define

function GameCommon:define()
    --
    -- User
    --

    -- Server sends full state to a new client when it connects
    self:defineMessageKind('fullState', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = false,
    })

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    --
    -- Physics
    --

    local function definePhysicsConstructors(methodNames) -- For `love.physics.new<X>`, first arg is new `physicsId`
        for _, methodName in ipairs(methodNames) do
            local kind = 'physics_' .. methodName

            self:defineMessageKind(kind, {
                from = 'server',
                to = 'all',
                reliable = true,
                channel = PHYSICS_RELIABLE_CHANNEL,
                selfSend = true,
                forward = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        local obj
                        local succeeded, err = pcall(function(...)
                            obj = love.physics[methodName](...)
                        end, ...)
                        if succeeded then
                            self.physicsIdToObject[physicsId] = obj
                            self.physicsObjectToId[obj] = physicsId
                        else
                            error(kind .. ': ' .. err)
                        end
                    end)(self:physics_resolveIds(...))
                end

                GameCommon[kind] = function(self, ...)
                    local physicsId = self:generateId()
                    self:send({ kind = kind }, physicsId, ...)
                    return physicsId
                end
            end
        end
    end

    definePhysicsConstructors({
        'newBody', 'newChainShape', 'newCircleShape', 'newDistanceJoint',
        'newEdgeShape', 'newFixture', 'newFrictionJoint', 'newGearJoint',
        'newMotorJoint', 'newMouseJoint', 'newPolygonShape', 'newPrismaticJoint',
        'newPulleyJoint', 'newRectangleShape', 'newRevoluteJoint', 'newRopeJoint',
        'newWeldJoint', 'newWheelJoint', 'newWorld',
    })

    local function definePhysicsReliableMethods(methodNames) -- For any `:<foo>` method, first arg is `physicsId` of target
        for _, methodName in ipairs(methodNames) do
            local kind = 'physics_' .. methodName

            self:defineMessageKind(kind, {
                to = 'all',
                reliable = true,
                channel = PHYSICS_RELIABLE_CHANNEL,
                selfSend = true,
                forward = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        local obj = self.physicsIdToObject[physicsId]
                        if not obj then
                            error("no / bad `physicsId` given as first parameter to '" .. kind .. "'")
                        end
                        local succeeded, err = pcall(function(...)
                            obj[methodName](obj, ...)
                        end, ...)
                        if not succeeded then
                            error(kind .. ': ' .. err)
                        end
                    end)(self:physics_resolveIds(...))
                end

                GameCommon[kind] = function(self, ...)
                    self:send({ kind = kind }, ...)
                end
            end
        end
    end

    definePhysicsReliableMethods({
        -- Setters
        'setActive', 'setAngle', 'setAngularDamping', 'setAngularOffset',
        'setAngularVelocity', 'setAwake', 'setBullet', 'setCategory',
        'setContactFilter', 'setCorrectionFactor', 'setDampingRatio', 'setDensity',
        'setEnabled', 'setFilterData', 'setFixedRotation', 'setFrequency',
        'setFriction', 'setGravity', 'setGravityScale', 'setGroupIndex', 'setInertia',
        'setLength', 'setLimits', 'setLimitsEnabled', 'setLinearDamping',
        'setLinearOffset', 'setLinearVelocity', 'setLowerLimit', 'setMask', 'setMass',
        'setMassData', 'setMaxForce', 'setMaxLength', 'setMaxMotorForce',
        'setMaxMotorTorque', 'setMaxTorque', 'setMotorEnabled', 'setMotorSpeed',
        'setNextVertex', 'setPoint', 'setPosition', 'setPreviousVertex', 'setRadius',
        'setRatio', 'setRestitution', 'setSensor', 'setSleepingAllowed',
        'setSpringDampingRatio', 'setSpringFrequency', 'setTangentSpeed', 'setTarget',
        'setType', 'setUpperLimit', 'setX', 'setY',
    })

    self:defineMessageKind('physics_destroyObject', {
        from = 'server',
        to = 'all',
        reliable = true,
        channel = PHYSICS_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_setOwner', {
        to = 'all',
        reliable = true,
        channel = PHYSICS_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_serverBodySyncs', {
        from = 'server',
        channel = PHYSICS_SERVER_SYNCS_CHANNEL,
        reliable = false,
        rate = 20,
        selfSend = false,
    })

    self:defineMessageKind('physics_clientBodySync', {
        from = 'client',
        channel = PHYSICS_CLIENT_SYNCS_CHANNEL,
        reliable = false,
        rate = 30,
        selfSend = false,
        forward = true,
    })

    --
    -- Scene
    --

    -- Client receives `physicsId` of the world
    self:defineMessageKind('mainWorldId', {
        to = 'all',
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
    })

    --
    -- Touches
    --

    -- Client tells everyone about a touch press
    self:defineMessageKind('addTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
    })

    -- Client tells everyone about a touch release -- `forwardToOrigin` rather than `selfSend` to be
    -- more aligned with what others see
    self:defineMessageKind('removeTouch', {
        reliable = true,
        channel = TOUCHES_CHANNEL,
        forward = true,
        forwardToOrigin = true,
        selfSend = false,
    })

    -- Client tells everyone about touch position updates -- `forwardToOrigin` rather than `selfSend` to be
    -- more aligned with what others see
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

    self.physicsIdToObject = {} -- `physicsId` -> `World` / `Body` / `Fixture` / `Shape` / ...
    self.physicsObjectToId = {}

    self.physicsObjectIdToOwnerId = {} -- `physicsId` -> `clientId`
    self.physicsOwnerIdToObjectIds = {} -- `clientId` -> `physicsId` -> `true`
    setmetatable(self.physicsOwnerIdToObjectIds, {
        __index = function(t, k)
            local v = {}
            t[k] = v
            return v
        end,
    })

    self.mainWorldId = nil

    self.touches = {}
end


-- Mes

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Physics

function GameCommon:physics_resolveIds(...)
    if select('#', ...) == 0 then
        return
    end
    local firstArg = select(1, ...)
    return self.physicsIdToObject[firstArg] or firstArg, self:physics_resolveIds(select(2, ...))
end

function GameCommon:physics_destroyObject(physicsId)
    self:send({ kind = 'physics_destroyObject' }, physicsId)
end

function GameCommon.receivers:physics_destroyObject(time, physicsId)
    local obj = self.physicsIdToObject[physicsId]
    if not obj then
        error("physics_destroyObject: no / bad `physicsId`")
    end

    -- TODO(nikki): Destroy attached fixtures and joints if it's a body

    self.physicsIdToObject[physicsId] = nil
    self.physicsObjectToId[obj] = nil

    if obj.destroy then
        obj:destroy()
    else
        obj:release()
    end
end

function GameCommon.receivers:physics_setOwner(time, physicsId, newOwnerId)
    local currentOwnerId = self.physicsObjectIdToOwnerId[physicsId]
    if newOwnerId == nil then -- Removing owner
        if currentOwnerId == nil then
            return
        else
            self.physicsObjectIdToOwnerId[physicsId] = nil
            self.physicsOwnerIdToObjectIds[currentOwnerId][physicsId] = nil
        end
    else -- Setting owner
        if currentOwnerId ~= nil then -- Already owned by someone?
            if currentOwnerId == newOwnerId then
                return -- Already owned by this client, nothing to do
            else
                error("physics_setOwner: object already owned by different client")
            end
        end

        self.physicsObjectIdToOwnerId[physicsId] = newOwnerId
        self.physicsOwnerIdToObjectIds[newOwnerId][physicsId] = true
    end
end

function GameCommon:physics_getBodySync(body)
    local x, y = body:getPosition()
    local vx, vy = body:getLinearVelocity()
    local a = body:getAngle()
    local va = body:getAngularVelocity()
    return x, y, vx, vy, a, va
end

function GameCommon:physics_applyBodySync(body, x, y, vx, vy, a, va)
    body:setPosition(x, y)
    body:setLinearVelocity(vx, vy)
    body:setAngle(a)
    body:setAngularVelocity(va)
end

function GameCommon.receivers:physics_serverBodySyncs(time, syncs)
    for bodyId, sync in pairs(syncs) do
        local body = self.physicsIdToObject[bodyId]
        if body then
            self:physics_applyBodySync(body, unpack(sync))
        end
    end
end

function GameCommon.receivers:physics_clientBodySync(time, bodyId, ...)
    local body = self.physicsIdToObject[bodyId]
    if body then
        self:physics_applyBodySync(body, ...)
    end
end


-- Scene

function GameCommon.receivers:mainWorldId(time, mainWorldId)
    self.mainWorldId = mainWorldId
end


-- Touches

function GameCommon.receivers:addTouch(time, clientId, touchId, x, y, bodyId, localX, localY)
    -- Create touch entry
    local touch = {
        finished = false,
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

    local body = self.physicsIdToObject[bodyId]
    if body then
        -- Create mouse joint
        local worldX, worldY = body:getWorldPoint(localX, localY)
        touch.mouseJoint = love.physics.newMouseJoint(body, worldX, worldY)
    end

    -- Add to tables
    self.touches[touchId] = touch
end

function GameCommon.receivers:removeTouch(time, touchId, x, y)
    local touch = self.touches[touchId]
    if touch then
        -- Add the final position
        table.insert(touch.positionHistory, {
            time = time,
            x = x,
            y = y,
        })

        -- We'll actually remove it when we exhaust the history while interpolating
        touch.finished = true
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
    -- Set `self.mainWorld` from `self.mainWorldId`
    if not self.mainWorld then
        if self.mainWorldId then
            self.mainWorld = self.physicsIdToObject[self.mainWorldId]
        end
    end

    -- Interpolate touches and update associated joints
    do
        local interpTime = self.time - 0.1
        for touchId, touch in pairs(self.touches) do
            local history = touch.positionHistory

            -- Remove position if next one is also before interpolation time -- we need one before and one after
            while #history >= 2 and history[1].time < interpTime and history[2].time < interpTime do
                table.remove(history, 1)
            end

            -- If have only one entry left and finished, remove this touch
            if touch.finished and #history <= 1 then
                if touch.mouseJoint then -- Destroy mouse joint
                    touch.mouseJoint:destroy()
                end

                self.touches[touchId] = nil
            else
                -- Update position
                if #history >= 2 then
                    -- Have one before and one after, interpolate
                    local f = (interpTime - history[1].time) / (history[2].time - history[1].time)
                    local dx, dy = history[2].x - history[1].x, history[2].y - history[1].y
                    touch.x, touch.y = history[1].x + f * dx, history[1].y + f * dy
                elseif #history == 1 then
                    -- Have only one before, just set
                    touch.x, touch.y = history[1].x, history[1].y
                end

                -- Update mouse joint if it has one
                if touch.mouseJoint then
                    touch.mouseJoint:setTarget(touch.x, touch.y)
                end
            end
        end
    end

    -- Do a physics step
    if self.mainWorld then
        self.mainWorld:update(dt)
    end
end