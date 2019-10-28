local Game = {}


--
-- Framework
--

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
    end

    if self.client then
        self.connected = false
    end

    self.sendUnreliables = false
    self.sendUnreliablesRate = 35
    self.lastSentUnreliables = nil

    self:start()
end

function Game:_connect(clientId)
    if self.server then
        self.clientIds[clientId] = true
    end
    if self.client then
        self.connected = true
        self.clientId = self.client.id
    end
    self:connect(clientId)
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
--     data = <string -- data to send with the message, you do your own serialization>
--     self = <boolean -- whether to send to self>
--     reliable = <boolean -- whether this message MUST be received by the other end>
--     channel = <number -- messages are ordered within channels>
--     [CLIENT] forward = false <boolean -- whether server should forward this message to other clients when it receives it>
--     [SERVER] clientId = <number -- which client to send this message to, or 'all' if all>
-- }
--
function Game:send(opts)
    local kind = opts.kind
    assert(type(kind) == 'string', 'send: `kind` needs to be a string')
    local kindNum = assert(self.kindToNum[kind], "no receiver for kind '" .. kind .. "'")

    local data = opts.data
    assert(type(data) == 'string', 'send: `data` needs to be a string')

    local reliable = opts.reliable
    assert(type(reliable) == 'boolean', 'send: `reliable` needs to be a boolean')
    local flag = reliable and 'reliable' or 'unreliable'

    local channel = opts.channel
    assert(type(channel) == 'number', 'send: `channel` needs to be a number')

    if reliable or self.sendUnreliables then
        if self.server then
            local clientId = opts.clientId
            assert(type(clientId) == 'number' or clientId == 'all', "send: `clientId` needs to be a number or 'all'")
            self.server.sendExt(clientId, channel, flag, kindNum, data)
        end
        if self.client then
            local forward = opts.forward == true
            if forward then
                self.client.sendExt(channel, flag, kindNum, data, true, channel, reliable)
            else
                self.client.sendExt(channel, flag, kindNum, data, false)
            end
        end
    end

    assert(type(opts.self) == 'boolean', 'send: `self` needs to be a boolean')
    if opts.self then
        self:_receive(self.clientId, kindNum, data, false)
    end
end

function Game:_receive(fromClientId, kindNum, data, forward, channel, reliable)
    local kind = assert(self.numToKind[kindNum], 'receive: bad `kindNum`')

    if self.receive then
        self:receive(kind, data)
    end
    local receiver = self.receivers[kind]
    if receiver then
        receiver(self, data)
    end

    if self.server and forward then
        local flag = reliable and 'reliable' or 'unreliable'
        for clientId in pairs(self.clientIds) do
            if clientId ~= fromClientId then
                self.server.sendExt(clientId, channel, flag, kindNum, data)
            end
        end
    end
end


function Game:_update(dt)
    if self.sendUnreliables then
        self.sendUnreliables = false
        self.lastSentUnreliables = love.timer.getTime()
    else
        if not self.lastSentUnreliables or love.timer.getTime() - self.lastSentUnreliables > 1 / self.sendUnreliablesRate then
            self.sendUnreliables = true
        end
    end

    self:update(dt)
end


--
-- Game
--

function Game:start()
    self.players = {}
end

function Game:stop()
end


function Game:connect(clientId)
    if self.server then
        -- Send full state to new client
        do
            local blob = BlobWriter()
            blob:table(self.players)
            self:send({
                clientId = clientId,
                kind = 'fullState',
                channel = 0,
                reliable = true,
                self = false,
                data = blob:tostring(),
            })
        end

        -- Add player for new client
        do
            local x, y = math.random(40, 800 - 40), math.random(40, 450 - 40)

            local blob = BlobWriter()
            blob:number(clientId)
            blob:number(x)
            blob:number(y)
            self:send({
                clientId = 'all',
                kind = 'addPlayer',
                channel = 0,
                reliable = true,
                self = true,
                data = blob:tostring(),
            })
        end
    end
end

function Game:disconnect(clientId)
    if self.server then
        -- Remove player for old client
        local blob = BlobWriter()
        blob:number(clientId)
        self:send({
            clientId = 'all',
            kind = 'removePlayer',
            channel = 0,
            reliable = true,
            self = true,
            data = blob:tostring(),
        })
    end
end


function Game.receivers:fullState(data)
    local blob = BlobReader(data)
    self.players = blob:table()
end

function Game.receivers:addPlayer(data)
    local blob = BlobReader(data)
    local clientId = blob:number()
    local x = blob:number()
    local y = blob:number()

    self.players[clientId] = {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
    }
end

function Game.receivers:removePlayer(data)
    local blob = BlobReader(data)
    local clientId = blob:number()
    self.players[clientId] = nil
end

function Game.receivers:playerPositionVelocity(data)
    local blob = BlobReader(data)
    local clientId = blob:number()
    local x = blob:number()
    local y = blob:number()
    local vx = blob:number()
    local vy = blob:number()

    local player = self.players[clientId]
    player.x, player.y = x, y
    player.vx, player.vy = vx, vy
end


local PLAYER_SPEED = 200

function Game:update(dt)
    -- Disconnected client?
    if self.client and not self.connected then
        return
    end

    -- Client update
    if self.client then
        local ownPlayer = self.players[self.clientId]

        -- Own player input
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
        end

        -- All players motion
        for clientId, player in pairs(self.players) do
            player.x, player.y = player.x + player.vx * dt, player.y + player.vy * dt
        end

        -- Send own player update
        if ownPlayer then
            local blob = BlobWriter()
            blob:number(self.clientId)
            blob:number(ownPlayer.x)
            blob:number(ownPlayer.y)
            blob:number(ownPlayer.vx)
            blob:number(ownPlayer.vy)
            self:send({
                kind = 'playerPositionVelocity',
                self = false,
                reliable = false,
                channel = 1,
                forward = true,
                data = blob:tostring(),
            })
        end
    end
end


function Game:draw()
    for clientId, player in pairs(self.players) do
        love.graphics.rectangle('fill', player.x - 20, player.y - 20, 40, 40)
    end
end


return Game