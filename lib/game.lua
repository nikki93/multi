Game = {}


NUM_CHANNELS = NUM_CHANNELS or 200


local PriorityQueue = require 'https://raw.githubusercontent.com/Roblox/Wiki-Lua-Libraries/776a48bd1562c7df557a92e3ade6544efa5b031b/StandardLibraries/PriorityQueue.lua'


--
-- Framework
--

function Game:_new()
    return setmetatable({}, { __index = self })
end


Game.receivers = {}


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

    self.nextKindNum = 1
    self.kindToNum, self.numToKind = {}, {}
    self.kindDefaults = {}

    self.kindThrottles = {} -- `kind` -> `{ period, timeSinceLastSend }`

    self:defineMessageKind('_initial', {
        reliable = true,
        channel = 0,
        selfSend = false,
    })

    self:define()

    self:start()
end

function Game:_connect(clientId)
    if self.server then
        self.clientIds[clientId] = true
        self:send({
            to = clientId,
            kind = '_initial',
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


function Game:defineMessageKind(kind, defaults)
    assert(not self.kindToNum[kind], "kind '" .. kind .. "' already defined")

    local kindNum = self.nextKindNum
    self.nextKindNum = self.nextKindNum + 1

    self.kindToNum[kind] = kindNum
    self.numToKind[kindNum] = kind

    self.kindDefaults[kind] = defaults

    local period = 1 / math.max(0, math.min(defaults.rate or 35, 35))
    self.kindThrottles[kind] = {
        period = period,
        timeSinceLastSend = period * math.random(),
    }
end

function Game:send(opts, ...)
    local kind = opts.kind
    assert(type(kind) == 'string', 'send: `kind` needs to be a string')
    local kindNum = assert(self.kindToNum[kind], "kind '" .. kind .. "' not defined")

    local defaults = self.kindDefaults[kind]

    local reliable = opts.reliable or defaults.reliable
    assert(type(reliable) == 'boolean', 'send: `reliable` needs to be a boolean')

    local shouldSend
    if reliable then
        shouldSend = true
    else
        local throttle = self.kindThrottles[kind]
        if throttle.timeSinceLastSend > throttle.period then
            shouldSend = true
        end
    end

    if shouldSend then
        local channel = opts.channel or defaults.channel
        assert(type(channel) == 'number', 'send: `channel` needs to be a number')
        assert(0 <= channel and channel < NUM_CHANNELS, 'send: `channel` out of range')

        local flag = reliable and 'reliable' or 'unreliable'

        if self.server then
            local to = opts.to or defaults.to
            assert(type(to) == 'number' or to == 'all', "send: `to` needs to be a number or 'all'")
            self.server.sendExt(to, channel, flag, kindNum, self.time, false, nil, nil, ...)
        end
        if self.client then
            local forward = opts.forward
            if forward == nil then
                forward = defaults.forward
            end
            assert(type(forward) == 'boolean', 'send: `forward` needs to be a boolean')
            if forward then
                self.client.sendExt(channel, flag, kindNum, self.time, true, channel, reliable, ...)
            else
                self.client.sendExt(channel, flag, kindNum, self.time, false, nil, nil, ...)
            end
        end
    end

    local selfSend = opts.selfSend
    if selfSend == nil then
        selfSend = defaults.selfSend
    end
    assert(type(selfSend) == 'boolean', 'send: `self` needs to be a boolean')
    if selfSend then
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

    local receiver = self.receivers[kind]
    if receiver then
        receiver(self, time, ...)
    end
end


function Game:_update(dt)
    -- Manage throttling
    for kind, throttle in pairs(self.kindThrottles) do
        if throttle.timeSinceLastSend > throttle.period then
            -- Sending was enabled last frame, so reset
            throttle.timeSinceLastSend = 0
        end
        throttle.timeSinceLastSend = throttle.timeSinceLastSend + dt
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
-- Default events
--

function Game:define()
end

function Game:start()
end

function Game:stop()
end

function Game:connect()
end

function Game:disconnect()
end

function Game:update(dt)
end

function Game:draw()
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
