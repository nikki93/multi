-- Define

function Game.Common:define()
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

    -- Server sends add or remove player events to all
    self:defineMessageKind('addPlayer', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
    })
    self:defineMessageKind('removePlayer', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
    })

    -- Client sends position updates for its own player, forwarded to all
    self:defineMessageKind('playerPositionVelocity', {
        reliable = false,
        channel = 1,
        rate = 20,
        selfSend = false,
        forward = true,
    })
end


-- Start / stop

function Game.Common:start()
    self.players = {}
    self.mes = {}
end


-- Receivers

function Game.Common.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end

function Game.Common.receivers:addPlayer(time, clientId, x, y)
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
        -- Other's player -- motion history with interpolation
        player.own = false
        player.history = {}
    end

    self.players[clientId] = player
end

function Game.Common.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end

function Game.Common.receivers:playerPositionVelocity(time, clientId, x, y, vx, vy)
    local player = self.players[clientId]
    if player then
        assert(not player.own, 'received `playerPositionVelocity` for own player')
        table.insert(player.history, {
            time = time,
            x = x,
            y = y,
            vx = vx,
            vy = vy,
        })
    end
end


-- Update

local PLAYER_SPEED = 200

function Game.Common:update(dt)
    -- Interpolate players' positions based on history
    local interpTime = self.time - 0.2 -- Interpolated players are slightly in the past
    for clientId, player in pairs(self.players) do
        if not player.own then -- Own player is directly moved, not interpolated
            local history = player.history

            -- Remove position if next one is also before interpolation time -- we need one before and one after
            while #history >= 2 and history[1].time < interpTime and history[2].time < interpTime do
                table.remove(history, 1)
            end

            if #history >= 2 then
                -- Have one before and one after, interpolate
                local f = (interpTime - history[1].time) / (history[2].time - history[1].time)
                local dx, dy = history[2].x - history[1].x, history[2].y - history[1].y
                player.x, player.y = history[1].x + f * dx, history[1].y + f * dy
            elseif #history == 1 then
                -- Have only one before, just extrapolate with velocity
                local idt = interpTime - history[1].time
                player.x, player.y = history[1].x + history[1].vx * idt, history[1].y + history[1].vy * idt
            end
        end
    end
end
