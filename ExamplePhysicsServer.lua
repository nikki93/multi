require 'server' -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsCommon'


-- Start / stop

function GameServer:start()
    GameCommon.start(self)


    local worldId = self:physics_newWorld(0, 0, true)


    -- Walls

    local function createWall(x, y, width, height)
        local bodyId = self:physics_newBody(worldId, x, y)
        local shapeId = self:physics_newRectangleShape(width, height)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
        self:physics_destroyObject(shapeId)
    end

    local wallThickness = 20

    createWall(800 / 2, wallThickness / 2, 800, wallThickness)
    createWall(800 / 2, 450 - wallThickness / 2, 800, wallThickness)
    createWall(wallThickness / 2, 450 / 2, wallThickness, 450)
    createWall(800 - wallThickness / 2, 450 / 2, wallThickness, 450)


    -- Dynamic bodies

    local function createDynamicBody(shapeId)
        local bodyId = self:physics_newBody(worldId, math.random(70, 800 - 70), math.random(70, 450 - 70), 'dynamic')
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1.5)
        self:physics_destroyObject(shapeId)
        self:physics_setRestitution(fixtureId, 0.6)
        self:physics_setAngularDamping(bodyId, 1.6)
        self:physics_setLinearDamping(bodyId, 2.2)
    end

    for i = 1, 80 do -- Small balls
        createDynamicBody(self:physics_newCircleShape(math.random(5, 12)))
    end

    for i = 1, 2 do -- Big boxes
        createDynamicBody(self:physics_newRectangleShape(math.random(90, 120), math.random(200, 300)))
    end


    self:send({ kind = 'mainWorldId' }, worldId)
end


-- Connect / disconnect

function GameServer:connect(clientId)
    local function send(kind, ...) -- Shorthand to send messages to the client that just connected
        self:send({
            kind = kind,

            -- Send only to this client
            to = clientId,
            selfSend = false,

            -- Send everything in order
            channel = MAIN_RELIABLE_CHANNEL,
        }, ...)
    end

    -- Mes
    for clientId, me in pairs(self.mes) do
        send('me', clientId, me)
    end

    -- Physics
    do
        local visited = {}

        local function visit(obj, physicsId) -- Send constructor + setters for this physics object
            if visited[obj] then
                return visited[obj]
            end

            physicsId = physicsId or self.physicsObjectToId[obj] or self:generateId()

            visited[obj] = physicsId

            if obj:typeOf('World') then
                local gravityX, gravityY = obj:getGravity()
                send('physics_newWorld', physicsId, gravityX, gravityY, obj:isSleepingAllowed())
            elseif obj:typeOf('Body') then
                send('physics_newBody', physicsId, visit(obj:getWorld()), obj:getX(), obj:getY(), obj:getType())
                send('physics_setMassData', physicsId, obj:getMassData())
                send('physics_setFixedRotation', physicsId, obj:isFixedRotation())

                send('physics_setAngle', physicsId, obj:getAngle())

                send('physics_setLinearVelocity', physicsId, obj:getLinearVelocity())
                send('physics_setAngularVelocity', physicsId, obj:getAngularVelocity())

                send('physics_setLinearDamping', physicsId, obj:getLinearDamping())
                send('physics_setAngularDamping', physicsId, obj:getAngularDamping())

                send('physics_setAwake', physicsId, obj:isAwake())
                send('physics_setActive', physicsId, obj:isActive())
                send('physics_setBullet', physicsId, obj:isBullet())
                send('physics_setGravityScale', physicsId, obj:getGravityScale())
            elseif obj:typeOf('Fixture') then
                send('physics_newFixture', physicsId, visit(obj:getBody()), visit(obj:getShape()), obj:getDensity())
                send('physics_setFilterData', physicsId, obj:getFilterData())
                send('physics_setFriction', physicsId, obj:getFriction())
                send('physics_setRestitution', physicsId, obj:getRestitution())
                send('physics_setSensor', physicsId, obj:isSensor())
            elseif obj:typeOf('Shape') then
                local shapeType = obj:getType()
                if shapeType == 'circle' then
                    local x, y = obj:getPoint()
                    send('physics_newCircleShape', physicsId, x, y, obj:getRadius())
                elseif shapeType == 'polygon' then
                    send('physics_newPolygonShape', physicsId, obj:getPoints())
                elseif shapeType == 'edge' then
                    send('physics_newEdgeShape', physicsId, obj:getPoints())
                    send('physics_setPreviousVertex', physicsId, obj:getPreviousVertex())
                    send('physics_setNextVertex', physicsId, obj:getNextVertex())
                elseif shapeType == 'chain' then
                    send('physics_newChainShape', physicsId, obj:getPoints())
                    send('physics_setPreviousVertex', physicsId, obj:getPreviousVertex())
                    send('physics_setNextVertex', physicsId, obj:getNextVertex())
                end
            end
            -- TODO(nikki): Handle joints!

            return physicsId
        end

        for physicsId, obj in pairs(self.physicsIdToObject) do -- Visit all physics objects
            visit(obj, physicsId)
        end

        if self.mainWorldId then
            send('mainWorldId', self.mainWorldId)
        end
    end

    -- Touches
    for touchId, touch in pairs(self.touches) do
        send('addTouch',
            touch.clientId, touchId,
            touch.x, touch.y,
            touch.bodyId, touch.localX, touch.localY,
            touch.positionHistory)
    end
end

function GameServer:disconnect(clientId)
end


-- Update

function GameServer:update(dt)
    -- Common update
    GameCommon.update(self, dt)

    -- Send body syncs
    if self.mainWorld then
        for clientId in pairs(self._clientIds) do
            local syncs = {}
            for _, body in ipairs(self.mainWorld:getBodies()) do
                if body:isAwake() then
                    local bodyId = self.physicsObjectToId[body]
                    local ownerId = self.physicsObjectIdToOwnerId[bodyId]
                    if ownerId == nil then -- Clients will send syncs for bodies they own
                        syncs[bodyId] = { self:physics_getBodySync(body) }
                    end
                end
            end
            self:send({
                kind = 'physics_serverBodySyncs',
                to = clientId,
            }, syncs)
        end
    end
end