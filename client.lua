local clientServer = require 'cs'

require 'game'


local client = clientServer.client
client.numChannels = NUM_CHANNELS

if USE_LOCAL_SERVER then
    client.enabled = true
    client.start('127.0.0.1:22122')
else
    client.useCastleConfig()
end


local game = GameClient:_new()


function client.load()
    game:_init({
        client = client,
    })
end

function client.quit()
    game:stop()
end


function client.connect()
    print('client: connected to server')

    game:_connect()
end

function client.disconnect()
    print('client: disconnected from server')

    game:_disconnect()
end


function client.receive(...)
    game:_receive(nil, ...)
end


function client.draw()
    game:draw()
end

function client.update(dt)
    game:_update(dt)
end


local loveCallbacks = {
    -- Implemented above
    --    load = true,
    --    quit = true,
    --    update = true,
    --    draw = true,

    -- Skipping these
    --    errhand = true,
    --    errorhandler = true,
    --    run = true,

    lowmemory = true,
    threaderror = true,
    directorydropped = true,

    filedropped = true,
    focus = true,
    keypressed = true,
    keyreleased = true,
    mousefocus = true,
    mousemoved = true,
    mousepressed = true,
    mousereleased = true,
    resize = true,
    textedited = true,
    textinput = true,
    touchmoved = true,
    touchpressed = true,
    touchreleased = true,
    visible = true,
    wheelmoved = true,
    gamepadaxis = true,
    gamepadpressed = true,
    gamepadreleased = true,
    joystickadded = true,
    joystickaxis = true,
    joystickhat = true,
    joystickpressed = true,
    joystickreleased = true,
    joystickremoved = true,
}

for loveCallback in pairs(loveCallbacks) do
    client[loveCallback] = function(...)
        if game[loveCallback] then
            game[loveCallback](game, ...)
        end
    end
end