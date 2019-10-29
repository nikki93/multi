-- Connect / disconnect

function GameServer:connect(clientId)
    -- Send full state to new client
    self:send({
        clientId = clientId,
        kind = 'fullState',
        channel = 0,
        reliable = true,
        self = false,
    }, {
        players = self.players,
        mes = self.mes,
    })

    -- Add player for new client
    local x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)
    self:send({
        clientId = 'all',
        kind = 'addPlayer',
        channel = 0,
        reliable = true,
        self = true,
    }, clientId, x, y)
end

function GameServer:disconnect(clientId)
    -- Remove player for old client
    self:send({
        clientId = 'all',
        kind = 'removePlayer',
        channel = 0,
        reliable = true,
        self = true,
    }, clientId)
end
