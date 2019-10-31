require 'server' -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExampleWalkingCommon'


-- Connect / disconnect

function GameServer:connect(clientId)
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
    self:send({ kind = 'addPlayer' }, clientId, x, y)
end

function GameServer:disconnect(clientId)
    -- Remove player for old client
    self:send({ kind = 'removePlayer' }, clientId)
end
