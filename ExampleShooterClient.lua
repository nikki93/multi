require 'lib.client' -- You would use the full 'https://...' raw URI to 'lib/client.lua' here


require 'ExampleShooterCommon'


-- Start / stop

function GameClient:start()
    GameCommon.start(self)

    -- Client-local data

    self.photoImages = {}
    self.scoreText = love.graphics.newText(love.graphics.newFont(14))

    self.shotTimer = 0
end


-- Utils

function GameClient:loadPhotoImage(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Connect / disconnect

function GameClient:connect()
    GameCommon.connect(self)

    -- Send `me`
    local me = castle.user.getMe()
    self:send({ kind = 'me' }, self.clientId, me)
end


-- Receivers

function GameClient.receivers:me(time, clientId, me)
    GameCommon.receivers.me(self, time, clientId, me)

    -- When we get a `me`, load the photo
    self:loadPhotoImage(clientId)
end

function GameClient.receivers:fullState(time, state)
    -- Read players
    self.players = state.players
    for playerId, player in pairs(self.players) do
        self:addPlayerBump(player)
    end

    -- Read `me`s and load photos -- here we merge because we may have set our own `me` already
    for clientId, me in pairs(state.mes) do
        self.mes[clientId] = me
        self:loadPhotoImage(clientId)
    end

    -- Read bullets
    self.bullets = state.bullets
    for bulletId, bullet in pairs(self.bullets) do
        self:addBulletBump(bullet)
    end

    -- Read walls
    self.walls = state.walls
    for bulletId, wall in pairs(self.walls) do
        self:addWallBump(wall)
    end
end

function GameClient.receivers:bulletPosition(time, bulletId, x, y)
    local bullet = self.bullets[bulletId]
    if bullet then
        local dt = self.time - time
        bullet.x, bullet.y = x + bullet.vx * dt, y + bullet.vy * dt
    end
end


-- Update

function GameClient:update(dt)
    -- Not connected?
    if not self.connected then
        return
    end

    -- Keep a reference to our own player
    local ownPlayer = self.players[self.clientId]

    -- Move own player
    if ownPlayer then
        -- Set velocity based on keys
        ownPlayer.vx, ownPlayer.vy = 0, 0
        if love.keyboard.isDown('left') or love.keyboard.isDown('a') then
            ownPlayer.vx = ownPlayer.vx - PLAYER_SPEED
        end
        if love.keyboard.isDown('right') or love.keyboard.isDown('d') then
            ownPlayer.vx = ownPlayer.vx + PLAYER_SPEED
        end
        if love.keyboard.isDown('up') or love.keyboard.isDown('w') then
            ownPlayer.vy = ownPlayer.vy - PLAYER_SPEED
        end
        if love.keyboard.isDown('down') or love.keyboard.isDown('s') then
            ownPlayer.vy = ownPlayer.vy + PLAYER_SPEED
        end

        -- Move with collision response
        local targetX, targetY = ownPlayer.x + ownPlayer.vx * dt, ownPlayer.y + ownPlayer.vy * dt
        self:walkPlayerTo(ownPlayer, targetX, targetY)
    end

    -- Handle shooting
    if ownPlayer then
        self.shotTimer = self.shotTimer - dt

        if love.mouse.isDown(1) and self.shotTimer <= 0 then
            self.shotTimer = 1 / SHOOT_RATE

            local mouseX, mouseY = love.mouse.getPosition()

            self:send({ kind = 'shoot' }, self.clientId, ownPlayer.x, ownPlayer.y, mouseX,  mouseY)
        end
    end

    -- Move bullets, no collision check (server handles bullet collisions)
    for bulletId, bullet in pairs(self.bullets) do
        bullet.x, bullet.y = bullet.x + bullet.vx * dt, bullet.y + bullet.vy * dt
    end

    -- Do common update
    GameCommon.update(self, dt)

    -- Send own player position
    if ownPlayer then
        self:send({
            kind = 'playerPositionVelocity',
        }, self.clientId, ownPlayer.spawnCount, ownPlayer.x, ownPlayer.y, ownPlayer.vx, ownPlayer.vy)
    end
end


-- Draw

-- Some cool FX

local moonshine = require 'https://raw.githubusercontent.com/nikki93/moonshine/9e04869e3ceaa76c42a69c52a954ea7f6af0469c/init.lua'

local effect

local function setupEffect()
    effect = moonshine(moonshine.effects.glow)
    effect.glow.strength = 1.6
end
setupEffect()

function love.resize()
    setupEffect()
end

local visibilityCanvas = love.graphics.newCanvas()

function GameClient:draw()
    -- Not connected?
    if not self.connected then
        return
    end

    effect(function()
        -- Background
        local STRIP_WIDTH = 800 / 80
        for i = 0, 800 / STRIP_WIDTH do
            local t = 0.1 * i + 1.2 * love.timer.getTime()
            love.graphics.setColor(
                0.08 + 0.06 * (1 + math.sin(t)),
                0.08 + 0.04 * (1 + math.sin(t + 0.4)),
                0.08 + 0.06 * (1 + math.sin(t + 0.8)))
            love.graphics.rectangle('fill', i * STRIP_WIDTH, 0, STRIP_WIDTH, 450)
        end

        -- Draw players
        for clientId, player in pairs(self.players) do
            if self.photoImages[clientId] then
                love.graphics.setColor(1.5 * player.r, 1.5 * player.g, 1.5 * player.b)
                love.graphics.rectangle(
                    'fill',
                    player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
                    PLAYER_SIZE, PLAYER_SIZE, 4)
                love.graphics.setColor(player.r, player.g, player.b)
                local image = self.photoImages[clientId]
                love.graphics.draw(
                    image,
                    player.x - 0.475 * PLAYER_SIZE, player.y - 0.475 * PLAYER_SIZE,
                    0,
                    0.95 * PLAYER_SIZE / image:getWidth(), 0.95 * PLAYER_SIZE / image:getHeight())
            else
                love.graphics.rectangle(
                    'fill',
                    player.x - 0.5 * PLAYER_SIZE, player.y - 0.5 * PLAYER_SIZE,
                    PLAYER_SIZE, PLAYER_SIZE)
            end
        end

        -- Draw bullets
        for bulletId, bullet in pairs(self.bullets) do
            local player = self.players[bullet.clientId]
            if player then
                love.graphics.setColor(1.8 * player.r, 1.8 * player.g, 1.8 * player.b)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.push()
            love.graphics.translate(bullet.x, bullet.y)
            love.graphics.rotate(math.atan2(bullet.vy, bullet.vx))
            love.graphics.ellipse('fill', 0, 0, 3.5 * BULLET_DRAW_RADIUS, 0.6 * BULLET_DRAW_RADIUS)
            love.graphics.pop()
        end

        -- Draw walls
        love.graphics.setLineWidth(3)
        for wallId, wall in pairs(self.walls) do
            love.graphics.setColor(1.4 * wall.r, 1.4 * wall.g, 1.4 * wall.b)
            love.graphics.rectangle('line', wall.x - 0.1, wall.y - 0.1, wall.width + 0.2, wall.height + 0.2, 2)
        end
        for wallId, wall in pairs(self.walls) do
            love.graphics.setColor(0.7 * wall.r, 0.6 * wall.g, 0.8 * wall.b)
            love.graphics.rectangle('fill', wall.x, wall.y, wall.width, wall.height)
        end

        -- Draw shadows
        do
            local ownPlayer = self.players[self.clientId]
            if ownPlayer then
                local visibilityPoints = {}

                local D_ANGLE = 2 * math.pi / 360
                local c = math.cos(D_ANGLE)
                local s = math.sin(D_ANGLE)

                for wallId, wall in pairs(self.walls) do
                    local wallPoints = {
                        { wall.x, wall.y },
                        { wall.x + wall.width, wall.y },
                        { wall.x, wall.y + wall.height },
                        { wall.x + wall.width, wall.y + wall.height },
                    }
                    for _, wallPoint in ipairs(wallPoints) do
                        local dirX, dirY = wallPoint[1] - ownPlayer.x, wallPoint[2] - ownPlayer.y
                        local dirLen = math.sqrt(dirX * dirX + dirY * dirY)
                        dirX, dirY = 1000 * dirX / dirLen, 1000 * dirY / dirLen

                        local dirs = {
                            { c * dirX + s * dirY, -1 * s * dirX + c * dirY },
                            { dirX, dirY },
                            { c * dirX - s * dirY, s * dirX + c * dirY },
                        }

                        for i, dir in ipairs(dirs) do
                            dirX, dirY = dir[1], dir[2]

                            local targetX, targetY = ownPlayer.x + dirX, ownPlayer.y + dirY
                            local items = self.bumpWorld:querySegmentWithCoords(
                                ownPlayer.x, ownPlayer.y,
                                targetX, targetY, function(other)
                                    return other.type == 'wall'
                                end)

                            local hitX, hitY
                            if #items > 0 then
                                hitX, hitY = items[1].x1, items[1].y1
                            end

                            if hitX and hitY then
                                local hitDX, hitDY = hitX - ownPlayer.x, hitY - ownPlayer.y
                                local hitLen = math.sqrt(hitDX * hitDX + hitDY * hitDY)

                                if i == 2 and hitLen > dirLen then
                                    table.insert(visibilityPoints, wallPoint)
                                else
                                    table.insert(visibilityPoints, { hitX, hitY })
                                end
                            else
                                table.insert(visibilityPoints, wallPoint)
                            end
                        end
                    end
                end
                table.sort(visibilityPoints, function(p1, p2)
                    local angle1 = math.atan2(p1[2] - ownPlayer.y, p1[1] - ownPlayer.x)
                    local angle2 = math.atan2(p2[2] - ownPlayer.y, p2[1] - ownPlayer.x)
                    return angle1 < angle2
                end)

                visibilityCanvas:renderTo(function()
                    love.graphics.clear(0, 0, 0)
                    love.graphics.setColor(1, 1, 1)
                    for i = 1, #visibilityPoints do
                        local p1 = visibilityPoints[i]
                        local p2 = visibilityPoints[i == #visibilityPoints and 1 or (i + 1)]
                        love.graphics.polygon('fill', ownPlayer.x, ownPlayer.y, p1[1], p1[2], p2[1], p2[2])
                    end
                end)

                love.graphics.push('all')
                love.graphics.setBlendMode('multiply', 'premultiplied')
                love.graphics.draw(visibilityCanvas, 0, 0)
                love.graphics.pop('all')

                -- For testing
                -- love.graphics.setColor(1, 1, 1)
                -- for i, visibilityPoint in ipairs(visibilityPoints) do
                --     love.graphics.line(ownPlayer.x, ownPlayer.y, visibilityPoint[1], visibilityPoint[2])
                --     -- love.graphics.circle('fill', visibilityPoint[1], visibilityPoint[2], 20, 20)
                --     love.graphics.print(i, visibilityPoint[1], visibilityPoint[2])
                -- end
                -- local visibilityPolygon = {}
                -- for _, visibilityPoint in ipairs(visibilityPoints) do
                --     table.insert(visibilityPolygon, visibilityPoint[1])
                --     table.insert(visibilityPolygon, visibilityPoint[2])
                -- end
                -- love.graphics.setColor(1, 1, 1)
                -- for _, triangle in ipairs(love.math.triangulate(visibilityPolygon)) do
                --     love.graphics.polygon('line', triangle)
                -- end
            end
        end

        -- Draw score
        do
            local scoreFormat = {}

            local playersByScore = {}
            for clientId, player in pairs(self.players) do
                table.insert(playersByScore, player)
            end
            table.sort(playersByScore, function(a, b)
                if a.score == b.score then
                    return a.clientId > b.clientId
                end
                return a.score > b.score
            end)
            for _, player in ipairs(playersByScore) do
                local username = self.mes[player.clientId] and self.mes[player.clientId].username or '<no name>'

                table.insert(scoreFormat, { 1.4 * player.r, 1.4 * player.g, 1.4 * player.b })
                table.insert(scoreFormat, username .. ': ' .. player.score .. '\n')
            end
            self.scoreText:setf(scoreFormat, 800, 'left')

            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle(
                'fill',
                10, 10,
                self.scoreText:getWidth() + 20, self.scoreText:getHeight() + 20,
                5)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(self.scoreText, 20, 20)
        end
    end)
end