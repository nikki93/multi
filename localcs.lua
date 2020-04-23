local bitser = require "vendor.bitser"

local encode = bitser.dumps
local decode = bitser.loads

local server = {}
local client = {}

do
    local clientId = 1
    local serverHasSentConnect = false
    local serverPendingMessages = {}

    function server.useCastleConfig()
    end

    function server.disableCompression()
    end

    function server.start(port)
    end

    function server.closePort()
    end

    function server.sendExt(id, channel, flag, ...)
        local data = encode({select("#", ...), ...})
        client.LOCALSEND(data, channel)
    end

    function server.send(id, ...)
        server.sendExt(id, nil, nil, ...)
    end

    function server.kick(id)
    end

    function server.getPing(id)
        return 40
    end

    function server.getENetHost()
        -- not used anywhere in scene creator
        return nil
    end

    function server.getENetPeer(id)
        -- commented out use in scene creator
        return nil
    end

    function server.LOCALSEND(data, channel)
        table.insert(
            serverPendingMessages,
            {
                data = data,
                channel = channel
            }
        )
    end

    function server.preupdate()
        if not serverHasSentConnect then
            server.connect(clientId)
            serverHasSentConnect = true
        end

        while next(serverPendingMessages) ~= nil do
            local event = table.remove(serverPendingMessages, 1)

            local request = decode(event.data)

            -- Message?
            if request[1] then
                server.receive(clientId, event.channel, unpack(request, 2, request[1] + 1))
            end
        end
    end

    function server.postupdate(dt)
    end
end

do
    local clientHasSentConnect = false
    local clientPendingMessages = {}
    client.id = 1

    function client.useCastleConfig()
    end

    function client.disableCompression()
    end

    function client.start(address, retryClientId)
    end

    function client.retry()
    end

    function client.sendExt(channel, flag, ...)
        local data = encode({select("#", ...), ...})
        server.LOCALSEND(data, channel)
    end

    function client.send(...)
        client.sendExt(nil, nil, ...)
    end

    function client.kick(send)
    end

    function client.getPing()
        return 40
    end

    function client.getENetHost()
        -- not used anywhere in scene creator
        return nil
    end

    function client.getENetPeer()
        -- commented out use in scene creator
        return nil
    end

    function client.LOCALSEND(data, channel)
        table.insert(
            clientPendingMessages,
            {
                data = data,
                channel = channel
            }
        )
    end

    function client.preupdate(dt)
        if not clientHasSentConnect then
            client.connect()
            clientHasSentConnect = true
        end

        while next(clientPendingMessages) ~= nil do
            local event = table.remove(clientPendingMessages, 1)

            local request = decode(event.data)

            -- Message?
            if request[1] then
                client.receive(event.channel, unpack(request, 2, request[1] + 1))
            end
        end
    end

    function client.postupdate(dt)
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
