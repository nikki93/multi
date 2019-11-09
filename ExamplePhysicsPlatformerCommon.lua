local Physics = require 'physics' -- You would use the full 'https://...' raw URI to 'physics.lua' here


love.physics.setMeter(64)


MAIN_RELIABLE_CHANNEL = 0
TOUCHES_CHANNEL = 50


-- Define

function GameCommon:define()
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

function GameCommon:start()
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

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end


-- Players

function GameCommon.receivers:addPlayer(time, clientId, bodyId)
    local player = {
        clientId = clientId,
        bodyId = bodyId,
    }

    self.players[clientId] = player
end

function GameCommon.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end


-- Update

function GameCommon:update(dt)
    -- Update physics with a fixed rate of 144 Hz
    local worldId, world = self.physics:getWorld()
    if worldId then
        self.physics:updateWorld(worldId, dt, 144)
    end
end