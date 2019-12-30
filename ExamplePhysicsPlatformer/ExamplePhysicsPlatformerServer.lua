Game = require('../server', { root = true }) -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsPlatformerCommon'


-- Start / stop

function Game.Server:start()
    Game.Common.start(self)


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
        local bodyId = self.physics:newBody(worldId, math.random(70, 800 - 70), math.random(70, 70), 'dynamic')
        local fixtureId = self.physics:newFixture(bodyId, shapeId, 1)
        self.physics:destroyObject(shapeId)
        self.physics:setFriction(fixtureId, 0.2)
        self.physics:setLinearDamping(bodyId, 1.2)
    end

    -- for i = 1, 10 do -- Rectangles
    --     local s = math.random(20, 30)
    --     createDynamicBody(self.physics:newRectangleShape(s, s))
    -- end
    for i = 1, 3 do -- Circles
        createDynamicBody(self.physics:newCircleShape(math.random(10, 20)))
    end
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
    local shapeId = self.physics:newRectangleShape(32, 90)
    local fixtureId = self.physics:newFixture(bodyId, shapeId, 0)
    self.physics:setFriction(fixtureId, 0.4)
    self.physics:setLinearDamping(bodyId, 2.8)
    self.physics:setFixedRotation(bodyId, true)
    self.physics:setOwner(bodyId, clientId, true)
    self:send('addPlayer', clientId, bodyId)

    -- Try having client own everything
    -- local worldId, world = self.physics:getWorld()
    -- for _, body in ipairs(world:getBodies()) do
    --     self.physics:setOwner(self.physics:idForObject(body), clientId)
    -- end
end

function Game.Server:disconnect(clientId)
end


-- Update

function Game.Server:update(dt)
    -- Common update
    Game.Common.update(self, dt)

    -- Send physics syncs
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:sendSyncs(worldId)
    end
end
