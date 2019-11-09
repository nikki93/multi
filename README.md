<p float="left" align="center">
  <img src="ExampleShooter.gif" height="250">
  <img src="ExamplePhysicsDragging.gif" height="250">
</p>

# What is this?

This is a framework for laying out multiplayer gameplay code in a Lua-based game, specifically intended for use with [LÖVE](https://love2d.org/) on the [Castle](http://castle.games/) platform. LÖVE provides an update loop and low-level networking libraries while Castle provides automatic dedicated server hosting (both of them also provide a lot more other stuff, and these aren't necessarily their primary purposes).

The 'cs.lua', 'game.lua', 'server.lua', 'client.lua' and 'physics.lua' files constitute the framework. The rest of the files are examples and documentation. The 'physics.lua' file provides a synchronization system for [love.physics](https://love2d.org/wiki/love.physics) that uses the rest of the framework.

# Examples

Each example has a common module ('...Common.lua'), a server module ('...Server.lua'), a client module ('...Client.lua'). The examples can be launched on a remote server by opening the '.castle' file in Castle, or with a local server session by opening the '...Local.lua' file in Castle.

## Walking example

In this example players occupy the same space and can walk around and see each other walking around in real-time. A client moves its own player object directly. Player objects of other clients are interpolated based on a history of past positions received. This interpolation behavior also happens on the server. Each player is rendered using their Castle avatar.

## Shooter example

This example builds on the walking example for player movement. Random rectangular walls are placed and [bump.lua](https://github.com/kikito/bump.lua) is used for collision detection and response. The server owns bullet motion and lifetime, players simply send a 'shoot' message to the server when they want to shoot. Player scores are also maintained and drawn. The client also draws 'shadows' of walls to limit the field of view of the player.

## Physics dragging example

This example uses the 'physics.lua' module to provide a synchronized physics scene. Players can drag and throw objects around and see others' influences on the scene too.

# Reference

## Module layout

You must have separate client and server modules that you specify as `main: ` and `serverMain: ` in your project's '.castle' file ([the `serverMain: ` key appears under the `multiplayer: ` key](https://castle.games/documentation/reference/castle-project-file-reference)).

The client module must `require` the 'client.lua' file in this repository, while the server module must `require` the 'server.lua' file. You can `require` them using direct 'https://...' URIs as is possible in Castle. The globals `GameCommon` and `GameClient` will become available on the client, and `GameCommon` and `GameServer` will be available on the server.

You implement methods in `GameCommon`, `GameClient` and `GameServer` to define your game. The methods you implement are listed under the 'Methods you implement' heading below. In any implemented method, `GameClient` or `GameServer` can call the `GameCommon` version using `GameCommon.<methodName>(self, ...)`, passing along all of the arguments that it received (it is free to pass in different arguments too).

In your methods, you can call methods on `self` that are pre-defined by the library. These are listed under the 'Methods you call' heading below.

## Variables you can read

### `self.server`

### `self.client`

### `self.connected`

### `self.clientId`

### `self.time`

## Methods you can call

### `:defineMessageKind`

### `:send`

### `:generateId`

## Methods you can implement

### `:define`

### `:start`

### `:stop`

### `:connect`

### `:disconnect`

### `.receivers:<messageKind>`

### LÖVE callbacks

You can also implement any method named like a [LÖVE callback](https://love2d.org/wiki/love#Callbacks) to have it be called when the corresponding LÖVE event occurs. So, for example, on the client, you can implement `GameClient:keypressed(key)` which would be called when a key is pressed.

**On the server, only `:update(dt)` is available.** This is because the server may run in a Castle remote server which is not connected to any input or output.

On the client, all LÖVE callbacks are available and the same arguments are passed in that are passed by LÖVE.

# Attributions

Crosshair image in multiplayer shooter example is from https://www.kenney.nl/assets/crosshair-pack. Thanks!
