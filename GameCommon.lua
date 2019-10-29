-- Start / stop

function GameCommon:start()
    self.players = {}
    self.mes = {}

    self:defineMessageKind('fullState')

    self:defineMessageKind('me')

    self:defineMessageKind('addPlayer')
    self:defineMessageKind('removePlayer')
    self:defineMessageKind('playerPosition')
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

    if self.client and clientId == self.clientId then
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
    local interpolatedTime = self.time - 0.2 -- interpolated players are slightly in the past
    for clientId, player in pairs(self.players) do
        if not player.own then -- Own player is moved directly by us, no interpolation
            local positions = player.positions
            while #positions >= 2 and positions[1].time < interpolatedTime and positions[2].time < interpolatedTime do
                -- Remove unnecessary positions
                table.remove(positions, 1)
            end
            if #positions >= 2 then
                -- Interpolate
                local f = (interpolatedTime - positions[1].time) / (positions[2].time - positions[1].time)
                local dx, dy = positions[2].x - positions[1].x, positions[2].y - positions[1].y
                player.x, player.y = positions[1].x + f * dx, positions[1].y + f * dy
            elseif #positions == 1 then
                -- Set
                player.x, player.y = positions[1].x, positions[1].y
            end
        end
    end
end