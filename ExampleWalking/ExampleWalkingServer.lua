Game = require('../server', { root = true }) -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExampleWalkingCommon'


-- Start / stop

function Game.Server:start()
    Game.Common.start(self)

    -- Server-local data
    self.disconnectTimes = {}
end


-- Connect / disconnect

function Game.Server:connect(clientId)
    -- Send full state to new client
    self:send({
        to = clientId,
        kind = 'fullState',
    }, {
        players = self.players,
        mes = self.mes,
    })

    -- Add player for new client
    local x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)
    self:send('addPlayer', clientId, x, y)
end

function Game.Server:reconnect(clientId)
    -- Unmark them as disconnected
    self.disconnectTimes[clientId] = nil

    -- Send full state to client
    self:send({
        to = clientId,
        kind = 'fullState',
    }, {
        players = self.players,
        mes = self.mes,
    })
end

function Game.Server:disconnect(clientId)
    local player = self.players[clientId]
    if player then
        -- Don't remove -- just remember the time they disconnected
        self.disconnectTimes[clientId] = self.time

        -- Make sure they stop moving
        self:send({
            to = 'all',
            kind = 'playerPositionVelocity',
            reliable = true,
            selfSend = true,
        }, clientId, player.x, player.y, 0, 0)
    end
end

function Game.Server:update(dt)
    -- Remove players that have stayed disconnected for too long
    for clientId, player in pairs(self.players) do
        if self.disconnectTimes[clientId] and self.time - self.disconnectTimes[clientId] > 60 then
            self:send('removePlayer', clientId)
        end
    end

    Game.Common.update(self, dt)
end
