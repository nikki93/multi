PLAYER_SPEED = 170
PLAYER_SIZE = 30

SHOOT_RATE = 5
BULLET_SPEED = 700
BULLET_LIFETIME = 2
BULLET_RADIUS = 5


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

    -- Client sends shoot message to server when it wants to shoot a bullet
    self:defineMessageKind('shoot', {
        reliable = true,
        channel = 2,
        selfSend = false,
        forward = false,
    })

    -- Server sends add or remove bullet events to all
    self:defineMessageKind('addBullet', {
        to = 'all',
        reliable = true,
        channel = 2,
        selfSend = true,
    })
    self:defineMessageKind('removeBullet', {
        to = 'all',
        reliable = true,
        channel = 2,
        selfSend = true,
    })

    -- Server sends bullet position updates to all
    self:defineMessageKind('bulletPosition', {
        to = 'all',
        reliable = false,
        channel = 3,
        rate = 5,
        selfSend = false,
    })
end


-- Start / stop

function GameCommon:start()
    self.players = {}
    self.mes = {}
    self.bullets = {}
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
        -- Other's player -- motion history with interpolation
        player.own = false
        player.history = {}
    end

    self.players[clientId] = player
end

function GameCommon.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end

function GameCommon.receivers:playerPositionVelocity(time, clientId, x, y, vx, vy)
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

function GameCommon.receivers:addBullet(time, clientId, bulletId, x, y, vx, vy)
    local dt = self.time - time
    self.bullets[bulletId] = {
        clientId = clientId,
        x = x + vx * dt,
        y = y + vy * dt,
        vx = vx,
        vy = vy,
        timeLeft = BULLET_LIFETIME,
    }
end

function GameCommon.receivers:removeBullet(time, bulletId)
    self.bullets[bulletId] = nil
end


-- Update

local PLAYER_SPEED = 200

function GameCommon:update(dt)
    -- Interpolate players' positions based on history
    local interpTime = self.time - 0.1 -- Interpolated players are slightly in the past
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

    -- Move bullets
    for bulletId, bullet in pairs(self.bullets) do
        bullet.x, bullet.y = bullet.x + bullet.vx * dt, bullet.y + bullet.vy * dt
    end
end