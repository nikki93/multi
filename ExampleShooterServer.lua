require 'lib.server' -- You would use the full 'https://...' raw URI to 'lib/server.lua' here


require 'ExampleShooterCommon'


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
    })

    -- Add player for new client
    local x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)
    self:send({ kind = 'addPlayer' }, clientId, x, y)
end

function GameServer:disconnect(clientId)
    -- Remove player for old client
    self:send({ kind = 'removePlayer' }, clientId)
end


-- Receivers

function GameServer.receivers:shoot(time, clientId, x, y, dirX, dirY)
    local player = self.players[clientId]
    if not player then
        return
    end

    local bulletId = self:generateId()

    local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
    dirX, dirY = dirX / dirLen, dirY / dirLen
    local vx, vy = BULLET_SPEED * dirX, BULLET_SPEED * dirY

    -- Compromise between server and client player position
    local x, y = 0.5 * (player.x + x), 0.5 * (player.y + y)

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

    -- Send bullet positions
    for bulletId, bullet in pairs(self.bullets) do
        self:send({ kind = 'bulletPosition' }, bulletId, bullet.x, bullet.y)
    end
end
