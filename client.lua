require 'common'

local client = clientServer.client

if USE_LOCAL_SERVER then
    client.enabled = true
    client.start('127.0.0.1:22122')
else
    client.useCastleConfig()
end

function client.connect()
    print('client: connected to server')
end

function client.disconnect()
    print('client: disconnected from server')
end

function client.receive(message, ...)
end