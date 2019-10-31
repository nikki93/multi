bump = require 'https://raw.githubusercontent.com/kikito/bump.lua/7cae5d1ef796068a185d8e2d0c632a030ac8c148/bump.lua'


PLAYER_SPEED = 170
PLAYER_SIZE = 29

SHOOT_RATE = 8
BULLET_SPEED = 1200
BULLET_LIFETIME = 0.8
BULLET_BOUNCES = 2
BULLET_RADIUS = 2.5
BULLET_DRAW_RADIUS = 3
BULLET_DAMAGE = 15

MIN_WALL_SIZE = 30
MAX_WALL_SIZE = 150
WALL_GRID_SIZE = 30


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

    -- Client sends position and velocity updates for its own player, forwarded to all
    self:defineMessageKind('playerPositionVelocity', {
        reliable = false,
        channel = 1,
        rate = 20,
        selfSend = false,
        forward = true,
    })

    -- Server sends player health updates to all
    self:defineMessageKind('playerHealth', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
    })

    -- Server sends player score updates to all
    self:defineMessageKind('playerScore', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
    })

    -- Server sends player respawn events to all
    self:defineMessageKind('respawnPlayer', {
        to = 'all',
        reliable = true,
        channel = 0,
        selfSend = true,
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

    -- Server sends bullet position and velocity updates to all
    self:defineMessageKind('bulletPositionVelocity', {
        to = 'all',
        reliable = false,
        channel = 3,
        rate = 12,
        selfSend = false,
    })
end


-- Start / stop

function GameCommon:start()
    self.players = {}
    self.mes = {}
    self.bullets = {}

    -- 'bump.lua' world
    self.bumpWorld = bump.newWorld()
end


-- 'bump.lua' colliders -- 'bump.lua' uses top-left corner for position

function GameCommon:addPlayerBump(player)
    self.bumpWorld:add(
        player,
        player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
        PLAYER_SIZE, PLAYER_SIZE)
end

function GameCommon:addBulletBump(bullet)
    self.bumpWorld:add(
        bullet,
        bullet.x - BULLET_RADIUS, bullet.y - BULLET_RADIUS,
        2 * BULLET_RADIUS, 2 * BULLET_RADIUS)
end

function GameCommon:addWallBump(wall)
    self.bumpWorld:add(wall, wall.x, wall.y, wall.width, wall.height)
end

function GameCommon:walkPlayerTo(player, targetX, targetY) -- Move player with collision response
    targetX = math.max(0.5 * PLAYER_SIZE, math.min(targetX, 800 - 0.5 * PLAYER_SIZE))
    targetY = math.max(0.5 * PLAYER_SIZE, math.min(targetY, 450 - 0.5 * PLAYER_SIZE))
    local bumpX, bumpY, cols = self.bumpWorld:move(
        player,
        targetX - 0.5 * PLAYER_SIZE, targetY - 0.5 * PLAYER_SIZE,
        function(_, other)
            if other.type == 'player' then
                return 'slide'
            elseif other.type == 'wall' then
                return 'slide'
            elseif other.type == 'bullet' then
                return 'cross'
            end
        end)
    player.x, player.y = bumpX + 0.5 * PLAYER_SIZE, bumpY + 0.5 * PLAYER_SIZE
end

function GameCommon:moveBullet(bullet, dt) -- Move bullet with collision response, returl collisions
    local targetX, targetY = bullet.x + bullet.vx * dt, bullet.y + bullet.vy * dt
    local bumpX, bumpY, cols = self.bumpWorld:move(
        bullet,
        targetX - BULLET_RADIUS, targetY - BULLET_RADIUS,
        function(_, other)
            if other.type == 'wall' then
                return 'bounce'
            end
            return 'cross'
        end)
    bullet.x, bullet.y = bumpX + BULLET_RADIUS, bumpY + BULLET_RADIUS

    for _, col in ipairs(cols) do -- Update velocity if hit wall
        if col.other.type == 'wall' then
            local bounceX, bounceY = bumpX - col.touch.x, bumpY - col.touch.y
            local bounceLen = math.sqrt(bounceX * bounceX + bounceY * bounceY)
            bullet.vx, bullet.vy = BULLET_SPEED * bounceX / bounceLen, BULLET_SPEED * bounceY / bounceLen
        end
    end

    return cols
end


-- Receivers

function GameCommon.receivers:me(time, clientId, me)
    self.mes[clientId] = me
end

function GameCommon.receivers:addPlayer(time, clientId, x, y, r, g, b)
    local player = {
        type = 'player',
        clientId = clientId,
        x = x,
        y = y,
        r = r,
        g = g,
        b = b,
        health = 100,
        spawnCount = 1,
        score = 0,
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

    self:addPlayerBump(player)
end

function GameCommon.receivers:removePlayer(time, clientId)
    local player = self.players[clientId]
    if player then
        self.bumpWorld:remove(player)
        self.players[clientId] = nil
    end
end

function GameCommon.receivers:playerPositionVelocity(time, clientId, spawnCount, x, y, vx, vy)
    local player = self.players[clientId]
    if player then
        assert(not player.own, 'received `playerPositionVelocity` for own player')

        if player.spawnCount == spawnCount then -- Make sure it's from this lifetime
            -- Insert into history, we'll interpolate in `:update` below
            table.insert(player.history, {
                time = time,
                x = x,
                y = y,
                vx = vx,
                vy = vy,
            })
        end
    end
end

function GameCommon.receivers:playerHealth(time, clientId, health)
    local player = self.players[clientId]
    if player then
        player.health = health
    end
end

function GameCommon.receivers:playerScore(time, clientId, score)
    local player = self.players[clientId]
    if player then
        player.score = score
    end
end

function GameCommon.receivers:respawnPlayer(time, clientId, spawnCount, x, y)
    local player = self.players[clientId]
    if player then
        player.spawnCount = spawnCount

        player.x, player.y = x, y

        self.bumpWorld:update(player, x - 0.5 * PLAYER_SIZE, y - 0.5 * PLAYER_SIZE)

        if player.own then
            -- Own player -- reset velocity
            player.vx, player.vy = 0, 0
        else
            -- Other's player -- reset motion history
            player.history = {}
        end

        player.health = 100
    end
end

function GameCommon.receivers:addBullet(time, clientId, bulletId, x, y, vx, vy)
    local dt = self.time - time

    local bullet = {
        type = 'bullet',
        clientId = clientId,
        x = x + vx * dt,
        y = y + vy * dt,
        vx = vx,
        vy = vy,
    }

    if self.server then -- Server keeps track of lifetime
        bullet.timeLeft = BULLET_LIFETIME
        bullet.bouncesLeft = BULLET_BOUNCES
    end

    self.bullets[bulletId] = bullet

    self:addBulletBump(bullet)
end

function GameCommon.receivers:removeBullet(time, bulletId)
    local bullet = self.bullets[bulletId]
    if bullet then
        self.bumpWorld:remove(bullet)
        self.bullets[bulletId] = nil
    end
end


-- Update

local PLAYER_SPEED = 200

function GameCommon:update(dt)
    -- Interpolate players' positions based on history
    local interpTime = self.time - 0.15 -- Interpolated players are slightly in the past
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

                -- In the interpolation case just set position directly since owning client already computed collisions
                player.x, player.y = history[1].x + f * dx, history[1].y + f * dy
                self.bumpWorld:update(player, player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE)
            elseif #history == 1 then
                -- Have only one before, just extrapolate with velocity
                local idt = interpTime - history[1].time
                local targetX, targetY = history[1].x + history[1].vx * idt, history[1].y + history[1].vy * idt

                -- Here we need to compute collisions since we are extrapolating
                self:walkPlayerTo(player, targetX, targetY)
            end
        end
    end
end