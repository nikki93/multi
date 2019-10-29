Game = {}


local PriorityQueue = require 'https://raw.githubusercontent.com/Roblox/Wiki-Lua-Libraries/776a48bd1562c7df557a92e3ade6544efa5b031b/StandardLibraries/PriorityQueue.lua'


--
-- Framework
--

function Game:_new()
    return setmetatable({}, { __index = self })
end


Game.receivers = {}

Game.kindToNum, Game.numToKind = {}, {}
do
    local nextKindNum = 1

    setmetatable(Game.receivers, {
        __newindex = function(t, k, v)
            local num = nextKindNum
            nextKindNum = nextKindNum + 1

            Game.kindToNum[k] = num
            Game.numToKind[num] = k

            rawset(t, k, v)
        end
    })
end


function Game:_init(opts)
    self.server = opts.server
    self.client = opts.client

    if self.server then
        self.clientIds = {}
        self.startTime = love.timer.getTime()
    end

    if self.client then
        self.connected = false
    end

    self.sendUnreliables = false
    self.sendUnreliablesRate = 35
    self.lastSentUnreliables = nil

    self.pendingReceives = PriorityQueue.new(function(a, b)
        -- Priority is `{ time, receiveSequenceNum }` so time-ties are broken sequentially
        if a[1] > b[1] then
            return true
        end
        if a[1] < b[1] then
            return false
        end
        return a[2] > b[2]
    end)
    self.nextReceiveSequenceNum = 1

    self:start()
end

function Game:_connect(clientId)
    if self.server then
        self.clientIds[clientId] = true
        self:send({
            clientId = clientId,
            kind = '_initial',
            reliable = true,
            channel = 0,
            self = false,
        }, self.time)
        self:connect(clientId)
    end

    -- Client will call `:connect` in `_initial` receiver
end

function Game.receivers:_initial(_, time)
    -- This is only sent server -> client

    -- Initialize time
    self.time = time
    self.timeDelta = time - love.timer.getTime()

    -- Ready to call `:connect`
    self.connected = true
    self.clientId = self.client.id
    self:connect()
end

function Game:_disconnect(clientId)
    self:disconnect(clientId)
    if self.server then
        self.clientIds[clientId] = nil
    end
end

-- 
-- opts = {
--     kind = <string -- kind, must have a receiver defined>
--     self = <boolean -- whether to send to self>
--     reliable = <boolean -- whether this message MUST be received by the other end>
--     channel = <number -- messages are ordered within channels>
--     [CLIENT] forward = false <boolean -- whether server should forward this message to other clients when it receives it>
--     [SERVER] clientId = <number -- which client to send this message to, or 'all' if all>
-- }
--
function Game:send(opts, ...)
    local kind = opts.kind
    assert(type(kind) == 'string', 'send: `kind` needs to be a string')
    local kindNum = assert(self.kindToNum[kind], "no receiver for kind '" .. kind .. "'")

    local reliable = opts.reliable
    assert(type(reliable) == 'boolean', 'send: `reliable` needs to be a boolean')
    local flag = reliable and 'reliable' or 'unreliable'

    local channel = opts.channel
    assert(type(channel) == 'number', 'send: `channel` needs to be a number')

    if reliable or self.sendUnreliables then
        if self.server then
            local clientId = opts.clientId
            assert(type(clientId) == 'number' or clientId == 'all', "send: `clientId` needs to be a number or 'all'")
            self.server.sendExt(clientId, channel, flag, kindNum, self.time, false, nil, nil, ...)
        end
        if self.client then
            local forward = opts.forward == true
            if forward then
                self.client.sendExt(channel, flag, kindNum, self.time, true, channel, reliable, ...)
            else
                self.client.sendExt(channel, flag, kindNum, self.time, false, nil, nil, ...)
            end
        end
    end

    assert(type(opts.self) == 'boolean', 'send: `self` needs to be a boolean')
    if opts.self then
        self:_receive(self.clientId, kindNum, self.time, false, nil, nil, ...)
    end
end

function Game:_receive(fromClientId, kindNum, time, forward, channel, reliable, ...)
    -- `_initial` is special -- receive it immediately. Otherwise, enqueue to receive based on priority later.
    if kindNum == self.kindToNum['_initial'] then
        self:_callReceiver(kindNum, time, ...)
    else
        self.pendingReceives:Add({
            kindNum = kindNum,
            time = time,
            args = { ... },
            nArgs = select('#', ...),
        }, { time, self.nextReceiveSequenceNum })
        self.nextReceiveSequenceNum = self.nextReceiveSequenceNum + 1
    end

    -- If forwarding, do that immediately
    if self.server and forward then
        local flag = reliable and 'reliable' or 'unreliable'
        for clientId in pairs(self.clientIds) do
            if clientId ~= fromClientId then
                self.server.sendExt(clientId, channel, flag, kindNum, time, false, nil, nil, ...)
            end
        end
    end
end

function Game:_callReceiver(kindNum, time, ...)
    local kind = assert(self.numToKind[kindNum], 'receive: bad `kindNum`')

    if self.receive then
        self:receive(kind, time, ...)
    end
    local receiver = self.receivers[kind]
    if receiver then
        receiver(self, time, ...)
    end
end


function Game:_update(dt)
    -- Periodically enable sending unreliable messages
    if self.sendUnreliables then
        self.sendUnreliables = false
        self.lastSentUnreliables = love.timer.getTime()
    else
        if not self.lastSentUnreliables or love.timer.getTime() - self.lastSentUnreliables > 1 / self.sendUnreliablesRate then
            self.sendUnreliables = true
        end
    end

    -- Let time pass
    if self.server then
        self.time = love.timer.getTime() - self.startTime
    end
    if self.client and self.timeDelta then
        self.time = love.timer.getTime() + self.timeDelta
    end

    if self.time then
        while true do
            local pendingReceive = self.pendingReceives:Peek()
            if pendingReceive == nil then
                break
            end
            if pendingReceive.time > self.time then
                break
            end
            self.pendingReceives:Pop()

            self:_callReceiver(
                pendingReceive.kindNum,
                pendingReceive.time,
                unpack(pendingReceive.args, 1, pendingReceive.nArgs))
        end
    end
    self.nextReceiveSequenceNum = 1

    self:update(dt)
end


--
-- Inheriters
--

GameCommon = setmetatable({}, { __index = Game })

GameServer = setmetatable({
    receivers = setmetatable({}, { __index = GameCommon.receivers })
}, { __index = GameCommon })

GameClient = setmetatable({
    receivers = setmetatable({}, { __index = GameCommon.receivers })
}, { __index = GameCommon })


--
-- Game
--

-- Start / stop

function Game:start()
    self.players = {}
    self.mes = {}

    if self.client then
        self.photoImages = {}
    end
end

function Game:stop()
end


-- Connect / disconnect

function Game:connect(clientId)
    if self.server then
        -- Send full state to new client
        do
            self:send({
                clientId = clientId,
                kind = 'fullState',
                channel = 0,
                reliable = true,
                self = false,
            }, {
                players = self.players,
                mes = self.mes,
            })
        end

        -- Add player for new client
        do
            local x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)
            self:send({
                clientId = 'all',
                kind = 'addPlayer',
                channel = 0,
                reliable = true,
                self = true,
            }, clientId, x, y)
        end
    end

    if self.client then
        -- Send `me`
        local me = castle.user.getMe()
        self:send({
            kind = 'me',
            channel = 0,
            reliable = true,
            self = true,
            forward = true,
        }, self.clientId, me)
    end
end

function Game:disconnect(clientId)
    if self.server then
        -- Remove player for old client
        self:send({
            clientId = 'all',
            kind = 'removePlayer',
            channel = 0,
            reliable = true,
            self = true,
        }, clientId)
    end
end


-- Utils

function Game:loadPhoto(clientId)
    local photoUrl = self.mes[clientId].photoUrl
    if photoUrl then
        network.async(function()
            self.photoImages[clientId] = love.graphics.newImage(photoUrl)
        end)
    end
end


-- Receivers

function Game.receivers:fullState(time, state)
    for clientId, player in pairs(state.players) do
        self.players[clientId] = player
    end
    for clientId, me in pairs(state.mes) do
        self.mes[clientId] = me
        self:loadPhoto(clientId)
    end
end

function Game.receivers:me(time, clientId, me)
    self.mes[clientId] = me
    if self.client then
        self:loadPhoto(clientId)
    end
end

function Game.receivers:addPlayer(time, clientId, x, y)
    local player = {
        clientId = clientId,
        x = x,
        y = y,
    }

    if self.client and clientId == self.clientId then
        -- Own player -- keep velocity
        player.vx, player.vy = 0, 0
    else
        -- Other's player -- keep position history
        player.positions = {}
    end

    self.players[clientId] = player
end

function Game.receivers:removePlayer(time, clientId)
    self.players[clientId] = nil
end

function Game.receivers:playerPosition(time, clientId, x, y)
    local player = self.players[clientId]
    if player then -- May arrive before `addPlayer` since it's on a different channel
        -- Insert into position history
        table.insert(player.positions, {
            time = time,
            x = x,
            y = y,
        })
    end
end


-- Update

local PLAYER_SPEED = 200

function Game:update(dt)
    -- Disconnected client?
    if self.client and not self.connected then
        return
    end

    -- Move own player directly and send updates
    if self.client then
        local ownPlayer = self.players[self.clientId]
        if ownPlayer then
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

            ownPlayer.x, ownPlayer.y = ownPlayer.x + ownPlayer.vx * dt, ownPlayer.y + ownPlayer.vy * dt

            self:send({
                kind = 'playerPosition',
                self = false,
                reliable = false,
                channel = 1,
                forward = true,
            }, self.clientId, ownPlayer.x, ownPlayer.y)
        end
    end

    -- Interpolate others' players' positions based on history
    local displayTime = self.time - 0.2
    for clientId, player in pairs(self.players) do
        if not (self.client and player.clientId == self.clientId) then
            local positions = player.positions
            while #positions >= 2 and positions[1].time < displayTime and positions[2].time < displayTime do
                -- Remove unnecessary positions
                table.remove(positions, 1)
            end
            if #positions >= 2 then
                -- Interpolate
                local f = (displayTime - positions[1].time) / (positions[2].time - positions[1].time)
                local dx, dy = positions[2].x - positions[1].x, positions[2].y - positions[1].y
                player.x, player.y = positions[1].x + f * dx, positions[1].y + f * dy
            elseif #positions == 1 then
                -- Set
                player.x, player.y = positions[1].x, positions[1].y
            end
        end
    end
end


-- Draw

function Game:draw()
    -- Draw players
    for clientId, player in pairs(self.players) do
        if self.photoImages[clientId] then
            local image = self.photoImages[clientId]
            love.graphics.draw(image, player.x - 20, player.y - 20, 0, 40 / image:getWidth(), 40 / image:getHeight())
        else
            love.graphics.rectangle('fill', player.x - 20, player.y - 20, 40, 40)
        end
    end
end