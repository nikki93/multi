local Physics = require '../physics' -- You would use the full 'https://...' raw URI to 'physics.lua' here


love.physics.setMeter(64)


MAIN_RELIABLE_CHANNEL = 0
TOUCHES_CHANNEL = 50


-- Define

function Game.Common:define()
    --
    -- User
    --

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
        forward = true,
    })

    --
    -- Players
    --

    -- Server sends add or remove player events to all
    self:defineMessageKind('addPlayer', {
        to = 'all',
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
    })
    self:defineMessageKind('removePlayer', {
        to = 'all',
        reliable = true,
        channel = MAIN_RELIABLE_CHANNEL,
        selfSend = true,
    })
end


-- Start / stop

function Game.Common:start()
    self.mes = {}

    self.physics = Physics.new({
        game = self,

        -- Let's send physics reliable messages on the main channel so that we can be sure
        -- the body is available in `addPlayer` receiver etc.
        reliableChannel = MAIN_RELIABLE_CHANNEL,
    })

    self.players = {}
end


-- Mes

function Game.Common.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Players

function Game.Common.receivers:addPlayer(time, clientId, bodyId)
    local player = {
        clientId = clientId,
        bodyId = bodyId,
    }

    self.players[clientId] = player
end

function Game.Common.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end


-- Update

function Game.Common:update(dt)
    -- Update physics
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:updateWorld(worldId, dt)
    end
end
