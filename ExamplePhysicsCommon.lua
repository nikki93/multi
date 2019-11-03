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
                from = 'server',
                to = 'all',
                reliable = true,
                channel = MIN_PHYSICS_CHANNEL,
                selfSend = true,
            })

            if not GameCommon.receivers[kind] then
                GameCommon.receivers[kind] = function(self, time, physicsId, ...)
                    (function (...)
                        self.physicsObjects[physicsId] = love.physics[methodName](...)
                    end)(self:resolvePhysicsIds(...))
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
                        local obj = self.physicsObjects[physicsId]
                        if not obj then
                            error("no / bad `physicsId` given as first parameter to '" .. kind .. "'")
                        end
                        obj[methodName](obj, ...)
                    end)(self:resolvePhysicsIds(...))
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

    self.physicsObjects = {} -- `physicsId` -> `World` / `Body` / `Fixture` / `Shape` / ...

    self.mainWorldId = nil
end


-- Mes

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Physics

function GameCommon:resolvePhysicsIds(...)
    if select('#', ...) == 0 then
        return
    end
    local firstArg = select(1, ...)
    return self.physicsObjects[firstArg] or firstArg, self:resolvePhysicsIds(select(2, ...))
end

function GameCommon.receivers:physics_destroyObject(time, physicsId)
    local obj = self.physicsObjects[physicsId]
    if obj then
        obj:destroy()
    end
end


-- Scene

function GameCommon.receivers:mainWorldId(time, mainWorldId)
    self.mainWorldId = mainWorldId
end


-- Update

function GameCommon:update(dt)
    if self.mainWorldId then
        self.physicsObjects[self.mainWorldId]:update(dt)
    end
end