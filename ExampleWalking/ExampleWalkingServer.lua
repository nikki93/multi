Game = require('../server', { root = true }) -- You would use the full 'https://...' raw URI to 'server.lua' here


require 'ExampleWalkingCommon'


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

function Game.Server:disconnect(clientId)
    -- Remove player for old client
    self:send('removePlayer', clientId)
end
