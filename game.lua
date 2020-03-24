local Game = {}


local PriorityQueue = require 'vendor.PriorityQueue'


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
        self._clientIds = {}
        self._startTime = love.timer.getTime()
        self.time = 0
    end

    if self.client then
        self.connected = false
        self.autoRetry = true
        -- Some more members are initialized in `_initial` receiver below
    end

    self._nextIdSuffix = 1

    self._pendingReceives = PriorityQueue.new(function(a, b)
        -- Priority is `{ time, receiveSequenceNum }` so time-ties are broken sequentially
        if a[1] > b[1] then
            return true
        end
        if a[1] < b[1] then
            return false
        end
        return a[2] > b[2]
    end)
    self._nextReceiveSequenceNum = 1

    self._nextKindNum = 1
    self._kindToNum, self._numToKind = {}, {}
    self._kindDefaults = {}

    self._kindThrottles = {} -- `kind` -> `{ period, timeSinceLastSend }`

    self._transaction = nil

    self:defineMessageKind('_initial', {
        from = 'server',
        reliable = true,
        channel = 0,
        selfSend = false,
    })

    self:defineMessageKind('_ping', {
        from = 'server',
        to = 'all',
        reliable = false,
        channel = 0,
        rate = 10,
        selfSend = false,
    })

    self:defineMessageKind('_pong', {
        reliable = true,
        channel = 50,
        selfSend = false,
        forward = false,
    })

    self:defineMessageKind('_transact', {
        -- Make user have to specify options
    })

    self:define()

    self:start()

    self._started = true
end

function Game:_connect(clientId, isReconnect)
    if self.server then
        self._clientIds[clientId] = true
        self:send({
            to = clientId,
            kind = '_initial',
        }, self.time)
        if isReconnect then
            self:reconnect(clientId)
        else
            self:connect(clientId)
        end
    end

    -- Client will call `:connect` in `_initial` receiver
end

function Game.receivers:_initial(_, time)
    -- This is only sent server -> client

    -- Initialize time
    self.time = time
    self._timeDelta = self.time - love.timer.getTime()

    -- Ready to call `:connect`
    self.connected = true
    self._connectTime = love.timer.getTime()
    self._lastPongSent = 0
    self._lastPongReceived = nil
    self._lastRetryTime = nil
    if self.clientId then -- Is it a reconnect?
        self:reconnect()
    else -- First connect!
        self.clientId = self.client.id
        self:connect()
    end
end

function Game.receivers:_ping(_, time)
    -- Update time
    self.time = math.max(self.time, 0.6 * self.time + 0.4 * time)
    self._timeDelta = self.time - love.timer.getTime()
    self._lastPingTime = self.time
end

function Game.receivers:_pong(_, clientId, pong)
    if self.server then
        -- Send pong back to client
        self:send({
            kind = '_pong',
            to = clientId,
        }, clientId, pong)
    end
    if self.client then
        -- If our pong, track it as received
        if self.clientId == clientId then
            self._lastPongReceived = pong
        end
    end
end

function Game:_disconnect(clientId)
    self:disconnect(clientId)
    self._pendingReceives = PriorityQueue.new(self._pendingReceives.Compare)
    if self.server then
        self._clientIds[clientId] = nil
    end
    if self.client then
        self.connected = false
        self.time = nil
        self._timeDelta = nil
    end
end


function Game:defineMessageKind(kind, defaults)
    assert(not self._kindToNum[kind], "kind '" .. kind .. "' already defined")

    local kindNum = self._nextKindNum
    self._nextKindNum = self._nextKindNum + 1

    self._kindToNum[kind] = kindNum
    self._numToKind[kindNum] = kind

    self._kindDefaults[kind] = defaults

    local period = 1 / math.max(0, math.min(defaults.rate or 35, 35))
    self._kindThrottles[kind] = {
        period = period,
        timeSinceLastSend = period * math.random(),
    }
end

function Game:send(opts, ...)
    if type(opts) == 'string' then -- Shorthand
        opts = { kind = opts }
    end

    local kind = opts.kind
    assert(type(kind) == 'string', 'send: `kind` needs to be a string')
    local kindNum = assert(self._kindToNum[kind], "kind '" .. kind .. "' not defined")

    if self._transaction then -- Transacting? Insert into transaction, call local receiver immediately if self-send
        local transaction = self._transaction
        table.insert(transaction.messages, { kindNum, select('#', ...), ... })
        if transaction.opts.selfSend or transaction.opts.selfSendOnly then
            self:_callReceiver(kindNum, transaction.time, ...)
        end
        return
    end

    local time = opts.time or self.time

    local defaults = self._kindDefaults[kind]

    local from = opts.from or defaults.from
    if from then
        if from == 'server' and self.client then
            error("kind '" .. kind .. "' can only be sent by server")
        end
        if from == 'client' and self.server then
            error("kind '" .. kind .. "' can only be sent by client")
        end
    end

    local reliable = opts.reliable or defaults.reliable
    assert(type(reliable) == 'boolean', 'send: `reliable` needs to be a boolean')

    local selfSendOnly = opts.selfSendOnly
    if selfSendOnly == nil then
        selfSendOnly = defaults.selfSendOnly
    end
    local shouldSend
    if selfSendOnly then
        shouldSend = false
    elseif reliable then
        shouldSend = true
    else
        local throttle = self._kindThrottles[kind]
        if throttle.timeSinceLastSend > throttle.period then
            shouldSend = true
        end
    end

    if shouldSend then
        local channel = opts.channel or defaults.channel
        assert(type(channel) == 'number', 'send: `channel` needs to be a number')
        assert(0 <= channel and channel < (NUM_CHANNELS or 200), 'send: `channel` out of range')

        local flag = reliable and 'reliable' or 'unreliable'

        if self.server then
            local to = opts.to or defaults.to
            assert(type(to) == 'number' or to == 'all', "send: `to` needs to be a number or 'all'")
            self.server.sendExt(to, channel, flag, kindNum, time, false, nil, ...)
        end
        if self.client then
            local forward = opts.forward
            if forward == nil then
                forward = defaults.forward
            end
            assert(type(forward) == 'boolean', 'send: `forward` needs to be a boolean')
            if forward then
                self.client.sendExt(channel, flag, kindNum, time, true, reliable, ...)
            else
                self.client.sendExt(channel, flag, kindNum, time, false, nil, ...)
            end
        end
    end

    local selfSend = selfSendOnly or opts.selfSend
    if selfSend == nil then
        selfSend = defaults.selfSend
    end
    assert(type(selfSend) == 'boolean', 'send: `selfSend` needs to be a boolean')
    if selfSend then
        self:_callReceiver(kindNum, time, ...)
    end
end

function Game:_receive(fromClientId, channel, kindNum, time, forward, reliable, ...)
    -- `_initial` and `_ping` are special -- receive immediately. Otherwise, enqueue to receive based
    -- on priority later.
    if kindNum == self._kindToNum['_initial'] or kindNum == self._kindToNum['_ping'] then
        self:_callReceiver(kindNum, time, ...)
    else
        self._pendingReceives:Add({
            kindNum = kindNum,
            time = time,
            args = { ... },
            nArgs = select('#', ...),
        }, { time, self._nextReceiveSequenceNum })
        self._nextReceiveSequenceNum = self._nextReceiveSequenceNum + 1
    end

    -- If forwarding, do that immediately
    if self.server and forward then
        local defaults = self._kindDefaults[self._numToKind[kindNum]]
        local forwardToOrigin = defaults.forwardToOrigin

        local flag = reliable and 'reliable' or 'unreliable'
        for clientId in pairs(self._clientIds) do
            if forwardToOrigin or clientId ~= fromClientId then
                self.server.sendExt(clientId, channel, flag, kindNum, time, false, nil, ...)
            end
        end
    end
end

function Game:_callReceiver(kindNum, time, ...)
    local kind = assert(self._numToKind[kindNum], '_callReceiver: bad `kindNum`')

    if self.debugReceive then
        self:debugReceive(kind, time, ...)
    end

    local receiver = self.receivers[kind]
    if receiver then
        receiver(self, time, ...)
    end
end

function Game:transact(opts, func, ...)
    if self._transaction then
        error('transact: already in a transaction')
    end

    local transaction = {
        time = opts.time or self.time,
        opts = opts,
        messages = {},
    }

    self._transaction = transaction
    local succeeded, err = pcall(func, ...)
    self._transaction = nil
    if not succeeded then
        error(err, 0)
    end

    self:send(setmetatable({
        kind = '_transact',
        time = transaction.time,
        selfSend = false, -- Local receivers have already been called, `_transact` shouldn't self-send
        selfSendOnly = false,
    }, { __index = transaction.opts }), transaction.messages)
end

function Game.receivers:_transact(time, messages)
    for _, message in ipairs(messages) do
        self:_callReceiver(message[1], time, unpack(message, 3, message[2] + 2))
    end
end


function Game:_update(dt)
    if not self._started then -- May happen if `love.load` didn't finish yet
        return
    end

    -- Manage throttling
    for kind, throttle in pairs(self._kindThrottles) do
        if throttle.timeSinceLastSend > throttle.period then
            -- Sending was enabled last frame, so reset
            throttle.timeSinceLastSend = 0
        end
        throttle.timeSinceLastSend = throttle.timeSinceLastSend + dt
    end

    if self.server then
        self.time = love.timer.getTime() - self._startTime
        self:send('_ping', self.time)
    end

    if self.client then
        -- Maintain server time
        if self._timeDelta then
            self.time = love.timer.getTime() + self._timeDelta
        end

        -- Periodically send pongs. Restart the connection if we didn't get a pong back for more than one second.
        if self.connected then
            local pong = math.floor(10 * (love.timer.getTime() - self._connectTime))
            if self._lastPongReceived and pong - self._lastPongReceived >= 18 then
                self:kick()
            elseif pong - self._lastPongSent >= 8 then
                self._lastPongSent = pong
                self:send('_pong', self.clientId, pong)
            end
        end

        -- Auto-reconnection
        if self.autoRetry and self.clientId and not self.connected then
            self:retry()
        end
    end

    -- Flush pending receives
    if self.time then
        while true do
            local pendingReceive = self._pendingReceives:Peek()
            if pendingReceive == nil then
                break
            end
            if pendingReceive.time > self.time then
                break
            end
            self._pendingReceives:Pop()

            self:_callReceiver(
                pendingReceive.kindNum,
                pendingReceive.time,
                unpack(pendingReceive.args, 1, pendingReceive.nArgs))
        end
    end
    self._nextReceiveSequenceNum = 1

    self:update(dt)
end


--
-- Connection management
--

function Game:kick(id)
    if self.server then
        self.server.kick(id)
    end
    if self.client then
        self.client.kick()
    end
end

function Game:retry()
    assert(self.client, 'only clients can retry')
    if not self._lastRetryTime or love.timer.getTime() - self._lastRetryTime > 3 then
        self.client.retry()
        self._lastRetryTime = love.timer.getTime()
    end
end


--
-- Utilities
--

function Game:generateId()
    assert(self.server or self.connected, "generateId: need to be connected")

    local suffix = tostring(self._nextIdSuffix)
    self._nextIdSuffix = self._nextIdSuffix + 1

    local prefix
    if self.server then
        prefix = '0'
    else
        prefix = tostring(self.clientId)
    end

    return prefix .. '-' .. suffix
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

function Game:reconnect()
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

Game.Common = setmetatable({}, { __index = Game })

Game.Server = setmetatable({
    receivers = setmetatable({}, { __index = Game.Common.receivers })
}, { __index = Game.Common })

Game.Client = setmetatable({
    receivers = setmetatable({}, { __index = Game.Common.receivers })
}, { __index = Game.Common })


return Game
