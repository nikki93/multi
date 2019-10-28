clientServer = require 'https://raw.githubusercontent.com/castle-games/share.lua/6d70831ea98c57219f2aa285b4ad7bf7156f7c03/cs.lua'
BlobReader = require 'https://raw.githubusercontent.com/megagrump/moonblob/38cd53bfed2d058b4aa658a9da203a4469828b00/lua/BlobReader.lua'
BlobWriter = require 'https://raw.githubusercontent.com/megagrump/moonblob/38cd53bfed2d058b4aa658a9da203a4469828b00/lua/BlobWriter.lua'

Game = require 'game'

function newGame()
    return setmetatable({}, {
        __index = Game,
    })
end