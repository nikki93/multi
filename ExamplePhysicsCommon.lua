-- Define

function GameCommon:define()
    -- Server sends full state to a new client when it connects
    self:defineMessageKind('fullState', {
        reliable = true,
        channel = 0,
        selfSend = false,
    })

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = 0,
        selfSend = true,
        forward = true,
    })
end


-- Start / stop

function GameCommon:start()
    self.mes = {}
end


-- Mes

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Update

function GameCommon:update(dt)
end