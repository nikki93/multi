local clientServer = require 'cs'

local Game = require 'game'


local server = clientServer.server
server.numChannels = NUM_CHANNELS or 200

if USE_LOCAL_SERVER then
    server.enabled = true
    server.start('22122')
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

    table.insert(needsConnect, clientId)
end

function server.disconnect(clientId)
    print('server: client ' .. clientId .. ' disconnected')

    game:_disconnect(clientId)
end


function server.receive(clientId, ...)
    game:_receive(clientId, ...)
end


function server.update(dt)
    for i = #needsConnect, 1, -1 do
        local clientId = needsConnect[i]
        table.remove(needsConnect, i)
        game:_connect(clientId)
    end

    game:_update(dt)
end


return Game
