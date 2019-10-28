require 'common'

local server = clientServer.server
server.numChannels = 200

if USE_LOCAL_SERVER then
    server.enabled = true
    server.start('22122')
else
    server.useCastleConfig()
end


local game = newGame()


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
    for _, clientId in ipairs(needsConnect) do
        game:_connect(clientId)
    end
    needsConnect = {}

    game:_update(dt)
end