require 'lib.server' -- You would use the full 'https://...' raw URI to 'lib/server.lua' here


require 'ExampleShooterCommon'


-- Utilities

local function roundTo(value, multiple)
    return math.floor(value / multiple + 0.5) * multiple
end

function GameServer:generatePlayerPosition() -- Generate player position not overlapping anything
    local x, y
    while true do
        x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)
        local hits = self.bumpWorld:queryRect(
            x - 0.5 * PLAYER_SIZE, y - 0.5 * PLAYER_SIZE,
            PLAYER_SIZE, PLAYER_SIZE)
        if #hits == 0 then
            break
        end
    end
    return x, y
end


-- Start / stop

function GameServer:addWall(x, y, width, height)
    local wallId = self:generateId()

    local wall = {
        type = 'wall',
        x = x,
        y = y,
        width = width,
        height = height,
    }

    self.walls[wallId] = wall

    self:addWallBump(wall)
end

function GameServer:start()
    GameCommon.start(self)

    self.walls = {}

    -- -- Generate boundary walls
    self:addWall(-40, -40, 40, 530) -- Left
    self:addWall(800, -40, 40, 530) -- Right
    self:addWall(0, -40, 800, 40) -- Top
    self:addWall(0, 450, 800, 40) -- Bottom

    -- Generate random walls
    for i = 1, 8 do
        local x1, y1 = roundTo(math.random(0, 800), WALL_GRID_SIZE), roundTo(math.random(0, 450), WALL_GRID_SIZE)
        local x2, y2
        local width, height
        while true do
            x2, y2 = roundTo(math.random(0, 800), WALL_GRID_SIZE), roundTo(math.random(0, 450), WALL_GRID_SIZE)
            width, height = math.abs(x1 - x2), math.abs(y1 - y2)
            local area = width * height
            if MIN_WALL_SIZE <= width and width <= MAX_WALL_SIZE and
                MIN_WALL_SIZE <= height and height <= MAX_WALL_SIZE then
                -- Fits our criteria
                break
            end
            -- Doesn't fit, regen
        end
        self:addWall(math.min(x1, x2), math.min(y1, y2), width, height)
    end

    -- Available colors for players
    self.playerColorsAvailable = {
        { 255, 136, 0 },
        { 140, 153, 115 },
        { 0, 217, 87 },
        { 191, 217, 255 },
        { 242, 61, 157 },
    }
end


-- Connect / disconnect

function GameServer:connect(clientId)
    -- Send full state to new client
    self:send({
        to = clientId,
        kind = 'fullState',
    }, {
        players = self.players,
        mes = self.mes,
        bullets = self.bullets,
        walls = self.walls,
    })

    -- Add player for new client

    local r, g, b
    if #self.playerColorsAvailable > 0 then
        local i = math.random(1, #self.playerColorsAvailable)
        local color = table.remove(self.playerColorsAvailable, i)
        r, g, b = color[1] / 255, color[2] / 255, color[3], 255
    else
        r, g, b = 0.4 + 0.8 * math.random(), 0.4 + 0.8 * math.random(), 0.4 + 0.8 * math.random()
    end

    local x, y = self:generatePlayerPosition()
    self:send({ kind = 'addPlayer' }, clientId, x, y, r, g, b)
end

function GameServer:disconnect(clientId)
    -- Remove player for old client
    self:send({ kind = 'removePlayer' }, clientId)
end


-- Receivers

function GameServer.receivers:shoot(time, clientId, x, y, targetX, targetY)
    local player = self.players[clientId]
    if not player then
        return
    end

    local bulletId = self:generateId()

    -- Compromise between server and client player position -- other players are seeing
    -- this player near the server position, while they see themselves at their client
    -- position
    local x, y = 0.5 * (player.x + x), 0.5 * (player.y + y)

    local dirX, dirY = targetX - x, targetY - y
    local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
    dirX, dirY = dirX / dirLen, dirY / dirLen
    local vx, vy = BULLET_SPEED * dirX, BULLET_SPEED * dirY

    self:send({ kind = 'addBullet' }, clientId, bulletId, x, y, vx, vy)
end


-- Update

function GameServer:update(dt)
    -- Do common update
    GameCommon.update(self, dt)

    -- Bullet lifetime
    for bulletId, bullet in pairs(self.bullets) do
        bullet.timeLeft = bullet.timeLeft - dt
        if bullet.timeLeft <= 0 then
            self:send({ kind = 'removeBullet' }, bulletId)
        end
    end

    -- Move bullets, checking player collisions
    for bulletId, bullet in pairs(self.bullets) do
        local cols = self:moveBullet(bullet, dt)

        for _, col in ipairs(cols) do
            local other = col.other
            if other.type == 'wall' then
                bullet.bouncesLeft = bullet.bouncesLeft - 1
                if bullet.bouncesLeft <= 0 then
                    self:send({ kind = 'removeBullet' }, bulletId)
                end
            elseif other.type == 'player' and other.clientId ~= bullet.clientId then
                other.health = other.health - BULLET_DAMAGE
                if other.health > 0 then
                    -- Reduce health of other player
                    self:send({ kind = 'playerHealth' }, other.clientId, other.health)
                else
                    -- Respawn other player
                    local newX, newY = self:generatePlayerPosition()
                    self:send({ kind = 'respawnPlayer' }, other.clientId, other.spawnCount + 1, newX, newY)

                    -- Award shooter
                    local shooter = self.players[bullet.clientId]
                    if shooter then
                        self:send({ kind = 'playerScore' }, shooter.clientId, shooter.score + 1)
                    end
                end

                self:send({ kind = 'removeBullet' }, bulletId)
            end
        end
    end

    -- Send bullet positions
    for bulletId, bullet in pairs(self.bullets) do
        self:send({ kind = 'bulletPositionVelocity' }, bulletId, bullet.x, bullet.y, bullet.vx, bullet.vy)
    end
end
