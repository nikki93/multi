clientServer = require 'https://raw.githubusercontent.com/castle-games/share.lua/6d70831ea98c57219f2aa285b4ad7bf7156f7c03/cs.lua'

Game = require 'game'

function newGame()
    return setmetatable({}, {
        __index = Game,
    })
end