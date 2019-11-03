love.physics.setMeter(64)


-- Define

function GameCommon:define()
    --
    -- User
    --

    -- Server sends full state to a new client when it connects
    self:defineMessageKind('fullState', {
        reliable = true,
        channel = 0,
        selfSend = false,
    })

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = 0,
        selfSend = true,
        forward = true,
    })

    --
    -- Physics
    --

    local MIN_PHYSICS_CHANNEL = 100

    local function definePhysicsConstructors(methodNames) -- For `love.physics.new<X>`, first arg is new `physicsId`
        for _, methodName in ipairs(methodNames) do
            local kind = 'physics_' .. methodName

            self:defineMessageKind(kind, {
                from = methodName ~= 'newMouseJoint' and 'server' or nil, -- Allow clients to create mouse joints
                to = 'all',
                reliable = true,
                channel = MIN_PHYSICS_CHANNEL,
                selfSend = true,
                forward = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        local obj = love.physics[methodName](...)
                        self.physicsIdToObject[physicsId] = obj
                        self.physicsObjectToId[obj] = physicsId
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
                channel = MIN_PHYSICS_CHANNEL,
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
                        obj[methodName](obj, ...)
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
        to = 'all',
        reliable = true,
        channel = MIN_PHYSICS_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_setOwner', {
        to = 'all',
        reliable = true,
        channel = MIN_PHYSICS_CHANNEL,
        selfSend = true,
        forward = true,
    })

    self:defineMessageKind('physics_serverBodySync', {
        from = 'server',
        channel = MIN_PHYSICS_CHANNEL + 1,
        reliable = false,
        rate = 20,
        selfSend = false,
    })

    self:defineMessageKind('physics_clientBodySync', {
        from = 'client',
        channel = MIN_PHYSICS_CHANNEL + 2,
        reliable = false,
        rate = 35,
        selfSend = false,
        forward = false,
    })

    --
    -- Scene
    --

    self:defineMessageKind('createMainWorld', {
        reliable = true,
        channel = 0,
        forward = false,
        selfSend = false,
    })

    self:defineMessageKind('mainWorldId', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
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

function GameCommon.receivers:physics_destroyObject(time, physicsId)
    local obj = self.physicsIdToObject[physicsId]
    if not obj then
        error("physics_destroyObject: no / bad `physicsId`")
    end

    self.physicsIdToObject[physicsId] = nil
    self.physicsObjectToId[obj] = nil

    obj:destroy()
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

function GameCommon.receivers:physics_serverBodySync(time, bodyId, ...)
    local body = self.physicsIdToObject[bodyId]
    if body then
        self:physics_applyBodySync(body, ...)
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


-- Update

function GameCommon:update(dt)
    if self.mainWorldId then
        self.physicsIdToObject[self.mainWorldId]:update(dt)
    end
end