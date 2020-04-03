local clientServer = require 'cs'

local Game = require 'game'

local print = PRINT_OVERRIDE or print


local server = clientServer.server
server.numChannels = NUM_CHANNELS or 200

if LOCAL_SERVER then
    server.enabled = true
    server.start(LOCAL_SERVER_PORT)
else
    server.useCastleConfig()
end


local game = Game.Server:_new()


function server.load()
    game:_init({
        server = server,
    })
end

function server.quit()
    game:stop()
end


local needsConnect = {}

function server.connect(clientId)
    print('server: client ' .. clientId .. ' connected')

    table.insert(needsConnect, { clientId = clientId, isReconnect = false })
end

function server.reconnect(clientId)
    print('server: client ' .. clientId .. ' reconnected')

    table.insert(needsConnect, { clientId = clientId, isReconnect = true })
end

function server.disconnect(clientId)
    print('server: client ' .. clientId .. ' disconnected')

    game:_disconnect(clientId)
end


function server.receive(clientId, channel, ...)
    game:_receive(clientId, channel, ...)
end


function server.update(dt)
    for i = #needsConnect, 1, -1 do
        local entry = needsConnect[i]
        table.remove(needsConnect, i)
        game:_connect(entry.clientId, entry.isReconnect)
    end

    game:_update(dt)
end


return Game
