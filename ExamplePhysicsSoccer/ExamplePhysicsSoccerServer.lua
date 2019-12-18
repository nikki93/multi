Game = require('../server', { root = true }) -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsSoccerCommon'


-- Start / stop

function Game.Server:start()
    Game.Common.start(self)


    local worldId = self.physics:newWorld(0, 0, true)


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

    createWall(wallThickness / 2, 450 / 10, wallThickness, 450 / 2)
    createWall(800 - wallThickness / 2, 450 / 10, wallThickness, 450 / 2)
    createWall(wallThickness / 2, 450 - 450 / 10, wallThickness, 450 / 2)
    createWall(800 - wallThickness / 2, 450 - 450 / 10, wallThickness, 450 / 2)


    -- Corners

    local function createCorner(x, y)
        local bodyId = self.physics:newBody(worldId, x, y)
        local shapeId = self.physics:newPolygonShape(
            0, -2 * wallThickness,
            2 * wallThickness, 0,
            0, 2 * wallThickness,
            -2 * wallThickness, 0)
        local fixtureId = self.physics:newFixture(bodyId, shapeId)
        self.physics:destroyObject(shapeId)
    end

    createCorner(wallThickness, wallThickness)
    createCorner(800 - wallThickness, wallThickness)
    createCorner(800 - wallThickness, 450 - wallThickness)
    createCorner(wallThickness, 450 - wallThickness)


    -- Dynamic bodies

    local function createDynamicBody(shapeId)
        local bodyId = self.physics:newBody(worldId, 800 / 2, 450 / 2, 'dynamic')
        local fixtureId = self.physics:newFixture(bodyId, shapeId, 1)
        self.physics:destroyObject(shapeId)
        self.physics:setFriction(fixtureId, 1.2)
        self.physics:setRestitution(fixtureId, 0.8)
        self.physics:setLinearDamping(bodyId, 0.8)
        return bodyId
    end

    self.ballBodyId = createDynamicBody(self.physics:newCircleShape(15))
end


-- Connect / disconnect

function Game.Server:connect(clientId)
    local function send(kind, ...) -- Shorthand to send messages to this client only
        self:send({
            kind = kind,
            to = clientId,
            selfSend = false,
            channel = MAIN_RELIABLE_CHANNEL,
        }, ...)
    end

    -- Sync physics (do this before stuff below so that the physics world exists)
    self.physics:syncNewClient({
        clientId = clientId,
        channel = MAIN_RELIABLE_CHANNEL,
    })

    -- Sync mes
    for clientId, me in pairs(self.mes) do
        send('me', clientId, me)
    end

    -- Sync players
    for clientId, player in pairs(self.players) do
        send('addPlayer', clientId, player.bodyId)
    end

    -- Add player body and table entry
    local x, y = math.random(70, 800 - 70), 450 - 70
    local bodyId = self.physics:newBody(self.physics:getWorld(), x, y, 'dynamic')
    local shapeId = self.physics:newRectangleShape(40, 40)
    local fixtureId = self.physics:newFixture(bodyId, shapeId, 0)
    self.physics:setFriction(fixtureId, 1.2)
    self.physics:setLinearDamping(bodyId, 2.8)
    self.physics:setFixedRotation(bodyId, true)
    self.physics:setOwner(bodyId, clientId, true)
    self:send({ kind = 'addPlayer' }, clientId, bodyId)
end

function Game.Server:disconnect(clientId)
end


-- Update

function Game.Server:update(dt)
    -- Common update
    Game.Common.update(self, dt)

    -- Check scoring
    local ballBody = self.physics:objectForId(self.ballBodyId)
    local ballX, ballY = ballBody:getPosition()
    if ballX < 0 or ballX > 800 then
        self.physics:setOwner(self.ballBodyId, nil, false)
        ballBody:setPosition(800 / 2, 450 / 2)
        ballBody:setAngle(0)
        ballBody:setLinearVelocity(0, 0)
        ballBody:setAngularVelocity(0)
    end

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end
