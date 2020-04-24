local enet = require "enet"
local serpent = require "vendor.serpent"
local bitser = require "vendor.bitser"
local inspect = require "vendor.inspect"

local print = PRINT_OVERRIDE or print

local encode = bitser.dumps
local decode = bitser.loads

local MAX_MAX_CLIENTS = 64

local server = {}
do
    server.enabled = false
    server.maxClients = MAX_MAX_CLIENTS
    server.isAcceptingClients = true
    server.timeout = 60
    server.sendRate = 35
    server.numChannels = 1

    server.started = false
    server.backgrounded = false

    local host
    local peerToId = {}
    local idToPeer = {}
    local idToSessionToken = {}
    local idToDisconnectTime = {}
    local nextId = 1
    local numClients = 0

    function server.useCastleConfig()
        if castle then
            function castle.startServer(port)
                server.enabled = true
                server.start(port)
            end
        end
    end

    local useCompression = true
    function server.disableCompression()
        useCompression = false
    end

    function server.start(port)
        host = enet.host_create("*:" .. tostring(port or "22122"), MAX_MAX_CLIENTS, server.numChannels)
        if host == nil then
            print("couldn't start server -- is port in use?")
            server.enabled = false
            return
        end
        if useCompression then
            host:compress_with_range_coder()
        end
        server.started = true
    end

    function server.closePort()
        getmetatable(host).__gc(host)
    end

    function server.sendExt(id, channel, flag, ...)
        local data = encode({select("#", ...), ...})

        if DEBUG_CS then
            local request = decode(data)
            print("server sendext: " .. inspect(request))
        end

        if id == "all" then
            host:broadcast(data, channel, flag)
        else
            assert(idToPeer[id], "no connected client with this `id`"):send(data, channel, flag)
        end
    end

    function server.send(id, ...)
        server.sendExt(id, nil, nil, ...)
    end

    function server.kick(id)
        assert(idToPeer[id], "no connected client with this `id`"):disconnect()
    end

    function server.getPing(id)
        return assert(idToPeer[id], "no connected client with this `id`"):round_trip_time()
    end

    function server.getENetHost()
        return host
    end

    function server.getENetPeer(id)
        return idToPeer[id]
    end

    function server.preupdate()
        -- Process network events
        if host then
            while true do
                local event = host:service(0)
                if not event then
                    break
                end

                -- Someone connected?
                if event.type == "connect" then
                    local id, fail
                    if event.data ~= 0 then -- Retry?
                        id = event.data
                        if idToPeer[id] then -- Clear zombie peer if exists
                            idToPeer[id]:disconnect_now()
                            peerToId[idToPeer[id]] = nil
                            idToPeer[id] = nil
                            idToDisconnectTime[id] = nil
                        elseif idToDisconnectTime[event.data] then -- No zombie, within timeout
                            idToDisconnectTime[event.data] = nil
                        else -- Timed out!
                            fail = "timeout"
                        end
                    elseif numClients < server.maxClients then -- New connect, generate an id
                        id = nextId
                        nextId = nextId + 1
                        numClients = numClients + 1
                    else
                        fail = "full"
                    end
                    if id then
                        peerToId[event.peer] = id
                        idToPeer[id] = event.peer
                        if CASTLE_SERVER then
                            castle.setIsAcceptingClients(server.isAcceptingClients and numClients < server.maxClients)
                        end
                        if event.data ~= 0 then
                            if server.reconnect then
                                server.reconnect(id)
                            end
                        else
                            if server.connect then
                                if DEBUG_CS then
                                    print("server.connect " .. id)
                                end
                                server.connect(id)
                            end
                        end
                        event.peer:send(
                            encode(
                                {
                                    id = id
                                }
                            )
                        )
                    else
                        event.peer:send(encode({fail = fail}))
                        event.peer:disconnect_later()
                    end
                end

                -- Someone disconnected?
                if event.type == "disconnect" then
                    local id = peerToId[event.peer]
                    if id then
                        if server.disconnect then
                            server.disconnect(id)
                        end
                        idToPeer[id] = nil
                        peerToId[event.peer] = nil
                        idToDisconnectTime[id] = love.timer.getTime()
                    -- Decrement `numClients` etc. only after the timeout
                    end
                end

                -- Received a request?
                if event.type == "receive" then
                    local id = peerToId[event.peer]
                    if id then
                        local request = decode(event.data)

                        -- Session token?
                        if request.sessionToken then
                            idToSessionToken[id] = request.sessionToken
                        end

                        -- Message?
                        if request[1] and server.receive then
                            if DEBUG_CS then
                                print("server receive: " .. inspect(request))
                            end
                            server.receive(id, event.channel, unpack(request, 2, request[1] + 1))
                        end
                    end
                end
            end
        end
    end

    local timeSinceLastUpdate = 0

    function server.postupdate(dt)
        timeSinceLastUpdate = timeSinceLastUpdate + dt
        if timeSinceLastUpdate < 1 / server.sendRate then
            return
        end
        timeSinceLastUpdate = 0

        if host then
            host:flush() -- Tell ENet to send outgoing messages
        end

        local time = love.timer.getTime()
        for id, disconnectTime in pairs(idToDisconnectTime) do
            if time - disconnectTime > server.timeout then
                idToDisconnectTime[id] = nil
                --idToSessionToken[id] = nil -- NOTE: Keep session token around to auth future connects
                numClients = numClients - 1
                if CASTLE_SERVER then
                    castle.setIsAcceptingClients(server.isAcceptingClients and numClients < server.maxClients)
                end
            end
        end

        if CASTLE_SERVER then -- On hosted servers we need to heartbeat the underlying infrastructure
            local sessionTokens = {}
            for k, v in pairs(idToSessionToken) do
                table.insert(sessionTokens, v)
            end
            castle.multiplayer.heartbeatV2(numClients, sessionTokens)
        end
    end
end

local client = {}
do
    client.enabled = false
    client.sessionToken = nil
    client.sendRate = 35
    client.numChannels = 1

    client.connected = false
    client.address = nil
    client.id = nil
    client.backgrounded = false

    local host
    local peer

    function client.useCastleConfig()
        if castle then
            function castle.startClient(address, sessionToken)
                client.enabled = true
                client.sessionToken = sessionToken
                client.start(address)
            end
        end
    end

    local useCompression = true
    function client.disableCompression()
        useCompression = false
    end

    function client.start(address, retryClientId)
        host = enet.host_create(nil, 1, client.numChannels)
        if useCompression then
            host:compress_with_range_coder()
        end
        client.address = address or "127.0.0.1:22122"
        host:connect(client.address, client.numChannels, retryClientId or 0)
    end

    function client.retry()
        assert(not client.connected, "client isn't currently disconnected")
        client.start(client.address, assert(client.id, "client wasn't previously connected"))
    end

    function client.sendExt(channel, flag, ...)
        local data = encode({select("#", ...), ...})

        if DEBUG_CS then
            local request = decode(data)
            print("client sendext: " .. inspect(request))
        end

        assert(peer, "client is not connected"):send(data, channel, flag)
    end

    function client.send(...)
        client.sendExt(nil, nil, ...)
    end

    function client.kick(send)
        if send ~= false then
            assert(peer, "client is not connected"):disconnect()
            host:flush()
        end
        if client.disconnect then
            client.disconnect()
        end
        client.connected = false
        --client.id = nil -- NOTE: We're keeping `client.id` for retries
        host = nil
        peer = nil
    end

    function client.getPing()
        return assert(peer, "client is not connected"):round_trip_time()
    end

    function client.getENetHost()
        return host
    end

    function client.getENetPeer()
        return peer
    end

    function client.preupdate(dt)
        -- Process network events
        if host then
            while true do
                if not host then
                    break
                end
                local event
                local succeeded =
                    pcall(
                    function()
                        event = host:service(0)
                    end
                )
                if not succeeded then -- `:service` error? Abort!
                    client.kick(false)
                    break
                end
                if not event then
                    break
                end

                -- Server connected?
                if event.type == "connect" then
                -- Ignore this, wait till we receive id (see below)
                end

                -- Server disconnected?
                if event.type == "disconnect" then
                    client.kick(false)
                end

                -- Received a request?
                if event.type == "receive" then
                    local request = decode(event.data)

                    -- Message?
                    if request[1] and client.receive then
                        if DEBUG_CS then
                            print("client receive: " .. inspect(request))
                        end
                        client.receive(event.channel, unpack(request, 2, request[1] + 1))
                    end

                    -- Id?
                    if request.id then
                        peer = event.peer
                        client.connected = true
                        if client.id then
                            assert(client.id == request.id, "reconnected with a different `id`")
                            if client.reconnect then
                                client.reconnect()
                            end
                        else
                            client.id = request.id
                            if client.connect then
                                if DEBUG_CS then
                                    print("client.connect")
                                end
                                client.connect()
                            end
                        end

                        -- Send sessionToken now that we have an id
                        peer:send(
                            encode(
                                {
                                    sessionToken = client.sessionToken
                                }
                            )
                        )
                    end

                    -- Fail?
                    if request.fail then
                        if client.fail then
                            client.fail(request.fail)
                        end
                        if castle and castle.connectionFailed then
                            castle.connectionFailed(request.fail)
                        end
                    end
                end
            end
        end
    end

    local timeSinceLastUpdate = 0

    function client.postupdate(dt)
        timeSinceLastUpdate = timeSinceLastUpdate + dt
        if timeSinceLastUpdate < 1 / client.sendRate then
            return
        end
        timeSinceLastUpdate = 0

        if host then
            host:flush() -- Tell ENet to send outgoing messages
        end
    end
end

local loveCbs = {
    load = {server = true, client = true},
    lowmemory = {server = true, client = true},
    quit = {server = true, client = true},
    threaderror = {server = true, client = true},
    update = {server = true, client = true},
    directorydropped = {client = true},
    draw = {client = true},
    --    errhand = { client = true },
    --    errorhandler = { client = true },
    filedropped = {client = true},
    focus = {client = true},
    keypressed = {client = true},
    keyreleased = {client = true},
    mousefocus = {client = true},
    mousemoved = {client = true},
    mousepressed = {client = true},
    mousereleased = {client = true},
    resize = {client = true},
    --    run = { client = true },
    textedited = {client = true},
    textinput = {client = true},
    touchmoved = {client = true},
    touchpressed = {client = true},
    touchreleased = {client = true},
    visible = {client = true},
    wheelmoved = {client = true},
    gamepadaxis = {client = true},
    gamepadpressed = {client = true},
    gamepadreleased = {client = true},
    joystickadded = {client = true},
    joystickaxis = {client = true},
    joystickhat = {client = true},
    joystickpressed = {client = true},
    joystickreleased = {client = true},
    joystickremoved = {client = true}
}

for cbName, where in pairs(loveCbs) do
    love[cbName] = function(...)
        if where.server and server.enabled then
            if cbName == "update" then
                server.backgrounded = false
                server.preupdate(...)
            end
            local serverCb = server[cbName]
            if serverCb then
                serverCb(...)
            end
            if cbName == "update" then
                server.postupdate(...)
            end
        end
        if where.client and client.enabled then
            if cbName == "update" then
                client.backgrounded = false
                client.preupdate(...)
            end
            local clientCb = client[cbName]
            if clientCb then
                clientCb(...)
            end
            if cbName == "update" then
                client.postupdate(...)
            end
            if cbName == "quit" and client.connected then
                client.kick()
            end
        end
    end
end

function castle.backgroundupdate(...)
    if server.enabled then
        server.backgrounded = true
        server.preupdate(...)
        if server.update then
            server.update(...)
        end
        server.postupdate(...)
    end
    if client.enabled then
        client.backgrounded = true
        client.preupdate(...)
        if client.update then
            client.update(...)
        end
        client.postupdate(...)
    end
end

function castle.uiupdate(...)
    if client.enabled then
        if client.uiupdate then
            client.uiupdate(...)
        end
    end
end

return {
    server = server,
    client = client
}
