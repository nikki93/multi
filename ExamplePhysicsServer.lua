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
        local shapeId = self:physics_newRectangleShape(800, 50)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
    end

    do -- Left wall
        local bodyId = self:physics_newBody(worldId, 50 / 2, 450 / 2)
        local shapeId = self:physics_newRectangleShape(50, 450)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
    end

    do -- Right wall
        local bodyId = self:physics_newBody(worldId, 800 - 50 / 2, 450 / 2)
        local shapeId = self:physics_newRectangleShape(50, 450)
        local fixtureId = self:physics_newFixture(bodyId, shapeId)
    end

    for i = 1, 10 do -- Balls
        local bodyId = self:physics_newBody(worldId, math.random(70, 800 - 70), math.random(0, 300), 'dynamic')
        local shapeId = self:physics_newCircleShape(20)
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1)
        self:physics_setRestitution(fixtureId, 0.9)
    end

    for i = 1, 10 do -- Boxes
        local bodyId = self:physics_newBody(worldId, math.random(70, 800 - 70), math.random(0, 300), 'dynamic')
        local shapeId = self:physics_newRectangleShape(40, 40)
        local fixtureId = self:physics_newFixture(bodyId, shapeId, 1)
        self:physics_setRestitution(fixtureId, 0.9)
    end

    self:send({ kind = 'mainWorldId' }, worldId)
end


-- Update

function GameServer:update(dt)
    -- Common update
    GameCommon.update(self, dt)

    -- Send body syncs
    if self.mainWorldId then
        for _, body in ipairs(self.physicsIdToObject[self.mainWorldId]:getBodies()) do
            if body:isAwake() then
                local bodyId = self.physicsObjectToId[body]
                local ownerId = self.physicsObjectIdToOwnerId[bodyId]
                for clientId in pairs(self._clientIds) do
                    if clientId ~= ownerId then -- Don't send a sync to the owner of this object
                        self:send({
                            kind = 'physics_serverBodySync',
                            to = clientId,
                        }, bodyId, self:physics_getBodySync(body))
                    end
                end
            end
        end
    end
end