require 'server' -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExamplePhysicsCommon'


-- Connect / disconnect

function GameServer:connect(clientId)
    -- Send full state to new client
    self:send({
        to = clientId,
        kind = 'fullState',
    }, {
    })
end

function GameServer:disconnect(clientId)
end


-- Scene

function GameServer.receivers:createMainWorld()
    if self.mainWorldId then
        return
    end

    local worldId = self:physics_newWorld(0, 9.81 * 64, true)

    do -- Ground
        local bodyId = self:physics_newBody(worldId, 800 / 2, 450 - 50 / 2)
        local shapeId = self:physics_newRectangleShape(650, 50)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
    end

    do -- Ball
        local bodyId = self:physics_newBody(worldId, 800 / 2, 450 / 2, 'dynamic')
        local shapeId = self:physics_newCircleShape(20)
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1)
        self:physics_setRestitution(fixtureId, 0.9)
    end

    do -- Ball 2
        local bodyId = self:physics_newBody(worldId, 800 / 2, 0, 'dynamic')
        local shapeId = self:physics_newCircleShape(20)
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1)
        self:physics_setRestitution(fixtureId, 0.9)
        self:physics_setLinearVelocity(bodyId, 0, 200)
    end

    self:send({ kind = 'mainWorldId' }, worldId)
end
