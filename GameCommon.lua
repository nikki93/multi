-- Define

function GameCommon:define()
    -- Server sends full state to a new client when it connects
    self:defineMessageKind('fullState', {
        channel = 0,
        reliable = true,
        selfSend = false,
    })

    -- Client sends user profile info when it connects, forwarded to all and self
    self:defineMessageKind('me', {
        channel = 0,
        reliable = true,
        selfSend = true,
        forward = true,
    })

    -- Server sends add or remove player events to all
    self:defineMessageKind('addPlayer', {
        to = 'all',
        channel = 0,
        reliable = true,
        selfSend = true,
    })
    self:defineMessageKind('removePlayer', {
        to = 'all',
        channel = 0,
        reliable = true,
        selfSend = true,
    })

    -- Client sends position updates for its own player, forwarded to all
    self:defineMessageKind('playerPosition', {
        reliable = false,
        channel = 1,
        selfSend = false,
        forward = true,
    })
end


-- Start / stop

function GameCommon:start()
    self.players = {}
    self.mes = {}
end


-- Receivers

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end

function GameCommon.receivers:addPlayer(time, clientId, x, y)
    local player = {
        clientId = clientId,
        x = x,
        y = y,
    }

    if self.clientId == clientId then
        -- Own player -- direct motion with velocity
        player.own = true
        player.vx, player.vy = 0, 0
    else
        -- Other's player -- position history with interpolation
        player.own = false
        player.positions = {}
    end

    self.players[clientId] = player
end

function GameCommon.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end

function GameCommon.receivers:playerPosition(time, clientId, x, y)
    local player = self.players[clientId]
    if player then
        assert(not player.own, 'received `playerPosition` for own player')
        table.insert(player.positions, {
            time = time,
            x = x,
            y = y,
        })
    end
end


-- Update

local PLAYER_SPEED = 200

function GameCommon:update(dt)
    -- Interpolate players' positions based on history
    local interpTime = self.time - 0.2 -- Interpolated players are slightly in the past
    for clientId, player in pairs(self.players) do
        if not player.own then -- Own player is directly moved, not interpolated
            local positions = player.positions

            -- Remove position if next one is also before interpolation time -- we need one before and one after
            while #positions >= 2 and positions[1].time < interpTime and positions[2].time < interpTime do
                table.remove(positions, 1)
            end

            if #positions >= 2 then
                -- Have one before and one after, interpolate
                local f = (interpTime - positions[1].time) / (positions[2].time - positions[1].time)
                local dx, dy = positions[2].x - positions[1].x, positions[2].y - positions[1].y
                player.x, player.y = positions[1].x + f * dx, positions[1].y + f * dy
            elseif #positions == 1 then
                -- Have only one before, just set
                player.x, player.y = positions[1].x, positions[1].y
            end
        end
    end
end