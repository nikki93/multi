# Examples

Each example has a common module ('...Common.lua'), a server module ('...Server.lua'), a client module ('...Client.lua'). The examples can be launched on a remote server by running opening the '.castle' file in Castle, or with a local server session by opening the '...Local.lua' file in Castle.

## Walking example

# Reference

## Module layout

You must have separate client and server modules that you specify as `main: ` and `serverMain: ` in your project's '.castle' file. The client module must `require` the 'lib/client.lua' file in this repository, while the server module must `require` the 'lib/server.lua' file. The globals `GameCommon` and `GameClient` will become available on the client, and `GameCommon` and `GameServer` will be available on the server. You implement methods in these tables to define your game. The methods you implement are listed under the 'Methods you implement' heading below.

In implemented methods, you can methods on `self` that are pre-defined by the library to send messages or define message types. These are listed under the 'Methods you call' heading below.

## Methods you call

### `:defineMessageKind`

### `:send`

## Methods you implement

### `:define`

### `:start`

### `:stop`

### `:connect`

### `:disconnect`

### `.receivers:<messageKind>`