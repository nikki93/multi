Game = require('../server', { root = true }) -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsDraggingCommon'


-- Start / stop

function Game.Server:start()
    Game.Common.start(self)


    local worldId = self.physics:newWorld(0, 9.8 * 64, true)


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

    for i = 1, 80 do -- Small balls
        createDynamicBody(self.physics:newCircleShape(math.random(5, 12)))
    end

    for i = 1, 2 do -- Big boxes
        createDynamicBody(self.physics:newRectangleShape(math.random(90, 120), math.random(200, 300)))
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

    -- Mes
    for clientId, me in pairs(self.mes) do
        send('me', clientId, me)
    end

    -- Physics
    self.physics:syncNewClient({
        clientId = clientId,
        channel = MAIN_RELIABLE_CHANNEL,
    })

    -- Touches
    for touchId, touch in pairs(self.touches) do
        send('beginTouch', touch.clientId, touchId, touch.x, touch.y, touch.bodyId, touch.localX, touch.localY)
    end
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
