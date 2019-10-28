require 'common'

local server = clientServer.server

if USE_LOCAL_SERVER then
    server.enabled = true
    server.start('22122')
else
    server.useCastleConfig()
end

function server.connect(clientId)
    print('server: client ' .. clientId .. ' connected')
end

function server.disconnect(clientId)
    print('server: client ' .. clientId .. ' disconnected')
end

function server.receive(clientId, message, ...)
end