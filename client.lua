local clientServer = require 'cs'

local Game = require 'game'

local print = PRINT_OVERRIDE or print


local client = clientServer.client
client.numChannels = NUM_CHANNELS or 200

if GET_SERVER_MODULE_NAME then
    local gameUrl = castle.game.getCurrent().url
    local isFileUrl = gameUrl:match('^file://')
    local isLANUrl = gameUrl:match('^http://192') or gameUrl:match('^http://172.20') -- NOTE(nikki): May need to add more patterns here...
    if isFileUrl or isLANUrl then
        USE_LOCAL_SERVER = true
        if isLANUrl then
            LOCAL_SERVER_ADDRESS = gameUrl:match('^http://([^:/]*)')
        else
            getfenv(GET_SERVER_MODULE_NAME).require(GET_SERVER_MODULE_NAME())
        end
    end
end

if USE_LOCAL_SERVER then
    client.enabled = true
    client.start((LOCAL_SERVER_ADDRESS or '127.0.0.1') .. ':22122')
else
    client.useCastleConfig()
end


local game = Game.Client:_new()


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

function client.reconnect()
    print('client: reconnected to server')

    game:_connect(nil, true)
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

function client.uiupdate(...)
    if game.uiupdate then
        game:uiupdate(...)
    end
end


return Game
