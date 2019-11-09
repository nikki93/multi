require 'server' -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsPlatformerCommon'


-- Start / stop

function GameServer:start()
    GameCommon.start(self)


    local worldId = self.physics:newWorld(0, 32 * 64, true)


    -- Walls

    local function createWall(x, y, width, height)
        local bodyId = self.physics:newBody(worldId, x, y)
        local shapeId = self.physics:newRectangleShape(width, height)
        local fixtureId = self.physics:newFixture(bodyId, shapeId)
        self.physics:destroyObject(shapeId)
    end

    local wallThickness = 20

    createWall(800 / 2, wallThickness / 2, 800, wallThickness)
    createWall(800 / 2, 450 - wallThickness / 2, 800, wallThickness)
    createWall(wallThickness / 2, 450 / 2, wallThickness, 450)
    createWall(800 - wallThickness / 2, 450 / 2, wallThickness, 450)


    -- Dynamic bodies

    local function createDynamicBody(shapeId)
        local bodyId = self.physics:newBody(worldId, math.random(70, 800 - 70), math.random(70, 450 - 70), 'dynamic')
        local fixtureId = self.physics:newFixture(bodyId, shapeId, 1.5)
        self.physics:destroyObject(shapeId)
        self.physics:setRestitution(fixtureId, 0.6)
    end

    for i = 1, 20 do -- Small balls
        createDynamicBody(self.physics:newCircleShape(math.random(5, 12)))
    end
end


-- Connect / disconnect

function GameServer:connect(clientId)
    local function send(kind, ...) -- Shorthand to send messages to this client only
        self:send({
            kind = kind,
            to = clientId,
            selfSend = false,
            channel = MAIN_RELIABLE_CHANNEL,
        }, ...)
    end

    -- Sync mes
    for clientId, me in pairs(self.mes) do
        send('me', clientId, me)
    end

    -- Sync physics (do this before stuff below so that the physics world exists)
    self.physics:syncNewClient({
        clientId = clientId,
        channel = MAIN_RELIABLE_CHANNEL,
    })

    -- Add player body and table entry
    local x, y = math.random(70, 800 - 70), 450 - 70
    local bodyId = self.physics:newBody(self.physics:getWorld(), x, y, 'dynamic')
    local shapeId = self.physics:newRectangleShape(32, 90)
    local fixtureId = self.physics:newFixture(bodyId, shapeId, 0)
    self.physics:setFriction(fixtureId, 0.4)
    self.physics:setLinearDamping(bodyId, 2.8)
    self.physics:setFixedRotation(bodyId, true)
    self.physics:setOwner(bodyId, clientId)
    self:send({ kind = 'addPlayer' }, clientId, bodyId)
end

function GameServer:disconnect(clientId)
end


-- Update

function GameServer:update(dt)
    -- Common update
    GameCommon.update(self, dt)

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end
