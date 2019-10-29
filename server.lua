clientServer = require 'https://raw.githubusercontent.com/castle-games/share.lua/6d70831ea98c57219f2aa285b4ad7bf7156f7c03/cs.lua'


require 'game'


local server = clientServer.server
server.numChannels = NUM_CHANNELS

if USE_LOCAL_SERVER then
    server.enabled = true
    server.start('22122')
else
    server.useCastleConfig()
end


local game = GameServer:_new()


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